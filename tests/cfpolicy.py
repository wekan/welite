"""API value policies follow current board administration, never site-admin status."""
import json
import sqlite3
from urllib.parse import quote
from wire import DateMs, encode

FIELDS=['policy-open','policy-private','policy-locked','policy-both','policy-gone','policy-wrong','policy-empty']

def exercise(call,base,uid,role,site_admin,field,snapshot,fail,clear,shared):
    def read(method='GET',suffix='',data=None):
        status,_,body=call(method,base+suffix,data)
        assert status==200,(method,suffix,status,body)
        return json.loads(body)['customFields']
    def values(rows):return {row['_id']:row.get('value','MISSING') for row in rows}
    def expect(admin=False):
        before=snapshot();rows=read();assert snapshot()==before,'GET changed source'
        assert [row['_id'] for row in rows]==(FIELDS if shared else sorted(FIELDS)),(rows,FIELDS)
        result=values(rows)
        assert result['policy-open']=='open' and result['policy-locked']=='locked',result
        for name,value in [('policy-private','private'),('policy-both','both')]:
            assert result[name]==(value if admin else None),result
        assert result['policy-gone'] is None and result['policy-wrong'] is None,result
        assert result['policy-empty']==('MISSING' if shared else '' if admin else None),result
    def write(name,status):
        before=snapshot()
        actual,_,body=call('POST',base+'/customFields/'+name,dict(value=name))
        assert actual==status,(name,status,actual,body)
        if status!=200:assert snapshot()==before,(name,'Denied write changed source')
    site_admin(False);role(True,True,False);expect(True)
    # Empty fields remain positionally present; hidden values never reach response routes.
    role(False,True,False);expect()
    definition_path=base.split('/lists/',1)[0]+'/custom-fields'
    def create(private,status):
        before=snapshot();actual,_,body=call('POST',definition_path,dict(name='Policy creation',readOnly=True,adminOnly=private))
        assert actual==status,(private,status,actual,body)
        if status!=200:assert snapshot()==before
        else:
            result=json.loads(call('GET',definition_path+'/'+json.loads(body)['_id'],None)[2])
            assert result['readOnly'] is True and result['adminOnly'] is private,result
    create(False,200);create(True,403)
    for method,suffix,data in [('PUT','',dict(title='Policy card')),
                               ('POST','/members/'+quote(uid,safe=''),None),
                               ('DELETE','/members/'+quote(uid,safe=''),None),
                               ('POST','/assignees/'+quote(uid,safe=''),None),
                               ('DELETE','/assignees/'+quote(uid,safe=''),None),
                               ('POST','/archive',dict(isArchive='false'))]:
        result=values(read(method,suffix,data))
        assert result['policy-private'] is None and result['policy-both'] is None,result
    for name in ['policy-private','policy-locked','policy-both']:write(name,403)
    write('policy-open',200);field('policy-open',dict(value='open'))
    role(False,True,True);expect()
    write('policy-open',403)
    # A global administrator without active board administration still cannot
    # read/write protected fields, even though ordinary board access is allowed.
    site_admin(True);role(False,False,False);expect()
    create(True,403)
    for name in ['policy-private','policy-locked','policy-both']:write(name,403)
    write('policy-open',200);field('policy-open',dict(value='open'))
    site_admin(False);role(True,True,False)
    for name in ['policy-private','policy-locked','policy-both']:write(name,200)
    for name in ['policy-private','policy-locked','policy-both']:field(name,dict(value=name.removeprefix('policy-')))
    expect(True)
    # A trigger revokes the authority after the actual write. The second guard
    # must roll back both the value and the triggered policy/role change.
    role(False,True,False)
    for stage in ['definition','membership','disabled','association','card']+(['binding'] if shared else []):
        fail(stage)
        try:
            before=snapshot();write('policy-open',500)
            assert snapshot()==before,stage
        finally:clear()
    for stage in ['definition','membership','disabled','association','repoint']+(['binding','readonly'] if shared else []):
        fail(stage,True)
        try:create(False,500)
        finally:clear()
    # Real BSON numeric/date values are never boolean policy grants.
    if shared:
        for bad in [0,1,'false',DateMs(0)]:
            field('policy-open',dict(adminOnly=bad))
            before=snapshot();assert values(read())['policy-open'] is None
            write('policy-open',403);assert snapshot()==before
        field('policy-open',dict(adminOnly=False))
        for bad in [0,1,'false',DateMs(0)]:
            field('policy-open',dict(readOnly=bad))
            assert values(read())['policy-open']=='open'
            write('policy-open',403)
        field('policy-open',dict(readOnly=False))
        for bad in [1,DateMs(1),'true']:
            role(bad,True,False)
            assert values(read())['policy-private'] is None
            write('policy-private',403)
        role(True,True,False)
    else:role(True,True,False)
    site_admin(False);expect(True)
    print('PASS: API field-policy redaction on every card response, null/missing positions, editor/read-only/inactive/global-admin boundaries, malformed BSON flags and transaction-time policy/role/source rollback')


