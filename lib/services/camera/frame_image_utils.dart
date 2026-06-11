import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../models/bounding_box.dart';
import '../../models/frame_context.dart';

class FrameImageUtils {
  const FrameImageUtils._();

  static img.Image? decodeFrame(FrameContext frame) {
    if (frame.encodedImageBytes case final bytes?) {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return null;
      }
      return _applyRotation(decoded, frame.rotation);
    }

    if (frame.snapshot case final snapshot?) {
      final decoded = _decodeSnapshot(snapshot);
      if (decoded == null) {
        return null;
      }
      return _applyRotation(decoded, frame.rotation);
    }

    return null;
  }

  static img.Image? cropBoundingBox({
    required img.Image image,
    required BoundingBox boundingBox,
  }) {
    if (image.width <= 0 || image.height <= 0) {
      return null;
    }

    final left = boundingBox.left.floor().clamp(0, image.width - 1).toInt();
    final top = boundingBox.top.floor().clamp(0, image.height - 1).toInt();
    final width = boundingBox.width.ceil();
    final height = boundingBox.height.ceil();
    final cropWidth = math.min(image.width - left, math.max(4, width)).toInt();
    final cropHeight = math
        .min(image.height - top, math.max(4, height))
        .toInt();

    if (cropWidth <= 0 || cropHeight <= 0) {
      return null;
    }

    return img.copyCrop(
      image,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
    );
  }

  static Uint8List rgbaBytes(img.Image image) {
    return image.getBytes(order: img.ChannelOrder.rgba);
  }

  static img.Image? _decodeSnapshot(FrameSnapshot snapshot) {
    return switch (snapshot.pixelFormat) {
      FramePixelFormat.bgra8888 => _decodeBgra(snapshot),
      FramePixelFormat.yuv420 => _decodeYuv420(snapshot),
      FramePixelFormat.unsupported => null,
    };
  }

  static img.Image _decodeBgra(FrameSnapshot snapshot) {
    final plane = snapshot.planes.first;
    final image = img.Image(width: snapshot.width, height: snapshot.height);

    for (var y = 0; y < snapshot.height; y += 1) {
      for (var x = 0; x < snapshot.width; x += 1) {
        final index =
            (y * plane.bytesPerRow) + (x * (plane.bytesPerPixel ?? 4));
        final b = plane.bytes[index];
        final g = plane.bytes[index + 1];
        final r = plane.bytes[index + 2];
        final a = plane.bytes[index + 3];
        image.setPixelRgba(x, y, r, g, b, a);
      }
    }

    return image;
  }

  static img.Image? _decodeYuv420(FrameSnapshot snapshot) {
    if (snapshot.planes.length < 3) {
      return null;
    }

    final yPlane = snapshot.planes[0];
    final uPlane = snapshot.planes[1];
    final vPlane = snapshot.planes[2];
    final image = img.Image(width: snapshot.width, height: snapshot.height);
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;

    for (var y = 0; y < snapshot.height; y += 1) {
      final uvRow = y ~/ 2;
      for (var x = 0; x < snapshot.width; x += 1) {
        final uvCol = x ~/ 2;
        final yIndex = (y * yPlane.bytesPerRow) + x;
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
        image.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    return image;
  }

  static img.Image _applyRotation(img.Image image, FrameRotation rotation) {
    return switch (rotation) {
      FrameRotation.rotation0 => image,
      FrameRotation.rotation90 => img.copyRotate(image, angle: 90),
      FrameRotation.rotation180 => img.copyRotate(image, angle: 180),
      FrameRotation.rotation270 => img.copyRotate(image, angle: -90),
    };
  }
}
