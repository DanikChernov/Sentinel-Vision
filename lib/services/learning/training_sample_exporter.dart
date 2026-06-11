import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../models/frame_context.dart';
import '../../models/learning_models.dart';
import '../../models/tracked_entity.dart';
import '../camera/frame_image_utils.dart';
import '../orchestrator/perception_result.dart';
import 'usage_memory_store.dart';

class TrainingSampleExporter {
  Future<TrainingSampleRecord?> captureSample({
    required FrameContext frame,
    required TrackedEntity entity,
    required UsageMemoryStore store,
  }) async {
    final decoded = FrameImageUtils.decodeFrame(frame);
    if (decoded == null) {
      return null;
    }

    final cropped = FrameImageUtils.cropBoundingBox(
      image: decoded,
      boundingBox: entity.boundingBox,
    );
    if (cropped == null) {
      return null;
    }

    final fileName =
        '${_sanitizeForFileName(entity.stableLabel)}_${frame.timestamp.millisecondsSinceEpoch}.png';
    final cropFile = File(p.join((await store.cropDirectory).path, fileName));
    await cropFile.writeAsBytes(img.encodePng(cropped), flush: true);

    final sample = TrainingSampleRecord(
      cropPath: cropFile.path,
      originalLabel: entity.classLabel,
      correctedLabel: entity.learnedLabel,
      stableLabel: entity.stableLabel,
      confidence: entity.displayConfidence,
      timestamp: frame.timestamp,
      boundingBox: entity.boundingBox,
      sourceType: frame.sourceType,
      feedbackApplied: entity.learnedLabel != null,
    );

    return store.saveTrainingSample(sample);
  }

  Future<String> exportDataset({
    required UsageMemoryStore store,
    required List<TrainingSampleRecord> samples,
    PerceptionResult? perceptionResult,
  }) async {
    final exportRoot = await store.exportDirectory;
    final exportPath = p.join(
      exportRoot.path,
      'dataset_${DateTime.now().millisecondsSinceEpoch}',
    );
    final exportDir = Directory(exportPath);
    await exportDir.create(recursive: true);
    final cropsDir = Directory(p.join(exportDir.path, 'crops'));
    await cropsDir.create(recursive: true);

    final manifest = <Map<String, Object?>>[];
    final exportedIds = <int>[];

    for (final sample in samples) {
      final sourceFile = File(sample.cropPath);
      String? exportedCropPath;
      if (await sourceFile.exists()) {
        final targetName = p.basename(sample.cropPath);
        final targetFile = File(p.join(cropsDir.path, targetName));
        await sourceFile.copy(targetFile.path);
        exportedCropPath = p.join('crops', targetName);
      }

      manifest.add(<String, Object?>{
        'id': sample.id,
        'crop_path': exportedCropPath,
        'original_label': sample.originalLabel,
        'corrected_label': sample.correctedLabel,
        'stable_label': sample.stableLabel,
        'confidence': sample.confidence,
        'timestamp': sample.timestamp.toIso8601String(),
        'source_type': sample.sourceType.name,
        'bounding_box': sample.boundingBox.toJson(),
        'feedback_applied': sample.feedbackApplied,
        'identity_id': sample.stableLabel,
      });

      if (sample.id != null) {
        exportedIds.add(sample.id!);
      }
    }

    final manifestFile = File(p.join(exportDir.path, 'training_samples.json'));
    const encoder = JsonEncoder.withIndent('  ');
    await manifestFile.writeAsString(encoder.convert(manifest), flush: true);

    if (perceptionResult != null) {
      final metadataFile = File(
        p.join(exportDir.path, 'perception_metadata.json'),
      );
      await metadataFile.writeAsString(
        encoder.convert(_perceptionMetadata(perceptionResult)),
        flush: true,
      );
    }

    if (exportedIds.isNotEmpty) {
      await store.markTrainingSamplesExported(exportedIds);
    }

    return exportDir.path;
  }

  Map<String, Object?> _perceptionMetadata(PerceptionResult result) {
    return <String, Object?>{
      'frame_id': result.frameId,
      'timestamp': result.timestamp.toIso8601String(),
      'detections': result.detections
          .map((detection) {
            return <String, Object?>{
              'id': detection.id,
              'label': detection.classLabel,
              'confidence': detection.confidence,
              'bounding_box': detection.boundingBox.toJson(),
            };
          })
          .toList(growable: false),
      'segmentations': result.segmentations
          .map((segmentation) {
            return <String, Object?>{
              'id': segmentation.segmentationId,
              'label': segmentation.classLabel,
              'confidence': segmentation.confidence,
              'bounding_box': segmentation.boundingBox.toJson(),
              'mask_area': segmentation.maskArea,
              'polygon': segmentation.polygonPoints
                  .map(
                    (point) => <String, double>{'x': point.dx, 'y': point.dy},
                  )
                  .toList(growable: false),
              'track_id': segmentation.associatedTrackId,
              'refined': segmentation.refined,
            };
          })
          .toList(growable: false),
      'identities': result.identities
          .map((identity) {
            return <String, Object?>{
              'track_id': identity.trackId,
              'persistent_entity_id': identity.persistentEntityId,
              'display_label': identity.displayLabel,
              'confidence': identity.confidence,
              'reason_breakdown': identity.reasonBreakdown,
            };
          })
          .toList(growable: false),
      'poses': result.poses
          .map((pose) {
            return <String, Object?>{
              'id': pose.poseId,
              'track_id': pose.associatedTrackId,
              'confidence': pose.confidence,
              'keypoints': pose.keypoints
                  .map((keypoint) {
                    return <String, Object?>{
                      'label': keypoint.label,
                      'x': keypoint.position.dx,
                      'y': keypoint.position.dy,
                      'confidence': keypoint.confidence,
                    };
                  })
                  .toList(growable: false),
            };
          })
          .toList(growable: false),
      'depth': result.depth == null
          ? null
          : <String, Object?>{
              'map_width': result.depth!.mapSize.width,
              'map_height': result.depth!.mapSize.height,
              'entity_depths': result.depth!.entityDepths
                  .map((depth) {
                    return <String, Object?>{
                      'track_id': depth.trackId,
                      'relative_depth': depth.relativeDepth,
                      'confidence': depth.confidence,
                    };
                  })
                  .toList(growable: false),
            },
      'scene_context': result.sceneContext == null
          ? null
          : <String, Object?>{
              'labels': result.sceneContext!.labels,
              'confidence': result.sceneContext!.contextConfidence,
              'risk_hints': result.sceneContext!.riskHints,
              'interaction_hints': result.sceneContext!.interactionHints,
              'summary': result.sceneContext!.summary,
            },
    };
  }

  String _sanitizeForFileName(String input) {
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }
}
