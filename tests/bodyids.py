"""All API relation IDs are validated before mutations; author attribution is explicit."""
import json
import sqlite3

def run(request,db,admin,writer):
    with sqlite3.connect(db) as con:
        uid=con.execute("SELECT id FROM users WHERE username='member'").fetchone()[0]
        con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES('bodies','Body IDs','bodies','now')")
        con.execute("INSERT INTO swimlanes(id,boardId,title,createdAt) VALUES('blane','bodies','Lane','now')")
        con.execute("INSERT INTO lists(id,boardId,swimlaneId,title,createdAt) VALUES('blist','bodies','blane','List','now')")
        for target,disabled,active in [('btarget',0,1),('bdisabled',1,1),('binactive',0,0),('boutsider',0,None)]:
            con.execute("INSERT INTO users(id,username,loginDisabled,createdAt,modifiedAt) VALUES(?,?,?,'now','now')",(target,target,disabled))
            if active is not None:con.execute("INSERT INTO board_members(boardId,userId,isActive) VALUES('bodies',?,?)",(target,active))
        con.execute("INSERT INTO board_members(boardId,userId) VALUES('bodies',?)",(uid,))
        for label in ['good','second']:
            con.execute("INSERT INTO board_labels(boardId,id,name,color) VALUES('bodies',?,?,'red')",(label,label))
        con.execute("INSERT INTO board_labels(boardId,id,name,color) VALUES('otherboard','foreignlabel','Foreign','blue')")
    base='/api/boards/bodies/lists/blist/cards'
    def post(path,data,token=writer,method='POST'):
        return request(method,path+'?token='+token,json.dumps(data).encode())
    def snapshot():
        with sqlite3.connect(db) as con:return '\n'.join(con.iterdump())
    status,_,body=post(base,dict(title='Card 日本語',description='Original',swimlaneId='blane',labelIds=['good'],members=['btarget'],assignees=['btarget']))
    assert status==200,(status,body)
    cid=json.loads(body)['_id'];card=base+'/'+cid
    with sqlite3.connect(db) as con:
        assert con.execute('SELECT userId FROM cards WHERE id=?',(cid,)).fetchone()[0]==uid
    for raw in [b'{',b'[]',b'null',b'not-json']:
        before=snapshot()
        assert request('PUT',card+'?token='+writer,raw)[0]==400
        assert request('POST',base+'?token='+writer,raw)[0]==400
        assert snapshot()==before,'Malformed JSON changed the database'
    invalid=[dict(labelIds=['foreignlabel']),dict(labelIds=['good',7]),dict(labelIds={}),dict(labelIds='good,,second'),dict(members=['boutsider']),dict(members=['bdisabled']),dict(members=['binactive']),dict(assignees=['missing']),dict(assignees=['btarget'],labelIds=['good','foreignlabel'])]
    for values in invalid:
        before=snapshot();values=dict(values,title='Must stay unchanged')
        assert post(card,values,method='PUT')[0]==400,values
        assert snapshot()==before,'Invalid body partially edited card'
        assert post(base,dict(values,swimlaneId='blane'))[0]==400,values
        assert snapshot()==before,'Invalid create body left a card behind'
    assert post(card,dict(labelIds=['good','good','second'],members=[],assignees=[]),method='PUT')[0]==200
    with sqlite3.connect(db) as con:
        assert con.execute('SELECT COUNT(*) FROM card_labels WHERE cardId=?',(cid,)).fetchone()[0]==2
        assert con.execute('SELECT COUNT(*) FROM card_members WHERE cardId=?',(cid,)).fetchone()[0]==0
    assert request('PUT',card+'?token='+writer,dict(labelIds='',description=''))[0]==200
    with sqlite3.connect(db) as con:
        assert con.execute('SELECT description FROM cards WHERE id=?',(cid,)).fetchone()[0]==''
        assert con.execute('SELECT COUNT(*) FROM card_labels WHERE cardId=?',(cid,)).fetchone()[0]==0
    for field in ['members','assignees']:
        for target in ['boutsider','bdisabled','binactive','missing']:
            before=snapshot()
            assert request('POST',card+'/'+field+'/'+target+'?token='+writer,{})[0]==400
            assert snapshot()==before
        assert request('POST',card+'/'+field+'/btarget?token='+writer,{})[0]==200
        with sqlite3.connect(db) as con:con.execute("UPDATE board_members SET isActive=0 WHERE boardId='bodies' AND userId='btarget'")
        assert request('DELETE',card+'/'+field+'/btarget?token='+writer)[0]==200
        with sqlite3.connect(db) as con:con.execute("UPDATE board_members SET isActive=1 WHERE boardId='bodies' AND userId='btarget'")
    # Regular editors cannot forge another member's authorship; tenant admins can import
    # attribution only for an enabled member of the same board.
    comments='/api/boards/bodies/cards/'+cid+'/comments'
    for token,target in [(writer,'btarget'),(writer,'missing'),(admin,'bdisabled'),(admin,'boutsider')]:
        before=snapshot()
        assert post(base,dict(title='Forged',authorId=target,swimlaneId='blane'),token)[0]==403
        assert post(comments,dict(comment='Forged',authorId=target),token)[0]==403
        assert snapshot()==before
    assert post(base,dict(title='Attributed',authorId='btarget',swimlaneId='blane'),admin)[0]==200
    assert post(comments,dict(comment='Attributed',authorId='btarget'),admin)[0]==200
    assert post(comments,dict(comment='Own comment'))[0]==200
    # A real relation write failure must roll back both the card update and prior inserts.
    with sqlite3.connect(db) as con:
        con.execute("CREATE TRIGGER reject_body_labels BEFORE INSERT ON card_labels WHEN NEW.labelId='second' BEGIN SELECT RAISE(ABORT,'forced label failure'); END")
    before=snapshot()
    assert post(card,dict(title='Must roll back',labelIds=['good','second']),method='PUT')[0]==500
    assert snapshot()==before
    assert post(base,dict(title='Must roll back',labelIds=['good','second'],swimlaneId='blane'))[0]==500
    assert snapshot()==before
    with sqlite3.connect(db) as con:con.execute('DROP TRIGGER reject_body_labels')
    print('PASS: label/member/assignee arrays and comma strings, same-board enabled targets, author policy and atomic relation failures')
