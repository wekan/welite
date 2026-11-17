"""Native arrow names dispatch without captions and ambiguous commands consume no proof."""
import sqlite3
from layout import Forms
from urllib.parse import parse_qs,urlsplit

def run(request,database,session):
    route='/board?id=protected&view=all&sessionId='+session+'&lang=ar'
    def fields():
        status,_,body=request('GET',route);assert status==200
        parser=Forms();parser.feed(body.decode())
        return next(fields for action,fields in parser.forms if action=='/board/move')
    def snapshot():
        with sqlite3.connect(database) as con:
            return [con.execute('SELECT * FROM '+table+' ORDER BY id').fetchall() for table in ('cards','lists','swimlanes')]
    before=snapshot()
    for commands in [ [('move_left','x'),('move_right','x')], [('move_up','x'),('move_up','y')],
                      [('move_left','x'),('dir','drop')], [('move_down','x'),('action','export')],
                      [('move_left','x'),('action','')], [('move_far','x')] ]:
        form=fields()
        status,headers,_=request('POST','/board/move',list(form.items())+commands)
        assert status==400 and headers['Content-Language']=='ar',(commands,status)
        assert snapshot()==before,'Rejected native command changed board data'
        # Reuse the exact proof from the rejected request: no command was admitted.
        status,_,_=request('POST','/board/move',dict(form,action='clear'))
        assert status==302,'Malformed submit consumed the proof'
    with sqlite3.connect(database) as con:
        original=con.execute("SELECT listId,swimlaneId,sort FROM cards WHERE id='card'").fetchone()
        lists=[row[0] for row in con.execute("SELECT id FROM lists WHERE boardId='protected' AND swimlaneId=? AND archived=0 ORDER BY sort,id",(original[1],))]
    assert len(lists)==2 and original[0] in lists
    index=lists.index(original[0]);direction='left' if index==0 else 'right'
    try:
        # Arabic physical left advances the logical index. The visible value is ignored.
        form=fields();form.update(sel_card='card');form['move_'+direction]='drop'
        status,headers,_=request('POST','/board/move',form)
        assert status==302 and parse_qs(urlsplit(headers['Location']).query)['lang']==['ar']
        with sqlite3.connect(database) as con:
            assert con.execute("SELECT listId FROM cards WHERE id='card'").fetchone()==(lists[1-index],)
        form=fields();form.update(sel_card='card');form['move_'+('right' if direction=='left' else 'left')]='translated label'
        assert request('POST','/board/move',form)[0]==302
        with sqlite3.connect(database) as con:
            assert con.execute("SELECT listId FROM cards WHERE id='card'").fetchone()==(original[0],)
    finally:
        with sqlite3.connect(database) as con:
            con.execute("UPDATE cards SET listId=?,swimlaneId=?,sort=? WHERE id='card'",original)
    assert snapshot()==before,'Native move round trip changed unrelated board data'
    print('PASS: real native arrow dispatch ignores labels, retains RTL/locale, rejects duplicate/unknown/mixed commands without data changes or proof consumption')
