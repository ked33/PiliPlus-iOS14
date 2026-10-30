#!/usr/bin/env python3
"""Write release metadata without replacing the official base version number."""
import json
from pathlib import Path
import subprocess
import time

root = Path(__file__).resolve().parents[2]
revision = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
path = root / 'pubspec.yaml'
original = path.read_bytes()
before = b'version: 2.1.6+1'
if original.count(before) != 1:
    raise SystemExit('Expected official release 2.1.6 version anchor')
path.write_bytes(original.replace(before, b'version: 2.1.6+5472', 1))
(root / 'pili_release.json').write_text(json.dumps({
    'pili.name': '2.1.6', 'pili.code': 5472,
    'pili.hash': revision, 'pili.time': int(time.time()),
}) + '\n')
