import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart' as litert;
import 'package:image/image.dart' as img;

import '../../models/app_settings.dart';
import '../../models/bounding_box.dart';
import '../../models/detection_result.dart';
import '../../models/frame_context.dart';
import '../../models/inference_diagnostics.dart';
import 'detector.dart';

class LiteRtObjectDetector extends Detector {
  LiteRtObjectDetector({
    this.modelAssetPath = 'assets/models/efficientdet_lite0.tflite',
    this.labelMapAssetPath = 'assets/models/labelmap.txt',
    this.scoreThreshold = 0.05,
    this.maxResults = 16,
    InferenceAcceleration acceleration = InferenceAcceleration.auto,
    int requestedInputSize = 320,
    int threadCount = 2,
  }) : _acceleration = acceleration,
       _requestedInputSize = requestedInputSize,
       _threadCount = threadCount,
       _diagnostics = DetectorDiagnostics(
         backendName: 'LiteRT / TFLite Detector',
         delegateName: acceleration.label,
         threadCount: threadCount,
         requestedInputSize: requestedInputSize,
       );

  final String modelAssetPath;
  final String labelMapAssetPath;
  final double scoreThreshold;
  final int maxResults;

  DetectorDiagnostics _diagnostics;
  Isolate? _workerIsolate;
  ReceivePort? _workerReceivePort;
  StreamSubscription<dynamic>? _workerSubscription;
  SendPort? _workerSendPort;
  Completer<void>? _initializationCompleter;
  final Map<int, Completer<Map<String, Object?>>> _pendingRequests =
      <int, Completer<Map<String, Object?>>>{};
  int _nextRequestId = 1;
  InferenceAcceleration _acceleration;
  int _requestedInputSize;
  int _threadCount;

  @override
  String get backendLabel => 'LiteRT / TFLite Detector';

  @override
  DetectorDiagnostics get diagnostics => _diagnostics;

  @override
  Future<void> initialize() async {
    if (_workerSendPort != null) {
      return;
    }
    if (_initializationCompleter case final completer?) {
      return completer.future;
    }

    final completer = Completer<void>();
    _initializationCompleter = completer;
    try {
      await _spawnWorker();
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _initializationCompleter = null;
    }
  }

  @override
  Future<void> applySettings(AppSettings settings) async {
    final previousAcceleration = _acceleration;
    final previousInputSize = _requestedInputSize;
    final previousThreadCount = _threadCount;
    final nextAcceleration = settings.acceleration;
    final nextInputSize = settings.modelInputSize;
    final nextThreadCount = settings.tfliteThreadCount.clamp(1, 8);
    final configChanged =
        nextAcceleration != _acceleration ||
        nextInputSize != _requestedInputSize ||
        nextThreadCount != _threadCount;
    if (!configChanged) {
      return;
    }

    _acceleration = nextAcceleration;
    _requestedInputSize = nextInputSize;
    _threadCount = nextThreadCount;
    _diagnostics = _diagnostics.copyWith(
      delegateName: _acceleration.label,
      threadCount: _threadCount,
      requestedInputSize: _requestedInputSize,
    );
    try {
      await _restartWorker();
    } catch (error) {
      _acceleration = previousAcceleration;
      _requestedInputSize = previousInputSize;
      _threadCount = previousThreadCount;
      _diagnostics = _diagnostics.copyWith(
        delegateName: _acceleration.label,
        threadCount: _threadCount,
        requestedInputSize: _requestedInputSize,
        lastInferenceError:
            'Rejected detector settings and reverted to the previous configuration: $error',
      );
      await _restartWorker();
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    await _shutdownWorker();
  }

  @override
  Future<List<DetectionResult>> detect(FrameContext frame) async {
    await initialize();
    _diagnostics = _diagnostics.copyWith(
      framesReceived: _diagnostics.framesReceived + 1,
      frameWidth: frame.sourceSize.width.round(),
      frameHeight: frame.sourceSize.height.round(),
      clearLastInferenceError: true,
    );

    final response = await _sendWorkerRequest('detect', <String, Object?>{
      'frame': _serializeFrame(frame),
    });

    final detections = _deserializeDetections(
      response['detections'] as List<dynamic>? ?? const <dynamic>[],
      frame.timestamp,
    );
    _diagnostics = _copyDiagnosticsFromWorker(response);
    return detections;
  }

  @override
  Future<DetectorTestResult> runTestInference({FrameContext? frame}) async {
    await initialize();
    final response = await _sendWorkerRequest('test', <String, Object?>{
      if (frame != null) 'frame': _serializeFrame(frame),
    });
    _diagnostics = _copyDiagnosticsFromWorker(response);
    final result = DetectorTestResult(
      success: (response['success'] as bool?) ?? false,
      message: response['message'] as String? ?? 'Worker test completed.',
      inputShape: _toIntList(response['inputShape']),
      outputShapes: _toShapeList(response['outputShapes']),
      sampleValues: _toDoubleList(response['sampleValues']),
    );
    return result;
  }

  Future<void> _restartWorker() async {
    await _shutdownWorker();
    await initialize();
  }

  Future<void> _spawnWorker() async {
    final receivePort = ReceivePort();
    final workerReady = Completer<SendPort>();
    _workerReceivePort = receivePort;
    _workerSubscription = receivePort.listen((dynamic message) {
      if (message is SendPort) {
        if (!workerReady.isCompleted) {
          workerReady.complete(message);
        }
        return;
      }

      if (message is! Map) {
        return;
      }
      final payload = Map<String, Object?>.from(message);
      final requestId = payload['id'] as int?;
      if (requestId == null) {
        return;
      }
      final completer = _pendingRequests.remove(requestId);
      if (completer == null) {
        return;
      }
      if ((payload['ok'] as bool?) ?? false) {
        completer.complete(payload);
      } else {
        completer.completeError(
          StateError(payload['error'] as String? ?? 'Worker request failed.'),
        );
      }
    });

    _workerIsolate = await Isolate.spawn(
      _liteRtWorkerMain,
      receivePort.sendPort,
      debugName: 'sentinel_litert_detector',
    );
    _workerSendPort = await workerReady.future;

    final modelData = await rootBundle.load(modelAssetPath);
    late final String labelMap;
    late final String labelMapName;
    try {
      labelMap = await rootBundle.loadString(labelMapAssetPath);
      labelMapName = labelMapAssetPath;
    } catch (_) {
      labelMap = _defaultCocoLabelMap.join('\n');
      labelMapName = 'built-in-coco';
    }
    final response = await _sendWorkerRequest('initialize', <String, Object?>{
      'modelBytes': TransferableTypedData.fromList(<TypedData>[
        modelData.buffer.asUint8List(),
      ]),
      'labelMap': labelMap,
      'labelMapName': labelMapName,
      'scoreThreshold': scoreThreshold,
      'maxResults': maxResults,
      'requestedInputSize': _requestedInputSize,
      'threadCount': _threadCount,
      'acceleration': _acceleration.name,
    });

    _diagnostics = _copyDiagnosticsFromWorker(response);
  }

  Future<void> _shutdownWorker() async {
    final isolate = _workerIsolate;
    final subscription = _workerSubscription;
    final receivePort = _workerReceivePort;
    _workerIsolate = null;
    _workerSubscription = null;
    _workerReceivePort = null;
    _workerSendPort = null;

    for (final completer in _pendingRequests.values) {
      completer.completeError(
        StateError('LiteRT detector worker was restarted.'),
      );
    }
    _pendingRequests.clear();

    await subscription?.cancel();
    receivePort?.close();
    isolate?.kill(priority: Isolate.immediate);
  }

  Future<Map<String, Object?>> _sendWorkerRequest(
    String operation,
    Map<String, Object?> payload,
  ) async {
    final sendPort = _workerSendPort;
    if (sendPort == null) {
      throw StateError('LiteRT detector worker is not initialized.');
    }

    final requestId = _nextRequestId++;
    final completer = Completer<Map<String, Object?>>();
    _pendingRequests[requestId] = completer;
    sendPort.send(<String, Object?>{
      'id': requestId,
      'op': operation,
      ...payload,
    });
    return completer.future;
  }

  DetectorDiagnostics _copyDiagnosticsFromWorker(
    Map<String, Object?> response,
  ) {
    return _diagnostics.copyWith(
      backendName: response['backendName'] as String? ?? backendLabel,
      modelLoaded: (response['modelLoaded'] as bool?) ?? true,
      delegateName: response['delegateName'] as String? ?? _acceleration.label,
      threadCount: (response['threadCount'] as int?) ?? _threadCount,
      requestedInputSize:
          (response['requestedInputSize'] as int?) ?? _requestedInputSize,
      framesReceived:
          (response['framesReceived'] as int?) ?? _diagnostics.framesReceived,
      framesInferred:
          (response['framesInferred'] as int?) ?? _diagnostics.framesInferred,
      frameWidth: (response['frameWidth'] as int?) ?? _diagnostics.frameWidth,
      frameHeight:
          (response['frameHeight'] as int?) ?? _diagnostics.frameHeight,
      inputShape: _toIntList(response['inputShape']),
      outputShapes: _toShapeList(response['outputShapes']),
      inputTensorType:
          response['inputTensorType'] as String? ??
          _diagnostics.inputTensorType,
      outputTensorTypes: _toStringList(response['outputTensorTypes']),
      labelMapLoaded:
          (response['labelMapLoaded'] as bool?) ?? _diagnostics.labelMapLoaded,
      labelMapName:
          response['labelMapName'] as String? ?? _diagnostics.labelMapName,
      labelCount: (response['labelCount'] as int?) ?? _diagnostics.labelCount,
      rawClassIds: _toIntList(response['rawClassIds']),
      mappedLabels: _toStringList(response['mappedLabels']),
      unknownLabelCount:
          (response['unknownLabelCount'] as int?) ??
          _diagnostics.unknownLabelCount,
      missingClassIds: _toIntList(response['missingClassIds']),
      preprocessSummary:
          response['preprocessSummary'] as String? ??
          _diagnostics.preprocessSummary,
      parserMode: response['parserMode'] as String? ?? _diagnostics.parserMode,
      rawCandidateCount:
          (response['rawCandidateCount'] as int?) ??
          _diagnostics.rawCandidateCount,
      filteredCandidateCount:
          (response['filteredCandidateCount'] as int?) ??
          _diagnostics.filteredCandidateCount,
      sampleOutputValues: _toDoubleList(response['sampleOutputValues']),
      sourceAcquisitionMs:
          (response['sourceAcquisitionMs'] as num?)?.toDouble() ??
          _diagnostics.sourceAcquisitionMs,
      colorConversionMs:
          (response['colorConversionMs'] as num?)?.toDouble() ??
          _diagnostics.colorConversionMs,
      rotationMs:
          (response['rotationMs'] as num?)?.toDouble() ??
          _diagnostics.rotationMs,
      resizeMs:
          (response['resizeMs'] as num?)?.toDouble() ?? _diagnostics.resizeMs,
      normalizationMs:
          (response['normalizationMs'] as num?)?.toDouble() ??
          _diagnostics.normalizationMs,
      tensorCopyMs:
          (response['tensorCopyMs'] as num?)?.toDouble() ??
          _diagnostics.tensorCopyMs,
      inferenceMs:
          (response['inferenceMs'] as num?)?.toDouble() ??
          _diagnostics.inferenceMs,
      outputParsingMs:
          (response['outputParsingMs'] as num?)?.toDouble() ??
          _diagnostics.outputParsingMs,
      usingIsolateWorker: true,
      lastInferenceError: response['lastInferenceError'] as String?,
      clearLastInferenceError: response['lastInferenceError'] == null,
    );
  }

  List<DetectionResult> _deserializeDetections(
    List<dynamic> rawDetections,
    DateTime timestamp,
  ) {
    return rawDetections
        .map((dynamic item) {
          final map = Map<String, Object?>.from(item as Map);
          return DetectionResult(
            id: map['id'] as String? ?? 'det',
            classId: (map['classId'] as num?)?.toInt() ?? -1,
            classLabel: map['classLabel'] as String? ?? 'unknown',
            sourceModel:
                map['sourceModel'] as String? ?? 'LiteRT / TFLite Detector',
            confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
            boundingBox: BoundingBox(
              left: (map['left'] as num?)?.toDouble() ?? 0,
              top: (map['top'] as num?)?.toDouble() ?? 0,
              width: (map['width'] as num?)?.toDouble() ?? 0,
              height: (map['height'] as num?)?.toDouble() ?? 0,
            ),
            timestamp: timestamp,
          );
        })
        .toList(growable: false);
  }

  List<int> _toIntList(Object? value) {
    if (value is! List) {
      return const <int>[];
    }
    return value
        .map((dynamic item) => (item as num?)?.toInt() ?? 0)
        .toList(growable: false);
  }

  List<List<int>> _toShapeList(Object? value) {
    if (value is! List) {
      return const <List<int>>[];
    }
    return value
        .map((dynamic item) => _toIntList(item))
        .toList(growable: false);
  }

  List<double> _toDoubleList(Object? value) {
    if (value is! List) {
      return const <double>[];
    }
    return value
        .map((dynamic item) => (item as num?)?.toDouble() ?? 0)
        .toList(growable: false);
  }

  List<String> _toStringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((dynamic item) => item?.toString() ?? '')
        .toList(growable: false);
  }
}

