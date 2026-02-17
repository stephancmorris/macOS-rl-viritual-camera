#!/usr/bin/env python3
"""
Phase 2: PPO fine-tuning.

Loads BC-pretrained weights (or trains from scratch) and fine-tunes with
Proximal Policy Optimization on the CinematicFramingEnv.

Usage:
    python train_ppo.py --bc-model models/bc_pretrained.zip --total-steps 500000
    python train_ppo.py --from-scratch --total-steps 1000000
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import CheckpointCallback

from cinematic_env import CinematicFramingEnv


def train_ppo(
    data_dirs: list[Path],
    bc_model_path: Path | None = None,
    output_path: Path = Path("models/ppo_final"),
    total_timesteps: int = 500_000,
    lr: float = 1e-4,
    n_steps: int = 2048,
    batch_size: int = 64,
    n_epochs: int = 10,
    checkpoint_freq: int = 50_000,
    tb_log_dir: str = "models/tb_logs",
    verbose: int = 1,
) -> PPO:
    """Train PPO, optionally starting from BC-pretrained weights."""
    env = CinematicFramingEnv(data_dirs=data_dirs)

    if bc_model_path and bc_model_path.exists():
        if verbose:
            print(f"Loading BC-pretrained model from {bc_model_path}")
        model = PPO.load(
            str(bc_model_path),
            env=env,
            learning_rate=lr,
            n_steps=n_steps,
            batch_size=batch_size,
            n_epochs=n_epochs,
            tensorboard_log=tb_log_dir,
            verbose=verbose,
        )
    else:
        if bc_model_path:
            print(f"WARNING: BC model not found at {bc_model_path}, training from scratch")
        model = PPO(
            "MlpPolicy",
            env,
            learning_rate=lr,
            n_steps=n_steps,
            batch_size=batch_size,
            n_epochs=n_epochs,
            clip_range=0.2,
            tensorboard_log=tb_log_dir,
            verbose=verbose,
        )

    # Checkpoint callback
    checkpoint_dir = Path("models/checkpoints")
    checkpoint_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_cb = CheckpointCallback(
        save_freq=checkpoint_freq,
        save_path=str(checkpoint_dir),
        name_prefix="ppo_cinematic",
    )

    if verbose:
        print(f"Training PPO for {total_timesteps:,} timesteps...")

    model.learn(
        total_timesteps=total_timesteps,
        callback=checkpoint_cb,
    )

    # Save final model
    output_path.parent.mkdir(parents=True, exist_ok=True)
    model.save(str(output_path))
    if verbose:
        print(f"Saved final model to {output_path}")

    env.close()
    return model


def main() -> int:
    parser = argparse.ArgumentParser(description="Phase 2: PPO Fine-Tuning")
    parser.add_argument(
        "--data-dir", type=str, default="output",
        help="Directory containing session data",
    )
    parser.add_argument(
        "--bc-model", type=str, default=None,
        help="Path to BC-pretrained model (.zip)",
    )
    parser.add_argument(
        "--from-scratch", action="store_true",
        help="Train from random initialization (skip BC)",
    )
    parser.add_argument("--total-steps", type=int, default=500_000)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--n-steps", type=int, default=2048)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument(
        "--output", type=str, default="models/ppo_final",
        help="Output model path (without .zip)",
    )

    args = parser.parse_args()

    bc_path = None
    if not args.from_scratch:
        bc_path = Path(args.bc_model) if args.bc_model else Path("models/bc_pretrained.zip")

    train_ppo(
        data_dirs=[Path(args.data_dir)],
        bc_model_path=bc_path,
        output_path=Path(args.output),
        total_timesteps=args.total_steps,
        lr=args.lr,
        n_steps=args.n_steps,
        batch_size=args.batch_size,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