def run_native(call,db,uid,board,list_id):
    cid='policy-card';base='/api/boards/'+quote(board,safe='')+'/lists/'+quote(list_id,safe='')+'/cards/'+cid
    with sqlite3.connect(db) as con:
        original_user=con.execute('SELECT isAdmin FROM users WHERE id=?',(uid,)).fetchone()[0]
        original_member=con.execute('SELECT isAdmin,isActive,isReadOnly FROM board_members WHERE boardId=? AND userId=?',(board,uid)).fetchone()
        con.execute("INSERT INTO cards(id,boardId,listId,title,userId,createdAt,modifiedAt,dateLastActivity) VALUES(?,?,?,'Policy card',?,'now','now','now')",(cid,board,list_id,uid))
        for name in FIELDS:
            if name!='policy-gone':
                con.execute("INSERT INTO custom_fields(id,name,type,readOnly,adminOnly,modifiedAt) VALUES(?,?,'text',?,?,'now')",(name,name,int(name in ['policy-locked','policy-both']),int(name in ['policy-private','policy-both','policy-empty'])))
                if name!='policy-wrong':con.execute('INSERT INTO custom_field_boards VALUES(?,?)',(name,board))
            con.execute('INSERT INTO card_custom_field_values(cardId,customFieldId,value) VALUES(?,?,?)',(cid,name,None if name=='policy-empty' else name.removeprefix('policy-')))
    def role(admin,active,readonly):
        with sqlite3.connect(db) as con:con.execute('UPDATE board_members SET isAdmin=?,isActive=?,isReadOnly=? WHERE boardId=? AND userId=?',(int(admin),int(active),int(readonly),board,uid))
    def site_admin(value):
        with sqlite3.connect(db) as con:con.execute('UPDATE users SET isAdmin=? WHERE id=?',(int(value),uid))
    def field(name,changes):
        with sqlite3.connect(db) as con:
            if 'value' in changes:con.execute('UPDATE card_custom_field_values SET value=? WHERE cardId=? AND customFieldId=?',(changes['value'],cid,name))
            else:
                for key,value in changes.items():con.execute('UPDATE custom_fields SET '+key+'=? WHERE id=?',(value,name))
    def snapshot():
        with sqlite3.connect(db) as con:
            return tuple(con.execute('SELECT * FROM '+table+' ORDER BY 1,2').fetchall() for table in ['cards','custom_fields','custom_field_boards','card_custom_field_values','board_members','users','activities'])
    def fail(stage,creation=False):
        q=lambda value:"'"+value.replace("'","''")+"'"
        action=dict(repoint='SELECT 1;',definition="UPDATE custom_fields SET adminOnly=1 WHERE id='policy-open';",
                    membership='UPDATE board_members SET isActive=0 WHERE boardId='+q(board)+' AND userId='+q(uid)+';',
                    disabled='UPDATE users SET loginDisabled=1 WHERE id='+q(uid)+';',
                    association="DELETE FROM custom_field_boards WHERE customFieldId='policy-open';",
                    card='UPDATE cards SET boardId=\'other\' WHERE id='+q(cid)+';')[stage]
        if creation:
            if stage=='definition':action="UPDATE custom_fields SET adminOnly=1 WHERE id=json_extract(NEW.data_json,'$.customFieldId');"
            if stage=='association':action="DELETE FROM custom_field_boards WHERE customFieldId=json_extract(NEW.data_json,'$.customFieldId');"
            if stage=='repoint':action="INSERT INTO custom_field_boards VALUES(json_extract(NEW.data_json,'$.customFieldId'),'path foreign 漢');"
            target='AFTER INSERT ON activities'
        else:target="AFTER UPDATE ON card_custom_field_values WHEN NEW.cardId='policy-card' AND NEW.customFieldId='policy-open'"
        with sqlite3.connect(db) as con:con.execute('CREATE TRIGGER policy_fail '+target+' BEGIN '+action+' END')
    def clear():
        with sqlite3.connect(db) as con:con.execute('DROP TRIGGER policy_fail')
    try:exercise(call,base,uid,role,site_admin,field,snapshot,fail,clear,False)
    finally:
        role(*original_member);site_admin(original_user)