const List<String> _defaultCocoLabelMap = <String>[
  'person',
  'bicycle',
  'car',
  'motorcycle',
  'airplane',
  'bus',
  'train',
  'truck',
  'boat',
  'traffic light',
  'fire hydrant',
  '???',
  'stop sign',
  'parking meter',
  'bench',
  'bird',
  'cat',
  'dog',
  'horse',
  'sheep',
  'cow',
  'elephant',
  'bear',
  'zebra',
  'giraffe',
  '???',
  'backpack',
  'umbrella',
  '???',
  '???',
  'handbag',
  'tie',
  'suitcase',
  'frisbee',
  'skis',
  'snowboard',
  'sports ball',
  'kite',
  'baseball bat',
  'baseball glove',
  'skateboard',
  'surfboard',
  'tennis racket',
  'bottle',
  '???',
  'wine glass',
  'cup',
  'fork',
  'knife',
  'spoon',
  'bowl',
  'banana',
  'apple',
  'sandwich',
  'orange',
  'broccoli',
  'carrot',
  'hot dog',
  'pizza',
  'donut',
  'cake',
  'chair',
  'couch',
  'potted plant',
  'bed',
  '???',
  'dining table',
  '???',
  '???',
  'toilet',
  '???',
  'tv',
  'laptop',
  'mouse',
  'remote',
  'keyboard',
  'cell phone',
  'microwave',
  'oven',
  'toaster',
  'sink',
  'refrigerator',
  '???',
  'book',
  'clock',
  'vase',
  'scissors',
  'teddy bear',
  'hair drier',
  'toothbrush',
];

void _liteRtWorkerMain(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  final worker = _LiteRtWorkerState();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((dynamic message) async {
    if (message is! Map) {
      return;
    }

    final payload = Map<String, Object?>.from(message);
    final requestId = payload['id'] as int? ?? 0;
    try {
      final operation = payload['op'] as String? ?? '';
      late final Map<String, Object?> response;
      switch (operation) {
        case 'initialize':
          response = await worker.initialize(payload);
          break;
        case 'detect':
          response = await worker.detect(payload);
          break;
        case 'test':
          response = await worker.runTest(payload);
          break;
        default:
          throw StateError('Unsupported detector worker operation: $operation');
      }
      mainSendPort.send(<String, Object?>{
        'id': requestId,
        'ok': true,
        ...response,
      });
    } catch (error) {
      mainSendPort.send(<String, Object?>{
        'id': requestId,
        'ok': false,
        'error': error.toString(),
      });
    }
  });
}

class _LiteRtWorkerState {
  litert.Interpreter? _interpreter;
  litert.Delegate? _delegate;
  List<String> _labels = const <String>[];
  String _labelMapName = 'unbound';
  List<int> _lastRawClassIds = const <int>[];
  List<String> _lastMappedLabels = const <String>[];
  List<int> _lastMissingClassIds = const <int>[];
  int _lastUnknownLabelCount = 0;
  List<_TensorInfo> _outputTensors = const <_TensorInfo>[];
  _OutputLayout? _outputLayout;
  List<List<double>> _anchors = const <List<double>>[];
  int _inputWidth = 0;
  int _inputHeight = 0;
  int _inputChannels = 0;
  litert.TensorType _inputTensorType = litert.TensorType.noType;
  double _inputScale = 1.0;
  int _inputZeroPoint = 0;
  Float32List? _floatBuffer;
  Int8List? _int8Buffer;
  Uint8List? _uint8Buffer;
  Uint8List? _inputBytes;
  int _requestedInputSize = 320;
  int _threadCount = 2;
  int _maxResults = 16;
  InferenceAcceleration _acceleration = InferenceAcceleration.auto;
  int _framesReceived = 0;
  int _framesInferred = 0;
  String _delegateName = 'Unknown';

