from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[2]


def _env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    return int(value) if value is not None else default


def _env_float(name: str, default: float) -> float:
    value = os.getenv(name)
    return float(value) if value is not None else default


@dataclass(slots=True)
class Settings:
    app_name: str
    host: str
    port: int
    frontend_dir: Path
    data_dir: Path
    source_store_path: Path
    detector_model: str
    detector_confidence: float
    target_fps: int
    max_frame_width: int
    preview_jpeg_quality: int
    reid_similarity_threshold: float
    reid_memory_seconds: int
    track_absence_seconds: int
    appearance_refresh_seconds: float
    clip_model_name: str
    vlm_model_name: str
    vlm_adapter_path: str | None
    vlm_enabled: bool

    @classmethod
    def from_env(cls) -> "Settings":
        data_dir = BASE_DIR / "data" / "runtime"
        frontend_dir = BASE_DIR / "frontend"
        return cls(
            app_name=os.getenv("SENTINEL_APP_NAME", "Sentinel Vision Console"),
            host=os.getenv("SENTINEL_HOST", "127.0.0.1"),
            port=_env_int("SENTINEL_PORT", 8000),
            frontend_dir=frontend_dir,
            data_dir=data_dir,
            source_store_path=data_dir / "sources.json",
            detector_model=os.getenv("SENTINEL_DETECTOR_MODEL", "yolov8n.pt"),
            detector_confidence=_env_float("SENTINEL_DETECTOR_CONFIDENCE", 0.35),
            target_fps=_env_int("SENTINEL_TARGET_FPS", 4),
            max_frame_width=_env_int("SENTINEL_MAX_FRAME_WIDTH", 1280),
            preview_jpeg_quality=_env_int("SENTINEL_PREVIEW_JPEG_QUALITY", 82),
            reid_similarity_threshold=_env_float("SENTINEL_REID_SIMILARITY", 0.84),
            reid_memory_seconds=_env_int("SENTINEL_REID_MEMORY_SECONDS", 120),
            track_absence_seconds=_env_int("SENTINEL_TRACK_ABSENCE_SECONDS", 8),
            appearance_refresh_seconds=_env_float("SENTINEL_APPEARANCE_REFRESH_SECONDS", 1.0),
            clip_model_name=os.getenv("SENTINEL_CLIP_MODEL", "openai/clip-vit-base-patch32"),
            vlm_model_name=os.getenv("SENTINEL_VLM_MODEL", "Qwen/Qwen2-VL-2B-Instruct"),
            vlm_adapter_path=os.getenv("SENTINEL_VLM_ADAPTER_PATH"),
            vlm_enabled=os.getenv("SENTINEL_VLM_ENABLED", "false").lower() == "true",
        )


settings = Settings.from_env()
settings.data_dir.mkdir(parents=True, exist_ok=True)

