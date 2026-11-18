"""Native board links, titles and empty/not-found states over real HTTP."""
import html
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from urllib.parse import urlencode,parse_qs,urlsplit
from homelang import Page
from layout import Forms
root=Path(__file__).resolve().parents[1]
catalog=json.loads((root/'i18n/locales.jsn').read_text())
english=json.loads((root/'i18n/data/en.jsn').read_text())

class BoardPage(Page):
    def __init__(self,body):self.maps=[];self.submits=[];super().__init__(body)
    def handle_starttag(self,tag,attrs):
        if tag=='table' and 'data-board-map' in dict(attrs):self.maps.append(dict(attrs))
        if tag=='input' and dict(attrs).get('type')=='submit':self.submits.append(dict(attrs))
        super().handle_starttag(tag,attrs)

def run(request,database,administrator,member,base):
    with sqlite3.connect(database) as con:
        profile=con.execute("SELECT profile_json FROM users WHERE username='administrator'").fetchone()[0]
        for bid,title in [('boardtxt','Board <user>'),('boardnone','No lanes <user>')]:
            con.execute("INSERT INTO boards(id,title,slug,permission,createdAt) VALUES(?,?,?,'public','now')",(bid,title,bid))
        for lid,order in [('txtlane',0),('txtlane2',1),('txtempty',2)]:
            con.execute("INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES(?,'boardtxt',?,?,'now')",(lid,lid,order))
        con.execute("INSERT INTO pages(id,url,title,doctype,dir,minRole,createdAt,modifiedAt) VALUES('boardtxt','/boardtxt','Configured title','html4','auto','anon','now','now')")
        con.execute("INSERT INTO page_widgets(id,pageId,type,binding,options_json,createdAt,modifiedAt) VALUES('boardtxt','boardtxt','dataview','board',?,'now','now')",(json.dumps({'boardId':'protected'}),))
        for lid,lane,order in [('txtlist','txtlane',0),('txtlist2','txtlane',1),('txtlist3','txtlane2',0),('txtlist4','txtlane2',1)]:
            con.execute("INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES(?,'boardtxt',?,'List <user>',?,'now')",(lid,lane,order))
        con.execute("UPDATE lists SET collapsed=1 WHERE id='txtlist'")
        author=con.execute("SELECT id FROM users WHERE username='administrator'").fetchone()[0]
        con.execute("INSERT INTO cards(id,boardId,swimlaneId,listId,title,userId,dateLastActivity,createdAt,modifiedAt) "
                    "VALUES('txtcard','boardtxt','txtlane','txtlist','Hidden until expanded',?,'now','now','now')",(author,))
        con.execute("UPDATE cards SET spentTime=2.5,isOvertime=1 WHERE id='txtcard'")
        for identity,title,archived in [('txtchild','Subtask <child>',0),('txtoldchild','Archived subtask',1)]:
            con.execute("INSERT INTO cards(id,boardId,swimlaneId,listId,title,userId,parentId,archived,dateLastActivity,createdAt,modifiedAt) "
                        "VALUES(?,'boardtxt','txtlane','txtlist',?,?,'txtcard',?,'now','now','now')",
                        (identity,title,author,archived))
    card_path='/board/card?id=boardtxt&card=txtcard'
    upload_path='/board/attachment/upload?id=boardtxt&card=txtcard'
    status,_,guest_body=request('GET',card_path)
    assert status==200 and upload_path.split('?')[0].encode() not in guest_body
    with sqlite3.connect(database) as con:
        reader,=con.execute("SELECT id FROM users WHERE username='member'").fetchone()
        con.execute("INSERT INTO board_members(boardId,userId,isReadOnly) VALUES('boardtxt',?,1)",(reader,))
    status,_,reader_body=request('GET',card_path+'&sessionId='+member)
    assert status==200 and upload_path.split('?')[0].encode() not in reader_body
    status,headers,body=request('GET',card_path+'&lang=ar&sessionId='+administrator)
    assert status==200 and headers['Content-Language']=='ar' and 'Set-Cookie' not in headers
    forms=Forms()
    forms.feed(body.decode())
    fields,=[values for action,values in forms.forms if action==upload_path]
    assert fields['lang']=='ar'
    boundary='welite-card-upload-fixture'
    data=b'\x00\x01\xff\n'
    body=b''.join(
        f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode()
        for key,value in fields.items())
    body+=f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="native.bin"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode()
    body+=data+f'\r\n--{boundary}--\r\n'.encode()
    def upload(path):
        return request('POST',path,body,content_type='multipart/form-data; boundary='+boundary)
    guest_body=body.replace(fields['sessionId'].encode(),b'invalid-session')
    assert request('POST',upload_path,guest_body,
                   content_type='multipart/form-data; boundary='+boundary)[0]==403
    reader_body=body.replace(fields['sessionId'].encode(),member.encode())
    assert request('POST',upload_path,reader_body,
                   content_type='multipart/form-data; boundary='+boundary)[0]==403
    with sqlite3.connect(database) as con:
        con.execute("DELETE FROM board_members WHERE boardId='boardtxt' AND userId=?",(reader,))
    assert upload(upload_path.replace('card=txtcard','card=txtchild'))[0]==403
    status,headers,body_response=upload(upload_path)
    assert status==303 and 'Set-Cookie' not in headers,(status,body_response)
    assert parse_qs(urlsplit(headers['Location']).query)['lang']==['ar']
    status,headers,body_response=request('GET',headers['Location'])
    assert status==200 and headers['Content-Language']=='ar' and b'dir="rtl"' in body_response
    assert upload(upload_path)[0]==403
    with sqlite3.connect(database) as con:
        identity,=con.execute("SELECT id FROM attachments WHERE cardId='txtcard' AND name='native.bin'").fetchone()
    download='/board/attachment?id=boardtxt&card=txtcard&file='+identity+'&sessionId='+administrator
    status,headers,downloaded=request('GET',download)
    assert status==200 and downloaded==data and 'Set-Cookie' not in headers
    print('PASS: native multipart card upload scopes the action, rejects replay and downloads exact bytes')
    minicard='/board?id=boardtxt&expand=txtlist'
    def card_page(session):
        status,_,html=request('GET',minicard+'&sessionId='+session)
        assert status==200
        return html
    with sqlite3.connect(database) as con:
        con.execute("UPDATE boards SET settings_json=? WHERE id='boardtxt'",(json.dumps({'allowsCustomFieldsOnMinicard':True}),))
        con.executemany("INSERT INTO custom_fields(id,name,type,adminOnly,showLabelOnMiniCard,modifiedAt) VALUES(?,?,'text',?,1,'now')",
                        [('native-mini-field','Original field',0),('native-mini-private','Private field',1)])
        con.executemany("INSERT INTO custom_field_boards VALUES(?,'boardtxt')",
                        [('native-mini-field',),('native-mini-private',)])
        con.executemany("INSERT INTO card_custom_field_values(cardId,customFieldId,value) VALUES('txtcard',?,?)",
                        [('native-mini-field','Visible <value>'),('native-mini-private','Hidden value')])
        con.execute("INSERT INTO board_members(boardId,userId,isReadOnly) VALUES('boardtxt',?,1)",(reader,))
        con.execute("INSERT INTO custom_fields(id,name,type,showLabelOnMiniCard,dropdownItemsPresent,modifiedAt) "
                    "VALUES('native-mini-dropdown','Choice','dropdown',1,1,'now'),"
                    "('native-mini-multi','Choices','dropdownMultiSelect',1,1,'now')")
        con.executemany("INSERT INTO custom_field_boards VALUES(?,'boardtxt')",
                        [('native-mini-dropdown',),('native-mini-multi',)])
        con.executemany("INSERT INTO custom_field_dropdown_items(customFieldId,id,name) VALUES(?,?,?)",[
            ('native-mini-dropdown','option-key','Original option'),
            ('native-mini-dropdown','alternate','Alternate option'),
            ('native-mini-multi','one','First option'),('native-mini-multi','two','Second option')])
        con.executemany("INSERT INTO card_custom_field_values(cardId,customFieldId,value) VALUES('txtcard',?,?)",[
            ('native-mini-dropdown','option-key'),('native-mini-multi',json.dumps(['two','one']))])
        con.execute("INSERT INTO custom_fields(id,name,type,showLabelOnMiniCard,modifiedAt) "
                    "VALUES('native-mini-check','Confirmed','checkbox',1,'now')")
        con.execute("INSERT INTO custom_field_boards VALUES('native-mini-check','boardtxt')")
        con.execute("INSERT INTO card_custom_field_values VALUES('txtcard','native-mini-check','false')")
        con.execute("INSERT INTO board_members(boardId,userId,isAdmin) VALUES('boardtxt',?,1)",(author,))
    status,_,french=request('GET',minicard+'&lang=fr&sessionId='+member)
    assert status==200 and b'Confirmed: Non' in french
    visible=card_page(member)
    assert b'Original field: Visible &lt;value&gt;' in visible and b'Private field' not in visible and b'Hidden value' not in visible
    assert b'Private field: Hidden value' in card_page(administrator)
    assert b'Choice: Original option' in visible and b'Choices: Second option, First option' in visible
    dropdown='/api/boards/boardtxt/custom-fields/native-mini-dropdown/dropdown-items/option-key?token='+administrator
    status,_,body=request('PUT',dropdown,dict(name='Updated <option>'))
    assert status==200,(status,body)
    assert b'Choice: Updated &lt;option&gt;' in card_page(member)
    status,_,detail=request('GET',card_path+'&lang=ar&sessionId='+administrator)
    assert status==200 and b'class="card-custom-fields"' in detail
    assert b'Choice: Updated &lt;option&gt;' in detail
    assert b'<option value="option-key" selected>Updated &lt;option&gt;</option>' in detail
    forms=Forms()
    forms.feed(detail.decode())
    path,fields=next((action,values) for action,values in forms.forms
                     if action.startswith('/board/card/dropdown?'))
    status,headers,rejected=request('POST',path,dict(fields,option='missing'))
    assert status==404 and headers['Content-Language']=='ar' and 'Set-Cookie' not in headers
    assert b'dir="rtl"' in rejected and b'lang=ar' in rejected and b'/board/card?' in rejected
    status,headers,_=request('POST',path,dict(fields,option='alternate'))
    assert status==303 and 'Set-Cookie' not in headers
    assert b'<option value="alternate" selected>Alternate option</option>' in request('GET',headers['Location'])[2]
    assert request('POST',path,dict(fields,option='option-key'))[0]==403
    with sqlite3.connect(database) as con:
        con.execute("UPDATE boards SET settings_json=json_set(settings_json,'$.allowsCustomFields',json('false')) WHERE id='boardtxt'")
    status,_,detail=request('GET',card_path+'&sessionId='+administrator)
    assert status==200 and b'class="card-custom-fields"' not in detail
    endpoint='/api/boards/boardtxt/custom-fields/native-mini-field?token='+administrator
    status,_,body=request('PUT',endpoint,dict(name='Updated <field>'))
    assert status==200,(status,body)
    visible=card_page(member)
    assert b'Updated &lt;field&gt;: Visible &lt;value&gt;' in visible and b'Original field' not in visible
    with sqlite3.connect(database) as con:
        con.execute("DELETE FROM card_custom_field_values WHERE cardId='txtcard'")
        con.execute("DELETE FROM custom_field_boards WHERE boardId='boardtxt'")
        con.execute("DELETE FROM custom_field_dropdown_items WHERE customFieldId IN ('native-mini-dropdown','native-mini-multi')")
        con.execute("DELETE FROM custom_fields WHERE id IN ('native-mini-field','native-mini-private','native-mini-dropdown','native-mini-multi','native-mini-check')")
        con.execute("DELETE FROM board_members WHERE boardId='boardtxt' AND userId=?",(reader,))
        con.execute("DELETE FROM board_members WHERE boardId='boardtxt' AND userId=?",(author,))
        con.execute("UPDATE boards SET settings_json='{}' WHERE id='boardtxt'")
    print('PASS: native minicard shows the renamed field and escapes values while hiding admin-only data')
    def content_state():
        with sqlite3.connect(database) as con:
            return [con.execute('SELECT * FROM '+table+' WHERE '+condition+' ORDER BY id').fetchall()
                    for table,condition in [('boards',"id IN ('boardtxt','boardnone')"),
                                            ('swimlanes',"boardId='boardtxt'"),('lists',"boardId='boardtxt'")]]
    before=content_state()
    def check(tag,session='',query=None,header='en',board='boardtxt'):
        row=next(row for row in catalog if row['tag']==tag)
        local=json.loads((root/'i18n/data'/row['file']).read_text())
        words={key:local.get(key) or value for key,value in english.items()}
        fields=dict(id=board,view='all');fields.update(query or {})
        if session:fields['sessionId']=session
        status,headers,body=request('GET','/board?'+urlencode(fields),extra_headers={'Accept-Language':header})
        assert headers['Content-Language']==tag.replace('_','-')
        assert 'Accept-Language' in headers['Vary'] and 'Set-Cookie' not in headers
        assert ('<title>'+html.escape(words['board'],quote=False)+'</title>').encode() in body,(tag,'title')
        if board in ('missing-txt','protected'):
            assert status==404 and html.escape(words['board-not-found'],quote=False).encode() in body
            assert b'Board &lt;user&gt;' not in body
            return
        assert status==200
        page=BoardPage(body)
        assert page.captions('/')==[words['all-boards']],(tag,'all-boards',page.items)
        assert len(page.maps)==1 and page.maps[0]['summary']==words['board']+' / '+words['view'],(tag,page.maps)
        assert page.maps[0]['data-board-map']==board
        legend=words['color-yellow']+': '+words['current']+'; *: '+words['cards']+'; -: '+words['no-items-message']
        assert html.escape(legend,quote=False).encode() in body,(tag,'legend')
        arrows={'left':'<','right':'>','up':'^','down':'v'}
        native=[(attrs,text) for name,attrs,text in page.items if name=='a' and 'data-view-dir' in attrs]
        if board=='boardtxt':assert len(native)>=2,(tag,native)
        for attrs,text in native:
            assert attrs['dir']=='ltr' and text==words['view']+' '+arrows[attrs['data-view-dir']],(tag,attrs,text)

        all_captions=[text for name,attrs,text in page.items if name=='a' and 'data-list-toggle' not in attrs and parse_qs(urlsplit(attrs['href']).query).get('view')==['all']]
        assert all_captions==[words['view-all']],(tag,'view-all')
        assert html.escape(words['no-items-message'],quote=False).encode() in body,(tag,'empty')
        assert b'Board <user>' not in body and b'List <user>' not in body
        actions={attrs['name']:attrs['value'] for attrs in page.submits if attrs['name'].startswith('action_')}
        if session==administrator:
            expected={'action_edit':words['edit'],'action_delete':words['r-delete-selected'],
                      'action_clear':words['r-unselect-all'],'action_export':words['r-export-selected'],
                      'action_clone':words['copySelectionPopup-title']}
            assert actions==expected,(tag,actions,expected)
            summary=words['multi-selection']+': '+words['swimlanes']+' 0; '+words['lists']+' 0; '+words['cards']+' 0'
            assert html.escape(summary,quote=False).encode() in body,(tag,'selection summary')
        else:assert not actions,(tag,'anonymous actions')

    try:
        for row in catalog:
            check(row['tag'],query={'lang':row['tag']})
            check(row['tag'],administrator,{'lang':row['tag']})
        for tag in ('en','fi','ar','he'):
            check(tag,query={'lang':tag},board='boardnone')
            check(tag,query={'lang':tag},board='missing-txt')
            check(tag,query={'lang':tag},board='protected')
            status,headers,body=request('GET','/boardtxt?'+urlencode({'lang':tag}))
            local=json.loads((root/'i18n/data'/(tag+'.jsn')).read_text())
            assert status==200 and headers['Content-Language']==tag
            assert html.escape(local['board-not-found'],quote=False).encode() in body
            assert b'Card &lt;test&gt;' not in body

        # Empty lanes still occupy one navigable map position and allow vertical escape.
        for tag in ('fi','ar'):
            status,_,body=request('GET','/board?'+urlencode(dict(id='boardtxt',x=999,y=3,lang=tag)))
            assert status==200 and b'X 1 Y 3' in body,(tag,'empty position')
            page=BoardPage(body)
            views={attrs['data-view-dir']:attrs['href'] for name,attrs,_ in page.items if name=='a' and 'data-view-dir' in attrs}
            assert set(views)=={'up'},(tag,views)
            assert parse_qs(urlsplit(views['up']).query)['y']==['2']
            status,_,body=request('GET',views['up']);assert status==200 and b'X 1 Y 2' in body
            page=BoardPage(body)
            empty=next(attrs['href'] for name,attrs,_ in page.items if name=='a' and attrs.get('title','').startswith('txtempty / '))
            params=parse_qs(urlsplit(empty).query)
            assert params['x']==['1'] and params['y']==['3'] and params['lang']==[tag]
            status,_,body=request('GET',empty);assert status==200 and b'X 1 Y 3' in body
            status,_,body=request('GET','/board?'+urlencode(dict(id='boardnone',x=999,y=999,lang=tag)))
            assert status==200 and b'X 1 Y 1' in body
            assert not any('data-view-dir' in attrs for name,attrs,_ in BoardPage(body).items if name=='a')
        # A middle empty lane must expose both vertical neighbors as well.
        with sqlite3.connect(database) as con:con.execute("UPDATE swimlanes SET sort=0.5 WHERE id='txtempty'")
        for tag in ('fi','ar'):
            status,_,body=request('GET','/board?'+urlencode(dict(id='boardtxt',x=999,y=2,lang=tag)))
            assert status==200 and b'X 1 Y 2' in body
            views={attrs['data-view-dir']:attrs['href'] for name,attrs,_ in BoardPage(body).items if name=='a' and 'data-view-dir' in attrs}
            assert set(views)=={'up','down'},views
            for direction,target in [('up','1'),('down','3')]:
                assert parse_qs(urlsplit(views[direction]).query)['y']==[target]
                assert request('GET',views[direction])[0]==200
        with sqlite3.connect(database) as con:con.execute("UPDATE swimlanes SET sort=2 WHERE id='txtempty'")
        check('fi',header='fi')
        with sqlite3.connect(database) as con:con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(json.dumps({'language':'ar'}),))
        check('ar',administrator,header='fi')
        check('fi',administrator,{'lang':'fi'},'he')
        check('fi','invalid',header='fi')
        if os.environ.get('WELITE_UI')=='1':
            subprocess.run([os.environ.get('NODE','node'),str(root/'tests/boardtxt.js'),base,administrator],check=True)
        status,_,body=request('GET','/board?id=boardtxt&x=1&y=1&lang=en')
        assert status==200 and b'Hidden until expanded' not in body
        status,_,body=request('GET','/board?id=boardtxt&x=1&y=1&lang=en&expand=txtlist')
        assert status==200 and b'Hidden until expanded' in body
        assert b'Overtime (hours): 2.5' in body
        with sqlite3.connect(database) as con:
            con.execute("""UPDATE boards SET settings_json='{"allowsSpentTimeOnMinicard":false}' WHERE id='boardtxt'""")
        status,_,body=request('GET','/board?id=boardtxt&x=1&y=1&lang=en&expand=txtlist')
        assert status==200 and b'Overtime (hours): 2.5' not in body
        with sqlite3.connect(database) as con:
            con.execute("UPDATE boards SET settings_json='{}' WHERE id='boardtxt'")

        if os.environ.get('WELITE_DILLO_TOOLS'):
            from dillo import run as check_dillo
            check_dillo(base)
        check('en',header='en')
        assert content_state()==before,'Viewport/map navigation changed board content'
    finally:
        with sqlite3.connect(database) as con:
            con.execute("DELETE FROM page_widgets WHERE pageId='boardtxt'")
            con.execute("DELETE FROM pages WHERE id='boardtxt'")
            con.execute("DELETE FROM cards WHERE boardId='boardtxt'")
            con.execute("DELETE FROM lists WHERE boardId='boardtxt'")
            con.execute("DELETE FROM swimlanes WHERE boardId='boardtxt'")
            con.execute("DELETE FROM boards WHERE id IN ('boardtxt','boardnone')")
            con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(profile,))
    print('PASS: all installed native board link/title/empty captions, translated no-lane/not-found states, profile/query/header selection and escaped user titles')
