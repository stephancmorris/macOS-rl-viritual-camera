"""Synthetic replay consumer tests, with real adapters when installed.

The NumPy tests exercise the shared feature/sample path. Optional Gymnasium and
Torch tests instantiate the actual environment and dataset. These tests do not
train or export a model and do not establish production inference parity.
"""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from framing_samples import build_observation, expert_pairs, speaker_velocity
from replay_timing import TimestampTiming, partition_frames


HAS_GYM = importlib.util.find_spec("gymnasium") is not None
HAS_TORCH = importlib.util.find_spec("torch") is not None


def frame(index, speaker_x, crop_x):
    crop = {"x": crop_x, "y": 0.1, "w": 0.8, "h": 0.45, "zoom": 1 / 0.45}
    return {
        "frame_idx": index, "t": index / 30,
        "speaker": None if speaker_x is None else {"x": speaker_x, "y": 0.5, "z": 1.0},
        "keypoints": None, "current_crop": crop.copy(), "ideal_crop": crop.copy(),
    }


def gap_frames():
    return [frame(0, 0.30, 0.10), frame(10, 0.31, 0.11), frame(11, 0.311, 0.111)]


def declared_gap(previous, current):
    # This fixture declares one specific missing interval; it is not a default.
    return (previous["frame_idx"], current["frame_idx"]) != (0, 10)


class SharedFramingSamplesTests(unittest.TestCase):
    def test_golden_legacy_bc_observation_and_actions_are_unchanged(self):
        pairs = list(expert_pairs(gap_frames(), 30))
        self.assertEqual(len(pairs), 2)
        expected_obs = np.array([
            1, .31, .5, .1, 0, 0, 0, 0, .11, .1, .8, .45,
            (1 / .45) / 4, .3, 0, 0, 0, 0,
        ], dtype=np.float32)
        np.testing.assert_array_equal(pairs[1][0], expected_obs)
        np.testing.assert_array_equal(pairs[0][1], np.array([.5, 0, 0], dtype=np.float32))
        np.testing.assert_array_equal(pairs[1][1], np.array([.05, 0, 0], dtype=np.float32))
        self.assertEqual(pairs[0][0].dtype, np.float32)

    def test_elapsed_velocity_uses_seconds_while_actions_keep_step_units(self):
        frames = gap_frames()
        segment, = partition_frames(frames, timing=TimestampTiming(lambda a, b: True))
        legacy = list(expert_pairs(frames, 30))
        actual = list(expert_pairs(frames, 30, elapsed_seconds=segment.elapsed_seconds))
        self.assertAlmostEqual(float(actual[1][0][13]), .03, places=7)
        self.assertAlmostEqual(float(legacy[1][0][13]), .30, places=7)
        for old, new in zip(legacy, actual):
            np.testing.assert_array_equal(old[1], new[1])
        self.assertAlmostEqual(float(actual[0][1][0]), .5)

    def test_declared_boundary_removes_gap_pair_and_resets_sample_history(self):
        segments = partition_frames(gap_frames(), timing=TimestampTiming(declared_gap))
        pairs = [pair for segment in segments
                 for pair in expert_pairs(segment.frames, 30, elapsed_seconds=segment.elapsed_seconds)]
        self.assertEqual(len(pairs), 1)
        self.assertAlmostEqual(float(pairs[0][0][1]), .31, places=7)
        self.assertEqual(float(pairs[0][0][13]), 0)
        self.assertAlmostEqual(float(pairs[0][1][0]), .05, places=7)

    def test_declared_subsampling_and_elapsed_time_ignore_metadata_row_rate(self):
        frames = [frame(0, .30, .10), frame(2, .302, .102), frame(4, .304, .104)]
        segment, = partition_frames(frames, timing=TimestampTiming(lambda a, b: b["frame_idx"] - a["frame_idx"] == 2))
        # An explicitly supplied elapsed time does not derive seconds from FPS.
        for metadata_fps in (15, 30, 120):
            pairs = list(expert_pairs(frames, metadata_fps, elapsed_seconds=segment.elapsed_seconds))
            self.assertAlmostEqual(float(pairs[1][0][13]), .03, places=7)

    def test_missing_detection_has_no_velocity_and_clipping_is_preserved(self):
        self.assertEqual(speaker_velocity(None, {"x": .4, "y": .5}, fps=30, elapsed_seconds=.1), (0, 0))
        self.assertEqual(speaker_velocity({"x": .4, "y": .5}, None, fps=30, elapsed_seconds=.1), (0, 0))
        self.assertEqual(speaker_velocity({"x": 0, "y": 1}, {"x": 1, "y": 0}, fps=30, elapsed_seconds=.1), (1, -1))
        for invalid in (True, 0, -1, float("inf"), float("nan")):
            with self.subTest(dt=invalid):
                with self.assertRaisesRegex(ValueError, "elapsed_seconds must be finite and positive"):
                    speaker_velocity(None, None, fps=30, elapsed_seconds=invalid)

    def test_invalid_elapsed_sequence_shape_is_refused(self):
        with self.assertRaisesRegex(ValueError, "one duration per adjacent row pair"):
            list(expert_pairs(gap_frames(), 30, elapsed_seconds=[.1]))

    def test_absent_labels_remain_excluded_and_absent_features_keep_defaults(self):
        frames = gap_frames()
        frames[0]["ideal_crop"] = None
        pairs = list(expert_pairs(frames, 30))
        self.assertEqual(len(pairs), 1)
        expected = np.array([0] * 8 + [0, 0, 1, 1, .25, 0, 0, 0, 0, 0], dtype=np.float32)
        np.testing.assert_array_equal(build_observation({}, 0, 0, 1, 1, 1, 0, 0), expected)


class SessionFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="framing-timing-test-")
        self.addCleanup(self.temporary.cleanup)
        self.data_dir = Path(self.temporary.name)
        self.session = self.data_dir / "session_synthetic"
        self.session.mkdir()
        self.write_frames(gap_frames())

    def write_frames(self, frames, fps=30):
        (self.session / "frames.jsonl").write_text("".join(json.dumps(row) + "\n" for row in frames))
        (self.session / "metadata.json").write_text(json.dumps({
            "session_id": self.session.name, "fps": fps, "total_frames": len(frames),
            "label_source": "auto",
        }))


@unittest.skipUnless(HAS_GYM, "Gymnasium unavailable: actual environment adapter tests require it")
class EnvironmentTimingTests(SessionFixture):
    def env(self, timing=None):
        from cinematic_env import CinematicFramingEnv
        env = CinematicFramingEnv([self.data_dir], min_session_frames=1, timing=timing)
        self.addCleanup(env.close)
        return env

    def test_timestamp_mode_reports_actual_seconds_and_velocity(self):
        env = self.env(TimestampTiming(lambda a, b: True))
        obs, info = env.reset(seed=42)
        self.assertEqual(info["timing_source"], "timestamp_seconds")
        self.assertEqual(float(obs[13]), 0)
        obs, reward, terminated, truncated, info = env.step([0, 0, 0])
        self.assertAlmostEqual(float(obs[13]), .03, places=7)
        self.assertAlmostEqual(info["elapsed_seconds"], 10 / 30)
        self.assertFalse(terminated)
        self.assertFalse(truncated)
        self.assertTrue(np.isfinite(reward))
        _, _, _, truncated, info = env.step([0, 0, 0])
        self.assertTrue(truncated)
        self.assertEqual(info["frame_idx"], 11)
        with self.assertRaisesRegex(RuntimeError, "no remaining transition"):
            env.step([0, 0, 0])

    def test_legacy_velocity_history_and_terminal_step_remain_unchanged(self):
        env = self.env()
        _, info = env.reset(seed=42)
        self.assertEqual(info["timing_source"], "assumed_fixed_row_rate")
        obs, _, _, truncated, info = env.step([0, 0, 0])
        self.assertAlmostEqual(float(obs[13]), .30, places=7)
        self.assertIsNone(info["elapsed_seconds"])
        self.assertFalse(truncated)
        _, _, _, truncated, _ = env.step([0, 0, 0])
        self.assertFalse(truncated)
        obs, _, _, truncated, _ = env.step([0, 0, 0])
        self.assertTrue(truncated)
        self.assertEqual(float(obs[13]), 0)

    def test_declared_boundary_limits_episodes_and_resets_history(self):
        env = self.env(TimestampTiming(declared_gap))
        for seed in range(4):
            obs, info = env.reset(seed=seed)
            self.assertEqual(info["episode_start_row"], 1)
            self.assertEqual(info["episode_length"], 2)
            self.assertEqual(float(obs[13]), 0)
            obs, _, _, truncated, info = env.step([0, 0, 0])
            self.assertEqual(info["frame_idx"], 11)
            self.assertTrue(truncated)
            self.assertAlmostEqual(float(obs[13]), .03, places=7)

    def test_missing_detection_resets_only_opt_in_history(self):
        self.write_frames([frame(0, .3, .1), frame(1, None, .1), frame(2, .31, .1)])
        for timing, expected in [(None, .3), (TimestampTiming(lambda a, b: True), 0)]:
            env = self.env(timing)
            env.reset(seed=1)
            obs, *_ = env.step([0, 0, 0])
            self.assertEqual(float(obs[13]), 0)
            obs, *_ = env.step([0, 0, 0])
            self.assertAlmostEqual(float(obs[13]), expected, places=7)

    def test_anticipation_reward_uses_elapsed_velocity_and_crop_units_stay_fixed(self):
        self.write_frames([frame(0, .3, .1), frame(10, .301, .101)])
        legacy = self.env()
        actual = self.env(TimestampTiming(lambda a, b: True))
        legacy.reset(seed=1)
        actual.reset(seed=1)
        old_obs, old_reward, *_ = legacy.step([1, 0, 0])
        new_obs, new_reward, *_ = actual.step([1, 0, 0])
        self.assertAlmostEqual(float(old_obs[8]), .12, places=7)
        self.assertEqual(float(old_obs[8]), float(new_obs[8]))
        self.assertAlmostEqual(old_reward - new_reward, .1, places=7)
        self.assertAlmostEqual(float(new_obs[13]), .003, places=7)

    def test_unknown_timing_is_allowed_only_by_legacy_assumption(self):
        frames = gap_frames()
        del frames[1]["t"]
        self.write_frames(frames)
        legacy = self.env()
        legacy.reset(seed=1)
        with self.assertRaisesRegex(ValueError, "session_synthetic: row 1 requires finite t"):
            self.env(TimestampTiming(lambda a, b: True))

    def test_partition_without_real_transitions_and_one_row_episode_refuse(self):
        with self.assertRaisesRegex(ValueError, "No caller-declared continuous transitions"):
            self.env(TimestampTiming(lambda a, b: False))
        env = self.env(TimestampTiming(lambda a, b: True))
        with self.assertRaisesRegex(ValueError, "at least two rows"):
            env.reset(options={"min_episode_len": 1, "max_episode_len": 1})

    def test_episode_slice_uses_corresponding_elapsed_interval(self):
        frames = [frame(i, .3 + i / 1000, .1) for i in range(8)]
        for i, row in enumerate(frames):
            row["t"] = i * i / 30
        self.write_frames(frames)
        env = self.env(TimestampTiming(lambda a, b: True))
        for seed in range(8):
            _, reset_info = env.reset(seed=seed, options={"min_episode_len": 2, "max_episode_len": 2})
            start = reset_info["episode_start_row"]
            obs, _, _, truncated, info = env.step([0, 0, 0])
            expected_dt = frames[start + 1]["t"] - frames[start]["t"]
            self.assertEqual(info["elapsed_seconds"], expected_dt)
            self.assertAlmostEqual(float(obs[13]), .001 / expected_dt, places=7)
            self.assertTrue(truncated)

    def test_existing_feature_reexports_remain_the_shared_implementation(self):
        import cinematic_env
        import framing_samples
        self.assertIs(cinematic_env.build_observation, framing_samples.build_observation)
        self.assertEqual(cinematic_env.MAX_PAN_SPEED, .02)
        self.assertEqual(cinematic_env.MAX_ZOOM_SPEED, .05)


