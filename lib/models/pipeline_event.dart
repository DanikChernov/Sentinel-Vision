enum PipelineEventType {
  detection,
  identityAssigned,
  identityRecovered,
  learningObservation,
  learningCorrection,
  falsePositive,
  datasetExport,
  memoryReset,
  pipelineState,
  sourceChanged,
  trackerState,
}

class PipelineEvent {
  const PipelineEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.details,
  });

  final PipelineEventType type;
  final String message;
  final DateTime timestamp;
  final Map<String, Object?>? details;
}
