"""Compile current Windows amd64 disk/embedded servers and inspect PE headers."""
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
prefix = Path(os.environ['WELITE_WIN64']).resolve()
fpc = prefix / 'lib/fpc/3.2.3/ppcrossx64'
resource = os.environ['FPCRES']

def run(args, cwd):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd,
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr

with tempfile.TemporaryDirectory(prefix='wlwin64-', dir=os.environ['TMPDIR']) as temp:
    for backend in ('linked', 'cli'):
        for embedded in (False, True):
            out = Path(temp) / (backend + ('embed' if embedded else 'disk'))
            out.mkdir()
            shutil.copyfile(root / 'src/wlhttp.lpr', out / 'wlhttp.lpr')
            if embedded:
                run(['python3', root / 'releases/genasset.py', out / 'wlassets.pas',
                     out / 'wlpublic.rc'], root)
                run([resource, 'wlpublic.rc', '-o', 'wlpublic.res', '-of', 'res'], out)
            binary = out / 'wwinx64.exe'
            run([fpc, '-n', '-B', '-Px86_64', '-Twin64', '-FR' + resource,
                 *(['-dWLDB_CLI'] if backend == 'cli' else []),
                 *(['-dWLEMBED'] if embedded else []), '-O3', '-Xs',
                 '-Fu' + str(root / 'src'),
                 '-Fu' + str(prefix / 'lib/fpc/3.2.3/units/x86_64-win64/*'),
                 '-FU' + str(out), '-FE' + str(out), '-o' + str(binary), out / 'wlhttp.lpr'], out)
            data = binary.read_bytes()
            assert data[:2] == b'MZ'
            pe = struct.unpack_from('<I', data, 60)[0]
            assert data[pe:pe+4] == b'PE\0\0'
            assert struct.unpack_from('<H', data, pe+4)[0] == 0x8664
            assert struct.unpack_from('<H', data, pe+24)[0] == 0x20b
            assert struct.unpack_from('<H', data, pe+24+68)[0] == 3
            if backend == 'linked':
                assert b'sqlite3.dll' in data.lower()
            print(backend + ' ' + ('embedded' if embedded else 'disk') + ': Windows AMD64 PE32+ console verified')
