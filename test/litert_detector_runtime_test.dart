import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sentinel_vision_mobile/models/frame_context.dart';
import 'package:sentinel_vision_mobile/models/video_source.dart';
import 'package:sentinel_vision_mobile/services/detection/litert_object_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LiteRT detector produces detections on TensorFlow sample image', () async {
    final bytes = await File('test/fixtures/cat1.png').readAsBytes();
    final decoded = img.decodeImage(bytes);
    expect(decoded, isNotNull);

    final frame = FrameContext(
      frameNumber: 1,
      sourceSize: Size(decoded!.width.toDouble(), decoded.height.toDouble()),
      timestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
      sourceType: VisionSourceType.videoFile,
      encodedImageBytes: bytes,
    );

    final detector = LiteRtObjectDetector();
    await detector.initialize();
    final detections = await detector.detect(frame);

    addTearDown(detector.dispose);

    expect(detections, isNotEmpty);
    expect(
      detections.any((detection) => detection.classLabel.contains('cat')),
      isTrue,
    );
  });
}
