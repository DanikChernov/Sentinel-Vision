import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel_vision_mobile/models/app_settings.dart';
import 'package:sentinel_vision_mobile/models/bounding_box.dart';
import 'package:sentinel_vision_mobile/models/detection_result.dart';
import 'package:sentinel_vision_mobile/models/frame_context.dart';
import 'package:sentinel_vision_mobile/models/pipeline_event.dart';
import 'package:sentinel_vision_mobile/models/tracked_entity.dart';
import 'package:sentinel_vision_mobile/models/video_source.dart';
import 'package:sentinel_vision_mobile/services/detection/detector.dart';
import 'package:sentinel_vision_mobile/services/identity/heuristic_identity_registry.dart';
import 'package:sentinel_vision_mobile/services/orchestrator/fusion_engine.dart';
import 'package:sentinel_vision_mobile/services/pipeline/vision_pipeline_controller.dart';
import 'package:sentinel_vision_mobile/services/tracking/heuristic_tracker.dart';

void main() {
  test('detector implementations preserve frame timestamps', () async {
    final detector = _TimestampDetector();
    final frame = FrameContext(
      frameNumber: 12,
      sourceSize: const Size(1280, 720),
      timestamp: DateTime.utc(2026, 1, 1, 12),
      sourceType: VisionSourceType.camera,
    );

    final detections = await detector.detect(frame);

    expect(detections, isNotEmpty);
    expect(detections.first.timestamp, frame.timestamp);
  });

  test('heuristic tracker keeps a stable track across adjacent frames', () {
    final tracker = HeuristicTracker();
    final frame1 = FrameContext(
      frameNumber: 1,
      sourceSize: const Size(1280, 720),
      timestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
      sourceType: VisionSourceType.camera,
    );
    final frame2 = FrameContext(
      frameNumber: 2,
      sourceSize: const Size(1280, 720),
      timestamp: DateTime.utc(2026, 1, 1, 12, 0, 0, 120),
      sourceType: VisionSourceType.camera,
    );

    final firstUpdate = tracker.update([
      DetectionResult(
        id: 'd1',
        classLabel: 'person',
        confidence: 0.84,
        boundingBox: const BoundingBox(
          left: 120,
          top: 90,
          width: 140,
          height: 300,
        ),
        timestamp: frame1.timestamp,
      ),
    ], frame1);

    final secondUpdate = tracker.update([
      DetectionResult(
        id: 'd2',
        classLabel: 'person',
        confidence: 0.86,
        boundingBox: const BoundingBox(
          left: 132,
          top: 94,
          width: 142,
          height: 302,
        ),
        timestamp: frame2.timestamp,
      ),
    ], frame2);

    expect(firstUpdate, hasLength(1));
    expect(secondUpdate, hasLength(1));
    expect(secondUpdate.single.trackId, firstUpdate.single.trackId);
  });

  test('label propagation uses class label plus track ID in overlays', () {
    final timestamp = DateTime.utc(2026, 1, 1, 12);
    final track = TrackedEntity(
      trackId: 'track-003',
      stableLabel: 'track-003',
      detectionId: 'det-1',
      classId: 0,
      classLabel: 'person',
      boundingBox: const BoundingBox(
        left: 120,
        top: 90,
        width: 140,
        height: 300,
      ),
      confidence: 0.87,
      firstSeenAt: timestamp,
      lastSeenAt: timestamp,
    );

    final overlay = const FusionEngine().buildOverlayItems(
      tracks: [track],
      segmentations: const [],
      identities: const [],
      previousItems: const [],
    );

    expect(overlay.single.displayLabel, contains('person'));
    expect(overlay.single.displayLabel, contains('#003'));
    expect(overlay.single.displayLabel, isNot(contains('track-003')));
  });

  test('unknown class labels render as unknown plus track ID', () {
    final timestamp = DateTime.utc(2026, 1, 1, 12);
    final track = TrackedEntity(
      trackId: 'track-003',
      stableLabel: 'track-003',
      detectionId: 'det-unknown',
      classId: 999,
      classLabel: 'unknown',
      boundingBox: const BoundingBox(
        left: 120,
        top: 90,
        width: 140,
        height: 300,
      ),
      confidence: 0.5,
      firstSeenAt: timestamp,
      lastSeenAt: timestamp,
    );

    final overlay = const FusionEngine().buildOverlayItems(
      tracks: [track],
      segmentations: const [],
      identities: const [],
      previousItems: const [],
    );

    expect(overlay.single.displayLabel, 'unknown #003');
  });

  test('identity registry recovers the same label after track replacement', () {
    final registry = HeuristicIdentityRegistry();
    final frame1 = FrameContext(
      frameNumber: 1,
      sourceSize: const Size(1280, 720),
      timestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
      sourceType: VisionSourceType.camera,
    );
    final frame2 = FrameContext(
      frameNumber: 2,
      sourceSize: const Size(1280, 720),
      timestamp: DateTime.utc(2026, 1, 1, 12, 0, 2),
      sourceType: VisionSourceType.camera,
    );

    final firstPass = registry.reconcile(
      [
        TrackedEntity(
          trackId: 'track-001',
          stableLabel: 'track-001',
          classLabel: 'person',
          boundingBox: const BoundingBox(
            left: 220,
            top: 110,
            width: 150,
            height: 320,
          ),
          confidence: 0.88,
          firstSeenAt: frame1.timestamp,
          lastSeenAt: frame1.timestamp,
        ),
      ],
      frame1,
      persistence: const Duration(seconds: 4),
    );

    final recoveredPass = registry.reconcile(
      [
        TrackedEntity(
          trackId: 'track-002',
          stableLabel: 'track-002',
          classLabel: 'person',
          boundingBox: const BoundingBox(
            left: 228,
            top: 112,
            width: 150,
            height: 320,
          ),
          confidence: 0.86,
          firstSeenAt: frame2.timestamp,
          lastSeenAt: frame2.timestamp,
        ),
      ],
      frame2,
      persistence: const Duration(seconds: 4),
    );

    expect(firstPass.tracks.single.stableLabel, 'person-001');
    expect(recoveredPass.tracks.single.stableLabel, 'person-001');
    expect(recoveredPass.tracks.single.persistentEntityId, 'person-001');
    expect(
      recoveredPass.events.any(
        (event) => event.type == PipelineEventType.identityRecovered,
      ),
      isTrue,
    );
  });

  test('identity registry creates a new ID when recovery score is too low', () {
    final registry = HeuristicIdentityRegistry();
    final frame1 = FrameContext(
      frameNumber: 1,
      sourceSize: const Size(1280, 720),
      timestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
      sourceType: VisionSourceType.camera,
    );
    final frame2 = FrameContext(
      frameNumber: 2,
      sourceSize: const Size(1280, 720),
      timestamp: DateTime.utc(2026, 1, 1, 12, 0, 2),
      sourceType: VisionSourceType.camera,
    );

    registry.reconcile(
      [
        TrackedEntity(
          trackId: 'track-001',
          stableLabel: 'track-001',
          classLabel: 'person',
          boundingBox: const BoundingBox(
            left: 20,
            top: 20,
            width: 120,
            height: 240,
          ),
          confidence: 0.88,
          firstSeenAt: frame1.timestamp,
          lastSeenAt: frame1.timestamp,
        ),
      ],
      frame1,
      persistence: const Duration(seconds: 4),
      confidenceThreshold: 0.9,
    );

    final second = registry.reconcile(
      [
        TrackedEntity(
          trackId: 'track-002',
          stableLabel: 'track-002',
          classLabel: 'person',
          boundingBox: const BoundingBox(
            left: 900,
            top: 420,
            width: 220,
            height: 260,
          ),
          confidence: 0.84,
          firstSeenAt: frame2.timestamp,
          lastSeenAt: frame2.timestamp,
        ),
      ],
      frame2,
      persistence: const Duration(seconds: 4),
      confidenceThreshold: 0.9,
    );

    expect(second.tracks.single.stableLabel, 'person-002');
    expect(registry.diagnostics.matchesAccepted, 0);
    expect(registry.diagnostics.matchesAttempted, greaterThan(0));
  });

  test(
    'invalid backend switch is rejected and previous backend remains active',
    () {
      final controller = VisionPipelineController(
        detector: _TimestampDetector(),
      );
      addTearDown(controller.dispose);

      controller.updateSettings(const AppSettings(backend: ModelBackend.onnx));

      expect(controller.settings.backend, ModelBackend.tflite);
      expect(controller.errorMessage, isNull);
    },
  );

  test('unsupported resolution switch is rejected safely', () {
    final controller = VisionPipelineController(detector: _TimestampDetector());
    addTearDown(controller.dispose);

    controller.updateSettings(const AppSettings(modelInputSize: 640));

    expect(controller.settings.modelInputSize, 320);
    expect(controller.supportedModelInputSizes, [320]);
  });
}

class _TimestampDetector extends Detector {
  @override
  String get backendLabel => 'Test Detector';

  @override
  Future<List<DetectionResult>> detect(FrameContext frame) async {
    return [
      DetectionResult(
        id: 'detector-1',
        classId: 0,
        classLabel: 'person',
        sourceModel: backendLabel,
        confidence: 0.84,
        boundingBox: const BoundingBox(
          left: 120,
          top: 90,
          width: 140,
          height: 300,
        ),
        timestamp: frame.timestamp,
      ),
    ];
  }
}
