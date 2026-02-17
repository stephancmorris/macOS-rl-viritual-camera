"""
Expert demonstration dataset for Behavioral Cloning.

Derives (observation, expert_action) pairs from JSONL sessions that contain
ideal_crop data (YouTube/reference clips from Task 3.1b). Expert actions are
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

from cinematic_env import (
    ASPECT_RATIO,
    MAX_PAN_SPEED,
    MAX_TILT_SPEED,
    MAX_ZOOM,
    MAX_ZOOM_SPEED,
)
from env_loader import scan_sessions


def build_observation(
    frame: dict,
    crop_x: float,
    crop_y: float,
    crop_w: float,
    crop_h: float,
    zoom: float,
    vel_x: float,
    vel_y: float,
) -> np.ndarray:
    """Build the 18-dim observation vector from frame data and crop state.

    Mirrors CinematicFramingEnv._build_observation() for consistency.
    """
    speaker = frame.get("speaker")
    keypoints = frame.get("keypoints")

    has_person = 1.0 if speaker else 0.0
    sp_x = speaker["x"] if speaker else 0.0
    sp_y = speaker["y"] if speaker else 0.0
    sp_z = min(speaker["z"] / 10.0, 1.0) if speaker else 0.0

    head_x = keypoints["head_x"] if keypoints else 0.0
    head_y = keypoints["head_y"] if keypoints else 0.0
    waist_x = keypoints["waist_x"] if keypoints else 0.0
    waist_y = keypoints["waist_y"] if keypoints else 0.0
    pose_conf = keypoints["pose_confidence"] if keypoints else 0.0

    zoom_norm = min(zoom / MAX_ZOOM, 1.0)

    if crop_h > 0.01 and has_person > 0.5:
        head_rel_y = np.clip((head_y - crop_y) / crop_h, 0.0, 1.0)
        waist_rel_y = np.clip((waist_y - crop_y) / crop_h, 0.0, 1.0)
    else:
        head_rel_y = 0.0
        waist_rel_y = 0.0

    obs = np.array([
        has_person, sp_x, sp_y, sp_z,
        head_x, head_y, waist_x, waist_y,
        crop_x, crop_y, crop_w, crop_h,
        zoom_norm, vel_x, vel_y,
        head_rel_y, waist_rel_y, pose_conf,
    ], dtype=np.float32)

    return np.nan_to_num(obs, nan=0.0, posinf=1.0, neginf=-1.0)


class ExpertDataset(Dataset):
    """PyTorch Dataset of (observation, expert_action) pairs from expert demos."""

    def __init__(
        self,
        data_dirs: list[Path | str] | None = None,
        min_session_frames: int = 30,
    ):
        if data_dirs is None:
            data_dirs = [Path(__file__).parent / "output"]
        dirs = [Path(d) for d in data_dirs]

        sessions = scan_sessions(dirs, min_frames=min_session_frames)

        self._observations: list[np.ndarray] = []
        self._actions: list[np.ndarray] = []

        for session in sessions:
            self._extract_pairs(session.frames, session.fps)

        if not self._observations:
            raise ValueError(
                "No expert demonstrations found. Ensure sessions have "
                "'ideal_crop' data (run extract_frames.py on YouTube clips)."
            )

    def _extract_pairs(self, frames: list[dict], fps: int) -> None:
        """Extract (obs, action) pairs from consecutive frames with ideal_crop."""
        for i in range(len(frames) - 1):
            frame_t = frames[i]
            frame_t1 = frames[i + 1]

            ideal_t = frame_t.get("ideal_crop")
            ideal_t1 = frame_t1.get("ideal_crop")
            if not ideal_t or not ideal_t1:
                continue

            # Derive expert action from consecutive ideal crops
            dx = (ideal_t1.get("x", 0) - ideal_t.get("x", 0)) / MAX_PAN_SPEED
            dy = (ideal_t1.get("y", 0) - ideal_t.get("y", 0)) / MAX_TILT_SPEED
            dz = (ideal_t1.get("zoom", 1) - ideal_t.get("zoom", 1)) / MAX_ZOOM_SPEED
            action = np.clip(np.array([dx, dy, dz], dtype=np.float32), -1.0, 1.0)

            # Build observation from frame_t using ideal_crop as the current crop
            crop_x = ideal_t.get("x", 0.0)
            crop_y = ideal_t.get("y", 0.0)
            crop_w = ideal_t.get("w", 1.0)
            crop_h = ideal_t.get("h", 1.0)
            zoom = ideal_t.get("zoom", 1.0)

            # Compute speaker velocity
            vel_x, vel_y = 0.0, 0.0
            if i > 0:
                prev = frames[i - 1]
                sp_prev = prev.get("speaker")
                sp_curr = frame_t.get("speaker")
                if sp_prev and sp_curr:
                    vel_x = float(np.clip(
                        (sp_curr["x"] - sp_prev["x"]) * fps, -1.0, 1.0
                    ))
                    vel_y = float(np.clip(
                        (sp_curr["y"] - sp_prev["y"]) * fps, -1.0, 1.0
                    ))

            obs = build_observation(
                frame_t, crop_x, crop_y, crop_w, crop_h, zoom, vel_x, vel_y
            )

            self._observations.append(obs)
            self._actions.append(action)

    def __len__(self) -> int:
        return len(self._observations)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, torch.Tensor]:
        return (
            torch.from_numpy(self._observations[idx]),
            torch.from_numpy(self._actions[idx]),
        )
