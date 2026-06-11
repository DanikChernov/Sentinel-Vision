class DetectorDiagnostics {
  const DetectorDiagnostics({
    required this.backendName,
    this.modelLoaded = false,
    this.delegateName = 'Unknown',
    this.threadCount = 0,
    this.requestedInputSize = 0,
    this.framesReceived = 0,
    this.framesInferred = 0,
    this.frameWidth = 0,
    this.frameHeight = 0,
    this.inputShape = const <int>[],
    this.outputShapes = const <List<int>>[],
    this.inputTensorType = 'unknown',
    this.outputTensorTypes = const <String>[],
    this.labelMapLoaded = false,
    this.labelMapName = 'unbound',
    this.labelCount = 0,
    this.rawClassIds = const <int>[],
    this.mappedLabels = const <String>[],
    this.unknownLabelCount = 0,
    this.missingClassIds = const <int>[],
    this.preprocessSummary = 'Idle',
    this.parserMode = 'unbound',
    this.rawCandidateCount = 0,
    this.filteredCandidateCount = 0,
    this.trackerInputCount = 0,
    this.trackerOutputCount = 0,
    this.queueDepth = 0,
    this.skippedFrames = 0,
    this.usingIsolateWorker = false,
    this.sampleOutputValues = const <double>[],
    this.sourceAcquisitionMs = 0,
    this.colorConversionMs = 0,
    this.rotationMs = 0,
    this.resizeMs = 0,
    this.normalizationMs = 0,
    this.tensorCopyMs = 0,
    this.inferenceMs = 0,
    this.outputParsingMs = 0,
    this.lastInferenceError,
  });

  final String backendName;
  final bool modelLoaded;
  final String delegateName;
  final int threadCount;
  final int requestedInputSize;
  final int framesReceived;
  final int framesInferred;
  final int frameWidth;
  final int frameHeight;
  final List<int> inputShape;
  final List<List<int>> outputShapes;
  final String inputTensorType;
  final List<String> outputTensorTypes;
  final bool labelMapLoaded;
  final String labelMapName;
  final int labelCount;
  final List<int> rawClassIds;
  final List<String> mappedLabels;
  final int unknownLabelCount;
  final List<int> missingClassIds;
  final String preprocessSummary;
  final String parserMode;
  final int rawCandidateCount;
  final int filteredCandidateCount;
  final int trackerInputCount;
  final int trackerOutputCount;
  final int queueDepth;
  final int skippedFrames;
  final bool usingIsolateWorker;
  final List<double> sampleOutputValues;
  final double sourceAcquisitionMs;
  final double colorConversionMs;
  final double rotationMs;
  final double resizeMs;
  final double normalizationMs;
  final double tensorCopyMs;
  final double inferenceMs;
  final double outputParsingMs;
  final String? lastInferenceError;

  DetectorDiagnostics copyWith({
    String? backendName,
    bool? modelLoaded,
    String? delegateName,
    int? threadCount,
    int? requestedInputSize,
    int? framesReceived,
    int? framesInferred,
    int? frameWidth,
    int? frameHeight,
    List<int>? inputShape,
    List<List<int>>? outputShapes,
    String? inputTensorType,
    List<String>? outputTensorTypes,
    bool? labelMapLoaded,
    String? labelMapName,
    int? labelCount,
    List<int>? rawClassIds,
    List<String>? mappedLabels,
    int? unknownLabelCount,
    List<int>? missingClassIds,
    String? preprocessSummary,
    String? parserMode,
    int? rawCandidateCount,
    int? filteredCandidateCount,
    int? trackerInputCount,
    int? trackerOutputCount,
    int? queueDepth,
    int? skippedFrames,
    bool? usingIsolateWorker,
    List<double>? sampleOutputValues,
    double? sourceAcquisitionMs,
    double? colorConversionMs,
    double? rotationMs,
    double? resizeMs,
    double? normalizationMs,
    double? tensorCopyMs,
    double? inferenceMs,
    double? outputParsingMs,
    String? lastInferenceError,
    bool clearLastInferenceError = false,
  }) {
    return DetectorDiagnostics(
      backendName: backendName ?? this.backendName,
      modelLoaded: modelLoaded ?? this.modelLoaded,
      delegateName: delegateName ?? this.delegateName,
      threadCount: threadCount ?? this.threadCount,
      requestedInputSize: requestedInputSize ?? this.requestedInputSize,
      framesReceived: framesReceived ?? this.framesReceived,
      framesInferred: framesInferred ?? this.framesInferred,
      frameWidth: frameWidth ?? this.frameWidth,
      frameHeight: frameHeight ?? this.frameHeight,
      inputShape: inputShape ?? this.inputShape,
      outputShapes: outputShapes ?? this.outputShapes,
      inputTensorType: inputTensorType ?? this.inputTensorType,
      outputTensorTypes: outputTensorTypes ?? this.outputTensorTypes,
      labelMapLoaded: labelMapLoaded ?? this.labelMapLoaded,
      labelMapName: labelMapName ?? this.labelMapName,
      labelCount: labelCount ?? this.labelCount,
      rawClassIds: rawClassIds ?? this.rawClassIds,
      mappedLabels: mappedLabels ?? this.mappedLabels,
      unknownLabelCount: unknownLabelCount ?? this.unknownLabelCount,
      missingClassIds: missingClassIds ?? this.missingClassIds,
      preprocessSummary: preprocessSummary ?? this.preprocessSummary,
      parserMode: parserMode ?? this.parserMode,
      rawCandidateCount: rawCandidateCount ?? this.rawCandidateCount,
      filteredCandidateCount:
          filteredCandidateCount ?? this.filteredCandidateCount,
      trackerInputCount: trackerInputCount ?? this.trackerInputCount,
      trackerOutputCount: trackerOutputCount ?? this.trackerOutputCount,
      queueDepth: queueDepth ?? this.queueDepth,
      skippedFrames: skippedFrames ?? this.skippedFrames,
      usingIsolateWorker: usingIsolateWorker ?? this.usingIsolateWorker,
      sampleOutputValues: sampleOutputValues ?? this.sampleOutputValues,
      sourceAcquisitionMs: sourceAcquisitionMs ?? this.sourceAcquisitionMs,
      colorConversionMs: colorConversionMs ?? this.colorConversionMs,
      rotationMs: rotationMs ?? this.rotationMs,
      resizeMs: resizeMs ?? this.resizeMs,
      normalizationMs: normalizationMs ?? this.normalizationMs,
      tensorCopyMs: tensorCopyMs ?? this.tensorCopyMs,
      inferenceMs: inferenceMs ?? this.inferenceMs,
      outputParsingMs: outputParsingMs ?? this.outputParsingMs,
      lastInferenceError: clearLastInferenceError
          ? null
          : lastInferenceError ?? this.lastInferenceError,
    );
  }
}

class DetectorTestResult {
  const DetectorTestResult({
    required this.success,
    required this.message,
    this.inputShape = const <int>[],
    this.outputShapes = const <List<int>>[],
    this.sampleValues = const <double>[],
  });

  final bool success;
  final String message;
  final List<int> inputShape;
  final List<List<int>> outputShapes;
  final List<double> sampleValues;
}
