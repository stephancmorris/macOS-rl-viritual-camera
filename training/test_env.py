#!/usr/bin/env python3
"""
Smoke tests for CinematicFramingEnv.

Creates synthetic JSONL test data and validates:
  1. Environment creates successfully
  2. Observation and action spaces are valid
  3. reset() and step() return correct shapes
  4. Observations stay within bounds
  5. Rewards are finite and in expected range
  6. Episodes truncate at expected length
  7. SB3 check_env() passes (if stable-baselines3 is installed)
"""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

import numpy as np


def create_synthetic_session(
    session_dir: Path,
    num_frames: int = 100,
    fps: int = 30,
) -> None:
    """Create a synthetic JSONL session with a moving speaker."""
    session_dir.mkdir(parents=True, exist_ok=True)

    frames = []
    for i in range(num_frames):
        t = i / fps
        # Speaker moves slowly from left to right, slight vertical oscillation
        sx = 0.3 + 0.4 * (i / num_frames)
        sy = 0.55 + 0.05 * np.sin(2 * np.pi * i / num_frames)
        head_y = sy + 0.15
        waist_y = sy - 0.10

        frame = {
            "t": round(t, 3),
            "frame_idx": i,
            "speaker": {
                "x": round(sx, 4),
                "y": round(sy, 4),
                "z": round(1.0 / 0.35, 4),
                "bbox": [round(sx - 0.15, 4), round(waist_y, 4), 0.30, 0.35],
                "confidence": 0.95,
            },
            "keypoints": {
                "head_x": round(sx, 4),
                "head_y": round(head_y, 4),
                "waist_x": round(sx, 4),
                "waist_y": round(waist_y, 4),
                "pose_confidence": 0.90,
            },
            "current_crop": {
                "x": 0.1,
                "y": 0.15,
                "w": 0.8,
                "h": 0.45,
                "zoom": round(1.0 / 0.45, 4),
            },
            "ideal_crop": {
                "x": 0.1,
                "y": 0.15,
                "w": 0.8,
                "h": 0.45,
                "zoom": round(1.0 / 0.45, 4),
                "source": "youtube",
            },
            "interpolating": False,
        }
        frames.append(frame)

    # Write frames.jsonl
    with open(session_dir / "frames.jsonl", "w") as f:
        for frame in frames:
            f.write(json.dumps(frame, separators=(",", ":")) + "\n")

    # Write metadata.json
    metadata = {
        "camera_name": "synthetic_test",
        "composer_config": {
            "deadzone_threshold": 0.0,
            "horizontal_padding": 0.0,
            "smoothing_factor": 0.0,
            "use_rule_of_thirds": False,
        },
        "detector_config": {
            "confidence_threshold": 0.5,
            "high_accuracy": True,
            "max_persons": 1,
        },
        "duration_seconds": num_frames / fps,
        "end_time": None,
        "fps": fps,
        "label_source": "youtube",
        "resolution": {"width": 1920, "height": 1080},
        "session_id": session_dir.name,
        "start_time": "2026-01-01T00:00:00Z",
        "total_frames": num_frames,
    }
    with open(session_dir / "metadata.json", "w") as f:
        json.dump(metadata, f, indent=2, sort_keys=True)


def test_env_creation(data_dir: Path) -> None:
    """Test that the environment creates successfully."""
    from cinematic_env import CinematicFramingEnv

    env = CinematicFramingEnv(data_dirs=[data_dir])
    assert env.observation_space.shape == (18,), f"obs shape: {env.observation_space.shape}"
    assert env.action_space.shape == (3,), f"action shape: {env.action_space.shape}"
    print("PASS: Environment creation")
    env.close()


def test_reset(data_dir: Path) -> None:
    """Test reset returns correct format."""
    from cinematic_env import CinematicFramingEnv

    env = CinematicFramingEnv(data_dirs=[data_dir])
    obs, info = env.reset(seed=42)

    assert obs.shape == (18,), f"obs shape: {obs.shape}"
    assert obs.dtype == np.float32, f"obs dtype: {obs.dtype}"
    assert env.observation_space.contains(obs), f"obs out of bounds: {obs}"
    assert "session_id" in info
    assert "episode_length" in info
    print("PASS: reset() format")
    env.close()


