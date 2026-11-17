"""Published/editor spanning grids, required metadata and no-JS cell ordering."""
from html.parser import HTMLParser
from urllib.parse import urlencode
import sqlite3

class Forms(HTMLParser):
    def __init__(self):
        super().__init__()
        self.forms = []
        self.fields = {}
        self.path = None
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'form':
            self.path = attrs.get('action')
            self.fields = {}
        if tag == 'input' and attrs.get('type') == 'hidden':
            self.fields[attrs['name']] = attrs.get('value','')
    def handle_endtag(self, tag):
        if tag == 'form':
            self.forms.append((self.path,dict(self.fields)))

def run(request, db, session):
    def post(source,path,fields,widget_id=''):
        status, _, body = request('GET',source)
        assert status == 200
        parser = Forms()
        parser.feed(body.decode())
        forms = [data for action,data in parser.forms if action==path and (not widget_id or data.get('widgetId')==widget_id)]
        assert forms, (source,path,widget_id)
        return request('POST',path,dict(forms[-1],**fields))
    home = '/designer?sessionId='+session
    page = dict(action='save',url='/layout',title='Spanning layout',cols='3',doctype='html4',dir='auto',minRole='admin')
    assert post(home,'/designer/page/save',page)[0] == 302
    with sqlite3.connect(db) as con:
        page_id = con.execute("SELECT id FROM pages WHERE url='/layout'").fetchone()[0]
    editor = '/designer/page?'+urlencode(dict(id=page_id,sessionId=session))
    base = dict(type='label',label='span first',name='',value='',target='',binding='',row='0',col='0',rowspan='2',colspan='2',sort='0',options_json='{}',fgColor='',bgColor='')
    save = '/designer/widget/save'
    assert post(editor,save,base)[0] == 302
    with sqlite3.connect(db) as con:
        first = con.execute('SELECT id FROM page_widgets WHERE pageId=?',(page_id,)).fetchone()[0]
    assert post(editor,save,dict(base,label='span second',sort='1'))[0] == 302
    assert post(editor,save,dict(base,label='inside covered cell',row='1',col='1',rowspan='1',colspan='1'))[0] == 409
    assert post(editor,save,dict(base,label='inconsistent same anchor',rowspan='1'))[0] == 409
    required = dict(base,type='textinput',label='Required text',name='requiredText',value='',col='2',rowspan='1',colspan='1',required='1')
    assert post(editor,save,required)[0] == 302
    with sqlite3.connect(db) as con:
        required_id = con.execute("SELECT id FROM page_widgets WHERE pageId=? AND name='requiredText'",(page_id,)).fetchone()[0]
    assert post(editor,'/designer/widget/move',dict(dir='left'),required_id)[0] == 409
    status, _, body = request('GET','/layout?sessionId='+session)
    assert status == 200
    assert body.startswith(b'<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"')
    assert body.count(b'rowspan="2" colspan="2"') == 1
    assert body.count(b'span first') == 1 and body.count(b'span second') == 1
    assert b'name="requiredText" value="" required="required"' in body and b'* (required)' in body
    assert body.index(b'span first') < body.index(b'span second')
    assert post(editor,'/designer/widget/sort',dict(dir='down'),first)[0] == 302
    body = request('GET','/layout?sessionId='+session)[2]
    assert body.index(b'span second') < body.index(b'span first')
    assert post(editor,'/designer/widget/sort',dict(dir='up'),first)[0] == 302
    body = request('GET','/layout?sessionId='+session)[2]
    assert body.index(b'span first') < body.index(b'span second')
    # Same geometry is emitted for both directions, at the correct visual leading edge.
    rtl = request('GET','/layout?lang=ar&sessionId='+session)[2]
    assert rtl.count(b'rowspan="2" colspan="2"') == 1
    assert rtl.index(b'data-grid-col="2"') < rtl.index(b'data-grid-col="0"')
    assert body.index(b'data-grid-col="0"') < body.index(b'data-grid-col="2"')
    assert b'<table dir="ltr"' in rtl and b'<td dir="rtl"' in rtl
    assert post(home,'/designer/page/save',dict(page,pageId=page_id,dir='rtl',doctype='html32'))[0] == 302
    legacy=request('GET','/layout?lang=en&sessionId='+session)[2]
    assert legacy.startswith(b'<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 FINAL//EN"')
    assert post(home,'/designer/page/save',dict(page,pageId=page_id,dir='rtl'))[0] == 302
    fixed = request('GET','/layout?lang=en&sessionId='+session)[2]
    assert fixed.index(b'data-grid-col="2"') < fixed.index(b'data-grid-col="0"')
    print('PASS: spanning grids, covered/overlap cells, required metadata, cell sort and fixed/automatic RTL')
    return editor
