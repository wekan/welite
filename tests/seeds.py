"""Private bootstrap SQL selection and refusal boundaries."""
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wlseed-',dir=os.environ['TMPDIR']) as directory:
    out=Path(directory)
    (out/'over.sql').write_bytes("\ufeffSELECT 'override ä 中文';\n".encode())
    (out/'disk.sql').write_text("SELECT 'disk';\n")
    (out/'nul.sql').write_bytes(b'SELECT 1;\x00SELECT 2;')
    (out/'empty.sql').write_text(' \t\n')
    with (out/'big.sql').open('wb') as handle:handle.truncate(16*1024*1024+1)
    (out/'dir').mkdir()
    result=subprocess.run([os.environ.get('FPC','fpc'),'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/seeds.lpr')],capture_output=True,text=True)
    assert result.returncode==0,result.stdout+result.stderr
    subprocess.run([str(out/'seeds'),str(out)],check=True)
