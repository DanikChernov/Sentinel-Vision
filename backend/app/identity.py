from __future__ import annotations

import math
import threading
import time
from collections import defaultdict
from dataclasses import dataclass, field


def _slugify(value: str) -> str:
    cleaned = "".join(char if char.isalnum() else "-" for char in value.lower()).strip("-")
    return cleaned or "object"


def cosine_similarity(left: list[float] | None, right: list[float] | None) -> float:
    if not left or not right or len(left) != len(right):
        return 0.0
    numerator = 0.0
    left_norm = 0.0
    right_norm = 0.0
    for left_value, right_value in zip(left, right):
        numerator += left_value * right_value
        left_norm += left_value * left_value
        right_norm += right_value * right_value
    if left_norm == 0.0 or right_norm == 0.0:
        return 0.0
    return numerator / math.sqrt(left_norm * right_norm)


@dataclass(slots=True)
class IdentityRecord:
    global_id: str
    label: str
    class_name: str
    primary_source_id: str
    created_at: float
    last_seen_at: float
    last_similarity: float = 0.0
    sightings: int = 0
    active: bool = True
    last_tracker_id: str | None = None
    embedding: list[float] | None = None
    semantic_label: str | None = None
    notes: str | None = None
    source_ids: set[str] = field(default_factory=set)


@dataclass(slots=True)
class IdentityMatch:
    global_id: str
    label: str
    class_name: str
    semantic_label: str | None
    reacquired: bool
    similarity: float


