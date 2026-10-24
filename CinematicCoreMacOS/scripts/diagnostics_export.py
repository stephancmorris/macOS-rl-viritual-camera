#!/usr/bin/env python3
"""Explicit local export of allowlisted Alfie diagnostic metrics.

Usage: diagnostics_export.py alfie_soak_<stamp>.csv --out /separate/folder/metrics.json
       [--memory alfie_memory_<same-stamp>.csv]

Only the selected CSV files are read. No manifest, text log, recording, directory
scan, upload, or source-file cleanup is performed. Relative elapsed seconds are
retained; source identity, wall clocks, notes and picture/person geometry are
omitted. This projection is not anonymous and does not qualify a rig or release.
The detailed diagnostics_report.py evidence report remains a separate tool.
"""

from __future__ import annotations

import argparse
import csv
from decimal import Decimal, InvalidOperation
import json
import math
import os
import re
import sys
from pathlib import Path


class ExportError(ValueError):
    """A controlled error that never quotes input contents or filesystem paths."""


# These are literal reviewed names, never names learned from a file/manifest.
# Picture geometry and person counts are deliberately outside this projection.
THROUGHPUT_NUMBERS = frozenset("""
elapsed_s cpu_cores cpu_pct threads footprint_mb hop_mean_ms hop_max_ms
queue_mean_ms queue_max_ms vision_mean_ms vision_max_ms frame_wall_mean_ms
frame_wall_max_ms detections frames_window frames_total handoff_refused_window
handoff_refused_total gate_drops_window gate_drops_total main_active_mean_ms
main_active_max_ms observation_age_mean_ms observation_age_max_ms
processed_input_fps detector_fps handoff_fps window_s delivered_window
admitted_window capture_dropped_window capture_dropped_total render_failed_window
render_failed_total routed_window no_route_window repeated_window repeated_total
diag_emit_ms
""".split())
THROUGHPUT_ALIASES = {
    "frame_mean_ms": "frame_wall_mean_ms",
    "frame_max_ms": "frame_wall_max_ms",
    # Old combined losses cannot become a specific pipeline-stage counter.
    "out_drops_window": "legacy_mixed_drops_window",
    "out_drops_total": "legacy_mixed_drops_total",
}
MEMORY_NUMBERS = frozenset("""
elapsed_s footprint_mb internal_mb compressed_mb external_mb heap_mb heap_blocks
frames_total
""".split())
MEMORY_ALIASES = {
    "latency_samples": "latency_sample_count",
    "drop_timestamps": "drop_sample_count",
    "input_timestamps": "input_sample_count",
}
ENUMS = {
    "window_kind": frozenset({"full", "partial", "marker"}),
    "thermal": frozenset({"nominal", "fair", "serious", "critical", "unknown"}),
    "low_power": frozenset({"yes", "no"}),
}


# Legacy stamps remain readable. New files add the complete UUID token so
# same-second sessions cannot be paired by their wall-clock prefix alone.
SESSION_TOKEN = (r"\d{4}-\d{2}-\d{2}_\d{6}"
                 r"(?:_[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})?")


def _selected_file(path: Path, kind: str) -> tuple[Path, str]:
    match = re.fullmatch(r"alfie_" + kind + "_(" + SESSION_TOKEN + r")\.csv", path.name)
    if not match or path.is_symlink() or not path.is_file():
        raise ExportError("Select a regular Alfie diagnostics CSV of the requested kind.")
    return path.resolve(), match.group(1)


def _number(raw: str, *, integer: bool = False) -> float | int | None:
    if raw in {"", "unknown"}:
        return None
    try:
        exact = Decimal(raw)
    except InvalidOperation:
        raise ExportError("An allowlisted metric is not numeric.") from None
    if not exact.is_finite() or exact < 0:
        raise ExportError("Allowlisted metrics must be finite and nonnegative.")
    if integer:
        # Count domains come from the app's integer counters. Parsing through
        # Double would lose low bits above 2**53 and can hide fractional counts.
        if exact != exact.to_integral_value() or exact > 2**64 - 1:
            raise ExportError("A diagnostic counter must be an unsigned 64-bit whole number.")
        return int(exact)
    value = float(exact)
    if not math.isfinite(value) or (value == 0 and exact != 0):
        raise ExportError("A diagnostic measurement is outside the finite numeric range.")
    return int(value) if value.is_integer() else value


