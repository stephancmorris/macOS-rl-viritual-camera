"""Exercise the real CI guard in disposable repositories, without Xcode/signing."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE_ROOT = Path(__file__).resolve().parents[2]
PROJECT = Path('CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj/project.pbxproj')


class ConsistencyGuardTests(unittest.TestCase):
    def setUp(self):
        self.storage = tempfile.TemporaryDirectory(prefix='alfie-consistency-')
        self.addCleanup(self.storage.cleanup)
        self.root = Path(self.storage.name)
        for name in (
            'scripts/ci/check_consistency.sh',
            'CinematicCoreMacOS/CinematicCoreMacOS/DeveloperFlags.swift',
            'CinematicCoreMacOS/CinematicCoreExtension/Info.plist',
        ):
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SOURCE_ROOT / name, destination)
        self.project = self.root / PROJECT
        self.project.parent.mkdir(parents=True)
        self.project.write_text('ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = NO;\nOTHER_SETTING = YES;\n')
        self.config = self.root / 'App.xcconfig'
        self.config.write_text('ENABLE_USER_SELECTED_FILES = readonly\n')
        self.entitlements = self.root / 'App.entitlements'
        self.entitlements.write_text('<plist><dict/></plist>\n')
        stub_bin = self.root / 'stub-bin'
        stub_bin.mkdir()
        xcodebuild = stub_bin / 'xcodebuild'
        xcodebuild.write_text('#!/bin/bash\nprintf "    MARKETING_VERSION = 1.0\\n    CURRENT_PROJECT_VERSION = 4\\n"\n')
        xcodebuild.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{stub_bin}:{os.environ["PATH"]}')
        self.git('init', '-q')
        self.git('add', '.')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                 '-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture')
        self.env['BASE_SHA'] = self.git('rev-parse', 'HEAD').strip()
        self.env['ALLOW_ENTITLEMENT_CHANGE'] = '0'

    def git(self, *args):
        return subprocess.check_output(
            ['git', '-c', 'core.fsmonitor=false', *args], cwd=self.root, text=True
        )

    def guard(self, *, allowed=False):
        env = dict(self.env, ALLOW_ENTITLEMENT_CHANGE='1' if allowed else '0')
        return subprocess.run(
            ['bash', 'scripts/ci/check_consistency.sh'], cwd=self.root,
            env=env, text=True, capture_output=True, check=False
        )

    def assertRejected(self):
        result = self.guard()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('allow-entitlement-change', result.stderr)

    def test_unchanged_passes(self):
        result = self.guard()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_unrelated_build_setting_passes(self):
        self.project.write_text(self.project.read_text().replace('OTHER_SETTING = YES', 'OTHER_SETTING = NO'))
        self.assertEqual(self.guard().returncode, 0)

    def test_each_capability_family_and_config_format_requires_label(self):
        assignments = (
            'ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES;',
            'ENABLE_RESOURCE_ACCESS_USB = NO;',
            'ENABLE_RESOURCE_ACCESS_FUTURE_CAPABILITY = YES;',
            'ENABLE_USER_SELECTED_FILES = readwrite;',
            'ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;',
            '"ENABLE_RESOURCE_ACCESS_CAMERA[sdk=macosx*]" = NO;',
            'ENABLE_USER_SELECTED_FILES[config=Debug] = readwrite',
        )
        for target in (self.project, self.config):
            original = target.read_text()
            for assignment in assignments:
                with self.subTest(file=target.name, assignment=assignment):
                    target.write_text(original + '\t' + assignment + '\n')
                    self.assertRejected()
            target.write_text(original)

    def test_removing_capability_requires_label(self):
        self.project.write_text('OTHER_SETTING = YES;\n')
        self.assertRejected()

    def test_entitlement_file_requires_label(self):
        self.entitlements.write_text('<plist><dict><key>changed</key><true/></dict></plist>\n')
        self.assertRejected()

    def test_label_allows_capability_and_entitlement_change(self):
        self.project.write_text('ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES;\n')
        self.entitlements.write_text('<plist><dict><key>changed</key><true/></dict></plist>\n')
        result = self.guard(allowed=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('allowed by label', result.stdout)


if __name__ == '__main__':
    unittest.main()
