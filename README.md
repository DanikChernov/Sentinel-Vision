#  Sentinel Vision Mobile

Sentinel Vision Mobile is a local-first Flutter/Dart mobile vision console for on-device object detection, tracking, identity persistence, semantic crop labeling, face-analysis-assisted recovery, and adaptive learning. The app is structured so detector, tracker, persistence, identity memory, semantic labeling, and learning can evolve independently without hard-coding the app around one model family.

Current runtime stack:

- live camera inference through Flutter `camera`
- front-camera iris/eye-region app lock with local encrypted template matching
- optional device biometric and salted PIN fallback through local platform APIs
- local video-file inference through extracted video frames
- on-device object detection with direct LiteRT/TFLite EfficientDet inference
- central Perception Orchestrator for scheduling, latest-frame queues, and fusion
- YOLO26 detection and YOLO26-seg adapter hooks with no-output unavailable states
- optional SAM 3.1 refinement hook for local/server prompt-based masks
- modular face, object embedding, pose, depth, and scene-context adapters
- separate semantic crop labeling with Google ML Kit image labeling
- heuristic tracking plus face-analysis persistence
- Sentinel Learning Core for local memory, corrections, pattern history, and dataset export

## What Works

- realtime camera preview with tracked overlays
- first-launch primary admin enrollment before main app access
- cold-start, resume, background, and inactivity app locking
- 5-scan biometric login with 3 required local template matches
- admin-gated user management for adding, renaming, removing, and re-enrolling approved users
- detector class labels in overlays, for example `person #003 87%`
- separate short-term track IDs (`T-003`) and persistent entity IDs (`P-001`)
- stable persistent labels such as `person-001` after Re-ID recovery
- confidence display, FPS, latency, and event logging
- local identity persistence and recovery after brief misses
- face-analysis-assisted identity recovery with local descriptor embeddings
- user correction storage and false-positive feedback
- adaptive label refinement from local usage
- optional crop capture plus training-dataset export
- live inference diagnostics panel plus detector self-test
- label-map diagnostics, raw class IDs, mapped labels, and unknown-label counts
- safe backend/acceleration/resolution selection with rejection and rollback
- Android-first runtime path, with iOS preparation kept current where practical

## Architecture

```text
camera frame / video frame
-> latest-frame scheduler
-> Perception Orchestrator
-> YOLO26/LiteRT fast detector
-> YOLO26-seg realtime masks
-> optional SAM 3.1 mask refinement
-> tracker
-> face/person re-ID
-> object embedding recognition
-> pose processor
-> monocular depth processor
-> scene/context processor
-> identity fusion engine
-> semantic labeler and face persistence
-> Sentinel Learning Core
-> lightweight overlay painters
-> diagnostics/events
```

The preview remains independent from inference. The live frame queue is latest-frame-wins, stale pending work is dropped before new frames are accepted, and heavy modules publish deferred results without blocking the camera preview.

Project layout:

```text
lib/
  app.dart
  main.dart
  models/
    security/
  screens/
    dashboard_screen.dart
    event_log_screen.dart
    learning_screen.dart
    live_view_screen.dart
    settings_screen.dart
    security/
  services/
    camera/
      frame_image_utils.dart
      media_source_service.dart
    detection/
      detector.dart
      litert_object_detector.dart
    identity/
      identity_fusion_engine.dart
      identity_memory_store.dart
      persistent_entity.dart
      identity_confidence_score.dart
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
      correction_memory.dart
      adaptive_confidence_engine.dart
    models/
      detection/
      segmentation/
      tracking/
      reid/
      object_embeddings/
      pose/
      depth/
      scene/
    orchestrator/
      perception_orchestrator.dart
      perception_frame.dart
      perception_result.dart
      perception_schedule.dart
      model_task.dart
      model_task_queue.dart
      latency_budget.dart
      fusion_engine.dart
    persistence/
      persistence_processor.dart
      face_embedding_adapter.dart
      temporal_consistency_engine.dart
      identity_matcher.dart
      embedding_memory_store.dart
      face_alignment_processor.dart
    pipeline/
    security/
    tracking/
  widgets/
    overlays/
      perception_overlay_painter.dart
      mask_overlay_painter.dart
      pose_overlay_painter.dart
      depth_overlay_painter.dart
    security/
```

This is a local-first modular perception research app. Adapters without configured model files or local backends return no results and publish explicit diagnostics.

## Secure Biometric App Lock

Sentinel Vision gates the main app behind local authentication. This is an iris / eye-region biometric flow using the front camera; it is not described as a medical or hardware retina scan.

