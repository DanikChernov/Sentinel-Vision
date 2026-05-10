// ignore_for_file: use_null_aware_elements

import 'bounding_box.dart';

class TrackedEntity {
  const TrackedEntity({
    required this.trackId,
    required this.stableLabel,
    required this.classLabel,
    required this.boundingBox,
    required this.confidence,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.detectorConfidence,
    this.semanticLabel,
    this.learnedLabel,
    this.learnedLabelConfidence,
    this.adaptiveConfidence,
    this.identityConfidence,
    this.faceConfidence,
    this.embeddingSimilarity,
    this.temporalConfidence,
    this.correctionCount = 0,
    this.falsePositiveCount = 0,
    this.missedFrames = 0,
    this.isVisible = true,
    this.recoveredInFrame = false,
  });

  final String trackId;
  final String stableLabel;
  final String classLabel;
  final double? detectorConfidence;
  final String? semanticLabel;
  final String? learnedLabel;
  final double? learnedLabelConfidence;
  final double? adaptiveConfidence;
  final double? identityConfidence;
  final double? faceConfidence;
  final double? embeddingSimilarity;
  final double? temporalConfidence;
  final int correctionCount;
  final int falsePositiveCount;
  final BoundingBox boundingBox;
  final double confidence;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int missedFrames;
  final bool isVisible;
  final bool recoveredInFrame;

  String get displayLabel {
    final preferredLabel = learnedLabel ?? semanticLabel;
    return preferredLabel == null ? stableLabel : '$stableLabel / $preferredLabel';
  }

  String get detailLabel {
    final parts = <String>[
      if (learnedLabel != null) learnedLabel!,
      if (semanticLabel != null && semanticLabel != learnedLabel) semanticLabel!,
      classLabel,
    ];
    return parts.join(' | ');
  }

  double get displayConfidence => adaptiveConfidence ?? confidence;

  double get confidenceGain =>
      displayConfidence - (detectorConfidence ?? confidence);

  TrackedEntity resetLearningState() {
    return TrackedEntity(
      trackId: trackId,
      stableLabel: stableLabel,
      classLabel: classLabel,
      boundingBox: boundingBox,
      confidence: confidence,
      detectorConfidence: detectorConfidence,
      firstSeenAt: firstSeenAt,
      lastSeenAt: lastSeenAt,
      semanticLabel: semanticLabel,
      missedFrames: missedFrames,
      isVisible: isVisible,
      recoveredInFrame: recoveredInFrame,
    );
  }

  TrackedEntity copyWith({
    String? trackId,
    String? stableLabel,
    String? classLabel,
    double? detectorConfidence,
    String? semanticLabel,
    String? learnedLabel,
    double? learnedLabelConfidence,
    double? adaptiveConfidence,
    double? identityConfidence,
    double? faceConfidence,
    double? embeddingSimilarity,
    double? temporalConfidence,
    int? correctionCount,
    int? falsePositiveCount,
    BoundingBox? boundingBox,
    double? confidence,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
    int? missedFrames,
    bool? isVisible,
    bool? recoveredInFrame,
  }) {
    return TrackedEntity(
      trackId: trackId ?? this.trackId,
      stableLabel: stableLabel ?? this.stableLabel,
      classLabel: classLabel ?? this.classLabel,
      detectorConfidence: detectorConfidence ?? this.detectorConfidence,
      semanticLabel: semanticLabel ?? this.semanticLabel,
      learnedLabel: learnedLabel ?? this.learnedLabel,
      learnedLabelConfidence:
          learnedLabelConfidence ?? this.learnedLabelConfidence,
      adaptiveConfidence: adaptiveConfidence ?? this.adaptiveConfidence,
      identityConfidence: identityConfidence ?? this.identityConfidence,
      faceConfidence: faceConfidence ?? this.faceConfidence,
      embeddingSimilarity: embeddingSimilarity ?? this.embeddingSimilarity,
      temporalConfidence: temporalConfidence ?? this.temporalConfidence,
      correctionCount: correctionCount ?? this.correctionCount,
      falsePositiveCount: falsePositiveCount ?? this.falsePositiveCount,
      boundingBox: boundingBox ?? this.boundingBox,
      confidence: confidence ?? this.confidence,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      missedFrames: missedFrames ?? this.missedFrames,
      isVisible: isVisible ?? this.isVisible,
      recoveredInFrame: recoveredInFrame ?? this.recoveredInFrame,
    );
  }
}
