import '../../models/frame_context.dart';
import '../../models/identity_profile.dart';
import '../../models/pipeline_event.dart';
import '../../models/tracked_entity.dart';

class IdentityResolution {
  const IdentityResolution({
    required this.tracks,
    required this.events,
  });

  final List<TrackedEntity> tracks;
  final List<PipelineEvent> events;
}

abstract interface class IdentityRegistry {
  Iterable<IdentityProfile> get profiles;

  int get knownIdentityCount;

  IdentityResolution reconcile(
    List<TrackedEntity> tracks,
    FrameContext frame, {
    required Duration persistence,
  });

  void reset();
}