Security flow:

- first launch opens primary admin enrollment instead of the vision console
- enrollment captures multiple front-camera eye/face-region samples after basic liveness and quality checks
- login captures 5 scan attempts by default and unlocks only after 3 successful local matches
- the app locks on cold start, background, resume, and configurable inactivity timeout
- camera AI features, settings, model manager, and stored data remain behind `AuthGateScreen`
- Settings includes an Admin Security section for users, fallbacks, lock settings, and data clearing

Storage and privacy:

- biometric templates are encrypted locally with AES-GCM before being written to the app vault
- encryption keys and PIN salt are held through `flutter_secure_storage` / platform keystore or keychain
- raw eye images are not stored by default
- biometric data is not uploaded
- PIN fallback is optional and stored only as a salted HMAC hash
- device biometric fallback uses `local_auth` only when explicitly enabled

Implemented security modules:

- `AppLockService`: cold-start, lifecycle, background, and inactivity locking
- `BiometricAuthService`: enrollment, login, fallback auth, admin user management, failure cooldown
- `IrisScanService`: liveness gate plus adapter-driven template generation
- `BiometricTemplateStore`: encrypted local template vault and security settings
- `BiometricTemplateMatcher`: cosine similarity matching against enrolled local templates
- `SecurityAuditLog`: local security event history for enrollment, login, lock, and settings changes

Biometric adapters:

- `MockEyeBiometricAdapter`: development-only eye-region template generator, clearly labeled insecure and not production biometric security
- `FutureTFLiteIrisAdapter`: placeholder for a real local TFLite/LiteRT iris model
- `FutureONNXIrisAdapter`: placeholder for a future ONNX iris model
- `FaceEmbeddingFallbackAdapter`: placeholder for a future face embedding fallback

Liveness is intentionally basic in this build. It checks frame/eye presence proxies, brightness, blur, blink prompts, and small movement prompts. Production spoof resistance requires a real mobile biometric model or platform biometric fallback.

## Labels, Tracks, and Persistent IDs

Sentinel Vision keeps object class labels, short-term tracks, and long-term identities separate:

- `classLabel`: detector output mapped through the active label map, for example `person`, `book`, `tv`, `laptop`, `chair`, or `dining table`
- `trackId`: short-term frame-to-frame tracker ID, displayed as `#003` or `T-003`
- `persistentEntityId`: longer-term Re-ID memory ID, displayed as `P-001`

Default live overlay format:

```text
person #003 87%
```

When persistent identity is available:

```text
person P-001 / T-014 86%
```

The app does not use `track-###` as the object label. If a detector class ID cannot be mapped, the overlay uses `unknown #003` and diagnostics/event logs include the missing class IDs, label map loaded state, label map name, raw class IDs, mapped labels, and unknown-label count.

## Label Maps

The shipped detector uses `assets/models/labelmap.txt`, a COCO-style label map that matches the bundled EfficientDet Lite0 model. `LiteRtObjectDetector` also accepts a custom label-map asset path through its constructor. If the configured label map cannot be loaded, the detector falls back to a built-in COCO label list and reports the fallback in diagnostics.

When adding a custom detector:

1. Add the model under `assets/models/`.
2. Add the model and label map to `pubspec.yaml`.
3. Configure the detector/model adapter with both paths.
4. Run detector self-test.
5. Confirm tensor shapes, parser mode, label count, raw class IDs, and mapped labels in diagnostics.

## Perception Modules

### Perception Orchestrator

`PerceptionOrchestrator` is the central AI coordinator. It decides which model runs, when it runs, which detections or crops are eligible for heavier work, how much work is allowed per frame, when to skip or defer modules, and how to fuse outputs into smooth overlays.

Default scheduling:

- every frame: preview, lightweight track reuse/interpolation, overlay publishing
- every 3 frames: fast detection
- every 5 frames: YOLO26 segmentation when enabled
- every 10 frames: SAM refinement when enabled
- person-only: face alignment and face embedding re-ID
- uncertain objects only: object embedding recognition
- mode-gated: pose, depth, and scene context
- background path: learning memory, correction consolidation, export metadata, confidence recalculation

### Model Adapter System

Each model family has its own adapter interface with enabled state, backend name, initialization status, diagnostics, latency measurements, output counts, error state, and future LiteRT/TFLite, ONNX, or local API backend paths.

Adapter folders currently cover:

