from __future__ import annotations

import json
import threading
import time
import uuid
from pathlib import Path

from .config import Settings
from .detector import YoloDetector
from .embeddings import AppearanceEncoder
from .identity import IdentityRegistry
from .runtime import get_runtime_matrix, missing_video_pipeline_dependencies
from .schemas import SourceCreate, SourcePatch, SourceRecord
from .video import SharedInferenceStack, VideoSourceWorker
from .vlm import MiniVisionAssistant


class SourceManager:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._lock = threading.Lock()
        self._sources: dict[str, SourceRecord] = {}
        self._workers: dict[str, VideoSourceWorker] = {}
        self.identity_registry = IdentityRegistry(
            similarity_threshold=settings.reid_similarity_threshold,
            memory_seconds=settings.reid_memory_seconds,
            track_absence_seconds=settings.track_absence_seconds,
        )
        self.inference = SharedInferenceStack(
            detector=YoloDetector(settings.detector_model, settings.detector_confidence),
            appearance_encoder=AppearanceEncoder(settings.clip_model_name),
            labeler=MiniVisionAssistant(
                model_name=settings.vlm_model_name,
                adapter_path=settings.vlm_adapter_path,
                enabled=settings.vlm_enabled,
            ),
        )
        self._load_sources()

    def create_source(self, payload: SourceCreate) -> dict[str, object]:
        source_id = f"src-{uuid.uuid4().hex[:8]}"
        record = SourceRecord(
            source_id=source_id,
            name=payload.name,
            source_type=payload.source_type,
            uri=payload.uri,
            camera_index=payload.camera_index,
            target_fps=payload.target_fps or self.settings.target_fps,
            enabled_classes=payload.enabled_classes,
            auto_start=payload.auto_start,
        )
        with self._lock:
            self._sources[source_id] = record
            self._persist_sources()
        if record.auto_start:
            return self.start_source(source_id)
        return self.get_source_state(source_id)

    def update_source(self, source_id: str, payload: SourcePatch) -> dict[str, object]:
        with self._lock:
            record = self._require_source(source_id)
            update = record.model_dump()
            changes = payload.model_dump(exclude_none=True)
            update.update(changes)
            updated = SourceRecord(**update)
            self._sources[source_id] = updated
            self._persist_sources()
        if source_id in self._workers and self._workers[source_id].is_alive():
            self.stop_source(source_id)
            self.start_source(source_id)
        return self.get_source_state(source_id)

    def delete_source(self, source_id: str) -> None:
        self.stop_source(source_id)
        with self._lock:
            self._sources.pop(source_id, None)
            self._workers.pop(source_id, None)
            self._persist_sources()

    def list_sources(self) -> list[dict[str, object]]:
        with self._lock:
            source_ids = list(self._sources.keys())
        return [self.get_source_state(source_id) for source_id in source_ids]

    def get_source_state(self, source_id: str) -> dict[str, object]:
        with self._lock:
            record = self._require_source(source_id)
            worker = self._workers.get(source_id)
        state = record.model_dump()
        if worker:
            state.update(worker.public_state())
        else:
            state.update(
                {
                    "status": "idle",
                    "last_error": None,
                    "preview_jpeg_base64": None,
                    "last_frame_at": None,
                    "fps": 0.0,
                    "counts_by_class": {},
                    "objects": [],
                    "events": [],
                }
            )
        return state

    def start_source(self, source_id: str) -> dict[str, object]:
        missing = missing_video_pipeline_dependencies()
        if missing:
            raise RuntimeError(f"Video pipeline dependencies are missing: {', '.join(missing)}")
        with self._lock:
            record = self._require_source(source_id)
            worker = self._workers.get(source_id)
            if worker and worker.is_alive():
                return worker.public_state()
            worker = VideoSourceWorker(
                config=record,
                settings=self.settings,
                inference=self.inference,
                identity_registry=self.identity_registry,
            )
            self._workers[source_id] = worker
            worker.start()
        time.sleep(0.05)
        return self.get_source_state(source_id)

    def stop_source(self, source_id: str) -> dict[str, object]:
        with self._lock:
            worker = self._workers.pop(source_id, None)
        if worker:
            worker.stop()
            worker.join(timeout=5.0)
        self.identity_registry.deactivate_source(source_id)
        return self.get_source_state(source_id)

    def dashboard_snapshot(self) -> dict[str, object]:
        sources = self.list_sources()
        summary = self.identity_registry.summary()
        active_sources = sum(1 for source in sources if source["status"] == "running")
        total_tracks = sum(len(source["objects"]) for source in sources)
        recent_events = []
        for source in sources:
            recent_events.extend(source.get("events", []))
        recent_events.sort(key=lambda item: item.get("ts", 0), reverse=True)
        return {
            "app_name": self.settings.app_name,
            "generated_at": time.time(),
            "sources": sources,
            "identities": self.identity_registry.snapshot(),
            "summary": {
                **summary,
                "active_sources": active_sources,
                "configured_sources": len(sources),
                "tracked_objects": total_tracks,
            },
            "runtime": get_runtime_matrix(),
            "model_config": {
                "detector_model": self.settings.detector_model,
                "clip_model": self.settings.clip_model_name,
                "vlm_model": self.settings.vlm_model_name,
                "vlm_enabled": self.settings.vlm_enabled,
                "vlm_adapter_path": self.settings.vlm_adapter_path,
            },
            "recent_events": recent_events[:30],
        }

    def shutdown(self) -> None:
        with self._lock:
            source_ids = list(self._workers.keys())
        for source_id in source_ids:
            self.stop_source(source_id)

    def _require_source(self, source_id: str) -> SourceRecord:
        record = self._sources.get(source_id)
        if record is None:
            raise KeyError(source_id)
        return record

    def _persist_sources(self) -> None:
        rows = [record.model_dump() for record in self._sources.values()]
        self.settings.source_store_path.parent.mkdir(parents=True, exist_ok=True)
        self.settings.source_store_path.write_text(json.dumps(rows, indent=2), encoding="utf-8")

    def _load_sources(self) -> None:
        path = self.settings.source_store_path
        if not path.exists():
            return
        rows = json.loads(path.read_text(encoding="utf-8"))
        with self._lock:
            self._sources = {row["source_id"]: SourceRecord(**row) for row in rows}
        for source in self._sources.values():
            if source.auto_start and not missing_video_pipeline_dependencies():
                self.start_source(source.source_id)
