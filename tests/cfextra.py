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
        def run(db, mode="all"):
            result=subprocess.run([str(out/'cfup'),str(db),mode],capture_output=True,text=True)
            assert result.returncode==0,result.stderr
            return result.stdout.strip()
        def legacy(db):
            with sqlite3.connect(db) as con:
                con.executescript("CREATE TABLE custom_fields(id TEXT PRIMARY KEY,name TEXT,currencyCode TEXT,legacy INTEGER); INSERT INTO custom_fields VALUES('field','漢','EUR',7); CREATE TABLE related(field TEXT REFERENCES custom_fields(id)); INSERT INTO related VALUES('field');")
        db=out/'old.db';legacy(db)
        with ThreadPoolExecutor(max_workers=4) as pool:assert list(pool.map(lambda _:run(db),range(4)))==['yes']*4
        assert run(db)=='yes'
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT * FROM custom_fields').fetchall()==[('field','漢','EUR',7,'{}',0,0)]
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
        # Policy upgrades preserve existing true flags and reject conflicting columns
        # before adding the other column. Denials leave the complete store unchanged.
        for label,columns,values in [
            ('textflag', 'readOnly TEXT NOT NULL DEFAULT 0', "'0'"),
            ('nullable', 'readOnly INTEGER DEFAULT 0', '0'),
            ('baddefault', 'adminOnly INTEGER NOT NULL DEFAULT 1', '1'),
            ('badvalue', 'readOnly INTEGER NOT NULL DEFAULT 0', '2'),
            ('badtype', 'adminOnly INTEGER NOT NULL DEFAULT 0', "'true'"),
        ]:
            path=out/(label+'.db')
            with sqlite3.connect(path) as con:
                con.executescript('CREATE TABLE custom_fields(id TEXT,'+columns+'); INSERT INTO custom_fields VALUES(\'keep\','+values+');')
                before='\n'.join(con.iterdump())
            assert run(path,'policy')=='no',label
            with sqlite3.connect(path) as con:assert '\n'.join(con.iterdump())==before,label
        partial=out/'partial.db'
        with sqlite3.connect(partial) as con:
            con.executescript("CREATE TABLE custom_fields(id TEXT,readOnly INTEGER NOT NULL DEFAULT 0); INSERT INTO custom_fields VALUES('keep',1)")
        assert run(partial,'policy')=='yes'
        with sqlite3.connect(partial) as con:
            assert con.execute('SELECT id,readOnly,adminOnly FROM custom_fields').fetchall()==[('keep',1,0)]
            for field in ['readOnly','adminOnly']:
                con.execute('UPDATE custom_fields SET '+field+'=1');con.commit()
            try:con.execute('UPDATE custom_fields SET adminOnly=2')
            except sqlite3.IntegrityError:con.rollback()
            else:raise AssertionError('Added policy column lacks boolean constraint')
        assert run(partial,'policy')=='yes'
        foreign=out/'foreign.db';legacy(foreign)
        with sqlite3.connect(foreign) as con:con.execute('CREATE TABLE _ferretdb_collections(name TEXT)');con.commit();before='\n'.join(con.iterdump())
        assert run(foreign)=='no'
        assert run(foreign,'policy')=='no'
        with sqlite3.connect(foreign) as con:assert '\n'.join(con.iterdump())==before
        fresh=out/'fresh.db'
        with sqlite3.connect(fresh) as con:con.executescript((root/'src/schema.sql').read_text())
        assert run(fresh)=='yes'
        assert run(out/'minimal.db')=='yes'
        print('PASS:',backend,'fresh/additive concurrent settings/policy upgrade, preserved legacy rows/relations, JSON ownership checks, incompatible schema/data and foreign-store refusal')
