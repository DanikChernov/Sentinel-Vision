import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../../models/bounding_box.dart';

class FaceAlignmentResult {
  const FaceAlignmentResult({
    required this.alignedFace,
    required this.faceBoundingBox,
    required this.faceConfidence,
  });

  final img.Image alignedFace;
  final BoundingBox faceBoundingBox;
  final double faceConfidence;
}

class FaceAlignmentProcessor {
  const FaceAlignmentProcessor();

  FaceAlignmentResult? align({
    required img.Image personCrop,
    required Face face,
  }) {
    final paddedBox = _toBoundingBox(face.boundingBox).inflate(
      horizontal: 0.12,
      vertical: 0.18,
      maxWidth: personCrop.width.toDouble(),
      maxHeight: personCrop.height.toDouble(),
    );
    final cropped = img.copyCrop(
      personCrop,
      x: paddedBox.left.floor(),
      y: paddedBox.top.floor(),
      width: paddedBox.width.ceil().clamp(1, personCrop.width).toInt(),
      height: paddedBox.height.ceil().clamp(1, personCrop.height).toInt(),
    );

    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    img.Image aligned = cropped;

    if (leftEye != null && rightEye != null) {
      final dx = rightEye.x - leftEye.x;
      final dy = rightEye.y - leftEye.y;
      final angle = math.atan2(dy, dx) * (180 / math.pi);
      aligned = img.copyRotate(cropped, angle: -angle);
    }

    return FaceAlignmentResult(
      alignedFace: img.copyResize(
        aligned,
        width: 112,
        height: 112,
        interpolation: img.Interpolation.linear,
      ),
      faceBoundingBox: paddedBox,
      faceConfidence: _faceConfidence(face),
    );
  }

  BoundingBox _toBoundingBox(Rect rect) {
    return BoundingBox(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
    );
  }

  double _faceConfidence(Face face) {
    final leftEyeOpen = face.leftEyeOpenProbability;
    final rightEyeOpen = face.rightEyeOpenProbability;
    final smiling = face.smilingProbability;
    final trackingBoost = face.trackingId == null ? 0.0 : 0.08;

    final average = <double?>[
      leftEyeOpen,
      rightEyeOpen,
      smiling,
    ].whereType<double>().fold<double>(0, (sum, value) => sum + value);
    final count = <double?>[
      leftEyeOpen,
      rightEyeOpen,
      smiling,
    ].whereType<double>().length;

    final expressionScore = count == 0 ? 0.72 : average / count;
    return (0.62 + (expressionScore * 0.25) + trackingBoost)
        .clamp(0.0, 0.99)
        .toDouble();
  }
}
