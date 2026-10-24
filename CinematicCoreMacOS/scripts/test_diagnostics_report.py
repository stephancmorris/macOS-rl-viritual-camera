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
                       "operatorMode": "single_cam", "requestedWidth": 3840, "requestedHeight": 2160, "configuredCaptureFPS": 50,
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
        self.assertIn("profile stage · mode single_cam", text)
        self.assertIn("| Delivered to Alfie | 3000 | 50.0 |", text)
        self.assertIn("| Presented downstream | unknown | unknown |", text)
        self.assertIn("**Cadence:** 0 of 12 full windows", text)
        self.assertIn("Nothing outside the expected ranges", text)

    def report_with_source(self, *, profile, configured_fps, below_show_rate, reason,
                           operator_mode="multi_cam", show_fps=50):
        with tempfile.TemporaryDirectory() as tmp:
            folder = write_session(Path(tmp), admitted=round(configured_fps * 5))
            path = next(folder.glob("alfie_session_*.json"))
            manifest = json.loads(path.read_text())
            source = manifest["identity"]["source"]
            source.update(captureProfile=profile, configuredCaptureFPS=configured_fps,
                          belowShowRate=below_show_rate, captureSelectionReason=reason,
                          operatorMode=operator_mode, requestedWidth=1920, requestedHeight=1080,
                          deliveredWidth=1920, deliveredHeight=1080)
            manifest["identity"]["output"].update(showFPS=show_fps, playoutFPS=show_fps)
            path.write_text(json.dumps(manifest))
            session = report.load(report.locate(path))
            original_identity = json.loads(json.dumps(session.manifest["identity"]))
            text = report.build_report(session)
            self.assertEqual(session.manifest["identity"], original_identity)
            return text

    def test_native_stage_source_has_no_fallback_claim(self):
        text = self.report_with_source(profile="stage", configured_fps=50, below_show_rate=False,
                                       reason="preferred format")
        self.assertIn("profile stage · mode multi_cam", text)
        self.assertIn("Requested 1920×1080 at 50.00 fps; delivered 1920×1080\n", text)
        self.assertNotIn("below the show rate", text)
        self.assertNotIn("Webcam fallback", text)
        self.assertNotIn("built-in camera test", text)

    def test_built_in_30_fps_test_is_identified_without_claiming_native_show_cadence(self):
        text = self.report_with_source(profile="stage-built-in-test", configured_fps=30,
                                       below_show_rate=True, reason="explicit built-in camera test fallback")
        self.assertIn("profile stage-built-in-test · mode multi_cam", text)
        self.assertIn("Requested 1920×1080 at 30.00 fps; delivered 1920×1080"
                      " · below the show rate (built-in camera test)", text)
        self.assertIn("Expected rate: 30.00 fps (manifest configured capture rate)", text)
        self.assertIn("| Delivered to Alfie | 1800 | 30.0 |", text)
        self.assertIn("playout clock 50.00 fps", text)
        self.assertIn("| Presented downstream | unknown | unknown |", text)
        self.assertIn("Capture choice: explicit built-in camera test fallback", text)
        self.assertNotIn("Webcam fallback", text)
        self.assertNotIn("qualified", text.lower())
        self.assertNotIn("certified", text.lower())

    def test_webcam_profile_keeps_its_specific_fallback_label(self):
        # Source profile is authoritative; do not infer it from operator mode.
        text = self.report_with_source(profile="webcam", configured_fps=30, below_show_rate=True,
                                       reason="nearest lower rate", operator_mode="single_cam")
        self.assertIn("below the show rate (Webcam fallback)", text)
        self.assertIn("profile webcam · mode single_cam", text)
        self.assertIn("Capture choice: nearest lower rate", text)
        self.assertNotIn("built-in camera test", text)

    def test_unknown_or_stage_fallback_does_not_invent_a_profile_or_mode(self):
        for profile in ("stage", "debug-stage", "future-profile", None):
            with self.subTest(profile=profile):
                text = self.report_with_source(profile=profile, configured_fps=30, below_show_rate=True,
                                               reason="recorded source selection reason", operator_mode="unknown")
                self.assertIn(f"profile {profile or '–'} · mode unknown", text)
                self.assertIn("delivered 1920×1080 · below the show rate\n", text)
                self.assertIn("Capture choice: recorded source selection reason", text)
                self.assertIn("Expected rate: 30.00 fps", text)
                self.assertNotIn("Webcam fallback", text)
                self.assertNotIn("built-in camera test", text)

    def test_60_fps_source_uses_recorded_below_rate_flag_without_rate_or_reason_inference(self):
        text = self.report_with_source(profile="stage-built-in-test", configured_fps=60,
                                       below_show_rate=False, show_fps=60,
                                       reason="original built-in test selection detail")
        self.assertIn("profile stage-built-in-test", text)
        self.assertIn("Requested 1920×1080 at 60.00 fps; delivered 1920×1080\n", text)
        self.assertIn("Expected rate: 60.00 fps", text)
        self.assertIn("Capture choice: original built-in test selection detail", text)
        self.assertNotIn("below the show rate", text)
        self.assertNotIn("Webcam fallback", text)
        self.assertNotIn("(built-in camera test)", text)

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

    def test_uuid_session_token_selects_only_its_own_exact_companions(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            first = "2026-09-28_120000_00000000-0000-0000-0000-000000000001"
            second = "2026-09-28_120000_00000000-0000-0000-0000-000000000002"
            write_session(folder, admitted=250, stamp=first)
            write_session(folder, admitted=100, stamp=second)
            (folder / f"alfie_memory_{first}.csv").write_text("elapsed_s,heap_blocks\n5,100\n")
            (folder / f"alfie_memory_{second}.csv").write_text("elapsed_s,heap_blocks\n5,999\n")
            for kind, extension in (("soak", "csv"), ("memory", "csv"), ("session", "json")):
                with self.subTest(kind=kind):
                    selected = report.load(report.locate(folder / f"alfie_{kind}_{first}.{extension}"))
                    self.assertEqual(selected.stamp, first)
                    self.assertEqual(selected.soak_path.name, f"alfie_soak_{first}.csv")
                    self.assertEqual(selected.memory_path.name, f"alfie_memory_{first}.csv")
                    self.assertEqual(selected.manifest_path.name, f"alfie_session_{first}.json")
                    self.assertEqual(selected.memory[0]["heap_blocks"], "100")
                    self.assertIn("| Delivered to Alfie | 3000 |", report.build_report(selected))
            with self.assertRaisesRegex(SystemExit, "select an explicit"):
                report.locate(folder)

    def test_mixed_legacy_and_uuid_names_keep_the_same_local_time_chronology(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            legacy = "2026-10-21_105959"
            newer = "2026-10-21_110000_00000000-0000-0000-0000-000000000001"
            write_session(folder, admitted=100, stamp=legacy)
            write_session(folder, admitted=250, stamp=newer)
            selected = report.load(report.locate(folder))
            self.assertEqual(selected.stamp, newer)
            self.assertIn("| Delivered to Alfie | 3000 |", report.build_report(selected))
            # A later legacy session remains selectable in a mixed archive too.
            latest = "2026-10-21_110001"
            write_session(folder, admitted=200, stamp=latest)
            self.assertEqual(report.locate(folder).stamp, latest)

    def test_folder_can_choose_a_unique_new_token_without_matching_filename_prefixes(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            write_session(folder)
            newest = "2026-09-29_120000_00000000-0000-0000-0000-000000000001"
            write_session(folder, stamp=newest)
            (folder / "backup_alfie_soak_2099-01-01_000000.csv").write_text("ignored")
            (folder / "alfie_soak_2099-01-01_000000.csv.bak").write_text("ignored")
            (folder / "alfie_session_2099-01-01_000000.csv").write_text("ignored")
            self.assertEqual(report.locate(folder).stamp, newest)

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
