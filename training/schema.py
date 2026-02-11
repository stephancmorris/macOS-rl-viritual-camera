"""
Data models matching the Swift TrainingDataRecorder JSONL schema.

All field names use snake_case to match Swift's JSONEncoder with
.keyEncodingStrategy = .convertToSnakeCase.

Coordinate system: Apple Vision (bottom-left origin, Y increases upward, 0-1 normalized).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass
class SpeakerData:
    x: float          # bbox center X in canvas coords (0-1)
    y: float          # bbox center Y in canvas coords (0-1, Vision: Y-up)
    z: float          # depth proxy = 1.0 / bbox_height
    bbox: list[float]  # [origin_x, origin_y, width, height] in canvas coords
    confidence: float

    def to_dict(self) -> dict:
        return {
            "x": self.x,
            "y": self.y,
            "z": self.z,
            "bbox": self.bbox,
            "confidence": self.confidence,
        }


@dataclass
class KeypointData:
    head_x: float
    head_y: float          # Vision coords (Y-up)
    waist_x: float
    waist_y: float         # Vision coords (Y-up)
    pose_confidence: float

    def to_dict(self) -> dict:
        return {
            "head_x": self.head_x,
            "head_y": self.head_y,
            "waist_x": self.waist_x,
            "waist_y": self.waist_y,
            "pose_confidence": self.pose_confidence,
        }


@dataclass
class CropData:
    x: float   # crop origin X
    y: float   # crop origin Y (Vision coords)
    w: float   # crop width
    h: float   # crop height
    zoom: float  # 1.0 / h

    def to_dict(self) -> dict:
        return {
            "x": self.x,
            "y": self.y,
            "w": self.w,
            "h": self.h,
            "zoom": self.zoom,
        }


@dataclass
class IdealCropData:
    x: float
    y: float
    w: float
    h: float
    zoom: float
    source: str  # "auto", "manual", or "youtube"

    def to_dict(self) -> dict:
        return {
            "x": self.x,
            "y": self.y,
            "w": self.w,
            "h": self.h,
            "zoom": self.zoom,
            "source": self.source,
        }


@dataclass
class FrameObservation:
    t: float
    frame_idx: int
    speaker: Optional[SpeakerData]
    keypoints: Optional[KeypointData]
    current_crop: CropData
    ideal_crop: IdealCropData
    interpolating: bool = False

    def to_dict(self) -> dict:
        return {
            "t": self.t,
            "frame_idx": self.frame_idx,
            "speaker": self.speaker.to_dict() if self.speaker else None,
            "keypoints": self.keypoints.to_dict() if self.keypoints else None,
            "current_crop": self.current_crop.to_dict(),
            "ideal_crop": self.ideal_crop.to_dict(),
            "interpolating": self.interpolating,
        }


@dataclass
class SessionMetadata:
    session_id: str
    start_time: str           # ISO 8601
    end_time: Optional[str]
    duration_seconds: Optional[float]
    total_frames: Optional[int]
    fps: int
    resolution: dict          # {"width": int, "height": int}
    camera_name: str
    label_source: str
    composer_config: dict
    detector_config: dict

    def to_dict(self) -> dict:
        return {
            "camera_name": self.camera_name,
            "composer_config": self.composer_config,
            "detector_config": self.detector_config,
            "duration_seconds": self.duration_seconds,
            "end_time": self.end_time,
            "fps": self.fps,
            "label_source": self.label_source,
            "resolution": self.resolution,
            "session_id": self.session_id,
            "start_time": self.start_time,
            "total_frames": self.total_frames,
        }
