class PipelineMetrics {
  const PipelineMetrics({
    this.fps = 0,
    this.frameLatencyMs = 0,
    this.processedFrames = 0,
    this.droppedFrames = 0,
    this.queuedFrames = 0,
    this.inferenceFrames = 0,
    this.adaptiveFrameIntervalMs = 0,
    this.thermalThrottleSuggested = false,
    this.lastFrameAt,
  });

  final double fps;
  final double frameLatencyMs;
  final int processedFrames;
  final int droppedFrames;
  final int queuedFrames;
  final int inferenceFrames;
  final double adaptiveFrameIntervalMs;
  final bool thermalThrottleSuggested;
  final DateTime? lastFrameAt;

  PipelineMetrics copyWith({
    double? fps,
    double? frameLatencyMs,
    int? processedFrames,
    int? droppedFrames,
    int? queuedFrames,
    int? inferenceFrames,
    double? adaptiveFrameIntervalMs,
    bool? thermalThrottleSuggested,
    DateTime? lastFrameAt,
  }) {
    return PipelineMetrics(
      fps: fps ?? this.fps,
      frameLatencyMs: frameLatencyMs ?? this.frameLatencyMs,
      processedFrames: processedFrames ?? this.processedFrames,
      droppedFrames: droppedFrames ?? this.droppedFrames,
      queuedFrames: queuedFrames ?? this.queuedFrames,
      inferenceFrames: inferenceFrames ?? this.inferenceFrames,
      adaptiveFrameIntervalMs:
          adaptiveFrameIntervalMs ?? this.adaptiveFrameIntervalMs,
      thermalThrottleSuggested:
          thermalThrottleSuggested ?? this.thermalThrottleSuggested,
      lastFrameAt: lastFrameAt ?? this.lastFrameAt,
    );
  }
}
