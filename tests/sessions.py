"""Web/API disabled-account denial and actual panel revocation/re-enable behavior."""
from layout import Forms
from urllib.parse import parse_qs, urlsplit
import json
import sqlite3
from pathlib import Path
SOURCE_WORDS=json.loads((Path(__file__).resolve().parents[1]/'i18n/data/en.jsn').read_text())
LOGIN_DENIAL=SOURCE_WORDS['invalid-credentials'].encode()
USERNAME_TAKEN=SOURCE_WORDS['error-username-taken'].encode()

def run(request,db,admin):
    user='session-user';password='test-password'
    status,headers,_=request('POST','/register',dict(username=user,password=password,confirm=password))
    assert status==302
    old=parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
    first=request('POST','/users/login',dict(username=user,password=password))
    assert first[0]==200
    api=json.loads(first[2])['token']
    assert old!=api and len(old)==64 and len(api)==64
    with sqlite3.connect(db) as con:uid=con.execute('SELECT id FROM users WHERE username=?',(user,)).fetchone()[0]
    def people(action):
        parser=Forms();parser.feed(request('GET','/admin/people?sessionId='+admin)[2].decode())
        data=next(values for path,values in parser.forms if path=='/admin/people')
        return request('POST','/admin/people',dict(data,action=action,userId=uid))
    assert request('GET','/api/user?token='+api)[0]==200
    # A direct disabled flag is checked on every request, independent of panel revocation.
    with sqlite3.connect(db) as con:con.execute('UPDATE users SET loginDisabled=1 WHERE id=?',(uid,))
    assert request('GET','/api/user?token='+api)[0]==401
    assert request('GET','/designer?sessionId='+old)[0]==302
    web=request('POST','/sign-in',dict(username=user,password=password))
    assert web[0]==200 and LOGIN_DENIAL in web[2] and 'Location' not in web[1]
    assert request('POST','/users/login',dict(username=user,password=password))[0]==401
    duplicate=request('POST','/register',dict(username=user,password=password,confirm=password))
    assert duplicate[0]==200 and USERNAME_TAKEN in duplicate[2] and 'Location' not in duplicate[1]
    with sqlite3.connect(db) as con:con.execute('UPDATE users SET loginDisabled=0 WHERE id=?',(uid,))
    assert people('disable')[0]==302
    with sqlite3.connect(db) as con:assert con.execute('SELECT COUNT(*) FROM login_tokens WHERE userId=?',(uid,)).fetchone()[0]==0
    assert request('GET','/api/user?token='+old)[0]==401
    assert request('GET','/api/user?token='+api)[0]==401
    assert people('enable')[0]==302
    # Re-enabling never revives the previously revoked credentials.
    assert request('GET','/api/user?token='+api)[0]==401
    assert request('GET','/designer?sessionId='+old)[0]==302
    new=request('POST','/sign-in',dict(username=user,password=password))
    assert new[0]==302
    fresh=parse_qs(urlsplit(new[1]['Location']).query)['sessionId'][0]
    assert fresh!=old
    # A password-hash change invalidates the web context's credential binding.
    with sqlite3.connect(db) as con:
        services=con.execute('SELECT services_json FROM users WHERE id=?',(uid,)).fetchone()[0]
        con.execute("UPDATE users SET services_json='{}' WHERE id=?",(uid,))
    assert request('GET','/designer?sessionId='+fresh)[0]==302
    with sqlite3.connect(db) as con:con.execute('UPDATE users SET services_json=? WHERE id=?',(services,uid))
    with sqlite3.connect(db) as con:
        con.execute("CREATE TRIGGER reject_session BEFORE INSERT ON login_tokens BEGIN SELECT RAISE(ABORT,'forced token failure'); END")
        # Pre-authentication reservations persist even when token issuance fails.
        before='\n'.join(line for line in con.iterdump() if not line.startswith('INSERT INTO "_wl_attempt"'))
    assert request('POST','/sign-in',dict(username=user,password=password))[0]==500
    assert request('POST','/users/login',dict(username=user,password=password))[0]==500
    with sqlite3.connect(db) as con:
        assert '\n'.join(line for line in con.iterdump() if not line.startswith('INSERT INTO "_wl_attempt"'))==before
        con.execute('DROP TRIGGER reject_session')
    # Actual Meteor services.password object; fixture independently checked by Go.
    meteor=dict(password=dict(bcrypt='$2b$04$......................b8CYpLYfgS/XMWDCU3/.oCRJREnOf3y',reset=dict(token='preserve-reset')),resume=dict(loginTokens=[dict(hashedToken='meteor-resume-not-private')]))
    with sqlite3.connect(db) as con:con.execute('UPDATE users SET services_json=? WHERE id=?',(json.dumps(meteor),uid))
    response=request('POST','/sign-in',dict(username=user,password=password))
    assert response[0]==302
    meteor_web=parse_qs(urlsplit(response[1]['Location']).query)['sessionId'][0]
    response=request('POST','/users/login',dict(username=user,password=password))
    assert response[0]==200
    meteor_api=json.loads(response[2])['token']
    assert request('GET','/api/user?token='+meteor_api)[0]==200
    assert request('POST','/users/login',dict(username=user,password='wrong'))[0]==401
    with sqlite3.connect(db) as con:
        assert json.loads(con.execute('SELECT services_json FROM users WHERE id=?',(uid,)).fetchone()[0])==meteor
    # Current Meteor gives Argon2 precedence. A stale bcrypt must not authorize login.
    meteor['password']['argon2']='$argon2id$unsupported-test'
    with sqlite3.connect(db) as con:con.execute('UPDATE users SET services_json=? WHERE id=?',(json.dumps(meteor),uid))
    assert request('POST','/users/login',dict(username=user,password=password))[0]==401
    response=request('POST','/sign-in',dict(username=user,password=password))
    assert response[0]==200 and LOGIN_DENIAL in response[2]
    assert request('GET','/api/user?token='+meteor_api)[0]==401
    assert request('GET','/designer?sessionId='+meteor_web)[0]==302
    # Version-19 Argon2 is the active credential even when bcrypt is present.
    meteor['password']['argon2']='$argon2id$v=19$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$eL9VAPxb5H9dbhpqPyL7Z7AkFp72MImsQmo94Yh0kAY'
    with sqlite3.connect(db) as con:con.execute('UPDATE users SET services_json=? WHERE id=?',(json.dumps(meteor),uid))
    response=request('POST','/sign-in',dict(username=user,password=password))
    assert response[0]==302
    argon_web=parse_qs(urlsplit(response[1]['Location']).query)['sessionId'][0]
    response=request('POST','/users/login',dict(username=user,password=password))
    assert response[0]==200
    argon_api=json.loads(response[2])['token']
    assert request('GET','/api/user?token='+argon_api)[0]==200
    assert request('GET','/api/user?token='+argon_web)[0]==200
    assert request('POST','/users/login',dict(username=user,password='wrong'))[0]==401
    with sqlite3.connect(db) as con:
        assert json.loads(con.execute('SELECT services_json FROM users WHERE id=?',(uid,)).fetchone()[0])==meteor
    # Exceeding a verification budget never falls back to otherwise correct bcrypt.
    meteor['password']['argon2']=meteor['password']['argon2'].replace('m=32','m=65537')
    with sqlite3.connect(db) as con:con.execute('UPDATE users SET services_json=? WHERE id=?',(json.dumps(meteor),uid))
    assert request('POST','/users/login',dict(username=user,password=password))[0]==401
    response=request('POST','/sign-in',dict(username=user,password=password))
    assert response[0]==200 and LOGIN_DENIAL in response[2]
    assert request('GET','/api/user?token='+argon_api)[0]==401
    assert request('GET','/designer?sessionId='+argon_web)[0]==302
    legacy_argon='$argon2id$v=16$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$shmop4+uHY9Bws9kfsVWl7IO3PvjjDUJpB4nB4wjPno'
    meteor['password'].pop('bcrypt',None)
    for encoded in [legacy_argon,legacy_argon.replace('$v=16','')]:
        meteor['password']['argon2']=encoded
        with sqlite3.connect(db) as con:con.execute('UPDATE users SET services_json=? WHERE id=?',(json.dumps(meteor),uid))
        assert request('POST','/sign-in',dict(username=user,password=password))[0]==302
        response=request('POST','/users/login',dict(username=user,password=password))
        assert response[0]==200
        token=json.loads(response[2])['token']
        assert request('GET','/api/user?token='+token)[0]==200
        assert request('POST','/users/login',dict(username=user,password='wrong'))[0]==401
        with sqlite3.connect(db) as con:
            assert json.loads(con.execute('SELECT services_json FROM users WHERE id=?',(uid,)).fetchone()[0])==meteor
    # An imported factor policy must not be bypassed through either password route.
    policy_services=json.loads(json.dumps(meteor))
    for factor in [dict(type='otp',secret='JBSWY3DPEHPK3PXP'),dict(type='unknown',secret='fixture'),'malformed']:
        before=request('POST','/users/login',dict(username=user,password=password));assert before[0]==200
        policy_api=json.loads(before[2])['token']
        before=request('POST','/sign-in',dict(username=user,password=password));assert before[0]==302
        policy_web=parse_qs(urlsplit(before[1]['Location']).query)['sessionId'][0]
        blocked=json.loads(json.dumps(policy_services));blocked['twoFactorAuthentication']=factor
        with sqlite3.connect(db) as con:
            con.execute('UPDATE users SET services_json=? WHERE id=?',(json.dumps(blocked),uid))
            count=con.execute('SELECT count(*) FROM login_tokens WHERE userId=?',(uid,)).fetchone()[0]
        assert request('POST','/users/login',dict(username=user,password=password))[0]==401
        denied=request('POST','/sign-in',dict(username=user,password=password))
        assert denied[0]==200 and LOGIN_DENIAL in denied[2]
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT count(*) FROM login_tokens WHERE userId=?',(uid,)).fetchone()[0]==count
            assert json.loads(con.execute('SELECT services_json FROM users WHERE id=?',(uid,)).fetchone()[0])==blocked
        assert request('GET','/api/user?token='+policy_api)[0]==401
        assert request('GET','/designer?sessionId='+policy_web)[0]==302
        with sqlite3.connect(db) as con:con.execute('UPDATE users SET services_json=? WHERE id=?',(json.dumps(policy_services),uid))
        assert request('GET','/api/user?token='+policy_api)[0]==401
        assert request('GET','/designer?sessionId='+policy_web)[0]==302
    pending=json.loads(json.dumps(policy_services));pending['twoFactorAuthentication']=dict(secret='pending')
    with sqlite3.connect(db) as con:con.execute('UPDATE users SET services_json=? WHERE id=?',(json.dumps(pending),uid))
    assert request('POST','/users/login',dict(username=user,password=password))[0]==200
    print('PASS: active/unknown/malformed factors block password-only web/API login and observed old tokens stay revoked; pending setup remains allowed')
    print('PASS: legacy explicit-v16/versionless Argon2 web/API login and unchanged credential metadata')
    print('PASS: actual Meteor Argon2 web/API logins, metadata preservation, credential-bound tokens and over-budget/stale-bcrypt denial')
    print('PASS: actual Meteor bcrypt web/API logins, unknown service preservation, credential-bound tokens and Argon2 precedence denial')
    print('PASS: disabled web/API logins and live tokens denied, panel revocation survives re-enable, fresh nonces and token persistence failures')
