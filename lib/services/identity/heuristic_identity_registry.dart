import 'dart:math' as math;

import '../../models/frame_context.dart';
import '../../models/identity_profile.dart';
import '../../models/pipeline_event.dart';
import '../../models/tracked_entity.dart';
import 'identity_registry.dart';

class HeuristicIdentityRegistry implements IdentityRegistry {
  final Map<String, IdentityProfile> _profiles = <String, IdentityProfile>{};
  final Map<String, String> _trackToIdentity = <String, String>{};
  final Map<String, int> _classCounters = <String, int>{};

  int _matchesAttempted = 0;
  int _matchesAccepted = 0;
  int _identityRecoveries = 0;
  int _identitySwitches = 0;
  double _scoreTotal = 0;
  IdentityMatchScore? _lastMatchScore;
  String _lastMatchReason = 'idle';

  @override
  Iterable<IdentityProfile> get profiles => _profiles.values;

  @override
  int get knownIdentityCount => _profiles.length;

  @override
  IdentityRegistryDiagnostics get diagnostics {
    return IdentityRegistryDiagnostics(
      persistentEntitiesStored: _profiles.length,
      matchesAttempted: _matchesAttempted,
      matchesAccepted: _matchesAccepted,
      identityRecoveries: _identityRecoveries,
      identitySwitches: _identitySwitches,
      averageFinalScore: _matchesAttempted == 0
          ? 0
          : _scoreTotal / _matchesAttempted,
      lastMatchReason: _lastMatchReason,
      lastMatchScore: _lastMatchScore,
    );
  }

