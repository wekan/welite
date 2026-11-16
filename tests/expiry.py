"""Atomic shared/local expiry, scoped links and legacy identity preservation."""
import copy
from datetime import datetime,timezone
import subprocess
import time
from wire import DateMs,Long,Binary,encode

def run(out,db,client,sql,physical,password,env,meteor_hash,local_hash):
    def q(value):return "'"+value.replace("'","''")+"'"
    def iso(ms):return datetime.fromtimestamp(ms//1000,timezone.utc).replace(microsecond=(ms%1000)*1000).isoformat(timespec='milliseconds').replace('+00:00','Z')
    def issue(uid,raw):
        assert subprocess.check_output([str(out/'factor/factor'),str(db),'api',uid,'test-password','',raw],env=env,text=True).strip()=='yes'
    def check(raw):return subprocess.check_output([str(out/'factor/factor'),str(db),'check',raw],env=env,text=True).strip()
    def sweep(at):return subprocess.check_output([str(out/'sweep/sweep'),str(db),str(at)],env=env,text=True).strip()
    client.command({'insert':'users','documents':[dict(_id=uid,username=uid,services=dict(password=password),extra=Binary(b'expiry',4)) for uid in ['cleanup-user','cleanup-other']]})
    dead=['expired-hash','expired-raw','expired-both','legacy-unknown']
    for raw in dead+['active-sibling']:issue('cleanup-user',raw)
    issue('cleanup-other','other-active')
    source=client.find('users','cleanup-user')[0]
    records=source['services']['resume']['loginTokens']
    raw_entry=next(entry for entry in records if entry.get('hashedToken')==meteor_hash('expired-raw'))
    del raw_entry['hashedToken'];raw_entry['token']='expired-raw';raw_entry['keep']=Long(9007199254740993)
    records.append(dict(token='expired-both',when=DateMs(int(time.time()*1000)),extra=Long(9007199254740993)))
    records.extend(['opaque',None,123,dict(token=123,when=DateMs(int(time.time()*1000)))])
    client.command({'update':'users','updates':[dict(q=dict(_id='cleanup-user'),u={'$set':{'services.resume.loginTokens':records}})]})
    now=int(time.time()*1000)
    for raw in dead:
        assert sql('UPDATE login_tokens SET expiresAt='+q(iso(now))+' WHERE hashedToken='+q(local_hash(raw))+';','exec')=='ok'
    assert sql('UPDATE _wl_pair SET sharedHash=NULL WHERE hashedToken='+q(local_hash('legacy-unknown'))+';','exec')=='ok'
    # Private web/orphan rows also keep identity before deletion, without publishing.
    for raw in ['web-expired','orphan-expired']:
        assert sql('INSERT INTO login_tokens VALUES('+','.join(q(v) for v in [local_hash(raw),'cleanup-user',iso(now-1),iso(now)])+');','exec')=='ok'
    assert sql('INSERT INTO authmeta VALUES('+q(local_hash('web-expired'))+",'fixture','fixture','web');",'exec')=='ok'
    assert sql("PRAGMA foreign_keys=OFF; INSERT INTO authmeta VALUES('orphan-meta','fixture','fixture','api'); PRAGMA foreign_keys=ON;",'exec')=='ok'
    assert sql('DELETE FROM _wl_seen WHERE hashedToken='+q(local_hash('orphan-expired'))+';','exec')=='ok'
    assert sql('UPDATE _wl_sweep SET lastAt=-600000;','exec')=='ok'
    names=['login_tokens','authmeta','_wl_pair','_wl_seen','_wl_sweep','_wl_authsrc','_wl_otp','_wl_enrol']
    def snapshot():return {name:sql('SELECT * FROM '+q(name)+' ORDER BY 1;') for name in names}
    before=snapshot();source=client.find('users','cleanup-user')[0];other=encode(client.find('users','cleanup-other')[0])
    triggers=[
        'BEFORE UPDATE ON '+q(physical)+" WHEN OLD._ferretdb_sjson->>'_id'='cleanup-user'",
        'BEFORE DELETE ON authmeta',
        'BEFORE DELETE ON login_tokens',
        'BEFORE INSERT ON _wl_pair',
        'BEFORE INSERT ON _wl_seen',
    ]
    for clause in triggers:
        assert sql('CREATE TRIGGER fail_expiry '+clause+' BEGIN SELECT RAISE(IGNORE); END;','exec')=='ok'
        assert sweep(now)=='no',clause
        assert snapshot()==before,('Partial private expiry commit',clause)
        assert encode(client.find('users','cleanup-user')[0])==encode(source),('Partial source expiry commit',clause)
        assert encode(client.find('users','cleanup-other')[0])==other
        assert sql('DROP TRIGGER fail_expiry;','exec')=='ok'
    assert sweep(now)=='yes'
    expected=copy.deepcopy(source)
    known=dead[:3]
    expected['services']['resume']['loginTokens']=[entry for entry in expected['services']['resume']['loginTokens'] if not isinstance(entry,dict) or (entry.get('hashedToken') not in [meteor_hash(raw) for raw in known] and entry.get('token') not in known)]
    assert encode(client.find('users','cleanup-user')[0])==encode(expected),'Cleanup damaged retained source/BSON'
    assert encode(client.find('users','cleanup-other')[0])==other,'Cleanup revoked another account'
    for raw in dead+['web-expired','orphan-expired']:
        key=local_hash(raw)
        assert sql('SELECT count(*) FROM login_tokens WHERE hashedToken='+q(key)+';')==[['0']]
        assert sql('SELECT count(*) FROM authmeta WHERE hashedToken='+q(key)+';')==[['0']]
        assert sql('SELECT count(*) FROM _wl_seen WHERE hashedToken='+q(key)+';')==[['1']]
        assert sql('SELECT userId FROM _wl_pair WHERE hashedToken='+q(key)+';')==[['cleanup-user']]
    assert sql("SELECT count(*) FROM authmeta WHERE hashedToken='orphan-meta';")==[['0']]
    assert sql('SELECT * FROM _wl_otp ORDER BY 1;')==before['_wl_otp']
    assert sql('SELECT * FROM _wl_enrol ORDER BY 1;')==before['_wl_enrol']
    assert check('active-sibling')=='yes' and check('other-active')=='yes'
    assert check('expired-hash')=='no'
    # Unknown legacy hash stays on Meteor's own expiry schedule until raw observation.
    assert any(isinstance(entry,dict) and entry.get('hashedToken')==meteor_hash('legacy-unknown') for entry in client.find('users','cleanup-user')[0]['services']['resume']['loginTokens'])
    assert check('legacy-unknown')=='no'
    expected['services']['resume']['loginTokens']=[entry for entry in expected['services']['resume']['loginTokens'] if not isinstance(entry,dict) or entry.get('hashedToken')!=meteor_hash('legacy-unknown')]
    assert encode(client.find('users','cleanup-user')[0])==encode(expected)
    assert check('active-sibling')=='yes'
    # The running idle worker executes the same private cleanup, without a request.
    issue('cleanup-user','idle-expired')
    assert sql('UPDATE login_tokens SET expiresAt='+q(iso(int(time.time()*1000)-1))+' WHERE hashedToken='+q(local_hash('idle-expired'))+'; UPDATE _wl_sweep SET lastAt=-600000;','exec')=='ok'
    worker=subprocess.Popen([str(out/'maint/maint'),str(db)],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        assert worker.stdout.readline().strip()=='ready'
        for _ in range(200):
            if sql('SELECT count(*) FROM login_tokens WHERE hashedToken='+q(local_hash('idle-expired'))+';')==[['0']]:break
            assert worker.poll() is None;time.sleep(.05)
        else:raise AssertionError('Idle worker did not clean an expired private credential')
        assert encode(client.find('users','cleanup-user')[0])==encode(expected)
        output,errors=worker.communicate('stop\n',timeout=10)
        assert worker.returncode==0 and output.strip()=='stopped',(output,errors)
    finally:
        if worker.poll() is None:worker.kill();worker.wait()
    assert check('active-sibling')=='yes' and check('other-active')=='yes'
    client.command({'delete':'users','deletes':[dict(q=dict(_id=uid),limit=1) for uid in ['cleanup-user','cleanup-other']]})
