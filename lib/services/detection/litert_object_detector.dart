import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart' as litert;
import 'package:image/image.dart' as img;

import '../../models/bounding_box.dart';
import '../../models/detection_result.dart';
import '../../models/frame_context.dart';
import '../camera/frame_image_utils.dart';
import 'detector.dart';

class LiteRtObjectDetector extends Detector {
  LiteRtObjectDetector({
    this.modelAssetPath = 'assets/models/efficientdet_lite0.tflite',
    this.labelMapAssetPath = 'assets/models/labelmap.txt',
    this.performanceConfig = const litert.PerformanceConfig(),
    this.scoreThreshold = 0.05,
    this.maxResults = 12,
  });

  final String modelAssetPath;
  final String labelMapAssetPath;
  final litert.PerformanceConfig performanceConfig;
  final double scoreThreshold;
  final int maxResults;

  litert.Interpreter? _interpreter;
  litert.Delegate? _delegate;
  litert.TensorFloat32Views? _views;
  List<String> _labels = const <String>[];
  _DetectorOutputBinding? _binding;
  List<List<double>> _anchors = const <List<double>>[];
  int _inputWidth = 0;
  int _inputHeight = 0;

  @override
  String get backendLabel => 'LiteRT EfficientDet-Lite0';

  @override
  Future<void> initialize() async {
    if (_interpreter != null) {
      return;
    }

    final (options, delegate) = litert.InterpreterFactory.create(performanceConfig);
    try {
      final interpreter = await litert.Interpreter.fromAsset(
        modelAssetPath,
        options: options,
      );
      final inputShape = interpreter.getInputTensor(0).shape;
      _inputHeight = inputShape[1];
      _inputWidth = inputShape[2];
      _binding = _discoverOutputBinding(interpreter);
      _anchors = _generateEfficientDetAnchors(imageSize: _inputWidth);
      _views = litert.TensorFloat32Views.capture(interpreter);
      _labels = _parseLabelMap(await rootBundle.loadString(labelMapAssetPath));
      _delegate = delegate;
      _interpreter = interpreter;
    } catch (_) {
      delegate?.delete();
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    final interpreter = _interpreter;
    final delegate = _delegate;
    _interpreter = null;
    _delegate = null;
    _views = null;
    _binding = null;
    _anchors = const <List<double>>[];
    _labels = const <String>[];
    if (interpreter != null) {
      interpreter.close();
    }
    delegate?.delete();
  }

  @override
  Future<List<DetectionResult>> detect(FrameContext frame) async {
    await initialize();
    final interpreter = _interpreter;
    final views = _views;
    final binding = _binding;
    if (interpreter == null || views == null || binding == null) {
      return const <DetectionResult>[];
    }

    final frameImage = FrameImageUtils.decodeFrame(frame);
    if (frameImage == null) {
      return const <DetectionResult>[];
    }

    final prepared = _convertImageToTensor(
      frameImage,
      outW: _inputWidth,
      outH: _inputHeight,
      buffer: views.inputs[0],
    );
    views.inputs[0].setAll(0, prepared.tensor);
    interpreter.invoke();

    final boxBuffer = views.outputs[binding.boxesIdx];
    final classBuffer = views.outputs[binding.classesIdx];
    final decoded = _decodeAnchorsAndScore(
      boxBuffer: boxBuffer,
      classBuffer: classBuffer,
      scoreFloor: scoreThreshold,
    );
    final unpadded = _removeLetterboxPadding(decoded, prepared.padding);
    unpadded.sort((a, b) => b.score.compareTo(a.score));

    final weighted = litert.weightedNms(
      unpadded
          .map((detection) => [
                detection.boundingBox.xmin,
                detection.boundingBox.ymin,
                detection.boundingBox.xmax,
                detection.boundingBox.ymax,
              ])
          .toList(growable: false),
      unpadded.map((detection) => detection.score).toList(growable: false),
      iouThres: 0.45,
      maxDet: maxResults,
    );

    final width = frameImage.width.toDouble();
    final height = frameImage.height.toDouble();

    return weighted.asMap().entries.map((entry) {
      final nmsIndex = entry.value.index;
      final detection = unpadded[nmsIndex];
      final classLabel = _classLabelFor(detection.classIndex);
      return DetectionResult(
        id: '${classLabel}_${frame.frameNumber}_${entry.key + 1}',
        classLabel: classLabel,
        confidence: entry.value.score,
        boundingBox: BoundingBox(
          left: detection.boundingBox.xmin * width,
          top: detection.boundingBox.ymin * height,
          width: (detection.boundingBox.xmax - detection.boundingBox.xmin) * width,
          height: (detection.boundingBox.ymax - detection.boundingBox.ymin) * height,
        ).clampTo(frame.sourceSize),
        timestamp: frame.timestamp,
      );
    }).toList(growable: false);
  }

  _DetectorOutputBinding _discoverOutputBinding(litert.Interpreter interpreter) {
    final outputTensors = interpreter.getOutputTensors();
    int? boxesIdx;
    int? classesIdx;
    int? numAnchors;
    int? numClasses;

    for (var index = 0; index < outputTensors.length; index += 1) {
      final shape = outputTensors[index].shape;
      if (shape.length != 3) {
        continue;
      }
      if (shape[2] == 4) {
        boxesIdx = index;
        numAnchors = shape[1];
      } else if (shape[2] > 4) {
        classesIdx = index;
        numClasses = shape[2];
        numAnchors ??= shape[1];
      }
    }

    if (boxesIdx == null ||
        classesIdx == null ||
        numAnchors == null ||
        numClasses == null) {
      throw StateError(
        'Unable to identify EfficientDet output tensors. '
        'Got ${outputTensors.map((tensor) => tensor.shape).toList()}.',
      );
    }

    return _DetectorOutputBinding(
      boxesIdx: boxesIdx,
      classesIdx: classesIdx,
      numAnchors: numAnchors,
      numClasses: numClasses,
    );
  }

  _PreparedTensor _convertImageToTensor(
    img.Image source, {
    required int outW,
    required int outH,
    Float32List? buffer,
  }) {
    final letterbox = litert.computeLetterboxParams(
      srcWidth: source.width,
      srcHeight: source.height,
      targetWidth: outW,
      targetHeight: outH,
    );

    final resized = img.copyResize(
      source,
      width: letterbox.newWidth,
      height: letterbox.newHeight,
      interpolation: img.Interpolation.linear,
    );
    final rgbBytes = resized.getBytes(order: img.ChannelOrder.rgb);
    final tensor = buffer ?? Float32List(outW * outH * 3);
    tensor.fillRange(0, tensor.length, -1.0);

    for (var y = 0; y < letterbox.newHeight; y += 1) {
      final destY = y + letterbox.padTop;
      final rowOffset = destY * outW * 3;
      final sourceRowOffset = y * letterbox.newWidth * 3;
      for (var x = 0; x < letterbox.newWidth; x += 1) {
        final destOffset = rowOffset + ((x + letterbox.padLeft) * 3);
        final sourceOffset = sourceRowOffset + (x * 3);
        tensor[destOffset] = (rgbBytes[sourceOffset] - 127.5) / 127.5;
        tensor[destOffset + 1] = (rgbBytes[sourceOffset + 1] - 127.5) / 127.5;
        tensor[destOffset + 2] = (rgbBytes[sourceOffset + 2] - 127.5) / 127.5;
      }
    }

    return _PreparedTensor(
      tensor: tensor,
      padding: <double>[
        letterbox.padTop / outH,
        letterbox.padBottom / outH,
        letterbox.padLeft / outW,
        letterbox.padRight / outW,
      ],
    );
  }

  List<_RawDetection> _decodeAnchorsAndScore({
    required Float32List boxBuffer,
    required Float32List classBuffer,
    required double scoreFloor,
  }) {
    final binding = _binding!;
    final detections = <_RawDetection>[];
    final minimumLogit = scoreFloor > 0 && scoreFloor < 1
        ? math.log(scoreFloor / (1.0 - scoreFloor))
        : -1e9;

    for (var anchorIndex = 0; anchorIndex < binding.numAnchors; anchorIndex += 1) {
      final classBase = anchorIndex * binding.numClasses;
      double bestLogit = -double.infinity;
      var bestClass = -1;

      for (var classIndex = 0; classIndex < binding.numClasses; classIndex += 1) {
        final value = classBuffer[classBase + classIndex];
        if (value > bestLogit) {
          bestLogit = value;
          bestClass = classIndex;
        }
      }

      if (bestLogit < minimumLogit) {
        continue;
      }

      final score = litert.sigmoid(bestLogit);
      if (score < scoreFloor) {
        continue;
      }

      final anchor = _anchors[anchorIndex];
      final centerX = anchor[0];
      final centerY = anchor[1];
      final anchorWidth = anchor[2];
      final anchorHeight = anchor[3];
      final boxBase = anchorIndex * 4;
      final ty = boxBuffer[boxBase];
      final tx = boxBuffer[boxBase + 1];
      final th = boxBuffer[boxBase + 2];
      final tw = boxBuffer[boxBase + 3];

      final cy = (ty * anchorHeight) + centerY;
      final cx = (tx * anchorWidth) + centerX;
      final height = math.exp(th) * anchorHeight;
      final width = math.exp(tw) * anchorWidth;

      var xmin = cx - (width * 0.5);
      var ymin = cy - (height * 0.5);
      var xmax = cx + (width * 0.5);
      var ymax = cy + (height * 0.5);

      xmin = xmin.clamp(0.0, 1.0).toDouble();
      ymin = ymin.clamp(0.0, 1.0).toDouble();
      xmax = xmax.clamp(0.0, 1.0).toDouble();
      ymax = ymax.clamp(0.0, 1.0).toDouble();

      if (xmax - xmin < 0.001 || ymax - ymin < 0.001) {
        continue;
      }

      detections.add(
        _RawDetection(
          boundingBox: _RectF(xmin, ymin, xmax, ymax),
          score: score,
          classIndex: bestClass,
        ),
      );
    }

    return detections;
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

    double clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

    final results = <_RawDetection>[];
    for (final detection in detections) {
      final box = detection.boundingBox;
      final unpadded = _RectF(
        clamp01((box.xmin - padLeft) / scaleX),
        clamp01((box.ymin - padTop) / scaleY),
        clamp01((box.xmax - padLeft) / scaleX),
        clamp01((box.ymax - padTop) / scaleY),
      );
      if (unpadded.xmax - unpadded.xmin < 0.0001 ||
          unpadded.ymax - unpadded.ymin < 0.0001) {
        continue;
      }
      results.add(
        _RawDetection(
          boundingBox: unpadded,
          score: detection.score,
          classIndex: detection.classIndex,
        ),
      );
    }
    return results;
  }

  List<String> _parseLabelMap(String raw) {
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  String _classLabelFor(int classIndex) {
    if (classIndex < 0 || classIndex >= _labels.length) {
      return 'object';
    }

    final normalized = _labels[classIndex].trim().toLowerCase().replaceAll('_', ' ');
    if (normalized.isEmpty || normalized == '???') {
      return 'object';
    }
    return normalized;
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
}

class _DetectorOutputBinding {
  const _DetectorOutputBinding({
    required this.boxesIdx,
    required this.classesIdx,
    required this.numAnchors,
    required this.numClasses,
  });

  final int boxesIdx;
  final int classesIdx;
  final int numAnchors;
  final int numClasses;
}

class _PreparedTensor {
  const _PreparedTensor({
    required this.tensor,
    required this.padding,
  });

  final Float32List tensor;
  final List<double> padding;
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
