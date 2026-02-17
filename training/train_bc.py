#!/usr/bin/env python3
"""
Phase 1: Behavioral Cloning pre-training.

Trains an SB3-compatible MlpPolicy on expert demonstrations derived from
YouTube/reference clips. The trained weights can be loaded directly by
PPO for fine-tuning (Phase 2).

Usage:
    python train_bc.py --data-dir output --epochs 50
    python train_bc.py --data-dir output --epochs 50 --lr 1e-3 --batch-size 512
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader

from bc_dataset import ExpertDataset
from cinematic_env import CinematicFramingEnv


def train_bc(
    data_dirs: list[Path],
    output_path: Path,
    epochs: int = 50,
    lr: float = 3e-4,
    batch_size: int = 256,
    val_split: float = 0.1,
    verbose: bool = True,
) -> dict:
    """Train behavioral cloning and save SB3-compatible model.

    Returns dict with training stats.
    """
    from stable_baselines3 import PPO

    # Load expert dataset
    dataset = ExpertDataset(data_dirs=data_dirs)
    if verbose:
        print(f"Expert dataset: {len(dataset)} samples")

    # Train/val split
    n_val = max(1, int(len(dataset) * val_split))
    n_train = len(dataset) - n_val
    train_set, val_set = torch.utils.data.random_split(
        dataset, [n_train, n_val],
        generator=torch.Generator().manual_seed(42),
    )

    train_loader = DataLoader(train_set, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_set, batch_size=batch_size, shuffle=False)

    if verbose:
        print(f"Train: {n_train}, Val: {n_val}")

    # Create SB3 PPO model to get the policy architecture
    env = CinematicFramingEnv(data_dirs=data_dirs)
    model = PPO("MlpPolicy", env, verbose=0)
    env.close()

    policy = model.policy
    policy.train()

    # Collect trainable parameters from actor network only
    actor_params = (
        list(policy.mlp_extractor.policy_net.parameters())
        + list(policy.action_net.parameters())
    )
    optimizer = torch.optim.Adam(actor_params, lr=lr)
    loss_fn = torch.nn.MSELoss()

    best_val_loss = float("inf")
    stats = {"train_losses": [], "val_losses": []}

    for epoch in range(epochs):
        # Training
        policy.train()
        train_loss_sum = 0.0
        train_count = 0

        for obs_batch, action_batch in train_loader:
            # Forward through actor network
            features = policy.extract_features(obs_batch, policy.pi_features_extractor)
            latent_pi = policy.mlp_extractor.forward_actor(features)
            predicted = policy.action_net(latent_pi)

            loss = loss_fn(predicted, action_batch)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()

            train_loss_sum += loss.item() * len(obs_batch)
            train_count += len(obs_batch)

        avg_train = train_loss_sum / train_count

        # Validation
        policy.eval()
        val_loss_sum = 0.0
        val_count = 0

        with torch.no_grad():
            for obs_batch, action_batch in val_loader:
                features = policy.extract_features(obs_batch, policy.pi_features_extractor)
                latent_pi = policy.mlp_extractor.forward_actor(features)
                predicted = policy.action_net(latent_pi)
                val_loss_sum += loss_fn(predicted, action_batch).item() * len(obs_batch)
                val_count += len(obs_batch)

        avg_val = val_loss_sum / val_count
        stats["train_losses"].append(avg_train)
        stats["val_losses"].append(avg_val)

        if avg_val < best_val_loss:
            best_val_loss = avg_val

        if verbose and (epoch + 1) % max(1, epochs // 10) == 0:
            print(
                f"Epoch {epoch + 1:3d}/{epochs} | "
                f"train_loss: {avg_train:.6f} | "
                f"val_loss: {avg_val:.6f}"
            )

    # Save as SB3-compatible model
    output_path.parent.mkdir(parents=True, exist_ok=True)
    model.save(str(output_path))

    if verbose:
        print(f"\nSaved BC model to {output_path}")
        print(f"Best val loss: {best_val_loss:.6f}")

    stats["best_val_loss"] = best_val_loss
    stats["n_samples"] = len(dataset)
    return stats


def main() -> int:
    parser = argparse.ArgumentParser(description="Phase 1: Behavioral Cloning")
    parser.add_argument(
        "--data-dir", type=str, default="output",
        help="Directory containing session data (default: output)",
    )
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument(
        "--output", type=str, default="models/bc_pretrained",
        help="Output model path (without .zip extension)",
    )

    args = parser.parse_args()
    data_dir = Path(args.data_dir)
    output_path = Path(args.output)

    train_bc(
        data_dirs=[data_dir],
        output_path=output_path,
        epochs=args.epochs,
        lr=args.lr,
        batch_size=args.batch_size,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
