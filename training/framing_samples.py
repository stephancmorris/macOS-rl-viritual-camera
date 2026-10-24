"""NumPy framing features and expert samples shared by training consumers.

Actions retain their existing fixed increment per accepted control step. An
explicit elapsed time changes speaker velocity only, not the action units.
"""

from __future__ import annotations

import math
from collections.abc import Iterator, Sequence

import numpy as np

# Action scaling constants (per accepted control step)
MAX_PAN_SPEED = 0.02    # max 2% of canvas per control step
MAX_TILT_SPEED = 0.02
MAX_ZOOM_SPEED = 0.05   # max 5% zoom change per control step

MAX_ZOOM = 4.0
ASPECT_RATIO = 16.0 / 9.0


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

    Shared by the environment and behavioral-cloning samples.
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


def speaker_velocity(
    previous: dict | None,
    current: dict | None,
    *,
    fps: int | float,
    elapsed_seconds: float | None = None,
) -> tuple[float, float]:
    """Return clipped velocity using actual seconds or the legacy row rate.

    None elapsed seconds explicitly selects the legacy delta-times-FPS formula.
    A missing detection at either endpoint supplies no velocity evidence.
    """
    if elapsed_seconds is not None:
        try:
            valid = (not isinstance(elapsed_seconds, bool)
                     and isinstance(elapsed_seconds, (int, float))
                     and math.isfinite(elapsed_seconds) and elapsed_seconds > 0)
        except OverflowError:
            valid = False
        if not valid:
            raise ValueError("elapsed_seconds must be finite and positive")
    if not previous or not current:
        return 0.0, 0.0
    dx = current["x"] - previous["x"]
    dy = current["y"] - previous["y"]
    if elapsed_seconds is None:
        vel_x, vel_y = dx * fps, dy * fps
    else:
        vel_x, vel_y = dx / elapsed_seconds, dy / elapsed_seconds
    return float(np.clip(vel_x, -1.0, 1.0)), float(np.clip(vel_y, -1.0, 1.0))


def expert_pairs(
    frames: list[dict],
    fps: int | float,
    *,
    elapsed_seconds: Sequence[float] | None = None,
) -> Iterator[tuple[np.ndarray, np.ndarray]]:
    """Derive samples inside one declared partition, retaining fixed action units.

    Callers partition discontinuities before calling this function. A supplied
    elapsed-time sequence has exactly one entry per adjacent row pair.
    """
    if elapsed_seconds is not None and len(elapsed_seconds) != max(0, len(frames) - 1):
        raise ValueError("elapsed_seconds must contain one duration per adjacent row pair")
    for i in range(len(frames) - 1):
        frame_t = frames[i]
        frame_t1 = frames[i + 1]
        ideal_t = frame_t.get("ideal_crop")
        ideal_t1 = frame_t1.get("ideal_crop")
        if not ideal_t or not ideal_t1:
            continue

        dx = (ideal_t1.get("x", 0) - ideal_t.get("x", 0)) / MAX_PAN_SPEED
        dy = (ideal_t1.get("y", 0) - ideal_t.get("y", 0)) / MAX_TILT_SPEED
        dz = (ideal_t1.get("zoom", 1) - ideal_t.get("zoom", 1)) / MAX_ZOOM_SPEED
        action = np.clip(np.array([dx, dy, dz], dtype=np.float32), -1.0, 1.0)

        vel_x, vel_y = 0.0, 0.0
        if i > 0:
            vel_x, vel_y = speaker_velocity(
                frames[i - 1].get("speaker"), frame_t.get("speaker"), fps=fps,
                elapsed_seconds=None if elapsed_seconds is None else elapsed_seconds[i - 1],
            )
        obs = build_observation(
            frame_t, ideal_t.get("x", 0.0), ideal_t.get("y", 0.0),
            ideal_t.get("w", 1.0), ideal_t.get("h", 1.0),
            ideal_t.get("zoom", 1.0), vel_x, vel_y,
        )
        yield obs, action
