"""
CinematicFramingEnv-v0: Gymnasium environment for cinematic framing RL.

Replays recorded sessions (JSONL from TrainingDataRecorder and extract_frames.py)
and lets an RL agent learn to frame a speaker using velocity-based crop adjustments. The agent
observes speaker position + current crop and outputs pan/tilt/zoom velocities.

Usage:
    env = CinematicFramingEnv(data_dirs=["training/output"])
    obs, info = env.reset()
    obs, reward, terminated, truncated, info = env.step(action)
"""

from __future__ import annotations

from pathlib import Path

import gymnasium
import numpy as np

from env_loader import scan_sessions
from env_reward import compute_reward
from framing_samples import (
    ASPECT_RATIO, MAX_PAN_SPEED, MAX_TILT_SPEED, MAX_ZOOM, MAX_ZOOM_SPEED,
    build_observation, speaker_velocity,
)
from replay_timing import TimestampTiming, partition_frames, timing_diagnostics


class CinematicFramingEnv(gymnasium.Env):
    """Gymnasium environment for learning cinematic camera framing.

    Observation: 18-dim float32 vector (speaker state + crop state + velocity)
    Action: 3-dim float32 vector (pan, tilt, zoom velocities in [-1, 1])
    Reward: sum of framing, smoothness, cutoff, thirds, and anticipation components

    timing=None preserves the legacy fixed-row-rate assumption. TimestampTiming
    uses actual timestamp seconds for velocity and caller-declared partitions;
    actions and jitter penalties retain their per-control-step units.
    """

    metadata = {"render_modes": [], "render_fps": 30}

    def __init__(
        self,
        data_dirs: list[Path | str] | None = None,
        min_session_frames: int = 30,
        render_mode: str | None = None,
        timing: TimestampTiming | None = None,
    ):
        super().__init__()
        self.render_mode = render_mode
        self._timing = timing

        # Load sessions
        if data_dirs is None:
            data_dirs = [Path(__file__).parent / "output"]
        dirs = [Path(d) for d in data_dirs]
        self._sessions = scan_sessions(dirs, min_frames=min_session_frames)
        if not self._sessions:
            raise ValueError(
                f"No valid sessions found in {[str(d) for d in dirs]}. "
                "Run extract_frames.py first to generate training data."
            )

        self._replays = [
            (session, segment)
            for session in self._sessions
            for segment in partition_frames(
                session.frames, timing=timing, context=session.session_id,
            )
            if timing is None or len(segment.frames) >= 2
        ]
        if not self._replays:
            raise ValueError("No caller-declared continuous transitions available for TimestampTiming")

        # Observation: 18-dim vector
        low = np.array(
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, -1, 0, 0, 0],
            dtype=np.float32,
        )
        high = np.array(
            [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
            dtype=np.float32,
        )
        self.observation_space = gymnasium.spaces.Box(low=low, high=high, dtype=np.float32)

        # Action: pan (dx), tilt (dy), zoom (dz)
        self.action_space = gymnasium.spaces.Box(
            low=-1.0, high=1.0, shape=(3,), dtype=np.float32,
        )

        # Episode state (initialized in reset)
        self._current_frames: list[dict] = []
        self._step_idx: int = 0
        self._fps: int | float = 30
        self._current_elapsed_seconds: tuple[float, ...] | None = None
        self._crop_x: float = 0.0
        self._crop_y: float = 0.0
        self._crop_w: float = 1.0
        self._crop_h: float = 1.0
        self._zoom: float = 1.0
        self._prev_action: np.ndarray | None = None
        self._prev_prev_action: np.ndarray | None = None
        self._prev_speaker_x: float | None = None
        self._prev_speaker_y: float | None = None

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)

        # Pick a session partition; explicit timing never crosses its boundary.
        idx = self.np_random.integers(0, len(self._replays))
        session, segment = self._replays[idx]
        self._fps = session.fps

        # Random slice of session
        min_len = 60
        max_len = 900
        if options:
            min_len = options.get("min_episode_len", min_len)
            max_len = options.get("max_episode_len", max_len)

        total = len(segment.frames)
        lower = min(min_len, total)
        upper = min(total, max_len)
        if self._timing is not None:
            lower = max(2, lower)
            if upper < lower:
                raise ValueError("TimestampTiming episodes require at least two rows and valid length bounds")
        ep_len = int(self.np_random.integers(lower, upper + 1))
        start = int(self.np_random.integers(0, total - ep_len + 1))

        self._current_frames = segment.frames[start:start + ep_len]
        self._current_elapsed_seconds = (
            None if segment.elapsed_seconds is None
            else segment.elapsed_seconds[start:start + ep_len - 1]
        )
        self._step_idx = 0

        # Initialize crop from first frame
        first = self._current_frames[0]
        crop = first.get("current_crop", {})
        self._crop_x = crop.get("x", 0.0)
        self._crop_y = crop.get("y", 0.0)
        self._crop_w = crop.get("w", 1.0)
        self._crop_h = crop.get("h", 1.0)
        self._zoom = crop.get("zoom", 1.0)

        # Reset history
        self._prev_action = None
        self._prev_prev_action = None
        self._prev_speaker_x = None
        self._prev_speaker_y = None

        # Store initial speaker position for velocity computation
        speaker = first.get("speaker")
        if speaker:
            self._prev_speaker_x = speaker["x"]
            self._prev_speaker_y = speaker["y"]

        obs = self._build_observation(0.0, 0.0)
        info = {
            "session_id": session.session_id,
            "episode_length": ep_len,
            "source": session.source,
            "episode_start_row": segment.start_row + start,
            **timing_diagnostics(self._timing),
        }
        return obs, info

    def step(self, action):
        if self._timing is not None and self._step_idx >= len(self._current_frames) - 1:
            raise RuntimeError("TimestampTiming episode has no remaining transition; call reset()")
        action = np.clip(np.asarray(action, dtype=np.float32), -1.0, 1.0)

        # Apply action to crop state
        self._apply_action(action)

        # Advance to next frame
        self._step_idx += 1

        # Timestamp replay ends on the last real transition. Legacy replay
        # retains its existing terminal repeated-row behavior.
        if self._timing is not None:
            truncated = self._step_idx == len(self._current_frames) - 1
            elapsed_seconds = self._current_elapsed_seconds[self._step_idx - 1]
        else:
            truncated = self._step_idx >= len(self._current_frames)
            if truncated:
                self._step_idx = len(self._current_frames) - 1
            elapsed_seconds = None

        # Compute velocity from consecutive speaker positions
        frame = self._current_frames[self._step_idx]
        speaker = frame.get("speaker")
        previous = None if self._prev_speaker_x is None else {
            "x": self._prev_speaker_x, "y": self._prev_speaker_y,
        }
        vel_x, vel_y = speaker_velocity(
            previous, speaker, fps=self._fps, elapsed_seconds=elapsed_seconds,
        )

        # Build observation
        obs = self._build_observation(vel_x, vel_y)

        # Extract keypoint positions for reward
        keypoints = frame.get("keypoints")
        has_person = speaker is not None
        head_y = keypoints["head_y"] if keypoints else 0.0
        waist_y = keypoints["waist_y"] if keypoints else 0.0
        speaker_x = speaker["x"] if speaker else 0.0

        # Compute reward
        reward = compute_reward(
            has_person=has_person,
            head_y=head_y,
            waist_y=waist_y,
            speaker_x=speaker_x,
            crop_x=self._crop_x,
            crop_y=self._crop_y,
            crop_w=self._crop_w,
            crop_h=self._crop_h,
            action=action,
            prev_action=self._prev_action,
            prev_prev_action=self._prev_prev_action,
            velocity_x=vel_x,
            velocity_y=vel_y,
        )

        # Update history
        self._prev_prev_action = self._prev_action
        self._prev_action = action.copy()
        if speaker:
            self._prev_speaker_x = speaker["x"]
            self._prev_speaker_y = speaker["y"]
        elif self._timing is not None:
            self._prev_speaker_x = None
            self._prev_speaker_y = None

        info = {
            "frame_idx": frame.get("frame_idx", self._step_idx),
            "timestamp": frame.get("t", 0.0),
            "elapsed_seconds": elapsed_seconds,
            **timing_diagnostics(self._timing),
        }

        terminated = False
        return obs, float(reward), terminated, truncated, info

    def _apply_action(self, action: np.ndarray) -> None:
        """Apply velocity action to update crop state."""
        dx = float(action[0]) * MAX_PAN_SPEED
        dy = float(action[1]) * MAX_TILT_SPEED
        dz = float(action[2]) * MAX_ZOOM_SPEED

        # Update zoom (clamped to [1.0, 4.0])
        self._zoom = float(np.clip(self._zoom + dz, 1.0, MAX_ZOOM))

        # Derive crop size from zoom, maintaining aspect ratio
        self._crop_h = 1.0 / self._zoom
        self._crop_w = self._crop_h * ASPECT_RATIO

        # If crop width exceeds canvas, clamp and recompute
        if self._crop_w > 1.0:
            self._crop_w = 1.0
            self._crop_h = self._crop_w / ASPECT_RATIO
            self._zoom = 1.0 / self._crop_h

        # Update origin (clamped to canvas bounds)
        self._crop_x = float(np.clip(
            self._crop_x + dx, 0.0, 1.0 - self._crop_w,
        ))
        self._crop_y = float(np.clip(
            self._crop_y + dy, 0.0, 1.0 - self._crop_h,
        ))

    def _build_observation(self, vel_x: float, vel_y: float) -> np.ndarray:
        """Build the 18-dim observation vector from current state."""
        return build_observation(
            self._current_frames[self._step_idx],
            self._crop_x, self._crop_y, self._crop_w, self._crop_h,
            self._zoom, vel_x, vel_y,
        )
