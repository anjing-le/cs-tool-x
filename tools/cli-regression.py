#!/usr/bin/env python3
"""Exercise the public CLI contract against isolated local configuration and a fake stdio engine."""
from pathlib import Path
import argparse, concurrent.futures, json, os, subprocess, sys, tempfile, time

parser=argparse.ArgumentParser();parser.add_argument('--binary',type=Path,required=True)
args=parser.parse_args();binary=str(args.binary.resolve())
with tempfile.TemporaryDirectory(prefix='cs-tool-x-cli-') as temporary:
    directory=Path(temporary)
    def call(command,payload=None,status=0,raw=None):
        result=subprocess.run([binary,*command,'--config-dir',str(directory)],
            input=raw if raw is not None else (json.dumps(payload) if payload is not None else ''),
            text=True,capture_output=True,timeout=12)
        assert result.returncode==status,(command,result.returncode,result.stdout,result.stderr)
        envelope=json.loads(result.stdout)
        assert envelope['schemaVersion']==1 and envelope['ok']==(status==0),(command,envelope)
        return envelope.get('result') if status==0 else envelope['error']
    schema=subprocess.run([binary,'schema'],capture_output=True,text=True,check=True,timeout=8)
    assert json.loads(schema.stdout)['result']['version']==1
    for command in [[],['servers'],['--help'],['--version']]:
        result=subprocess.run([binary,*command],capture_output=True,text=True,timeout=8)
        assert result.returncode==0 and result.stdout
    result=subprocess.run([binary,'bogus','sensitive-unknown-token'],capture_output=True,text=True,timeout=8)
    assert result.returncode==2 and json.loads(result.stdout)['error']['code']=='usage'
    assert 'sensitive-unknown-token' not in result.stdout+result.stderr
    initial=call(['servers','list']);assert initial['servers']==[] and initial['revision']=='missing'
    assert not (directory/'shell.json').exists()
    created=call(['servers','put'],{'name':'fixture','host':'fixture.invalid','user':'fixture','password':'fixture-secret'})
    identifier=str(created['id']);revision=created['revision']
    listing=call(['servers','list']);assert 'password' not in listing['servers'][0]
    assert listing['servers'][0]['passwordStored'] is True
    assert call(['servers','show',identifier,'--show-secrets'])['server']['password']=='fixture-secret'
    call(['servers','put'],{'id':int(identifier),'name':'bad'},status=2)
    assert call(['servers','put','--if-revision','old'],{'id':int(identifier),'name':'bad'},status=4)['code']=='revision_conflict'
    call(['servers','put','--if-revision',revision],{'id':int(identifier),'host':'other.invalid'},status=2)
    changed=call(['servers','put','--if-revision',revision],{'id':int(identifier),'notes':'changed'})
    assert changed['revision']!=revision
    assert call(['servers','show',identifier,'--show-secrets'])['server']['password']=='fixture-secret'
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lambda i:call(['servers','put'],{'name':f'parallel-{i}','host':'fixture.invalid'}),range(8)))
    listing=call(['servers','list']);assert len(listing['servers'])==9
    def cas(i):
        result=subprocess.run([binary,'servers','put','--config-dir',str(directory),'--if-revision',listing['revision']],
            input=json.dumps({'id':int(identifier),'notes':f'cas-{i}'}),text=True,capture_output=True,timeout=8)
        json.loads(result.stdout);return result.returncode
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(cas,range(2)))==[0,4]
    call(['servers','put'],status=2,raw='{')
    call(['servers','put'],status=2,raw='x'*(1024*1024+1))
    call(['servers','put'],{'name':'unknown','host':'fixture.invalid','unknown':'secret-not-to-echo'},status=2)
    call(['ssh','exec',identifier],{'command':'bad\0script'},status=2)
    call(['sftp','ls',identifier],{'path':'x\nbye'},status=2)
    call(['ssh','exec','9999'],{'command':'printf test'},status=3)
    profile=call(['profiles','put'],{'kind':'mysql','database':'fixture','name':'fixture'})
    pid=profile['id'];prev=profile['revision']
    call(['profiles','put'],{'kind':'mysql','database':'fixture','password':'must-not-persist'},status=2)
    assert len(call(['profiles','list'])['profiles'])==1
    call(['profiles','put'],{'id':pid,'name':'changed'},status=2)
    fake=directory/'fixture-engine'
    log=directory/'engine-methods';process_id=directory/'engine-pid'
    fake.write_text(f'''#!{sys.executable}
import json,sys,os
from pathlib import Path
Path({str(process_id)!r}).write_text(str(os.getpid()))
for line in sys.stdin:
 r=json.loads(line);m=r['method']
 with open({str(log)!r},'a') as f:f.write(m+'\\n')
 if m=='hello':v={{'protocol':1}}
 elif m=='connect':v={{'id':'fixture-session','elapsedMs':1}}
 elif m=='run':v={{'columns':['number'],'rows':[['9007199254740993']],'elapsedMs':1,'truncated':False,'note':'fixture'}}
 else:v=None
 print(json.dumps({{'id':r['id'],'ok':True,'result':v}}),flush=True)
''')
    fake.chmod(0o700)
    query=call(['data','query',pid,'--engine',str(fake)],{'text':'SELECT 1','password':'ephemeral-test-password'})
    assert query['output']['rows'][0][0]=='9007199254740993'
    assert log.read_text().splitlines()==['hello','connect','run','disconnect']
    assert 'ephemeral-test-password' not in (directory/'connections.json').read_text()
    child=int(process_id.read_text())
    for _ in range(50):
        try:os.kill(child,0)
        except ProcessLookupError:break
        time.sleep(.02)
    else:raise AssertionError('CLI left the fixture engine running')
    call(['data','query',pid,'--engine','/missing/fixture-engine'],{'text':'SELECT 1'},status=5)
    call(['profiles','delete',pid,'--if-revision',prev])
    assert call(['profiles','list'])['profiles']==[]
    latest=call(['servers','list'])
    call(['servers','delete',identifier,'--if-revision',latest['revision']])
    assert (directory/'shell.json.backup').exists()
    for name in ['shell.json','shell.json.backup','shell.json.lock','connections.json','connections.json.backup']:
        assert (directory/name).stat().st_mode & 0o777 == 0o600,name
    (directory/'shell.json').write_text('{bad')
    assert call(['servers','list'],status=3)['code']=='invalid_configuration'
    print('PASS: CLI JSON/exit codes, secrets, CAS conflicts, concurrent processes, input caps, bounded command validation, one-shot engine cleanup and private atomic backups.')
