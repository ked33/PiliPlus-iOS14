import importlib.util
from pathlib import Path
import struct
import unittest

path = Path(__file__).resolve().parents[2] / 'tool/ios14/verify_ipa.py'
spec = importlib.util.spec_from_file_location('verify_ipa', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def macho(major, minor=0, platform=2):
    header = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 6, 1, 24, 0, 0)
    command = struct.pack('<6I', 0x32, 24, platform, (major << 16) | (minor << 8), 0, 0)
    return header + command


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


if __name__ == '__main__':
    unittest.main()
