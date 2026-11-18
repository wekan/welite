"""WeKan dropdown append contract on native and shared storage."""
import json
from urllib.parse import quote, urlencode


def run(call, board, snapshot, stored, fail, clear):
    fields = '/api/boards/' + quote(board, safe='') + '/custom-fields'
    for initial in [None, [], [dict(_id='first', name='First')]]:
        settings = dict(future=dict(keep=True))
        if initial is not None:
            settings['dropdownItems'] = initial
        status, _, body = call('POST', fields, dict(name='Append options', type='dropdown', settings=settings))
        assert status == 200, (status, body)
        identity = json.loads(body)['_id']
        field = fields + '/' + quote(identity, safe='')
        route = field + '/dropdown-items'

        before = snapshot()
        for data in [{}, dict(items='ignored'), dict(items=[None, 1, {}])]:
            status, _, body = call('POST', route, data)
            assert status == 200 and json.loads(body) == dict(_id=identity), (status, body)
            assert snapshot() == before
        status, _, body = call('POST', fields + '/missing/dropdown-items', dict(items=['new']))
        assert status == 404 and json.loads(body) == dict(error='Custom field not found'), (status, body)
        assert snapshot() == before
        fail('append')
        try:
            status, _, body = call('POST', route, dict(items=['Before failure', 'Fail append']))
            assert status == 500, (status, body)
            assert snapshot() == before
        finally:
            clear()

        expected = list(initial or [])
        for data, names in [(dict(items=['Unicode 漢', 42, 'Unicode 漢']), ['Unicode 漢', 'Unicode 漢']),
                            (urlencode(dict(items=json.dumps(['Quoted "name"\nnext']))), ['Quoted "name"\nnext'])]:
            status, _, body = call('POST', route, data)
            assert status == 200 and json.loads(body) == dict(_id=identity), (status, body)
            status, _, body = call('GET', field, None)
            assert status == 200, (status, body)
            items = json.loads(body)['settings']['dropdownItems']
            assert items[:len(expected)] == expected
            assert [item['name'] for item in items[len(expected):]] == names
            assert len({item['_id'] for item in items}) == len(items)
            expected = items
            stored(identity, dict(settings, dropdownItems=expected))
    print('PASS: dropdown append initializes missing arrays, preserves order and settings, filters nonstrings and rolls back the complete batch')
