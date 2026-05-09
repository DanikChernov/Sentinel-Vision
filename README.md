# Sentinel Vision Console

Sentinel Vision Console is a local-first realtime video intelligence stack focused on modular perception, persistent object identity, and extensible vision pipelines.

The project supports:
- live object and person detection from webcams, RTSP streams, HTTP feeds, or local video files
- per-object tracking with stable unique labels such as `person-001`
- re-identification memory so tracked entities can recover identity after leaving and re-entering frame
- an optional vision labeler hook that can later be fine-tuned with QLoRA for custom semantic labeling
- a React dashboard served directly by FastAPI, allowing the API and UI to run as a unified local stack
- helper scripts for remote dashboard exposure and host tunneling workflows

Sentinel is designed as a lightweight experimental framework for local-first computer vision research, realtime scene understanding, and identity persistence across evolving perception environments.

Some architectural decisions in this repository are intentionally aligned with longer-term experimental systems under the Epyk-3 and Myne-2 research directions, particularly around modular perception, spatial awareness, and local-first AI processing.

## Architecture

backend/app/main.py: FastAPI application, REST API, WebSocket stream, static frontend hosting

backend/app/video.py: source workers, frame ingestion, detection, tracking, preview rendering

backend/app/identity.py: global identity registry and re-identification memory

frontend/: React dashboard served directly by FastAPI

train/: dataset preparation and QLoRA training scripts for the optional vision labeler

## Runtime model split

The system uses two model paths:

- YOLO + DeepSORT for box detection and frame-to-frame tracking
- Mini labeler for semantic refinement of object labels from cropped detections

The included QLoRA trainer fine-tunes the second path. That gives a practical way to teach the system custom domain labels without replacing the detector. If new bounding-box classes are later required, a dedicated detector fine-tuning pipeline can be added separately.

The architecture intentionally keeps the detector, tracker, labeler, and identity systems modular so they can evolve independently for future multi-camera, robotics, or spatial-computing experimentation.

## Future Directions

- vector embedding identity memory
- multi-camera identity persistence
- synthetic-data robustness pipelines
- event-driven scene analytics
- lightweight edge deployment profiles
- experimental Epyk-3 perception integrations
- early-stage Myne-2 spatial awareness experimentation