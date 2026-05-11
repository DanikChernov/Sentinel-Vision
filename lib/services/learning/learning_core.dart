import 'dart:async';
import 'dart:math' as math;

import '../../models/app_settings.dart';
import '../../models/frame_context.dart';
import '../../models/learning_models.dart';
import '../../models/pipeline_event.dart';
import '../../models/tracked_entity.dart';
import 'adaptive_label_refiner.dart';
import 'feedback_trainer.dart';
import 'identity_pattern_memory.dart';
import 'training_sample_exporter.dart';
import 'usage_memory_store.dart';

class LearningProcessingResult {
  const LearningProcessingResult({
    required this.entities,
    this.events = const <PipelineEvent>[],
  });

  final List<TrackedEntity> entities;
  final List<PipelineEvent> events;
}

class SentinelLearningCore {
  SentinelLearningCore({
    UsageMemoryStore? usageMemoryStore,
    AdaptiveLabelRefiner? adaptiveLabelRefiner,
    IdentityPatternMemory? identityPatternMemory,
    TrainingSampleExporter? trainingSampleExporter,
  })  : _usageMemoryStore = usageMemoryStore ?? UsageMemoryStore(),
        _adaptiveLabelRefiner = adaptiveLabelRefiner ?? AdaptiveLabelRefiner(),
        _identityPatternMemory = identityPatternMemory ?? IdentityPatternMemory(),
        _trainingSampleExporter =
            trainingSampleExporter ?? TrainingSampleExporter() {
    _feedbackTrainer = FeedbackTrainer(
      labelRefiner: _adaptiveLabelRefiner,
      identityPatternMemory: _identityPatternMemory,
    );
  }

  final UsageMemoryStore _usageMemoryStore;
  final AdaptiveLabelRefiner _adaptiveLabelRefiner;
  final IdentityPatternMemory _identityPatternMemory;
  final TrainingSampleExporter _trainingSampleExporter;
  late final FeedbackTrainer _feedbackTrainer;

  LearningSnapshot _snapshot = const LearningSnapshot();
  final Map<String, DateTime> _lastSampleCaptureAt = <String, DateTime>{};
  bool _isInitialized = false;

