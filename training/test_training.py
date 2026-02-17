#!/usr/bin/env python3
"""
Smoke tests for the BC + PPO + CoreML training pipeline.

Tests:
  1. ExpertDataset creates valid (obs, action) pairs from synthetic data
  2. Expert actions are in [-1, 1] range
  3. Observations match env observation space shape (18,)
  4. BC training runs for 1 epoch without errors
  5. CoreML export produces valid .mlpackage (if coremltools available)
  6. Exported model accepts 18-dim input, returns 3-dim output in [-1, 1]
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import numpy as np
import torch

# Reuse synthetic data generator from test_env
from test_env import create_synthetic_session


def test_expert_dataset(data_dir: Path) -> None:
    """Test that ExpertDataset creates valid pairs."""
    from bc_dataset import ExpertDataset

    dataset = ExpertDataset(data_dirs=[data_dir])
    assert len(dataset) > 0, f"Empty dataset"

    obs, action = dataset[0]
    assert obs.shape == (18,), f"obs shape: {obs.shape}"
    assert action.shape == (3,), f"action shape: {action.shape}"
    assert obs.dtype == torch.float32
    assert action.dtype == torch.float32

    print(f"PASS: ExpertDataset creation ({len(dataset)} pairs)")


def test_expert_actions_bounded(data_dir: Path) -> None:
    """Test all expert actions are in [-1, 1]."""
    from bc_dataset import ExpertDataset

    dataset = ExpertDataset(data_dirs=[data_dir])

    for i in range(len(dataset)):
        _, action = dataset[i]
        assert torch.all(action >= -1.0) and torch.all(action <= 1.0), (
            f"action {i} out of bounds: {action}"
        )

    print("PASS: Expert actions bounded [-1, 1]")


def test_expert_obs_shape(data_dir: Path) -> None:
    """Test observations match env observation space."""
    from bc_dataset import ExpertDataset
    from cinematic_env import CinematicFramingEnv

    dataset = ExpertDataset(data_dirs=[data_dir])
    env = CinematicFramingEnv(data_dirs=[data_dir])

    for i in range(min(10, len(dataset))):
        obs, _ = dataset[i]
        assert obs.shape == env.observation_space.shape, (
            f"obs shape mismatch: {obs.shape} vs {env.observation_space.shape}"
        )

    env.close()
    print("PASS: Observation shapes match env")


def test_bc_training_smoke(data_dir: Path) -> None:
    """Test BC training runs for 1 epoch without errors."""
    from train_bc import train_bc

    with tempfile.TemporaryDirectory() as tmpdir:
        output_path = Path(tmpdir) / "test_bc"
        stats = train_bc(
            data_dirs=[data_dir],
            output_path=output_path,
            epochs=1,
            batch_size=32,
            verbose=False,
        )
        assert "best_val_loss" in stats
        assert np.isfinite(stats["best_val_loss"])
        assert Path(str(output_path) + ".zip").exists()

    print("PASS: BC training smoke test (1 epoch)")


def test_coreml_export(data_dir: Path) -> None:
    """Test CoreML export produces valid .mlpackage."""
    try:
        import coremltools as ct
    except ImportError:
        print("SKIP: coremltools not installed")
        return

    from stable_baselines3 import PPO

    from export_coreml import export_coreml

    with tempfile.TemporaryDirectory() as tmpdir:
        # First create a model to export
        from cinematic_env import CinematicFramingEnv

        env = CinematicFramingEnv(data_dirs=[data_dir])
        model = PPO("MlpPolicy", env, verbose=0)
        model_path = Path(tmpdir) / "test_model"
        model.save(str(model_path))
        env.close()

        # Export to CoreML
        mlpackage_path = Path(tmpdir) / "test.mlpackage"
        export_coreml(
            model_path=Path(str(model_path) + ".zip"),
            output_path=mlpackage_path,
            verbose=False,
        )

        assert mlpackage_path.exists(), "mlpackage not created"

        # Verify output
        mlmodel = ct.models.MLModel(str(mlpackage_path))
        pred = mlmodel.predict(
            {"observation": np.zeros((1, 18), dtype=np.float32)}
        )
        action = pred["action"]
        assert action.shape == (1, 3), f"output shape: {action.shape}"
        assert np.all(np.abs(action) <= 1.0), f"output out of [-1,1]: {action}"

    print("PASS: CoreML export and verification")


def main() -> int:
    with tempfile.TemporaryDirectory() as tmpdir:
        data_dir = Path(tmpdir)
        session_dir = data_dir / "session_test_2026-01-01_00-00-00"
        create_synthetic_session(session_dir, num_frames=100, fps=30)

        print(f"Test data: {session_dir}")
        print()

        test_expert_dataset(data_dir)
        test_expert_actions_bounded(data_dir)
        test_expert_obs_shape(data_dir)
        test_bc_training_smoke(data_dir)
        test_coreml_export(data_dir)

    print()
    print("All training pipeline tests passed!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
