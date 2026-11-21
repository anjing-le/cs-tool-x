#!/usr/bin/env python3
import argparse, json, os, pathlib, subprocess, tempfile, time
p=argparse.ArgumentParser();p.add_argument('--binary',required=True);p.add_argument('--worker',required=True);a=p.parse_args()
binary=str(pathlib.Path(a.binary).resolve());worker=str(pathlib.Path(a.worker).resolve())
def render(text,success=True):
    result=subprocess.run([worker],input=text.encode(),capture_output=True,timeout=8)
    assert (result.returncode==0)==success,(result.returncode,result.stderr[:200])
    return result.stdout.decode()
assert render('')==''
source='# 标题\n\n**粗体** 和 *斜体*，`code`。\n\n> 引用\n\n- [x] done\n- item\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```swift\nlet x = 1\n```\n\n~~删除~~\n'
html=render(source)
for tag in ['<h1>标题','<strong>粗体','<em>斜体','<blockquote>','<table>','type="checkbox"','language-swift','<del>删除']:assert tag in html,tag
html=render('<script>alert(1)</script>\n\n[x](javascript:alert(1))\n\n![image](https://example.invalid/p.png)')
assert '<script>' not in html and 'href="javascript:' not in html
render('a'*(4*1024*1024+1),False)
render('a\n\n'*16000,False) # exceeds node budget rather than rendering an enormous DOM
with tempfile.TemporaryDirectory() as d:
    path=pathlib.Path(d)/'large.txt';original=('你好 hello\n'*1024*256).encode();path.write_bytes(original)
    result=subprocess.run([binary,'text','inspect',str(path)],capture_output=True,text=True,timeout=20)
    body=json.loads(result.stdout);assert result.returncode==0 and body['ok']
    assert body['result']['bytes']==len(original) and path.read_bytes()==original
    path.write_text(source)
    result=subprocess.run([binary,'text','preview',str(path)],capture_output=True,text=True,timeout=12)
    body=json.loads(result.stdout);assert body['ok'] and 'default-src \'none\'' in body['result']['html']
    fifo=pathlib.Path(d)/'fifo';os.mkfifo(fifo)
    result=subprocess.run([worker,'--read-text',str(fifo)],capture_output=True,timeout=3);assert result.returncode!=0
print('PASS: CommonMark/GFM, empty/Unicode input, raw HTML/unsafe links omitted, input/node budgets, large readonly UTF-8 import and CLI preview; no file changes')
