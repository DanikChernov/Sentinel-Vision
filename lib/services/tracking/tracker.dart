import '../../models/detection_result.dart';
import '../../models/frame_context.dart';
import '../../models/tracked_entity.dart';

abstract interface class Tracker {
  List<TrackedEntity> update(
    List<DetectionResult> detections,
    FrameContext frame,
  );

  void reset();
}
