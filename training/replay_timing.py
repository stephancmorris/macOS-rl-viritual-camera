"""Explicit, opt-in timing for recorded framing observations.

Legacy replay assumes one fixed-rate control step per stored row. TimestampTiming
instead uses the supplied ``t`` fields as seconds and requires the caller to
classify every adjacent row pair as continuous or a boundary. Neither frame
indices nor metadata FPS establish continuity or elapsed timestamp time.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Callable


@dataclass(frozen=True)
class TimestampTiming:
    """Use timestamp seconds within caller-declared continuous partitions.

    ``continuity(previous_row, next_row)`` must return a Python bool for every
    adjacent stored pair. False starts a new partition. No gap threshold, index
    stride, timestamp tolerance, or action-time conversion is inferred.
    """

    continuity: Callable[[dict, dict], bool]

    def __post_init__(self) -> None:
        if not callable(self.continuity):
            raise ValueError("TimestampTiming.continuity must be callable")


@dataclass(frozen=True)
class ReplaySegment:
    frames: list[dict]
    # None explicitly identifies legacy assumed timing, rather than a measured dt.
    elapsed_seconds: tuple[float, ...] | None
    start_row: int


def timing_diagnostics(timing: TimestampTiming | None) -> dict[str, str]:
    """Describe whether elapsed time and continuity were supplied or assumed."""
    return {
        "timing_source": "timestamp_seconds" if timing is not None else "assumed_fixed_row_rate",
        "continuity_source": "caller_declared" if timing is not None else "assumed_adjacent_rows",
    }


def _finite_number(value: object) -> bool:
    try:
        return (not isinstance(value, bool) and isinstance(value, (int, float))
                and math.isfinite(value))
    except OverflowError:
        return False


def partition_frames(
    frames: list[dict],
    *,
    timing: TimestampTiming | None = None,
    context: str = "session",
) -> list[ReplaySegment]:
    """Resolve timestamp timing without guessing continuity or missing values.

    Every row requires a finite numeric ``t`` in timestamp mode. Continuous
    edges require a finite, strictly positive elapsed time. Clock resets may
    occur only across caller-declared boundaries. Singleton partitions remain
    explicit here; consumers cannot derive a transition from them.
    """
    if timing is None:
        return [ReplaySegment(frames, None, 0)] if frames else []
    if not isinstance(timing, TimestampTiming):
        raise ValueError("timing must be TimestampTiming or None")

    timestamps = []
    for i, frame in enumerate(frames):
        timestamp = frame.get("t")
        if not _finite_number(timestamp):
            raise ValueError(f"{context}: row {i} requires finite t in seconds for TimestampTiming")
        timestamps.append(timestamp)

    if not frames:
        return []
    segments = []
    start = 0
    elapsed = []
    for i in range(len(frames) - 1):
        edge = f"{context}: rows {i} -> {i + 1}"
        try:
            continuous = timing.continuity(frames[i], frames[i + 1])
        except Exception as error:
            raise ValueError(f"{edge}: continuity callback failed") from error
        if type(continuous) is not bool:
            raise ValueError(f"{edge}: continuity callback must return bool")
        if continuous:
            dt = timestamps[i + 1] - timestamps[i]
            if not _finite_number(dt) or dt <= 0:
                raise ValueError(f"{edge}: continuous timestamps require finite positive elapsed seconds")
            elapsed.append(dt)
        else:
            segments.append(ReplaySegment(frames[start:i + 1], tuple(elapsed), start))
            start = i + 1
            elapsed = []
    segments.append(ReplaySegment(frames[start:], tuple(elapsed), start))
    return segments
