#!/usr/bin/env python3
"""Summarise one Alfie diagnostics session as Markdown evidence.

Reads the files Alfie writes per capture session (sandbox container:
~/Library/Containers/Morris.CinematicCoreMacOS/Data/Documents/CinematicCore/Diagnostics):

    alfie_session_<stamp>.json   manifest: build, source, route, column definitions (schema 2+)
    alfie_soak_<stamp>.csv       one row per ~5 s window
    alfie_memory_<stamp>.csv     memory breakdown, same windows

Older sessions (before the METRICS change) have no manifest and one mixed
`out_drops` column; they are still summarised, with that limitation stated.

The report states observations and measured numbers only. It never infers a
presented or downstream frame rate from host handoffs, and it does not pass or
fail a run: SOAK / PAN-HITCH / DISPLAY-QA reports make that call with their
own frozen budgets.

Usage:
    diagnostics_report.py <session .csv | .json | diagnostics folder> [--out report.md]
                          [--expected-fps 50] [--cadence-floor 0.97]
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import statistics
import sys
from dataclasses import dataclass, field
from pathlib import Path

SOAK_WINDOW_S = 5.0

# Column aliases across schema versions: canonical name -> accepted names.
ALIASES = {
    "frame_wall_mean_ms": ["frame_wall_mean_ms", "frame_mean_ms"],
    "frame_wall_max_ms": ["frame_wall_max_ms", "frame_max_ms"],
}


@dataclass
class Session:
    stamp: str
    soak_path: Path | None = None
    memory_path: Path | None = None
    manifest_path: Path | None = None
    manifest: dict | None = None
    rows: list[dict] = field(default_factory=list)      # measured windows
    markers: list[dict] = field(default_factory=list)   # marker rows
    memory: list[dict] = field(default_factory=list)
    columns: list[str] = field(default_factory=list)

    @property
    def schema(self) -> int:
        if self.manifest:
            return int(self.manifest.get("schemaVersion", 2))
        return 1


# ---------------------------------------------------------------- loading

STAMP = re.compile(r"alfie_(?:soak|memory|session)_(\d{4}-\d{2}-\d{2}_\d{6})")


def locate(target: Path) -> Session:
    """Find the session files for a CSV, manifest or folder (newest session)."""
    if target.is_dir():
        stamps = sorted({m.group(1) for p in target.iterdir() if (m := STAMP.search(p.name))})
        if not stamps:
            raise SystemExit(f"No Alfie diagnostics files in {target}")
        folder, stamp = target, stamps[-1]
    else:
        match = STAMP.search(target.name)
        if not match:
            raise SystemExit(f"Not an Alfie diagnostics file: {target}")
        folder, stamp = target.parent, match.group(1)

    session = Session(stamp=stamp)
    for kind, attr in (("soak", "soak_path"), ("memory", "memory_path")):
        path = folder / f"alfie_{kind}_{stamp}.csv"
        if path.exists():
            setattr(session, attr, path)
    manifest = folder / f"alfie_session_{stamp}.json"
    if manifest.exists():
        session.manifest_path = manifest
        session.manifest = json.loads(manifest.read_text())
    if session.soak_path is None:
        raise SystemExit(f"No soak CSV for session {stamp} in {folder}")
    return session


def _num(value: str | None) -> float | None:
    if value is None or value == "" or value == "unknown":
        return None
    try:
        return float(value)
    except ValueError:
        return None


def load(session: Session) -> Session:
    with session.soak_path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        session.columns = reader.fieldnames or []
        for row in reader:
            kind = row.get("window_kind")
            is_marker = kind == "marker" if kind else _num(row.get("window_s") or row.get("frames_window")) is None
            (session.markers if is_marker else session.rows).append(row)
    if session.memory_path:
        with session.memory_path.open(newline="") as handle:
            session.memory = list(csv.DictReader(handle))
    return session


def col(row: dict, name: str) -> float | None:
    for alias in ALIASES.get(name, [name]):
        if alias in row:
            return _num(row[alias])
    return None


def series(rows: list[dict], name: str) -> list[float]:
    return [v for r in rows if (v := col(r, name)) is not None]


# ---------------------------------------------------------------- analysis

def window_seconds(row: dict, previous_elapsed: float | None) -> float | None:
    explicit = col(row, "window_s")
    if explicit:
        return explicit
    elapsed = col(row, "elapsed_s")
    if elapsed is not None and previous_elapsed is not None and elapsed > previous_elapsed:
        return elapsed - previous_elapsed
    return None


def per_window_rates(rows: list[dict], count_column: str) -> list[tuple[float, float]]:
    """(elapsed_s, frames per second) for each window with a known length."""
    out, previous = [], None
    for row in rows:
        seconds = window_seconds(row, previous)
        previous = col(row, "elapsed_s")
        count = col(row, count_column)
        if seconds and count is not None and row.get("window_kind", "full") != "partial":
            out.append((previous or 0.0, count / seconds))
    return out


def slope_per_minute(points: list[tuple[float, float]]) -> float | None:
    """Least-squares slope of value over elapsed seconds, per minute."""
    if len(points) < 3:
        return None
    xs, ys = zip(*points)
    mean_x, mean_y = statistics.fmean(xs), statistics.fmean(ys)
    denom = sum((x - mean_x) ** 2 for x in xs)
    if denom == 0:
        return None
    return sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / denom * 60


def thirds_growth(values: list[float]) -> float | None:
    """Mean of the last third ÷ mean of the first third (None if too short)."""
    if len(values) < 6:
        return None
    third = len(values) // 3
    first, last = statistics.fmean(values[:third]), statistics.fmean(values[-third:])
    return last / first if first > 0 else None


def expected_fps(session: Session, override: float | None) -> tuple[float | None, str]:
    if override:
        return override, "--expected-fps"
    if session.manifest:
        source = session.manifest.get("identity", {}).get("source", {})
        if source.get("configuredCaptureFPS"):
            return float(source["configuredCaptureFPS"]), "manifest configured capture rate"
        show = session.manifest.get("identity", {}).get("output", {}).get("showFPS")
        if show:
            return float(show), "manifest show standard"
    for marker in session.markers:
        match = re.search(r"show_fps=([\d.]+)", marker.get("note", ""))
        if match:
            return float(match.group(1)), "show_fps in the session start note"
    return None, "unknown"


# ---------------------------------------------------------------- report

def fmt(value: float | None, digits: int = 1, unit: str = "") -> str:
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return "–"
    return f"{value:.{digits}f}{unit}"


def mmss(seconds: float | None) -> str:
    if seconds is None:
        return "–"
    return f"{int(seconds // 60)}:{int(seconds % 60):02d}"


def build_report(session: Session, expected_override: float | None = None, cadence_floor: float = 0.97) -> str:
    rows, lines, findings = session.rows, [], []
    total_elapsed = max(series(rows + session.markers, "elapsed_s") or [0.0])
    partial = [r for r in rows if r.get("window_kind") == "partial"]
    target, target_source = expected_fps(session, expected_override)

    lines.append(f"# Diagnostics session {session.stamp}")
    lines.append("")
    lines.append(f"- Files: `{session.soak_path.name}`"
                 + (f", `{session.memory_path.name}`" if session.memory_path else "")
                 + (f", `{session.manifest_path.name}`" if session.manifest_path else ""))
    if session.schema >= 2:
        lines.append(f"- Schema {session.schema}: every column has a stage, unit, window and provenance in the manifest.")
    else:
        lines.append("- Schema 1 (before METRICS): no manifest, so build/source identity comes only from the start note; "
                     "`out_drops` mixes capture, render and route losses; HOLD repeats count as sent frames.")
    lines.append(f"- Duration {mmss(total_elapsed)} ({fmt(total_elapsed, 0)} s), {len(rows)} measured windows"
                 f" ({len(partial)} partial), {len(session.markers)} marker rows.")
    lines.append(f"- Expected rate: {fmt(target, 2)} fps ({target_source}).")
    lines.append("")

    # Identity
    lines.append("## Identity")
    lines.append("")
    if session.manifest:
        identity = session.manifest.get("identity", {})
        build, source, output = identity.get("build", {}), identity.get("source", {}), identity.get("output", {})
        lines += [
            f"- Build: {build.get('appVersion', '?')} ({build.get('buildNumber', '?')}), "
            f"source fingerprint `{build.get('sourceFingerprint', 'unrecorded')}`",
            f"- Host: {build.get('machineModel', '?')}, {build.get('osVersion', '?')}",
            f"- Source: {source.get('inputKind', '?')} · {source.get('deviceName') or '–'}"
            f" · profile {source.get('captureProfile') or '–'}",
            f"- Requested {source.get('requestedWidth', '–')}×{source.get('requestedHeight', '–')} at "
            f"{fmt(source.get('configuredCaptureFPS'), 2)} fps; delivered "
            f"{source.get('deliveredWidth', '–')}×{source.get('deliveredHeight', '–')}"
            + (" · below the show rate (Webcam fallback)" if source.get("belowShowRate") else ""),
            f"- Capture choice: {source.get('captureSelectionReason') or '–'}",
            f"- Output: {output.get('route') or 'no active route'} · show standard {output.get('showStandard', '?')}"
            f" · playout clock {fmt(output.get('playoutFPS'), 2)} fps",
        ]
        closing = session.manifest.get("closing")
        if closing:
            lines.append(f"- Closed {closing.get('endedAt', '?')} ({closing.get('note', '')}); "
                         f"{closing.get('windowsWritten', '?')} windows; partial last window flushed: "
                         f"{'yes' if closing.get('partialWindowFlushed') else 'no'}")
        else:
            lines.append("- No closing record: the session did not reach Stop (crash, force quit or still running).")
            findings.append("The session has no closing record, so it did not end with Stop.")
    else:
        start = next((m.get("note", "") for m in session.markers), "")
        lines.append(f"- Start note: `{start or 'none'}`")
    lines.append("")

    # Stages
    lines.append("## Frames per stage")
    lines.append("")
    lines.append("Rates are per full window (partial windows excluded). *Handoff* means the output route accepted "
                 "the frame; when a display or virtual-camera consumer shows it is not observable, so no presented "
                 "rate is reported or implied.")
    lines.append("")
    lines.append("| Stage | Total | Mean fps | Worst window | At |")
    lines.append("| --- | ---: | ---: | ---: | ---: |")
    stage_specs = [
        ("Delivered to Alfie", "delivered_window", None),
        ("Admitted to the pipeline", "admitted_window", None),
        ("Handoff accepted", "frames_window", "frames_total"),
        ("Repeated (HOLD)", "repeated_window", "repeated_total"),
    ]
    for label, window_col, total_col in stage_specs:
        if window_col not in session.columns:
            continue
        rates = per_window_rates(rows, window_col)
        total = (series(rows, total_col) or [None])[-1] if total_col else sum(series(rows, window_col))
        worst = min(rates, key=lambda p: p[1]) if rates else None
        lines.append(f"| {label} | {fmt(total, 0)} | {fmt(statistics.fmean(r for _, r in rates) if rates else None)} | "
                     f"{fmt(worst[1] if worst else None)} | {mmss(worst[0]) if worst else '–'} |")
    lines.append("| Presented downstream | unknown | unknown | – | – |")
    lines.append("")

    loss_specs = [
        ("Lost before delivery (AVCapture)", "capture_dropped_window"),
        ("Skipped by the processing gate", "gate_drops_window"),
        ("Crop render failed", "render_failed_window"),
        ("Refused by the output route", "handoff_refused_window"),
        ("Produced with no route", "no_route_window"),
        ("Mixed drops (schema 1)", "out_drops_window"),
    ]
    present = [(label, c) for label, c in loss_specs if c in session.columns]
    if present:
        lines.append("| Loss | Total | Windows with any | First at |")
        lines.append("| --- | ---: | ---: | ---: |")
        for label, column in present:
            values = [(col(r, "elapsed_s"), col(r, column) or 0) for r in rows]
            hit = [e for e, v in values if v > 0]
            total = sum(v for _, v in values)
            lines.append(f"| {label} | {fmt(total, 0)} | {len(hit)} | {mmss(hit[0]) if hit else '–'} |")
            if total > 0 and column != "gate_drops_window":
                findings.append(f"{label}: {int(total)} frame(s), first at {mmss(hit[0])}.")
        lines.append("")

    # Cadence against the expected rate
    if target:
        cadence_col = "delivered_window" if "delivered_window" in session.columns else "frames_window"
        rates = per_window_rates(rows, cadence_col)
        short = [(e, r) for e, r in rates if r < target * cadence_floor]
        stage_name = "delivered" if cadence_col == "delivered_window" else "handoff (schema 1: no delivered count)"
        lines.append(f"**Cadence:** {len(short)} of {len(rates)} full windows had {stage_name} below "
                     f"{cadence_floor:.0%} of {fmt(target, 2)} fps"
                     + (f"; first at {mmss(short[0][0])} ({fmt(short[0][1])} fps)." if short else "."))
        lines.append("")
        if short:
            findings.append(f"{len(short)} window(s) with {stage_name} below {cadence_floor:.0%} of "
                            f"{fmt(target, 2)} fps, first at {mmss(short[0][0])}.")

    # Stalls
    stalls = [r for r in rows if (w := col(r, "window_s")) and w > SOAK_WINDOW_S * 1.5 and r.get("window_kind") != "partial"]
    if stalls:
        findings.append(f"{len(stalls)} window(s) ran long (> {SOAK_WINDOW_S * 1.5:.1f} s): the pipeline or MainActor stalled.")

    # Timing
    lines.append("## Timing")
    lines.append("")
    lines.append("| Measure | Mean of window means | Max | Last third ÷ first third |")
    lines.append("| --- | ---: | ---: | ---: |")
    for label, mean_col, max_col in [
        ("Capture → MainActor hop (ms)", "hop_mean_ms", "hop_max_ms"),
        ("processFrame wall (ms)", "frame_wall_mean_ms", "frame_wall_max_ms"),
        ("MainActor busy per frame (ms)", "main_active_mean_ms", "main_active_max_ms"),
        ("Vision wall (ms)", "vision_mean_ms", "vision_max_ms"),
        ("Observation age (ms)", "observation_age_mean_ms", "observation_age_max_ms"),
        ("Diagnostics row cost (ms)", "diag_emit_ms", "diag_emit_ms"),
    ]:
        means = [v for v in series(rows, mean_col) if v > 0]
        if not means:
            continue
        growth = thirds_growth(means)
        lines.append(f"| {label} | {fmt(statistics.fmean(means), 2)} | {fmt(max(series(rows, max_col) or [0]), 2)} | "
                     f"{fmt(growth, 2, '×')} |")
        if growth and growth > 1.5 and label != "Diagnostics row cost (ms)":
            findings.append(f"{label} grew {growth:.1f}× from the first to the last third of the session.")
    lines.append("")

    # Memory
    lines.append("## Memory and heat")
    lines.append("")
    footprint = [(e, v) for r in rows if (e := col(r, "elapsed_s")) is not None and (v := col(r, "footprint_mb")) is not None]
    if footprint:
        slope = slope_per_minute(footprint)
        lines.append(f"- Footprint {fmt(footprint[0][1], 0)} → {fmt(footprint[-1][1], 0)} MB; trend {fmt(slope, 1)} MB/min.")
        if slope is not None and slope > 5:
            findings.append(f"Footprint trended up {slope:.1f} MB/min.")
    if session.memory:
        blocks = [(e, v) for r in session.memory if (e := _num(r.get("elapsed_s"))) is not None and (v := _num(r.get("heap_blocks"))) is not None]
        external = [(e, v) for r in session.memory if (e := _num(r.get("elapsed_s"))) is not None and (v := _num(r.get("external_mb"))) is not None]
        if blocks:
            lines.append(f"- Heap blocks {fmt(blocks[0][1], 0)} → {fmt(blocks[-1][1], 0)}; trend {fmt(slope_per_minute(blocks), 0)} blocks/min "
                         "(flat blocks with rising footprint points below the allocator, e.g. image/IOSurface memory).")
        if external:
            lines.append(f"- External (IOSurface-backed) {fmt(external[0][1], 0)} → {fmt(external[-1][1], 0)} MB; "
                         f"trend {fmt(slope_per_minute(external), 1)} MB/min.")
    thermal_changes, last = [], None
    for row in sorted(rows + session.markers, key=lambda r: col(r, "elapsed_s") or 0):
        state = row.get("thermal")
        if state and state != last:
            thermal_changes.append(f"{state} at {mmss(col(row, 'elapsed_s'))}")
            last = state
    lines.append(f"- Thermal: {', '.join(thermal_changes) or 'not recorded'}.")
    if any(s.startswith(("serious", "critical")) for s in thermal_changes):
        findings.append("The Mac reached a serious or critical thermal state.")
    lines.append("")

    # Notes
    notes = [(col(r, "elapsed_s"), r.get("note", "")) for r in sorted(rows + session.markers, key=lambda r: col(r, "elapsed_s") or 0) if r.get("note")]
    if notes:
        lines.append("## Events")
        lines.append("")
        for elapsed, note in notes[:60]:
            lines.append(f"- {mmss(elapsed)} — {note}")
        if len(notes) > 60:
            lines.append(f"- … {len(notes) - 60} more")
        lines.append("")

    # Unobservable
    lines.append("## Not observable from Alfie")
    lines.append("")
    unobservable = (session.manifest or {}).get("unobservable") or [
        "ATEM / downstream switcher acquisition, cadence and tally",
        "physical display scan-out time",
        "end-to-end glass-to-glass latency",
    ]
    for item in unobservable:
        lines.append(f"- {item}")
    lines.append("")

    summary = ["## Observations", ""]
    summary += [f"- {f}" for f in findings] or ["- Nothing outside the expected ranges in this summary. Judge against the card's frozen budgets."]
    summary.append("")
    # Observations go right after the header block.
    header_end = lines.index("## Identity")
    return "\n".join(lines[:header_end] + summary + lines[header_end:]) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--expected-fps", type=float)
    parser.add_argument("--cadence-floor", type=float, default=0.97)
    args = parser.parse_args(argv)
    session = load(locate(args.target))
    report = build_report(session, args.expected_fps, args.cadence_floor)
    if args.out:
        args.out.write_text(report)
    else:
        sys.stdout.write(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
