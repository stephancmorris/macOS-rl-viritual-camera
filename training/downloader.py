"""
Video acquisition: YouTube download (via yt-dlp) and local file validation.
"""

from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

_SUPPORTED_EXTENSIONS = {".mp4", ".mov", ".avi", ".mkv", ".webm"}


@dataclass
class VideoInfo:
    path: Path
    title: str
    duration: float  # seconds (0 if unknown)
    is_downloaded: bool


def acquire_video(
    source: str,
    output_dir: Path,
    max_resolution: int = 1080,
) -> VideoInfo:
    """Acquire a video from a URL or local path.

    Args:
        source: YouTube/Vimeo URL or local file path.
        output_dir: Directory to download into.
        max_resolution: Max video height for downloads.

    Returns:
        VideoInfo with path to the local video file.
    """
    if source.startswith("http://") or source.startswith("https://"):
        return _download_video(source, output_dir, max_resolution)
    else:
        return _validate_local(source)


def _download_video(
    url: str, output_dir: Path, max_resolution: int
) -> VideoInfo:
    """Download a video using yt-dlp."""
    if not shutil.which("yt-dlp"):
        raise RuntimeError(
            "yt-dlp is not installed. Install it with:\n"
            "  pip install yt-dlp\n"
            "  or: brew install yt-dlp"
        )

    output_dir.mkdir(parents=True, exist_ok=True)

    # Get video metadata first
    title = "unknown"
    duration = 0.0
    try:
        meta_result = subprocess.run(
            [
                "yt-dlp",
                "--print", "title",
                "--print", "duration",
                "--no-download",
                url,
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if meta_result.returncode == 0:
            lines = meta_result.stdout.strip().split("\n")
            if len(lines) >= 1:
                title = lines[0].strip()
            if len(lines) >= 2:
                try:
                    duration = float(lines[1].strip())
                except ValueError:
                    pass
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    # Download video
    output_path = output_dir / "source_video.mp4"
    format_spec = (
        f"bestvideo[height<={max_resolution}]+bestaudio"
        f"/best[height<={max_resolution}]"
    )

    print(f"Downloading: {title}")
    result = subprocess.run(
        [
            "yt-dlp",
            "-f", format_spec,
            "--merge-output-format", "mp4",
            "-o", str(output_path),
            "--no-playlist",
            url,
        ],
        capture_output=True,
        text=True,
        timeout=600,
    )

    if result.returncode != 0:
        raise RuntimeError(
            f"yt-dlp download failed:\n{result.stderr.strip()}"
        )

    if not output_path.exists():
        raise RuntimeError(
            f"Download completed but file not found at {output_path}"
        )

    print(f"Downloaded: {output_path} ({output_path.stat().st_size / 1e6:.1f} MB)")

    return VideoInfo(
        path=output_path,
        title=title,
        duration=duration,
        is_downloaded=True,
    )


def _validate_local(source: str) -> VideoInfo:
    """Validate a local video file."""
    path = Path(source).resolve()

    if not path.exists():
        raise FileNotFoundError(f"Video file not found: {path}")

    if path.suffix.lower() not in _SUPPORTED_EXTENSIONS:
        raise ValueError(
            f"Unsupported format '{path.suffix}'. "
            f"Supported: {', '.join(sorted(_SUPPORTED_EXTENSIONS))}"
        )

    return VideoInfo(
        path=path,
        title=path.stem,
        duration=0.0,  # will be read from OpenCV
        is_downloaded=False,
    )
