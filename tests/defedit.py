"""Atomic custom-field definition updates over the real HTTP router."""
import json
from urllib.parse import quote


def run(call, board, snapshot, stored, fail, clear):
    base = '/api/boards/' + quote(board, safe='') + '/custom-fields'
    original = dict(dropdownItems=[dict(_id='old', name='Old')], future=dict(remove=True))
    status, _, body = call('POST', base, dict(name='Before edit', type='dropdown', settings=original,
                                            showOnCard=True, showLabelOnMiniCard=True))
    assert status == 200, (status, body)
    identity = json.loads(body)['_id']
    route = base + '/' + quote(identity, safe='')

    before = snapshot()
    for bad in [dict(type='invalid'), dict(settings='invalid'), dict(settings=dict(dropdownItems=False))]:
        status, _, body = call('PUT', route, dict(name='Rejected', **bad))
        assert status == 500, (status, body)
        assert snapshot() == before
    for ignored in [{}, dict(boardIds=['foreign'], adminOnly=True)]:
        status, _, body = call('PUT', route, ignored)
        assert status == 200 and json.loads(body) == dict(_id=identity), (status, body)
        assert snapshot() == before

    replacement = dict(dropdownItems=[dict(_id='new', name='New'), dict(_id='second', name='Second')],
                       future=dict(keep=True))
    update = dict(name='Updated 漢', settings=replacement, showOnCard=False, showLabelOnMiniCard=False,
                  alwaysOnCard=False)
    fail('edit')
    try:
        status, _, body = call('PUT', route, update)
        assert status == 500, (status, body)
        assert snapshot() == before
    finally:
        clear()

    for settings in [replacement, dict(dropdownItems=[]), {}]:
        status, _, body = call('PUT', route, dict(update, settings=settings))
        assert status == 200 and json.loads(body) == dict(_id=identity), (status, body)
        status, _, body = call('GET', route, None)
        assert status == 200, (status, body)
        field = json.loads(body)
        assert field['settings'] == settings and field['name'] == update['name'], field
        assert field['type'] == 'dropdown' and not field['showOnCard'] and not field['showLabelOnMiniCard'], field
        stored(identity, settings)
    print('PASS: definition PUT validates and updates fields atomically, preserves omitted fields, and replaces settings and dropdown presence')
