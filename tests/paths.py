"""The runtime store contract, independently calculated from SHA-256 and registry IDs."""
import hashlib
from pathlib import Path
import sqlite3

def stored(db,identity,kind='attachme'):
    digest=hashlib.sha256(identity.encode()).hexdigest()
    path=Path(db).parents[1]/kind
    for offset in range(0,56,8):path/=digest[offset:offset+8]
    return path/(digest[56:]+'.bin')

def domain_db(data,host):
    with sqlite3.connect(Path(data)/'admin/files/db/wekan.db') as con:
        identity=con.execute('SELECT id FROM tenantdirs WHERE host=?',(host,)).fetchone()[0]
    return Path(data)/'domains'/f'd{identity:07x}'/'files/db/wekan.db'
