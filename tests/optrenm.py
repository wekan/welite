"""Typed scoped dropdown rename, no-op bodies, validation and atomic rollback."""
import json
from urllib.parse import quote,urlencode
from optdel import run_native as fixture_native,run_shared as fixture_shared

def exercise(call,board,snapshot,stored,assign,install,clear,extra_kinds=()):
    base='/api/boards/'+quote(board,safe='')+'/custom-fields'
    options=[dict(_id="first '漢+%2F",name='First'),dict(_id='second',name='Second'),dict(_id='last',name='Last')]
    status,_,body=call('POST',base,dict(name='Rename options',type='dropdown',settings=dict(dropdownItems=options,future=dict(keep=True))))
    assert status==200,(status,body)
    identity=json.loads(body)['_id'];assign(identity)
    route=base+'/'+quote(identity,safe='')+'/dropdown-items/'+quote(options[0]['_id'],safe='')
    before=snapshot();status,_,body=call('PUT',route,{})
    assert status==200 and json.loads(body)==dict(_id=options[0]['_id']) and snapshot()==before
    for name in [None,False,3,[],{},'', '  ', '\0']:
        before=snapshot();status,_,body=call('PUT',route,dict(name=name))
        assert status==400,(name,status,body)
        assert snapshot()==before
    for bad in [b'{"name":"one","name":"two"}',urlencode([('name','one'),('name','two')])]:
        before=snapshot();assert call('PUT',route,bad)[0]==400;assert snapshot()==before
    before=snapshot();assert call('PUT',route.rsplit('/',1)[0]+'/missing',dict(name='Missing'))[0]==404;assert snapshot()==before
    before=snapshot();assert call('PUT',route.rsplit('/',1)[0]+'/%GG',dict(name='Bad path'))[0]==400;assert snapshot()==before
    # Shared fixtures seed a Regex with this same rendering; this must become a string.
    for value in [dict(name='First'),urlencode(dict(name='Renamed 漢 "quoted"\nline'))]:
        status,_,body=call('PUT',route,value);assert status==200,(status,body)
        assert json.loads(body)==dict(_id=options[0]['_id'])
        options[0]['name']='First' if isinstance(value,dict) else 'Renamed 漢 "quoted"\nline'
        stored(identity,options)
    for kind in ['fail','revoke']+list(extra_kinds):
        install(identity,kind)
        try:
            before=snapshot();status,_,body=call('PUT',route,dict(name='Rollback'))
            assert status==500,(kind,status,body)
            assert snapshot()==before,kind
        finally:clear()
    before=snapshot();assert call('PUT',route,{})[0]==200;assert snapshot()==before
    print('PASS: dropdown rename exact IDs, JSON/form Unicode/newlines, absent-name no-op, invalid/duplicate/missing refusal, typed same-text Regex repair, retained assignments/order and failure/revocation rollback')

def run_native(call,db,board,uid):
    fixture_native(call,db,board,uid,exercise_case=exercise,operation='rename')

def run_shared(call,client,db,board,uid):
    fixture_shared(call,client,db,board,uid,exercise_case=lambda *args:exercise(*args,extra_kinds=['type']),operation='rename')
