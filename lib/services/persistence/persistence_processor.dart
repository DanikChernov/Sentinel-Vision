import 'dart:math' as math;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../models/app_settings.dart';
import '../../models/frame_context.dart';
import '../../models/persistence_models.dart';
import '../../models/pipeline_event.dart';
import '../../models/tracked_entity.dart';
import '../camera/frame_image_utils.dart';
import 'embedding_memory_store.dart';
import 'face_alignment_processor.dart';
import 'face_embedding_adapter.dart';
import 'identity_matcher.dart';
import 'temporal_consistency_engine.dart';

class PersistenceProcessingResult {
  const PersistenceProcessingResult({
    required this.entities,
    required this.snapshot,
    this.events = const <PipelineEvent>[],
  });

  final List<TrackedEntity> entities;
  final PersistenceSnapshot snapshot;
  final List<PipelineEvent> events;
}

class PersistenceProcessor {
  PersistenceProcessor({
    EmbeddingMemoryStore? memoryStore,
    FaceEmbeddingAdapter? embeddingAdapter,
    IdentityMatcher? identityMatcher,
    TemporalConsistencyEngine? temporalConsistencyEngine,
    FaceAlignmentProcessor? faceAlignmentProcessor,
  })  : _memoryStore = memoryStore ?? EmbeddingMemoryStore(),
        _embeddingAdapter =
            embeddingAdapter ?? LocalDescriptorFaceEmbeddingAdapter(),
        _identityMatcher = identityMatcher ?? const IdentityMatcher(),
        _temporalConsistencyEngine =
            temporalConsistencyEngine ?? const TemporalConsistencyEngine(),
        _faceAlignmentProcessor =
            faceAlignmentProcessor ?? const FaceAlignmentProcessor();

  final EmbeddingMemoryStore _memoryStore;
  final FaceEmbeddingAdapter _embeddingAdapter;
  final IdentityMatcher _identityMatcher;
  final TemporalConsistencyEngine _temporalConsistencyEngine;
  final FaceAlignmentProcessor _faceAlignmentProcessor;

  FaceDetector? _faceDetector;
  PersistenceSnapshot _snapshot = const PersistenceSnapshot();
  bool _initialized = false;

