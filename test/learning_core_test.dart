import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sentinel_vision_mobile/models/app_settings.dart';
import 'package:sentinel_vision_mobile/models/bounding_box.dart';
import 'package:sentinel_vision_mobile/models/frame_context.dart';
import 'package:sentinel_vision_mobile/models/tracked_entity.dart';
import 'package:sentinel_vision_mobile/models/video_source.dart';
import 'package:sentinel_vision_mobile/services/learning/learning_core.dart';
import 'package:sentinel_vision_mobile/services/learning/usage_memory_store.dart';

void main() {
  test(
    'learning core reuses corrected object labels for future matches',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'sentinel_learning_',
      );
      final core = SentinelLearningCore(
        usageMemoryStore: UsageMemoryStore(storageRootPath: tempDir.path),
      );
      await core.initialize();

      final settings = const AppSettings();
      final timestamp = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final frame1 = FrameContext(
        frameNumber: 1,
        sourceSize: const Size(640, 360),
        timestamp: timestamp,
        sourceType: VisionSourceType.camera,
      );
      final observed = await core.observeFrame(
        frame: frame1,
        settings: settings,
        entities: [
          TrackedEntity(
            trackId: 'track-001',
            stableLabel: 'object-001',
            classLabel: 'cup',
            boundingBox: const BoundingBox(
              left: 120,
              top: 120,
              width: 110,
              height: 110,
            ),
            confidence: 0.61,
            detectorConfidence: 0.61,
            firstSeenAt: timestamp,
            lastSeenAt: timestamp,
          ),
        ],
      );

      await core.applyCorrection(
        entity: observed.entities.single,
        correctedLabel: 'coffee mug',
        frame: frame1,
        settings: settings,
      );

      final frame2 = FrameContext(
        frameNumber: 2,
        sourceSize: const Size(640, 360),
        timestamp: timestamp.add(const Duration(seconds: 1)),
        sourceType: VisionSourceType.camera,
      );
      final refined = await core.observeFrame(
        frame: frame2,
        settings: settings,
        entities: [
          TrackedEntity(
            trackId: 'track-002',
            stableLabel: 'object-002',
            classLabel: 'cup',
            boundingBox: const BoundingBox(
              left: 124,
              top: 118,
              width: 112,
              height: 108,
            ),
            confidence: 0.6,
            detectorConfidence: 0.6,
            firstSeenAt: frame2.timestamp,
            lastSeenAt: frame2.timestamp,
          ),
        ],
      );

      expect(refined.entities.single.learnedLabel, 'coffee mug');
      expect(core.snapshot.correctedLabels, hasLength(1));
      expect(core.snapshot.correctedLabels.single.correctedLabel, 'coffee mug');
      expect(core.snapshot.metrics.correctionCount, 1);

      await core.dispose();
      await tempDir.delete(recursive: true);
    },
  );

  test('learning core reinforces corrected person aliases locally', () async {
    final tempDir = await Directory.systemTemp.createTemp('sentinel_learning_');
    final core = SentinelLearningCore(
      usageMemoryStore: UsageMemoryStore(storageRootPath: tempDir.path),
    );
    await core.initialize();

    const settings = AppSettings();
    final timestamp = DateTime.utc(2026, 1, 1, 13, 0, 0);
    final frame1 = FrameContext(
      frameNumber: 10,
      sourceSize: const Size(1280, 720),
      timestamp: timestamp,
      sourceType: VisionSourceType.camera,
    );
    final firstPass = await core.observeFrame(
      frame: frame1,
      settings: settings,
      entities: [
        TrackedEntity(
          trackId: 'track-person-1',
          stableLabel: 'person-001',
          classLabel: 'person',
          boundingBox: const BoundingBox(
            left: 220,
            top: 110,
            width: 160,
            height: 320,
          ),
          confidence: 0.86,
          detectorConfidence: 0.86,
          firstSeenAt: timestamp,
          lastSeenAt: timestamp,
        ),
      ],
    );

    await core.applyCorrection(
      entity: firstPass.entities.single,
      correctedLabel: 'Dan',
      frame: frame1,
      settings: settings,
    );

    final frame2 = FrameContext(
      frameNumber: 11,
      sourceSize: const Size(1280, 720),
      timestamp: timestamp.add(const Duration(seconds: 2)),
      sourceType: VisionSourceType.camera,
    );
    final secondPass = await core.observeFrame(
      frame: frame2,
      settings: settings,
      entities: [
        TrackedEntity(
          trackId: 'track-person-2',
          stableLabel: 'person-001',
          classLabel: 'person',
          boundingBox: const BoundingBox(
            left: 228,
            top: 112,
            width: 162,
            height: 322,
          ),
          confidence: 0.84,
          detectorConfidence: 0.84,
          firstSeenAt: frame2.timestamp,
          lastSeenAt: frame2.timestamp,
        ),
      ],
    );

    expect(secondPass.entities.single.learnedLabel, 'Dan');
    expect(core.snapshot.identities, hasLength(1));
    expect(core.snapshot.identities.single.preferredAlias, 'Dan');
    expect(core.snapshot.identities.single.correctionCount, 1);

    await core.dispose();
    await tempDir.delete(recursive: true);
  });

  test('dataset export includes all locally stored training samples', () async {
    final tempDir = await Directory.systemTemp.createTemp('sentinel_learning_');
    final core = SentinelLearningCore(
      usageMemoryStore: UsageMemoryStore(storageRootPath: tempDir.path),
    );
    await core.initialize();

    final settings = const AppSettings(saveDetectionCropsEnabled: true);
    final snapshot = _bgraSnapshot(width: 8, height: 8);

    for (var index = 0; index < 30; index += 1) {
      final timestamp = DateTime.utc(2026, 1, 1, 14, 0, index);
      final frame = FrameContext(
        frameNumber: index + 1,
        sourceSize: const Size(8, 8),
        timestamp: timestamp,
        sourceType: VisionSourceType.camera,
        snapshot: snapshot,
      );

      await core.observeFrame(
        frame: frame,
        settings: settings,
        entities: [
          TrackedEntity(
            trackId: 'track-$index',
            stableLabel: 'object-${index.toString().padLeft(3, '0')}',
            classLabel: 'cup',
            boundingBox: const BoundingBox(
              left: 1,
              top: 1,
              width: 4,
              height: 4,
            ),
            confidence: 0.72,
            detectorConfidence: 0.72,
            firstSeenAt: timestamp,
            lastSeenAt: timestamp,
          ),
        ],
      );
    }

    final exportPath = await core.exportTrainingDataset();
    expect(exportPath, isNotNull);
    expect(core.snapshot.metrics.trainingSampleCount, 30);
    expect(core.snapshot.recentSamples, hasLength(24));

    final manifestPath = p.join(exportPath!, 'training_samples.json');
    final manifestJson = await File(manifestPath).readAsString();
    final manifest = jsonDecode(manifestJson) as List<dynamic>;

    expect(manifest, hasLength(30));
    expect(
      core.snapshot.recentSamples.every((sample) => sample.exported),
      isTrue,
    );

    await core.dispose();
    await tempDir.delete(recursive: true);
  });
}

FrameSnapshot _bgraSnapshot({required int width, required int height}) {
  final bytes = Uint8List(width * height * 4);
  for (var index = 0; index < width * height; index += 1) {
    final offset = index * 4;
    bytes[offset] = 0x24;
    bytes[offset + 1] = 0x9A;
    bytes[offset + 2] = 0xE4;
    bytes[offset + 3] = 0xFF;
  }

  return FrameSnapshot(
    width: width,
    height: height,
    pixelFormat: FramePixelFormat.bgra8888,
    planes: [
      FramePlaneData(bytes: bytes, bytesPerRow: width * 4, bytesPerPixel: 4),
    ],
  );
}
