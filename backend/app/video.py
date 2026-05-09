from __future__ import annotations

import base64
import threading
import time
from collections import Counter, deque
from dataclasses import dataclass

from .config import Settings
from .detector import YoloDetector
from .embeddings import AppearanceEncoder
from .identity import IdentityRegistry
from .schemas import SourceRecord, SourceType
from .tracker import ObjectTracker
from .vlm import MiniVisionAssistant


@dataclass(slots=True)
class SharedInferenceStack:
    detector: YoloDetector
    appearance_encoder: AppearanceEncoder
    labeler: MiniVisionAssistant


class VideoSourceWorker(threading.Thread):
    def __init__(
        self,
        *,
        config: SourceRecord,
        settings: Settings,
        inference: SharedInferenceStack,
        identity_registry: IdentityRegistry,
    ) -> None:
        super().__init__(name=f"source-{config.source_id}", daemon=True)
        self.config = config
        self.settings = settings
        self.inference = inference
        self.identity_registry = identity_registry
        self.tracker = ObjectTracker(use_appearance=True)
        self.stop_event = threading.Event()
        self.state_lock = threading.Lock()
        self.status = "idle"
        self.last_error: str | None = None
        self.preview_jpeg_base64: str | None = None
        self.last_frame_at: float | None = None
        self.recent_objects: list[dict[str, object]] = []
        self.recent_events: deque[dict[str, object]] = deque(maxlen=25)
        self.fps: float = 0.0
        self.counts_by_class: Counter[str] = Counter()
        self.frame_index = 0
        self._last_embedding_refresh: dict[str, float] = {}

    def run(self) -> None:
        try:
            self._run_loop()
        except Exception as exc:
            with self.state_lock:
                self.status = "error"
                self.last_error = str(exc)
        finally:
            self.identity_registry.cleanup_source_trackers(self.config.source_id, set(), time.time())

    def stop(self) -> None:
        self.stop_event.set()

    def public_state(self) -> dict[str, object]:
        with self.state_lock:
            return {
                "source_id": self.config.source_id,
                "name": self.config.name,
                "source_type": self.config.source_type.value,
                "target_fps": self.config.target_fps,
                "enabled_classes": list(self.config.enabled_classes),
                "status": self.status,
                "last_error": self.last_error,
                "preview_jpeg_base64": self.preview_jpeg_base64,
                "last_frame_at": self.last_frame_at,
                "fps": round(self.fps, 2),
                "counts_by_class": dict(self.counts_by_class),
                "objects": list(self.recent_objects),
                "events": list(self.recent_events),
                "uri": self.config.uri,
                "camera_index": self.config.camera_index,
                "auto_start": self.config.auto_start,
            }

    def _run_loop(self) -> None:
        import cv2

        capture_target = self._resolve_capture_target()
        capture = cv2.VideoCapture(capture_target)
        if not capture.isOpened():
            raise RuntimeError(f"Unable to open source {self.config.name}")
        frame_interval = 1.0 / max(self.config.target_fps, 1)
        last_tick = time.perf_counter()
        with self.state_lock:
            self.status = "running"
            self.last_error = None

        while not self.stop_event.is_set():
            loop_started = time.perf_counter()
            ok, frame = capture.read()
            if not ok:
                with self.state_lock:
                    self.status = "reconnecting"
                    self.last_error = "Frame read failed; retrying"
                time.sleep(1.0)
                capture.release()
                capture = cv2.VideoCapture(capture_target)
                continue

            frame = self._resize_frame(frame)
            now = time.time()
            detections = self.inference.detector.detect(
                frame,
                allowed_classes=set(self.config.enabled_classes) if self.config.enabled_classes else None,
            )
            tracks = self.tracker.update(frame, detections)
            active_trackers = set()
            objects: list[dict[str, object]] = []
            counts: Counter[str] = Counter()

            for track in tracks:
                active_trackers.add(track.tracker_id)
                crop = self._crop(frame, track.x1, track.y1, track.x2, track.y2)
                embedding = None
                last_refresh = self._last_embedding_refresh.get(track.tracker_id, 0.0)
                if crop is not None and now - last_refresh >= self.settings.appearance_refresh_seconds:
                    embedding = self.inference.appearance_encoder.encode(crop)
                    self._last_embedding_refresh[track.tracker_id] = now
                match = self.identity_registry.register_observation(
                    source_id=self.config.source_id,
                    tracker_id=track.tracker_id,
                    class_name=track.class_name,
                    timestamp=now,
                    embedding=embedding,
                )
                semantic_label = match.semantic_label
                label_info = None
                if crop is not None and self.inference.labeler.enabled:
                    label_info = self.inference.labeler.describe_crop(crop, track.class_name)
                    if label_info and isinstance(label_info.get("label"), str):
                        semantic_label = label_info["label"].strip()
                        self.identity_registry.annotate_identity(match.global_id, semantic_label, notes=str(label_info))
                counts[track.class_name] += 1
                row = {
                    "identity_id": match.global_id,
                    "label": match.label,
                    "class_name": track.class_name,
                    "semantic_label": semantic_label,
                    "tracker_id": track.tracker_id,
                    "confidence": round(track.confidence, 4),
                    "reacquired": match.reacquired,
                    "similarity": round(match.similarity, 4),
                    "bbox": [track.x1, track.y1, track.x2, track.y2],
                }
                objects.append(row)
                if match.reacquired:
                    self.recent_events.appendleft(
                        {
                            "ts": now,
                            "source_id": self.config.source_id,
                            "identity_id": match.global_id,
                            "type": "reacquired",
                            "label": match.label,
                        }
                    )
                self._draw_annotation(frame, row)

            self.identity_registry.cleanup_source_trackers(self.config.source_id, active_trackers, now)
            preview = self._encode_preview(frame)
            current_tick = time.perf_counter()
            elapsed = current_tick - last_tick
            fps = 1.0 / elapsed if elapsed > 0 else 0.0
            last_tick = current_tick

            with self.state_lock:
                self.status = "running"
                self.last_error = None
                self.preview_jpeg_base64 = preview
                self.last_frame_at = now
                self.recent_objects = objects
                self.counts_by_class = counts
                self.fps = fps

            sleep_for = max(frame_interval - (current_tick - loop_started), 0.0)
            if sleep_for > 0:
                time.sleep(sleep_for)
            self.frame_index += 1

        capture.release()
        with self.state_lock:
            self.status = "stopped"

    def _resolve_capture_target(self):
        if self.config.source_type == SourceType.camera:
            return int(self.config.camera_index or 0)
        return self.config.uri

    def _resize_frame(self, frame):
        import cv2

        height, width = frame.shape[:2]
        if width <= self.settings.max_frame_width:
            return frame
        scale = self.settings.max_frame_width / width
        resized = cv2.resize(frame, (int(width * scale), int(height * scale)))
        return resized

    @staticmethod
    def _crop(frame, x1: int, y1: int, x2: int, y2: int):
        height, width = frame.shape[:2]
        x1 = max(0, min(x1, width))
        x2 = max(0, min(x2, width))
        y1 = max(0, min(y1, height))
        y2 = max(0, min(y2, height))
        if x2 <= x1 or y2 <= y1:
            return None
        return frame[y1:y2, x1:x2].copy()

    def _encode_preview(self, frame) -> str | None:
        import cv2

        success, buffer = cv2.imencode(
            ".jpg",
            frame,
            [int(cv2.IMWRITE_JPEG_QUALITY), self.settings.preview_jpeg_quality],
        )
        if not success:
            return None
        return base64.b64encode(buffer.tobytes()).decode("ascii")

    @staticmethod
    def _draw_annotation(frame, row: dict[str, object]) -> None:
        import cv2

        x1, y1, x2, y2 = row["bbox"]
        label = row["label"]
        class_name = row["class_name"]
        semantic_label = row.get("semantic_label")
        title = f"{label} | {semantic_label or class_name}"
        cv2.rectangle(frame, (x1, y1), (x2, y2), (62, 188, 255), 2)
        cv2.rectangle(frame, (x1, max(y1 - 24, 0)), (min(x2, x1 + 320), y1), (20, 28, 40), -1)
        cv2.putText(frame, title, (x1 + 6, max(y1 - 8, 14)), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (240, 245, 250), 1)
