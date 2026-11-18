"""Checklist CRUD against live WeKan-shaped FerretDB documents."""
import json

from wire import DateMs


def run(request, client, token, card):
    card_id = card['_id']
    base = '/api/boards/b/cards/' + card_id + '/checklists'

    def call(method, path, data=None):
        status, _, body = request(method, path, data, token)
        assert status == 200, (method, path, status, body)
        return json.loads(body)

    # WeKan writes cardId and checklistId without denormalized boardId.
    assert client.command({'insert': 'checklists', 'documents': [
        dict(_id='legacy-checklist', cardId=card_id, title='Legacy', sort=0,
             createdAt=DateMs(0), modifiedAt=DateMs(0))]})['n'] == 1
    assert client.command({'insert': 'checklistItems', 'documents': [
        dict(_id='legacy-item', checklistId='legacy-checklist', cardId=card_id,
             title='Legacy item', sort=0, isFinished=False, modifiedAt=DateMs(0))]})['n'] == 1

    legacy = base + '/legacy-checklist'
    assert call('GET', legacy)['items'][0]['_id'] == 'legacy-item'
    assert call('PUT', legacy + '/items/legacy-item', dict(isFinished=True)) == {'_id': 'legacy-item'}
    assert call('GET', legacy + '/items/legacy-item')['isFinished'] is True
    assert call('PUT', legacy, dict(title='Renamed')) == {'_id': 'legacy-checklist'}

    due = '2026-11-18T07:30:00.123Z'
    identity = call('POST', base, dict(title='Checklist', items=['first','second'], dueAt=due))['_id']
    path = base + '/' + identity
    stored = client.find('checklists', identity)[0]
    assert isinstance(stored['dueAt'], DateMs)
    checklist = call('GET', path)
    assert checklist['dueAt'] == due and [item['title'] for item in checklist['items']] == ['first','second']
    assert checklist in call('GET', base)
    card_path = '/api/boards/b/lists/' + card['listId'] + '/cards/' + card_id
    assert checklist in call('GET', card_path)['checklists']
    item_id = call('POST', path + '/items', dict(title='Deadline', dueAt=due))['_id']
    assert client.find('checklistItems', item_id)[0]['dueAt'] == stored['dueAt']
    assert isinstance(client.find('checklistItems', item_id)[0]['dueAt'], DateMs)
    assert call('PUT', path + '/items/' + item_id, dict(dueAt=None)) == {'_id': item_id}
    assert call('GET', path + '/items/' + item_id)['dueAt'] is None
    assert call('PUT', path, dict(dueAt=None)) == {'_id': identity}
    assert call('GET', path)['dueAt'] is None
    assert call('DELETE', path) == {'_id': identity}
    assert client.find('checklists', identity) == []
    assert client.find('checklistItems', item_id) == []
    assert call('DELETE', legacy) == {'_id': 'legacy-checklist'}
    assert client.find('checklistItems', 'legacy-item') == []
    print('PASS: live shared checklist and item CRUD, typed deadlines and legacy card ownership')
