import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/tracked_entity.dart';
import '../models/video_source.dart';
import '../services/pipeline/vision_pipeline_controller.dart';
import '../services/pipeline/vision_scope.dart';
import '../widgets/bounding_box_overlay.dart';
import '../widgets/metric_tile.dart';
import '../widgets/status_chip.dart';
import '../widgets/tracked_entity_card.dart';

class LiveViewScreen extends StatelessWidget {
  const LiveViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = VisionScope.of(context);
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewHeight = constraints.maxHeight * 0.46;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sentinel Vision Mobile', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Local-first live perception console for camera, identity persistence, and adaptive on-device learning.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: previewHeight.clamp(260.0, 520.0).toDouble(),
                  child: _PreviewCard(controller: controller),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    StatusChip(
                      label: 'Pipeline',
                      value: controller.pipelineStatus,
                      color: controller.isProcessing
                          ? const Color(0xFF67E39C)
                          : const Color(0xFFFFC857),
                      icon: controller.isProcessing
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                    StatusChip(
                      label: 'Source',
                      value: controller.sourceState.type.label,
                      color: const Color(0xFF85C6FF),
                      icon: Icons.stream_rounded,
                    ),
                    StatusChip(
                      label: 'Backend',
                      value: controller.settings.backend.label,
                      color: const Color(0xFFFF9A3D),
                      icon: Icons.memory_rounded,
                    ),
                    StatusChip(
                      label: 'Learning',
                      value: controller.settings.continuousLearningEnabled ? 'On' : 'Off',
                      color: const Color(0xFF85C6FF),
                      icon: Icons.psychology_rounded,
                    ),
                    StatusChip(
                      label: 'Tracks',
                      value: '${controller.trackedEntities.length}',
                      color: const Color(0xFF3ED4D3),
                      icon: Icons.track_changes_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: controller.sourceState.isReady
                          ? controller.toggleProcessing
                          : null,
                      icon: Icon(
                        controller.isProcessing ? Icons.stop_circle : Icons.play_circle_fill,
                      ),
                      label: Text(
                        controller.isProcessing ? 'Stop Processing' : 'Start Processing',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showSourceSelector(context),
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: const Text('Source'),
                    ),
                    OutlinedButton.icon(
                      onPressed: controller.pickVideoFile,
                      icon: const Icon(Icons.video_file_rounded),
                      label: const Text('Load Video'),
                    ),
                  ],
                ),
                if (controller.errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      controller.errorMessage!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    MetricTile(
                      label: 'FPS',
                      value: controller.metrics.fps.toStringAsFixed(1),
                      caption: 'live pipeline throughput',
                    ),
                    MetricTile(
                      label: 'Latency',
                      value: '${controller.metrics.frameLatencyMs.toStringAsFixed(1)} ms',
                      caption: 'frame processing time',
                    ),
                    MetricTile(
                      label: 'Frames',
                      value: '${controller.metrics.processedFrames}',
                      caption: controller.sourceState.label,
                    ),
                    MetricTile(
                      label: 'Samples',
                      value: '${controller.learningSnapshot.metrics.trainingSampleCount}',
                      caption: 'local training crops',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('Tap A Detection To Teach It', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                if (controller.trackedEntities.isEmpty)
                  _LearningHint(theme: theme)
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
                const SizedBox(height: 10),
                Text(
                  'Corrections stay on-device and feed the Sentinel Learning Core without requiring cloud sync.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
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
          title: Text('Rename ${entity.stableLabel}'),
          content: TextField(
            controller: input,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Corrected label',
              hintText: 'Dan / coffee mug / backpack',
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
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSourceSelector(BuildContext context) async {
    final controller = VisionScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101C28),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: VisionSourceType.values.map((source) {
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: Icon(_iconForSource(source)),
                  title: Text(source.label),
                  subtitle: Text(
                    source == VisionSourceType.futureStream
                        ? 'Reserved for future RTSP/WebRTC input'
                        : source == VisionSourceType.videoFile
                            ? 'Run on extracted local video frames'
                            : 'Use the live device camera',
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await controller.selectSource(source);
                  },
                );
              }).toList(growable: false),
            ),
          ),
        );
      },
    );
  }

  IconData _iconForSource(VisionSourceType source) {
    return switch (source) {
      VisionSourceType.camera => Icons.videocam_rounded,
      VisionSourceType.videoFile => Icons.video_file_rounded,
      VisionSourceType.futureStream => Icons.cast_connected_rounded,
    };
  }
}

class _LearningHint extends StatelessWidget {
  const _LearningHint({
    required this.theme,
  });

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(
        'Start processing to populate live detections. Once tracks appear here, you can rename them or flag false positives.',
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.controller,
  });

  final VisionPipelineController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cameraController = controller.cameraController;
    final videoController = controller.videoController;
    final sourceSize = controller.sourceSize;

    Widget preview = _PreviewPlaceholder(
      title: controller.sourceState.label,
      subtitle: controller.sourceState.isReady
          ? 'Ready for on-device processing'
          : 'Prepare a source to begin',
    );

    if (controller.sourceState.type == VisionSourceType.camera &&
        cameraController != null &&
        cameraController.value.isInitialized) {
      preview = CameraPreview(cameraController);
    } else if (controller.sourceState.type == VisionSourceType.videoFile &&
        videoController != null &&
        videoController.value.isInitialized) {
      preview = VideoPlayer(videoController);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF112234),
            Color(0xFF09131E),
          ],
        ),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF112234).withValues(alpha: 0.5),
                    Colors.black,
                  ],
                ),
              ),
            ),
            if (sourceSize != null)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: sourceSize.width,
                  height: sourceSize.height,
                  child: preview,
                ),
              )
            else
              preview,
            Positioned.fill(
              child: BoundingBoxOverlay(
                entities: controller.trackedEntities,
                sourceSize: sourceSize,
              ),
            ),
            const Positioned(
              top: 16,
              left: 16,
              child: _OverlayBadge(
                label: 'LIVE VIEW',
                icon: Icons.blur_on_rounded,
              ),
            ),
            Positioned(
              right: 16,
              top: 16,
              child: _OverlayBadge(
                label: controller.isProcessing ? 'PROCESSING' : 'IDLE',
                icon: controller.isProcessing ? Icons.motion_photos_on : Icons.pause_circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayBadge extends StatelessWidget {
  const _OverlayBadge({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: const Color(0xFF09131E),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3ED4D3), Color(0xFF0B8D98)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3ED4D3).withValues(alpha: 0.35),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(Icons.sensors, size: 40, color: Colors.black),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
