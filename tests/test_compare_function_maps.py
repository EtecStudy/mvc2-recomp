import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/compare_function_maps.py'
spec = importlib.util.spec_from_file_location('crosscheck', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CompareTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.p = Path(self.tmp.name)
        self.elf = self.p / 'original-probe.elf'
        head = struct.pack('<16sHHIIIIIHHHHHH', b'\x7fELF\x01\x01\x01'+bytes(9),
                           2, 8, 1, 0x100000, 52, 0, 0, 52, 32, 1, 40, 0, 0)
        ph = struct.pack('<8I', 1, 256, 0x100000, 0x100000, 64, 96, 5, 256)
        self.elf.write_bytes((head+ph).ljust(256, b'\0')+bytes(64))
        self.gh, self.an = self.p/'gh.csv', self.p/'an.csv'
        self.gt, self.at = self.p/'gh.toml', self.p/'an.toml'
        # Non-contiguous Ghidra body and an executable label inside its extent.
        self.gh.write_text('Name,Start,End,Size\nfunc,0x100000,0x100010,8\nlabel,0x100008,0x100010,8\n')
        self.an.write_text('Name,Start,End,Size\nentry,0x100000,0x10000c,12\nother,0x100020,0x100024,4\n')
        self.gt.write_text(f'[general]\ninput={json.dumps(str(self.elf))}\nghidra_output={json.dumps(str(self.gh))}\nstubs=["not_a_function_map@0x00100030"]\n[ghidra_export]\nfunction_count=1\ncode_label_count=1\ncsv_record_count=2\n')
        self.at.write_text(f'[general]\ninput={json.dumps(str(self.elf))}\nstubs=["not_a_map@0x00100038"]\n[mmio]\n"0x00100034"="0x10000000"\n')

    def compare(self):
        return module.compare(self.elf, self.gh, self.an, self.gt, self.at)

    def test_real_sets_boundaries_labels_not_toml_tokens(self):
        r = self.compare()
        self.assertEqual((r['ghidra_records'], r['analyzer_records'], r['common_starts']), (2, 2, 1))
        self.assertEqual((r['ghidra_functions'], r['ghidra_code_labels']), (1, 1))
        self.assertEqual(len(r['boundary_disagreements']), 1)
        self.assertEqual(r['ghidra_only_starts'], ['0x00100008'])
        self.assertEqual(r['analyzer_only_starts'], ['0x00100020'])

    def test_reject_bad_rows_and_empty_maps(self):
        for text in ('Name,Start,End,Size\n',
                     'Name,Start,End,Size\nx,0x100000,0x100010\n',
                     'Name,Start,End,Size\nx,0x100000,0x100010,16,extra\n',
                     'Name,Start,End,Size\nx,0x100000,0x100010,16\ny,0x100000,0x100010,16\n',
                     'Name,Start,End,Size\nx,0x100000,0x100011,16\n',
                     'Name,Start,End,Size\nx,0x100000,0x100010,20\n'):
            with self.subTest(text=text):
                self.an.write_text(text)
                with self.assertRaises(ValueError): self.compare()

    def test_reject_bss_as_file_backed_code(self):
        self.an.write_text('Name,Start,End,Size\nx,0x100000,0x100044,68\n')
        with self.assertRaisesRegex(ValueError, 'executable file segment'): self.compare()

    def test_reject_wrong_configs_or_stale_metadata(self):
        original = self.gt.read_text()
        for text in (original.replace('csv_record_count=2', 'csv_record_count=9'),
                     original.replace('code_label_count=1', 'code_label_count=0'),
                     original.replace('function_count=1', 'function_count=true'),
                     original.replace('function_count=1', 'function_count=0'),
                     'general=1\n',
                     original.replace('[ghidra_export]\n', 'ghidra_export=1\n[other]\n'),
                     original.replace(str(self.elf), str(self.p/'different.elf')),
                     original.replace(str(self.gh), str(self.an))):
            with self.subTest(text=text):
                self.gt.write_text(text)
                with self.assertRaises(ValueError): self.compare()

    def test_entry_must_be_covered(self):
        self.an.write_text('Name,Start,End,Size\nx,0x100020,0x100024,4\n')
        with self.assertRaisesRegex(ValueError, 'entry is not covered'): self.compare()

    def test_reject_malformed_elf(self):
        original = self.elf.read_bytes()
        for b in (b'bad', original[:60], original[:18]+b'\x3e\x00'+original[20:]):
            with self.subTest():
                self.elf.write_bytes(b)
                with self.assertRaises(ValueError): self.compare()

    def test_cli_writes_only_validated_report(self):
        out = self.p/'comparison.json'
        cmd = [sys.executable, str(SCRIPT), str(self.elf), str(self.gh), str(self.an), str(self.gt), str(self.at), str(out)]
        subprocess.run(cmd, check=True, capture_output=True)
        before = out.read_bytes()
        self.an.write_text('invalid')
        result = subprocess.run(cmd, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'Map cross-check refused', result.stderr)
        self.assertEqual(out.read_bytes(), before)
        self.assertEqual(list(self.p.glob('.map-comparison-*')), [])


if __name__ == '__main__':
    unittest.main()
