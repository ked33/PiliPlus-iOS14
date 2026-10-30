#!/usr/bin/env python3
"""Reject IPA files whose plist or Mach-O deployment targets exceed iOS 14.7.

This is a packaging check, not a substitute for execution on an iOS 14 device.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import zipfile

MAXIMUM = (14, 7, 0)
MACH_MAGICS = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}


def version(number):
    return (number >> 16, (number >> 8) & 255, number & 255)


def targets(data):
    if data[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        wide = data[3] == 191
        count = struct.unpack_from('>I', data, 4)[0]
        if count > 16:
            raise ValueError('Invalid Mach-O architecture count')
        result = []
        for i in range(count):
            fields = struct.unpack_from('>IIQQII' if wide else '>IIIII', data, 8 + i * (32 if wide else 20))
            offset, size = fields[2:4]
            if offset + size > len(data):
                raise ValueError('Truncated universal Mach-O')
            result.extend(targets(data[offset:offset + size]))
        return result
    if data[:4] not in MACH_MAGICS:
        raise ValueError('Expected Mach-O binary')
    count, command_bytes = struct.unpack_from('<II', data, 16)
    offset = 32 if data[:4] == b'\xcf\xfa\xed\xfe' else 28
    end = offset + command_bytes
    if end > len(data) or count > 10000:
        raise ValueError('Truncated Mach-O load commands')
    result = []
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, offset)
        if size < 8 or offset + size > end:
            raise ValueError('Invalid Mach-O load command')
        if command == 0x32:
            platform, minimum = struct.unpack_from('<II', data, offset + 8)
            if platform != 2:
                raise ValueError(f'Expected iPhoneOS platform, got {platform}')
            result.append(version(minimum))
        elif command == 0x25:
            result.append(version(struct.unpack_from('<I', data, offset + 8)[0]))
        offset += size
    if not result:
        raise ValueError('Mach-O has no iOS deployment target')
    return result


def verify(path):
    errors, records = [], []
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        main_plists = [name for name in names if name.startswith('Payload/') and name.count('/') == 2 and name.endswith('.app/Info.plist')]
        if len(main_plists) != 1:
            raise ValueError('Expected exactly one app in Payload')
        for name in sorted(names):
            if name.endswith('/'):
                continue
            with archive.open(name) as stream:
                magic = stream.read(4)
            if magic in MACH_MAGICS:
                try:
                    minimums = targets(archive.read(name))
                    records.append({'path': name, 'minimums': ['.'.join(map(str, v)) for v in minimums]})
                    if any(v > MAXIMUM for v in minimums):
                        errors.append(f'{name}: binary requires {minimums}')
                except (ValueError, struct.error) as error:
                    errors.append(f'{name}: {error}')
            if name.endswith('/Info.plist'):
                info = plistlib.loads(archive.read(name))
                executable = info.get('CFBundleExecutable')
                if executable:
                    binary = str(PurePosixPath(name).parent / executable)
                    if binary not in names:
                        errors.append(f'{name}: missing executable {executable}')
                    minimum = info.get('MinimumOSVersion')
                    if not minimum:
                        errors.append(f'{name}: missing MinimumOSVersion')
                    else:
                        parts = tuple(map(int, minimum.split('.')))
                        if (parts + (0, 0))[:3] > MAXIMUM:
                            errors.append(f'{name}: plist requires {minimum}')
        if not records:
            errors.append('No Mach-O executable found')
        main = plistlib.loads(archive.read(main_plists[0]))
        app_root = str(PurePosixPath(main_plists[0]).parent)
        for name in ['Flutter', 'App']:
            if f'{app_root}/Frameworks/{name}.framework/{name}' not in names:
                errors.append(f'Missing {name}.framework')
    return {'version': main.get('CFBundleShortVersionString'), 'build': main.get('CFBundleVersion'), 'binaries': records, 'errors': errors}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    report = verify(args.ipa)
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    for error in report['errors']:
        print(error)
    print(f"Checked {len(report['binaries'])} Mach-O binaries: {'FAIL' if report['errors'] else 'PASS'}")
    raise SystemExit(bool(report['errors']))
