#!/usr/bin/env python3
"""Restore hash-pinned source dependencies and emit an offline CMake cache."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile

ROOT = Path(__file__).resolve().parents[1]


def restore():
    meta = json.loads((ROOT/'tools/analyzer_deps.json').read_text())
    archive = ROOT/meta['archive']
    if archive.stat().st_size != meta['bytes'] or hashlib.sha256(archive.read_bytes()).hexdigest() != meta['sha256']:
        raise ValueError('Dependency archive size/SHA-256 mismatch; refusing extraction')
    dest = ROOT/'builddir/analyzer-deps'
    if dest.is_symlink() or not dest.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError('Unsafe dependency cache root')
    dest.mkdir(parents=True, exist_ok=True)
    allowed = {name+'-src' for name in meta['commits']}
    with tarfile.open(archive, 'r:gz') as tar:
        for member in tar.getmembers():
            path = PurePosixPath(member.name)
            if (path.is_absolute() or '..' in path.parts or not path.parts
                    or path.parts[0] not in allowed or not (member.isfile() or member.isdir())):
                raise ValueError(f'Unsafe dependency archive member: {member.name}')
            # Check existing parents too, so an altered cache cannot redirect writes.
            target = dest/member.name
            if target.is_symlink() or not target.resolve().is_relative_to(dest.resolve()):
                raise ValueError(f'Unsafe existing dependency path: {target}')
        tar.extractall(dest)  # Every member and destination validated above; no links/devices.
    lines = ['# Generated from verified local source archive; no network fetches.']
    for name in sorted(meta['commits']):
        path = dest/(name+'-src')
        sentinel = 'include/rabbitizer.h' if name == 'rabbitizer' else 'CMakeLists.txt'
        if not (path/sentinel).is_file():
            raise ValueError(f'Missing source sentinel: {name}/{sentinel}')
        lines.append(f'set(FETCHCONTENT_SOURCE_DIR_{name.upper()} {json.dumps(path.as_posix())} CACHE PATH "" FORCE)')
    lines.append('set(FETCHCONTENT_FULLY_DISCONNECTED ON CACHE BOOL "" FORCE)')
    output = ROOT/'builddir/analyzer-deps.cmake'
    output.write_text('\n'.join(lines)+'\n')
    print(f'Offline dependency cache ready: {output}')


if __name__ == '__main__':
    restore()
