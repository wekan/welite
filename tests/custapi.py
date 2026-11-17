"""Custom-value API replacement, body parsing and truthful failure responses."""
import json
import sqlite3
from urllib.parse import quote, urlencode
from wire import DateMs, Long, Binary, encode


def exercise(call, base, snapshot, check, fail, un_fail, typed):
    def post(kind, value):
        return call('POST', base + '/customFields/cust-' + kind, dict(value=value))

    def accepted(kind, value, expected):
        status, _, body = post(kind, value)
        assert status == 200, (kind, status, body)
        assert json.loads(body)['_id'] == 'cust-"id'
        check(kind, expected)

    accepted('text', 'first', 'first')
    accepted('text', 'replacement', 'replacement')
    accepted('text', '', '')
    accepted('text', "'; DELETE FROM cards; -- 漢", "'; DELETE FROM cards; -- 漢")
    accepted('array', ['one', '漢', '\\quoted\\'], ['one', '漢', '\\quoted\\'])
    accepted('array', [], [])
    status, _, body = call('POST', base + '/customFields/cust-array',
                          urlencode(dict(value='["form"]')))
    assert status == 200, (status, body)
    check('array', ['form'])
    accepted('number', 12.5, 12.5)
    accepted('number', 27, 27)
    accepted('bool', True, True)
    accepted('bool', False, False)
    accepted('date', '1969-12-31T23:59:59.999Z', DateMs(-1) if typed else '1969-12-31T23:59:59.999Z')
    accepted('date', 1234, DateMs(1234) if typed else 1234)
    for raw in [{}, dict(value=None), dict(value={}), dict(value=[1]),
                dict(value=[True]), dict(value=[[]]), dict(value='\0'), dict(value=['\0']),
                b'{"value":"one","value":"two"}', b'{"value":1}garbage', b'{"value":1e999}',
                'value=one&value=two', 'other=missing']:
        before = snapshot()
        status, _, body = call('POST', base + '/customFields/cust-text', raw)
        assert status == 400, (raw, status, body)
        assert snapshot() == before, raw
    for suffix in ['/customFields/cust-foreign', '/customFields/cust-missing']:
        before = snapshot()
        assert call('POST', base + suffix, dict(value='attack'))[0] == 404
        assert snapshot() == before
    if typed:
        for kind, value in [('bool', 2), ('date', 1.5), ('array', '[1]'), ('number', 'no number')]:
            before = snapshot()
            assert post(kind, value)[0] == 500, (kind, value)
            assert snapshot() == before
    # An AFTER-write FAIL leaves a changed row until the transaction rolls back.
    for operation in ['update', 'insert']:
        fail(operation)
        try:
            before = snapshot()
            kind = 'text' if operation == 'update' else 'failure'
            status, _, body = post(kind, 'fail')
            assert status == 500, (operation, status, body)
            assert snapshot() == before, operation
        finally:
            un_fail()
        accepted('text', 'after-' + operation, 'after-' + operation)
    print('PASS: custom API native/shared atomic replacement, JSON/form arrays/scalars, escaped IDs, invalid bodies, scope guards and rollback after write failure')


