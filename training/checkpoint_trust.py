"""
Guard for loading Stable-Baselines3 checkpoints from the command line.

`PPO.load` restores part of a checkpoint .zip with cloudpickle, so loading a
checkpoint runs code stored in it (CR-044). The CLIs therefore load, by
default, only checkpoints under this pipeline's own `training/models/`
folder. Anything else needs `--trust-checkpoint`, which says the operator
knows where the file came from. Library callers (tests, make_test_model.py)
pass their own temporary files and are not affected.
"""

from __future__ import annotations

from pathlib import Path

TRUSTED_DIR = Path(__file__).resolve().parent / "models"


class UntrustedCheckpointError(ValueError):
    """A checkpoint outside the trusted folder was given without consent."""


def require_trusted(
    path: Path,
    allow_untrusted: bool = False,
    trusted_dir: Path = TRUSTED_DIR,
) -> Path:
    """Return the resolved path, or raise if it is not under `trusted_dir`."""
    resolved = Path(path).expanduser().resolve()
    if allow_untrusted:
        print(
            f"WARNING: loading {resolved} with --trust-checkpoint. "
            "Stable-Baselines3 unpickles checkpoints; only load files you made."
        )
        return resolved
    if not resolved.is_relative_to(Path(trusted_dir).resolve()):
        raise UntrustedCheckpointError(
            f"{resolved} is outside {trusted_dir}. Loading a Stable-Baselines3 "
            "checkpoint runs code stored in it. Move the file into "
            "training/models/, or pass --trust-checkpoint if you made it."
        )
    return resolved
