#!/usr/bin/env python3
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
def fields(block):
    return dict(re.findall(r'^([A-Za-z_]+) = "([^"\n]*)"$',block,re.M))
lock={'package':[fields(block) for block in re.findall(r'\[\[package\]\]\n(.*?)(?=\n\[\[package\]\]|\Z)',(ROOT/'engine/Cargo.lock').read_text(),re.S)]}
registry=Path.home()/'.cargo/registry/src'
parts=['Rust dependency license notices for cs-tool-x\nGenerated from the locked crates.io sources available to this build.\n']
for package in sorted(lock['package'],key=lambda p:(p['name'],p['version'])):
    if not package.get('source','').startswith('registry+'): continue
    name=package['name'];version=package['version'];source=next(registry.glob(f'*/{name}-{version}'),None)
    parts.append(f'\n{"="*72}\n{name} {version}\nhttps://crates.io/crates/{name}/{version}\n')
    if source:
        manifest={'package':fields((source/'Cargo.toml').read_text())}
        parts.append('License expression: '+manifest.get('package',{}).get('license','See upstream source')+'\n')
        files=sorted({p for pattern in ['LICENSE*','COPYING*','NOTICE*'] for p in source.glob(pattern) if p.is_file() and p.stat().st_size<131072})
        for file in files:
            try: parts.append(f'\n--- {file.name} ---\n'+file.read_text())
            except UnicodeDecodeError: pass
    else: parts.append('Target-specific dependency; see the upstream crate for license text.\n')
(ROOT/'Resources/Rust-THIRD-PARTY-LICENSES.txt').write_text('\n'.join(line.rstrip() for line in '\n'.join(parts).splitlines())+'\n')