- `detection`: current LiteRT/TFLite detector and YOLO26 model path
- `segmentation`: YOLO26-seg, SAM 3.1, mask processing, polygon extraction
- `tracking`: heuristic tracker, ByteTrack backend slot, DeepSORT backend slot
- `reid`: InsightFace, ArcFace, MobileFaceNet backend slots, embedding matching, face alignment hooks
- `object_embeddings`: MobileCLIP, DINOv2, CLIP backend slots and object similarity matching
- `pose`: YOLO-pose, MediaPipe, RTMPose backend slots
- `depth`: DepthAnything and MiDaS backend slots
- `scene`: lightweight classifier and future VLM backend slot

### Detector

`LiteRtObjectDetector` remains the active runtime detector and is now wrapped by the YOLO26 detection adapter. The adapter name is future-facing: it supports the current LiteRT/TFLite path today and keeps the hooks needed for YOLO26 model files later.

- COCO-style object classes, including `person`
- camera-stream inference from raw image planes
- encoded-frame inference for local video files
- isolate-backed preprocessing and inference queueing
- parser support for EfficientDet split outputs, SSD-style outputs, `[1,84,8400]` / `[1,8400,84]`, and row-based `[N,6]` / `[N,7]` detectors
- visible diagnostics for model load state, tensor shapes, candidate counts, sample values, and last inference error
- visible label diagnostics for label-map loaded state, label-map name, label count, raw class IDs, mapped labels, unknown-label count, and missing class IDs
- safe runtime reconfiguration: acceleration/thread/input-size changes pause inference, reinitialize, run a self-test, and revert on failure
- clear TODO path for future ONNX or API backends

YOLO26 integration path:

1. Add the `.tflite` or LiteRT-compatible model under `assets/models/`.
2. Add the asset path in `pubspec.yaml`.
3. Point `Yolo26DetectionAdapter` or the detector constructor at the model path.
4. Run detector self-test and confirm input/output tensor shapes in diagnostics.
5. Unsupported output shapes are reported as parser errors and do not crash the app.

### YOLO26 Segmentation

`Yolo26SegmentationAdapter` defines the realtime instance segmentation contract. It is ready for boxes, classes, scores, mask coefficients, prototype masks, mask reconstruction, resizing to preview coordinates, and polygon extraction. Until a YOLO26-seg model is provided and its parser is wired, it returns no masks and reports `Selected model does not support segmentation. Configure a YOLO segmentation model separately.`

The bundled EfficientDet model is detection-only. Enabling segmentation with the bundled model is safe, but it is reported as unavailable and no fake masks are drawn.

Settings include segmentation enablement, mask drawing, polygon outlines, opacity, quality, and input size.

To add a YOLO segmentation model:

1. Add the segmentation `.tflite` or LiteRT-compatible model under `assets/models/`.
2. Add it to `pubspec.yaml`.
3. Configure `Yolo26SegmentationAdapter(modelAssetPath: ...)` separately from the detection model path.
4. Confirm the output tensors include boxes/classes/scores, mask coefficients, and prototype masks.
5. Wire or validate the parser for that model's tensor layout.
6. Run with segmentation enabled and check masks generated, polygons generated, tensor shapes, latency, and parser errors in diagnostics.

### SAM 3.1 Refinement

`Sam31SegmentationAdapter` is optional and does not replace YOLO26 detection or segmentation by default. It is intended for box prompt mode from YOLO boxes, text prompt mode where supported, video refinement mode for uploaded video, and selected object mode for tapped tracks.

The backend can be a local server, local-network server, or future mobile backend. If SAM is unavailable, SAM returns no masks and diagnostics report the missing backend URL or missing client implementation. Configure a local SAM backend by providing a backend URL in settings or wiring it into `Sam31SegmentationAdapter`. The current adapter does not upload frames to any cloud service.

### Semantic Labeler

`MlKitSemanticLabeler` remains separate from detection. It crops tracked entities from the current frame and sends those crops through ML Kit image labeling.

- semantic refinement is post-detection and post-tracking
- a small cache keeps repeated labels practical on-device
- detector class labels and semantic labels stay decoupled

### Tracking, Identity, and Persistence

- `HeuristicTracker` keeps frame-to-frame tracks alive across short gaps
- `HeuristicIdentityRegistry` assigns persistent labels such as `person-001` and writes them separately to `persistentEntityId`
- `IdentityMatchScore` records class, spatial, temporal, size, mask, embedding, correction, final score, accepted state, and reason
- `PersistenceProcessor` adds face detection, face alignment, local descriptor embeddings, temporal scoring, and local embedding memory for stronger person re-identification
- `SentinelLearningCore` reinforces repeated identities over time using local history

