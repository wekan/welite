"""Policy batching and denial behavior under normal and checked Pascal builds."""
import json
import os
from pathlib import Path
import sqlite3
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
            result=run([dict(fields=fields),dict(field=fields[0]['_id'],write=True),dict(field=fields[1]['_id'],write=True)])
            assert json.loads(result[0])==expected and result[1:]==['1','0'],result
            # A policy SQL error masks the complete chunk instead of returning data.
            with sqlite3.connect(db) as con:con.execute('ALTER TABLE custom_fields RENAME COLUMN adminOnly TO broken')
            try:
                rows=json.loads(run([dict(fields=fields)])[0]);assert rows==[{**row,**({'value':None} if 'value' in row else {})} for row in fields]
            finally:
                with sqlite3.connect(db) as con:con.execute('ALTER TABLE custom_fields RENAME COLUMN broken TO adminOnly')
            print('PASS:',backend,mode,'132-field chunking, quoted Unicode IDs, preserved order/missing values and fail-closed SQL errors')
