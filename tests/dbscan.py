"""Bounded row reads: CSV chunk boundaries, late errors, pipe pressure and cleanup."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wldbscan-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory);db=tmp/'scan.db';scratch=tmp/'scratch'
    values=['',None,'a,b','quote"x','CR\rLF\nCRLF\r\n','漢😀','x'*8190+'"z','a'*8191+'漢',"'; drop table sample; --"]
    values+=['header,"\r\n漢😀'+str(i)+'x'*16384 for i in range(20)]
    with sqlite3.connect(db) as con:
        con.execute('CREATE TABLE sample(id INTEGER PRIMARY KEY,value TEXT,tag TEXT)')
        con.executemany('INSERT INTO sample VALUES(?,?,?)',[(i,value,'row '+str(i)) for i,value in enumerate(values)])
    expected=[[value or '', 'row '+str(i)] for i,value in enumerate(values)]
    for backend,options in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
            out=tmp/(backend+mode);out.mkdir()
            built=subprocess.run([os.environ.get('FPC','fpc'),'-B',*options,*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/dbscan.lpr')],capture_output=True,text=True)
            assert built.returncode==0,built.stdout+built.stderr
            def run(cases,env=None):
                result=subprocess.run([str(out/'dbscan'),str(db),str(scratch)],input='\n'.join(json.dumps(case) for case in cases)+'\n',env=env,capture_output=True,text=True,timeout=30)
                assert result.returncode==0,result.stderr
                assert not scratch.exists() or list(scratch.iterdir())==[],'SQL scratch files leaked'
                return [json.loads(line) for line in result.stdout.splitlines()]
            result=run([dict(sql='SELECT value,tag FROM sample ORDER BY id'),dict(sql='SELECT value FROM sample WHERE 0'),dict(sql="SELECT 'first' UNION ALL SELECT json('broken')"),dict(sql='SELECT * FROM absent'),dict(sql='SELECT a.value FROM sample a,sample b',failAt=1),dict(sql="SELECT 'still usable'"),dict(sql="SELECT 'quote'",keep=False),dict(sql=".mode csv")])
            assert result[0]['ok'] and result[0]['rows']==expected,result[0]
            assert result[0]['bytes']==sum(len(cell.encode()) for row in expected for cell in row)
            assert result[1]==dict(ok=True,count=0,bytes=0,rows=[]),result[1]
            assert all(not row['ok'] and row['rows'] is None for row in result[2:5]),result
            assert result[5]['ok'] and result[5]['rows']==[['still usable']]
            assert result[6]==dict(ok=True,count=1,bytes=5,rows=[])
            assert not result[7]['ok'] and result[7]['rows'] is None
            if backend=='cli':
                empty=out/'emptybin';empty.mkdir()
                row=run([dict(sql='SELECT 1')],dict(os.environ,PATH=str(empty)))[0]
                assert not row['ok'] and row['rows'] is None,'Missing SQLite executable authorized a scan'
                fake=out/'fake';fake.mkdir();exe=fake/'sqlite3'
                exe.write_text('#!'+sys.executable+'\n'+'''import os,time
payload=bytes.fromhex(os.environ['SCAN_DATA'])
if os.environ.get('SCAN_NOISE'):
    for index in range(40):
        os.write(2,b'error '*2048)
        os.write(1,b'ignored,row\\n')
for offset in range(0,len(payload),8192):
    os.write(1,payload[offset:offset+8192]);time.sleep(.002)
raise SystemExit(int(os.environ.get('SCAN_EXIT','0')))
''');exe.chmod(0o700)
                base=dict(os.environ,PATH=str(fake)+os.pathsep+os.environ['PATH'])
                base.pop('WELITE_SQLITE_EXT',None)
                for raw,wanted in [(b'""',[['']]),(b',\n',[['','']]),(b'a\r\nb\rc\n',[['a'],['b'],['c']]),(b'"'+b'x'*8190+b'""z"\r\n',[['x'*8190+'"z']]),(('a'*8191+'漢\n').encode(),[['a'*8191+'漢']])]:
                    row=run([dict(sql='SELECT 1')],dict(base,SCAN_DATA=raw.hex()))[0]
                    assert row['ok'] and row['rows']==wanted,row
                for raw in [b'"unclosed',b'bad"quote\n',b'"closed"garbage\n']:
                    row=run([dict(sql='SELECT 1')],dict(base,SCAN_DATA=raw.hex()))[0]
                    assert not row['ok'] and row['rows'] is None,row
                for extra in [dict(SCAN_EXIT='7'),dict(SCAN_NOISE='1')]:
                    row=run([dict(sql='SELECT 1')],dict(base,SCAN_DATA=b'valid,row\n'.hex(),**extra))[0]
                    assert not row['ok'] and row['rows'] is None,row
                for prefix in [b'\n',b'\r\n']:
                    row=run([dict(sql='SELECT 1')],dict(base,SCAN_DATA=(prefix+b'valid,row\n').hex(),WELITE_SQLITE_EXT='extension.so'))[0]
                    assert row['ok'] and row['rows']==[['valid','row']],row
                row=run([dict(sql='SELECT 1')],dict(base,SCAN_DATA=b'bad-prefix\n'.hex(),WELITE_SQLITE_EXT='extension.so'))[0]
                assert not row['ok'],row
            print('PASS:',backend,mode,'streamed UTF-8/CSV, empty rows, SQL/handler failures, statement reuse, pipe pressure and scratch cleanup')
