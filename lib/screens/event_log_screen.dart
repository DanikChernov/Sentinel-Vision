import 'package:flutter/material.dart';

import '../services/pipeline/vision_scope.dart';
import '../widgets/event_log_card.dart';

class EventLogScreen extends StatelessWidget {
  const EventLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = VisionScope.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Event Log', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Session-local detection, identity, and pipeline events.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: controller.clearEventLog,
                icon: const Icon(Icons.delete_sweep_rounded),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: controller.eventLog.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Text(
                      'No events captured yet. Start the pipeline to populate the session log.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: controller.eventLog.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return EventLogCard(event: controller.eventLog[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
