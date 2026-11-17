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
        status, _, body = call('GET', base, None)
        assert status == 200, (status, body)
        fields = json.loads(body)['customFields']
        response = next(row['value'] for row in fields if row['_id'] == 'cust-' + kind)
        assert isinstance(response, str), (kind, response)
        assert response == value, (kind, response, value)
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
        before = encode(card)
        status, _, body = call('GET', base, None)
        assert status == 200, (status, body)
        data = json.loads(body)
        assert 'unknown' not in data and '_wl_source' not in data
        assert all(set(row) <= {'_id', 'value'} for row in data['customFields'])
        value = next(row['value'] for row in data['customFields'] if row['_id'] == 'cust-' + kind)
        if isinstance(expected, DateMs):
            from datetime import datetime, timezone
            assert value == datetime.fromtimestamp(expected / 1000, timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z'), (value, expected)
        elif kind == 'number':
            assert isinstance(value, (int, float)) and not isinstance(value, bool) and value == expected
        else:
            assert type(value) is type(expected) and value == expected, (kind, value, expected)
        assert encode(client.find('cards', identity)[0]) == before, 'GET mutated BSON'
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

    # Live Mongo values, rather than current definitions, determine shared output.
    special = [dict(_id='text',value='true',unknown='private'),
               dict(_id='bool',value=True),dict(_id='number',value=9007199254740993),
               dict(_id='array',value=['漢','one']),dict(_id='empty',value=[]),
               dict(_id='null',value=None),dict(_id='missing'),
               dict(_id='early',value=DateMs(-62167219200000)),
               dict(_id='future',value=DateMs(253402300800000)),
               dict(_id='minimum',value=DateMs(-8640000000000000)),
               dict(_id='maximum',value=DateMs(8640000000000000)),
               dict(_id='invalid',value=DateMs(8640000000000001))]
    assert client.command({'update':'cards','updates':[dict(q=dict(_id=identity),u={'$set':dict(customFields=special)})]})['n'] == 1
    before = snapshot()
    status, _, body = call('GET',base,None)
    assert status == 200, (status,body)
    fields = json.loads(body)['customFields']
    dates = dict(early='0000-01-01T00:00:00.000Z',future='+010000-01-01T00:00:00.000Z',
                 minimum='-271821-04-20T00:00:00.000Z',maximum='+275760-09-13T00:00:00.000Z',invalid=None)
    expected = [{key:dates.get(row['_id'],value) if key == 'value' and row['_id'] in dates else value
                 for key,value in row.items() if key in ['_id','value']} for row in special]
    assert fields == expected, (fields,expected)
    assert snapshot() == before
    # Corrupt metadata late in the array: return a complete error, never a prefix.
    where=" WHERE json_extract(_ferretdb_sjson,'$._id')=?"
    with sqlite3.connect(db) as con:
        physical=con.execute("SELECT table_name FROM _ferretdb_collections WHERE name='cards'").fetchone()[0]
        name='"'+physical.replace('"','""')+'"'
        original=con.execute('SELECT _ferretdb_sjson FROM '+name+where,(identity,)).fetchone()[0]
        corrupted=json.loads(con.execute('SELECT json(?)',(original,)).fetchone()[0])
        corrupted['$s']['p']['customFields']['i'][2]['$s']['p']['value']['t']='bool'
        con.execute('UPDATE '+name+' SET _ferretdb_sjson=jsonb(?)'+where,(json.dumps(corrupted),identity))
    try:
        status, _, body = call('GET',base,None)
        assert status == 500, (status,body)
        error=json.loads(body)
        assert 'customFields' not in error and 'unknown' not in error
    finally:
        with sqlite3.connect(db) as con:
            con.execute('UPDATE '+name+' SET _ferretdb_sjson=?'+where,(original,identity))
    assert snapshot() == before
    print('PASS: shared custom API typed GET, full-range Date JSON, missing/null values, unchanged BSON and controlled corrupt-source errors')