def run_shared(call,client,db,uid,board,list_id):
    cid='policy-card';base='/api/boards/'+quote(board,safe='')+'/lists/'+quote(list_id,safe='')+'/cards/'+cid
    original_user=client.find('users',uid)[0];original_board=client.find('boards',board)[0]
    def update(collection,identity,changes):
        assert client.command({'update':collection,'updates':[dict(q=dict(_id=identity),u={'$set':changes})]})['n']==1
    documents=[dict(_id=name,name=name,type='text',boardIds=[] if name=='policy-wrong' else [board],
                    readOnly=name in ['policy-locked','policy-both'],adminOnly=name in ['policy-private','policy-both','policy-empty']) for name in FIELDS if name!='policy-gone']
    assert client.command({'insert':'customFields','documents':documents})['n']==len(documents)
    fields=[dict(_id=name,value=name.removeprefix('policy-')) for name in FIELDS]
    del fields[-1]['value']
    assert client.command({'insert':'cards','documents':[dict(_id=cid,title='Policy card',boardId=board,listId=list_id,customFields=fields,unknown=DateMs(-7))]})['n']==1
    def role(admin,active,readonly):update('boards',board,dict(members=[dict(userId=uid,isAdmin=admin,isActive=active,isReadOnly=readonly)]))
    def site_admin(value):update('users',uid,dict(isAdmin=bool(value)))
    def field(name,changes):
        if 'value' in changes:
            card=client.find('cards',cid)[0]
            next(row for row in card['customFields'] if row['_id']==name)['value']=changes['value']
            update('cards',cid,dict(customFields=card['customFields']))
        else:update('customFields',name,changes)
    def snapshot():
        with sqlite3.connect(db) as con:
            registry=con.execute('SELECT * FROM _wl_models ORDER BY name').fetchall()
            for collection in ['customFields','activities']:
                physical=con.execute('SELECT table_name FROM _ferretdb_collections WHERE name=?',(collection,)).fetchone()[0]
                registry.append(con.execute('SELECT _ferretdb_sjson FROM "'+physical.replace('"','""')+'" ORDER BY json_extract(_ferretdb_sjson,\'$._id\')').fetchall())
        return registry,[encode(client.find(collection,identity)[0]) for collection,identity in [('users',uid),('boards',board),('cards',cid)]+[('customFields',row['_id']) for row in documents]]
    def fail(stage,creation=False):
        q=lambda value:"'"+value.replace("'","''")+"'"
        with sqlite3.connect(db) as con:
            tables={name:'"'+table.replace('"','""')+'"' for name,table in con.execute('SELECT name,table_name FROM _ferretdb_collections')}
            field_table=tables['customFields'];board_table=tables['boards'];user_table=tables['users'];card_table=tables['cards']
            action=dict(repoint='UPDATE '+field_table+" SET _ferretdb_sjson=jsonb_insert(_ferretdb_sjson,'$.boardIds[#]','path foreign 漢','$.\"$s\".p.boardIds.i[#]',json('{\"t\":\"string\"}')) WHERE json_extract(_ferretdb_sjson,'$._id')='policy-open';",
                        readonly='UPDATE '+field_table+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.readOnly',0,'$.\"$s\".p.readOnly.t','date') WHERE json_extract(_ferretdb_sjson,'$._id')='policy-open';",binding="DELETE FROM _wl_models WHERE name='custom_fields';",definition='UPDATE '+field_table+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.adminOnly',json('true')) WHERE json_extract(_ferretdb_sjson,'$._id')='policy-open';",
                        membership='UPDATE '+board_table+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.members[0].isActive',json('false')) WHERE json_extract(_ferretdb_sjson,'$._id')="+q(board)+';',
                        disabled='UPDATE '+user_table+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.loginDisabled',json('true'),'$.\"$s\".p.loginDisabled',json('{\"t\":\"bool\"}'),'$.\"$s\".\"$k\"[#]','loginDisabled') WHERE json_extract(_ferretdb_sjson,'$._id')="+q(uid)+';',
                        association='UPDATE '+field_table+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.boardIds',json('[]'),'$.\"$s\".p.boardIds.i',json('[]')) WHERE json_extract(_ferretdb_sjson,'$._id')='policy-open';",
                        card='UPDATE '+card_table+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.boardId','other') WHERE json_extract(_ferretdb_sjson,'$._id')="+q(cid)+';')[stage]
            if creation:
                action=action.replace("='policy-open'", "=json_extract(NEW._ferretdb_sjson,'$.customFieldId')")
                target='AFTER INSERT ON '+tables['activities']
            else:target='AFTER UPDATE ON '+card_table+" WHEN json_extract(NEW._ferretdb_sjson,'$._id')='policy-card'"
            con.execute('CREATE TRIGGER policy_fail '+target+' BEGIN '+action+' END')
    def clear():
        with sqlite3.connect(db) as con:con.execute('DROP TRIGGER policy_fail')
    try:
        exercise(call,base,uid,role,site_admin,field,snapshot,fail,clear,True)
        # A valid JSON source with inconsistent BSON metadata must fail closed.
        with sqlite3.connect(db) as con:
            table=con.execute("SELECT table_name FROM _ferretdb_collections WHERE name='customFields'").fetchone()[0]
            table='"'+table.replace('"','""')+'"'
            where=" WHERE json_extract(_ferretdb_sjson,'$._id')='policy-open'"
            saved=con.execute('SELECT _ferretdb_sjson FROM '+table+where).fetchone()[0]
            con.execute('UPDATE '+table+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.adminOnly','false')"+where)
        try:
            with sqlite3.connect(db) as con:before='\n'.join(con.iterdump())
            status,_,body=call('GET',base,None)
            assert status==200,(status,body)
            assert all(row.get('value') is None for row in json.loads(body)['customFields'])
            assert call('POST',base+'/customFields/policy-open',dict(value='attack'))[0]==403
            with sqlite3.connect(db) as con:assert '\n'.join(con.iterdump())==before
        finally:
            with sqlite3.connect(db) as con:con.execute('UPDATE '+table+' SET _ferretdb_sjson=?'+where,(saved,))
        # Exercise more than one union batch against actual BSON-backed views.
        batch=[dict(_id='policy-batch-'+str(i),name=str(i),type='text',boardIds=[board],adminOnly=bool(i%2)) for i in range(70)]
        assert client.command({'insert':'customFields','documents':batch})['n']==len(batch)
        role(False,True,False)
        rows=[dict(_id=row['_id'],value=row['name']) for row in batch]
        update('cards',cid,dict(customFields=rows))
        before=encode(client.find('cards',cid)[0]);status,_,body=call('GET',base,None)
        assert status==200,(status,body)
        assert json.loads(body)['customFields']==[dict(_id=row['_id'],value=None if i%2 else str(i)) for i,row in enumerate(batch)]
        assert encode(client.find('cards',cid)[0])==before
        print('PASS: corrupt BSON policy metadata masks values without mutation; 70-field shared batches preserve positions and readable values')
    finally:
        update('boards',board,dict(members=original_board['members']))
        operation={'$set':dict(isAdmin=original_user['isAdmin'])} if 'isAdmin' in original_user else {'$unset':dict(isAdmin='')}
        assert client.command({'update':'users','updates':[dict(q=dict(_id=uid),u=operation)]})['n']==1
