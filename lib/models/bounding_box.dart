import 'dart:math' as math;
import 'dart:ui';

class BoundingBox {
  const BoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get area => math.max(0.0, width) * math.max(0.0, height);
  Offset get center => Offset(left + (width / 2), top + (height / 2));

  Rect toRect() => Rect.fromLTWH(left, top, width, height);

  Map<String, Object> toJson() {
    return <String, Object>{
      'left': left,
      'top': top,
      'width': width,
      'height': height,
    };
  }

  factory BoundingBox.fromJson(Map<String, Object?> json) {
    return BoundingBox(
      left: (json['left'] as num?)?.toDouble() ?? 0,
      top: (json['top'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 0,
      height: (json['height'] as num?)?.toDouble() ?? 0,
    );
  }

  BoundingBox clampTo(Size bounds) {
    final clampedLeft = left.clamp(0.0, bounds.width).toDouble();
    final clampedTop = top.clamp(0.0, bounds.height).toDouble();
    final clampedRight = right.clamp(0.0, bounds.width).toDouble();
    final clampedBottom = bottom.clamp(0.0, bounds.height).toDouble();
    return BoundingBox(
      left: clampedLeft,
      top: clampedTop,
      width: math.max(0.0, clampedRight - clampedLeft),
      height: math.max(0.0, clampedBottom - clampedTop),
    );
  }

  BoundingBox inflate({
    required double horizontal,
    required double vertical,
    required double maxWidth,
    required double maxHeight,
  }) {
    final horizontalPadding = width * horizontal;
    final verticalPadding = height * vertical;
    final inflated = BoundingBox(
      left: left - horizontalPadding,
      top: top - verticalPadding,
      width: width + (horizontalPadding * 2),
      height: height + (verticalPadding * 2),
    );
    return inflated.clampTo(Size(maxWidth, maxHeight));
  }

  double intersectionOverUnion(BoundingBox other) {
    final overlapLeft = math.max(left, other.left);
    final overlapTop = math.max(top, other.top);
    final overlapRight = math.min(right, other.right);
    final overlapBottom = math.min(bottom, other.bottom);

    final overlapWidth = math.max(0.0, overlapRight - overlapLeft);
    final overlapHeight = math.max(0.0, overlapBottom - overlapTop);
    final intersection = overlapWidth * overlapHeight;

    if (intersection == 0) {
      return 0;
    }

    final union = area + other.area - intersection;
    if (union <= 0) {
      return 0;
    }

    return intersection / union;
  }

  double normalizedCenterDistance(BoundingBox other, Size frameSize) {
    final delta = center - other.center;
    final diagonal = math.sqrt(
      (frameSize.width * frameSize.width) +
          (frameSize.height * frameSize.height),
    );
    if (diagonal == 0) {
      return 0;
    }
    return delta.distance / diagonal;
  }

  double sizeDelta(BoundingBox other) {
    final widthBase = math.max(width, other.width);
    final heightBase = math.max(height, other.height);
    if (widthBase == 0 || heightBase == 0) {
      return 0;
    }
    final widthDelta = (width - other.width).abs() / widthBase;
    final heightDelta = (height - other.height).abs() / heightBase;
    return (widthDelta + heightDelta) / 2;
  }

  @override
  String toString() {
    return 'BoundingBox(left: $left, top: $top, width: $width, height: $height)';
  }
}