def _project_csv(path: Path, *, memory: bool) -> tuple[list[dict], str]:
    numbers = MEMORY_NUMBERS if memory else THROUGHPUT_NUMBERS
    aliases = MEMORY_ALIASES if memory else THROUGHPUT_ALIASES
    enums = {} if memory else ENUMS
    try:
        with path.open(encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle, strict=True)
            header = reader.fieldnames or []
            if len(header) != len(set(header)) or "elapsed_s" not in header:
                raise ExportError("Diagnostics CSV headers are missing or ambiguous.")
            numeric_names = (numbers | aliases.keys()) & set(header)
            if not numeric_names - {"elapsed_s"}:
                raise ExportError("No reviewed diagnostic measurements were found.")
            # Two input columns must never overwrite one canonical output field.
            targets = [aliases.get(name, name) for name in header if name in numeric_names]
            if len(targets) != len(set(targets)):
                raise ExportError("Diagnostics CSV metric aliases are ambiguous.")
            rows = []
            for row in reader:
                if None in row or any(value is None for value in row.values()):
                    raise ExportError("A diagnostics CSV row has the wrong number of fields.")
                projected = {}
                for name in sorted(numeric_names):
                    is_counter = name.endswith(("_window", "_total")) or name in {
                        "threads", "detections", "heap_blocks", "latency_samples",
                        "drop_timestamps", "input_timestamps",
                    }
                    value = _number(row[name], integer=is_counter)
                    if value is not None:
                        projected[aliases.get(name, name)] = value
                if "elapsed_s" not in projected:
                    raise ExportError("Each exported row needs relative elapsed seconds.")
                for name, allowed in enums.items():
                    value = row.get(name, "")
                    if value:
                        if value not in allowed:
                            raise ExportError("A diagnostic state is outside the reviewed enum.")
                        projected[name] = value
                rows.append(projected)
    except (OSError, UnicodeError, csv.Error):
        raise ExportError("The selected diagnostics CSV could not be read.") from None
    if not rows:
        raise ExportError("The selected diagnostics CSV has no rows.")
    layout = "splitStages" if "delivered_window" in header else (
        "legacyMixedDrops" if "out_drops_window" in header else "unspecified")
    return rows, layout


def export_metrics(soak: Path, destination: Path, memory: Path | None = None) -> dict:
    """Project explicit inputs into a new JSON file outside their directories.

    Validation finishes before destination creation. Existing files/symlinks are
    refused; no input or sidecar is written, renamed, deleted or copied wholesale.
    """
    soak, stamp = _selected_file(Path(soak), "soak")
    selected = [soak]
    if memory is not None:
        memory, memory_stamp = _selected_file(Path(memory), "memory")
        if stamp != memory_stamp:
            raise ExportError("Selected throughput and memory files must belong to the same session.")
        selected.append(memory)
    destination = Path(destination)
    resolved_destination = destination.resolve()
    if not destination.parent.is_dir() or any(
        resolved_destination.is_relative_to(source.parent) for source in selected
    ):
        raise ExportError("Choose an existing output folder outside the selected input folders.")
    if destination.exists() or destination.is_symlink():
        raise ExportError("The export destination must be a new file.")

    throughput, layout = _project_csv(soak, memory=False)
    memory_rows = _project_csv(memory, memory=True)[0] if memory is not None else []
    result = {
        "exportSchemaVersion": 1,
        "kind": "alfieDiagnosticMetrics",
        "sourceLayout": layout,
        "throughput": throughput,
        "memory": memory_rows,
        "presentedFPS": "unknown",
        "limitations": [
            "Host measurements do not establish downstream presentation or qualification.",
            "Identity, wall clocks, notes, picture geometry and unreviewed fields are omitted.",
            "Numeric workload patterns may still identify a session; review before sharing.",
        ],
    }
    payload = json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + "\n"
    try:
        descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except OSError:
        raise ExportError("A new export file could not be created.") from None
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(payload)
    except OSError:
        destination.unlink(missing_ok=True)
        raise ExportError("The new export file could not be completed.") from None
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("soak", type=Path, help="explicit alfie_soak_<stamp>.csv")
    parser.add_argument("--memory", type=Path, help="optional explicit matching memory CSV")
    parser.add_argument("--out", type=Path, required=True, help="new JSON file in a separate existing folder")
    args = parser.parse_args(argv)
    try:
        export_metrics(args.soak, args.out, args.memory)
    except (ExportError, OSError, RuntimeError, ValueError):
        # Neither exception details nor argument paths belong in shareable output.
        print("Diagnostics export refused. Check the selected CSV schema and choose a new file in a separate folder.", file=sys.stderr)
        return 2
    print("Created a local metrics projection. Review it before sharing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
