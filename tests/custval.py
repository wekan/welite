"""Existing custom-value SQL edits retain Mongo types and unrelated BSON."""
import json
from wire import DateMs, Long, Binary, encode


def run(client, sql):
    def q(value):
        return "'" + value.replace("'", "''") + "'"

    identity = 'typed-custom-card'
    values = [
        dict(_id='text', value='true'),
        dict(_id='number', value=12),
        dict(_id='long', value=Long(9007199254740993)),
        dict(_id='double', value=1.25),
        dict(_id='bool', value=True),
        dict(_id='date', value=DateMs(-1)),
        dict(_id='array', value=['one', '漢字']),
        dict(_id='empty', value=[]),
        dict(_id='missing'),
        dict(_id='unknown', value=Binary(b'preserve', 4)),
    ]
    for row in values:
        row['other'] = dict(date=DateMs(7), long=Long(9007199254740993))
    document = dict(_id=identity, boardId='board', listId='list', title='Typed',
                    customFields=values, unknown=Binary(b'root', 4))
    assert client.command({'insert': 'cards', 'documents': [document]})['n'] == 1

    def write(key, expression):
        return sql('UPDATE card_custom_field_values SET value=' + expression +
                   ' WHERE cardId=' + q(identity) + ' AND customFieldId=' + q(key) + ';', 'exec')

    def equal():
        actual = client.find('cards', identity)[0]
        assert encode(actual) == encode(document), (actual, document)

    equal()
    assert sql('UPDATE card_custom_field_values SET value=value WHERE cardId=' + q(identity) + ';', 'exec') == 'ok'
    equal()
    changes = [
        ('text', q('["still text"]'), '["still text"]'),
        ('number', '27', 27),
        ('number', q('3.5'), 3.5),
        ('long', q('9007199254740995'), Long(9007199254740995)),
        ('double', q('2.75'), 2.75),
        ('bool', '0', False),
        ('bool', q('true'), True),
        ('date', q('1970-01-01T00:00:01.234Z'), DateMs(1234)),
        ('date', '-1001', DateMs(-1001)),
        ('array', q(json.dumps(['new', '漢字', '\\quoted\\'])), ['new', '漢字', '\\quoted\\']),
        ('empty', q('["filled"]'), ['filled']),
        ('missing', q('new text'), 'new text'),
    ]
    for key, expression, expected in changes:
        assert write(key, expression) == 'ok', (key, expression)
        next(row for row in values if row['_id'] == key)['value'] = expected
        equal()
    for key, expression in [
        ('number', q('not a number')), ('number', q('Infinity')),
        ('bool', '2'), ('bool', q('yes')),
        ('date', '1.5'), ('date', q('not a date')),
        ('array', q('[1]')), ('array', q('[true]')),
        ('array', q('{}')), ('array', q('["broken"')),
        ('array', q('[],"extra":true')),
        ('unknown', q('replace binary')),
    ]:
        assert write(key, expression) == 'error', (key, expression)
        equal()
    # One bad row aborts the entire SQL statement, including earlier good rows.
    assert sql('UPDATE card_custom_field_values SET value=2 WHERE cardId=' + q(identity) +
               " AND customFieldId IN ('number','bool');", 'exec') == 'error'
    equal()
    assert sql('DELETE FROM cards WHERE id=' + q(identity) + ';', 'exec') == 'ok'
    assert client.find('cards', identity) == []
