"""Limited password enrollment proofs, private pending setup and atomic activation."""
from concurrent.futures import ThreadPoolExecutor
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import sqlite3
import struct
import subprocess
import tempfile
import time
root=Path(__file__).resolve().parents[1]
binding=hashlib.sha256(b'peer-and-agent').hexdigest()
credential=dict(password=dict(bcrypt='$2b$04$......................b8CYpLYfgS/XMWDCU3/.oCRJREnOf3y',reset=dict(retain='yes')),other=dict(retain=True))
def otp(secret,counter):
    key=base64.b32decode(secret+'='*((-len(secret))%8));digest=hmac.new(key,struct.pack('>Q',counter),hashlib.sha1).digest();offset=digest[-1]&15
    return str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
with tempfile.TemporaryDirectory(prefix='wlenroll-',dir=os.environ['TMPDIR']) as directory:
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=Path(directory)/backend;out.mkdir();db=out/'main.db'
        for program in ['enroll','factor','token']:
            built=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests'/f'{program}.lpr')],capture_output=True,text=True)
            assert built.returncode==0,built.stdout+built.stderr
        env=dict(os.environ,REQUIRE_2FA='all')
        for name in ['LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN','WELITE_ARGON_SECRET_FILE','WELITE_ENTROPY_FILE']:env.pop(name,None)
        with sqlite3.connect(db) as con:
            con.executescript((root/'src/schema.sql').read_text())
            for user in ['user','other']:
                con.execute('INSERT INTO users(id,username,createdAt,modifiedAt,services_json) VALUES(?,?,\'now\',\'now\',?)',(user,user,json.dumps(credential)))
        def run(*args,settings=None,database=db):
            return subprocess.check_output([str(out/'enroll'),str(database),*args],env=dict(env,**(settings or {})),text=True,timeout=30).strip()
        def start(user='user',password='test-password',sql='',mode='start',settings=None,database=db):
            result=run(mode,user,password,binding,sql,settings=settings,database=database).splitlines()
            if result==['no']:return None
            assert len(result)==2 and len(result[0])==64 and len(result[1])==32,result
            assert len(base64.b32decode(result[1]))==20
            return result
        def confirm(token,secret,counter=None,client=binding,code=None):
            return run('confirm',token,client,code if code is not None else otp(secret,counter if counter is not None else int(time.time())//30))
        twin=out/'twin.db'
        with sqlite3.connect(twin) as con:
            con.executescript((root/'src/schema.sql').read_text())
            con.execute("INSERT INTO users(id,username,createdAt,modifiedAt,services_json) VALUES('user','user','now','now',?)",(json.dumps(credential),))
        assert run('cross','user','test-password',binding,'',str(twin))=='no','Enrollment proof crossed tenant databases'
        assert start(password='wrong') is None
        assert start(mode='twice') is not None,'A required account could not obtain its limited setup proof'
        token,secret=start()
        with sqlite3.connect(db) as con:
            assert json.loads(con.execute("SELECT services_json FROM users WHERE id='user'").fetchone()[0])==credential,'Starting setup changed shared account services'
            assert con.execute('SELECT count(*) FROM login_tokens').fetchone()==(0,)
            assert con.execute('SELECT tokenKey FROM _wl_enrol WHERE userId=\'user\'').fetchone()[0]!=token
        assert subprocess.check_output([str(out/'token'),'check',str(db),token],env=env,text=True).strip()=='no','Setup token granted app access'
        assert confirm(token,secret,client='0'*64)=='no'
        assert confirm(token,secret,code='bad')=='no'
        old=token;token,secret=start()
        assert confirm(old,secret)=='no','Replaced pending token remained usable'
        # Invalidated credentials/policy after proof cannot start setup.
        assert start(sql="UPDATE users SET loginDisabled=1 WHERE id='user'") is None
        with sqlite3.connect(db) as con:con.execute("UPDATE users SET loginDisabled=0 WHERE id='user'")
        # Expired or future-created pending setup cannot activate a factor.
        with sqlite3.connect(db) as con:con.execute('UPDATE _wl_enrol SET created=0,expires=1')
        assert confirm(token,secret)=='no'
        token,secret=start()
        with sqlite3.connect(db) as con:con.execute('UPDATE _wl_enrol SET created=created+1000,expires=expires+1000')
        assert confirm(token,secret)=='no'
        token,secret=start()
        with sqlite3.connect(db) as con:
            con.execute("UPDATE users SET services_json=json_set(services_json,'$.other.changed',1) WHERE id='user'")
        assert confirm(token,secret)=='no'
        with sqlite3.connect(db) as con:con.execute("UPDATE users SET services_json=? WHERE id='user'",(json.dumps(credential),))
        # Forced activation failure rolls back counter, pending setup and token deletion.
        token,secret=start();assert run('ensure')=='yes'
        with sqlite3.connect(db) as con:
            con.execute("CREATE TABLE authmeta(hashedToken TEXT PRIMARY KEY REFERENCES login_tokens(hashedToken) ON DELETE CASCADE,tenantKey TEXT NOT NULL,credentialRef TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('web','api')))")
            con.execute("INSERT INTO login_tokens(hashedToken,userId,createdAt) VALUES('old-token','user','now')")
            con.execute("INSERT INTO authmeta VALUES('old-token','tenant','old','api')")
            con.execute("CREATE TRIGGER deny_enrol BEFORE UPDATE ON users BEGIN SELECT RAISE(ABORT,'forced'); END")
        with sqlite3.connect(db) as con:saved=list(con.iterdump())
        assert confirm(token,secret)=='no'
        with sqlite3.connect(db) as con:
            assert list(con.iterdump())==saved
            assert con.execute('SELECT count(*) FROM _wl_enrol').fetchone()==(1,)
            assert con.execute('SELECT count(*) FROM _wl_otp').fetchone()==(0,)
            assert con.execute("SELECT count(*) FROM login_tokens WHERE hashedToken='old-token'").fetchone()==(1,)
            assert json.loads(con.execute("SELECT services_json FROM users WHERE id='user'").fetchone()[0])==credential
            con.execute('DROP TRIGGER deny_enrol')
            con.execute("CREATE TRIGGER ignore_enrol BEFORE UPDATE ON users BEGIN SELECT RAISE(IGNORE); END")
            saved=list(con.iterdump())
        assert confirm(token,secret)=='no','Ignored user update was reported as enrollment success'
        with sqlite3.connect(db) as con:
            assert list(con.iterdump())==saved
            con.execute('DROP TRIGGER ignore_enrol')
        center=int(time.time())//30
        with ThreadPoolExecutor(max_workers=16) as pool:
            results=list(pool.map(lambda i:confirm(token,secret,center),range(16)))
        assert results.count('yes')==1 and results.count('no')==15,results
        with sqlite3.connect(db) as con:
            expected=dict(credential,twoFactorAuthentication=dict(type='otp',secret=secret))
            assert json.loads(con.execute("SELECT services_json FROM users WHERE id='user'").fetchone()[0])==expected
            assert con.execute('SELECT count(*) FROM _wl_enrol').fetchone()==(0,)
            assert con.execute("SELECT count(*) FROM login_tokens WHERE userId='user'").fetchone()==(0,)
            assert con.execute('SELECT count(*) FROM authmeta').fetchone()==(0,)
            assert con.execute('SELECT counter FROM _wl_otp').fetchone()==(center,)
        assert start() is None,'Password-only setup could replace an active factor'
        assert confirm(token,secret,center+1)=='no','Confirmed setup token remained usable'
        def login(counter):return subprocess.check_output([str(out/'factor'),str(db),'api','user','test-password',otp(secret,counter),'after-enroll'],env=env,text=True).strip()
        assert login(center)=='no','Activation code was reusable for login'
        assert login(center+1)=='yes'
        # Null pending metadata activates correctly, and user deletion cleans pending secrets.
        with sqlite3.connect(db) as con:con.execute("UPDATE users SET services_json=json_set(services_json,'$.twoFactorAuthentication',NULL) WHERE id='other'")
        token2,secret2=start(user='other');assert confirm(token2,secret2)=='yes'
        with sqlite3.connect(db) as con:
            assert json.loads(con.execute("SELECT services_json FROM users WHERE id='other'").fetchone()[0])['twoFactorAuthentication']==dict(type='otp',secret=secret2)
            con.execute("UPDATE users SET services_json=? WHERE id='other'",(json.dumps(credential),))
        token2,secret2=start(user='other')
        with sqlite3.connect(db) as con:con.execute("DELETE FROM users WHERE id='other'");assert con.execute('SELECT count(*) FROM _wl_enrol').fetchone()==(0,)
        # Schema refusal preserves foreign data.
        weak=out/'weak.db'
        with sqlite3.connect(weak) as con:con.execute('CREATE TABLE _wl_enrol(value TEXT)');con.execute("INSERT INTO _wl_enrol VALUES('preserve')")
        assert run('ensure',database=weak)=='no'
        with sqlite3.connect(weak) as con:assert con.execute('SELECT * FROM _wl_enrol').fetchall()==[('preserve',)]
        print('PASS: '+backend+' limited enrollment proof, 20-byte secrets, private pending setup, binding/expiry/stale policy denial, 16-way atomic activation, rollback/retry, token revocation and consumed-code login refusal')
