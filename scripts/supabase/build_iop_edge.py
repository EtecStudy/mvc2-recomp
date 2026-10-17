#!/usr/bin/env python3
"""Bundle the tested parser + Edge entry; secrets/output are local ignored files."""
import json
import os
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[2]
if len(sys.argv) != 2:
    raise SystemExit('Usage: build_iop_edge.py PATH_TO_LOCAL_TEMP_TOKEN_FILE')
token = Path(sys.argv[1]).read_text().strip()
if not re.fullmatch(r'[A-Za-z0-9_-]{32,128}', token):
    raise SystemExit('Invalid temporary token format')
parser = (root / 'scripts/supabase/iop_inventory.mjs').read_text()
parser = re.sub(r'^export ', '', parser, flags=re.M)
entry = (root / 'scripts/supabase/iop_edge_entry.ts').read_text()
assert entry.count("'__TEMPORARY_STAGE_TOKEN__'") == 1
entry = entry.replace("'__TEMPORARY_STAGE_TOKEN__'", json.dumps(token))
out = root / 'builddir/transfer/iop-edge-bundle.ts'
out.parent.mkdir(parents=True, exist_ok=True)
fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as f:
    f.write(parser + '\n' + entry)
os.chmod(out, 0o600)
print(f'Wrote ignored temporary deployment bundle: {out}')
