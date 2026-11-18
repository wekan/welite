"""Compare the Pascal list lifecycle digest with the actual WeKan hash."""
import json
import os
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

payload = ''.join(json.dumps(row, ensure_ascii=False)+'\n' for row in rows)
node = r"""
const { hashHistoryRow, canonical, sha256 } = require(process.argv[1]);
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
  console.log(hashHistoryRow(row), sha256(canonical(row)));
}
"""
expected = subprocess.check_output([os.environ.get('NODE','node'), '-e', node, str(oracle)], input=payload, text=True)
with tempfile.TemporaryDirectory(prefix='wlchhash-',dir=os.environ['TMPDIR']) as directory:
    subprocess.run([os.environ.get('FPC','fpc'),'-B','-Fu'+str(root/'src'),'-FU'+directory,
                    '-FE'+directory,str(root/'tests/chhash.lpr')],check=True,capture_output=True)
    actual = subprocess.check_output([str(Path(directory)/'chhash')],input=payload,text=True)
assert actual == expected, (actual,expected)
print('PASS: list lifecycle and typed reservation hashes match the WeKan implementation')
