"""Actual session state transitions and concurrent token consumption on both backends."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wlsess-',dir=os.environ['TMPDIR']) as tmp:
    tmp=Path(tmp)
    for name,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=tmp/name;out.mkdir()
        for file in ['main.db','other.db']:
            with sqlite3.connect(out/file) as con:
                con.executescript((root/'src/schema.sql').read_text())
                for uid,username in [('u','user\x02日本語'),('other','other')]:
                    con.execute("INSERT INTO users(id,username,createdAt,modifiedAt,services_json) VALUES(?,?,'now','now',?)",(uid,username,json.dumps(dict(password='credential'))))
        build=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/session.lpr')],capture_output=True,text=True)
        if build.returncode:raise RuntimeError(build.stdout+build.stderr)
        env=dict(os.environ,WELITE_SESSION_IDLE='1')
        for variable in ['REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN']:env.pop(variable,None)
        subprocess.run([str(out/'session'),str(out/'main.db'),str(out/'other.db'),str(root/'i18n')],env=env,check=True,timeout=20)
