#!/usr/bin/env python3
"""Read-only Git browser regression using disposable repositories and no network."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, tempfile

def fixture(directory):
    directory.mkdir(parents=True, exist_ok=False)
    env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
    env.update(GIT_CONFIG_GLOBAL='/dev/null',GIT_CONFIG_NOSYSTEM='1',GIT_AUTHOR_NAME='Demo Author',GIT_AUTHOR_EMAIL='demo@example.invalid',GIT_COMMITTER_NAME='Demo Author',GIT_COMMITTER_EMAIL='demo@example.invalid')
    def git(repo,*args):return subprocess.check_output(['/usr/bin/git','-C',str(repo),*args],env=env,stderr=subprocess.PIPE,text=True).strip()
    one=directory/'app-core';one.mkdir();git(one,'init','-b','main')
    (one/'README.md').write_text('demo\n');git(one,'add','.');git(one,'commit','-m','Create project workspace')
    git(one,'tag','-a','v1.0','-m','First release')
    git(one,'checkout','-b','feature/git-browser')
    (one/'browser.swift').write_text('// demo\n');git(one,'add','.');git(one,'commit','-m','Add repository and branch filters','-m','Search across commit history')
    feature=git(one,'rev-parse','HEAD')
    git(one,'checkout','main');(one/'theme.swift').write_text('// theme\n');git(one,'add','.');git(one,'commit','-m','Polish paper theme and compact toolbar')
    git(one,'merge','--no-ff','feature/git-browser','-m','Merge Git browser into main')
    git(one,'update-ref','refs/remotes/origin/main','HEAD');git(one,'update-ref','refs/remotes/origin/feature/git-browser',feature)
    two=directory/'toolkit';two.mkdir();git(two,'init','-b','develop')
    (two/'tool.txt').write_text('tool\n');git(two,'add','.');git(two,'commit','-m','Add shared local tools')
    git(two,'branch','release/1.0');git(two,'update-ref','refs/remotes/origin/develop','HEAD')
    empty=directory/'empty-project';empty.mkdir();git(empty,'init','-b','main')
    return one,feature

def verify(binary):
    with tempfile.TemporaryDirectory(prefix='cs-tool-git-') as temporary:
        root=Path(temporary)/'repos';one,feature=fixture(root)
        def call(args,code=0):
            r=subprocess.run([str(binary),*args],capture_output=True,text=True,timeout=30)
            assert r.returncode==code,(args[:2],r.returncode,r.stdout,r.stderr)
            d=json.loads(r.stdout);assert d['ok']==(code==0)
            return d.get('result') if code==0 else d['error']
        def manifest():return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()}
        before=manifest()
        scan=call(['git','scan',str(root)]);assert len(scan['repositories'])==3 and not scan['limited']
        refs=call(['git','refs',str(one)]);assert refs['branch']=='main' and len(refs['references'])==5
        assert any(r['kind']=='remote' for r in refs['references'])
        page=call(['git','log',str(one),'--limit','2']);assert len(page['commits'])==2 and page['hasMore']
        next_page=call(['git','log',str(one),'--offset',str(page['nextOffset']),'--limit','2'])
        assert len({c['oid'] for c in page['commits']+next_page['commits']})==4
        found=call(['git','log',str(one),'--search','Search across commit history']);assert [c['oid'] for c in found['commits']]==[feature]
        branch=call(['git','log',str(one),'--branch','refs/heads/feature/git-browser']);assert branch['commits'][0]['oid']==feature
        detail=call(['git','show',str(one),refs['head']]);assert detail['files'][0]['path']=='browser.swift'
        call(['git','show',str(one),'--not-a-hash'],2)
        call(['git','log',str(one),'--limit','201'],2)
        call(['git','log',str(one),'--days','3'],2)
        assert call(['git','log',str(one),'--branch','refs/heads/does-not-exist'],5)['code']=='operation_failed'
        assert before==manifest(),'Git browser changed repository contents'
        # A missing object in a partial clone must not launch a lazy-fetch transport helper.
        helper=Path(temporary)/'transport-helper'
        helper.write_text('#!/bin/sh\nprintf attempted > "$0.marker"\nexit 1\n');helper.chmod(0o700)
        marker=helper.with_name(helper.name+'.marker')
        env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
        env.update(GIT_CONFIG_GLOBAL='/dev/null',GIT_CONFIG_NOSYSTEM='1')
        for key,value in [('remote.origin.url','ext::'+str(helper)),('remote.origin.promisor','true'),('protocol.ext.allow','always')]:
            subprocess.run(['/usr/bin/git','-C',str(one),'config',key,value],env=env,check=True)
        missing='f'*40
        control=subprocess.run(['/usr/bin/git','-C',str(one),'cat-file','-p',missing],env=env,capture_output=True,timeout=10)
        assert control.returncode and marker.exists(),'Fixture must prove an unguarded read can invoke the fetch helper'
        marker.unlink()
        partial_before=manifest()
        call(['git','show',str(one),missing],5)
        assert not marker.exists(),'Git browser started a lazy-fetch helper'
        assert partial_before==manifest(),'Missing-object read changed repository contents'
        print('PASS: Git CLI discovery, refs, paginated graph data, branch/text filtering, merge details, invalid inputs unchanged repositories and blocked lazy fetch')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--binary',type=Path);parser.add_argument('--write-fixture',type=Path);args=parser.parse_args()
    if args.write_fixture:fixture(args.write_fixture);print('Created disposable Git UI fixture')
    if args.binary:verify(args.binary.resolve())
