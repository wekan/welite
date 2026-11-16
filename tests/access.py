"""Board permission matrix against actual Pascal code and the canonical schema."""
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wlaccess-', dir=os.environ['TMPDIR']) as tmp:
    tmp = Path(tmp)
    for backend, flags in [('linked', []), ('cli', ['-dWLDB_CLI'])]:
        out = tmp/backend
        out.mkdir()
        db = out/'data.db'
        with sqlite3.connect(db) as con:
            con.executescript((root/'src/schema.sql').read_text())
            for board in ['private', 'public', 'archived']:
                con.execute("INSERT INTO boards(id,title,slug,permission,archived,createdAt) VALUES(?,?,?,?,?,'now')", (board,board,board,'public' if board=='public' else 'private', int(board=='archived')))
            for user in ['editor', 'reader', 'comment', 'assigned', 'inactive', 'disabled', 'admin']:
                con.execute("INSERT INTO users(id,username,isAdmin,loginDisabled,createdAt,modifiedAt) VALUES(?,?,?,?,'now','now')", (user,user,int(user in ['admin','disabled']),int(user=='disabled')))
                con.execute("INSERT INTO board_members(boardId,userId,isReadOnly,isCommentOnly,isReadAssignedOnly,isActive) VALUES('private',?,?,?,?,?)", (user,int(user=='reader'),int(user=='comment'),int(user=='assigned'),int(user!='inactive')))
            for card, board in [('c', 'private'), ('foreign', 'public')]:
                con.execute("INSERT INTO cards(id,boardId,userId,createdAt,modifiedAt,dateLastActivity) VALUES(?,?,'editor','now','now','now')", (card,board))
            con.execute("INSERT INTO lists(id,boardId,title,archived,createdAt) VALUES('archlist','private','archived',1,'now')")
        result = subprocess.run([os.environ.get('FPC','fpc'), *flags, '-B', '-Fu'+str(root/'src'), '-FU'+str(out), '-FE'+str(out), str(root/'tests/access.lpr')], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if result.returncode:
            raise RuntimeError(result.stdout)
        subprocess.run([str(out/'access'), str(db)], check=True)