class IdentityRegistry:
    def __init__(
        self,
        similarity_threshold: float = 0.84,
        memory_seconds: int = 120,
        track_absence_seconds: int = 8,
    ) -> None:
        self.similarity_threshold = similarity_threshold
        self.memory_seconds = memory_seconds
        self.track_absence_seconds = track_absence_seconds
        self._lock = threading.Lock()
        self._records: dict[str, IdentityRecord] = {}
        self._bindings: dict[str, dict[str, str]] = defaultdict(dict)
        self._tracker_last_seen: dict[tuple[str, str], float] = {}
        self._class_counters: dict[str, int] = defaultdict(int)

    def register_observation(
        self,
        *,
        source_id: str,
        tracker_id: str,
        class_name: str,
        timestamp: float | None = None,
        embedding: list[float] | None = None,
    ) -> IdentityMatch:
        now = timestamp or time.time()
        with self._lock:
            bindings = self._bindings[source_id]
            existing_global_id = bindings.get(tracker_id)
            if existing_global_id:
                record = self._records[existing_global_id]
                self._tracker_last_seen[(source_id, tracker_id)] = now
                self._update_record(record, source_id, tracker_id, now, embedding, record.last_similarity)
                return IdentityMatch(
                    global_id=record.global_id,
                    label=record.label,
                    class_name=record.class_name,
                    semantic_label=record.semantic_label,
                    reacquired=False,
                    similarity=record.last_similarity,
                )

            match_id, similarity = self._find_reacquire_match(
                source_id=source_id,
                class_name=class_name,
                timestamp=now,
                embedding=embedding,
            )

            if match_id:
                record = self._records[match_id]
                bindings[tracker_id] = match_id
                self._tracker_last_seen[(source_id, tracker_id)] = now
                self._update_record(record, source_id, tracker_id, now, embedding, similarity)
                return IdentityMatch(
                    global_id=record.global_id,
                    label=record.label,
                    class_name=record.class_name,
                    semantic_label=record.semantic_label,
                    reacquired=True,
                    similarity=similarity,
                )

            record = self._create_record(source_id=source_id, class_name=class_name, timestamp=now, embedding=embedding)
            bindings[tracker_id] = record.global_id
            self._tracker_last_seen[(source_id, tracker_id)] = now
            self._update_record(record, source_id, tracker_id, now, embedding, 0.0)
            return IdentityMatch(
                global_id=record.global_id,
                label=record.label,
                class_name=record.class_name,
                semantic_label=record.semantic_label,
                reacquired=False,
                similarity=0.0,
            )

    def cleanup_source_trackers(self, source_id: str, active_tracker_ids: set[str], timestamp: float | None = None) -> None:
        now = timestamp or time.time()
        with self._lock:
            bindings = self._bindings.get(source_id, {})
            for tracker_id, global_id in list(bindings.items()):
                last_seen = self._tracker_last_seen.get((source_id, tracker_id), now)
                if tracker_id in active_tracker_ids:
                    continue
                if now - last_seen <= self.track_absence_seconds:
                    continue
                record = self._records.get(global_id)
                if record:
                    record.active = False
                del bindings[tracker_id]
                self._tracker_last_seen.pop((source_id, tracker_id), None)
            self._prune_expired(now)

    def deactivate_source(self, source_id: str, timestamp: float | None = None) -> None:
        now = timestamp or time.time()
        with self._lock:
            bindings = self._bindings.pop(source_id, {})
            for tracker_id, global_id in bindings.items():
                self._tracker_last_seen.pop((source_id, tracker_id), None)
                record = self._records.get(global_id)
                if record:
                    record.active = False
            self._prune_expired(now)

    def annotate_identity(self, global_id: str, semantic_label: str, notes: str | None = None) -> None:
        with self._lock:
            record = self._records.get(global_id)
            if not record:
                return
            record.semantic_label = semantic_label.strip() or None
            record.notes = notes

    def snapshot(self, *, limit: int = 50) -> list[dict[str, object]]:
        with self._lock:
            ordered = sorted(self._records.values(), key=lambda record: record.last_seen_at, reverse=True)
            rows = []
            for record in ordered[:limit]:
                rows.append(
                    {
                        "global_id": record.global_id,
                        "label": record.label,
                        "class_name": record.class_name,
                        "semantic_label": record.semantic_label,
                        "primary_source_id": record.primary_source_id,
                        "last_seen_at": record.last_seen_at,
                        "created_at": record.created_at,
                        "sightings": record.sightings,
                        "active": record.active,
                        "last_similarity": record.last_similarity,
                        "notes": record.notes,
                    }
                )
            return rows

    def summary(self) -> dict[str, int]:
        with self._lock:
            total = len(self._records)
            active = sum(1 for record in self._records.values() if record.active)
            return {"total_identities": total, "active_identities": active}

    def _find_reacquire_match(
        self,
        *,
        source_id: str,
        class_name: str,
        timestamp: float,
        embedding: list[float] | None,
    ) -> tuple[str | None, float]:
        if not embedding:
            return None, 0.0
        best_match_id = None
        best_similarity = self.similarity_threshold
        for record in self._records.values():
            if record.class_name != class_name:
                continue
            if record.primary_source_id != source_id:
                continue
            if record.active:
                continue
            if timestamp - record.last_seen_at > self.memory_seconds:
                continue
            similarity = cosine_similarity(embedding, record.embedding)
            if similarity >= best_similarity:
                best_match_id = record.global_id
                best_similarity = similarity
        return best_match_id, best_similarity if best_match_id else 0.0

    def _create_record(
        self,
        *,
        source_id: str,
        class_name: str,
        timestamp: float,
        embedding: list[float] | None,
    ) -> IdentityRecord:
        class_slug = _slugify(class_name)
        self._class_counters[class_slug] += 1
        global_id = f"{class_slug}-{self._class_counters[class_slug]:03d}"
        record = IdentityRecord(
            global_id=global_id,
            label=global_id,
            class_name=class_name,
            primary_source_id=source_id,
            created_at=timestamp,
            last_seen_at=timestamp,
            embedding=embedding,
        )
        self._records[global_id] = record
        return record

    def _update_record(
        self,
        record: IdentityRecord,
        source_id: str,
        tracker_id: str,
        timestamp: float,
        embedding: list[float] | None,
        similarity: float,
    ) -> None:
        record.last_seen_at = timestamp
        record.last_similarity = similarity
        record.sightings += 1
        record.active = True
        record.last_tracker_id = tracker_id
        record.source_ids.add(source_id)
        if embedding:
            record.embedding = embedding

    def _prune_expired(self, timestamp: float) -> None:
        for record in self._records.values():
            if record.active:
                continue
            if timestamp - record.last_seen_at > self.memory_seconds:
                record.embedding = None
