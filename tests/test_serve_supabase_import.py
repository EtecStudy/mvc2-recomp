#!/usr/bin/env python3
"""Synthetic-only tests. No cloud/network access beyond a local test server."""
import hashlib
import http.client
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from subprocess import CompletedProcess

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
from serve_supabase_import import ImportServer, PUBLIC_SOURCE


class BrowserImport(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.target = Path(cls.tmp.name)/'working/SLUS_204.86'
        cls.payload = bytes(range(256))*2
        cls.sha = hashlib.sha256(cls.payload).hexdigest()
        cls.server = ImportServer(('127.0.0.1', 0), cls.target,
                                  ('SLUS_204.86', len(cls.payload), cls.sha))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join()
        cls.tmp.cleanup()

    def setUp(self):
        if self.target.exists() or self.target.is_symlink():
            self.target.unlink()

    def request(self, method, path, body=None, nonce=None, headers=None):
        conn = http.client.HTTPConnection(*self.server.server_address, timeout=5)
        h = dict(headers or {})
        if nonce is not None:
            h['X-Import-Nonce'] = nonce
        conn.request(method, path, body, h)
        response = conn.getresponse()
        status, result, result_headers = response.status, response.read(), dict(response.getheaders())
        conn.close()
        return status, result, result_headers

    def upload(self, payload=None, **kwargs):
        return self.request('POST', '/api/import', self.payload if payload is None else payload,
                            nonce=self.server.nonce, **kwargs)

    def test_preview_and_status(self):
        status, body, headers = self.request('GET', '/')
        self.assertEqual(status, 200)
        self.assertIn(PUBLIC_SOURCE.encode(), body)
        self.assertIn(b'X-Import', (Path(__file__).resolve().parents[1]/'scripts/supabase_import/app.js').read_bytes())
        self.assertNotIn('X-Frame-Options', headers)  # Existing authenticated preview can embed.
        self.assertNotIn('Access-Control-Allow-Origin', headers)
        self.assertEqual(headers['Cache-Control'], 'no-store')
        status, body, _ = self.request('GET', '/api/status')
        self.assertFalse(json.loads(body)['verified'])

    def test_missing_and_wrong_nonce(self):
        for nonce in (None, 'not-the-preview-nonce', '\u00ff'):
            self.assertEqual(self.request('POST', '/api/import', self.payload, nonce)[0], 403)
        self.assertFalse(self.target.exists())

    def test_exact_body_length_required(self):
        for payload in (b'', self.payload[:-1], self.payload+b'x'):
            self.assertEqual(self.upload(payload)[0], 413)
        self.assertFalse(self.target.exists())

    def test_hash_mismatch_does_not_publish(self):
        status, body, _ = self.upload(b'\0'*len(self.payload))
        self.assertEqual(status, 400)
        self.assertIn('SHA-256 mismatch', json.loads(body)['error'])
        self.assertFalse(self.target.exists())

    def test_valid_and_idempotent_publication(self):
        status, body, _ = self.upload()
        self.assertEqual(status, 200)
        result = json.loads(body)
        self.assertTrue(result['verified']); self.assertTrue(result['created'])
        self.assertFalse(result['whole_game_analysis_complete'])
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.assertFalse(json.loads(self.upload()[1])['created'])
        self.assertTrue(json.loads(self.request('GET', '/api/status')[1])['verified'])

    def test_conflicting_destination_never_overwritten(self):
        self.target.parent.mkdir(parents=True, exist_ok=True)
        self.target.write_bytes(b'preserve existing local file')
        self.assertEqual(self.upload()[0], 400)
        self.assertEqual(self.target.read_bytes(), b'preserve existing local file')

    def test_no_file_serving_proxy_or_cors_preflight(self):
        for path in ('/game/working/SLUS_204.86', '/../../scripts/target.sh',
                     '/api/proxy?url=https://example.com', '/?source=other'):
            self.assertEqual(self.request('GET', path)[0], 404)
        status, _, headers = self.request('OPTIONS', '/api/import', headers={
            'Origin': 'https://unrelated.example', 'Access-Control-Request-Method': 'POST'})
        self.assertEqual(status, 501)
        self.assertNotIn('Access-Control-Allow-Origin', headers)

    def test_analysis_is_opt_in_waits_for_verified_event_and_runs_once(self):
        # Mock child launch: this fixture never launches Ghidra or game codegen.
        server = ImportServer(('127.0.0.1', 0), Path(self.tmp.name)/'absent',
                              ('SLUS_204.86', len(self.payload), self.sha))
        try:
            with patch('serve_supabase_import.subprocess.run', return_value=CompletedProcess([], 0)) as run:
                server.enable_analysis()
                worker = server.analysis_thread
                server.enable_analysis()
                self.assertIs(worker, server.analysis_thread)
                self.assertFalse(run.called)
                self.assertEqual(server.analysis['state'], 'waiting_for_verified_elf')
                server.elf_ready.set()
                worker.join(5)
                self.assertFalse(worker.is_alive())
                run.assert_called_once()
                args = run.call_args.args[0]
                self.assertEqual(args[0], 'bash')
                self.assertTrue(args[1].endswith('/scripts/fase1_analyze.sh'))
                self.assertEqual(args[-1], '--recomp')
                self.assertEqual(server.analysis['state'], 'completed')
        finally:
            server.server_close()

    def test_transfer_encoding_rejected(self):
        self.assertEqual(self.upload(headers={'Transfer-Encoding': 'chunked'})[0], 400)
        self.assertFalse(self.target.exists())


if __name__ == '__main__':
    unittest.main()
