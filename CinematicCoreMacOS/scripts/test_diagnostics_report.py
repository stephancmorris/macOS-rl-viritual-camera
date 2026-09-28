#!/usr/bin/env python3
"""Tests for diagnostics_report.py. Run: python3 -m unittest scripts/test_diagnostics_report.py"""

import csv
import json
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
                  thermal_at=None, windows=12):
    stamp = "2026-09-28_120000"
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

    @unittest.skipUnless(LEGACY.exists(), "legacy fixture not present")
    def test_legacy_schema1_session_is_summarised_with_its_limits(self):
        text = self.run_report(LEGACY)
        self.assertIn("Schema 1 (before METRICS)", text)
        self.assertIn("`out_drops` mixes", text)
        self.assertIn("Handoff accepted", text)
        # The known August symptom: hop lag and footprint grew over the run.
        self.assertIn("Capture → MainActor hop (ms) grew", text)
        self.assertIn("Footprint trended up", text)


if __name__ == "__main__":
    unittest.main()
