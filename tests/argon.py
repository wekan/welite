"""Argon2 v1.3 against the actual maintained Go deriveKey implementation."""
import json
import base64
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
tools=root.parents[1]
crypto=Path(os.environ.get('CRYPTO_SRC',str(tools/'go/gomodcache/golang.org/x/crypto@v0.59.0')))
with tempfile.TemporaryDirectory(prefix='wlargon-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory);local=tmp/'crypto';local.mkdir();(tmp/'patch').mkdir()
    for file in ['go.mod','LICENSE']:shutil.copy2(crypto/file,local/file)
    for package in ['argon2','blake2b']:shutil.copytree(crypto/package,local/package)
    (tmp/'go.mod').write_text('module wlprobe\ngo 1.26.0\nrequire golang.org/x/crypto v0.59.0\nreplace golang.org/x/crypto => '+str(local)+'\n')
    (tmp/'main.go').write_text('package main\nimport("encoding/json";"encoding/hex";"os";"golang.org/x/crypto/argon2")\nfunc main(){var in struct{Mode int;Passes,Memory,Lanes,Size uint32;Password,Salt,Secret,Data []byte};if err:=json.NewDecoder(os.Stdin).Decode(&in);err!=nil{panic(err)};json.NewEncoder(os.Stdout).Encode(hex.EncodeToString(argon2.WeliteProbe(in.Mode,in.Password,in.Salt,in.Secret,in.Data,in.Passes,in.Memory,in.Lanes,in.Size)))}\n')
    (tmp/'patch/probe.go').write_text('package argon2\nfunc WeliteProbe(mode int,password,salt,secret,data []byte,t,m,p,n uint32) []byte{return deriveKey(mode,password,salt,secret,data,t,m,uint8(p),n)}\n')
    (tmp/'overlay.json').write_text(json.dumps({'Replace':{str(local/'argon2/wlprobe.go'):str(tmp/'patch/probe.go')}}))
    env=dict(os.environ,GOPROXY='off',GOSUMDB='off',GOTOOLCHAIN='local',GOCACHE=str(tools/'go/gocache'),GOPATH=str(tools/'go/gopath'),GOMODCACHE=str(tools/'go/gomodcache'))
    built=subprocess.run([os.environ.get('GO','go'),'build','-overlay',str(tmp/'overlay.json'),'-o',str(tmp/'oracle'),'.'],cwd=tmp,env=env,capture_output=True,text=True)
    assert built.returncode==0,built.stdout+built.stderr
    def oracle(mode,password,salt,secret,data,t,m,p,n):
        import base64
        value=dict(Mode=mode,Passes=t,Memory=m,Lanes=p,Size=n,**{k:base64.b64encode(v).decode() for k,v in dict(Password=password,Salt=salt,Secret=secret,Data=data).items()})
        return json.loads(subprocess.check_output([str(tmp/'oracle')],input=json.dumps(value),text=True))
    # RFC 9106 section 5, including secret and associated data.
    rfc_tags=['512b391b6f1162975371d30919734294f868e3be3984f3c1a13a4db9fabe4acb',
              'c814d9d1dc7f37aa13f0d77f2494bda1c8de6b016dd388d29952a4c4672b6ce8',
              '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659']
    vectors=[]
    for mode in range(3):
        for t,m,p,n in [(1,8,1,4),(1,9,1,32),(2,32,1,32),(3,32,4,32),(2,37,3,65),(2,1024,2,64),(1,1025,1,96),(2,19456,1,32)]:
            password='日本語\0password 🔑'.encode();salt=bytes(range(16));secret=b'\0secret';data=b'associated\0data'
            args=(mode,password,salt,secret,data,t,m,p,n);vectors.append((args,oracle(*args)))
        args=(mode,b'\1'*32,b'\2'*16,b'\3'*8,b'\4'*12,3,32,4,32)
        assert oracle(*args)==rfc_tags[mode]
        vectors.append((args,rfc_tags[mode]))
    args=(2,b'password',b'salt-16-byte-long',b'',b'',3,65536,4,32)
    vectors.append((args,oracle(*args)))
    for checked in [False,True]:
        out=tmp/('checked' if checked else 'normal');out.mkdir()
        built=subprocess.run([os.environ.get('FPC','fpc'),*(['-Cr','-Co'] if checked else []),'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/argon.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        def run(args):
            mode,password,salt,secret,data,t,m,p,n=args
            return subprocess.check_output([str(out/'argon'),str(mode),str(t),str(m),str(p),str(n)],input='\n'.join(v.hex() for v in [password,salt,secret,data])+'\n',text=True,timeout=30).strip()
        for args,expected in vectors:assert run(args)==expected,(checked,args,run(args),expected)
        for mode,t,m,p,n in [(-1,1,32,1,32),(3,1,32,1,32),(2,0,32,1,32),(2,17,32,1,32),(2,1,65537,1,32),(2,1,32,0,32),(2,1,32,65,32),(2,1,7,1,32),(2,1,32,1,3),(2,1,32,1,1025)]:
            assert run((mode,b'p',b'12345678',b'',b'',t,m,p,n))=='error'
        assert run((2,b'p',b'short',b'',b'',1,32,1,32))=='error'
        if os.name=='posix':
            import resource
            def low_memory():resource.setrlimit(resource.RLIMIT_AS,(48*1024*1024,48*1024*1024))
            denied=subprocess.run([str(out/'argon'),'2','1','65536','1','32'],input='70\n3132333435363738\n\n\n',text=True,capture_output=True,preexec_fn=low_memory,timeout=30)
            assert denied.returncode==0 and denied.stdout.strip()=='error',(denied.returncode,denied.stdout,denied.stderr)
        built=subprocess.run([os.environ.get('FPC','fpc'),*(['-Cr','-Co'] if checked else []),'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/phc.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        credential_env=dict(os.environ)
        for variable in ['WELITE_ARGON_MEMORY_KIB','WELITE_ARGON_PASSES','WELITE_ARGON_LANES','WELITE_ARGON_KEY_BYTES']:credential_env.pop(variable,None)
        def verify(password,record,mode='raw',overrides=None):
            value=password if isinstance(password,bytes) else password.encode()
            return subprocess.check_output([str(out/'phc'),mode],input=value.hex()+'\n'+record+'\n',text=True,env=dict(credential_env,**(overrides or {})),timeout=30).strip()
        def b64(value):return base64.b64encode(value).decode().rstrip('=')
        def encoded(mode,password,data=b'',m=32,t=2,p=1,n=32):
            salt=bytes(range(16));tag=bytes.fromhex(oracle(mode,password,salt,b'',data,t,m,p,n))
            params=f'm={m},t={t},p={p}'+(',data='+b64(data) if data else '')
            return '$'+['argon2d','argon2i','argon2id'][mode]+'$v=19$'+params+'$'+b64(salt)+'$'+b64(tag)
        plaintext='Meteor 日本語 🔑 '+('long-password-'*8)+'\0tail'
        digest=hashlib.sha256(plaintext.encode()).hexdigest().encode()
        for variant in range(3):
            for associated in [b'',b'context\0data']:
                record=encoded(variant,digest,associated)
                assert verify(digest,record)=='yes'
                assert verify(plaintext,record)=='no'
                envelope=json.dumps(dict(argon2=record,bcrypt='$2b$04$stale',reset=dict(token='retain')))
                assert verify(plaintext,envelope,'meteor')=='yes'
                assert verify('wrong',envelope,'meteor')=='no'
        record=encoded(2,digest,m=19456)
        assert verify(plaintext,json.dumps(dict(argon2=record)),'meteor')=='yes'
        record=encoded(2,digest)
        for altered in [record.replace('v=19','v=16'),record.replace('$v=19',''),record.replace('argon2id','argon2x'),record+'$',record+'=',record.replace('m=32','m=032'),record.replace('m=32','m=-32'),record.replace('m=32','m=0'),record.replace('m=32','m=4294967296'),record.replace('m=32','m=65537'),record.replace('t=2','t=17'),record.replace('p=1','p=0'),record.replace('p=1','p=65'),record.replace('m=32','m=32,m=32'),record.replace('m=32,',''),record.replace('p=1','x=1'),record.replace('p=1','p=1,keyid=AA'),record.replace('p=1','p=1,data=A'),record[:-1]+'B']:
            assert verify(digest,altered)=='no',altered
        parts=record.split('$')
        for salt,tag in [(b'1234567',b'x'*32),(bytes(range(16)),b'xxx'),(bytes(range(16)),b'x'*1025)]:
            assert verify(digest,'$'.join(parts[:4]+[b64(salt),b64(tag)]))=='no'
        for variable,value in [('WELITE_ARGON_MEMORY_KIB','16'),('WELITE_ARGON_PASSES','1'),('WELITE_ARGON_KEY_BYTES','16'),('WELITE_ARGON_LANES','0'),('WELITE_ARGON_MEMORY_KIB','invalid'),('WELITE_ARGON_MEMORY_KIB','4294967296')]:
            assert verify(digest,record,overrides={variable:value})=='no'
        assert verify(digest,record,overrides=dict(WELITE_ARGON_MEMORY_KIB='32',WELITE_ARGON_PASSES='2',WELITE_ARGON_LANES='1',WELITE_ARGON_KEY_BYTES='32'))=='yes'
        raised=encoded(2,digest,m=65540,t=1)
        assert verify(digest,raised)=='no'
        assert verify(digest,raised,overrides=dict(WELITE_ARGON_MEMORY_KIB='65540'))=='yes'
        assert verify(digest,record+'$'*10000)=='no'
        assert verify(digest,record.replace('m=32','m=32'+',x=1'*10000))=='no'
        assert verify(digest,'A'*(1024*1024+1))=='no'
        # Correct bcrypt for test-password must not rescue a different Argon2 password.
        bcrypt='$2b$04$......................b8CYpLYfgS/XMWDCU3/.oCRJREnOf3y'
        assert verify('test-password',json.dumps(dict(argon2=record,bcrypt=bcrypt)),'meteor')=='no'
        # Shared deterministic fixture used by real HTTP and FerretDB tests.
        fixture=encoded(2,hashlib.sha256(b'test-password').hexdigest().encode())
        assert fixture=='$argon2id$v=19$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$eL9VAPxb5H9dbhpqPyL7Z7AkFp72MImsQmo94Yh0kAY'
        print('PASS: Argon2 PHC/Meteor envelopes, associated data, long UTF-8, malformed/duplicate/version denial, configurable budgets and stale bcrypt refusal')
        print('PASS: Argon2d/i/id RFC tags and maintained Go oracle, lanes/passes/memory rounding/address boundaries, secrets/AD, Unicode/NUL, resource denial and '+('checked' if checked else 'normal')+' arithmetic')
