"""Fresh embedded HTTP deployments have no source/schema/static directory dependency."""
import http.client
import json
import os
from pathlib import Path
import shutil
import shlex
import socket
import sqlite3
import subprocess
import tempfile
import time
from urllib.parse import urlencode,parse_qs,urlsplit
from layout import Forms
root=Path(__file__).resolve().parents[1]
fpc=os.environ.get('FPC','fpc');resource=os.environ.get('FPCRES',str(Path(fpc).with_name('fpcres')))
runner=shlex.split(os.environ.get('WELITE_RUNNER',''))
backends=os.environ.get('WELITE_EMBED_BACKENDS','linked,cli').split(',')
assert backends and all(name in ('linked','cli') for name in backends), backends
build_env=dict(os.environ)
if Path(fpc).is_absolute():build_env['PATH']=str(Path(fpc).parent)+os.pathsep+build_env.get('PATH','')
def command(args,**kwargs):
    result=subprocess.run(args,env=build_env,capture_output=True,text=True,**kwargs)
    assert result.returncode==0,result.stdout+result.stderr
    return result
with tempfile.TemporaryDirectory(prefix='wlembhttp-',dir=os.environ['TMPDIR']) as directory:
    for backend in backends:
        flags=['-dWLDB_CLI'] if backend=='cli' else []
        out=Path(directory)/backend;build=out/'build';build.mkdir(parents=True);work=out/'run';work.mkdir()
        command(['python3',str(root/'releases/genasset.py'),str(build/'wlassets.pas'),str(build/'wlpublic.rc')],cwd=root)
        command([resource,'wlpublic.rc','-o','wlpublic.res','-of','res'],cwd=build)
        shutil.copyfile(root/'src/wlhttp.lpr',build/'wlhttp.lpr')
        command([fpc,'-B','-dWLEMBED',*flags,'-Fu'+str(root/'src'),'-FU'+str(build),'-FE'+str(build),str(build/'wlhttp.lpr')])
        binary=work/'welite';shutil.copy2(build/'wlhttp',binary)
        with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        env=dict(build_env,WELITE_PORT=str(port),WELITE_DATA=str(work/'data'),WELITE_SHARED='0',
                 WELITE_PUBLIC=str(work/'absent-public'),WELITE_I18N=str(work/'absent-i18n'),WELITE_ADMIN_PASSWORD='test-password')
        for key in ['WELITE_SCHEMA','WELITE_DESIGNER','WELITE_SHORT_NAMES','WELITE_SQLITE_EXT','WELITE_ENTROPY_FILE',
                    'WELITE_ARGON_SECRET_FILE','REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN',
                    'PASSWORD_LOGIN_ENABLED','ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS','WELITE_TRUSTED_PROXIES']:env.pop(key,None)
        missing=out/'bad';missing.mkdir()
        refused=subprocess.run([*runner,str(binary),'initadmin','embedded-admin'],cwd=missing,
            env=dict(env,WELITE_DATA=str(missing/'data'),WELITE_SCHEMA=str(missing/'none.sql')),capture_output=True,text=True)
        assert refused.returncode!=0,'Explicit missing schema silently fell back to resources'
        initialized=subprocess.run([*runner,str(binary),'initadmin','embedded-admin'],cwd=work,env=env,capture_output=True,text=True)
        assert initialized.returncode==0,(backend,'directory-free initadmin',initialized.stdout,initialized.stderr)
        def request(method,path,fields=None,host='localhost'):
            con=http.client.HTTPConnection('127.0.0.1',port,timeout=30)
            headers={'Host':host,'User-Agent':'embedded-http'}
            if fields is not None:headers['Content-Type']='application/x-www-form-urlencoded'
            con.request(method,path,urlencode(fields) if fields is not None else None,headers)
            response=con.getresponse();result=response.status,dict(response.getheaders()),response.read();con.close();return result
        with (out/'http.log').open('w+') as log:
            server=subprocess.Popen([*runner,str(binary)],cwd=work,env=env,stdout=log,stderr=log)
            try:
                for attempt in range(600):
                    try:
                        if request('GET','/robots.txt')[0]==200:break
                    except OSError:pass
                    assert server.poll() is None
                    time.sleep(.05)
                else:raise AssertionError('Embedded HTTP startup timed out')
                for url,file in [('/robots.txt',root/'public/robots.txt'),('/i18n/locales.jsn',root/'i18n/locales.jsn'),('/i18n/data/bs.jsn',root/'i18n/data/bs.jsn')]:
                    status,_,body=request('GET',url);assert status==200 and body==file.read_bytes(),url
                for tag, direction in [('am','ltr'),('ckb','rtl'),('ur','rtl')]:
                    locale_file=root/f'i18n/data/{tag}.jsn'
                    status,_,body=request('GET',f'/i18n/data/{tag}.jsn')
                    assert status==200 and body==locale_file.read_bytes(),tag
                    status,headers,body=request('GET',f'/sign-in?lang={tag}')
                    assert status==200 and headers['Content-Language']==tag and 'Set-Cookie' not in headers
                    assert (b'dir="rtl"' in body)==(direction=='rtl'),tag
                    label=json.loads(locale_file.read_text())['username']
                    assert label!='Username' and label.encode() in body,(tag,label)
                    words=json.loads(locale_file.read_text())
                    for path,key in [('/missing-route?unused=1','page-not-found'),
                                     ('/board/card?id=missing&card=missing','field-link-not-found'),
                                     ('/board/attachments?id=missing','board-not-found'),
                                     ('/board/attachment?id=missing&card=missing&file=missing','attachment-repair-broken')]:
                        status,headers,body=request('GET',f'{path}&lang={tag}')
                        assert status==404 and headers['Content-Language']==tag and 'Set-Cookie' not in headers
                        assert (b'dir="rtl"' in body)==(direction=='rtl'),tag
                        assert words[key].encode() in body,(tag,key)
                status,headers,body=request('GET','/sign-in?lang=fi')
                assert status==200 and headers['Content-Language']=='fi'
                assert json.loads((root/'i18n/data/fi.jsn').read_text())['username'].encode() in body
                status,headers,_=request('POST','/register?lang=fi',dict(username='embedded-user',password='test-password',confirm='test-password'))
                assert status==302 and 'Set-Cookie' not in headers
                session=parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
                status,_,body=request('GET','/designer?sessionId='+session+'&lang=fi');assert status==200
                parser=Forms();parser.feed(body.decode())
                fields=next(fields for action,fields in parser.forms if action=='/designer/page/save')
                fields.update(action='save',url='/embedded',title='Embedded page',cols='1',doctype='html4',dir='auto',minRole='admin')
                assert request('POST','/designer/page/save',fields)[0]==302
                status,headers,body=request('GET','/embedded?sessionId='+session+'&lang=ar')
                assert status==200 and headers['Content-Language']=='ar' and b'dir="rtl"' in body
                with sqlite3.connect(work/'data/local/files/db/wekan.db') as con:
                    con.execute("INSERT INTO boards(id,title,slug,permission,createdAt) "
                                "VALUES('embedded-board','Embedded board','embedded-board','public','now')")
                    con.execute("INSERT INTO swimlanes(id,boardId,title,createdAt) "
                                "VALUES('embedded-lane','embedded-board','Lane','now')")
                    con.execute("INSERT INTO lists(id,boardId,title,createdAt) "
                                "VALUES('embedded-list','embedded-board','List','now')")
                status,headers,body=request('GET','/board?id=embedded-board&lang=ar')
                assert status==200 and headers['Content-Language']=='ar' and 'Set-Cookie' not in headers
                assert body.startswith(b'<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"')
                assert b'<meta name="viewport" content="width=device-width, initial-scale=1">' in body
                assert b'dir="rtl"' in body and b'<h1>Embedded board</h1>' in body
                attachment_page='/board/attachments?id=embedded-board'
                assert request('GET',attachment_page+'&lang=ar')[0]==404
                status,headers,body=request('GET',attachment_page+'&lang=ar&sessionId='+session)
                assert status==200 and headers['Content-Language']=='ar' and 'Set-Cookie' not in headers
                words=json.loads((root/'i18n/data/ar.jsn').read_text())
                assert all(words[key].encode() in body for key in ('attachments','no-items-message'))
                assert b'dir="rtl"' in body and b'/board?id=embedded-board' in body

                for path in ['/schema.sql','/designer.sql','/src/schema.sql','/_seed/schema.sql']:
                    status,_,body=request('GET',path);assert status==404 and b'CREATE TABLE' not in body,path
                login=request('POST','/sign-in?lang=ar',dict(username='embedded-admin',password='test-password'),host='admin')
                assert login[0]==302
                admin=parse_qs(urlsplit(login[1]['Location']).query)['sessionId'][0]
                assert request('GET','/admin/domains?sessionId='+admin+'&lang=ar',host='admin')[0]==200
                for name in ['public','i18n','src','schema.sql','designer.sql','absent-public','absent-i18n']:assert not (work/name).exists(),name
                with sqlite3.connect(work/'data/local/files/db/wekan.db') as con:
                    assert con.execute("SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('users','pages','page_widgets')").fetchone()==(3,)
            finally:
                server.terminate()
                try:server.wait(timeout=30)
                except subprocess.TimeoutExpired:server.kill();server.wait();raise
                if server.returncode:log.seek(0);raise AssertionError(log.read())
        print('PASS: '+backend+' fresh directory-free embedded admin/tenant/Designer bootstrap, exact static/catalog/locale bytes, translated auth, HTML4 board and attachment page, private SQL and clean shutdown')
