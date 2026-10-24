#!/usr/bin/env python3
"""
CoreML export: converts a trained SB3 PPO policy to .mlpackage.

Extracts the actor-only network (no critic/value head), preserves deterministic
SB3 clipping for the supported framing policy, and exports via coremltools.

Usage:
    python export_coreml.py --model models/ppo_final.zip --output models/CinematicFraming.mlpackage
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn


class ActorModule(nn.Module):
    """Standalone actor network extracted from SB3 policy.

    Supports the standard SB3 ActorCriticPolicy with unsquashed diagonal
    Gaussian actions, float32 Box observations of shape (18,), and float32 Box
    actions of shape (3,) bounded by [-1, 1]. Other configurations are refused.
    Deterministic SB3 prediction clips the actor mean to the action bounds.
    """

    def __init__(self, policy):
        super().__init__()
        from gymnasium.spaces import Box
        from stable_baselines3.common.distributions import DiagGaussianDistribution
        from stable_baselines3.common.policies import ActorCriticPolicy

        if type(policy) is not ActorCriticPolicy:
            raise ValueError("ActorModule supports the standard SB3 ActorCriticPolicy only")
        if policy.squash_output or type(policy.action_dist) is not DiagGaussianDistribution:
            raise ValueError("ActorModule requires unsquashed diagonal Gaussian actions")
        observations = policy.observation_space
        if (not isinstance(observations, Box) or observations.shape != (18,)
                or observations.dtype != np.dtype(np.float32)):
            raise ValueError("ActorModule requires a float32 Box observation space of shape (18,)")
        actions = policy.action_space
        if (not isinstance(actions, Box) or actions.shape != (3,)
                or actions.dtype != np.dtype(np.float32)
                or not np.all(actions.low == -1.0) or not np.all(actions.high == 1.0)):
            raise ValueError("ActorModule requires a float32 Box action space of shape (3,) with [-1, 1] bounds")

        self.features_extractor = policy.pi_features_extractor
        self.policy_net = policy.mlp_extractor.policy_net
        self.action_net = policy.action_net

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        features = self.features_extractor(x)
        latent = self.policy_net(features)
        raw_action = self.action_net(latent)
        return torch.clamp(raw_action, min=-1.0, max=1.0)


def export_coreml(
    model_path: Path,
    output_path: Path,
    verbose: bool = True,
) -> None:
    """Export SB3 model to CoreML .mlpackage."""
    import coremltools as ct
    from stable_baselines3 import PPO

    if verbose:
        print(f"Loading SB3 model from {model_path}")

    model = PPO.load(str(model_path))
    policy = model.policy
    policy.eval()

    # Extract actor-only network
    actor = ActorModule(policy)
    actor.eval()

    # Trace with dummy input
    dummy_input = torch.randn(1, 18, dtype=torch.float32)
    traced = torch.jit.trace(actor, dummy_input)

    if verbose:
        # Quick sanity check
        with torch.no_grad():
            test_output = actor(dummy_input)
        print(f"Actor output shape: {test_output.shape}")
        print(f"Actor output range: [{test_output.min():.3f}, {test_output.max():.3f}]")

    # Convert to CoreML
    if verbose:
        print("Converting to CoreML...")

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="observation", shape=(1, 18))],
        outputs=[ct.TensorType(name="action")],
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.macOS14,
    )

    # Add metadata
    mlmodel.author = "CinematicCore Training Pipeline"
    mlmodel.short_description = (
        "Cinematic framing policy: observes speaker position, "
        "outputs pan/tilt/zoom velocities in [-1, 1]."
    )
    mlmodel.input_description["observation"] = (
        "18-dim float32: [has_person, speaker_xyz, head_xy, waist_xy, "
        "crop_xywh, zoom, vel_xy, head_rel_y, waist_rel_y, pose_conf]"
    )
    mlmodel.output_description["action"] = (
        "3-dim float32: [pan_velocity, tilt_velocity, zoom_velocity] in [-1, 1]"
    )

    # Save
    output_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output_path))

    if verbose:
        print(f"Saved CoreML model to {output_path}")

        # Verify round-trip
        pred = mlmodel.predict({"observation": np.zeros((1, 18), dtype=np.float32)})
        action = pred["action"]
        print(f"Verification — zero obs → action shape: {action.shape}, values: {action.flatten()}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Export SB3 model to CoreML")
    parser.add_argument(
        "--model", type=str, required=True,
        help="Path to SB3 model (.zip)",
    )
    parser.add_argument(
        "--output", type=str, default="models/CinematicFraming.mlpackage",
        help="Output .mlpackage path",
    )
    parser.add_argument(
        "--trust-checkpoint", action="store_true",
        help="Load a checkpoint from outside training/models/ (it is unpickled)",
    )

    args = parser.parse_args()
    from checkpoint_trust import UntrustedCheckpointError, require_trusted
    try:
        model_path = require_trusted(Path(args.model), allow_untrusted=args.trust_checkpoint)
    except UntrustedCheckpointError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    export_coreml(
        model_path=model_path,
        output_path=Path(args.output),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
