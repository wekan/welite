"""Attachment upload/download/delete retain metadata while using short digest paths."""
import base64
import json
import sqlite3
from paths import stored

def run(request,db,session):
    with sqlite3.connect(db) as con:lane,lid=con.execute("SELECT swimlaneId,listId FROM cards WHERE id='card'").fetchone()
    payload=b'bytes\0with\r\nnewlines\xff'
    filename='VeryLongOriginalFileName-日本語.txt'
    body=json.dumps(dict(boardId='protected',swimlaneId=lane,listId=lid,cardId='card',fileName=filename,fileData=base64.b64encode(payload).decode())).encode()
    response=request('POST','/api/attachment/upload?token='+session,body)
    assert response[0]==200,response
    identity=json.loads(response[2])['attachmentId'];path=stored(db,identity)
    assert len(identity)>8 and path.read_bytes()==payload
    downloaded=request('GET','/api/attachment/download/'+identity+'?token='+session)
    assert downloaded[0]==200
    data=json.loads(downloaded[2]);assert data['fileName']==filename and base64.b64decode(data['base64Data'])==payload
    assert request('DELETE','/api/attachment/delete/'+identity+'?token='+session)[0]==200 and not path.exists()
    print('PASS: long attachment IDs/original Unicode names survive short-path upload, binary download and delete')
