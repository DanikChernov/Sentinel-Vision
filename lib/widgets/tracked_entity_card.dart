import 'package:flutter/material.dart';

import '../models/tracked_entity.dart';

class TrackedEntityCard extends StatelessWidget {
  const TrackedEntityCard({
    required this.entity,
    this.onRename,
    this.onFalsePositive,
    super.key,
  });

  final TrackedEntity entity;
  final VoidCallback? onRename;
  final VoidCallback? onFalsePositive;

  @override
  Widget build(BuildContext context) {
    final accent = entity.classLabel == 'person'
        ? const Color(0xFF3ED4D3)
        : const Color(0xFFFF9A3D);
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: entity.isVisible ? 0.1 : 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent.withValues(alpha: entity.isVisible ? 0.45 : 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entity.overlayLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  entity.isVisible ? 'ACTIVE' : 'PERSISTED',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            entity.displayLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entity.detailLabel,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _FactPill(
                label: 'Detector',
                value:
                    '${((entity.detectorConfidence ?? entity.confidence) * 100).toStringAsFixed(0)}%',
              ),
              _FactPill(
                label: 'Adaptive',
                value:
                    '${(entity.displayConfidence * 100).toStringAsFixed(0)}%',
              ),
              _FactPill(
                label: 'Corrections',
                value: '${entity.correctionCount}',
              ),
              _FactPill(label: 'Missed', value: '${entity.missedFrames}'),
              _FactPill(
                label: 'Updated',
                value: _formatTime(entity.lastSeenAt),
              ),
              if (entity.identityConfidence != null)
                _FactPill(
                  label: 'Identity AI',
                  value:
                      '${(entity.identityConfidence! * 100).toStringAsFixed(0)}%',
                ),
              if (entity.faceConfidence != null)
                _FactPill(
                  label: 'Face',
                  value:
                      '${(entity.faceConfidence! * 100).toStringAsFixed(0)}%',
                ),
              if (entity.embeddingSimilarity != null)
                _FactPill(
                  label: 'Embed',
                  value:
                      '${(entity.embeddingSimilarity! * 100).toStringAsFixed(0)}%',
                ),
              if (entity.temporalConfidence != null)
                _FactPill(
                  label: 'Temporal',
                  value:
                      '${(entity.temporalConfidence! * 100).toStringAsFixed(0)}%',
                ),
              if (entity.recoveredInFrame)
                const _FactPill(label: 'Identity', value: 'Recovered'),
            ],
          ),
          if (onRename != null || onFalsePositive != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (onRename != null)
                  OutlinedButton.icon(
                    onPressed: onRename,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Rename'),
                  ),
                if (onFalsePositive != null)
                  OutlinedButton.icon(
                    onPressed: onFalsePositive,
                    icon: const Icon(Icons.report_gmailerrorred_outlined),
                    label: const Text('False Positive'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    final ss = timestamp.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}

class _FactPill extends StatelessWidget {
  const _FactPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
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
