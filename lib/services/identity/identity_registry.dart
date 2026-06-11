import '../../models/frame_context.dart';
import '../../models/identity_profile.dart';
import '../../models/pipeline_event.dart';
import '../../models/tracked_entity.dart';

class IdentityMatchScore {
  const IdentityMatchScore({
    required this.classScore,
    required this.spatialScore,
    required this.temporalScore,
    required this.sizeScore,
    required this.maskScore,
    required this.faceEmbeddingScore,
    required this.objectEmbeddingScore,
    required this.correctionScore,
    required this.finalScore,
    required this.accepted,
    required this.reason,
  });

  final double classScore;
  final double spatialScore;
  final double temporalScore;
  final double sizeScore;
  final double maskScore;
  final double faceEmbeddingScore;
  final double objectEmbeddingScore;
  final double correctionScore;
  final double finalScore;
  final bool accepted;
  final String reason;

  Map<String, double> toBreakdown() {
    return <String, double>{
      'class': classScore,
      'spatial': spatialScore,
      'temporal': temporalScore,
      'size': sizeScore,
      'mask': maskScore,
      'faceEmbedding': faceEmbeddingScore,
      'objectEmbedding': objectEmbeddingScore,
      'correction': correctionScore,
      'final': finalScore,
    };
  }
}

class IdentityRegistryDiagnostics {
  const IdentityRegistryDiagnostics({
    this.persistentEntitiesStored = 0,
    this.matchesAttempted = 0,
    this.matchesAccepted = 0,
    this.identityRecoveries = 0,
    this.identitySwitches = 0,
    this.averageFinalScore = 0,
    this.lastMatchReason = 'idle',
    this.lastMatchScore,
  });

  final int persistentEntitiesStored;
  final int matchesAttempted;
  final int matchesAccepted;
  final int identityRecoveries;
  final int identitySwitches;
  final double averageFinalScore;
  final String lastMatchReason;
  final IdentityMatchScore? lastMatchScore;
}

class IdentityResolution {
  const IdentityResolution({required this.tracks, required this.events});

  final List<TrackedEntity> tracks;
  final List<PipelineEvent> events;
}

abstract interface class IdentityRegistry {
  Iterable<IdentityProfile> get profiles;

  int get knownIdentityCount;

  IdentityRegistryDiagnostics get diagnostics;

  IdentityResolution reconcile(
    List<TrackedEntity> tracks,
    FrameContext frame, {
    required Duration persistence,
    double confidenceThreshold = 0.45,
  });

  void reset();
}
