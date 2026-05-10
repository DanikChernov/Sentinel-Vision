import 'dart:math' as math;

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image/image.dart' as img;

import '../../models/bounding_box.dart';
import '../../models/frame_context.dart';
import '../../models/tracked_entity.dart';
import '../camera/frame_image_utils.dart';
import 'semantic_labeler.dart';

class MlKitSemanticLabeler extends SemanticLabeler {
  MlKitSemanticLabeler({
    this.confidenceThreshold = 0.6,
    this.cacheTtl = const Duration(seconds: 2),
    this.maxFreshLabelsPerFrame = 2,
  });

  final double confidenceThreshold;
  final Duration cacheTtl;
  final int maxFreshLabelsPerFrame;

  ImageLabeler? _labeler;
  final Map<String, _CachedSemanticLabel> _cache = <String, _CachedSemanticLabel>{};

  @override
  String get labelerName => 'ML Kit Image Labeler';

  @override
  Future<void> initialize() async {
    _labeler ??= ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: confidenceThreshold),
    );
  }

  @override
  Future<void> dispose() async {
    final labeler = _labeler;
    _labeler = null;
    _cache.clear();
    if (labeler != null) {
      await labeler.close();
    }
  }

  @override
  Future<List<TrackedEntity>> refine(
    List<TrackedEntity> tracks,
    FrameContext frame,
  ) async {
    await initialize();
    final labeler = _labeler;
    if (labeler == null || tracks.isEmpty) {
      return tracks;
    }

    final frameImage = FrameImageUtils.decodeFrame(frame);
    if (frameImage == null) {
      return tracks;
    }

    var labelingBudget = maxFreshLabelsPerFrame;
    final updatedTracks = <TrackedEntity>[];

    for (final track in tracks) {
      final cached = _cache[track.stableLabel];
      if (!_shouldLabel(track, frameImage)) {
        updatedTracks.add(
          cached == null
              ? track
              : track.copyWith(semanticLabel: cached.label),
        );
        continue;
      }

      if (_canReuseCache(cached, track, frame.timestamp)) {
        updatedTracks.add(track.copyWith(semanticLabel: cached!.label));
        continue;
      }

      if (labelingBudget <= 0) {
        updatedTracks.add(
          cached == null
              ? track
              : track.copyWith(semanticLabel: cached.label),
        );
        continue;
      }

      labelingBudget -= 1;
      final cropped = FrameImageUtils.cropBoundingBox(
        image: frameImage,
        boundingBox: track.boundingBox,
      );
      if (cropped == null) {
        updatedTracks.add(track);
        continue;
      }

      final label = await _labelCrop(
        labeler: labeler,
        crop: _resizeForLabeling(cropped),
        classLabel: track.classLabel,
      );
      if (label == null) {
        updatedTracks.add(
          cached == null
              ? track
              : track.copyWith(semanticLabel: cached.label),
        );
        continue;
      }

      _cache[track.stableLabel] = _CachedSemanticLabel(
        label: label,
        observedAt: frame.timestamp,
        boundingBox: track.boundingBox,
      );
      updatedTracks.add(track.copyWith(semanticLabel: label));
    }

    return updatedTracks;
  }

  bool _shouldLabel(TrackedEntity track, img.Image frameImage) {
    if (!track.isVisible) {
      return false;
    }
    if (track.boundingBox.width < 18 || track.boundingBox.height < 18) {
      return false;
    }
    return track.boundingBox.area >= frameImage.width * frameImage.height * 0.002;
  }

  bool _canReuseCache(
    _CachedSemanticLabel? cached,
    TrackedEntity track,
    DateTime timestamp,
  ) {
    if (cached == null) {
      return false;
    }
    if (timestamp.difference(cached.observedAt) > cacheTtl) {
      return false;
    }
    return cached.boundingBox.intersectionOverUnion(track.boundingBox) >= 0.55;
  }

  img.Image _resizeForLabeling(img.Image crop) {
    const maxEdge = 320;
    if (crop.width <= maxEdge && crop.height <= maxEdge) {
      return crop;
    }

    final scale = maxEdge / math.max(crop.width, crop.height);
    return img.copyResize(
      crop,
      width: (crop.width * scale).round(),
      height: (crop.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  Future<String?> _labelCrop({
    required ImageLabeler labeler,
    required img.Image crop,
    required String classLabel,
  }) async {
    final inputImage = InputImage.fromBitmap(
      bitmap: FrameImageUtils.rgbaBytes(crop),
      width: crop.width,
      height: crop.height,
    );
    final labels = await labeler.processImage(inputImage);
    if (labels.isEmpty) {
      return null;
    }

    final normalizedClassLabel = classLabel.trim().toLowerCase();
    for (final label in labels) {
      final normalized = label.label.trim().toLowerCase();
      if (normalized.isEmpty || normalized == normalizedClassLabel) {
        continue;
      }
      return normalized;
    }

    return labels.first.label.trim().toLowerCase();
  }
}

class _CachedSemanticLabel {
  const _CachedSemanticLabel({
    required this.label,
    required this.observedAt,
    required this.boundingBox,
  });

  final String label;
  final DateTime observedAt;
  final BoundingBox boundingBox;
}
