"""Shared endpoint drop validation, atomic multi-card writes and token replay."""
from layout import Forms
import sqlite3

def run(request,db,session):
    with sqlite3.connect(db) as con:
        con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES('drag','Drag board','drag','now')")
        for lane in ['dlan1','dlan2']:
            con.execute("INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES(?,'drag',?,0,'now')",(lane,lane))
        for lid,lane in [('dlist1','dlan1'),('dlist2','dlan2')]:
            con.execute("INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES(?,'drag',?,?,0,'now')",(lid,lane,lid))
        for cid in ['dcard1','dcard2']:
            con.execute("INSERT INTO cards(id,boardId,listId,swimlaneId,title,userId,createdAt,modifiedAt,dateLastActivity) VALUES(?,'drag','dlist1','dlan1',?,'u','now','now','now')",(cid,cid))
    def data(**extra):
        parser=Forms();parser.feed(request('GET','/board?id=drag&view=all&sessionId='+session)[2].decode())
        fields=parser.forms[-1][1];fields.update(dir='drop',sel_card=['dcard1','dcard2'],targetList='dlist2',targetLane='dlan2');fields.update(extra)
        # urlencode of dict cannot repeat values in the harness: encode a raw form body.
        from urllib.parse import urlencode
        return urlencode(fields,doseq=True).encode()
    def post(body):return request('POST','/board/move',body,content_type='application/x-www-form-urlencoded')[0]
    def rows():
        with sqlite3.connect(db) as con:return con.execute("SELECT id,listId,swimlaneId,sort FROM cards WHERE boardId='drag' ORDER BY id").fetchall()
    original=rows()
    assert post(data(targetList='todo',targetLane='lane'))==400 and rows()==original
    assert post(data(targetLane='dlan1'))==400 and rows()==original
    with sqlite3.connect(db) as con:con.execute("CREATE TRIGGER nodrop BEFORE UPDATE ON cards WHEN NEW.id='dcard2' BEGIN SELECT RAISE(ABORT,'blocked');END")
    assert post(data())==400 and rows()==original
    with sqlite3.connect(db) as con:con.execute('DROP TRIGGER nodrop')
    token=data();assert post(token)==302
    moved=rows();assert all(row[1:3]==('dlist2','dlan2') for row in moved) and moved[0][3]!=moved[1][3]
    assert post(token)==403 and rows()==moved
    print('PASS: shared-endpoint multi-card drops, target ownership/lane checks, transaction rollback and token replay rejection')