Minimum Re-ID behavior works without embeddings. A candidate recovery must match class label, fit within the memory timeout, and pass the configurable Re-ID confidence threshold using spatial, size, and temporal scoring. If confidence is too low, a new persistent ID is created instead of forcing a bad match. Track IDs can change while persistent IDs remain stable.

Face-analysis persistence is recognition-only:

- no face swapping
- no face generation
- no cloud lookup
- no real-world identity search
- user-assigned labels remain local

### Identity Fusion

`IdentityFusionEngine` combines tracker confidence, detection class consistency, face similarity, object embedding similarity, mask/shape similarity, pose presence, depth/location hints, temporal continuity, correction history, and learning confidence. It outputs a persistent entity ID, display label, final confidence, and a reason breakdown.

Example:

```json
{
  "tracker": 0.72,
  "face": 0.91,
  "objectEmbedding": 0.0,
  "maskShape": 0.64,
  "temporal": 0.8,
  "final": 0.86
}
```

The Identity Debug screen shows current fusion scores plus face persistence records.

### Pose, Depth, and Scene Context

Pose, depth, and scene modules are optional. Without configured model files or local backends, their adapters return no results and publish diagnostics:

- pose supports body/hand keypoint contracts for YOLO-pose, MediaPipe, and RTMPose
- depth supports low-res relative depth maps and entity depth estimates for DepthAnything/MiDaS paths
- scene context supports local labels and future VLM-style summary hooks

Depth shading is only drawn when a depth adapter produces a real `DepthMapResult`. With the current repository assets, enabling depth reports `Depth model unavailable: DepthAnything model is not configured.` rather than silently pretending depth is active.

To add a depth model:

1. Add the model file under `assets/models/` and register it in `pubspec.yaml`.
2. Implement or configure a `DepthAdapter` that loads the model, validates input/output tensors, and returns `DepthMapResult`.
3. Report model loaded state, backend, depth map resolution, depth latency, render latency, and last error through `ModelAdapterDiagnostics`.
4. Enable depth processing and `Draw depth shading`; the overlay only shades when a real depth map is present.

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

Dataset export includes detection boxes, identity IDs, corrected labels, and optional `perception_metadata.json` with segmentation polygons, mask metadata, identity fusion scores, pose keypoints, depth estimates, and scene context where available. This creates a continual-learning-ready path for later TFLite personalization, ONNX model swaps, vector embedding identity memory, YOLO segmentation export, or offline fine-tuning workflows without pretending the MVP retrains the detector on-device today.

## Inference Diagnostics

The live view exposes a debug panel for detector health:

- backend name
- model loaded state
- frames received and inferred
- input and output tensor shapes
- parser mode
- label map loaded state, label map name, label count
- raw class IDs, mapped labels, unknown-label count, and missing class IDs
- raw and filtered candidate counts
- tracker input and output counts
- queue depth and skipped frames
- sample output values
- last inference error
- detector self-test results

The Perception Dashboard adds:

- active models and enabled modules
- camera/UI/inference-oriented FPS
- segmentation latency and FPS estimate
- per-module latency and output count
- per-module enabled, available, initialized, active, backend, last error, and output count
- queue sizes and dropped latest-frame work
- active entities and recovered identities
- identity fusion score breakdowns on the Identity Debug screen

## Source Modes

- `Camera`: live device camera stream for realtime inference
- `Video file`: local video playback plus extracted frame inference
- `Future stream`: reserved hook for later RTSP/WebRTC/API sources

## Settings and Backend Selection

Implemented backend selections:

- `LiteRT / TFLite`

Unavailable architecture hooks are shown as unavailable and rejected safely:

- `YOLO26 LiteRT/TFLite`
- `ONNX Hook`
- `Remote/Local API Hook`

If an unavailable backend is selected programmatically or through a stale UI state, the controller keeps the previous working backend and logs a user-visible event.

Implemented acceleration choices:

- `Auto`
- `CPU`
- `XNNPACK`

`GPU` is shown as unavailable in this build because the app does not yet validate a GPU delegate path across target devices. Invalid acceleration choices are rejected before the interpreter is switched.

Resolution selection is model-driven. The bundled EfficientDet Lite0 model reports a fixed `320x320` input, so the UI exposes only `320x320`. Performance modes that request `416` or `640` are sanitized back to the active model size. If a future dynamic-shape model is added, the interpreter/session must be recreated and self-tested before the new input size is accepted.

To debug backend or resolution failures:

