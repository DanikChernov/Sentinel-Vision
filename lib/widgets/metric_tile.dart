import 'package:flutter/material.dart';

class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.label,
    required this.value,
    this.caption,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 148),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.bodySmall?.copyWith(
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 8),
            Text(caption!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
