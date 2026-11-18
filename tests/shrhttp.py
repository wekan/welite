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
from chkshare import run as check_shared_checklists
from listsoft import run as check_list_soft_delete
from cfexpt import run_shared as check_export_policy
from cfclon import run_shared as check_clone_policy
from selrels import run_shared as check_relation_scope
from graphsnp import configure as snapshot_proxy,run_shared as check_graph_snapshot
root=Path(__file__).resolve().parents[1]
ferret=Path(os.environ['FERRETDB'])
backends = {'linked': [], 'cli': ['-dWLDB_CLI']}
upstream = os.environ.get('WELITE_WEKAN_PLAYWRIGHT')
if upstream:
    upstream = Path(upstream).resolve()
    playwright = upstream / 'node_modules/playwright/cli.js'
    if not playwright.is_file():
        raise SystemExit('WELITE_WEKAN_PLAYWRIGHT must point to WeKan tests/playwright with dependencies installed')
upstream_filter = os.environ.get('WELITE_WEKAN_API_GREP')
selected_backend = os.environ.get('WELITE_SHARED_BACKEND')
if selected_backend is not None:
    if selected_backend not in backends:
        raise SystemExit('WELITE_SHARED_BACKEND must be linked or cli')
    backends = {selected_backend: backends[selected_backend]}
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
    for backend,flags in backends.items():
        print(f'RUN: shared HTTP with {backend} SQLite', flush=True)
        out=tmp/backend;out.mkdir();build(root/'src/wlhttp.lpr',out/'build',flags)
        env=dict(os.environ,WELITE_DATA=str(out/'data'),WELITE_SCHEMA=str(root/'src/schema.sql'),WELITE_DESIGNER=str(root/'src/designer.sql'),WELITE_PUBLIC=str(root/'public'),WELITE_I18N=str(root/'i18n'),WELITE_SHARED='1')
        for key in ['WELITE_SHORT_NAMES','WELITE_SQLITE_EXT','WELITE_ENTROPY_FILE','WELITE_ARGON_SECRET_FILE','REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN','PASSWORD_LOGIN_ENABLED','ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS']:env.pop(key,None)
        if backend=='cli':
            build(root/'src/wlfunc.lpr',out/'ext',['-Cg','-dWLSQLEXT'],'wlfunc.so');env['WELITE_SQLITE_EXT']=str(out/'ext/wlfunc.so')
        snapshot_control=snapshot_proxy(env,out) if backend=='cli' else None
        data=out/'data/local/files/db';data.mkdir(parents=True);state=out/'state';state.mkdir()
        mongo_port=port();http_port=port();env['WELITE_PORT']=str(http_port)
        database=data/'wekan.sqlite';shadow=data/'wekan.db';app=None
        with (out/'ferret.log').open('w+') as mongo_log,(out/'http.log').open('w+') as app_log:
            mongo_command=[str(ferret),'--handler=sqlite','--sqlite-url='+data.as_uri()+'/','--state-dir='+str(state),'--listen-addr=127.0.0.1:'+str(mongo_port),'--debug-addr=127.0.0.1:'+str(port()),'--log-level=ERROR','--telemetry=disable']
            client=Client(mongo_port)
            def start_ferret():
                return subprocess.Popen(mongo_command,env=env,stdout=mongo_log,stderr=mongo_log)
            server=[start_ferret()]
            def refresh_ferret():
                server[0].terminate()
                server[0].wait(timeout=10)
                server[0]=start_ferret()
                wait_for_ferret()
            def wait_for_ferret():
                for _ in range(100):
                    try:
                        client.command({'ping':1})
                        return
                    except OSError:
                        time.sleep(.05)
                raise AssertionError('FerretDB startup timed out')
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
                wait_for_ferret()
                for collection in ['boards','swimlanes','lists','cards','card_comments','checklists','checklistItems','customFields','users','activities','attachments']:client.command({'create':collection})
                if upstream:
                    for collection in ['rules','triggers','actions','savedCardFilters','scrumSnapshotRows']:
                        client.command({'create':collection})
                    app=start('1')
                    subprocess.run([
                        os.environ.get('NODE','node'),str(playwright),'test',
                        '17-rest-api.e2e.js','23-rest-api-more.e2e.js',
                        '--reporter=list','--output',str(out/'playwright-results'),
                        *(['--grep', upstream_filter] if upstream_filter else []),
                    ],cwd=upstream,env=dict(env,
                        WEKAN_BASE_URL=f'http://127.0.0.1:{http_port}',
                        WEKAN_MONGO_URL=f'mongodb://127.0.0.1:{mongo_port}/wekan',
                        WEKAN_PLAYWRIGHT_PROJECT='chromium',WEKAN_PLAYWRIGHT_PROBE='0',
                        WEKAN_PLAYWRIGHT_ALL='0',WEKAN_PLAYWRIGHT_WORKERS='1'),
                        check=True)
                    continue
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
                card_path='/api/boards/b/lists/l/cards/'+card['_id']
                assert card['members']==[] and card['assignees']==[]
                client.command({'update':'cards','updates':[
                    dict(q=dict(_id=card['_id']),u={'$set':{'members':None},'$unset':{'assignees':''}})]})
                assert request('PUT',card_path,dict(members=None,assignees=''),token)[0]==200
                assignments=client.find('cards',card['_id'])[0]
                assert assignments['members']==[] and assignments['assignees']==[]
                print('PASS: shared REST card assignments normalize missing and null BSON arrays')
                dates=dict(receivedAt=0,startAt='-1',dueAt='2026-06-07T14:00:00.000+02:00',endAt='2026-06-08')
                assert request('PUT',card_path,dates,token)[0]==200
                stored=client.find('cards',card['_id'])[0]
                assert [stored[field] for field in dates]==[
                    DateMs(0),DateMs(-1),DateMs(1780833600000),DateMs(1780876800000)]
                assert request('PUT',card_path,dict(dueAt='invalid'),token)[0]==404
                assert client.find('cards',card['_id'])[0]==stored
                assert request('PUT',card_path,dict(receivedAt=None,startAt='null',dueAt='',endAt=''),token)[0]==200
                cleared=client.find('cards',card['_id'])[0]
                assert all(field not in cleared for field in dates)
                print('PASS: shared REST card dates set as BSON Date and clear by field removal')

                bulk_path='/api/boards/b/lists/l/cards/bulk'
                status,_,body=request('POST',bulk_path,dict(swimlaneId='s',cards=[
                    dict(title='Child',parentId=card['_id'],members=['u']),
                    dict(title='Invalid placement',swimlaneId='missing'),
                    dict(title='Unassigned',assignees=None),
                ]),token)
                assert status==200,(status,body)
                created=json.loads(body)
                assert created[1]==dict(index=1,error='Invalid card placement'),created
                child,unassigned=[client.find('cards',created[i]['_id'])[0] for i in (0,2)]
                assert child['parentId']==card['_id'] and child['members']==['u']
                assert unassigned['members']==[] and unassigned['assignees']==[]
                assert [child['cardNumber'],unassigned['cardNumber']]==[card['cardNumber']+1,card['cardNumber']+2]
                delete_path='/api/boards/b/cards/bulk'
                ids=[child['_id'],unassigned['_id']]
                assert request('DELETE',delete_path,dict(cardIds=[ids[0],None]),token)[0]==400
                assert client.find('cards',ids[0])
                status,_,body=request('DELETE',delete_path,dict(cardIds=[ids[0],'missing',ids[1],ids[0]]),token)
                assert (status,json.loads(body))==(200,dict(deleted=ids,notFound=['missing',ids[0]])),(status,body)
                for card_id in ids:
                    assert not client.find('cards',card_id)
                    activity,=client.command({'find':'activities','filter':dict(cardId=card_id,activityType='deleteCard')})['cursor']['firstBatch']
                    assert activity['userId']=='u' and activity['boardId']=='b'
                print('PASS: shared REST bulk deletion reports missing entries and writes one activity per card')
                print('PASS: shared REST bulk creation saves valid entries, assignment arrays and distinct card numbers')

                check_shared_checklists(request,client,token,card)
                status,headers,_=request('POST','/sign-in',urlencode(dict(username='user',password='test-password')))
                assert status in [302,303] and 'Set-Cookie' not in headers,(status,headers)
                assert request('GET',headers['Location'])[0]==200
                web_session=parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
                check_list_soft_delete(request,client,database,token,refresh_ferret,web_session)
                list_path='/api/boards/b/lists/l'
                before=client.find('lists','l')[0]
                assert request('PUT',list_path,dict(title='Rejected',color='#abc'),token)[0]==400
                assert client.find('lists','l')[0]==before
                members=client.find('boards','b')[0]['members']
                def set_list_admin(enabled):
                    result=client.command({'update':'boards','updates':[dict(q={'_id':'b'},u={'$set':{
                        'members':[dict(member,isAdmin=enabled) if member['userId']=='u' else member for member in members]
                    }})]})
                    assert result['n']==1,result
                wip=dict(value=4,enabled=True,soft=False)
                set_list_admin(False)
                try:
                    assert request('PUT',list_path,dict(title='Rejected',wipLimit=wip),token)[0]==403
                    assert client.find('lists','l')[0]==before
                finally:
                    set_list_admin(True)
                status,_,body=request('PUT',list_path,dict(title='Edited list',color='#Aa01fF',starred=True,wipLimit=wip),token)
                assert status==200 and json.loads(body)=={'_id':'l'},(status,body)
                updated=client.find('lists','l')[0]
                assert (updated['title'],updated['color'],updated['starred'])==('Edited list','#Aa01fF',True),updated
                assert updated['wipLimit']['value']==4 and updated['wipLimit']['enabled'] is True and updated['wipLimit']['soft'] is False,updated
                print('PASS: live shared list PUT stores typed WIP values and rejects unauthorized or invalid edits atomically')

                settings_path='/api/boards/b/cardSettings'
                client.command({'update':'boards','updates':[dict(q={'_id':'b'},u={'$set':{'legacySetting':now}})]})
                status,_,body=request('GET',settings_path,token=token)
                assert status==200 and json.loads(body)['allowsDueDate'] is True
                assert 'legacySetting' not in json.loads(body)
                assert request('PUT',settings_path,dict(unknownSetting=True),token)[0]==400
                set_list_admin(False)
                try:
                    assert request('PUT',settings_path,dict(allowsDueDate=False),token)[0]==403
                finally:
                    set_list_admin(True)
                status,_,body=request('PUT',settings_path,dict(allowsDueDate=False,cardAgingDays1=14),token)
                assert status==200 and json.loads(body)['allowsDueDate'] is False and json.loads(body)['cardAgingDays1']==14
                settings_board=client.find('boards','b')[0]
                assert settings_board['allowsDueDate'] is False and settings_board['cardAgingDays1']==14
                assert settings_board['legacySetting']==now
                print('PASS: shared REST card settings return defaults, enforce admin access and preserve unrelated BSON')

                label_path='/api/boards/b/labels'
                assert request('PUT',label_path,dict(label=dict(name='Bad',color='invalid')),token)[0]==400
                status,_,body=request('PUT',label_path,dict(label=' Bug '),token)
                assert status==200,(status,body)
                label_id=json.loads(body)
                assert isinstance(label_id,str)
                assert client.find('boards','b')[0]['labels']==[dict(_id=label_id,name='Bug',color='green')]
                repeat=request('PUT',label_path,dict(label=dict(name='Bug',color='green')),token)
                assert repeat[0]==200 and json.loads(repeat[2])==label_id
                assert len(client.find('boards','b')[0]['labels'])==1
                print('PASS: shared board label creation returns a bare ID and deduplicates trimmed names')
                labels_path='/api/boards/b/cards/labels'
                assert request('POST',labels_path,dict(cardIds=[card['_id']],addLabelIds=[],removeLabelIds=[]),token)[0]==400
                status,_,body=request('POST',labels_path,dict(cardIds=[card['_id'],'missing'],addLabelIds=[label_id,label_id]),token)
                assert (status,json.loads(body))==(200,dict(updated=[{'_id':card['_id'],'labelIds':[label_id]}],notFound=['missing']))
                assert client.find('cards',card['_id'])[0]['labelIds']==[label_id]
                status,_,body=request('POST',labels_path,dict(cardIds=[card['_id']],removeLabelIds=[label_id]),token)
                assert status==200 and json.loads(body)['updated'][0]['labelIds']==[]
                assert client.find('cards',card['_id'])[0]['labelIds']==[]
                print('PASS: shared bulk labels preserve request order, report missing cards and clear the last label')


                check_custom_api(request,client,database,token)
                check_export_policy(request,client,database)
                check_relation_scope(request,client,database)
                check_graph_snapshot(request,client,database,snapshot_control)
                check_clone_policy(request,client,database,token)
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
                tokens=['fixture-first-rest-token','fixture-second-rest-token','fixture-third-rest-token']
                records=[dict(hashedToken=base64.b64encode(hashlib.sha256(raw.encode()).digest()).decode(),when=now)
                         for raw in tokens]
                client.command({'update':'users','updates':[dict(q=dict(_id='u'),u={'$set':{'services.resume.loginTokens':records}})]})
                assert request('POST','/users/logout',{},tokens[0])[0]==200
                assert request('GET','/api/user',token=tokens[0])[0]==401
                assert client.find('users','u')[0]['services']['resume']['loginTokens']==records[1:]
                assert request('GET','/api/user',token=tokens[1])[0]==200
                assert request('GET',board_url)[0]==200
                assert request('POST','/users/logout',dict(all=True),tokens[1])[0]==200
                assert client.find('users','u')[0]['services']['resume']['loginTokens']==[]
                for raw in tokens[1:]:
                    assert request('GET','/api/user',token=raw)[0]==401
                assert request('GET',board_url)[0]==404
                print('PASS: shared REST logout preserves other sessions by default and revokes all on request')
                restart_token='fixture-restart-token'
                restart_record=dict(hashedToken=base64.b64encode(hashlib.sha256(restart_token.encode()).digest()).decode(),when=now)
                client.command({'update':'users','updates':[dict(q=dict(_id='u'),u={'$set':{'services.resume.loginTokens':[restart_record]}})]})
                assert request('GET','/api/user',token=restart_token)[0]==200
                stop();app=start('1')
                assert request('GET','/api/user',token=restart_token)[0]==200,'API token did not survive adapter restart'
                client.command({'update':'users','updates':[dict(q=dict(_id='u'),u={'$set':{'services.resume.loginTokens':[]}})]})
                assert request('GET','/api/user',token=restart_token)[0]==401
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
                stop();server[0].terminate();server[0].wait(timeout=10)