  Future<Map<String, Object?>> initialize(Map<String, Object?> payload) async {
    _disposeInterpreter();
    final modelBytes = (payload['modelBytes'] as TransferableTypedData)
        .materialize()
        .asUint8List();
    _labels = _parseLabelMap(payload['labelMap'] as String? ?? '');
    _labelMapName = payload['labelMapName'] as String? ?? 'unbound';
    _lastRawClassIds = const <int>[];
    _lastMappedLabels = const <String>[];
    _lastMissingClassIds = const <int>[];
    _lastUnknownLabelCount = 0;
    _requestedInputSize = (payload['requestedInputSize'] as int?) ?? 320;
    _threadCount = ((payload['threadCount'] as int?) ?? 2).clamp(1, 8);
    _maxResults = (payload['maxResults'] as int?) ?? 16;
    _acceleration = InferenceAcceleration.values.firstWhere(
      (candidate) => candidate.name == payload['acceleration'],
      orElse: () => InferenceAcceleration.auto,
    );
    final performanceConfig = _performanceConfigFor(
      _acceleration,
      _threadCount,
    );
    final (options, delegate) = litert.InterpreterFactory.create(
      performanceConfig,
    );
    final interpreter = litert.Interpreter.fromBuffer(
      modelBytes,
      options: options,
    );
    _delegate = delegate;
    _delegateName = _delegateLabelFor(_acceleration, delegate);

    final inputTensor = interpreter.getInputTensor(0);
    final nativeShape = inputTensor.shape;
    if (nativeShape.length != 4 || nativeShape[0] != 1 || nativeShape[3] != 3) {
      throw StateError(
        'Unsupported model input shape $nativeShape. Expected [1,H,W,3].',
      );
    }

    if (_requestedInputSize > 0 &&
        (_requestedInputSize != nativeShape[1] ||
            _requestedInputSize != nativeShape[2])) {
      try {
        interpreter.resizeInputTensor(0, <int>[
          1,
          _requestedInputSize,
          _requestedInputSize,
          3,
        ]);
        interpreter.allocateTensors();
      } catch (_) {
        // Fixed-shape models fall back to their native input size.
      }
    }

    final configuredInput = interpreter.getInputTensor(0);
    final configuredShape = configuredInput.shape;
    _inputHeight = configuredShape[1];
    _inputWidth = configuredShape[2];
    _inputChannels = configuredShape[3];
    _inputTensorType = configuredInput.type;
    _inputScale = configuredInput.params.scale;
    _inputZeroPoint = configuredInput.params.zeroPoint;
    _outputTensors = interpreter
        .getOutputTensors()
        .asMap()
        .entries
        .map((entry) {
          final tensor = entry.value;
          return _TensorInfo(
            index: entry.key,
            shape: tensor.shape,
            type: tensor.type,
            scale: tensor.params.scale,
            zeroPoint: tensor.params.zeroPoint,
          );
        })
        .toList(growable: false);
    _outputLayout = _discoverOutputLayout(_outputTensors);
    _anchors = _outputLayout?.mode == _OutputParserMode.efficientDetAnchors
        ? _generateEfficientDetAnchors(imageSize: _inputWidth)
        : const <List<double>>[];
    _allocateInputBuffers();
    _interpreter = interpreter;
    _framesReceived = 0;
    _framesInferred = 0;

    return _baseResponse(
      preprocessSummary:
          'Worker ready at ${_inputWidth}x$_inputHeight using $_delegateName',
      sampleOutputValues: const <double>[],
      rawCandidateCount: 0,
      filteredCandidateCount: 0,
      sourceAcquisitionMs: 0,
      colorConversionMs: 0,
      rotationMs: 0,
      resizeMs: 0,
      normalizationMs: 0,
      tensorCopyMs: 0,
      inferenceMs: 0,
      outputParsingMs: 0,
      frameWidth: 0,
      frameHeight: 0,
      lastInferenceError: null,
    );
  }

  Future<Map<String, Object?>> detect(Map<String, Object?> payload) async {
    final interpreter = _interpreter;
    final outputLayout = _outputLayout;
    if (interpreter == null || outputLayout == null) {
      throw StateError('LiteRT worker is not initialized.');
    }

    final frame = _deserializeWorkerFrame(
      Map<String, Object?>.from(payload['frame'] as Map),
    );
    _framesReceived += 1;

    final preprocess = _preprocessFrame(frame);
    final tensorCopyWatch = Stopwatch()..start();
    interpreter.getInputTensor(0).data = _inputBytes!;
    tensorCopyWatch.stop();

    final inferenceWatch = Stopwatch()..start();
    interpreter.invoke();
    inferenceWatch.stop();
    _framesInferred += 1;

    final parseWatch = Stopwatch()..start();
    final rawDetections = _parseOutputs(
      interpreter: interpreter,
      outputLayout: outputLayout,
      padding: preprocess.padding,
      frame: frame,
      scoreThreshold: preprocess.scoreThreshold,
    );
    final filtered = _applyNms(rawDetections, frame);
    final sampleValues = _sampleOutputValues(interpreter);
    parseWatch.stop();

    final detections = filtered
        .map((detection) {
          return <String, Object?>{
            'id': detection.id,
            'classId': detection.classId,
            'classLabel': detection.classLabel,
            'sourceModel': detection.sourceModel,
            'confidence': detection.confidence,
            'left': detection.boundingBox.left,
            'top': detection.boundingBox.top,
            'width': detection.boundingBox.width,
            'height': detection.boundingBox.height,
          };
        })
        .toList(growable: false);

    return _baseResponse(
      preprocessSummary: preprocess.summary,
      sampleOutputValues: sampleValues,
      rawCandidateCount: rawDetections.length,
      filteredCandidateCount: filtered.length,
      sourceAcquisitionMs: frame.sourceAcquisitionMs,
      colorConversionMs: preprocess.colorConversionMs,
      rotationMs: preprocess.rotationMs,
      resizeMs: preprocess.resizeMs,
      normalizationMs: preprocess.normalizationMs,
      tensorCopyMs: tensorCopyWatch.elapsedMicroseconds / 1000,
      inferenceMs: inferenceWatch.elapsedMicroseconds / 1000,
      outputParsingMs: parseWatch.elapsedMicroseconds / 1000,
      frameWidth: frame.sourceWidth.round(),
      frameHeight: frame.sourceHeight.round(),
      lastInferenceError: null,
      detections: detections,
    );
  }

  Future<Map<String, Object?>> runTest(Map<String, Object?> payload) async {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('LiteRT worker is not initialized.');
    }

    if (payload['frame'] case final rawFrame?) {
      final frame = _deserializeWorkerFrame(
        Map<String, Object?>.from(rawFrame as Map),
      );
      final preprocess = _preprocessFrame(frame);
      final tensorCopyWatch = Stopwatch()..start();
      interpreter.getInputTensor(0).data = _inputBytes!;
      tensorCopyWatch.stop();
      final inferenceWatch = Stopwatch()..start();
      interpreter.invoke();
      inferenceWatch.stop();
      final sampleValues = _sampleOutputValues(interpreter);
      return _baseResponse(
        preprocessSummary: preprocess.summary,
        sampleOutputValues: sampleValues,
        rawCandidateCount: 0,
        filteredCandidateCount: 0,
        sourceAcquisitionMs: frame.sourceAcquisitionMs,
        colorConversionMs: preprocess.colorConversionMs,
        rotationMs: preprocess.rotationMs,
        resizeMs: preprocess.resizeMs,
        normalizationMs: preprocess.normalizationMs,
        tensorCopyMs: tensorCopyWatch.elapsedMicroseconds / 1000,
        inferenceMs: inferenceWatch.elapsedMicroseconds / 1000,
        outputParsingMs: 0,
        frameWidth: frame.sourceWidth.round(),
        frameHeight: frame.sourceHeight.round(),
        lastInferenceError: null,
        success: true,
        message: 'Frame test inference completed.',
        sampleValues: sampleValues,
      );
    }

