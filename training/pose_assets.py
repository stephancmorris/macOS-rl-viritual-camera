"""Pinned MediaPipe pose-landmarker files.

The task files are not in git. PersonDetector checks the SHA-256 of a known
filename before it loads the file. The digests below are from the version-1
objects at MODEL_URL, downloaded on this machine. Those same files still match
the MD5 values previously written next to the URLs: lite
04a75ddf7c811ac7a1a4523266dd7d88, full 83879689d373d143be094c972355e48e, heavy
453dec4d02ccc4d3ce812b6de84fa516.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "{name}/float16/1/{name}.task"
)

# complexity -> (filename stem, sha256)
_MODELS = {
    0: ("pose_landmarker_lite", "59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a"),
    1: ("pose_landmarker_full", "5134a3aad27a58b93da0088d431f366da362b44e3ccfbe3462b3827a839011b1"),
    2: ("pose_landmarker_heavy", "64437af838a65d18e5ba7a0d39b465540069bc8aae8308de3e318aad31fcbc7b"),
}


def model_record(model_complexity: int) -> tuple[str, str]:
    try:
        return _MODELS[model_complexity]
    except KeyError:
        raise ValueError(f"model_complexity must be 0, 1 or 2, got {model_complexity}") from None


def model_sha256(model_complexity: int) -> str:
    return model_record(model_complexity)[1]


def default_model_path(model_complexity: int) -> Path:
    """The model file for a complexity level, next to this package."""
    name, _sha256 = model_record(model_complexity)
    return Path(__file__).parent / f"{name}.task"


def download_instructions(model_complexity: int, destination: Path) -> str:
    name, sha256 = model_record(model_complexity)
    url = MODEL_URL.format(name=name)
    return (
        "Download it with:\n"
        f"  curl -L -o {destination} {url}\n"
        "and check it with:\n"
        f"  shasum -a 256 {destination}   # expect {sha256}"
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_pose_model(path: Path) -> None:
    """Reject a pinned model file whose SHA-256 does not match.

    A filename that is not one of the three version-1 assets is left alone so
    a caller can still pass their own model.
    """
    matched = [
        (complexity, name, sha256)
        for complexity, (name, sha256) in _MODELS.items()
        if path.name == f"{name}.task"
    ]
    if not matched:
        return
    complexity, _name, expected = matched[0]
    actual = sha256_file(path)
    if actual == expected:
        return
    instructions = download_instructions(complexity, path)
    raise RuntimeError(
        f"MediaPipe model at {path} does not match the pinned SHA-256.\n"
        f"expected {expected}\n"
        f"got      {actual}\n"
        f"{instructions}"
    )
