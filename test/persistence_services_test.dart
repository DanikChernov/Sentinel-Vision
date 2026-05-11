import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel_vision_mobile/models/bounding_box.dart';
import 'package:sentinel_vision_mobile/models/frame_context.dart';
import 'package:sentinel_vision_mobile/models/persistence_models.dart';
import 'package:sentinel_vision_mobile/models/tracked_entity.dart';
import 'package:sentinel_vision_mobile/models/video_source.dart';
import 'package:sentinel_vision_mobile/services/persistence/identity_matcher.dart';
import 'package:sentinel_vision_mobile/services/persistence/temporal_consistency_engine.dart';

void main() {
  test('identity matcher prefers the most similar stored embedding', () {
    const matcher = IdentityMatcher();

    final match = matcher.findBestMatch(
      embedding: const <double>[0.90, 0.10, 0.20, 0.30],
      records: [
        FaceEmbeddingRecord(
          stableLabel: 'person-001',
          classLabel: 'person',
          embedding: const <double>[0.91, 0.09, 0.19, 0.31],
          embeddingCount: 2,
          sightings: 3,
          recoveries: 1,
          correctionCount: 1,
          averageSimilarity: 0.88,
          averageTemporalConfidence: 0.73,
          averageFaceConfidence: 0.81,
          lastBoundingBox: const BoundingBox(
            left: 100,
            top: 80,
            width: 140,
            height: 280,
          ),
          lastSeenAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
        ),
        FaceEmbeddingRecord(
          stableLabel: 'person-002',
          classLabel: 'person',
          embedding: const <double>[0.10, 0.70, 0.30, 0.10],
          embeddingCount: 2,
          sightings: 4,
          recoveries: 2,
          correctionCount: 0,
          averageSimilarity: 0.74,
          averageTemporalConfidence: 0.65,
          averageFaceConfidence: 0.77,
          lastBoundingBox: const BoundingBox(
            left: 320,
            top: 100,
            width: 150,
            height: 300,
          ),
          lastSeenAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
        ),
      ],
      similarityThreshold: 0.7,
    );

    expect(match, isNotNull);
    expect(match!.stableLabel, 'person-001');
    expect(match.similarity, greaterThan(0.95));
  });

  test('temporal consistency rewards nearby recent embeddings', () {
    const engine = TemporalConsistencyEngine();
    final timestamp = DateTime.utc(2026, 1, 1, 12, 0, 4);
    final frame = FrameContext(
      frameNumber: 4,
      sourceSize: const Size(1280, 720),
      timestamp: timestamp,
      sourceType: VisionSourceType.camera,
    );
    final entity = TrackedEntity(
      trackId: 'track-004',
      stableLabel: 'track-004',
      classLabel: 'person',
      boundingBox: const BoundingBox(
        left: 212,
        top: 102,
        width: 158,
        height: 318,
      ),
      confidence: 0.42,
      detectorConfidence: 0.42,
      correctionCount: 0,
      firstSeenAt: timestamp,
      lastSeenAt: timestamp,
    );
    final recentRecord = FaceEmbeddingRecord(
      stableLabel: 'person-001',
      classLabel: 'person',
      embedding: const <double>[0.8, 0.2, 0.1, 0.5],
      embeddingCount: 6,
      sightings: 8,
      recoveries: 3,
      correctionCount: 0,
      averageSimilarity: 0.91,
      averageTemporalConfidence: 0.83,
      averageFaceConfidence: 0.8,
      lastBoundingBox: const BoundingBox(
        left: 208,
        top: 100,
        width: 160,
        height: 320,
      ),
      lastSeenAt: timestamp.subtract(const Duration(seconds: 1)),
      preferredAlias: 'Dan',
    );
    final staleRecord = recentRecord.copyWith(
      lastBoundingBox: const BoundingBox(
        left: 600,
        top: 140,
        width: 180,
        height: 340,
      ),
      lastSeenAt: timestamp.subtract(const Duration(seconds: 8)),
    );

    final recentScore = engine.score(
      entity: entity,
      record: recentRecord,
      frame: frame,
      embeddingSimilarity: 0.42,
      enableTemporalPersistence: true,
    );
    final staleScore = engine.score(
      entity: entity,
      record: staleRecord,
      frame: frame,
      embeddingSimilarity: 0.42,
      enableTemporalPersistence: true,
    );

    expect(recentScore, greaterThan(staleScore));
    expect(recentScore, greaterThan(0.75));
  });
}
