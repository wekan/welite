"""Nested setting SQL columns match WeKan and preserve unrelated typed data."""
import json
from wire import DateMs, Long, Binary, encode


def run(client, sql):
    q=lambda value:"'"+value.replace("'","''")+"'"
    columns=['currencyCode','stringtemplateFormat','stringtemplateSeparator']
    document=dict(_id='settings-field',name='Settings',type='currency',boardIds=['board'],
                  currencyCode='legacy root currency',stringtemplateFormat='legacy root format',
                  stringtemplateSeparator='legacy root separator',modifiedAt=DateMs(0),
                  settings=dict(currencyCode='EUR',stringtemplateFormat='__card__',stringtemplateSeparator=' / ',
                                dropdownItems=[dict(_id='option',name='Option',unknown=DateMs(-1))],
                                jiraTimeField='remaining',unknown=dict(long=Long(9007199254740993),binary=Binary(b'keep',4),date=DateMs(-7))))
    assert client.command({'insert':'customFields','documents':[document]})['n']==1
    def equal():
        actual=client.find('customFields','settings-field')[0]
        assert encode(actual)==encode(document),(actual,document)
    def read():return sql("SELECT currencyCode,stringtemplateFormat,stringtemplateSeparator FROM custom_fields WHERE id='settings-field';")
    observed=read()
    assert observed==[['EUR','__card__',' / ']],observed
    assert sql("UPDATE custom_fields SET currencyCode='USD' WHERE id='settings-field';",'exec')=='ok'
    document['settings']['currencyCode']='USD';equal()
    template='prefix "__card__"\n漢'
    assert sql('UPDATE custom_fields SET stringtemplateFormat='+q(template)+",stringtemplateSeparator='' WHERE id='settings-field';",'exec')=='ok'
    document['settings'].update(stringtemplateFormat=template,stringtemplateSeparator='');equal()
    changed=dict(currencyCode='JPY',stringtemplateFormat='__board__',stringtemplateSeparator=' | ')
    assert client.command({'update':'customFields','updates':[dict(q=dict(_id='settings-field'),u={'$set':{'settings.'+key:value for key,value in changed.items()}})]})['n']==1
    document['settings'].update(changed)
    assert read()==[['JPY','__board__',' | ']];equal()
    assert sql("UPDATE custom_field_dropdown_items SET name='Renamed' WHERE customFieldId='settings-field' AND id='option';",'exec')=='ok'
    document['settings']['dropdownItems'][0]['name']='Renamed';equal()
    assert sql("INSERT INTO custom_fields(id,name,type,currencyCode,stringtemplateFormat,stringtemplateSeparator,modifiedAt) VALUES('settings-insert','Insert','stringtemplate','GBP','__card__',' / ','1970-01-01T00:00:00.000Z');",'exec')=='ok'
    inserted=client.find('customFields','settings-insert')[0]
    assert inserted['settings']==dict(currencyCode='GBP',stringtemplateFormat='__card__',stringtemplateSeparator=' / '),inserted
    assert all(key not in inserted for key in columns),inserted
    missing=dict(_id='settings-missing',name='Missing',type='currency',modifiedAt=DateMs(0),unknown=DateMs(-1))
    assert client.command({'insert':'customFields','documents':[missing]})['n']==1
    assert sql("SELECT currencyCode IS NULL,stringtemplateFormat IS NULL,stringtemplateSeparator IS NULL FROM custom_fields WHERE id='settings-missing';")==[['1','1','1']]
    assert sql("UPDATE custom_fields SET currencyCode='CHF' WHERE id='settings-missing';",'exec')=='ok'
    missing['settings']=dict(currencyCode='CHF')
    assert encode(client.find('customFields','settings-missing')[0])==encode(missing)
    invalid=dict(_id='settings-invalid',name='Invalid',type='currency',settings='do not overwrite',modifiedAt=DateMs(0))
    assert client.command({'insert':'customFields','documents':[invalid]})['n']==1
    assert sql("UPDATE custom_fields SET currencyCode='BAD' WHERE id IN ('settings-field','settings-invalid');",'exec')=='error'
    equal();assert encode(client.find('customFields','settings-invalid')[0])==encode(invalid)
    # Reinstall an adapter view/descriptor in the old flat shape, then upgrade it.
    current=sql("SELECT sql FROM sqlite_master WHERE type='view' AND name='custom_fields';")[0][0]
    old=current
    for key in columns:old=old.replace('$."settings"."'+key+'"','$."'+key+'"')
    assert old!=current
    spec=json.loads(sql("SELECT spec FROM _wl_models WHERE name='custom_fields';")[0][0])
    for field in spec['fields']:
        if field['name'] in columns:field['path']=field['name']
    assert sql('DROP VIEW custom_fields; '+old+'; UPDATE _wl_models SET spec='+q(json.dumps(spec))+" WHERE name='custom_fields';",'exec')=='ok'
    assert read()==[['legacy root currency','legacy root format','legacy root separator']]
    assert sql('', 'install')=='ok'
    assert read()==[['JPY','__board__',' | ']];equal()
    assert encode(client.find('customFields','settings-insert')[0])==encode(inserted)
    assert encode(client.find('customFields','settings-missing')[0])==encode(missing)
    assert encode(client.find('customFields','settings-invalid')[0])==encode(invalid)
    upgraded=json.loads(sql("SELECT spec FROM _wl_models WHERE name='custom_fields';")[0][0])
    assert {field['name']:field['path'] for field in upgraded['fields'] if field['name'] in columns}=={key:'settings.'+key for key in columns}
    for identity in ['settings-field','settings-insert','settings-missing','settings-invalid']:
        assert sql('DELETE FROM custom_fields WHERE id='+q(identity)+';','exec')=='ok'
    print('PASS: nested currency/template SQL settings, two-way source edits, unknown BSON/dropdowns, legacy-root preservation, invalid-parent rollback and old-view upgrade')
