import 'dart:math' as math;

import '../../models/frame_context.dart';
import '../../models/learning_models.dart';
import '../../models/tracked_entity.dart';
import 'adaptive_label_refiner.dart';
import 'identity_pattern_memory.dart';
import 'usage_memory_store.dart';

class FeedbackTrainingResult {
  const FeedbackTrainingResult({
    required this.updatedEntity,
    this.updatedIdentity,
    this.updatedMapping,
  });

  final TrackedEntity updatedEntity;
  final LearnedIdentitySummary? updatedIdentity;
  final CorrectedLabelSummary? updatedMapping;
}

class FeedbackTrainer {
  FeedbackTrainer({
    required AdaptiveLabelRefiner labelRefiner,
    required IdentityPatternMemory identityPatternMemory,
  }) : _labelRefiner = labelRefiner,
       _identityPatternMemory = identityPatternMemory;

  final AdaptiveLabelRefiner _labelRefiner;
  final IdentityPatternMemory _identityPatternMemory;

  Future<FeedbackTrainingResult> applyCorrection({
    required TrackedEntity entity,
    required String correctedLabel,
    required FrameContext frame,
    required UsageMemoryStore store,
    required bool allowIdentityLearning,
    required bool allowLabelCorrectionLearning,
  }) async {
    final normalized = correctedLabel.trim();
    await store.saveCorrection(
      stableLabel: entity.stableLabel,
      classLabel: entity.classLabel,
      originalLabel: entity.learnedLabel ?? entity.classLabel,
      correctedLabel: normalized,
      falsePositive: false,
      sourceType: frame.sourceType,
      correctedAt: frame.timestamp,
      boundingBox: entity.boundingBox,
      confidence: entity.displayConfidence,
    );

    LearnedIdentitySummary? identitySummary;
    if (allowIdentityLearning) {
      identitySummary = _identityPatternMemory.reinforceAlias(
        entity.stableLabel,
        normalized,
        correctedAt: frame.timestamp,
      );
      await store.upsertIdentityPattern(identitySummary);
    }

    CorrectedLabelSummary? mappingSummary;
    if (allowLabelCorrectionLearning && entity.classLabel != 'person') {
      final key = _labelRefiner.mappingKeyFor(
        entity.classLabel,
        entity.boundingBox,
        frame,
      );
      final existing = _labelRefiner.mappingFor(entity, frame);
      final usageCount = (existing?.usageCount ?? 0) + 1;
      final learningConfidence = math
          .min(0.99, 0.48 + (usageCount * 0.08))
          .toDouble();
      mappingSummary = CorrectedLabelSummary(
        key: key,
        originalLabel: entity.classLabel,
        correctedLabel: normalized,
        usageCount: usageCount,
        falsePositiveCount: existing?.falsePositiveCount ?? 0,
        averageLearningConfidence: existing == null
            ? learningConfidence
            : ((existing.averageLearningConfidence * (usageCount - 1)) +
                      learningConfidence) /
                  usageCount,
        lastUpdatedAt: frame.timestamp,
      );
      _labelRefiner.upsert(mappingSummary);
      await store.upsertLabelMapping(mappingSummary);
    }

    await store.applyCorrectionToLatestTrainingSample(
      stableLabel: entity.stableLabel,
      correctedLabel: normalized,
    );

    final updatedEntity = entity.copyWith(
      learnedLabel: normalized,
      learnedLabelConfidence: math.max(
        identitySummary?.learnedConfidence ?? 0,
        mappingSummary?.averageLearningConfidence ?? 0.9,
      ),
      adaptiveConfidence: math.max(entity.displayConfidence, 0.94),
      correctionCount: entity.correctionCount + 1,
    );

    return FeedbackTrainingResult(
      updatedEntity: updatedEntity,
      updatedIdentity: identitySummary,
      updatedMapping: mappingSummary,
    );
  }

  Future<FeedbackTrainingResult> markFalsePositive({
    required TrackedEntity entity,
    required FrameContext frame,
    required UsageMemoryStore store,
  }) async {
    await store.saveCorrection(
      stableLabel: entity.stableLabel,
      classLabel: entity.classLabel,
      originalLabel: entity.learnedLabel ?? entity.classLabel,
      correctedLabel: null,
      falsePositive: true,
      sourceType: frame.sourceType,
      correctedAt: frame.timestamp,
      boundingBox: entity.boundingBox,
      confidence: entity.displayConfidence,
    );

    final key = _labelRefiner.mappingKeyFor(
      entity.classLabel,
      entity.boundingBox,
      frame,
    );
    final existing = _labelRefiner.mappingFor(entity, frame);
    final mappingSummary = CorrectedLabelSummary(
      key: key,
      originalLabel: entity.classLabel,
      correctedLabel: existing?.correctedLabel ?? entity.classLabel,
      usageCount: existing?.usageCount ?? 0,
      falsePositiveCount: (existing?.falsePositiveCount ?? 0) + 1,
      averageLearningConfidence:
          existing?.averageLearningConfidence ?? entity.displayConfidence,
      lastUpdatedAt: frame.timestamp,
    );
    _labelRefiner.upsert(mappingSummary);
    await store.upsertLabelMapping(mappingSummary);

    final updatedEntity = entity.copyWith(
      falsePositiveCount: entity.falsePositiveCount + 1,
      adaptiveConfidence: math.max(0.02, entity.displayConfidence - 0.2),
    );

    return FeedbackTrainingResult(
      updatedEntity: updatedEntity,
      updatedMapping: mappingSummary,
    );
  }
}
