import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../../models/frame_context.dart';
import '../../models/video_source.dart';

typedef SourceFrameCallback = Future<void> Function(FrameContext frame);

class MediaSourceService {
  VideoSourceState _sourceState = const VideoSourceState(
    type: VisionSourceType.camera,
    label: 'Initializing camera',
    isReady: false,
  );

  CameraController? _cameraController;
  VideoPlayerController? _videoController;
  Timer? _videoTick;
  int _frameCounter = 0;
  bool _sourceBusy = false;
  Size? _currentFrameSourceSize;

  VideoSourceState get sourceState => _sourceState;
  CameraController? get cameraController => _cameraController;
  VideoPlayerController? get videoController => _videoController;

  Size? get sourceSize {
    if (_currentFrameSourceSize != null) {
      return _currentFrameSourceSize;
    }
    if (_sourceState.isCamera) {
      return _cameraController?.value.previewSize;
    }
    if (_sourceState.isVideoFile) {
      final value = _videoController?.value;
      if (value == null || !value.isInitialized) {
        return null;
      }
      return value.size;
    }
    return null;
  }

  double get previewAspectRatio {
    final size = sourceSize;
    if (size == null || size.height == 0) {
      return 16 / 9;
    }
    return size.width / size.height;
  }

  Future<void> initialize() async {
    await _initializeCameraIfNeeded();
  }

  Future<void> switchSource(VisionSourceType type) async {
    await stop();
    _currentFrameSourceSize = null;

    if (type == VisionSourceType.camera) {
      await _initializeCameraIfNeeded();
      return;
    }

    if (type == VisionSourceType.videoFile) {
      _sourceState = VideoSourceState(
        type: VisionSourceType.videoFile,
        label: _videoController?.value.isInitialized == true
            ? 'Selected video'
            : 'No video selected',
        isReady: _videoController?.value.isInitialized == true,
        selectedFilePath: _sourceState.selectedFilePath,
      );
      return;
    }

    _sourceState = const VideoSourceState(
      type: VisionSourceType.futureStream,
      label: 'Future stream source',
      isReady: false,
    );
  }

  Future<void> pickVideoFile() async {
    final result = await FilePicker.pickFiles(type: FileType.video);
    if (result == null || result.files.single.path == null) {
      return;
    }

    final selectedPath = result.files.single.path!;
    await _videoController?.dispose();

    final controller = VideoPlayerController.file(File(selectedPath));
    await controller.initialize();
    await controller.setLooping(true);

    _videoController = controller;
    _currentFrameSourceSize = controller.value.size;
    _sourceState = VideoSourceState(
      type: VisionSourceType.videoFile,
      label: result.files.single.name,
      isReady: true,
      selectedFilePath: selectedPath,
    );
  }

  Future<void> start(SourceFrameCallback onFrame) async {
    if (_sourceState.type == VisionSourceType.camera) {
      await _startCameraStream(onFrame);
      return;
    }

    if (_sourceState.type == VisionSourceType.videoFile) {
      await _startVideoTick(onFrame);
    }
  }

  Future<void> stop() async {
    _videoTick?.cancel();
    _videoTick = null;
    _sourceBusy = false;

    final cameraController = _cameraController;
    if (cameraController != null && cameraController.value.isStreamingImages) {
      await cameraController.stopImageStream();
    }

    final videoController = _videoController;
    if (videoController != null && videoController.value.isInitialized) {
      await videoController.pause();
    }
  }

  Future<void> dispose() async {
    await stop();
    await _cameraController?.dispose();
    await _videoController?.dispose();
  }

  Future<void> _initializeCameraIfNeeded() async {
    final existing = _cameraController;
    if (existing != null && existing.value.isInitialized) {
      _sourceState = const VideoSourceState(
        type: VisionSourceType.camera,
        label: 'Rear camera',
        isReady: true,
      );
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      _currentFrameSourceSize = null;
      _sourceState = const VideoSourceState(
        type: VisionSourceType.camera,
        label: 'No camera available',
        isReady: false,
      );
      return;
    }

    final rearCameras = cameras.where((camera) {
      return camera.lensDirection == CameraLensDirection.back;
    });
    final preferredCamera = rearCameras.isNotEmpty ? rearCameras.first : cameras.first;

    final controller = CameraController(
      preferredCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();

    _cameraController = controller;
    _currentFrameSourceSize = null;
    _sourceState = const VideoSourceState(
      type: VisionSourceType.camera,
      label: 'Rear camera',
      isReady: true,
    );
  }

  Future<void> _startCameraStream(SourceFrameCallback onFrame) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      await _initializeCameraIfNeeded();
    }

    final readyController = _cameraController;
    if (readyController == null || readyController.value.isStreamingImages) {
      return;
    }

