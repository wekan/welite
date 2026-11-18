"""Compare the Pascal list lifecycle digest with the actual WeKan hash."""
import json
import hashlib
import os
import random
import struct
import math
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
oracle = root.parents[2] / 'models/lib/changeHistoryIntegrity.js'
rows = []
for restoring in (False, True):
    before = dict(deleted=restoring, deleteBatchId='batch/漢')
    after = dict(deleted=not restoring, deleteBatchId='batch/漢')
    (before if restoring else after)['deletedAt'] = '2026-11-18T08:20:00.125Z'
    rows.append(dict(boardId='board', swimlaneId='', listId='list', cardId=None, entityType='list',
                     entityId='list', group='lifecycle', changeType='added' if restoring else 'removed',
                     previousContent=before, newContent=after, userId='u"\\\n',
                     createdAt='2026-11-18T08:20:01.001Z', batchId='batch/漢',
                     restoredFromId=None, restoredByUserId=None, previousHash='a'*64 if restoring else None))
rows.append(dict(rows[0], undone=True, superseded=True))
def typed(value):
    if value is None:
        return {'t': 'null'}
    if isinstance(value, bool):
        return {'t': 'bool'}
    if isinstance(value, float):
        return {'t': 'double'}
    if isinstance(value, int):
        return {'t': 'int'}
    if isinstance(value, str):
        return {'t': 'string'}
    if isinstance(value, list):
        return {'t': 'array', 'i': [typed(item) for item in value]}
    return {'t': 'object', '$s': {'$k': list(value), 'p': {key: typed(item) for key,item in value.items()}}}

card = dict(_id='card-history', boardId='board', cardId='card', createdAt=123, previousHash=None,
            newContent={'deletedAt': 'literal', 'timestamp': 456, '\ue000': [False, None, 1], '😀': {}})
schema = typed(card)['$s']
schema['p']['createdAt']['t'] = 'date'
schema['p']['newContent']['$s']['p']['timestamp']['t'] = 'date'
rows.append(dict(card, **{'$s': schema}))

rng = random.Random(137)
numbers = [0.0, -0.0, 0.1, -0.125, 0.000001, 0.0000001, 1e20, 1e21, 5e-324,
           2.2250738585072014e-308, 1.7976931348623157e308, 1000000000000000100.0]
for exponent in (-1074, -1022, -53, -1, 0, 52, 53, 1023):
    number = math.ldexp(1.0, exponent)
    numbers.extend((math.nextafter(number, 0.0), number, math.nextafter(number, math.inf)))
for _ in range(2048):
    number, = struct.unpack('>d', rng.getrandbits(64).to_bytes(8, 'big'))
    if math.isfinite(number):
        numbers.append(number)
for number in numbers:
    row = dict(card, newContent=number)
    schema = typed(row)['$s']
    schema['p']['createdAt']['t'] = 'date'
    rows.append(dict(row, **{'$s': schema}))

protected = ('batchId', 'boardId', 'cardId', 'changeType', 'createdAt', 'entityId', 'entityType',
             'group', 'listId', 'newContent', 'previousContent', 'previousHash', 'restoredByUserId',
             'restoredFromId', 'swimlaneId', 'userId')
undefined = {'$undefined': True}
for variant in ('undefined', 'cleaned', 'combined', 'tampered'):
    row = dict(boardId='board', newContent={'added': 2}, previousContent={'removed': 1}, cardId=None)
    original = {key: row.get(key, undefined) for key in protected}
    if variant != 'cleaned':
        original.update(newContent={'added': 2, 'removed': undefined},
                        previousContent={'added': undefined, 'removed': 1})
    if variant != 'undefined':
        original.update(cardId='', group='')
    row['integrityHash'] = hashlib.sha256(json.dumps(original, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if variant == 'tampered':
        row['newContent']['added'] = 3
    rows.append(dict(row, **{'$s': typed(row)['$s']}))

payload = ''.join(json.dumps(row, ensure_ascii=False)+'\n' for row in rows)
node = r"""
const { hashHistoryRow, rowHashIsValid, canonical, sha256 } = require(process.argv[1]);
const fs = require('node:fs');
for (const line of fs.readFileSync(0, 'utf8').trimEnd().split('\n')) {
  function decode(value, schema) {
    switch (schema.t) {
      case 'object': return Object.fromEntries(Object.entries(schema.$s.p || {}).map(
        ([key, item]) => [key, decode(value[key], item)]));
      case 'array': return value.map((item, index) => decode(item, schema.i[index]));
      case 'date': return new Date(value);
      default: return value;
    }
  }
  const input = JSON.parse(line);
  const row = input.$s ? decode(input, { t: 'object', $s: input.$s }) :
    JSON.parse(line, (key, value) =>
      (key === 'createdAt' || key === 'deletedAt') && typeof value === 'string' ? new Date(value) : value);
  console.log(rowHashIsValid(row) ? row.integrityHash : hashHistoryRow(row), sha256(canonical(row)));
}
"""
expected = subprocess.check_output([os.environ.get('NODE','node'), '-e', node, str(oracle)], input=payload, text=True)
with tempfile.TemporaryDirectory(prefix='wlchhash-',dir=os.environ['TMPDIR']) as directory:
    subprocess.run([os.environ.get('FPC','fpc'),'-B','-Fu'+str(root/'src'),'-FU'+directory,
                    '-FE'+directory,str(root/'tests/chhash.lpr')],check=True,capture_output=True)
    actual = subprocess.check_output([str(Path(directory)/'chhash')],input=payload,text=True)
for row, got, want in zip(rows, actual.splitlines(), expected.splitlines(), strict=True):
    assert got == want, (row, got, want)
print('PASS: list lifecycle and typed reservation hashes match the WeKan implementation')
