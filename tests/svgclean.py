#!/usr/bin/env python3
"""An SVG attachment's sanitizer (src/wlsvg.pas), as plain data.

    FPC=/path/to/fpc python3 -I tests/svgclean.py

Each case is a file and what must and must not be in what is served - or
None for a file that is not well-formed, which is downloaded, never shown.
The negatives are the ways a script gets into an SVG: elements, handlers,
script URLs spelled with references and spaces, data: documents, styles,
DOCTYPE entities and their loops.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FPC = os.environ.get('FPC', 'fpc')
NS = 'xmlns="http://www.w3.org/2000/svg"'

# (file, must contain, must not contain) - None: not well-formed.
CASES = [
    ('<svg %s width="40" height="40" onload="window.__svgRan=1"><script>window.__svgRan=2</script>'
     '<rect width="40" height="40" fill="#2b6cb0"/></svg>' % NS, ['<rect width="40" height="40" fill="#2b6cb0"></rect>', '<svg '],
     ['script', 'onload', '__svgRan']),
    ('<?xml version="1.0"?><svg %s><circle r="1"/></svg>' % NS, ['<?xml version="1.0"?>', '<circle r="1"></circle>'], []),
    ('<svg %s><a href="&#x6A;avascript:alert(1)"><text>x</text></a></svg>' % NS, ['<a>', '<text>x</text>'], ['alert', 'href']),
    ('<svg %s><a xlink:href="java&#9;script:alert(1)">x</a></svg>' % NS, ['<a>x</a>'], ['alert']),
    ('<svg %s><a href=" JaVaScRiPt:alert(1)">x</a></svg>' % NS, ['<a>x</a>'], ['alert']),
    ('<svg %s><image href="data:text/html,&lt;script&gt;alert(1)&lt;/script&gt;"/></svg>' % NS, ['<image></image>'], ['data:text/html']),
    ('<svg %s><image href="data:image/png;base64,AAAA"/></svg>' % NS, ['href="data:image/png;base64,AAAA"'], []),
    ('<svg %s><rect style="width:expression(alert(1))"/><rect style="fill:red"/></svg>' % NS,
     ['<rect></rect>', 'style="fill:red"'], ['expression']),
    ('<svg %s><style>@import url(//evil.example/x.css);</style><style>rect{fill:red}</style></svg>' % NS,
     ['<style>rect{fill:red}</style>'], ['@import', 'evil']),
    ('<svg %s><foreignObject><div onclick="x()">html</div></foreignObject><g/></svg>' % NS, ['<g></g>'], ['html', 'onclick', 'foreign']),
    ('<svg %s><animate attributeName="href" to="javascript:alert(1)"/><set attributeName="onload"/><g/></svg>' % NS,
     ['<g></g>'], ['animate', '<set', 'javascript']),
    ('<svg %s><g ONMOUSEOVER="x()" xlink:onclick="y()"/></svg>' % NS, ['<g></g>'], ['x()', 'y()']),
    ('<svg %s><!-- <script>alert(1)</script> --><g/></svg>' % NS, ['<g></g>'], ['alert', '<!--']),
    ('<svg %s><text><![CDATA[a<b & "c"]]></text></svg>' % NS, ['<text>a&lt;b &amp; &#34;c&#34;</text>'], ['CDATA']),
    ('<svg %s><?php echo 1 ?><g/></svg>' % NS, ['<g></g>'], ['php']),
    ('<!DOCTYPE svg [<!ENTITY x "y">]><svg %s><g/></svg>' % NS, ['<g></g>'], ['DOCTYPE', 'ENTITY']),
    ('<svg %s><text>&amp;&lt;&#233;&#x1F600;</text></svg>' % NS, ['<text>&amp;&lt;é\U0001F600</text>'], []),
    ('<svg %s><text>Ääkköset 漢字</text></svg>' % NS, ['Ääkköset 漢字'], []),
    # Not well-formed: downloaded, never shown.
    ('<!DOCTYPE svg [<!ENTITY a "aaaa"><!ENTITY b "&a;&a;&a;">]><svg %s><text>&b;</text></svg>' % NS, None, None),
    ('<svg %s><g></svg>' % NS, None, None),
    ('<svg %s><g></h></svg>' % NS, None, None),
    ('<svg %s></svg><svg %s></svg>' % (NS, NS), None, None),
    ('<svg %s><g a="1"b="2"/></svg>' % NS, None, None),
    ('<svg %s><g a=1/></svg>' % NS, None, None),
    ('<svg %s><text>&#0;</text></svg>' % NS, None, None),
    ('<svg %s>' % NS, None, None),
    ('not xml', None, None),
    ('', None, None),
]


def q(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    base = Path(os.environ.get('TMPDIR') or tempfile.gettempdir())
    with tempfile.TemporaryDirectory(prefix='svgclean.', dir=base) as name:
        tmp = Path(name)
        L = ['program svgcheck;', '{$mode objfpc}{$H+}', '{$CODEPAGE UTF8}', 'uses SysUtils, wlsvg;',
             'var O, R: string; C: Boolean;', 'begin']
        for text, _, _ in CASES:
            L.append("  if SanitizeSvg(%s, O, C, R) then WriteLn('+', StringReplace(O, #10, ' ', [rfReplaceAll])) else WriteLn('-');" % q(text))
        L += ["  WriteLn(IsSvg('image/svg+xml; charset=utf-8', 'x'), IsSvg('', 'a.SVG?x=1'), IsSvg('image/png', 'a.png'));", 'end.']
        src = tmp / 'svgcheck.lpr'
        src.write_text('\n'.join(L) + '\n', encoding='utf-8')
        out = tmp / 'build'
        out.mkdir()
        r = subprocess.run([FPC, '-B', '-Fu' + str(ROOT / 'src'), '-FU' + str(out), '-FE' + str(out), str(src)],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert r.returncode == 0, r.stdout
        got = subprocess.run([str(out / 'svgcheck')], capture_output=True, check=True).stdout.decode('utf-8').split('\n')
        failed = 0
        for (text, need, never), line in zip(CASES, got):
            ok = line == '-' if need is None else (line.startswith('+') and all(n in line for n in need) and
                                                     not any(n.lower() in line.lower() for n in never))
            if not ok:
                failed += 1
                print('FAIL: %r\n  got %r' % (text[:90], line[:300]))
        assert got[len(CASES)] == 'TRUETRUEFALSE', got[len(CASES)]
        assert failed == 0, failed
    print('PASS: SVG sanitizer, %d files' % len(CASES))


if __name__ == '__main__':
    sys.exit(main())
