"""Private Argon2 secret policy and real web/API token lifecycle, both backends."""
from signin import session_of, signed_in
import hashlib
import hmac
import http.client
import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import tempfile
import time
from urllib.parse import urlencode,urlsplit,parse_qs
root=Path(__file__).resolve().parents[1]
secret=b'operator\0secret\n'
fixture='$argon2id$v=19$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$YP4w4kIb5cnL7j3QC7YWdgIgvtjmj5Q22x+qTOqyF+w'
with tempfile.TemporaryDirectory(prefix='wlsecret-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=tmp/backend;out.mkdir();build=out/'build';build.mkdir();pepper=out/'pepper.key';pepper.write_bytes(b'wrong');pepper.chmod(0o600)
        for source in [root/'src/wlhttp.lpr',root/'tests/token.lpr']:
            result=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(build),'-FE'+str(build),str(source)],capture_output=True,text=True)
            assert result.returncode==0,result.stdout+result.stderr
        with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        env=dict(os.environ,WELITE_SHARED='0',WELITE_PORT=str(port),WELITE_DATA=str(out/'data'),WELITE_SCHEMA=str(root/'src/schema.sql'),WELITE_DESIGNER=str(root/'src/designer.sql'),WELITE_ARGON_SECRET_FILE=str(pepper))
        for variable in ['WELITE_ENTROPY_FILE','WELITE_ARGON_MEMORY_KIB','WELITE_ARGON_PASSES','WELITE_ARGON_LANES','REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN','WELITE_ARGON_KEY_BYTES']:env.pop(variable,None)
        initialized=subprocess.run([str(build/'wlhttp'),'initadmin','global'],cwd=out,env=dict(env,WELITE_ADMIN_PASSWORD='test-password'),capture_output=True,text=True)
        assert initialized.returncode==0,initialized.stderr
        with (out/'server.log').open('w+') as log:
            server=subprocess.Popen([str(build/'wlhttp')],cwd=out,env=env,stdout=log,stderr=log)
            try:
                def request(method,path,data=None):
                    conn=http.client.HTTPConnection('127.0.0.1',port,timeout=10)
                    conn.request(method,path,urlencode(data) if data else None,{'Host':'localhost','User-Agent':'secret-test','Content-Type':'application/x-www-form-urlencoded'})
                    response=conn.getresponse();result=response.status,dict(response.getheaders()),response.read();conn.close();return result
                for attempt in range(100):
                    try:request('GET','/sign-in');break
                    except OSError:
                        if server.poll() is not None:log.seek(0);raise AssertionError(log.read())
                        time.sleep(.05)
                else:raise AssertionError('Server did not start')
                for name in ['secret-user','bcrypt-user']:
                    assert signed_in(request('POST','/register',dict(username=name,password='test-password',confirm='test-password')))
                db=out/'data/local/files/db/wekan.db'
                services=dict(password=dict(argon2=fixture,bcrypt='$2b$04$......................b8CYpLYfgS/XMWDCU3/.oCRJREnOf3y',reset=dict(token='retain')))
                with sqlite3.connect(db) as con:
                    con.execute('UPDATE users SET services_json=? WHERE username=?',(json.dumps(services),'secret-user'))
                    uid=con.execute("SELECT id FROM users WHERE username='secret-user'").fetchone()[0]
                def login(name='secret-user',route='/users/login'):
                    # Each secret-rotation case uses a fresh login budget; otphttp.py
                    # covers denial and persistence of the actual shared allowance.
                    with sqlite3.connect(db) as con:
                        if con.execute("SELECT 1 FROM sqlite_master WHERE name='_wl_attempt'").fetchone():
                            con.execute('UPDATE _wl_attempt SET started=0')
                    return request('POST',route,dict(username=name,password='test-password'))
                assert login()[0]==401
                assert login(route='/sign-in')[0]==200
                assert login('bcrypt-user')[0]==200
                pepper.write_bytes(secret)
                web_response=login(route='/sign-in')
                web=signed_in(web_response)
                api_response=login();assert api_response[0]==200
                api=json.loads(api_response[2])['token']
                assert request('GET','/api/user?token='+web)[0]==200 and request('GET','/api/user?token='+api)[0]==200
                with sqlite3.connect(db) as con:
                    stored=json.loads(con.execute('SELECT services_json FROM users WHERE id=?',(uid,)).fetchone()[0]);assert stored==services
                    raw=con.execute("SELECT json_extract(services_json,'$.password') FROM users WHERE id=?",(uid,)).fetchone()[0]
                    expected=hmac.new(secret,b'welite-argon-secret-v1\0'+raw.encode(),hashlib.sha256).hexdigest()
                    refs=con.execute('SELECT credentialRef FROM authmeta JOIN login_tokens USING(hashedToken) WHERE userId=?',(uid,)).fetchall()
                    assert (expected,) in refs
                def token(*args):return subprocess.check_output([str(build/'token'),args[0],str(db),*args[1:]],env=env,text=True).strip()
                proof=token('proof','secret-user','test-password');assert proof==expected
                # Rotation between password proof and token issuance must refuse issuance.
                pepper.write_bytes(b'rotated')
                assert token('issue-ref',uid,'race-token',proof)=='no'
                assert request('GET','/api/user?token='+api)[0]==401
                assert request('GET','/designer?sessionId='+web)[0]==302
                pepper.write_bytes(secret)
                assert request('GET','/api/user?token='+api)[0]==401
                assert request('GET','/designer?sessionId='+web)[0]==302
                assert token('issue-ref',uid,'restart-token',proof)=='yes'
                assert token('check','restart-token')=='yes'
                # Missing or empty configured files never mean an empty Argon2 secret.
                pepper.unlink()
                assert login()[0]==401 and login('bcrypt-user')[0]==200
                assert token('check','restart-token')=='no'
                pepper.write_bytes(b'');pepper.chmod(0o600)
                assert login()[0]==401
                pepper.write_bytes(secret)
                assert token('check','restart-token')=='no'
                assert login()[0]==200
                with sqlite3.connect(db) as con:assert json.loads(con.execute('SELECT services_json FROM users WHERE id=?',(uid,)).fetchone()[0])==services
                print('PASS: '+backend+' private Argon2 secret logins, HMAC binding, proof/issue rotation, web/API durable revocation, missing/empty denial and bcrypt isolation')
            finally:
                server.terminate()
                try:server.wait(timeout=5)
                except subprocess.TimeoutExpired:server.kill();server.wait()
