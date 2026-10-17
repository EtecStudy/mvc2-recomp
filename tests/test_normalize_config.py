import importlib.util
from pathlib import Path
import tempfile
import tomllib
import unittest

spec = importlib.util.spec_from_file_location('normalizer', Path(__file__).resolve().parents[1] / 'scripts/normalize_recomp_config.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class NormalizeTests(unittest.TestCase):
    def test_modify_general_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'config.toml'
            p.write_text('[general]\ninput="probe.elf"\noutput="wrong"\nsingle_file_output=true\n[other]\noutput="preserve"\nlow_memory_mode=false\n')
            module.normalize(p, Path(tmp) / 'cpp')
            d = tomllib.loads(p.read_text())
            self.assertEqual(d['general']['output'], str(Path(tmp) / 'cpp'))
            self.assertTrue(d['general']['low_memory_mode'])
            self.assertFalse(d['general']['single_file_output'])
            self.assertEqual(d['general']['output_worker_threads'], 1)
            self.assertEqual(d['other'], {'output': 'preserve', 'low_memory_mode': False})
            first = p.read_text()
            module.normalize(p, Path(tmp) / 'cpp')
            self.assertEqual(p.read_text(), first)

    def test_invalid_or_missing_general_preserved(self):
        for text in ('[other]\noutput="x"\n', '[general]\na=1\na=2\n'):
            with self.subTest(text=text), tempfile.TemporaryDirectory() as tmp:
                p = Path(tmp) / 'config.toml'
                p.write_text(text)
                with self.assertRaises(ValueError):
                    module.normalize(p, Path(tmp) / 'cpp')
                self.assertEqual(p.read_text(), text)

if __name__ == '__main__':
    unittest.main()
