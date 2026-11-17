"""Real-server checks for definition-directed SQL custom-value insertion."""
import json
from wire import Binary, DateMs, Long, encode


def run(client, sql):
    def q(value):
        return "'" + value.replace("'", "''") + "'"

    identity = 'custom-insert-card'
    rows = [dict(_id='source-only', value=DateMs(-7), other=Binary(b'keep', 4))]
    document = dict(_id=identity, boardId='board', listId='list', title='Insert types',
                    customFields=rows, unknown=dict(date=DateMs(-9), long=Long(9007199254740993)))
    assert client.command({'insert': 'cards', 'documents': [document]})['n'] == 1
    types = ['text', 'number', 'currency', 'checkbox', 'date', 'dropdown',
             'dropdownMultiSelect', 'stringtemplate', 'future']
    definitions = [dict(_id='insert-' + kind, name=kind, type=kind, unknown=DateMs(-1))
                   for kind in types]
    assert client.command({'insert': 'customFields', 'documents': definitions})['n'] == len(types)

    def equal():
        actual = client.find('cards', identity)[0]
        assert encode(actual) == encode(document), (actual, document)

    def statement(kind, expression):
        return ('INSERT INTO card_custom_field_values(cardId,customFieldId,value) VALUES(' +
                q(identity) + ',' + q('insert-' + kind) + ',' + expression + ');')

    cases = [
        ('text', q('true'), 'true'),
        ('number', q('12.5'), 12.5),
        ('currency', q('120.25'), 120.25),
        ('checkbox', '1', True),
        ('date', q('1969-12-31T23:59:59.999Z'), DateMs(-1)),
        ('dropdown', q('option'), 'option'),
        ('dropdownMultiSelect', q(json.dumps(['option', '漢字', '\\value\\'])), ['option', '漢字', '\\value\\']),
        ('stringtemplate', q('["literal"]'), '["literal"]'),
    ]
    for kind, expression, expected in cases:
        assert sql(statement(kind, expression), 'exec') == 'ok', kind
        rows.append(dict(_id='insert-' + kind, value=expected))
        equal()
        assert sql(statement(kind, expression), 'exec') == 'error', kind
        equal()
    # Definitions are read for this statement, rather than frozen at installation.
    assert client.command({'update': 'customFields', 'updates': [
        {'q': {'_id': 'insert-future'}, 'u': {'$set': {'type': 'date'}}}]})['n'] == 1
    assert sql(statement('future', '1234'), 'exec') == 'ok'
    rows.append(dict(_id='insert-future', value=DateMs(1234)))
    equal()
    for kind, expression, _ in cases:
        assert sql('DELETE FROM card_custom_field_values WHERE cardId=' + q(identity) +
                   ' AND customFieldId=' + q('insert-' + kind) + ';', 'exec') == 'ok'
        rows.remove(next(row for row in rows if row['_id'] == 'insert-' + kind))
        equal()
    for kind, expression in [
        ('number', q('no number')), ('number', q('Infinity')),
        ('currency', q('NaN')), ('checkbox', '2'), ('checkbox', q('yes')),
        ('date', '1.5'), ('date', q('bad date')),
        ('dropdownMultiSelect', q('[1]')), ('dropdownMultiSelect', q('{}')),
        ('dropdownMultiSelect', q('[],"extra":true')), ('missing', q('text')),
    ]:
        assert sql(statement(kind, expression), 'exec') == 'error', kind
        equal()
    assert client.command({'update': 'customFields', 'updates': [
        {'q': {'_id': 'insert-text'}, 'u': {'$set': {'type': 'unsupported'}}}]})['n'] == 1
    assert sql(statement('text', q('do not guess')), 'exec') == 'error'
    equal()
    assert client.command({'update': 'customFields', 'updates': [
        {'q': {'_id': 'insert-text'}, 'u': {'$set': {'type': 'text'}}}]})['n'] == 1
    # A later invalid row rolls back an earlier valid insert in the same statement.
    bulk = ('INSERT INTO card_custom_field_values(cardId,customFieldId,value) VALUES(' +
            q(identity) + ",'insert-text','valid'),(" + q(identity) + ",'insert-checkbox',2);")
    assert sql(bulk, 'exec') == 'error'
    equal()
    # Both missing and empty source arrays can acquire a BSON Date.
    for present in [False, True]:
        patch = {'$set': {'customFields': []}} if present else {'$unset': {'customFields': ''}}
        assert client.command({'update': 'cards', 'updates': [{'q': {'_id': identity}, 'u': patch}]})['n'] == 1
        assert sql(statement('date', '-1234'), 'exec') == 'ok'
        assert encode(client.find('cards', identity)[0]['customFields'][0]) == encode(
            dict(_id='insert-date', value=DateMs(-1234)))
    assert sql('DELETE FROM cards WHERE id=' + q(identity) + ';', 'exec') == 'ok'
    for definition in definitions:
        assert sql('DELETE FROM custom_fields WHERE id=' + q(definition['_id']) + ';', 'exec') == 'ok'
