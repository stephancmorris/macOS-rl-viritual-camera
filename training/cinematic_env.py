"""
CinematicFramingEnv-v0: Gymnasium environment for cinematic framing RL.

Replays recorded sessions (JSONL from Tasks 3.1/3.1b) and lets an RL agent
learn to frame a speaker using velocity-based crop adjustments. The agent
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

from env_loader import SessionData, scan_sessions
from env_reward import compute_reward

# Action scaling constants (per frame)
MAX_PAN_SPEED = 0.02    # max 2% of canvas per frame
MAX_TILT_SPEED = 0.02
MAX_ZOOM_SPEED = 0.05   # max 5% zoom change per frame

# Crop constraints (matching ShotComposer.clampCropToFrame)
MIN_CROP_H = 0.25       # max zoom 4x
MAX_ZOOM = 4.0
ASPECT_RATIO = 16.0 / 9.0


class CinematicFramingEnv(gymnasium.Env):
    """Gymnasium environment for learning cinematic camera framing.

    Observation: 18-dim float32 vector (speaker state + crop state + velocity)
    Action: 3-dim float32 vector (pan, tilt, zoom velocities in [-1, 1])
    Reward: sum of framing, smoothness, cutoff, thirds, and anticipation components
    """

    metadata = {"render_modes": [], "render_fps": 30}

    def __init__(
        self,
        data_dirs: list[Path | str] | None = None,
        min_session_frames: int = 30,
        render_mode: str | None = None,
    ):
        super().__init__()
        self.render_mode = render_mode

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
        self._fps: int = 30
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

        # Pick a random session
        idx = self.np_random.integers(0, len(self._sessions))
        session = self._sessions[idx]
        self._fps = session.fps

        # Random slice of session
        min_len = 60
        max_len = 900
        if options:
            min_len = options.get("min_episode_len", min_len)
            max_len = options.get("max_episode_len", max_len)

        total = len(session.frames)
        ep_len = int(self.np_random.integers(
            min(min_len, total),
            min(total, max_len) + 1,
        ))
        start = int(self.np_random.integers(0, total - ep_len + 1))

        self._current_frames = session.frames[start:start + ep_len]
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
        }
        return obs, info

    def step(self, action):
        action = np.clip(np.asarray(action, dtype=np.float32), -1.0, 1.0)

        # Apply action to crop state
        self._apply_action(action)

        # Advance to next frame
        self._step_idx += 1

        # Check truncation
        truncated = self._step_idx >= len(self._current_frames)
        if truncated:
            self._step_idx = len(self._current_frames) - 1

        # Compute velocity from consecutive speaker positions
        frame = self._current_frames[self._step_idx]
        speaker = frame.get("speaker")
        vel_x, vel_y = 0.0, 0.0
        if speaker and self._prev_speaker_x is not None:
            vel_x = (speaker["x"] - self._prev_speaker_x) * self._fps
            vel_y = (speaker["y"] - self._prev_speaker_y) * self._fps
            vel_x = float(np.clip(vel_x, -1.0, 1.0))
            vel_y = float(np.clip(vel_y, -1.0, 1.0))

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

        info = {
            "frame_idx": frame.get("frame_idx", self._step_idx),
            "timestamp": frame.get("t", 0.0),
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
        frame = self._current_frames[self._step_idx]
        speaker = frame.get("speaker")
        keypoints = frame.get("keypoints")

        has_person = 1.0 if speaker else 0.0

        # Speaker position
        sp_x = speaker["x"] if speaker else 0.0
        sp_y = speaker["y"] if speaker else 0.0
        sp_z = min(speaker["z"] / 10.0, 1.0) if speaker else 0.0

        # Keypoints
        head_x = keypoints["head_x"] if keypoints else 0.0
        head_y = keypoints["head_y"] if keypoints else 0.0
        waist_x = keypoints["waist_x"] if keypoints else 0.0
        waist_y = keypoints["waist_y"] if keypoints else 0.0
        pose_conf = keypoints["pose_confidence"] if keypoints else 0.0

        # Crop state
        crop_x = self._crop_x
        crop_y = self._crop_y
        crop_w = self._crop_w
        crop_h = self._crop_h
        zoom_norm = min(self._zoom / MAX_ZOOM, 1.0)

        # Relative positions within crop
        if crop_h > 0.01 and has_person > 0.5:
            head_rel_y = np.clip((head_y - crop_y) / crop_h, 0.0, 1.0)
            waist_rel_y = np.clip((waist_y - crop_y) / crop_h, 0.0, 1.0)
        else:
            head_rel_y = 0.0
            waist_rel_y = 0.0

        obs = np.array([
            has_person,       # 0
            sp_x,             # 1
            sp_y,             # 2
            sp_z,             # 3
            head_x,           # 4
            head_y,           # 5
            waist_x,          # 6
            waist_y,          # 7
            crop_x,           # 8
            crop_y,           # 9
            crop_w,           # 10
            crop_h,           # 11
            zoom_norm,        # 12
            vel_x,            # 13
            vel_y,            # 14
            head_rel_y,       # 15
            waist_rel_y,      # 16
            pose_conf,        # 17
        ], dtype=np.float32)

        # Safety: replace any NaN/Inf
        return np.nan_to_num(obs, nan=0.0, posinf=1.0, neginf=-1.0)
