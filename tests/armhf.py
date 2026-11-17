"""Compile both advertised Linux ARM hard-float variants with matching target RTL."""
import os
from pathlib import Path
import shutil
import shlex
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
prefix = Path(os.environ['WELITE_ARMHF']).resolve()
fpc = prefix / 'lib/fpc/3.2.3/ppcrossarm'
resource = os.environ['FPCRES']
runner = shlex.split(os.environ.get('WELITE_ARM_RUNNER', ''))

def run(args, cwd):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd,
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr

with tempfile.TemporaryDirectory(prefix='wlarmhf-', dir=os.environ['TMPDIR']) as temp:
    for variant, cpu_flags in (('armhf', []), ('armv7', ['-Cparmv7a'])):
        for embedded in (False, True):
            out = Path(temp) / (variant + ('embed' if embedded else 'disk'))
            out.mkdir()
            shutil.copyfile(root / 'src/wlhttp.lpr', out / 'wlhttp.lpr')
            if embedded:
                run(['python3', root / 'releases/genasset.py', out / 'wlassets.pas',
                     out / 'wlpublic.rc'], root)
                run([resource, 'wlpublic.rc', '-o', 'wlpublic.res', '-of', 'res'], out)
            binary = out / 'welite.exe'
            run([fpc, '-n', '-B', '-Parm', '-Tlinux', '-CaEABIHF', '-CfVFPV3',
                 *cpu_flags, '-dWLDB_CLI', *(['-dWLEMBED'] if embedded else []),
                 '-FR' + resource, '-O3', '-Xs', '-Fu' + str(root / 'src'),
                 '-Fu' + str(prefix / 'lib/fpc/3.2.3/units/arm-linux/*'),
                 '-FD' + str(prefix / 'bin'), '-XParm-linux-gnueabihf-',
                 '-Fl' + str(prefix / 'sysroot/usr/arm-linux-gnueabihf/lib'),
                 '-k--sysroot=' + str(prefix / 'sysroot'),
                 '-FU' + str(out), '-FE' + str(out), '-o' + str(binary), out / 'wlhttp.lpr'], out)
            data = binary.read_bytes()
            assert data[:6] == b'\x7fELF\x01\x01'
            assert struct.unpack_from('<H', data, 18)[0] == 40
            flags = struct.unpack_from('<I', data, 36)[0]
            assert flags & 0xff000000 == 0x05000000, hex(flags)
            # FPC issue 40374: the pinned compiler can omit hard-float ELF metadata.
            assert flags & 0x600 in (0x200, 0x400), hex(flags)
            phoff = struct.unpack_from('<I', data, 28)[0]
            phsize, phcount = struct.unpack_from('<HH', data, 42)
            interpreters = []
            for index in range(phcount):
                kind, offset, _, _, size = struct.unpack_from('<IIIII', data, phoff+index*phsize)
                if kind == 3:
                    interpreters.append(data[offset:offset+size].rstrip(b'\0'))
            assert interpreters == [b'/lib/ld-linux-armhf.so.3'], interpreters
            print(variant + ' ' + ('embedded' if embedded else 'disk') + ': ARM ELF32 EABI5/hard-float loader; flags=' + hex(flags))
    probe = Path(temp) / 'abicall.lpr'
    probe.write_text("""program abicall;
{$mode objfpc}{$H+}
{$ifndef FPC_ABI_EABIHF}{$fatal Hard-float ABI required}{$endif}
function cpow(x,y:Double):Double;cdecl;external 'm' name 'pow';
function cstrtod(s:PChar;var tail:PChar):Double;cdecl;external 'c' name 'strtod';
var tail:PChar;x,y,z:Double;
begin
  x:=cstrtod('2.5x',tail);if (x<>2.5) or (tail^<>'x') then Halt(1);
  y:=3.0;z:=cpow(x,y);if Abs(z-15.625)>0.0000001 then Halt(2);
  Writeln('PASS: ARM hard-float libc return and libm arguments/return');
end.
""")
    executable = Path(temp) / 'abicall'
    run([fpc, '-n', '-B', '-Parm', '-Tlinux', '-CaEABIHF', '-CfVFPV3',
         '-Fu' + str(prefix / 'lib/fpc/3.2.3/units/arm-linux/*'),
         '-FD' + str(prefix / 'bin'), '-XParm-linux-gnueabihf-',
         '-Fl' + str(prefix / 'sysroot/usr/arm-linux-gnueabihf/lib'),
         '-k--sysroot=' + str(prefix / 'sysroot'),
         '-FU' + str(Path(temp)), '-o' + str(executable), probe], Path(temp))
    if runner:
        result = subprocess.run([*runner, str(executable)], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stdout + result.stderr
        assert 'PASS: ARM hard-float' in result.stdout, result.stdout
        print(result.stdout.strip())
    else:
        print('ABI probe compiled; set WELITE_ARM_RUNNER to verify foreign calls at runtime')
