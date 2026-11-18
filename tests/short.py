"""Short generated paths, durable mappings, SQLite sidecars and offline migration."""
import importlib.util
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('pathmove',root/'releases/pathmove.py')
migration=importlib.util.module_from_spec(spec);spec.loader.exec_module(migration)
short=re.compile(r'[A-Za-z0-9_-]{1,8}(\.[A-Za-z0-9_-]{1,3})?\Z')
def assert_short(data):
    for path in data.rglob('*'):assert short.fullmatch(path.name),path
backends={'linked': [], 'cli': ['-dWLDB_CLI']}
selected=os.environ.get('WELITE_SHORT_BACKEND')
if selected:
    if selected not in backends:
        raise SystemExit('WELITE_SHORT_BACKEND must be linked or cli')
    backends={selected: backends[selected]}
with tempfile.TemporaryDirectory(prefix='wlpaths-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    for backend,flags in backends.items():
        out=tmp/backend;out.mkdir();data=out/'data'
        built=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/short.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        env=dict(os.environ,WELITE_SCHEMA=str(root/'src/schema.sql'))
        # An ordinary SQLite build must refuse strict operation rather than silently
        # create long journal names. The strict run below uses consistently built tools.
        if os.environ.get('WELITE_SHORT_NAMES')!='1':
            refused=subprocess.run([str(out/'short'),str(out/'reject')],env=dict(env,WELITE_SHORT_NAMES='1'),capture_output=True,text=True)
            assert refused.returncode!=0 and 'SQLITE_ENABLE_8_3_NAMES=2' in refused.stderr,refused.stderr

        for attempt in range(2):
            proc=subprocess.Popen([str(out/'short'),str(data)],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            lines=[]
            while True:
                line=proc.stdout.readline()
                if not line:raise AssertionError(proc.stderr.read())
                if line.strip()=='READY':break
                lines.append(line.strip())
            assert len(lines)==6,lines
            assert Path(lines[0])==data/'domains/d0000001/files/db/wekan.db'
            assert Path(lines[1])==data/'certs/d0000001'
            assert lines[2]!=lines[3] and all(Path(p).is_dir() for p in lines[2:4])
            framework=Path(lines[4]);assert framework.name=='upload.tmp' and framework.parent.is_dir() and data in framework.parents
            if os.environ.get('WELITE_SHORT_NAMES')=='1':
                assert_short(data)
                if backend=='linked':
                    db_dir=Path(lines[0]).parent
                    assert (db_dir/'wekan.wal').is_file(),'No live short WAL observed'
                    assert (db_dir/'wekan.shm').is_file(),'No live short SHM observed'
            proc.communicate('\n',timeout=10);assert proc.returncode==0
            with sqlite3.connect(lines[0]) as db:assert db.execute('SELECT COUNT(*) FROM durable').fetchone()[0]==attempt+1
        if backend=='linked' and os.environ.get('WELITE_SHORT_NAMES')=='1':
            probe=subprocess.Popen([str(out/'short'),str(out/'journal'),'journal'],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            while True:
                line=probe.stdout.readline()
                if not line:raise AssertionError(probe.stderr.read())
                if line.strip()=='READY':break
            journals=list((out/'journal').rglob('*.nal'))
            assert journals,'No live short rollback journal observed'
            assert_short(out/'journal')
            probe.communicate('\n',timeout=10);assert probe.returncode==0
        print('PASS:',backend,'persistent tenant keys, distinct long domains, short temp allocation and live SQLite sidecars')
    # Migrate a deliberately old tree, then resolve its domain through the current runtime.
    old=tmp/'old';admin=old/'admin/db/data.db';admin.parent.mkdir(parents=True)
    with sqlite3.connect(admin) as db:
        db.executescript((root/'src/schema.sql').read_text())
        db.execute('CREATE TABLE domains(host TEXT PRIMARY KEY,enabled INTEGER,createdAt TEXT,modifiedAt TEXT)')
        db.execute('CREATE TABLE domain_aliases(alias TEXT PRIMARY KEY,host TEXT)')
        for host in ['a-very-long.customer.example','a-very-long.customer.other']:
            db.execute('INSERT INTO domains VALUES(?,1,\'now\',NULL)',(host,))
    tenant=old/'domains/a-very-long.customer.example'
    database=tenant/'db/data.db';database.parent.mkdir(parents=True)
    with sqlite3.connect(database) as db:
        db.executescript((root/'src/schema.sql').read_text())
        db.execute('CREATE TABLE durable(value TEXT)');db.execute("INSERT INTO durable VALUES('original')")
    files=tenant/'files/attachments';files.mkdir(parents=True)
    (files/'LongCaseSensitiveIdentifier').write_bytes(b'legacy\0bytes')
    probe_path=tmp/next(iter(backends))/'short'
    legacy=subprocess.run([str(probe_path),str(old)],capture_output=True,text=True,env=dict(os.environ,WELITE_SCHEMA=str(root/'src/schema.sql')))
    assert legacy.returncode!=0 and 'Legacy paths detected' in legacy.stderr
    assert not (old/'admin/files').exists(),'Startup modified legacy storage'
    target=tmp/'new';migration.migrate(old,target);assert_short(target)
    copied=target/'domains/d0000001/files/db/wekan.db'
    with sqlite3.connect(copied) as db:assert db.execute('SELECT value FROM durable').fetchone()==('original',)
    expected=migration.file_path(copied.parents[1],'attachme','LongCaseSensitiveIdentifier')
    assert expected.read_bytes()==b'legacy\0bytes' and (files/'LongCaseSensitiveIdentifier').read_bytes()==b'legacy\0bytes'
    restarted=subprocess.run([str(probe_path),str(target)],input='\n',capture_output=True,text=True,env=dict(os.environ,WELITE_SCHEMA=str(root/'src/schema.sql')),timeout=20)
    assert restarted.returncode==0,restarted.stderr
    with sqlite3.connect(copied) as db:assert db.execute('SELECT value FROM durable ORDER BY rowid').fetchall()==[('original',),('retained',)]
    for suffix in ['existing','symlink','invalid']:
        rejected=tmp/suffix
        if suffix=='existing':rejected.mkdir()
        elif suffix=='symlink':(files/'link').symlink_to(files/'LongCaseSensitiveIdentifier')
        else:
            (files/'link').unlink();(tenant/'unexpected-long-name').write_text('preserve')
        try:migration.migrate(old,rejected);raise AssertionError('Unsafe migration succeeded')
        except ValueError:pass
        assert suffix=='existing' or not rejected.exists()
    print('PASS: offline migration preserves original bytes/rows, publishes only short verified paths and rejects unknown/symlink/existing targets')
