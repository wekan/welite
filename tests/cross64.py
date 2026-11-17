"""Compile current disk/embedded servers with an isolated Linux amd64 toolchain."""
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
prefix = Path(os.environ['WELITE_CROSS64']).resolve()
fpc = prefix / 'lib/fpc/3.2.3/ppcrossx64'
resource = os.environ['FPCRES']
backends = os.environ.get('WELITE_CROSS_BACKENDS', 'cli').split(',')
assert backends and all(name in ('cli', 'linked') for name in backends), backends

def run(args, cwd):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd,
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr

with tempfile.TemporaryDirectory(prefix='wlcross64-', dir=os.environ['TMPDIR']) as temp:
    for backend in backends:
        for embedded in (False, True):
            out = Path(temp) / (backend + ('embed' if embedded else 'disk'))
            out.mkdir()
            shutil.copyfile(root / 'src/wlhttp.lpr', out / 'wlhttp.lpr')
            if embedded:
                run(['python3', root / 'releases/genasset.py', out / 'wlassets.pas',
                     out / 'wlpublic.rc'], root)
                run([resource, 'wlpublic.rc', '-o', 'wlpublic.res', '-of', 'res'], out)
            binary = out / 'wlinx64.exe'
            run([fpc, '-n', '-B', '-Px86_64', '-Tlinux',
                 *(['-dWLDB_CLI'] if backend == 'cli' else []),
                 *(['-dWLEMBED'] if embedded else []), '-FR' + resource, '-O3', '-Xs',
                 '-Fu' + str(root / 'src'),
                 '-Fu' + str(prefix / 'lib/fpc/3.2.3/units/x86_64-linux/*'),
                 '-FD' + str(prefix / 'bin'), '-XPx86_64-linux-gnu-',
                 '-Fl' + str(prefix / 'sysroot/usr/x86_64-linux-gnu/lib'),
                 '-Fl' + str(prefix / 'sysroot/usr/lib/x86_64-linux-gnu'),
                 '-k--sysroot=' + str(prefix / 'sysroot'),
                 '-FU' + str(out), '-FE' + str(out), '-o' + str(binary), out / 'wlhttp.lpr'], out)
            header = binary.read_bytes()[:64]
            assert header[:6] == b'\x7fELF\x02\x01', header
            assert struct.unpack_from('<H', header, 18)[0] == 62, header
            assert binary.stat().st_mode & 0o111
            print(backend + ' ' + ('embedded' if embedded else 'disk') + ': Linux x86-64 ELF verified')