    final normalizationWatch = Stopwatch()..start();
    _fillSyntheticInput();
    normalizationWatch.stop();
    final tensorCopyWatch = Stopwatch()..start();
    interpreter.getInputTensor(0).data = _inputBytes!;
    tensorCopyWatch.stop();
    final inferenceWatch = Stopwatch()..start();
    interpreter.invoke();
    inferenceWatch.stop();
    final sampleValues = _sampleOutputValues(interpreter);
    return _baseResponse(
      preprocessSummary: 'Synthetic test tensor',
      sampleOutputValues: sampleValues,
      rawCandidateCount: 0,
      filteredCandidateCount: 0,
      sourceAcquisitionMs: 0,
      colorConversionMs: 0,
      rotationMs: 0,
      resizeMs: 0,
      normalizationMs: normalizationWatch.elapsedMicroseconds / 1000,
      tensorCopyMs: tensorCopyWatch.elapsedMicroseconds / 1000,
      inferenceMs: inferenceWatch.elapsedMicroseconds / 1000,
      outputParsingMs: 0,
      frameWidth: 0,
      frameHeight: 0,
      lastInferenceError: null,
      success: true,
      message: 'Synthetic test inference completed.',
      sampleValues: sampleValues,
    );
  }

  Map<String, Object?> _baseResponse({
    required String preprocessSummary,
    required List<double> sampleOutputValues,
    required int rawCandidateCount,
    required int filteredCandidateCount,
    required double sourceAcquisitionMs,
    required double colorConversionMs,
    required double rotationMs,
    required double resizeMs,
    required double normalizationMs,
    required double tensorCopyMs,
    required double inferenceMs,
    required double outputParsingMs,
    required int frameWidth,
    required int frameHeight,
    required String? lastInferenceError,
    List<Map<String, Object?>> detections = const <Map<String, Object?>>[],
    bool success = true,
    String message = 'LiteRT worker ready.',
    List<double>? sampleValues,
  }) {
    return <String, Object?>{
      'backendName': 'LiteRT / TFLite Detector',
      'modelLoaded': _interpreter != null,
      'delegateName': _delegateName,
      'threadCount': _threadCount,
      'requestedInputSize': _requestedInputSize,
      'framesReceived': _framesReceived,
      'framesInferred': _framesInferred,
      'frameWidth': frameWidth,
      'frameHeight': frameHeight,
      'inputShape': <int>[1, _inputHeight, _inputWidth, _inputChannels],
      'outputShapes': _outputTensors
          .map((tensor) => tensor.shape)
          .toList(growable: false),
      'inputTensorType': _inputTensorType.name,
      'outputTensorTypes': _outputTensors
          .map((tensor) => tensor.type.name)
          .toList(growable: false),
      'labelMapLoaded': _labels.isNotEmpty,
      'labelMapName': _labelMapName,
      'labelCount': _labels.length,
      'rawClassIds': _lastRawClassIds,
      'mappedLabels': _lastMappedLabels,
      'unknownLabelCount': _lastUnknownLabelCount,
      'missingClassIds': _lastMissingClassIds,
      'preprocessSummary': preprocessSummary,
      'parserMode': _outputLayout?.label ?? 'unbound',
      'rawCandidateCount': rawCandidateCount,
      'filteredCandidateCount': filteredCandidateCount,
      'sampleOutputValues': sampleOutputValues,
      'sourceAcquisitionMs': sourceAcquisitionMs,
      'colorConversionMs': colorConversionMs,
      'rotationMs': rotationMs,
      'resizeMs': resizeMs,
      'normalizationMs': normalizationMs,
      'tensorCopyMs': tensorCopyMs,
      'inferenceMs': inferenceMs,
      'outputParsingMs': outputParsingMs,
      'lastInferenceError': lastInferenceError,
      'detections': detections,
      'success': success,
      'message': message,
      'sampleValues': sampleValues ?? sampleOutputValues,
    };
  }

  _PreprocessResult _preprocessFrame(_WorkerFrame frame) {
    final effectiveThreshold = frame.debugMode
        ? math.min(frame.scoreThreshold, 0.05)
        : frame.scoreThreshold;
    if (frame.snapshot != null) {
      final result = _preprocessSnapshot(frame);
      return result.copyWith(scoreThreshold: effectiveThreshold);
    }
    if (frame.encodedImageBytes != null) {
      final result = _preprocessEncodedImage(frame);
      return result.copyWith(scoreThreshold: effectiveThreshold);
    }
    throw StateError('Frame payload is missing image data for inference.');
  }

  _PreprocessResult _preprocessSnapshot(_WorkerFrame frame) {
    final snapshot = frame.snapshot!;
    final orientedWidth = frame.rotation.swapsDimensions
        ? snapshot.height
        : snapshot.width;
    final orientedHeight = frame.rotation.swapsDimensions
        ? snapshot.width
        : snapshot.height;
    final letterbox = litert.computeLetterboxParams(
      srcWidth: orientedWidth,
      srcHeight: orientedHeight,
      targetWidth: _inputWidth,
      targetHeight: _inputHeight,
    );

    _fillPadding();
    final conversionWatch = Stopwatch()..start();
    switch (snapshot.pixelFormat) {
      case FramePixelFormat.yuv420:
        _fillFromYuvSnapshot(snapshot, frame.rotation, letterbox);
        break;
      case FramePixelFormat.bgra8888:
        _fillFromBgraSnapshot(snapshot, frame.rotation, letterbox);
        break;
      case FramePixelFormat.unsupported:
        throw StateError(
          'Unsupported snapshot pixel format for LiteRT worker.',
        );
    }
    conversionWatch.stop();

    final summary =
        '${snapshot.pixelFormat.name} direct sample ${snapshot.width}x${snapshot.height}'
        ' -> ${_inputWidth}x$_inputHeight'
        ' using inline rotation/resize/normalization';
    return _PreprocessResult(
      padding: <double>[
        letterbox.padTop / _inputHeight,
        letterbox.padBottom / _inputHeight,
        letterbox.padLeft / _inputWidth,
        letterbox.padRight / _inputWidth,
      ],
      summary: summary,
      colorConversionMs: conversionWatch.elapsedMicroseconds / 1000,
      rotationMs: 0,
      resizeMs: 0,
      normalizationMs: 0,
      scoreThreshold: frame.scoreThreshold,
    );
  }

  _PreprocessResult _preprocessEncodedImage(_WorkerFrame frame) {
    final decodeWatch = Stopwatch()..start();
    var decoded = img.decodeImage(frame.encodedImageBytes!);
    decodeWatch.stop();
    if (decoded == null) {
      throw StateError('Unable to decode encoded frame bytes for inference.');
    }

    final rotationWatch = Stopwatch();
    if (frame.rotation != FrameRotation.rotation0) {
      rotationWatch.start();
      decoded = switch (frame.rotation) {
        FrameRotation.rotation90 => img.copyRotate(decoded, angle: 90),
        FrameRotation.rotation180 => img.copyRotate(decoded, angle: 180),
        FrameRotation.rotation270 => img.copyRotate(decoded, angle: -90),
        FrameRotation.rotation0 => decoded,
      };
      rotationWatch.stop();
    }

    final letterbox = litert.computeLetterboxParams(
      srcWidth: decoded.width,
      srcHeight: decoded.height,
      targetWidth: _inputWidth,
      targetHeight: _inputHeight,
    );
    final resizeWatch = Stopwatch()..start();
    final resized = img.copyResize(
      decoded,
      width: letterbox.newWidth,
      height: letterbox.newHeight,
      interpolation: img.Interpolation.linear,
    );
    resizeWatch.stop();

    final normalizationWatch = Stopwatch()..start();
    final rgbBytes = resized.getBytes(order: img.ChannelOrder.rgb);
    _fillPadding();
    for (var y = 0; y < letterbox.newHeight; y += 1) {
      final destY = y + letterbox.padTop;
      final rowOffset = destY * _inputWidth * _inputChannels;
      final sourceRowOffset = y * letterbox.newWidth * _inputChannels;
      for (var x = 0; x < letterbox.newWidth; x += 1) {
        final destOffset =
            rowOffset + ((x + letterbox.padLeft) * _inputChannels);
        final sourceOffset = sourceRowOffset + (x * _inputChannels);
        _writeRgbPixel(
          destOffset,
          rgbBytes[sourceOffset],
          rgbBytes[sourceOffset + 1],
          rgbBytes[sourceOffset + 2],
        );
      }
    }
    normalizationWatch.stop();

    return _PreprocessResult(
      padding: <double>[
        letterbox.padTop / _inputHeight,
        letterbox.padBottom / _inputHeight,
        letterbox.padLeft / _inputWidth,
        letterbox.padRight / _inputWidth,
      ],
      summary:
          'decode ${decoded.width}x${decoded.height} -> ${_inputWidth}x$_inputHeight,'
          ' decode ${decodeWatch.elapsedMicroseconds / 1000} ms',
      colorConversionMs: 0,
      rotationMs: rotationWatch.elapsedMicroseconds / 1000,
      resizeMs: resizeWatch.elapsedMicroseconds / 1000,
      normalizationMs: normalizationWatch.elapsedMicroseconds / 1000,
      scoreThreshold: frame.scoreThreshold,
    );
  }

  void _fillPadding() {
    if (_floatBuffer case final buffer?) {
      buffer.fillRange(0, buffer.length, -1.0);
      return;
    }
    if (_int8Buffer case final buffer?) {
      buffer.fillRange(0, buffer.length, _inputZeroPoint.clamp(-128, 127));
      return;
    }
    _uint8Buffer!.fillRange(
      0,
      _uint8Buffer!.length,
      _inputZeroPoint.clamp(0, 255),
    );
  }

  void _fillSyntheticInput() {
    _fillPadding();
    for (var y = 0; y < _inputHeight; y += 1) {
      for (var x = 0; x < _inputWidth; x += 1) {
        final offset =
            (y * _inputWidth * _inputChannels) + (x * _inputChannels);
        final signal = ((x + y) % 255).clamp(0, 255);
        _writeRgbPixel(offset, signal, 127, 255 - signal);
      }
    }
  }

  void _fillFromBgraSnapshot(
    _WorkerSnapshot snapshot,
    FrameRotation rotation,
    litert.LetterboxParams letterbox,
  ) {
    final plane = snapshot.planes.first;
    final rawWidth = snapshot.width;
    final rawHeight = snapshot.height;
    final orientedWidth = rotation.swapsDimensions ? rawHeight : rawWidth;
    final orientedHeight = rotation.swapsDimensions ? rawWidth : rawHeight;
    final bytesPerPixel = plane.bytesPerPixel ?? 4;

    for (var y = 0; y < letterbox.newHeight; y += 1) {
      final destY = y + letterbox.padTop;
      final sourceY = (((y + 0.5) * orientedHeight) / letterbox.newHeight)
          .clamp(0.0, orientedHeight - 1.0);
      final rowOffset = destY * _inputWidth * _inputChannels;
      for (var x = 0; x < letterbox.newWidth; x += 1) {
        final sourceX = (((x + 0.5) * orientedWidth) / letterbox.newWidth)
            .clamp(0.0, orientedWidth - 1.0);
        final rawPoint = _mapOrientedToRaw(
          sourceX.round(),
          sourceY.round(),
          rawWidth,
          rawHeight,
          rotation,
        );
        final index =
            (rawPoint.$2 * plane.bytesPerRow) + (rawPoint.$1 * bytesPerPixel);
        final destOffset =
            rowOffset + ((x + letterbox.padLeft) * _inputChannels);
        _writeRgbPixel(
          destOffset,
          plane.bytes[index + 2],
          plane.bytes[index + 1],
          plane.bytes[index],
        );
      }
    }
  }

  void _fillFromYuvSnapshot(
    _WorkerSnapshot snapshot,
    FrameRotation rotation,
    litert.LetterboxParams letterbox,
  ) {
    if (snapshot.planes.length < 3) {
      throw StateError('YUV420 snapshot must provide 3 planes.');
    }
    final yPlane = snapshot.planes[0];
    final uPlane = snapshot.planes[1];
    final vPlane = snapshot.planes[2];
    final rawWidth = snapshot.width;
    final rawHeight = snapshot.height;
    final orientedWidth = rotation.swapsDimensions ? rawHeight : rawWidth;
    final orientedHeight = rotation.swapsDimensions ? rawWidth : rawHeight;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;

    for (var y = 0; y < letterbox.newHeight; y += 1) {
      final destY = y + letterbox.padTop;
      final sourceY = (((y + 0.5) * orientedHeight) / letterbox.newHeight)
          .clamp(0.0, orientedHeight - 1.0);
      final rowOffset = destY * _inputWidth * _inputChannels;
      for (var x = 0; x < letterbox.newWidth; x += 1) {
        final sourceX = (((x + 0.5) * orientedWidth) / letterbox.newWidth)
            .clamp(0.0, orientedWidth - 1.0);
        final rawPoint = _mapOrientedToRaw(
          sourceX.round(),
          sourceY.round(),
          rawWidth,
          rawHeight,
          rotation,
        );
        final rawX = rawPoint.$1;
        final rawY = rawPoint.$2;
        final uvRow = rawY ~/ 2;
        final uvCol = rawX ~/ 2;
        final yIndex = (rawY * yPlane.bytesPerRow) + rawX;
        final uIndex = (uvRow * uPlane.bytesPerRow) + (uvCol * uPixelStride);
        final vIndex = (uvRow * vPlane.bytesPerRow) + (uvCol * vPixelStride);
        final yp = yPlane.bytes[yIndex].toDouble();
        final up = uPlane.bytes[uIndex].toDouble();
        final vp = vPlane.bytes[vIndex].toDouble();
        final r = (yp + (1.403 * (vp - 128))).round().clamp(0, 255);
        final g = (yp - (0.344 * (up - 128)) - (0.714 * (vp - 128)))
            .round()
            .clamp(0, 255);
        final b = (yp + (1.770 * (up - 128))).round().clamp(0, 255);
        final destOffset =
            rowOffset + ((x + letterbox.padLeft) * _inputChannels);
        _writeRgbPixel(destOffset, r, g, b);
      }
    }
  }

  (int, int) _mapOrientedToRaw(
    int orientedX,
    int orientedY,
    int rawWidth,
    int rawHeight,
    FrameRotation rotation,
  ) {
    return switch (rotation) {
      FrameRotation.rotation90 => (
        orientedY.clamp(0, rawWidth - 1),
        (rawHeight - 1 - orientedX).clamp(0, rawHeight - 1),
      ),
      FrameRotation.rotation180 => (
        (rawWidth - 1 - orientedX).clamp(0, rawWidth - 1),
        (rawHeight - 1 - orientedY).clamp(0, rawHeight - 1),
      ),
      FrameRotation.rotation270 => (
        (rawWidth - 1 - orientedY).clamp(0, rawWidth - 1),
        orientedX.clamp(0, rawHeight - 1),
      ),
      FrameRotation.rotation0 => (
        orientedX.clamp(0, rawWidth - 1),
        orientedY.clamp(0, rawHeight - 1),
      ),
    };
  }

  void _writeRgbPixel(int offset, int r, int g, int b) {
    if (_floatBuffer case final buffer?) {
      buffer[offset] = (r - 127.5) / 127.5;
      buffer[offset + 1] = (g - 127.5) / 127.5;
      buffer[offset + 2] = (b - 127.5) / 127.5;
      return;
    }
    if (_int8Buffer case final buffer?) {
      buffer[offset] = _quantizeInput(r);
      buffer[offset + 1] = _quantizeInput(g);
      buffer[offset + 2] = _quantizeInput(b);
      return;
    }
    _uint8Buffer![offset] = r.clamp(0, 255);
    _uint8Buffer![offset + 1] = g.clamp(0, 255);
    _uint8Buffer![offset + 2] = b.clamp(0, 255);
  }

  int _quantizeInput(int channel) {
    if (_inputTensorType == litert.TensorType.uint8) {
      return channel.clamp(0, 255);
    }
    if (_inputScale == 0) {
      return (channel + _inputZeroPoint).clamp(-128, 127);
    }
    return (((channel.toDouble() / _inputScale) + _inputZeroPoint).round())
        .clamp(-128, 127);
  }

  void _allocateInputBuffers() {
    final totalValues = _inputWidth * _inputHeight * _inputChannels;
    _floatBuffer = null;
    _int8Buffer = null;
    _uint8Buffer = null;

    switch (_inputTensorType) {
      case litert.TensorType.float32:
        final floatBuffer = Float32List(totalValues);
        _floatBuffer = floatBuffer;
        _inputBytes = floatBuffer.buffer.asUint8List();
        break;
      case litert.TensorType.int8:
        final int8Buffer = Int8List(totalValues);
        _int8Buffer = int8Buffer;
        _inputBytes = int8Buffer.buffer.asUint8List();
        break;
      case litert.TensorType.uint8:
        final uint8Buffer = Uint8List(totalValues);
        _uint8Buffer = uint8Buffer;
        _inputBytes = uint8Buffer;
        break;
      default:
        throw StateError(
          'Unsupported input tensor type ${_inputTensorType.name}.',
        );
    }
  }

  List<_ParsedDetection> _parseOutputs({
    required litert.Interpreter interpreter,
    required _OutputLayout outputLayout,
    required List<double> padding,
    required _WorkerFrame frame,
    required double scoreThreshold,
  }) {
    final rawDetections = switch (outputLayout.mode) {
      _OutputParserMode.efficientDetAnchors => _parseEfficientDetAnchors(
        interpreter,
        outputLayout,
        scoreThreshold,
      ),
      _OutputParserMode.ssdSplit => _parseSsdSplit(
        interpreter,
        outputLayout,
        scoreThreshold,
      ),
      _OutputParserMode.yoloCombined => _parseCombinedCandidates(
        interpreter,
        outputLayout,
        true,
        scoreThreshold,
      ),
      _OutputParserMode.candidateRows => _parseCandidateRows(
        interpreter,
        outputLayout,
        scoreThreshold,
      ),
    };

    final unpadded = _removeLetterboxPadding(rawDetections, padding);
    final parsed = unpadded
        .asMap()
        .entries
        .map((entry) {
          final raw = entry.value;
          final classLabel = _classLabelFor(raw.classIndex);
          return _ParsedDetection(
            id: 'det-${frame.frameNumber}-${entry.key}',
            classId: raw.classIndex,
            classLabel: classLabel,
            sourceModel: 'LiteRT / TFLite Detector',
            confidence: raw.score,
            boundingBox: BoundingBox(
              left: raw.boundingBox.xmin * frame.sourceWidth,
              top: raw.boundingBox.ymin * frame.sourceHeight,
              width:
                  (raw.boundingBox.xmax - raw.boundingBox.xmin) *
                  frame.sourceWidth,
              height:
                  (raw.boundingBox.ymax - raw.boundingBox.ymin) *
                  frame.sourceHeight,
            ),
          );
        })
        .toList(growable: false);
    _lastRawClassIds =
        unpadded
            .map((detection) => detection.classIndex)
            .toSet()
            .toList(growable: false)
          ..sort();
    _lastMappedLabels =
        parsed
            .map((detection) => detection.classLabel)
            .toSet()
            .toList(growable: false)
          ..sort();
    _lastMissingClassIds = _lastRawClassIds
        .where((classId) => _isUnknownClassId(classId))
        .toList(growable: false);
    _lastUnknownLabelCount = parsed
        .where((detection) => detection.classLabel == 'unknown')
        .length;
    return parsed;
  }

  List<_RawDetection> _parseEfficientDetAnchors(
    litert.Interpreter interpreter,
    _OutputLayout layout,
    double scoreThreshold,
  ) {
    final boxInfo = _outputTensors[layout.primaryTensorIndex];
    final classInfo = _outputTensors[layout.secondaryTensorIndex!];
    final boxRaw = _dequantizedOutput(
      interpreter.getOutputTensor(boxInfo.index),
      boxInfo,
    );
    final classRaw = _dequantizedOutput(
      interpreter.getOutputTensor(classInfo.index),
      classInfo,
    );
    final detections = <_RawDetection>[];
    final classCount = classInfo.shape[2];

    for (var candidate = 0; candidate < layout.candidateCount; candidate += 1) {
      if (candidate >= _anchors.length) {
        break;
      }
      double bestClassScore = 0;
      var bestClassIndex = 0;
      final classOffset = candidate * classCount;
      for (var classIndex = 0; classIndex < classCount; classIndex += 1) {
        final score = _normalizeScore(classRaw[classOffset + classIndex]);
        if (score > bestClassScore) {
          bestClassScore = score;
          bestClassIndex = classIndex;
        }
      }

      if (bestClassScore < scoreThreshold) {
        continue;
      }

      final anchor = _anchors[candidate];
      final boxOffset = candidate * 4;
      final ty = boxRaw[boxOffset];
      final tx = boxRaw[boxOffset + 1];
      final th = boxRaw[boxOffset + 2];
      final tw = boxRaw[boxOffset + 3];
      final anchorY = anchor[1];
      final anchorX = anchor[0];
      final anchorH = anchor[3];
      final anchorW = anchor[2];
      final centerY = (ty * anchorH) + anchorY;
      final centerX = (tx * anchorW) + anchorX;
      final height = math.exp(th).toDouble() * anchorH;
      final width = math.exp(tw).toDouble() * anchorW;
      final rect = _RectF(
        (centerX - (width * 0.5)).clamp(0.0, 1.0).toDouble(),
        (centerY - (height * 0.5)).clamp(0.0, 1.0).toDouble(),
        (centerX + (width * 0.5)).clamp(0.0, 1.0).toDouble(),
        (centerY + (height * 0.5)).clamp(0.0, 1.0).toDouble(),
      );
      if (rect.xmax <= rect.xmin || rect.ymax <= rect.ymin) {
        continue;
      }
      detections.add(
        _RawDetection(
          boundingBox: rect,
          score: bestClassScore,
          classIndex: bestClassIndex,
        ),
      );
    }

    return detections;
  }

  List<_RawDetection> _parseSsdSplit(
    litert.Interpreter interpreter,
    _OutputLayout layout,
    double scoreThreshold,
  ) {
    final boxInfo = _outputTensors[layout.primaryTensorIndex];
    final classInfo = _outputTensors[layout.secondaryTensorIndex!];
    final scoreInfo = _outputTensors[layout.tertiaryTensorIndex!];
    final boxRaw = _dequantizedOutput(
      interpreter.getOutputTensor(boxInfo.index),
      boxInfo,
    );
    final classRaw = _dequantizedOutput(
      interpreter.getOutputTensor(classInfo.index),
      classInfo,
    );
    final scoreRaw = _dequantizedOutput(
      interpreter.getOutputTensor(scoreInfo.index),
      scoreInfo,
    );
    final detections = <_RawDetection>[];

    for (var candidate = 0; candidate < layout.candidateCount; candidate += 1) {
      final score = _normalizeScore(scoreRaw[candidate]);
      if (score < scoreThreshold) {
        continue;
      }
      final rect = _normalizedRect(
        boxRaw[(candidate * 4) + 1],
        boxRaw[candidate * 4],
        boxRaw[(candidate * 4) + 3],
        boxRaw[(candidate * 4) + 2],
      );
      if (rect == null) {
        continue;
      }
      detections.add(
        _RawDetection(
          boundingBox: rect,
          score: score,
          classIndex: classRaw[candidate].round(),
        ),
      );
    }

    return detections;
  }

  List<_RawDetection> _parseCombinedCandidates(
    litert.Interpreter interpreter,
    _OutputLayout layout,
    bool expectsCenterBoxes,
    double scoreThreshold,
  ) {
    final tensorInfo = _outputTensors[layout.primaryTensorIndex];
    final raw = _dequantizedOutput(
      interpreter.getOutputTensor(tensorInfo.index),
      tensorInfo,
    );
    final detections = <_RawDetection>[];
    final attributes = layout.attributeCount;
    final candidates = layout.candidateCount;

    for (var candidate = 0; candidate < candidates; candidate += 1) {
      final values = List<double>.generate(attributes, (attribute) {
        final index = layout.transposeCombined
            ? (attribute * candidates) + candidate
            : (candidate * attributes) + attribute;
        return raw[index];
      }, growable: false);
      final parsed = _parseCandidateVector(
        values,
        expectsCenterBoxes: expectsCenterBoxes,
        scoreThreshold: scoreThreshold,
      );
      if (parsed != null) {
        detections.add(parsed);
      }
    }

    return detections;
  }

  List<_RawDetection> _parseCandidateRows(
    litert.Interpreter interpreter,
    _OutputLayout layout,
    double scoreThreshold,
  ) {
    final tensorInfo = _outputTensors[layout.primaryTensorIndex];
    final raw = _dequantizedOutput(
      interpreter.getOutputTensor(tensorInfo.index),
      tensorInfo,
    );
    final detections = <_RawDetection>[];
    final rowWidth = layout.attributeCount;

    for (var rowIndex = 0; rowIndex < layout.candidateCount; rowIndex += 1) {
      final row = raw
          .skip(rowIndex * rowWidth)
          .take(rowWidth)
          .toList(growable: false);
      final parsed = _parseCandidateRow(row, scoreThreshold);
      if (parsed != null) {
        detections.add(parsed);
      }
    }

    return detections;
  }

  _RawDetection? _parseCandidateVector(
    List<double> values, {
    required bool expectsCenterBoxes,
    required double scoreThreshold,
  }) {
    if (values.length < 6) {
      return null;
    }

    final coords = values.take(4).toList(growable: false);
    var objectness = 1.0;
    var classOffset = 4;
    if (values.length > 6) {
      final candidateObjectness = _normalizeScore(values[4]);
      if (candidateObjectness > 0 && candidateObjectness <= 1.0) {
        objectness = candidateObjectness;
        classOffset = 5;
      }
    }

    double bestClassScore = 0;
    var bestClassIndex = 0;
    for (var index = classOffset; index < values.length; index += 1) {
      final score = _normalizeScore(values[index]);
      if (score > bestClassScore) {
        bestClassScore = score;
        bestClassIndex = index - classOffset;
      }
    }

    final confidence = (objectness * bestClassScore).clamp(0.0, 1.0).toDouble();
    if (confidence < scoreThreshold) {
      return null;
    }

    final rect = expectsCenterBoxes
        ? _centerBoxToRect(coords[0], coords[1], coords[2], coords[3])
        : _normalizedRect(coords[0], coords[1], coords[2], coords[3]);
    if (rect == null) {
      return null;
    }

    return _RawDetection(
      boundingBox: rect,
      score: confidence,
      classIndex: bestClassIndex,
    );
  }

  _RawDetection? _parseCandidateRow(List<double> row, double scoreThreshold) {
    if (row.length == 6) {
      if (_looksLikeScore(row[4])) {
        final rect = _normalizedRect(row[0], row[1], row[2], row[3]);
        if (rect == null || row[4] < scoreThreshold) {
          return null;
        }
        return _RawDetection(
          boundingBox: rect,
          score: row[4],
          classIndex: row[5].round(),
        );
      }
      if (_looksLikeScore(row[1])) {
        final rect = _normalizedRect(row[2], row[3], row[4], row[5]);
        if (rect == null || row[1] < scoreThreshold) {
          return null;
        }
        return _RawDetection(
          boundingBox: rect,
          score: row[1],
          classIndex: row[0].round(),
        );
      }
    }

    if (row.length >= 7 && _looksLikeScore(row[2])) {
      final rect = _normalizedRect(row[3], row[4], row[5], row[6]);
      if (rect == null || row[2] < scoreThreshold) {
        return null;
      }
      return _RawDetection(
        boundingBox: rect,
        score: row[2],
        classIndex: row[1].round(),
      );
    }

    return null;
  }

  List<_ParsedDetection> _applyNms(
    List<_ParsedDetection> detections,
    _WorkerFrame frame,
  ) {
    if (detections.isEmpty) {
      return const <_ParsedDetection>[];
    }

    final sorted = List<_ParsedDetection>.from(detections, growable: true)
      ..sort((left, right) => right.confidence.compareTo(left.confidence));
    final weighted = litert.weightedNms(
      sorted
          .map(
            (detection) => <double>[
              detection.boundingBox.left / frame.sourceWidth,
              detection.boundingBox.top / frame.sourceHeight,
              detection.boundingBox.right / frame.sourceWidth,
              detection.boundingBox.bottom / frame.sourceHeight,
            ],
          )
          .toList(growable: false),
      sorted.map((detection) => detection.confidence).toList(growable: false),
      iouThres: 0.45,
      maxDet: _maxResults,
    );
    return weighted
        .map((result) => sorted[result.index])
        .toList(growable: false);
  }

  List<_RawDetection> _removeLetterboxPadding(
    List<_RawDetection> detections,
    List<double> padding,
  ) {
    final padTop = padding[0];
    final padBottom = padding[1];
    final padLeft = padding[2];
    final padRight = padding[3];
    final scaleX = 1.0 - (padLeft + padRight);
    final scaleY = 1.0 - (padTop + padBottom);
    if (scaleX <= 0 || scaleY <= 0) {
      return detections;
    }

    final results = <_RawDetection>[];
    for (final detection in detections) {
      final rect = _RectF(
        ((detection.boundingBox.xmin - padLeft) / scaleX)
            .clamp(0.0, 1.0)
            .toDouble(),
        ((detection.boundingBox.ymin - padTop) / scaleY)
            .clamp(0.0, 1.0)
            .toDouble(),
        ((detection.boundingBox.xmax - padLeft) / scaleX)
            .clamp(0.0, 1.0)
            .toDouble(),
        ((detection.boundingBox.ymax - padTop) / scaleY)
            .clamp(0.0, 1.0)
            .toDouble(),
      );
      if (rect.xmax - rect.xmin <= 0.0001 || rect.ymax - rect.ymin <= 0.0001) {
        continue;
      }
      results.add(
        _RawDetection(
          boundingBox: rect,
          score: detection.score,
          classIndex: detection.classIndex,
        ),
      );
    }
    return results;
  }

  _OutputLayout _discoverOutputLayout(List<_TensorInfo> outputs) {
    if (outputs.length >= 4) {
      int? boxesIndex;
      int? classesIndex;
      int? scoresIndex;
      for (var index = 0; index < outputs.length; index += 1) {
        final shape = outputs[index].shape;
        if (shape.isEmpty) {
          continue;
        }
        final flattenedTail = shape.length == 2 ? shape[1] : shape.last;
        if (shape.length >= 2 && flattenedTail == 4 && boxesIndex == null) {
          boxesIndex = index;
        } else if (flattenedTail > 1 &&
            flattenedTail < 5 &&
            classesIndex == null) {
          classesIndex = index;
        } else if (flattenedTail == 1 || shape.length == 1) {
          scoresIndex ??= index;
        }
      }
      if (boxesIndex != null && classesIndex != null && scoresIndex != null) {
        return _OutputLayout(
          mode: _OutputParserMode.ssdSplit,
          label: 'ssd-split',
          primaryTensorIndex: boxesIndex,
          secondaryTensorIndex: classesIndex,
          tertiaryTensorIndex: scoresIndex,
          candidateCount: outputs[boxesIndex].shape[1],
          attributeCount: 4,
          transposeCombined: false,
        );
      }
    }

    if (outputs.length == 2) {
      int? boxesIndex;
      int? classesIndex;
      for (var index = 0; index < outputs.length; index += 1) {
        final shape = outputs[index].shape;
        if (shape.length == 3 && shape[2] == 4) {
          boxesIndex = index;
        } else if (shape.length == 3 && shape[2] > 4) {
          classesIndex = index;
        }
      }
      if (boxesIndex != null && classesIndex != null) {
        final classShape = outputs[classesIndex].shape;
        return _OutputLayout(
          mode: _OutputParserMode.efficientDetAnchors,
          label: 'efficientdet-split',
          primaryTensorIndex: boxesIndex,
          secondaryTensorIndex: classesIndex,
          candidateCount: classShape[1],
          attributeCount: classShape[2] + 4,
          transposeCombined: false,
        );
      }
    }

    if (outputs.length == 1) {
      final shape = outputs.first.shape;
      if (shape.length == 3 && shape[0] == 1) {
        if (shape[1] > 5 && shape[2] > 5) {
          final transpose = shape[1] < shape[2];
          final attributes = transpose ? shape[1] : shape[2];
          final candidates = transpose ? shape[2] : shape[1];
          if (attributes == 6 || attributes == 7) {
            return _OutputLayout(
              mode: _OutputParserMode.candidateRows,
              label: transpose ? 'candidate-rows-transposed' : 'candidate-rows',
              primaryTensorIndex: 0,
              candidateCount: candidates,
              attributeCount: attributes,
              transposeCombined: transpose,
            );
          }
          return _OutputLayout(
            mode: _OutputParserMode.yoloCombined,
            label: transpose ? 'combined-transposed' : 'combined',
            primaryTensorIndex: 0,
            candidateCount: candidates,
            attributeCount: attributes,
            transposeCombined: transpose,
          );
        }
      }
      if (shape.length == 2 && (shape[1] == 6 || shape[1] == 7)) {
        return _OutputLayout(
          mode: _OutputParserMode.candidateRows,
          label: 'candidate-rows',
          primaryTensorIndex: 0,
          candidateCount: shape[0],
          attributeCount: shape[1],
          transposeCombined: false,
        );
      }
    }

    throw StateError(
      'Unsupported detector output shapes:'
      ' ${outputs.map((tensor) => tensor.shape).toList()}.',
    );
  }

  List<double> _dequantizedOutput(litert.Tensor tensor, _TensorInfo info) {
    final bytes = tensor.data;
    if (info.type == litert.TensorType.float32) {
      final values = Float32List.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ Float32List.bytesPerElement,
      );
      return values.toList(growable: false);
    }

    if (info.type == litert.TensorType.int8) {
      final raw = Int8List.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      return raw
          .map((value) {
            return info.scale == 0
                ? value.toDouble()
                : (value - info.zeroPoint) * info.scale;
          })
          .toList(growable: false);
    }

    final raw = Uint8List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    return raw
        .map((value) {
          return info.scale == 0
              ? value.toDouble()
              : (value - info.zeroPoint) * info.scale;
        })
        .toList(growable: false);
  }

  List<double> _sampleOutputValues(litert.Interpreter interpreter) {
    final values = <double>[];
    for (final tensorInfo in _outputTensors) {
      final raw = _dequantizedOutput(
        interpreter.getOutputTensor(tensorInfo.index),
        tensorInfo,
      );
      values.addAll(raw.take(4));
      if (values.length >= 12) {
        break;
      }
    }
    return values.take(12).toList(growable: false);
  }

  String _classLabelFor(int classIndex) {
    if (_isUnknownClassId(classIndex)) {
      return 'unknown';
    }
    final label = _labels[classIndex].trim().toLowerCase().replaceAll('_', ' ');
    return label.isEmpty || label == '???' ? 'unknown' : label;
  }

  bool _isUnknownClassId(int classIndex) {
    if (classIndex < 0 || classIndex >= _labels.length) {
      return true;
    }
    final label = _labels[classIndex].trim().toLowerCase();
    return label.isEmpty || label == '???' || label == 'unknown';
  }

  List<String> _parseLabelMap(String raw) {
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  _RectF? _normalizedRect(double x1, double y1, double x2, double y2) {
    final left = _normalizeCoordinate(x1, axisLength: _inputWidth);
    final top = _normalizeCoordinate(y1, axisLength: _inputHeight);
    final right = _normalizeCoordinate(x2, axisLength: _inputWidth);
    final bottom = _normalizeCoordinate(y2, axisLength: _inputHeight);
    if (right <= left || bottom <= top) {
      return null;
    }
    return _RectF(left, top, right, bottom);
  }

  _RectF? _centerBoxToRect(double cx, double cy, double width, double height) {
    final normalizedCx = _normalizeCoordinate(cx, axisLength: _inputWidth);
    final normalizedCy = _normalizeCoordinate(cy, axisLength: _inputHeight);
    final normalizedWidth = _normalizeExtent(width, axisLength: _inputWidth);
    final normalizedHeight = _normalizeExtent(height, axisLength: _inputHeight);
    if (normalizedWidth <= 0 || normalizedHeight <= 0) {
      return null;
    }
    final left = (normalizedCx - (normalizedWidth * 0.5))
        .clamp(0.0, 1.0)
        .toDouble();
    final top = (normalizedCy - (normalizedHeight * 0.5))
        .clamp(0.0, 1.0)
        .toDouble();
    final right = (normalizedCx + (normalizedWidth * 0.5))
        .clamp(0.0, 1.0)
        .toDouble();
    final bottom = (normalizedCy + (normalizedHeight * 0.5))
        .clamp(0.0, 1.0)
        .toDouble();
    if (right <= left || bottom <= top) {
      return null;
    }
    return _RectF(left, top, right, bottom);
  }

  double _normalizeCoordinate(double value, {required int axisLength}) {
    if (value.abs() <= 1.5) {
      return value.clamp(0.0, 1.0).toDouble();
    }
    return (value / axisLength).clamp(0.0, 1.0).toDouble();
  }

  double _normalizeExtent(double value, {required int axisLength}) {
    if (value.abs() <= 1.5) {
      return value.clamp(0.0, 1.0).toDouble();
    }
    return (value / axisLength).clamp(0.0, 1.0).toDouble();
  }

  bool _looksLikeScore(double value) => value >= 0 && value <= 1.0;

  double _normalizeScore(double value) {
    if (value.isNaN) {
      return 0;
    }
    if (value >= 0 && value <= 1.0) {
      return value;
    }
    return litert.sigmoid(value);
  }

  List<List<double>> _generateEfficientDetAnchors({
    required int imageSize,
    int minLevel = 3,
    int maxLevel = 7,
    int numScales = 3,
    List<double> aspectRatios = const <double>[1.0, 2.0, 0.5],
    double anchorScale = 4.0,
  }) {
    final anchors = <List<double>>[];
    for (var level = minLevel; level <= maxLevel; level += 1) {
      final stride = 1 << level;
      final featureSize = (imageSize / stride).ceil();
      final baseAnchorSize = anchorScale * stride.toDouble();
      for (var y = 0; y < featureSize; y += 1) {
        for (var x = 0; x < featureSize; x += 1) {
          final cy = ((y + 0.5) * stride) / imageSize;
          final cx = ((x + 0.5) * stride) / imageSize;
          for (var scaleIndex = 0; scaleIndex < numScales; scaleIndex += 1) {
            final scale = math.pow(2, scaleIndex / numScales).toDouble();
            for (final aspect in aspectRatios) {
              final sqrtAspect = math.sqrt(aspect);
              final width = baseAnchorSize * scale * sqrtAspect / imageSize;
              final height = baseAnchorSize * scale / sqrtAspect / imageSize;
              anchors.add(<double>[cx, cy, width, height]);
            }
          }
        }
      }
    }
    return anchors;
  }

  litert.PerformanceConfig _performanceConfigFor(
    InferenceAcceleration acceleration,
    int threadCount,
  ) {
    return switch (acceleration) {
      InferenceAcceleration.cpu => litert.PerformanceConfig(
        mode: litert.PerformanceMode.disabled,
        numThreads: threadCount,
      ),
      InferenceAcceleration.xnnpack => litert.PerformanceConfig.xnnpack(
        numThreads: threadCount,
      ),
      InferenceAcceleration.gpu => litert.PerformanceConfig.gpu(
        numThreads: threadCount,
      ),
      InferenceAcceleration.auto => litert.PerformanceConfig.auto(
        numThreads: threadCount,
      ),
    };
  }

  String _delegateLabelFor(
    InferenceAcceleration acceleration,
    litert.Delegate? delegate,
  ) {
    if (delegate == null) {
      return acceleration == InferenceAcceleration.cpu ? 'CPU' : 'CPU Isolate';
    }
    return switch (acceleration) {
      InferenceAcceleration.auto => 'Auto/XNNPACK',
      InferenceAcceleration.xnnpack => 'XNNPACK',
      InferenceAcceleration.gpu => 'GPU',
      InferenceAcceleration.cpu => 'CPU',
    };
  }

  void _disposeInterpreter() {
    _interpreter?.close();
    _interpreter = null;
    _delegate?.delete();
    _delegate = null;
  }
}

