from __future__ import annotations

import unittest

from backend.app.identity import IdentityRegistry


class IdentityRegistryTest(unittest.TestCase):
    def test_reacquires_identity_after_source_absence(self) -> None:
        registry = IdentityRegistry(similarity_threshold=0.8, memory_seconds=20, track_absence_seconds=1)
        first = registry.register_observation(
            source_id="cam-a",
            tracker_id="1",
            class_name="person",
            timestamp=10.0,
            embedding=[1.0, 0.0, 0.0],
        )
        registry.cleanup_source_trackers("cam-a", set(), timestamp=12.5)
        second = registry.register_observation(
            source_id="cam-a",
            tracker_id="9",
            class_name="person",
            timestamp=15.0,
            embedding=[0.99, 0.01, 0.0],
        )
        self.assertEqual(first.global_id, second.global_id)
        self.assertTrue(second.reacquired)

    def test_creates_new_identity_for_different_embedding(self) -> None:
        registry = IdentityRegistry(similarity_threshold=0.9, memory_seconds=20, track_absence_seconds=1)
        first = registry.register_observation(
            source_id="cam-a",
            tracker_id="1",
            class_name="person",
            timestamp=10.0,
            embedding=[1.0, 0.0],
        )
        registry.cleanup_source_trackers("cam-a", set(), timestamp=12.0)
        second = registry.register_observation(
            source_id="cam-a",
            tracker_id="2",
            class_name="person",
            timestamp=15.0,
            embedding=[0.0, 1.0],
        )
        self.assertNotEqual(first.global_id, second.global_id)
        self.assertEqual(second.label, "person-002")


if __name__ == "__main__":
    unittest.main()
