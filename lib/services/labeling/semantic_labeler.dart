import '../../models/frame_context.dart';
import '../../models/tracked_entity.dart';

abstract class SemanticLabeler {
  String get labelerName;

  Future<void> initialize() async {}

  Future<void> dispose() async {}

  Future<List<TrackedEntity>> refine(
    List<TrackedEntity> tracks,
    FrameContext frame,
  );
}
