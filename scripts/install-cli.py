#!/usr/bin/env python3
"""Expose the CLI inside the existing app; never install another application."""
from pathlib import Path
import argparse, os, shlex, sys, tempfile

MARKER='# cs-tool-x managed CLI launcher'

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--app',type=Path,default=Path('/Applications/cs-tool-x.app'))
    parser.add_argument('--bin-dir',type=Path,default=Path.home()/'.local/bin')
    args=parser.parse_args()
    target=args.app.resolve()/'Contents/MacOS/cs-tool-x'
    if not target.is_file() or not os.access(target,os.X_OK):
        sys.exit('CLI missing in this app. Update to 0.0.7 or later first.')
    folder=args.bin_dir.expanduser().absolute();folder.mkdir(parents=True,exist_ok=True)
    link=folder/'cs-tool-x'
    # 0.0.7 derives its askpass executable from argv[0]. Always exec an absolute
    # path: PATH invocation can otherwise supply only the bare command name.
    content=f'#!/bin/sh\n{MARKER}\nexec {shlex.quote(str(target))} "$@"\n'
    ours=link.is_symlink() and link.resolve()==target
    if link.exists() and not link.is_symlink():
        if link.is_file() and link.stat().st_uid==os.getuid():
            with link.open('rb') as existing:ours=MARKER.encode() in existing.read(256)
    if (link.exists() or link.is_symlink()) and not ours:
        sys.exit(f'Refusing to replace an existing unrelated command: {link}')
    descriptor,name=tempfile.mkstemp(prefix='.cs-tool-x-launcher-',dir=folder)
    temporary=Path(name)
    try:
        with os.fdopen(descriptor,'w') as handle:handle.write(content)
        temporary.chmod(0o755);temporary.replace(link)
    finally:temporary.unlink(missing_ok=True)
    print(f'Installed managed launcher: {link} -> {target}')
    if str(folder) not in os.environ.get('PATH','').split(os.pathsep):
        print(f'Add this directory to your shell PATH: {folder}')
    print('No second app, background service, shell startup changes or Keychain access.')
if __name__=='__main__':main()
