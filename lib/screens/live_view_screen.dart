import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/inference_diagnostics.dart';
import '../models/pipeline_metrics.dart';
import '../models/stage_timing_breakdown.dart';
import '../models/tracked_entity.dart';
import '../models/video_source.dart';
import '../services/orchestrator/perception_result.dart';
import '../services/pipeline/vision_pipeline_controller.dart';
import '../services/pipeline/vision_scope.dart';
import '../widgets/metric_tile.dart';
import '../widgets/overlays/perception_overlay_painter.dart';
import '../widgets/status_chip.dart';
import '../widgets/tracked_entity_card.dart';

class LiveViewScreen extends StatefulWidget {
  const LiveViewScreen({super.key});

  @override
  State<LiveViewScreen> createState() => _LiveViewScreenState();
}

class _LiveViewScreenState extends State<LiveViewScreen> {
  @override
  Widget build(BuildContext context) {
    final controller = VisionScope.read(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        controller.recordLiveViewBuild();
      }
    });
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
                _StatusStrip(controller: controller),
                const SizedBox(height: 16),
                _ControlBar(
                  controller: controller,
                  onSelectSource: () =>
                      _showSourceSelector(context, controller),
                ),
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final errorMessage = controller.errorMessage;
                    if (errorMessage == null) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.error.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: Text(
                          errorMessage,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<PipelineMetrics>(
                  valueListenable: controller.metricsListenable,
                  builder: (context, metrics, _) {
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        MetricTile(
                          label: 'FPS',
                          value: metrics.fps.toStringAsFixed(1),
                          caption: 'preview stays independent from inference',
                        ),
                        MetricTile(
                          label: 'Latency',
                          value:
                              '${metrics.frameLatencyMs.toStringAsFixed(1)} ms',
                          caption: 'full pipeline latency',
                        ),
                        MetricTile(
                          label: 'Frames',
                          value: '${metrics.processedFrames}',
                          caption: controller.sourceState.label,
                        ),
                        MetricTile(
                          label: 'Queue',
                          value: '${metrics.queuedFrames}',
                          caption:
                              '${metrics.droppedFrames} dropped / ${metrics.adaptiveFrameIntervalMs.toStringAsFixed(0)} ms pacing',
                        ),
                        MetricTile(
                          label: 'Inference',
                          value: '${metrics.inferenceFrames}',
                          caption: 'worker isolate frames',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                _PerformanceBreakdownPanel(controller: controller),
                const SizedBox(height: 18),
                _InferenceDebugPanel(controller: controller),
                const SizedBox(height: 18),
                Text(
                  'Tap A Detection To Teach It',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<List<TrackedEntity>>(
                  valueListenable: controller.trackedEntitiesListenable,
                  builder: (context, entities, _) {
                    if (entities.isEmpty) {
                      return _LearningHint(theme: theme);
                    }
                    return Column(
                      children: entities
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
                    );
                  },
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

  Future<void> _showSourceSelector(
    BuildContext context,
    VisionPipelineController controller,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101C28),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: VisionSourceType.values
                  .map((source) {
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
                  })
                  .toList(growable: false),
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

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.controller});

  final VisionPipelineController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoSourceState>(
      valueListenable: controller.sourceStateListenable,
      builder: (context, sourceState, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: controller.processingListenable,
          builder: (context, isProcessing, _) {
            return ValueListenableBuilder<DetectorDiagnostics>(
              valueListenable: controller.diagnosticsListenable,
              builder: (context, diagnostics, _) {
                return ValueListenableBuilder<List<TrackedEntity>>(
                  valueListenable: controller.trackedEntitiesListenable,
                  builder: (context, entities, _) {
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        StatusChip(
                          label: 'Pipeline',
                          value: controller.pipelineStatus,
                          color: isProcessing
                              ? const Color(0xFF67E39C)
                              : const Color(0xFFFFC857),
                          icon: isProcessing
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                        ),
                        StatusChip(
                          label: 'Source',
                          value: sourceState.type.label,
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
                          label: 'Delegate',
                          value: diagnostics.delegateName,
                          color: const Color(0xFF9EE37D),
                          icon: Icons.bolt_rounded,
                        ),
                        StatusChip(
                          label: 'Tracks',
                          value: '${entities.length}',
                          color: const Color(0xFF3ED4D3),
                          icon: Icons.track_changes_rounded,
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.controller, required this.onSelectSource});

  final VisionPipelineController controller;
  final VoidCallback onSelectSource;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoSourceState>(
      valueListenable: controller.sourceStateListenable,
      builder: (context, sourceState, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: controller.processingListenable,
          builder: (context, isProcessing, _) {
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: sourceState.isReady
                      ? controller.toggleProcessing
                      : null,
                  icon: Icon(
                    isProcessing ? Icons.stop_circle : Icons.play_circle_fill,
                  ),
                  label: Text(
                    isProcessing ? 'Stop Processing' : 'Start Processing',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onSelectSource,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Source'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.pickVideoFile,
                  icon: const Icon(Icons.video_file_rounded),
                  label: const Text('Load Video'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.runDetectorSelfTest,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Run Test Inference'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PerformanceBreakdownPanel extends StatelessWidget {
  const _PerformanceBreakdownPanel({required this.controller});

  final VisionPipelineController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<StageTimingBreakdown>(
      valueListenable: controller.stageTimingListenable,
      builder: (context, timings, _) {
        return Container(
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
              Text('Performance Breakdown', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _DebugChip(
                    label: 'Acquire',
                    value:
                        '${timings.sourceAcquisitionMs.toStringAsFixed(1)} ms',
                  ),
                  _DebugChip(
                    label: 'Convert',
                    value: '${timings.colorConversionMs.toStringAsFixed(1)} ms',
                  ),
                  _DebugChip(
                    label: 'Rotate',
                    value: '${timings.rotationMs.toStringAsFixed(1)} ms',
                  ),
                  _DebugChip(
                    label: 'Resize',
                    value: '${timings.resizeMs.toStringAsFixed(1)} ms',
                  ),
                  _DebugChip(
                    label: 'Normalize',
                    value: '${timings.normalizationMs.toStringAsFixed(1)} ms',
                  ),
                  _DebugChip(
                    label: 'Tensor Copy',
                    value: '${timings.tensorCopyMs.toStringAsFixed(1)} ms',
                  ),
                  _DebugChip(
                    label: 'Inference',
                    value: '${timings.inferenceMs.toStringAsFixed(1)} ms',
                  ),
                  _DebugChip(
                    label: 'Parse',
                    value: '${timings.outputParsingMs.toStringAsFixed(1)} ms',
                  ),
                  _DebugChip(
                    label: 'Track',
                    value: '${timings.trackingMs.toStringAsFixed(1)} ms',
                  ),
                  _DebugChip(
                    label: 'Persistence',
                    value: '${timings.persistenceMs.toStringAsFixed(1)} ms',
                  ),
                  _DebugChip(
                    label: 'Learning',
                    value: '${timings.learningMs.toStringAsFixed(1)} ms',
                  ),
                  _DebugChip(
                    label: 'Logging',
                    value: '${timings.loggingMs.toStringAsFixed(1)} ms',
                  ),
                  _DebugChip(
                    label: 'Overlay',
                    value:
                        '${timings.overlayRepaintMs.toStringAsFixed(1)} ms / ${timings.overlayRepaintCount}',
                  ),
                  _DebugChip(
                    label: 'Builds',
                    value: '${timings.liveWidgetBuildCount}',
                  ),
                  _DebugChip(
                    label: 'Total',
                    value: '${timings.totalPipelineMs.toStringAsFixed(1)} ms',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(timings.pipelinePath, style: theme.textTheme.bodySmall),
            ],
          ),
        );
      },
    );
  }
}

class _InferenceDebugPanel extends StatelessWidget {
  const _InferenceDebugPanel({required this.controller});

  final VisionPipelineController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<DetectorDiagnostics>(
      valueListenable: controller.diagnosticsListenable,
      builder: (context, diagnostics, _) {
        final testResult = controller.lastDetectorTestResult;
        return Container(
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
              Text('Inference Debug', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _DebugChip(label: 'Backend', value: diagnostics.backendName),
                  _DebugChip(
                    label: 'Loaded',
                    value: diagnostics.modelLoaded ? 'Yes' : 'No',
                  ),
                  _DebugChip(
                    label: 'Delegate',
                    value: diagnostics.delegateName,
                  ),
                  _DebugChip(
                    label: 'Threads',
                    value: '${diagnostics.threadCount}',
                  ),
                  _DebugChip(
                    label: 'Frames',
                    value:
                        '${diagnostics.framesReceived}/${diagnostics.framesInferred}',
                  ),
                  _DebugChip(
                    label: 'Frame',
                    value:
                        '${diagnostics.frameWidth}x${diagnostics.frameHeight}',
                  ),
                  _DebugChip(
                    label: 'Requested',
                    value: diagnostics.requestedInputSize == 0
                        ? '-'
                        : '${diagnostics.requestedInputSize}',
                  ),
                  _DebugChip(
                    label: 'Input',
                    value: diagnostics.inputShape.isEmpty
                        ? '-'
                        : diagnostics.inputShape.join('x'),
                  ),
                  _DebugChip(
                    label: 'Outputs',
                    value: diagnostics.outputShapes.isEmpty
                        ? '-'
                        : diagnostics.outputShapes
                              .map((shape) => shape.join('x'))
                              .join(' | '),
                  ),
                  _DebugChip(label: 'Parser', value: diagnostics.parserMode),
                  _DebugChip(
                    label: 'Labels',
                    value: diagnostics.labelMapLoaded
                        ? '${diagnostics.labelCount} from ${diagnostics.labelMapName}'
                        : 'not loaded',
                  ),
                  _DebugChip(
                    label: 'Class IDs',
                    value: diagnostics.rawClassIds.isEmpty
                        ? '-'
                        : diagnostics.rawClassIds.join(','),
                  ),
                  _DebugChip(
                    label: 'Mapped',
                    value: diagnostics.mappedLabels.isEmpty
                        ? '-'
                        : diagnostics.mappedLabels.join(', '),
                  ),
                  _DebugChip(
                    label: 'Unknown',
                    value: '${diagnostics.unknownLabelCount}',
                  ),
                  _DebugChip(
                    label: 'Raw',
                    value: '${diagnostics.rawCandidateCount}',
                  ),
                  _DebugChip(
                    label: 'Filtered',
                    value: '${diagnostics.filteredCandidateCount}',
                  ),
                  _DebugChip(
                    label: 'Tracker',
                    value:
                        '${diagnostics.trackerInputCount} -> ${diagnostics.trackerOutputCount}',
                  ),
                  _DebugChip(
                    label: 'Queue',
                    value: '${diagnostics.queueDepth}',
                  ),
                  _DebugChip(
                    label: 'Skipped',
                    value: '${diagnostics.skippedFrames}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                diagnostics.preprocessSummary,
                style: theme.textTheme.bodySmall,
              ),
              if (diagnostics.sampleOutputValues.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Sample output: ${diagnostics.sampleOutputValues.map((value) => value.toStringAsFixed(3)).join(', ')}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (diagnostics.lastInferenceError != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Last error: ${diagnostics.lastInferenceError}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (testResult != null) ...[
                const SizedBox(height: 8),
                Text(
                  testResult.success
                      ? 'Self-test: ${testResult.message}'
                      : 'Self-test failed: ${testResult.message}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.controller});

  final VisionPipelineController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<VideoSourceState>(
      valueListenable: controller.sourceStateListenable,
      builder: (context, sourceState, _) {
        return ValueListenableBuilder<Size?>(
          valueListenable: controller.sourceSizeListenable,
          builder: (context, sourceSize, _) {
            final cameraController = controller.cameraController;
            final videoController = controller.videoController;
            Widget preview = _PreviewIdleState(
              title: sourceState.label,
              subtitle: sourceState.isReady
                  ? 'Ready for on-device processing'
                  : 'Prepare a source to begin',
            );

            if (sourceState.type == VisionSourceType.camera &&
                cameraController != null &&
                cameraController.value.isInitialized) {
              preview = CameraPreview(cameraController);
            } else if (sourceState.type == VisionSourceType.videoFile &&
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
                  colors: [Color(0xFF112234), Color(0xFF09131E)],
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
                      child: ValueListenableBuilder<PerceptionResult?>(
                        valueListenable: controller.perceptionResultListenable,
                        builder: (context, result, _) {
                          return PerceptionOverlay(
                            result: result,
                            sourceSize: sourceSize,
                            settings: controller.settings,
                            onPainted: controller.recordOverlayRepaint,
                          );
                        },
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
                      child: ValueListenableBuilder<bool>(
                        valueListenable: controller.processingListenable,
                        builder: (context, isProcessing, _) {
                          return _OverlayBadge(
                            label: isProcessing ? 'PROCESSING' : 'IDLE',
                            icon: isProcessing
                                ? Icons.motion_photos_on
                                : Icons.pause_circle,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DebugChip extends StatelessWidget {
  const _DebugChip({required this.label, required this.value});

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

class _LearningHint extends StatelessWidget {
  const _LearningHint({required this.theme});

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

class _OverlayBadge extends StatelessWidget {
  const _OverlayBadge({required this.label, required this.icon});

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

class _PreviewIdleState extends StatelessWidget {
  const _PreviewIdleState({required this.title, required this.subtitle});

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
