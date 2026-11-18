"""Compile current Windows disk/embedded servers and inspect target PE headers."""
import os
from pathlib import Path
import shlex
import shutil
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
targets = []
for variable, cpu, system, compiler, machine, magic, label in (
    ('WELITE_WIN32', 'i386', 'win32', 'ppcross386', 0x14c, 0x10b, 'x86 PE32'),
    ('WELITE_WIN64', 'x86_64', 'win64', 'ppcrossx64', 0x8664, 0x20b, 'AMD64 PE32+'),
):
    if os.environ.get(variable):
        targets.append((Path(os.environ[variable]).resolve(), cpu, system,
                        compiler, machine, magic, label))
assert targets, 'Set WELITE_WIN32 and/or WELITE_WIN64 to an installed target prefix'
resource = os.environ['FPCRES']
runner = shlex.split(os.environ.get('WELITE_WIN_RUNNER', ''))

def run(args, cwd):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd,
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr

def imports(data, pe, magic):
    optional = pe + 24
    sections = optional + struct.unpack_from('<H', data, pe+20)[0]
    section_count = struct.unpack_from('<H', data, pe+6)[0]
    def offset(rva):
        for index in range(section_count):
            section = sections + 40 * index
            virtual_size, virtual, raw_size, raw = struct.unpack_from('<IIII', data, section+8)
            if virtual <= rva < virtual + max(virtual_size, raw_size):
                assert rva - virtual < raw_size, 'Import points outside file section'
                return raw + rva - virtual
        raise AssertionError('Import RVA has no section')
    directory = optional + (112 if magic == 0x20b else 96)
    rva, size = struct.unpack_from('<II', data, directory+8)
    assert rva and size
    descriptor = offset(rva)
    libraries = {}
    entry = '<Q' if magic == 0x20b else '<I'
    width = struct.calcsize(entry)
    ordinal_flag = 1 << (width*8-1)
    for index in range(size // 20 + 1):
        fields = struct.unpack_from('<IIIII', data, descriptor+index*20)
        if not any(fields):
            return libraries
        name = offset(fields[3])
        end = data.index(b'\0', name)
        library = data[name:end].decode('ascii').lower()
        thunk = offset(fields[0] or fields[4])
        symbols = libraries.setdefault(library,set())
        while True:
            address, = struct.unpack_from(entry,data,thunk)
            if not address:
                break
            if not address & ordinal_flag:
                symbol = offset(address)+2
                symbols.add(data[symbol:data.index(b'\0',symbol)].decode('ascii').lower())
            thunk += width
    raise AssertionError('Unterminated PE import directory')

with tempfile.TemporaryDirectory(prefix='wlwincross-', dir=os.environ['TMPDIR']) as temp:
    for prefix, cpu, system, compiler, machine, magic, label in targets:
        fpc = prefix / 'lib/fpc/3.2.3' / compiler
        flags = [fpc, '-n', '-B', '-P' + cpu, '-T' + system, '-FR' + resource,
                 '-Fu' + str(root / 'src'),
                 '-Fu' + str(prefix / ('lib/fpc/3.2.3/units/' + cpu + '-' + system + '/*'))]
        probe = Path(temp) / (system + '-resolver')
        probe.mkdir()
        binary = probe / 'webhookdns.exe'
        run([*flags, '-FU' + str(probe), '-o' + str(binary), root / 'tests/webhookdns.lpr'], probe)
        if runner:
            run([*runner, binary], probe)
            print('Windows ' + label + ' webhook resolver probe passed')
        else:
            print('Windows ' + label + ' webhook resolver probe compiled')
        for backend in ('linked', 'cli'):
            for embedded in (False, True):
                out = Path(temp) / (system + backend + ('embed' if embedded else 'disk'))
                out.mkdir()
                shutil.copyfile(root / 'src/wlhttp.lpr', out / 'wlhttp.lpr')
                if embedded:
                    run(['python3', root / 'releases/genasset.py', out / 'wlassets.pas',
                         out / 'wlpublic.rc'], root)
                    run([resource, 'wlpublic.rc', '-o', 'wlpublic.res', '-of', 'res'], out)
                binary = out / 'welite.exe'
                run([*flags,
                     *(['-dWLDB_CLI'] if backend == 'cli' else []),
                     *(['-dWLEMBED'] if embedded else []), '-O3', '-Xs',
                     '-FU' + str(out), '-FE' + str(out), '-o' + str(binary), out / 'wlhttp.lpr'], out)
                data = binary.read_bytes()
                assert data[:2] == b'MZ'
                pe = struct.unpack_from('<I', data, 60)[0]
                assert data[pe:pe+4] == b'PE\0\0'
                assert struct.unpack_from('<H', data, pe+4)[0] == machine
                assert struct.unpack_from('<H', data, pe+24)[0] == magic
                assert struct.unpack_from('<H', data, pe+24+68)[0] == 3
                libraries = imports(data, pe, magic)
                assert 'kernel32.dll' in libraries, libraries
                assert {'wsastartup','getaddrinfo','freeaddrinfo','wsacleanup'} <= libraries.get('ws2_32.dll',set()), libraries
                assert ('sqlite3.dll' in libraries) == (backend == 'linked'), libraries
                print(backend + ' ' + ('embedded' if embedded else 'disk') + ': Windows ' + label + ' console verified')
