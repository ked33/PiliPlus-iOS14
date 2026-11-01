import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

path = Path(__file__).resolve().parents[2] / 'tool/ios14/verify_ipa.py'
spec = importlib.util.spec_from_file_location('verify_ipa', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def macho(major, minor=0, platform=2):
    header = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 6, 1, 24, 0, 0)
    command = struct.pack('<6I', 0x32, 24, platform, (major << 16) | (minor << 8), 0, 0)
    return header + command


def macho_with_symbol(name, *, weak=False, defined=False, wide=True):
    header_size, entry_size = (32, 16) if wide else (28, 12)
    header = struct.pack('<7I', 0xfeedfacf if wide else 0xfeedface,
                         0x100000c if wide else 12, 0, 6, 2, 48, 0)
    if wide:
        header += b'\0' * 4
    strings = b'\0' + name.encode() + b'\0'
    symbol_offset = header_size + 48
    target = struct.pack('<6I', 0x32, 24, 2, 14 << 16, 0, 0)
    table = struct.pack('<6I', 2, 24, symbol_offset, 1, symbol_offset + entry_size, len(strings))
    symbol = struct.pack('<IBBHQ' if wide else '<IBBHI', 1,
                         0x0f if defined else 0x01, 1 if defined else 0,
                         0x40 if weak else 0, 0)
    return header + target + table + symbol + strings


class VerifyIpaTest(unittest.TestCase):
    def test_reads_actual_binary_target(self):
        self.assertEqual(module.targets(macho(14, 7)), [(14, 7, 0)])
        self.assertGreater(module.targets(macho(15))[0], module.MAXIMUM)

    def test_rejects_simulator_binary(self):
        with self.assertRaisesRegex(ValueError, 'iPhoneOS'):
            module.targets(macho(14, platform=7))

    def test_rejects_truncated_binary(self):
        with self.assertRaises(ValueError):
            module.targets(macho(14)[:-4])

    def test_checks_each_universal_slice(self):
        first, second = macho(14), macho(15)
        fat = struct.pack('>II', 0xcafebabe, 2)
        fat += struct.pack('>5I', 0x100000c, 0, 48, len(first), 0)
        fat += struct.pack('>5I', 0x100000c, 0, 48 + len(first), len(second), 0)
        self.assertEqual(module.targets(fat + first + second), [(14, 0, 0), (15, 0, 0)])

    def test_distinguishes_strong_weak_and_defined_symbols(self):
        name = '_CMTimebaseCreateWithSourceClock'
        for wide in (False, True):
            with self.subTest(wide=wide):
                self.assertEqual(module.strong_undefined_symbols(macho_with_symbol(name, wide=wide)), {name})
                self.assertEqual(module.strong_undefined_symbols(macho_with_symbol(name, weak=True, wide=wide)), set())
                self.assertEqual(module.strong_undefined_symbols(macho_with_symbol(name, defined=True, wide=wide)), set())

    def test_rejects_truncated_symbol_table(self):
        with self.assertRaisesRegex(ValueError, 'symbol table'):
            module.strong_undefined_symbols(macho_with_symbol('_CMTimebaseCreateWithSourceClock')[:-1])

    def test_imports_from_every_universal_slice(self):
        first = macho_with_symbol('_CMTimebaseCreateWithMasterClock')
        second = macho_with_symbol('_CMTimebaseCreateWithSourceClock')
        fat = struct.pack('>II', 0xcafebabe, 2)
        fat += struct.pack('>5I', 0x100000c, 0, 48, len(first), 0)
        fat += struct.pack('>5I', 0x100000c, 0, 48 + len(first), len(second), 0)
        self.assertEqual(module.strong_undefined_symbols(fat + first + second),
                         {'_CMTimebaseCreateWithMasterClock', '_CMTimebaseCreateWithSourceClock'})

    def test_ipa_rejects_ios14_target_with_unavailable_import(self):
        for name, weak, should_fail in [
            ('_CMTimebaseCreateWithSourceClock', False, True),
            ('_CMTimebaseCreateWithSourceClock', True, False),
            ('_CMTimebaseCreateWithMasterClock', False, False),
        ]:
            with self.subTest(name=name, weak=weak), tempfile.TemporaryDirectory() as folder:
                ipa = Path(folder) / 'app.ipa'
                with zipfile.ZipFile(ipa, 'w') as archive:
                    archive.writestr('Payload/Runner.app/Info.plist', plistlib.dumps({
                        'CFBundleExecutable': 'Runner', 'MinimumOSVersion': '14.0',
                    }))
                    archive.writestr('Payload/Runner.app/Runner', macho_with_symbol(name, weak=weak))
                    for framework in ('Flutter', 'App'):
                        archive.writestr(f'Payload/Runner.app/Frameworks/{framework}.framework/{framework}', macho(14))
                errors = module.verify(ipa)['errors']
                if should_fail:
                    self.assertEqual(len(errors), 1)
                    self.assertIn('strong import _CMTimebaseCreateWithSourceClock', errors[0])
                else:
                    self.assertEqual(errors, [])


if __name__ == '__main__':
    unittest.main()
