from __future__ import annotations

from dataclasses import dataclass

from .detector import Detection


@dataclass(slots=True)
class TrackedObject:
    tracker_id: str
    x1: int
    y1: int
    x2: int
    y2: int
    confidence: float
    class_name: str


class ObjectTracker:
    def __init__(self, max_age: int = 30, n_init: int = 2, use_appearance: bool = True) -> None:
        self.max_age = max_age
        self.n_init = n_init
        self.use_appearance = use_appearance
        self._tracker = None

    def update(self, frame, detections: list[Detection]) -> list[TrackedObject]:
        tracker = self._ensure_tracker()
        ds_detections = [
            ([det.x1, det.y1, det.width, det.height], det.confidence, det.class_name) for det in detections
        ]
        tracks = tracker.update_tracks(ds_detections, frame=frame)
        tracked: list[TrackedObject] = []
        for track in tracks:
            if not track.is_confirmed():
                continue
            left, top, right, bottom = track.to_ltrb()
            class_name = self._resolve_class_name(track)
            confidence = float(self._resolve_confidence(track))
            tracked.append(
                TrackedObject(
                    tracker_id=str(track.track_id),
                    x1=int(left),
                    y1=int(top),
                    x2=int(right),
                    y2=int(bottom),
                    confidence=confidence,
                    class_name=class_name,
                )
            )
        return tracked

    def _ensure_tracker(self):
        if self._tracker is not None:
            return self._tracker
        from deep_sort_realtime.deepsort_tracker import DeepSort

        embedder = "mobilenet" if self.use_appearance else None
        self._tracker = DeepSort(
            max_age=self.max_age,
            n_init=self.n_init,
            embedder=embedder,
            half=False,
        )
        return self._tracker

    @staticmethod
    def _resolve_class_name(track) -> str:
        if hasattr(track, "get_det_class"):
            value = track.get_det_class()
            if value:
                return str(value)
        return str(getattr(track, "det_class", "object"))

    @staticmethod
    def _resolve_confidence(track) -> float:
        if hasattr(track, "get_det_conf"):
            value = track.get_det_conf()
            if value is not None:
                return float(value)
        value = getattr(track, "det_conf", 0.0)
        return float(value or 0.0)
