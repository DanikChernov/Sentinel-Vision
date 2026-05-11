class StageTimingBreakdown {
  const StageTimingBreakdown({
    this.sourceAcquisitionMs = 0,
    this.colorConversionMs = 0,
    this.rotationMs = 0,
    this.resizeMs = 0,
    this.normalizationMs = 0,
    this.tensorCopyMs = 0,
    this.inferenceMs = 0,
    this.outputParsingMs = 0,
    this.trackingMs = 0,
    this.persistenceMs = 0,
    this.learningMs = 0,
    this.loggingMs = 0,
    this.overlayRepaintMs = 0,
    this.totalPipelineMs = 0,
    this.overlayRepaintCount = 0,
    this.liveWidgetBuildCount = 0,
    this.pipelinePath = 'idle',
  });

  final double sourceAcquisitionMs;
  final double colorConversionMs;
  final double rotationMs;
  final double resizeMs;
  final double normalizationMs;
  final double tensorCopyMs;
  final double inferenceMs;
  final double outputParsingMs;
  final double trackingMs;
  final double persistenceMs;
  final double learningMs;
  final double loggingMs;
  final double overlayRepaintMs;
  final double totalPipelineMs;
  final int overlayRepaintCount;
  final int liveWidgetBuildCount;
  final String pipelinePath;

  StageTimingBreakdown copyWith({
    double? sourceAcquisitionMs,
    double? colorConversionMs,
    double? rotationMs,
    double? resizeMs,
    double? normalizationMs,
    double? tensorCopyMs,
    double? inferenceMs,
    double? outputParsingMs,
    double? trackingMs,
    double? persistenceMs,
    double? learningMs,
    double? loggingMs,
    double? overlayRepaintMs,
    double? totalPipelineMs,
    int? overlayRepaintCount,
    int? liveWidgetBuildCount,
    String? pipelinePath,
  }) {
    return StageTimingBreakdown(
      sourceAcquisitionMs:
          sourceAcquisitionMs ?? this.sourceAcquisitionMs,
      colorConversionMs:
          colorConversionMs ?? this.colorConversionMs,
      rotationMs: rotationMs ?? this.rotationMs,
      resizeMs: resizeMs ?? this.resizeMs,
      normalizationMs:
          normalizationMs ?? this.normalizationMs,
      tensorCopyMs: tensorCopyMs ?? this.tensorCopyMs,
      inferenceMs: inferenceMs ?? this.inferenceMs,
      outputParsingMs: outputParsingMs ?? this.outputParsingMs,
      trackingMs: trackingMs ?? this.trackingMs,
      persistenceMs: persistenceMs ?? this.persistenceMs,
      learningMs: learningMs ?? this.learningMs,
      loggingMs: loggingMs ?? this.loggingMs,
      overlayRepaintMs:
          overlayRepaintMs ?? this.overlayRepaintMs,
      totalPipelineMs: totalPipelineMs ?? this.totalPipelineMs,
      overlayRepaintCount:
          overlayRepaintCount ?? this.overlayRepaintCount,
      liveWidgetBuildCount:
          liveWidgetBuildCount ?? this.liveWidgetBuildCount,
      pipelinePath: pipelinePath ?? this.pipelinePath,
    );
  }
}
