enum VisionSourceType {
  camera('Camera'),
  videoFile('Video File'),
  futureStream('Future Stream');

  const VisionSourceType(this.label);

  final String label;
}

class VideoSourceState {
  const VideoSourceState({
    required this.type,
    required this.label,
    required this.isReady,
    this.selectedFilePath,
  });

  final VisionSourceType type;
  final String label;
  final bool isReady;
  final String? selectedFilePath;

  bool get isCamera => type == VisionSourceType.camera;
  bool get isVideoFile => type == VisionSourceType.videoFile;

  VideoSourceState copyWith({
    VisionSourceType? type,
    String? label,
    bool? isReady,
    String? selectedFilePath,
  }) {
    return VideoSourceState(
      type: type ?? this.type,
      label: label ?? this.label,
      isReady: isReady ?? this.isReady,
      selectedFilePath: selectedFilePath ?? this.selectedFilePath,
    );
  }
}
