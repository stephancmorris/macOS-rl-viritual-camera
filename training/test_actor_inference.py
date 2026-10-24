"""Actual SB3/Torch actor parity without training, checkpoints or CoreML."""

from __future__ import annotations

import importlib.util
import unittest

import numpy as np

HAS_RUNTIME = all(importlib.util.find_spec(name) is not None
                  for name in ("torch", "gymnasium", "stable_baselines3"))


@unittest.skipUnless(HAS_RUNTIME, "Actor inference tests require Torch, Gymnasium and SB3")
class ActorInferenceTests(unittest.TestCase):
    def setUp(self):
        import torch
        from gymnasium.spaces import Box
        from stable_baselines3.common.policies import ActorCriticPolicy
        from export_coreml import ActorModule
        self.torch = torch
        self.Box = Box
        self.Policy = ActorCriticPolicy
        self.Actor = ActorModule

    def policy(self, observation_space=None, action_space=None, **kwargs):
        observations = observation_space if observation_space is not None else self.Box(
            low=-1, high=1, shape=(18,), dtype=np.float32,
        )
        actions = action_space if action_space is not None else self.Box(
            low=-1, high=1, shape=(3,), dtype=np.float32,
        )
        policy = self.Policy(observations, actions, lr_schedule=lambda _: .001, **kwargs)
        policy.set_training_mode(False)
        return policy

    def set_constant_action(self, policy, values):
        with self.torch.no_grad():
            policy.action_net.weight.zero_()
            policy.action_net.bias.copy_(self.torch.tensor(values, dtype=self.torch.float32))

    def assert_parity(self, policy, observations):
        expected, _ = policy.predict(observations, deterministic=True)
        actor = self.Actor(policy).eval()
        with self.torch.no_grad():
            actual = actor(self.torch.from_numpy(observations)).numpy()
        np.testing.assert_allclose(actual, expected, rtol=1e-6, atol=1e-7)
        self.assertEqual(actual.dtype, np.float32)
        return actual

    def test_interior_exact_boundary_and_clipped_actions_match_sb3(self):
        policy = self.policy()
        observations = np.zeros((4, 18), dtype=np.float32)
        for raw, expected in [
            ([.5, .25, -.75], [.5, .25, -.75]),
            ([-1, 1, 0], [-1, 1, 0]),
            ([-2, .5, 2], [-1, .5, 1]),
        ]:
            with self.subTest(raw=raw):
                self.set_constant_action(policy, raw)
                actual = self.assert_parity(policy, observations)
                np.testing.assert_array_equal(actual, np.tile(np.array(expected, dtype=np.float32), (4, 1)))

    def test_nonconstant_actor_path_matches_actual_sb3_for_batched_observations(self):
        rng = np.random.default_rng(42)
        observations = rng.uniform(-1, 1, (7, 18)).astype(np.float32)
        for shared in (True, False):
            with self.subTest(shared_features=shared):
                self.assert_parity(self.policy(share_features_extractor=shared), observations)

    def test_in_memory_trace_preserves_clipping_and_sb3_output(self):
        policy = self.policy()
        self.set_constant_action(policy, [.5, 1, 2])
        observations = np.zeros((2, 18), dtype=np.float32)
        actor = self.Actor(policy).eval()
        inputs = self.torch.from_numpy(observations)
        traced = self.torch.jit.trace(actor, inputs)
        with self.torch.no_grad():
            actual = traced(inputs).numpy()
        expected, _ = policy.predict(observations, deterministic=True)
        np.testing.assert_array_equal(actual, expected)

    def test_squashed_and_state_dependent_distributions_are_refused(self):
        for kwargs in ({"use_sde": True}, {"use_sde": True, "squash_output": True}):
            with self.subTest(configuration=kwargs):
                with self.assertRaisesRegex(ValueError, "requires unsquashed diagonal Gaussian actions"):
                    self.Actor(self.policy(**kwargs))

    def test_wrong_observation_shapes_and_dtypes_are_refused(self):
        for observations in [self.Box(-1, 1, (17,), dtype=np.float32),
                             self.Box(-1, 1, (18,), dtype=np.float64)]:
            with self.subTest(space=observations):
                with self.assertRaisesRegex(ValueError, "float32 Box observation space"):
                    self.Actor(self.policy(observation_space=observations))

    def test_wrong_action_shapes_bounds_and_dtypes_are_refused(self):
        for actions in [self.Box(-1, 1, (4,), dtype=np.float32),
                        self.Box(0, 1, (3,), dtype=np.float32),
                        self.Box(-2, 2, (3,), dtype=np.float32),
                        self.Box(-1, 1, (3,), dtype=np.float64)]:
            with self.subTest(space=actions):
                with self.assertRaisesRegex(ValueError, "float32 Box action space"):
                    self.Actor(self.policy(action_space=actions))

    def test_custom_policy_subclasses_and_discrete_actions_are_refused(self):
        from gymnasium.spaces import Discrete
        class CustomPolicy(self.Policy):
            pass
        policy = CustomPolicy(self.Box(-1, 1, (18,), dtype=np.float32),
                              self.Box(-1, 1, (3,), dtype=np.float32),
                              lr_schedule=lambda _: .001)
        with self.assertRaisesRegex(ValueError, "standard SB3 ActorCriticPolicy only"):
            self.Actor(policy)
        with self.assertRaisesRegex(ValueError, "requires unsquashed diagonal Gaussian actions"):
            self.Actor(self.policy(action_space=Discrete(3)))


if __name__ == "__main__":
    unittest.main()
