#!/usr/bin/env python3
"""Reversible, local-only Finder icon metadata; release bundles stay untouched."""
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = Path('/Applications/cs-tool-x.app')
WORK = ROOT / '.local/dock-icon'
RECEIPT = WORK / 'receipt.json'
HELPER = WORK / 'file-icon'

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(262144), b''):
            h.update(block)
    return h.hexdigest()

def contents():
    result = {}
    for parent, directories, files in os.walk(APP / 'Contents', followlinks=False):
        for name in directories + files:
            p = Path(parent) / name
            if p.is_symlink():
                result[str(p.relative_to(APP))] = ['link', os.readlink(p)]
            elif p.is_file():
                result[str(p.relative_to(APP))] = ['file', digest(p)]
    return result

def attrs(path):
    # Python's os xattr functions are not available in every macOS Python build.
    names = subprocess.check_output(['/usr/bin/xattr', str(path)], text=True).splitlines()
    return {key: base64.b64encode(bytes.fromhex(subprocess.check_output(
        ['/usr/bin/xattr', '-p', '-x', key, str(path)], text=True))).decode('ascii')
        for key in names}

def metadata(path):
    return {'sha256': digest(path), 'attrs': {
        key: hashlib.sha256(base64.b64decode(value)).hexdigest()
        for key, value in attrs(path).items()}}

def run(*arguments):
    subprocess.run([str(x) for x in arguments], check=True)

def save(value):
    temporary = RECEIPT.with_suffix('.tmp')
    with temporary.open('w') as stream:
        os.chmod(temporary, 0o600)
        json.dump(value, stream, sort_keys=True)
    os.replace(temporary, RECEIPT)

def inspect(name):
    path = WORK / name
    run(HELPER, 'inspect', path)
    print('System icon read back to ' + str(path))

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ('apply', 'clear', 'inspect'):
        raise ValueError('Usage: local-file-icon.py apply|clear|inspect')
    if APP.is_symlink() or not APP.is_dir():
        raise ValueError('Expected the sole installed application at ' + str(APP))
    info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'cc.anjing.cs-tool-x':
        raise ValueError('Unexpected application identity')
    WORK.mkdir(parents=True, exist_ok=True)
    lock = os.open(WORK / 'lock', os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(lock, 'a') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        source = ROOT / 'tools/local-file-icon.swift'
        if not HELPER.exists() or HELPER.stat().st_mtime < source.stat().st_mtime:
            run('swiftc', source, '-o', HELPER)
        if sys.argv[1] == 'inspect':
            inspect('system-current.png')
            return
        icon = APP / 'Icon\r'
        current = contents()
        if sys.argv[1] == 'apply':
            if icon.exists():
                raise ValueError('Custom icon already exists; inspect or clear the recorded customization first')
            run('/usr/bin/codesign', '--verify', '--deep', '--strict', APP)
            record = {'version': info['CFBundleShortVersionString'],
                      'build': info['CFBundleVersion'], 'contents': current,
                      'beforeAttrs': attrs(APP), 'active': False}
            save(record)
            run(HELPER, 'apply')
            if contents() != current:
                raise ValueError('Application contents changed; do not claim integrity passed')
            record.update(active=True, afterAttrs=attrs(APP), icon=metadata(icon))
            save(record)
            inspect('system-custom.png')
            print('Applied local Finder metadata; signed Contents bytes unchanged. Strict codesign may report metadata detritus.')
        else:
            record = json.loads(RECEIPT.read_text())
            if not record['active'] or record['contents'] != current:
                raise ValueError('Receipt does not match this installation; refusing cleanup')
            if attrs(APP) != record['afterAttrs'] or metadata(icon) != record['icon']:
                raise ValueError('Icon metadata changed since application; refusing overwrite')
            run(HELPER, 'clear')
            run(HELPER, 'trash')
            original = record['beforeAttrs']
            allowed = {'com.apple.FinderInfo', 'com.apple.ResourceFork'}
            for key in set(attrs(APP)) | set(original):
                if key not in allowed:
                    if attrs(APP).get(key) != original.get(key):
                        raise ValueError('Unrelated application metadata changed')
                    continue
                if key in original:
                    run('/usr/bin/xattr', '-w', '-x', key,
                        base64.b64decode(original[key]).hex(), APP)
                elif key in attrs(APP):
                    run('/usr/bin/xattr', '-d', key, APP)
            if contents() != current or attrs(APP) != original:
                raise ValueError('Original state was not restored')
            run('/usr/bin/codesign', '--verify', '--deep', '--strict', APP)
            record['active'] = False
            save(record)
            print('Restored original icon metadata and strict signature verification passed.')

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
