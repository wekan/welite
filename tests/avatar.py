#!/usr/bin/env python3
"""WeKan's avatarDisplayUrl (models/lib/avatarDisplayUrl.js) in Pascal
(src/wlavatar.pas), compared with the same cases run through WeKan's own
JavaScript when Node.js is there.

    FPC=/path/to/fpc [NODE=/path/to/node] [WEKAN=/path/to/wekan] python3 -I tests/avatar.py

A stored avatar URL is a name: the host or the old ROOT_URL path before
/cdn/storage/avatars/ (or CollectionFS's /cfs/files/avatars/) is dropped and
the current path put in its place. The negative cases - an external picture,
an avatar path inside another URL's query, a scheme that is not http(s), an
empty name - stay exactly as stored.
"""
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FPC = os.environ.get('FPC', 'fpc')

CASES = [
    # (stored, prefix, expected)
    ('/cdn/storage/avatars/abc', '', '/cdn/storage/avatars/abc'),
    ('/cdn/storage/avatars/abc', '/wekan', '/wekan/cdn/storage/avatars/abc'),
    ('/cdn/storage/avatars/abc', '/wekan/', '/wekan/cdn/storage/avatars/abc'),
    ('/wekan/cdn/storage/avatars/abc', '', '/cdn/storage/avatars/abc'),
    ('https://old-name.example/wekan/cdn/storage/avatars/subPathAvatar1', '', '/cdn/storage/avatars/subPathAvatar1'),
    ('http://old:3000/cdn/storage/avatars/x/original/x.png?x=1', '/w', '/w/cdn/storage/avatars/x/original/x.png'),
    ('/cfs/files/avatars/old1', '/wekan', '/wekan/cfs/files/avatars/old1'),
    ('https://h/cdn/storage/avatars/', '', 'https://h/cdn/storage/avatars/'),
    ('https://h/cdn/storage/avatars/?a', '', 'https://h/cdn/storage/avatars/?a'),
    # Negative: not WeKan's avatar.
    ('https://example.com/picture.png', '/wekan', 'https://example.com/picture.png'),
    ('data:image/png;base64,AAAA', '', 'data:image/png;base64,AAAA'),
    ('https://evil.example/?next=/cdn/storage/avatars/abc', '', 'https://evil.example/?next=/cdn/storage/avatars/abc'),
    ('javascript:/cdn/storage/avatars/abc', '', 'javascript:/cdn/storage/avatars/abc'),
    ('ftp://h/cdn/storage/avatars/abc', '', 'ftp://h/cdn/storage/avatars/abc'),
    ('https:///cdn/storage/avatars/abc', '', 'https:///cdn/storage/avatars/abc'),
    ('', '', ''),
]


def q(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    with tempfile.TemporaryDirectory(prefix='wlavatar-', dir=os.environ.get('TMPDIR')) as tmp:
        program = Path(tmp) / 'avatart.pas'
        lines = ['program avatart;', '{$mode objfpc}{$H+}', 'uses wlavatar;', 'begin']
        for stored, prefix, _ in CASES:
            lines.append('  WriteLn(AvatarDisplayUrl(' + q(stored) + ',' + q(prefix) + '));')
        lines.append('end.')
        program.write_text('\n'.join(lines) + '\n')
        subprocess.run([FPC, '-Fu' + str(ROOT / 'src'), '-FU' + tmp, '-FE' + tmp, str(program)],
                       check=True, capture_output=True)
        got = subprocess.run([str(Path(tmp) / 'avatart')], check=True, capture_output=True, text=True).stdout.split('\n')
    for (stored, prefix, expected), value in zip(CASES, got):
        assert value == expected, (stored, prefix, value, expected)
    print('PASS: avatarDisplayUrl drops an old host and path prefix, keeps the current one, and leaves the rest as stored')
    wekan, node = os.environ.get('WEKAN'), os.environ.get('NODE')
    if wekan and node and (Path(wekan) / 'models/lib/avatarDisplayUrl.js').exists():
        script = ("const {avatarDisplayUrl}=require(process.argv[1]);"
                  "const cases=JSON.parse(process.argv[2]);"
                  "console.log(JSON.stringify(cases.map(([s,p])=>avatarDisplayUrl(s,p))));")
        out = subprocess.run([node, '-e', script, str(Path(wekan) / 'models/lib/avatarDisplayUrl.js'),
                              json.dumps([[s, p] for s, p, _ in CASES])], check=True, capture_output=True, text=True).stdout
        assert json.loads(out) == [e for _, _, e in CASES], out
        print('PASS: the same cases give the same answers in WeKan\'s own avatarDisplayUrl')


if __name__ == '__main__':
    main()
