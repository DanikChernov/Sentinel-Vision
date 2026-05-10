import 'dart:async';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../models/app_settings.dart';
import '../../models/detection_result.dart';
import '../../models/frame_context.dart';
import '../../models/learning_models.dart';
import '../../models/pipeline_event.dart';
import '../../models/pipeline_metrics.dart';
import '../../models/tracked_entity.dart';
import '../../models/video_source.dart';
import '../camera/media_source_service.dart';
import '../detection/detector.dart';
import '../detection/litert_object_detector.dart';
import '../identity/heuristic_identity_registry.dart';
import '../identity/identity_registry.dart';
import '../labeling/mlkit_semantic_labeler.dart';
import '../labeling/semantic_labeler.dart';
import '../learning/learning_core.dart';
import '../tracking/heuristic_tracker.dart';
import '../tracking/tracker.dart';

class VisionPipelineController extends ChangeNotifier {
  VisionPipelineController({
    MediaSourceService? mediaSourceService,
    Detector? detector,
    Tracker? tracker,
    IdentityRegistry? identityRegistry,
    SemanticLabeler? semanticLabeler,
    SentinelLearningCore? learningCore,
  })  : _mediaSourceService = mediaSourceService ?? MediaSourceService(),
        _detector = detector ?? LiteRtObjectDetector(),
        _tracker = tracker ?? HeuristicTracker(),
        _identityRegistry = identityRegistry ?? HeuristicIdentityRegistry(),
        _semanticLabeler = semanticLabeler ?? MlKitSemanticLabeler(),
        _learningCore = learningCore ?? SentinelLearningCore();

  final MediaSourceService _mediaSourceService;
  final Detector _detector;
  final Tracker _tracker;
  final IdentityRegistry _identityRegistry;
  final SemanticLabeler _semanticLabeler;
  final SentinelLearningCore _learningCore;

  AppSettings _settings = const AppSettings();
  LearningSnapshot _learningSnapshot = const LearningSnapshot();
  PipelineMetrics _metrics = const PipelineMetrics();
  VideoSourceState _sourceState = const VideoSourceState(
    type: VisionSourceType.camera,
    label: 'Booting source',
    isReady: false,
  );
  final List<PipelineEvent> _eventLog = <PipelineEvent>[];
  final List<DateTime> _frameWindow = <DateTime>[];
  List<TrackedEntity> _trackedEntities = const <TrackedEntity>[];
  List<DetectionResult> _recentDetections = const <DetectionResult>[];
  bool _isInitializing = false;
  bool _isProcessing = false;
  bool _isProcessingFrame = false;
  String _pipelineStatus = 'Idle';
  String? _errorMessage;
  DateTime? _lastDetectionEventAt;
  int _lastDetectionCount = -1;
  FrameContext? _lastFrameContext;

  AppSettings get settings => _settings;
  LearningSnapshot get learningSnapshot => _learningSnapshot;
  PipelineMetrics get metrics => _metrics;
  VideoSourceState get sourceState => _sourceState;
  List<PipelineEvent> get eventLog => List.unmodifiable(_eventLog.reversed);
  List<TrackedEntity> get trackedEntities => List.unmodifiable(_trackedEntities);
  List<DetectionResult> get recentDetections => List.unmodifiable(_recentDetections);
  bool get isInitializing => _isInitializing;
  bool get isProcessing => _isProcessing;
  String get pipelineStatus => _pipelineStatus;
  String? get errorMessage => _errorMessage;
  int get identityMemoryCount => _identityRegistry.knownIdentityCount;
  int get learningMemoryCount => _learningSnapshot.identities.length;
  String get detectorLabel => _detector.backendLabel;
  String get labelerLabel => _semanticLabeler.labelerName;
  CameraController? get cameraController => _mediaSourceService.cameraController;
  VideoPlayerController? get videoController => _mediaSourceService.videoController;
  double get previewAspectRatio => _mediaSourceService.previewAspectRatio;
  Size? get sourceSize => _mediaSourceService.sourceSize;

