#!/usr/bin/env python3
"""Tests for checkpoint_trust (CR-044). Standard library only:
    python3 -m unittest test_checkpoint_trust   (from training/)
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from checkpoint_trust import TRUSTED_DIR, UntrustedCheckpointError, require_trusted


class RequireTrustedTests(unittest.TestCase):
    def test_checkpoint_under_models_is_trusted(self) -> None:
        path = TRUSTED_DIR / "bc_pretrained.zip"
        self.assertEqual(require_trusted(path), path.resolve())

    def test_checkpoint_elsewhere_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(UntrustedCheckpointError):
                require_trusted(Path(tmp) / "downloaded.zip")

    def test_parent_traversal_does_not_escape(self) -> None:
        with self.assertRaises(UntrustedCheckpointError):
            require_trusted(TRUSTED_DIR / ".." / ".." / "elsewhere.zip")

    def test_explicit_trust_allows_any_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "mine.zip"
            self.assertEqual(require_trusted(path, allow_untrusted=True), path.resolve())


if __name__ == "__main__":
    unittest.main()
