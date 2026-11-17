"""Translated sign-in HTML on linked/CLI backends, with no script/cookie requirement."""
import html
import http.client
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
from urllib.parse import quote,urlencode,urlsplit,parse_qs
root=Path(__file__).resolve().parents[1]
catalog=json.loads((root/'i18n/locales.jsn').read_text())
english=json.loads((root/'i18n/data/en.jsn').read_text())
with tempfile.TemporaryDirectory(prefix='wlsign-',dir=os.environ['TMPDIR']) as directory:
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=Path(directory)/backend;out.mkdir();build=out/'build';build.mkdir()
        result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(build),'-FE'+str(build),str(root/'src/wlhttp.lpr')],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
        with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        env=dict(os.environ,WELITE_PORT=str(port),WELITE_DATA=str(out/'data'),WELITE_I18N=str(root/'i18n'),WELITE_SCHEMA=str(root/'src/schema.sql'),WELITE_DESIGNER=str(root/'src/designer.sql'),WELITE_SHARED='0')
        for key in ['WELITE_ENTROPY_FILE','WELITE_SHORT_NAMES','WELITE_SQLITE_EXT','REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN']:env.pop(key,None)
        def request(tag='',method='GET',data=None,path=None):
            con=http.client.HTTPConnection('127.0.0.1',port,timeout=5)
            try:
                headers={'Host':'localhost'}
                if data is not None:headers['Content-Type']='application/x-www-form-urlencoded'
                con.request(method,path or '/sign-in?lang='+quote(tag),urlencode(data) if data is not None else None,headers=headers)
                response=con.getresponse();return response.status,dict(response.getheaders()),response.read().decode()
            finally:con.close()
        with (out/'http.log').open('w+') as log:
            app=subprocess.Popen([str(build/'wlhttp')],env=env,cwd=out,stdout=log,stderr=log)
            try:
                for _ in range(100):
                    try:request('en');break
                    except OSError:
                        assert app.poll() is None;time.sleep(.05)
                else:raise AssertionError('HTTP startup timeout')
                for row in catalog:
                    local=json.loads((root/'i18n/data'/row['file']).read_text())
                    status,headers,body=request(row['tag'])
                    assert status==200 and 'Set-Cookie' not in headers
                    assert headers['Content-Language']==row['tag'].replace('_','-')
                    assert 'Accept-Language' in headers['Vary']
                    assert 'lang="'+row['tag'].replace('_','-')+'"' in body
                    assert ('dir="rtl"' in body)==row['rtl'],row['tag']
                    for key in ['log-in','username','password','otp','create-account']:
                        expected=html.escape(local.get(key) or english[key],quote=True).replace('&#x27;',"'")
                        assert expected in body,(row['tag'],key,expected)
                    assert 'action="/sign-in?lang='+row['tag']+'"' in body
                    assert '<form method="GET" action="/sign-in">' in body
                    assert '<option value="'+row['tag']+'" selected="selected">' in body
                    assert html.escape(row['name'],quote=True).replace('&#x27;',"'") in body
                    assert '<script' not in body.lower()
                    for field in ['username','password','code']:assert 'name="'+field+'"' in body
                wrong='wrongsecret-sensitive'
                status,headers,body=request('ar','POST',dict(username='private-username',password=wrong))
                assert status==200 and headers['Content-Language']=='ar' and 'dir="rtl"' in body
                assert 'action="/sign-in?lang=ar"' in body and wrong not in body and 'private-username' not in body
                status,_,_=request(method='POST',path='/register',data=dict(username='user',password='test-password',confirm='test-password'))
                assert status==302
                status,headers,_=request('fi','POST',dict(username='user',password='test-password'))
                assert status==302
                location=parse_qs(urlsplit(headers['Location']).query)
                assert location['lang']==['fi'] and 'sessionId' in location and set(location)=={'lang','sessionId'}
                app.terminate();assert app.wait(timeout=8)==0
                fixture=out/'i18n';(fixture/'data').mkdir(parents=True)
                en=dict(next(row for row in catalog if row['tag']=='en'),name='<script>native</script>')
                (fixture/'locales.jsn').write_text(json.dumps([en]))
                hostile=dict(english,username='<script>alert("label")</script>')
                hostile['log-in']='" onfocus="alert(1)'
                (fixture/'data/en.jsn').write_text(json.dumps(hostile))
                env['WELITE_I18N']=str(fixture)
                app=subprocess.Popen([str(build/'wlhttp')],env=env,cwd=out,stdout=log,stderr=log)
                for _ in range(100):
                    try:status,headers,body=request('en');break
                    except OSError:
                        assert app.poll() is None;time.sleep(.05)
                else:raise AssertionError('Fixture HTTP startup timeout')
                class Markup(HTMLParser):
                    def __init__(self):super().__init__();self.inputs=[];self.tags=[]
                    def handle_starttag(self,tag,attrs):
                        self.tags.append(tag)
                        if tag=='input':self.inputs.append(dict(attrs))
                parsed=Markup();parsed.feed(body)
                assert 'script' not in parsed.tags and '<script>' not in body
                assert all('onfocus' not in fields for fields in parsed.inputs)
                assert any(fields.get('type')=='submit' and fields.get('value')==hostile['log-in'] for fields in parsed.inputs)
                assert '&lt;script&gt;' in body
                print('PASS:',backend,'all installed sign-in translations, escaped labels, language/direction headers, preserved form language and no scripts/cookies')
            finally:
                app.terminate()
                try:assert app.wait(timeout=8)==0
                except subprocess.TimeoutExpired:app.kill();app.wait();raise
