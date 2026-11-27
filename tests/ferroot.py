"""Real FerretDB and Welite root projections share one SQLite document file."""
import json
from datetime import datetime
import base64
import hashlib
import hmac
from concurrent.futures import ThreadPoolExecutor
import os
import sys
from pathlib import Path
import shutil
import socket
import sqlite3
import struct
import subprocess
import tempfile
import time
from wire import encode,Client,Long,DateMs,Binary,ObjectId,Timestamp,Regex
from discov import run as check_discovery
from refkind import run as check_reference_identity
from expiry import run as check_expiry
from custval import run as check_custom_values
from custins import run as check_custom_inserts
from custnull import run as check_custom_nulls
from cfset import run as check_custom_settings
root=Path(__file__).resolve().parents[1]
tools=root.parents[1]
# Never mix short-sidecar and normal-sidecar libraries on a live shared database.
with sqlite3.connect(':memory:') as check:
    assert check.execute("SELECT sqlite_compileoption_used('ENABLE_8_3_NAMES=2')").fetchone()==(0,),'Run live FerretDB tests with the normal-sidecar SQLite library'
subprocess.run([sys.executable,str(root/'releases/genmodel.py'),'--check'],check=True)
ferret=Path(os.environ.get('FERRETDB',str(tools/'ferretdb-test/ferretdb')))
assert ferret.is_file(),'Set FERRETDB to a native built server'
def port():
    with socket.socket() as sock:sock.bind(('127.0.0.1',0));return sock.getsockname()[1]
