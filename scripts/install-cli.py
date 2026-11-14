#!/usr/bin/env python3
"""Expose the CLI inside the existing app; never install another application."""
from pathlib import Path
import argparse, os, sys

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
    if link.is_symlink() and link.resolve()==target:
        print(f'Already installed: {link} -> {target}')
    elif link.exists() or link.is_symlink():
        sys.exit(f'Refusing to replace an existing unrelated command: {link}')
    else:
        link.symlink_to(target);print(f'Installed: {link} -> {target}')
    if str(folder) not in os.environ.get('PATH','').split(os.pathsep):
        print(f'Add this directory to your shell PATH: {folder}')
    print('No second app, background service, shell startup changes or Keychain access.')
if __name__=='__main__':main()
