#!/usr/bin/env python3
"""Synthetic temporary-file checks for explicit sanitized diagnostic export."""

import csv
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import diagnostics_export as export

STAMP = "2026-10-21_123456"
SENTINEL = "PRIVATE_PERSON_/Users/private/clip.mov_2031-02-03T12:34:56Z"


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.inputs = self.root / "private-inputs"
        self.outputs = self.root / "exports"
        self.inputs.mkdir()
        self.outputs.mkdir()
        self.soak = self.inputs / f"alfie_soak_{STAMP}.csv"
        self.memory = self.inputs / f"alfie_memory_{STAMP}.csv"
        self.out = self.outputs / "metrics.json"

    def write(self, path, rows):
        with path.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)

    def throughput(self, **changes):
        row = dict(elapsed_s="5", clock=SENTINEL, window_kind="full", thermal="nominal", low_power="no",
                   delivered_window="250", frames_window="249", frames_total="249", window_s="5",
                   cpu_pct="125.5", hop_mean_ms="0.5", presented_fps=SENTINEL, note=SENTINEL,
                   source_h="2160", crop_h_frac="0.8", inferred_name=SENTINEL,
                   face_embedding=SENTINEL, unexpected_payload=SENTINEL)
        row.update(changes)
        return row

    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(Path(export.__file__)), *map(str, args)],
                              text=True, capture_output=True)

    def test_projection_is_allowlisted_and_leaves_all_source_files_unchanged(self):
        self.write(self.soak, [self.throughput()])
        self.write(self.memory, [dict(elapsed_s="5", clock=SENTINEL, footprint_mb="512.25",
                                    heap_blocks="100", drop_timestamps="4", input_timestamps="50",
                                    detected_persons="3", note=SENTINEL, raw_pixels=SENTINEL)])
        # These adjacent files are never opened, even if their formats are invalid.
        for name in [f"alfie_session_{STAMP}.json", "frames.jsonl", "alfie-diagnostics.log", "picture.png"]:
            (self.inputs / name).write_text(SENTINEL)
        before = {p.name: p.read_bytes() for p in self.inputs.iterdir()}
        result = export.export_metrics(self.soak, self.out, self.memory)
        text = self.out.read_text()
        self.assertEqual(json.loads(text), result)
        for forbidden in [SENTINEL, STAMP, str(self.root), "source_h", "crop_h_frac", "detected_persons",
                          "inferred_name", "face_embedding", "unexpected_payload", "raw_pixels", "clock"]:
            self.assertNotIn('"' + forbidden + '"', text)
        self.assertNotIn(SENTINEL, text)
        self.assertNotIn(STAMP, text)
        self.assertNotIn(str(self.root), text)
        self.assertEqual(result["throughput"][0], {
            "elapsed_s": 5, "window_kind": "full", "thermal": "nominal", "low_power": "no",
            "delivered_window": 250, "frames_window": 249, "frames_total": 249, "window_s": 5,
            "cpu_pct": 125.5, "hop_mean_ms": 0.5})
        self.assertEqual(result["memory"][0], {"elapsed_s": 5, "footprint_mb": 512.25,
                                               "heap_blocks": 100, "drop_sample_count": 4,
                                               "input_sample_count": 50})
        self.assertEqual(result["presentedFPS"], "unknown")
        self.assertEqual({p.name: p.read_bytes() for p in self.inputs.iterdir()}, before)
        self.assertEqual(self.out.stat().st_mode & 0o777, 0o600)

    def test_legacy_losses_keep_their_mixed_stage_label_and_have_no_wall_clock(self):
        self.write(self.soak, [dict(elapsed_s="5", clock=SENTINEL, frames_window="245",
                                    out_drops_window="5", out_drops_total="5", frame_mean_ms="1.5",
                                    frame_max_ms="4", note=SENTINEL)])
        result = export.export_metrics(self.soak, self.out)
        self.assertEqual(result["sourceLayout"], "legacyMixedDrops")
        self.assertEqual(result["memory"], [])
        self.assertEqual(result["throughput"][0]["legacy_mixed_drops_window"], 5)
        self.assertEqual(result["throughput"][0]["frame_wall_mean_ms"], 1.5)
        self.assertNotIn(SENTINEL, self.out.read_text())

    def test_blank_and_unknown_measurements_are_omitted_without_inventing_zero(self):
        self.write(self.soak, [self.throughput(hop_mean_ms="unknown", frames_window="")])
        row = export.export_metrics(self.soak, self.out)["throughput"][0]
        self.assertNotIn("hop_mean_ms", row)
        self.assertNotIn("frames_window", row)

    def test_invalid_allowlisted_values_and_states_refuse_before_creation(self):
        cases = [("cpu_pct", v) for v in ["NaN", "inf", "-1", SENTINEL]]
        cases += [("frames_window", "2.5"), ("thermal", SENTINEL), ("low_power", "maybe"), ("window_kind", SENTINEL), ("elapsed_s", "")]
        for name, value in cases:
            with self.subTest(name=name, value=value):
                self.write(self.soak, [self.throughput(**{name: value})])
                with self.assertRaises(export.ExportError) as caught:
                    export.export_metrics(self.soak, self.out)
                self.assertNotIn(SENTINEL, str(caught.exception))
                self.assertFalse(self.out.exists())

    def test_large_counters_are_exact_and_cannot_hide_fractional_values(self):
        self.write(self.soak, [self.throughput(frames_total="9007199254740993",
                                             frames_window="18446744073709551615")])
        result = export.export_metrics(self.soak, self.out)
        self.assertEqual(result["throughput"][0]["frames_total"], 9007199254740993)
        self.assertEqual(result["throughput"][0]["frames_window"], 18446744073709551615)
        self.assertIn("9007199254740993", self.out.read_text())
        self.out.unlink()
        for invalid in ["9007199254740992.5", "18446744073709551616", "1e999999999"]:
            with self.subTest(invalid=invalid):
                self.write(self.soak, [self.throughput(frames_total=invalid)])
                with self.assertRaises(export.ExportError):
                    export.export_metrics(self.soak, self.out)
                self.assertFalse(self.out.exists())

    def test_ambiguous_headers_aliases_malformed_rows_and_empty_csv_are_rejected(self):
        contents = ["elapsed_s,cpu_pct,cpu_pct\n5,1,2\n", "elapsed_s,note\n5,secret\n",
                    "elapsed_s,frame_mean_ms,frame_wall_mean_ms\n5,1,2\n",
                    "elapsed_s,cpu_pct\n5,1,extra\n", "elapsed_s,cpu_pct\n5\n",
                    "elapsed_s,cpu_pct\n", "elapsed_s,cpu_pct\n\"unclosed,1\n"]
        for text in contents:
            with self.subTest(text=text):
                self.soak.write_text(text)
                with self.assertRaises(export.ExportError):
                    export.export_metrics(self.soak, self.out)
                self.assertFalse(self.out.exists())

    def test_mismatched_or_unreadable_memory_refuses_before_output(self):
        self.write(self.soak, [self.throughput()])
        other = self.inputs / "alfie_memory_2026-10-20_123456.csv"
        self.write(other, [dict(elapsed_s="5", heap_blocks="100")])
        with self.assertRaises(export.ExportError):
            export.export_metrics(self.soak, self.out, other)
        self.memory.write_bytes(b"\xff\xfe")
        with self.assertRaises(export.ExportError):
            export.export_metrics(self.soak, self.out, self.memory)
        self.assertFalse(self.out.exists())

    def test_explicit_new_destination_never_overwrites_or_adds_to_source_storage(self):
        self.write(self.soak, [self.throughput()])
        original = self.soak.read_bytes()
        self.out.write_text("existing report")
        with self.assertRaises(export.ExportError):
            export.export_metrics(self.soak, self.out)
        self.assertEqual(self.out.read_text(), "existing report")
        for destination in [self.soak, self.inputs / "new.json", self.inputs / "nested" / "new.json"]:
            with self.subTest(destination=destination):
                with self.assertRaises(export.ExportError):
                    export.export_metrics(self.soak, destination)
        self.assertEqual(self.soak.read_bytes(), original)
        self.assertEqual(sorted(p.name for p in self.inputs.iterdir()), [self.soak.name])

    def test_symlink_inputs_and_destinations_are_refused(self):
        self.write(self.soak, [self.throughput()])
        linked = self.root / self.soak.name
        linked.symlink_to(self.soak)
        with self.assertRaises(export.ExportError):
            export.export_metrics(linked, self.out)
        self.out.symlink_to(self.root / "missing.json")
        with self.assertRaises(export.ExportError):
            export.export_metrics(self.soak, self.out)
        self.assertFalse((self.root / "missing.json").exists())

    def test_no_directory_scan_or_recording_file_admission(self):
        self.write(self.soak, [self.throughput()])
        recording = self.inputs / "frames.jsonl"
        recording.write_text(SENTINEL)
        for source in [self.inputs, recording]:
            with self.subTest(source=source):
                with self.assertRaises(export.ExportError):
                    export.export_metrics(source, self.out)
        self.assertFalse(self.out.exists())

    def test_cli_requires_output_and_does_not_emit_input_paths_or_contents_on_error(self):
        self.write(self.soak, [self.throughput(cpu_pct=SENTINEL)])
        missing = self.run_cli(self.soak)
        self.assertEqual(missing.returncode, 2)
        refused = self.run_cli(self.soak, "--out", self.out)
        self.assertEqual(refused.returncode, 2)
        self.assertNotIn(SENTINEL, refused.stdout + refused.stderr)
        self.assertNotIn(str(self.root), refused.stdout + refused.stderr)
        self.assertFalse(self.out.exists())

    def test_cli_symlink_loop_failure_has_no_path_or_contents(self):
        self.write(self.soak, [self.throughput()])
        loop = self.outputs / "loop"
        loop.symlink_to(loop)
        process = self.run_cli(self.soak, "--out", loop / "metrics.json")
        self.assertEqual(process.returncode, 2)
        self.assertNotIn(str(self.root), process.stdout + process.stderr)
        self.assertNotIn("Traceback", process.stderr)

    def test_cli_exports_only_after_explicit_invocation(self):
        self.write(self.soak, [self.throughput()])
        self.assertFalse(self.out.exists())
        process = self.run_cli(self.soak, "--out", self.out)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(json.loads(self.out.read_text())["sourceLayout"], "splitStages")
        self.assertNotIn(str(self.root), process.stdout + process.stderr)


if __name__ == "__main__":
    unittest.main()
