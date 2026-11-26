#!/usr/bin/env python3
"""The HTML5 view's Markdown viewer (src/wlmd.pas), as plain data.

    FPC=/path/to/fpc python3 -I tests/markdown.py

Each case is a text and the HTML MarkdownViewer must make of it. The negative
cases are what a user may type to run script or reach another site: none of
it may come out as markup.
"""
import json
import re
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FPC = os.environ.get('FPC', 'fpc')

CASES = [
    ('plain', '<span class="viewer">plain</span>'),
    ('[Wekan](https://example.invalid/card-title-link)',
     '<span class="viewer"><a href="https://example.invalid/card-title-link" rel="nofollow noopener" target="_blank">Wekan</a></span>'),
    ('**bold** and *em* and ~~gone~~ and `x<y`',
     '<span class="viewer"><strong>bold</strong> and <em>em</em> and <del>gone</del> and <code>x&lt;y</code></span>'),
    ('see https://wekan.fi/install.', '<span class="viewer">see <a href="https://wekan.fi/install" rel="nofollow noopener" target="_blank">https://wekan.fi/install</a>.</span>'),
    ('# Title\n\nfirst\nsecond\n\n- a\n- b\n\n1. one\n> quote',
     '<div class="viewer"><h1>Title</h1><p>first<br>second</p><ul><li>a</li><li>b</li></ul><ol><li>one</li></ol>'
     '<blockquote><p>quote</p></blockquote></div>'),
    ('```\n<b>code</b>\n```', '<div class="viewer"><pre><code>&lt;b&gt;code&lt;/b&gt;</code></pre></div>'),
    ('[home](/b/x/y) [mail](mailto:a@b.example)',
     '<span class="viewer"><a href="/b/x/y" rel="nofollow noopener" target="_blank">home</a> '
     '<a href="mailto:a@b.example" rel="nofollow noopener" target="_blank">mail</a></span>'),
    ('Ääkköset ja 漢字', '<span class="viewer">Ääkköset ja 漢字</span>'),
    # Negative: HTML is text, a script address is no link, nor another host by //.
    ('<script>alert(1)</script>', '<span class="viewer">&lt;script&gt;alert(1)&lt;/script&gt;</span>'),
    ('<img src=x onerror=alert(1)>', '<span class="viewer">&lt;img src=x onerror=alert(1)&gt;</span>'),
    ('[x](javascript:alert(1))', '<span class="viewer">x)</span>'),
    ('[x](JavaScript:alert`1`)', '<span class="viewer">x</span>'),
    ('[x](data:text/html,<b>)', '<span class="viewer">x</span>'),
    ('[x](//evil.example/)', '<span class="viewer">x</span>'),
    ('[x](https://a.example/" onclick="alert(1))', '<span class="viewer">x)</span>'),
    ('[x](https://a.example/&quot;x)', '<span class="viewer"><a href="https://a.example/&amp;quot;x" rel="nofollow noopener" target="_blank">x</a></span>'),
    ('"quoted" & \'single\'', '<span class="viewer">&quot;quoted&quot; &amp; &#39;single&#39;</span>'),
    # markdown-it-emoji: a known shortcode is its emoji, never inside code,
    # an unknown one stays text.
    (':thumbsup: :heart: :tada: :nosuchcode: `:smile:`',
     '<span class="viewer">👍 ❤️ 🎉 :nosuchcode: <code>:smile:</code></span>'),
    ('# Demo [card](https://example.com/) :thumbsup:',
     '<div class="viewer"><h1>Demo <a href="https://example.com/" rel="nofollow noopener" target="_blank">card</a> 👍</h1></div>'),
]
# Admin Panel's text display: (text, PlainLinks, PlainSource, HTML).
POLICY = [
    ('[card](https://example.com/) :tada:', True, False, '<span class="viewer">card 🎉</span>'),
    ('see https://wekan.fi/', True, False, '<span class="viewer">see https://wekan.fi/</span>'),
    ('# Demo <b>x</b>', False, True, '<div class="viewer"><pre># Demo &lt;b&gt;x&lt;/b&gt;</pre></div>'),
    ('[card](https://example.com/)', False, False,
     '<span class="viewer"><a href="https://example.com/" rel="nofollow noopener" target="_blank">card</a></span>'),
]


def main():
    base = Path(os.environ.get('TMPDIR') or tempfile.gettempdir())
    with tempfile.TemporaryDirectory(prefix='markdown.', dir=base) as name:
        tmp = Path(name)
        (tmp / 'cases.json').write_text(json.dumps([c[0] for c in CASES]))
        src = tmp / 'mdcheck.lpr'
        lines = ['program mdcheck;', '{$mode objfpc}{$H+}', '{$CODEPAGE UTF8}', 'uses SysUtils, wlmd;', 'begin']
        for text, _ in CASES:
            pascal = "'" + text.replace("'", "''").replace('\n', "'#10'") + "'"
            lines.append('  WriteLn(MarkdownViewer(%s));' % pascal)
        for text, links, source, _ in POLICY:
            pascal = "'" + text.replace("'", "''").replace('\n', "'#10'") + "'"
            lines.append('  WriteLn(MarkdownViewer(%s, %s, %s));' % (pascal, str(links), str(source)))
        lines.append('end.')
        src.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        out = tmp / 'build'
        out.mkdir()
        result = subprocess.run([FPC, '-B', '-Fu' + str(ROOT / 'src'), '-FU' + str(out), '-FE' + str(out), str(src)],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert result.returncode == 0, result.stdout
        got = subprocess.run([str(out / 'mdcheck')], capture_output=True, check=True).stdout.decode('utf-8').splitlines()
        failed = 0
        for (text, want), line in zip(CASES, got):
            if line != want:
                failed += 1
                print('FAIL: %r\n  got  %s\n  want %s' % (text, line, want))
        assert len(got) == len(CASES) + len(POLICY), got
        for (text, links, source, want), line in zip(POLICY, got[len(CASES):]):
            if line != want:
                failed += 1
                print('FAIL policy: %r\n  got  %s\n  want %s' % (text, line, want))
        # Negative, for every case: each '<' starts one of the viewer's own
        # tags, and only a link has an address - a safe one.
        allowed = re.compile(r'<(?:/?(?:p|br|h[1-6]|ul|ol|li|blockquote|pre|code|strong|em|del|span|div|a)|span class="viewer"|'
                             r'div class="viewer"|a href="(?:https?://|mailto:|/(?!/)|#)[^"<>]*" rel="nofollow noopener" target="_blank")>')
        for line in got:
            rest = allowed.sub('', line)
            assert '<' not in rest and '>' not in rest, (line, rest)
        assert failed == 0, failed
    print('PASS: Markdown viewer, %d cases' % (len(CASES) + len(POLICY)))


if __name__ == '__main__':
    sys.exit(main())
