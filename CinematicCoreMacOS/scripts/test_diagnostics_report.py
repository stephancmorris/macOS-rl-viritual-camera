#!/usr/bin/env python3
"""Tests for diagnostics_report.py. Run: python3 -m unittest scripts/test_diagnostics_report.py"""

import csv
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import diagnostics_report as report  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
LEGACY = REPO / "reports/alfie-diagnostics-2026-09-06/evidence/alfie_soak_2026-08-23_034717.csv"

HEADER = ("elapsed_s,clock,window_kind,thermal,low_power,cpu_cores,cpu_pct,threads,source_h,crop_h_frac,upscale,"
          "footprint_mb,hop_mean_ms,hop_max_ms,queue_mean_ms,queue_max_ms,vision_mean_ms,vision_max_ms,"
          "frame_wall_mean_ms,frame_wall_max_ms,detections,frames_window,frames_total,handoff_refused_window,"
          "handoff_refused_total,gate_drops_window,gate_drops_total,main_active_mean_ms,main_active_max_ms,"
          "observation_age_mean_ms,observation_age_max_ms,processed_input_fps,detector_fps,handoff_fps,window_s,"
          "delivered_window,admitted_window,capture_dropped_window,capture_dropped_total,render_failed_window,"
          "render_failed_total,routed_window,no_route_window,repeated_window,repeated_total,presented_fps,"
          "diag_emit_ms,note").split(",")


