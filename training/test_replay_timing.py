"""Stdlib tests of explicit timing declarations; no training dependencies."""

from __future__ import annotations

import math
import unittest

from replay_timing import TimestampTiming, partition_frames, timing_diagnostics


def row(index, timestamp):
    return {"frame_idx": index, "t": timestamp}


class ReplayTimingTests(unittest.TestCase):
    def test_legacy_keeps_rows_and_marks_timing_assumed_even_without_timestamps(self):
        frames = [{"frame_idx": 0}, {"frame_idx": 10}, {"frame_idx": 11}]
        segment, = partition_frames(frames)
        self.assertIs(segment.frames, frames)
        self.assertIsNone(segment.elapsed_seconds)
        self.assertEqual(timing_diagnostics(None), {
            "timing_source": "assumed_fixed_row_rate",
            "continuity_source": "assumed_adjacent_rows",
        })

    def test_required_caller_decision_partitions_the_verified_gap(self):
        frames = [row(0, 0), row(10, 10 / 30), row(11, 11 / 30)]
        # This synthetic study explicitly declares its observed missing interval.
        timing = TimestampTiming(lambda previous, current: previous["frame_idx"] != 0)
        segments = partition_frames(frames, timing=timing, context="session_gap")
        self.assertEqual([s.start_row for s in segments], [0, 1])
        self.assertEqual([[r["frame_idx"] for r in s.frames] for s in segments], [[0], [10, 11]])
        self.assertEqual(segments[0].elapsed_seconds, ())
        self.assertAlmostEqual(segments[1].elapsed_seconds[0], 1 / 30)
        self.assertEqual(timing_diagnostics(timing)["continuity_source"], "caller_declared")

    def test_subsampling_stride_is_a_caller_decision_not_an_inferred_gap(self):
        frames = [row(0, 0), row(2, 2 / 30), row(4, 4 / 30)]
        # The study declares stride two to be its continuous sampling cadence.
        timing = TimestampTiming(lambda previous, current: current["frame_idx"] - previous["frame_idx"] == 2)
        segment, = partition_frames(frames, timing=timing)
        self.assertEqual(segment.elapsed_seconds, (2 / 30, 2 / 30))

    def test_frame_indices_are_not_required_or_used_to_derive_elapsed_time(self):
        frames = [{"t": 10.0}, {"t": 10.25}]
        segment, = partition_frames(frames, timing=TimestampTiming(lambda a, b: True))
        self.assertEqual(segment.elapsed_seconds, (0.25,))

    def test_missing_and_invalid_timestamps_refuse_explicit_mode(self):
        invalid = [None, True, "0.1", float("nan"), float("inf"), 10 ** 1000]
        for value in invalid:
            with self.subTest(timestamp=value):
                with self.assertRaisesRegex(ValueError, "session_bad: row 1 requires finite t"):
                    partition_frames([row(0, 0), row(1, value)],
                                     timing=TimestampTiming(lambda a, b: True), context="session_bad")
        with self.assertRaisesRegex(ValueError, "row 1 requires finite t"):
            partition_frames([row(0, 0), {}], timing=TimestampTiming(lambda a, b: False))

    def test_equal_reverse_and_overflow_elapsed_time_refuse_continuous_edges(self):
        for first, second in [(0, 0), (1, 0), (-1e308, 1e308), (-10 ** 308, 10 ** 308)]:
            with self.subTest(first=first, second=second):
                with self.assertRaisesRegex(ValueError, "session_clock: rows 0 -> 1: continuous timestamps"):
                    partition_frames([row(0, first), row(1, second)],
                                     timing=TimestampTiming(lambda a, b: True), context="session_clock")

    def test_no_tolerance_or_minimum_elapsed_threshold_is_added(self):
        tiny = math.nextafter(0.0, 1.0)
        segment, = partition_frames([row(0, 0), row(1, tiny)],
                                    timing=TimestampTiming(lambda a, b: True))
        self.assertEqual(segment.elapsed_seconds, (tiny,))

    def test_clock_reset_requires_a_declared_boundary(self):
        segments = partition_frames([row(0, 100), row(1, 0), row(2, 0.2)],
                                    timing=TimestampTiming(lambda a, b: b["frame_idx"] != 1))
        self.assertEqual([s.elapsed_seconds for s in segments], [(), (0.2,)])

    def test_callback_is_required_callable_and_returns_actual_booleans(self):
        with self.assertRaises(TypeError):
            TimestampTiming()
        with self.assertRaisesRegex(ValueError, "must be callable"):
            TimestampTiming(None)
        for value in (None, 1, 0, "continuous"):
            with self.subTest(result=value):
                with self.assertRaisesRegex(ValueError, "rows 0 -> 1: continuity callback must return bool"):
                    partition_frames([row(0, 0), row(1, 1)],
                                     timing=TimestampTiming(lambda a, b: value))
        with self.assertRaisesRegex(ValueError, "timing must be TimestampTiming or None"):
            partition_frames([row(0, 0)], timing=True)

    def test_callback_failure_has_session_and_edge_context(self):
        def fails(previous, current):
            raise KeyError("study boundary evidence missing")
        with self.assertRaisesRegex(ValueError, "session_policy: rows 0 -> 1: continuity callback failed") as caught:
            partition_frames([row(0, 0), row(1, 1)], timing=TimestampTiming(fails), context="session_policy")
        self.assertIsInstance(caught.exception.__cause__, KeyError)

    def test_empty_and_singleton_partitions_cannot_invent_transitions(self):
        timing = TimestampTiming(lambda a, b: True)
        self.assertEqual(partition_frames([], timing=timing), [])
        segment, = partition_frames([row(0, 0)], timing=timing)
        self.assertEqual(segment.elapsed_seconds, ())


if __name__ == "__main__":
    unittest.main()
