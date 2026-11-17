"""Compile the actual native arrow protocol/markup checks on both database backends."""
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wlkeypad-',dir=os.environ['TMPDIR']) as directory:
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=Path(directory)/backend;out.mkdir()
        result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/keypad.lpr')],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
        subprocess.run([str(out/'keypad')],check=True)
