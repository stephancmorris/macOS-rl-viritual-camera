"""
Reward function for CinematicFramingEnv.

Five components matching the ROADMAP.md specification:
  1. Framing reward (+1.0): head at upper third, waist at lower third
  2. Jitter penalty (-0.5): penalizes jerky acceleration changes
  3. Head cutoff penalty (-1.0): head outside crop bounds
  4. Rule of thirds bonus (+0.2): horizontal compositional quality
  5. Anticipation bonus (+0.1): camera moves in speaker's direction

All functions are pure (no env state coupling) for testability.
"""

from __future__ import annotations

import numpy as np


def framing_reward(
    head_y: float,
    waist_y: float,
    crop_y: float,
    crop_h: float,
    has_person: bool,
) -> float:
    """Reward for rule-of-thirds vertical framing.

    Ideal: head at 2/3 from crop bottom, waist at 1/3.
    Uses Gaussian shaping (sigma=0.1) for smooth gradients.

    Returns: [0.0, 1.0]
    """
    if not has_person or crop_h < 0.01:
        return 0.0

    head_rel = (head_y - crop_y) / crop_h    # ideal: 0.667
    waist_rel = (waist_y - crop_y) / crop_h   # ideal: 0.333

    head_error = abs(head_rel - 0.667)
    waist_error = abs(waist_rel - 0.333)
    error = (head_error + waist_error) / 2.0

    return float(np.exp(-(error ** 2) / (2 * 0.1 ** 2)))


def jitter_penalty(
    action: np.ndarray | None,
    prev_action: np.ndarray | None,
    prev_prev_action: np.ndarray | None,
) -> float:
    """Penalty for jerky camera movement (high jerk = change in acceleration).

    Returns: [-0.5, 0.0]
    """
    if action is None or prev_action is None or prev_prev_action is None:
        return 0.0

    accel_now = action - prev_action
    accel_prev = prev_action - prev_prev_action
    jerk = float(np.linalg.norm(accel_now - accel_prev))

    return -0.5 * min(jerk / 1.0, 1.0)


def head_cutoff_penalty(
    head_y: float,
    crop_y: float,
    crop_h: float,
    has_person: bool,
) -> float:
    """Penalty when speaker's head is cut off or near crop edge.

    Returns: [-1.0, 0.0]
    """
    if not has_person or crop_h < 0.01:
        return 0.0

    head_rel = (head_y - crop_y) / crop_h

    # Head completely outside crop
    if head_rel > 1.0 or head_rel < 0.0:
        return -1.0

    # Soft penalty when head is within 5% of edge
    margin = min(head_rel, 1.0 - head_rel)
    if margin < 0.05:
        return -0.5

    return 0.0


def rule_of_thirds_bonus(
    speaker_x: float,
    crop_x: float,
    crop_w: float,
    has_person: bool,
) -> float:
    """Bonus for horizontal rule-of-thirds placement.

    Rewards speaker near the 1/3 or 2/3 horizontal lines.
    Uses Gaussian shaping (sigma=0.05).

    Returns: [0.0, 0.2]
    """
    if not has_person or crop_w < 0.01:
        return 0.0

    speaker_rel_x = (speaker_x - crop_x) / crop_w

    dist_left = abs(speaker_rel_x - 0.333)
    dist_right = abs(speaker_rel_x - 0.667)
    min_dist = min(dist_left, dist_right)

    return 0.2 * float(np.exp(-(min_dist ** 2) / (2 * 0.05 ** 2)))


def anticipation_bonus(
    action_dx: float,
    action_dy: float,
    velocity_x: float,
    velocity_y: float,
    has_person: bool,
) -> float:
    """Bonus when camera movement aligns with speaker velocity.

    Rewards anticipatory tracking (moving with the speaker).

    Returns: [0.0, 0.1]
    """
    if not has_person:
        return 0.0

    speed = np.sqrt(velocity_x ** 2 + velocity_y ** 2)
    if speed < 0.01:
        return 0.0

    movement = np.array([action_dx, action_dy])
    velocity = np.array([velocity_x, velocity_y])

    move_norm = np.linalg.norm(movement)
    if move_norm < 1e-8:
        return 0.0

    alignment = float(np.dot(movement, velocity) / (move_norm * speed))
    return 0.1 * max(0.0, alignment)


def compute_reward(
    has_person: bool,
    head_y: float,
    waist_y: float,
    speaker_x: float,
    crop_x: float,
    crop_y: float,
    crop_w: float,
    crop_h: float,
    action: np.ndarray | None,
    prev_action: np.ndarray | None,
    prev_prev_action: np.ndarray | None,
    velocity_x: float,
    velocity_y: float,
) -> float:
    """Compute total reward from all components.

    Returns: clipped to [-2.0, 1.5]
    """
    r = 0.0
    r += framing_reward(head_y, waist_y, crop_y, crop_h, has_person)
    r += jitter_penalty(action, prev_action, prev_prev_action)
    r += head_cutoff_penalty(head_y, crop_y, crop_h, has_person)
    r += rule_of_thirds_bonus(speaker_x, crop_x, crop_w, has_person)
    r += anticipation_bonus(
        float(action[0]) if action is not None else 0.0,
        float(action[1]) if action is not None else 0.0,
        velocity_x, velocity_y, has_person,
    )
    return float(np.clip(r, -2.0, 1.5))
