"""Startup discovery on independent SQLite backups, never filename aliases."""
import json
from pathlib import Path
import sqlite3
import subprocess
import time

def run(out,source,physical,env):
    root=out/'discover';root.mkdir()
    admin=root/'admin/files/db/wekan.db';admin.parent.mkdir(parents=True)
    with sqlite3.connect(admin) as db:
        db.executescript('CREATE TABLE domains(host TEXT PRIMARY KEY,enabled INTEGER); CREATE TABLE tenantdirs(id INTEGER PRIMARY KEY,host TEXT);')
        db.executemany('INSERT INTO domains VALUES(?,?)',[('one.example',1),('two.example',0),('../invalid',1),('missing.example',1)])
        db.executemany('INSERT INTO tenantdirs VALUES(?,?)',[(1,'one.example'),(2,'two.example'),(3,'orphan.example'),(5,'../invalid'),(6,'missing.example')])
    stores={0:root/'local/files/db/wekan.db'}
    stores.update({i:root/'domains'/f'd{i:07x}'/'files/db/wekan.db' for i in [1,2,3,4,5]})
    for path in stores.values():
        path.parent.mkdir(parents=True)
        with sqlite3.connect(source) as original,sqlite3.connect(path) as target:original.backup(target)
    def document(index):
        with sqlite3.connect(stores[index]) as db:
            return json.loads(db.execute('SELECT json(_ferretdb_sjson) FROM "'+physical.replace('"','""')+'" WHERE json_extract(_ferretdb_sjson,\'$._id\')=\'discovery-user\'').fetchone()[0])
    before={i:document(i) for i in stores}
    worker=subprocess.Popen([str(out/'maint/maint'),'--root',str(root)],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    def wait_clean(indices):
        for _ in range(200):
            if all(len(document(i)['services']['resume']['loginTokens'])==1 for i in indices):return
            assert worker.poll() is None
            time.sleep(.05)
        raise AssertionError('Registered tenant discovery did not sweep without a request')
    try:
        assert worker.stdout.readline().strip()=='ready'
        wait_clean([0,1])
        for i in [2,3,4,5]:assert document(i)==before[i],('Unexpected discovered store',i)
        # The same worker notices new registry entries and enabling without HTTP.
        with sqlite3.connect(admin) as db:
            db.execute("UPDATE domains SET enabled=1 WHERE host='two.example'")
            db.execute("INSERT INTO domains VALUES('four.example',1)")
            db.execute("INSERT INTO tenantdirs VALUES(4,'four.example')")
        wait_clean([2,4])
        for i in [3,5]:assert document(i)==before[i]
        assert not (root/'domains/d0000006').exists(),'Discovery provisioned a missing store'
        worker.stdin.write('status\n');worker.stdin.flush()
        assert worker.stdout.readline().strip()=='0','Normal registry/native stores reported failed sweeps'
        # A failed query must differ from a valid empty registry and be retried.
        with sqlite3.connect(admin) as db:db.execute('ALTER TABLE domains RENAME TO broken')
        for _ in range(200):
            worker.stdin.write('status\n');worker.stdin.flush()
            if int(worker.stdout.readline().strip())>0:break
            assert worker.poll() is None;time.sleep(.05)
        else:raise AssertionError('Registry read failure was mistaken for an empty registry')
        with sqlite3.connect(admin) as db:
            db.execute('ALTER TABLE broken RENAME TO domains')
            db.execute("INSERT INTO domains VALUES('orphan.example',1)")
        wait_clean([3])
        assert document(5)==before[5]
        output,errors=worker.communicate('stop\n',timeout=10)
        assert worker.returncode==0 and output.strip()=='stopped',(output,errors)
    finally:
        if worker.poll() is None:worker.kill();worker.wait()