Map<String, Object?> _serializeFrame(FrameContext frame) {
  return <String, Object?>{
    'frameNumber': frame.frameNumber,
    'sourceWidth': frame.sourceSize.width,
    'sourceHeight': frame.sourceSize.height,
    'rotation': frame.rotation.degreesClockwise,
    'sourceAcquisitionMs':
        frame.sourceAcquisitionDuration.inMicroseconds / 1000.0,
    'debugMode': false,
    'scoreThreshold': 0.05,
    'encodedImageBytes': frame.encodedImageBytes == null
        ? null
        : TransferableTypedData.fromList(<TypedData>[frame.encodedImageBytes!]),
    'snapshot': frame.snapshot == null
        ? null
        : <String, Object?>{
            'width': frame.snapshot!.width,
            'height': frame.snapshot!.height,
            'pixelFormat': frame.snapshot!.pixelFormat.name,
            'planes': frame.snapshot!.planes
                .map(
                  (plane) => <String, Object?>{
                    'bytes': TransferableTypedData.fromList(<TypedData>[
                      plane.bytes,
                    ]),
                    'bytesPerRow': plane.bytesPerRow,
                    'bytesPerPixel': plane.bytesPerPixel,
                  },
                )
                .toList(growable: false),
          },
  };
}

_WorkerFrame _deserializeWorkerFrame(Map<String, Object?> payload) {
  final snapshotMap = payload['snapshot'] as Map<String, Object?>?;
  return _WorkerFrame(
    frameNumber: (payload['frameNumber'] as int?) ?? 0,
    sourceWidth: (payload['sourceWidth'] as num?)?.toDouble() ?? 0,
    sourceHeight: (payload['sourceHeight'] as num?)?.toDouble() ?? 0,
    rotation: _frameRotationFromDegrees((payload['rotation'] as int?) ?? 0),
    sourceAcquisitionMs:
        (payload['sourceAcquisitionMs'] as num?)?.toDouble() ?? 0,
    encodedImageBytes: (payload['encodedImageBytes'] as TransferableTypedData?)
        ?.materialize()
        .asUint8List(),
    snapshot: snapshotMap == null
        ? null
        : _WorkerSnapshot(
            width: snapshotMap['width'] as int,
            height: snapshotMap['height'] as int,
            pixelFormat: _pixelFormatFromName(
              snapshotMap['pixelFormat'] as String? ?? 'unsupported',
            ),
            planes: (snapshotMap['planes'] as List<dynamic>)
                .map((dynamic item) {
                  final plane = Map<String, Object?>.from(item as Map);
                  return _WorkerPlane(
                    bytes: (plane['bytes'] as TransferableTypedData)
                        .materialize()
                        .asUint8List(),
                    bytesPerRow: plane['bytesPerRow'] as int,
                    bytesPerPixel: plane['bytesPerPixel'] as int?,
                  );
                })
                .toList(growable: false),
          ),
    debugMode: (payload['debugMode'] as bool?) ?? false,
    scoreThreshold: (payload['scoreThreshold'] as num?)?.toDouble() ?? 0.05,
  );
}

