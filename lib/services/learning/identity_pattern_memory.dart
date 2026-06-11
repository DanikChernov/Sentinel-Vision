import 'dart:math' as math;
import 'dart:ui';

import '../../models/bounding_box.dart';
import '../../models/frame_context.dart';
import '../../models/learning_models.dart';
import '../../models/tracked_entity.dart';

class IdentityPatternMemory {
  final Map<String, LearnedIdentitySummary> _patterns =
      <String, LearnedIdentitySummary>{};
  final Map<String, Offset> _lastCenters = <String, Offset>{};

  Iterable<LearnedIdentitySummary> get identities => _patterns.values;

  void seed(Iterable<LearnedIdentitySummary> identities) {
    _patterns
      ..clear()
      ..addEntries(
        identities.map((identity) => MapEntry(identity.stableLabel, identity)),
      );
    _lastCenters
      ..clear()
      ..addEntries(
        identities.map(
          (identity) => MapEntry(
            identity.stableLabel,
            Offset(identity.averageCenterX, identity.averageCenterY),
          ),
        ),
      );
  }

  LearnedIdentitySummary? summaryFor(String stableLabel) =>
      _patterns[stableLabel];

  LearnedIdentitySummary observeEntity(
    TrackedEntity entity,
    FrameContext frame,
  ) {
    final existing = _patterns[entity.stableLabel];
    final nextSightings = (existing?.sightings ?? 0) + 1;
    final detectorConfidence = entity.detectorConfidence ?? entity.confidence;
    final previousCenter = _lastCenters[entity.stableLabel];
    final motion = previousCenter == null
        ? 0.0
        : _normalizedDistance(
            previousCenter,
            entity.boundingBox.center,
            frame.sourceSize,
          );

    final updated = LearnedIdentitySummary(
      stableLabel: entity.stableLabel,
      classLabel: entity.classLabel,
      preferredAlias: existing?.preferredAlias,
      sightings: nextSightings,
      recoveries:
          (existing?.recoveries ?? 0) + (entity.recoveredInFrame ? 1 : 0),
      correctionCount: math.max(
        existing?.correctionCount ?? 0,
        entity.correctionCount,
      ),
      averageDetectorConfidence: _rollingAverage(
        existing?.averageDetectorConfidence ?? detectorConfidence,
        detectorConfidence,
        nextSightings,
      ),
      learnedConfidence: 0,
      averageWidth: _rollingAverage(
        existing?.averageWidth ?? entity.boundingBox.width,
        entity.boundingBox.width,
        nextSightings,
      ),
      averageHeight: _rollingAverage(
        existing?.averageHeight ?? entity.boundingBox.height,
        entity.boundingBox.height,
        nextSightings,
      ),
      averageCenterX: _rollingAverage(
        existing?.averageCenterX ?? entity.boundingBox.center.dx,
        entity.boundingBox.center.dx,
        nextSightings,
      ),
      averageCenterY: _rollingAverage(
        existing?.averageCenterY ?? entity.boundingBox.center.dy,
        entity.boundingBox.center.dy,
        nextSightings,
      ),
      averageMotion: _rollingAverage(
        existing?.averageMotion ?? motion,
        motion,
        nextSightings,
      ),
      lastSeenAt: frame.timestamp,
      lastSourceType: frame.sourceType,
    );

    final learnedConfidence = scoreEntity(entity, updated, frame);
    final finalized = updated.copyWith(learnedConfidence: learnedConfidence);
    _patterns[entity.stableLabel] = finalized;
    _lastCenters[entity.stableLabel] = entity.boundingBox.center;
    return finalized;
  }

  LearnedIdentitySummary reinforceAlias(
    String stableLabel,
    String alias, {
    DateTime? correctedAt,
  }) {
    final existing = _patterns[stableLabel];
    final now = correctedAt ?? DateTime.now();
    final updated =
        (existing ??
                LearnedIdentitySummary(
                  stableLabel: stableLabel,
                  classLabel: 'object',
                  preferredAlias: alias,
                  sightings: 0,
                  recoveries: 0,
                  correctionCount: 0,
                  averageDetectorConfidence: 0.5,
                  learnedConfidence: 0.5,
                  averageWidth: 0,
                  averageHeight: 0,
                  averageCenterX: 0,
                  averageCenterY: 0,
                  averageMotion: 0,
                  lastSeenAt: now,
                ))
            .copyWith(
              preferredAlias: alias,
              correctionCount: (existing?.correctionCount ?? 0) + 1,
              learnedConfidence: ((existing?.learnedConfidence ?? 0.5) + 0.1)
                  .clamp(0.0, 0.99)
                  .toDouble(),
              lastSeenAt: now,
            );

    _patterns[stableLabel] = updated;
    return updated;
  }

  double scoreEntity(
    TrackedEntity entity,
    LearnedIdentitySummary summary,
    FrameContext frame,
  ) {
    final averageBox = BoundingBox(
      left: summary.averageCenterX - (summary.averageWidth / 2),
      top: summary.averageCenterY - (summary.averageHeight / 2),
      width: summary.averageWidth,
      height: summary.averageHeight,
    );
    final positionScore =
        1 -
        averageBox.normalizedCenterDistance(
          entity.boundingBox,
          frame.sourceSize,
        );
    final sizeScore = 1 - averageBox.sizeDelta(entity.boundingBox);
    final lastCenter = _lastCenters[entity.stableLabel];
    final motion = lastCenter == null
        ? 0.0
        : _normalizedDistance(
            lastCenter,
            entity.boundingBox.center,
            frame.sourceSize,
          );
    final motionScore =
        1 - (summary.averageMotion - motion).abs().clamp(0.0, 1.0);
    final timeGapSeconds =
        frame.timestamp.difference(summary.lastSeenAt).inMilliseconds / 1000.0;
    final timeGapScore = 1 - (timeGapSeconds / 12).clamp(0.0, 1.0);

    final score =
        0.28 +
        (positionScore.clamp(0.0, 1.0) * 0.18) +
        (sizeScore.clamp(0.0, 1.0) * 0.14) +
        (motionScore.clamp(0.0, 1.0) * 0.1) +
        (timeGapScore.toDouble() * 0.1) +
        math.min(0.16, summary.sightings * 0.025) +
        math.min(0.12, summary.recoveries * 0.04) +
        math.min(0.12, summary.correctionCount * 0.05);

    return score.clamp(0.0, 0.99).toDouble();
  }

  double _rollingAverage(double currentAverage, double nextValue, int count) {
    if (count <= 1) {
      return nextValue;
    }
    return ((currentAverage * (count - 1)) + nextValue) / count;
  }

  double _normalizedDistance(Offset a, Offset b, Size size) {
    final delta = a - b;
    final diagonal = math.sqrt(
      (size.width * size.width) + (size.height * size.height),
    );
    if (diagonal == 0) {
      return 0;
    }
    return delta.distance / diagonal;
  }
}
