import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../../models/app_settings.dart';
import '../../models/detection_result.dart';
import '../../models/frame_context.dart';
import '../../models/inference_diagnostics.dart';
import '../../models/learning_models.dart';
import '../../models/persistence_models.dart';
import '../../models/pipeline_event.dart';
import '../../models/pipeline_metrics.dart';
import '../../models/stage_timing_breakdown.dart';
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
import '../models/detection/yolo26_detection_adapter.dart';
import '../models/tracking/heuristic_tracker_adapter.dart';
import '../orchestrator/perception_orchestrator.dart';
import '../orchestrator/perception_result.dart';
import '../persistence/persistence_processor.dart';
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
    PersistenceProcessor? persistenceProcessor,
    PerceptionOrchestrator? perceptionOrchestrator,
  }) : _mediaSourceService = mediaSourceService ?? MediaSourceService(),
       _detector = detector ?? LiteRtObjectDetector(),
       _tracker = tracker ?? HeuristicTracker(),
       _identityRegistry = identityRegistry ?? HeuristicIdentityRegistry(),
       _semanticLabeler = semanticLabeler ?? MlKitSemanticLabeler(),
       _learningCore = learningCore ?? SentinelLearningCore(),
       _persistenceProcessor = persistenceProcessor ?? PersistenceProcessor() {
    _perceptionOrchestrator =
        perceptionOrchestrator ??
        PerceptionOrchestrator(
          detectionAdapter: Yolo26DetectionAdapter(detector: _detector),
          trackerAdapter: HeuristicTrackerAdapter(tracker: _tracker),
        );
  }

  final MediaSourceService _mediaSourceService;
  final Detector _detector;
  final Tracker _tracker;
  final IdentityRegistry _identityRegistry;
  final SemanticLabeler _semanticLabeler;
  final SentinelLearningCore _learningCore;
  final PersistenceProcessor _persistenceProcessor;
  late final PerceptionOrchestrator _perceptionOrchestrator;
  final ValueNotifier<List<TrackedEntity>> _trackedEntitiesNotifier =
      ValueNotifier<List<TrackedEntity>>(const <TrackedEntity>[]);
  final ValueNotifier<PipelineMetrics> _metricsNotifier =
      ValueNotifier<PipelineMetrics>(const PipelineMetrics());
  final ValueNotifier<DetectorDiagnostics> _diagnosticsNotifier =
      ValueNotifier<DetectorDiagnostics>(
        const DetectorDiagnostics(backendName: 'LiteRT / TFLite Detector'),
      );
  final ValueNotifier<StageTimingBreakdown> _stageTimingNotifier =
      ValueNotifier<StageTimingBreakdown>(const StageTimingBreakdown());
  final ValueNotifier<VideoSourceState> _sourceStateNotifier =
      ValueNotifier<VideoSourceState>(
        const VideoSourceState(
          type: VisionSourceType.camera,
          label: 'Booting source',
          isReady: false,
        ),
      );
  final ValueNotifier<Size?> _sourceSizeNotifier = ValueNotifier<Size?>(null);
  final ValueNotifier<bool> _processingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<PerceptionResult?> _perceptionResultNotifier =
      ValueNotifier<PerceptionResult?>(null);

  AppSettings _settings = const AppSettings();
  LearningSnapshot _learningSnapshot = const LearningSnapshot();
  PersistenceSnapshot _persistenceSnapshot = const PersistenceSnapshot();
  PipelineMetrics _metrics = const PipelineMetrics();
  DetectorDiagnostics _inferenceDiagnostics = const DetectorDiagnostics(
    backendName: 'LiteRT / TFLite Detector',
  );
  VideoSourceState _sourceState = const VideoSourceState(
    type: VisionSourceType.camera,
    label: 'Booting source',
    isReady: false,
  );
  final List<PipelineEvent> _eventLog = <PipelineEvent>[];
  final List<DateTime> _frameWindow = <DateTime>[];
  final ListQueue<FrameContext> _frameQueue = ListQueue<FrameContext>();
  List<TrackedEntity> _trackedEntities = const <TrackedEntity>[];
  List<DetectionResult> _recentDetections = const <DetectionResult>[];
  PerceptionResult? _lastPerceptionResult;
  StageTimingBreakdown _stageTimingBreakdown = const StageTimingBreakdown();
  bool _isInitializing = false;
  bool _isProcessing = false;
  bool _isProcessingFrame = false;
  bool _isDrainingQueue = false;
  String _pipelineStatus = 'Idle';
  String? _errorMessage;
  DateTime? _lastDetectionEventAt;
  DateTime? _lastAcceptedFrameAt;
  int _lastDetectionCount = -1;
  int _skippedFrames = 0;
  FrameContext? _lastFrameContext;
  Duration _adaptiveFrameInterval = Duration.zero;
  DetectorTestResult? _lastDetectorTestResult;

  AppSettings get settings => _settings;
  LearningSnapshot get learningSnapshot => _learningSnapshot;
  PersistenceSnapshot get persistenceSnapshot => _persistenceSnapshot;
  PipelineMetrics get metrics => _metrics;
  DetectorDiagnostics get inferenceDiagnostics => _inferenceDiagnostics;
  VideoSourceState get sourceState => _sourceState;
  List<PipelineEvent> get eventLog => List.unmodifiable(_eventLog.reversed);
  List<TrackedEntity> get trackedEntities =>
      List.unmodifiable(_trackedEntities);
  List<DetectionResult> get recentDetections =>
      List.unmodifiable(_recentDetections);
  ValueListenable<List<TrackedEntity>> get trackedEntitiesListenable =>
      _trackedEntitiesNotifier;
  ValueListenable<PipelineMetrics> get metricsListenable => _metricsNotifier;
  ValueListenable<DetectorDiagnostics> get diagnosticsListenable =>
      _diagnosticsNotifier;
  ValueListenable<StageTimingBreakdown> get stageTimingListenable =>
      _stageTimingNotifier;
  ValueListenable<VideoSourceState> get sourceStateListenable =>
      _sourceStateNotifier;
  ValueListenable<Size?> get sourceSizeListenable => _sourceSizeNotifier;
  ValueListenable<bool> get processingListenable => _processingNotifier;
  ValueListenable<PerceptionResult?> get perceptionResultListenable =>
      _perceptionResultNotifier;
  bool get isInitializing => _isInitializing;
  bool get isProcessing => _isProcessing;
  String get pipelineStatus => _pipelineStatus;
  String? get errorMessage => _errorMessage;
  int get identityMemoryCount => _identityRegistry.knownIdentityCount;
  IdentityRegistryDiagnostics get identityDiagnostics =>
      _identityRegistry.diagnostics;
  int get learningMemoryCount => _learningSnapshot.identities.length;
  DetectorTestResult? get lastDetectorTestResult => _lastDetectorTestResult;
  StageTimingBreakdown get stageTimingBreakdown => _stageTimingBreakdown;
  PerceptionResult? get perceptionResult => _lastPerceptionResult;
  String get detectorLabel => _detector.backendLabel;
  String get labelerLabel => _semanticLabeler.labelerName;
  CameraController? get cameraController =>
      _mediaSourceService.cameraController;
  VideoPlayerController? get videoController =>
      _mediaSourceService.videoController;
  double get previewAspectRatio => _mediaSourceService.previewAspectRatio;
  Size? get sourceSize => _mediaSourceService.sourceSize;
  List<ModelBackend> get availableBackends => const <ModelBackend>[
    ModelBackend.tflite,
  ];
  List<InferenceAcceleration> get availableAccelerations =>
      const <InferenceAcceleration>[
        InferenceAcceleration.auto,
        InferenceAcceleration.cpu,
        InferenceAcceleration.xnnpack,
      ];
  List<int> get supportedModelInputSizes {
    final shape = _inferenceDiagnostics.inputShape;
    if (shape.length == 4 && shape[1] > 0 && shape[1] == shape[2]) {
      return <int>[shape[1]];
    }
    return const <int>[320];
  }

  bool isBackendAvailable(ModelBackend backend) {
    return availableBackends.contains(backend);
  }

  bool isAccelerationAvailable(InferenceAcceleration acceleration) {
    return availableAccelerations.contains(acceleration);
  }

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
      await _persistenceProcessor.initialize();
      _persistenceSnapshot = _persistenceProcessor.snapshot;
      await _detector.initialize();
      await _detector.applySettings(_settings);
      await _perceptionOrchestrator.initialize(_settings);
      _inferenceDiagnostics = _detector.diagnostics;
      _publishDiagnostics();
      await _semanticLabeler.initialize();

      _pipelineStatus = 'Initializing media source';
      notifyListeners();

      await _mediaSourceService.initialize();
      _sourceState = _mediaSourceService.sourceState;
      _publishSourceState();
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
      _publishMetrics();
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
    _frameQueue.clear();
    _skippedFrames = 0;
    _adaptiveFrameInterval = Duration.zero;
    _lastAcceptedFrameAt = null;
    _pipelineStatus = 'Processing ${_sourceState.type.label.toLowerCase()}';
    _errorMessage = null;
    _processingNotifier.value = true;
    _updatePipelineMetrics();
    _appendEvent(
      PipelineEvent(
        type: PipelineEventType.pipelineState,
        message: 'Started pipeline on ${_sourceState.type.label}.',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();

    await _mediaSourceService.start(_enqueueFrame);
  }

  Future<void> stopProcessing() async {
    if (!_isProcessing) {
      return;
    }

    _isProcessing = false;
    _isProcessingFrame = false;
    _isDrainingQueue = false;
    _frameQueue.clear();
    _pipelineStatus = 'Stopped';
    _processingNotifier.value = false;
    await _mediaSourceService.stop();
    _updatePipelineMetrics();
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
    _publishSourceState();
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
    _publishSourceState();
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
    final previousSettings = _settings;
    final previousBackend = _settings.backend;
    final validation = _validatedSettings(settings, previousSettings);
    final nextSettings = validation.settings;

    for (final message in validation.messages) {
      _appendEvent(
        PipelineEvent(
          type: PipelineEventType.pipelineState,
          message: message,
          timestamp: DateTime.now(),
        ),
      );
    }

    _settings = nextSettings;
    unawaited(_applyRuntimeSettings(previousSettings, _settings));

    if (!_settings.trackingEnabled) {
      _tracker.reset();
      _perceptionOrchestrator.resetTracking();
      _trackedEntities = const <TrackedEntity>[];
      _publishTrackedEntities();
    }

    if (!_settings.reidentificationEnabled) {
      _identityRegistry.reset();
    }

    if (!_settings.faceAnalysisPersistenceEnabled) {
      _appendEvent(
        PipelineEvent(
          type: PipelineEventType.pipelineState,
          message:
              'Face analysis persistence disabled. Embedding memory is retained locally.',
          timestamp: DateTime.now(),
        ),
      );
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

  _SettingsValidation _validatedSettings(
    AppSettings requested,
    AppSettings previous,
  ) {
    var next = requested;
    final messages = <String>[];

    if (!isBackendAvailable(requested.backend)) {
      next = next.copyWith(backend: previous.backend);
      messages.add(
        '${requested.backend.label} is not implemented. Keeping ${previous.backend.label}.',
      );
    }

    if (!isAccelerationAvailable(requested.acceleration)) {
      final fallback = isAccelerationAvailable(previous.acceleration)
          ? previous.acceleration
          : InferenceAcceleration.auto;
      next = next.copyWith(acceleration: fallback);
      messages.add(
        '${requested.acceleration.label} acceleration is unavailable on this build. Keeping ${fallback.label}.',
      );
    }

    final supportedSizes = supportedModelInputSizes;
    if (!supportedSizes.contains(requested.modelInputSize)) {
      final fallback = supportedSizes.contains(previous.modelInputSize)
          ? previous.modelInputSize
          : supportedSizes.first;
      next = next.copyWith(modelInputSize: fallback);
      messages.add(
        'Model input ${requested.modelInputSize} is unsupported by the active model. Keeping ${fallback}x$fallback.',
      );
    }

    return _SettingsValidation(settings: next, messages: messages);
  }

  Future<void> _applyRuntimeSettings(
    AppSettings previousSettings,
    AppSettings nextSettings,
  ) async {
    final detectorConfigChanged =
        previousSettings.acceleration != nextSettings.acceleration ||
        previousSettings.modelInputSize != nextSettings.modelInputSize ||
        previousSettings.tfliteThreadCount != nextSettings.tfliteThreadCount;
    final cameraProfileChanged =
        previousSettings.cameraCaptureProfile !=
        nextSettings.cameraCaptureProfile;
    final requiresRestart = detectorConfigChanged || cameraProfileChanged;
    final resumeProcessing = requiresRestart && _isProcessing;

    if (resumeProcessing) {
      await stopProcessing();
    }

    try {
      if (cameraProfileChanged) {
        await _mediaSourceService.updateCameraCaptureProfile(
          nextSettings.cameraCaptureProfile,
        );
        _sourceState = _mediaSourceService.sourceState;
        _publishSourceState();
      }

      if (detectorConfigChanged) {
        await _detector.applySettings(nextSettings);
        final testResult = await _detector.runTestInference(
          frame: _lastFrameContext,
        );
        _lastDetectorTestResult = testResult;
        if (!testResult.success) {
          throw StateError('Detector self-test failed: ${testResult.message}');
        }
      }
      await _perceptionOrchestrator.applySettings(nextSettings);

      _inferenceDiagnostics = _detector.diagnostics;
      _publishDiagnostics();
      _pipelineStatus = _sourceState.isReady ? 'Ready' : _pipelineStatus;
      notifyListeners();
    } catch (error) {
      _settings = previousSettings;
      _errorMessage = error.toString();
      try {
        await _detector.applySettings(previousSettings);
        await _perceptionOrchestrator.applySettings(previousSettings);
        _inferenceDiagnostics = _detector.diagnostics;
        _publishDiagnostics();
      } catch (rollbackError) {
        _errorMessage =
            'Runtime settings update failed: $error; rollback failed: $rollbackError';
      }
      _appendEvent(
        PipelineEvent(
          type: PipelineEventType.pipelineState,
          message:
              'Runtime settings update failed and previous settings were restored: $_errorMessage',
          timestamp: DateTime.now(),
        ),
      );
      notifyListeners();
    } finally {
      if (resumeProcessing && _sourceState.isReady) {
        await startProcessing();
      }
    }
  }

  void clearEventLog() {
    _eventLog.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_mediaSourceService.dispose());
    unawaited(_detector.dispose());
    unawaited(_perceptionOrchestrator.dispose());
    unawaited(_semanticLabeler.dispose());
    unawaited(_learningCore.dispose());
    unawaited(_persistenceProcessor.dispose());
    _trackedEntitiesNotifier.dispose();
    _metricsNotifier.dispose();
    _diagnosticsNotifier.dispose();
    _stageTimingNotifier.dispose();
    _sourceStateNotifier.dispose();
    _sourceSizeNotifier.dispose();
    _processingNotifier.dispose();
    _perceptionResultNotifier.dispose();
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
    _trackedEntities = _trackedEntities
        .map((item) {
          return item.trackId == entity.trackId ? updatedEntity : item;
        })
        .toList(growable: false);
    _publishTrackedEntities();
    await _persistenceProcessor.registerCorrection(updatedEntity);
    _learningSnapshot = _learningCore.snapshot;
    _persistenceSnapshot = _persistenceProcessor.snapshot;
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
    _publishTrackedEntities();
    _learningSnapshot = _learningCore.snapshot;
    _persistenceSnapshot = _persistenceProcessor.snapshot;
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
    final exportPath = await _learningCore.exportTrainingDataset(
      perceptionResult: _lastPerceptionResult,
    );
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
    _trackedEntities = _trackedEntities
        .map((entity) => entity.resetLearningState())
        .toList();
    _publishTrackedEntities();
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

  Future<void> clearEmbeddingMemory() async {
    await _persistenceProcessor.clearMemory();
    _persistenceSnapshot = _persistenceProcessor.snapshot;
    _appendEvent(
      PipelineEvent(
        type: PipelineEventType.memoryReset,
        message: 'Cleared face-analysis embedding memory.',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<DetectorTestResult> runDetectorSelfTest() async {
    final frame = _lastFrameContext;
    final result = await _detector.runTestInference(frame: frame);
    _lastDetectorTestResult = result;
    _inferenceDiagnostics = _detector.diagnostics.copyWith(
      queueDepth: _frameQueue.length,
      skippedFrames: _skippedFrames,
      trackerInputCount: _inferenceDiagnostics.trackerInputCount,
      trackerOutputCount: _inferenceDiagnostics.trackerOutputCount,
    );
    _publishDiagnostics();
    _appendEvent(
      PipelineEvent(
        type: PipelineEventType.pipelineState,
        message: result.success
            ? 'Detector self-test completed.'
            : 'Detector self-test failed: ${result.message}',
        timestamp: DateTime.now(),
        details: <String, Object?>{
          'inputShape': result.inputShape.join('x'),
          'outputs': result.outputShapes
              .map((shape) => shape.join('x'))
              .join(', '),
        },
      ),
    );
    notifyListeners();
    return result;
  }

  Future<void> _enqueueFrame(FrameContext frame) async {
    if (!_isProcessing) {
      return;
    }

    if (_lastAcceptedFrameAt != null &&
        _adaptiveFrameInterval > Duration.zero &&
        frame.timestamp.difference(_lastAcceptedFrameAt!) <
            _adaptiveFrameInterval) {
      _skippedFrames += 1;
      _updatePipelineMetrics();
      return;
    }

    _lastAcceptedFrameAt = frame.timestamp;
    if (_frameQueue.isNotEmpty) {
      _skippedFrames += _frameQueue.length;
      _frameQueue.clear();
    }
    _frameQueue.addLast(frame);

    _updatePipelineMetrics();
    if (_isDrainingQueue) {
      return;
    }
    _isDrainingQueue = true;
    unawaited(_drainFrameQueue());
  }

  Future<void> _drainFrameQueue() async {
    while (_isProcessing && _frameQueue.isNotEmpty) {
      final frame = _frameQueue.removeFirst();
      _updatePipelineMetrics();
      await _processFrame(frame);
    }
    _isDrainingQueue = false;
  }

  Future<void> _processFrame(FrameContext frame) async {
    if (!_isProcessing || _isProcessingFrame) {
      return;
    }

    _isProcessingFrame = true;
    _lastFrameContext = frame;
    final totalWatch = Stopwatch()..start();

    try {
      _errorMessage = null;
      _sourceState = _mediaSourceService.sourceState;
      _publishSourceState();

      final trackingWatch = Stopwatch()..start();
      final perceptionResult = await _perceptionOrchestrator.processFrame(
        frame: frame,
        settings: _settings,
      );
      var detections = perceptionResult.detections;
      var entities = perceptionResult.tracks;
      _lastPerceptionResult = perceptionResult;
      _publishPerceptionResult();
      _inferenceDiagnostics = _detector.diagnostics;
      _publishDiagnostics();

      if (_settings.trackingEnabled && _settings.reidentificationEnabled) {
        final resolution = _identityRegistry.reconcile(
          entities,
          frame,
          persistence: _settings.identityPersistence,
          confidenceThreshold: _settings.reIdConfidenceThreshold,
        );
        entities = resolution.tracks;
        for (final event in resolution.events) {
          _appendEvent(event);
        }
      } else if (_settings.trackingEnabled) {
        entities = entities
            .map((entity) {
              return entity.copyWith(
                stableLabel: entity.trackId,
                clearPersistentEntityId: true,
              );
            })
            .toList(growable: false);
      }

      if (_settings.semanticLabelerEnabled) {
        entities = await _semanticLabeler.refine(entities, frame);
      }
      trackingWatch.stop();

      final persistenceWatch = Stopwatch()..start();
      if (_settings.faceAnalysisPersistenceEnabled) {
        final persistenceResult = await _persistenceProcessor.process(
          frame: frame,
          entities: entities,
          settings: _settings,
        );
        entities = persistenceResult.entities;
        _persistenceSnapshot = persistenceResult.snapshot;
        for (final event in persistenceResult.events) {
          _appendEvent(event);
        }
      }
      persistenceWatch.stop();

      final learningWatch = Stopwatch()..start();
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
      learningWatch.stop();

      _trackedEntities = entities;
      _publishTrackedEntities();
      _lastPerceptionResult = _lastPerceptionResult?.copyWith(
        tracks: entities,
        overlayItems: _overlayItemsForEntities(
          entities,
          _lastPerceptionResult?.segmentations ?? const <SegmentationResult>[],
          _lastPerceptionResult?.identities ?? const <IdentityFusionResult>[],
        ),
      );
      _publishPerceptionResult();
      _recentDetections = <DetectionResult>[
        ...detections.reversed,
        ..._recentDetections,
      ].take(24).toList(growable: false);

      final loggingWatch = Stopwatch()..start();
      _syncInferenceDiagnostics(
        trackerInputCount: detections.length,
        trackerOutputCount: entities.length,
      );
      _maybeLogDetectionEvent(detections, frame.timestamp);
      loggingWatch.stop();
      totalWatch.stop();
      _stageTimingBreakdown = _stageTimingBreakdown.copyWith(
        sourceAcquisitionMs: _inferenceDiagnostics.sourceAcquisitionMs,
        colorConversionMs: _inferenceDiagnostics.colorConversionMs,
        rotationMs: _inferenceDiagnostics.rotationMs,
        resizeMs: _inferenceDiagnostics.resizeMs,
        normalizationMs: _inferenceDiagnostics.normalizationMs,
        tensorCopyMs: _inferenceDiagnostics.tensorCopyMs,
        inferenceMs: _inferenceDiagnostics.inferenceMs,
        outputParsingMs: _inferenceDiagnostics.outputParsingMs,
        trackingMs: trackingWatch.elapsedMicroseconds / 1000,
        persistenceMs: persistenceWatch.elapsedMicroseconds / 1000,
        learningMs: learningWatch.elapsedMicroseconds / 1000,
        loggingMs: loggingWatch.elapsedMicroseconds / 1000,
        totalPipelineMs: totalWatch.elapsedMicroseconds / 1000,
        pipelinePath:
            '${_sourceState.type.label.toLowerCase()} -> frame scheduler'
            ' -> perception orchestrator -> detector/segmentation/tracker'
            ' -> identity fusion -> persistence -> learning',
      );
      _publishStageTimings();
      _refreshMetrics(totalWatch.elapsed);
    } catch (error) {
      totalWatch.stop();
      _errorMessage = error.toString();
      _syncInferenceDiagnostics(lastError: _errorMessage);
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
    final shouldLog =
        _lastDetectionCount != detections.length ||
        _lastDetectionEventAt == null ||
        timestamp.difference(_lastDetectionEventAt!) >
            const Duration(seconds: 2);

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
          'rawClassIds': _inferenceDiagnostics.rawClassIds.join(', '),
          'mappedLabels': _inferenceDiagnostics.mappedLabels.join(', '),
          'unknownLabelCount': _inferenceDiagnostics.unknownLabelCount,
          'labelMapLoaded': _inferenceDiagnostics.labelMapLoaded,
          'labelMapName': _inferenceDiagnostics.labelMapName,
        },
      ),
    );

    if (_inferenceDiagnostics.unknownLabelCount > 0) {
      _appendEvent(
        PipelineEvent(
          type: PipelineEventType.pipelineState,
          message:
              'Missing label map entries for class id(s): ${_inferenceDiagnostics.missingClassIds.join(', ')}.',
          timestamp: timestamp,
        ),
      );
    }
  }

  void _refreshMetrics(Duration latency) {
    final now = DateTime.now();
    _frameWindow.add(now);
    _frameWindow.removeWhere(
      (stamp) => now.difference(stamp) > const Duration(seconds: 3),
    );

    final fps = _frameWindow.length < 2 ? 0.0 : _frameWindow.length / 3;
    final latencyMs = latency.inMicroseconds / 1000;
    _adaptiveFrameInterval = switch (latencyMs) {
      > 260 => const Duration(milliseconds: 220),
      > 180 => const Duration(milliseconds: 120),
      > 120 => const Duration(milliseconds: 60),
      _ => Duration.zero,
    };
    final thermalThrottleSuggested =
        latencyMs > 220 || _frameQueue.length > 1 || _skippedFrames > 0;

    _metrics = _metrics.copyWith(
      fps: fps,
      frameLatencyMs: latencyMs,
      processedFrames: _metrics.processedFrames + 1,
      inferenceFrames: _metrics.inferenceFrames + 1,
      queuedFrames: _frameQueue.length,
      droppedFrames: _skippedFrames,
      adaptiveFrameIntervalMs: _adaptiveFrameInterval.inMilliseconds.toDouble(),
      thermalThrottleSuggested: thermalThrottleSuggested,
      lastFrameAt: now,
    );
    _syncInferenceDiagnostics();
    _publishMetrics();
  }

  void _updatePipelineMetrics() {
    _metrics = _metrics.copyWith(
      queuedFrames: _frameQueue.length,
      droppedFrames: _skippedFrames,
      adaptiveFrameIntervalMs: _adaptiveFrameInterval.inMilliseconds.toDouble(),
    );
    _syncInferenceDiagnostics();
    _publishMetrics();
  }

  void _syncInferenceDiagnostics({
    int? trackerInputCount,
    int? trackerOutputCount,
    String? lastError,
  }) {
    _inferenceDiagnostics = _detector.diagnostics.copyWith(
      queueDepth: _frameQueue.length,
      skippedFrames: _skippedFrames,
      trackerInputCount:
          trackerInputCount ?? _inferenceDiagnostics.trackerInputCount,
      trackerOutputCount:
          trackerOutputCount ?? _inferenceDiagnostics.trackerOutputCount,
      lastInferenceError: lastError,
      clearLastInferenceError: lastError == null,
    );
    _publishDiagnostics();
  }

  void recordLiveViewBuild() {
    _stageTimingBreakdown = _stageTimingBreakdown.copyWith(
      liveWidgetBuildCount: _stageTimingBreakdown.liveWidgetBuildCount + 1,
    );
    _publishStageTimings();
  }

  void recordOverlayRepaint(Duration duration) {
    final nextBreakdown = _stageTimingBreakdown.copyWith(
      overlayRepaintCount: _stageTimingBreakdown.overlayRepaintCount + 1,
      overlayRepaintMs: duration.inMicroseconds / 1000,
    );
    if (SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks ||
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.postFrameCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _stageTimingBreakdown = nextBreakdown;
        _publishStageTimings();
      });
      return;
    }
    _stageTimingBreakdown = nextBreakdown;
    _publishStageTimings();
  }

  void _publishTrackedEntities() {
    _trackedEntitiesNotifier.value = List<TrackedEntity>.from(
      _trackedEntities,
      growable: false,
    );
  }

  void _publishPerceptionResult() {
    _perceptionResultNotifier.value = _lastPerceptionResult;
  }

  List<PerceptionOverlayItem> _overlayItemsForEntities(
    List<TrackedEntity> entities,
    List<SegmentationResult> segmentations,
    List<IdentityFusionResult> identities,
  ) {
    return entities
        .map((entity) {
          final identity = identities.where(
            (item) => item.trackId == entity.trackId,
          );
          final mask = segmentations.where((segmentation) {
            return segmentation.associatedTrackId == entity.trackId ||
                segmentation.boundingBox.intersectionOverUnion(
                      entity.boundingBox,
                    ) >
                    0.4;
          });
          final identityItem = identity.isEmpty ? null : identity.first;
          return PerceptionOverlayItem(
            id: entity.trackId,
            label: entity.overlayLabel,
            classLabel: entity.effectiveClassLabel,
            trackLabel: entity.trackLabel,
            persistentEntityId:
                entity.persistentEntityId ?? identityItem?.persistentEntityId,
            boundingBox: entity.boundingBox,
            confidence: entity.displayConfidence,
            mask: mask.isEmpty ? null : mask.first,
            reasonBreakdown:
                identityItem?.reasonBreakdown ?? const <String, double>{},
          );
        })
        .toList(growable: false);
  }

  void _publishMetrics() {
    _metricsNotifier.value = _metrics;
  }

  void _publishDiagnostics() {
    _diagnosticsNotifier.value = _inferenceDiagnostics;
  }

  void _publishStageTimings() {
    _stageTimingNotifier.value = _stageTimingBreakdown;
  }

  void _publishSourceState() {
    _sourceStateNotifier.value = _sourceState;
    _sourceSizeNotifier.value = sourceSize;
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

class _SettingsValidation {
  const _SettingsValidation({required this.settings, required this.messages});

  final AppSettings settings;
  final List<String> messages;
}
