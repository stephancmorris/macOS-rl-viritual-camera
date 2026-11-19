#!/usr/bin/env python3
"""Offline face-verification scorer for the subject lock.

Scores a labelled set of face crops with one or more identity methods and
reports, per face-height bin, the true-accept rate at the distance threshold
that keeps false accepts at or below a target rate (0.1% per decision by
default). The result decides the thresholds in `IdentityThresholds` and
whether a face-recognition model (SFace) earns a place behind the app's
`IdentityEmbedder` seam.

Methods:
  * Vision feature print (the app's current signature): distances come from
    `scripts/face_verification/feature_print_distances.swift`, which runs the
    same pinned Vision request on the same padded crop as the app.
  * SFace (OpenCV Zoo, Apache-2.0): embeddings computed here with OpenCV's
    DNN module from a locally downloaded ONNX file. The model is not
    committed; see FACE_VERIFICATION_EVAL.md.

The labelled footage is owner-supplied under the owner's consent and
retention terms. Nothing here downloads, uploads or commits media.

Manifest (CSV with a header row), one row per face:
  image       path to the full frame, relative to the manifest
  identity    stable label for the person
  clip        label for the clip or session the frame came from
  face_x, face_y, face_w, face_h
              normalised face box, Vision convention (origin bottom-left)
  face_height_px (optional)
              face height in source pixels; computed from the image when absent
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Sequence

DEFAULT_FALSE_ACCEPT_RATE = 0.001
HEIGHT_BINS: tuple[tuple[str, float, float], ...] = (
    ('<48', 0.0, 48.0),
    ('48-64', 48.0, 64.0),
    ('64-96', 64.0, 96.0),
    ('>=96', 96.0, math.inf),
)
# The app's crop pads the face box by 15% on every side (FaceSignatureExtractor).
APP_CROP_PADDING = 0.15


@dataclass(frozen=True)
class Face:
    image: str
    identity: str
    clip: str
    box: tuple[float, float, float, float]
    face_height_px: float | None = None


@dataclass(frozen=True)
class Pair:
    first: int
    second: int
    distance: float
    genuine: bool
    face_height_px: float


@dataclass(frozen=True)
class BinResult:
    label: str
    genuine_pairs: int
    impostor_pairs: int
    true_accept_rate: float | None
    false_accept_rate: float | None


@dataclass(frozen=True)
class MethodResult:
    method: str
    threshold: float | None
    false_accept_target: float
    genuine_pairs: int
    impostor_pairs: int
    true_accept_rate: float | None
    false_accept_rate: float | None
    bins: tuple[BinResult, ...]
    warnings: tuple[str, ...]


class ManifestError(ValueError):
    pass


def load_manifest(path: Path) -> list[Face]:
    required = {'image', 'identity', 'clip', 'face_x', 'face_y', 'face_w', 'face_h'}
    with path.open(newline='') as handle:
        reader = csv.DictReader(handle)
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ManifestError(f'manifest is missing columns: {", ".join(sorted(missing))}')
        faces = []
        for line, row in enumerate(reader, start=2):
            try:
                box = tuple(float(row[key]) for key in ('face_x', 'face_y', 'face_w', 'face_h'))
            except ValueError as error:
                raise ManifestError(f'line {line}: face box is not numeric') from error
            if box[2] <= 0 or box[3] <= 0:
                raise ManifestError(f'line {line}: face box has no area')
            height = row.get('face_height_px') or None
            faces.append(Face(image=row['image'], identity=row['identity'], clip=row['clip'],
                              box=box, face_height_px=float(height) if height else None))
    if len({face.identity for face in faces}) < 2:
        raise ManifestError('need at least two identities to measure false accepts')
    return faces


def pairs_from_distances(faces: Sequence[Face], distance: Callable[[int, int], float | None]) -> list[Pair]:
    """Every unordered pair of faces from different frames. Pairs a method
    cannot compare are skipped."""
    pairs = []
    for i in range(len(faces)):
        for j in range(i + 1, len(faces)):
            if faces[i].image == faces[j].image:
                continue
            d = distance(i, j)
            if d is None or not math.isfinite(d):
                continue
            heights = [h for h in (faces[i].face_height_px, faces[j].face_height_px) if h is not None]
            pairs.append(Pair(i, j, d, faces[i].identity == faces[j].identity,
                              min(heights) if heights else 0.0))
    return pairs


def threshold_for(impostor_distances: Iterable[float], false_accept_rate: float) -> float | None:
    """The largest threshold t such that at most `false_accept_rate` of
    impostor pairs have distance < t (a pair is accepted when distance < t)."""
    ordered = sorted(impostor_distances)
    if not ordered:
        return None
    allowed = math.floor(false_accept_rate * len(ordered))
    # Accepting the `allowed` closest impostors: the threshold sits at the next one.
    return ordered[allowed]


def _rate(accepted: int, total: int) -> float | None:
    return accepted / total if total else None


def evaluate(method: str, pairs: Sequence[Pair], false_accept_rate: float = DEFAULT_FALSE_ACCEPT_RATE) -> MethodResult:
    impostors = [p.distance for p in pairs if not p.genuine]
    genuine = [p for p in pairs if p.genuine]
    threshold = threshold_for(impostors, false_accept_rate)
    warnings = []
    if len(impostors) < math.ceil(1 / false_accept_rate):
        warnings.append(f'only {len(impostors)} impostor pairs: a {false_accept_rate:.1%} false-accept '
                        f'rate needs at least {math.ceil(1 / false_accept_rate)} to be measurable')
    if not genuine:
        warnings.append('no genuine pairs')

    def accepted(subset: Sequence[Pair]) -> int:
        return sum(1 for p in subset if threshold is not None and p.distance < threshold)

    bins = []
    for label, low, high in HEIGHT_BINS:
        in_bin = [p for p in pairs if low <= p.face_height_px < high]
        g = [p for p in in_bin if p.genuine]
        i = [p for p in in_bin if not p.genuine]
        bins.append(BinResult(label, len(g), len(i), _rate(accepted(g), len(g)), _rate(accepted(i), len(i))))
    impostor_pairs = [p for p in pairs if not p.genuine]
    return MethodResult(method=method, threshold=threshold, false_accept_target=false_accept_rate,
                        genuine_pairs=len(genuine), impostor_pairs=len(impostor_pairs),
                        true_accept_rate=_rate(accepted(genuine), len(genuine)),
                        false_accept_rate=_rate(accepted(impostor_pairs), len(impostor_pairs)),
                        bins=tuple(bins), warnings=tuple(warnings))


def load_feature_print_distances(path: Path, faces: Sequence[Face]) -> dict[tuple[int, int], float]:
    """Read the Swift tool's output: {"count": n, "faceHeights": [...], "pairs": [[i, j, d], ...]}."""
    data = json.loads(path.read_text())
    if data.get('count') != len(faces):
        raise ManifestError(f'{path} scored {data.get("count")} faces; the manifest has {len(faces)}')
    distances = {}
    for i, j, d in data['pairs']:
        distances[(min(i, j), max(i, j))] = float(d)
    return distances


