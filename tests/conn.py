"""Advertise the pinned FPC server's single-request connection lifecycle."""
import http.client
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wlconn-',dir=os.environ['TMPDIR']) as directory:
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=Path(directory)/backend;out.mkdir();build=out/'build';build.mkdir()
        result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(build),'-FE'+str(build),str(root/'src/wlhttp.lpr')],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
        public=out/'public';public.mkdir();(public/'robots.txt').write_bytes(b'User-agent: *\nDisallow: /\n')
        with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        env=dict(os.environ,WELITE_PORT=str(port),WELITE_DATA=str(out/'data'),WELITE_SHARED='0',WELITE_PUBLIC=str(public),WELITE_I18N=str(root/'i18n'),WELITE_SCHEMA=str(root/'src/schema.sql'),WELITE_DESIGNER=str(root/'src/designer.sql'))
        for key in ['WELITE_ENTROPY_FILE','WELITE_SQLITE_EXT','WELITE_SHORT_NAMES','WELITE_ARGON_SECRET_FILE','REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN']:env.pop(key,None)
        with (out/'http.log').open('w+') as log:
            app=subprocess.Popen([str(build/'wlhttp')],cwd=out,env=env,stdout=log,stderr=log)
            try:
                for _ in range(100):
                    try:
                        with socket.create_connection(('127.0.0.1',port),timeout=1):break
                    except OSError:assert app.poll() is None;time.sleep(.05)
                else:raise AssertionError('Server startup timeout')
                client=http.client.HTTPConnection('127.0.0.1',port,timeout=10)
                try:
                    cases=[('GET','/sign-in',None,{200}),('GET','/robots.txt',None,{200}),('GET','/',None,{200}),
                           # '/' is the guest home page since fd5f992, no longer a redirect to sign-in.
                           ('GET','/missing-route',None,{404}),('GET','/api/user?token=invalid',None,{401}),
                           ('POST','/board/move','sessionId=invalid',{403}),('POST','/sign-in','username=missing&password=invalid',{200,429})]
                    for _ in range(4):
                        for method,path,body,statuses in cases:
                            client.request(method,path,body,{'Host':'localhost','User-Agent':'Conn-test','Connection':'keep-alive','Content-Type':'application/x-www-form-urlencoded'})
                            response=client.getresponse();response.read()
                            assert response.status in statuses,(backend,path,response.status)
                            assert response.version==11
                            assert response.getheader('Connection','').lower()=='close',(backend,path,response.getheaders())
                            assert response.will_close and client.sock is None,(backend,path,'client retained closing socket')
                finally:client.close()
                with socket.create_connection(('127.0.0.1',port),timeout=5) as wire:
                    wire.sendall(b'GET /robots.txt HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n')
                    chunks=[]
                    while True:
                        part=wire.recv(8192)
                        if not part:break
                        chunks.append(part)
                    raw=b''.join(chunks)
                    assert b'\r\nconnection: close\r\n' in raw.lower()
                    assert raw.endswith((public/'robots.txt').read_bytes())
                subprocess.run([os.environ.get('NODE','node'),str(root/'tests/conn.js'),'http://127.0.0.1:'+str(port)],check=True,timeout=60)
                assert app.poll() is None
            finally:
                app.terminate()
                try:app.wait(timeout=10)
                except subprocess.TimeoutExpired:app.kill();app.wait();raise
                if app.returncode:log.seek(0);raise AssertionError(log.read())
        print('PASS: '+backend+' HTTP/1.1 close header, mixed routed statuses, actual EOF, pooled reconnects and clean shutdown')
