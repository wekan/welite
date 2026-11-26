#!/usr/bin/env python3
"""The HTML5 view's language flags (src/wlflag.pas) against WeKan's own
imports/i18n/languageFlags.js, for every language WeKan lists.

    FPC=/path/to/fpc NODE=/path/to/node WEKAN=/path/to/wekan python3 -I tests/langflag.py

Node runs WeKan's languageFlags and languageLabelParts for each tag and name
of imports/i18n/languages.js; the Pascal port must give the same flags and
the same split of the name, and a few names no language has yet.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FPC = os.environ.get('FPC', 'fpc')
NODE = os.environ.get('NODE', 'node')
WEKAN = Path(os.environ.get('WEKAN', ROOT.parent.parent.parent))

# Beyond WeKan's list: no flag, a wide parenthesis, nested ones, Spanish and
# Portuguese regions, a separator twice, and a name with no region.
EXTRA = [('xx', 'Nothing'), ('xx-ZZ', 'Nothing (Zed)'), ('zh-TW', '中文（台灣）'), ('en-GB', 'English (a (b) c)'),
         ('es-CO', 'Español de Colombia'), ('pt-BR', 'Português do Brasil'), ('ca@valencia', 'Català (Valencià)'),
         ('sr-Latn-RS', 'Srpski'), ('de-CH', 'Deutsch (Schweiz) '), ('es-AR', 'Español en')]


def main():
    base = Path(os.environ.get('TMPDIR') or tempfile.gettempdir())
    with tempfile.TemporaryDirectory(prefix='langflag.', dir=base) as name:
        tmp = Path(name)
        (tmp / 'flags.mjs').write_text((WEKAN / 'imports/i18n/languageFlags.js').read_text(encoding='utf-8'), encoding='utf-8')
        script = tmp / 'expect.mjs'
        script.write_text("""
import { languageFlags, languageLabelParts } from './flags.mjs';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const require = createRequire(import.meta.url);
const { parseLanguageMetadata } = require(%s);
const rows = parseLanguageMetadata(fs.readFileSync(%s, 'utf8')).map(r => [r[2], r[3]]).concat(%s);
console.log(JSON.stringify(rows.map(([tag, name]) => {
  const f = languageFlags(tag); const p = languageLabelParts(name, f.country);
  return [tag, name, f.language, f.country, p.languageName, p.regionName];
})));
""" % (json.dumps(str(WEKAN / 'tests/lib/languageRegistrySource.cjs')), json.dumps(str(WEKAN / 'imports/i18n/languages.js')),
            json.dumps(EXTRA)), encoding='utf-8')
        want = json.loads(subprocess.run([NODE, str(script)], capture_output=True, check=True, text=True).stdout)
        assert len(want) > 200, len(want)
        src = tmp / 'flagcheck.lpr'
        lines = ['program flagcheck;', '{$mode objfpc}{$H+}', '{$CODEPAGE UTF8}', 'uses SysUtils, wlflag;',
                 'var L, C, N, R: string;', 'begin']
        for tag, name, *_ in want:
            q = lambda s: "'" + s.replace("'", "''") + "'"
            lines += ['  LanguageFlags(%s, L, C); LanguageLabelParts(%s, C, N, R);' % (q(tag), q(name)),
                      "  WriteLn(L, #9, C, #9, N, #9, R);"]
        lines.append('end.')
        src.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        out = tmp / 'build'
        out.mkdir()
        result = subprocess.run([FPC, '-B', '-Fu' + str(ROOT / 'src'), '-Fi' + str(ROOT / 'src'), '-FU' + str(out), '-FE' + str(out), str(src)],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert result.returncode == 0, result.stdout
        got = subprocess.run([str(out / 'flagcheck')], capture_output=True, check=True).stdout.decode('utf-8').split('\n')
        failed = 0
        for row, line in zip(want, got):
            if line.split('\t') != row[2:]:
                failed += 1
                print('FAIL: %s %r\n  got  %r\n  want %r' % (row[0], row[1], line.split('\t'), row[2:]))
        assert failed == 0, failed
    print('PASS: language flags, %d tags as WeKan draws them' % len(want))


if __name__ == '__main__':
    sys.exit(main())