def test_step(data_dir: Path) -> None:
    """Test step returns correct format and observations stay in bounds."""
    from cinematic_env import CinematicFramingEnv

    env = CinematicFramingEnv(data_dirs=[data_dir])
    obs, _ = env.reset(seed=42)

    total_reward = 0.0
    steps = 0

    while True:
        action = env.action_space.sample()
        obs, reward, terminated, truncated, info = env.step(action)

        assert obs.shape == (18,), f"step {steps}: obs shape {obs.shape}"
        assert obs.dtype == np.float32
        assert env.observation_space.contains(obs), (
            f"step {steps}: obs out of bounds: {obs}"
        )
        assert np.isfinite(reward), f"step {steps}: reward {reward}"
        assert -2.0 <= reward <= 1.5, f"step {steps}: reward {reward} out of range"
        assert isinstance(terminated, bool)
        assert isinstance(truncated, bool)
        assert not terminated, "episodes should never terminate, only truncate"

        total_reward += reward
        steps += 1

        if truncated:
            break

    print(f"PASS: step() format ({steps} steps, avg reward: {total_reward / steps:.3f})")
    env.close()


def test_multiple_resets(data_dir: Path) -> None:
    """Test multiple reset/episode cycles."""
    from cinematic_env import CinematicFramingEnv

    env = CinematicFramingEnv(data_dirs=[data_dir])

    for episode in range(5):
        obs, info = env.reset(seed=episode)
        assert env.observation_space.contains(obs)

        for _ in range(20):
            action = env.action_space.sample()
            obs, reward, terminated, truncated, info = env.step(action)
            if truncated:
                break

    print("PASS: Multiple reset/episode cycles")
    env.close()


def test_reward_components() -> None:
    """Test individual reward functions with known inputs."""
    from env_reward import (
        anticipation_bonus,
        framing_reward,
        head_cutoff_penalty,
        jitter_penalty,
        rule_of_thirds_bonus,
    )

    # Perfect framing: head at 2/3, waist at 1/3 of crop
    r = framing_reward(head_y=0.667, waist_y=0.333, crop_y=0.0, crop_h=1.0, has_person=True)
    assert 0.95 < r <= 1.0, f"perfect framing: {r}"

    # Bad framing
    r = framing_reward(head_y=0.5, waist_y=0.5, crop_y=0.0, crop_h=1.0, has_person=True)
    assert r < 0.5, f"bad framing: {r}"

    # No person
    r = framing_reward(head_y=0.667, waist_y=0.333, crop_y=0.0, crop_h=1.0, has_person=False)
    assert r == 0.0

    # Head cutoff
    r = head_cutoff_penalty(head_y=1.5, crop_y=0.0, crop_h=1.0, has_person=True)
    assert r == -1.0

    # Head safe
    r = head_cutoff_penalty(head_y=0.5, crop_y=0.0, crop_h=1.0, has_person=True)
    assert r == 0.0

    # No jitter (constant action)
    a = np.array([0.5, 0.5, 0.0])
    r = jitter_penalty(a, a, a)
    assert r == 0.0

    # High jitter
    r = jitter_penalty(
        np.array([1.0, 0.0, 0.0]),
        np.array([-1.0, 0.0, 0.0]),
        np.array([1.0, 0.0, 0.0]),
    )
    assert r < -0.3

    # Rule of thirds: speaker at 1/3 horizontal
    r = rule_of_thirds_bonus(speaker_x=0.333, crop_x=0.0, crop_w=1.0, has_person=True)
    assert 0.18 < r <= 0.2, f"thirds at 1/3: {r}"

    # Anticipation: camera moves with speaker
    r = anticipation_bonus(action_dx=1.0, action_dy=0.0, velocity_x=1.0, velocity_y=0.0, has_person=True)
    assert 0.09 < r <= 0.1, f"anticipation aligned: {r}"

    # Anticipation: camera moves against speaker
    r = anticipation_bonus(action_dx=-1.0, action_dy=0.0, velocity_x=1.0, velocity_y=0.0, has_person=True)
    assert r == 0.0

    print("PASS: Reward component unit tests")


def test_sb3_check_env(data_dir: Path) -> None:
    """Run SB3's check_env for full API compliance."""
    try:
        from stable_baselines3.common.env_checker import check_env
    except ImportError:
        print("SKIP: stable-baselines3 not installed (check_env)")
        return

    from cinematic_env import CinematicFramingEnv

    env = CinematicFramingEnv(data_dirs=[data_dir])
    check_env(env, warn=True)
    print("PASS: SB3 check_env()")
    env.close()


def main() -> int:
    with tempfile.TemporaryDirectory() as tmpdir:
        data_dir = Path(tmpdir)
        session_dir = data_dir / "session_test_2026-01-01_00-00-00"
        create_synthetic_session(session_dir, num_frames=100, fps=30)

        print(f"Test data: {session_dir}")
        print()

        test_reward_components()
        test_env_creation(data_dir)
        test_reset(data_dir)
        test_step(data_dir)
        test_multiple_resets(data_dir)
        test_sb3_check_env(data_dir)

    print()
    print("All tests passed!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
