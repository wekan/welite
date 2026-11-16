"""Real FerretDB and Welite root projections share one SQLite document file."""
import json
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
        settings=dict(os.environ);settings.pop('WELITE_SHORT_NAMES',None);settings.pop('WELITE_ENTROPY_FILE',None);settings.pop('WELITE_SQLITE_EXT',None)
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
                assert sql("INSERT INTO boards(id,title,slug,createdAt) VALUES('new','New','new','1969-12-31T23:59:59.999Z');",'exec')=='ok'
                assert client.find('boards','new')[0]['createdAt']==DateMs(-1)
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
                print('PASS:',backend,'live FerretDB-to-SQL and SQL-to-FerretDB roots, BSON types/bits, nested paths, defaults, all child views and typed relation edits, rollback, immutable IDs and ownership-safe reinstall')
            finally:
                server.terminate()
                try:server.wait(timeout=10)
                except subprocess.TimeoutExpired:server.kill();server.wait()
