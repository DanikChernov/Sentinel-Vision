import 'bounding_box.dart';

class DetectionResult {
  const DetectionResult({
    required this.id,
    required this.classLabel,
    required this.confidence,
    required this.boundingBox,
    required this.timestamp,
  });

  final String id;
  final String classLabel;
  final double confidence;
  final BoundingBox boundingBox;
  final DateTime timestamp;
}
