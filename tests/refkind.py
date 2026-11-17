"""Typed reference identity, explicit repairs and cascade isolation on real roots."""
import json
from wire import ObjectId,Regex,DateMs,encode

def run(sql,client):
    def q(value):return "'"+value.replace("'","''")+"'"
    oid=ObjectId(bytes.fromhex('00112233445566778899aabb'));collision=oid.hex()
    owner='typed-owner';cascade='ffeeddccbbaa998877665544'
    ids={'boards':[oid,owner,cascade],'lists':['typed-parent-probe','typed-legacy','typed-bad-seed','typed-repaired-copy','typed-real','typed-regex','typed-oid']}
    def insert(collection,record):assert client.command({'insert':collection,'documents':[record]})['n']==1
    try:
        insert('boards',dict(_id=oid,title='ObjectId parent',slug='typed-objectid',createdAt=DateMs(0)))
        status=sql("INSERT INTO lists(id,boardId,title,createdAt) VALUES('typed-parent-probe',"+q(collision)+",'Probe','1970-01-01T00:00:00.000Z');",'exec')
        assert status=='error','A nonstring parent ID authorized a string reference'
        assert client.find('lists','typed-parent-probe')==[]
        insert('boards',dict(_id=owner,title='Typed owner',slug=owner,createdAt=DateMs(0)))
        insert('lists',dict(_id='typed-legacy',boardId=Regex(owner,''),title='Legacy',createdAt=DateMs(0),unknown=DateMs(-7)))
        physical=dict(sql('SELECT name,table_name FROM _ferretdb_collections;'))['lists']
        seed=sql('SELECT json(_ferretdb_sjson) FROM '+q(physical)+" WHERE json_extract(_ferretdb_sjson,'$._id')='typed-legacy';")[0][0]
        before=encode(client.find('lists','typed-legacy')[0])
        assert sql("INSERT INTO lists(id,_wl_source) VALUES('typed-bad-seed',"+q(seed)+');','exec')=='error','A nonstring source reference acquired string authority'
        assert encode(client.find('lists','typed-legacy')[0])==before and client.find('lists','typed-bad-seed')==[]
        assert sql("INSERT INTO lists(id,boardId,_wl_source) VALUES('typed-repaired-copy',"+q(owner)+','+q(seed)+');','exec')=='ok'
        copy=client.find('lists','typed-repaired-copy')[0]
        assert type(copy['boardId']) is str and copy['boardId']==owner and isinstance(copy['unknown'],DateMs)
        assert encode(client.find('lists','typed-legacy')[0])==before
        assert sql("UPDATE lists SET boardId="+q(owner)+" WHERE id='typed-legacy';",'exec')=='ok'
        repaired=client.find('lists','typed-legacy')[0]
        assert type(repaired['boardId']) is str and repaired['boardId']==owner and repaired['unknown']==DateMs(-7)
        insert('boards',dict(_id=cascade,title='Cascade parent',slug='typed-cascade',createdAt=DateMs(0)))
        for identity,value in [('typed-real',cascade),('typed-regex',Regex(cascade,'')),('typed-oid',ObjectId(bytes.fromhex(cascade)))]:
            insert('lists',dict(_id=identity,boardId=value,title=identity,createdAt=DateMs(0),unknown=DateMs(-7)))
        untouched={key:encode(client.find('lists',key)[0]) for key in ['typed-regex','typed-oid']}
        # Custom view-trigger ordering survives an adapter reinstall: custom
        # triggers still observe the row before the owned delete trigger runs.
        assert sql("CREATE TABLE typed_audit(value TEXT); CREATE TRIGGER typed_delete_audit INSTEAD OF DELETE ON lists WHEN OLD.id='typed-real' BEGIN INSERT INTO typed_audit SELECT CASE WHEN EXISTS(SELECT 1 FROM lists WHERE id=OLD.id) THEN 'before' ELSE 'after' END; END;",'exec')=='ok'
        assert sql(mode='install')=='ok'
        assert sql('DELETE FROM boards WHERE id='+q(cascade)+';','exec')=='ok'
        assert client.find('boards',cascade)==[] and client.find('lists','typed-real')==[]
        assert sql('SELECT value FROM typed_audit;')==[['before']]
        assert all(encode(client.find('lists',key)[0])==value for key,value in untouched.items()),'Cascade removed or changed a BSON lookalike'
        print('PASS: typed parent/source identity, same-text reference repairs, isolated Regex/ObjectId cascades and restored custom delete order')
    finally:
        sql('DROP TRIGGER IF EXISTS typed_delete_audit; DROP TABLE IF EXISTS typed_audit;','exec')
        for collection,values in reversed(list(ids.items())):
            client.command({'delete':collection,'deletes':[dict(q=dict(_id=value),limit=1) for value in values]})
