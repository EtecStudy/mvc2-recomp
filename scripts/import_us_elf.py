#!/usr/bin/env python3
"""Copy an owner-supplied attachment into the US working path, without overwrite.

The CLI has no digest override: identity comes from scripts/target.sh. Source
bytes are never moved/modified. Wrong-size/hash files never become the target.
"""
import argparse
import hashlib
import os
from pathlib import Path
import re
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def target_identity():
    text = (ROOT/'scripts/target.sh').read_text()
    def value(name, pattern):
        matches = re.findall(rf'^{name}="({pattern})"$', text, re.M)
        if len(matches) != 1:
            raise ValueError(f'Missing/ambiguous pinned identity: {name}')
        return matches[0]
    serial = value('MVC2_TARGET_SERIAL', r'SLUS_204\.86')
    sizes = re.findall(r'^MVC2_TARGET_STORAGE_BYTES=(\d+)$', text, re.M)
    if len(sizes) != 1 or int(sizes[0]) <= 0:
        raise ValueError('Missing/ambiguous pinned target size')
    size = int(sizes[0])
    sha = value('MVC2_TARGET_SHA256', r'[0-9a-f]{64}')
    return serial, size, sha


def file_identity(path):
    count = 0
    sha = hashlib.sha256()
    with path.open('rb') as stream:
        while b := stream.read(1024*1024):
            count += len(b)
            sha.update(b)
    return count, sha.hexdigest()


def stage(source, destination, expected_size, expected_sha):
    source, destination = Path(source), Path(destination)
    if not source.is_file():
        raise ValueError('Source must be an existing regular file')
    if source.stat().st_size != expected_size:
        raise ValueError(f'Wrong size: expected {expected_size} bytes')
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.incoming-us-', dir=destination.parent)
    tmp = Path(temporary)
    try:
        count = 0
        digest = hashlib.sha256()
        with os.fdopen(fd, 'wb') as out, source.open('rb') as stream:
            while b := stream.read(1024*1024):
                count += len(b)
                if count > expected_size:
                    raise ValueError('Source grew during copy; import refused')
                digest.update(b)
                out.write(b)
            out.flush()
            os.fsync(out.fileno())
        if count != expected_size or digest.hexdigest() != expected_sha:
            raise ValueError('Content SHA-256/size mismatch; import refused')
        if file_identity(tmp) != (expected_size, expected_sha):
            raise ValueError('Independent destination verification failed')
        # Hard-link publication is atomic and cannot overwrite a concurrently
        # created destination. The temporary file is on the same filesystem.
        try:
            os.link(tmp, destination)
            return True
        except FileExistsError:
            if destination.is_symlink() or not destination.is_file():
                raise ValueError('Existing target is not a regular non-symlink file')
            if file_identity(destination) != (expected_size, expected_sha):
                raise ValueError('Refusing to overwrite an existing different target')
            return False
    finally:
        tmp.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('attachment', type=Path, help='Path of the owner-supplied US ELF attachment')
    args = parser.parse_args()
    try:
        serial, size, sha = target_identity()
        destination = ROOT/'game/working'/serial
        created = stage(args.attachment, destination, size, sha)
    except (ValueError, OSError) as e:
        parser.exit(1, f'US ELF import refused: {e}\n')
    print(f"{'Imported' if created else 'Already verified'}: {destination}")
    print(f'SHA-256: {sha}; source preserved; no Storage/GitHub upload performed')


if __name__ == '__main__':
    main()
