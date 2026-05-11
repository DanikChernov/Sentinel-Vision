import 'bounding_box.dart';

enum FaceEmbeddingBackend {
  localDescriptor('Local Descriptor'),
  arcFaceTflite('ArcFace TFLite Hook'),
  mobileFaceNetTflite('MobileFaceNet TFLite Hook'),
  faceNetTflite('FaceNet TFLite Hook'),
  insightFaceOnnx('InsightFace ONNX Hook'),
  deepFaceStyleOnnx('DeepFace-Style ONNX Hook');

  const FaceEmbeddingBackend(this.label);

  final String label;
}

class FaceEmbeddingRecord {
  const FaceEmbeddingRecord({
    required this.stableLabel,
    required this.classLabel,
    required this.embedding,
    required this.embeddingCount,
    required this.sightings,
    required this.recoveries,
    required this.correctionCount,
    required this.averageSimilarity,
    required this.averageTemporalConfidence,
    required this.averageFaceConfidence,
    required this.lastBoundingBox,
    required this.lastSeenAt,
    this.preferredAlias,
  });

  final String stableLabel;
  final String classLabel;
  final List<double> embedding;
  final int embeddingCount;
  final int sightings;
  final int recoveries;
  final int correctionCount;
  final double averageSimilarity;
  final double averageTemporalConfidence;
  final double averageFaceConfidence;
  final BoundingBox lastBoundingBox;
  final DateTime lastSeenAt;
  final String? preferredAlias;

  FaceEmbeddingRecord copyWith({
    List<double>? embedding,
    int? embeddingCount,
    int? sightings,
    int? recoveries,
    int? correctionCount,
    double? averageSimilarity,
    double? averageTemporalConfidence,
    double? averageFaceConfidence,
    BoundingBox? lastBoundingBox,
    DateTime? lastSeenAt,
    String? preferredAlias,
    bool clearPreferredAlias = false,
  }) {
    return FaceEmbeddingRecord(
      stableLabel: stableLabel,
      classLabel: classLabel,
      embedding: embedding ?? this.embedding,
      embeddingCount: embeddingCount ?? this.embeddingCount,
      sightings: sightings ?? this.sightings,
      recoveries: recoveries ?? this.recoveries,
      correctionCount: correctionCount ?? this.correctionCount,
      averageSimilarity: averageSimilarity ?? this.averageSimilarity,
      averageTemporalConfidence:
          averageTemporalConfidence ?? this.averageTemporalConfidence,
      averageFaceConfidence:
          averageFaceConfidence ?? this.averageFaceConfidence,
      lastBoundingBox: lastBoundingBox ?? this.lastBoundingBox,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      preferredAlias: clearPreferredAlias
          ? null
          : preferredAlias ?? this.preferredAlias,
    );
  }
}

class PersistenceSnapshot {
  const PersistenceSnapshot({
    this.backend = FaceEmbeddingBackend.localDescriptor,
    this.embeddingsStored = 0,
    this.recoveredIdentities = 0,
    this.averageSimilarity = 0,
    this.identityRecoveryRate = 0,
    this.averageTemporalConfidence = 0,
    this.averageFaceConfidence = 0,
    this.memoryBytes = 0,
    this.identities = const <FaceEmbeddingRecord>[],
  });

  final FaceEmbeddingBackend backend;
  final int embeddingsStored;
  final int recoveredIdentities;
  final double averageSimilarity;
  final double identityRecoveryRate;
  final double averageTemporalConfidence;
  final double averageFaceConfidence;
  final int memoryBytes;
  final List<FaceEmbeddingRecord> identities;

  PersistenceSnapshot copyWith({
    FaceEmbeddingBackend? backend,
    int? embeddingsStored,
    int? recoveredIdentities,
    double? averageSimilarity,
    double? identityRecoveryRate,
    double? averageTemporalConfidence,
    double? averageFaceConfidence,
    int? memoryBytes,
    List<FaceEmbeddingRecord>? identities,
  }) {
    return PersistenceSnapshot(
      backend: backend ?? this.backend,
      embeddingsStored: embeddingsStored ?? this.embeddingsStored,
      recoveredIdentities: recoveredIdentities ?? this.recoveredIdentities,
      averageSimilarity: averageSimilarity ?? this.averageSimilarity,
      identityRecoveryRate: identityRecoveryRate ?? this.identityRecoveryRate,
      averageTemporalConfidence:
          averageTemporalConfidence ?? this.averageTemporalConfidence,
      averageFaceConfidence:
          averageFaceConfidence ?? this.averageFaceConfidence,
      memoryBytes: memoryBytes ?? this.memoryBytes,
      identities: identities ?? this.identities,
    );
  }
}

class FaceEmbeddingResult {
  const FaceEmbeddingResult({
    required this.embedding,
    required this.faceConfidence,
  });

  final List<double> embedding;
  final double faceConfidence;
}

class IdentityMatchResult {
  const IdentityMatchResult({
    required this.stableLabel,
    required this.similarity,
    required this.temporalConfidence,
    required this.combinedConfidence,
    required this.record,
  });

  final String stableLabel;
  final double similarity;
  final double temporalConfidence;
  final double combinedConfidence;
  final FaceEmbeddingRecord record;
}