def run_native(request, db):
    status, _, body = request('POST', '/users/login', dict(username='administrator', password='test-password'))
    assert status == 200, (status, body)
    login = json.loads(body)
    kinds = dict(text='text', array='dropdownMultiSelect', number='number', bool='checkbox', date='date', failure='text', foreign='text')
    with sqlite3.connect(db) as con:
        con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES('cust-board','Custom','custom','now')")
        con.execute("INSERT INTO board_members(boardId,userId,isAdmin) VALUES('cust-board',?,1)", (login['id'],))
        con.execute("INSERT INTO lists(id,boardId,title,createdAt) VALUES('cust-list','cust-board','List','now')")
        con.execute('INSERT INTO cards(id,boardId,listId,title,createdAt,userId,dateLastActivity,modifiedAt) VALUES(?,?,?,?,?,?,?,?)', ('cust-"id','cust-board','cust-list','Card','now',login['id'],'now','now'))
        for kind, typ in kinds.items():
            con.execute('INSERT INTO custom_fields(id,name,type,modifiedAt) VALUES(?,?,?,?)', ('cust-' + kind, kind, typ,'now'))
            if kind != 'foreign':
                con.execute("INSERT INTO custom_field_boards(customFieldId,boardId) VALUES(?,'cust-board')", ('cust-' + kind,))
    def call(method, path, data):
        if isinstance(data, str):
            return request(method, path + '?token=' + login['token'], data.encode(), content_type='application/x-www-form-urlencoded')
        return request(method, path + '?token=' + login['token'], json.dumps(data).encode() if isinstance(data, dict) else data)
    def snapshot():
        with sqlite3.connect(db) as con:
            return con.execute("SELECT * FROM card_custom_field_values WHERE cardId=? ORDER BY customFieldId", ('cust-"id',)).fetchall()
    def check(kind, expected):
        with sqlite3.connect(db) as con:
            value = con.execute('SELECT value FROM card_custom_field_values WHERE cardId=? AND customFieldId=?', ('cust-"id', 'cust-' + kind)).fetchone()[0]
        if isinstance(expected, list):
            assert json.loads(value) == expected, (value, expected)
        elif isinstance(expected, bool):
            assert value == str(int(expected)), (value, expected)
        else:
            assert value == str(expected), (value, expected)
    def fail(operation):
        with sqlite3.connect(db) as con:
            con.execute('CREATE TRIGGER cust_fail AFTER ' + operation.upper() +
                        " ON card_custom_field_values WHEN NEW.value='fail' BEGIN SELECT RAISE(FAIL,'test failure'); END")
    def un_fail():
        with sqlite3.connect(db) as con:con.execute('DROP TRIGGER cust_fail')
    base='/api/boards/cust-board/lists/cust-list/cards/' + quote('cust-"id', safe='"')
    exercise(call, base, snapshot, check, fail, un_fail, False)


def run_shared(request, client, db, token):
    identity = 'cust-"id'
    kinds = dict(text='text', array='dropdownMultiSelect', number='number', bool='checkbox', date='date', failure='text', foreign='text')
    definitions = [dict(_id='cust-' + kind, name=kind, type=typ, boardIds=[] if kind == 'foreign' else ['b']) for kind, typ in kinds.items()]
    assert client.command({'insert':'customFields','documents':definitions})['n'] == len(definitions)
    original = dict(_id=identity, boardId='b', listId='l', title='Custom API',
                    customFields=[dict(_id='cust-text', value='original', unknown=DateMs(-1)),
                                  dict(_id='cust-legacy', value=Binary(b'keep', 4))], unknown=Long(9007199254740993))
    assert client.command({'insert':'cards','documents':[original]})['n'] == 1
    def call(method, path, data):
        # Preserve raw malformed/duplicate JSON, rather than re-encoding it.
        return request(method, path, data, token)
    def snapshot():return encode(client.find('cards', identity)[0])
    def check(kind, expected):
        card=client.find('cards', identity)[0]
        row=next(row for row in card['customFields'] if row['_id']=='cust-' + kind)
        if kind == 'number':
            assert isinstance(row['value'], (int, float)) and not isinstance(row['value'], bool) and row['value'] == expected
        else:
            assert encode(dict(value=row['value'])) == encode(dict(value=expected)), (kind, row, expected)
        assert card['unknown'] == Long(9007199254740993)
        assert next(row for row in card['customFields'] if row['_id']=='cust-legacy')['value'] == Binary(b'keep', 4)
        assert next(row for row in card['customFields'] if row['_id']=='cust-text')['unknown'] == DateMs(-1)
    def fail(operation):
        with sqlite3.connect(db) as con:
            physical=con.execute("SELECT table_name FROM _ferretdb_collections WHERE name='cards'").fetchone()[0]
            con.execute('CREATE TRIGGER cust_fail AFTER UPDATE ON "' + physical.replace('"','""') +
                        '" WHEN json_extract(NEW._ferretdb_sjson,\'$._id\')=' + "'cust-\"id'" +
                        " AND instr(json(NEW._ferretdb_sjson),'fail')>0 BEGIN SELECT RAISE(FAIL,'test failure'); END")
    def un_fail():
        with sqlite3.connect(db) as con:con.execute('DROP TRIGGER cust_fail')
    base='/api/boards/b/lists/l/cards/' + quote(identity, safe='"')
    exercise(call, base, snapshot, check, fail, un_fail, True)
