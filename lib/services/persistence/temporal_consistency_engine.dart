import '../../models/bounding_box.dart';
import '../../models/frame_context.dart';
import '../../models/persistence_models.dart';
import '../../models/tracked_entity.dart';

class TemporalConsistencyEngine {
  const TemporalConsistencyEngine();

  double score({
    required TrackedEntity entity,
    required FaceEmbeddingRecord record,
    required FrameContext frame,
    required double embeddingSimilarity,
    required bool enableTemporalPersistence,
  }) {
    final timeGap = frame.timestamp.difference(record.lastSeenAt);
    final agePenalty = (timeGap.inMilliseconds / 6000).clamp(0.0, 1.0).toDouble();
    final distance = record.lastBoundingBox.normalizedCenterDistance(
      entity.boundingBox,
      frame.sourceSize,
    );
    final sizeDelta = record.lastBoundingBox.sizeDelta(entity.boundingBox);
    final motionScore = (1 - distance.clamp(0.0, 1.0).toDouble()) * 0.45;
    final sizeScore = (1 - sizeDelta.clamp(0.0, 1.0).toDouble()) * 0.15;
    final trackerScore = entity.confidence.clamp(0.0, 1.0).toDouble() * 0.1;
    final correctionScore = (record.correctionCount / 10).clamp(0.0, 0.1).toDouble();
    final temporalScore = enableTemporalPersistence
        ? ((1 - agePenalty) * 0.2) + motionScore + sizeScore
        : 0.0;
    final combined = (embeddingSimilarity * 0.45) +
        temporalScore +
        trackerScore +
        correctionScore;
    return combined.clamp(0.0, 1.0).toDouble();
  }

  BoundingBox mixBoundingBoxes(BoundingBox current, BoundingBox previous) {
    return BoundingBox(
      left: ((current.left * 0.7) + (previous.left * 0.3)).toDouble(),
      top: ((current.top * 0.7) + (previous.top * 0.3)).toDouble(),
      width: ((current.width * 0.7) + (previous.width * 0.3)).toDouble(),
      height: ((current.height * 0.7) + (previous.height * 0.3)).toDouble(),
    );
  }
}
