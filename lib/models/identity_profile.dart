import 'bounding_box.dart';

class IdentityProfile {
  const IdentityProfile({
    required this.id,
    required this.classLabel,
    required this.lastBoundingBox,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.sightings,
    required this.recoveries,
  });

  final String id;
  final String classLabel;
  final BoundingBox lastBoundingBox;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int sightings;
  final int recoveries;

  IdentityProfile copyWith({
    BoundingBox? lastBoundingBox,
    DateTime? lastSeenAt,
    int? sightings,
    int? recoveries,
  }) {
    return IdentityProfile(
      id: id,
      classLabel: classLabel,
      lastBoundingBox: lastBoundingBox ?? this.lastBoundingBox,
      firstSeenAt: firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      sightings: sightings ?? this.sightings,
      recoveries: recoveries ?? this.recoveries,
    );
  }
}
