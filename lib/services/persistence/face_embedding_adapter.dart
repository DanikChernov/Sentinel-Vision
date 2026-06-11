import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../../models/persistence_models.dart';

abstract class FaceEmbeddingAdapter {
  FaceEmbeddingBackend get backend;

  Future<void> initialize() async {}

  Future<void> dispose() async {}

  Future<FaceEmbeddingResult?> embed({
    required img.Image alignedFace,
    required double faceConfidence,
  });
}

class LocalDescriptorFaceEmbeddingAdapter extends FaceEmbeddingAdapter {
  @override
  FaceEmbeddingBackend get backend => FaceEmbeddingBackend.localDescriptor;

  @override
  Future<FaceEmbeddingResult?> embed({
    required img.Image alignedFace,
    required double faceConfidence,
  }) async {
    final resized = img.copyResize(
      alignedFace,
      width: 96,
      height: 96,
      interpolation: img.Interpolation.linear,
    );
    final embedding = <double>[];

    final quadrants = <(int, int, int, int)>[
      (0, 0, 48, 48),
      (48, 0, 48, 48),
      (0, 48, 48, 48),
      (48, 48, 48, 48),
    ];

    for (final quadrant in quadrants) {
      embedding.addAll(
        _histogramForRegion(
          resized,
          quadrant.$1,
          quadrant.$2,
          quadrant.$3,
          quadrant.$4,
        ),
      );
    }
    embedding.addAll(_gradientSignature(resized));

    final normalized = _l2Normalize(embedding);
    return FaceEmbeddingResult(
      embedding: normalized,
      faceConfidence: faceConfidence,
    );
  }

  List<double> _histogramForRegion(
    img.Image image,
    int left,
    int top,
    int width,
    int height,
  ) {
    final red = List<double>.filled(8, 0, growable: false);
    final green = List<double>.filled(8, 0, growable: false);
    final blue = List<double>.filled(8, 0, growable: false);
    final luminance = List<double>.filled(8, 0, growable: false);
    var count = 0.0;

    for (var y = top; y < top + height; y += 1) {
      for (var x = left; x < left + width; x += 1) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final l = ((r * 0.299) + (g * 0.587) + (b * 0.114)).round();
        red[(r / 32).floor().clamp(0, 7)] += 1;
        green[(g / 32).floor().clamp(0, 7)] += 1;
        blue[(b / 32).floor().clamp(0, 7)] += 1;
        luminance[(l / 32).floor().clamp(0, 7)] += 1;
        count += 1;
      }
    }

    if (count == 0) {
      return List<double>.filled(32, 0, growable: false);
    }

    return <double>[
      ...red.map((value) => value / count),
      ...green.map((value) => value / count),
      ...blue.map((value) => value / count),
      ...luminance.map((value) => value / count),
    ];
  }

  List<double> _gradientSignature(img.Image image) {
    final values = <double>[];
    for (var y = 8; y < image.height; y += 16) {
      for (var x = 8; x < image.width; x += 16) {
        final center = image.getPixel(x, y).luminanceNormalized.toDouble();
        final dx =
            image.getPixel(x + 1, y).luminanceNormalized.toDouble() -
            image.getPixel(x - 1, y).luminanceNormalized.toDouble();
        final dy =
            image.getPixel(x, y + 1).luminanceNormalized.toDouble() -
            image.getPixel(x, y - 1).luminanceNormalized.toDouble();
        values.add(center);
        values.add(dx);
        values.add(dy);
      }
    }
    return values;
  }

  List<double> _l2Normalize(List<double> values) {
    var norm = 0.0;
    for (final value in values) {
      norm += value * value;
    }
    norm = math.sqrt(norm);
    if (norm <= 0) {
      return List<double>.filled(values.length, 0, growable: false);
    }
    return values.map((value) => value / norm).toList(growable: false);
  }
}
