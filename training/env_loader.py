"""
JSONL session loading for the Gymnasium environment.

Scans directories for session_*/frames.jsonl files produced by:
  - Task 3.1 (Swift TrainingDataRecorder)
  - Task 3.1b (YouTube extract_frames.py pipeline)

Both produce the same JSONL schema, so they load identically.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass
class SessionData:
    session_id: str
    frames: list[dict]
    fps: int
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
            if len(frames) < min_frames:
                continue

            # Load metadata
            fps = 30
            source = "unknown"
            metadata_path = session_dir / "metadata.json"
            if metadata_path.exists():
                try:
                    with open(metadata_path, encoding="utf-8") as f:
                        meta = json.load(f)
                    fps = meta.get("fps", 30)
                    label_source = meta.get("label_source", "")
                    if "youtube" in label_source:
                        source = "youtube"
                    elif label_source in ("auto", "manual"):
                        source = "live"
                except (json.JSONDecodeError, KeyError):
                    pass

            sessions.append(SessionData(
                session_id=session_dir.name,
                frames=frames,
                fps=fps,
                source=source,
            ))

    sessions.sort(key=lambda s: s.session_id)
    return sessions


def _load_jsonl(path: Path) -> list[dict]:
    """Load a JSONL file, skipping malformed lines."""
    frames = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                frames.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return frames
