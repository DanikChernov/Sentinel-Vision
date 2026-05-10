#  Sentinel Vision Mobile

Sentinel Vision Mobile is a local-first Flutter/Dart mobile vision console for on-device object detection, tracking, identity persistence, semantic crop labeling, and adaptive learning. The app is structured so detector, tracker, identity memory, semantic labeling, and learning can evolve independently without hard-coding the app around one model family.

Current runtime stack:

- live camera inference through Flutter `camera`
- local video-file inference through extracted video frames
- on-device object detection with direct LiteRT/TFLite EfficientDet inference
- separate semantic crop labeling with Google ML Kit image labeling
- heuristic tracking and identity recovery
- Sentinel Learning Core for local memory, corrections, pattern history, and dataset export

## What Works

- realtime camera preview with tracked overlays
- stable labels such as `person-001`
- confidence display, FPS, latency, and event logging
- local identity persistence and recovery after brief misses
- user correction storage and false-positive feedback
- adaptive label refinement from local usage
- optional crop capture plus training-dataset export
- Android-first runtime path, with iOS preparation kept current where practical

## Architecture

```text
camera frame / video frame
-> detector
-> tracker
-> identity registry
-> semantic labeler
-> Sentinel Learning Core
-> refined output
-> user feedback
-> local memory update
```

Project layout:

```text
lib/
  app.dart
  main.dart
  models/
  screens/
    dashboard_screen.dart
    event_log_screen.dart
    learning_screen.dart
    live_view_screen.dart
    settings_screen.dart
  services/
    camera/
      frame_image_utils.dart
      media_source_service.dart
    detection/
      detector.dart
      litert_object_detector.dart
    identity/
    labeling/
      mlkit_semantic_labeler.dart
      semantic_labeler.dart
    learning/
      adaptive_label_refiner.dart
      feedback_trainer.dart
      identity_pattern_memory.dart
      learning_core.dart
      training_sample_exporter.dart
      usage_memory_store.dart
    pipeline/
    tracking/
  widgets/
```

## Perception Modules

### Detector

`LiteRtObjectDetector` is the active detector backend. It uses `flutter_litert` directly with bundled EfficientDet-Lite assets and Dart-side post-processing.

- COCO-style object classes, including `person`
- camera-stream inference from raw image planes
- encoded-frame inference for local video files
- clear TODO path for future ONNX or API backends

### Semantic Labeler

`MlKitSemanticLabeler` remains separate from detection. It crops tracked entities from the current frame and sends those crops through ML Kit image labeling.

- semantic refinement is post-detection and post-tracking
- a small cache keeps repeated labels practical on-device
- detector class labels and semantic labels stay decoupled

### Tracking and Identity

- `HeuristicTracker` keeps frame-to-frame tracks alive across short gaps
- `HeuristicIdentityRegistry` assigns persistent labels such as `person-001`
- `SentinelLearningCore` reinforces repeated identities over time using local history

## Sentinel Learning Core

The learning layer is local-first and intentionally real, not decorative:

- every visible observation is stored with confidence, source, timestamp, and box metadata
- user corrections are stored locally and reused later
- false positives are remembered
- repeated identities accumulate confidence and correction history
- crop samples can be saved and exported for later fine-tuning

Stored data includes:

- observations
- corrections
- identity patterns
- label mappings
- training samples

This creates a continual-learning-ready path for later TFLite personalization, ONNX model swaps, vector embedding identity memory, or exported QLoRA-style workflows without pretending the MVP retrains the detector on-device today.

## Source Modes

- `Camera`: live device camera stream for realtime inference
- `Video file`: local video playback plus extracted frame inference
- `Future stream`: reserved hook for later RTSP/WebRTC/API sources

## Settings and Backend Selection

The active backend today is:

- `LiteRT / TFLite`

The UI still exposes:

- `ONNX Hook`
- `Remote/Local API Hook`

Those entries are architecture hooks only. If selected, the controller rejects them and keeps the active LiteRT backend until those integrations are implemented.

## Local Storage and Privacy

- learning memory stays on-device through `sqflite`
- crop samples and exported datasets are written to local app support storage
- no cloud dependency is required
- the app includes controls to clear learned memory and export collected training data

## Future Integration Path

The app is ready for:

- custom LiteRT/TFLite detector swaps
- ONNX runtime detector integration
- vector embedding re-identification
- exported training data for later offline fine-tuning
- subtle Epyk-3-style modular perception experiments
- subtle Myne-2-style spatial and local-AI processing experiments

## Platform Notes

Android is the primary target.

iOS support is kept compatible where practical for the current plugin mix:

- `ios/Podfile` now targets iOS `15.5`
- `ios/Runner.xcodeproj` deployment target is `15.5`
- `ios/Runner/Info.plist` includes camera and photo-library usage descriptions

## Running

1. Install Flutter with a Dart SDK compatible with `>=3.10.0 <4.0.0`.
2. Run `flutter pub get`.
3. On Windows, enable Developer Mode if Flutter asks for symlink support.
4. For iOS, run `pod install` in `ios/` after `flutter pub get`.
5. Run `flutter run`.

## Tests

The current unit tests cover:

- detector contract timestamp behavior
- tracker identity continuity
- identity recovery after track replacement
- corrected-label reuse in Sentinel Learning Core
- learned person alias reinforcement
- dataset export beyond the recent-sample dashboard cache

Run them with:

```bash
flutter test -r expanded
```
