#!/usr/bin/env python3
"""Report actual locked components and upstream sources; no downloads or upgrades."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WANTED = {'sqlx', 'sqlx-mysql', 'sqlx-postgres', 'redis', 'reqwest', 'tokio'}
crates = []
for block in (ROOT / 'engine/Cargo.lock').read_text().split('[[package]]')[1:]:
    # Cargo-generated lockfile string fields are JSON-compatible for these values.
    fields = {key: json.loads(value) for key, value in re.findall(
        r'^(name|version|source|checksum)\s*=\s*("[^"\n]*")\s*$', block, re.MULTILINE)}
    if fields.get('name') not in WANTED:
        continue
    if fields.get('source') != 'registry+https://github.com/rust-lang/crates.io-index':
        raise SystemExit('Dependency source requires explicit review: ' + fields['name'])
    if not re.fullmatch(r'[0-9a-f]{64}', fields.get('checksum', '')):
        raise SystemExit('Missing locked crate checksum: ' + fields['name'])
    crates.append(fields)
if {item['name'] for item in crates} != WANTED:
    raise SystemExit('Required dependency is missing from Cargo.lock')
swift = json.loads((ROOT / 'Package.resolved').read_text())['pins']
print(json.dumps({
    'rust': sorted(crates, key=lambda item: item['name']),
    'swift': [{'name': item['identity'], 'source': item['location'], **item['state']}
              for item in swift],
    'runtime_driver_downloads': False,
    'key_components_only': True,
    'note': 'Library versions are not a database-server compatibility guarantee.'
}, ensure_ascii=False, indent=2))
