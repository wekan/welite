"""Recursive payload policy: encoded JSON, BSON source, activity aliases and hashes."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
plain=[dict(extra_json=json.dumps(dict(_wl_source='literal source text',other_json='ordinary text'))),dict(data_json='{"timestamp":18446744073709551615}'),dict(note='ordinary value',value='public'),dict(customFields=[]),dict(customFields={}),dict(customFields=None),
       dict(customFields=[dict(_id='f',value='readable')]),dict(customFields=[dict(_id='missing',value=None)]),
       dict(customFieldId='f',oldValue='old',newValue='new',customFieldValue='alias'),
       dict(field='customFields',value=[dict(_id='f',value=True)]),dict(integrityHash=None,previousHash=None)]
hidden=[dict(customFields=[dict(_id='p',value='secret')]),dict(customFields=[dict(_id='missing',value='orphan')]),
        dict(customFields=[dict(_id='missing',value=None,unknown='private metadata')]),dict(customFields=[dict(value='no identity')]),
        dict(field='customFields',value=[dict(_id='p',value='secret')]),dict(integrityHash='guessing oracle'),dict(previousHash='guessing oracle'),
        dict(customFields=[dict(_id='f',value='readable'),dict(_id='F',value='case-sensitive private')])]
hidden += [dict(customFieldId=identity,**{key:'secret'}) for identity in ['p','missing'] for key in ['value','oldValue','newValue','customFieldValue']]
plain += [dict(field='customFields',oldValue=[dict(_id='f',value='old')],newValue=[dict(_id='f',value='new')],customFieldValue=[dict(_id='f',value='alias')])]
hidden += [dict(field='customFields',**{key:[dict(_id='p',value='batch secret')]}) for key in ['oldValue','newValue','customFieldValue']]
hidden += [dict(boardId='foreign',customFieldId='f',value='wrong board')]
invalid=[dict(data_json='bad'),dict(data_json='{"duplicate":1,"duplicate":2}'),dict(data_json='{"bad":1e999}'),
         dict(_wl_source='{}'),dict(customFields='malformed'),dict(boardId=7,customFieldId='f',value='invalid scope')]
with tempfile.TemporaryDirectory(prefix='wlcfscan-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory);db=tmp/'policy.db'
    with sqlite3.connect(db) as con:
        con.executescript((root/'src/schema.sql').read_text())
        con.execute("INSERT INTO users(id,username,createdAt,modifiedAt) VALUES('u','user','now','now')")
        for board in ['board','foreign']:
            con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES(?,?,?,'now')",(board,board,board))
            con.execute("INSERT INTO board_members(boardId,userId,isAdmin) VALUES(?,'u',0)",(board,))
        collision='0123456789abcdef01234567'
        con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES(?,?,?,'now')",(collision,collision,collision))
        con.execute("INSERT INTO board_members(boardId,userId,isAdmin) VALUES(?,'u',1)",(collision,))
        for identity,private in [('f',0),('p',1),('F',1),(collision,0)]:
            con.execute("INSERT INTO custom_fields(id,name,type,adminOnly,modifiedAt) VALUES(?,?,'text',?,'now')",(identity,identity,private))
            con.execute('INSERT INTO custom_field_boards VALUES(?,?)',(identity,'board'))
    cases=[]
    for payload,expected in [(value,1) for value in plain]+[(value,0) for value in hidden]:
        cases += [(dict(payload=payload),expected),(dict(payload=dict(nested=[payload])),expected),
                  (dict(payload=dict(data_json=json.dumps(payload))),expected),
                  (dict(payload=dict(extra_json=json.dumps(dict(nested=[payload])))),expected),
                  (dict(payload=payload,typed=True),expected)]
    cases += [(dict(payload=payload),0) for payload in invalid]
    cases += [(dict(payload=dict(_wl_source=json.dumps({'$s':{}}),extra_json=json.dumps(hidden[0]))),0)]
    collision='0123456789abcdef01234567'
    cases += [
        (dict(payload=dict(customFieldId=collision,value='typed orphan'),typed=True,hints=dict(customFieldId='objectId')),0),
        (dict(payload=dict(boardId=collision,integrityHash='scope oracle'),typed=True,hints=dict(boardId='objectId')),0),
        (dict(payload=dict(boardId=collision,note='ordinary opaque value'),typed=True,hints=dict(boardId='objectId')),1),
        (dict(payload=dict(boardId=0,note='ordinary opaque date'),typed=True,hints=dict(boardId='date')),1),
        (dict(payload=dict(boardId=0,customFieldId='f',value='wrong date scope'),typed=True,hints=dict(boardId='date')),0),
        (dict(payload=dict(boardId=0,customFieldId='f',value='JSON falsey scope')),1),
    ]

    for backend,options in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
            out=tmp/(backend+mode);out.mkdir()
            built=subprocess.run([os.environ.get('FPC','fpc'),'-B',*options,*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/cfscan.lpr')],capture_output=True,text=True)
            assert built.returncode==0,built.stdout+built.stderr
            def run(items):
                result=subprocess.run([str(out/'cfscan'),str(db)],input='\n'.join(json.dumps(case) for case in items)+'\n',capture_output=True,text=True)
                assert result.returncode==0,result.stderr
                return result.stdout.splitlines()
            result=run([case for case,_ in cases]);assert result==[str(expected) for _,expected in cases],[(i,a,e) for i,(a,(_,e)) in enumerate(zip(result,cases)) if a!=str(e)]
            assert run([dict(payload=dict(customFieldId='f',value='copy'),copy=True)])==['1']
            assert run([dict(payload=dict(customFieldId='f',value='copy'),copy=True,revoke=True)])==['0'],'Collected copy guards must recheck changed flags'
            with sqlite3.connect(db) as con:con.execute("UPDATE custom_fields SET readOnly=1 WHERE id='f'")
            assert run([dict(payload=dict(customFields=[dict(_id='f',value='readonly')]),copy=True)])==['0']
            assert run([dict(payload=dict(customFields=[dict(_id='f',value=None)]),copy=True)])==['1']
            with sqlite3.connect(db) as con:con.execute("UPDATE custom_fields SET readOnly=0 WHERE id='f'")
            with sqlite3.connect(db) as con:con.execute("UPDATE board_members SET isAdmin=1 WHERE boardId='board'")
            assert run([dict(payload=dict(customFieldId='p',oldValue='historical secret',integrityHash='hash'))])==['1'],'Board admins can read historical fields without a live card'
            with sqlite3.connect(db) as con:
                con.execute("UPDATE board_members SET isAdmin=0 WHERE boardId='board'")
                con.execute("UPDATE users SET isAdmin=1 WHERE id='u'")
            assert run([dict(payload=dict(customFieldId='p',value='secret'))])==['0'],'Site administration is not board administration'
            with sqlite3.connect(db) as con:con.execute("UPDATE users SET isAdmin=0 WHERE id='u'")
            print('PASS:',backend,mode,len(cases),'plain/nested/JSON/BSON payload cases, aliases, hashes, case-sensitive IDs, invalid data, historical admin access and unchanged input')
