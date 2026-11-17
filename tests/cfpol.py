"""Policy batching and denial behavior under normal and checked Pascal builds."""
import json
import os
from pathlib import Path
import sqlite3
import shlex
import shutil
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wlcfpol-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory);db=tmp/'policy.db';uid="user ' 漢";board="board ' 漢";card="card ' 漢"
    fields=[];expected=[]
    with sqlite3.connect(db) as con:
        con.executescript((root/'src/schema.sql').read_text())
        con.execute("INSERT INTO users(id,username,createdAt,modifiedAt) VALUES(?,?,'now','now')",(uid,uid))
        con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES(?,?,?,'now')",(board,board,board))
        con.execute('INSERT INTO board_members(boardId,userId,isAdmin) VALUES(?,?,0)',(board,uid))
        con.execute("INSERT INTO cards(id,title,boardId,listId,userId,createdAt,modifiedAt,dateLastActivity) VALUES(?,?,?,'list',?,'now','now','now')",(card,card,board,uid))
        for index in range(130):
            name="field ' 漢 "+str(index);private=index%2==1
            row=dict(_id=name)
            if index%10:row['value']=str(index)
            fields.append(row);expected.append(dict(row,**({'value':None} if private and 'value' in row else {})))
            con.execute("INSERT INTO custom_fields(id,name,type,adminOnly,modifiedAt) VALUES(?,?,'text',?,'now')",(name,name,int(private)))
            con.execute('INSERT INTO custom_field_boards VALUES(?,?)',(name,board))
        fields.extend([dict(_id='missing',value='private'),dict(_id='missing-empty')]);expected.extend([dict(_id='missing',value=None),dict(_id='missing-empty')])
    for backend,options in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
            out=tmp/(backend+mode);out.mkdir()
            built=subprocess.run([os.environ.get('FPC','fpc'),'-B',*options,*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/cfpol.lpr')],capture_output=True,text=True)
            assert built.returncode==0,built.stdout+built.stderr
            def run(cases):
                result=subprocess.run([str(out/'cfpol'),str(db),uid,board,card],input='\n'.join(json.dumps(case) for case in cases)+'\n',capture_output=True,text=True)
                assert result.returncode==0,result.stderr
                return result.stdout.splitlines()
            result=run([dict(fields=fields),dict(field=fields[0]['_id'],write=True),dict(field=fields[1]['_id'],write=True),dict(definition=True),dict(definition=True,admin=True),dict(definition=True,field=fields[0]['_id']),dict(definition=True,field=fields[1]['_id'])])
            assert json.loads(result[0])==expected and result[1:]==['1','0','1','0','1','0'],result
            with sqlite3.connect(db) as con:con.execute('INSERT INTO custom_field_boards VALUES(?,?)',(fields[0]['_id'],'another-board'))
            try:assert run([dict(definition=True,field=fields[0]['_id'])])==['0']
            finally:
                with sqlite3.connect(db) as con:con.execute('DELETE FROM custom_field_boards WHERE boardId=?',('another-board',))
            assert run([dict(clone=True)])==['1'],'Unassigned private definitions do not write a cloned value'
            assert run([dict(export=True)])==['0'],'Unassigned private definition must gate the whole board'
            with sqlite3.connect(db) as con:con.execute('UPDATE custom_fields SET adminOnly=0')
            assert run([dict(export=True)])==['1']
            if backend=='cli' and mode=='normal':
                trace=tmp/'sqlcalls';wrapper=tmp/'tracebin';wrapper.mkdir()
                cli=shutil.which('sqlite3');assert cli
                script=wrapper/'sqlite3'
                script.write_text('#!/bin/sh\nprintf x >> '+shlex.quote(str(trace))+'\nexec '+shlex.quote(cli)+' "$@"\n')
                script.chmod(0o700)
                previous=os.environ['PATH'];os.environ['PATH']=str(wrapper)+os.pathsep+previous
                try:
                    trace.write_text('');assert run([dict(export=True)])==['1'];empty_calls=trace.stat().st_size
                    assert empty_calls>0,'CLI trace wrapper was not invoked'
                    with sqlite3.connect(db) as con:
                        con.executemany('INSERT INTO card_custom_field_values VALUES(?,?,?)',[(card,row['_id'],'readable') for row in fields[:130]])
                    trace.write_text('');assert run([dict(export=True)])==['1'];full_calls=trace.stat().st_size
                    assert full_calls==empty_calls,(empty_calls,full_calls,'Per-value CLI subprocess regression')
                finally:
                    os.environ['PATH']=previous
                    with sqlite3.connect(db) as con:con.execute('DELETE FROM card_custom_field_values')
            # Correlate both identifiers: a later card must not borrow the first
            # card's readable definition, and other boards do not gate this one.
            second=card+' second';outside=card+' outside'
            with sqlite3.connect(db) as con:
                for identity,owner in [(second,board),(outside,'other-board')]:
                    con.execute("INSERT INTO cards(id,title,boardId,listId,userId,createdAt,modifiedAt,dateLastActivity) VALUES(?,?,?,'list',?,'now','now','now')",(identity,identity,owner,uid))
                con.execute('INSERT INTO card_custom_field_values VALUES(?,?,?)',(second,fields[0]['_id'],'readable second card'))
                con.execute('INSERT INTO card_custom_field_values VALUES(?,?,?)',(outside,'orphan','outside secret'))
            assert run([dict(export=True)])==['1'],'Ignore values outside this board'
            with sqlite3.connect(db) as con:con.execute('INSERT INTO card_custom_field_values VALUES(?,?,?)',(second,'orphan','second secret'))
            assert run([dict(export=True)])==['0'],'Check every card and field correlation'
            with sqlite3.connect(db) as con:con.execute('UPDATE card_custom_field_values SET value=NULL WHERE cardId=? AND customFieldId=?',(second,'orphan'))
            assert run([dict(export=True)])==['1'],'Null orphan on another card stays exportable'
            with sqlite3.connect(db) as con:
                con.execute('DELETE FROM card_custom_field_values WHERE cardId IN (?,?)',(second,outside))
                con.execute('DELETE FROM cards WHERE id IN (?,?)',(second,outside))
            with sqlite3.connect(db) as con:con.execute('INSERT INTO card_custom_field_values VALUES(?,?,?)',(card,'orphan','secret'))
            assert run([dict(export=True)])==['0'],'Unknown nonnull value must gate administrators too'
            with sqlite3.connect(db) as con:con.execute('UPDATE board_members SET isAdmin=1')
            assert run([dict(export=True)])==['0']
            assert run([dict(clone=True)])==['0'],'Non-null orphan values cannot be cloned even by admins'
            with sqlite3.connect(db) as con:con.execute('UPDATE card_custom_field_values SET value=NULL')
            assert run([dict(export=True)])==['1'],'Unknown null values do not contain private prose'
            assert run([dict(clone=True)])==['1']
            assert run([dict(export=True,rows=[dict(cardId=card,customFieldId='orphan',value='captured private value')])])==['0'],'Check captured rows even after the stored private value was cleared'
            assert run([dict(export=True,rows=[dict(cardId=card,customFieldId=fields[0]['_id'],value='readable')])])==['1']
            with sqlite3.connect(db) as con:
                con.execute('DELETE FROM card_custom_field_values')
                con.execute('UPDATE custom_fields SET adminOnly=CAST(substr(id,instr(id,\'漢 \')+2) AS INTEGER)%2')
                con.execute('UPDATE board_members SET isAdmin=0')
            with sqlite3.connect(db) as con:
                con.execute('UPDATE custom_fields SET readOnly=1 WHERE id=?',(fields[0]['_id'],))
                con.execute('INSERT INTO card_custom_field_values VALUES(?,?,?)',(card,fields[0]['_id'],'readonly value'))
            assert run([dict(clone=True)])==['0']
            with sqlite3.connect(db) as con:con.execute('UPDATE users SET isAdmin=1')
            assert run([dict(clone=True)])==['0'],'Global admin is not board admin for read-only copies'
            with sqlite3.connect(db) as con:con.execute('UPDATE board_members SET isAdmin=1')
            assert run([dict(clone=True)])==['1']
            with sqlite3.connect(db) as con:
                con.execute('UPDATE users SET isAdmin=0');con.execute('UPDATE board_members SET isAdmin=0')
                con.execute('DELETE FROM card_custom_field_values');con.execute('UPDATE custom_fields SET readOnly=0')
            # A policy SQL error masks the complete chunk instead of returning data.
            with sqlite3.connect(db) as con:con.execute('ALTER TABLE custom_fields RENAME COLUMN adminOnly TO broken')
            try:
                rows=json.loads(run([dict(fields=fields)])[0]);assert rows==[{**row,**({'value':None} if 'value' in row else {})} for row in fields]
            finally:
                with sqlite3.connect(db) as con:con.execute('ALTER TABLE custom_fields RENAME COLUMN broken TO adminOnly')
            print('PASS:',backend,mode,'132-field chunking, quoted Unicode IDs, preserved order/missing values and fail-closed SQL errors')
