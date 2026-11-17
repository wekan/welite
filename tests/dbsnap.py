"""Pinned read transactions, CLI framing, read-only enforcement and handle gating."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import select
import sqlite3
import subprocess
import tempfile
import time
root=Path(__file__).resolve().parents[1]
@contextmanager
def connect(path):
    con=sqlite3.connect(path)
    try:
        with con:yield con
    finally:con.close()
with tempfile.TemporaryDirectory(prefix='wldbsnap-',dir=os.environ['TMPDIR']) as directory:
    temp=Path(directory)
    for backend,extra in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]+([('stock',['-dWLNOOSRAND'])] if backend=='cli' else []):
            out=temp/(backend+mode);out.mkdir();db=out/'source.db';scratch=out/'space " quote 漢'
            with connect(db) as con:
                con.executescript("PRAGMA journal_mode=WAL;CREATE TABLE t(x TEXT);INSERT INTO t VALUES('old');CREATE VIEW v AS SELECT x FROM t;")
            built=subprocess.run([os.environ.get('FPC','fpc'),'-B',*extra,*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/dbsnap.lpr')],capture_output=True,text=True)
            assert built.returncode==0,built.stdout+built.stderr
            env=dict(os.environ);stock=out/'stock.db'
            if mode=='stock':
                with connect(stock) as con:
                    con.execute('CREATE TABLE entropy(id INTEGER PRIMARY KEY,value BLOB NOT NULL)')
                    con.executemany('INSERT INTO entropy(value) VALUES(?)',[(os.urandom(32),) for _ in range(10)])
                env['WELITE_ENTROPY_FILE']=str(stock)
            proc=subprocess.Popen([str(out/'dbsnap'),str(db),str(scratch)],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
            def command(op='read',**options):
                proc.stdin.write(json.dumps(dict(op=op,**options))+'\n');proc.stdin.flush()
                ready=select.select([proc.stdout],[],[],15)[0]
                assert ready,'Snapshot reader hung'
                line=proc.stdout.readline();assert line,(proc.poll(),proc.stderr.read() if proc.poll() is not None else '')
                return json.loads(line)
            try:
                assert command('begin')==dict(ok=True)
                assert command('begin')==dict(ok=False),'Nested begin must not end an existing read'
                with connect(db) as con:
                    con.execute("UPDATE t SET x='new'");con.execute("CREATE TABLE added(value TEXT)")
                assert command()['rows']==[['old']],'Snapshot must pin before first caller query'
                assert command(sql="SELECT count(*) FROM sqlite_master WHERE name='added'")['rows']==[['0']]
                assert command(sql='SELECT x FROM v')['rows']==[['old']]
                for sql in ["UPDATE t SET x='bad' RETURNING x","SELECT 1; COMMIT;","COMMIT","ROLLBACK","PRAGMA query_only=OFF","-- prefix\nSELECT 1;/* gap */END;",'.mode csv']:
                    assert command(sql=sql)['rows']==[],sql
                assert command('exec',sql="UPDATE t SET x='bad'")==dict(ok=False)
                assert command('scan-fail')==dict(ok=False)
                assert command()['rows']==[['old']],'Handler failure cannot lose the transaction'
                assert command(sql="/* prefix */ SELECT ';--not a command' AS value; -- tail")['rows']==[[';--not a command']]
                assert command(sql="WITH a AS (SELECT 'quoted\"\r\n漢' value) SELECT value FROM a")['rows']==[['quoted"\r\n漢']]
                assert command(sql='PRAGMA table_info(t)')['rows'][0][1]=='x'
                assert command('writer-start')==dict(ok=True)
                deadline=time.monotonic()+3
                while command('writer-state')['started']==0:
                    assert time.monotonic()<deadline;time.sleep(.01)
                time.sleep(.05);assert command('writer-state')['done']==0,'A cached handle writer crossed the read boundary'
                assert command('end')==dict(ok=True)
                deadline=time.monotonic()+5
                while command('writer-state')['done']==0:
                    assert time.monotonic()<deadline;time.sleep(.01)
                assert command()['rows']==[['thread']]
                assert command('end')==dict(ok=False)
                assert command('exec',sql="UPDATE t SET x='after'")==dict(ok=True)
                assert command()['rows']==[['after']]
                assert command('begin')==dict(ok=True)
                assert command(sql="SELECT 'first' UNION ALL SELECT json('broken')")['rows']==[]
                assert command('end')==dict(ok=backend=='linked')
                assert command()['rows']==[['after']],'A failed snapshot poisoned later live reads'
                assert command('begin')==dict(ok=True)
                assert command(sql="WITH a AS (SELECT 1) UPDATE t SET x='mutating CTE' RETURNING x")['rows']==[]
                assert command('end')==dict(ok=backend=='linked')
                assert command()['rows']==[['after']],'A mutating CTE wrote through a read snapshot'
                assert command('begin')==dict(ok=True)
                assert command()['rows']==[['after']]
                # EOF/destruction must also release the read connection and private files.
            finally:
                proc.stdin.close();proc.wait(timeout=15)
            assert proc.returncode==0,proc.stderr.read()
            assert not scratch.exists() or list(scratch.iterdir())==[],'Snapshot scratch files leaked'
            with connect(db) as con:con.execute("UPDATE t SET x='reopened'")
            if mode=='stock':
                with connect(stock) as con:
                    assert con.execute('SELECT count(*) FROM entropy').fetchone()==(6,),'Framing consumed entropy per query or nested begin'
                    con.execute('DELETE FROM entropy')
                proc=subprocess.Popen([str(out/'dbsnap'),str(db),str(scratch)],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
                try:
                    assert command('begin')==dict(ok=False),'Exhausted framing entropy must deny a snapshot'
                    assert command()['rows']==[['reopened']]
                finally:proc.stdin.close();proc.wait(timeout=10)
                assert proc.returncode==0,proc.stderr.read()
                assert not scratch.exists() or list(scratch.iterdir())==[]

            assert not list(out.rglob('query.sql')),'Snapshot SQL scratch file leaked'
            print('PASS:',backend,mode,'pinned rows/schema, independent WAL writer, readonly SQL, framing/UTF-8 paths, nested begin, handler failure, handle gate, reuse and cleanup')
