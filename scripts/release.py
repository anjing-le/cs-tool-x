#!/usr/bin/env python3
"""Prepare verifiable Sparkle assets. Publishing is a separate explicit command."""
from pathlib import Path
import argparse, base64, datetime, email.utils, hashlib, plistlib, re, subprocess, sys
import xml.etree.ElementTree as ET
from build import ROOT, BUNDLE, FEED, run, signing_key_file

def inspect(app):
    run(['/usr/bin/codesign','--verify','--deep','--strict',app])
    with (app/'Contents/Info.plist').open('rb') as f: info=plistlib.load(f)
    expected={'CFBundleIdentifier':BUNDLE,'CFBundleExecutable':'CSToolX','CSToolXUpdatesEnabled':True,'SUFeedURL':FEED,
              'SUPublicEDKey':(ROOT/'Resources/update-public-key.txt').read_text().strip(),
              'SUVerifyUpdateBeforeExtraction':True,'SURequireSignedFeed':True,'SUSignedFeedFailureExpirationInterval':0,'SUAllowsAutomaticUpdates':False}
    for key,value in expected.items():
        if info.get(key)!=value: raise ValueError(f'Release configuration mismatch: {key}')
    return info

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--app',type=Path,default=ROOT/'dist/cs-tool-x.app')
    parser.add_argument('--previous',type=Path)
    parser.add_argument('--output',type=Path,default=ROOT/'dist/releases')
    args=parser.parse_args();app=args.app.resolve();info=inspect(app)
    version=info['CFBundleShortVersionString'];build=info['CFBundleVersion']
    if not re.fullmatch(r'\d+\.\d+\.\d+',version) or not re.fullmatch(r'[1-9]\d*',build): raise ValueError('Invalid release version/build.')
    if version!='0.0.1':
        if not args.previous: raise ValueError('After 0.0.1, --previous must point to the previous signed app for identity verification.')
        run(['python3',ROOT/'tools/verify-update-identity.py',args.previous,app])
        with (args.previous/'Contents/Info.plist').open('rb') as f: old=plistlib.load(f)
        if tuple(map(int,version.split('.'))) <= tuple(map(int,old['CFBundleShortVersionString'].split('.'))): raise ValueError('Marketing version must increase too.')
    folder=args.output.resolve();folder.mkdir(parents=True,exist_ok=True)
    archive=folder/f'cs-tool-x-{version}.zip';feed=folder/'appcast.xml'
    if archive.exists() or feed.exists(): raise ValueError('Release output already exists. Use a new version/output folder.')
    signer=ROOT/'.build/artifacts/sparkle/Sparkle/bin/sign_update'
    run(['/usr/bin/ditto','-c','-k','--sequesterRsrc','--keepParent',app,archive])
    key_file=signing_key_file()
    signature=subprocess.check_output([str(signer),'--ed-key-file',str(key_file),'-p',str(archive)],text=True).strip()
    if len(base64.b64decode(signature,validate=True))!=64: raise ValueError('Invalid Ed25519 signature.')
    run(['swift',ROOT/'scripts/verify-update.swift',archive,signature,ROOT/'Resources/update-public-key.txt'])
    nsurl='http://www.andymatuschak.org/xml-namespaces/sparkle';ET.register_namespace('sparkle',nsurl);ns='{'+nsurl+'}'
    rss=ET.Element('rss',{'version':'2.0'});channel=ET.SubElement(rss,'channel')
    ET.SubElement(channel,'title').text='cs-tool-x';ET.SubElement(channel,'link').text='https://github.com/anjing-le/cs-tool-x'
    ET.SubElement(channel,'description').text='cs-tool-x stable updates'
    item=ET.SubElement(channel,'item');ET.SubElement(item,'title').text='cs-tool-x '+version
    ET.SubElement(item,ns+'version').text=build;ET.SubElement(item,ns+'shortVersionString').text=version
    ET.SubElement(item,ns+'minimumSystemVersion').text=info['LSMinimumSystemVersion']
    architectures=subprocess.check_output(['/usr/bin/lipo','-archs',str(app/'Contents/MacOS/CSToolX')],text=True).split()
    if architectures==['arm64']: ET.SubElement(item,ns+'hardwareRequirements').text='arm64'
    elif set(architectures)!={'arm64','x86_64'}: raise ValueError('Unsupported architecture set.')
    ET.SubElement(item,'pubDate').text=email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc),usegmt=True)
    ET.SubElement(item,'enclosure',{'url':f'https://github.com/anjing-le/cs-tool-x/releases/download/v{version}/{archive.name}',
                                  'length':str(archive.stat().st_size),'type':'application/octet-stream',ns+'edSignature':signature})
    tree=ET.ElementTree(rss);ET.indent(tree,space='  ');tree.write(feed,encoding='utf-8',xml_declaration=True)
    run([signer,'--ed-key-file',key_file,feed])
    run([signer,'--ed-key-file',key_file,'--verify',feed])
    (folder/(archive.name+'.sha256')).write_text(hashlib.sha256(archive.read_bytes()).hexdigest()+'  '+archive.name+'\n')
    # Verify negative cases using only public material; never export signing secrets.
    with archive.open('rb') as f: prefix=f.read(1024)
    tampered=folder/'.tampered-probe';tampered.write_bytes(prefix+b'tampered')
    try:
        check=subprocess.run(['swift',str(ROOT/'scripts/verify-update.swift'),str(tampered),signature,str(ROOT/'Resources/update-public-key.txt')],capture_output=True)
        if check.returncode==0: raise ValueError('Tampered archive unexpectedly passed verification.')
    finally: tampered.unlink(missing_ok=True)
    modified=folder/'.tampered-feed.xml'
    original_feed=feed.read_bytes()
    needle=f'<sparkle:version>{build}</sparkle:version>'.encode()
    if original_feed.count(needle)!=1: raise ValueError('Cannot locate signed feed version for tamper probe.')
    modified.write_bytes(original_feed.replace(needle,f'<sparkle:version>{int(build)+1}</sparkle:version>'.encode(),1))
    try:
        check=subprocess.run([str(signer),'--ed-key-file',str(key_file),'--verify',str(modified)],capture_output=True)
        if check.returncode==0: raise ValueError('Tampered feed unexpectedly passed verification.')
    finally: modified.unlink(missing_ok=True)
    print(f'Prepared and verified {archive.name}, checksum and signed appcast. Tamper probes rejected. Nothing uploaded.')
if __name__=='__main__':
    try: main()
    except (ValueError,OSError,subprocess.CalledProcessError) as error: sys.exit(str(error))
