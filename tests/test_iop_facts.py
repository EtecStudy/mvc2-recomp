"""Validate captured derived facts offline; these are not game-execution tests."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
FACTS = ROOT / 'analysis/scout/slus_20486'


def load(name):
    return json.loads((FACTS / name).read_text())


def modules():
    text = (FACTS / 'iop_modules_compact.txt').read_text().strip()
    assert hashlib.sha256(text.encode()).hexdigest() == '7b89ca2f9885c781169629c312fab25483e5ed4b91f13eaaa984940fc983704a'
    result = {}
    def tables(text):
        rows = []
        for t in filter(None, text.split(',')):
            name, rest = t.split('@')
            version, count = rest.split(':')
            rows.append((name, int(version, 16), int(count)))
        return rows
    for line in text.splitlines():
        path, size, sha, typ, im, ex = line.split('|')
        assert path not in result
        result[path] = dict(bytes=int(size), sha256=sha, elf_type=int(typ), imports=tables(im), exports=tables(ex))
    return result


class FactsTests(unittest.TestCase):
    def test_canonical_copy_and_counts(self):
        m = modules()
        self.assertEqual(len(m), 41)
        self.assertEqual(sum(len(x['imports']) for x in m.values()), 284)
        self.assertEqual(sum(len(x['exports']) for x in m.values()), 41)
        uploaded = {f['path']: f['size_bytes'] for f in load('storage_inventory.json')['files']}
        disk = [p for p in m if '#' not in p]
        self.assertEqual(len(disk), 26)
        for path in disk:
            self.assertEqual(m[path]['bytes'], uploaded[path])
            self.assertEqual(m[path]['elf_type'], 0xff80)
            self.assertEqual(len(bytes.fromhex(m[path]['sha256'])), 32)

    def test_relocated_export_regression_and_sound_profile(self):
        m = modules()
        self.assertIn(('modhsyn', 0x104, 29), m['MODULES/MODHSYN.IRX']['exports'])
        self.assertIn(('thbase', 0x102, 52), m['MODULES/IOPRP255.IMG#THREADMAN']['exports'])
        p = load('tsnddrv_imports.json')
        self.assertEqual(sum(len(t['ordinals']) for t in p['imports']), 61)
        self.assertEqual(len(p['imports']), 14)
        self.assertEqual(p['sha256'], m[p['path']]['sha256'])
        for t in p['imports']:
            self.assertIn((t['library'], t['version'], len(t['ordinals'])), m[p['path']]['imports'])
            providers = [path for path, module in m.items() if any(
                name == t['library'] and version >> 8 == t['version'] >> 8 and count > max(t['ordinals'])
                for name, version, count in module['exports'])]
            self.assertEqual(sorted(providers), sorted(t['uploaded_provider_candidates']))

    def test_romdir_extents(self):
        rom = load('romdir.json')
        self.assertEqual(len(rom['entries']), 18)
        cursor = 0
        for e in rom['entries']:
            self.assertEqual(e['file_offset'], cursor)
            self.assertLessEqual(cursor + e['bytes'], rom['bytes'])
            cursor += (e['bytes'] + 15) // 16 * 16
        self.assertEqual(cursor - rom['bytes'], 15)  # absent final alignment padding, not payload

    def test_missing_assets_from_us_filelist(self):
        a = load('asset_completeness.json')
        uploaded = {f['path'].lower() for f in load('storage_inventory.json')['files']}
        missing = {'ps2/' + n.lower() for n in a['filelist']['listed_names']} - uploaded
        self.assertEqual(missing, {n.lower() for n in a['missing_listed_objects']})
        self.assertEqual(missing, {'ps2/afs00.afs', 'ps2/afs02.afs'})
        for f in a['uploaded_afs']:
            self.assertLessEqual(f['required_payload_end'], f['bytes'])

    def test_static_dependency_caveats(self):
        r = load('iop_dependency_report.json')
        self.assertEqual(r['ordinal_span_available_tables'] + r['no_uploaded_export_tables'], 284)
        audit = {a['library']: a for a in r['core_dispatch_audit']}
        self.assertEqual(audit['secrman']['missing_case_ordinals'], [6])
        self.assertIn('zero-return', audit['dmacman']['status'])


if __name__ == '__main__':
    unittest.main()
