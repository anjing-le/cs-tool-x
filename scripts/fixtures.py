"""Isolated local fixtures. Never connects to existing databases. Run start / stop."""
from pathlib import Path
import socket, subprocess, sys, os, signal, json, time
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'.local'/'fixtures'
BASE.mkdir(parents=True,exist_ok=True)
PG='/opt/homebrew/opt/postgresql@16/bin/'

def run(args,**kw):
    subprocess.run(list(map(str,args)),check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,**kw)

def ready(port):
    for _ in range(100):
        try:
            with socket.create_connection(('127.0.0.1',port),timeout=.2): return
        except OSError: time.sleep(.1)
    raise RuntimeError(f'fixture {port} not ready')

if sys.argv[1]=='stop':
    if (BASE/'pg'/'postmaster.pid').exists(): run([PG+'pg_ctl','-D',BASE/'pg','-m','fast','stop'])
    for filename in ['mysql.pid','redis.pid','es.pid']:
        p=BASE/filename
        if p.exists():
            try: os.kill(int(p.read_text().strip()), signal.SIGTERM)
            except ProcessLookupError: pass
    print('Stopped isolated fixtures')
    sys.exit()
for port in [16432,13306,16379,19200]:
    with socket.socket() as s:
        s.bind(('127.0.0.1',port))
if not (BASE/'pg').exists(): run([PG+'initdb','-D',BASE/'pg','-A','trust','-U','datax_fixture','--no-locale','-E','UTF8'])
run([PG+'pg_ctl','-D',BASE/'pg','-l',BASE/'pg.log','-o',f'-h 127.0.0.1 -p 16432 -k {BASE}','start'])
if not (BASE/'mysql').exists():
    (BASE/'mysql').mkdir()
    run(['/opt/homebrew/bin/mysqld','--no-defaults','--initialize-insecure',f'--datadir={BASE}/mysql'])
mysql_log=open(BASE/'mysql.log','ab')
p=subprocess.Popen(['/opt/homebrew/bin/mysqld','--no-defaults',f'--datadir={BASE}/mysql','--bind-address=127.0.0.1','--port=13306',f'--socket={BASE}/mysql.sock',f'--pid-file={BASE}/mysql.pid','--mysqlx=OFF'],stdout=mysql_log,stderr=mysql_log,start_new_session=True)
ready(13306)
run(['/opt/homebrew/bin/mysql','--no-defaults','-h127.0.0.1','-P13306','-uroot','-e',"CREATE DATABASE IF NOT EXISTS datax_fixture; CREATE TABLE IF NOT EXISTS datax_fixture.sample (id BIGINT PRIMARY KEY, label VARCHAR(100)); REPLACE INTO datax_fixture.sample VALUES (9007199254740993, '本地测试');"])
run([PG+'psql','-h127.0.0.1','-p16432','-Udatax_fixture','-dpostgres','-c',"CREATE TABLE IF NOT EXISTS sample (id BIGINT PRIMARY KEY, label TEXT); INSERT INTO sample VALUES (9007199254740993, '本地测试') ON CONFLICT DO NOTHING;"])
run(['/opt/homebrew/bin/redis-server','--bind','127.0.0.1','--port','16379','--save','','--appendonly','no','--daemonize','yes','--pidfile',BASE/'redis.pid','--logfile',BASE/'redis.log'])
ready(16379)
run(['/opt/homebrew/bin/redis-cli','-p','16379','SET','datax:fixture','本地测试'])
run(['/opt/homebrew/bin/redis-cli','-p','16379','HSET','datax:hash','label','本地测试','id','9007199254740993'])
eslog=open(BASE/'es.log','ab')
p=subprocess.Popen([sys.executable,ROOT/'scripts'/'es_fixture.py'],stdout=eslog,stderr=eslog,start_new_session=True)
(BASE/'es.pid').write_text(str(p.pid));ready(19200)
print('Fixtures ready: MySQL 13306, PG 16432, Redis 16379, ES protocol fixture 19200')
