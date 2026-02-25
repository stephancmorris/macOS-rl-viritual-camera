#!/usr/bin/env python3
"""
Quick test model generator — no real training data required.

Generates a minimal CinematicFraming.mlpackage using synthetic data + 3 epochs
of BC training. The resulting model is intentionally undertrained (random-ish
behavior) but is structurally valid and lets you verify the full Xcode
integration pipeline before committing to hours of real training.

Usage:
    python make_test_model.py

Output:
    models/CinematicFraming.mlpackage  ← drag this into Xcode
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

# Ensure we're in the right directory
HERE = Path(__file__).parent


def main() -> int:
    print("=== CinematicCore Test Model Generator ===")
    print("Generating synthetic training data...")

    # Step 1: Generate synthetic JSONL sessions
    from test_env import create_synthetic_session

    with tempfile.TemporaryDirectory() as tmpdir:
        data_dir = Path(tmpdir)

        # Create a handful of synthetic sessions with varied movement
        for i in range(5):
            session_dir = data_dir / f"session_test_{i:04d}_2026-01-01_00-00-00"
            create_synthetic_session(session_dir, num_frames=200, fps=30)

        print(f"Created 5 synthetic sessions (200 frames each)")

        # Step 2: BC training (3 epochs — fast, produces a valid model)
        print("\nRunning Behavioral Cloning (3 epochs, ~20 seconds)...")
        from train_bc import train_bc

        models_dir = HERE / "models"
        models_dir.mkdir(exist_ok=True)
        bc_path = models_dir / "bc_test"

        stats = train_bc(
            data_dirs=[data_dir],
            output_path=bc_path,
            epochs=3,
            batch_size=64,
            verbose=True,
        )

        bc_zip = Path(str(bc_path) + ".zip")
        if not bc_zip.exists():
            print("ERROR: BC model not created")
            return 1

        # Step 3: Export to CoreML
        print("\nExporting to CoreML...")
        from export_coreml import export_coreml

        mlpackage_path = models_dir / "CinematicFraming.mlpackage"
        export_coreml(
            model_path=bc_zip,
            output_path=mlpackage_path,
            verbose=True,
        )

        if not mlpackage_path.exists():
            print("ERROR: CoreML export failed")
            return 1

    print("\n=== Done ===")
    print(f"\nTest model saved to:")
    print(f"  {mlpackage_path.resolve()}")
    print()
    print("Next steps:")
    print("  1. Open CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj in Xcode")
    print("  2. Drag the .mlpackage above into the CinematicCoreMacOS/ group")
    print("     in the Xcode Project Navigator")
    print('  3. When prompted, check "Add to target: CinematicCoreMacOS" → Add')
    print("  4. Build & Run (⌘R)")
    print("  5. Click the 'Agent' (brain icon) button in the app's control bar")
    print("  6. The popover should show 'Model loaded (Neural Engine)'")
    print("  7. Toggle 'Use RL Agent' ON, then enable Crop")
    print()
    print("Note: This model is undertrained (synthetic data, 3 epochs).")
    print("For real cinematic framing, collect YouTube clips and run the")
    print("full training pipeline — see training/TRAINING_GUIDE.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
