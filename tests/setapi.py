"""Scalar/remainder settings creation and complete definition reads."""
import json
from urllib.parse import quote, urlencode


def exercise(call,board,snapshot,stored,fail,clear):
    path='/api/boards/'+quote(board,safe='')+'/custom-fields'
    cases=[{},dict(currencyCode='EUR'),
           dict(stringtemplateFormat='__card__ + "漢"\n\'literal\'',stringtemplateSeparator=''),
           dict(jiraTimeField='remaining',jiraEstimateFieldId='customfield_12345678901234567890',jiraEstimateUnit='x'*78+'😀',future=dict(enabled=True,values=[None,'漢',3.5]))]
    for index,settings in enumerate(cases):
        data=dict(name='Settings '+str(index),type='currency',settings=settings,showOnCard=True)
        status,_,body=call('POST',path,data)
        assert status==200,(settings,status,body)
        identity=json.loads(body)['_id'];stored(identity,settings)
        status,_,body=call('GET',path+'/'+quote(identity,safe=''),None)
        assert status==200,(status,body)
        result=json.loads(body)
        assert result.get('settings')==settings,(result,settings)
        assert result['boardIds']==[board] and result['showOnCard'] is True,result
        assert isinstance(result['createdAt'],str) and result['createdAt'].endswith('Z'),result
        assert isinstance(result['modifiedAt'],str) and result['modifiedAt'].endswith('Z'),result
        assert '$s' not in result and '_wl_source' not in result
    settings=dict(currencyCode='USD',jiraTimeField='original',future=dict(flag=False))
    status,_,body=call('POST',path,urlencode(dict(name='Form settings',type='text',settings=json.dumps(settings))))
    assert status==200,(status,body)
    identity=json.loads(body)['_id'];stored(identity,settings)
    assert json.loads(call('GET',path+'/'+quote(identity,safe=''),None)[2])['settings']==settings
    invalid=[None,[],False,'bad',dict(currencyCode=7),dict(currencyCode='\0'),
             dict(stringtemplateFormat={}),dict(stringtemplateSeparator=None),
             dict(jiraTimeField='estimate'),dict(jiraEstimateFieldId='customfield_'),
             dict(jiraEstimateFieldId='customfield_１２'),dict(jiraEstimateFieldId='customfield_'+'1'*21),
             dict(jiraEstimateUnit='x'*79+'😀')]
    # Dropdown creation is a separate managed-array/presence step; never silently drop it.
    invalid += [dict(dropdownItems=[]),dict(dropdownItems=[dict(_id='one',name='One')])]
    for settings in invalid:
        before=snapshot();status,_,body=call('POST',path,dict(name='Invalid settings',type='text',settings=settings))
        assert status==400,(settings,status,body)
        assert snapshot()==before,settings
    for raw in [b'{"name":"bad","settings":{"future":{"x":1,"x":2}}}',
                b'{"name":"bad","settings":{"future":1e999}}']:
        before=snapshot();assert call('POST',path,raw)[0]==400;assert snapshot()==before
    for stage in ['board','activity']:
        fail(stage)
        try:
            before=snapshot()
            status,_,body=call('POST',path,dict(name='Settings rollback',type='currency',settings=dict(currencyCode='GBP',future=dict(flag=True))))
            assert status==500,(stage,status,body)
            assert snapshot()==before,stage
        finally:clear()
    print('PASS: native/shared settings scalar/remainder JSON/form creation, complete metadata GET, Jira/UTF-16 validation, unsupported-array refusal and transactional rollback')
