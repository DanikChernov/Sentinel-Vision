enum ModelBackend {
  tflite('LiteRT / TFLite'),
  yolo26('YOLO26 LiteRT/TFLite'),
  onnx('ONNX Hook'),
  api('Remote/Local API Hook');

  const ModelBackend(this.label);

  final String label;
}

enum InferenceAcceleration {
  auto('Auto'),
  cpu('CPU'),
  xnnpack('XNNPACK'),
  gpu('GPU');

  const InferenceAcceleration(this.label);

  final String label;
}

enum CameraCaptureProfile {
  low('Low 360p/480p'),
  medium('Medium 480p/640p'),
  high('High 640p/720p');

  const CameraCaptureProfile(this.label);

  final String label;
}

enum PerceptionPerformanceMode {
  fast('Fast'),
  balanced('Balanced'),
  accurate('Accurate'),
  research('Research');

  const PerceptionPerformanceMode(this.label);

  final String label;
}

enum SegmentationQuality {
  fast('Fast'),
  balanced('Balanced'),
  accurate('Accurate');

  const SegmentationQuality(this.label);

  final String label;
}

enum SamPromptMode {
  box('Box Prompt'),
  text('Text Prompt'),
  video('Video Refinement'),
  selectedObject('Selected Object');

  const SamPromptMode(this.label);

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
    this.reIdConfidenceThreshold = 0.45,
    this.embeddingSimilarityThreshold = 0.78,
    this.backend = ModelBackend.tflite,
    this.acceleration = InferenceAcceleration.auto,
    this.cameraCaptureProfile = CameraCaptureProfile.low,
    this.modelInputSize = 320,
    this.tfliteThreadCount = 2,
    this.performanceMode = PerceptionPerformanceMode.balanced,
    this.detectionInterval = 3,
    this.segmentationEnabled = false,
    this.segmentationInterval = 5,
    this.samRefinementEnabled = false,
    this.samRefinementInterval = 10,
    this.samPromptMode = SamPromptMode.box,
    this.samBackendUrl = '',
    this.samSelectedObjectsOnly = true,
    this.samVideoFilesOnly = false,
    this.faceReIdInterval = 10,
    this.objectEmbeddingsEnabled = false,
    this.objectEmbeddingInterval = 10,
    this.objectEmbeddingsOnlyWhenUncertain = true,
    this.objectSimilarityThreshold = 0.76,
    this.poseEnabled = false,
    this.bodyPoseEnabled = true,
    this.handPoseEnabled = false,
    this.poseInterval = 6,
    this.depthEnabled = false,
    this.depthInterval = 8,
    this.sceneContextEnabled = false,
    this.sceneContextInterval = 15,
    this.maxObjectsRefinedPerFrame = 2,
    this.maxFaceEmbeddingsPerFrame = 2,
    this.maxObjectEmbeddingsPerFrame = 3,
    this.storeLocalFaceEmbeddings = true,
    this.storeLocalObjectEmbeddings = true,
    this.saveMasksEnabled = false,
    this.savePoseMetadataEnabled = false,
    this.saveDepthMetadataEnabled = false,
    this.drawBoxes = true,
    this.drawLabels = true,
    this.drawMasks = true,
    this.drawPolygons = true,
    this.drawPoseSkeleton = true,
    this.drawDepthOverlay = false,
    this.drawIdentityConfidence = true,
    this.drawDiagnosticsOverlay = false,
    this.maskOpacity = 0.28,
    this.maskQuality = SegmentationQuality.balanced,
    this.segmentationInputSize = 416,
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
  final double reIdConfidenceThreshold;
  final double embeddingSimilarityThreshold;
  final ModelBackend backend;
  final InferenceAcceleration acceleration;
  final CameraCaptureProfile cameraCaptureProfile;
  final int modelInputSize;
  final int tfliteThreadCount;
  final PerceptionPerformanceMode performanceMode;
  final int detectionInterval;
  final bool segmentationEnabled;
  final int segmentationInterval;
  final bool samRefinementEnabled;
  final int samRefinementInterval;
  final SamPromptMode samPromptMode;
  final String samBackendUrl;
  final bool samSelectedObjectsOnly;
  final bool samVideoFilesOnly;
  final int faceReIdInterval;
  final bool objectEmbeddingsEnabled;
  final int objectEmbeddingInterval;
  final bool objectEmbeddingsOnlyWhenUncertain;
  final double objectSimilarityThreshold;
  final bool poseEnabled;
  final bool bodyPoseEnabled;
  final bool handPoseEnabled;
  final int poseInterval;
  final bool depthEnabled;
  final int depthInterval;
  final bool sceneContextEnabled;
  final int sceneContextInterval;
  final int maxObjectsRefinedPerFrame;
  final int maxFaceEmbeddingsPerFrame;
  final int maxObjectEmbeddingsPerFrame;
  final bool storeLocalFaceEmbeddings;
  final bool storeLocalObjectEmbeddings;
  final bool saveMasksEnabled;
  final bool savePoseMetadataEnabled;
  final bool saveDepthMetadataEnabled;
  final bool drawBoxes;
  final bool drawLabels;
  final bool drawMasks;
  final bool drawPolygons;
  final bool drawPoseSkeleton;
  final bool drawDepthOverlay;
  final bool drawIdentityConfidence;
  final bool drawDiagnosticsOverlay;
  final double maskOpacity;
  final SegmentationQuality maskQuality;
  final int segmentationInputSize;

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
    double? reIdConfidenceThreshold,
    double? embeddingSimilarityThreshold,
    ModelBackend? backend,
    InferenceAcceleration? acceleration,
    CameraCaptureProfile? cameraCaptureProfile,
    int? modelInputSize,
    int? tfliteThreadCount,
    PerceptionPerformanceMode? performanceMode,
    int? detectionInterval,
    bool? segmentationEnabled,
    int? segmentationInterval,
    bool? samRefinementEnabled,
    int? samRefinementInterval,
    SamPromptMode? samPromptMode,
    String? samBackendUrl,
    bool? samSelectedObjectsOnly,
    bool? samVideoFilesOnly,
    int? faceReIdInterval,
    bool? objectEmbeddingsEnabled,
    int? objectEmbeddingInterval,
    bool? objectEmbeddingsOnlyWhenUncertain,
    double? objectSimilarityThreshold,
    bool? poseEnabled,
    bool? bodyPoseEnabled,
    bool? handPoseEnabled,
    int? poseInterval,
    bool? depthEnabled,
    int? depthInterval,
    bool? sceneContextEnabled,
    int? sceneContextInterval,
    int? maxObjectsRefinedPerFrame,
    int? maxFaceEmbeddingsPerFrame,
    int? maxObjectEmbeddingsPerFrame,
    bool? storeLocalFaceEmbeddings,
    bool? storeLocalObjectEmbeddings,
    bool? saveMasksEnabled,
    bool? savePoseMetadataEnabled,
    bool? saveDepthMetadataEnabled,
    bool? drawBoxes,
    bool? drawLabels,
    bool? drawMasks,
    bool? drawPolygons,
    bool? drawPoseSkeleton,
    bool? drawDepthOverlay,
    bool? drawIdentityConfidence,
    bool? drawDiagnosticsOverlay,
    double? maskOpacity,
    SegmentationQuality? maskQuality,
    int? segmentationInputSize,
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
      reIdConfidenceThreshold:
          reIdConfidenceThreshold ?? this.reIdConfidenceThreshold,
      embeddingSimilarityThreshold:
          embeddingSimilarityThreshold ?? this.embeddingSimilarityThreshold,
      backend: backend ?? this.backend,
      acceleration: acceleration ?? this.acceleration,
      cameraCaptureProfile: cameraCaptureProfile ?? this.cameraCaptureProfile,
      modelInputSize: modelInputSize ?? this.modelInputSize,
      tfliteThreadCount: tfliteThreadCount ?? this.tfliteThreadCount,
      performanceMode: performanceMode ?? this.performanceMode,
      detectionInterval: detectionInterval ?? this.detectionInterval,
      segmentationEnabled: segmentationEnabled ?? this.segmentationEnabled,
      segmentationInterval: segmentationInterval ?? this.segmentationInterval,
      samRefinementEnabled: samRefinementEnabled ?? this.samRefinementEnabled,
      samRefinementInterval:
          samRefinementInterval ?? this.samRefinementInterval,
      samPromptMode: samPromptMode ?? this.samPromptMode,
      samBackendUrl: samBackendUrl ?? this.samBackendUrl,
      samSelectedObjectsOnly:
          samSelectedObjectsOnly ?? this.samSelectedObjectsOnly,
      samVideoFilesOnly: samVideoFilesOnly ?? this.samVideoFilesOnly,
      faceReIdInterval: faceReIdInterval ?? this.faceReIdInterval,
      objectEmbeddingsEnabled:
          objectEmbeddingsEnabled ?? this.objectEmbeddingsEnabled,
      objectEmbeddingInterval:
          objectEmbeddingInterval ?? this.objectEmbeddingInterval,
      objectEmbeddingsOnlyWhenUncertain:
          objectEmbeddingsOnlyWhenUncertain ??
          this.objectEmbeddingsOnlyWhenUncertain,
      objectSimilarityThreshold:
          objectSimilarityThreshold ?? this.objectSimilarityThreshold,
      poseEnabled: poseEnabled ?? this.poseEnabled,
      bodyPoseEnabled: bodyPoseEnabled ?? this.bodyPoseEnabled,
      handPoseEnabled: handPoseEnabled ?? this.handPoseEnabled,
      poseInterval: poseInterval ?? this.poseInterval,
      depthEnabled: depthEnabled ?? this.depthEnabled,
      depthInterval: depthInterval ?? this.depthInterval,
      sceneContextEnabled: sceneContextEnabled ?? this.sceneContextEnabled,
      sceneContextInterval: sceneContextInterval ?? this.sceneContextInterval,
      maxObjectsRefinedPerFrame:
          maxObjectsRefinedPerFrame ?? this.maxObjectsRefinedPerFrame,
      maxFaceEmbeddingsPerFrame:
          maxFaceEmbeddingsPerFrame ?? this.maxFaceEmbeddingsPerFrame,
      maxObjectEmbeddingsPerFrame:
          maxObjectEmbeddingsPerFrame ?? this.maxObjectEmbeddingsPerFrame,
      storeLocalFaceEmbeddings:
          storeLocalFaceEmbeddings ?? this.storeLocalFaceEmbeddings,
      storeLocalObjectEmbeddings:
          storeLocalObjectEmbeddings ?? this.storeLocalObjectEmbeddings,
      saveMasksEnabled: saveMasksEnabled ?? this.saveMasksEnabled,
      savePoseMetadataEnabled:
          savePoseMetadataEnabled ?? this.savePoseMetadataEnabled,
      saveDepthMetadataEnabled:
          saveDepthMetadataEnabled ?? this.saveDepthMetadataEnabled,
      drawBoxes: drawBoxes ?? this.drawBoxes,
      drawLabels: drawLabels ?? this.drawLabels,
      drawMasks: drawMasks ?? this.drawMasks,
      drawPolygons: drawPolygons ?? this.drawPolygons,
      drawPoseSkeleton: drawPoseSkeleton ?? this.drawPoseSkeleton,
      drawDepthOverlay: drawDepthOverlay ?? this.drawDepthOverlay,
      drawIdentityConfidence:
          drawIdentityConfidence ?? this.drawIdentityConfidence,
      drawDiagnosticsOverlay:
          drawDiagnosticsOverlay ?? this.drawDiagnosticsOverlay,
      maskOpacity: maskOpacity ?? this.maskOpacity,
      maskQuality: maskQuality ?? this.maskQuality,
      segmentationInputSize:
          segmentationInputSize ?? this.segmentationInputSize,
    );
  }

  AppSettings applyPerformanceMode(PerceptionPerformanceMode mode) {
    return switch (mode) {
      PerceptionPerformanceMode.fast => copyWith(
        performanceMode: mode,
        detectionInterval: 5,
        segmentationEnabled: false,
        segmentationInterval: 10,
        samRefinementEnabled: false,
        faceReIdInterval: 15,
        objectEmbeddingsEnabled: false,
        poseEnabled: false,
        depthEnabled: false,
        modelInputSize: 320,
        segmentationInputSize: 320,
      ),
      PerceptionPerformanceMode.balanced => copyWith(
        performanceMode: mode,
        detectionInterval: 3,
        segmentationEnabled: true,
        segmentationInterval: 5,
        samRefinementEnabled: false,
        faceReIdInterval: 10,
        objectEmbeddingsEnabled: true,
        objectEmbeddingsOnlyWhenUncertain: true,
        modelInputSize: 416,
        segmentationInputSize: 416,
      ),
      PerceptionPerformanceMode.accurate => copyWith(
        performanceMode: mode,
        detectionInterval: 2,
        segmentationEnabled: true,
        segmentationInterval: 3,
        samRefinementEnabled: true,
        faceReIdInterval: 6,
        objectEmbeddingsEnabled: true,
        modelInputSize: 640,
        segmentationInputSize: 640,
      ),
      PerceptionPerformanceMode.research => copyWith(
        performanceMode: mode,
        detectionInterval: 1,
        segmentationEnabled: true,
        segmentationInterval: 2,
        samRefinementEnabled: true,
        faceReIdInterval: 4,
        objectEmbeddingsEnabled: true,
        poseEnabled: true,
        depthEnabled: true,
        sceneContextEnabled: true,
        modelInputSize: 640,
        segmentationInputSize: 640,
        drawDiagnosticsOverlay: true,
      ),
    };
  }
}
