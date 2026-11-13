#!/usr/bin/env python3
"""Publisher-side verification of the actual public GitHub Release assets."""
from pathlib import Path
import argparse, base64, hashlib, subprocess, sys
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('version');parser.add_argument('--folder',type=Path)
    args=parser.parse_args();version=args.version
    import re
    if not re.fullmatch(r'\d+\.\d+\.\d+',version): raise ValueError('Invalid version')
    folder=args.folder or ROOT/'.local'/f'published-{version}'
    folder.mkdir(parents=True,exist_ok=True)
    archive_name=f'cs-tool-x-{version}.zip'
    for filename in [archive_name,archive_name+'.sha256','appcast.xml']:
        subprocess.run(['gh','release','download','v'+version,'--repo','anjing-le/cs-tool-x','--pattern',filename,'--dir',str(folder)],check=True)
    expected=(folder/(archive_name+'.sha256')).read_text().split()
    archive=folder/archive_name
    if len(expected)!=2 or expected[1]!=archive_name or hashlib.sha256(archive.read_bytes()).hexdigest()!=expected[0]: raise ValueError('Published checksum mismatch')
    item=ET.parse(folder/'appcast.xml').getroot().find('channel/item')
    ns='{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    if item is None or item.findtext(ns+'shortVersionString')!=version: raise ValueError('Published feed version mismatch')
    enclosure=item.find('enclosure')
    if enclosure is None: raise ValueError('Missing enclosure')
    url=f'https://github.com/anjing-le/cs-tool-x/releases/download/v{version}/{archive_name}'
    if enclosure.get('url')!=url or int(enclosure.get('length','0'))!=archive.stat().st_size: raise ValueError('Published enclosure mismatch')
    signature=enclosure.get(ns+'edSignature','')
    if len(base64.b64decode(signature,validate=True))!=64: raise ValueError('Invalid published signature')
    subprocess.run(['swift',str(ROOT/'scripts/verify-update.swift'),str(archive),signature,str(ROOT/'Resources/update-public-key.txt')],check=True)
    signer=ROOT/'.build/artifacts/sparkle/Sparkle/bin/sign_update'
    sys.path.insert(0,str(ROOT/'scripts'))
    from build import signing_key_file
    subprocess.run([str(signer),'--ed-key-file',str(signing_key_file()),'--verify',str(folder/'appcast.xml')],check=True)
    print('PASS: actual public ZIP, SHA-256, signed feed, version, length and enclosure URL. Installation remains user acceptance.')
if __name__=='__main__':
    try: main()
    except (ValueError,OSError,subprocess.CalledProcessError) as error: sys.exit(str(error))
