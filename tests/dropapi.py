"""Definition dropdown initialization rejects stale bindings and ambiguous parents."""
import sqlite3
from urllib.parse import quote


def run_shared(call,db,snapshot,board):
    with sqlite3.connect(db) as con:
        table=con.execute("SELECT table_name FROM _wl_models WHERE name='custom_fields'").fetchone()[0]
    quoted='"'+table.replace('"','""')+'"'
    attacks=["UPDATE _wl_models SET version=version+1 WHERE name='custom_field_dropdown_items';",
             'INSERT INTO '+quoted+'(_ferretdb_sjson) VALUES(NEW._ferretdb_sjson);']
    for attack in attacks:
        with sqlite3.connect(db) as con:
            versions=con.execute('SELECT name,version FROM _wl_models ORDER BY name').fetchall()
            con.execute('CREATE TRIGGER drop_bad AFTER INSERT ON '+quoted+' BEGIN '+attack+' END')
        try:
            before=snapshot()
            status,_,body=call('POST','/api/boards/'+quote(board,safe='')+'/custom-fields',dict(name='Guard rollback',type='dropdown',settings=dict(dropdownItems=[])))
            assert status==500,(status,body)
            assert snapshot()==before
            with sqlite3.connect(db) as con:assert con.execute('SELECT name,version FROM _wl_models ORDER BY name').fetchall()==versions
        finally:
            with sqlite3.connect(db) as con:con.execute('DROP TRIGGER drop_bad')
    print('PASS: shared dropdown creation rolls back relation-binding changes and duplicate parent injection')