  Future<void> initialize() async {
    if (_isInitializing) {
      return;
    }

    _isInitializing = true;
    _pipelineStatus = 'Initializing media source';
    notifyListeners();

    try {
      _pipelineStatus = 'Loading local AI backends';
      notifyListeners();

      await _learningCore.initialize();
      _learningSnapshot = _learningCore.snapshot;
      await _detector.initialize();
      await _semanticLabeler.initialize();

      _pipelineStatus = 'Initializing media source';
      notifyListeners();

      await _mediaSourceService.initialize();
      _sourceState = _mediaSourceService.sourceState;
      _pipelineStatus = _sourceState.isReady ? 'Ready' : 'Source unavailable';
      _appendEvent(
        PipelineEvent(
          type: PipelineEventType.pipelineState,
          message:
              'Pipeline initialized with $detectorLabel and $labelerLabel.',
          timestamp: DateTime.now(),
        ),
      );
    } catch (error) {
      _errorMessage = error.toString();
      _pipelineStatus = 'Initialization failed';
      _appendEvent(
        PipelineEvent(
          type: PipelineEventType.pipelineState,
          message: 'Initialization failed: $_errorMessage',
          timestamp: DateTime.now(),
        ),
      );
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> toggleProcessing() async {
    if (_isProcessing) {
      await stopProcessing();
      return;
    }
    await startProcessing();
  }

  Future<void> startProcessing() async {
    if (_isProcessing || !_sourceState.isReady) {
      return;
    }

    _isProcessing = true;
    _pipelineStatus = 'Processing ${_sourceState.type.label.toLowerCase()}';
    _errorMessage = null;
    _appendEvent(
      PipelineEvent(
        type: PipelineEventType.pipelineState,
        message: 'Started pipeline on ${_sourceState.type.label}.',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();

    await _mediaSourceService.start(_handleFrame);
  }

  Future<void> stopProcessing() async {
    if (!_isProcessing) {
      return;
    }

    _isProcessing = false;
    _isProcessingFrame = false;
    _pipelineStatus = 'Stopped';
    await _mediaSourceService.stop();
    _appendEvent(
      PipelineEvent(
        type: PipelineEventType.pipelineState,
        message: 'Stopped pipeline processing.',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<void> selectSource(VisionSourceType type) async {
    final resumeAfterSwitch = _isProcessing;
    if (_isProcessing) {
      await stopProcessing();
    }

    await _mediaSourceService.switchSource(type);
    _sourceState = _mediaSourceService.sourceState;
    _pipelineStatus = _sourceState.isReady ? 'Ready' : 'Source pending';
    _appendEvent(
      PipelineEvent(
        type: PipelineEventType.sourceChanged,
        message: 'Switched source to ${type.label}.',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();

    if (resumeAfterSwitch && _sourceState.isReady) {
      await startProcessing();
    }
  }

  Future<void> pickVideoFile() async {
    final resumeAfterPick = _isProcessing;
    if (_isProcessing) {
      await stopProcessing();
    }

    await _mediaSourceService.pickVideoFile();
    _sourceState = _mediaSourceService.sourceState;
    _pipelineStatus = _sourceState.isReady ? 'Ready' : 'Video unavailable';
    _appendEvent(
      PipelineEvent(
        type: PipelineEventType.sourceChanged,
        message: _sourceState.isReady
            ? 'Loaded local video source ${_sourceState.label}.'
            : 'Video selection was cancelled.',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();

    if (resumeAfterPick && _sourceState.isReady) {
      await startProcessing();
    }
  }

  void updateSettings(AppSettings settings) {
    final previousBackend = _settings.backend;
    var nextSettings = settings;

    if (settings.backend != ModelBackend.tflite) {
      nextSettings = settings.copyWith(backend: ModelBackend.tflite);
      _appendEvent(
        PipelineEvent(
          type: PipelineEventType.pipelineState,
          message:
              '${settings.backend.label} is not wired yet. The pipeline remains on $detectorLabel.',
          timestamp: DateTime.now(),
        ),
      );
    }

    _settings = nextSettings;

    if (!_settings.trackingEnabled) {
      _tracker.reset();
      _trackedEntities = const <TrackedEntity>[];
    }

    if (!_settings.reidentificationEnabled) {
      _identityRegistry.reset();
    }

    if (previousBackend != _settings.backend) {
      _appendEvent(
        PipelineEvent(
          type: PipelineEventType.pipelineState,
          message: 'Active detector backend set to ${_settings.backend.label}.',
          timestamp: DateTime.now(),
        ),
      );
    }

    notifyListeners();
  }

  void clearEventLog() {
    _eventLog.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_mediaSourceService.dispose());
    unawaited(_detector.dispose());
    unawaited(_semanticLabeler.dispose());
    unawaited(_learningCore.dispose());
    super.dispose();
  }

  Future<void> applyEntityCorrection(
    TrackedEntity entity,
    String correctedLabel,
  ) async {
    final frame = _lastFrameContext ?? _fallbackFrame();
    final updatedEntity = await _learningCore.applyCorrection(
      entity: entity,
      correctedLabel: correctedLabel,
      frame: frame,
      settings: _settings,
    );
    _trackedEntities = _trackedEntities.map((item) {
      return item.trackId == entity.trackId ? updatedEntity : item;
    }).toList(growable: false);
    _learningSnapshot = _learningCore.snapshot;
    _appendEvent(
      PipelineEvent(
        type: PipelineEventType.learningCorrection,
        message:
            'Stored correction for ${entity.stableLabel}: ${entity.classLabel} -> $correctedLabel.',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<void> markEntityFalsePositive(TrackedEntity entity) async {
    final frame = _lastFrameContext ?? _fallbackFrame();
    await _learningCore.markFalsePositive(
      entity: entity,
      frame: frame,
      settings: _settings,
    );
    _trackedEntities = _trackedEntities
        .where((item) => item.trackId != entity.trackId)
        .toList(growable: false);
    _learningSnapshot = _learningCore.snapshot;
    _appendEvent(
      PipelineEvent(
        type: PipelineEventType.falsePositive,
        message: 'Flagged ${entity.stableLabel} as a false positive.',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<String?> exportLearningDataset() async {
    final exportPath = await _learningCore.exportTrainingDataset();
    _learningSnapshot = _learningCore.snapshot;
    if (exportPath != null) {
      _appendEvent(
        PipelineEvent(
          type: PipelineEventType.datasetExport,
          message: 'Exported learning dataset to $exportPath.',
          timestamp: DateTime.now(),
        ),
      );
      notifyListeners();
    }
    return exportPath;
  }

  Future<void> clearLearnedMemory() async {
    await _learningCore.clearAllLearning();
    _trackedEntities =
        _trackedEntities.map((entity) => entity.resetLearningState()).toList();
    _learningSnapshot = _learningCore.snapshot;
    _appendEvent(
      PipelineEvent(
        type: PipelineEventType.memoryReset,
        message: 'Cleared Sentinel Learning Core memory.',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<void> _handleFrame(FrameContext frame) async {
    if (!_isProcessing || _isProcessingFrame) {
      return;
    }

    _isProcessingFrame = true;
    _lastFrameContext = frame;
    final start = DateTime.now();

    try {
      _errorMessage = null;
      _sourceState = _mediaSourceService.sourceState;

      List<DetectionResult> detections = const <DetectionResult>[];
      if (_settings.detectionEnabled) {
        detections = await _detector.detect(frame);
        detections = detections
            .where((detection) => detection.confidence >= _settings.confidenceThreshold)
            .toList(growable: false);
      }

      List<TrackedEntity> entities;
      if (_settings.trackingEnabled) {
        entities = _tracker.update(detections, frame);
      } else {
        entities = detections.map((detection) {
          return TrackedEntity(
            trackId: detection.id,
            stableLabel: detection.classLabel,
            classLabel: detection.classLabel,
            boundingBox: detection.boundingBox,
            confidence: detection.confidence,
            detectorConfidence: detection.confidence,
            firstSeenAt: detection.timestamp,
            lastSeenAt: detection.timestamp,
          );
        }).toList(growable: false);
      }

      if (_settings.trackingEnabled && _settings.reidentificationEnabled) {
        final resolution = _identityRegistry.reconcile(
          entities,
          frame,
          persistence: _settings.identityPersistence,
        );
        entities = resolution.tracks;
        for (final event in resolution.events) {
          _appendEvent(event);
        }
      } else if (_settings.trackingEnabled) {
        entities = entities.map((entity) {
          return entity.copyWith(stableLabel: entity.trackId);
        }).toList(growable: false);
      }

      if (_settings.semanticLabelerEnabled) {
        entities = await _semanticLabeler.refine(entities, frame);
      }

      final learningResult = await _learningCore.observeFrame(
        frame: frame,
        entities: entities,
        settings: _settings,
      );
      entities = learningResult.entities;
      _learningSnapshot = _learningCore.snapshot;
      for (final event in learningResult.events) {
        _appendEvent(event);
      }

      _trackedEntities = entities;
      _recentDetections = <DetectionResult>[
        ...detections.reversed,
        ..._recentDetections,
      ].take(24).toList(growable: false);

      _maybeLogDetectionEvent(detections, frame.timestamp);
      _refreshMetrics(DateTime.now().difference(start));
    } catch (error) {
      _errorMessage = error.toString();
      _appendEvent(
        PipelineEvent(
          type: PipelineEventType.pipelineState,
          message: 'Frame processing error: $_errorMessage',
          timestamp: DateTime.now(),
        ),
      );
    } finally {
      _isProcessingFrame = false;
      notifyListeners();
    }
  }

  void _maybeLogDetectionEvent(
    List<DetectionResult> detections,
    DateTime timestamp,
  ) {
    final shouldLog = _lastDetectionCount != detections.length ||
        _lastDetectionEventAt == null ||
        timestamp.difference(_lastDetectionEventAt!) > const Duration(seconds: 2);

    if (!shouldLog) {
      return;
    }

    _lastDetectionEventAt = timestamp;
    _lastDetectionCount = detections.length;

    _appendEvent(
      PipelineEvent(
        type: PipelineEventType.detection,
        message:
            'Processed ${detections.length} detection(s) from ${_sourceState.type.label.toLowerCase()}.',
        timestamp: timestamp,
        details: <String, Object?>{
          'count': detections.length,
          'source': _sourceState.type.label,
        },
      ),
    );
  }

  void _refreshMetrics(Duration latency) {
    final now = DateTime.now();
    _frameWindow.add(now);
    _frameWindow.removeWhere(
      (stamp) => now.difference(stamp) > const Duration(seconds: 3),
    );

    final fps = _frameWindow.length < 2
        ? 0.0
        : _frameWindow.length / 3;

    _metrics = _metrics.copyWith(
      fps: fps,
      frameLatencyMs: latency.inMicroseconds / 1000,
      processedFrames: _metrics.processedFrames + 1,
      lastFrameAt: now,
    );
  }

  void _appendEvent(PipelineEvent event) {
    _eventLog.add(event);
    if (_eventLog.length > 180) {
      _eventLog.removeAt(0);
    }
  }

  FrameContext _fallbackFrame() {
    return FrameContext(
      frameNumber: 0,
      sourceSize: sourceSize ?? const Size(1280, 720),
      timestamp: DateTime.now(),
      sourceType: _sourceState.type,
    );
  }
}