@unittest.skipUnless(HAS_TORCH, "Torch unavailable: actual BC adapter tests require it")
class DatasetTimingTests(SessionFixture):
    def dataset(self, timing=None):
        from bc_dataset import ExpertDataset
        return ExpertDataset([self.data_dir], min_session_frames=1, timing=timing)

    def test_actual_torch_dataset_excludes_gap_pair_and_resets_velocity(self):
        legacy = self.dataset()
        actual = self.dataset(TimestampTiming(declared_gap))
        self.assertEqual(len(legacy), 2)
        self.assertEqual(len(actual), 1)
        obs, action = actual[0]
        self.assertEqual(tuple(obs.shape), (18,))
        self.assertEqual(tuple(action.shape), (3,))
        self.assertEqual(float(obs[13]), 0)
        self.assertAlmostEqual(float(action[0]), .05, places=7)
        self.assertAlmostEqual(float(legacy[1][0][13]), .30, places=7)
        self.assertEqual(actual.timing_info["timing_source"], "timestamp_seconds")

    def test_actual_torch_dataset_uses_elapsed_time_and_fixed_action_units(self):
        actual = self.dataset(TimestampTiming(lambda a, b: True))
        self.assertEqual(len(actual), 2)
        self.assertAlmostEqual(float(actual[1][0][13]), .03, places=7)
        self.assertAlmostEqual(float(actual[0][1][0]), .5, places=7)

    def test_actual_torch_dataset_refuses_missing_timestamp_and_empty_transitions(self):
        frames = gap_frames()
        del frames[1]["t"]
        self.write_frames(frames)
        with self.assertRaisesRegex(ValueError, "row 1 requires finite t"):
            self.dataset(TimestampTiming(lambda a, b: True))
        self.write_frames(gap_frames())
        with self.assertRaisesRegex(ValueError, "No expert demonstrations found"):
            self.dataset(TimestampTiming(lambda a, b: False))


if __name__ == "__main__":
    unittest.main()
