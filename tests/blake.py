"""BLAKE2b against hashlib and Argon2 H' against the actual Go helper."""
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
tools=root.parents[1]
crypto=Path(os.environ.get('CRYPTO_SRC',str(tools/'go/gomodcache/golang.org/x/crypto@v0.59.0')))
assert crypto.is_dir(),'Set CRYPTO_SRC to cached golang.org/x/crypto source'
with tempfile.TemporaryDirectory(prefix='wlblake-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    local=tmp/'crypto';local.mkdir()
    shutil.copy2(crypto/'go.mod',local/'go.mod')
    shutil.copy2(crypto/'LICENSE',local/'LICENSE')
    for package in ['argon2','blake2b']:shutil.copytree(crypto/package,local/package)
    (tmp/'patch').mkdir()
    (tmp/'go.mod').write_text('module wlprobe\ngo 1.26.0\nrequire golang.org/x/crypto v0.59.0\nreplace golang.org/x/crypto => '+str(local)+'\n')
    (tmp/'main.go').write_text('package main\nimport("encoding/json";"encoding/hex";"os";"golang.org/x/crypto/argon2")\nfunc main(){var in struct{Data string;Size int};if err:=json.NewDecoder(os.Stdin).Decode(&in);err!=nil{panic(err)};data,err:=hex.DecodeString(in.Data);if err!=nil{panic(err)};json.NewEncoder(os.Stdout).Encode(hex.EncodeToString(argon2.WeliteProbe(data,in.Size)))}\n')
    (tmp/'patch/probe.go').write_text('package argon2\nfunc WeliteProbe(in []byte,n int) []byte{out:=make([]byte,n);blake2bHash(out,in);return out}\n')
    (tmp/'overlay.json').write_text(json.dumps({'Replace':{str(local/'argon2/wlprobe.go'):str(tmp/'patch/probe.go')}}))
    settings=dict(os.environ,GOPROXY='off',GOSUMDB='off',GOTOOLCHAIN='local',GOCACHE=str(tools/'go/gocache'),GOPATH=str(tools/'go/gopath'),GOMODCACHE=str(tools/'go/gomodcache'))
    built=subprocess.run([os.environ.get('GO','go'),'build','-overlay',str(tmp/'overlay.json'),'-o',str(tmp/'oracle'),'.'],cwd=tmp,env=settings,capture_output=True,text=True)
    assert built.returncode==0,built.stdout+built.stderr
    def oracle(data,size):return json.loads(subprocess.check_output([str(tmp/'oracle')],input=json.dumps(dict(Data=data.hex(),Size=size)),text=True))
    cases=[bytes((i*37)%256 for i in range(n)) for n in [0,1,2,63,64,65,127,128,129,255,256,257,1023,1024,1025]]
    cases+=['日本語\0tail 🔑'.encode(),bytes(range(256))*8]
    for checked in [False,True]:
        out=tmp/('checked' if checked else 'normal');out.mkdir()
        built=subprocess.run([os.environ.get('FPC','fpc'),*(['-Cr','-Co'] if checked else []),'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/blake.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        def run(mode,data,size):return subprocess.check_output([str(out/'blake'),mode,str(size)],input=data.hex()+'\n',text=True).strip()
        for data in cases:
            for size in [1,2,16,32,63,64]:assert run('plain',data,size)==hashlib.blake2b(data,digest_size=size).hexdigest(),(checked,len(data),size)
            for size in [1,32,64,65,95,96,97,127,128,129,255,256,257,1024]:assert run('argon',data,size)==oracle(data,size),(checked,len(data),size)
        assert run('plain',b'',0)=='error' and run('plain',b'',65)=='error'
        assert run('argon',b'',0)=='error' and run('argon',b'',-1)=='error'
        print('PASS: BLAKE2b hashlib and actual Go Argon2 H\' oracle, block/output boundaries, binary/Unicode/NUL and '+('checked' if checked else 'normal')+' arithmetic')
