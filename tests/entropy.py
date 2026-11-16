"""OS entropy and fail-closed, durable, concurrent portable entropy stocks."""
import concurrent.futures
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
env=dict(os.environ)
env.pop('WELITE_ENTROPY_FILE',None)
with tempfile.TemporaryDirectory(prefix='wlrandom-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        programs=[]
        for mode,extra in [('native',[]),('portable',['-dWLNOOSRAND'])]:
            out=tmp/(backend+mode);out.mkdir()
            build=subprocess.run([os.environ.get('FPC','fpc'),*flags,*extra,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/entropy.lpr')],capture_output=True,text=True,env=env)
            assert build.returncode==0,build.stdout+build.stderr
            programs.append(out/'entropy')
        native,portable=programs
        def run(program,*args,stock=None):
            settings=dict(env)
            if stock is not None:settings['WELITE_ENTROPY_FILE']=str(stock)
            return subprocess.run([str(program),*map(str,args)],env=settings,capture_output=True,text=True,timeout=30)
        if os.environ.get('WELITE_SHORT_NAMES')=='1':
            invalid=run(native,'create',tmp/'overlongname.db',32)
            assert invalid.returncode!=0 and '8.3 database filename' in invalid.stderr
        assert len(run(native).stdout.strip())==64
        assert run(portable).returncode!=0
        stock=tmp/(backend+'.db')
        assert run(native,'create',stock,2048).returncode==0
        assert stock.stat().st_mode&0o777==0o600
        def count():
            with sqlite3.connect(stock) as db:return db.execute('SELECT COUNT(*) FROM entropy').fetchone()[0]
        assert count()==64
        assert run(native,'create',stock,32).returncode!=0 and count()==64
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results=list(pool.map(lambda _:run(portable,stock=stock),range(32)))
        assert all(result.returncode==0 for result in results),[(r.stdout,r.stderr) for r in results if r.returncode]
        assert len({r.stdout for r in results})==32 and count()==32
        with sqlite3.connect(stock) as db:
            db.execute("CREATE TRIGGER blocked BEFORE DELETE ON entropy BEGIN SELECT RAISE(ABORT,'blocked'); END")
        failed=run(native,stock=stock)
        assert failed.returncode!=0 and failed.stdout=='' and count()==32
        with sqlite3.connect(stock) as db:
            db.execute('DROP TRIGGER blocked');db.execute('DELETE FROM entropy')
        assert run(native,stock=stock).returncode!=0
        missing=tmp/(backend+'x.db')
        assert run(native,stock=missing).returncode!=0 and not missing.exists()
        assert run(portable,'create',missing,32).returncode!=0 and not missing.exists()
        with sqlite3.connect(stock) as db:
            db.execute('DROP TABLE entropy');db.execute('CREATE TABLE entropy(id INTEGER PRIMARY KEY,value BLOB)')
            db.execute("INSERT INTO entropy VALUES(1,X'00')")
        malformed=run(native,stock=stock)
        assert malformed.returncode!=0 and malformed.stdout==''
        print('PASS:',backend,'native entropy, forced portable mode, private stock, concurrent one-use blocks and failure denial')
