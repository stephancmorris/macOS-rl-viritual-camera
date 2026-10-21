"""Synthetic loader integrity checks; standard library only."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import tempfile
import unittest

from env_loader import scan_sessions


class SessionValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.session = self.root / "session_synthetic"
        self.session.mkdir()
        self.row = {
            "t": 0.0, "frame_idx": 0,
            "speaker": {"x": 0.3, "y": 0.5, "z": 1.0, "confidence": 0.9},
            "keypoints": {"head_x": 0.3, "head_y": 0.7, "waist_x": 0.3,
                "waist_y": 0.4, "pose_confidence": 0.8},
            "current_crop": {"x": 0.1, "y": 0.1, "w": 0.8, "h": 0.45, "zoom": 2.2},
            "ideal_crop": {"x": 0.1, "y": 0.1, "w": 0.8, "h": 0.45, "zoom": 2.2},
        }
        self.write_rows([self.row])

    def write_rows(self, rows):
        (self.session / "frames.jsonl").write_text(
            "".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")

    def write_metadata(self, **overrides):
        metadata = {"session_id": self.session.name, "total_frames": 1,
            "fps": 30, "label_source": "auto"}
        metadata.update(overrides)
        (self.session / "metadata.json").write_text(json.dumps(metadata), encoding="utf-8")

    def load(self, min_frames=1):
        return scan_sessions([self.root], min_frames=min_frames)

    def test_valid_metadata_and_actual_row_count(self):
        self.write_metadata()
        loaded = self.load()
        self.assertEqual(len(loaded), 1)
        self.assertEqual(loaded[0].frames, [self.row])
        self.assertEqual((loaded[0].fps, loaded[0].source), (30, "live"))
        self.assertEqual(self.load(min_frames=2), [])

    def test_legacy_missing_optional_metadata_and_frame_defaults(self):
        self.write_rows([{}, {"speaker": None, "keypoints": None,
            "current_crop": {}, "ideal_crop": None}])
        loaded = self.load()[0]
        self.assertEqual((loaded.fps, loaded.source), (30, "unknown"))
        metadata = self.session / "metadata.json"
        for value in ({}, {"total_frames": None}, {"fps": 29.97, "label_source": "youtube_reference"}):
            with self.subTest(metadata=value):
                metadata.write_text(json.dumps(value), encoding="utf-8")
                loaded = self.load()[0]
                self.assertEqual(len(loaded.frames), 2)
                if "fps" in value:
                    self.assertEqual((loaded.fps, loaded.source), (29.97, "youtube"))

    def test_subsampling_and_loss_gaps_are_preserved_without_contiguity_claim(self):
        for indices in ([0, 2, 4], [0, 10, 11], [7, 12, 20]):
            with self.subTest(indices=indices):
                rows = [dict(self.row, frame_idx=index, t=index / 30) for index in indices]
                self.write_rows(rows)
                self.write_metadata(total_frames=3)
                loaded = self.load()[0]
                self.assertEqual([row["frame_idx"] for row in loaded.frames], list(indices))
                self.assertEqual([row["t"] for row in loaded.frames], [index / 30 for index in indices])

    def test_invalid_row_roots_and_nested_shapes_are_actionable(self):
        invalid = [None, [], 3, "row"]
        invalid += [dict(self.row, **{name: value})
            for name in ("speaker", "keypoints", "current_crop", "ideal_crop")
            for value in ([], "invalid", 4)]
        invalid += [dict(self.row, current_crop=None)]
        for row in invalid:
            with self.subTest(row=row):
                self.write_rows([row])
                with self.assertRaisesRegex(ValueError, r"session_synthetic/frames.jsonl line 1: .*object"):
                    self.load()

    def test_directly_used_speaker_and_keypoint_fields_are_required(self):
        for name, keys in (("speaker", ("x", "y", "z")),
            ("keypoints", ("head_x", "head_y", "waist_x", "waist_y", "pose_confidence"))):
            for key in keys:
                with self.subTest(field=f"{name}.{key}"):
                    row = copy.deepcopy(self.row)
                    del row[name][key]
                    self.write_rows([row])
                    with self.assertRaisesRegex(ValueError, rf"{name}\.{key} is required"):
                        self.load()

    def test_used_numeric_fields_refuse_nonfinite_and_wrong_types(self):
        fields = [(None, "t"), ("speaker", "x"), ("speaker", "y"), ("speaker", "z"),
            ("speaker", "confidence")]
        fields += [("keypoints", key) for key in self.row["keypoints"]]
        fields += [(crop, key) for crop in ("current_crop", "ideal_crop") for key in self.row[crop]]
        for name, key in fields:
            for invalid in (True, "0.5", None, float("nan"), float("inf"), -float("inf"), 10 ** 400):
                with self.subTest(field=f"{name}.{key}", value=invalid):
                    row = copy.deepcopy(self.row)
                    (row if name is None else row[name])[key] = invalid
                    self.write_rows([row])
                    field = key if name is None else rf"{name}\.{key}"
                    with self.assertRaisesRegex(ValueError, field + " must be a finite number"):
                        self.load()

    def test_frame_indices_have_integer_shape_without_imposing_a_stride(self):
        for invalid in (True, 0.5, "0", -1, None):
            with self.subTest(index=invalid):
                self.write_rows([dict(self.row, frame_idx=invalid)])
                with self.assertRaisesRegex(ValueError, "frame_idx must be a nonnegative integer"):
                    self.load()

    def test_present_fps_must_be_numeric_finite_and_positive(self):
        for invalid in (True, "30", None, 0, -1, float("nan"), float("inf"), -float("inf"), 10 ** 400):
            with self.subTest(fps=invalid):
                self.write_metadata(fps=invalid)
                with self.assertRaisesRegex(ValueError, r"metadata.json: fps must be"):
                    self.load()

    def test_metadata_binding_and_count_use_persisted_rows(self):
        for invalid in ("session_other", None, True, 3):
            with self.subTest(session_id=invalid):
                self.write_metadata(session_id=invalid)
                with self.assertRaisesRegex(ValueError, "session_id must match"):
                    self.load()
        for invalid in (True, "1", 1.0, -1, float("nan"), float("inf")):
            with self.subTest(total_frames=invalid):
                self.write_metadata(total_frames=invalid)
                with self.assertRaisesRegex(ValueError, "total_frames must be a nonnegative integer"):
                    self.load()
        for invalid in (0, 2, 999):
            with self.subTest(total_frames=invalid):
                self.write_metadata(total_frames=invalid)
                with self.assertRaisesRegex(ValueError, "total_frames must match the persisted row count"):
                    self.load()

    def test_malformed_json_is_refused_instead_of_silently_losing_rows(self):
        (self.session / "frames.jsonl").write_text(json.dumps(self.row) + '\n{"t":', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "frames.jsonl line 2: invalid JSON observation"):
            self.load()
        self.write_rows([self.row])
        (self.session / "metadata.json").write_text('{"fps":', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "metadata.json: invalid JSON metadata"):
            self.load()

    def test_metadata_root_and_label_source_types_are_checked(self):
        for value in (None, [], 3, "metadata"):
            with self.subTest(metadata=value):
                (self.session / "metadata.json").write_text(json.dumps(value), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "metadata must be an object"):
                    self.load()
        for value in (None, [], True, 4):
            with self.subTest(label_source=value):
                self.write_metadata(label_source=value)
                with self.assertRaisesRegex(ValueError, "label_source must be a string"):
                    self.load()

    def test_blank_lines_do_not_count_as_observations(self):
        path = self.session / "frames.jsonl"
        path.write_text("\n  \n" + json.dumps(self.row) + "\n\n", encoding="utf-8")
        self.write_metadata(total_frames=1)
        self.assertEqual(len(self.load()[0].frames), 1)


if __name__ == "__main__":
    unittest.main()
