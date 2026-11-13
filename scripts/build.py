#!/usr/bin/env python3
"""Build a native app without Keychain access; OTA authenticity uses Ed25519."""
from pathlib import Path
import argparse, base64, hashlib, json, os, plistlib, re, shutil, subprocess, sys, tempfile
ROOT=Path(__file__).resolve().parents[1]
BUNDLE='cc.anjing.cs-tool-x'
FEED='https://github.com/anjing-le/cs-tool-x/releases/latest/download/appcast.xml'

def run(args,**kwargs):
    return subprocess.run(list(map(str,args)),check=True,**kwargs)

def signing_key_file():
    path=Path(os.environ.get('CSTOOLX_UPDATE_KEY_FILE',str(Path.home()/'Library/Application Support/cs-tool-x-publisher/update-signing.key')))
    resolved=path.resolve()
    if resolved.is_relative_to(ROOT) or path.is_symlink() or not path.is_file():
        raise ValueError('OTA signing file must be a regular file outside the repository.')
    metadata=path.stat()
    if metadata.st_uid != os.getuid() or metadata.st_mode & 0o777 != 0o600:
        raise ValueError('OTA signing file must be owned by the current user with mode 0600.')
    if len(base64.b64decode(path.read_text().strip(),validate=True)) != 32:
        raise ValueError('OTA signing file must contain a valid Ed25519 seed.')
    return resolved

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--development',action='store_true',help='Disable OTA and use a separate development bundle identifier.')
    parser.add_argument('--configuration',choices=['debug','release'],default='release')
    parser.add_argument('--output',type=Path,default=ROOT/'dist')
    args=parser.parse_args()
    metadata=json.loads((ROOT/'version.json').read_text());version=metadata['version'];build=str(metadata['build'])
    if not re.fullmatch(r'\d+\.\d+\.\d+',version) or not re.fullmatch(r'[1-9]\d*',build): raise ValueError('Invalid version/build.')
    identity='-'
    key=(ROOT/'Resources/update-public-key.txt').read_text().strip()
    if len(base64.b64decode(key,validate=True))!=32: raise ValueError('Invalid OTA public key.')
    if not args.development: signing_key_file()
    run(['cargo','build','--manifest-path',ROOT/'engine/Cargo.toml']+(['--release'] if args.configuration=='release' else []))
    run(['python3',ROOT/'scripts/collect-licenses.py'])
    run(['swift','build','--disable-keychain','-c',args.configuration,'--product','CSToolX'],cwd=ROOT)
    bin_dir=Path(subprocess.check_output(['swift','build','--disable-keychain','-c',args.configuration,'--show-bin-path'],cwd=ROOT,text=True).strip())
    framework=ROOT/'.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
    args.output.mkdir(parents=True,exist_ok=True)
    app=args.output/('cs-tool-x Dev.app' if args.development else 'cs-tool-x.app')
    if app.is_symlink(): raise ValueError('Refusing symbolic-link output bundle.')
    if app.exists(): shutil.rmtree(app)
    contents=app/'Contents';(contents/'MacOS').mkdir(parents=True);(contents/'Helpers').mkdir();(contents/'Resources').mkdir();(contents/'Frameworks').mkdir()
    shutil.copy2(bin_dir/'CSToolX',contents/'MacOS/CSToolX')
    shutil.copy2(ROOT/'engine/target'/args.configuration/'cs-tool-engine',contents/'Helpers/cs-tool-engine')
    run(['/usr/bin/ditto',framework,contents/'Frameworks/Sparkle.framework'])
    # SwiftTerm 1.20 probes Bundle.main.resourceURL for its Metal resource bundle.
    for bundle in bin_dir.glob('SwiftTerm_*.bundle'): shutil.copytree(bundle,contents/'Resources'/bundle.name)
    for resource in (ROOT/'Resources').iterdir():
        if resource.is_file(): shutil.copy2(resource,contents/'Resources'/resource.name)
    bundle_id=BUNDLE+'.dev' if args.development else BUNDLE
    info={'CFBundleName':'cs-tool-x','CFBundleDisplayName':'cs-tool-x Dev' if args.development else 'cs-tool-x','CFBundleIdentifier':bundle_id,
          'CFBundleExecutable':'CSToolX','CFBundlePackageType':'APPL','CFBundleIconFile':'AppIcon.icns','CFBundleShortVersionString':version,'CFBundleVersion':build,
          'LSMinimumSystemVersion':'14.0','LSApplicationCategoryType':'public.app-category.developer-tools','NSHighResolutionCapable':True,
          'CSToolXUpdatesEnabled':not args.development,'SUEnableAutomaticChecks':not args.development,'SUScheduledCheckInterval':3600,
          'SUAutomaticallyUpdate':False,'SUAllowsAutomaticUpdates':False,'SUEnableSystemProfiling':False,'SUShowReleaseNotes':False,
          'SUVerifyUpdateBeforeExtraction':True,'SURequireSignedFeed':True,'SUSignedFeedFailureExpirationInterval':0}
    if not args.development: info.update(SUFeedURL=FEED,SUPublicEDKey=key)
    with (contents/'Info.plist').open('wb') as file: plistlib.dump(info,file)
    common=['--force','--sign',identity,'--options','0','--timestamp=none']
    fw=contents/'Frameworks/Sparkle.framework'
    components=list((fw/'Versions/Current/XPCServices').glob('*.xpc'))+[fw/'Versions/Current/Updater.app',fw/'Versions/Current/Autoupdate',fw]
    for component in components: run(['/usr/bin/codesign',*common,'--preserve-metadata=identifier,entitlements',component])
    run(['/usr/bin/codesign',*common,'--identifier',bundle_id+'.engine',contents/'Helpers/cs-tool-engine'])
    run(['/usr/bin/codesign',*common,'--identifier',bundle_id,app])
    run(['/usr/bin/codesign','--verify','--deep','--strict',app])
    run(['/usr/bin/plutil','-lint',contents/'Info.plist'])
    print(f'Built {app} · {version} ({build}) · OTA={not args.development}')
    print('Ad-hoc application integrity signature; signed Ed25519 feed and archive provide OTA authenticity. No Keychain access.')
if __name__=='__main__':
    try: main()
    except (ValueError,OSError,subprocess.CalledProcessError,subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
