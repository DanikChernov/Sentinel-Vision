from __future__ import annotations

import importlib.util
from dataclasses import asdict, dataclass
from functools import lru_cache
from importlib import metadata


PACKAGE_MAP = {
    "fastapi": "fastapi",
    "uvicorn": "uvicorn",
    "cv2": "opencv-python-headless",
    "ultralytics": "ultralytics",
    "deep_sort_realtime": "deep-sort-realtime",
    "torch": "torch",
    "transformers": "transformers",
    "peft": "peft",
    "bitsandbytes": "bitsandbytes",
}


@dataclass(slots=True)
class DependencyStatus:
    module: str
    package: str
    available: bool
    version: str | None
    feature: str


def _version_for(package: str) -> str | None:
    try:
        return metadata.version(package)
    except metadata.PackageNotFoundError:
        return None


def _probe(module: str, feature: str) -> DependencyStatus:
    package = PACKAGE_MAP[module]
    available = importlib.util.find_spec(module) is not None
    return DependencyStatus(
        module=module,
        package=package,
        available=available,
        version=_version_for(package) if available else None,
        feature=feature,
    )


@lru_cache(maxsize=1)
def get_runtime_matrix() -> dict[str, object]:
    dependencies = [
        _probe("fastapi", "api"),
        _probe("uvicorn", "api"),
        _probe("cv2", "video_ingest"),
        _probe("ultralytics", "detector"),
        _probe("deep_sort_realtime", "tracker"),
        _probe("torch", "detector_and_embeddings"),
        _probe("transformers", "labeler"),
        _probe("peft", "qlora_inference"),
        _probe("bitsandbytes", "qlora_training"),
    ]
    ready = {
        "api": all(dep.available for dep in dependencies[:2]),
        "video_pipeline": all(
            dep.available for dep in dependencies if dep.module in {"cv2", "ultralytics", "deep_sort_realtime", "torch"}
        ),
        "labeler": all(dep.available for dep in dependencies if dep.module in {"transformers", "torch"}),
        "qlora_training": all(dep.available for dep in dependencies if dep.module in {"transformers", "torch", "peft", "bitsandbytes"}),
    }
    return {
        "dependencies": [asdict(dep) for dep in dependencies],
        "ready": ready,
    }


def missing_video_pipeline_dependencies() -> list[str]:
    matrix = get_runtime_matrix()
    return [
        dependency["package"]
        for dependency in matrix["dependencies"]
        if dependency["module"] in {"cv2", "ultralytics", "deep_sort_realtime", "torch"} and not dependency["available"]
    ]

