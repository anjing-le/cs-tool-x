#!/usr/bin/env python3
"""Personal-device installation only. Never copies cursor artwork into an app or repository."""
from pathlib import Path
import argparse,hashlib,json,shutil
parser=argparse.ArgumentParser();parser.add_argument('--development',action='store_true');args=parser.parse_args()
root=Path(__file__).resolve().parents[1];source=root/'.local/cursor-preview'
manifest=json.loads((source/'cursors.json').read_text())
assert manifest.get('personalPreviewOnly') is True
for key in ['arrow','pointer']:
    spec=manifest[key]
    assert spec['file'] in ['arrow.png','pointer.png']
    assert hashlib.sha256((source/spec['file']).read_bytes()).hexdigest()==spec['sha256']
name='cs-tool-x-dev' if args.development else 'cs-tool-x'
destination=Path.home()/'Library/Application Support'/name/'Cursors'
destination.mkdir(parents=True,exist_ok=True,mode=0o700)
for filename in ['arrow.png','pointer.png','cursors.json','NOTICE.txt']:
    target=destination/filename
    shutil.copyfile(source/filename,target);target.chmod(0o600)
print('Installed private cursor pair in user Application Support; app/release bundles contain no private artwork.')
