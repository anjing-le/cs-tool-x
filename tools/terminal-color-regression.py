#!/usr/bin/env python3
"""Bounded native renderer and real macOS ls PTY color checks; no user shell edits."""
from pathlib import Path
import errno,json,os,pty,select,subprocess,tempfile,time
root=Path(__file__).resolve().parents[1]
names=['Theme','PaperControls','WorkbenchWindow','WritingCursors','WritingCursorPreviewTheme','WritingDragCursor','Shell/TerminalAppearance']
output=root/'.local/terminal-color-regression';output.parent.mkdir(exist_ok=True)
objects=[*list((root/'.build/debug/ToolCore.build').glob('*.o')),*list((root/'.build/debug/SwiftTerm.build').glob('*.o'))]
subprocess.run(['swiftc','-parse-as-library','-I',str(root/'.build/debug/Modules'),*[str(root/'Sources/CSToolX'/(n+'.swift')) for n in names],*map(str,objects),str(root/'tools/terminal-color-regression.swift'),'-o',str(output)],check=True,timeout=60)
with tempfile.TemporaryDirectory(prefix='cs-tool-x-color-') as temporary:
 directory=Path(temporary);environment=directory/'environment.json'
 subprocess.run(['python3',str(root/'tools/run-ui-regression.py'),str(output),str(environment)],check=True,timeout=65)
 (directory/'folder').mkdir();(directory/'file.txt').write_text('fixture\n')
 master,slave=pty.openpty()
 process=subprocess.Popen(['/bin/ls','-l',str(directory)],env=json.loads(environment.read_text()),stdin=subprocess.DEVNULL,stdout=slave,stderr=slave)
 os.close(slave);data=b'';deadline=time.monotonic()+5
 try:
  while time.monotonic()<deadline:
   ready,_,_=select.select([master],[],[],0.1)
   if ready:
    try:chunk=os.read(master,4096)
    except OSError as error:
     if error.errno==errno.EIO:break
     raise
    if not chunk:break
    data+=chunk
    if len(data)>16384:raise RuntimeError('Fixture output exceeded 16 KiB')
   elif process.poll() is not None:break
  process.wait(timeout=1)
  assert process.returncode==0 and b'\x1b[' in data and b'folder' in data, 'Local ls must emit ANSI colors on a PTY'
 finally:
  os.close(master)
  if process.poll() is None:process.kill();process.wait()
print('PASS: real macOS ls emits directory color with actual local launch defaults, under byte/time budget')
