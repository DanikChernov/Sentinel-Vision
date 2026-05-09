from __future__ import annotations

import threading
from dataclasses import dataclass


@dataclass(slots=True)
class Detection:
    x1: int
    y1: int
    x2: int
    y2: int
    confidence: float
    class_id: int
    class_name: str

    @property
    def width(self) -> int:
        return max(self.x2 - self.x1, 0)

    @property
    def height(self) -> int:
        return max(self.y2 - self.y1, 0)


class YoloDetector:
    def __init__(self, model_name: str, confidence: float) -> None:
        self.model_name = model_name
        self.confidence = confidence
        self._model = None
        self._lock = threading.Lock()

    def detect(self, frame, allowed_classes: set[str] | None = None) -> list[Detection]:
        model = self._ensure_model()
        with self._lock:
            results = model.predict(frame, conf=self.confidence, verbose=False)
        batch = results[0]
        if batch.boxes is None:
            return []
        names = batch.names
        detections: list[Detection] = []
        xyxy = batch.boxes.xyxy.cpu().tolist()
        scores = batch.boxes.conf.cpu().tolist()
        classes = batch.boxes.cls.cpu().tolist()
        for bbox, score, class_index in zip(xyxy, scores, classes):
            class_name = names[int(class_index)]
            if allowed_classes and class_name not in allowed_classes:
                continue
            x1, y1, x2, y2 = (int(value) for value in bbox)
            detections.append(
                Detection(
                    x1=x1,
                    y1=y1,
                    x2=x2,
                    y2=y2,
                    confidence=float(score),
                    class_id=int(class_index),
                    class_name=class_name,
                )
            )
        return detections

    def _ensure_model(self):
        if self._model is not None:
            return self._model
        with self._lock:
            if self._model is not None:
                return self._model
            from ultralytics import YOLO

            self._model = YOLO(self.model_name)
            return self._model

