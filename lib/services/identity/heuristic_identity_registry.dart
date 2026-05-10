import '../../models/frame_context.dart';
import '../../models/identity_profile.dart';
import '../../models/pipeline_event.dart';
import '../../models/tracked_entity.dart';
import 'identity_registry.dart';

class HeuristicIdentityRegistry implements IdentityRegistry {
  final Map<String, IdentityProfile> _profiles = <String, IdentityProfile>{};
  final Map<String, String> _trackToIdentity = <String, String>{};
  final Map<String, int> _classCounters = <String, int>{};

  @override
  Iterable<IdentityProfile> get profiles => _profiles.values;

  @override
  int get knownIdentityCount => _profiles.length;

  @override
  IdentityResolution reconcile(
    List<TrackedEntity> tracks,
    FrameContext frame, {
    required Duration persistence,
  }) {
    final events = <PipelineEvent>[];
    final updatedTracks = <TrackedEntity>[];
    final liveTrackIds = tracks.map((track) => track.trackId).toSet();

    // Remove bindings for tracks that no longer exist before recovery so a
    // replacement track can reclaim the previous stable identity.
    _trackToIdentity.removeWhere((trackId, _) => !liveTrackIds.contains(trackId));

    for (final track in tracks) {
      final existingIdentityId = _trackToIdentity[track.trackId];
      if (existingIdentityId != null && _profiles.containsKey(existingIdentityId)) {
        final profile = _profiles[existingIdentityId]!;
        _profiles[existingIdentityId] = profile.copyWith(
          lastBoundingBox: track.boundingBox,
          lastSeenAt: track.lastSeenAt,
          sightings: profile.sightings + (track.isVisible ? 1 : 0),
        );
        updatedTracks.add(
          track.copyWith(
            stableLabel: existingIdentityId,
            recoveredInFrame: false,
          ),
        );
        continue;
      }

      final recoveredIdentity = _findRecoverableIdentity(
        track,
        frame,
        persistence,
      );

      if (recoveredIdentity != null) {
        final profile = _profiles[recoveredIdentity]!;
        _trackToIdentity[track.trackId] = recoveredIdentity;
        _profiles[recoveredIdentity] = profile.copyWith(
          lastBoundingBox: track.boundingBox,
          lastSeenAt: track.lastSeenAt,
          sightings: profile.sightings + 1,
          recoveries: profile.recoveries + 1,
        );
        updatedTracks.add(
          track.copyWith(
            stableLabel: recoveredIdentity,
            recoveredInFrame: true,
          ),
        );
        events.add(
          PipelineEvent(
            type: PipelineEventType.identityRecovered,
            message: 'Recovered $recoveredIdentity after a short absence.',
            timestamp: frame.timestamp,
            details: <String, Object?>{'trackId': track.trackId},
          ),
        );
        continue;
      }

      final identityId = _allocateIdentityId(track.classLabel);
      _trackToIdentity[track.trackId] = identityId;
      _profiles[identityId] = IdentityProfile(
        id: identityId,
        classLabel: track.classLabel,
        lastBoundingBox: track.boundingBox,
        firstSeenAt: track.firstSeenAt,
        lastSeenAt: track.lastSeenAt,
        sightings: 1,
        recoveries: 0,
      );
      updatedTracks.add(track.copyWith(stableLabel: identityId));
      events.add(
        PipelineEvent(
          type: PipelineEventType.identityAssigned,
          message: 'Assigned new identity $identityId.',
          timestamp: frame.timestamp,
          details: <String, Object?>{'trackId': track.trackId},
        ),
      );
    }
    return IdentityResolution(tracks: updatedTracks, events: events);
  }

  String? _findRecoverableIdentity(
    TrackedEntity track,
    FrameContext frame,
    Duration persistence,
  ) {
    String? bestIdentity;
    double bestScore = 0;

    for (final profile in _profiles.values) {
      if (profile.classLabel != track.classLabel) {
        continue;
      }
      if (_trackToIdentity.containsValue(profile.id)) {
        continue;
      }

      final age = frame.timestamp.difference(profile.lastSeenAt);
      if (age > persistence) {
        continue;
      }

      final distance = profile.lastBoundingBox.normalizedCenterDistance(
        track.boundingBox,
        frame.sourceSize,
      );
      final sizeDelta = profile.lastBoundingBox.sizeDelta(track.boundingBox);
      final score = ((1 - distance.clamp(0.0, 1.0).toDouble()) * 0.65) +
          ((1 - sizeDelta.clamp(0.0, 1.0).toDouble()) * 0.25) +
          ((1 -
                      (age.inMilliseconds / persistence.inMilliseconds)
                          .clamp(0.0, 1.0)
                          .toDouble()) *
                  0.1);

      if (score > bestScore && score >= 0.45) {
        bestScore = score;
        bestIdentity = profile.id;
      }
    }

    return bestIdentity;
  }

  String _allocateIdentityId(String classLabel) {
    final nextValue = (_classCounters[classLabel] ?? 0) + 1;
    _classCounters[classLabel] = nextValue;
    return '$classLabel-${nextValue.toString().padLeft(3, '0')}';
  }

  @override
  void reset() {
    _profiles.clear();
    _trackToIdentity.clear();
    _classCounters.clear();
  }
}
