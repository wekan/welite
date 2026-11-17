"""Scoped atomic dropdown option deletion retains assigned values and typed siblings."""
from contextlib import contextmanager
import json
import sqlite3
from urllib.parse import quote
from wire import DateMs,Long,Regex,encode

@contextmanager
def connect(db):
    con=sqlite3.connect(db)
    try:
        with con:yield con
    finally:con.close()

def exercise(call,board,snapshot,stored,assign,install,clear):
    base='/api/boards/'+quote(board,safe='')+'/custom-fields'
    options=[dict(_id="first '漢+%2F",name='First'),dict(_id='second',name='Second'),dict(_id='last',name='Last')]
    status,_,body=call('POST',base,dict(name='Delete options',type='dropdown',settings=dict(dropdownItems=options,future=dict(keep=True))))
    assert status==200,(status,body)
    identity=json.loads(body)['_id'];assign(identity)
    def path(item):return base+'/'+quote(identity,safe='')+'/dropdown-items/'+quote(item,safe='')
    def remove(item):return call('DELETE',path(item),None)
    before=snapshot()
    assert remove('missing')[0]==404 and snapshot()==before
    assert call('DELETE',base+'/missing/dropdown-items/second',None)[0]==404 and snapshot()==before
    assert call('DELETE',path('second').replace('/second','/%GG'),None)[0]==400 and snapshot()==before
    for kind in ['fail','revoke']:
        install(identity,kind)
        try:
            before=snapshot();status,_,body=remove(options[0]['_id'])
            assert status==500,(kind,status,body)
            assert snapshot()==before,kind
        finally:clear()
    for index,option in enumerate(options):
        status,_,body=remove(option['_id']);assert status==200,(status,body)
        assert json.loads(body)==dict(_id=identity)
        stored(identity,options[index+1:])
        status,_,body=call('GET',base+'/'+quote(identity,safe=''),None)
        assert status==200 and [{key:item[key] for key in ['_id','name']} for item in json.loads(body)['settings']['dropdownItems']]==options[index+1:],body
        before=snapshot();assert remove(option['_id'])[0]==404 and snapshot()==before
    print('PASS: dropdown deletion exact Unicode/plus/percent IDs, missing/malformed refusal, retained empty arrays/assigned values, typed siblings and transaction-time failure/revocation rollback')

def run_native(call,db,board,uid):
    card=None;value_before=None
    def snapshot():
        with connect(db) as con:return list(con.iterdump())
    def assign(identity):
        nonlocal card,value_before
        with connect(db) as con:
            # Legacy populated definitions predate the explicit-presence marker.
            con.execute('UPDATE custom_fields SET dropdownItemsPresent=0 WHERE id=?',(identity,))
            card=con.execute('SELECT id FROM cards WHERE boardId=? ORDER BY id LIMIT 1',(board,)).fetchone()[0]
            con.execute('INSERT INTO card_custom_field_values(cardId,customFieldId,value) VALUES(?,?,?)',(card,identity,'second'))
            value_before=con.execute('SELECT * FROM card_custom_field_values WHERE cardId=? AND customFieldId=?',(card,identity)).fetchall()
    def stored(identity,options):
        with connect(db) as con:
            assert con.execute('SELECT id,name FROM custom_field_dropdown_items WHERE customFieldId=? ORDER BY sort,id',(identity,)).fetchall()==[(item['_id'],item['name']) for item in options]
            assert con.execute('SELECT dropdownItemsPresent FROM custom_fields WHERE id=?',(identity,)).fetchone()==(1,)
            assert con.execute('SELECT * FROM card_custom_field_values WHERE cardId=? AND customFieldId=?',(card,identity)).fetchall()==value_before
    def install(identity,kind):
        with connect(db) as con:
            body="SELECT RAISE(FAIL,'option failure');" if kind=='fail' else "UPDATE users SET loginDisabled=1 WHERE id='"+uid.replace("'","''")+"';"
            con.execute("CREATE TRIGGER opt_fail AFTER DELETE ON custom_field_dropdown_items WHEN OLD.customFieldId='"+identity+"' BEGIN "+body+' END')
    def clear():
        with connect(db) as con:con.execute('DROP TRIGGER opt_fail')
    exercise(call,board,snapshot,stored,assign,install,clear)

