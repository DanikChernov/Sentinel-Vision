import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/pipeline/vision_scope.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = VisionScope.of(context);
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
            title: 'Pipeline Modules',
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.detectionEnabled,
                  title: const Text('Detection enabled'),
                  subtitle: const Text('Toggle detector execution for each frame.'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(detectionEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.trackingEnabled,
                  title: const Text('Tracking enabled'),
                  subtitle: const Text('Maintain frame-to-frame object identity.'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(trackingEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.reidentificationEnabled,
                  title: const Text('Re-identification enabled'),
                  subtitle: const Text('Recover stable identities after short exits.'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(reidentificationEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.semanticLabelerEnabled,
                  title: const Text('Semantic labeler enabled'),
                  subtitle: const Text('Apply semantic refinements after tracking.'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(semanticLabelerEnabled: value),
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
                  subtitle: const Text('Observe usage, detections, and confidence trends locally.'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(continuousLearningEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.saveDetectionCropsEnabled,
                  title: const Text('Save detection crops'),
                  subtitle: const Text('Capture local crops and metadata for exportable training samples.'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(saveDetectionCropsEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.identityLearningEnabled,
                  title: const Text('Identity learning enabled'),
                  subtitle: const Text('Strengthen repeated-identity memory and recovery confidence.'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(identityLearningEnabled: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.labelCorrectionLearningEnabled,
                  title: const Text('Label correction learning enabled'),
                  subtitle: const Text('Use local corrections to refine future labels.'),
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(labelCorrectionLearningEnabled: value),
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
                  items: ModelBackend.values.map((backend) {
                    return DropdownMenuItem<ModelBackend>(
                      value: backend,
                      child: Text(backend.label),
                    );
                  }).toList(growable: false),
                  onChanged: (backend) {
                    if (backend == null) {
                      return;
                    }
                    controller.updateSettings(settings.copyWith(backend: backend));
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  'LiteRT/TFLite is the active on-device backend in this MVP. ONNX and API entries stay exposed as integration hooks and are rejected until wired.',
                  style: theme.textTheme.bodySmall,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.child,
  });

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
