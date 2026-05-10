import 'package:flutter/material.dart';

import '../models/pipeline_event.dart';

class EventLogCard extends StatelessWidget {
  const EventLogCard({
    required this.event,
    super.key,
  });

  final PipelineEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (event.type) {
      PipelineEventType.identityAssigned => const Color(0xFF3ED4D3),
      PipelineEventType.identityRecovered => const Color(0xFF67E39C),
      PipelineEventType.learningObservation => const Color(0xFF85C6FF),
      PipelineEventType.learningCorrection => const Color(0xFFF6D06C),
      PipelineEventType.falsePositive => const Color(0xFFFF6E6E),
      PipelineEventType.datasetExport => const Color(0xFFC0F284),
      PipelineEventType.memoryReset => const Color(0xFFF4A261),
      PipelineEventType.pipelineState => const Color(0xFFFF9A3D),
      PipelineEventType.sourceChanged => const Color(0xFF85C6FF),
      PipelineEventType.trackerState => const Color(0xFFEEC96D),
      PipelineEventType.detection => const Color(0xFFE8F2F7),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${event.type.name.toUpperCase()} - ${_formatTime(event.timestamp)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
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
