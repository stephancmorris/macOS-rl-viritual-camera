"""
Session writer for JSONL frames and metadata.json output.

Produces the same directory structure as the Swift TrainingDataRecorder:
  <output_dir>/session_youtube_YYYY-MM-DD_HH-mm-ss/
    frames.jsonl
    metadata.json
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from schema import FrameObservation, SessionMetadata


class SessionWriter:
    def __init__(
        self,
        base_dir: Path,
        video_title: str,
        fps: int,
        resolution: tuple[int, int],
        confidence_threshold: float = 0.5,
        model_complexity: int = 1,
    ):
        timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        self.session_id = f"session_youtube_{timestamp}"
        self.session_dir = base_dir / self.session_id
        self.session_dir.mkdir(parents=True, exist_ok=True)

        self.frames_path = self.session_dir / "frames.jsonl"
        self._file = open(self.frames_path, "w", encoding="utf-8")
        self._frame_count = 0

        self._metadata = SessionMetadata(
            session_id=self.session_id,
            start_time=datetime.now(timezone.utc).isoformat(),
            end_time=None,
            duration_seconds=None,
            total_frames=None,
            fps=fps,
            resolution={"width": resolution[0], "height": resolution[1]},
            camera_name=video_title,
            label_source="youtube",
            composer_config={
                "deadzone_threshold": 0.0,
                "horizontal_padding": 0.0,
                "smoothing_factor": 0.0,
                "use_rule_of_thirds": False,
            },
            detector_config={
                "confidence_threshold": confidence_threshold,
                "high_accuracy": model_complexity >= 1,
                "max_persons": 1,
            },
        )

    def write_frame(self, observation: FrameObservation) -> None:
        """Write a single frame observation as one line of JSONL."""
        line = json.dumps(observation.to_dict(), separators=(",", ":"))
        self._file.write(line + "\n")
        self._frame_count += 1

    def finalize(self, total_frames: int, duration: float) -> None:
        """Write metadata.json and close the frames file."""
        self._file.close()

        self._metadata.end_time = datetime.now(timezone.utc).isoformat()
        self._metadata.duration_seconds = round(duration, 3)
        self._metadata.total_frames = total_frames

        metadata_path = self.session_dir / "metadata.json"
        with open(metadata_path, "w", encoding="utf-8") as f:
            json.dump(self._metadata.to_dict(), f, indent=2, sort_keys=True)

    def close(self) -> None:
        """Close files without finalizing (for error recovery)."""
        if not self._file.closed:
            self._file.close()
