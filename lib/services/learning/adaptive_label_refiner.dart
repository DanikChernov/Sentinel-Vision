import 'dart:math' as math;

import '../../models/bounding_box.dart';
import '../../models/frame_context.dart';
import '../../models/learning_models.dart';
import '../../models/tracked_entity.dart';

class AdaptiveLabelRefiner {
  final Map<String, CorrectedLabelSummary> _mappings =
      <String, CorrectedLabelSummary>{};

  void seed(Iterable<CorrectedLabelSummary> mappings) {
    _mappings
      ..clear()
      ..addEntries(mappings.map((mapping) => MapEntry(mapping.key, mapping)));
  }

  Iterable<CorrectedLabelSummary> get mappings => _mappings.values;

  CorrectedLabelSummary? mappingFor(TrackedEntity entity, FrameContext frame) {
    return _mappings[mappingKeyFor(entity.classLabel, entity.boundingBox, frame)];
  }

  String mappingKeyFor(
    String classLabel,
    BoundingBox boundingBox,
    FrameContext frame,
  ) {
    final widthRatio = boundingBox.width / frame.sourceSize.width;
    final heightRatio = boundingBox.height / frame.sourceSize.height;
    final sizeRatio =
        (boundingBox.width * boundingBox.height) /
        (frame.sourceSize.width * frame.sourceSize.height);
    final center = boundingBox.center;
    final zoneX = ((center.dx / frame.sourceSize.width) * 3).floor().clamp(0, 2);
    final zoneY = ((center.dy / frame.sourceSize.height) * 3).floor().clamp(0, 2);
    final sizeBucket = sizeRatio < 0.03
        ? 'small'
        : sizeRatio < 0.12
            ? 'medium'
            : 'large';
    final aspectBucket = widthRatio > heightRatio ? 'wide' : 'tall';
    return '$classLabel|$sizeBucket|$aspectBucket|$zoneX$zoneY';
  }

  void upsert(CorrectedLabelSummary summary) {
    _mappings[summary.key] = summary;
  }

  TrackedEntity refineEntity({
    required TrackedEntity entity,
    required FrameContext frame,
    LearnedIdentitySummary? identitySummary,
    required bool enableLabelCorrections,
  }) {
    var learnedLabel = entity.learnedLabel;
    var learnedConfidence = entity.learnedLabelConfidence ?? 0.0;
    var adaptiveConfidence = entity.adaptiveConfidence ?? entity.confidence;
    var falsePositiveCount = entity.falsePositiveCount;
    var correctionCount = entity.correctionCount;

    if (enableLabelCorrections && identitySummary?.preferredAlias != null) {
      learnedLabel = identitySummary!.preferredAlias;
      learnedConfidence = math.max(learnedConfidence, identitySummary.learnedConfidence);
      correctionCount = math.max(correctionCount, identitySummary.correctionCount);
      adaptiveConfidence = _blendConfidence(
        adaptiveConfidence,
        identitySummary.learnedConfidence,
      );
    }

    final mapping = _mappings[mappingKeyFor(entity.classLabel, entity.boundingBox, frame)];
    if (enableLabelCorrections && mapping != null && entity.classLabel != 'person') {
      learnedLabel = mapping.correctedLabel;
      learnedConfidence = math.max(
        learnedConfidence,
        mapping.averageLearningConfidence,
      );
      falsePositiveCount = mapping.falsePositiveCount;
      correctionCount = math.max(correctionCount, mapping.usageCount);
      adaptiveConfidence = _blendConfidence(
        adaptiveConfidence,
        mapping.averageLearningConfidence,
      );
      adaptiveConfidence -= math.min(0.18, mapping.falsePositiveCount * 0.03);
    } else if (mapping != null) {
      falsePositiveCount = mapping.falsePositiveCount;
      adaptiveConfidence -= math.min(0.12, mapping.falsePositiveCount * 0.02);
    }

    return entity.copyWith(
      learnedLabel: learnedLabel,
      learnedLabelConfidence:
          learnedConfidence == 0.0 ? null : learnedConfidence.clamp(0.0, 0.99),
      adaptiveConfidence: adaptiveConfidence.clamp(0.02, 0.99).toDouble(),
      correctionCount: correctionCount,
      falsePositiveCount: falsePositiveCount,
    );
  }

  double _blendConfidence(double base, double learned) {
    return base + ((learned - base) * 0.45);
  }
}
