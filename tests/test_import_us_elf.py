import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('intake', ROOT/'scripts/import_us_elf.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root/'owner-attachment'
        self.data = b'Original synthetic import-test fixture, not game bytes.'
        self.source.write_bytes(self.data)
        self.destination = self.root/'working/SLUS_204.86'
        self.sha = hashlib.sha256(self.data).hexdigest()

    def stage(self):
        return module.stage(self.source,self.destination,len(self.data),self.sha)

    def assert_clean(self):
        self.assertEqual(list(self.root.rglob('.incoming-us-*')),[])
        self.assertEqual(self.source.read_bytes(),self.data)

    def test_copy_and_independent_hash_source_preserved(self):
        self.assertTrue(self.stage())
        self.assertEqual(self.destination.read_bytes(),self.data)
        self.assert_clean()

    def test_wrong_size_and_hash_never_publish(self):
        for size,sha in ((len(self.data)+1,self.sha),(len(self.data),'0'*64)):
            with self.subTest(size=size),self.assertRaises(ValueError):
                module.stage(self.source,self.destination,size,sha)
            self.assertFalse(self.destination.exists())
            self.assert_clean()

    def test_existing_correct_target_is_reused(self):
        self.stage()
        before = self.destination.stat()
        self.assertFalse(self.stage())
        after = self.destination.stat()
        self.assertEqual((before.st_ino,before.st_mtime_ns),(after.st_ino,after.st_mtime_ns))
        self.assert_clean()

    def test_existing_different_target_never_overwritten(self):
        self.destination.parent.mkdir()
        self.destination.write_bytes(b'preserve existing content')
        with self.assertRaisesRegex(ValueError,'overwrite'): self.stage()
        self.assertEqual(self.destination.read_bytes(),b'preserve existing content')
        self.assert_clean()

    def test_symlink_destination_is_not_replaced(self):
        self.destination.parent.mkdir()
        self.destination.symlink_to(self.source)
        with self.assertRaisesRegex(ValueError,'non-symlink'): self.stage()
        self.assertTrue(self.destination.is_symlink())
        self.assert_clean()

    def test_concurrently_created_target_never_overwritten(self):
        def race(src,dst):
            Path(dst).write_bytes(b'concurrent owner file')
            raise FileExistsError()
        with patch.object(module.os,'link',side_effect=race):
            with self.assertRaisesRegex(ValueError,'overwrite'): self.stage()
        self.assertEqual(self.destination.read_bytes(),b'concurrent owner file')
        self.assert_clean()

    def test_cli_identity_is_pinned_to_active_us_target(self):
        serial,size,sha=module.target_identity()
        self.assertEqual(serial,'SLUS_204.86')
        self.assertEqual(size,3942320)
        self.assertEqual(sha,'48ebf907d8149122ca9bd622ed11c290d5f93173078ea5bd570e1ac5566f13d7')


if __name__ == '__main__': unittest.main()
