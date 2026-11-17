"""Additive native remainder upgrade and its JSON/ownership invariants."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wlcfup-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=tmp/backend;out.mkdir()
        built=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/cfup.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        def run(db):
            result=subprocess.run([str(out/'cfup'),str(db)],capture_output=True,text=True)
            assert result.returncode==0,result.stderr
            return result.stdout.strip()
        def legacy(db):
            with sqlite3.connect(db) as con:
                con.executescript("CREATE TABLE custom_fields(id TEXT PRIMARY KEY,name TEXT,currencyCode TEXT,legacy INTEGER); INSERT INTO custom_fields VALUES('field','漢','EUR',7); CREATE TABLE related(field TEXT REFERENCES custom_fields(id)); INSERT INTO related VALUES('field');")
        db=out/'old.db';legacy(db)
        with ThreadPoolExecutor(max_workers=4) as pool:assert list(pool.map(lambda _:run(db),range(4)))==['yes']*4
        assert run(db)=='yes'
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT * FROM custom_fields').fetchall()==[('field','漢','EUR',7,'{}')]
            assert con.execute('SELECT * FROM related').fetchall()==[('field',)]
            for value in ['bad','[]','null','{"currencyCode":"USD"}','{"dropdownItems":[]}','{"stringtemplateFormat":"x"}']:
                try:con.execute('UPDATE custom_fields SET settings_json=?',(value,))
                except sqlite3.IntegrityError:con.rollback()
                else:raise AssertionError(value)
            text=json.dumps(dict(jiraTimeField='remaining',future=dict(flag=True)))
            con.execute('UPDATE custom_fields SET settings_json=?',(text,));con.commit()
        assert run(db)=='yes'
        with sqlite3.connect(db) as con:assert con.execute('SELECT settings_json FROM custom_fields').fetchone()[0]==text
        for label,ddl in [('view','CREATE VIEW custom_fields AS SELECT 1 AS id'),
                          ('conflict',"CREATE TABLE custom_fields(settings_json INTEGER)"),
                          ('invalid',"CREATE TABLE custom_fields(settings_json TEXT NOT NULL DEFAULT '{}'); INSERT INTO custom_fields VALUES('[]')"),
                          ('shadow',"CREATE TABLE custom_fields(settings_json TEXT NOT NULL DEFAULT '{}'); INSERT INTO custom_fields VALUES('{\"currencyCode\":\"EUR\"}')")]:
            path=out/(label+'.db')
            with sqlite3.connect(path) as con:con.executescript(ddl);before='\n'.join(con.iterdump())
            assert run(path)=='no',label
            with sqlite3.connect(path) as con:assert '\n'.join(con.iterdump())==before,label
        foreign=out/'foreign.db';legacy(foreign)
        with sqlite3.connect(foreign) as con:con.execute('CREATE TABLE _ferretdb_collections(name TEXT)');con.commit();before='\n'.join(con.iterdump())
        assert run(foreign)=='no'
        with sqlite3.connect(foreign) as con:assert '\n'.join(con.iterdump())==before
        fresh=out/'fresh.db'
        with sqlite3.connect(fresh) as con:con.executescript((root/'src/schema.sql').read_text())
        assert run(fresh)=='yes'
        assert run(out/'minimal.db')=='yes'
        print('PASS:',backend,'fresh/additive concurrent settings upgrade, preserved legacy rows/relations, JSON ownership checks, incompatible schema/data and foreign-store refusal')
