"""Run the real Pascal movement code against the canonical SQLite schema."""
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="wlmove-", dir=os.environ["TMPDIR"]) as tmp:
    db = Path(tmp) / "data.db"
    con = sqlite3.connect(db)
    con.executescript((root / "src/schema.sql").read_text())
    for board in ("b", "o"):
        con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES(?,?,?,?)", (board,board,board,"now"))
    for sid, board, order, archived in (("s1","b",0,0),("skip","b",1,1),("s2","b",2,0),("os","o",1,0)):
        con.execute("INSERT INTO swimlanes(id,boardId,title,sort,archived,createdAt) VALUES(?,?,?,?,?,?)", (sid,board,sid,order,archived,"now"))
    for lid, board, lane, order, archived in (("l1","b","s1",0,0),("l2","b","s1",1,0),("dest","b","s2",7,0),("other","o","os",0,0),("legacy","b","",0,0),("archived","b","s2",0,1)):
        con.execute("INSERT INTO lists(id,boardId,swimlaneId,title,sort,archived,createdAt) VALUES(?,?,?,?,?,?,?)", (lid,board,lane,lid,order,archived,"now"))
    for cid, board, lane, archived in (("c1","b","s1",0),("c2","b","s1",1),("foreign","o","os",0)):
        con.execute("INSERT INTO cards(id,boardId,listId,swimlaneId,userId,archived,createdAt,modifiedAt,dateLastActivity) VALUES(?,?,?,?,?,?,'now','now','now')", (cid,board,"l1",lane,"u",archived))
    con.commit()
    con.close()
    for backend, flags in (("linked", []), ("cli", ["-dWLDB_CLI"])):
        out = Path(tmp) / backend
        out.mkdir()
        copy = out / "data.db"
        copy.write_bytes(db.read_bytes())
        result = subprocess.run([os.environ.get("FPC", "fpc"), *flags, "-B", "-Fu"+str(root/"src"), "-FU"+str(out), "-FE"+str(out), str(root/"tests/movelist.lpr")], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if result.returncode:
            raise RuntimeError(result.stdout)
        subprocess.run([str(out/"movelist"), str(copy)], check=True)