def q(value):return "'"+value.replace("'","''")+"'"
with tempfile.TemporaryDirectory(prefix='wlroots-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    def build(source,out,flags=(),name=None):
        out.mkdir(exist_ok=True)
        result=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),*(['-o'+str(out/name)] if name else []),str(source)],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
    build(root/'src/wlfunc.lpr',tmp/'ext',['-Cg','-dWLSQLEXT'],'wlfunc.so')
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=tmp/backend;build(root/'tests/sjsql.lpr',out,flags)
        build(root/'tests/replay.lpr',out/'replay',flags)
        build(root/'tests/factor.lpr',out/'factor',flags)
        build(root/'tests/attempt.lpr',out/'attempt',flags)
        build(root/'tests/enroll.lpr',out/'enroll',flags)
        build(root/'tests/revoke.lpr',out/'revoke',flags)
        build(root/'tests/sweep.lpr',out/'sweep',flags)
        build(root/'tests/maint.lpr',out/'maint',flags)
        settings=dict(os.environ)
        for variable in ['REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN']:settings.pop(variable,None)
        settings.pop('ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS',None)
        settings.pop('WELITE_ARGON_SECRET_FILE',None);settings.pop('WELITE_SHORT_NAMES',None);settings.pop('WELITE_ENTROPY_FILE',None);settings.pop('WELITE_SQLITE_EXT',None)
        if backend=='cli':settings['WELITE_SQLITE_EXT']=str(tmp/'ext/wlfunc.so')
        data=out/'data';data.mkdir();state=out/'state';state.mkdir();listen=port();debug=port();db=data/'wekan.sqlite'
        with (out/'server.log').open('w+') as log:
            server=subprocess.Popen([str(ferret),'--handler=sqlite','--sqlite-url='+data.as_uri()+'/','--state-dir='+str(state),'--listen-addr=127.0.0.1:'+str(listen),'--debug-addr=127.0.0.1:'+str(debug),'--log-level=ERROR','--telemetry=disable'],stdout=log,stderr=log,env=settings)
            client=Client(listen)
            try:
                for attempt in range(100):
                    try:client.command({'ping':1});break
                    except (OSError,EOFError):
                        if server.poll() is not None:log.seek(0);raise AssertionError(log.read())
                        time.sleep(.05)
                else:raise AssertionError('FerretDB did not start')
                # Create the real metadata/indexes through the server before wrapping it.
                collections=['boards','swimlanes','lists','cards','card_comments','checklists','checklistItems','customFields','users','activities','attachments']
                for collection in collections:client.command({'create':collection})
                client.command({'insert':'boards','documents':[{'_id':'board','title':'Original','slug':'board','createdAt':DateMs(1794832496789),'archived':False,'unknown':{'date':DateMs(-1),'long':Long(9007199254740993),'binary':Binary(bytes(range(16)),4),'oid':ObjectId(bytes(range(12))),'timestamp':Timestamp(2**63+7),'regex':Regex('test','im'),'zero':-0.0,'null':None},'members':[{'userId':'member','isActive':True}]}]})
                client.command({'insert':'lists','documents':[{'_id':'list','boardId':'board','title':'List','createdAt':DateMs(0),'wipLimit':{'enabled':False,'value':3,'soft':True,'other':'preserve'}}]})
                client.command({'insert':'attachments','documents':[{'_id':'file','name':'File','createdAt':DateMs(0),'meta':{'boardId':'board','cardId':'card','listId':'list','swimlaneId':'lane','other':'keep'},'versions':{'original':{'path':'keep'}}}]})
                initial=client.find('boards','board')[0]
                def sql(text='',mode='query',database=db):
                    result=subprocess.run([str(out/'sjsql'),str(database),mode],input=text,env=settings,capture_output=True,text=True,timeout=30)
                    assert result.returncode==0,result.stderr
                    return result.stdout.strip() if mode!='query' else json.loads(result.stdout)
                assert sql(mode='install')=='ok'
                assert sql("SELECT title,createdAt FROM boards WHERE id='board';")==[['Original','2026-11-16T12:34:56.789Z']]
                assert sql("UPDATE boards SET title='Welite 日本語',archived=1 WHERE id='board';",'exec')=='ok'
                board=client.find('boards','board')[0]
                assert board['title']=='Welite 日本語' and board['archived'] is True and isinstance(board['createdAt'],DateMs)
                unknown=board['unknown'];assert isinstance(unknown['date'],DateMs) and int(unknown['date'])==-1
                assert isinstance(unknown['long'],Long) and unknown['long']==9007199254740993
                assert unknown['binary']==bytes(range(16)) and unknown['binary'].subtype==4
                assert isinstance(unknown['oid'],ObjectId) and isinstance(unknown['timestamp'],Timestamp) and isinstance(unknown['regex'],Regex)
                assert struct.pack('<d',unknown['zero'])==struct.pack('<d',initial['unknown']['zero']) and unknown['null'] is None,(initial['unknown']['zero'],unknown['zero'])
                assert board['members']==[{'userId':'member','isActive':True}]
                client.command({'update':'boards','updates':[{'q':{'_id':'board'},'u':{'$set':{'title':'FerretDB back'}}}]})
                assert sql("SELECT title FROM boards WHERE id='board';")==[['FerretDB back']]
                assert sql("UPDATE lists SET wip_enabled=1,wip_value=8 WHERE id='list';",'exec')=='ok'
                assert client.find('lists','list')[0]['wipLimit']=={'enabled':True,'value':8,'soft':True,'other':'preserve'}
                assert sql("UPDATE attachments SET cardId='next' WHERE id='file';",'exec')=='ok'
                attachment=client.find('attachments','file')[0]
                assert attachment['meta']['cardId']=='next' and attachment['meta']['other']=='keep' and attachment['versions']['original']['path']=='keep'
                hours=1.2345678901234567
                assert sql(f"INSERT INTO boards(id,title,slug,createdAt,spentTime) VALUES('new','New','new','1969-12-31T23:59:59.999Z',{hours!r});",'exec')=='ok'
                inserted=client.find('boards','new')[0]
                assert inserted['createdAt']==DateMs(-1)
                assert inserted['spentTime']==hours,inserted['spentTime']
                hours=9.876543210987654
                assert sql(f"UPDATE boards SET spentTime={hours!r} WHERE id='new';",'exec')=='ok'
                assert client.find('boards','new')[0]['spentTime']==hours
                stamp='2026-11-16T12:34:56.789Z'
                inserts=[
                    ('swimlanes','lane',dict(boardId='board',title='Lane',createdAt=stamp)),
                    ('cards','card',dict(boardId='board',listId='list',swimlaneId='lane',title='Card',userId='author',createdAt=stamp,modifiedAt=stamp,dateLastActivity=stamp)),
                    ('card_comments','comment',dict(boardId='board',cardId='card',userId='author',text='Comment',createdAt=stamp,modifiedAt=stamp)),
                    ('checklists','check',dict(cardId='card',boardId='board',sort=0,createdAt=stamp,modifiedAt=stamp)),
                    ('checklist_items','item',dict(checklistId='check',cardId='card',boardId='board',title='Item',sort=0,isFinished=1,modifiedAt=stamp)),
                    ('custom_fields','field',dict(name='Field',type='text',showOnCard=1,modifiedAt=stamp)),
                    ('users','author',dict(username='author',createdAt=stamp,modifiedAt=stamp,services_json='{"password":{"bcrypt":"test-only"}}',profile_json='{"language":"fi"}')),
                    ('activities','activity',dict(activityType='test',boardId='board',cardId='card',createdAt=stamp,data_json='{"other":null,"count":42}')),
                ]
                names={'checklist_items':'checklistItems','custom_fields':'customFields'}
                for table,identity,values in inserts:
                    row=dict(id=identity,**values)
                    statement='INSERT INTO '+table+'('+','.join(row)+') VALUES('+','.join(str(v) if isinstance(v,int) else q(v) for v in row.values())+');'
                    assert sql(statement,'exec')=='ok',(table,statement)
                    document=client.find(names.get(table,table),identity)[0]
                    assert document['_id']==identity,table
                    if 'createdAt' in values:assert document['createdAt']==DateMs(1794832496789),table
                assert client.find('checklistItems','item')[0]['isFinished'] is True
                assert client.find('users','author')[0]['profile']=={'language':'fi'}
                assert client.find('activities','activity')[0]['other'] is None
                # All generated child views map to the actual embedded model paths.
                children=[
                    ('board_labels','boards','board','labels',dict(boardId='board',id='label',name='Label',color='red')),
                    ('board_members','boards','board','members',dict(boardId='board',userId='extra',isAdmin=1)),
                    ('board_orgs','boards','board','orgs',dict(boardId='board',orgId='org',orgDisplayName='Org')),
                    ('board_teams','boards','board','teams',dict(boardId='board',teamId='team',teamDisplayName='Team')),
                    ('board_domains','boards','board','domains',dict(boardId='board',domain='example.org')),
                    ('card_members','cards','card','members',dict(cardId='card',userId='author')),
                    ('card_assignees','cards','card','assignees',dict(cardId='card',userId='author')),
                    ('card_labels','cards','card','labelIds',dict(cardId='card',labelId='label')),
                    ('card_custom_field_values','cards','card','customFields',dict(cardId='card',customFieldId='field',value='plain text')),
                    ('card_dependencies','cards','card','cardDependencies',dict(cardId='card',targetCardId='target')),
                    ('custom_field_boards','customFields','field','boardIds',dict(customFieldId='field',boardId='board')),
                    ('custom_field_dropdown_items','customFields','field','settings.dropdownItems',dict(customFieldId='field',id='option',name='Option',sort=1)),
                    ('user_emails','users','author','emails',dict(userId='author',address='user@example.org',verified=1)),
                ]
                for table,collection,identity,path,values in children:
                    statement='INSERT INTO '+table+'('+','.join(values)+') VALUES('+','.join(str(v) if isinstance(v,int) else q(v) for v in values.values())+');'
                    assert sql(statement,'exec')=='ok',(table,statement)
                    document=client.find(collection,identity)[0]
                    for key in path.split('.'):document=document[key]
                    assert isinstance(document,list) and len(document)>0,table
                    assert sql('SELECT count(*) FROM '+table+';')[0][0]!='0',table
                    assert sql(statement,'exec')=='error',table
                check_custom_values(client,sql)
                check_custom_inserts(client,sql)
                check_custom_nulls(client,sql)
                check_custom_settings(client,sql)
                assert client.find('cards','card')[0]['cardDependencies']==[dict(cardId='target',type='related-to',color='#eb144c',icon='link')]
                assert client.find('customFields','field')[0]['settings']['dropdownItems'][0]['_id']=='option'
                assert client.find('boards','board')[0]['labels'][0]['_id']=='label'
                assert client.find('users','author')[0]['emails'][0]['verified'] is True
                assert sql("UPDATE board_labels SET id='renamed',name='Changed',color='blue' WHERE boardId='board' AND id='label';",'exec')=='ok'
                assert client.find('boards','board')[0]['labels']==[dict(_id='renamed',name='Changed',color='blue')]
                assert sql("UPDATE board_labels SET boardId='new' WHERE boardId='board';",'exec')=='error'
                assert sql("INSERT INTO board_labels(boardId,id,color) VALUES('absent','bad','red');",'exec')=='error'
                assert sql("UPDATE board_members SET isAdmin=2 WHERE userId='extra';",'exec')=='error'
                # Mongo edits are immediately visible, with unknown properties preserved by SQL.
                client.command({'update':'boards','updates':[{'q':{'_id':'board'},'u':{'$set':{'labels':[dict(_id='renamed',name='Mongo',color='blue',unknown=DateMs(-1))]}}}]})
                assert sql("SELECT name FROM board_labels WHERE id='renamed';")==[['Mongo']]
                assert sql("UPDATE board_labels SET name='SQL' WHERE id='renamed';",'exec')=='ok'
                assert isinstance(client.find('boards','board')[0]['labels'][0]['unknown'],DateMs)
                assert sql("DELETE FROM board_labels WHERE id='renamed';",'exec')=='ok'
                assert client.find('boards','board')[0]['labels']==[]
                # Optional dependency type defaults participate in matching and uniqueness.
                client.command({'update':'cards','updates':[{'q':{'_id':'card'},'u':{'$set':{'cardDependencies':[dict(cardId='target',unknown=DateMs(-1))]}}}]})
                assert sql("UPDATE card_dependencies SET color='green' WHERE cardId='card' AND targetCardId='target' AND type='related-to';",'exec')=='ok'
                dependency=client.find('cards','card')[0]['cardDependencies'][0]
                assert dependency['color']=='green' and isinstance(dependency['unknown'],DateMs)
                assert sql("INSERT INTO card_dependencies(cardId,targetCardId) VALUES('card','target');",'exec')=='error'
                # Clone seed retains unknown BSON metadata; managed arrays start empty
                # because relation insertion must remap their child identifiers later.
                physical=sql("SELECT table_name FROM _ferretdb_collections WHERE name='boards';")[0][0]
                seed=sql('SELECT json(_ferretdb_sjson) FROM '+q(physical)+" WHERE _ferretdb_sjson->>'_id'='board';")[0][0]
                assert sql("INSERT INTO boards(id,title,slug,createdAt,_wl_source) VALUES('copy','Copy','copy',"+q(stamp)+','+q(seed)+');','exec')=='ok'
                clone=client.find('boards','copy')[0]
                assert clone['unknown']['long']==9007199254740993 and isinstance(clone['unknown']['date'],DateMs) and 'members' not in clone
                assert sql("UPDATE boards SET settings_json='{"+chr(34)+"replacement"+chr(34)+":null}' WHERE id='copy';",'exec')=='ok'
                clone=client.find('boards','copy')[0]
                assert clone['replacement'] is None and 'unknown' not in clone and clone['title']=='Copy'
                # Explicit clone envelopes still run through actual root-view
                # reference and unique checks; ordinary seed inserts above keep defaults.
                list_seed=sql('SELECT json(_ferretdb_sjson) FROM '+q(sql("SELECT table_name FROM _ferretdb_collections WHERE name='lists';")[0][0])+" WHERE _ferretdb_sjson->>'_id'='list';")[0][0]
                envelope=json.dumps(dict(_wl_clone=1,source=list_seed,columns=dict(id='clone-bad-reference',boardId='missing')))
                assert sql("INSERT INTO lists(id,_wl_source) VALUES('clone-bad-reference',"+q(envelope)+');','exec')=='error'
                assert sql("SELECT count(*) FROM lists WHERE id='clone-bad-reference';")==[['0']]
                envelope=json.dumps(dict(_wl_clone=1,source=seed,columns=dict(id='new')))
                assert sql("INSERT INTO boards(id,_wl_source) VALUES('new',"+q(envelope)+');','exec')=='error'
                assert client.find('boards','new')[0]['title']=='New'
                # Embedded relation edits retain per-row unknown BSON metadata.
                client.command({'update':'boards','updates':[{'q':{'_id':'board'},'u':{'$set':{'members':[{'userId':'member','isActive':True,'unknown':{'when':DateMs(-1),'large':Long(9007199254740993)}},{'userId':'second','isActive':False}]}}}]})
                member_spec={'path':'members','keys':['userId'],'fields':[
                    dict(name='userId',type='TEXT',required=True,default=None),
                    dict(name='isActive',type='INTEGER',kind='bool',required=True,default=1)]}
                def relation(spec,op,old,values):
                    command=json.dumps(dict(op=op,old=old,values=values),ensure_ascii=False)
                    expression='wl_relation(json(_ferretdb_sjson),'+q(command)+','+q(json.dumps(spec))+')'
                    return sql('UPDATE '+q(physical)+' SET _ferretdb_sjson=CASE WHEN wl_storage('+q(physical)+")='blob' THEN jsonb("+expression+') ELSE '+expression+" END WHERE _ferretdb_sjson->>'_id'='board';",'exec')
                assert relation(member_spec,'update',{'userId':'member'},{'isActive':0})=='ok'
                members=client.find('boards','board')[0]['members']
                assert [v['userId'] for v in members]==['member','second'] and members[0]['isActive'] is False
                assert isinstance(members[0]['unknown']['when'],DateMs) and isinstance(members[0]['unknown']['large'],Long)
                assert relation(member_spec,'insert',{},dict(userId='third'))=='ok'
                assert client.find('boards','board')[0]['members'][2]=={'userId':'third','isActive':True}
                saved=encode(client.find('boards','board')[0])
                for op,old,values in [('insert',{},dict(userId='third')),('update',dict(userId='second'),dict(userId='member')),('update',dict(userId='member'),dict(isActive=2)),('update',dict(userId='absent'),dict(isActive=1)),('insert',{},dict(userId=None)),('update',dict(userId='member'),dict(unknown='no'))]:
                    assert relation(member_spec,op,old,values)=='error'
                    assert encode(client.find('boards','board')[0])==saved
                assert relation(member_spec,'delete',dict(userId='second'),{})=='ok'
                assert [v['userId'] for v in client.find('boards','board')[0]['members']]==['member','third']
                scalar_spec={'path':'test.ids','scalar':True,'keys':['id'],'fields':[dict(name='id',type='TEXT',required=True,default=None)]}
                assert relation(scalar_spec,'insert',{},dict(id='日本語'))=='ok'
                assert relation(scalar_spec,'insert',{},dict(id='two'))=='ok'
                assert relation(scalar_spec,'update',dict(id='日本語'),dict(id='renamed'))=='ok'
                assert client.find('boards','board')[0]['test']['ids']==['renamed','two']
                assert relation(scalar_spec,'delete',dict(id='renamed'),{})=='ok'
                assert client.find('boards','board')[0]['test']['ids']==['two']
                client.command({'update':'boards','updates':[{'q':{'_id':'board'},'u':{'$set':{'test':{'ids':'malformed'}}}}]})
                assert relation(scalar_spec,'insert',{},dict(id='denied'))=='error'
                before=sql("SELECT json(_ferretdb_sjson) FROM "+q(sql("SELECT table_name FROM _ferretdb_collections WHERE name='boards';")[0][0])+" ORDER BY rowid;")
                assert sql("BEGIN; UPDATE boards SET title='rollback' WHERE id='new'; UPDATE boards SET createdAt='invalid' WHERE id='new'; COMMIT;",'exec')=='error'
                assert sql("SELECT json(_ferretdb_sjson) FROM "+q(sql("SELECT table_name FROM _ferretdb_collections WHERE name='boards';")[0][0])+" ORDER BY rowid;")==before
                assert sql("UPDATE boards SET id='changed' WHERE id='new';",'exec')=='error'
                assert sql("DELETE FROM card_comments WHERE id='comment';",'exec')=='ok' and client.find('card_comments','comment')==[]
                assert sql("UPDATE boards SET _wl_source='{}' WHERE id='new';",'exec')=='error'
                assert sql("INSERT INTO boards(id,title,slug,createdAt) VALUES('new','Duplicate','duplicate',"+q(stamp)+');','exec')=='error'
                assert sql('CREATE TABLE audit(value TEXT); CREATE TRIGGER custom_audit INSTEAD OF UPDATE OF title ON boards BEGIN INSERT INTO audit VALUES(NEW.title);END;','exec')=='ok'
                assert sql('CREATE TRIGGER child_audit INSTEAD OF UPDATE OF name ON custom_field_dropdown_items BEGIN INSERT INTO audit VALUES(NEW.name);END;','exec')=='ok'
                assert sql(mode='install')=='ok' and client.find('boards','new')[0]['title']=='New'
                assert sql("UPDATE custom_field_dropdown_items SET name='Child audit' WHERE id='option';",'exec')=='ok'
                assert sql("UPDATE boards SET title='Audited' WHERE id='new';",'exec')=='ok'
                assert sql('SELECT value FROM audit;')==[['Child audit'],['Audited']]
                assert client.find('boards','new')[0]['title']=='Audited'

                # Declared root references are enforced on both insert and update.
                assert sql("INSERT INTO card_comments(id,boardId,cardId,userId,text,createdAt,modifiedAt) VALUES('cascade-comment','board','card','author','Text',"+q(stamp)+','+q(stamp)+');','exec')=='ok'
                physicals=dict(sql('SELECT name,table_name FROM _ferretdb_collections;'))
                def snapshot():
                    return {name:sql('SELECT json(_ferretdb_sjson) FROM '+q(table)+' ORDER BY rowid;') for name,table in physicals.items()}
                references=[('swimlanes','lane','boardId'),('lists','list','boardId'),('cards','card','boardId'),('card_comments','cascade-comment','boardId'),('card_comments','cascade-comment','cardId'),('checklists','check','cardId'),('checklist_items','item','checklistId')]
                stable=snapshot()
                for table,identity,column in references:
                    assert sql('UPDATE '+table+' SET '+column+"='missing' WHERE id="+q(identity)+';','exec')=='error',(table,column)
                    assert snapshot()==stable
                    physical_name=physicals[names.get(table,table)]
                    source=sql('SELECT json(_ferretdb_sjson) FROM '+q(physical_name)+" WHERE _ferretdb_sjson->>'_id'="+q(identity)+';')[0][0]
                    assert sql('INSERT INTO '+table+'(id,'+column+',_wl_source) VALUES('+q('bad-'+table+'-'+column)+",'missing',"+q(source)+');','exec')=='error',(table,column)
                    assert snapshot()==stable
                check_reference_identity(sql,client)
                # Optional references permit NULL, while undeclared references retain
                # schema semantics (attachments/activities are not cascade-owned).
                assert sql("UPDATE cards SET boardId=NULL WHERE id='card';",'exec')=='ok'
                assert sql("UPDATE cards SET boardId='board' WHERE id='card';",'exec')=='ok'
                stable=snapshot()
                assert sql("CREATE TRIGGER block_cascade INSTEAD OF DELETE ON checklist_items WHEN OLD.id='item' BEGIN SELECT RAISE(ABORT,'test denial');END;",'exec')=='ok'
                assert sql("DELETE FROM boards WHERE id='board';",'exec')=='error'
                assert snapshot()==stable,'A failed nested cascade partially deleted records'
                assert sql('DROP TRIGGER block_cascade;','exec')=='ok'
                assert sql("DELETE FROM boards WHERE id='board';",'exec')=='ok'
                for collection,identity in [('boards','board'),('swimlanes','lane'),('lists','list'),('cards','card'),('card_comments','cascade-comment'),('checklists','check'),('checklistItems','item')]:
                    assert client.find(collection,identity)==[],collection
                for table in ['board_members','board_orgs','board_teams','board_domains','card_members','card_assignees','card_labels','card_custom_field_values','card_dependencies']:
                    assert sql('SELECT count(*) FROM '+table+';')==[['0']],table
                assert client.find('boards','new')[0]['title']=='Audited'
                assert client.find('attachments','file') and client.find('activities','activity') and client.find('users','author') and client.find('customFields','field')
                # Deleting a different root only removes its embedded children.
                assert sql("DELETE FROM users WHERE id='author';",'exec')=='ok'
                assert sql('SELECT count(*) FROM user_emails;')==[['0']]
                assert sql("DELETE FROM custom_fields WHERE id='field';",'exec')=='ok'
                for table in ['custom_field_boards','custom_field_dropdown_items']:
                    assert sql('SELECT count(*) FROM '+table+';')==[['0']]

                # SQLite JSON subtypes must not change TEXT patch value types.
                json_services=dict(password=dict(bcrypt='test-only'))
                assert sql("INSERT INTO users(id,username,createdAt,modifiedAt,services_json,profile_json) VALUES('json-user','json-user',"+q(stamp)+','+q(stamp)+',json('+q(json.dumps(json_services))+"),json_object('language','fi'));",'exec')=='ok'
                json_user=client.find('users','json-user')[0]
                assert json_user['services']==json_services and json_user['profile']==dict(language='fi')
                assert sql("UPDATE users SET profile_json=json_set(profile_json,'$.language','sv') WHERE id='json-user';",'exec')=='ok'
                assert client.find('users','json-user')[0]['profile']==dict(language='sv')
                assert sql("DELETE FROM users WHERE id='json-user';",'exec')=='ok'
                # Shared resume writes retain BSON Date and shifted sibling schemas.
                def meteor_hash(raw):return base64.b64encode(hashlib.sha256(raw.encode()).digest()).decode()
                first_hash=meteor_hash('first-resume-token');new_hash=meteor_hash('new-resume-token')
                resume_doc=dict(_id='resume-doc',username='resume-doc',services=dict(password=dict(reset=dict(when=DateMs(-1))),resume=dict(loginTokens=[dict(hashedToken=first_hash,when=DateMs(-1234),extra=Binary(b'keep',4)),dict(token='legacy-plain-token',when=DateMs(1794835200000),extra=Long(9007199254740993))],other=dict(retain=True)),other=DateMs(-5)),unknown=dict(long=Long(9007199254740993),zero=-0.0,precise=1.0000000000000002))
                client.command({'insert':'users','documents':[resume_doc]})
                # Compare against actual stored BSON, including any source backend
                # normalization that occurred before the WeLite mutation.
                resume_doc=client.find('users','resume-doc')[0]
                assert struct.pack('>d',resume_doc['unknown']['precise'])==struct.pack('>d',1.0000000000000002)
                resume_table=physicals['users']
                def resume_sql(command):
                    value='wl_resume(json(_ferretdb_sjson),'+q(json.dumps(command))+')'
                    return 'UPDATE '+q(resume_table)+" SET _ferretdb_sjson=CASE WHEN wl_storage("+q(resume_table)+")='blob' THEN jsonb("+value+') ELSE '+value+" END WHERE _ferretdb_sjson->>'_id'='resume-doc';"
                assert sql(resume_sql(dict(op='append',hashedToken=new_hash,when=1794835200123)),'exec')=='ok'
                resume_doc['services']['resume']['loginTokens'].append(dict(hashedToken=new_hash,when=DateMs(1794835200123)))
                actual_resume=client.find('users','resume-doc')[0]
                assert encode(actual_resume)==encode(resume_doc),(repr(actual_resume),repr(resume_doc))
                # A conversion keeps the exact BSON timestamp and unknown metadata.
                with ThreadPoolExecutor(max_workers=8) as pool:
                    converted=list(pool.map(lambda _:sql(resume_sql(dict(op='convert',token='legacy-plain-token')),'exec'),range(8)))
                assert converted==['ok']*8,converted
                legacy=resume_doc['services']['resume']['loginTokens'][1]
                del legacy['token'];legacy['hashedToken']=meteor_hash('legacy-plain-token')
                assert encode(client.find('users','resume-doc')[0])==encode(resume_doc),'Legacy conversion changed BSON types/bits or sibling data'
                # Duplicate hashes already present in one document are all removed.
                duplicated=dict(hashedToken=first_hash,when=DateMs(100),extra=Long(42))
                client.command({'update':'users','updates':[dict(q=dict(_id='resume-doc'),u={'$push':{'services.resume.loginTokens':duplicated}})]})
                resume_doc['services']['resume']['loginTokens'].append(duplicated)
                assert sql(resume_sql(dict(op='remove',hashedToken=first_hash)),'exec')=='ok'
                resume_doc['services']['resume']['loginTokens']=[value for value in resume_doc['services']['resume']['loginTokens'] if value.get('hashedToken')!=first_hash]
                assert encode(client.find('users','resume-doc')[0])==encode(resume_doc),'Removal changed shifted legacy token types/bits'
                def resume_state(hash_value,at,life):
                    return sql('SELECT wl_rescheck(json(_ferretdb_sjson),'+q(hash_value)+','+str(at)+','+str(life)+') FROM '+q(resume_table)+" WHERE _ferretdb_sjson->>'_id'='resume-doc';")[0][0]
                assert resume_state(new_hash,1794835201122,1000)=='valid'
                assert resume_state(new_hash,1794835201123,1000)=='expired'
                assert sql(resume_sql(dict(op='expire',before=1794835200123)),'exec')=='ok'
                resume_doc['services']['resume']['loginTokens']=[value for value in resume_doc['services']['resume']['loginTokens'] if value['when']>=1794835200123]
                assert encode(client.find('users','resume-doc')[0])==encode(resume_doc)
                assert resume_state(new_hash,1794835201122,1000)=='valid'
                stable_resume=encode(client.find('users','resume-doc')[0])
                assert sql('BEGIN IMMEDIATE; '+resume_sql(dict(op='append',hashedToken=meteor_hash('rolled-back'),when=1))+resume_sql(dict(op='append',hashedToken='invalid',when=1))+' COMMIT;','exec')=='error'
                assert encode(client.find('users','resume-doc')[0])==stable_resume
                assert sql(resume_sql(dict(op='clear')),'exec')=='ok'
                resume_doc['services']['resume']['loginTokens']=[]
                assert encode(client.find('users','resume-doc')[0])==encode(resume_doc)
                client.command({'delete':'users','deletes':[dict(q=dict(_id='resume-doc'),limit=1)]})

                # A durable due sweep uses Meteor's strict-before cutoff across accounts.
                sweep_now=1794835200000;cutoff=sweep_now-90*86400000
                sweep_docs=[dict(_id='sweep-'+str(i),services=dict(resume=dict(loginTokens=[dict(hashedToken=meteor_hash('sweep-old-'+str(i)),when=DateMs(cutoff-1),extra=Long(9007199254740993)),dict(token='sweep-numeric-'+str(i),when=cutoff-0.5),dict(hashedToken=meteor_hash('sweep-boundary-'+str(i)),when=DateMs(cutoff),keep=Binary(b'keep',4)),dict(token='sweep-future-'+str(i),when=DateMs(sweep_now+1))],keep=DateMs(-1))),unknown=dict(precise=1.0000000000000002)) for i in range(2)]
                client.command({'insert':'users','documents':sweep_docs})
                sweep_docs=[client.find('users',doc['_id'])[0] for doc in sweep_docs]
                def sweep(at):return subprocess.check_output([str(out/'sweep/sweep'),str(db),str(at)],env=settings,text=True).strip()
                assert sql('CREATE TRIGGER deny_sweep BEFORE UPDATE ON '+q(physicals['users'])+" WHEN OLD._ferretdb_sjson->>'_id'='sweep-1' BEGIN SELECT RAISE(IGNORE); END;",'exec')=='ok'
                assert sweep(sweep_now)=='no'
                assert sql('SELECT lastAt FROM _wl_sweep;')==[['-600000']]
                assert all(encode(client.find('users',doc['_id'])[0])==encode(doc) for doc in sweep_docs),'Failed sweep partially committed'
                assert sql('DROP TRIGGER deny_sweep;','exec')=='ok'
                assert sql('CREATE TRIGGER deny_clock BEFORE UPDATE ON _wl_sweep BEGIN SELECT RAISE(IGNORE); END;','exec')=='ok'
                assert sweep(sweep_now)=='no'
                assert sql('SELECT lastAt FROM _wl_sweep;')==[['-600000']]
                assert all(encode(client.find('users',doc['_id'])[0])==encode(doc) for doc in sweep_docs)
                assert sql('DROP TRIGGER deny_clock;','exec')=='ok'
                with ThreadPoolExecutor(max_workers=4) as pool:swept=list(pool.map(lambda _:sweep(sweep_now),range(4)))
                assert 'yes' in swept and all(value in ['yes','no'] for value in swept),swept
                for doc in sweep_docs:
                    doc['services']['resume']['loginTokens']=doc['services']['resume']['loginTokens'][2:]
                    assert encode(client.find('users',doc['_id'])[0])==encode(doc),'Sweep changed retained BSON types/bits'
                assert sql('SELECT lastAt FROM _wl_sweep;')==[[str(sweep_now)]]
                assert sweep(sweep_now-1)=='no','Clock rollback advanced expiry maintenance'
                assert sweep(sweep_now+599999)=='yes' and sql('SELECT lastAt FROM _wl_sweep;')==[[str(sweep_now)]]
                assert sql(mode='install')=='ok' and sql('SELECT lastAt FROM _wl_sweep;')==[[str(sweep_now)]]
                assert sweep(sweep_now+600000)=='yes'
                for doc in sweep_docs:
                    doc['services']['resume']['loginTokens']=doc['services']['resume']['loginTokens'][1:]
                    assert encode(client.find('users',doc['_id'])[0])==encode(doc)
                client.command({'delete':'users','deletes':[dict(q=dict(_id=doc['_id']),limit=1) for doc in sweep_docs]})
                # Fractional configured lifetime clips the cutoff after subtraction.
                fractional_now=sweep_now+1200000;fractional_days=0.000001
                fractional_cutoff=int(subprocess.check_output([os.environ.get('NODE','node'),'-e','console.log(new Date(Number(process.argv[1])-Number(process.argv[2])*86400000).getTime())',str(fractional_now),str(fractional_days)],text=True))
                client.command({'create':'settings'})
                client.command({'insert':'settings','documents':[dict(_id='sweep-settings',loginOptions=dict(loginExpirationInDays=fractional_days))]})
                fractional_doc=dict(_id='sweep-fraction',services=dict(resume=dict(loginTokens=[dict(token='before',when=DateMs(fractional_cutoff-1)),dict(token='equal',when=DateMs(fractional_cutoff),extra=Long(9007199254740993)),dict(token='numeric',when=fractional_cutoff-0.5)])))
                client.command({'insert':'users','documents':[fractional_doc]})
                fractional_doc=client.find('users','sweep-fraction')[0]
                assert sweep(fractional_now)=='yes'
                fractional_doc['services']['resume']['loginTokens']=fractional_doc['services']['resume']['loginTokens'][1:2]
                assert encode(client.find('users','sweep-fraction')[0])==encode(fractional_doc)
                # Bad source identity cannot advance a durable due timestamp.
                sweep_source=sql("SELECT settings FROM _ferretdb_collections WHERE name='users';")[0][0]
                assert sql("UPDATE _ferretdb_collections SET settings=json_set(settings,'$.uuid','bad') WHERE name='users';",'exec')=='ok'
                assert sweep(fractional_now+600000)=='no'
                assert sql('SELECT lastAt FROM _wl_sweep;')==[[str(fractional_now)]]
                assert sql("UPDATE _ferretdb_collections SET settings="+q(sweep_source)+" WHERE name='users';",'exec')=='ok'
                client.command({'drop':'settings'})
                client.command({'delete':'users','deletes':[dict(q=dict(_id='sweep-fraction'),limit=1)]})


                # A real worker retries failures and sweeps without further requests.
                missing_store=out/'missing.db';native_store=out/'native.db'
                with sqlite3.connect(native_store) as native:
                    native.execute('CREATE TABLE users(id TEXT)');native.execute("INSERT INTO users VALUES('unchanged')")
                worker_doc=dict(_id='worker-user',services=dict(resume=dict(loginTokens=[dict(token='worker-old',when=DateMs(0)),dict(token='worker-future',when=DateMs(int(time.time()*1000)+86400000),extra=Long(9007199254740993))])),keep=Binary(b'worker',4))
                client.command({'insert':'users','documents':[worker_doc]})
                worker_doc=client.find('users','worker-user')[0]
                assert sql('UPDATE _wl_sweep SET lastAt=-600000;','exec')=='ok'
                assert sql('CREATE TRIGGER deny_worker BEFORE UPDATE ON '+q(physicals['users'])+" WHEN OLD._ferretdb_sjson->>'_id'='worker-user' BEGIN SELECT RAISE(IGNORE); END;",'exec')=='ok'
                maint=subprocess.Popen([str(out/'maint/maint'),str(db),str(native_store),str(missing_store)],env=settings,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                try:
                    assert maint.stdout.readline().strip()=='ready'
                    for attempt in range(100):
                        maint.stdin.write('status\n');maint.stdin.flush()
                        if int(maint.stdout.readline().strip())>0:break
                        assert maint.poll() is None;time.sleep(.05)
                    else:raise AssertionError('Worker did not report an attempted failing sweep')
                    assert maint.poll() is None and sql('SELECT lastAt FROM _wl_sweep;')==[['-600000']]
                    assert encode(client.find('users','worker-user')[0])==encode(worker_doc)
                    assert sql('DROP TRIGGER deny_worker;','exec')=='ok'
                    for attempt in range(100):
                        if len(client.find('users','worker-user')[0]['services']['resume']['loginTokens'])==1:break
                        assert maint.poll() is None;time.sleep(.05)
                    else:raise AssertionError('Idle background maintenance did not retry')
                    worker_doc['services']['resume']['loginTokens']=worker_doc['services']['resume']['loginTokens'][1:]
                    assert encode(client.find('users','worker-user')[0])==encode(worker_doc)
                    # Force another due interval and verify the same worker keeps running.
                    client.command({'update':'users','updates':[dict(q=dict(_id='worker-user'),u={'$push':{'services.resume.loginTokens':dict(token='worker-later',when=DateMs(0))}})]})
                    assert sql('UPDATE _wl_sweep SET lastAt=-600000;','exec')=='ok'
                    for attempt in range(100):
                        if len(client.find('users','worker-user')[0]['services']['resume']['loginTokens'])==1:break
                        assert maint.poll() is None;time.sleep(.05)
                    else:raise AssertionError('Background worker stopped after its first pass')
                    output,errors=maint.communicate('stop\n',timeout=10)
                    assert maint.returncode==0 and output.strip()=='stopped',(output,errors)
                finally:
                    if maint.poll() is None:maint.kill();maint.wait()
                assert not missing_store.exists()
                with sqlite3.connect(native_store) as native:assert native.execute('SELECT * FROM users').fetchall()==[('unchanged',)]
                client.command({'delete':'users','deletes':[dict(q=dict(_id='worker-user'),limit=1)]})

                # Startup discovery uses separate backups under the managed layout.
                discovery_doc=dict(_id='discovery-user',services=dict(resume=dict(loginTokens=[dict(token='discovery-old',when=DateMs(0)),dict(token='discovery-future',when=DateMs(int(time.time()*1000)+86400000))])))
                client.command({'insert':'users','documents':[discovery_doc]})
                checkpoint=sql('SELECT lastAt FROM _wl_sweep;')[0][0]
                assert sql('UPDATE _wl_sweep SET lastAt=-600000;','exec')=='ok'
                check_discovery(out,db,physicals['users'],settings)
                assert sql('UPDATE _wl_sweep SET lastAt='+checkpoint+';','exec')=='ok'
                client.command({'delete':'users','deletes':[dict(q=dict(_id='discovery-user'),limit=1)]})

                # Private tokens reference a user view without invalid SQLite FKs.
                build(root/'tests/token.lpr',out/'tokens',flags)
                auth_state={'active':'api-test-token','sequence':0}
                def auth(mode,token='api-test-token',password=''):
                    if mode=='issue':
                        auth_state['sequence']+=1;auth_state['active']='api-test-token-'+str(auth_state['sequence'])
                        token=auth_state['active']
                    elif mode=='check' and token=='api-test-token':token=auth_state['active']
                    result=subprocess.run([str(out/'tokens/token'),mode,str(db),token,password],env=settings,capture_output=True,text=True,timeout=30)
                    assert result.returncode==0,result.stderr
                    return result.stdout.strip()
                assert sql('PRAGMA foreign_key_list(login_tokens);')==[]
                assert sql('PRAGMA foreign_key_list(authmeta);')[0][2]=='login_tokens'
                assert sql("INSERT INTO users(id,username,createdAt,modifiedAt,services_json) VALUES('u','user',"+q(stamp)+','+q(stamp)+",'{\"password\":\"credential\"}');",'exec')=='ok'
                shared_password=dict(bcrypt='$2b$04$......................b8CYpLYfgS/XMWDCU3/.oCRJREnOf3y',reset=dict(token='retain'))
                client.command({'insert':'users','documents':[dict(_id='meteor-account',username='meteor-account',services=dict(password=shared_password,other=dict(retain=True)))]})
                shared_before=encode(client.find('users','meteor-account')[0])
                assert sql("SELECT spec FROM _wl_models WHERE name='_wl_attempt';")==[['{"kind":"private-auth","version":1}']]
                for index in range(6):
                    limited=subprocess.check_output([str(out/'attempt/attempt'),str(db),'meteor-account','127.0.0.1','1000'],env=settings,text=True,timeout=30).strip()
                    assert limited==('yes' if index<5 else 'no')
                assert encode(client.find('users','meteor-account')[0])==shared_before
                assert sql(mode='install')=='ok'
                assert subprocess.check_output([str(out/'attempt/attempt'),str(db),'meteor-account','127.0.0.1','1000'],env=settings,text=True,timeout=30).strip()=='no'
                assert auth('password','meteor-account','test-password')=='yes'
                assert auth('password','meteor-account','wrong')=='no'
                assert encode(client.find('users','meteor-account')[0])==shared_before
                client.command({'update':'users','updates':[dict(q=dict(_id='meteor-account'),u={'$set':{'services.password.argon2':'$argon2id$v=19$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$eL9VAPxb5H9dbhpqPyL7Z7AkFp72MImsQmo94Yh0kAY'}})]})
                argon_before=encode(client.find('users','meteor-account')[0])
                assert auth('password','meteor-account','test-password')=='yes'
                assert auth('password','meteor-account','wrong')=='no'
                assert encode(client.find('users','meteor-account')[0])==argon_before
                legacy_argon='$argon2id$v=16$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$shmop4+uHY9Bws9kfsVWl7IO3PvjjDUJpB4nB4wjPno'
                for encoded in [legacy_argon,legacy_argon.replace('$v=16','')]:
                    client.command({'update':'users','updates':[dict(q=dict(_id='meteor-account'),u={'$set':{'services.password.argon2':encoded},'$unset':{'services.password.bcrypt':''}})]})
                    legacy_before=encode(client.find('users','meteor-account')[0])
                    assert auth('password','meteor-account','test-password')=='yes'
                    assert auth('password','meteor-account','wrong')=='no'
                    assert encode(client.find('users','meteor-account')[0])==legacy_before
                pepper=out/'pepper.key';pepper.write_bytes(b'operator\0secret\n');pepper.chmod(0o600)
                settings['WELITE_ARGON_SECRET_FILE']=str(pepper)
                secret_fixture='$argon2id$v=19$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$YP4w4kIb5cnL7j3QC7YWdgIgvtjmj5Q22x+qTOqyF+w'
                client.command({'update':'users','updates':[dict(q=dict(_id='meteor-account'),u={'$set':{'services.password.argon2':secret_fixture}})]})
                secret_before=encode(client.find('users','meteor-account')[0])
                assert auth('password','meteor-account','test-password')=='yes'
                pepper.write_bytes(b'wrong')
                assert auth('password','meteor-account','test-password')=='no'
                assert encode(client.find('users','meteor-account')[0])==secret_before
                settings.pop('WELITE_ARGON_SECRET_FILE')
                client.command({'update':'users','updates':[dict(q=dict(_id='meteor-account'),u={'$set':{'services.twoFactorAuthentication':dict(type='otp',secret='JBSWY3DPEHPK3PXP')}})]})
                policy_before=encode(client.find('users','meteor-account')[0])
                assert auth('lookup','meteor-account')=='no'
                assert auth('password','meteor-account','test-password')=='no'
                assert encode(client.find('users','meteor-account')[0])==policy_before
                client.command({'update':'users','updates':[dict(q=dict(_id='meteor-account'),u={'$unset':{'services.twoFactorAuthentication.type':''}})]})
                settings['WELITE_ARGON_SECRET_FILE']=str(pepper);pepper.write_bytes(b'operator\0secret\n')
                assert auth('password','meteor-account','test-password')=='yes'
                settings.pop('WELITE_ARGON_SECRET_FILE')
                factor_secret='GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'
                client.command({'update':'users','updates':[dict(q=dict(_id='meteor-account'),u={'$set':{'services.twoFactorAuthentication':dict(type='otp',secret=factor_secret)}})]})
                settings['WELITE_ARGON_SECRET_FILE']=str(pepper)
                factor_before=encode(client.find('users','meteor-account')[0])
                counter=int(time.time())//30
                digest=hmac.new(b'12345678901234567890',struct.pack('>Q',counter),hashlib.sha1).digest();offset=digest[-1]&15
                code=str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
                def factor_call(mode,raw='factor-shared',entered=code):
                    result=subprocess.run([str(out/'factor/factor'),str(db),mode,'meteor-account','test-password',entered,raw],env=settings,capture_output=True,text=True,timeout=30)
                    assert result.returncode==0,result.stderr
                    return result.stdout.strip()
                assert factor_call('api')=='yes'
                assert factor_call('api')=='no','Shared account OTP replay succeeded'
                checked=subprocess.run([str(out/'factor/factor'),str(db),'check','factor-shared'],env=settings,capture_output=True,text=True,timeout=30)
                assert checked.returncode==0 and checked.stdout.strip()=='yes'
                paired=client.find('users','meteor-account')[0]
                stamped=paired['services'].pop('resume')['loginTokens']
                assert len(stamped)==1 and stamped[0]['hashedToken']==meteor_hash('factor-shared') and isinstance(stamped[0]['when'],DateMs)
                assert encode(paired)==factor_before
                # A cross-account shared collision must also roll back OTP usage.
                collision_raw='factor-global-collision'
                client.command({'insert':'users','documents':[dict(_id='factor-collision',services=dict(resume=dict(loginTokens=[dict(hashedToken=meteor_hash(collision_raw),when=DateMs(1))])))]})
                next_digest=hmac.new(b'12345678901234567890',struct.pack('>Q',counter+1),hashlib.sha1).digest();offset=next_digest[-1]&15
                next_code=str((struct.unpack('>I',next_digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
                assert factor_call('api',collision_raw,next_code)=='no'
                assert sql("SELECT counter FROM _wl_otp WHERE userId='meteor-account';")==[[str(counter)]]
                client.command({'delete':'users','deletes':[dict(q=dict(_id='factor-collision'),limit=1)]})
                assert factor_call('api',collision_raw,next_code)=='yes','Failed paired issuance consumed OTP'
                assert sql("SELECT counter FROM _wl_otp WHERE userId='meteor-account';")==[[str(counter+1)]]
                assert sql("DELETE FROM login_tokens WHERE userId='meteor-account';",'exec')=='ok'
                settings.pop('WELITE_ARGON_SECRET_FILE')
                # Limited enrollment changes only factor fields in actual shared BSON.
                enrolling=dict(_id='enrolling',username='enrolling',services=dict(password=shared_password,other=dict(keep=DateMs(-1)),resume=dict(loginTokens=[dict(hashedToken=meteor_hash('before-enrollment'),when=DateMs(1794835200000)),dict(token='legacy-before-enrollment',when=DateMs(-1))],keep=Long(9007199254740993))),unknown=Long(9007199254740993))
                client.command({'insert':'users','documents':[enrolling]})
                binding=hashlib.sha256(b'enrollment-client').hexdigest()
                enroll_settings=dict(settings,REQUIRE_2FA='all')
                started=subprocess.check_output([str(out/'enroll/enroll'),str(db),'start','enrolling','test-password',binding],env=enroll_settings,text=True,timeout=30).strip().splitlines()
                assert len(started)==2,started
                setup_token,setup_secret=started
                assert encode(client.find('users','enrolling')[0])==encode(enrolling)
                assert sql(mode='install')=='ok','Reinstall lost pending enrollment ownership'
                counter=int(time.time())//30
                digest=hmac.new(base64.b32decode(setup_secret),struct.pack('>Q',counter),hashlib.sha1).digest();offset=digest[-1]&15
                setup_code=str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
                confirmed=subprocess.check_output([str(out/'enroll/enroll'),str(db),'confirm',setup_token,binding,setup_code],env=enroll_settings,text=True,timeout=30).strip()
                assert confirmed=='yes',confirmed
                enrolling['services']['twoFactorAuthentication']=dict(type='otp',secret=setup_secret)
                enrolling['services']['resume']['loginTokens']=[]
                assert encode(client.find('users','enrolling')[0])==encode(enrolling)
                assert sql("SELECT counter FROM _wl_otp WHERE userId='enrolling';")==[[str(counter)]]
                assert sql("SELECT count(*) FROM _wl_enrol WHERE userId='enrolling';")==[['0']]
                client.command({'delete':'users','deletes':[dict(q=dict(_id='enrolling'),limit=1)]})
                assert sql("SELECT count(*) FROM _wl_otp WHERE userId='enrolling';")==[['0']]
                # Physical Mongo deletion also removes a pending private secret.
                enrolling['services'].pop('twoFactorAuthentication')
                client.command({'insert':'users','documents':[enrolling]})
                pending=subprocess.check_output([str(out/'enroll/enroll'),str(db),'start','enrolling','test-password',binding],env=enroll_settings,text=True,timeout=30).strip().splitlines()
                assert len(pending)==2,pending
                client.command({'delete':'users','deletes':[dict(q=dict(_id='enrolling'),limit=1)]})
                assert sql("SELECT count(*) FROM _wl_enrol WHERE userId='enrolling';")==[['0']]
                # SQL uniqueness follows the canonical BINARY/NULL semantics.
                assert auth('lookup','user')=='yes' and auth('lookup','User')=='no'
                assert sql("INSERT INTO users(id,username,createdAt,modifiedAt) VALUES('duplicate','user',"+q(stamp)+','+q(stamp)+');','exec')=='error'
                for identity,username in [('other','other'),('upper','User'),('nil1',None),('nil2',None)]:
                    assert sql('INSERT INTO users(id,username,createdAt,modifiedAt) VALUES('+q(identity)+','+('NULL' if username is None else q(username))+','+q(stamp)+','+q(stamp)+');','exec')=='ok'
                client.command({'insert':'users','documents':[dict(_id='null-user-one',username=None),dict(_id='null-user-two',username=None),dict(_id='no-username-one'),dict(_id='no-username-two')]})
                users_before=sql('SELECT json(_ferretdb_sjson) FROM '+q(physicals['users'])+' ORDER BY rowid;')
                assert sql("UPDATE users SET username='user' WHERE id='other';",'exec')=='error'
                source=sql('SELECT json(_ferretdb_sjson) FROM '+q(physicals['users'])+" WHERE _ferretdb_sjson->>'_id'='u';")[0][0]
                assert sql("INSERT INTO users(id,_wl_source) VALUES('source-duplicate',"+q(source)+');','exec')=='error'
                assert sql('SELECT json(_ferretdb_sjson) FROM '+q(physicals['users'])+' ORDER BY rowid;')==users_before
                assert sql("UPDATE users SET username='other',modifiedAt="+q(stamp)+" WHERE id='other';",'exec')=='ok'
                def concurrent_user(index):
                    return sql('INSERT INTO users(id,username,createdAt,modifiedAt) VALUES('+q('race-'+str(index))+",'race',"+q(stamp)+','+q(stamp)+');','exec')
                with ThreadPoolExecutor(max_workers=4) as executor:outcomes=list(executor.map(concurrent_user,range(4)))
                assert outcomes.count('ok')==1 and outcomes.count('error')==3,outcomes
                # Physical keys protect writes that never pass through SQL views.
                unique_name=sql("SELECT name FROM _wl_models WHERE table_name="+q(physicals['users'])+" AND json_extract(spec,'$.kind')='unique-model-key';")[0][0]
                indexes_before=client.command({'listIndexes':'users'})['cursor']['firstBatch']
                rejected=client.command({'insert':'users','documents':[dict(_id='blocked-mongo',username='user')]},check=False)
                assert rejected.get('writeErrors') and rejected['writeErrors'][0]['code']==11000,rejected
                assert client.find('users','blocked-mongo')==[]
                rejected=client.command({'update':'users','updates':[dict(q=dict(_id='other'),u={'$set':dict(username='user')})]},check=False)
                assert rejected.get('writeErrors') or rejected.get('ok')==0,rejected
                assert client.find('users','other')[0]['username']=='other'
                def mixed_writer(index):
                    if index%2==0:
                        return sql('INSERT INTO users(id,username,createdAt,modifiedAt) VALUES('+q('mixed-'+str(index))+",'mixed-race',"+q(stamp)+','+q(stamp)+');','exec')=='ok'
                    response=Client(listen).command({'insert':'users','documents':[dict(_id='mixed-'+str(index),username='mixed-race')]},check=False)
                    return response.get('ok')==1 and not response.get('writeErrors')
                with ThreadPoolExecutor(max_workers=8) as executor:mixed=list(executor.map(mixed_writer,range(8)))
                assert mixed.count(True)==1,mixed
                # Private constraints do not invent managed Mongo index metadata.
                assert client.command({'listIndexes':'users'})['cursor']['firstBatch']==indexes_before
                saved_index=sql('SELECT sql FROM sqlite_master WHERE name='+q(unique_name)+';')[0][0]
                # Simulate an older store or an externally removed constraint to keep
                # ambiguous-login denial and duplicate preflight covered independently.
                assert sql('DROP INDEX '+q(unique_name)+';','exec')=='ok'
                # A later direct Mongo duplicate must never select an arbitrary login.
                client.command({'insert':'users','documents':[dict(_id='mongo-duplicate',username='user',loginDisabled=True)]})
                assert auth('lookup','user')=='no'
                duplicate_before=sql('SELECT json(_ferretdb_sjson) FROM '+q(physicals['users'])+' ORDER BY rowid;')
                assert sql(mode='install')=='error'
                assert sql('SELECT json(_ferretdb_sjson) FROM '+q(physicals['users'])+' ORDER BY rowid;')==duplicate_before
                client.command({'delete':'users','deletes':[dict(q=dict(_id='mongo-duplicate'),limit=1)]})
                assert auth('lookup','user')=='yes' and sql(mode='install')=='ok'
                assert sql('SELECT sql FROM sqlite_master WHERE name='+q(unique_name)+';')==[[saved_index]]
                # Owned but altered definitions cannot be silently adopted or replaced.
                assert sql('DROP INDEX '+q(unique_name)+';','exec')=='ok'
                assert sql('CREATE INDEX '+q(unique_name)+' ON '+q(physicals['users'])+'(_ferretdb_sjson);','exec')=='ok'
                altered=sql('SELECT sql FROM sqlite_master WHERE name='+q(unique_name)+';')
                assert sql(mode='install')=='error'
                assert sql('SELECT sql FROM sqlite_master WHERE name='+q(unique_name)+';')==altered
                assert sql('DROP INDEX '+q(unique_name)+';','exec')=='ok' and sql(mode='install')=='ok'
                owner=sql('SELECT name,table_name,spec,version FROM _wl_models WHERE name='+q(unique_name)+';')[0]
                assert sql('DELETE FROM _wl_models WHERE name='+q(unique_name)+';','exec')=='ok'
                assert sql(mode='install')=='error','Unowned physical constraint was silently adopted'
                assert sql('SELECT sql FROM sqlite_master WHERE name='+q(unique_name)+';')==[[saved_index]]
                assert sql('INSERT INTO _wl_models VALUES('+','.join(q(value) for value in owner[:3])+',1);','exec')=='ok'
                assert sql(mode='install')=='ok'
                assert sql("UPDATE users SET loginDisabled=1 WHERE id='u';",'exec')=='ok'
                assert auth('lookup','user')=='no'
                assert sql("UPDATE users SET loginDisabled=0 WHERE id='u';",'exec')=='ok'
                replay=subprocess.run([str(out/'replay/replay'),str(db),'claim','u','JBSWY3DPEHPK3PXP','100','replay-fixture'],env=settings,capture_output=True,text=True,timeout=30)
                assert replay.returncode==0 and replay.stdout.strip()=='ok',replay.stdout+replay.stderr
                assert sql("SELECT counter FROM _wl_otp WHERE userId='u';")==[['100']]
                assert sql("DELETE FROM login_tokens WHERE hashedToken='replay-fixture';",'exec')=='ok'
                assert sql("SELECT counter FROM _wl_otp WHERE userId='u';")==[['100']]
                assert auth('issue')=='yes' and auth('check')=='yes'
                assert sql('SELECT count(*) FROM authmeta;')==[['1']]
                assert sql("INSERT INTO login_tokens VALUES('bad','absent','now',NULL);",'exec')=='error'
                assert sql("UPDATE login_tokens SET userId='absent';",'exec')=='error'
                assert auth('check')=='yes'
                assert sql(mode='install')=='ok' and auth('check')=='yes'
                assert sql("UPDATE users SET services_json='{\"password\":\"changed\"}' WHERE id='u';",'exec')=='ok'
                assert auth('check')=='no'
                assert sql("UPDATE users SET services_json='{\"password\":\"credential\"}' WHERE id='u';",'exec')=='ok'
                assert auth('issue')=='yes'
                assert sql("DELETE FROM users WHERE id='u';",'exec')=='ok'
                assert auth('check')=='no'
                assert sql("SELECT count(*) FROM _wl_otp WHERE userId='u';")==[['0']]
                assert sql('SELECT count(*) FROM login_tokens;')==[['0']] and sql('SELECT count(*) FROM authmeta;')==[['0']]
                client.command({'insert':'users','documents':[dict(_id='u',username='user',services=dict(password='credential'))]})
                assert auth('issue')=='yes' and auth('check')=='yes'
                client.command({'delete':'users','deletes':[dict(q=dict(_id='u'),limit=1)]})
                assert auth('check')=='no'
                assert sql('SELECT count(*) FROM login_tokens;')==[['0']] and sql('SELECT count(*) FROM authmeta;')==[['0']]
                client.command({'insert':'users','documents':[dict(_id='u',username='user',services=dict(password='credential'))]})
                assert auth('issue')=='yes'
                assert sql('PRAGMA foreign_keys=OFF; DELETE FROM login_tokens;','exec')=='ok'
                assert sql('SELECT count(*) FROM authmeta;')==[['0']]
                client.command({'update':'users','updates':[dict(q=dict(_id='u'),u={'$set':{'services.resume.loginTokens':[]}})]})
                # A denial during token cleanup rolls the entire Mongo user deletion back.
                assert auth('issue')=='yes'
                assert sql("CREATE TRIGGER deny_meta BEFORE DELETE ON authmeta BEGIN SELECT RAISE(ABORT,'test denial'); END;",'exec')=='ok'
                response=client.command({'delete':'users','deletes':[dict(q=dict(_id='u'),limit=1)]},check=False)
                assert response.get('ok')==0 and 'test denial' in response.get('errmsg',''),response
                assert client.find('users','u') and auth('check')=='yes'
                assert sql('DROP TRIGGER deny_meta;','exec')=='ok'
                client.command({'delete':'users','deletes':[dict(q=dict(_id='u'),limit=1)]})
                assert sql('SELECT count(*) FROM authmeta;')==[['0']]

                # Paired API lifecycle: source removal/expiry is authoritative too.
                client.command({'insert':'users','documents':[dict(_id='paired-api',username='paired-api',services=dict(password=shared_password,keep=DateMs(-1)))]})
                def pair(raw,extra=None,entered=''):
                    return subprocess.check_output([str(out/'factor/factor'),str(db),'api','paired-api','test-password',entered,raw],env=dict(settings,**(extra or {})),text=True).strip()
                def local_hash(raw):return hashlib.sha256(('welite-token-v2\0'+str(db.resolve())+'\0'+raw).encode()).hexdigest()
                def paired_check(raw):return subprocess.check_output([str(out/'factor/factor'),str(db),'check',raw],env=settings,text=True).strip()
                # Existing Meteor bearers are adopted without refreshing their expiry.
                adopted_when=int(time.time()*1000)-12345
                adopt_doc=dict(_id='adopted-user',username='adopted-user',services=dict(password=shared_password,resume=dict(loginTokens=[dict(token='adopt-legacy',when=DateMs(adopted_when),extra=Long(9007199254740993)),dict(hashedToken=meteor_hash('adopt-hashed'),when=DateMs(adopted_when))])),unknown=Binary(b'keep',4))
                client.command({'insert':'users','documents':[adopt_doc]})
                adopt_doc=client.find('users','adopted-user')[0]
                with ThreadPoolExecutor(max_workers=4) as pool:adopted=list(pool.map(lambda _:paired_check('adopt-legacy'),range(4)))
                assert adopted==['yes']*4,adopted
                old=adopt_doc['services']['resume']['loginTokens'][0];del old['token'];old['hashedToken']=meteor_hash('adopt-legacy')
                assert encode(client.find('users','adopted-user')[0])==encode(adopt_doc)
                assert paired_check('adopt-hashed')=='yes'
                assert sql('SELECT userId,sharedHash FROM _wl_pair WHERE hashedToken='+q(local_hash('adopt-hashed'))+';')==[['adopted-user',meteor_hash('adopt-hashed')]]
                assert sql('DELETE FROM login_tokens WHERE hashedToken='+q(local_hash('adopt-hashed'))+';','exec')=='ok'
                assert paired_check('adopt-hashed')=='no'
                assert all(entry.get('hashedToken')!=meteor_hash('adopt-hashed') for entry in client.find('users','adopted-user')[0]['services']['resume']['loginTokens']),'Deleted local row lost shared revocation identity'

                dates=sql('SELECT createdAt,expiresAt FROM login_tokens WHERE hashedToken='+q(local_hash('adopt-legacy'))+';')[0]
                assert round(datetime.fromisoformat(dates[0].replace('Z','+00:00')).timestamp()*1000)==adopted_when
                assert round(datetime.fromisoformat(dates[1].replace('Z','+00:00')).timestamp()*1000)==adopted_when+90*86400000
                # A later local-metadata or shared-write failure rolls conversion/history back.
                rollback_record=dict(token='adopt-rollback',when=DateMs(adopted_when))
                client.command({'update':'users','updates':[dict(q=dict(_id='adopted-user'),u={'$push':{'services.resume.loginTokens':rollback_record}})]})
                stable_adopt=encode(client.find('users','adopted-user')[0])
                for trigger in ["CREATE TRIGGER fail_adopt BEFORE INSERT ON authmeta BEGIN SELECT RAISE(IGNORE); END;",'CREATE TRIGGER fail_adopt BEFORE UPDATE ON '+q(physicals['users'])+" WHEN OLD._ferretdb_sjson->>'_id'='adopted-user' BEGIN SELECT RAISE(IGNORE); END;"]:
                    assert sql(trigger,'exec')=='ok'
                    assert paired_check('adopt-rollback')=='no'
                    assert encode(client.find('users','adopted-user')[0])==stable_adopt
                    assert sql('SELECT count(*) FROM _wl_seen WHERE hashedToken='+q(local_hash('adopt-rollback'))+';')==[['0']]
                    assert sql('SELECT count(*) FROM login_tokens WHERE hashedToken='+q(local_hash('adopt-rollback'))+';')==[['0']]
                    assert sql('SELECT count(*) FROM _wl_pair WHERE hashedToken='+q(local_hash('adopt-rollback'))+';')==[['0']]
                    assert sql('DROP TRIGGER fail_adopt;','exec')=='ok'
                assert paired_check('adopt-rollback')=='yes'
                # Expiry, duplicate ownership and disabled accounts deny adoption.
                for raw,records in [('adopt-expired',[dict(token='adopt-expired',when=DateMs(0))]),('adopt-duplicate',[dict(token='adopt-duplicate',when=DateMs(adopted_when)),dict(token='adopt-duplicate',when=DateMs(adopted_when+1))])]:
                    client.command({'update':'users','updates':[dict(q=dict(_id='adopted-user'),u={'$push':{'services.resume.loginTokens':{'$each':records}}})]})
                    assert paired_check(raw)=='no'
                client.command({'insert':'users','documents':[dict(_id='adopt-conflict',services=dict(resume=dict(loginTokens=[dict(hashedToken=meteor_hash('adopt-foreign'),when=DateMs(adopted_when))])))]})
                client.command({'update':'users','updates':[dict(q=dict(_id='adopted-user'),u={'$push':{'services.resume.loginTokens':dict(token='adopt-foreign',when=DateMs(adopted_when))}})]})
                assert paired_check('adopt-foreign')=='no'
                client.command({'update':'users','updates':[dict(q=dict(_id='adopted-user'),u={'$set':{'loginDisabled':True},'$push':{'services.resume.loginTokens':dict(token='adopt-disabled',when=DateMs(adopted_when))}})]})
                assert paired_check('adopt-disabled')=='no'
                # Observed password mutation revokes and history prevents restored-record adoption.
                client.command({'update':'users','updates':[dict(q=dict(_id='adopted-user'),u={'$set':{'loginDisabled':False,'services.password':{'bcrypt':'changed'}}})]})
                assert paired_check('adopt-legacy')=='no'
                client.command({'update':'users','updates':[dict(q=dict(_id='adopted-user'),u={'$set':{'services.password':shared_password},'$push':{'services.resume.loginTokens':old}})]})
                assert paired_check('adopt-legacy')=='no'
                client.command({'delete':'users','deletes':[dict(q=dict(_id='adopted-user'),limit=1),dict(q=dict(_id='adopt-conflict'),limit=1)]})
                assert pair('paired-first')=='yes'
                first=client.find('users','paired-api')[0]['services']['resume']['loginTokens'][0]
                assert first['hashedToken']==meteor_hash('paired-first') and isinstance(first['when'],DateMs)
                seen_key=hashlib.sha256(('welite-token-v2\0'+str(db.resolve())+'\0paired-first').encode()).hexdigest()
                pair_uuid=sql('SELECT userUUID FROM _wl_authsrc;')[0][0]
                assert sql('SELECT userId,sharedHash,sourceUUID FROM _wl_pair WHERE hashedToken='+q(seen_key)+';')==[['paired-api',meteor_hash('paired-first'),pair_uuid]]
                # Legacy backfill knows the identity, never guesses the other digest.
                assert sql('DELETE FROM _wl_pair WHERE hashedToken='+q(seen_key)+';','exec')=='ok'
                assert sql('CREATE TRIGGER deny_pair BEFORE INSERT ON _wl_pair BEGIN SELECT RAISE(IGNORE); END;','exec')=='ok'
                assert sql(mode='install')=='error'
                assert sql('DROP TRIGGER deny_pair;','exec')=='ok' and sql(mode='install')=='ok'
                assert sql('SELECT userId,sharedHash,sourceUUID FROM _wl_pair WHERE hashedToken='+q(seen_key)+';')==[['paired-api','',pair_uuid]]
                assert paired_check('paired-first')=='yes'
                assert sql('SELECT sharedHash FROM _wl_pair WHERE hashedToken='+q(seen_key)+';')==[[meteor_hash('paired-first')]]
                # Failure to record a new link rolls issuance and shared BSON back.
                assert sql('CREATE TRIGGER deny_pair BEFORE INSERT ON _wl_pair BEGIN SELECT RAISE(IGNORE); END;','exec')=='ok'
                pair_before=encode(client.find('users','paired-api')[0])
                assert pair('pair-denied') in ['no','error']
                assert encode(client.find('users','paired-api')[0])==pair_before
                assert sql('SELECT count(*) FROM login_tokens WHERE hashedToken='+q(local_hash('pair-denied'))+';')==[['0']]
                assert sql('DROP TRIGGER deny_pair;','exec')=='ok'

                assert sql('SELECT hashedToken FROM _wl_seen WHERE hashedToken='+q(seen_key)+';')==[[seen_key]]
                # Upgrade backfills existing credentials without touching shared BSON.
                assert sql('DELETE FROM _wl_seen WHERE hashedToken='+q(seen_key)+';','exec')=='ok'
                assert sql('CREATE TRIGGER deny_history BEFORE INSERT ON _wl_seen BEGIN SELECT RAISE(IGNORE); END;','exec')=='ok'
                assert sql(mode='install')=='error','Ignored backfill committed an incomplete bearer history'
                assert sql('DROP TRIGGER deny_history;','exec')=='ok'
                assert sql(mode='install')=='ok'
                assert sql('SELECT hashedToken FROM _wl_seen WHERE hashedToken='+q(seen_key)+';')==[[seen_key]]
                # Direct SQL digest changes preserve both old and new history.
                assert sql("INSERT INTO login_tokens VALUES('history-old','paired-api','date',NULL); UPDATE login_tokens SET hashedToken='history-new' WHERE hashedToken='history-old'; DELETE FROM login_tokens WHERE hashedToken='history-new';",'exec')=='ok'
                assert sql("SELECT hashedToken FROM _wl_seen WHERE hashedToken IN ('history-old','history-new') ORDER BY hashedToken;")==[['history-new'],['history-old']]
                # An ignored history write must roll back local/shared issuance.
                assert sql('CREATE TRIGGER deny_history BEFORE INSERT ON _wl_seen BEGIN SELECT RAISE(IGNORE); END;','exec')=='ok'
                history_before=encode(client.find('users','paired-api')[0])
                assert pair('history-denied') in ['no','error']
                assert encode(client.find('users','paired-api')[0])==history_before
                assert sql('DROP TRIGGER deny_history;','exec')=='ok'

                client.command({'update':'users','updates':[dict(q=dict(_id='paired-api'),u={'$pull':{'services.resume.loginTokens':dict(hashedToken=meteor_hash('paired-first'))}})]})
                assert paired_check('paired-first')=='no'
                client.command({'update':'users','updates':[dict(q=dict(_id='paired-api'),u={'$push':{'services.resume.loginTokens':first}})]})
                assert paired_check('paired-first')=='no','Restoring source record revived a revoked local credential'
                assert sql('SELECT hashedToken FROM _wl_seen WHERE hashedToken='+q(seen_key)+';')==[[seen_key]],'Revocation erased bearer history'
                assert all(entry.get('hashedToken')!=meteor_hash('paired-first') for entry in client.find('users','paired-api')[0]['services']['resume']['loginTokens'])
                # Seed the collision independently of the now-complete raw revocation.
                client.command({'update':'users','updates':[dict(q=dict(_id='paired-api'),u={'$push':{'services.resume.loginTokens':first}})]})
                snapshot=encode(client.find('users','paired-api')[0])
                assert pair('paired-first')=='no','Existing shared hash was reused'
                assert encode(client.find('users','paired-api')[0])==snapshot
                assert sql("SELECT count(*) FROM login_tokens WHERE userId='paired-api';")==[['0']]
                # A later failure while appending must roll back local token/meta too.
                assert sql('CREATE TRIGGER fail_pair BEFORE UPDATE ON '+q(physicals['users'])+" WHEN OLD._ferretdb_sjson->>'_id'='paired-api' BEGIN SELECT RAISE(IGNORE); END;",'exec')=='ok'
                assert pair('paired-failed')=='no' and encode(client.find('users','paired-api')[0])==snapshot
                assert sql("SELECT count(*) FROM login_tokens WHERE userId='paired-api';")==[['0']]
                assert sql('DROP TRIGGER fail_pair;','exec')=='ok'
                assert pair('paired-next')=='yes'
                tokens=client.find('users','paired-api')[0]['services']['resume']['loginTokens']
                tokens[-1]['when']=DateMs(0)
                client.command({'update':'users','updates':[dict(q=dict(_id='paired-api'),u={'$set':{'services.resume.loginTokens':tokens}})]})
                assert paired_check('paired-next')=='no'
                assert client.find('users','paired-api')[0]['services']['resume']['loginTokens']==[first]
                assert pair('paired-ambiguous')=='yes'
                client.command({'insert':'users','documents':[dict(_id='foreign-bearer',services=dict(resume=dict(loginTokens=[dict(hashedToken=meteor_hash('paired-ambiguous'),when=DateMs(1))])))]})
                assert paired_check('paired-ambiguous')=='no'
                assert client.find('users','foreign-bearer')[0]['services']['resume']['loginTokens']
                client.command({'delete':'users','deletes':[dict(q=dict(_id='foreign-bearer'),limit=1)]})
                # Stored lifetime wins over env; stored auth overrides resolve directly.
                client.command({'create':'settings'})
                client.command({'insert':'settings','documents':[dict(_id='shared-config',loginOptions=dict(loginExpirationInDays=2),ldap=dict(enabled=False))]})
                assert subprocess.check_output([str(out/'factor/factor'),str(db),'ttl'],env=dict(settings,ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS='7'),text=True).strip()==str(2*86400)
                assert pair('two-day',dict(ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS='7'))=='yes'
                # Fractional days retain exact Date milliseconds, not rounded seconds.
                for ordinal,days in enumerate([0.5,1.23456789012345,0.000001,1e-8]):
                    client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'loginOptions.loginExpirationInDays':days}})]})
                    raw='fractional-'+str(ordinal)
                    assert pair(raw)=='yes'
                    record=next(entry for entry in client.find('users','paired-api')[0]['services']['resume']['loginTokens'] if entry.get('hashedToken')==meteor_hash(raw))
                    when=int(record['when'])
                    expected=int(subprocess.check_output([os.environ.get('NODE','node'),'-e','console.log(new Date(Number(process.argv[1])+Number(process.argv[2])*86400000).getTime())',str(when),str(days)],text=True))
                    expiry=sql("SELECT expiresAt FROM login_tokens WHERE hashedToken="+q(local_hash(raw))+";")[0][0]
                    actual=round(datetime.fromisoformat(expiry.replace('Z','+00:00')).timestamp()*1000)
                    assert actual==expected,(backend,days,when,expiry,actual,expected)
                    if days>=0.5:assert paired_check(raw)=='yes'
                    if days==1e-8:assert paired_check(raw)=='no','Submillisecond token was rounded up to a second'
                client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'loginOptions.loginExpirationInDays':None}})]})
                assert subprocess.check_output([str(out/'factor/factor'),str(db),'ttl'],env=dict(settings,ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS='.5'),text=True).strip()=='43200'
                for value in ['NaN','Infinity','-1','36501','1,5']:
                    client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'loginOptions.loginExpirationInDays':value}})]})
                    assert pair('invalid-lifetime-'+value) in ['no','error']
                client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'loginOptions.loginExpirationInDays':2}})]})
                client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'loginOptions.require2fa':'all'}})]})
                before_policy=encode(client.find('users','paired-api')[0])
                assert pair('blocked-policy') in ['no','error']
                assert encode(client.find('users','paired-api')[0])==before_policy
                setup=subprocess.check_output([str(out/'enroll/enroll'),str(db),'start','paired-api','test-password',binding],env=settings,text=True).strip().splitlines()
                assert len(setup)==2,setup
                setup_token,setup_secret=setup;setup_counter=int(time.time())//30
                def setup_code(counter):
                    value=hmac.new(base64.b32decode(setup_secret),struct.pack('>Q',counter),hashlib.sha1).digest();offset=value[-1]&15
                    return str((struct.unpack('>I',value[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
                assert subprocess.check_output([str(out/'enroll/enroll'),str(db),'confirm',setup_token,binding,setup_code(setup_counter)],env=settings,text=True).strip()=='yes'
                assert pair('stored-mfa-no-code')=='no'
                client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'loginOptions.loginExpirationInDays':0.5}})]})
                assert pair('stored-mfa',dict(REQUIRE_2FA='off'),setup_code(setup_counter+1))=='yes','Stored MFA mode did not override deployment off'
                mfa_record=next(entry for entry in client.find('users','paired-api')[0]['services']['resume']['loginTokens'] if entry.get('hashedToken')==meteor_hash('stored-mfa'))
                mfa_expiry=sql('SELECT expiresAt FROM login_tokens WHERE hashedToken='+q(local_hash('stored-mfa'))+';')[0][0]
                assert round(datetime.fromisoformat(mfa_expiry.replace('Z','+00:00')).timestamp()*1000)==int(mfa_record['when'])+43200000
                assert paired_check('stored-mfa')=='yes'
                client.command({'update':'users','updates':[dict(q=dict(_id='paired-api'),u={'$push':{'services.resume.loginTokens':dict(hashedToken=meteor_hash('meteor-mfa-resume'),when=DateMs(int(time.time()*1000)))}})]})
                assert paired_check('meteor-mfa-resume')=='yes'
                assert sql("SELECT counter FROM _wl_otp WHERE userId='paired-api';")==[[str(setup_counter+1)]],'Resuming an approved Meteor session consumed another OTP'

                # Stored LDAP disabling/enabling and fallback also override env.
                client.command({'insert':'users','documents':[dict(_id='override-ldap',username='override-ldap',authenticationMethod='ldap',services=dict(password=shared_password))]})
                def ldap_pair(raw,flags=None):
                    return subprocess.check_output([str(out/'factor/factor'),str(db),'api','override-ldap','test-password','',raw],env=dict(settings,**(flags or {})),text=True).strip()
                assert ldap_pair('stored-ldap-off',dict(LDAP_ENABLE='true'))=='yes'
                client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'ldap.enabled':True}})]})
                assert ldap_pair('stored-ldap-on')=='no'
                client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'ldap.loginFallback':True}})]})
                assert ldap_pair('stored-ldap-fallback')=='yes'
                client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'ldap.loginFallback':False,'ldap.migrationAllowPasswordLogin':True}})]})
                assert ldap_pair('stored-ldap-migration')=='yes'
                client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'ldap.migrationAllowPasswordLogin':None}})]})
                assert ldap_pair('migration-null-env',dict(LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN='true'))=='yes'
                assert ldap_pair('migration-null-denied')=='no'
                client.command({'delete':'users','deletes':[dict(q=dict(_id='override-ldap'),limit=1)]})
                client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'loginOptions.require2fa':'off','sqrlEnabled':True}})]})
                client.command({'update':'users','updates':[dict(q=dict(_id='paired-api'),u={'$set':{'sqrl':dict(idk='identity',sqrlOnly=True)}})]})
                assert pair('blocked-sqrl',entered=setup_code(setup_counter+2))=='no'
                assert sql("SELECT counter FROM _wl_otp WHERE userId='paired-api';")==[[str(setup_counter+1)]]
                client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'sqrlEnabled':False,'loginOptions.require2fa':'off'}})]})
                config_table=sql("SELECT table_name FROM _ferretdb_collections WHERE name='settings';")[0][0]
                mutate_policy='UPDATE '+q(config_table)+" SET _ferretdb_sjson=jsonb(json_set(json(_ferretdb_sjson),'$.loginOptions.require2fa','all'));"
                stale=subprocess.check_output([str(out/'factor/factor'),str(db),'mutate','paired-api','test-password',setup_code(setup_counter+2),'stale-settings-proof',mutate_policy],env=settings,text=True).strip()
                assert stale=='no'
                assert sql("SELECT json_extract(_ferretdb_sjson,'$.loginOptions.require2fa') FROM "+q(config_table)+';')==[['all']]
                assert sql("SELECT counter FROM _wl_otp WHERE userId='paired-api';")==[[str(setup_counter+1)]]
                client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'loginOptions.passwordLoginEnabled':False}})]})
                assert pair('password-disabled',entered=setup_code(setup_counter+2))=='no'
                assert paired_check('stored-mfa')=='no'
                client.command({'update':'settings','updates':[dict(q=dict(_id='shared-config'),u={'$set':{'loginOptions.passwordLoginEnabled':True}})]})
                assert paired_check('stored-mfa')=='no','Policy restoration revived a revoked API credential'
                client.command({'delete':'settings','deletes':[dict(q=dict(_id='shared-config'),limit=1)]})
                client.command({'delete':'users','deletes':[dict(q=dict(_id='paired-api'),limit=1)]})

                check_expiry(out,db,client,sql,physicals['users'],shared_password,settings,meteor_hash,local_hash)

                # Disabling clears shared and private bearers in one transaction.
                revoke_token=meteor_hash('revokee-shared')
                revokee=dict(_id='revokee',username='revokee',services=dict(password=shared_password,resume=dict(loginTokens=[dict(hashedToken=revoke_token,when=DateMs(1794835200000)),dict(token='legacy-revokee',when=DateMs(-1))],unknown=Long(9007199254740993))),other=DateMs(-3))
                bystander=dict(_id='revoke-other',username='revoke-other',services=dict(password=shared_password,resume=dict(loginTokens=[dict(hashedToken=meteor_hash('bystander-shared'),when=DateMs(1))])))
                client.command({'insert':'users','documents':[revokee,bystander]})
                for who in ['revokee','revoke-other']:
                    assert subprocess.check_output([str(out/'factor/factor'),str(db),'api',who,'test-password','',who+'-local'],env=settings,text=True).strip()=='yes'
                pending_revoke=subprocess.check_output([str(out/'enroll/enroll'),str(db),'start','revokee','test-password',binding],env=enroll_settings,text=True).strip().splitlines()
                assert len(pending_revoke)==2,pending_revoke
                revoke_before=encode(client.find('users','revokee')[0]);bystander_before=encode(client.find('users','revoke-other')[0])
                def revoke(mutation=''):
                    return subprocess.check_output([str(out/'revoke/revoke'),str(db),'revokee','disable',mutation],env=settings,text=True).strip()
                def local_check(who):
                    return subprocess.check_output([str(out/'factor/factor'),str(db),'check',who+'-local'],env=settings,text=True).strip()
                for trigger in [
                    'CREATE TRIGGER reject_revoke BEFORE UPDATE ON '+q(physicals['users'])+" WHEN OLD._ferretdb_sjson->>'_id'='revokee' BEGIN SELECT RAISE(ABORT,'forced shared failure'); END;",
                    "CREATE TRIGGER reject_revoke BEFORE DELETE ON authmeta BEGIN SELECT RAISE(ABORT,'forced metadata failure'); END;",
                    'CREATE TRIGGER reject_revoke BEFORE UPDATE ON '+q(physicals['users'])+" WHEN OLD._ferretdb_sjson->>'_id'='revokee' BEGIN SELECT RAISE(IGNORE); END;",
                ]:
                    assert sql(trigger,'exec')=='ok'
                    assert revoke()=='no'
                    assert encode(client.find('users','revokee')[0])==revoke_before
                    assert local_check('revokee')=='yes'
                    assert sql('DROP TRIGGER reject_revoke;','exec')=='ok'
                # A changed source after script construction must abort before clearing.
                saved_settings=sql("SELECT settings FROM _ferretdb_collections WHERE name='users';")[0][0]
                assert revoke("UPDATE _ferretdb_collections SET settings=json_set(settings,'$.uuid','11111111-2222-4333-8444-555555555555') WHERE name='users';")=='no'
                assert encode(client.find('users','revokee')[0])==revoke_before
                assert sql("UPDATE _ferretdb_collections SET settings="+q(saved_settings)+" WHERE name='users';",'exec')=='ok'
                assert revoke()=='yes'
                revokee['services']['resume']['loginTokens']=[];revokee['loginDisabled']=True
                assert encode(client.find('users','revokee')[0])==encode(revokee)
                assert sql("SELECT count(*) FROM login_tokens WHERE userId='revokee';")==[['0']]
                assert sql("SELECT count(*) FROM _wl_enrol WHERE userId='revokee';")==[['0']]
                assert local_check('revokee')=='no'
                assert encode(client.find('users','revoke-other')[0])==bystander_before and local_check('revoke-other')=='yes'
                assert sql("UPDATE users SET loginDisabled=0 WHERE id='revokee';",'exec')=='ok'
                assert client.find('users','revokee')[0]['services']['resume']['loginTokens']==[] and local_check('revokee')=='no'
                for who in ['revokee','revoke-other']:
                    client.command({'delete':'users','deletes':[dict(q=dict(_id=who),limit=1)]})

                # Per-token revocation removes both hashed and legacy forms only.
                single=dict(_id='single-revoke',username='single-revoke',services=dict(password=shared_password,resume=dict(loginTokens=[dict(extra=Long(9007199254740993))],keep=DateMs(-1))))
                client.command({'insert':'users','documents':[single]})
                for raw in ['target-token','other-token','third-token']:
                    assert subprocess.check_output([str(out/'factor/factor'),str(db),'api','single-revoke','test-password','',raw],env=settings,text=True).strip()=='yes'
                for raw in ['target-token','other-token']:
                    client.command({'update':'users','updates':[dict(q=dict(_id='single-revoke'),u={'$push':{'services.resume.loginTokens':dict(token=raw,when=DateMs(2))}})]})
                single=client.find('users','single-revoke')[0]
                def check_single(raw):return subprocess.check_output([str(out/'factor/factor'),str(db),'check',raw],env=settings,text=True).strip()
                def revoke_one(raw):return subprocess.check_output([str(out/'revoke/revoke'),str(db),'single-revoke','one','',raw],env=settings,text=True).strip()
                before_single=encode(client.find('users','single-revoke')[0])
                for trigger in [
                    'CREATE TRIGGER reject_single BEFORE UPDATE ON '+q(physicals['users'])+" WHEN OLD._ferretdb_sjson->>'_id'='single-revoke' BEGIN SELECT RAISE(IGNORE); END;",
                    "CREATE TRIGGER reject_single BEFORE DELETE ON authmeta BEGIN SELECT RAISE(ABORT,'forced partial revoke'); END;",
                ]:
                    assert sql(trigger,'exec')=='ok' and revoke_one('target-token')=='no'
                    assert encode(client.find('users','single-revoke')[0])==before_single
                    assert check_single('target-token')=='yes' and check_single('other-token')=='yes'
                    assert sql('DROP TRIGGER reject_single;','exec')=='ok'
                assert revoke_one('target-token')=='yes'
                single['services']['resume']['loginTokens']=[v for v in single['services']['resume']['loginTokens'] if v.get('hashedToken')!=meteor_hash('target-token') and v.get('token')!='target-token']
                assert encode(client.find('users','single-revoke')[0])==encode(single)
                assert check_single('target-token')=='no' and check_single('other-token')=='yes' and check_single('third-token')=='yes'
                assert revoke_one('not-present')=='yes' and encode(client.find('users','single-revoke')[0])==encode(single)
                # An observed credential change uses targeted shared/local cleanup.
                client.command({'update':'users','updates':[dict(q=dict(_id='single-revoke'),u={'$set':{'services.password.bcrypt':'changed'}})]})
                assert check_single('other-token')=='no'
                assert all(value.get('hashedToken')!=meteor_hash('other-token') and value.get('token')!='other-token' for value in client.find('users','single-revoke')[0]['services']['resume']['loginTokens'])
                client.command({'update':'users','updates':[dict(q=dict(_id='single-revoke'),u={'$set':{'services.password':shared_password}})]})
                assert check_single('other-token')=='no' and check_single('third-token')=='yes'
                assert sql("UPDATE login_tokens SET expiresAt='2000-01-01T00:00:00.000Z' WHERE userId='single-revoke';",'exec')=='ok'
                assert check_single('third-token')=='no'
                assert client.find('users','single-revoke')[0]['services']['resume']['loginTokens']==[dict(extra=Long(9007199254740993))]
                client.command({'delete':'users','deletes':[dict(q=dict(_id='single-revoke'),limit=1)]})

                # Bind private auth to users UUID, not just reused IDs/passwords.
                source_user=dict(_id='u',username='user',services=dict(password='credential'))
                pending_user=dict(_id='source-pending',username='source-pending',services=dict(password=shared_password))
                client.command({'insert':'users','documents':[source_user,pending_user]})
                assert auth('issue')=='yes' and auth('check')=='yes'
                replayed=subprocess.check_output([str(out/'replay/replay'),str(db),'claim','u','JBSWY3DPEHPK3PXP','100','source-ledger'],env=settings,text=True).strip()
                assert replayed=='ok'
                # The replay harness seeds a legacy API row without a digest link.
                # Complete its one-time migration before the idempotence snapshot.
                assert sql(mode='install')=='ok'
                assert sql("SELECT userId,sharedHash FROM _wl_pair WHERE hashedToken='source-ledger';")==[['u','']]

                def pending_source():
                    values=subprocess.check_output([str(out/'enroll/enroll'),str(db),'start','source-pending','test-password',binding],env=enroll_settings,text=True,timeout=30).strip().splitlines()
                    assert len(values)==2,values
                    return values
                pending_token,pending_secret=pending_source()
                source_settings=sql("SELECT table_name,settings FROM _ferretdb_collections WHERE name='users';")[0]
                old_uuid=json.loads(source_settings[1])['uuid']
                assert sql('SELECT userTable,userUUID FROM _wl_authsrc;')==[[source_settings[0],old_uuid]]
                private_tables=['login_tokens','authmeta','_wl_otp','_wl_enrol','_wl_authsrc','_wl_seen','_wl_sweep','_wl_pair']
                def private_snapshot():return {name:sql('SELECT * FROM '+q(name)+' ORDER BY 1;') for name in private_tables}
                # Proofs cannot cross a rebind even when account snapshots match.
                rebound_uuid='11111111-2222-4333-8444-555555555555'
                rebind="UPDATE _ferretdb_collections SET settings=json_set(settings,'$.uuid',"+q(rebound_uuid)+") WHERE name='users'; UPDATE _wl_authsrc SET userUUID="+q(rebound_uuid)+';'
                stale_proof=subprocess.check_output([str(out/'factor/factor'),str(db),'mutate','source-pending','test-password','','stale-source-proof',rebind],env=settings,text=True).strip()
                assert stale_proof=='no'
                assert sql("UPDATE _ferretdb_collections SET settings="+q(source_settings[1])+" WHERE name='users'; UPDATE _wl_authsrc SET userUUID="+q(old_uuid)+';','exec')=='ok'
                stale_setup=subprocess.check_output([str(out/'enroll/enroll'),str(db),'start','source-pending','test-password',binding,rebind],env=enroll_settings,text=True).strip()
                assert stale_setup=='no'
                assert sql("UPDATE _ferretdb_collections SET settings="+q(source_settings[1])+" WHERE name='users'; UPDATE _wl_authsrc SET userUUID="+q(old_uuid)+';','exec')=='ok'
                preserved=private_snapshot()
                seen_before_rebind=sql('SELECT hashedToken FROM _wl_seen ORDER BY hashedToken;')
                assert sql(mode='install')=='ok','Reinstall failed with paired state'
                after_reinstall=private_snapshot()
                assert after_reinstall==preserved,[name for name in private_tables if preserved[name]!=after_reinstall[name]]
                assert auth('check')=='yes'
                # Bad source metadata aborts installer cleanup and source rebinding together.
                assert sql("UPDATE _ferretdb_collections SET settings=json_set(settings,'$.uuid','bad') WHERE name='users';",'exec')=='ok'
                assert auth('lookup','user')=='no'
                assert sql(mode='install')=='error' and private_snapshot()==preserved
                assert sql("UPDATE _ferretdb_collections SET settings="+q(source_settings[1])+" WHERE name='users';",'exec')=='ok'
                assert auth('check')=='yes'
                # Upgrade an older unbound adapter: revoke credentials/setup once,
                # retaining its conservative replay boundary until provenance is known.
                assert sql('DROP TABLE _wl_authsrc;','exec')=='ok'
                assert auth('lookup','user')=='no'
                assert sql(mode='install')=='ok'
                for name in ['login_tokens','authmeta','_wl_enrol']:assert sql('SELECT count(*) FROM '+q(name)+';')==[['0']]
                assert sql('SELECT hashedToken FROM _wl_seen ORDER BY hashedToken;')==seen_before_rebind
                assert sql("SELECT counter FROM _wl_otp WHERE userId='u';")==[['100']]
                assert auth('issue')=='yes'
                pending_token,pending_secret=pending_source()
                client.command({'drop':'users'})
                # Even before repair/reinstall, a replacement collection cannot use
                # stale views/credentials; source guard also covers proof factories.
                client.command({'create':'users'})
                client.command({'insert':'users','documents':[source_user,pending_user]})
                new_uuid=json.loads(sql("SELECT settings FROM _ferretdb_collections WHERE name='users';")[0][0])['uuid']
                assert new_uuid!=old_uuid
                assert auth('lookup','user')=='no' and auth('issue')=='no' and auth('check')=='no'
                counter=int(time.time())//30
                digest=hmac.new(base64.b32decode(pending_secret),struct.pack('>Q',counter),hashlib.sha1).digest();offset=digest[-1]&15
                code=str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
                assert subprocess.check_output([str(out/'enroll/enroll'),str(db),'confirm',pending_token,binding,code],env=enroll_settings,text=True).strip()=='no'
                old_pairs=sql('SELECT * FROM _wl_pair ORDER BY hashedToken;')
                assert old_pairs
                assert sql('CREATE TRIGGER deny_pair_clear BEFORE DELETE ON _wl_pair BEGIN SELECT RAISE(IGNORE); END;','exec')=='ok'
                assert sql(mode='install')=='error','Ignored obsolete-link cleanup committed source rebinding'
                assert sql('SELECT * FROM _wl_pair ORDER BY hashedToken;')==old_pairs
                assert sql('SELECT userUUID FROM _wl_authsrc;')==[[old_uuid]]
                assert sql('DROP TRIGGER deny_pair_clear;','exec')=='ok'
                assert sql(mode='install')=='ok'
                assert sql('SELECT userUUID FROM _wl_authsrc;')==[[new_uuid]]
                assert sql('SELECT count(*) FROM _wl_pair;')==[['0']]
                assert set(map(tuple,seen_before_rebind)).issubset(set(map(tuple,sql('SELECT hashedToken FROM _wl_seen;'))))
                for name in ['login_tokens','authmeta','_wl_otp','_wl_enrol']:assert sql('SELECT count(*) FROM '+q(name)+';')==[['0']]
                assert auth('check')=='no' and auth('issue')=='yes' and auth('check')=='yes'

                # Normalized tables must never be overwritten by this installer.
                rejected=out/'legacy.db'
                with sqlite3.connect(rejected) as con:con.execute('CREATE TABLE boards(value TEXT)');con.execute("INSERT INTO boards VALUES('preserve')")
                assert sql(mode='install',database=rejected)=='error'
                with sqlite3.connect(rejected) as con:
                    assert con.execute('SELECT * FROM boards').fetchall()==[('preserve',)]
                    assert not con.execute("SELECT name FROM sqlite_master WHERE name='_ferretdb_collections'").fetchall()
                child_rejected=out/'child.db'
                with sqlite3.connect(child_rejected) as con:
                    con.execute('CREATE TABLE board_labels(value TEXT)');con.execute("INSERT INTO board_labels VALUES('preserve child')")
                assert sql(mode='install',database=child_rejected)=='error'
                with sqlite3.connect(child_rejected) as con:
                    assert con.execute('SELECT * FROM board_labels').fetchall()==[('preserve child',)]
                    assert not con.execute("SELECT name FROM sqlite_master WHERE name='_ferretdb_collections'").fetchall()
                private_rejected=out/'private.db'
                with sqlite3.connect(private_rejected) as con:
                    con.execute('CREATE TABLE login_tokens(value TEXT)');con.execute("INSERT INTO login_tokens VALUES('preserve token')")
                assert sql(mode='install',database=private_rejected)=='error'
                with sqlite3.connect(private_rejected) as con:
                    assert con.execute('SELECT * FROM login_tokens').fetchall()==[('preserve token',)]
                    assert not con.execute("SELECT name FROM sqlite_master WHERE name='_ferretdb_collections'").fetchall()
                fresh=out/'fresh';fresh.mkdir();freshdb=fresh/'wekan.sqlite'
                assert sql(mode='install',database=freshdb)=='ok'
                assert sql("INSERT INTO boards(id,title,slug,createdAt) VALUES('fresh','Fresh','fresh',"+q(stamp)+');','exec',freshdb)=='ok'
                freshstate=out/'fstate';freshstate.mkdir();freshport=port()
                freshserver=subprocess.Popen([str(ferret),'--handler=sqlite','--sqlite-url='+fresh.as_uri()+'/','--state-dir='+str(freshstate),'--listen-addr=127.0.0.1:'+str(freshport),'--debug-addr=127.0.0.1:'+str(port()),'--log-level=ERROR','--telemetry=disable'],stdout=log,stderr=log,env=settings)
                try:
                    freshclient=Client(freshport)
                    for attempt in range(100):
                        try:document=freshclient.find('boards','fresh')[0];break
                        except (OSError,EOFError):
                            assert freshserver.poll() is None,'Fresh metadata prevented FerretDB startup'
                            time.sleep(.05)
                    else:raise AssertionError('Fresh FerretDB did not start')
                    assert document['title']=='Fresh' and document['createdAt']==DateMs(1794832496789)
                    freshclient.command({'insert':'users','documents':[dict(_id='boot-user',username='boot-user')]})
                    duplicate=freshclient.command({'insert':'users','documents':[dict(_id='boot-duplicate',username='boot-user')]},check=False)
                    assert duplicate.get('writeErrors') and duplicate['writeErrors'][0]['code']==11000,duplicate
                    freshclient.command({'insert':'boards','documents':[{'_id':'from-ferret','title':'From Ferret'}]})
                    assert sql("SELECT title FROM boards WHERE id='from-ferret';",database=freshdb)==[['From Ferret']]
                finally:
                    freshserver.terminate()
                    try:freshserver.wait(timeout=10)
                    except subprocess.TimeoutExpired:freshserver.kill();freshserver.wait()
                olddir=out/'oldtext';olddir.mkdir();olddb=olddir/'wekan.sqlite'
                with sqlite3.connect(db) as con:entry=con.execute("SELECT name,table_name,settings FROM _ferretdb_collections WHERE name='boards'").fetchone()
                oldsettings=json.loads(entry[2]);oldsettings.pop('storage',None)
                with sqlite3.connect(olddb) as con:
                    con.execute('CREATE TABLE _ferretdb_collections(name TEXT UNIQUE,table_name TEXT UNIQUE,settings TEXT) STRICT')
                    con.execute('INSERT INTO _ferretdb_collections VALUES(?,?,?)',(entry[0],entry[1],json.dumps(oldsettings)))
                    con.execute('CREATE TABLE "'+entry[1]+'"(_ferretdb_sjson TEXT NOT NULL) STRICT')
                    con.execute('INSERT INTO "'+entry[1]+'"(rowid,_ferretdb_sjson) VALUES(7,?)',(seed,))
                    con.execute('CREATE UNIQUE INDEX "'+entry[1]+'__id_" ON "'+entry[1]+'"(_ferretdb_sjson->'+q('_id')+')')
                assert sql(mode='install',database=olddb)=='ok'
                oldstate=out/'ostate';oldstate.mkdir();oldport=port()
                oldserver=subprocess.Popen([str(ferret),'--handler=sqlite','--sqlite-url='+olddir.as_uri()+'/','--state-dir='+str(oldstate),'--listen-addr=127.0.0.1:'+str(oldport),'--debug-addr=127.0.0.1:'+str(port()),'--log-level=ERROR','--telemetry=disable'],stdout=log,stderr=log,env=settings)
                try:
                    oldclient=Client(oldport)
                    for attempt in range(100):
                        try:document=oldclient.find('boards','board')[0];break
                        except (OSError,EOFError):
                            assert oldserver.poll() is None,'Old TEXT metadata prevented startup'
                            time.sleep(.05)
                    else:raise AssertionError('Old TEXT server did not start')
                    assert document['title']=='FerretDB back'
                    assert sql("UPDATE boards SET title='Text after restart' WHERE id='board';",'exec',olddb)=='ok'
                    assert oldclient.find('boards','board')[0]['title']=='Text after restart'
                    with sqlite3.connect(olddb) as con:assert con.execute('SELECT rowid FROM "'+entry[1]+'"').fetchone()==(7,)
                finally:
                    oldserver.terminate()
                    try:oldserver.wait(timeout=10)
                    except subprocess.TimeoutExpired:oldserver.kill();oldserver.wait()
                print('PASS:',backend,'live FerretDB-to-SQL and SQL-to-FerretDB roots, BSON types/bits, nested paths, defaults, all child views, references/cascades, private tokens, unique accounts and typed relation edits, rollback, immutable IDs and ownership-safe reinstall')
            finally:
                server.terminate()
                try:server.wait(timeout=10)
                except subprocess.TimeoutExpired:server.kill();server.wait()
