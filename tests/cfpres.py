"""Native optional dropdown presence survives empty arrays and additive upgrades."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
@contextmanager
def connect(path):
    con=sqlite3.connect(path)
    try:
        with con:yield con
    finally:con.close()
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wlcfpres-',dir=os.environ['TMPDIR']) as directory:
    for backend,extra in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
            out=Path(directory)/(backend+mode);out.mkdir();db=out/'data.db'
            build=subprocess.run([os.environ.get('FPC','fpc'),'-B',*extra,*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/cfpres.lpr')],capture_output=True,text=True)
            assert build.returncode==0,build.stdout+build.stderr
            def run(arg):
                result=subprocess.run([str(out/'cfpres'),str(db),arg],capture_output=True,text=True,timeout=20)
                assert result.returncode==0,(result.stdout,result.stderr)
                return result.stdout.strip()
            def refuse():
                with connect(db) as con:before=list(con.iterdump())
                assert run('upgrade')=='no'
                with connect(db) as con:assert list(con.iterdump())==before
            def sql(text):
                with connect(db) as con:con.executescript(text)
            sql((root/'src/schema.sql').read_text())
            sql("INSERT INTO custom_fields(id,name,type,modifiedAt) VALUES('missing','Missing','dropdown','now'),('empty','Empty','dropdown','now'),('items','Items','dropdown','now'); UPDATE custom_fields SET dropdownItemsPresent=1 WHERE id='empty'; INSERT INTO custom_field_dropdown_items VALUES('items','z','First',0),('items','a','Second',1);")
            assert run('upgrade')=='yes'
            assert json.loads(run('missing'))['settings']=={}
            assert json.loads(run('empty'))['settings']==dict(dropdownItems=[])
            expected=[dict(_id='z',name='First'),dict(_id='a',name='Second')]
            assert json.loads(run('items'))['settings']==dict(dropdownItems=expected)
            sql("UPDATE custom_fields SET dropdownItemsPresent=1 WHERE id='items'; DELETE FROM custom_field_dropdown_items WHERE customFieldId='items';")
            assert json.loads(run('items'))['settings']==dict(dropdownItems=[])
            # A legacy nonempty array needs no synthetic marker; old missing values stay absent.
            sql("ALTER TABLE custom_fields DROP COLUMN dropdownItemsPresent; INSERT INTO custom_field_dropdown_items VALUES('items','one','Kept',0);")
            workers=[subprocess.Popen([str(out/'cfpres'),str(db),'upgrade'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True) for _ in range(2)]
            for proc in workers:
                stdout,stderr=proc.communicate(timeout=20);assert proc.returncode==0 and stdout.strip()=='yes',(stdout,stderr)
            assert json.loads(run('missing'))['settings']=={}
            assert json.loads(run('items'))['settings']==dict(dropdownItems=[dict(_id='one',name='Kept')])
            with connect(db) as con:
                assert con.execute('SELECT dropdownItemsPresent FROM custom_fields').fetchall()==[(0,),(0,),(0,)]
                for value in [None,2,'bad']:
                    try:con.execute('UPDATE custom_fields SET dropdownItemsPresent=?',(value,))
                    except sqlite3.IntegrityError:pass
                    else:raise AssertionError(value)
                con.execute('PRAGMA ignore_check_constraints=ON');con.execute('UPDATE custom_fields SET dropdownItemsPresent=2')
            refuse()
            bad=subprocess.run([str(out/'cfpres'),str(db),'empty'],capture_output=True,text=True)
            assert bad.returncode!=0 and 'Invalid dropdown presence' in bad.stderr
            sql('UPDATE custom_fields SET dropdownItemsPresent=0; CREATE TABLE _ferretdb_collections(name TEXT);')
            refuse()
            sql('DROP TABLE _ferretdb_collections; ALTER TABLE custom_fields DROP COLUMN dropdownItemsPresent; ALTER TABLE custom_fields ADD COLUMN dropdownItemsPresent TEXT;')
            refuse()
            db.unlink()
            sql('CREATE VIEW custom_fields AS SELECT 1 AS id;')
            refuse()
            db.unlink();sql('CREATE TABLE unrelated(value TEXT);')
            assert run('upgrade')=='yes'
            assert not list(out.glob('*.sql'))
            print('PASS:',backend,mode,'native missing/empty/ordered dropdown reads, retained explicit emptiness, additive/concurrent upgrades and incompatible/shared refusal')
