#!/usr/bin/env python3
"""Synthetic checks for the offline face-verification scorer. No footage,
model or OpenCV needed."""
import contextlib
import io
import json
import math
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import face_verification_eval as fve


def face(identity, image, height=80.0, clip='a'):
    return fve.Face(image=image, identity=identity, clip=clip, box=(0.4, 0.5, 0.05, 0.08), face_height_px=height)


class ThresholdTests(unittest.TestCase):
    def test_threshold_keeps_false_accepts_at_or_under_target(self):
        impostors = [i / 1000 for i in range(1, 2001)]
        threshold = fve.threshold_for(impostors, 0.001)
        accepted = sum(1 for d in impostors if d < threshold)
        self.assertLessEqual(accepted / len(impostors), 0.001)
        self.assertEqual(accepted, 2)

    def test_too_few_impostors_accept_none_and_warn(self):
        pairs = [fve.Pair(0, 1, 0.2, True, 80), fve.Pair(0, 2, 0.9, False, 80)]
        result = fve.evaluate('m', pairs)
        self.assertEqual(result.false_accept_rate, 0.0)
        self.assertTrue(any('impostor pairs' in w for w in result.warnings))

    def test_no_impostors_gives_no_threshold(self):
        self.assertIsNone(fve.threshold_for([], 0.001))


class PairTests(unittest.TestCase):
    def test_pairs_skip_the_same_frame_and_label_genuine(self):
        faces = [face('ann', 'f1.png'), face('bob', 'f1.png'), face('ann', 'f2.png', height=40)]
        pairs = fve.pairs_from_distances(faces, lambda i, j: 0.5)
        self.assertEqual([(p.first, p.second, p.genuine) for p in pairs], [(0, 2, True), (1, 2, False)])
        self.assertEqual(pairs[0].face_height_px, 40)

    def test_uncomparable_pairs_are_skipped(self):
        faces = [face('ann', 'f1.png'), face('bob', 'f2.png')]
        self.assertEqual(fve.pairs_from_distances(faces, lambda i, j: None), [])
        self.assertEqual(fve.pairs_from_distances(faces, lambda i, j: math.nan), [])


class EvaluationTests(unittest.TestCase):
    def synthetic(self):
        # Two well-separated identities with large faces; one small, ambiguous genuine pair.
        pairs = [fve.Pair(i, i + 1, 0.1, True, 100) for i in range(50)]
        pairs += [fve.Pair(i, i + 1, 0.95, True, 40) for i in range(10)]
        pairs += [fve.Pair(i, i + 1, 0.9 + (i % 100) / 1000, False, 100) for i in range(1000)]
        return pairs

    def test_rates_and_bins(self):
        result = fve.evaluate('synthetic', self.synthetic())
        self.assertEqual(result.impostor_pairs, 1000)
        self.assertLessEqual(result.false_accept_rate, 0.001)
        bins = {b.label: b for b in result.bins}
        self.assertEqual(bins['>=96'].true_accept_rate, 1.0)
        self.assertEqual(bins['<48'].true_accept_rate, 0.0)
        self.assertEqual(result.warnings, ())

    def test_report_names_the_threshold(self):
        report = fve.format_report([fve.evaluate('synthetic', self.synthetic())])
        self.assertIn('## synthetic', report)
        self.assertIn('| 64-96 |', report)

    def test_cosine_distance(self):
        self.assertAlmostEqual(fve.cosine_distance([1, 0], [1, 0]), 0.0)
        self.assertAlmostEqual(fve.cosine_distance([1, 0], [0, 1]), 1.0)
        self.assertIsNone(fve.cosine_distance([0, 0], [1, 0]))


class ManifestTests(unittest.TestCase):
    def write(self, folder, text, name='manifest.csv'):
        path = Path(folder) / name
        path.write_text(text)
        return path

    def test_manifest_requires_columns_and_two_identities(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(fve.ManifestError):
                fve.load_manifest(self.write(folder, 'image,identity\nf.png,ann\n'))
            one = 'image,identity,clip,face_x,face_y,face_w,face_h\nf.png,ann,a,0.1,0.1,0.1,0.1\n'
            with self.assertRaises(fve.ManifestError):
                fve.load_manifest(self.write(folder, one))

    def test_end_to_end_with_feature_print_distances(self):
        rows = ['image,identity,clip,face_x,face_y,face_w,face_h']
        rows += [f'f{i}.png,{"ann" if i % 2 else "bob"},a,0.4,0.5,0.05,0.08' for i in range(6)]
        with tempfile.TemporaryDirectory() as folder:
            manifest = self.write(folder, '\n'.join(rows) + '\n')
            pairs = [[i, j, 0.2 if i % 2 == j % 2 else 0.9] for i in range(6) for j in range(i + 1, 6)]
            distances = Path(folder) / 'd.json'
            distances.write_text(json.dumps({'count': 6, 'faceHeights': [70.0] * 6, 'pairs': pairs}))
            out = Path(folder) / 'r.json'
            with contextlib.redirect_stdout(io.StringIO()) as printed:
                code = fve.main([str(manifest), '--feature-print-distances', str(distances), '--json', str(out)])
            self.assertEqual(code, 0)
            self.assertIn('Vision feature print', printed.getvalue())
            result = json.loads(out.read_text())[0]
            self.assertEqual(result['genuine_pairs'], 6)
            self.assertEqual(result['impostor_pairs'], 9)
            self.assertEqual({b['label']: b['genuine_pairs'] for b in result['bins']}['64-96'], 6)

    def test_distance_count_must_match_manifest(self):
        rows = 'image,identity,clip,face_x,face_y,face_w,face_h\nf0.png,ann,a,0.4,0.5,0.05,0.08\nf1.png,bob,a,0.4,0.5,0.05,0.08\n'
        with tempfile.TemporaryDirectory() as folder:
            manifest = self.write(folder, rows)
            distances = Path(folder) / 'd.json'
            distances.write_text(json.dumps({'count': 3, 'pairs': []}))
            with self.assertRaises(fve.ManifestError):
                fve.load_feature_print_distances(distances, fve.load_manifest(manifest))


if __name__ == '__main__':
    unittest.main()