  LearningSnapshot get snapshot => _snapshot;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    await _usageMemoryStore.initialize();
    _snapshot = await _usageMemoryStore.loadSnapshot();
    _adaptiveLabelRefiner.seed(_snapshot.correctedLabels);
    _identityPatternMemory.seed(_snapshot.identities);
    _isInitialized = true;
  }

  Future<void> dispose() async {
    await _usageMemoryStore.dispose();
  }

  Future<LearningProcessingResult> observeFrame({
    required FrameContext frame,
    required List<TrackedEntity> entities,
    required AppSettings settings,
  }) async {
    if (!_isInitialized || !settings.continuousLearningEnabled) {
      return LearningProcessingResult(entities: entities);
    }

    final events = <PipelineEvent>[];
    final refinedEntities = <TrackedEntity>[];
    var autoRefinedCount = 0;
    var sampleCount = 0;

    for (final entity in entities) {
      var updatedEntity = entity;
      LearnedIdentitySummary? identitySummary;

      if (entity.isVisible && settings.identityLearningEnabled) {
        identitySummary = _identityPatternMemory.observeEntity(entity, frame);
        await _usageMemoryStore.upsertIdentityPattern(identitySummary);
        updatedEntity = updatedEntity.copyWith(
          identityConfidence:
              _identityPatternMemory.scoreEntity(entity, identitySummary, frame),
          correctionCount: math.max(
            entity.correctionCount,
            identitySummary.correctionCount,
          ),
        );
      }

      updatedEntity = _adaptiveLabelRefiner.refineEntity(
        entity: updatedEntity,
        frame: frame,
        identitySummary: identitySummary,
        enableLabelCorrections: settings.labelCorrectionLearningEnabled,
      );

      if (updatedEntity.learnedLabel != entity.learnedLabel ||
          updatedEntity.displayConfidence != entity.displayConfidence) {
        autoRefinedCount += 1;
      }

      refinedEntities.add(updatedEntity);

      if (!updatedEntity.isVisible) {
        continue;
      }

      await _usageMemoryStore.saveObservation(
        trackId: updatedEntity.trackId,
        stableLabel: updatedEntity.stableLabel,
        classLabel: updatedEntity.classLabel,
        detectorLabel: updatedEntity.classLabel,
        learnedLabel: updatedEntity.learnedLabel,
        detectorConfidence:
            updatedEntity.detectorConfidence ?? updatedEntity.confidence,
        adaptiveConfidence: updatedEntity.displayConfidence,
        identityConfidence: updatedEntity.identityConfidence,
        sourceType: frame.sourceType,
        observedAt: frame.timestamp,
        boundingBox: updatedEntity.boundingBox,
        recoveredInFrame: updatedEntity.recoveredInFrame,
        falsePositive: false,
      );

      if (settings.saveDetectionCropsEnabled &&
          _shouldCaptureSample(updatedEntity, frame.timestamp)) {
        final sample = await _trainingSampleExporter.captureSample(
          frame: frame,
          entity: updatedEntity,
          store: _usageMemoryStore,
        );
        if (sample != null) {
          sampleCount += 1;
          _snapshot = _snapshot.copyWith(
            recentSamples: <TrainingSampleRecord>[
              sample,
              ..._snapshot.recentSamples,
            ].take(24).toList(growable: false),
          );
        }
      }
    }

    _rebuildSnapshot(
      observationDelta:
          refinedEntities.where((entity) => entity.isVisible).length,
      trainingSampleDelta: sampleCount,
      refreshStorageBytes: sampleCount > 0,
    );

    if (autoRefinedCount > 0 && frame.frameNumber % 12 == 0) {
      events.add(
        PipelineEvent(
          type: PipelineEventType.learningObservation,
          message:
              'Sentinel Learning Core refined $autoRefinedCount entity label(s).',
          timestamp: frame.timestamp,
          details: <String, Object?>{'samples': sampleCount},
        ),
      );
    } else if (sampleCount > 0) {
      events.add(
        PipelineEvent(
          type: PipelineEventType.learningObservation,
          message: 'Captured $sampleCount training sample(s) for local learning.',
          timestamp: frame.timestamp,
        ),
      );
    }

    return LearningProcessingResult(
      entities: refinedEntities,
      events: events,
    );
  }

  Future<TrackedEntity> applyCorrection({
    required TrackedEntity entity,
    required String correctedLabel,
    required FrameContext frame,
    required AppSettings settings,
  }) async {
    final normalized = correctedLabel.trim();
    if (normalized.isEmpty) {
      return entity;
    }

    if (!_isInitialized || !settings.continuousLearningEnabled) {
      return entity.copyWith(
        learnedLabel: normalized,
        learnedLabelConfidence: 0.98,
        adaptiveConfidence: math.max(entity.displayConfidence, 0.95),
      );
    }

    final result = await _feedbackTrainer.applyCorrection(
      entity: entity,
      correctedLabel: normalized,
      frame: frame,
      store: _usageMemoryStore,
      allowIdentityLearning: settings.identityLearningEnabled,
      allowLabelCorrectionLearning: settings.labelCorrectionLearningEnabled,
    );

    if (result.updatedIdentity != null) {
      _identityPatternMemory.seed(<LearnedIdentitySummary>[
        ..._snapshot.identities.where(
          (identity) =>
              identity.stableLabel != result.updatedIdentity!.stableLabel,
        ),
        result.updatedIdentity!,
      ]);
    }

    if (result.updatedMapping != null) {
      _adaptiveLabelRefiner.upsert(result.updatedMapping!);
    }

    _replaceSnapshotEntries(
      updatedIdentity: result.updatedIdentity,
      updatedMapping: result.updatedMapping,
      correctionDelta: 1,
      refreshStorageBytes: true,
    );
    await _refreshRecentSamples();

    return result.updatedEntity;
  }

  Future<TrackedEntity> markFalsePositive({
    required TrackedEntity entity,
    required FrameContext frame,
    required AppSettings settings,
  }) async {
    if (!_isInitialized || !settings.continuousLearningEnabled) {
      return entity.copyWith(
        falsePositiveCount: entity.falsePositiveCount + 1,
        adaptiveConfidence: math.max(0.02, entity.displayConfidence - 0.2),
      );
    }

    final result = await _feedbackTrainer.markFalsePositive(
      entity: entity,
      frame: frame,
      store: _usageMemoryStore,
    );

    if (result.updatedMapping != null) {
      _adaptiveLabelRefiner.upsert(result.updatedMapping!);
    }

    _replaceSnapshotEntries(
      updatedMapping: result.updatedMapping,
      falsePositiveDelta: 1,
      refreshStorageBytes: false,
    );

    return result.updatedEntity;
  }

  Future<String?> exportTrainingDataset() async {
    if (!_isInitialized) {
      return null;
    }

    final samples = await _usageMemoryStore.loadTrainingSamples(limit: null);
    if (samples.isEmpty) {
      return null;
    }

    final exportPath = await _trainingSampleExporter.exportDataset(
      store: _usageMemoryStore,
      samples: samples,
    );

    await _refreshRecentSamples();
    await _refreshStorageBytes();
    return exportPath;
  }

  Future<void> clearAllLearning() async {
    if (!_isInitialized) {
      return;
    }

    await _usageMemoryStore.clearAll();
    _lastSampleCaptureAt.clear();
    _snapshot = const LearningSnapshot();
    _adaptiveLabelRefiner.seed(const <CorrectedLabelSummary>[]);
    _identityPatternMemory.seed(const <LearnedIdentitySummary>[]);
  }

  bool _shouldCaptureSample(TrackedEntity entity, DateTime timestamp) {
    final previousCapture = _lastSampleCaptureAt[entity.stableLabel];
    if (previousCapture != null &&
        timestamp.difference(previousCapture) < const Duration(seconds: 2)) {
      return false;
    }
    _lastSampleCaptureAt[entity.stableLabel] = timestamp;
    return true;
  }

  void _replaceSnapshotEntries({
    LearnedIdentitySummary? updatedIdentity,
    CorrectedLabelSummary? updatedMapping,
    int correctionDelta = 0,
    int falsePositiveDelta = 0,
    bool refreshStorageBytes = false,
  }) {
    final identities = updatedIdentity == null
        ? _snapshot.identities
        : <LearnedIdentitySummary>[
            updatedIdentity,
            ..._snapshot.identities.where(
              (identity) => identity.stableLabel != updatedIdentity.stableLabel,
            ),
          ]..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));

    final mappings = updatedMapping == null
        ? _snapshot.correctedLabels
        : <CorrectedLabelSummary>[
            updatedMapping,
            ..._snapshot.correctedLabels.where(
              (mapping) => mapping.key != updatedMapping.key,
            ),
          ]..sort((a, b) => b.usageCount.compareTo(a.usageCount));

    _snapshot = _snapshot.copyWith(
      identities: identities,
      correctedLabels: mappings,
      metrics: _snapshot.metrics.copyWith(
        correctionCount: _snapshot.metrics.correctionCount + correctionDelta,
        falsePositiveCount:
            _snapshot.metrics.falsePositiveCount + falsePositiveDelta,
        identityCount: identities.length,
        correctedLabelCount: mappings.length,
        averageConfidenceGain: _averageConfidenceGain(identities),
      ),
    );

    if (refreshStorageBytes) {
      unawaited(_refreshStorageBytes());
    }
  }

  void _rebuildSnapshot({
    int observationDelta = 0,
    int trainingSampleDelta = 0,
    bool refreshStorageBytes = false,
  }) {
    final identities = _identityPatternMemory.identities.toList(growable: true)
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    final mappings = _adaptiveLabelRefiner.mappings.toList(growable: true)
      ..sort((a, b) => b.usageCount.compareTo(a.usageCount));

    _snapshot = _snapshot.copyWith(
      identities: identities,
      correctedLabels: mappings,
      metrics: _snapshot.metrics.copyWith(
        observationCount: _snapshot.metrics.observationCount + observationDelta,
        trainingSampleCount:
            _snapshot.metrics.trainingSampleCount + trainingSampleDelta,
        identityCount: identities.length,
        correctedLabelCount: mappings.length,
        averageConfidenceGain: _averageConfidenceGain(identities),
      ),
    );

    if (refreshStorageBytes) {
      unawaited(_refreshStorageBytes());
    }
  }

  Future<void> _refreshStorageBytes() async {
    final storageBytes = await _usageMemoryStore.approximateStorageBytes();
    _snapshot = _snapshot.copyWith(
      metrics: _snapshot.metrics.copyWith(
        approximateStorageBytes: storageBytes,
      ),
    );
  }

  Future<void> _refreshRecentSamples() async {
    final recentSamples = await _usageMemoryStore.loadTrainingSamples();
    _snapshot = _snapshot.copyWith(recentSamples: recentSamples);
  }

  double _averageConfidenceGain(List<LearnedIdentitySummary> identities) {
    if (identities.isEmpty) {
      return 0;
    }

    final totalGain = identities.fold<double>(0, (sum, identity) {
      return sum + (identity.learnedConfidence - identity.averageDetectorConfidence);
    });
    return totalGain / identities.length;
  }
}
