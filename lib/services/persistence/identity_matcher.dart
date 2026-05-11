import 'dart:math' as math;

import '../../models/persistence_models.dart';

class IdentityMatcher {
  const IdentityMatcher();

  IdentityMatchResult? findBestMatch({
    required List<double> embedding,
    required Iterable<FaceEmbeddingRecord> records,
    required double similarityThreshold,
  }) {
    IdentityMatchResult? bestMatch;

    for (final record in records) {
      final similarity = cosineSimilarity(embedding, record.embedding);
      if (similarity < similarityThreshold) {
        continue;
      }
      if (bestMatch == null || similarity > bestMatch.similarity) {
        bestMatch = IdentityMatchResult(
          stableLabel: record.stableLabel,
          similarity: similarity,
          temporalConfidence: 0,
          combinedConfidence: similarity,
          record: record,
        );
      }
    }

    return bestMatch;
  }

  double cosineSimilarity(List<double> left, List<double> right) {
    final count = left.length < right.length ? left.length : right.length;
    if (count == 0) {
      return 0;
    }

    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;
    for (var index = 0; index < count; index += 1) {
      final l = left[index];
      final r = right[index];
      dot += l * r;
      leftNorm += l * l;
      rightNorm += r * r;
    }

    if (leftNorm == 0 || rightNorm == 0) {
      return 0;
    }
    return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
  }
}