def write_session(folder: Path, *, admitted=250, short_window_at=None, refused_at=None, closing=True,
                  thermal_at=None, windows=12, stamp="2026-09-28_120000"):
    rows, total = [], 0
    marker = {k: "" for k in HEADER}
    marker.update(elapsed_s="0.0", clock="12:00:00", window_kind="marker", thermal="nominal", low_power="no",
                  note="capture start; show_fps=50.0")
    rows.append(marker)
    refused_total = 0
    for i in range(windows):
        a = admitted // 2 if i == short_window_at else admitted
        refused = 2 if i == refused_at else 0
        refused_total += refused
        total += a - refused
        row = {k: "0" for k in HEADER}
        row.update(elapsed_s=f"{5.0 * (i + 1):.1f}", clock="12:00:05", window_kind="full",
                   thermal="serious" if thermal_at is not None and i >= thermal_at else "nominal",
                   low_power="no", footprint_mb="500", hop_mean_ms="0.5", hop_max_ms="2",
                   frame_wall_mean_ms="8", frame_wall_max_ms="15", detections="125", vision_mean_ms="16",
                   frames_window=str(a - refused), frames_total=str(total),
                   handoff_refused_window=str(refused), handoff_refused_total=str(refused_total),
                   window_s="5.000", delivered_window=str(a), admitted_window=str(a), routed_window=str(a),
                   presented_fps="unknown", diag_emit_ms="0.02", note="")
        rows.append(row)
    with (folder / f"alfie_soak_{stamp}.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=HEADER)
        writer.writeheader()
        writer.writerows(rows)
    manifest = {
        "schemaVersion": 2, "csvFile": f"alfie_soak_{stamp}.csv", "memoryFile": f"alfie_memory_{stamp}.csv",
        "startedAt": "2026-09-28T02:00:00Z",
        "identity": {
            "build": {"appVersion": "1.0", "buildNumber": "4", "sourceFingerprint": "abc123",
                      "osVersion": "26.0", "machineModel": "Mac16,1"},
            "source": {"inputKind": "Live camera", "deviceName": "Elgato 4K X", "captureProfile": "stage",
                       "requestedWidth": 3840, "requestedHeight": 2160, "configuredCaptureFPS": 50,
                       "captureSelectionReason": "preferred format", "belowShowRate": False,
                       "deliveredWidth": 3840, "deliveredHeight": 2160},
            "output": {"route": "Program Display", "showStandard": "1080p50", "showFPS": 50,
                       "presentation": "Program Display: handoff = IOSurface assigned …"},
        },
        "columns": [], "unobservable": ["ATEM / downstream switcher acquisition, cadence and tally"],
    }
    if closing:
        manifest["closing"] = {"endedAt": "2026-09-28T02:01:00Z", "note": "capture stop", "windowsWritten": windows,
                               "partialWindowFlushed": True, "emitMeanMS": 0.02, "emitMaxMS": 0.05}
    (folder / f"alfie_session_{stamp}.json").write_text(json.dumps(manifest))
    return folder


class ReportTests(unittest.TestCase):
    def run_report(self, folder):
        return report.build_report(report.load(report.locate(folder)))

    def test_healthy_schema2_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            text = self.run_report(write_session(Path(tmp)))
        self.assertIn("Schema 2", text)
        self.assertIn("Expected rate: 50.00 fps (manifest configured capture rate)", text)
        self.assertIn("Elgato 4K X", text)
        self.assertIn("| Delivered to Alfie | 3000 | 50.0 |", text)
        self.assertIn("| Presented downstream | unknown | unknown |", text)
        self.assertIn("**Cadence:** 0 of 12 full windows", text)
        self.assertIn("Nothing outside the expected ranges", text)

    def test_cadence_shortfall_and_refusals_are_observed(self):
        with tempfile.TemporaryDirectory() as tmp:
            text = self.run_report(write_session(Path(tmp), short_window_at=4, refused_at=7))
        self.assertIn("1 window(s) with delivered below 97% of 50.00 fps, first at 0:25", text)
        self.assertIn("Refused by the output route: 2 frame(s), first at 0:40", text)

    def test_missing_closing_and_thermal_are_observed(self):
        with tempfile.TemporaryDirectory() as tmp:
            text = self.run_report(write_session(Path(tmp), closing=False, thermal_at=6))
        self.assertIn("did not end with Stop", text)
        self.assertIn("serious at 0:35", text)
        self.assertIn("serious or critical thermal state", text)

    def test_folder_picks_the_newest_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = write_session(Path(tmp))
            (folder / "alfie_soak_2026-01-01_000000.csv").write_text(",".join(HEADER) + "\n")
            session = report.locate(folder)
        self.assertEqual(session.stamp, "2026-09-28_120000")

    def test_suffixed_file_trios_are_resolved_without_losing_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            stamp = "2026-09-28_120000_01234567-89AB-CDEF-0123-456789ABCDEF"
            write_session(folder, stamp=stamp)
            (folder / f"alfie_memory_{stamp}.csv").write_text("elapsed_s,note\n5,test\n")
            for name in (f"alfie_soak_{stamp}.csv", f"alfie_memory_{stamp}.csv", f"alfie_session_{stamp}.json"):
                session = report.locate(folder / name)
                self.assertEqual(session.stamp, stamp)
                self.assertEqual(session.soak_path.name, f"alfie_soak_{stamp}.csv")
                self.assertEqual(session.memory_path.name, f"alfie_memory_{stamp}.csv")
                self.assertEqual(session.manifest_path.name, f"alfie_session_{stamp}.json")
                self.assertIn("Elgato 4K X", report.build_report(report.load(session)))

    def test_same_second_folder_selection_uses_write_time_not_random_uuid(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            old = "2026-09-28_120000_FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
            new = "2026-09-28_120000_00000000-0000-0000-0000-000000000000"
            for index, stamp in enumerate((old, new), 1):
                write_session(folder, stamp=stamp)
                for path in folder.glob(f"*{stamp}*"):
                    os.utime(path, ns=(index * 1_000_000_000, index * 1_000_000_000))
            self.assertEqual(report.locate(folder).stamp, new)

    def test_malformed_suffix_does_not_alias_a_historical_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = write_session(Path(tmp))
            with self.assertRaises(SystemExit):
                report.locate(folder / "alfie_soak_2026-09-28_120000_bad.csv")

    @unittest.skipUnless(LEGACY.exists(), "legacy fixture not present")
    def test_legacy_schema1_session_is_summarised_with_its_limits(self):
        text = self.run_report(LEGACY)
        self.assertIn("Schema 1 (before METRICS)", text)
        self.assertIn("`out_drops` mixes", text)
        self.assertIn("Handoff accepted", text)
        # The known August symptom: hop lag and footprint grew over the run.
        self.assertIn("Capture → MainActor hop (ms) grew", text)
        self.assertIn("Footprint trended up", text)


class ReportParameterTests(unittest.TestCase):
    invalid_cli_values = ("nan", "inf", "-inf", "0", "-1", "1e309")
    invalid_api_values = (float("nan"), float("inf"), -float("inf"), 0.0, -1.0)

    def run_cli(self, folder, output, *options):
        return subprocess.run(
            [sys.executable, str(Path(report.__file__).resolve()), str(folder),
             "--out", str(output), *options],
            capture_output=True, text=True, check=False,
        )

    def assert_invalid_cli_preserves_output(self, option):
        with tempfile.TemporaryDirectory() as tmp:
            folder = write_session(Path(tmp), windows=2, short_window_at=1)
            output = folder / "summary.md"
            original = "existing reviewed evidence\n"
            for existing in (False, True):
                for value in self.invalid_cli_values:
                    with self.subTest(option=option, value=value, existing=existing):
                        if existing:
                            output.write_text(original)
                        elif output.exists():
                            output.unlink()
                        result = self.run_cli(folder, output, f"{option}={value}")
                        self.assertEqual(result.returncode, 2, result.stderr)
                        self.assertIn(f"{option} must be finite and greater than zero", result.stderr)
                        self.assertEqual(result.stdout, "")
                        if existing:
                            self.assertEqual(output.read_text(), original)
                        else:
                            self.assertFalse(output.exists())

    def test_cli_rejects_invalid_expected_fps_before_writing(self):
        self.assert_invalid_cli_preserves_output("--expected-fps")

    def test_cli_rejects_invalid_cadence_floor_before_writing(self):
        self.assert_invalid_cli_preserves_output("--cadence-floor")

    def test_cli_accepts_positive_custom_settings_and_reports_cadence(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = write_session(Path(tmp), windows=2, short_window_at=1)
            output = folder / "summary.md"
            # Rates are 50 and 25 fps. A multiplier above one remains supported.
            for fps, floor, short in ((25, 0.97, 0), (100, 0.4, 1), (50, 1.1, 2)):
                with self.subTest(fps=fps, floor=floor):
                    result = self.run_cli(folder, output, f"--expected-fps={fps}",
                                          f"--cadence-floor={floor}")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    text = output.read_text()
                    self.assertIn(f"Expected rate: {fps:.2f} fps (--expected-fps)", text)
                    self.assertIn(f"**Cadence:** {short} of 2 full windows", text)
                    self.assertIn(f"below {floor:.0%} of {fps:.2f} fps", text)
                    if short:
                        self.assertIn("first at 0:10" if short == 1 else "first at 0:05", text)

    def test_invalid_cli_parameter_is_rejected_before_input_loading(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "summary.md"
            result = self.run_cli(Path(tmp) / "missing-input", output, "--expected-fps=nan")
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("--expected-fps must be finite and greater than zero", result.stderr)
            self.assertFalse(output.exists())

    def test_build_report_rejects_invalid_expected_fps(self):
        with tempfile.TemporaryDirectory() as tmp:
            session = report.load(report.locate(write_session(Path(tmp), windows=2)))
            for value in self.invalid_api_values:
                with self.subTest(value=value):
                    with self.assertRaisesRegex(ValueError, "--expected-fps must be finite and greater than zero"):
                        report.build_report(session, expected_override=value)

    def test_build_report_rejects_invalid_cadence_floor(self):
        with tempfile.TemporaryDirectory() as tmp:
            session = report.load(report.locate(write_session(Path(tmp), windows=2)))
            for value in self.invalid_api_values:
                with self.subTest(value=value):
                    with self.assertRaisesRegex(ValueError, "--cadence-floor must be finite and greater than zero"):
                        report.build_report(session, cadence_floor=value)


if __name__ == "__main__":
    unittest.main()
