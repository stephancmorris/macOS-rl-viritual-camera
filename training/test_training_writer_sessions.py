"""Synthetic same-second training session allocation; standard library only."""
import builtins
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import json
from pathlib import Path
import tempfile
from threading import Barrier
import unittest
from unittest.mock import patch
from uuid import UUID

from env_loader import scan_sessions
from schema import CropData, FrameObservation, IdealCropData
import writer


class FrozenDateTime(datetime):
    @classmethod
    def now(cls, tz=None):
        return cls(2026, 10, 22, 12, 0, 0, tzinfo=tz)


class TrainingWriterSessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        clock = patch.object(writer, "datetime", FrozenDateTime)
        clock.start()
        self.addCleanup(clock.stop)

    def create(self, title="synthetic"):
        return writer.SessionWriter(self.root, title, 30, (16, 16))

    def record(self, index):
        session = self.create(f"synthetic {index}")
        session.write_frame(FrameObservation(index / 30, index, None, None,
            CropData(0, 0, 1, 1, 1), IdealCropData(0, 0, 1, 1, 1, "youtube")))
        session.finalize(total_frames=1, duration=1 / 30)
        return session

    def snapshot(self, session):
        return {path.name: path.read_bytes() for path in session.session_dir.iterdir()}

    def assert_sessions(self, sessions):
        self.assertEqual(len({session.session_id for session in sessions}), 2)
        self.assertEqual(len(list(self.root.iterdir())), 2)
        for index, session in enumerate(sessions):
            self.assertTrue(session.session_id.startswith("session_youtube_2026-10-22_12-00-00_"))
            rows = [json.loads(line) for line in session.frames_path.read_text().splitlines()]
            metadata = json.loads((session.session_dir / "metadata.json").read_text())
            self.assertEqual([row["frame_idx"] for row in rows], [index])
            self.assertEqual(metadata["session_id"], session.session_dir.name)
            self.assertEqual(metadata["camera_name"], f"synthetic {index}")
            self.assertEqual(metadata["total_frames"], 1)
        self.assertEqual(len(scan_sessions([self.root], min_frames=1)), 2)

    def test_same_second_sequential_sessions_preserve_first_files(self):
        first = self.record(0)
        original = self.snapshot(first)
        second = self.record(1)
        self.assertEqual(self.snapshot(first), original)
        self.assert_sessions([first, second])

    def test_same_second_concurrent_sessions_are_isolated(self):
        ready = Barrier(2)

        def record_concurrently(index):
            ready.wait(timeout=5)
            return self.record(index)

        with ThreadPoolExecutor(max_workers=2) as executor:
            sessions = list(executor.map(record_concurrently, (0, 1)))
        self.assert_sessions(sessions)

    def test_preexisting_uuid_directory_refuses_without_touching_files(self):
        token = UUID("00000000-0000-0000-0000-000000000001")
        session = self.root / f"session_youtube_2026-10-22_12-00-00_{token}"
        session.mkdir()
        originals = {"frames.jsonl": b"existing rows\n", "metadata.json": b"existing metadata\n"}
        for name, contents in originals.items():
            (session / name).write_bytes(contents)
        with patch.object(writer, "uuid4", return_value=token):
            with self.assertRaises(FileExistsError):
                self.create()
        self.assertEqual({path.name: path.read_bytes() for path in session.iterdir()}, originals)
        self.assertEqual(list(self.root.iterdir()), [session])

    def test_frame_file_collision_after_directory_allocation_preserves_file(self):
        sentinel = b"allocated by another writer\n"

        def raced_open(path, mode, **kwargs):
            # Simulate a file appearing after the exclusive directory reservation.
            Path(path).write_bytes(sentinel)
            return builtins.open(path, mode, **kwargs)

        with patch.object(writer, "open", side_effect=raced_open, create=True):
            with self.assertRaises(FileExistsError):
                self.create()
        session = next(self.root.iterdir())
        self.assertEqual((session / "frames.jsonl").read_bytes(), sentinel)
        self.assertFalse((session / "metadata.json").exists())

    def test_finalize_never_replaces_existing_metadata(self):
        session = self.record(0)
        original = self.snapshot(session)
        with self.assertRaises(FileExistsError):
            session.finalize(total_frames=999, duration=999)
        self.assertEqual(self.snapshot(session), original)


if __name__ == "__main__":
    unittest.main()