    await readyController.startImageStream((image) {
      if (_sourceBusy) {
        return;
      }

      _sourceBusy = true;
      final rotation = _cameraFrameRotation(readyController, image);
      final frameSize = _orientedSize(
        Size(image.width.toDouble(), image.height.toDouble()),
        rotation,
      );
      _currentFrameSourceSize = frameSize;
      final frame = FrameContext(
        frameNumber: ++_frameCounter,
        sourceSize: frameSize,
        timestamp: DateTime.now(),
        sourceType: VisionSourceType.camera,
        rotation: rotation,
        snapshot: _snapshotFromCameraImage(image),
      );

      Future<void>.sync(() => onFrame(frame)).whenComplete(() {
        _sourceBusy = false;
      });
    });
  }

  Future<void> _startVideoTick(SourceFrameCallback onFrame) async {
    final controller = _videoController;
    final videoPath = _sourceState.selectedFilePath;
    if (controller == null ||
        !controller.value.isInitialized ||
        videoPath == null) {
      return;
    }

    await controller.play();
    _videoTick = Timer.periodic(const Duration(milliseconds: 240), (_) {
      if (_sourceBusy) {
        return;
      }

      _sourceBusy = true;
      Future<void>.sync(() async {
        final frame = await _buildVideoFrame(
          controller: controller,
          videoPath: videoPath,
        );
        if (frame == null) {
          return;
        }
        _currentFrameSourceSize = frame.sourceSize;
        await onFrame(frame);
      }).whenComplete(() {
        _sourceBusy = false;
      });
    });
  }

  Future<FrameContext?> _buildVideoFrame({
    required VideoPlayerController controller,
    required String videoPath,
  }) async {
    final position = controller.value.position;
    final bytes = await vt.VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: vt.ImageFormat.JPEG,
      timeMs: position.inMilliseconds,
      quality: 70,
      maxWidth: 960,
    );
    if (bytes == null) {
      return null;
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }

    return FrameContext(
      frameNumber: ++_frameCounter,
      sourceSize: Size(decoded.width.toDouble(), decoded.height.toDouble()),
      timestamp: DateTime.now(),
      sourceType: VisionSourceType.videoFile,
      sourcePosition: position,
      encodedImageBytes: bytes,
      sourcePath: videoPath,
    );
  }

  FrameSnapshot _snapshotFromCameraImage(CameraImage image) {
    final pixelFormat = switch (image.format.group) {
      ImageFormatGroup.yuv420 => FramePixelFormat.yuv420,
      ImageFormatGroup.bgra8888 => FramePixelFormat.bgra8888,
      _ => FramePixelFormat.unsupported,
    };

    final planes = image.planes.map((plane) {
      return FramePlaneData(
        bytes: Uint8List.fromList(plane.bytes),
        bytesPerRow: plane.bytesPerRow,
        bytesPerPixel: plane.bytesPerPixel,
      );
    }).toList(growable: false);

    return FrameSnapshot(
      width: image.width,
      height: image.height,
      pixelFormat: pixelFormat,
      planes: planes,
    );
  }

  FrameRotation _cameraFrameRotation(
    CameraController controller,
    CameraImage image,
  ) {
    final sensorOrientation = controller.description.sensorOrientation;
    final isFrontCamera =
        controller.description.lensDirection == CameraLensDirection.front;
    final orientation = controller.value.deviceOrientation;

    if (Platform.isIOS) {
      final isPortrait = orientation == DeviceOrientation.portraitUp ||
          orientation == DeviceOrientation.portraitDown;
      if (!isPortrait || image.height >= image.width) {
        return FrameRotation.rotation0;
      }
      return _frameRotationFromDegrees(sensorOrientation);
    }

    if (Platform.isAndroid) {
      final deviceDegrees = switch (orientation) {
        DeviceOrientation.portraitUp => 0,
        DeviceOrientation.landscapeLeft => 90,
        DeviceOrientation.portraitDown => 180,
        DeviceOrientation.landscapeRight => 270,
      };
      final totalDegrees = isFrontCamera
          ? (sensorOrientation + deviceDegrees) % 360
          : (sensorOrientation - deviceDegrees + 360) % 360;
      return _frameRotationFromDegrees(totalDegrees);
    }

    return FrameRotation.rotation0;
  }

  FrameRotation _frameRotationFromDegrees(int degreesClockwise) {
    return switch (degreesClockwise % 360) {
      90 => FrameRotation.rotation90,
      180 => FrameRotation.rotation180,
      270 => FrameRotation.rotation270,
      _ => FrameRotation.rotation0,
    };
  }

  Size _orientedSize(Size sourceSize, FrameRotation rotation) {
    if (!rotation.swapsDimensions) {
      return sourceSize;
    }
    return Size(sourceSize.height, sourceSize.width);
  }
}
