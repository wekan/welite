"""Opt-in HTTP on the same canonical live FerretDB file, no filename aliases."""
import base64
import hashlib
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
from wire import Client,DateMs,Long
from custapi import run_shared as check_custom_api
from cfexpt import run_shared as check_export_policy
from cfclon import run_shared as check_clone_policy
root=Path(__file__).resolve().parents[1]
ferret=Path(os.environ['FERRETDB'])
with sqlite3.connect(':memory:') as con:assert con.execute("SELECT sqlite_compileoption_used('ENABLE_8_3_NAMES=2')").fetchone()==(0,)
def port():
    with socket.socket() as sock:sock.bind(('127.0.0.1',0));return sock.getsockname()[1]
with tempfile.TemporaryDirectory(prefix='wshared-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    def build(source,dest,flags=(),name=None):
        dest.mkdir(parents=True,exist_ok=True)
        result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(dest),'-FE'+str(dest),*(['-o'+str(dest/name)] if name else []),str(source)],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
    build(root/'tests/dbfile.lpr',tmp/'select')
    def selected(path,shared=False,extra=None):
        return subprocess.check_output([str(tmp/'select/dbfile'),str(path),'shared' if shared else 'native'],env=dict(os.environ,WELITE_SHARED='0',**(extra or {})),text=True).strip()
    cases=tmp/'paths';cases.mkdir()
    assert selected(cases)==str(cases/'wekan.db') and selected(cases,True)=='refused'
    assert list(cases.iterdir())==[]
    for orphan in ['wekan.sqlite-wal','wekan.db-shm','wekan.wal','other.sqlite']:
        (cases/orphan).touch();assert selected(cases)=='refused';(cases/orphan).unlink()
    (cases/'wekan.sqlite').touch()
    assert selected(cases)=='refused' and selected(cases,True)==str(cases/'wekan.sqlite')
    assert selected(cases,True,dict(WELITE_SHORT_NAMES='1'))=='refused'
    (cases/'wekan.db').touch();assert selected(cases,True)=='refused' and selected(cases)=='refused'
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=tmp/backend;out.mkdir();build(root/'src/wlhttp.lpr',out/'build',flags)
        env=dict(os.environ,WELITE_DATA=str(out/'data'),WELITE_SCHEMA=str(root/'src/schema.sql'),WELITE_DESIGNER=str(root/'src/designer.sql'),WELITE_PUBLIC=str(root/'public'),WELITE_I18N=str(root/'i18n'),WELITE_SHARED='1')
        for key in ['WELITE_SHORT_NAMES','WELITE_SQLITE_EXT','WELITE_ENTROPY_FILE','WELITE_ARGON_SECRET_FILE','REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN','PASSWORD_LOGIN_ENABLED','ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS']:env.pop(key,None)
        if backend=='cli':
            build(root/'src/wlfunc.lpr',out/'ext',['-Cg','-dWLSQLEXT'],'wlfunc.so');env['WELITE_SQLITE_EXT']=str(out/'ext/wlfunc.so')
        data=out/'data/local/files/db';data.mkdir(parents=True);state=out/'state';state.mkdir()
        mongo_port=port();http_port=port();env['WELITE_PORT']=str(http_port)
        database=data/'wekan.sqlite';shadow=data/'wekan.db';app=None
        with (out/'ferret.log').open('w+') as mongo_log,(out/'http.log').open('w+') as app_log:
            server=subprocess.Popen([str(ferret),'--handler=sqlite','--sqlite-url='+data.as_uri()+'/','--state-dir='+str(state),'--listen-addr=127.0.0.1:'+str(mongo_port),'--debug-addr=127.0.0.1:'+str(port()),'--log-level=ERROR','--telemetry=disable'],env=env,stdout=mongo_log,stderr=mongo_log)
            client=Client(mongo_port)
            def request(method,path,body=None,token=None,timeout=10):
                con=http.client.HTTPConnection('127.0.0.1',http_port,timeout=timeout)
                headers={'Host':'localhost','User-Agent':'shared-http-test'}
                if token:headers['Authorization']='Bearer '+token
                if body is not None:headers['Content-Type']='application/json' if isinstance(body,(dict,bytes)) else 'application/x-www-form-urlencoded'
                con.request(method,path,json.dumps(body) if isinstance(body,dict) else body,headers)
                response=con.getresponse();result=response.status,dict(response.getheaders()),response.read();con.close();return result
            def stop():
                if app is not None and app.poll() is None:app.terminate();app.wait(timeout=10)
            def start(mode,store=None):
                proc=subprocess.Popen([str(out/'build/wlhttp')],env=dict(env,WELITE_SHARED=mode,WELITE_DATA=str(store or out/'data')),cwd=out,stdout=app_log,stderr=app_log)
                for _ in range(100):
                    try:
                        request('GET','/sign-in');return proc
                    except OSError:
                        assert proc.poll() is None;time.sleep(.05)
                proc.kill();proc.wait();raise AssertionError('HTTP startup timed out')
            try:
                for _ in range(100):
                    try:client.command({'ping':1});break
                    except OSError:time.sleep(.05)
                else:raise AssertionError('FerretDB startup timed out')
                for collection in ['boards','swimlanes','lists','cards','card_comments','checklists','checklistItems','customFields','users','activities','attachments']:client.command({'create':collection})
                now=DateMs(int(time.time()*1000))
                password={'bcrypt':'$2b$04$......................b8CYpLYfgS/XMWDCU3/.oCRJREnOf3y'}
                client.command({'insert':'users','documents':[dict(_id='u',username='user',services=dict(password=password),profile=dict(language='ar',retained=Long(9007199254740993)),extra=Long(9007199254740993))]})
                client.command({'insert':'boards','documents':[dict(_id='b',title='Shared board',slug='shared-board',permission='private',createdAt=now,members=[dict(userId='u',isAdmin=True,isActive=True,isReadOnly=False)])]})
                client.command({'insert':'swimlanes','documents':[dict(_id='s',boardId='b',title='Lane',createdAt=now)]})
                client.command({'insert':'lists','documents':[dict(_id='l',boardId='b',title='List',createdAt=now)]})
                app=start('0')
                refused=request('GET','/')
                assert refused[0]==404 and not shadow.exists(),(backend,refused[0],shadow.exists(),refused[2])
                stop()
                app=start('1')
                status,_,body=request('POST','/users/login',dict(username='user',password='test-password'))
                assert status==200,(backend,status,body)
                login=json.loads(body);token=login['token']
                assert login['id']=='u' and request('GET','/api/boards/b',token=token)[0]==200
                user=client.find('users','u')[0];assert user['extra']==Long(9007199254740993)
                shared=user['services']['resume']['loginTokens'];assert len(shared)==1 and isinstance(shared[0]['when'],DateMs)
                assert shared[0]['hashedToken']==base64.b64encode(hashlib.sha256(token.encode()).digest()).decode()
                client.command({'update':'boards','updates':[dict(q=dict(_id='b'),u={'$set':{'title':'Mongo changed'}})]})
                assert b'Mongo changed' in request('GET','/api/boards/b',token=token)[2]
                status,_,body=request('POST','/api/boards/b/lists/l/cards',dict(title='HTTP card',swimlaneId='s'),token)
                assert status==200,(backend,status,body)
                card=client.find('cards',json.loads(body)['_id'])[0]
                assert card['title']=='HTTP card' and isinstance(card['createdAt'],DateMs)
                check_custom_api(request,client,database,token)
                check_export_policy(request,client,database)
                check_clone_policy(request,client,database,token)
                status,headers,_=request('POST','/sign-in',urlencode(dict(username='user',password='test-password')))
                assert status in [302,303] and 'Set-Cookie' not in headers,(status,headers)
                assert request('GET',headers['Location'])[0]==200
                web_session=parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
                board_url='/board?id=b&sessionId='+web_session
                profile_response=request('GET',board_url)
                assert b'dir="rtl"' in profile_response[2] and b'lang="ar"' in profile_response[2]
                assert profile_response[1]['Content-Language']=='ar'
                assert b'dir="rtl"' not in request('GET',board_url+'&lang=fi')[2]
                client.command({'update':'users','updates':[dict(q=dict(_id='u'),u={'$set':{'profile.language':'fi'}})]})
                profile_response=request('GET',board_url)
                assert b'dir="rtl"' not in profile_response[2] and profile_response[1]['Content-Language']=='fi'
                assert client.find('users','u')[0]['profile']==dict(language='fi',retained=Long(9007199254740993))
                assert len(client.find('users','u')[0]['services']['resume']['loginTokens'])==1,'Private browser session became a Meteor bearer'
                stop();app=start('1')
                assert request('GET','/api/user',token=token)[0]==200,'API token did not survive adapter restart'
                client.command({'update':'users','updates':[dict(q=dict(_id='u'),u={'$set':{'services.resume.loginTokens':[]}})]})
                assert request('GET','/api/user',token=token)[0]==401
                assert not shadow.exists(),'A normalized public database shadowed the shared file'
                with sqlite3.connect(database) as con:assert con.execute("SELECT type FROM sqlite_master WHERE name='users'").fetchone()==('view',)
                stop()
                empty=out/'empty'
                app=start('1',empty)
                assert request('GET','/')[0]==404
                assert not (empty/'local/files/db/wekan.db').exists() and not (empty/'local/files/db/wekan.sqlite').exists()
                stop()
                native=out/'native';native_file=native/'local/files/db/wekan.db';native_file.parent.mkdir(parents=True)
                with sqlite3.connect(native_file) as con:con.execute('CREATE TABLE users(id TEXT PRIMARY KEY)')
                app=start('1',native)
                assert request('GET','/')[0]==404
                with sqlite3.connect(native_file) as con:
                    assert con.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()==[('users',)]
                print('PASS:',backend,'canonical existing shared HTTP activation, no shadow, Mongo/HTTP changes, BSON, private web session, API restart and shared revocation')
            finally:
                stop();server.terminate();server.wait(timeout=10)
