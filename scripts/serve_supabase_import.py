#!/usr/bin/env python3
"""Private preview: owner browser reads one public Supabase object into workspace.

No arbitrary URL proxy, file picker, cloud key, public relay or auth bypass.
E2B's existing preview access control remains enabled. Only the pinned US ELF
can be published locally; original Storage/attachment bytes are never modified.
"""
import argparse
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import tempfile
import subprocess
import threading

from import_us_elf import ROOT, file_identity, stage, target_identity

PUBLIC_SOURCE = 'https://tkndzbkcmgfailtxuwie.supabase.co/storage/v1/object/public/ps2recomp/SLUS_204.86'
ASSETS = Path(__file__).resolve().parent/'supabase_import'


class ImportServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, destination=None, identity=None):
        self.serial, self.expected_size, self.expected_sha = identity or target_identity()
        self.destination = destination or ROOT/'game/working'/self.serial
        self.nonce = secrets.token_urlsafe(32)
        self.elf_ready = threading.Event()
        self.analysis = {'enabled': False, 'state': 'not_requested', 'exit_code': None}
        super().__init__(address, Handler)

    def enable_analysis(self):
        """Agent opt-in only; one fixed pipeline after the real hash gate.

        No command or argument is accepted from HTTP. Completion is a pipeline
        attempt, not a claim of correct maps, native build, boot or gameplay.
        """
        if self.analysis['enabled']:
            return
        self.analysis = {'enabled': True, 'state': 'waiting_for_verified_elf', 'exit_code': None}
        self.analysis_thread = threading.Thread(target=self._analyze_when_ready, daemon=True)
        self.analysis_thread.start()
        p = self.destination
        if not p.is_symlink() and p.is_file() and file_identity(p) == (self.expected_size, self.expected_sha):
            self.elf_ready.set()

    def _analyze_when_ready(self):
        self.elf_ready.wait()
        self.analysis = {'enabled': True, 'state': 'running', 'exit_code': None}
        print('US_ANALYSIS_STARTED fixed=fase1_analyze.sh --recomp', flush=True)
        try:
            log = ROOT/'builddir/logs/supabase-import-fase1.log'
            log.parent.mkdir(parents=True, exist_ok=True)
            with log.open('a') as out:
                result = subprocess.run(['bash', str(ROOT/'scripts/fase1_analyze.sh'),
                                         str(self.destination), '--recomp'],
                                        cwd=ROOT, stdout=out, stderr=subprocess.STDOUT)
            self.analysis = {'enabled': True, 'state': 'completed' if result.returncode == 0 else 'failed',
                             'exit_code': result.returncode}
            print(f'US_ANALYSIS_EXIT={result.returncode} log=builddir/logs/supabase-import-fase1.log', flush=True)
        except OSError as e:
            self.analysis = {'enabled': True, 'state': 'failed', 'exit_code': None}
            print(f'US_ANALYSIS_LAUNCH_ERROR {e}', flush=True)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        # Request routes only, never upload bytes/headers/nonce.
        print(fmt % args, flush=True)

    def respond(self, status, body, content_type='application/json'):
        if isinstance(body, dict):
            body = json.dumps(body).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' https://tkndzbkcmgfailtxuwie.supabase.co; object-src 'none'; base-uri 'none'")
        self.end_headers()
        self.wfile.write(body)

    def status(self):
        p = self.server.destination
        verified = not p.is_symlink() and p.is_file() and file_identity(p) == (self.server.expected_size, self.server.expected_sha)
        return {'verified': verified, 'bytes': self.server.expected_size, 'sha256': self.server.expected_sha,
                'analysis': dict(self.server.analysis)}

    def do_GET(self):
        if self.path in ('/', '/?auto=1'):
            config = {'source_url': PUBLIC_SOURCE, 'serial': self.server.serial,
                      'bytes': self.server.expected_size, 'sha256': self.server.expected_sha,
                      'nonce': self.server.nonce}
            html = (ASSETS/'index.html').read_text().replace('__CONFIG_JSON__', json.dumps(config).replace('<', '\\u003c'))
            self.respond(200, html, 'text/html; charset=utf-8')
        elif self.path == '/app.js':
            self.respond(200, (ASSETS/'app.js').read_bytes(), 'application/javascript; charset=utf-8')
        elif self.path == '/api/status':
            self.respond(200, self.status())
        else:
            self.respond(404, {'error': 'Not found'})

    def do_POST(self):
        if self.path != '/api/import':
            self.respond(404, {'error': 'Not found'}); return
        supplied_nonce = self.headers.get('X-Import-Nonce', '').encode('utf-8')
        if not hmac.compare_digest(supplied_nonce, self.server.nonce.encode('ascii')):
            self.respond(403, {'error': 'Invalid preview import nonce'}); return
        if self.headers.get('Transfer-Encoding'):
            self.respond(400, {'error': 'Chunked bodies are not accepted'}); return
        try:
            n = int(self.headers.get('Content-Length', '-1'))
        except ValueError:
            n = -1
        if n != self.server.expected_size:
            self.respond(413, {'error': f'Expected exactly {self.server.expected_size} bytes'}); return
        temp_root = ROOT/'builddir/transfer'
        temp_root.mkdir(parents=True, exist_ok=True)
        try:
            self.connection.settimeout(60)
            with tempfile.TemporaryDirectory(prefix='browser-import-', dir=temp_root) as directory:
                source = Path(directory)/'verified-browser-source.bin'
                digest = hashlib.sha256()
                with source.open('wb') as out:
                    remaining = n
                    while remaining:
                        b = self.rfile.read(min(remaining, 65536))
                        if not b:
                            raise ValueError('Upload ended early')
                        out.write(b); digest.update(b); remaining -= len(b)
                if digest.hexdigest() != self.server.expected_sha:
                    raise ValueError('US content SHA-256 mismatch')
                created = stage(source, self.server.destination, self.server.expected_size, self.server.expected_sha)
            verified = self.status()
            if not verified['verified']:
                raise ValueError('Final target did not verify')
            self.server.elf_ready.set()
            self.respond(200, {**verified, 'created': created, 'whole_game_analysis_complete': False})
            print(f'US_ELF_READY bytes={n} sha256={self.server.expected_sha}', flush=True)
        except (ValueError, OSError) as e:
            self.respond(400, {'error': str(e)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8790)
    parser.add_argument('--analyze', action='store_true',
                        help='Run the fixed FASE1 --recomp workflow once after verified intake')
    args = parser.parse_args()
    server = ImportServer(('0.0.0.0', args.port))
    if args.analyze:
        server.enable_analysis()
    print('Private browser-assisted Supabase import ready; no game bytes served by this app.', flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
