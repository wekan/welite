"""Normalized legacy-store expiry: real auth setup, atomic failure and idle work."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime,timezone
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time
root=Path(__file__).resolve().parents[1]
def iso(ms):return datetime.fromtimestamp(ms//1000,timezone.utc).replace(microsecond=(ms%1000)*1000).isoformat(timespec='milliseconds').replace('+00:00','Z')
with tempfile.TemporaryDirectory(prefix='wlegacy-',dir=os.environ['TMPDIR']) as directory:
    temp=Path(directory)
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=temp/backend;out.mkdir()
        def build(name):
            dest=out/name;dest.mkdir()
            result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(dest),'-FE'+str(dest),str(root/'tests'/f'{name}.lpr')],capture_output=True,text=True)
            assert result.returncode==0,result.stdout+result.stderr
        for name in ['sweep','factor','enroll','maint']:build(name)
        env=dict(os.environ)
        for variable in ['WELITE_SQLITE_EXT','REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN','WELITE_ARGON_SECRET_FILE']:env.pop(variable,None)
        db=out/'main.db'
        password={'bcrypt':'$2b$04$......................b8CYpLYfgS/XMWDCU3/.oCRJREnOf3y'}
        def seed(path):
            with sqlite3.connect(path) as con:
                con.executescript((root/'src/schema.sql').read_text())
                con.executemany('INSERT INTO users(id,username,createdAt,modifiedAt,services_json) VALUES(?,?,?,?,?)',[(uid,uid,'date','date',json.dumps(dict(password=password))) for uid in ['u','v']])
        seed(db)
        def sql(statement,args=()):
            with sqlite3.connect(db) as con:return con.execute(statement,args).fetchall()
        def digest(raw):return hashlib.sha256(('welite-token-v2\0'+str(db.resolve())+'\0'+raw).encode()).hexdigest()
        def issue(raw):assert subprocess.check_output([str(out/'factor/factor'),str(db),'api','u','test-password','',raw],env=env,text=True).strip()=='yes'
        def check(raw):return subprocess.check_output([str(out/'factor/factor'),str(db),'check',raw],env=env,text=True).strip()
        def sweep(at,path=db):return subprocess.check_output([str(out/'sweep/sweep'),str(path),str(at),'legacy'],env=env,text=True).strip()
        for raw in ['dead','keep']:issue(raw)
        for uid in ['u','v']:
            setup=subprocess.check_output([str(out/'enroll/enroll'),str(db),'start',uid,'test-password','d'*64],env=env,text=True).strip().splitlines()
            assert len(setup)==2
        now=int(time.time()*1000)
        sql('UPDATE login_tokens SET expiresAt=? WHERE hashedToken=?',(iso(now),digest('dead')))
        sql("UPDATE _wl_enrol SET created=?,expires=CASE WHEN userId='u' THEN ? ELSE ? END",(now//1000-1,now//1000,now//1000+3600))
        sql("INSERT INTO authmeta VALUES('orphan','fixture','fixture','api')")
        sql('CREATE TABLE _wl_otp(userId TEXT NOT NULL,factorKey TEXT NOT NULL,counter INTEGER NOT NULL CHECK(counter>=0),PRIMARY KEY(userId,factorKey)) STRICT')
        sql("INSERT INTO _wl_otp VALUES('u',?,123)",('a'*64,))
        def snapshot():
            with sqlite3.connect(db) as con:
                names=con.execute("SELECT name,sql FROM sqlite_master WHERE type='table' ORDER BY name").fetchall()
                return names,{name:con.execute('SELECT * FROM "'+name.replace('"','""')+'" ORDER BY 1').fetchall() for name,_ in names}
        before=snapshot()
        for table in ['authmeta','login_tokens','_wl_enrol']:
            sql('CREATE TRIGGER deny_legacy BEFORE DELETE ON '+table+' BEGIN SELECT RAISE(IGNORE); END;')
            assert sweep(now)=='no',table
            assert snapshot()==before,('Partial legacy cleanup',table)
            sql('DROP TRIGGER deny_legacy')
        with ThreadPoolExecutor(max_workers=4) as pool:results=list(pool.map(lambda _:sweep(now),range(4)))
        assert 'yes' in results and all(value in ['yes','no'] for value in results),results
        assert sql('SELECT lastAt FROM _wl_sweep')==[(now,)]
        assert check('dead')=='no' and check('keep')=='yes'
        assert sql("SELECT userId FROM _wl_enrol")==[('v',)]
        assert sql("SELECT count(*) FROM authmeta WHERE hashedToken='orphan'")==[(0,)]
        assert sql('SELECT * FROM _wl_otp')==[('u','a'*64,123)]
        assert not sql("SELECT name FROM sqlite_master WHERE name IN ('_wl_pair','_wl_seen','_wl_authsrc','_ferretdb_collections')")
        assert sweep(now-1)=='no' and sweep(now+599999)=='yes' and sql('SELECT lastAt FROM _wl_sweep')==[(now,)]
        # An ignored checkpoint update cannot commit credential deletion.
        issue('clock-dead');sql('UPDATE login_tokens SET expiresAt=? WHERE hashedToken=?',(iso(now+600000),digest('clock-dead')))
        baseline=snapshot();sql('CREATE TRIGGER deny_clock BEFORE UPDATE ON _wl_sweep BEGIN SELECT RAISE(IGNORE); END;')
        assert sweep(now+600000)=='no' and snapshot()==baseline
        sql('DROP TRIGGER deny_clock');assert sweep(now+600000)=='yes'
        # A missing checkpoint row plus an ignored seed cannot bypass assertions.
        issue('insert-dead');sql('UPDATE login_tokens SET expiresAt=? WHERE hashedToken=?',(iso(now),digest('insert-dead')))
        sql('DELETE FROM _wl_sweep');baseline=snapshot()
        sql('CREATE TRIGGER deny_seed BEFORE INSERT ON _wl_sweep BEGIN SELECT RAISE(IGNORE); END;')
        assert sweep(now+600000)=='no' and snapshot()==baseline
        sql('DROP TRIGGER deny_seed')
        # Run the real worker while no HTTP request is happening.
        issue('idle');sql('UPDATE login_tokens SET expiresAt=? WHERE hashedToken=?',(iso(int(time.time()*1000)-1),digest('idle')))
        sql('UPDATE _wl_sweep SET lastAt=-600000')
        tick=int(time.time());sql("UPDATE _wl_enrol SET created=?,expires=? WHERE userId='v'",(tick-1,tick))
        worker=subprocess.Popen([str(out/'maint/maint'),str(db)],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:
            assert worker.stdout.readline().strip()=='ready'
            for _ in range(200):
                if sql('SELECT count(*) FROM login_tokens WHERE hashedToken=?',(digest('idle'),))==[(0,)]:break
                assert worker.poll() is None;time.sleep(.05)
            else:raise AssertionError('Idle legacy maintenance did not run')
            assert sql('SELECT count(*) FROM _wl_enrol')==[(0,)]
            output,errors=worker.communicate('stop\n',timeout=10)
            assert worker.returncode==0 and output.strip()=='stopped',(output,errors)
        finally:
            if worker.poll() is None:worker.kill();worker.wait()
        assert check('keep')=='yes' and sql('SELECT * FROM _wl_otp')==[('u','a'*64,123)]
        assert check('insert-dead')=='no' and sql('SELECT count(*) FROM login_tokens WHERE hashedToken=?',(digest('insert-dead'),))==[(0,)]
        # Older stores without optional auth metadata still clean their tokens.
        bare=out/'bare.db';seed(bare)
        with sqlite3.connect(bare) as con:con.executemany('INSERT INTO login_tokens VALUES(?,?,?,?)',[('expired','u','date',iso(now)),('retained','u','date',iso(now+86400000))])
        assert sweep(now,bare)=='yes'
        with sqlite3.connect(bare) as con:
            assert con.execute('SELECT hashedToken FROM login_tokens').fetchall()==[('retained',)]
            assert not con.execute("SELECT name FROM sqlite_master WHERE name IN ('authmeta','_wl_enrol','_wl_pair','_wl_authsrc')").fetchall()
            con.execute('CREATE TABLE authmeta(other TEXT)')
        assert sweep(now+600000,bare)=='no','Incompatible metadata was adopted'
        with sqlite3.connect(bare) as con:
            assert con.execute('SELECT lastAt FROM _wl_sweep').fetchall()==[(now,)]
            con.execute('DROP TABLE authmeta');con.execute('DROP TABLE _wl_sweep');con.execute('CREATE TABLE _wl_sweep(id INTEGER,lastAt INTEGER)')
        assert sweep(now+600000,bare)=='no','Unowned checkpoint layout was adopted'
        mixed=out/'mixed.db';seed(mixed)
        with sqlite3.connect(mixed) as con:
            con.execute('CREATE TABLE _ferretdb_collections(name TEXT)')
            con.execute('INSERT INTO login_tokens VALUES(?,?,?,?)',('untouched','u','date',iso(now)))
        assert sweep(now,mixed)=='no'
        with sqlite3.connect(mixed) as con:
            assert con.execute('SELECT hashedToken FROM login_tokens').fetchall()==[('untouched',)]
            assert not con.execute("SELECT name FROM sqlite_master WHERE name='_wl_sweep'").fetchall()
        print('PASS:',backend,'legacy inclusive expiry, optional schemas, rollback, concurrency, checkpoint/clock, replay preservation, mixed-store refusal and idle cleanup')
