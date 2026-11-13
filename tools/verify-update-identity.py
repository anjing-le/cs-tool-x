#!/usr/bin/env python3
"""Ad-hoc app integrity + stable bundle and Ed25519 update identity, without Keychain."""
from pathlib import Path
import plistlib,subprocess,sys

def inspect(app):
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    with (app/'Contents/Info.plist').open('rb') as source: info=plistlib.load(source)
    if info.get('CFBundleIdentifier')!='cc.anjing.cs-tool-x': raise ValueError('Unexpected bundle identifier')
    return info
if __name__=='__main__':
    try:
        if len(sys.argv)!=3: raise ValueError('Usage: verify-update-identity.py previous.app candidate.app')
        old,new=(inspect(Path(path)) for path in sys.argv[1:])
        for key in ['CFBundleIdentifier','CFBundleExecutable','SUPublicEDKey','SUFeedURL']:
            if not old.get(key) or old[key]!=new.get(key): raise ValueError('Update identity changed: '+key)
        if int(new['CFBundleVersion'])<=int(old['CFBundleVersion']): raise ValueError('Build must increase')
        print('PASS: valid app integrity, stable bundle/executable/Ed25519 key/feed, increasing build. No certificate identity claim.')
    except (ValueError,OSError,subprocess.CalledProcessError) as error: sys.exit(str(error))
