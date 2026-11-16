"""Independent SHA/HMAC vectors, proxy policy and cross-process durable token binding."""
import hashlib
import hmac
import ipaddress
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
for source in list((root/'src').glob('*.pas'))+list((root/'src').glob('*.lpr')):
    text=source.read_text()
    assert '1469598103934665603' not in text and '1099511628211' not in text, source
    for weak in ['HashText(Token)','HashText(SessionId)','HashText(Result.SessionId)']:
        assert weak not in text, (source,weak)

with tempfile.TemporaryDirectory(prefix='wlcrypto-',dir=os.environ['TMPDIR']) as tmp:
    tmp=Path(tmp)
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=tmp/backend;out.mkdir()
        for source in ['crypto','token']:
            built=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests'/f'{source}.lpr')],capture_output=True,text=True)
            if built.returncode:raise RuntimeError(built.stdout+built.stderr)
        lines=subprocess.check_output([str(out/'crypto')],text=True).splitlines()
        expected=[hashlib.sha256(value).hexdigest() for value in [b'',b'abc','日本語\0tail'.encode()]]
        cases=[(b'\x0b'*20,b'Hi There'),(b'Jefe',b'what do ya want for nothing?'),(b'\xaa'*131,b'Test Using Larger Than Block-Size Key - Hash Key First')]
        expected+=[hmac.new(key,value,hashlib.sha256).hexdigest() for key,value in cases]
        assert lines[:6]==expected,(backend,lines,expected)
        assert 'PASS' in lines[6]
        for trusted,peer,header,result in [
            ('','198.51.100.20','203.0.113.9','198.51.100.20'),
            ('127.0.0.1,10.0.0.2','127.0.0.1','192.0.2.9,198.51.100.20,10.0.0.2','198.51.100.20'),
            ('127.0.0.1','198.51.100.20','203.0.113.9','198.51.100.20'),
            ('127.0.0.1','127.0.0.1','198.51.100.20,not-an-ip','127.0.0.1'),
            ('::1','0:0:0:0:0:0:0:1','2001:db8::9','2001:db8::9'),
        ]:
            value=subprocess.check_output([str(out/'crypto'),'proxy',peer,header],env=dict(os.environ,WELITE_TRUSTED_PROXIES=trusted),text=True).strip()
            assert ipaddress.ip_address(value)==ipaddress.ip_address(result),(trusted,peer,header,value)
        db=out/'main.db'
        with sqlite3.connect(db) as con:
            con.executescript((root/'src/schema.sql').read_text())
            con.execute("INSERT INTO users(id,username,createdAt,modifiedAt,services_json) VALUES('u','user','now','now','{\"password\":\"credential\"}')")
        def token(mode, database=db, value='api-test-token'):
            return subprocess.check_output([str(out/'token'),mode,str(database),value],text=True).strip()
        assert token('issue')=='yes'
        assert token('check')=='yes','Durable token did not survive process restart'
        with sqlite3.connect(db) as con:
            key=con.execute('SELECT hashedToken FROM login_tokens').fetchone()[0]
            assert key==hashlib.sha256(b'welite-token-v2\0'+str(db).encode()+b'\0api-test-token').hexdigest()
            con.execute("INSERT INTO login_tokens VALUES('0123456789ABCDEF','u','now','2099-01-01')")
            con.commit()
            target=sqlite3.connect(out/'copy.db')
            try:con.backup(target)
            finally:target.close()
        assert token('check',out/'copy.db')=='no','Copied database accepted another tenant token'
        assert token('check',value='legacy-predictable')=='no'
        with sqlite3.connect(db) as con:con.execute("UPDATE users SET services_json='{\"password\":\"changed\"}' WHERE id='u'")
        assert token('check')=='no'
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT COUNT(*) FROM login_tokens WHERE hashedToken=?',(key,)).fetchone()[0]==0
            assert con.execute('SELECT COUNT(*) FROM authmeta WHERE hashedToken=?',(key,)).fetchone()[0]==0
            con.execute("UPDATE users SET services_json='{\"password\":\"credential\"}' WHERE id='u'")
        assert token('check')=='no','Credential restoration revived a revoked token'
        web=token('web')
        assert token('check',value=web)=='no','Web context survived restart without server metadata'
        print('PASS:',backend,'SHA/HMAC vectors, trusted proxy chain, durable API restart/credential/tenant binding and legacy denial')
