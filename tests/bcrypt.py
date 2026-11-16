"""Portable bcrypt against the maintained Go implementation, without network access."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
tools=root.parents[1]
crypto=Path(os.environ.get('CRYPTO_SRC',str(tools/'go/gomodcache/golang.org/x/crypto@v0.59.0')))
assert crypto.is_dir(),'Set CRYPTO_SRC to cached golang.org/x/crypto source'
with tempfile.TemporaryDirectory(prefix='wlbc-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    (tmp/'go.mod').write_text('module wlprobe\ngo 1.26.0\nrequire golang.org/x/crypto v0.59.0\nreplace golang.org/x/crypto => '+str(crypto)+'\n')
    (tmp/'main.go').write_bytes((root/'tests/bcrypt.go').read_bytes())
    settings=dict(os.environ,GOPROXY='off',GOSUMDB='off',GOTOOLCHAIN='local',GOCACHE=str(tools/'go/gocache'),GOPATH=str(tools/'go/gopath'),GOMODCACHE=str(tools/'go/gomodcache'))
    subprocess.run([os.environ.get('GO','go'),'build','-o',str(tmp/'oracle'),'.'],cwd=tmp,env=settings,check=True,capture_output=True)
    def oracle(**values):return json.loads(subprocess.check_output([str(tmp/'oracle')],input=json.dumps(values),text=True))
    for checks in [False,True]:
        out=tmp/('checked' if checks else 'normal');out.mkdir()
        flags=['-Cr','-Co'] if checks else []
        built=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/bcrypt.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        def run(mode,key,stored):return subprocess.check_output([str(out/'bcrypt'),mode,key.encode().hex(),stored],text=True).strip()
        passwords=['','a','password','日本語 ä 🔑','a\0b','x'*71,'x'*72,hashlib.sha256('Meteor 日本語'.encode()).hexdigest()]
        for index,password in enumerate(passwords):
            cost=4+index%3
            expected=oracle(Password=password,Cost=cost)
            actual=run('hash',password,expected[:29])
            assert actual==expected,(password,actual,expected)
            assert oracle(Password=password,Hash=actual) is True
            assert run('verify',password,expected)=='yes'
            assert run('verify','wrong',expected)=='no'
            for version in ['2a','2b','2y']:
                variant='$'+version+expected[3:]
                assert run('verify',password,variant)=='yes'
            for bad in ['',expected[:-1],expected+'x',expected.replace('$2a$','$2x$').replace('$2b$','$2x$'),expected[:4]+'03'+expected[6:],expected[:4]+'32'+expected[6:],expected[:10]+'!'+expected[11:],expected[:-1]+'!']:
                assert run('verify',password,bad)=='no',bad
        assert run('verify','x'*73,expected)=='no'
        # Reject noncanonical unused salt/hash bits before doing expensive work.
        assert run('verify',password,expected[:28]+'B'+expected[29:])=='no'
        assert oracle(Password=hashlib.sha256(b'test-password').hexdigest(),Hash='$2b$04$......................b8CYpLYfgS/XMWDCU3/.oCRJREnOf3y') is True
        plaintext='Meteor 日本語 🔑'+'x'*100+'\0tail'
        digest=hashlib.sha256(plaintext.encode()).hexdigest()
        meteor_hash=oracle(Password=digest,Cost=10)
        envelope=json.dumps(dict(bcrypt=meteor_hash))
        assert run('password',plaintext,envelope)=='yes'
        assert run('password','wrong',envelope)=='no'
        assert run('password',digest,envelope)=='no','A digest sent as plaintext must be hashed again'
        for invalid in [dict(argon2='$argon2id$unsupported',bcrypt=meteor_hash),dict(bcrypt=1),dict(bcrypt=None),{},dict(argon2=True,bcrypt=meteor_hash)]:
            assert run('password',plaintext,json.dumps(invalid))=='no'
        assert run('password',plaintext,'{"bcrypt":'+json.dumps(meteor_hash)+',"bcrypt":'+json.dumps(meteor_hash)+'}')=='no'
        created=[run('meteor',plaintext,'') for _ in range(2)]
        assert created[0]!=created[1]
        for value in created:
            assert oracle(Password=digest,Hash=json.loads(value)['bcrypt']) is True
            assert run('password',plaintext,value)=='yes'
        legacy=run('legacy',plaintext,'')
        assert run('password',plaintext,legacy)=='yes' and run('password','wrong',legacy)=='no'
        print('PASS: bcrypt Go oracle, costs 4-6, 2a/2b/2y, Unicode/NUL/72-byte boundaries, SHA256/Meteor envelopes, new/legacy credentials, malformed denial and '+('checked' if checks else 'normal')+' arithmetic')