def with_measured_heights(faces: Sequence[Face], heights: Sequence[float | None]) -> list[Face]:
    return [face if face.face_height_px is not None or height is None
            else Face(face.image, face.identity, face.clip, face.box, float(height))
            for face, height in zip(faces, heights)]


def cosine_distance(a: Sequence[float], b: Sequence[float]) -> float | None:
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(x * x for x in b))
    if na == 0 or nb == 0:
        return None
    return 1.0 - sum(x * y for x, y in zip(a, b)) / (na * nb)


def sface_embeddings(faces: Sequence[Face], root: Path, model: Path) -> tuple[list[list[float] | None], list[float | None]]:
    """SFace embeddings for tight face crops resized to 112x112.

    The app does not align faces; neither does this, so the comparison is
    like for like. Returns embeddings and measured face heights."""
    import cv2  # Imported here so the pure scoring code needs no OpenCV.

    net = cv2.dnn.readNetFromONNX(str(model))
    embeddings: list[list[float] | None] = []
    heights: list[float | None] = []
    for face in faces:
        image = cv2.imread(str(root / face.image))
        if image is None:
            embeddings.append(None)
            heights.append(None)
            continue
        height, width = image.shape[:2]
        x, y, w, h = face.box
        top = int(round((1.0 - y - h) * height))
        left = int(round(x * width))
        crop = image[max(top, 0):max(top, 0) + int(round(h * height)),
                     max(left, 0):max(left, 0) + int(round(w * width))]
        heights.append(h * height)
        if crop.size == 0:
            embeddings.append(None)
            continue
        blob = cv2.dnn.blobFromImage(cv2.resize(crop, (112, 112)), 1.0, (112, 112), (0, 0, 0), swapRB=True)
        net.setInput(blob)
        embeddings.append([float(v) for v in net.forward().flatten()])
    return embeddings, heights


