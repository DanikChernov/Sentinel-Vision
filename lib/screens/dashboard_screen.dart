import 'package:flutter/material.dart';

import '../models/tracked_entity.dart';
import '../services/pipeline/vision_pipeline_controller.dart';
import '../services/pipeline/vision_scope.dart';
import '../widgets/metric_tile.dart';
import '../widgets/tracked_entity_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = VisionScope.of(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Console', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Active entities, recent detections, source state, pipeline health, and learned confidence shifts.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                MetricTile(
                  label: 'Source',
                  value: controller.sourceState.type.label,
                  caption: controller.sourceState.label,
                ),
                MetricTile(
                  label: 'Pipeline',
                  value: controller.pipelineStatus,
                  caption: controller.detectorLabel,
                ),
                MetricTile(
                  label: 'Memory',
                  value: '${controller.identityMemoryCount}',
                  caption: 'known identity registry entries',
                ),
                MetricTile(
                  label: 'Learning',
                  value: controller.settings.continuousLearningEnabled ? 'On' : 'Off',
                  caption:
                      '${controller.learningSnapshot.metrics.observationCount} observations',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Performance', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              MetricTile(
                label: 'FPS',
                value: controller.metrics.fps.toStringAsFixed(1),
              ),
              MetricTile(
                label: 'Latency',
                value: '${controller.metrics.frameLatencyMs.toStringAsFixed(1)} ms',
              ),
              MetricTile(
                label: 'Frames',
                value: '${controller.metrics.processedFrames}',
              ),
              MetricTile(
                label: 'AI Gain',
                value:
                    '${(controller.learningSnapshot.metrics.averageConfidenceGain * 100).toStringAsFixed(1)}%',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Active Tracked Entities', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (controller.trackedEntities.isEmpty)
            _EmptySection(
              title: 'No active entities',
              subtitle: 'Start the pipeline to populate tracker, identity memory, and local learning state.',
            )
          else
            Column(
              children: controller.trackedEntities
                  .map(
                    (entity) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TrackedEntityCard(
                        entity: entity,
                        onRename: () => _showCorrectionDialog(
                          context,
                          controller,
                          entity,
                        ),
                        onFalsePositive: () {
                          controller.markEntityFalsePositive(entity);
                        },
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          const SizedBox(height: 18),
          Text('Recent Detections', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (controller.recentDetections.isEmpty)
            const _EmptySection(
              title: 'No detections yet',
              subtitle: 'The detector feed will appear here once processing begins.',
            )
          else
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: Column(
                children: controller.recentDetections.take(8).map((detection) {
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: detection.classLabel == 'person'
                          ? const Color(0xFF3ED4D3).withValues(alpha: 0.16)
                          : const Color(0xFFFF9A3D).withValues(alpha: 0.16),
                      child: Icon(
                        detection.classLabel == 'person'
                            ? Icons.person_search_rounded
                            : Icons.category_rounded,
                        color: detection.classLabel == 'person'
                            ? const Color(0xFF3ED4D3)
                            : const Color(0xFFFF9A3D),
                      ),
                    ),
                    title: Text(
                      detection.classLabel,
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                    subtitle: Text(
                      'id ${detection.id} | ${(detection.confidence * 100).toStringAsFixed(0)}%',
                    ),
                    trailing: Text(
                      _formatTime(detection.timestamp),
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

  Future<void> _showCorrectionDialog(
    BuildContext context,
    VisionPipelineController controller,
    TrackedEntity entity,
  ) async {
    final input = TextEditingController(
      text: entity.learnedLabel ?? entity.classLabel,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Correct ${entity.stableLabel}'),
          content: TextField(
            controller: input,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Learned label',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await controller.applyEntityCorrection(entity, input.text);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Store'),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(DateTime timestamp) {
    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    final ss = timestamp.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
