"""Compile and test database behavior with both SQLite backends."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="wldb-", dir=os.environ["TMPDIR"]) as tmp:
    for backend, flags in (("linked", []), ("cli", ["-dWLDB_CLI"])):
        out = Path(tmp) / backend
        out.mkdir()
        result = subprocess.run([os.environ.get("FPC", "fpc"), *flags, "-B", "-Fu"+str(root/"src"), "-FU"+str(out), "-FE"+str(out), str(root/"tests/dbtext.lpr")], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if result.returncode:
            raise RuntimeError(result.stdout)
        subprocess.run([str(out/"dbtext"), str(out/"data.db")], check=True, timeout=15, cwd=out)
