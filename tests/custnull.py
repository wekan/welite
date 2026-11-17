"""First SQL edits of WeKan-assigned null/missing custom values use definitions."""
import json
from wire import DateMs, Long, Binary, encode


def run(client, sql):
    q=lambda value:"'"+value.replace("'","''")+"'"
    types=['text','number','currency','checkbox','date','dropdown','dropdownMultiSelect','stringtemplate']
    rows=[];definitions=[]
    for state in ['null','missing']:
        for kind in types:
            key=state+'-'+kind
            row=dict(_id=key)
            if state=='null':row['value']=None
            row['unknown']=dict(date=DateMs(-7),long=Long(9007199254740993),binary=Binary(b'preserve',4))
            rows.append(row)
            definitions.append(dict(_id=key,name=key,type=kind,unknown=DateMs(-1)))
    rows += [dict(_id='legacy',value=None),dict(_id='bad-definition',value=None)]
    definitions.append(dict(_id='bad-definition',name='Bad',type='unsupported'))
    document=dict(_id='null-custom-card',boardId='board',listId='list',customFields=rows,unknown=DateMs(-3))
    assert client.command({'insert':'customFields','documents':definitions})['n']==len(definitions)
    assert client.command({'insert':'cards','documents':[document]})['n']==1
    def equal():
        actual=client.find('cards','null-custom-card')[0]
        assert encode(actual)==encode(document),(actual,document)
    def write(key,expression):
        return sql("UPDATE card_custom_field_values SET value="+expression+" WHERE cardId='null-custom-card' AND customFieldId="+q(key)+';','exec')
    cases=dict(text=(q('true'),'true'),number=(q('12.5'),12.5),currency=(q('42.25'),42.25),
               checkbox=('0',False),date=('-1',DateMs(-1)),dropdown=(q('option'),'option'),
               dropdownMultiSelect=(q(json.dumps(['漢','one'])),['漢','one']),stringtemplate=(q('["literal"]'),'["literal"]'))
    for state in ['null','missing']:
        for kind in types:
            key=state+'-'+kind;expression,expected=cases[kind]
            assert write(key,expression)=='ok',(state,kind)
            next(row for row in rows if row['_id']==key)['value']=expected
            equal()
    # A legacy untyped value without a definition retains the established text fallback.
    assert write('legacy',q('legacy text'))=='ok'
    next(row for row in rows if row['_id']=='legacy')['value']='legacy text'
    equal()
    assert write('bad-definition',q('do not guess'))=='error'
    equal()
    for key,expression in [('null-number',q('not numeric')),('null-checkbox','2'),
                           ('null-date','1.5'),('null-dropdownMultiSelect',q('[1]'))]:
        # Return the source value to its actual WeKan assigned-null state.
        next(row for row in rows if row['_id']==key)['value']=None
        assert client.command({'update':'cards','updates':[dict(q=dict(_id='null-custom-card'),u={'$set':dict(customFields=rows)})]})['n']==1
        assert write(key,expression)=='error',(key,expression)
        equal()
    # One invalid first typed edit aborts earlier valid edits in the same statement.
    assert sql("UPDATE card_custom_field_values SET value=2 WHERE cardId='null-custom-card' AND customFieldId IN ('null-number','null-checkbox');",'exec')=='error'
    equal()
    # A definition changed through Mongo is read at the next untyped write.
    assert client.command({'update':'customFields','updates':[dict(q=dict(_id='null-date'),u={'$set':dict(type='checkbox')})]})['n']==1
    assert write('null-date','1')=='ok'
    next(row for row in rows if row['_id']=='null-date')['value']=True
    equal()
    assert sql("DELETE FROM cards WHERE id='null-custom-card';",'exec')=='ok'
    for definition in definitions:
        assert sql('DELETE FROM custom_fields WHERE id='+q(definition['_id'])+';','exec')=='ok'
