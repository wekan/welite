"""Durable pre-authentication limits through linked and CLI SQLite."""
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wlattempt-',dir=os.environ['TMPDIR']) as directory:
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=Path(directory)/backend;out.mkdir();db=out/'main.db'
        built=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/attempt.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        def run(user='user',peer='127.0.0.1',at=1000,database=db):
            return subprocess.check_output([str(out/'attempt'),str(database),user,peer,str(at)],text=True,timeout=30).strip()
        with ThreadPoolExecutor(max_workers=16) as pool:
            answers=list(pool.map(lambda i:run(),range(16)))
        assert answers.count('yes')==5 and answers.count('no')==11,answers
        with sqlite3.connect(db) as con:
            saved=list(con.iterdump())
            assert con.execute('SELECT attempts FROM _wl_attempt ORDER BY attempts').fetchall()==[(5,),(5,),(5,)]
        assert run(peer='different')=='no','Account allowance was peer-dependent'
        assert run(at=999)=='no' and run(at=1299)=='no'
        with sqlite3.connect(db) as con:assert list(con.iterdump())==saved,'Denial changed counters'
        assert run(at=1300)=='yes' and run(at=1301)=='yes'
        # One peer cannot evade its cap by cycling account names.
        for i in range(28):assert run(user='new-'+str(i),at=1301)=='yes'
        assert run(user='overflow',at=1301)=='no'
        assert run(user='independent',peer='other',at=1301)=='yes'
        # Tenant cap bounds attacker-controlled storage, even across peers.
        for i in range(269):assert run(user='global-'+str(i),peer='p-'+str(i),at=1301)=='yes'
        assert run(user='tenant-overflow',peer='p-overflow',at=1301)=='no'
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT count(*) FROM _wl_attempt').fetchone()[0]<=601
        assert run(user='fresh',peer='fresh',at=1601)=='yes'
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT count(*) FROM _wl_attempt').fetchone()==(3,)
            con.execute("CREATE TRIGGER deny_attempt BEFORE UPDATE ON _wl_attempt BEGIN SELECT RAISE(ABORT,'forced'); END")
            saved=list(con.iterdump())
        assert run(user='fresh',peer='fresh',at=1601)=='no'
        with sqlite3.connect(db) as con:
            assert list(con.iterdump())==saved
            con.execute('DROP TRIGGER deny_attempt')
        assert run(user='fresh',peer='fresh',at=1601)=='yes'
        for user,peer,at in [('', 'p',1700),('u','',1700),('u','p',-1),('x'*4097,'p',1700),('u','p'*257,1700)]:
            assert run(user,peer,at)=='no'
        other=out/'other.db'
        assert run(database=other)=='yes','Tenants shared allowance'
        weak=out/'weak.db'
        with sqlite3.connect(weak) as con:
            con.execute('CREATE TABLE _wl_attempt(bucket TEXT,started INTEGER,attempts INTEGER)')
            con.execute("INSERT INTO _wl_attempt VALUES('preserve',0,1)")
        assert run(database=weak)=='no'
        with sqlite3.connect(weak) as con:assert con.execute('SELECT * FROM _wl_attempt').fetchall()==[('preserve',0,1)]
        print('PASS: '+backend+' durable concurrent account/peer/tenant limits, window boundaries, clock rollback, atomic failures, bounded cleanup and isolation')
