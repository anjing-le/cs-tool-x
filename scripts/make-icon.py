#!/usr/bin/env python3
"""Package the supplied artwork as all standard macOS icon representations."""
from pathlib import Path
import subprocess, tempfile

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'assets/AppIcon.png'
with tempfile.TemporaryDirectory(prefix='cs-tool-x-icon-') as temporary:
    iconset = Path(temporary) / 'AppIcon.iconset'
    iconset.mkdir()
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = '@2x' if scale == 2 else ''
            output = iconset / f'icon_{size}x{size}{suffix}.png'
            subprocess.run(['sips', '-z', str(size * scale), str(size * scale),
                            str(source), '--out', str(output)], check=True,
                           stdout=subprocess.DEVNULL)
    subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o',
                    str(ROOT / 'Resources/AppIcon.icns')], check=True)
print('Packaged supplied artwork at 16–1024 pixels; original artwork preserved.')
