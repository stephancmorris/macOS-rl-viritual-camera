"""
JSONL session loading for the Gymnasium environment.

Scans directories for session_*/frames.jsonl files produced by:
  - the Swift TrainingDataRecorder
  - extract_frames.py (YouTube/reference clips)

Both produce the same JSONL schema, so they load identically.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path


@dataclass
class SessionData:
    session_id: str
    frames: list[dict]
    fps: int | float
    source: str  # "live", "youtube", or "unknown"


def scan_sessions(
    data_dirs: list[Path | str],
    min_frames: int = 30,
) -> list[SessionData]:
    """Scan directories for session data and load into memory.

    Args:
        data_dirs: List of directories to scan for session_*/frames.jsonl.
        min_frames: Minimum frames required per session (skip shorter ones).

    Returns:
        List of SessionData, sorted by session_id.

    Raises:
        ValueError: A supplied row or metadata field is invalid or inconsistent.

    Index gaps and subsampling strides are preserved. Loading a session does
    not establish that adjacent stored observations are adjacent in time.
    """
    sessions: list[SessionData] = []

    for data_dir in data_dirs:
        data_dir = Path(data_dir).expanduser()
        if not data_dir.exists():
            continue

        for session_dir in sorted(data_dir.iterdir()):
            if not session_dir.is_dir() or not session_dir.name.startswith("session_"):
                continue

            frames_path = session_dir / "frames.jsonl"
            if not frames_path.exists():
                continue

            # Load frames
            frames = _load_jsonl(frames_path)
            # Load metadata
            fps = 30
            source = "unknown"
            metadata_path = session_dir / "metadata.json"
            if metadata_path.exists():
                context = f"{session_dir.name}/metadata.json"
                try:
                    with open(metadata_path, encoding="utf-8") as f:
                        meta = json.load(f)
                except (json.JSONDecodeError, UnicodeError) as error:
                    raise ValueError(f"{context}: invalid JSON metadata") from error
                if not isinstance(meta, dict):
                    raise ValueError(f"{context}: metadata must be an object")
                if "fps" in meta:
                    fps = meta["fps"]
                    _finite_number(fps, f"{context}: fps")
                    if fps <= 0:
                        raise ValueError(f"{context}: fps must be positive")
                if "session_id" in meta and meta["session_id"] != session_dir.name:
                    raise ValueError(f"{context}: session_id must match its session directory")
                total = meta.get("total_frames")
                if total is not None:
                    if type(total) is not int or total < 0:
                        raise ValueError(f"{context}: total_frames must be a nonnegative integer")
                    if total != len(frames):
                        raise ValueError(f"{context}: total_frames must match the persisted row count")
                label_source = meta.get("label_source", "")
                if not isinstance(label_source, str):
                    raise ValueError(f"{context}: label_source must be a string")
                if "youtube" in label_source:
                    source = "youtube"
                elif label_source in ("auto", "manual"):
                    source = "live"

            if len(frames) < min_frames:
                continue

            sessions.append(SessionData(
                session_id=session_dir.name,
                frames=frames,
                fps=fps,
                source=source,
            ))

    sessions.sort(key=lambda s: s.session_id)
    return sessions


def _finite_number(value: object, context: str) -> None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{context} must be a finite number")
    try:
        finite = math.isfinite(value)
    except OverflowError:
        finite = False
    if not finite:
        raise ValueError(f"{context} must be a finite number")


def _validate_frame(frame: object, context: str) -> None:
    if not isinstance(frame, dict):
        raise ValueError(f"{context}: frame must be an object")
    if "t" in frame:
        _finite_number(frame["t"], f"{context}: t")
    if "frame_idx" in frame:
        index = frame["frame_idx"]
        if type(index) is not int or index < 0:
            raise ValueError(f"{context}: frame_idx must be a nonnegative integer")

    # Preserve the consumers' defaults for absent optional objects/crop fields,
    # but require every field they index directly when an object is supplied.
    shapes = (
        ("speaker", ("x", "y", "z"), ("x", "y", "z", "confidence")),
        ("keypoints", ("head_x", "head_y", "waist_x", "waist_y", "pose_confidence"),
            ("head_x", "head_y", "waist_x", "waist_y", "pose_confidence")),
        ("current_crop", (), ("x", "y", "w", "h", "zoom")),
        ("ideal_crop", (), ("x", "y", "w", "h", "zoom")),
    )
    for name, required, numeric in shapes:
        if name not in frame or (frame[name] is None and name != "current_crop"):
            continue
        value = frame[name]
        if not isinstance(value, dict):
            raise ValueError(f"{context}: {name} must be an object")
        for key in required:
            if key not in value:
                raise ValueError(f"{context}: {name}.{key} is required")
        for key in numeric:
            if key in value:
                _finite_number(value[key], f"{context}: {name}.{key}")


def _load_jsonl(path: Path) -> list[dict]:
    """Load validated JSONL rows; invalid observations refuse the session."""
    frames = []
    with open(path, encoding="utf-8") as f:
        for line_number, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            context = f"{path.parent.name}/frames.jsonl line {line_number}"
            try:
                frame = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f"{context}: invalid JSON observation") from error
            _validate_frame(frame, context)
            frames.append(frame)
    return frames
