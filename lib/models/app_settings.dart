enum ModelBackend {
  tflite('LiteRT / TFLite'),
  onnx('ONNX Hook'),
  api('Remote/Local API Hook');

  const ModelBackend(this.label);

  final String label;
}

class AppSettings {
  const AppSettings({
    this.detectionEnabled = true,
    this.trackingEnabled = true,
    this.reidentificationEnabled = true,
    this.semanticLabelerEnabled = true,
    this.continuousLearningEnabled = true,
    this.saveDetectionCropsEnabled = false,
    this.identityLearningEnabled = true,
    this.labelCorrectionLearningEnabled = true,
    this.faceAnalysisPersistenceEnabled = true,
    this.temporalPersistenceEnabled = true,
    this.confidenceThreshold = 0.45,
    this.identityPersistence = const Duration(seconds: 4),
    this.embeddingSimilarityThreshold = 0.78,
    this.backend = ModelBackend.tflite,
  });

  final bool detectionEnabled;
  final bool trackingEnabled;
  final bool reidentificationEnabled;
  final bool semanticLabelerEnabled;
  final bool continuousLearningEnabled;
  final bool saveDetectionCropsEnabled;
  final bool identityLearningEnabled;
  final bool labelCorrectionLearningEnabled;
  final bool faceAnalysisPersistenceEnabled;
  final bool temporalPersistenceEnabled;
  final double confidenceThreshold;
  final Duration identityPersistence;
  final double embeddingSimilarityThreshold;
  final ModelBackend backend;

  AppSettings copyWith({
    bool? detectionEnabled,
    bool? trackingEnabled,
    bool? reidentificationEnabled,
    bool? semanticLabelerEnabled,
    bool? continuousLearningEnabled,
    bool? saveDetectionCropsEnabled,
    bool? identityLearningEnabled,
    bool? labelCorrectionLearningEnabled,
    bool? faceAnalysisPersistenceEnabled,
    bool? temporalPersistenceEnabled,
    double? confidenceThreshold,
    Duration? identityPersistence,
    double? embeddingSimilarityThreshold,
    ModelBackend? backend,
  }) {
    return AppSettings(
      detectionEnabled: detectionEnabled ?? this.detectionEnabled,
      trackingEnabled: trackingEnabled ?? this.trackingEnabled,
      reidentificationEnabled:
          reidentificationEnabled ?? this.reidentificationEnabled,
      semanticLabelerEnabled:
          semanticLabelerEnabled ?? this.semanticLabelerEnabled,
      continuousLearningEnabled:
          continuousLearningEnabled ?? this.continuousLearningEnabled,
      saveDetectionCropsEnabled:
          saveDetectionCropsEnabled ?? this.saveDetectionCropsEnabled,
      identityLearningEnabled:
          identityLearningEnabled ?? this.identityLearningEnabled,
      labelCorrectionLearningEnabled:
          labelCorrectionLearningEnabled ?? this.labelCorrectionLearningEnabled,
      faceAnalysisPersistenceEnabled:
          faceAnalysisPersistenceEnabled ?? this.faceAnalysisPersistenceEnabled,
      temporalPersistenceEnabled:
          temporalPersistenceEnabled ?? this.temporalPersistenceEnabled,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      identityPersistence: identityPersistence ?? this.identityPersistence,
      embeddingSimilarityThreshold:
          embeddingSimilarityThreshold ?? this.embeddingSimilarityThreshold,
      backend: backend ?? this.backend,
    );
  }
}
