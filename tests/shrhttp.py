"""Opt-in HTTP on the same canonical live FerretDB file, no filename aliases."""
import base64
import datetime
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
from layout import Forms
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
upstream_specs = os.environ.get('WELITE_WEKAN_API_SPECS','17-rest-api.e2e.js 23-rest-api-more.e2e.js').split()
if upstream:
    upstream = Path(upstream).resolve()
    playwright = upstream / 'node_modules/playwright/cli.js'
    if not playwright.is_file():
        raise SystemExit('WELITE_WEKAN_PLAYWRIGHT must point to WeKan tests/playwright with dependencies installed')
    if not upstream_specs or any(
        Path(name).name != name or name.startswith('-') or not name.endswith('.e2e.js')
        or not (upstream / 'specs' / name).is_file() for name in upstream_specs
    ):
        raise SystemExit('WELITE_WEKAN_API_SPECS must name existing spec files in WeKan tests/playwright/specs')
upstream_filter = os.environ.get('WELITE_WEKAN_API_GREP')
selected_backend = os.environ.get('WELITE_SHARED_BACKEND')
if selected_backend is not None:
    if selected_backend not in backends:
        raise SystemExit('WELITE_SHARED_BACKEND must be linked or cli')
    backends = {selected_backend: backends[selected_backend]}
strict_shared = os.environ.get('WELITE_SHARED_SHORT_TEST') == '1'
if strict_shared and upstream:
    raise SystemExit('Run upstream API tests separately from WELITE_SHARED_SHORT_TEST')
with sqlite3.connect(':memory:') as con:
    compiled_short = bool(con.execute("SELECT sqlite_compileoption_used('ENABLE_8_3_NAMES=2')").fetchone()[0])
    assert compiled_short == strict_shared, 'Python SQLite must use the selected sidecar mode'
def port():
    with socket.socket() as sock:sock.bind(('127.0.0.1',0));return sock.getsockname()[1]
