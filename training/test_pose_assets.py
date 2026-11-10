"""SHA-256 pin for the version-1 pose models. Standard library only."""

import tempfile
import unittest
from pathlib import Path

import pose_assets


FULL_SHA256 = "5134a3aad27a58b93da0088d431f366da362b44e3ccfbe3462b3827a839011b1"


class PoseAssetTests(unittest.TestCase):
    def test_recorded_hashes_are_the_version_one_downloads(self):
        self.assertEqual(
            pose_assets.model_sha256(0),
            "59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a",
        )
        self.assertEqual(pose_assets.model_sha256(1), FULL_SHA256)
        self.assertEqual(
            pose_assets.model_sha256(2),
            "64437af838a65d18e5ba7a0d39b465540069bc8aae8308de3e318aad31fcbc7b",
        )

    def test_sha256_of_known_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bytes.bin"
            path.write_bytes(b"abc")
            self.assertEqual(
                pose_assets.sha256_file(path),
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            )

    def test_wrong_pinned_file_fails_with_the_download_instructions(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pose_landmarker_full.task"
            path.write_bytes(b"not the model")
            with self.assertRaises(RuntimeError) as caught:
                pose_assets.verify_pose_model(path)
        message = str(caught.exception)
        self.assertIn(FULL_SHA256, message)
        self.assertIn("float16/1/pose_landmarker_full.task", message)
        self.assertIn("shasum -a 256", message)
        self.assertNotIn("/latest/", message)

    def test_unknown_filename_is_not_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "custom.task"
            path.write_bytes(b"whatever")
            pose_assets.verify_pose_model(path)

    def test_download_instructions_name_the_version_one_url(self):
        text = pose_assets.download_instructions(1, Path("pose_landmarker_full.task"))
        self.assertIn("/float16/1/pose_landmarker_full.task", text)
        self.assertIn(FULL_SHA256, text)
        self.assertNotIn("/latest/", text)


if __name__ == "__main__":
    unittest.main()
