"""Portable SHA1 HOTP/TOTP against RFC vectors and independent Python HMAC."""
import base64
import hashlib
import hmac
import os
from pathlib import Path
import struct
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
def code(key,counter,digits=6):
    digest=hmac.new(key,struct.pack('>Q',counter),hashlib.sha1).digest();offset=digest[-1]&15
    value=struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff
    return str(value%(10**digits)).zfill(digits)
key=b'12345678901234567890';secret=base64.b32encode(key).decode().rstrip('=')
with tempfile.TemporaryDirectory(prefix='wltotp-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    for checked in [False,True]:
        out=tmp/('checked' if checked else 'normal');out.mkdir()
        built=subprocess.run([os.environ.get('FPC','fpc'),*(['-Cr','-Co'] if checked else []),'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/totp.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        def run(*args):return subprocess.check_output([str(out/'totp'),*[str(arg) for arg in args]],text=True).strip()
        for counter,expected in enumerate(['755224','287082','359152','969429','338314','254676','287922','162583','399871','520489']):
            assert run('code',secret,counter,6)==expected
        for seconds,expected in [(59,'94287082'),(1111111109,'07081804'),(1111111111,'14050471'),(1234567890,'89005924'),(2000000000,'69279037'),(20000000000,'65353130')]:
            assert run('code',secret,seconds//30,8)==expected
        for raw in [b'\0',b'fo',b'foo',b'foob',b'fooba',b'foobar',bytes(range(32)),bytes(range(256))*4]:
            encoded=base64.b32encode(raw).decode();assert run('encode',raw.hex())==encoded.rstrip('=')
            for spelling in [encoded,encoded.rstrip('=').lower()]:
                for counter in [0,1,2**32+1,2**64-1]:assert run('code',spelling,counter,6)==code(raw,counter)
        seconds=1794832496;center=seconds//30
        for delta in [-10,-1,0,1,10]:
            value=code(key,center+delta)
            assert run('match',secret,value,seconds,10,-1)==str(center+delta)
            assert run('match',secret,value,seconds,10,center+delta)=='no'
        assert run('match',secret,code(key,center),seconds,0,-1)==str(center)
        for delta in [-11,11]:assert run('match',secret,code(key,center+delta),seconds,10,-1)=='no'
        assert run('code',secret,0,7)=='error'
        for value in ['', '12345','1234567','12 3456','１２３４５６','12x456']:
            assert run('match',secret,value,seconds,10,-1)=='no'
        for bad in ['', 'A','AAA','AAAAAA','MZ','MY=','MY=======','MY======A',' MY======','M1======','a'*1641]:
            assert run('code',bad,0,6)=='error',bad
            assert run('match',bad,'123456',seconds,10,-1)=='no'
        for timestamp,window,minimum in [(-1,0,-1),(seconds,-1,-1),(seconds,11,-1),(seconds,0,-2)]:
            assert run('match',secret,'123456',timestamp,window,minimum)=='no'
        assert run('match',secret,code(key,0),0,10,-1)=='0'
        assert run('match',secret,code(key,(2**63-1)//30),2**63-1,0,-1)==str((2**63-1)//30)
        print('PASS: RFC HOTP/TOTP SHA1, independent HMAC, base32 padding/case/binary, wide counters/times, Meteor window, replay boundary and '+('checked' if checked else 'normal')+' arithmetic')
