import 'bounding_box.dart';

class DetectionResult {
  const DetectionResult({
    String? id,
    String? detectionId,
    this.classId = -1,
    required this.classLabel,
    required this.confidence,
    required this.boundingBox,
    required this.timestamp,
    this.sourceModel = 'unknown',
  }) : id = id ?? detectionId ?? 'det-unknown';

  final String id;
  String get detectionId => id;
  final int classId;
  final String classLabel;
  final double confidence;
  final BoundingBox boundingBox;
  final String sourceModel;
  final DateTime timestamp;

  bool get hasKnownClassLabel {
    final normalized = classLabel.trim().toLowerCase();
    return normalized.isNotEmpty &&
        normalized != 'unknown' &&
        normalized != '???';
  }
}
