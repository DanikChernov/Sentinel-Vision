import 'dart:typed_data';
import 'dart:ui';

import 'video_source.dart';

enum FramePixelFormat {
  yuv420,
  bgra8888,
  unsupported,
}

enum FrameRotation {
  rotation0(0),
  rotation90(90),
  rotation180(180),
  rotation270(270);

  const FrameRotation(this.degreesClockwise);

  final int degreesClockwise;

  bool get swapsDimensions =>
      this == FrameRotation.rotation90 || this == FrameRotation.rotation270;
}

class FramePlaneData {
  const FramePlaneData({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
}

class FrameSnapshot {
  const FrameSnapshot({
    required this.width,
    required this.height,
    required this.pixelFormat,
    required this.planes,
  });

  final int width;
  final int height;
  final FramePixelFormat pixelFormat;
  final List<FramePlaneData> planes;

  bool get canCrop => planes.isNotEmpty && pixelFormat != FramePixelFormat.unsupported;
  bool get isBgra => pixelFormat == FramePixelFormat.bgra8888;
}

class FrameContext {
  const FrameContext({
    required this.frameNumber,
    required this.sourceSize,
    required this.timestamp,
    required this.sourceType,
    this.sourcePosition,
    this.rotation = FrameRotation.rotation0,
    this.snapshot,
    this.encodedImageBytes,
    this.sourcePath,
    this.sourceAcquisitionDuration = Duration.zero,
  });

  final int frameNumber;
  final Size sourceSize;
  final DateTime timestamp;
  final VisionSourceType sourceType;
  final Duration? sourcePosition;
  final FrameRotation rotation;
  final FrameSnapshot? snapshot;
  final Uint8List? encodedImageBytes;
  final String? sourcePath;
  final Duration sourceAcquisitionDuration;
}