FrameRotation _frameRotationFromDegrees(int degreesClockwise) {
  return switch (degreesClockwise % 360) {
    90 => FrameRotation.rotation90,
    180 => FrameRotation.rotation180,
    270 => FrameRotation.rotation270,
    _ => FrameRotation.rotation0,
  };
}

FramePixelFormat _pixelFormatFromName(String name) {
  return switch (name) {
    'yuv420' => FramePixelFormat.yuv420,
    'bgra8888' => FramePixelFormat.bgra8888,
    _ => FramePixelFormat.unsupported,
  };
}

class _WorkerFrame {
  const _WorkerFrame({
    required this.frameNumber,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.rotation,
    required this.sourceAcquisitionMs,
    required this.debugMode,
    required this.scoreThreshold,
    this.snapshot,
    this.encodedImageBytes,
  });

  final int frameNumber;
  final double sourceWidth;
  final double sourceHeight;
  final FrameRotation rotation;
  final double sourceAcquisitionMs;
  final bool debugMode;
  final double scoreThreshold;
  final _WorkerSnapshot? snapshot;
  final Uint8List? encodedImageBytes;
}

class _WorkerSnapshot {
  const _WorkerSnapshot({
    required this.width,
    required this.height,
    required this.pixelFormat,
    required this.planes,
  });

