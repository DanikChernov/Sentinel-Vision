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
    this.detectionId,
    this.classId = -1,
    this.sourceModel = 'unknown',
    this.persistentEntityId,
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
  final String? detectionId;
  final int classId;
  final String classLabel;
  final String sourceModel;
  final String? persistentEntityId;
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

  String get effectiveClassLabel {
    final normalized = classLabel.trim().toLowerCase();
    if (normalized.isEmpty || normalized == '???') {
      return 'unknown';
    }
    return normalized;
  }

  String get trackLabel => _formatTrackLabel(trackId);

  String? get persistentLabel {
    final id = persistentEntityId;
    if (id == null || id.trim().isEmpty || id == trackId) {
      return null;
    }
    return _formatPersistentLabel(id);
  }

  String get overlayLabel {
    final persistent = persistentLabel;
    if (persistent != null) {
      return '$effectiveClassLabel $persistent / $trackLabel';
    }
    return '$effectiveClassLabel #${_idSuffix(trackId)}';
  }

  String get displayLabel {
    final preferredLabel = learnedLabel ?? semanticLabel;
    return preferredLabel == null
        ? overlayLabel
        : '$overlayLabel / $preferredLabel';
  }

  String get detailLabel {
    final parts = <String>[
      if (learnedLabel != null) learnedLabel!,
      if (semanticLabel != null && semanticLabel != learnedLabel)
        semanticLabel!,
      effectiveClassLabel,
      'track $trackLabel',
      if (persistentLabel != null) 'persistent ${persistentLabel!}',
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
      detectionId: detectionId,
      classId: classId,
      classLabel: classLabel,
      sourceModel: sourceModel,
      persistentEntityId: persistentEntityId,
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
    String? detectionId,
    int? classId,
    String? classLabel,
    String? sourceModel,
    String? persistentEntityId,
    bool clearPersistentEntityId = false,
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
      detectionId: detectionId ?? this.detectionId,
      classId: classId ?? this.classId,
      classLabel: classLabel ?? this.classLabel,
      sourceModel: sourceModel ?? this.sourceModel,
      persistentEntityId: clearPersistentEntityId
          ? null
          : persistentEntityId ?? this.persistentEntityId,
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

  static String _formatTrackLabel(String id) => 'T-${_idSuffix(id)}';

  static String _formatPersistentLabel(String id) => 'P-${_idSuffix(id)}';

  static String _idSuffix(String id) {
    final match = RegExp(r'(\d+)$').firstMatch(id);
    if (match == null) {
      return id;
    }
    return int.parse(match.group(1)!).toString().padLeft(3, '0');
  }
}
