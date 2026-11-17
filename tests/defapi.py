"""Definition creation commits its definition, board link and activity together."""
import json
import sqlite3
from urllib.parse import quote, urlencode
from setapi import exercise as check_settings


def exercise(call, board, uid, snapshot, verify, fail, clear):
    path='/api/boards/'+quote(board,safe='')+'/custom-fields'
    # Start with the second write failing, proving an earlier definition rolls back.
    for stage in ['board','activity','definition']:
        fail(stage)
        try:
            before=snapshot()
            status,_,body=call('POST',path,dict(name='definition-fail',type='text',readOnly=True,adminOnly=True))
            after=snapshot()
            assert status==500,(stage,status,before==after,body)
            assert after==before,stage
        finally:clear()
        status,_,body=call('POST',path,dict(name='retry-'+stage,type='text'))
        assert status==200,(stage,status,body)
        verify(json.loads(body)['_id'],'retry-'+stage,'text',[0,0,0,0],uid)
    kinds=['text','number','currency','date','checkbox','dropdown','dropdownMultiSelect','stringtemplate']
    for kind in kinds:
        name='漢 "definition" '+kind
        data=dict(name=name,type=kind,showOnCard=True,automaticallyOnCard=False,
                  showLabelOnMiniCard='1',showSumAtTopOfList='false',authorId='spoofed-author')
        status,_,body=call('POST',path,data)
        assert status==200,(kind,status,body)
        identity=json.loads(body)['_id'];verify(identity,name,kind,[1,0,1,0],uid)
        listed=call('GET',path,None)
        assert listed[0]==200,listed
        assert dict(_id=identity,name=name,type=kind) in json.loads(listed[2]),listed
        response=call('GET',path+'/'+quote(identity,safe=''),None)
        assert response[0]==200 and json.loads(response[2])['type']==kind,response
    for data,name,flags in [
        (dict(name='default type'),'default type',[0,0,0,0]),
        (dict(name='legacy JSON',type='text',showoncard='1',automaticallyoncard='true',showlabelonminicard='0',showsumattopoflist='1'),'legacy JSON',[1,1,0,1]),
        (urlencode(dict(name='form 漢',type='text',showOnCard='true',showSumAtTopOfList='1')),'form 漢',[1,0,0,1]),
        (dict(name='equivalent aliases',showOnCard=True,showoncard='1'),'equivalent aliases',[1,0,0,0]),
    ]:
        status,_,body=call('POST',path,data)
        assert status==200,(data,status,body)
        verify(json.loads(body)['_id'],name,'text',flags,uid)
    for data,expected in [
        (dict(name='private flag',readOnly=True,adminOnly=True),(True,True)),
        (dict(name='false flags',readOnly=False,adminOnly=False),(False,False)),
        (dict(name='legacy flags',readonly='1',adminonly='true'),(True,True)),
        (urlencode(dict(name='form flags',readOnly='true',adminOnly='1')),(True,True)),
        (dict(name='equivalent flag aliases',readOnly=True,readonly='1',adminOnly=False,adminonly='0'),(True,False)),
    ]:
        status,_,body=call('POST',path,data);assert status==200,(data,status,body)
        identity=json.loads(body)['_id']
        verify(identity,'form flags' if isinstance(data,str) else data['name'],'text',[0,0,0,0,*map(int,expected)],uid)
        result=json.loads(call('GET',path+'/'+quote(identity,safe=''),None)[2])
        assert (result['readOnly'],result['adminOnly'])==expected,result
    for key in ['readOnly','adminOnly']:
        for bad in [None,2,[],{},'yes']:
            before=snapshot();response=call('POST',path,dict(name='Invalid flag',**{key:bad}))
            assert response[0]==400,(key,bad,response);assert snapshot()==before
        before=snapshot();response=call('POST',path,dict(name='Conflicting flag',**{key:True,key.lower():False}))
        assert response[0]==400,(key,response);assert snapshot()==before
    invalid=[{},dict(name=''),dict(name='  '),dict(name=True),dict(name='bad',type='unsupported'),
             dict(name='bad',type={}),dict(name='bad',type=None),dict(name='\0'),
             dict(name='bad',showOnCard='yes'),dict(name='bad',showOnCard=None),
             dict(name='bad',showOnCard=True,showoncard=False),
             b'{"name":"one","name":"two"}', 'name=one&name=two&type=text']
    for data in invalid:
        before=snapshot();status,_,body=call('POST',path,data)
        assert status==400,(data,status,body)
        assert snapshot()==before,data
    print('PASS: custom definition atomic creation/link/activity, post-write rollback at every stage, canonical/legacy flags, supported types, default type and authenticated attribution')


