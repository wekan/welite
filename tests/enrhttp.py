"""Public required-factor enrollment without granting premature application access."""
from autherr import check as check_auth_error
import base64
import hashlib
import hmac
import http.client
import json
import os
from pathlib import Path
import re
import socket
import sqlite3
import struct
import subprocess
import tempfile
import time
from urllib.parse import urlencode
root=Path(__file__).resolve().parents[1]
def otp(secret,counter):
    digest=hmac.new(base64.b32decode(secret),struct.pack('>Q',counter),hashlib.sha1).digest();offset=digest[-1]&15
    return str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
with tempfile.TemporaryDirectory(prefix='wlenrhttp-',dir=os.environ['TMPDIR']) as directory:
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=Path(directory)/backend;out.mkdir();build=out/'build';build.mkdir()
        built=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(build),'-FE'+str(build),str(root/'src/wlhttp.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        env=dict(os.environ,WELITE_SHARED='0',WELITE_PORT=str(port),WELITE_SCHEMA=str(root/'src/schema.sql'),WELITE_DESIGNER=str(root/'src/designer.sql'),WELITE_DATA=str(out/'data'),WELITE_I18N=str(root/'i18n'),REQUIRE_2FA='all')
        for name in ['LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN','WELITE_ARGON_SECRET_FILE','WELITE_ENTROPY_FILE','WELITE_TRUSTED_PROXIES']:env.pop(name,None)
        db=out/'data/local/files/db/wekan.db'
        with (out/'server.log').open('w+') as log:
            server=None
            def request(method,path,data=None,agent='enrollment-http',headers=None):
                conn=http.client.HTTPConnection('127.0.0.1',port,timeout=15)
                fields={'Host':'localhost','User-Agent':agent,'Content-Type':'application/x-www-form-urlencoded'};fields.update(headers or {})
                conn.request(method,path,urlencode(data) if data is not None else None,fields)
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
            def register(user):
                response=request('POST','/register',dict(username=user,password='test-password',confirm='test-password'))
                assert response[0]==200 and b'Account created' in response[2] and b'/two-factor/setup' in response[2] and 'Location' not in response[1],response
                return response
            def setup(user,password='test-password'):
                response=request('POST','/two-factor/setup',dict(username=user,password=password))
                assert response[1].get('Cache-Control')=='no-store' and response[1].get('Referrer-Policy')=='no-referrer'
                assert 'Set-Cookie' not in response[1] and b'test-password' not in response[2]
                match=re.search(rb'<code id="otp-secret">([A-Z2-7]{32})</code>',response[2])
                if match:
                    token=re.search(rb'name="setupToken" value="([a-f0-9]{64})"',response[2]).group(1).decode()
                    return token,match.group(1).decode()
                return None
            def confirm(token,code,**kwargs):
                response=request('POST','/two-factor/confirm',dict(setupToken=token,code=code,username=kwargs.pop('username','spoofed')),**kwargs)
                assert response[1].get('Cache-Control')=='no-store' and 'Set-Cookie' not in response[1]
                assert 'Location' not in response[1]
                return response
            def services(user):
                with sqlite3.connect(db) as con:return json.loads(con.execute('SELECT services_json FROM users WHERE username=?',(user,)).fetchone()[0])
            try:
                start()
                assert b'/two-factor/setup' in request('GET','/sign-in')[2]
                response=request('GET','/two-factor/setup');assert b'otp-secret' not in response[2] and response[1].get('Cache-Control')=='no-store'
                for lang, source, direction in [('fi','fi','ltr'), ('ar','ar','rtl'),
                                                ('ar-DZ','ar','rtl'), ('ar-EG','ar','rtl'),
                                                ('de','de','ltr'), ('fr','fr','ltr'),
                                                ('fr-CA','fr','ltr'), ('es','es','ltr'), ('it','it','ltr'), ('sv','sv','ltr'), ('nl','nl','ltr'), ('pl','pl','ltr'), ('cs','cs','ltr'), ('sk','sk','ltr'), ('hu','hu','ltr'), ('ro','ro','ltr'), ('da','da','ltr'), ('pt','pt','ltr'), ('el','el','ltr'), ('tr','tr','ltr'), ('id','id','ltr'), ('vi','vi','ltr'), ('uk','uk','ltr'), ('ja','ja','ltr'), ('ko','ko','ltr'), ('ru','ru','ltr'), ('he','he','rtl'), ('fa','fa','rtl'), ('th','th','ltr'), ('hi','hi','ltr'), ('bn','bn','ltr'), ('ta','ta','ltr'), ('nb','nb','ltr'), ('is','is','ltr'), ('bg','bg','ltr'), ('hr','hr','ltr'), ('sl','sl','ltr'), ('ca','ca','ltr'), ('eu','eu','ltr'), ('gl','gl','ltr'), ('lv','lv','ltr'), ('lt','lt','ltr'), ('eo','eo','ltr'), ('af','af','ltr'), ('sw','sw','ltr'), ('ms','ms','ltr'), ('cy','cy','ltr'), ('ga','ga','ltr'), ('gd','gd','ltr'), ('mt','mt','ltr'), ('sq','sq','ltr'), ('sr','sr','ltr'), ('mk','mk','ltr'), ('ka','en','ltr')]:
                    catalog = json.loads((root/'i18n'/'data'/f'{source}.jsn').read_text())
                    expected = catalog['enrollment-password-instructions']
                    status, headers, body = request('GET', '/two-factor/setup?lang='+lang)
                    assert status == 200 and headers.get('Cache-Control') == 'no-store'
                    assert headers['Content-Language'] == lang
                    assert expected.encode() in body and f'lang="{lang}"'.encode() in body
                    assert (b'dir="rtl"' in body) == (direction == 'rtl')
                notices = {}
                for lang in ('fi','ar'):
                    catalog = json.loads((root/'i18n'/'data'/f'{lang}.jsn').read_text())
                    notices[lang] = catalog['registration-first-admin'].encode()
                    status, headers, body = request('GET','/register?lang='+lang)
                    assert status==200 and headers['Content-Language']==lang
                    assert notices[lang] in body and 'Set-Cookie' not in headers
                register('required');before=services('required')
                for lang, notice in notices.items():
                    status, headers, body = request('GET','/register?lang='+lang)
                    assert status==200 and notice not in body
                assert request('POST','/users/login',dict(username='required',password='test-password'))[0]==401
                assert setup('required',password='wrong') is None
                token,secret=setup('required');assert services('required')==before
                with sqlite3.connect(db) as con:assert con.execute('SELECT count(*) FROM login_tokens').fetchone()==(0,)
                assert request('GET','/api/user?token='+token)[0]==401
                center=int(time.time())//30
                assert b'Two-factor authentication is enabled' not in confirm(token,otp(secret,center),agent='different-browser')[2]
                assert services('required')==before
                assert b'Invalid authentication code' in confirm(token,'bad')[2]
                assert b'Two-factor authentication is enabled' in confirm(token,otp(secret,center))[2]
                assert services('required')['twoFactorAuthentication']==dict(type='otp',secret=secret)
                assert request('POST','/users/login',dict(username='required',password='test-password',code=otp(secret,center+1)))[0]==429,'Enrollment did not share login account limits'
                expire()
                assert request('POST','/users/login',dict(username='required',password='test-password',code=otp(secret,center)))[0]==401,'Confirmation code was reusable'
                logged=request('POST','/users/login',dict(username='required',password='test-password',code=otp(secret,center+1)))
                assert logged[0]==200,logged
                api=json.loads(logged[2])['token'];assert request('GET','/api/user?token='+api)[0]==200
                assert setup('required') is None,'Password alone replaced an active factor'
                assert b'Two-factor authentication is enabled' not in confirm(token,otp(secret,center+2))[2]
                # A private storage failure retains the frame without disclosing setup secrets.
                register('frame-fail');expire();failure_before=services('frame-fail')
                with sqlite3.connect(db) as con:
                    con.execute("CREATE TRIGGER framefail BEFORE INSERT ON _wl_enrol BEGIN SELECT RAISE(ABORT,'forced'); END")
                try:
                    failed=request('POST','/two-factor/setup?lang=fi',dict(username='frame-fail',password='test-password'))
                    assert failed[0]==500;check_auth_error(failed,'fi',private=True,title_key='two-factor-required-title')
                    assert '<p>Käyttöönottoa ei voitu aloittaa</p>'.encode() in failed[2]
                    assert services('frame-fail')==failure_before
                    with sqlite3.connect(db) as con:
                        assert con.execute("SELECT count(*) FROM _wl_enrol WHERE username='frame-fail'").fetchone()==(0,)
                finally:
                    with sqlite3.connect(db) as con:con.execute('DROP TRIGGER framefail')
                expire()
                # Confirmation account comes from pending setup, not posted fields.
                register('limited');limited_before=services('limited');expire();token2,secret2=setup('limited')
                for index in range(4):
                    denied=confirm(token2,'bad',username='rotate-'+str(index),headers={'X-Forwarded-For':'198.51.100.'+str(index)})
                    assert denied[0]==200 and b'Invalid authentication code' in denied[2]
                denied=confirm(token2,otp(secret2,int(time.time())//30),username='another',headers={'Accept-Language':'ar'})
                assert denied[0]==429 and denied[1]['Retry-After']=='300'
                check_auth_error(denied,'ar',private=True,title_key='two-factor-required-title')
                denied=request('POST','/two-factor/setup',dict(username='limited',password='test-password',lang='fi'))
                assert denied[0]==429;check_auth_error(denied,'fi',private=True,title_key='two-factor-required-title')
                denied=request('POST','/sign-in?lang=ar',dict(username='limited',password='test-password'))
                assert denied[0]==429;check_auth_error(denied,'ar',title_key='log-in')
                assert services('limited')==limited_before
                expire()
                with sqlite3.connect(db) as con:con.execute("CREATE TRIGGER deny_enrol BEFORE UPDATE ON users BEGIN SELECT RAISE(ABORT,'forced'); END")
                assert b'Two-factor authentication is enabled' not in confirm(token2,otp(secret2,int(time.time())//30))[2]
                assert services('limited')==limited_before
                with sqlite3.connect(db) as con:
                    assert con.execute("SELECT count(*) FROM _wl_enrol WHERE username='limited'").fetchone()==(1,)
                    con.execute('DROP TRIGGER deny_enrol')
                stop();start()
                assert b'Two-factor authentication is enabled' in confirm(token2,otp(secret2,int(time.time())//30))[2],'Pending setup did not survive restart'
                # Expired setup does not activate; a fresh setup replaces its secret/token.
                register('expired');token3,secret3=setup('expired')
                with sqlite3.connect(db) as con:con.execute("UPDATE _wl_enrol SET created=0,expires=1 WHERE username='expired'")
                assert b'Two-factor authentication is enabled' not in confirm(token3,otp(secret3,int(time.time())//30))[2]
                token4,secret4=setup('expired');assert token3!=token4 and secret3!=secret4
                assert b'Two-factor authentication is enabled' not in confirm(token3,otp(secret3,int(time.time())//30))[2]
                assert b'Two-factor authentication is enabled' in confirm(token4,otp(secret4,int(time.time())//30))[2]
                from authlang import check_auth_language
                check_auth_language(request,db,otp)
                if os.environ.get('WELITE_UI')=='1':
                    register('browser-enroll');expire()
                    subprocess.run([os.environ.get('NODE','node'),str(root/'tests/enrhttp.js'),'http://localhost:'+str(port)],check=True)
                # Admin-only policy enrolls the first administrator while allowing
                # subsequent ordinary accounts to receive their normal session.
                stop();env['WELITE_DATA']=str(out/'admins-data');env['REQUIRE_2FA']='admins';start()
                register('first-admin')
                ordinary=request('POST','/register',dict(username='ordinary',password='test-password',confirm='test-password'))
                assert ordinary[0]==302 and 'sessionId=' in ordinary[1]['Location'],ordinary
                admins_db=out/'admins-data/local/files/db/wekan.db'
                with sqlite3.connect(admins_db) as con:
                    before=con.execute('SELECT hashedToken FROM login_tokens ORDER BY hashedToken').fetchall()
                    con.execute("CREATE TRIGGER fail_session BEFORE INSERT ON login_tokens BEGIN SELECT RAISE(ABORT,'forced'); END")
                failed=request('POST','/sign-in?lang=ar',dict(username='ordinary',password='test-password'))
                assert failed[0]==500 and 'Location' not in failed[1]
                check_auth_error(failed,'ar',title_key='log-in')
                assert '<p>تعذّر إنشاء جلسة</p>'.encode() in failed[2]
                with sqlite3.connect(admins_db) as con:
                    assert con.execute('SELECT hashedToken FROM login_tokens ORDER BY hashedToken').fetchall()==before
                failed=request('POST','/register?lang=fi',dict(username='saved-account',
                    password='test-password',confirm='test-password'))
                assert failed[0]==500 and 'Location' not in failed[1]
                check_auth_error(failed,'fi',title_key='register')
                assert '<p>Tili luotu. Jatka kirjautumalla sisään.</p>'.encode() in failed[2]
                with sqlite3.connect(admins_db) as con:
                    assert con.execute('SELECT hashedToken FROM login_tokens ORDER BY hashedToken').fetchall()==before
                    assert con.execute("SELECT count(*) FROM users WHERE username='saved-account'").fetchone()==(1,)
                    con.execute('DROP TRIGGER fail_session')
                recovered=request('POST','/sign-in?lang=fi',dict(username='saved-account',password='test-password'))
                assert recovered[0]==302 and 'sessionId=' in recovered[1]['Location']


                print('PASS: '+backend+' required-factor registration, private HTTP setup, cookie-free confirmation, client binding, shared derived-account limits, rollback/retry, pending restart, expiry/replacement and fresh-code login')
            finally:
                if server is not None and server.poll() is None:stop()
