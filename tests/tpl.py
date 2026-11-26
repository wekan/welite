#!/usr/bin/env python3
"""Weddy's page templates drawn by src/wltpl.pas, as plain data.

    FPC=/path/to/fpc python3 -I tests/tpl.py

Each case is a template (Go's html/template text, as Joker/jade makes it of
Weddy's Pug), the JSON it is drawn over and what it gives - or None for one
that must be refused (an unknown function, an if without its end, an end
without an if): never a page drawn half. The values are HTML-escaped, so a
title cannot become markup. The translation cases ({{t}}, copula) are drawn
by the browser tests of the Rules page, which uses them.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FPC = os.environ.get('FPC', 'fpc')

DATA = {'Board': {'ID': 'b1', 'Title': '<b>"Mine" & yours</b>'}, 'CanEdit': True, 'No': False, 'Zero': 0, 'Empty': [],
        'Rules': [{'ID': 'r1', 'Title': 'One', 'Actions': ['a', 'b']}, {'ID': 'r2', 'Title': "It's", 'Actions': []}],
        'Map': {'k': 'v'}, 'View': 'list'}
CASES = [
    ('<h1>{{.Board.Title}}</h1>', '<h1>&lt;b&gt;&#34;Mine&#34; &amp; yours&lt;/b&gt;</h1>'),
    ('{{ if .CanEdit }}yes{{ else }}no{{ end }}', 'yes'),
    ('{{ if .No }}yes{{ else }}no{{ end }}', 'no'),
    ('{{ if .Zero }}yes{{ end }}|{{ if .Empty }}yes{{ end }}|{{ if .Missing }}yes{{ end }}', '||'),
    ('{{ if not .No }}not{{ end }}', 'not'),
    ('{{ if and .CanEdit (eq .View "list") }}both{{ end }}', 'both'),
    ('{{ if and .CanEdit (eq .View `workflow`) }}both{{ else }}one{{ end }}', 'one'),
    ('{{ if or .No .Zero }}x{{ else }}neither{{ end }}', 'neither'),
    ('{{ range .Rules }}[{{.ID}}:{{.Title}}:{{ range .Actions }}{{.}}{{ else }}none{{ end }}]{{ end }}',
     '[r1:One:ab][r2:It&#39;s:none]'),
    ('{{ range .Empty }}x{{ else }}empty{{ end }}', 'empty'),
    ('{{ range .Rules }}{{ if eq .ID $.Rules }}{{ end }}{{$.Board.ID}}{{ end }}', 'b1b1'),
    ('{{len .Rules}} {{len .Empty}} {{index .Map "k"}}', '2 0 v'),
    ('{{/* a comment */}}plain', 'plain'),
    # Negative: refused, never half drawn.
    ('{{ nosuch .View }}', None),
    ('{{ if .CanEdit }}open', None),
    ('closed{{ end }}', None),
    ('{{ .View', None),
    ('{{ eq .View "list }}', None),
]


def q(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    base = Path(os.environ.get('TMPDIR') or tempfile.gettempdir())
    with tempfile.TemporaryDirectory(prefix='tpl.', dir=base) as name:
        tmp = Path(name)
        L = ['program tplcheck;', '{$mode objfpc}{$H+}', '{$CODEPAGE UTF8}', 'uses SysUtils, fpjson, jsonparser, wltpl;',
             'var D: TJSONObject;', 'procedure Try_(const T: string);', 'var S: string;', 'begin',
             "  try S := RenderTemplate(T, D, nil, 'en'); WriteLn('=', StringReplace(S, #10, '\\n', [rfReplaceAll]));",
             "  except on E: Exception do WriteLn('-'); end;", 'end;', 'begin',
             '  D := TJSONObject(GetJSON(%s));' % q(json.dumps(DATA))]
        L += ['  Try_(%s);' % q(t) for t, _ in CASES]
        L += ['  D.Free;', 'end.']
        src = tmp / 'tplcheck.lpr'
        src.write_text('\n'.join(L) + '\n', encoding='utf-8')
        out = tmp / 'build'
        out.mkdir()
        r = subprocess.run([FPC, '-B', '-Fu' + str(ROOT / 'src'), '-FU' + str(out), '-FE' + str(out), str(src)],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert r.returncode == 0, r.stdout
        got = subprocess.run([str(out / 'tplcheck')], capture_output=True, check=True, text=True).stdout.split('\n')
        failed = 0
        for (t, want), line in zip(CASES, got):
            expect = '-' if want is None else '=' + want
            if line != expect:
                failed += 1
                print('FAIL: %r\n  got  %s\n  want %s' % (t, line, expect))
        assert failed == 0, failed
    print('PASS: templates, %d cases' % len(CASES))


if __name__ == '__main__':
    sys.exit(main())