def run_native(call, db, board, uid):
    def snapshot():
        with sqlite3.connect(db) as con:
            return [con.execute('SELECT * FROM '+name+' ORDER BY 1,2').fetchall() for name in ['custom_fields','custom_field_boards','activities']]
    def verify(identity,name,kind,flags,actor):
        with sqlite3.connect(db) as con:
            row=con.execute('SELECT name,type,showOnCard,automaticallyOnCard,showLabelOnMiniCard,showSumAtTopOfList,readOnly,adminOnly FROM custom_fields WHERE id=?',(identity,)).fetchone()
            assert row==(name,kind,*(flags if len(flags)==6 else flags+[0,0])),row
            assert con.execute('SELECT boardId FROM custom_field_boards WHERE customFieldId=?',(identity,)).fetchall()==[(board,)]
            activities=con.execute("SELECT userId,boardId,data_json FROM activities WHERE activityType='createCustomField' AND json_extract(data_json,'$.customFieldId')=?",(identity,)).fetchall()
            assert len(activities)==1 and activities[0][:2]==(actor,board),activities
    def fail(stage):
        table=dict(board='custom_field_boards',activity='activities',definition='custom_fields',dropdown='custom_field_dropdown_items')[stage]
        with sqlite3.connect(db) as con:
            con.execute('CREATE TRIGGER def_fail AFTER INSERT ON '+table+(" WHEN NEW.id='second'" if stage=='dropdown' else '')+" BEGIN SELECT RAISE(FAIL,'test definition failure'); END")
    def clear():
        with sqlite3.connect(db) as con:con.execute('DROP TRIGGER def_fail')
    exercise(call,board,uid,snapshot,verify,fail,clear)
    def stored(identity,settings):
        with sqlite3.connect(db) as con:
            row=con.execute('SELECT currencyCode,stringtemplateFormat,stringtemplateSeparator,settings_json FROM custom_fields WHERE id=?',(identity,)).fetchone()
            keys=['currencyCode','stringtemplateFormat','stringtemplateSeparator']
            assert row[:3]==tuple(settings.get(key) for key in keys),row
            assert json.loads(row[3])=={key:value for key,value in settings.items() if key not in keys+['dropdownItems']},row
            assert con.execute('SELECT id,name FROM custom_field_dropdown_items WHERE customFieldId=? ORDER BY sort,id',(identity,)).fetchall()==[(item['_id'],item['name']) for item in settings.get('dropdownItems',[])]
            assert con.execute('SELECT dropdownItemsPresent FROM custom_fields WHERE id=?',(identity,)).fetchone()==(int('dropdownItems' in settings),)
    check_settings(call,board,snapshot,stored,fail,clear)
    from optdel import run_native as check_option_delete
    check_option_delete(call,db,board,uid)



def run_shared(call, client, db, board, uid):
    def snapshot():
        with sqlite3.connect(db) as con:
            names=con.execute("SELECT table_name FROM _ferretdb_collections WHERE name IN ('customFields','activities') ORDER BY name").fetchall()
            return [con.execute('SELECT _ferretdb_sjson FROM "'+name.replace('"','""')+'" ORDER BY json_extract(_ferretdb_sjson,\'$._id\')').fetchall() for name, in names]
    def verify(identity,name,kind,flags,actor):
        row=client.find('customFields',identity)[0]
        assert (row['name'],row['type'],row['boardIds'])==(name,kind,[board]),row
        assert row['settings']=={},row
        for key,value in zip(['showOnCard','automaticallyOnCard','showLabelOnMiniCard','showSumAtTopOfList','readOnly','adminOnly'],flags if len(flags)==6 else flags+[0,0]):
            assert row[key] is bool(value),(key,row)
        response=client.command({'find':'activities','filter':dict(activityType='createCustomField',customFieldId=identity)})
        activities=response['cursor']['firstBatch']
        assert len(activities)==1 and (activities[0]['userId'],activities[0]['boardId'])==(actor,board),activities
    def fail(stage):
        collection='activities' if stage=='activity' else 'customFields'
        event='UPDATE' if stage in ['board','dropdown'] else 'INSERT'
        with sqlite3.connect(db) as con:
            name=con.execute('SELECT table_name FROM _ferretdb_collections WHERE name=?',(collection,)).fetchone()[0]
            con.execute('CREATE TRIGGER def_fail AFTER '+event+' ON "'+name.replace('"','""')+'"'+(" WHEN json_array_length(NEW._ferretdb_sjson,'$.settings.dropdownItems')=2" if stage=='dropdown' else '')+' BEGIN SELECT RAISE(FAIL,\'test definition failure\'); END')
    def clear():
        with sqlite3.connect(db) as con:con.execute('DROP TRIGGER def_fail')
    exercise(call,board,uid,snapshot,verify,fail,clear)
    def stored(identity,settings):
        document=client.find('customFields',identity)[0]
        assert document['settings']==settings,(document,settings)
        assert all(key not in document for key in ['currencyCode','stringtemplateFormat','stringtemplateSeparator','settings_json']),document
    check_settings(call,board,snapshot,stored,fail,clear)
    from dropapi import run_shared as check_dropdown_guards
    check_dropdown_guards(call,db,snapshot,board)
    from optdel import run_shared as check_option_delete
    check_option_delete(call,client,db,board,uid)
