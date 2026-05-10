import '../../models/detection_result.dart';
import '../../models/frame_context.dart';
import '../../models/tracked_entity.dart';
import 'tracker.dart';

class HeuristicTracker implements Tracker {
  HeuristicTracker({
    this.maxMissedFrames = 8,
    this.minimumAssociationScore = 0.28,
  });

  final int maxMissedFrames;
  final double minimumAssociationScore;

  final Map<String, TrackedEntity> _activeTracks = <String, TrackedEntity>{};
  int _nextTrackId = 1;

  @override
  List<TrackedEntity> update(List<DetectionResult> detections, FrameContext frame) {
    final detectionPool = <int, DetectionResult>{
      for (var i = 0; i < detections.length; i += 1) i: detections[i],
    };
    final updatedTracks = <String, TrackedEntity>{};

    for (final track in _activeTracks.values) {
      int? bestIndex;
      double bestScore = 0;

      for (final entry in detectionPool.entries) {
        final detection = entry.value;
        if (detection.classLabel != track.classLabel) {
          continue;
        }

        final iou = track.boundingBox.intersectionOverUnion(detection.boundingBox);
        final distance = track.boundingBox.normalizedCenterDistance(
          detection.boundingBox,
          frame.sourceSize,
        );
        final sizeDelta = track.boundingBox.sizeDelta(detection.boundingBox);
        final score = (iou * 0.6) +
            ((1 - distance.clamp(0.0, 1.0).toDouble()) * 0.3) +
            ((1 - sizeDelta.clamp(0.0, 1.0).toDouble()) * 0.1);

        if (score > bestScore) {
          bestScore = score;
          bestIndex = entry.key;
        }
      }

      if (bestIndex != null && bestScore >= minimumAssociationScore) {
        final match = detectionPool.remove(bestIndex)!;
        updatedTracks[track.trackId] = track.copyWith(
          boundingBox: match.boundingBox,
          confidence: match.confidence,
          detectorConfidence: match.confidence,
          lastSeenAt: match.timestamp,
          missedFrames: 0,
          isVisible: true,
          recoveredInFrame: false,
        );
      } else {
        final missed = track.missedFrames + 1;
        if (missed <= maxMissedFrames) {
          updatedTracks[track.trackId] = track.copyWith(
            missedFrames: missed,
            isVisible: false,
            recoveredInFrame: false,
          );
        }
      }
    }

    for (final detection in detectionPool.values) {
      final trackId = 'track-${_nextTrackId.toString().padLeft(3, '0')}';
      _nextTrackId += 1;
      updatedTracks[trackId] = TrackedEntity(
        trackId: trackId,
        stableLabel: trackId,
        classLabel: detection.classLabel,
        boundingBox: detection.boundingBox,
        confidence: detection.confidence,
        detectorConfidence: detection.confidence,
        firstSeenAt: detection.timestamp,
        lastSeenAt: detection.timestamp,
      );
    }

    _activeTracks
      ..clear()
      ..addAll(updatedTracks);

    final sortedTracks = updatedTracks.values.toList()
      ..sort((a, b) => a.trackId.compareTo(b.trackId));
    return sortedTracks;
  }

  @override
  void reset() {
    _activeTracks.clear();
    _nextTrackId = 1;
  }
}