def format_report(results: Sequence[MethodResult]) -> str:
    def pct(value: float | None) -> str:
        return '–' if value is None else f'{value:.1%}'

    lines = ['# Face verification evaluation', '']
    for result in results:
        threshold = '–' if result.threshold is None else f'{result.threshold:.4f}'
        lines += [f'## {result.method}', '',
                  f'Threshold at ≤{result.false_accept_target:.1%} false accepts: **{threshold}**. '
                  f'True accepts {pct(result.true_accept_rate)} of {result.genuine_pairs} genuine pairs; '
                  f'false accepts {pct(result.false_accept_rate)} of {result.impostor_pairs} impostor pairs.', '',
                  '| Face height (px, smaller of the pair) | Genuine pairs | True accepts | Impostor pairs | False accepts |',
                  '| --- | --- | --- | --- | --- |']
        for b in result.bins:
            lines.append(f'| {b.label} | {b.genuine_pairs} | {pct(b.true_accept_rate)} | '
                         f'{b.impostor_pairs} | {pct(b.false_accept_rate)} |')
        lines += [''] + [f'- Warning: {w}' for w in result.warnings] + ([''] if result.warnings else [])
    return '\n'.join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--feature-print-distances', type=Path,
                        help='JSON from scripts/face_verification/feature_print_distances.swift')
    parser.add_argument('--sface-model', type=Path, help='local face_recognition_sface_2021dec.onnx')
    parser.add_argument('--false-accept-rate', type=float, default=DEFAULT_FALSE_ACCEPT_RATE)
    parser.add_argument('--json', type=Path, help='also write results as JSON')
    args = parser.parse_args(argv)

    faces = load_manifest(args.manifest)
    root = args.manifest.parent
    results = []
    if args.feature_print_distances:
        distances = load_feature_print_distances(args.feature_print_distances, faces)
        if any(face.face_height_px is None for face in faces):
            data = json.loads(args.feature_print_distances.read_text())
            faces = with_measured_heights(faces, data.get('faceHeights', [None] * len(faces)))
        results.append(evaluate('Vision feature print (Revision2)',
                                pairs_from_distances(faces, lambda i, j: distances.get((i, j))),
                                args.false_accept_rate))
    if args.sface_model:
        embeddings, heights = sface_embeddings(faces, root, args.sface_model)
        faces = with_measured_heights(faces, heights)
        results.append(evaluate('SFace (cosine distance)', pairs_from_distances(
            faces, lambda i, j: None if embeddings[i] is None or embeddings[j] is None
            else cosine_distance(embeddings[i], embeddings[j])), args.false_accept_rate))
    if not results:
        parser.error('give --feature-print-distances and/or --sface-model')
    print(format_report(results))
    if args.json:
        args.json.write_text(json.dumps([{
            **{k: v for k, v in r.__dict__.items() if k != 'bins'},
            'bins': [b.__dict__ for b in r.bins],
        } for r in results], indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
