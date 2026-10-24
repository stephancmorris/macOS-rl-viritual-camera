"""
Expert demonstration dataset for Behavioral Cloning.

Derives (observation, expert_action) pairs from JSONL sessions that contain
ideal_crop data (YouTube/reference clips from extract_frames.py). Expert actions are
computed as the velocity needed to move from ideal_crop[t] to ideal_crop[t+1].

Usage:
    dataset = ExpertDataset(data_dirs=["output"])
    obs, action = dataset[0]  # both float32 tensors
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import torch
from torch.utils.data import Dataset

from framing_samples import expert_pairs
from env_loader import scan_sessions
from replay_timing import TimestampTiming, partition_frames, timing_diagnostics


class ExpertDataset(Dataset):
    """PyTorch samples with optional caller-declared timestamp partitions.

    timing=None retains fixed-row-rate velocity and per-step expert actions.
    TimestampTiming changes velocity time and excludes boundary-spanning pairs.
    """

    def __init__(
        self,
        data_dirs: list[Path | str] | None = None,
        min_session_frames: int = 30,
        timing: TimestampTiming | None = None,
    ):
        if data_dirs is None:
            data_dirs = [Path(__file__).parent / "output"]
        dirs = [Path(d) for d in data_dirs]

        sessions = scan_sessions(dirs, min_frames=min_session_frames)

        self._observations: list[np.ndarray] = []
        self._actions: list[np.ndarray] = []

        self.timing_info = timing_diagnostics(timing)
        for session in sessions:
            for segment in partition_frames(
                session.frames, timing=timing, context=session.session_id,
            ):
                self._extract_pairs(segment.frames, session.fps, segment.elapsed_seconds)

        if not self._observations:
            raise ValueError(
                "No expert demonstrations found. Ensure sessions have "
                "'ideal_crop' data (run extract_frames.py on YouTube clips)."
            )

    def _extract_pairs(
        self,
        frames: list[dict],
        fps: int | float,
        elapsed_seconds: tuple[float, ...] | None = None,
    ) -> None:
        """Extract samples inside one partition without changing action units."""
        for obs, action in expert_pairs(frames, fps, elapsed_seconds=elapsed_seconds):
            self._observations.append(obs)
            self._actions.append(action)

    def __len__(self) -> int:
        return len(self._observations)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, torch.Tensor]:
        return (
            torch.from_numpy(self._observations[idx]),
            torch.from_numpy(self._actions[idx]),
        )
