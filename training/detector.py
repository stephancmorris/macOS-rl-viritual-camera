"""
Person detection and pose estimation using MediaPipe PoseLandmarker (tasks API).

All coordinates are returned in MediaPipe native space:
  - Top-left origin, Y increases downward
  - Normalized to [0, 1]

The Y-flip to Apple Vision coordinates happens in canvas.py.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import cv2
import mediapipe as mp
import numpy as np

BaseOptions = mp.tasks.BaseOptions
PoseLandmarker = mp.tasks.vision.PoseLandmarker
PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
RunningMode = mp.tasks.vision.RunningMode


@dataclass
class DetectionResult:
    has_person: bool
    bbox: Optional[tuple[float, float, float, float]] = None  # (x, y, w, h) normalized
    center: Optional[tuple[float, float]] = None               # (cx, cy) normalized
    bbox_height: Optional[float] = None
    confidence: Optional[float] = None
    head: Optional[tuple[float, float]] = None                  # (x, y) normalized
    waist: Optional[tuple[float, float]] = None                 # (x, y) normalized
    pose_confidence: Optional[float] = None


# MediaPipe Pose landmark indices
_NOSE = 0
_LEFT_EAR = 7
_RIGHT_EAR = 8
_LEFT_SHOULDER = 11
_RIGHT_SHOULDER = 12
_LEFT_HIP = 23
_RIGHT_HIP = 24

# Core body landmarks for overall confidence
_CORE_LANDMARKS = [_NOSE, _LEFT_SHOULDER, _RIGHT_SHOULDER, _LEFT_HIP, _RIGHT_HIP]

# MediaPipe pose models by --model-complexity (0=lite, 1=full, 2=heavy),
# pinned to model version 1 rather than `latest`. The md5 is what Google
# Cloud Storage reports for that object; check a download with `md5 -q`.
_MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "{name}/float16/1/{name}.task"
)
_MODELS = {
    0: ("pose_landmarker_lite", "04a75ddf7c811ac7a1a4523266dd7d88"),
    1: ("pose_landmarker_full", "83879689d373d143be094c972355e48e"),
    2: ("pose_landmarker_heavy", "453dec4d02ccc4d3ce812b6de84fa516"),
}


def default_model_path(model_complexity: int) -> Path:
    """The model file for a complexity level, next to this file."""
    if model_complexity not in _MODELS:
        raise ValueError(f"model_complexity must be 0, 1 or 2, got {model_complexity}")
    name, _ = _MODELS[model_complexity]
    return Path(__file__).parent / f"{name}.task"


def _download_instructions(model_complexity: int, destination: Path) -> str:
    name, md5 = _MODELS[model_complexity]
    url = _MODEL_URL.format(name=name)
    return (
        "Download it with:\n"
        f"  curl -L -o {destination} {url}\n"
        "and check it with:\n"
        f"  md5 -q {destination}   # expect {md5}"
    )


class PersonDetector:
    def __init__(
        self,
        confidence_threshold: float = 0.5,
        model_complexity: int = 1,
        model_path: Path | None = None,
    ):
        self.confidence_threshold = confidence_threshold

        # model_complexity picks the asset (lite / full / heavy). An explicit
        # model_path still wins. Default 1 is the full model, as before.
        model = model_path or default_model_path(model_complexity)
        if not model.exists():
            hint = _download_instructions(model_complexity, model) if model_path is None else ""
            raise FileNotFoundError(f"MediaPipe model not found at {model}.\n{hint}")

        options = PoseLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=str(model)),
            running_mode=RunningMode.VIDEO,
            num_poses=1,
            min_pose_detection_confidence=confidence_threshold,
            min_pose_presence_confidence=confidence_threshold,
            min_tracking_confidence=0.5,
        )
        self.landmarker = PoseLandmarker.create_from_options(options)
        self._frame_timestamp_ms = 0

    def detect(self, frame_bgr: np.ndarray) -> DetectionResult:
        """Process a single BGR frame and return detection results."""
        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)

        self._frame_timestamp_ms += 33  # ~30fps spacing
        results = self.landmarker.detect_for_video(mp_image, self._frame_timestamp_ms)

        if not results.pose_landmarks or len(results.pose_landmarks) == 0:
            return DetectionResult(has_person=False)

        # Use first detected pose
        landmarks = results.pose_landmarks[0]

        # Compute bounding box from visible landmarks
        bbox = self._compute_bbox(landmarks)
        if bbox is None:
            return DetectionResult(has_person=False)

        bx, by, bw, bh = bbox

        # Compute head position (average of ears, fallback to nose)
        head = self._compute_head(landmarks)

        # Compute waist position (average of hips)
        waist = self._compute_waist(landmarks)

        # Compute confidence scores
        confidence = self._compute_confidence(landmarks, _CORE_LANDMARKS)
        pose_conf = self._compute_confidence(
            landmarks,
            [_LEFT_EAR, _RIGHT_EAR, _NOSE, _LEFT_HIP, _RIGHT_HIP],
        )

        return DetectionResult(
            has_person=True,
            bbox=bbox,
            center=(bx + bw / 2, by + bh / 2),
            bbox_height=bh,
            confidence=confidence,
            head=head,
            waist=waist,
            pose_confidence=pose_conf,
        )

    def close(self):
        self.landmarker.close()

    def _compute_bbox(
        self, landmarks: list,
    ) -> Optional[tuple[float, float, float, float]]:
        """Compute bounding box from visible landmarks with 5% padding."""
        visible = [
            (lm.x, lm.y)
            for lm in landmarks
            if lm.visibility > self.confidence_threshold
        ]
        if len(visible) < 3:
            return None

        xs = [p[0] for p in visible]
        ys = [p[1] for p in visible]

        min_x, max_x = min(xs), max(xs)
        min_y, max_y = min(ys), max(ys)

        # Add 5% padding
        w = max_x - min_x
        h = max_y - min_y
        pad_x = w * 0.05
        pad_y = h * 0.05

        x = max(0.0, min_x - pad_x)
        y = max(0.0, min_y - pad_y)
        w = min(1.0 - x, w + 2 * pad_x)
        h = min(1.0 - y, h + 2 * pad_y)

        return (x, y, w, h)

    def _compute_head(self, landmarks: list) -> Optional[tuple[float, float]]:
        """Compute head position: average of ears, fallback to nose."""
        left_ear = landmarks[_LEFT_EAR]
        right_ear = landmarks[_RIGHT_EAR]

        if (
            left_ear.visibility > self.confidence_threshold
            and right_ear.visibility > self.confidence_threshold
        ):
            return (
                (left_ear.x + right_ear.x) / 2,
                (left_ear.y + right_ear.y) / 2,
            )

        nose = landmarks[_NOSE]
        if nose.visibility > self.confidence_threshold:
            return (nose.x, nose.y)

        return None

    def _compute_waist(self, landmarks: list) -> Optional[tuple[float, float]]:
        """Compute waist position: average of left and right hip."""
        left_hip = landmarks[_LEFT_HIP]
        right_hip = landmarks[_RIGHT_HIP]

        if (
            left_hip.visibility > self.confidence_threshold
            and right_hip.visibility > self.confidence_threshold
        ):
            return (
                (left_hip.x + right_hip.x) / 2,
                (left_hip.y + right_hip.y) / 2,
            )

        # Fallback: use whichever hip is visible
        if left_hip.visibility > self.confidence_threshold:
            return (left_hip.x, left_hip.y)
        if right_hip.visibility > self.confidence_threshold:
            return (right_hip.x, right_hip.y)

        return None

    def _compute_confidence(self, landmarks: list, indices: list[int]) -> float:
        """Average visibility of specified landmarks."""
        vis = [landmarks[i].visibility for i in indices]
        return float(np.mean(vis)) if vis else 0.0
