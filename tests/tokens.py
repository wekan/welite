"""Live token credential/tenant/client binding and HMAC tamper rejection."""
from signin import session_of, signed_in
from layout import Forms
from urllib.parse import parse_qs, urlsplit
import hashlib
import json
import sqlite3
from paths import domain_db

def run(request,db,admin):
    name='crypto-user';password='test-password'
    registered=request('POST','/register',dict(username=name,password=password,confirm=password))
    web=signed_in(registered)
    login=request('POST','/users/login',dict(username=name,password=password))
    assert login[0]==200
    api=json.loads(login[2])['token'];uid=json.loads(login[2])['id']
    assert request('GET','/api/user?token='+web)[0]==200
    assert request('GET','/api/user?token='+web,agent='Different client')[0]==401
    assert request('GET','/api/user?token='+web,extra_headers={'X-Forwarded-For':'203.0.113.50'})[0]==200
    assert request('GET','/api/user?token='+api,agent='API client')[0]==200
    with sqlite3.connect(db) as con:
        token=con.execute('SELECT * FROM login_tokens WHERE hashedToken=?',(hashlib.sha256(b'welite-token-v2\0'+str(db).encode()+b'\0'+api.encode()).hexdigest(),)).fetchone()
        assert token is not None and len(token[0])==64 and token[0]!=api
        meta=con.execute('SELECT * FROM authmeta WHERE hashedToken=?',(token[0],)).fetchone()
        user=con.execute('SELECT id,username,createdAt,modifiedAt,services_json FROM users WHERE id=?',(uid,)).fetchone()
        services=user[4]
        assert meta[1]==hashlib.sha256(str(db).encode()).hexdigest()
        credential=json.loads(services)['password']
        if isinstance(credential,dict):credential=json.dumps(credential,ensure_ascii=False,separators=(',',':'))
        assert meta[2]==hashlib.sha256(credential.encode()).hexdigest() and meta[3]=='api'
    other=domain_db(db.parents[3],'team.example')
    with sqlite3.connect(other) as con:
        con.execute('INSERT INTO users(id,username,createdAt,modifiedAt,services_json) VALUES(?,?,?,?,?)',user)
        con.execute('INSERT INTO login_tokens VALUES(?,?,?,?)',token)
        con.execute('INSERT INTO authmeta VALUES(?,?,?,?)',meta)
    assert request('GET','/api/user?token='+api,host='team.example')[0]==401
    assert request('GET','/api/user?token='+api)[0]==200
    with sqlite3.connect(db) as con:con.execute("UPDATE users SET services_json='{\"password\":\"changed\"}' WHERE id=?",(uid,))
    assert request('GET','/api/user?token='+api)[0]==401
    with sqlite3.connect(db) as con:
        assert con.execute('SELECT COUNT(*) FROM login_tokens WHERE hashedToken=?',(token[0],)).fetchone()[0]==0
        con.execute('UPDATE users SET services_json=? WHERE id=?',(services,uid))
    assert request('GET','/api/user?token='+api)[0]==401
    parser=Forms();parser.feed(request('GET','/board?id=protected&view=all&sessionId='+admin)[2].decode())
    form=parser.forms[-1][1]
    assert len(form['auth_hash'])==64
    tampered=dict(form,action='clone',sel_card='card',auth_hash=('0' if form['auth_hash'][0]!='0' else '1')+form['auth_hash'][1:])
    with sqlite3.connect(db) as con:before='\n'.join(con.iterdump())
    assert request('POST','/board/move',tampered)[0]==403
    with sqlite3.connect(db) as con:assert '\n'.join(con.iterdump())==before
    assert request('POST','/board/move',dict(form,action='clear'))[0]==302
    print('PASS: live tenant/credential/client token binding, default forwarded-IP spoof rejection and HMAC mutation tamper denial')
