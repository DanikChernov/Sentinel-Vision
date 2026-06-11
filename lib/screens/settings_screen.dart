import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../screens/security/security_settings_screen.dart';
import '../screens/security/user_management_screen.dart';
import '../services/pipeline/vision_scope.dart';
import '../services/security/security_scope.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = VisionScope.of(context);
    final security = SecurityScope.of(context);
    final settings = controller.settings;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Runtime switches for the modular mobile perception stack and Sentinel Learning Core.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          _SettingsCard(
            title: 'Admin Security',
            child: AnimatedBuilder(
              animation: security.authService,
              builder: (context, _) {
                final auth = security.authService;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.isAdminAuthenticated
                          ? 'Authenticated as ${auth.session?.user.displayName ?? 'admin'}'
                          : 'Admin authentication required',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${auth.users.length} enrolled user(s). Backend: ${auth.biometricBackendName}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (auth.usingMockBiometricBackend) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Mock eye biometric backend active. Insecure development mode only.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: auth.isAdminAuthenticated
                              ? () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        UserManagementScreen(authService: auth),
                                  ),
                                )
                              : null,
                          icon: const Icon(Icons.manage_accounts_outlined),
                          label: const Text('Manage users'),
                        ),
                        OutlinedButton.icon(
                          onPressed: auth.isAdminAuthenticated
                              ? () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => SecuritySettingsScreen(
                                      authService: auth,
                                    ),
                                  ),
                                )
                              : null,
                          icon: const Icon(Icons.lock_outline_rounded),
                          label: const Text('Security settings'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => security.appLockService.lock(
                            reason: 'Manual lock.',
                          ),
                          icon: const Icon(Icons.lock_reset_rounded),
                          label: const Text('Lock now'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Pipeline Modules',
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.detectionEnabled,
                  title: const Text('Detection enabled'),
                  subtitle: const Text(
                    'Toggle detector execution for each frame.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(detectionEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.trackingEnabled,
                  title: const Text('Tracking enabled'),
                  subtitle: const Text(
                    'Maintain frame-to-frame object identity.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(trackingEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.reidentificationEnabled,
                  title: const Text('Re-identification enabled'),
                  subtitle: const Text(
                    'Recover stable identities after short exits.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(reidentificationEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.semanticLabelerEnabled,
                  title: const Text('Semantic labeler enabled'),
                  subtitle: const Text(
                    'Apply semantic refinements after tracking.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(semanticLabelerEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.segmentationEnabled,
                  title: const Text('YOLO26 segmentation'),
                  subtitle: const Text(
                    'Requires a configured YOLO26-seg model; otherwise reports unavailable.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(segmentationEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.samRefinementEnabled,
                  title: const Text('SAM 3.1 refinement'),
                  subtitle: const Text(
                    'Refine selected or scheduled masks when a backend is available.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(samRefinementEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.objectEmbeddingsEnabled,
                  title: const Text('Object embeddings'),
                  subtitle: const Text(
                    'Use local object descriptors for persistence and uncertainty.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(objectEmbeddingsEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.poseEnabled,
                  title: const Text('Pose processor'),
                  subtitle: const Text(
                    'Estimate body and hand keypoints for person tracks.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(poseEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.depthEnabled,
                  title: const Text('Depth processor'),
                  subtitle: const Text(
                    'Requires a configured depth model; otherwise reports unavailable.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(depthEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.sceneContextEnabled,
                  title: const Text('Scene context'),
                  subtitle: const Text(
                    'Classify lightweight local scene context.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(sceneContextEnabled: value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Model Manager',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<PerceptionPerformanceMode>(
                  key: ValueKey<PerceptionPerformanceMode>(
                    settings.performanceMode,
                  ),
                  initialValue: settings.performanceMode,
                  decoration: const InputDecoration(
                    labelText: 'Performance Mode',
                    border: OutlineInputBorder(),
                  ),
                  items: PerceptionPerformanceMode.values
                      .map((mode) {
                        return DropdownMenuItem<PerceptionPerformanceMode>(
                          value: mode,
                          child: Text(mode.label),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (mode) {
                    if (mode == null) {
                      return;
                    }
                    controller.updateSettings(
                      settings.applyPerformanceMode(mode),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _IntervalSlider(
                  label: 'Detection interval',
                  value: settings.detectionInterval,
                  min: 1,
                  max: 15,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(detectionInterval: value),
                  ),
                ),
                _IntervalSlider(
                  label: 'Segmentation interval',
                  value: settings.segmentationInterval,
                  min: 1,
                  max: 20,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(segmentationInterval: value),
                  ),
                ),
                _IntervalSlider(
                  label: 'SAM refinement interval',
                  value: settings.samRefinementInterval,
                  min: 2,
                  max: 60,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(samRefinementInterval: value),
                  ),
                ),
                _IntervalSlider(
                  label: 'Face Re-ID interval',
                  value: settings.faceReIdInterval,
                  min: 2,
                  max: 60,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(faceReIdInterval: value),
                  ),
                ),
                _IntervalSlider(
                  label: 'Object embedding interval',
                  value: settings.objectEmbeddingInterval,
                  min: 2,
                  max: 60,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(objectEmbeddingInterval: value),
                  ),
                ),
                _IntervalSlider(
                  label: 'Pose interval',
                  value: settings.poseInterval,
                  min: 1,
                  max: 60,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(poseInterval: value),
                  ),
                ),
                _IntervalSlider(
                  label: 'Depth interval',
                  value: settings.depthInterval,
                  min: 1,
                  max: 60,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(depthInterval: value),
                  ),
                ),
                _IntervalSlider(
                  label: 'Scene context interval',
                  value: settings.sceneContextInterval,
                  min: 2,
                  max: 90,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(sceneContextInterval: value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Sentinel Learning Core',
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.continuousLearningEnabled,
                  title: const Text('Continuous learning enabled'),
                  subtitle: const Text(
                    'Observe usage, detections, and confidence trends locally.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(continuousLearningEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.saveDetectionCropsEnabled,
                  title: const Text('Save detection crops'),
                  subtitle: const Text(
                    'Capture local crops and metadata for exportable training samples.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(saveDetectionCropsEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.identityLearningEnabled,
                  title: const Text('Identity learning enabled'),
                  subtitle: const Text(
                    'Strengthen repeated-identity memory and recovery confidence.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(identityLearningEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.labelCorrectionLearningEnabled,
                  title: const Text('Label correction learning enabled'),
                  subtitle: const Text(
                    'Use local corrections to refine future labels.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(labelCorrectionLearningEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.faceAnalysisPersistenceEnabled,
                  title: const Text('Face analysis persistence'),
                  subtitle: const Text(
                    'Use local face detection plus descriptor embeddings for person re-identification.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(faceAnalysisPersistenceEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.temporalPersistenceEnabled,
                  title: const Text('Temporal persistence'),
                  subtitle: const Text(
                    'Blend embedding similarity with motion, box consistency, and time gap.',
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(temporalPersistenceEnabled: value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Detection Confidence',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${(settings.confidenceThreshold * 100).round()}%',
                  style: theme.textTheme.titleLarge,
                ),
                Slider(
                  value: settings.confidenceThreshold,
                  min: 0.1,
                  max: 0.95,
                  divisions: 17,
                  label: '${(settings.confidenceThreshold * 100).round()}%',
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(confidenceThreshold: value),
                  ),
                ),
                Text(
                  'Lower values expose more raw detector output and increase recall at the cost of more noise.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Identity Persistence Timeout',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${settings.identityPersistence.inSeconds}s',
                  style: theme.textTheme.titleLarge,
                ),
                Slider(
                  value: settings.identityPersistence.inSeconds.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '${settings.identityPersistence.inSeconds}s',
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(
                      identityPersistence: Duration(seconds: value.round()),
                    ),
                  ),
                ),
                Text(
                  'Controls how long the local identity memory will try to recover an entity after it leaves frame.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Re-ID Confidence Threshold',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.reIdConfidenceThreshold.toStringAsFixed(2),
                  style: theme.textTheme.titleLarge,
                ),
                Slider(
                  value: settings.reIdConfidenceThreshold,
                  min: 0.25,
                  max: 0.9,
                  divisions: 13,
                  label: settings.reIdConfidenceThreshold.toStringAsFixed(2),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(reIdConfidenceThreshold: value),
                  ),
                ),
                Text(
                  'Higher values reduce identity switches by creating new persistent IDs when recovery confidence is weak.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Embedding Similarity Threshold',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.embeddingSimilarityThreshold.toStringAsFixed(2),
                  style: theme.textTheme.titleLarge,
                ),
                Slider(
                  value: settings.embeddingSimilarityThreshold,
                  min: 0.55,
                  max: 0.95,
                  divisions: 8,
                  label: settings.embeddingSimilarityThreshold.toStringAsFixed(
                    2,
                  ),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(embeddingSimilarityThreshold: value),
                  ),
                ),
                Text(
                  'Higher values demand stronger face-descriptor similarity before the app reuses a stored identity.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Live Performance',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<CameraCaptureProfile>(
                  key: ValueKey<CameraCaptureProfile>(
                    settings.cameraCaptureProfile,
                  ),
                  initialValue: settings.cameraCaptureProfile,
                  decoration: const InputDecoration(
                    labelText: 'Camera Feed Profile',
                    border: OutlineInputBorder(),
                  ),
                  items: CameraCaptureProfile.values
                      .map((profile) {
                        return DropdownMenuItem<CameraCaptureProfile>(
                          value: profile,
                          child: Text(profile.label),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (profile) {
                    if (profile == null) {
                      return;
                    }
                    controller.updateSettings(
                      settings.copyWith(cameraCaptureProfile: profile),
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<InferenceAcceleration>(
                  key: ValueKey<InferenceAcceleration>(settings.acceleration),
                  initialValue: settings.acceleration,
                  decoration: const InputDecoration(
                    labelText: 'LiteRT Acceleration',
                    border: OutlineInputBorder(),
                  ),
                  items: InferenceAcceleration.values
                      .map((acceleration) {
                        final available = controller.isAccelerationAvailable(
                          acceleration,
                        );
                        return DropdownMenuItem<InferenceAcceleration>(
                          value: acceleration,
                          enabled: available,
                          child: Text(
                            available
                                ? acceleration.label
                                : '${acceleration.label} (unavailable)',
                          ),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (acceleration) {
                    if (acceleration == null) {
                      return;
                    }
                    controller.updateSettings(
                      settings.copyWith(acceleration: acceleration),
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey<int>(settings.tfliteThreadCount),
                  initialValue: settings.tfliteThreadCount,
                  decoration: const InputDecoration(
                    labelText: 'LiteRT Thread Count',
                    border: OutlineInputBorder(),
                  ),
                  items: const <int>[1, 2, 3, 4, 6, 8]
                      .map((threadCount) {
                        return DropdownMenuItem<int>(
                          value: threadCount,
                          child: Text('$threadCount threads'),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (threadCount) {
                    if (threadCount == null) {
                      return;
                    }
                    controller.updateSettings(
                      settings.copyWith(tfliteThreadCount: threadCount),
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey<int>(
                    controller.supportedModelInputSizes.contains(
                          settings.modelInputSize,
                        )
                        ? settings.modelInputSize
                        : controller.supportedModelInputSizes.first,
                  ),
                  initialValue:
                      controller.supportedModelInputSizes.contains(
                        settings.modelInputSize,
                      )
                      ? settings.modelInputSize
                      : controller.supportedModelInputSizes.first,
                  decoration: const InputDecoration(
                    labelText: 'Model Input Size',
                    border: OutlineInputBorder(),
                  ),
                  items: controller.supportedModelInputSizes
                      .map((inputSize) {
                        return DropdownMenuItem<int>(
                          value: inputSize,
                          child: Text('$inputSize x $inputSize'),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (inputSize) {
                    if (inputSize == null) {
                      return;
                    }
                    controller.updateSettings(
                      settings.copyWith(modelInputSize: inputSize),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  'The active model reports supported input size(s): ${controller.supportedModelInputSizes.map((size) => '${size}x$size').join(', ')}. Unsupported sizes are rejected before switching.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Model Backend',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<ModelBackend>(
                  key: ValueKey<ModelBackend>(settings.backend),
                  initialValue: settings.backend,
                  decoration: const InputDecoration(
                    labelText: 'Backend Selector',
                    border: OutlineInputBorder(),
                  ),
                  items: ModelBackend.values
                      .map((backend) {
                        final available = controller.isBackendAvailable(
                          backend,
                        );
                        return DropdownMenuItem<ModelBackend>(
                          value: backend,
                          enabled: available,
                          child: Text(
                            available
                                ? backend.label
                                : '${backend.label} (unavailable)',
                          ),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (backend) {
                    if (backend == null) {
                      return;
                    }
                    controller.updateSettings(
                      settings.copyWith(backend: backend),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  'Only implemented backends are selectable. ONNX, API, and unconfigured YOLO entries are rejected safely and the previous backend remains active.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Overlay Settings',
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.drawBoxes,
                  title: const Text('Draw boxes'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(drawBoxes: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.drawLabels,
                  title: const Text('Draw labels'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(drawLabels: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.drawMasks,
                  title: const Text('Draw masks'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(drawMasks: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.drawPolygons,
                  title: const Text('Draw polygon outlines'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(drawPolygons: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.drawPoseSkeleton,
                  title: const Text('Draw pose skeleton'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(drawPoseSkeleton: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.drawDepthOverlay,
                  title: const Text('Draw depth shading'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(drawDepthOverlay: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.drawIdentityConfidence,
                  title: const Text('Draw identity confidence'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(drawIdentityConfidence: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.drawDiagnosticsOverlay,
                  title: const Text('Draw diagnostics overlay'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(drawDiagnosticsOverlay: value),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Mask opacity: ${(settings.maskOpacity * 100).round()}%',
                  style: theme.textTheme.bodyMedium,
                ),
                Slider(
                  value: settings.maskOpacity,
                  min: 0.05,
                  max: 0.75,
                  divisions: 14,
                  label: '${(settings.maskOpacity * 100).round()}%',
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(maskOpacity: value),
                  ),
                ),
                DropdownButtonFormField<SegmentationQuality>(
                  key: ValueKey<SegmentationQuality>(settings.maskQuality),
                  initialValue: settings.maskQuality,
                  decoration: const InputDecoration(
                    labelText: 'Mask Quality',
                    border: OutlineInputBorder(),
                  ),
                  items: SegmentationQuality.values
                      .map((quality) {
                        return DropdownMenuItem<SegmentationQuality>(
                          value: quality,
                          child: Text(quality.label),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (quality) {
                    if (quality == null) {
                      return;
                    }
                    controller.updateSettings(
                      settings.copyWith(maskQuality: quality),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Learning Data Controls',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: controller.exportLearningDataset,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Export Learning Dataset'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.clearLearnedMemory,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Clear Learned Memory'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.clearEmbeddingMemory,
                  icon: const Icon(Icons.face_retouching_off_outlined),
                  label: const Text('Clear Embedding Memory'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _IntervalSlider extends StatelessWidget {
  const _IntervalSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: every $value frame(s)',
          style: theme.textTheme.bodyMedium,
        ),
        Slider(
          value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: '$value',
          onChanged: (next) => onChanged(next.round()),
        ),
      ],
    );
  }
}
