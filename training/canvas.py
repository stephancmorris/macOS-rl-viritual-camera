"""
Virtual canvas embedding algorithm.

Embeds a YouTube/reference frame as a crop within a virtual "wide shot" canvas
(normalized 1.0 x 1.0). Transforms all detection coordinates from frame-local
MediaPipe space into Apple Vision canvas coordinates (bottom-left origin, Y-up).

Key properties:
  - Zoom level is locked per video (temporal consistency)
  - Speaker trajectories are smooth across frames
  - Y-flip from MediaPipe (top-left, Y-down) to Vision (bottom-left, Y-up)
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import numpy as np

from detector import DetectionResult
from schema import CropData, IdealCropData, KeypointData, SpeakerData


@dataclass
class CanvasState:
    """Persistent state across frames for a single video."""

    zoom: float
    crop_h: float
    crop_w: float
    canvas_anchor_x: float  # where first speaker center maps in canvas X
    canvas_anchor_y: float  # where first speaker center maps in canvas Y (MP coords)
    first_frame_sx: float   # speaker center X in first frame
    first_frame_sy: float   # speaker center Y in first frame


@dataclass
class CanvasEmbedding:
    """Result of embedding a frame detection into the canvas."""

    speaker: Optional[SpeakerData]
    keypoints: Optional[KeypointData]
    crop: CropData           # in Vision canvas coords
    ideal_crop: IdealCropData  # same as crop for offline data
    state: CanvasState       # updated state for next frame


def _flip_y(y: float) -> float:
    """Convert MediaPipe Y (top-left, down) to Vision Y (bottom-left, up)."""
    return 1.0 - y


def _clamp(val: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, val))


def initialize_canvas(
    detection: DetectionResult,
    rng: np.random.Generator,
    zoom_range: tuple[float, float] = (1.5, 3.0),
    aspect_ratio: float = 16.0 / 9.0,
) -> CanvasState:
    """Initialize canvas state on the first frame with a detected person."""
    bh = detection.bbox_height or 0.3  # fallback if no bbox height

    # Heuristic: in a real wide shot, the speaker fills 12-22% of canvas height
    target_canvas_bh = rng.uniform(0.12, 0.22)
    zoom = bh / target_canvas_bh
    zoom = float(np.clip(zoom, zoom_range[0], zoom_range[1]))

    crop_h = 1.0 / zoom
    crop_w = crop_h * aspect_ratio
    if crop_w > 1.0:
        crop_w = 1.0
        crop_h = crop_w / aspect_ratio

    # Place speaker at a reasonable position in the canvas
    sx, sy = detection.center or (0.5, 0.5)
    canvas_anchor_x = float(rng.uniform(0.35, 0.65))
    canvas_anchor_y = float(rng.uniform(0.30, 0.55))

    return CanvasState(
        zoom=zoom,
        crop_h=crop_h,
        crop_w=crop_w,
        canvas_anchor_x=canvas_anchor_x,
        canvas_anchor_y=canvas_anchor_y,
        first_frame_sx=sx,
        first_frame_sy=sy,
    )


def embed_in_canvas(
    detection: DetectionResult,
    state: Optional[CanvasState],
    rng: np.random.Generator,
    zoom_range: tuple[float, float] = (1.5, 3.0),
    aspect_ratio: float = 16.0 / 9.0,
) -> CanvasEmbedding:
    """Embed a frame's detection results into the virtual canvas.

    Args:
        detection: Person detection from the current frame.
        state: Canvas state from previous frame (None on first frame).
        rng: Random number generator for reproducibility.
        zoom_range: Min/max virtual zoom levels.
        aspect_ratio: Output aspect ratio (16:9).

    Returns:
        CanvasEmbedding with all coordinates in Vision space.
    """
    # Initialize state on first detection
    if state is None and detection.has_person:
        state = initialize_canvas(detection, rng, zoom_range, aspect_ratio)

    # If we still have no state (no person detected yet), use defaults
    if state is None:
        default_crop_h = 1.0 / ((zoom_range[0] + zoom_range[1]) / 2)
        default_crop_w = min(1.0, default_crop_h * aspect_ratio)
        if default_crop_w >= 1.0:
            default_crop_h = default_crop_w / aspect_ratio

        crop_x_mp = (1.0 - default_crop_w) / 2
        crop_y_mp = (1.0 - default_crop_h) / 2
        zoom = 1.0 / default_crop_h

        # Convert crop to Vision coords
        crop_origin_y_vision = _flip_y(crop_y_mp + default_crop_h)

        crop = CropData(
            x=round(crop_x_mp, 6),
            y=round(crop_origin_y_vision, 6),
            w=round(default_crop_w, 6),
            h=round(default_crop_h, 6),
            zoom=round(zoom, 6),
        )
        ideal = IdealCropData(
            x=crop.x, y=crop.y, w=crop.w, h=crop.h,
            zoom=crop.zoom, source="youtube",
        )
        # Create a temporary state for continuity
        temp_state = CanvasState(
            zoom=zoom, crop_h=default_crop_h, crop_w=default_crop_w,
            canvas_anchor_x=0.5, canvas_anchor_y=0.5,
            first_frame_sx=0.5, first_frame_sy=0.5,
        )
        return CanvasEmbedding(
            speaker=None, keypoints=None,
            crop=crop, ideal_crop=ideal, state=temp_state,
        )

    # Compute crop position in MediaPipe canvas coords
    crop_x_mp, crop_y_mp = _compute_crop_position(detection, state)

    # Build speaker data
    speaker = None
    if detection.has_person and detection.bbox is not None:
        bx, by, bw, bh = detection.bbox

        # Transform bbox from frame-local to canvas coords (MediaPipe space)
        canvas_bx = crop_x_mp + bx * state.crop_w
        canvas_by = crop_y_mp + by * state.crop_h
        canvas_bw = bw * state.crop_w
        canvas_bh = bh * state.crop_h

        # Speaker center in canvas (MediaPipe space)
        cx_mp = canvas_bx + canvas_bw / 2
        cy_mp = canvas_by + canvas_bh / 2

        # Y-flip to Vision coords
        cx_vision = cx_mp
        cy_vision = _flip_y(cy_mp)
        bbox_origin_y_vision = _flip_y(canvas_by + canvas_bh)

        speaker = SpeakerData(
            x=round(_clamp(cx_vision), 6),
            y=round(_clamp(cy_vision), 6),
            z=round(1.0 / canvas_bh if canvas_bh > 0.01 else 0.0, 6),
            bbox=[
                round(_clamp(canvas_bx), 6),
                round(_clamp(bbox_origin_y_vision), 6),
                round(canvas_bw, 6),
                round(canvas_bh, 6),
            ],
            confidence=round(detection.confidence or 0.0, 6),
        )

    # Build keypoint data
    keypoints = None
    if detection.has_person and detection.head and detection.waist:
        hx_frame, hy_frame = detection.head
        wx_frame, wy_frame = detection.waist

        # Transform to canvas coords (MediaPipe space)
        hx_canvas = crop_x_mp + hx_frame * state.crop_w
        hy_canvas = crop_y_mp + hy_frame * state.crop_h
        wx_canvas = crop_x_mp + wx_frame * state.crop_w
        wy_canvas = crop_y_mp + wy_frame * state.crop_h

        # Y-flip to Vision coords
        keypoints = KeypointData(
            head_x=round(_clamp(hx_canvas), 6),
            head_y=round(_clamp(_flip_y(hy_canvas)), 6),
            waist_x=round(_clamp(wx_canvas), 6),
            waist_y=round(_clamp(_flip_y(wy_canvas)), 6),
            pose_confidence=round(detection.pose_confidence or 0.0, 6),
        )

    # Build crop data in Vision coords
    crop_origin_y_vision = _flip_y(crop_y_mp + state.crop_h)
    zoom = 1.0 / state.crop_h if state.crop_h > 0.01 else 1.0

    crop = CropData(
        x=round(_clamp(crop_x_mp), 6),
        y=round(_clamp(crop_origin_y_vision), 6),
        w=round(state.crop_w, 6),
        h=round(state.crop_h, 6),
        zoom=round(zoom, 6),
    )
    ideal = IdealCropData(
        x=crop.x, y=crop.y, w=crop.w, h=crop.h,
        zoom=crop.zoom, source="youtube",
    )

    return CanvasEmbedding(
        speaker=speaker,
        keypoints=keypoints,
        crop=crop,
        ideal_crop=ideal,
        state=state,
    )


def _compute_crop_position(
    detection: DetectionResult, state: CanvasState
) -> tuple[float, float]:
    """Compute crop origin in the canvas (MediaPipe coords).

    Tracks speaker movement relative to the first frame to maintain
    temporal consistency.
    """
    if not detection.has_person or detection.center is None:
        # No person: center the crop in the canvas
        crop_x = (1.0 - state.crop_w) / 2
        crop_y = (1.0 - state.crop_h) / 2
        return (crop_x, crop_y)

    sx, sy = detection.center

    # Speaker's movement since first frame
    delta_sx = sx - state.first_frame_sx
    delta_sy = sy - state.first_frame_sy

    # Speaker's canvas position shifts proportionally
    canvas_speaker_x = state.canvas_anchor_x + delta_sx * state.crop_w
    canvas_speaker_y = state.canvas_anchor_y + delta_sy * state.crop_h

    # Derive crop origin: crop_x + sx * crop_w = canvas_speaker_x
    crop_x = canvas_speaker_x - sx * state.crop_w
    crop_y = canvas_speaker_y - sy * state.crop_h

    # Clamp crop to canvas bounds [0, 1]
    crop_x = _clamp(crop_x, 0.0, 1.0 - state.crop_w)
    crop_y = _clamp(crop_y, 0.0, 1.0 - state.crop_h)

    return (crop_x, crop_y)
