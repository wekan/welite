"""Argon2 v16/v19 against the official C reference, with legacy PHC login tests."""
import base64
import ctypes as c
import hashlib
import hmac
import json
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
tools=root.parents[1]
source=Path(os.environ.get('ARGON2_SRC',str(tools/'tmp/wlargref/argon2')))
assert (source/'src/ref.c').is_file(),'Set ARGON2_SRC to the official P-H-C/phc-winner-argon2 source'
class Context(c.Structure):
    _fields_=[(name,typ) for name,typ in [('out',c.c_void_p),('outlen',c.c_uint32),('pwd',c.c_void_p),('pwdlen',c.c_uint32),('salt',c.c_void_p),('saltlen',c.c_uint32),('secret',c.c_void_p),('secretlen',c.c_uint32),('ad',c.c_void_p),('adlen',c.c_uint32),('t',c.c_uint32),('m',c.c_uint32),('lanes',c.c_uint32),('threads',c.c_uint32),('version',c.c_uint32),('alloc',c.c_void_p),('free',c.c_void_p),('flags',c.c_uint32)]]
with tempfile.TemporaryDirectory(prefix='wlargv-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    built=subprocess.run([os.environ.get('CC','cc'),'-O2','-fPIC','-shared','-DARGON2_NO_THREADS','-I'+str(source/'include'),'-I'+str(source/'src'),*[str(source/'src'/name) for name in ['argon2.c','core.c','encoding.c','ref.c','blake2/blake2b.c']],'-o',str(tmp/'ref.so')],capture_output=True,text=True)
    assert built.returncode==0,built.stdout+built.stderr
    lib=c.CDLL(str(tmp/'ref.so'));lib.argon2_ctx.argtypes=[c.POINTER(Context),c.c_int];lib.argon2_ctx.restype=c.c_int
    def oracle(mode,password,salt,secret,data,t,m,p,n,version):
        out=c.create_string_buffer(n);pwd=c.create_string_buffer(password);s=c.create_string_buffer(salt);key=c.create_string_buffer(secret);ad=c.create_string_buffer(data)
        context=Context(c.addressof(out),n,c.addressof(pwd),len(password),c.addressof(s),len(salt),c.addressof(key),len(secret),c.addressof(ad),len(data),t,m,p,1,version,None,None,0)
        status=lib.argon2_ctx(c.byref(context),mode);assert status==0,status
        return out.raw.hex()
    vectors=[]
    for version in [16,19]:
        for mode in range(3):
            for t,m,p,n in [(1,8,1,4),(2,32,1,32),(3,32,4,32),(2,37,3,65),(2,1024,2,32)]:
                args=(mode,'日本語\0🔑'.encode(),bytes(range(16)),b'secret\0',b'associated\0',t,m,p,n,version)
                vectors.append((args,oracle(*args)))
    for checked in [False,True]:
        out=tmp/('checked' if checked else 'normal');out.mkdir()
        for program in ['argon','phc']:
            built=subprocess.run([os.environ.get('FPC','fpc'),*(['-Cr','-Co'] if checked else []),'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests'/f'{program}.lpr')],capture_output=True,text=True)
            assert built.returncode==0,built.stdout+built.stderr
        for args,expected in vectors:
            mode,password,salt,secret,data,t,m,p,n,version=args
            actual=subprocess.check_output([str(out/'argon'),str(mode),str(t),str(m),str(p),str(n),str(version)],input='\n'.join(v.hex() for v in [password,salt,secret,data])+'\n',text=True,timeout=30).strip()
            assert actual==expected,(checked,args,actual,expected)
        settings=dict(os.environ)
        for variable in ['WELITE_ARGON_MEMORY_KIB','WELITE_ARGON_PASSES','WELITE_ARGON_LANES','WELITE_ARGON_KEY_BYTES','WELITE_ARGON_SECRET_FILE']:settings.pop(variable,None)
        def verify(password,record,mode='raw'):
            return subprocess.check_output([str(out/'phc'),mode],input=password.hex()+'\n'+record+'\n',env=settings,text=True,timeout=30).strip()
        def b64(value):return base64.b64encode(value).decode().rstrip('=')
        fixture=None
        plaintext='Legacy 日本語 '+('long-'*20)+'\0tail';digest=hashlib.sha256(plaintext.encode()).hexdigest().encode()
        for mode in range(3):
            for version in [16,19]:
                for data in [b'',b'context\0']:
                    salt=bytes(range(16));tag=bytes.fromhex(oracle(mode,digest,salt,b'',data,2,32,1,32,version))
                    params='m=32,t=2,p=1'+(',data='+b64(data) if data else '')
                    phc='$'+['argon2d','argon2i','argon2id'][mode]+'$v='+str(version)+'$'+params+'$'+b64(salt)+'$'+b64(tag)
                    assert verify(digest,phc)=='yes'
                    assert verify(plaintext.encode(),json.dumps(dict(argon2=phc)),'meteor')=='yes'
                    assert verify(b'wrong',phc)=='no'
                    for wrong_version in [15,17,18,20,version^3]:assert verify(digest,phc.replace('$v='+str(version),'$v='+str(wrong_version)))=='no'
                    versionless=phc.replace('$v='+str(version),'')
                    assert verify(digest,versionless)==('yes' if version==16 else 'no')
        for version in [0,15,17,20,255,256,4294967295]:
            denied=subprocess.check_output([str(out/'argon'),'2','1','32','1','32',str(version)],input='70\n3132333435363738\n\n\n',text=True,timeout=5).strip()
            assert denied=='error',version
        secret=b'operator\0secret\n';secret_file=tmp/'pepper.key';secret_file.write_bytes(secret);secret_file.chmod(0o600)
        for version in [16,19]:
            tag=bytes.fromhex(oracle(2,digest,bytes(range(16)),secret,b'',2,32,1,32,version))
            phc=f'$argon2id$v={version}$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$'+b64(tag)
            envelope=json.dumps(dict(argon2=phc))
            assert verify(plaintext.encode(),envelope,'meteor')=='no'
            settings['WELITE_ARGON_SECRET_FILE']=str(secret_file)
            assert verify(plaintext.encode(),envelope,'meteor')=='yes'
            expected_ref=hmac.new(secret,b'welite-argon-secret-v1\0'+envelope.encode(),hashlib.sha256).hexdigest()
            assert verify(plaintext.encode(),envelope,'proof')==expected_ref
            secret_file.write_bytes(b'wrong')
            assert verify(plaintext.encode(),envelope,'meteor')=='no'
            assert verify(plaintext.encode(),envelope,'fingerprint')!=expected_ref
            secret_file.write_bytes(b'')
            assert verify(plaintext.encode(),envelope,'meteor')=='no'
            assert verify(plaintext.encode(),envelope,'fingerprint')=='no'
            secret_file.write_bytes(secret);secret_file.chmod(0o644)
            if os.name=='posix':assert verify(plaintext.encode(),envelope,'meteor')=='no'
            secret_file.chmod(0o600)
            if os.name=='posix':
                link=tmp/'link.key';link.symlink_to(secret_file);settings['WELITE_ARGON_SECRET_FILE']=str(link)
                assert verify(plaintext.encode(),envelope,'meteor')=='no'
                link.unlink()
                fifo=tmp/'fifo.key';os.mkfifo(fifo);settings['WELITE_ARGON_SECRET_FILE']=str(fifo)
                assert verify(plaintext.encode(),envelope,'meteor')=='no'
                fifo.unlink()
            settings['WELITE_ARGON_SECRET_FILE']=str(tmp/'missing.key')
            assert verify(plaintext.encode(),envelope,'meteor')=='no'
            secret_file.write_bytes(b'x'*65537);settings['WELITE_ARGON_SECRET_FILE']=str(secret_file)
            assert verify(plaintext.encode(),envelope,'meteor')=='no'
            secret_file.write_bytes(secret);settings.pop('WELITE_ARGON_SECRET_FILE')
        for binary_secret in [b'\0\xff\x80\n',b'x'*65536]:
            tag=bytes.fromhex(oracle(2,digest,bytes(range(16)),binary_secret,b'',2,32,1,32,19))
            envelope=json.dumps(dict(argon2='$argon2id$v=19$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$'+b64(tag)))
            secret_file.write_bytes(binary_secret);settings['WELITE_ARGON_SECRET_FILE']=str(secret_file)
            assert verify(plaintext.encode(),envelope,'meteor')=='yes'
        secret_file.write_bytes(secret);settings.pop('WELITE_ARGON_SECRET_FILE')
        # Fixed independent fixture for the actual HTTP/token lifecycle test.
        tag=bytes.fromhex(oracle(2,hashlib.sha256(b'test-password').hexdigest().encode(),bytes(range(16)),secret,b'',2,32,1,32,19))
        secret_fixture='$argon2id$v=19$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$'+b64(tag)
        assert secret_fixture=='$argon2id$v=19$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$YP4w4kIb5cnL7j3QC7YWdgIgvtjmj5Q22x+qTOqyF+w'
        tag=bytes.fromhex(oracle(2,hashlib.sha256(b'test-password').hexdigest().encode(),bytes(range(16)),b'',b'',2,32,1,32,16))
        fixture='$argon2id$v=16$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$'+b64(tag)
        assert fixture=='$argon2id$v=16$m=32,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$shmop4+uHY9Bws9kfsVWl7IO3PvjjDUJpB4nB4wjPno'
        print('PASS: official C Argon2 d/i/id v16/v19, secrets/AD, lanes/passes/rounding, legacy/versionless PHC and '+('checked' if checked else 'normal')+' arithmetic')
