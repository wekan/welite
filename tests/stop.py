"""Graceful Unix signals with idle, busy and incomplete HTTP connections."""
import http.client
import os
from pathlib import Path
import signal
import socket
import sqlite3
import subprocess
import tempfile
import threading
import time
root=Path(__file__).resolve().parents[1]
assert os.name=='posix'
with tempfile.TemporaryDirectory(prefix='wlstop-',dir=os.environ['TMPDIR']) as directory:
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=Path(directory)/backend;out.mkdir();build=out/'build';build.mkdir()
        result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(build),'-FE'+str(build),str(root/'src/wlhttp.lpr')],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
        with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        env=dict(os.environ,WELITE_DATA=str(out/'data'),WELITE_PORT=str(port),WELITE_SCHEMA=str(root/'src/schema.sql'),WELITE_DESIGNER=str(root/'src/designer.sql'),WELITE_SHARED='0')
        for key in ['WELITE_SHORT_NAMES','WELITE_ENTROPY_FILE','WELITE_SQLITE_EXT']:env.pop(key,None)
        database=out/'data/local/files/db/wekan.db'
        def request():
            con=http.client.HTTPConnection('127.0.0.1',port,timeout=3)
            try:
                con.request('GET','/sign-in',headers={'Host':'localhost'})
                response=con.getresponse();response.read();assert response.status==200
            finally:con.close()
        with (out/'http.log').open('w+') as log:
            for mode,sig in [('idle',signal.SIGTERM),('busy',signal.SIGINT),('partial',signal.SIGTERM)]:
                print('Testing',backend,mode,flush=True)
                app=subprocess.Popen([str(build/'wlhttp')],cwd=out,env=env,stdout=log,stderr=log)
                partial=None;traffic=None;done=threading.Event()
                try:
                    for _ in range(100):
                        try:request();break
                        except OSError:
                            assert app.poll() is None
                            time.sleep(.05)
                    else:raise AssertionError('HTTP startup timeout')
                    def hammer():
                        while not done.is_set():
                            try:request()
                            except (OSError,http.client.HTTPException):return
                    if mode=='busy':traffic=threading.Thread(target=hammer);traffic.start()
                    if mode=='partial':
                        partial=socket.create_connection(('127.0.0.1',port),timeout=3)
                        partial.sendall(b'GET / HTTP/1.1\r\nHost: localhost\r\n')
                        time.sleep(.1)
                    app.send_signal(sig)
                    if mode=='partial':
                        time.sleep(.05);app.send_signal(sig)
                    assert app.wait(timeout=8)==0,(backend,mode,app.returncode)
                    with sqlite3.connect(database) as con:
                        assert con.execute('PRAGMA integrity_check').fetchone()==('ok',)
                    # The next iteration immediately reuses this port and database.
                finally:
                    done.set()
                    if app.poll() is None:app.kill();app.wait()
                    if partial:partial.close()
                    if traffic:traffic.join(timeout=5);assert not traffic.is_alive()
            log.seek(0);assert log.read().count('WeKan-Lite stopped')==3
            print('PASS:',backend,'SIGTERM/SIGINT exit 0, idle/busy/partial connections, immediate restart and SQLite integrity')
