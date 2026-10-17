#!/usr/bin/env python3
"""Normalize a Ghidra export, modifying only [general], with TOML validation."""
import json
from pathlib import Path
import re
import sys
import tomllib


def normalize(path: Path, output: Path) -> None:
    original = path.read_text()
    parsed = tomllib.loads(original)
    if not isinstance(parsed.get('general'), dict):
        raise ValueError('Missing [general] section; refusing codegen')
    section = re.search(r'^\[general\][ \t]*\r?\n(?P<body>.*?)(?=^\[|\Z)',
                        original, re.M | re.S)
    if not section:
        raise ValueError('Expected explicit [general] header')
    body = section['body']
    values = {
        'low_memory_mode': 'true',
        'output_worker_threads': '1',
        'single_file_output': 'false',
        'output': json.dumps(str(output.resolve())),
    }
    for key, value in values.items():
        pattern = rf'^[ \t]*{key}[ \t]*=.*$'
        if re.search(pattern, body, re.M):
            body = re.sub(pattern, lambda _: f'{key} = {value}', body, flags=re.M)
        else:
            body = f'{key} = {value}\n' + body
    text = original[:section.start('body')] + body + original[section.end('body'):]
    validated = tomllib.loads(text)
    assert validated['general']['low_memory_mode'] is True
    assert validated['general']['output_worker_threads'] == 1
    assert validated['general']['single_file_output'] is False
    assert validated['general']['output'] == str(output.resolve())
    path.write_text(text)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: normalize_recomp_config.py CONFIG.toml OUTPUT_DIRECTORY')
    normalize(Path(sys.argv[1]), Path(sys.argv[2]))
    print(f'Normalized {sys.argv[1]} (low memory, one worker, split C++, output={sys.argv[2]})')