  final int width;
  final int height;
  final FramePixelFormat pixelFormat;
  final List<_WorkerPlane> planes;
}

class _WorkerPlane {
  const _WorkerPlane({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
}

class _PreprocessResult {
  const _PreprocessResult({
    required this.padding,
    required this.summary,
    required this.colorConversionMs,
    required this.rotationMs,
    required this.resizeMs,
    required this.normalizationMs,
    required this.scoreThreshold,
  });

  final List<double> padding;
  final String summary;
  final double colorConversionMs;
  final double rotationMs;
  final double resizeMs;
  final double normalizationMs;
  final double scoreThreshold;

  _PreprocessResult copyWith({
    List<double>? padding,
    String? summary,
    double? colorConversionMs,
    double? rotationMs,
    double? resizeMs,
    double? normalizationMs,
    double? scoreThreshold,
  }) {
    return _PreprocessResult(
      padding: padding ?? this.padding,
      summary: summary ?? this.summary,
      colorConversionMs: colorConversionMs ?? this.colorConversionMs,
      rotationMs: rotationMs ?? this.rotationMs,
      resizeMs: resizeMs ?? this.resizeMs,
      normalizationMs: normalizationMs ?? this.normalizationMs,
      scoreThreshold: scoreThreshold ?? this.scoreThreshold,
    );
  }
}

enum _OutputParserMode {
  efficientDetAnchors,
  ssdSplit,
  yoloCombined,
  candidateRows,
}

class _OutputLayout {
  const _OutputLayout({
    required this.mode,
    required this.label,
    required this.primaryTensorIndex,
    required this.candidateCount,
    required this.attributeCount,
    required this.transposeCombined,
    this.secondaryTensorIndex,
    this.tertiaryTensorIndex,
  });

  final _OutputParserMode mode;
  final String label;
  final int primaryTensorIndex;
  final int? secondaryTensorIndex;
  final int? tertiaryTensorIndex;
  final int candidateCount;
  final int attributeCount;
  final bool transposeCombined;
}

class _TensorInfo {
  const _TensorInfo({
    required this.index,
    required this.shape,
    required this.type,
    required this.scale,
    required this.zeroPoint,
  });

  final int index;
  final List<int> shape;
  final litert.TensorType type;
  final double scale;
  final int zeroPoint;
}

class _RectF {
  const _RectF(this.xmin, this.ymin, this.xmax, this.ymax);

  final double xmin;
  final double ymin;
  final double xmax;
  final double ymax;
}

class _RawDetection {
  const _RawDetection({
    required this.boundingBox,
    required this.score,
    required this.classIndex,
  });

  final _RectF boundingBox;
  final double score;
  final int classIndex;
}

class _ParsedDetection {
  const _ParsedDetection({
    required this.id,
    required this.classId,
    required this.classLabel,
    required this.sourceModel,
    required this.confidence,
    required this.boundingBox,
  });

  final String id;
  final int classId;
  final String classLabel;
  final String sourceModel;
  final double confidence;
  final BoundingBox boundingBox;
}
