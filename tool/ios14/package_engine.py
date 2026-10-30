#!/usr/bin/env python3
"""Package only the local-engine files consumed by flutter build ios."""
import argparse
import json
from pathlib import Path
import tarfile

from patch_flutter import FLUTTER_REVISION


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('flutter_root', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    root = args.flutter_root.resolve()
    out = root / 'engine/src/out'
    targets = ['ios_release', 'host_release_arm64']
    required = [
        'ios_release/Flutter.xcframework',
        'ios_release/flutter_patched_sdk',
        'host_release_arm64/gen/dart-pkg/sky_engine',
        'host_release_arm64/font-subset',
    ]
    for name in required:
        if not (out / name).exists():
            raise SystemExit(f'Missing engine build output: {name}')
    # The local engine resolves its Dart SDK under the host output first.
    host_sdk = out / targets[1] / 'dart-sdk'
    if not host_sdk.exists():
        candidates = list((root / 'engine/src/flutter/prebuilts').glob('*/dart-sdk'))
        candidates = [p for p in candidates if 'macos-arm64' in str(p) or 'darwin-arm64' in str(p)]
        if len(candidates) != 1:
            raise SystemExit(f'Cannot locate matching arm64 Dart SDK: {candidates}')
        host_sdk.symlink_to(candidates[0], target_is_directory=True)
    metadata = out / 'ios14-engine.json'
    metadata.write_text(json.dumps({'flutter_revision': FLUTTER_REVISION, 'minimum_ios': '14.0'}) + '\n')
    excluded = {'obj', 'obj.host', 'thinlto-cache', 'exe.unstripped'}
    with tarfile.open(args.output, 'w:gz', dereference=True, compresslevel=3) as archive:
        archive.add(metadata, arcname='ios14-engine.json')
        for target in targets:
            for path in sorted((out / target).iterdir()):
                if path.name in excluded or path.name.startswith('.') or path.name.endswith(('.ninja', '.ninja.d')):
                    continue
                archive.add(path, arcname=str(path.relative_to(out)))
    print(f'Packaged engine: {args.output.stat().st_size // (1024 * 1024)} MiB')


if __name__ == '__main__':
    main()
