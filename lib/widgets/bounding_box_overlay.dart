import 'package:flutter/material.dart';

import '../models/tracked_entity.dart';

class BoundingBoxOverlay extends StatelessWidget {
  const BoundingBoxOverlay({
    required this.entities,
    required this.sourceSize,
    this.onPainted,
    super.key,
  });

  final List<TrackedEntity> entities;
  final Size? sourceSize;
  final ValueChanged<Duration>? onPainted;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _BoundingBoxPainter(
          entities: entities,
          sourceSize: sourceSize,
          onPainted: onPainted,
        ),
      ),
    );
  }
}

class _BoundingBoxPainter extends CustomPainter {
  const _BoundingBoxPainter({
    required this.entities,
    required this.sourceSize,
    required this.onPainted,
  });

  final List<TrackedEntity> entities;
  final Size? sourceSize;
  final ValueChanged<Duration>? onPainted;

  @override
  void paint(Canvas canvas, Size size) {
    final paintWatch = Stopwatch()..start();
    final source = sourceSize;
    if (source == null || source.width <= 0 || source.height <= 0) {
      paintWatch.stop();
      onPainted?.call(paintWatch.elapsed);
      return;
    }

    final fitted = applyBoxFit(BoxFit.cover, source, size);
    final sourceRect = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & source,
    );
    final destinationRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );

    final scaleX = destinationRect.width / sourceRect.width;
    final scaleY = destinationRect.height / sourceRect.height;

    for (final entity in entities) {
      final color = entity.classLabel == 'person'
          ? const Color(0xFF3ED4D3)
          : const Color(0xFFFF9A3D);
      final rect = Rect.fromLTWH(
        destinationRect.left + ((entity.boundingBox.left - sourceRect.left) * scaleX),
        destinationRect.top + ((entity.boundingBox.top - sourceRect.top) * scaleY),
        entity.boundingBox.width * scaleX,
        entity.boundingBox.height * scaleY,
      );

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = entity.isVisible ? 2.6 : 1.8
        ..color = entity.isVisible
            ? color
            : color.withValues(alpha: 0.42);

      if (entity.isVisible) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(12)),
          paint,
        );
      } else {
        _drawDashedRect(canvas, rect, paint);
      }

      final label =
          '${entity.stableLabel} ${(entity.displayConfidence * 100).toStringAsFixed(0)}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            backgroundColor: color.withValues(alpha: 0.8),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.7);

      textPainter.paint(
        canvas,
        Offset(
          rect.left,
          (rect.top - textPainter.height - 6).clamp(4.0, size.height - textPainter.height)
              .toDouble(),
        ),
      );
    }
    paintWatch.stop();
    onPainted?.call(paintWatch.elapsed);
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 8.0;
    const gap = 5.0;
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint, dash, gap);
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint, dash, gap);
    _drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint, dash, gap);
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint, dash, gap);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double dash,
    double gap,
  ) {
    final totalDistance = (end - start).distance;
    if (totalDistance == 0) {
      return;
    }
    final direction = (end - start) / totalDistance;
    double drawn = 0;
    while (drawn < totalDistance) {
      final from = start + (direction * drawn);
      final to = start +
          (direction * (drawn + dash).clamp(0.0, totalDistance).toDouble());
      canvas.drawLine(from, to, paint);
      drawn += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return oldDelegate.entities != entities || oldDelegate.sourceSize != sourceSize;
  }
}
