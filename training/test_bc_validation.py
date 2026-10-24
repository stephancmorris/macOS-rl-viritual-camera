"""BC split structure and guarded actual-entrypoint checks; no training."""

from __future__ import annotations

import importlib.util
import math
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from bc_validation import split_counts

HAS_RUNTIME = all(importlib.util.find_spec(name) is not None
                  for name in ("torch", "gymnasium", "stable_baselines3"))


class SplitCountTests(unittest.TestCase):
    def test_existing_rounding_and_smallest_nonempty_split_are_preserved(self):
        for samples, fraction, expected in [
            (2, .1, (1, 1)), (30, .1, (27, 3)), (99, .1, (90, 9)),
            (8, .375, (5, 3)), (3, .01, (2, 1)),
            (2, math.nextafter(1.0, 0.0), (1, 1)),
        ]:
            with self.subTest(samples=samples, fraction=fraction):
                self.assertEqual(split_counts(samples, fraction), expected)

    def test_invalid_fraction_types_ranges_and_nonfinite_values_are_refused(self):
        for value in [None, True, False, "0.1", [], {}, -1, 0, 1, 2,
                      float("nan"), float("inf"), -float("inf"), 10 ** 1000]:
            with self.subTest(fraction=value):
                with self.assertRaisesRegex(ValueError, "val_split must be a finite number strictly between 0 and 1"):
                    split_counts(30, value)

    def test_empty_partition_error_reports_sample_and_partition_counts(self):
        for samples, expected_train in [(0, -1), (1, 0)]:
            with self.subTest(samples=samples):
                with self.assertRaisesRegex(
                    ValueError, f"samples={samples}, train={expected_train}, validation=1, val_split=0.1",
                ):
                    split_counts(samples, .1)

    def test_sample_count_must_be_a_nonnegative_integer(self):
        for value in [None, True, -1, 1.5, "30"]:
            with self.subTest(samples=value):
                with self.assertRaisesRegex(ValueError, "sample_count must be a nonnegative integer"):
                    split_counts(value, .1)


@unittest.skipUnless(HAS_RUNTIME, "Actual BC entrypoint tests require Torch, Gymnasium and SB3")
class EntryPointPreflightTests(unittest.TestCase):
    def setUp(self):
        from test_env import create_synthetic_session
        self.temporary = tempfile.TemporaryDirectory(prefix="bc-preflight-test-")
        self.addCleanup(self.temporary.cleanup)
        self.data = Path(self.temporary.name)
        create_synthetic_session(self.data / "session_synthetic", num_frames=30, fps=30)
        self.output = self.data / "must_not_be_created" / "checkpoint"

    def assert_preflight_failure(self, message, **kwargs):
        import torch
        from train_bc import train_bc
        from torch.utils.data import DataLoader
        with patch("stable_baselines3.PPO", side_effect=AssertionError("Model construction prohibited")) as model, \
                patch("torch.utils.data.random_split", wraps=torch.utils.data.random_split) as split, \
                patch("train_bc.DataLoader", wraps=DataLoader) as loader:
            with self.assertRaisesRegex(ValueError, message):
                train_bc([self.data], self.output, verbose=False, **kwargs)
            model.assert_not_called()
            split.assert_not_called()
            loader.assert_not_called()
        self.assertFalse(self.output.parent.exists())

    def test_one_valid_timestamp_pair_refuses_before_split_model_or_save(self):
        from bc_dataset import ExpertDataset
        from replay_timing import TimestampTiming
        # This synthetic study declares exactly the final stored interval usable.
        timing = TimestampTiming(lambda previous, current: previous["frame_idx"] == 28)
        self.assertEqual(len(ExpertDataset([self.data], timing=timing)), 1)
        self.assert_preflight_failure("samples=1, train=0, validation=1", timing=timing)

    def test_invalid_split_configuration_refuses_before_runtime_split_or_model(self):
        for fraction in (0, 1, True, float("nan")):
            with self.subTest(fraction=fraction):
                self.assert_preflight_failure("val_split must be a finite number", val_split=fraction)


if __name__ == "__main__":
    unittest.main()
