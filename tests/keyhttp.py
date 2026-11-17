"""Native arrow names dispatch without captions and ambiguous commands consume no proof."""
import sqlite3
import json
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
                      [('move_left','x'),('action','')], [('move_far','x')],
                      [('action_edit','x'),('action_clone','x')], [('action_delete','x'),('action_delete','y')],
                      [('action_clear','x'),('move_up','x')], [('action_export','x'),('dir','drop')],
                      [('action_clone','x'),('action','clear')], [('action_unknown','x')],
                      [('action_save','x'),('action','save')], [('action_save','x'),('move_left','x')] ]:
        form=fields()
        status,headers,_=request('POST','/board/move',list(form.items())+commands)
        assert status==400 and headers['Content-Language']=='ar',(commands,status)
        assert snapshot()==before,'Rejected native command changed board data'
        # Reuse the exact proof from the rejected request: no command was admitted.
        status,_,_=request('POST','/board/move',dict(form,action_clear='ignored caption'))
        assert status==302,'Malformed submit consumed the proof'
    for action in ('edit','delete','clone','export','save'):
        form=fields()
        status,_,_=request('POST','/board/move',dict(form,sel_card='foreigncard',**{'action_'+action:'native label'}))
        assert status==403,(action,'foreign selection accepted')
        assert snapshot()==before,'Native action changed a foreign selection'
        assert request('POST','/board/move',dict(form,action_clear='clear'))[0]==302,'Rejected foreign selection consumed proof'
    form=fields();form['sel_card']='card'
    status,headers,body=request('POST','/board/move',dict(form,action_export='delete'))
    assert status==200 and headers['Content-Type'].startswith('application/json')
    assert [row['id'] for row in json.loads(body)['data']['cards']]==['card']
    assert snapshot()==before,'Native export mutated board data'
    assert request('POST','/board/move',dict(form,action_clear='native clear'))[0]==302,'Native export consumed its proof'
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