def run_shared(call,client,db,board,uid):
    card=None;card_before=None;original=None
    def snapshot():
        with connect(db) as con:
            names=con.execute('SELECT table_name FROM _ferretdb_collections ORDER BY name').fetchall()
            return [con.execute('SELECT _ferretdb_sjson FROM "'+name.replace('"','""')+'" ORDER BY json_extract(_ferretdb_sjson,\'$._id\')').fetchall() for name, in names]
    def assign(identity):
        nonlocal card,card_before,original
        doc=client.find('customFields',identity)[0]
        # Unknown typed data on the definition and surviving option must remain exact.
        items=doc['settings']['dropdownItems'];items[-1]['extra']=Long(9007199254740993)
        assert client.command({'update':'customFields','updates':[dict(q=dict(_id=identity),u={'$set':{'settings.dropdownItems':items,'unknown':DateMs(-7)}})]})['n']==1
        original=client.find('customFields',identity)[0]
        card=client.command({'find':'cards','filter':dict(boardId=board),'limit':1})['cursor']['firstBatch'][0]['_id']
        assert client.command({'update':'cards','updates':[dict(q=dict(_id=card),u={'$push':dict(customFields=dict(_id=identity,value='second'))})]})['n']==1
        card_before=encode(client.find('cards',card)[0])
    def stored(identity,options):
        doc=client.find('customFields',identity)[0];expected=dict(original)
        expected['modifiedAt']=doc['modifiedAt'];expected['settings']=dict(original['settings'])
        ids={item['_id'] for item in options}
        expected['settings']['dropdownItems']=[item for item in original['settings']['dropdownItems'] if item['_id'] in ids]
        assert encode(doc)==encode(expected),(doc,expected)
        assert encode(client.find('cards',card)[0])==card_before
    def install(identity,kind):
        with connect(db) as con:
            table=con.execute("SELECT table_name FROM _wl_models WHERE name='custom_fields'").fetchone()[0]
            body="SELECT RAISE(FAIL,'option failure');" if kind=='fail' else "UPDATE users SET loginDisabled=1 WHERE id='"+uid.replace("'","''")+"';"
            con.execute('CREATE TRIGGER opt_fail AFTER UPDATE ON "'+table.replace('"','""')+'" WHEN json_extract(NEW._ferretdb_sjson,\'$._id\')=\''+identity+"' AND json_array_length(NEW._ferretdb_sjson,'$.settings.dropdownItems')=2 AND json_array_length(OLD._ferretdb_sjson,'$.settings.dropdownItems')=3 BEGIN "+body+' END')
    def clear():
        with connect(db) as con:con.execute('DROP TRIGGER opt_fail')
    exercise(call,board,snapshot,stored,assign,install,clear)
    identity='option-typed-scope';base='/api/boards/'+quote(board,safe='')+'/custom-fields/'+identity+'/dropdown-items/target'
    doc=dict(_id=identity,name='Typed options',type='dropdown',boardIds=[board],modifiedAt=DateMs(0),settings=dict(dropdownItems=[]))
    assert client.command({'insert':'customFields','documents':[doc]})['n']==1
    for items,boards,expected in [
        ([dict(_id=Regex('target',''),name='Wrong type')],[board],404),
        ([dict(_id='target',name='String'),dict(_id=Regex('target',''),name='Shadow')],[board],500),
        ([dict(_id='target',name='Wrong board')],[Regex(board,'')],404),
        ([dict(_id='target',name='Foreign')],['unrelated-board'],404),
    ]:
        assert client.command({'update':'customFields','updates':[dict(q=dict(_id=identity),u={'$set':dict(settings=dict(dropdownItems=items),boardIds=boards)})]})['n']==1
        before=snapshot();status,_,body=call('DELETE',base,None)
        assert status==expected,(expected,status,body)
        assert snapshot()==before
    print('PASS: dropdown deletion excludes typed key/board lookalikes and refuses mixed duplicate shadows without mutation')

