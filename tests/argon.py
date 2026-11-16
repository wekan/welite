"""Argon2 v1.3 against the actual maintained Go deriveKey implementation."""
import json
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
        print('PASS: Argon2d/i/id RFC tags and maintained Go oracle, lanes/passes/memory rounding/address boundaries, secrets/AD, Unicode/NUL, resource denial and '+('checked' if checked else 'normal')+' arithmetic')