  @override
  IdentityResolution reconcile(
    List<TrackedEntity> tracks,
    FrameContext frame, {
    required Duration persistence,
    double confidenceThreshold = 0.45,
  }) {
    final events = <PipelineEvent>[];
    final updatedTracks = <TrackedEntity>[];
    final currentTrackIds = tracks.map((track) => track.trackId).toSet();
    final visibleBoundIdentityIds = tracks
        .where((track) => track.isVisible)
        .map((track) => _trackToIdentity[track.trackId])
        .whereType<String>()
        .toSet();

    // Remove bindings for tracks that no longer exist before recovery so a
    // replacement track can reclaim the previous persistent entity.
    _trackToIdentity.removeWhere(
      (trackId, _) => !currentTrackIds.contains(trackId),
    );

    for (final track in tracks) {
      final existingIdentityId = _trackToIdentity[track.trackId];
      if (existingIdentityId != null &&
          _profiles.containsKey(existingIdentityId)) {
        final profile = _profiles[existingIdentityId]!;
        _profiles[existingIdentityId] = profile.copyWith(
          lastBoundingBox: track.boundingBox,
          lastSeenAt: track.lastSeenAt,
          sightings: profile.sightings + (track.isVisible ? 1 : 0),
        );
        updatedTracks.add(
          track.copyWith(
            stableLabel: existingIdentityId,
            persistentEntityId: existingIdentityId,
            recoveredInFrame: false,
          ),
        );
        continue;
      }

      if (!track.isVisible) {
        updatedTracks.add(track);
        continue;
      }

      final recovered = _findRecoverableIdentity(
        track: track,
        frame: frame,
        persistence: persistence,
        confidenceThreshold: confidenceThreshold,
        blockedIdentityIds: visibleBoundIdentityIds,
      );

      if (recovered != null) {
        final profile = _profiles[recovered.identityId]!;
        _trackToIdentity[track.trackId] = recovered.identityId;
        _profiles[recovered.identityId] = profile.copyWith(
          lastBoundingBox: track.boundingBox,
          lastSeenAt: track.lastSeenAt,
          sightings: profile.sightings + 1,
          recoveries: profile.recoveries + 1,
        );
        _matchesAccepted += 1;
        _identityRecoveries += 1;
        updatedTracks.add(
          track.copyWith(
            stableLabel: recovered.identityId,
            persistentEntityId: recovered.identityId,
            identityConfidence: recovered.score.finalScore,
            recoveredInFrame: true,
          ),
        );
        events.add(
          PipelineEvent(
            type: PipelineEventType.identityRecovered,
            message: 'Recovered ${recovered.identityId} after a short absence.',
            timestamp: frame.timestamp,
            details: <String, Object?>{
              'trackId': track.trackId,
              'finalScore': recovered.score.finalScore,
              'reason': recovered.score.reason,
            },
          ),
        );
        continue;
      }

      final identityId = _allocateIdentityId(track.effectiveClassLabel);
      _trackToIdentity[track.trackId] = identityId;
      _profiles[identityId] = IdentityProfile(
        id: identityId,
        classLabel: track.effectiveClassLabel,
        lastBoundingBox: track.boundingBox,
        firstSeenAt: track.firstSeenAt,
        lastSeenAt: track.lastSeenAt,
        sightings: 1,
        recoveries: 0,
      );
      updatedTracks.add(
        track.copyWith(
          stableLabel: identityId,
          persistentEntityId: identityId,
          identityConfidence: math.max(track.identityConfidence ?? 0, 0.5),
        ),
      );
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

  _RecoveredIdentity? _findRecoverableIdentity({
    required TrackedEntity track,
    required FrameContext frame,
    required Duration persistence,
    required double confidenceThreshold,
    required Set<String> blockedIdentityIds,
  }) {
    _RecoveredIdentity? best;

    for (final profile in _profiles.values) {
      if (blockedIdentityIds.contains(profile.id)) {
        continue;
      }

      final score = _scoreCandidate(
        track: track,
        profile: profile,
        frame: frame,
        persistence: persistence,
        confidenceThreshold: confidenceThreshold,
      );
      _matchesAttempted += 1;
      _scoreTotal += score.finalScore;
      _lastMatchScore = score;
      _lastMatchReason = score.reason;

      if (!score.accepted) {
        continue;
      }
      if (best == null || score.finalScore > best.score.finalScore) {
        best = _RecoveredIdentity(identityId: profile.id, score: score);
      }
    }

    return best;
  }

  IdentityMatchScore _scoreCandidate({
    required TrackedEntity track,
    required IdentityProfile profile,
    required FrameContext frame,
    required Duration persistence,
    required double confidenceThreshold,
  }) {
    final classMatches = profile.classLabel == track.effectiveClassLabel;
    if (!classMatches) {
      return const IdentityMatchScore(
        classScore: 0,
        spatialScore: 0,
        temporalScore: 0,
        sizeScore: 0,
        maskScore: 0,
        faceEmbeddingScore: 0,
        objectEmbeddingScore: 0,
        correctionScore: 0,
        finalScore: 0,
        accepted: false,
        reason: 'class mismatch',
      );
    }

    final age = frame.timestamp.difference(profile.lastSeenAt);
    if (age.isNegative || age > persistence) {
      return IdentityMatchScore(
        classScore: 1,
        spatialScore: 0,
        temporalScore: 0,
        sizeScore: 0,
        maskScore: 0,
        faceEmbeddingScore: 0,
        objectEmbeddingScore: 0,
        correctionScore: 0,
        finalScore: 0,
        accepted: false,
        reason: 'outside memory timeout',
      );
    }

    final iou = profile.lastBoundingBox.intersectionOverUnion(
      track.boundingBox,
    );
    final distance = profile.lastBoundingBox.normalizedCenterDistance(
      track.boundingBox,
      frame.sourceSize,
    );
    final sizeDelta = profile.lastBoundingBox.sizeDelta(track.boundingBox);
    final spatialScore =
        ((iou * 0.55) + ((1 - distance.clamp(0.0, 1.0).toDouble()) * 0.45))
            .clamp(0.0, 1.0)
            .toDouble();
    final sizeScore = (1 - sizeDelta.clamp(0.0, 1.0).toDouble())
        .clamp(0.0, 1.0)
        .toDouble();
    final timeoutMs = math.max(1, persistence.inMilliseconds);
    final temporalScore =
        (1 - (age.inMilliseconds / timeoutMs).clamp(0.0, 1.0).toDouble())
            .clamp(0.0, 1.0)
            .toDouble();
    final correctionScore = track.learnedLabel == null ? 0.0 : 0.15;
    final finalScore =
        ((1.0 * 0.25) +
                (spatialScore * 0.42) +
                (temporalScore * 0.18) +
                (sizeScore * 0.15) +
                correctionScore)
            .clamp(0.0, 1.0)
            .toDouble();
    final accepted = finalScore >= confidenceThreshold;

    return IdentityMatchScore(
      classScore: 1,
      spatialScore: spatialScore,
      temporalScore: temporalScore,
      sizeScore: sizeScore,
      maskScore: 0,
      faceEmbeddingScore: 0,
      objectEmbeddingScore: 0,
      correctionScore: correctionScore,
      finalScore: finalScore,
      accepted: accepted,
      reason: accepted
          ? 'class/spatial/size/time match'
          : 'score below threshold',
    );
  }

  String _allocateIdentityId(String classLabel) {
    final normalized = classLabel.trim().isEmpty ? 'unknown' : classLabel;
    final nextValue = (_classCounters[normalized] ?? 0) + 1;
    _classCounters[normalized] = nextValue;
    return '$normalized-${nextValue.toString().padLeft(3, '0')}';
  }

  @override
  void reset() {
    _profiles.clear();
    _trackToIdentity.clear();
    _classCounters.clear();
    _matchesAttempted = 0;
    _matchesAccepted = 0;
    _identityRecoveries = 0;
    _identitySwitches = 0;
    _scoreTotal = 0;
    _lastMatchScore = null;
    _lastMatchReason = 'idle';
  }
}

class _RecoveredIdentity {
  const _RecoveredIdentity({required this.identityId, required this.score});

  final String identityId;
  final IdentityMatchScore score;
}
