#!/usr/bin/env python3
"""Hash build inputs, including local edits, without packaged or generated output."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
hash_value = hashlib.sha256()
for filename in ('BuildInfo.plist', 'build_release.sh', 'scripts/source_fingerprint.py'):
    path = root / filename
    hash_value.update(filename.encode() + b'\0' + path.read_bytes() + b'\0')
for folder in ('CinematicCoreMacOS', 'CinematicCoreExtension', 'Shared', 'CinematicCoreMacOS.xcodeproj'):
    for path in sorted((root / folder).rglob('*')):
        if not path.is_file() or any(p in ('xcuserdata', '.DS_Store') for p in path.parts):
            continue
        hash_value.update(path.relative_to(root).as_posix().encode() + b'\0')
        hash_value.update(path.read_bytes() + b'\0')
print(hash_value.hexdigest())
