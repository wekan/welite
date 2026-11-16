"""Real password+OTP proof, atomic issuance and factor-bound tokens on both backends."""
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
key=b'12345678901234567890';secret=base64.b32encode(key).decode().rstrip('=')
bcrypt='$2b$04$......................b8CYpLYfgS/XMWDCU3/.oCRJREnOf3y'
def otp(counter):
    digest=hmac.new(key,struct.pack('>Q',counter),hashlib.sha1).digest();offset=digest[-1]&15
    return str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
with tempfile.TemporaryDirectory(prefix='wlfactor-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=tmp/backend;out.mkdir();db=out/'main.db'
        for program in ['factor','token']:
            built=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests'/f'{program}.lpr')],capture_output=True,text=True)
            assert built.returncode==0,built.stdout+built.stderr
        env=dict(os.environ)
        for name in ['REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN','WELITE_ARGON_SECRET_FILE']:env.pop(name,None)
        services=dict(password=dict(bcrypt=bcrypt),twoFactorAuthentication=dict(type='otp',secret=secret))
        with sqlite3.connect(db) as con:
            con.executescript((root/'src/schema.sql').read_text())
            con.execute("INSERT INTO users(id,username,createdAt,modifiedAt,services_json) VALUES('u','user','now','now',?)",(json.dumps(services),))
        def run(mode,code='',token='token',password='test-password',sql='',settings=None):
            return subprocess.check_output([str(out/'factor'),str(db),mode,'user',password,code,token,sql],env=dict(env,**(settings or {})),text=True,timeout=30).strip()
        def check(token,settings=None):return subprocess.check_output([str(out/'factor'),str(db),'check',token],env=dict(env,**(settings or {})),text=True).strip()
        center=int(time.time())//30
        assert run('api',otp(center),password='wrong')=='no'
        assert run('api','')=='no' and run('api','１２３４５６')=='no'
        assert run('twice',otp(center),token='first')=='yes'
        assert check('first')=='yes','Factor-bound token did not survive process restart'
        assert run('api',otp(center),token='replayed')=='no'
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT count(*) FROM login_tokens').fetchone()==(1,)
            assert con.execute('SELECT counter FROM _wl_otp').fetchone()==(center,)
            stored=json.loads(con.execute('SELECT services_json FROM users').fetchone()[0]);assert stored==services
            base=hashlib.sha256(json.dumps(services['password'],separators=(',',':')).encode()).hexdigest()
            factor=hashlib.sha256(b'welite-otp-factor-v1\0'+secret.encode()).hexdigest()
            expected=hashlib.sha256(b'welite-otp-session-v1\0'+base.encode()+b'\0'+factor.encode()).hexdigest()
            assert con.execute('SELECT credentialRef FROM authmeta').fetchone()==(expected,)
        # Old password-only helpers cannot mint an active-factor credential.
        old=subprocess.check_output([str(out/'token'),'issue-ref',str(db),'u','old-helper',base],env=env,text=True).strip()
        assert old=='no'
        assert run('web',otp(center+1))=='yes'
        with ThreadPoolExecutor(max_workers=16) as executor:
            results=list(executor.map(lambda index:run('api',otp(center+2),token='race-'+str(index)),range(16)))
        assert results.count('yes')==1 and results.count('no')==15,results
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT count(*) FROM login_tokens').fetchone()==(3,)
            con.execute("CREATE TRIGGER deny_meta BEFORE INSERT ON authmeta BEGIN SELECT RAISE(ABORT,'forced failure'); END")
            snapshot=list(con.iterdump())
        assert run('api',otp(center+3),token='failed')=='no'
        with sqlite3.connect(db) as con:
            assert list(con.iterdump())==snapshot,'Failed factor issuance left token/counter writes'
            con.execute('DROP TRIGGER deny_meta')
        assert run('api',otp(center+3),token='retry')=='yes'
        with sqlite3.connect(db) as con:
            con.execute("CREATE TRIGGER deny_counter BEFORE UPDATE ON _wl_otp BEGIN SELECT RAISE(ABORT,'forced failure'); END")
            snapshot=list(con.iterdump())
        assert run('api',otp(center+4),token='counter-failed')=='no'
        with sqlite3.connect(db) as con:
            assert list(con.iterdump())==snapshot
            con.execute('DROP TRIGGER deny_counter')
        # Account changes between the verified proof and issuance are refused.
        assert run('mutate',otp(center+4),token='disabled',sql="UPDATE users SET loginDisabled=1 WHERE id='u';")=='no'
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT counter FROM _wl_otp').fetchone()==(center+3,)
            con.execute("UPDATE users SET loginDisabled=0 WHERE id='u'")
        changed=dict(services, twoFactorAuthentication=dict(type='otp',secret=base64.b32encode(b'changed-factor-secret').decode().rstrip('=')))
        mutation="UPDATE users SET services_json='"+json.dumps(changed).replace("'","''")+"' WHERE id='u';"
        assert run('mutate',otp(center+4),token='changed-factor',sql=mutation)=='no'
        assert check('first')=='no'
        with sqlite3.connect(db) as con:
            con.execute('UPDATE users SET services_json=? WHERE id=?',(json.dumps(services),'u'))
        assert check('first')=='no','Observed factor rotation revived an old token'
        assert run('api',otp(center+4),token='required',settings=dict(REQUIRE_2FA='all'))=='yes'
        assert check('required',settings=dict(REQUIRE_2FA='all'))=='yes'
        with sqlite3.connect(db) as con:con.execute("UPDATE users SET authenticationMethod='ldap' WHERE id='u'")
        assert run('api',otp(center+5),token='ldap-denied',settings=dict(LDAP_ENABLE='true'))=='no'
        assert run('api',otp(center+5),token='ldap-fallback',settings=dict(LDAP_ENABLE='true',LDAP_LOGIN_FALLBACK='true'))=='yes'
        assert check('ldap-fallback',settings=dict(LDAP_ENABLE='true',LDAP_LOGIN_FALLBACK='true'))=='yes'
        with sqlite3.connect(db) as con:con.execute("UPDATE users SET authenticationMethod='password' WHERE id='u'")
        # A covered account without an enabled factor still needs enrollment.
        with sqlite3.connect(db) as con:con.execute('UPDATE users SET services_json=?',(json.dumps(dict(password=dict(bcrypt=bcrypt))),))
        assert run('api','',token='missing-required',settings=dict(REQUIRE_2FA='all'))=='no'
        assert run('api','',token='plain')=='yes' and check('plain')=='yes'
        print('PASS: '+backend+' real password+OTP proofs, factor-bound web/API tokens, single-use proof/counter, 16 concurrent logins, rollback/retry, stale policy denial and required-factor modes')
