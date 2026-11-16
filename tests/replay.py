"""Durable OTP counter claims and atomic token rollback through both real DB backends."""
from concurrent.futures import ThreadPoolExecutor
import base64
import hashlib
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
secret='JBSWY3DPEHPK3PXP'
with tempfile.TemporaryDirectory(prefix='wlreplay-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=tmp/backend;out.mkdir();db=out/'main.db'
        with sqlite3.connect(db) as con:
            con.executescript((root/'src/schema.sql').read_text())
            con.execute("INSERT INTO users(id,createdAt,modifiedAt) VALUES('u','now','now')")
            con.execute("INSERT INTO users(id,createdAt,modifiedAt) VALUES('other','now','now')")
            con.execute("CREATE TABLE authmeta(hashedToken TEXT PRIMARY KEY REFERENCES login_tokens(hashedToken) ON DELETE CASCADE,tenantKey TEXT NOT NULL,credentialRef TEXT NOT NULL,kind TEXT NOT NULL)")
        built=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/replay.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        def run(mode,user='u',key=secret,counter=100,token='token',database=db):
            return subprocess.check_output([str(out/'replay'),str(database),mode,user,key,str(counter),token],text=True,timeout=30).strip()
        assert run('last')=='error','Missing replay schema must not reset a replay boundary'
        assert run('ensure')=='ok' and run('last')=='-1'
        assert run('without',token='not-issued')=='ok' and run('last')=='-1'
        assert run('claim')=='ok' and run('last')=='100'
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT factorKey FROM _wl_otp').fetchone()[0]==hashlib.sha256(b'welite-otp-factor-v1\0'+secret.encode()).hexdigest()
            saved=list(con.iterdump())
        assert run('claim',counter=100,token='replay')=='error'
        assert run('claim',counter=99,token='stale')=='error'
        with sqlite3.connect(db) as con:assert list(con.iterdump())==saved,'Rejected counter left token/metadata writes'
        assert run('claim',counter=101,token='next')=='ok'
        # Token logout/expiry never releases its consumed one-time counter.
        with sqlite3.connect(db) as con:con.execute('PRAGMA foreign_keys=ON');con.execute('DELETE FROM login_tokens')
        assert run('claim',counter=101,token='after-logout')=='error'
        assert run('claim',key=secret.lower(),counter=101,token='case')=='error'
        assert run('claim',key=secret+'========',counter=102,token='bad-padding')=='error'
        with ThreadPoolExecutor(max_workers=16) as executor:
            outcomes=list(executor.map(lambda index:run('claim',counter=102,token='race-'+str(index)),range(16)))
        assert outcomes.count('ok')==1 and outcomes.count('error')==15,outcomes
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT count(*) FROM login_tokens').fetchone()==(1,)
            assert con.execute('SELECT count(*) FROM authmeta').fetchone()==(1,)
            con.execute("CREATE TRIGGER deny_counter BEFORE UPDATE ON _wl_otp BEGIN SELECT RAISE(ABORT,'test failure'); END")
            saved=list(con.iterdump())
        assert run('claim',counter=103,token='failed-counter')=='error'
        with sqlite3.connect(db) as con:
            assert list(con.iterdump())==saved
            con.execute('DROP TRIGGER deny_counter')
            con.execute("CREATE TRIGGER deny_meta BEFORE INSERT ON authmeta BEGIN SELECT RAISE(ABORT,'test failure'); END")
            saved=list(con.iterdump())
        assert run('claim',counter=103,token='failed-meta')=='error'
        with sqlite3.connect(db) as con:
            assert list(con.iterdump())==saved
            con.execute('DROP TRIGGER deny_meta')
        assert run('claim',counter=103,token='retry')=='ok','Failed token transaction consumed the code'
        assert run('claim',user='other',counter=103,token='other')=='ok'
        assert run('claim',key='MY======',counter=1,token='padded')=='ok'
        assert run('claim',key='MY',counter=1,token='unpadded-replay')=='error'
        assert run('claim',user='absent',counter=104,token='missing-user')=='error'
        assert run('claim',key=base64.b32encode(b'different factor').decode().rstrip('='),counter=1,token='new-factor')=='ok'
        # Failed SELECTs are distinct from an unused factor.
        broken=out/'bad.db'
        with sqlite3.connect(broken) as con:con.execute('CREATE TABLE _wl_otp(value TEXT)');con.execute("INSERT INTO _wl_otp VALUES('preserve')")
        assert run('ensure',database=broken)=='error' and run('last',database=broken)=='error'
        with sqlite3.connect(broken) as con:assert con.execute('SELECT * FROM _wl_otp').fetchall()==[('preserve',)]
        weak=out/'weak.db'
        factor=hashlib.sha256(b'welite-otp-factor-v1\0'+secret.encode()).hexdigest()
        with sqlite3.connect(weak) as con:
            con.execute('CREATE TABLE _wl_otp(userId TEXT,factorKey TEXT,counter INTEGER)')
            con.execute('INSERT INTO _wl_otp VALUES(?,?,NULL)',('u',factor))
        assert run('last',database=weak)=='error','NULL counter was interpreted as unused'
        with sqlite3.connect(weak) as con:
            con.execute('DELETE FROM _wl_otp');con.executemany('INSERT INTO _wl_otp VALUES(?,?,?)',[('u',factor,1),('u',factor,2)])
        assert run('last',database=weak)=='error','Ambiguous counter was interpreted as one record'
        with sqlite3.connect(weak) as con:
            con.execute('DELETE FROM _wl_otp');con.execute('INSERT INTO _wl_otp VALUES(?,?,-1)',('u',factor))
        assert run('last',database=weak)=='error','Invalid stored negative counter was interpreted as unused'
        with sqlite3.connect(db) as con:
            con.execute('PRAGMA foreign_keys=ON');con.execute("DELETE FROM users WHERE id='u'")
            assert con.execute("SELECT count(*) FROM _wl_otp WHERE userId='u'").fetchone()==(0,)
            assert con.execute("SELECT count(*) FROM _wl_otp WHERE userId='other'").fetchone()==(1,)
        print('PASS: '+backend+' restart/case-stable OTP replay, 16 concurrent claims, atomic token/metadata rollback, retry, logout retention, factor/user isolation and schema-error denial')