1. Run `Run Test Inference` from Live View.
2. Check `Input`, `Outputs`, `Parser`, `Labels`, `Requested`, and `Last error` in the Inference Debug panel.
3. Check the event log for rejected backend, acceleration, or resolution changes.
4. Confirm the active model input shape before exposing a new resolution.
5. If a switch fails, the controller restores the previous settings and keeps the live pipeline alive.

Performance modes:

- `Fast`: detection every 5 frames, segmentation off, SAM off, object/pose/depth mostly off, 320 input
- `Balanced`: detection every 3 frames, segmentation every 5 frames, SAM off by default, face every 10 frames, active model input size
- `Accurate`: detection every 2 frames, segmentation every 3 frames, SAM enabled, embeddings enabled, active model input size unless a future model proves larger sizes are supported
- `Research`: all modules available, heavy diagnostics on, slower processing accepted for testing and uploaded videos

Model Manager settings expose detection, segmentation, SAM, face Re-ID, object embedding, pose, depth, and scene intervals plus per-frame caps.

## Local Storage and Privacy

- biometric templates stay on-device in the encrypted biometric vault
- biometric template encryption keys and PIN salts are stored through platform secure storage
- raw eye/face scan images are not stored by default
- biometric data is never uploaded by the implemented services
- enrolled biometric users can be cleared by an authenticated admin
- learning memory stays on-device through `sqflite`
- face-embedding memory stays on-device through `sqflite`
- crop samples and exported datasets are written to local app support storage
- no cloud dependency is required
- the app includes controls to clear learned memory, clear embedding memory, and export collected training data
- SAM/local API backends are disabled unless explicitly configured
- face embeddings are local descriptor records only
- no face swapping, face generation, synthetic identity creation, real-world identity lookup, or cloud upload is implemented
- labels are user-assigned and remain local by default

## Current Limitations

- The active eye-region biometric adapter is a mock development adapter and is not production-grade biometric security.
- The app does not perform true medical retina scanning; it uses front-camera iris / eye-region template matching.
- Basic liveness checks reduce obvious bad captures but are not full anti-spoofing.
- Real production biometric assurance requires a real local iris/face embedding model or platform biometric fallback.
- YOLO26 and YOLO26-seg adapters are wired, but the repository does not include YOLO26 model files.
- SAM 3.1 is an optional backend hook; the current adapter returns no masks unless a real backend client is implemented.
- ByteTrack, DeepSORT, InsightFace, ArcFace, MobileFaceNet, MobileCLIP, DINOv2, CLIP, YOLO-pose, MediaPipe, RTMPose, DepthAnything, MiDaS, and VLM adapters have real interfaces and diagnostics but return no results until their real model files or backend clients are configured.
- No segmentation masks are generated unless a real segmentation backend produces them.
- No depth shading is generated unless a real depth backend produces a depth map.
- The bundled detector is fixed at `320x320`; unsupported input sizes are rejected.
- GPU/ONNX/API backend selections are unavailable until those adapters pass initialization and self-test.
- The app remains local-first and research-oriented; production identity, segmentation, or depth quality depends on adding the intended local model files/backends.

## Future Integration Path

The app is ready for:

- custom LiteRT/TFLite detector swaps
- YOLO26 detection and YOLO26-seg segmentation model files
- SAM 3.1 local/server refinement
- ONNX runtime detector integration
- vector embedding re-identification
- TFLite personalization-ready face embedding swaps such as ArcFace, MobileFaceNet, or FaceNet
- ONNX face embedding adapters such as InsightFace or DeepFace-style recognition backends
- MobileCLIP, DINOv2, and CLIP object persistence
- YOLO-pose, MediaPipe, or RTMPose interaction tracking
- DepthAnything or MiDaS relative spatial awareness
- lightweight scene context and future local VLM layers
- exported training data for later offline fine-tuning
- Epyk-3-style modular perception experiments
- Myne-2-style spatial and local-AI processing experiments

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

- detector class label propagation into overlay labels
- unknown class fallback labels
- detector contract timestamp behavior
- tracker identity continuity
- identity recovery after track replacement
- identity recovery rejection when confidence is below threshold
- invalid backend switch rejection
- unsupported resolution rejection
- segmentation unavailable state for a detection-only model
- depth unavailable state without a configured model
- preview coordinate mapping
- face-embedding match selection
- temporal persistence scoring
- corrected-label reuse in Sentinel Learning Core
- learned person alias reinforcement
- dataset export beyond the recent-sample dashboard cache
- encrypted biometric template storage
- salted PIN fallback verification
- admin-only approved-user management
- 3-of-5 biometric login match approval
- app lock on background lifecycle transition

Run them with:

```bash
flutter test -r expanded
```
