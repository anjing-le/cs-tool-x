#!/usr/bin/env python3
"""Bound an offscreen component test; capture its own process stack if it stalls."""
import os,signal,subprocess,sys
from pathlib import Path
if len(sys.argv)<2:raise SystemExit('Expected a component executable and optional arguments')
print('Starting offscreen UI check:',Path(sys.argv[1]).name,flush=True)
p=subprocess.Popen(sys.argv[1:],start_new_session=True)
try:
    code=p.wait(timeout=60)
except subprocess.TimeoutExpired:
    print('UI check exceeded 60 seconds; sampling this test process before stopping it.',flush=True)
    folder=Path('.local');folder.mkdir(exist_ok=True);stack=folder/(Path(sys.argv[1]).name+'.sample.txt')
    try:
        subprocess.run(['/usr/bin/sample',str(p.pid),'2','1','-file',str(stack)],timeout=8,check=False)
        if stack.exists():print('\n'.join(stack.read_text(errors='replace').splitlines()[:140]),flush=True)
    except (OSError,subprocess.TimeoutExpired) as error:print(type(error).__name__,flush=True)
    os.killpg(p.pid,signal.SIGKILL);p.wait();code=1
raise SystemExit(code)
