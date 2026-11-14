#!/usr/bin/env python3
"""Check managed PATH launchers using disposable fake application paths."""
from pathlib import Path
import json, os, subprocess, sys, tempfile

installer=Path(__file__).resolve().parents[1]/'scripts/install-cli.py'
with tempfile.TemporaryDirectory(prefix='cs-tool-x-launcher-') as temporary:
    root=Path(temporary);app=root/"space ' app.app";binary=app/'Contents/MacOS/cs-tool-x'
    binary.parent.mkdir(parents=True)
    binary.write_text(f'#!{sys.executable}\nimport sys,json\nprint(json.dumps(sys.argv))\n')
    binary.chmod(0o755);folder=root/'bin';folder.mkdir()
    command=[sys.executable,str(installer),'--app',str(app),'--bin-dir',str(folder)]
    link=folder/'cs-tool-x'
    def install(status=0):
        result=subprocess.run(command,capture_output=True,text=True,timeout=5)
        assert result.returncode==status,(result.stdout,result.stderr)
    def invoke():
        env=dict(os.environ,PATH=str(folder)+os.pathsep+os.environ.get('PATH',''))
        result=subprocess.run(['cs-tool-x','arg with spaces',"literal'quote"],env=env,capture_output=True,text=True,check=True,timeout=5)
        assert json.loads(result.stdout)==[str(binary.resolve()),'arg with spaces',"literal'quote"]
    install();assert not link.is_symlink() and os.access(link,os.X_OK);invoke()
    install();invoke()
    link.unlink();link.symlink_to(binary);install();assert not link.is_symlink();invoke()
    link.unlink();link.write_text('unrelated command');install(1);assert link.read_text()=='unrelated command'
    link.unlink();link.symlink_to(root/'unrelated-missing');install(1);assert link.is_symlink()
print('PASS: PATH invocation uses absolute executable; quoting, arguments, repeat install, old symlink migration and unrelated-command refusal')