with tempfile.TemporaryDirectory(prefix='wshared-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    def build(source,dest,flags=(),name=None):
        dest.mkdir(parents=True,exist_ok=True)
        result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(dest),'-FE'+str(dest),*(['-o'+str(dest/name)] if name else []),str(source)],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
    build(root/'tests/dbfile.lpr',tmp/'select')
    def selected(path,shared=False,extra=None,fresh=False):
        return subprocess.check_output([str(tmp/'select/dbfile'),str(path),'fresh-shared' if fresh else 'shared' if shared else 'native'],env=dict(os.environ,WELITE_SHARED='0',**(extra or {})),text=True).strip()
    cases=tmp/'paths';cases.mkdir()
    assert selected(cases)==str(cases/'wekan.db') and selected(cases,True)=='refused'
    assert selected(cases,fresh=True)==str(cases/'wekan.sqlite')
    assert selected(cases,extra={'WELITE_SHORT_NAMES':'1'},fresh=True)==str(cases/'wekan.db')
    strict_auto=subprocess.check_output([str(tmp/'select/dbfile'),str(cases),'auto-fresh'],
        env=dict(os.environ,WELITE_SHARED='',WELITE_SHORT_NAMES='1'),text=True).strip()
    assert strict_auto==str(cases/'wekan.db')
    assert list(cases.iterdir())==[]
    for orphan in ['wekan.sqlite-wal','wekan.db-shm','wekan.wal','other.sqlite']:
        (cases/orphan).touch()
        assert selected(cases)=='refused' and selected(cases,fresh=True)=='refused'
        (cases/orphan).unlink()
    (cases/'wekan.sqlite').touch()
    assert selected(cases)=='refused' and selected(cases,True)==str(cases/'wekan.sqlite')
    assert selected(cases,True,dict(WELITE_SHORT_NAMES='1'))=='refused'
    (cases/'wekan.db').touch();assert selected(cases,True)=='refused' and selected(cases)=='refused'
    (cases/'wekan.sqlite').unlink()
    for sidecar in ('wekan.wal','wekan.shm','wekan.nal','wekan.db-wal','wekan.db-shm','wekan.db-journal'):
        (cases/sidecar).touch()
        settings={'WELITE_SHORT_NAMES':'1'} if sidecar.startswith('wekan.db-') else {}
        assert selected(cases,True,settings)=='refused'
        (cases/sidecar).unlink()
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
            server=subprocess.Popen(mongo_command,env=env,stdout=mongo_log,stderr=mongo_log)
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
            def start(mode,store=None,**settings):
                proc=subprocess.Popen([str(out/'build/wlhttp')],env={**env,'WELITE_SHARED':mode,'WELITE_DATA':str(store or out/'data'),**settings},cwd=out,stdout=app_log,stderr=app_log)
                for _ in range(100):
                    try:
                        request('GET','/sign-in');return proc
                    except OSError:
                        assert proc.poll() is None;time.sleep(.05)
                proc.kill();proc.wait();raise AssertionError('HTTP startup timed out')
            try:
                wait_for_ferret()
                if not strict_shared:
                    for collection in ['boards','swimlanes','lists','cards','card_comments','checklists','checklistItems','customFields','users','activities','attachments']:
                        client.command({'create':collection})
                if upstream:
                    for collection in ['rules','triggers','actions','integrations','eventlog','savedCardFilters','scrumSnapshotRows','org','team']:
                        client.command({'create':collection})
                    app=start('1')
                    subprocess.run([
                        os.environ.get('NODE','node'),str(playwright),'test',
                        *upstream_specs,
                        '--reporter=list','--output',str(out/'playwright-results'),
                        *(['--grep', upstream_filter] if upstream_filter else []),
                    ],cwd=upstream,env=dict(env,
                        WEKAN_BASE_URL=f'http://127.0.0.1:{http_port}',
                        WEKAN_MONGO_URL=f'mongodb://127.0.0.1:{mongo_port}/wekan',
                        WEKAN_PLAYWRIGHT_PROJECT='chromium',WEKAN_PLAYWRIGHT_PROBE='0',
                        WEKAN_PLAYWRIGHT_ALL='0',WEKAN_PLAYWRIGHT_WORKERS='1'),
                        check=True)
                    continue
                for extension in (('db',) if strict_shared else ('sqlite','db')):
                    fresh=out/('fresh-'+extension)
                    fresh_data=fresh/'local/files/db'
                    fresh_data.mkdir(parents=True)
                    fresh_file=fresh_data/('wekan.'+extension)
                    alternate=fresh_data/('wekan.sqlite' if extension=='db' else 'wekan.db')
                    fresh_port=port()
                    fresh_client=Client(fresh_port)
                    fresh_url=fresh_data.as_uri()+'/?dbext='+extension
                    if strict_shared:
                        fresh_url+='&shortnames=1'
                    fresh_command=[str(ferret),'--handler=sqlite','--sqlite-url='+fresh_url,
                        '--state-dir='+str(out/('fresh-state-'+extension)),'--listen-addr=127.0.0.1:'+str(fresh_port),
                        '--debug-addr=127.0.0.1:'+str(port()),'--log-level=ERROR','--telemetry=disable']
                    fresh_server=subprocess.Popen(fresh_command,env=env,stdout=mongo_log,stderr=mongo_log)
                    try:
                        for _ in range(100):
                            try:
                                fresh_client.command({'ping':1})
                                break
                            except OSError:
                                assert fresh_server.poll() is None
                                time.sleep(.05)
                        else:
                            raise AssertionError('FerretDB did not start')
                        assert fresh_client.command({'find':'users'})['cursor']['firstBatch']==[]
                        assert not fresh_file.exists()
                        databases=fresh_client.command({'listDatabases':1,'nameOnly':True},database='admin')
                        assert 'wekan' not in {row['name'] for row in databases['databases']}
                        if extension=='db' and not strict_shared:
                            fresh_client.command({'create':'users'})
                        app=start('1' if extension=='db' else '',fresh,WELITE_SHORT_NAMES='1' if strict_shared else '')
                        assert request('GET','/sign-in')[0]==200
                        assert fresh_file.is_file() and not alternate.exists()
                        with sqlite3.connect(fresh_file) as con:
                            names={row[0] for row in con.execute('SELECT name FROM _ferretdb_collections')}
                            assert {'users','boards','swimlanes','lists','cards'} <= names
                            assert con.execute("SELECT type FROM sqlite_master WHERE name='users'").fetchone()==('view',)
                        assert fresh_client.command({'find':'users'})['cursor']['firstBatch']==[]
                        databases=fresh_client.command({'listDatabases':1,'nameOnly':True},database='admin')
                        assert 'wekan' in {row['name'] for row in databases['databases']}
                        assert {'users','boards'} <= {row['name'] for row in
                            fresh_client.command({'listCollections':1})['cursor']['firstBatch']}
                        fresh_password={'bcrypt':'$2b$04$......................b8CYpLYfgS/XMWDCU3/.oCRJREnOf3y'}
                        assert fresh_client.command({'insert':'users','documents':[
                            dict(_id='first-user',username='first-user',services=dict(password=fresh_password))]})['n']==1
                        status,_,body=request('POST','/users/login',dict(username='first-user',password='test-password'))
                        assert status==200 and json.loads(body)['id']=='first-user',(status,body)
                        status,headers,_=request('POST','/sign-in',urlencode(
                            dict(username='first-user',password='test-password')))
                        assert status==302 and 'Set-Cookie' not in headers,(status,headers)
                        assert request('GET',headers['Location'])[0]==200
                        published=fresh_client.find('users','first-user')[0]['services']['resume']['loginTokens']
                        assert len(published)==1,published
                        if strict_shared:
                            assert (fresh_data/'wekan.wal').is_file()
                            assert (fresh_data/'wekan.shm').is_file()
                            assert not (fresh_data/'wekan.db-wal').exists()
                            assert not (fresh_data/'wekan.db-shm').exists()
                            token=json.loads(body)['token']
                            stop()
                            app=start('1',fresh,WELITE_SHORT_NAMES='1')
                            assert request('GET','/api/user',token=token)[0]==200
                    finally:
                        fresh_server.terminate()
                        fresh_server.wait(timeout=10)
                        stop()
                    if strict_shared:
                        print('PASS: running FerretDB discovers fresh strict shared storage and retains API login across HTTP restart')
                    elif extension=='db':
                        print('PASS: FerretDB and WeLite share one wekan.db with standard sidecars')
                    else:
                        print('PASS: running FerretDB discovers the fresh database provisioned through HTTP')

                occupied=out/'occupied'
                occupied_data=occupied/'local/files/db'
                occupied_data.mkdir(parents=True)
                occupied_file=occupied_data/('wekan.db' if strict_shared else 'wekan.sqlite')
                with sqlite3.connect(occupied_file) as con:
                    con.execute('CREATE TABLE users (id TEXT PRIMARY KEY)')
                    con.execute("INSERT INTO users VALUES ('retained')")
                for mode in (('1',) if strict_shared else ('','1')):
                    app=start(mode,occupied,WELITE_SHORT_NAMES='1' if strict_shared else '')
                    assert request('GET','/sign-in')[0]==404
                    stop()
                with sqlite3.connect(occupied_file) as con:
                    assert con.execute('SELECT id FROM users').fetchall()==[('retained',)]
                    assert con.execute("SELECT name FROM sqlite_master WHERE name='_ferretdb_collections'").fetchone() is None
                assert not (occupied_data/('wekan.sqlite' if strict_shared else 'wekan.db')).exists()
                if strict_shared:
                    print('PASS: strict shared provisioning preserves an existing native database')
                    continue

                native_fresh=out/'native-fresh'
                app=start('0',native_fresh)
                assert request('GET','/sign-in')[0]==200
                stop()
                native_data=native_fresh/'local/files/db'
                assert (native_data/'wekan.db').is_file() and not (native_data/'wekan.sqlite').exists()
                native_file=native_data/'wekan.db'
                with sqlite3.connect(native_file) as con:
                    assert con.execute("SELECT type FROM sqlite_master WHERE name='integrations'").fetchone()==('table',)
                    con.execute('DROP TABLE integrations')
                app=start('',native_fresh)
                assert request('GET','/sign-in')[0]==200
                with sqlite3.connect(native_file) as con:
                    assert con.execute("SELECT type FROM sqlite_master WHERE name='integrations'").fetchone()==('table',)
                form=urlencode(dict(username='native-user',password='test-password',confirm='test-password'))
                status,headers,_=request('POST','/register',form)
                assert status==302 and 'Set-Cookie' not in headers
                native_session=parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
                status,_,body=request('POST','/users/login',dict(username='native-user',password='test-password'))
                assert status==200,(status,body)
                native_token=json.loads(body)['token']
                native_boards=[]
                for title in ('Integration board','Other board'):
                    status,_,body=request('POST','/api/boards',dict(title=title,permission='private'),native_token)
                    assert status==200,(status,body)
                    native_boards.append(json.loads(body)['_id'])
                integration_base='/api/boards/'+native_boards[0]+'/integrations'
                assert request('POST',integration_base,dict(url='https://1.1.1.1/hook'))[0]==401
                assert request('POST',integration_base,dict(url='https://127.0.0.1/hook'),native_token)[0]==400
                status,_,body=request('POST',integration_base,dict(url='https://1.1.1.1/hook'),native_token)
                assert status==200,(status,body)
                integration_id=json.loads(body)['_id']
                integration=integration_base+'/'+integration_id
                status,_,body=request('GET',integration,token=native_token)
                assert status==200,(status,body)
                document=json.loads(body)
                assert document['activities']==['all'] and document['boardId']==native_boards[0]
                assert document['enabled'] is True and document['createdAt'].endswith('Z')
                wrong='/api/boards/'+native_boards[1]+'/integrations/'+integration_id
                assert request('DELETE',wrong,token=native_token)[0]==404
                assert request('PUT',integration,dict(url='https://[::1]/',title='invalid'),native_token)[0]==400
                assert json.loads(request('GET',integration,token=native_token)[2])==document
                changes=dict(url='https://1.0.0.1/updated',title='Updated',enabled=False,activities=[])
                assert request('PUT',integration,changes,native_token)[0]==200
                assert json.loads(request('GET',integration_base,token=native_token)[2])==[dict(document,**changes)]
                native_page='/board/webhooks?id='+native_boards[0]+'&sessionId='+native_session
                status,headers,body=request('GET',native_page)
                assert status==200 and 'Set-Cookie' not in headers and b'Updated' in body
                assert request('DELETE',integration,token=native_token)[0]==200
                assert request('GET',integration,token=native_token)[0]==404
                assert request('POST',integration_base,dict(url='https://1.1.1.1/cleanup'),native_token)[0]==200
                assert request('DELETE','/api/boards/'+native_boards[0],token=native_token)[0]==200
                with sqlite3.connect(native_file) as con:
                    assert con.execute('SELECT count(*) FROM integrations').fetchone()==(0,)
                print('PASS: native REST integrations support legacy upgrade, scoped CRUD and board cascade')
                stop()
                assert not (native_data/'wekan.sqlite').exists()

                if backend=='cli':
                    fallback=out/'no-extension'
                    app=start('',fallback,WELITE_SQLITE_EXT='')
                    assert request('GET','/sign-in')[0]==200
                    stop()
                    fallback_data=fallback/'local/files/db'
                    assert (fallback_data/'wekan.db').is_file()
                    assert not (fallback_data/'wekan.sqlite').exists()
                print('PASS: native provisioning and reuse preserve the native store')

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
                app=start('')
                assert request('GET','/sign-in')[0]==200 and not shadow.exists()
                with sqlite3.connect(database) as con:
                    assert con.execute("SELECT type FROM sqlite_master WHERE name='users'").fetchone()==('view',)
                status,_,body=request('POST','/users/login',dict(username='user',password='test-password'))
                assert status==200,(backend,status,body)
                login=json.loads(body);token=login['token']
                assert login['id']=='u' and request('GET','/api/boards/b',token=token)[0]==200
                policy_collection='tableVisibilityModeSettings'
                client.command({'create':policy_collection})
                client.command({'insert':policy_collection,'documents':[
                    dict(_id='tableVisibilityMode-boardCreationAdminOnly',booleanValue=True),
                    dict(_id='tableVisibilityMode-allowPrivateOnly',booleanValue=True),
                ]})
                board_body=dict(title='Created board',permission='public',owner='foreign-user')
                assert request('POST','/api/boards',board_body,token)[0]==403
                client.command({'update':policy_collection,'updates':[
                    dict(q={'_id':'tableVisibilityMode-boardCreationAdminOnly'},u={'$set':{'booleanValue':False}})]})
                status,_,body=request('POST','/api/boards',board_body,token)
                assert status==200,(status,body)
                created_board=json.loads(body)
                saved_board,=client.find('boards',created_board['_id'])
                owner,=saved_board['members']
                assert owner['userId']=='u' and owner['isAdmin'] is True and owner['isActive'] is True
                assert saved_board['permission']=='private'
                default_lane,=client.find('swimlanes',created_board['defaultSwimlaneId'])
                assert default_lane['boardId']==created_board['_id']
                assert request('DELETE','/api/boards/'+created_board['_id'],token=token)[0]==200
                print('PASS: REST board creation obeys shared settings and creates the caller owner and default swimlane')
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
                assert request('PUT',card_path,dict(members=['u']),token)[0]==200
                def my_cards(query=''):
                    status,_,body=request('GET','/api/user/cards'+query,token=token)
                    assert status==200,(status,body)
                    return {item['_id']:item for item in json.loads(body)}
                assert my_cards('?due=yes&from=2026-06-07&to=2026-06-08')[card['_id']]['members']==['u']
                assert card['_id'] not in my_cards('?to=2026-06-06')
                board_members=client.find('boards','b')[0]['members']
                def set_card_membership(members):
                    result=client.command({'update':'boards','updates':[dict(q={'_id':'b'},u={'$set':{'members':members}})]})
                    assert result['n']==1 and not result.get('writeErrors'),result
                    assert client.find('boards','b')[0]['members']==members,(result,client.find('boards','b')[0]['members'],members)
                try:
                    set_card_membership([dict(board_members[0],isReadAssignedOnly=True)])
                    assert card['_id'] not in my_cards()
                    set_card_membership([])
                    assert card['_id'] not in my_cards()
                finally:
                    set_card_membership(board_members)
                assert request('PUT',card_path,dict(members=[]),token)[0]==200
                stored=client.find('cards',card['_id'])[0]
                print('PASS: shared My Cards requires active board membership and applies due date bounds')
                dep_source='dep-source';dep_target='dep-target'
                client.command({'insert':'cards','documents':[dict(_id=card_id,boardId='b',
                    swimlaneId='s',listId='l',title='Dependency fixture',archived=False)
                    for card_id in (dep_source,dep_target)]})
                dep_path=f"/api/boards/b/cards/{dep_source}/dependencies"
                dep_item=dep_path+'/'+dep_target
                dep_input=dict(cardId=dep_target,type='blocks')
                try:
                    set_card_membership([dict(userId='u',isActive=True,isReadOnly=True,isNormalAssignedOnly=False,isWorker=False)])
                    assert request('POST',dep_path,dep_input,token)[0]==403
                    set_card_membership([dict(userId='u',isActive=True,isReadOnly=False,isNormalAssignedOnly=True,isWorker=False)])
                    assert request('POST',dep_path,dep_input,token)[0]==403
                    set_card_membership([dict(userId='u',isActive=True,isReadOnly=False,isNormalAssignedOnly=False,isWorker=True)])
                    dependency_response=request('POST',dep_path,dep_input,token)
                    assert dependency_response[0]==200,dependency_response
                    assert request('PUT',dep_item,dict(type='fixes'),token)[0]==200
                    before=client.find('cards',dep_source)[0]['cardDependencies']
                    with sqlite3.connect(database) as con:
                        con.execute("CREATE TRIGGER dependency_revoke INSTEAD OF UPDATE ON card_dependencies "
                                    "BEGIN DELETE FROM board_members WHERE boardId='b' AND userId='u'; END")
                    try:
                        assert request('PUT',dep_item,dict(type='blocks'),token)[0]==409
                        assert client.find('cards',dep_source)[0]['cardDependencies']==before
                        assert client.find('boards','b')[0]['members'][0]['isWorker'] is True
                    finally:
                        with sqlite3.connect(database) as con:
                            con.execute('DROP TRIGGER dependency_revoke')
                    assert request('DELETE',dep_item,token=token)[0]==200
                    status,_,body=request('DELETE',dep_item,token=token)
                    assert status==404 and json.loads(body)=={'error':'Dependency not found'}
                finally:
                    set_card_membership(board_members)
                    client.command({'delete':'cards','deletes':[dict(q={'_id':card_id},limit=1)
                        for card_id in (dep_source,dep_target)]})
                print('PASS: REST dependencies enforce role and assignment scope and roll back permission changes')
                domain_path='/api/boards/b/domains'
                assert request('GET',domain_path,token=token)[0]==403
                assert request('POST',domain_path,dict(domain='user@example.com'),token)[0]==400
                for domain in ('  PARTNER.EXAMPLE  ', 'partner.example'):
                    status,_,body=request('POST',domain_path,dict(domain=domain),token)
                    assert status==200 and json.loads(body)==[dict(domain='partner.example',isActive=True)]
                status,_,body=request('POST',domain_path,dict(domain='second.example'),token)
                assert status==200 and len(json.loads(body))==2
                normalized_delete=domain_path+'/%20PARTNER.EXAMPLE%20'
                status,_,body=request('DELETE',normalized_delete,token=token)
                assert status==200 and json.loads(body)==[dict(domain='second.example',isActive=True)],(status,body)
                assert client.find('boards','b')[0]['domains']==[dict(domain='second.example',isActive=True)]
                status,_,body=request('DELETE',normalized_delete,token=token)
                assert status==404 and json.loads(body)=={'error':'Domain not found'}
                assert request('DELETE',domain_path+'/second.example',token=token)[0]==200
                client.command({'update':'boards','updates':[dict(q={'_id':'b'},u={'$unset':{'domains':''}})]})
                print('PASS: board domain writes normalize names and preserve siblings on deletion')
                assert request('PUT',card_path,dict(dueAt='invalid'),token)[0]==404
                assert client.find('cards',card['_id'])[0]==stored
                assert request('PUT',card_path,dict(receivedAt=None,startAt='null',dueAt='',endAt=''),token)[0]==200
                cleared=client.find('cards',card['_id'])[0]
                assert all(field not in cleared for field in dates)
                print('PASS: shared REST card dates set as BSON Date and clear by field removal')

                update=dict(dueComplete=True,stickers=[dict(icon='star',highlight='round')],
                            locations=[dict(name='HQ',latitude='60.17',longitude=24.94)])
                assert request('PUT',card_path,update,token)[0]==200
                decorated,=client.find('cards',card['_id'])
                assert decorated['dueComplete'] is True and decorated['stickers']==update['stickers']
                location,=decorated['locations']
                assert location['_id'] and location['name']=='HQ' and location['latitude']==60.17 and location['longitude']==24.94
                assert request('PUT',card_path,dict(dueComplete=False,locations=[dict(latitude='bad')]),token)[0]==400
                assert client.find('cards',card['_id'])[0]==decorated
                assert request('PUT',card_path,dict(dueComplete=False,stickers=[],locations=[]),token)[0]==200
                undecorated,=client.find('cards',card['_id'])
                assert undecorated['dueComplete'] is False and undecorated['stickers']==[] and undecorated['locations']==[]
                print('PASS: REST card decorations normalize coordinates and reject invalid updates atomically')

                for payload,overtime in [(dict(isOverTime=True),True),('isOverTime=false',False)]:
                    status,_,body=request('PUT',card_path,payload,token)
                    assert status==200 and json.loads(body)==dict(_id=card['_id'])
                    stored=client.find('cards',card['_id'])[0]
                    assert stored['isOvertime'] is overtime and 'isOverTime' not in stored
                    status,_,body=request('GET',card_path,token=token)
                    assert status==200 and json.loads(body)['isOvertime'] is overtime
                status,_,body=request('PUT',card_path,dict(isOverTime=None,title='Do not write'),token)
                assert status==400 and json.loads(body)==dict(error='Invalid isOverTime')
                assert client.find('cards',card['_id'])[0]==stored
                print('PASS: REST overtime uses the canonical boolean and rejects invalid edits atomically')

                for payload,sort in [(dict(sort=0),0),(dict(sort=-1.25),-1.25),('sort=0',0)]:
                    status,_,body=request('PUT',card_path,payload,token)
                    assert status==200 and json.loads(body)==dict(_id=card['_id'])
                    stored=client.find('cards',card['_id'])[0]
                    assert stored['sort']==sort
                    status,_,body=request('GET',card_path,token=token)
                    assert status==200 and json.loads(body)['sort']==sort
                status,_,body=request('PUT',card_path,dict(sort=' ',title='Do not write'),token)
                assert status==400 and json.loads(body)==dict(error='Invalid sort')
                assert client.find('cards',card['_id'])[0]==stored
                print('PASS: REST card sort persists zero and fractional values and rejects invalid edits atomically')

                for relation,noun,key in [('members','Member','memberId'),('assignees','Assignee','assigneeId')]:
                    endpoint=card_path+'/'+relation+'/u'
                    for method,prefix,assigned in [('POST','join',['u']),('DELETE','unjoin',[])]:
                        for _ in range(2):
                            status,_,body=request(method,endpoint,token=token)
                            assert status==200 and json.loads(body)[relation]==assigned,(status,body)
                        events=client.command({'find':'activities','filter':{
                            'cardId':card['_id'],'activityType':prefix+noun,key:'u'}})['cursor']['firstBatch']
                        event,=events
                        assert (event['username'],event['boardId'],event['listId'])==('user','b','l')
                print('PASS: dedicated REST assignments record one activity for each actual addition or removal')

                for payload,description in [(dict(description="O'Brien"),"O'Brien"),
                                            (dict(description=None),''),('description=From+form','From form'),
                                            ('description=','')]:
                    status,_,body=request('PUT',card_path,payload,token)
                    assert status==200 and json.loads(body)['description']==description,(status,body)
                    stored=client.find('cards',card['_id'])[0]
                    assert stored['description']==description
                for invalid in [0,False,[],{}]:
                    status,_,body=request('PUT',card_path,dict(description=invalid,title='Do not write'),token)
                    assert status==400 and json.loads(body)==dict(error='Invalid description')
                    assert client.find('cards',card['_id'])[0]==stored
                print('PASS: REST card description clears with null or empty form values and rejects invalid edits atomically')

                status,_,body=request('POST','/api/boards/b/lists/l/cards',
                    dict(title='Single subtask',swimlaneId='s',parentId=card['_id']),token)
                assert status==200,(status,body)
                subtask_id=json.loads(body)['_id']
                assert client.find('cards',subtask_id)[0]['parentId']==card['_id']
                assert request('DELETE','/api/boards/b/lists/l/cards/'+subtask_id,token=token)[0]==200
                print('PASS: single REST card creation persists its visible parent')

                export_path='/api/boards/b/export'
                assert request('GET',export_path+'?listId=l',token=token)[0]==400
                for collection in ['rules','triggers','actions']:
                    client.command({'create':collection})
                client.command({'insert':'rules','documents':[
                    dict(_id='rule-b',boardId='b',triggerId='trigger-b',actionId='action-b',
                         extraTriggerIds=['trigger-extra','trigger-extra'],extraActionIds=['action-extra']),
                    dict(_id='rule-other',boardId='other',triggerId='trigger-other',actionId='action-other')]})
                client.command({'insert':'triggers','documents':[
                    dict(_id=key,activityType='createCard') for key in ['trigger-b','trigger-extra','trigger-other']]})
                client.command({'insert':'actions','documents':[
                    dict(_id=key,actionType='moveCardToTop') for key in ['action-b','action-extra','action-other']]})
                status,_,body=request('GET',export_path+'?attachments=false',token=token)
                assert status==200,(status,body)
                exported=json.loads(body)
                assert exported['_format']=='wekan-board-1.0.0' and exported['cards'][0]['_id']==card['_id']
                assert [r['_id'] for r in exported['rules']]==['rule-b']
                assert [r['_id'] for r in exported['triggers']]==['trigger-b','trigger-extra']
                assert [r['_id'] for r in exported['actions']]==['action-b','action-extra']
                import_path='/api/boards/import'
                invalid_export=dict(exported,rules=[dict(exported['rules'][0],triggerId='missing')])
                assert request('POST',import_path,dict(board=invalid_export),token)[0]==400
                input_card=exported['cards'][0]['_id']
                imported_payload=dict(exported,comments=[dict(_id='import-comment',cardId=input_card,text='Imported comment')],
                    checklists=[dict(_id='import-checklist',cardId=input_card,title='Imported checklist',
                                     dueAt='2026-06-07T12:00:00.000Z')],
                    checklistItems=[dict(_id='import-item',checklistId='import-checklist',cardId=input_card,
                                         title='Imported item',isFinished=True)])
                client.command({'insert':'users','documents':[dict(_id='import-local-author',username='import-local-author')]})
                mapping={'external-author':'import-local-author','external-alias':'import-local-author'}
                imported_payload['cards']=[dict(exported['cards'][0],members=['external-author','external-alias','unmapped'],
                    assignees=['external-alias'],requesters=['external-author'],assigners=['unmapped'])]
                imported_payload['customFields']=[
                    dict(_id='import-field',name='Imported field',type='dropdownMultiSelect',alwaysOnCard=True,
                         settings=dict(dropdownItems=[dict(_id='keep-option',name='Choice')])),
                    dict(_id='import-empty',name='Empty field',type='text')]
                imported_payload['cards'][0]['customFields']=[
                    dict(_id='import-field',value=['keep-option']),dict(_id='import-empty',value=None)]
                unknown_field=dict(imported_payload,cards=[dict(imported_payload['cards'][0],
                    customFields=[dict(_id='missing',value='unknown')])])
                assert request('POST',import_path,dict(board=unknown_field),token)[0]==400
                imported_payload['cards'][0].update(createdAt='2026-01-02T03:04:05.000Z',
                    receivedAt='2026-02-01T00:00:00.000Z',startAt='2026-02-02T00:00:00.000Z',
                    dueAt='2026-02-03T00:00:00.000Z',endAt='2026-02-04T00:00:00.000Z',
                    spentTime=1.25,isOvertime=True,requestedBy="O'Brien",assignedBy='Scheduler',archived=True)
                created_in_history='2025-01-02T03:04:05.000Z'
                imported_payload['activities']=[
                    dict(activityType='createCard',cardId=input_card,createdAt=created_in_history,userId='external-author'),
                    dict(activityType='createCard',cardId='unrelated',createdAt='invalid',userId='unknown')]
                broken_dates=dict(imported_payload,cards=[dict(imported_payload['cards'][0],startAt='invalid')])
                assert request('POST',import_path,dict(board=broken_dates),token)[0]==400
                imported_payload['labels']=[dict(_id='source-label',name='Imported label',color='green')]
                imported_payload['cards'][0]['labelIds']=['source-label','source-label']
                for collection in ['triggers','actions']:
                    imported_payload[collection]=[dict(row,labelId='source-label') for row in exported[collection]]
                unknown_label=dict(imported_payload,cards=[dict(imported_payload['cards'][0],labelIds=['missing'])])
                assert request('POST',import_path,dict(board=unknown_label),token)[0]==400
                imported_payload['members']=[dict(userId='external-author',isActive=True,isAdmin=True)]
                imported_payload['comments'][0]['userId']='external-author'
                assert request('POST',import_path,dict(board=imported_payload,
                    membersMapping={'external-author':'unknown-user'}),token)[0]==400
                attachment_contents=b'Board import binary fixture\x00'
                imported_payload['attachments']=[dict(_id='import-attachment',cardId=input_card,name='Imported file.bin',
                    type='application/octet-stream',file=base64.b64encode(attachment_contents).decode())]
                imported_payload['cards'][0]['coverId']='import-attachment'
                bad_payload=dict(imported_payload,rules=invalid_export['rules'])
                stored_before=set(data.parent.glob('attachme/**/*.bin'))
                assert request('POST',import_path,dict(board=bad_payload),token)[0]==400
                assert set(data.parent.glob('attachme/**/*.bin'))==stored_before
                status,_,body=request('POST',import_path,dict(board=imported_payload,membersMapping=mapping),token)
                assert status==200,(status,body)
                imported_id=json.loads(body)['_id']
                assert imported_id!='b'
                def imported_rows(collection):
                    return client.command({'find':collection,'filter':dict(boardId=imported_id)})['cursor']['firstBatch']
                imported_rule,=imported_rows('rules')
                assert imported_rule['triggerId']!='trigger-b' and imported_rule['actionId']!='action-b'
                assert set(imported_rule['extraTriggerIds'])<={r['_id'] for r in imported_rows('triggers')}
                imported_card,=imported_rows('cards')
                assert imported_card['listId'] in {r['_id'] for r in imported_rows('lists')}
                assert imported_card['swimlaneId'] in {r['_id'] for r in imported_rows('swimlanes')}
                assert imported_card['members']==imported_card['assignees']==imported_card['requesters']==['import-local-author']
                assert imported_card['assigners']==[]
                for field in ['createdAt','receivedAt','startAt','dueAt','endAt']:
                    original=created_in_history if field=='createdAt' else imported_payload['cards'][0][field]
                    instant=datetime.datetime.fromisoformat(original.replace('Z','+00:00'))
                    assert imported_card[field]==DateMs(int(instant.timestamp()*1000)),(field,imported_card[field])
                for field in ['spentTime','isOvertime','requestedBy','assignedBy','archived']:
                    assert imported_card[field]==imported_payload['cards'][0][field],(field,imported_card[field])
                assert imported_card['userId']=='import-local-author'
                print('PASS: matching card creation activity supplies the original date and mapped author')
                print('PASS: board import preserves card scheduling dates, elapsed time, bylines and archive status')
                imported_label,=client.find('boards',imported_id)[0]['labels']
                assert imported_label['_id']!='source-label'
                assert imported_label['name']=='Imported label' and imported_label['color']=='green'
                assert imported_card['labelIds']==[imported_label['_id']]
                for collection in ['triggers','actions']:
                    assert {row['labelId'] for row in imported_rows(collection)}=={imported_label['_id']}
                print('PASS: board import remaps label references on cards and workflow actions and triggers')
                imported_fields=client.command({'find':'customFields','filter':{'boardIds':imported_id}})['cursor']['firstBatch']
                by_name={field['name']:field for field in imported_fields}
                dropdown=by_name['Imported field']
                assert dropdown['_id']!='import-field' and dropdown['alwaysOnCard'] is True
                assert dropdown['settings']['dropdownItems']==[dict(_id='keep-option',name='Choice')]
                assert imported_card['customFields']==[
                    dict(_id=dropdown['_id'],value=['keep-option']),
                    dict(_id=by_name['Empty field']['_id'],value=None)],imported_card['customFields']
                print('PASS: board import remaps field definitions, preserves dropdown choices and stores mapped card values')
                print('PASS: board import remaps and deduplicates card participant arrays')
                imported_comment,=imported_rows('card_comments')
                imported_check,=imported_rows('checklists')
                imported_item,=imported_rows('checklistItems')
                assert imported_comment['cardId']==imported_check['cardId']==imported_item['cardId']==imported_card['_id']
                assert imported_item['checklistId']==imported_check['_id'] and imported_item['isFinished'] is True
                assert isinstance(imported_check['dueAt'],DateMs)
                assert imported_comment['text']=='Imported comment' and imported_comment['userId']=='import-local-author'
                imported_members={row['userId']:row for row in client.find('boards',imported_id)[0]['members']}
                assert imported_members['u']['isAdmin'] is True
                assert imported_members['import-local-author']['isActive'] is False
                assert imported_members['import-local-author']['isAdmin'] is False
                print('PASS: board import maps authors to existing local users without granting board access')
                imported_attachment,=client.command({'find':'attachments','filter':{'meta.boardId':imported_id}})['cursor']['firstBatch']
                assert imported_attachment['meta']['cardId']==imported_card['_id']
                assert imported_card['coverId']==imported_attachment['_id']
                status,_,body=request('GET','/api/attachment/download/'+imported_attachment['_id'],token=token)
                assert status==200 and base64.b64decode(json.loads(body)['base64Data'])==attachment_contents
                print('PASS: shared board import preserves attachment bytes and rolls back staged files on failure')
                assert request('DELETE','/api/boards/'+imported_id,token=token)[0]==200
                print('PASS: shared board import remaps structure and workflows and rejects dangling workflow references')
                for lists,lanes in [
                    ([dict(_id='first',title='First',swimlaneId='second-lane')],
                     [dict(_id='first-lane',title='First lane'),dict(_id='second-lane',title='Second lane')]),
                    ([],[]),
                ]:
                    legacy=dict(title='Legacy placements',lists=lists,swimlanes=lanes,
                        cards=[dict(_id='old-card',title='Recover me',listId='dangling-list',swimlaneId='dangling-lane',coverId='missing-file')],
                        attachments=[dict(_id='old-file',cardId='old-card',name='Legacy file',
                                          file=base64.b64encode(attachment_contents).decode())])
                    status,_,body=request('POST',import_path,dict(board=legacy),token)
                    assert status==200,(status,body)
                    imported_id=json.loads(body)['_id']
                    restored,=imported_rows('cards')
                    restored_list,=imported_rows('lists')
                    restored_lane=client.find('swimlanes',restored['swimlaneId'])[0]
                    assert not restored.get('coverId')
                    assert restored['listId']==restored_list['_id']
                    assert restored_list['title']==('First' if lists else 'Default')
                    assert restored_lane['title']==('Second lane' if lanes else 'Default')
                    restored_file,=client.command({'find':'attachments','filter':{'meta.boardId':imported_id}})['cursor']['firstBatch']
                    for key in ['listId','swimlaneId']:
                        assert restored_file['meta'][key]==restored[key]
                    assert request('DELETE','/api/boards/'+imported_id,token=token)[0]==200
                print('PASS: legacy board import assigns cards and attachments to usable fallback lists and swimlanes')
                presentation=dict(title='List and swimlane display',lists=[
                    dict(_id='valid-list',title='Wide list',color='#336699',width=486,archived=True,collapsed=True),
                    dict(_id='invalid-list',title='Default width',color='invalid color',width=2000,collapsed=False),
                    dict(_id='legacy-list',title='Legacy collapse'),
                ],swimlanes=[
                    dict(_id='valid-lane',title='Colored lane',color='green',archived=True),
                    dict(_id='invalid-lane',title='Default color',color=['green']),
                ])
                presentation['cards']=[
                    dict(_id='palette-card',title='Green card',sort=100,cardNumber=47,listId='invalid-list',swimlaneId='invalid-lane',color='green'),
                    dict(_id='hex-card',title='Hex card',sort=200,cardNumber=47,listId='invalid-list',swimlaneId='invalid-lane',color='#123abc'),
                    dict(_id='unknown-card',title='Uncolored card',parentId='palette-card',listId='invalid-list',swimlaneId='invalid-lane',color='unknown'),
                ]
                presentation['cards'][0]['cardDependencies']=[
                    dict(cardId='hex-card',type='blocks',color='#123abc',icon='link'),
                    'unknown-card','unknown-card','foreign-card',
                ]
                presentation['cards'][0]['attachedCardIds']=[
                    'hex-card','foreign-card','hex-card','palette-card','unknown-card']
                presentation['cards'][1]['cardDependencies']=['palette-card']
                status,_,body=request('POST',import_path,dict(board=presentation),token)
                assert status==200,(status,body)
                imported_id=json.loads(body)['_id']
                restored_lists={row['title']:row for row in imported_rows('lists')}
                restored_lanes={row['title']:row for row in imported_rows('swimlanes')}
                wide=restored_lists['Wide list']
                assert wide['width']==486 and wide['color']=='#336699' and wide['archived'] is True
                assert restored_lists['Default width']['width']==272 and not restored_lists['Default width'].get('color')
                assert wide['collapsed'] is True
                assert restored_lists['Default width']['collapsed'] is False
                assert restored_lists['Legacy collapse'].get('collapsed') is None
                colored=restored_lanes['Colored lane']
                assert colored['color']=='green' and colored['archived'] is True
                assert not restored_lanes['Default color'].get('color')
                restored_cards={row['title']:row for row in imported_rows('cards')}
                assert restored_cards['Green card']['color']=='green'
                assert restored_cards['Hex card']['color']=='#123abc'
                assert not restored_cards['Uncolored card'].get('color')
                green,hexa,uncolored=[restored_cards[title] for title in ['Green card','Hex card','Uncolored card']]
                assert green['attachedCardIds']==[hexa['_id'],uncolored['_id']]
                assert not hexa.get('attachedCardIds')
                print('PASS: card attachments retain remapped order and discard duplicate, self and foreign targets')
                assert green['cardDependencies']==[
                    dict(cardId=hexa['_id'],type='blocks',color='#123abc',icon='link'),
                    dict(cardId=uncolored['_id'],type='related-to',color='#eb144c',icon='link'),
                ]
                assert [link['cardId'] for link in hexa['cardDependencies']]==[green['_id']]
                print('PASS: imported card dependencies remap typed and legacy links and omit foreign targets')
                assert [restored_cards[title]['cardNumber'] for title in
                        ['Green card','Hex card','Uncolored card']]==[47,1,2]
                status,_,body=request('POST','/api/boards/'+imported_id+'/lists/'+restored_lists['Default width']['_id']+'/cards',
                    dict(title='Created after import',swimlaneId=restored_lanes['Default color']['_id']),token)
                assert status==200,(status,body)
                created_after=client.find('cards',json.loads(body)['_id'])[0]
                assert created_after['cardNumber']==48
                print('PASS: board import preserves unique card numbers and normal creation continues the sequence')
                client.command({'update':'boards','updates':[
                    {'q':{'_id':imported_id},'u':{'$set':{'permission':'public'}}}]})
                status,headers,body=request('GET','/board?id='+imported_id+'&view=all')
                assert status==200 and 'Set-Cookie' not in headers
                assert b'bgcolor="#3cb500">Green card' in body and b'bgcolor="#123abc">Hex card' in body
                assert b'>Uncolored card</p>' in body
                assert b'<li>Uncolored card</li>' not in body
                status,headers,body=request('GET','/board?id='+imported_id+'&view=all&subtasks='+green['_id'])
                assert status==200 and 'Set-Cookie' not in headers and b'<li>Uncolored card</li>' in body
                print('PASS: cookie-free board HTML reveals a card’s same-board subtasks on request')
                assert body.index(b'>Green card</p>')<body.index(b'>Hex card</p>')
                hex_path='/api/boards/'+imported_id+'/lists/'+hexa['listId']+'/cards/'+hexa['_id']
                assert request('PUT',hex_path,dict(sort=0),token)[0]==200
                for _ in range(2):
                    status,headers,body=request('GET','/board?id='+imported_id+'&view=all')
                    assert status==200 and 'Set-Cookie' not in headers
                    assert body.index(b'>Hex card</p>')<body.index(b'>Green card</p>')
                print('PASS: cookie-free board HTML renders REST sort zero ahead of the prior first card')
                assert request('DELETE','/api/boards/'+imported_id,token=token)[0]==200
                print('PASS: board import preserves list width, card/list/swimlane colors and archived state')
                integrations='/api/boards/b/integrations'
                assert request('POST',integrations,{'url':'https://1.1.1.1/hook'})[0]==401
                for invalid_url in ('file:///tmp/hook','https://localhost/','https://127.0.0.1/',
                                    'https://[::1]/','https://169.254.169.254/',
                                    'https://[::ffff:127.0.0.1]/','https://example.invalid/'):
                    status,_,body=request('POST',integrations,{'url':invalid_url},token)
                    assert status==400 and json.loads(body)['error']=='invalid-webhook-url',(status,body)
                status,_,body=request('POST',integrations,{'url':'https://1.1.1.1/hook'},token)
                assert status==200,(status,body)
                new_integration=json.loads(body)['_id']
                stored,=client.find('integrations',new_integration)
                assert stored['boardId']=='b' and stored['userId']=='u' and stored['enabled'] is True
                assert stored['activities']==['all'] and stored['type']=='outgoing-webhooks'
                assert isinstance(stored['createdAt'],DateMs) and isinstance(stored['modifiedAt'],DateMs)
                new_path=integrations+'/'+new_integration
                assert request('PUT',new_path,{'url':'https://[::1]/','title':'invalid'},token)[0]==400
                assert client.find('integrations',new_integration)==[stored]
                destination='https://[2606:4700:4700::1111]/new'
                assert request('PUT',new_path,{'url':destination},token)[0]==200
                assert client.find('integrations',new_integration)==[dict(stored,url=destination)]
                assert request('DELETE',new_path,token=token)[0]==200
                print('PASS: integration creation and destination edits validate public IPv4 and IPv6 and retain typed defaults')
                client.command({'insert':'integrations','documents':[dict(_id='fixture-webhook',boardId='b',
                    userId='u',url='https://example.invalid/hook',token='fixture-secret',enabled=True,createdAt=now)]})
                integration_path='/api/boards/b/integrations/fixture-webhook'
                status,_,body=request('GET',integration_path,token=token)
                assert status==200,(status,body)
                integration=json.loads(body)
                assert integration['_id']=='fixture-webhook' and 'token' not in integration
                assert json.loads(request('GET','/api/boards/b/integrations',token=token)[2])==[integration]
                before_integration=client.find('integrations','fixture-webhook')[0]
                settings=dict(title='Updated webhook',enabled=False,activities=[])
                status,_,body=request('PUT',integration_path,settings,token)
                assert status==200 and json.loads(body)==dict(_id='fixture-webhook')
                updated=client.find('integrations','fixture-webhook')[0]
                assert updated==dict(before_integration,**settings)
                status,_,body=request('PUT',integration_path,dict(title='Invalid',activities=[False]),token)
                assert status==400 and client.find('integrations','fixture-webhook')[0]==updated
                assert request('PUT',integration_path,{},token)[0]==200
                assert client.find('integrations','fixture-webhook')[0]==updated
                print('PASS: shared integration metadata updates preserve credentials and reject invalid edits atomically')
                assert request('DELETE',integration_path)[0]==401
                status,_,body=request('DELETE','/api/boards/b/integrations/missing',token=token)
                assert status==404 and json.loads(body)==dict(error='Integration not found')
                client.command({'insert':'integrations','documents':[dict(_id='remove-webhook',boardId='b')]})
                delete_integration='/api/boards/b/integrations/remove-webhook'
                status,_,body=request('DELETE',delete_integration,token=token)
                assert status==200 and json.loads(body)==dict(_id='remove-webhook')
                assert request('GET',delete_integration,token=token)[0]==404
                assert client.find('integrations','fixture-webhook') and not client.find('integrations','remove-webhook')
                print('PASS: shared REST integration reads redact tokens and scoped deletion leaves siblings intact')
                assert request('PUT',integration_path,dict(enabled=True),token)[0]==200
                status,_,body=request('POST','/api/boards/b/copy',dict(title='Rule copy'),token)
                assert status==200,(status,body)
                copy_id=json.loads(body)
                def copied_rows(collection):
                    return client.command({'find':collection,'filter':dict(boardId=copy_id)})['cursor']['firstBatch']
                copied_rule,=copied_rows('rules')
                copied_hook,=copied_rows('integrations')
                assert copied_hook['url']=='https://example.invalid/hook' and copied_hook['createdAt']==now
                assert {r['_id'] for r in copied_rows('triggers')}=={copied_rule['triggerId'],*copied_rule['extraTriggerIds']}
                assert {r['_id'] for r in copied_rows('actions')}=={copied_rule['actionId'],*copied_rule['extraActionIds']}
                assert copied_rule['triggerId']!='trigger-b' and copied_rule['actionId']!='action-b'
                assert request('DELETE','/api/boards/'+copy_id,token=token)[0]==200
                for collection in ['rules','triggers','actions','integrations']:
                    assert copied_rows(collection)==[], collection
                assert client.find('rules','rule-b') and client.find('integrations','fixture-webhook')
                print('PASS: shared board copy remaps workflow identities and preserves typed webhook fields')
                rules_path='/api/boards/b/rules'
                assert request('GET',rules_path)[0]==401
                status,_,body=request('GET',rules_path,token=token)
                assert status==200,(status,body)
                rule,=json.loads(body)
                assert rule['_id']=='rule-b' and rule['trigger']=={'activityType':'createCard'}
                assert rule['action']=={'actionType':'moveCardToTop'}
                assert len(rule['extraTriggers'])==2 and len(rule['extraActions'])==1
                status,_,body=request('GET',rules_path+'/rule-b',token=token)
                assert status==200 and json.loads(body)==rule
                assert request('GET',rules_path+'/rule-other',token=token)[0]==404
                invalid_rule=dict(title='Bad rule',trigger=dict(activityType='createCard'),action={})
                assert request('POST',rules_path,invalid_rule,token)[0]==400
                good_rule=dict(title='Created rule',trigger=dict(activityType='createCard',boardId='other'),
                               action=dict(actionType='moveCardToTop'))
                status,_,body=request('POST',rules_path,good_rule,token)
                assert status==200,(status,body)
                ids=json.loads(body)
                saved,=client.find('rules',ids['_id'])
                trigger,=client.find('triggers',ids['triggerId'])
                action,=client.find('actions',ids['actionId'])
                assert saved['title']=='Created rule' and saved['triggerId']==trigger['_id'] and saved['actionId']==action['_id']
                assert trigger['boardId']=='b' and action['boardId']=='b'
                assert trigger['listName']==trigger['userId']==trigger['swimlaneName']==trigger['cardTitle']=='*'
                print('PASS: shared REST rule creation saves typed linked parts and defaults missing trigger fields')
                client.command({'update':'rules','updates':[dict(q={'_id':'rule-other'},
                    u={'$set':{'extraActionIds':[ids['actionId']]}})]})
                edit_path=rules_path+'/'+ids['_id']
                assert request('PUT',edit_path,dict(title='Must not persist',action={}),token)[0]==400
                assert client.find('rules',ids['_id'])[0]==saved
                status,_,body=request('PUT',edit_path,dict(title='Changed rule',enabled=False,
                    action=dict(actionType='moveCardToBottom')),token)
                assert status==200,(status,body)
                changed,=client.find('rules',ids['_id'])
                assert changed['title']=='Changed rule' and changed['enabled'] is False
                assert changed['actionId']!=ids['actionId'] and changed['triggerId']==ids['triggerId']
                assert client.find('actions',changed['actionId'])[0]['actionType']=='moveCardToBottom'
                assert client.find('actions',ids['actionId'])[0]==action
                print('PASS: shared REST rule edit copies a reused part and preserves the original')
                client.command({'update':'rules','updates':[dict(q={'_id':ids['_id']},
                    u={'$set':{'extraActionIds':[ids['actionId']]}})]})
                assert request('DELETE',rules_path+'/rule-other',token=token)[0]==404
                assert request('DELETE',edit_path,token=token)[0]==200
                assert request('DELETE',edit_path,token=token)[0]==404
                assert not client.find('rules',ids['_id'])
                assert not client.find('triggers',ids['triggerId'])
                assert not client.find('actions',changed['actionId'])
                assert client.find('actions',ids['actionId'])[0]==action
                print('PASS: shared REST rule deletion removes unused parts and retains parts used by another rule')
                exported_user,=exported['users']
                assert exported_user=={'_id':'u','username':'user','profile':{}},exported_user
                assert all(key not in exported_user for key in ('services','emails','loginTokens'))
                client.command({'create':'settings'})
                client.command({'insert':'settings','documents':[dict(_id='export-settings',disableAllExport=True)]})
                assert request('GET',export_path,token=token)[0]==403
                client.command({'delete':'settings','deletes':[dict(q={'_id':'export-settings'},limit=1)]})
                print('PASS: REST whole-board export uses typed data and honors the shared export guard')

                create_card_path='/api/boards/b/lists/l/cards'
                status,_,body=request('POST',create_card_path,dict(linkedId=card['_id'],swimlaneId='s'),token)
                assert status==200,(status,body)
                linked_id=json.loads(body)['_id']
                linked,=client.find('cards',linked_id)
                assert linked['type']=='cardType-linkedCard' and linked['linkedId']==card['_id']
                assert linked['title']==card['title'] and linked['userId']=='u'
                activities=client.command({'find':'activities','filter':dict(cardId=linked_id,activityType='createCard')})
                assert len(activities['cursor']['firstBatch'])==1
                assert request('POST',create_card_path,dict(linkedId=linked_id,swimlaneId='s'),token)[0]==400
                assert request('DELETE',create_card_path+'/'+linked_id,token=token)[0]==200
                card=client.find('cards',card['_id'])[0]
                print('PASS: linked REST cards store a reference, emit one creation activity, and refuse link chains')

                bulk_path='/api/boards/b/lists/l/cards/bulk'
                client.command({'create':'eventlog'})
                client.command({'insert':'boards','documents':[dict(_id='parent-private-board',title='Private parent board',
                    slug='private-parent-board',permission='private',members=[])]})
                client.command({'insert':'cards','documents':[dict(_id='parent-private-card',boardId='parent-private-board',
                    title='Private parent title',archived=False)]})
                for expected in (1,2):
                    status,_,body=request('POST',bulk_path,dict(swimlaneId='s',
                        cards=[dict(title='Rejected child',parentId='parent-private-card')]),token)
                    assert (status,json.loads(body))==(200,[dict(index=0,error='Forbidden')]),(status,body)
                    event,=client.command({'find':'eventlog','filter':dict(bleed='ParentBleed')})['cursor']['firstBatch']
                    assert event['count']==expected and isinstance(event['at'],DateMs) and isinstance(event['firstAt'],DateMs)
                    if expected==1:first_seen=event['firstAt']
                    else:assert event['firstAt']==first_seen
                    assert 'parent-private-card' not in str(event) and 'parent-private-board' not in str(event)
                print('PASS: shared parent denials fold into one typed event without private identifiers')
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
                webhook_page='/board/webhooks?id=b&lang=en&sessionId='+web_session
                assert request('GET','/board/webhooks?id=b')[0]==401
                status,head,body=request('GET',webhook_page)
                assert status==200 and 'Set-Cookie' not in head and 'no-store' in head['Cache-Control']
                assert b'Outgoing Webhooks' in body and b'fixture-secret' not in body
                assert b'/board/webhooks?id=b' in request('GET','/board?id=b&sessionId='+web_session)[2]
                hook_members=client.find('boards','b')[0]['members']
                def set_webhook_members(members):
                    assert client.command({'update':'boards','updates':[
                        {'q':{'_id':'b'},'u':{'$set':{'members':members}}}
                    ]})['n']==1
                set_webhook_members([dict(member,isAdmin=False) if member['userId']=='u' else member
                                     for member in hook_members])
                try:
                    assert request('GET',webhook_page)[0]==403
                    assert b'/board/webhooks?id=b' not in request('GET','/board?id=b&sessionId='+web_session)[2]
                finally:
                    set_webhook_members(hook_members)
                assert request('PUT',integration_path,dict(title='Refreshed <name>',enabled=False),token)[0]==200
                body=request('GET',webhook_page)[2]
                assert b'Refreshed &lt;name&gt;' in body and b'Refreshed <name>' not in body
                assert request('DELETE',integration_path,token=token)[0]==200
                assert b'Refreshed' not in request('GET',webhook_page)[2]
                print('PASS: cookie-free board webhook settings reflect REST changes on reload')
                def webhook_form(operation, identity=''):
                    parser=Forms()
                    parser.feed(request('GET',webhook_page)[2].decode())
                    return next(fields for path,fields in parser.forms if path=='/board/webhooks'
                                and fields.get('operation')==operation and fields.get('integrationId')==identity)
                creation=webhook_form('create')
                creation['url']='https://1.1.1.1/browser'
                assert request('POST','/board/webhooks',urlencode(dict(creation,boardId='other')))[0] in (403,404)
                status,head,_=request('POST','/board/webhooks',urlencode(creation))
                assert status==303 and 'Set-Cookie' not in head and 'sessionId=' in head['Location'],(status,head)
                assert request('POST','/board/webhooks',urlencode(creation))[0]==403
                made,=json.loads(request('GET','/api/boards/b/integrations',token=token)[2])
                edit=dict(webhook_form('save',made['_id']),title='Edited in HTML',url=creation['url'])
                assert request('POST','/board/webhooks',urlencode(edit))[0]==303
                edited,=client.find('integrations',made['_id'])
                assert edited['title']=='Edited in HTML' and edited['enabled'] is False
                removal=webhook_form('delete',made['_id'])
                assert request('POST','/board/webhooks',urlencode(removal))[0]==303
                assert not client.find('integrations',made['_id'])
                print('PASS: cookie-free webhook forms create, edit and delete with scoped one-use tokens')
                if os.environ.get('WELITE_UI')=='1':
                    subprocess.run([os.environ.get('NODE','node'),str(root/'tests/webhooks.js'),
                                    f'http://localhost:{http_port}'+webhook_page],input=token,text=True,check=True)
                attachment_id='shared-export-file'
                contents=b'WeLite export regression'
                digest=hashlib.sha256(attachment_id.encode()).hexdigest()
                chunks=[digest[i:i+8] for i in range(0,len(digest),8)]
                attachment_path=data.parent.joinpath('attachme',*chunks[:-1],chunks[-1]+'.bin')
                attachment_path.parent.mkdir(parents=True)
                attachment_path.write_bytes(contents)
                client.command({'insert':'attachments','documents':[dict(_id=attachment_id,name='export.txt',
                    type='text/plain',storageBackend='filesystem',metadata_json='{}',
                    meta=dict(boardId='b',listId='l',swimlaneId='s',cardId=card['_id']))]})
                original_card,=client.find('cards',card['_id'])
                description='<b>Export roadmap</b><script>ignored content</script>'
                def update_export_card(change):
                    assert client.command({'update':'cards','updates':[
                        dict(q={'_id':card['_id']},u=change)]})['n']==1
                update_export_card({'$set':{'description':description}})
                download='/board/export?id=b&sessionId='+web_session
                assert request('GET','/board/export?id=b')[0]==401
                board_page=request('GET','/board?id=b&sessionId='+web_session)
                assert board_page[0]==200 and b'/board/export?id=b' in board_page[2]
                for suffix in ('','&attachments=false'):
                    status,download_headers,body=request('GET',download+suffix)
                    assert status==200 and 'Set-Cookie' not in download_headers,(status,body)
                    assert download_headers['Content-Disposition']=='attachment; filename="board.json"'
                    document=json.loads(body)
                    exported_card=next(row for row in document['cards'] if row['_id']==card['_id'])
                    assert exported_card['description']=='Export roadmap'
                    exported=next(row for row in document['attachments'] if row['_id']==attachment_id)
                    if suffix:assert 'file' not in exported
                    else:assert base64.b64decode(exported['file'])==contents
                if os.environ.get('WELITE_UI')=='1':
                    subprocess.run([os.environ.get('NODE','node'),str(root/'tests/boardexp.js'),
                                    f'http://localhost:{http_port}/board?id=b&sessionId='+web_session,
                                    card['_id'],attachment_id,base64.b64encode(contents).decode('ascii'),
                                    'Export roadmap'],check=True)
                assert client.find('cards',card['_id'])[0]['description']==description
                if 'description' in original_card:
                    update_export_card({'$set':{'description':original_card['description']}})
                else:
                    update_export_card({'$unset':{'description':''}})
                client.command({'delete':'attachments','deletes':[dict(q={'_id':attachment_id},limit=1)]})
                print('PASS: cookie-free board download includes real attachment bytes only when requested')
                lane_id='delete-scope-lane'
                lane_card='delete-scope-card'
                client.command({'insert':'swimlanes','documents':[dict(
                    _id=lane_id,boardId='b',title='Temporary lane',createdAt=now)]})
                client.command({'insert':'cards','documents':[dict(
                    _id=lane_card,boardId='b',listId='l',swimlaneId=lane_id,title='Temporary card',userId='u',createdAt=now)]})
                lane_path='/api/boards/b/swimlanes/'+lane_id
                with sqlite3.connect(database) as con:
                    physical,=con.execute("SELECT table_name FROM _ferretdb_collections WHERE name='swimlanes'").fetchone()
                    physical='"'+physical.replace('"','""')+'"'
                    con.execute('CREATE TRIGGER reject_lane_delete AFTER DELETE ON '+physical+
                                " BEGIN SELECT RAISE(FAIL,'fixture lane rollback'); END")
                try:
                    assert request('DELETE',lane_path,token=token)[0]==500
                    assert client.find('cards',lane_card) and client.find('swimlanes',lane_id)
                finally:
                    with sqlite3.connect(database) as con:
                        con.execute('DROP TRIGGER reject_lane_delete')
                assert request('DELETE',lane_path,token=token)[0]==200
                assert not client.find('cards',lane_card) and not client.find('swimlanes',lane_id)
                status,_,body=request('DELETE',lane_path,token=token)
                assert status==404 and json.loads(body)=={'error':'Swimlane not found'}
                print('PASS: REST swimlane deletion rolls back its cards on failure and reports missing lanes')
                check_list_soft_delete(request,client,database,token,web_session)
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
                target_token='fixture-delete-target-token'
                target_hash=base64.b64encode(hashlib.sha256(target_token.encode()).digest()).decode()
                client.command({'update':'users','updates':[dict(q=dict(_id='u'),
                    u={'$set':{'services.resume.loginTokens':[dict(hashedToken=target_hash,when=now)]}})]})
                assert request('GET','/api/user',token=target_token)[0]==200
                admin_token='fixture-site-admin-token'
                admin_hash=base64.b64encode(hashlib.sha256(admin_token.encode()).digest()).decode()
                client.command({'insert':'users','documents':[dict(_id='fixture-admin',username='fixture-admin',isAdmin=True,
                    services=dict(resume=dict(loginTokens=[dict(hashedToken=admin_hash,when=now)])))]})
                issue='/api/createtoken/u'
                assert request('POST',issue,dict(reason='test'))[0]==401
                assert request('POST',issue,dict(reason='test'),target_token)[0]==403
                assert request('POST',issue,dict(reason='  '),admin_token)[0]==400
                assert request('POST','/api/createtoken/missing',dict(reason='test'),admin_token)[0]==404
                status,_,body=request('POST',issue,dict(reason='  Regression audit  '),admin_token)
                issued=json.loads(body)
                assert status==200 and issued['_id']=='u',(status,body)
                assert request('GET','/api/user',token=issued['authToken'])[0]==200
                reason='restCreateToken: Regression audit'
                audit=client.command({'find':'impersonatedUsers','filter':dict(reason=reason)})['cursor']['firstBatch']
                assert len(audit)==1 and audit[0]['adminId']=='fixture-admin' and audit[0]['userId']=='u'
                assert isinstance(audit[0]['createdAt'],type(now)) and 'authToken' not in audit[0]
                before=client.find('users','u')[0]['services']['resume']['loginTokens']
                with sqlite3.connect(database) as con:
                    physical=con.execute("SELECT table_name FROM _ferretdb_collections WHERE name='impersonatedUsers'").fetchone()[0]
                    con.execute(f'CREATE TRIGGER issue_audit_fail BEFORE INSERT ON "{physical}" '
                                "BEGIN SELECT RAISE(ABORT,'fixture audit failure'); END")
                try:
                    assert request('POST',issue,dict(reason='Rollback audit'),admin_token)[0]!=200
                    assert client.find('users','u')[0]['services']['resume']['loginTokens']==before
                finally:
                    with sqlite3.connect(database) as con:
                        con.execute('DROP TRIGGER issue_audit_fail')
                issued_hash=base64.b64encode(hashlib.sha256(issued['authToken'].encode()).digest()).decode()
                assert request('POST','/api/deletetoken',dict(userId='u',token=issued_hash),admin_token)[0]==200
                print('PASS: admin issuance requires a reason, records a typed audit and rolls back on audit failure')
                revoked_token='fixture-revoke-one'
                revoked_hash=base64.b64encode(hashlib.sha256(revoked_token.encode()).digest()).decode()
                client.command({'update':'users','updates':[dict(q=dict(_id='u'),u={'$push':{
                    'services.resume.loginTokens':dict(hashedToken=revoked_hash,when=now)}})]})
                assert request('GET','/api/user',token=revoked_token)[0]==200
                revoke='/api/deletetoken'
                assert request('POST',revoke,dict(userId='u',token=revoked_hash),target_token)[0]==403
                assert request('POST',revoke,dict(userId='u',token=revoked_token),admin_token)[0]==200
                assert request('GET','/api/user',token=revoked_token)[0]==200
                status,_,body=request('POST',revoke,dict(userId='missing'),admin_token)
                assert status==404 and json.loads(body)=={'error':'User not found'}
                status,_,body=request('POST',revoke,dict(userId='u',token=revoked_hash),admin_token)
                assert status==200 and revoked_hash.encode() not in body
                assert request('GET','/api/user',token=revoked_token)[0]==401
                assert request('GET','/api/user',token=target_token)[0]==200
                print('PASS: admin revokes a specific stored hash and preserves other sessions')
                for group in ['org','team']:
                    endpoint='/api/admin/'+group+'s'
                    assert request('GET',endpoint)[0]==401
                    assert request('GET',endpoint,token=target_token)[0]==403
                    assert json.loads(request('GET',endpoint,token=admin_token)[2])==[]
                    client.command({'create':group})
                    row={'_id':'group',group+'DisplayName':'Example',group+'ShortName':'example',
                         group+'SharedTemplates':True,'unknown':'private fixture field'}
                    client.command({'insert':group,'documents':[row]})
                    status,_,body=request('GET',endpoint,token=admin_token)
                    assert status==200 and json.loads(body)==[{
                        '_id':'group',group+'DisplayName':'Example',group+'ShortName':'example',
                        group+'SharedTemplates':True,group+'PropagateMembersToBoards':False,
                        group+'SyncMembersFromAuth':False}],(status,body)
                    assert client.find(group,'group')[0]==row
                    bulk_features=endpoint+'/features'
                    flag=group+'SyncMembersFromAuth'
                    assert request('PUT',bulk_features,dict(field=flag,value=True),target_token)[0]==403
                    assert json.loads(request('PUT',bulk_features,dict(field='unknown',value=True),admin_token)[2])==dict(error='invalid-field')
                    assert request('PUT',bulk_features,dict(field=flag,value='false'),admin_token)[0]==400
                    assert client.find(group,'group')[0]==row
                    client.command({'insert':group,'documents':[dict(_id='other',counter=Long(9007199254740993))]})
                    for enabled in [True,False]:
                        status,_,body=request('PUT',bulk_features,dict(field=flag,value=enabled),admin_token)
                        assert status==200 and json.loads(body)==dict(updated=2),(status,body)
                        assert client.find(group,'group')[0]==dict(row,**{flag:enabled})
                        other=client.find(group,'other')[0]
                        assert other[flag] is enabled and isinstance(other['counter'],Long)
                print('PASS: shared bulk feature updates are admin-gated and preserve unrelated BSON')
                print('PASS: shared People list routes project names and boolean flags only for site administrators')
                member_path='/api/boards/b/members/fixture-admin'
                assert request('POST','/api/boards/b/members/u/remove',dict(action='remove'),target_token)[0]==409
                assert request('POST',member_path+'/add',dict(action='add',role='readOnly'),target_token)[0]==200
                def fixture_member():
                    return next(m for m in client.find('boards','b')[0]['members'] if m['userId']=='fixture-admin')
                assert fixture_member()['isActive'] is True and fixture_member()['isReadOnly'] is True
                assert request('POST',member_path+'/remove',dict(action='remove'),target_token)[0]==200
                assert fixture_member()['isActive'] is False and fixture_member()['isAdmin'] is False
                assert request('POST',member_path+'/remove',dict(action='remove'),target_token)[0]==404
                assert request('POST',member_path+'/add',dict(action='add',role='normal'),target_token)[0]==200
                assert fixture_member()['isActive'] is True and fixture_member()['isReadOnly'] is False
                print('PASS: shared REST membership guards the last admin and reactivates inactive members with new roles')
                response=request('DELETE','/api/users/u',token=target_token)
                assert response[0]==403 and client.find('users','u')
                response=request('DELETE','/api/users/u',token=admin_token)
                assert response[0]==200 and json.loads(response[2])=={'_id':'u'},response
                assert not client.find('users','u')
                assert request('GET','/api/user',token=target_token)[0]==401
                response=request('DELETE','/api/users/u',token=admin_token)
                assert response[0]==404 and json.loads(response[2])=={'error':'User not found'},response
                print('PASS: REST user deletion requires site administration and invalidates the deleted account bearer')
                assert not shadow.exists(),'A normalized public database shadowed the shared file'
                with sqlite3.connect(database) as con:assert con.execute("SELECT type FROM sqlite_master WHERE name='users'").fetchone()==('view',)
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
