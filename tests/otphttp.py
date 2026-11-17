"""Public web/API OTP logins and shared durable attempt limits, both SQLite backends."""
import base64
import hashlib
import hmac
import http.client
import json
import os
from pathlib import Path
import socket
import sqlite3
import struct
import subprocess
import tempfile
import time
from urllib.parse import urlencode,urlsplit,parse_qs
root=Path(__file__).resolve().parents[1]
key=b'12345678901234567890';secret=base64.b32encode(key).decode()
def otp(counter):
    digest=hmac.new(key,struct.pack('>Q',counter),hashlib.sha1).digest();offset=digest[-1]&15
    return str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
with tempfile.TemporaryDirectory(prefix='wlotphttp-',dir=os.environ['TMPDIR']) as directory:
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=Path(directory)/backend;out.mkdir();build=out/'build';build.mkdir()
        built=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(build),'-FE'+str(build),str(root/'src/wlhttp.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        env=dict(os.environ,WELITE_PORT=str(port),WELITE_SCHEMA=str(root/'src/schema.sql'),WELITE_DESIGNER=str(root/'src/designer.sql'),WELITE_DATA=str(out/'data'))
        for name in ['REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN','WELITE_ARGON_SECRET_FILE','WELITE_ENTROPY_FILE','WELITE_TRUSTED_PROXIES']:env.pop(name,None)
        db=out/'data/local/files/db/wekan.db'
        with (out/'server.log').open('w+') as log:
            server=None
            def request(method,path,data=None,as_json=False,headers=None):
                conn=http.client.HTTPConnection('127.0.0.1',port,timeout=15)
                fields={'Host':'localhost','User-Agent':'otp-http','Content-Type':'application/json' if as_json else 'application/x-www-form-urlencoded'}
                fields.update(headers or {})
                conn.request(method,path,(json.dumps(data) if as_json else urlencode(data)) if data is not None else None,fields)
                response=conn.getresponse();result=response.status,dict(response.getheaders()),response.read();conn.close();return result
            def start():
                global server
                server=subprocess.Popen([str(build/'wlhttp')],cwd=out,env=env,stdout=log,stderr=log)
                for attempt in range(100):
                    try:request('GET','/sign-in');return
                    except OSError:
                        if server.poll() is not None:log.seek(0);raise AssertionError(log.read())
                        time.sleep(.05)
                raise AssertionError('Server did not start')
            def stop():
                server.terminate()
                try:server.wait(timeout=5)
                except subprocess.TimeoutExpired:server.kill();server.wait()
            def expire():
                with sqlite3.connect(db) as con:con.execute('UPDATE _wl_attempt SET started=0')
            def login(route='/users/login',code=None,password='test-password',username='factor',**kwargs):
                data=dict(username=username,password=password)
                if code is not None:data['code']=code
                return request('POST',route,data,**kwargs)
            try:
                start()
                page=request('GET','/sign-in');assert b'name="code"' in page[2] and b'maxlength="6"' in page[2]
                credential=dict(password=dict(bcrypt='$2b$04$......................b8CYpLYfgS/XMWDCU3/.oCRJREnOf3y'),twoFactorAuthentication=dict(type='otp',secret=secret))
                with sqlite3.connect(db) as con:
                    con.execute("INSERT INTO users(id,username,createdAt,modifiedAt,services_json) VALUES('factor','factor','now','now',?)",(json.dumps(credential),))
                    con.execute("INSERT INTO users(id,username,createdAt,modifiedAt,services_json) VALUES('plain','plain','now','now',?)",(json.dumps(dict(password=credential['password'])),))
                center=int(time.time())//30
                assert login(password='wrong',code=otp(center))[0]==401
                assert login()[0]==401
                assert login(code='１２３４５６')[0]==401
                response=login(code=otp(center),as_json=True);assert response[0]==200,response
                api=json.loads(response[2])['token']
                assert request('GET','/api/user',headers={'Authorization':'Bearer '+api})[0]==200
                assert login(code=otp(center))[0]==401
                denied=login('/sign-in',otp(center+1),headers={'X-Forwarded-For':'198.51.100.99'})
                assert denied[0]==429 and denied[1]['Retry-After']=='300' and 'Location' not in denied[1]
                with sqlite3.connect(db) as con:
                    assert con.execute('SELECT count(*) FROM login_tokens').fetchone()==(1,)
                    assert con.execute('SELECT counter FROM _wl_otp').fetchone()==(center,)
                stop();start()
                assert login(code=otp(center+1))[0]==429,'Restart reset allowance'
                assert request('GET','/api/user?token='+api)[0]==200
                expire()
                response=login('/sign-in',otp(center+1));assert response[0]==302,response
                assert 'Set-Cookie' not in response[1]
                web=parse_qs(urlsplit(response[1]['Location']).query)['sessionId'][0]
                assert b'Username: factor' in request('GET',response[1]['Location'])[2]
                assert login('/sign-in',otp(center+1))[0]==200,'Replay was accepted'
                # Existing password-only accounts still use the same issuer and limiter.
                assert login(username='plain')[0]==200
                assert login('/sign-in',username='plain')[0]==302
                # An issuer error leaves both the OTP and token tables unchanged.
                with sqlite3.connect(db) as con:
                    con.execute("CREATE TRIGGER deny_meta BEFORE INSERT ON authmeta BEGIN SELECT RAISE(ABORT,'forced'); END")
                    tokens=con.execute('SELECT * FROM login_tokens ORDER BY hashedToken').fetchall()
                assert login(code=otp(center+2))[0]==500
                with sqlite3.connect(db) as con:
                    assert con.execute('SELECT * FROM login_tokens ORDER BY hashedToken').fetchall()==tokens
                    assert con.execute('SELECT counter FROM _wl_otp').fetchone()==(center+1,)
                    con.execute('DROP TRIGGER deny_meta')
                assert login(code=otp(center+2))[0]==200
                # The peer cap covers all accounts and both endpoints; spoofed headers
                # cannot buy a new allowance. Use independent nonexistent accounts.
                expire()
                for index in range(30):
                    response=login('/sign-in' if index%2 else '/users/login',username='absent-'+str(index),headers={'X-Forwarded-For':'198.51.100.'+str(index)})
                    assert response[0]==(200 if index%2 else 401),response
                assert login(username='plain')[0]==429
                expire();stop();env['REQUIRE_2FA']='all';start()
                assert login(username='plain')[0]==401,'Required enrollment granted application access'
                assert login(code=otp(center+3))[0]==200
                if os.environ.get('WELITE_UI')=='1':
                    subprocess.run([os.environ.get('NODE','node'),str(root/'tests/otphttp.js'),'http://localhost:'+str(port),otp(center+4)],check=True)
                # Changing the active factor revokes previously issued web/API tokens.
                with sqlite3.connect(db) as con:
                    con.execute("UPDATE users SET services_json=json_set(services_json,'$.twoFactorAuthentication.secret','JBSWY3DPEHPK3PXP') WHERE id='factor'")
                assert request('GET','/api/user?token='+api)[0]==401
                assert b'Username: factor' not in request('GET','/?sessionId='+web)[2]
                print('PASS: '+backend+' public OTP web/form/JSON login, replay and rollback, shared durable limits, spoof denial, restart, password-only compatibility, required enrollment and factor revocation')
            finally:
                if server is not None and server.poll() is None:stop()