  PersistenceSnapshot get snapshot => _snapshot;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    await _memoryStore.initialize();
    await _embeddingAdapter.initialize();
    await _reloadSnapshot();
    _initialized = true;
  }

  Future<void> dispose() async {
    final detector = _faceDetector;
    _faceDetector = null;
    if (detector != null) {
      await detector.close();
    }
    await _embeddingAdapter.dispose();
    await _memoryStore.dispose();
  }

  Future<PersistenceProcessingResult> process({
    required FrameContext frame,
    required List<TrackedEntity> entities,
    required AppSettings settings,
  }) async {
    await initialize();
    if (!settings.faceAnalysisPersistenceEnabled || entities.isEmpty) {
      return PersistenceProcessingResult(entities: entities, snapshot: _snapshot);
    }

    final detector = _faceDetector;
    if (detector == null) {
      return PersistenceProcessingResult(entities: entities, snapshot: _snapshot);
    }

    final decodedFrame = FrameImageUtils.decodeFrame(frame);
    if (decodedFrame == null) {
      return PersistenceProcessingResult(entities: entities, snapshot: _snapshot);
    }

    final records = (await _memoryStore.loadRecords()).toList(growable: true);
    final events = <PipelineEvent>[];
    final reservedLabels = entities
        .where((entity) => entity.isVisible)
        .map((entity) => entity.stableLabel)
        .toSet();
    final updatedEntities = <TrackedEntity>[];

    for (final entity in entities) {
      if (!entity.isVisible || entity.classLabel != 'person') {
        updatedEntities.add(entity);
        continue;
      }

      final personCrop = FrameImageUtils.cropBoundingBox(
        image: decodedFrame,
        boundingBox: entity.boundingBox,
      );
      if (personCrop == null) {
        updatedEntities.add(entity);
        continue;
      }

      final faces = List<Face>.from(
        await detector.processImage(
        InputImage.fromBitmap(
          bitmap: FrameImageUtils.rgbaBytes(personCrop),
          width: personCrop.width,
          height: personCrop.height,
        ),
      ),
        growable: true,
      );
      if (faces.isEmpty) {
        updatedEntities.add(entity);
        continue;
      }

      faces.sort((left, right) {
        final leftArea = left.boundingBox.width * left.boundingBox.height;
        final rightArea = right.boundingBox.width * right.boundingBox.height;
        return rightArea.compareTo(leftArea);
      });
      final face = faces.first;
      final aligned = _faceAlignmentProcessor.align(
        personCrop: personCrop,
        face: face,
      );
      if (aligned == null) {
        updatedEntities.add(entity);
        continue;
      }

      final embedded = await _embeddingAdapter.embed(
        alignedFace: aligned.alignedFace,
        faceConfidence: aligned.faceConfidence,
      );
      if (embedded == null || embedded.embedding.isEmpty) {
        updatedEntities.add(entity);
        continue;
      }

      final match = _identityMatcher.findBestMatch(
        embedding: embedded.embedding,
        records: records.where((record) => record.classLabel == entity.classLabel),
        similarityThreshold: settings.embeddingSimilarityThreshold,
      );

      var updatedEntity = entity.copyWith(
        faceConfidence: embedded.faceConfidence,
        embeddingSimilarity: match?.similarity ?? entity.embeddingSimilarity,
      );

      if (match != null) {
        final combined = _temporalConsistencyEngine.score(
          entity: entity,
          record: match.record,
          frame: frame,
          embeddingSimilarity: match.similarity,
          enableTemporalPersistence: settings.temporalPersistenceEnabled,
        );
        final temporalConfidence =
            settings.temporalPersistenceEnabled ? combined : match.similarity;

        if (combined >= settings.embeddingSimilarityThreshold &&
            (match.stableLabel == entity.stableLabel ||
                !reservedLabels.contains(match.stableLabel))) {
          reservedLabels.remove(entity.stableLabel);
          reservedLabels.add(match.stableLabel);
          updatedEntity = updatedEntity.copyWith(
            stableLabel: match.stableLabel,
            recoveredInFrame: entity.stableLabel != match.stableLabel,
            identityConfidence: math.max(
              entity.identityConfidence ?? 0,
              combined,
            ),
            temporalConfidence: temporalConfidence,
            embeddingSimilarity: match.similarity,
          );
          if (entity.stableLabel != match.stableLabel) {
            events.add(
              PipelineEvent(
                type: PipelineEventType.identityRecovered,
                message:
                    'Face persistence recovered ${match.stableLabel} from local embedding memory.',
                timestamp: frame.timestamp,
                details: <String, Object?>{
                  'trackId': entity.trackId,
                  'similarity': match.similarity,
                  'confidence': combined,
                },
              ),
            );
          }
        } else {
          updatedEntity = updatedEntity.copyWith(
            temporalConfidence: temporalConfidence,
            identityConfidence: math.max(
              entity.identityConfidence ?? 0,
              combined,
            ),
          );
        }
      }

      final existing = records.where((record) => record.stableLabel == updatedEntity.stableLabel);
      final prior = existing.isEmpty ? null : existing.first;
      final nextRecord = _mergeRecord(
        prior: prior,
        entity: updatedEntity,
        embedding: embedded.embedding,
        frame: frame,
        faceConfidence: embedded.faceConfidence,
      );
      await _memoryStore.upsertRecord(nextRecord);
      records.removeWhere(
        (record) => record.stableLabel == nextRecord.stableLabel,
      );
      records.add(nextRecord);
      updatedEntities.add(updatedEntity);
    }

    await _reloadSnapshot();
    return PersistenceProcessingResult(
      entities: updatedEntities,
      snapshot: _snapshot,
      events: events,
    );
  }

  Future<void> registerCorrection(TrackedEntity entity) async {
    await initialize();
    final alias = entity.learnedLabel;
    if (alias == null || alias.trim().isEmpty) {
      return;
    }
    await _memoryStore.updateCorrection(
      stableLabel: entity.stableLabel,
      alias: alias,
    );
    await _reloadSnapshot();
  }

  Future<void> clearMemory() async {
    await initialize();
    await _memoryStore.clear();
    await _reloadSnapshot();
  }

  FaceEmbeddingRecord _mergeRecord({
    required FaceEmbeddingRecord? prior,
    required TrackedEntity entity,
    required List<double> embedding,
    required FrameContext frame,
    required double faceConfidence,
  }) {
    if (prior == null) {
      return FaceEmbeddingRecord(
        stableLabel: entity.stableLabel,
        classLabel: entity.classLabel,
        embedding: embedding,
        embeddingCount: 1,
        sightings: 1,
        recoveries: entity.recoveredInFrame ? 1 : 0,
        correctionCount: entity.correctionCount,
        averageSimilarity: entity.embeddingSimilarity ?? 1,
        averageTemporalConfidence: entity.temporalConfidence ?? 0,
        averageFaceConfidence: faceConfidence,
        lastBoundingBox: entity.boundingBox,
        lastSeenAt: frame.timestamp,
        preferredAlias: entity.learnedLabel,
      );
    }

    final nextCount = prior.embeddingCount + 1;
    final mergedEmbedding = List<double>.generate(
      math.min(prior.embedding.length, embedding.length),
      (index) => ((prior.embedding[index] * prior.embeddingCount) + embedding[index]) /
          nextCount,
      growable: false,
    );
    final nextRecoveries =
        prior.recoveries + (entity.recoveredInFrame ? 1 : 0);
    final averageSimilarity = _rollingAverage(
      prior.averageSimilarity,
      prior.embeddingCount,
      entity.embeddingSimilarity ?? 1,
    );
    final averageTemporalConfidence = _rollingAverage(
      prior.averageTemporalConfidence,
      prior.embeddingCount,
      entity.temporalConfidence ?? 0,
    );
    final averageFaceConfidence = _rollingAverage(
      prior.averageFaceConfidence,
      prior.embeddingCount,
      faceConfidence,
    );

    return prior.copyWith(
      embedding: mergedEmbedding,
      embeddingCount: nextCount,
      sightings: prior.sightings + 1,
      recoveries: nextRecoveries,
      correctionCount: math.max(prior.correctionCount, entity.correctionCount),
      averageSimilarity: averageSimilarity,
      averageTemporalConfidence: averageTemporalConfidence,
      averageFaceConfidence: averageFaceConfidence,
      lastBoundingBox: entity.boundingBox,
      lastSeenAt: frame.timestamp,
      preferredAlias: entity.learnedLabel ?? prior.preferredAlias,
    );
  }

  Future<void> _reloadSnapshot() async {
    final records = await _memoryStore.loadRecords();
    final memoryBytes = await _memoryStore.approximateStorageBytes();
    final embeddingsStored = records.fold<int>(
      0,
      (sum, record) => sum + record.embeddingCount,
    );
    final recoveredIdentities = records.fold<int>(
      0,
      (sum, record) => sum + record.recoveries,
    );
    final averageSimilarity = _average(
      records.map((record) => record.averageSimilarity),
    );
    final averageTemporalConfidence = _average(
      records.map((record) => record.averageTemporalConfidence),
    );
    final averageFaceConfidence = _average(
      records.map((record) => record.averageFaceConfidence),
    );
    final recoveryRate = records.isEmpty
        ? 0.0
        : records
                .map((record) => record.sightings == 0
                    ? 0.0
                    : record.recoveries / record.sightings)
                .reduce((left, right) => left + right) /
            records.length;

    _snapshot = PersistenceSnapshot(
      backend: _embeddingAdapter.backend,
      embeddingsStored: embeddingsStored,
      recoveredIdentities: recoveredIdentities,
      averageSimilarity: averageSimilarity,
      identityRecoveryRate: recoveryRate,
      averageTemporalConfidence: averageTemporalConfidence,
      averageFaceConfidence: averageFaceConfidence,
      memoryBytes: memoryBytes,
      identities: records,
    );
  }

  double _rollingAverage(double current, int count, double next) {
    return ((current * count) + next) / (count + 1);
  }

  double _average(Iterable<double> values) {
    final list = values.toList(growable: false);
    if (list.isEmpty) {
      return 0;
    }
    return list.reduce((left, right) => left + right) / list.length;
  }
}
