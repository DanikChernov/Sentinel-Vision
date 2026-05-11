import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/pipeline/vision_scope.dart';
import '../widgets/metric_tile.dart';

class LearningScreen extends StatelessWidget {
  const LearningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = VisionScope.of(context);
    final learning = controller.learningSnapshot;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AI Learning', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Sentinel Learning Core stores local usage memory, corrections, identity patterns, and training samples for future personalization.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              MetricTile(
                label: 'Identities',
                value: '${learning.metrics.identityCount}',
                caption: 'learned identity patterns',
              ),
              MetricTile(
                label: 'Corrections',
                value: '${learning.metrics.correctionCount}',
                caption: 'stored local label corrections',
              ),
              MetricTile(
                label: 'Samples',
                value: '${learning.metrics.trainingSampleCount}',
                caption: 'dataset crops captured',
              ),
              MetricTile(
                label: 'Storage',
                value: _formatBytes(learning.metrics.approximateStorageBytes),
                caption: 'privacy-first on-device cache',
              ),
              MetricTile(
                label: 'AI Gain',
                value:
                    '${(learning.metrics.averageConfidenceGain * 100).toStringAsFixed(1)}%',
                caption: 'average adaptive confidence delta',
              ),
              MetricTile(
                label: 'False Pos',
                value: '${learning.metrics.falsePositiveCount}',
                caption: 'rejected detections remembered',
              ),
              MetricTile(
                label: 'Embeddings',
                value: '${controller.persistenceSnapshot.embeddingsStored}',
                caption: controller.persistenceSnapshot.backend.label,
              ),
              MetricTile(
                label: 'Recoveries',
                value: '${controller.persistenceSnapshot.recoveredIdentities}',
                caption:
                    '${(controller.persistenceSnapshot.identityRecoveryRate * 100).toStringAsFixed(1)}% recovery rate',
              ),
              MetricTile(
                label: 'Similarity',
                value:
                    '${(controller.persistenceSnapshot.averageSimilarity * 100).toStringAsFixed(1)}%',
                caption: 'average embedding similarity',
              ),
              MetricTile(
                label: 'Temporal',
                value:
                    '${(controller.persistenceSnapshot.averageTemporalConfidence * 100).toStringAsFixed(1)}%',
                caption: 'average temporal confidence',
              ),
              MetricTile(
                label: 'Face',
                value:
                    '${(controller.persistenceSnapshot.averageFaceConfidence * 100).toStringAsFixed(1)}%',
                caption: 'average face confidence',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.tonalIcon(
                onPressed: controller.exportLearningDataset,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Export Training Data'),
              ),
              OutlinedButton.icon(
                onPressed: controller.clearLearnedMemory,
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Clear Memory'),
              ),
              OutlinedButton.icon(
                onPressed: controller.clearEmbeddingMemory,
                icon: const Icon(Icons.face_retouching_off_outlined),
                label: const Text('Clear Embeddings'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Face Persistence Memory', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (controller.persistenceSnapshot.identities.isEmpty)
            const _EmptyLearningCard(
              message: 'No face-descriptor identities stored yet. Repeated visible people will accumulate local embedding memory here.',
            )
          else
            Column(
              children: controller.persistenceSnapshot.identities.map((identity) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          identity.preferredAlias == null
                              ? identity.stableLabel
                              : '${identity.stableLabel} / ${identity.preferredAlias}',
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _StatChip(label: 'Embeds', value: '${identity.embeddingCount}'),
                            _StatChip(label: 'Sightings', value: '${identity.sightings}'),
                            _StatChip(label: 'Recoveries', value: '${identity.recoveries}'),
                            _StatChip(
                              label: 'Similarity',
                              value:
                                  '${(identity.averageSimilarity * 100).toStringAsFixed(0)}%',
                            ),
                            _StatChip(
                              label: 'Temporal',
                              value:
                                  '${(identity.averageTemporalConfidence * 100).toStringAsFixed(0)}%',
                            ),
                            _StatChip(
                              label: 'Face',
                              value:
                                  '${(identity.averageFaceConfidence * 100).toStringAsFixed(0)}%',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          const SizedBox(height: 18),
          Text('Learned Identities', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (learning.identities.isEmpty)
            const _EmptyLearningCard(
              message: 'No learned identities yet. Repeated sightings and corrections will build local memory here.',
            )
          else
            Column(
              children: learning.identities.map((identity) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          identity.preferredAlias == null
                              ? identity.stableLabel
                              : '${identity.stableLabel} / ${identity.preferredAlias}',
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _StatChip(label: 'Class', value: identity.classLabel),
                            _StatChip(label: 'Sightings', value: '${identity.sightings}'),
                            _StatChip(label: 'Recoveries', value: '${identity.recoveries}'),
                            _StatChip(
                              label: 'Confidence',
                              value:
                                  '${(identity.learnedConfidence * 100).toStringAsFixed(0)}%',
                            ),
                            _StatChip(
                              label: 'Corrections',
                              value: '${identity.correctionCount}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          const SizedBox(height: 18),
          Text('Corrected Labels', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (learning.correctedLabels.isEmpty)
            const _EmptyLearningCard(
              message: 'No adaptive label mappings yet. Rename recurring objects to train local refinements.',
            )
          else
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: Column(
                children: learning.correctedLabels.take(10).map((mapping) {
                  return ListTile(
                    title: Text(
                      '${mapping.originalLabel} -> ${mapping.correctedLabel}',
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                    subtitle: Text(
                      'usage ${mapping.usageCount} | false positives ${mapping.falsePositiveCount}',
                    ),
                    trailing: Text(
                      '${(mapping.averageLearningConfidence * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
          const SizedBox(height: 18),
          Text('Training Samples', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (learning.recentSamples.isEmpty)
            const _EmptyLearningCard(
              message: 'Enable crop capture in Settings to collect local fine-tuning samples from camera detections.',
            )
          else
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: Column(
                children: learning.recentSamples.take(10).map((sample) {
                  return ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: Text(
                      sample.correctedLabel == null
                          ? sample.originalLabel
                          : '${sample.originalLabel} -> ${sample.correctedLabel}',
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${sample.stableLabel} | ${sample.sourceType.label} | ${p.basename(sample.cropPath)}',
                    ),
                    trailing: Text(
                      _formatTime(sample.timestamp),
                      style: theme.textTheme.bodySmall,
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String _formatTime(DateTime timestamp) {
    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    final ss = timestamp.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}

class _EmptyLearningCard extends StatelessWidget {
  const _EmptyLearningCard({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(message, style: theme.textTheme.bodyMedium),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
