import 'bounding_box.dart';
import 'video_source.dart';

class LearnedIdentitySummary {
  const LearnedIdentitySummary({
    required this.stableLabel,
    required this.classLabel,
    required this.sightings,
    required this.recoveries,
    required this.correctionCount,
    required this.averageDetectorConfidence,
    required this.learnedConfidence,
    required this.averageWidth,
    required this.averageHeight,
    required this.averageCenterX,
    required this.averageCenterY,
    required this.averageMotion,
    required this.lastSeenAt,
    this.preferredAlias,
    this.lastSourceType = VisionSourceType.camera,
  });

  final String stableLabel;
  final String classLabel;
  final String? preferredAlias;
  final int sightings;
  final int recoveries;
  final int correctionCount;
  final double averageDetectorConfidence;
  final double learnedConfidence;
  final double averageWidth;
  final double averageHeight;
  final double averageCenterX;
  final double averageCenterY;
  final double averageMotion;
  final DateTime lastSeenAt;
  final VisionSourceType lastSourceType;

  LearnedIdentitySummary copyWith({
    String? preferredAlias,
    int? sightings,
    int? recoveries,
    int? correctionCount,
    double? averageDetectorConfidence,
    double? learnedConfidence,
    double? averageWidth,
    double? averageHeight,
    double? averageCenterX,
    double? averageCenterY,
    double? averageMotion,
    DateTime? lastSeenAt,
    VisionSourceType? lastSourceType,
  }) {
    return LearnedIdentitySummary(
      stableLabel: stableLabel,
      classLabel: classLabel,
      preferredAlias: preferredAlias ?? this.preferredAlias,
      sightings: sightings ?? this.sightings,
      recoveries: recoveries ?? this.recoveries,
      correctionCount: correctionCount ?? this.correctionCount,
      averageDetectorConfidence:
          averageDetectorConfidence ?? this.averageDetectorConfidence,
      learnedConfidence: learnedConfidence ?? this.learnedConfidence,
      averageWidth: averageWidth ?? this.averageWidth,
      averageHeight: averageHeight ?? this.averageHeight,
      averageCenterX: averageCenterX ?? this.averageCenterX,
      averageCenterY: averageCenterY ?? this.averageCenterY,
      averageMotion: averageMotion ?? this.averageMotion,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastSourceType: lastSourceType ?? this.lastSourceType,
    );
  }
}

class CorrectedLabelSummary {
  const CorrectedLabelSummary({
    required this.key,
    required this.originalLabel,
    required this.correctedLabel,
    required this.usageCount,
    required this.falsePositiveCount,
    required this.averageLearningConfidence,
    required this.lastUpdatedAt,
  });

  final String key;
  final String originalLabel;
  final String correctedLabel;
  final int usageCount;
  final int falsePositiveCount;
  final double averageLearningConfidence;
  final DateTime lastUpdatedAt;

  CorrectedLabelSummary copyWith({
    int? usageCount,
    int? falsePositiveCount,
    double? averageLearningConfidence,
    DateTime? lastUpdatedAt,
  }) {
    return CorrectedLabelSummary(
      key: key,
      originalLabel: originalLabel,
      correctedLabel: correctedLabel,
      usageCount: usageCount ?? this.usageCount,
      falsePositiveCount: falsePositiveCount ?? this.falsePositiveCount,
      averageLearningConfidence:
          averageLearningConfidence ?? this.averageLearningConfidence,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }
}

class TrainingSampleRecord {
  const TrainingSampleRecord({
    this.id,
    required this.cropPath,
    required this.originalLabel,
    required this.stableLabel,
    required this.confidence,
    required this.timestamp,
    required this.boundingBox,
    required this.sourceType,
    this.correctedLabel,
    this.exported = false,
    this.feedbackApplied = false,
  });

  final int? id;
  final String cropPath;
  final String originalLabel;
  final String? correctedLabel;
  final String stableLabel;
  final double confidence;
  final DateTime timestamp;
  final BoundingBox boundingBox;
  final VisionSourceType sourceType;
  final bool exported;
  final bool feedbackApplied;

  TrainingSampleRecord copyWith({
    int? id,
    String? correctedLabel,
    bool? exported,
    bool? feedbackApplied,
  }) {
    return TrainingSampleRecord(
      id: id ?? this.id,
      cropPath: cropPath,
      originalLabel: originalLabel,
      correctedLabel: correctedLabel ?? this.correctedLabel,
      stableLabel: stableLabel,
      confidence: confidence,
      timestamp: timestamp,
      boundingBox: boundingBox,
      sourceType: sourceType,
      exported: exported ?? this.exported,
      feedbackApplied: feedbackApplied ?? this.feedbackApplied,
    );
  }
}

class LearningMetrics {
  const LearningMetrics({
    this.observationCount = 0,
    this.correctionCount = 0,
    this.falsePositiveCount = 0,
    this.trainingSampleCount = 0,
    this.identityCount = 0,
    this.correctedLabelCount = 0,
    this.averageConfidenceGain = 0,
    this.approximateStorageBytes = 0,
  });

  final int observationCount;
  final int correctionCount;
  final int falsePositiveCount;
  final int trainingSampleCount;
  final int identityCount;
  final int correctedLabelCount;
  final double averageConfidenceGain;
  final int approximateStorageBytes;

  LearningMetrics copyWith({
    int? observationCount,
    int? correctionCount,
    int? falsePositiveCount,
    int? trainingSampleCount,
    int? identityCount,
    int? correctedLabelCount,
    double? averageConfidenceGain,
    int? approximateStorageBytes,
  }) {
    return LearningMetrics(
      observationCount: observationCount ?? this.observationCount,
      correctionCount: correctionCount ?? this.correctionCount,
      falsePositiveCount: falsePositiveCount ?? this.falsePositiveCount,
      trainingSampleCount: trainingSampleCount ?? this.trainingSampleCount,
      identityCount: identityCount ?? this.identityCount,
      correctedLabelCount: correctedLabelCount ?? this.correctedLabelCount,
      averageConfidenceGain:
          averageConfidenceGain ?? this.averageConfidenceGain,
      approximateStorageBytes:
          approximateStorageBytes ?? this.approximateStorageBytes,
    );
  }
}

class LearningSnapshot {
  const LearningSnapshot({
    this.metrics = const LearningMetrics(),
    this.identities = const <LearnedIdentitySummary>[],
    this.correctedLabels = const <CorrectedLabelSummary>[],
    this.recentSamples = const <TrainingSampleRecord>[],
  });

  final LearningMetrics metrics;
  final List<LearnedIdentitySummary> identities;
  final List<CorrectedLabelSummary> correctedLabels;
  final List<TrainingSampleRecord> recentSamples;

  LearningSnapshot copyWith({
    LearningMetrics? metrics,
    List<LearnedIdentitySummary>? identities,
    List<CorrectedLabelSummary>? correctedLabels,
    List<TrainingSampleRecord>? recentSamples,
  }) {
    return LearningSnapshot(
      metrics: metrics ?? this.metrics,
      identities: identities ?? this.identities,
      correctedLabels: correctedLabels ?? this.correctedLabels,
      recentSamples: recentSamples ?? this.recentSamples,
    );
  }
}
