#!/usr/bin/env python3
"""Exercise the public CLI, actual isolation deadline, stream hashing, and every catalog mode."""
import argparse, hashlib, json, pathlib, subprocess, tempfile, time
p=argparse.ArgumentParser();p.add_argument('--binary',required=True);args=p.parse_args()
binary=str(pathlib.Path(args.binary).resolve())
def call(request,ok=True):
    result=subprocess.run([binary,'toolbox','run'],input=json.dumps(request),text=True,capture_output=True,timeout=40)
    body=json.loads(result.stdout)
    assert body['ok']==ok and (result.returncode==0)==ok,(request['tool'],result.returncode,body)
    return body.get('result')
catalog=json.loads(subprocess.check_output([binary,'toolbox','list']))['result']
assert len(catalog)==10
samples={'case':'Hello World','lines':'a\na\nb','srt':'1\n00:00:00,000 --> 00:00:01,000\nhello','diff':'a\nb','timestamp':'0','codec':'hello','json':'{"a":1}','regex':'a12','hash':'abc','random':''}
for item in catalog:
    for mode in item['modes']:
        text=samples[item['id']];other=''
        if item['id']=='timestamp' and mode.startswith('date-'):text='1970-01-01T00:00:00Z'
        if item['id']=='codec' and mode.endswith('decode'):text={'base64-decode':'aGVsbG8=','url-decode':'hello%20world','hex-decode':'68656c6c6f'}[mode]
        if mode=='json-unescape':text='"hello"'
        if item['id']=='regex':other='(\\d+)'
        if item['id']=='diff':other='a\nc'
        call(dict(tool=item['id'],mode=mode,text=text,other=other,replacement='[$1]'))
with tempfile.TemporaryDirectory() as directory:
    path=pathlib.Path(directory)/'fixture';data=b'0123456789abcdef'*524288;path.write_bytes(data)
    result=call(dict(tool='hash',file=str(path),other=hashlib.sha256(data).hexdigest()))
    assert result['detail']=='校验一致'
    fifo=pathlib.Path(directory)/'fifo'
    import os
    os.mkfifo(fifo)
    started=time.monotonic();call(dict(tool='hash',file=str(fifo)),ok=False);assert time.monotonic()-started<2
started=time.monotonic()
call(dict(tool='regex',text='a'*30000+'!',other='(a+)+$'),ok=False)
assert 3.5<time.monotonic()-started<8,'Actual regex worker must be stopped on deadline'
call(dict(tool='hash',text='abc')) # Recovery after killing the pathological regex.
call(dict(tool='case',text='a'*49153),ok=False)
print('PASS: all ten tools and every mode, Unicode/core checks, 8MiB streaming checksum, FIFO rejection, regex process deadline and recovery')
