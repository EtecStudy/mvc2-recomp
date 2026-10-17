import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('deps', ROOT/'scripts/restore_analyzer_deps.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root/'tools/downloads').mkdir(parents=True)
        self.archive = self.root/'tools/downloads/analyzer-deps.tar.gz'
        self.patch = patch.object(module, 'ROOT', self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def fixture(self, extra=None, missing=False):
        with tarfile.open(self.archive, 'w:gz') as tar:
            for name in (['elfio-src/CMakeLists.txt'] if missing else
                         ['elfio-src/CMakeLists.txt', 'rabbitizer-src/include/rabbitizer.h']):
                info = tarfile.TarInfo(name)
                b = b'original unit-test fixture\n'
                info.size = len(b)
                tar.addfile(info, io.BytesIO(b))
            if extra is not None:
                tar.addfile(extra, io.BytesIO(b'x') if extra.isfile() else None)
        b = self.archive.read_bytes()
        meta = {'archive': str(self.archive.relative_to(self.root)), 'bytes': len(b),
                'sha256': hashlib.sha256(b).hexdigest(), 'commits': {'elfio': 'fixture', 'rabbitizer': 'fixture'}}
        (self.root/'tools/analyzer_deps.json').write_text(json.dumps(meta))

    def test_valid_source_restore_and_offline_cmake(self):
        self.fixture()
        module.restore()
        cache = (self.root/'builddir/analyzer-deps.cmake').read_text()
        self.assertIn('FETCHCONTENT_FULLY_DISCONNECTED ON', cache)
        self.assertIn('FETCHCONTENT_SOURCE_DIR_RABBITIZER', cache)
        module.restore()  # idempotent

    def test_bad_hash_fails_before_extraction(self):
        self.fixture()
        with self.archive.open('ab') as f: f.write(b'altered')
        with self.assertRaisesRegex(ValueError, 'size/SHA-256'): module.restore()
        self.assertFalse((self.root/'builddir/analyzer-deps').exists())

    def test_unsafe_archive_members(self):
        for name, link in (('../escape', False), ('/absolute', False), ('elfio-src/link', True)):
            with self.subTest(name=name):
                info = tarfile.TarInfo(name)
                if link:
                    info.type = tarfile.SYMTYPE
                    info.linkname = '/tmp/outside'
                else: info.size = 1
                self.fixture(info)
                with self.assertRaisesRegex(ValueError, 'Unsafe dependency archive'): module.restore()

    def test_existing_parent_symlink_escape(self):
        self.fixture()
        dest = self.root/'builddir/analyzer-deps'
        dest.mkdir(parents=True)
        outside = self.root/'outside'
        outside.mkdir()
        (dest/'elfio-src').symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Unsafe existing dependency path'): module.restore()
        self.assertFalse((outside/'CMakeLists.txt').exists())

    def test_missing_sentinel_does_not_emit_cache(self):
        self.fixture(missing=True)
        with self.assertRaisesRegex(ValueError, 'Missing source sentinel'): module.restore()
        self.assertFalse((self.root/'builddir/analyzer-deps.cmake').exists())


if __name__ == '__main__':
    unittest.main()
