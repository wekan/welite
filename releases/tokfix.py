#!/usr/bin/env python3
"""Repair unambiguous locale token spelling/case, preserving all surrounding prose.

Audit by default; --apply writes repairs. Ambiguous/missing-token cases are reported
and left for a separate translation review. No translation service or network is used.
"""
import argparse
from collections import Counter
import json
import os
import stat
import tempfile
from pathlib import Path
import re
URL=re.compile(r'''https?://[^\s<>"']+''')
OCTET=re.compile(r'%[0-9a-f]{2}',re.I)
CODE_TITLES={'act-withBoardTitle','act-withCardTitle'}
# Match the maintained WeKan protected-marker format and source numbering.
INDEXED_MARKER=re.compile(r'(?:@\s*){1,2}PH(\d+)(?:\s*@){1,2}')
PROTECTED_SOURCE=re.compile(r'`[^`]+`|<[^>]+>|__[^\s]+?__|%(?:\d+\$)?[A-Za-z]')
TOKEN=re.compile(r'__[^\s]+?__|%\{[^}]+\}|%%|%(?:\d+\$)?[-+#0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[A-Za-z]|%\d+')
def spans(value):
    octets=[]
    for url in URL.finditer(value):
        octets.extend((url.start()+part.start(),url.start()+part.end()) for part in OCTET.finditer(url[0]))
    result=[]
    for match in TOKEN.finditer(value):
        token=match[0]
        # Explicit named containers remain arguments even inside a URL. Ordinary
        # percent octets are URL bytes, including overlaps with a literal %%.
        named=token.startswith('__') or token.startswith('%{')
        if not named and any(match.start()<end and match.end()>start for start,end in octets):continue
        result.append((match.start(),match.end(),token))
    return result
def tokens(value):return Counter(token for _,_,token in spans(value))
def prose(value):
    parts=[];at=0
    for start,end,_ in spans(value):parts.append(value[at:start]);at=end
    return ''.join(parts)+value[at:]
def code_only(value):
    # Accept translated/malformed underscore argument names, including single
    # fences and spaces inside names, but never erase prose outside a container.
    remainder=prose(value)
    remainder=re.sub(r'_+[^_]+?_+','',remainder)
    return re.search(r'[^\W_]',remainder,flags=re.UNICODE) is None
def repair(source,value,key=''):
    markers=list(INDEXED_MARKER.finditer(value))
    if markers:
        protected=PROTECTED_SOURCE.findall(source)
        indexes=[int(match[1]) for match in markers]
        if len(indexes)!=len(set(indexes)) or any(index>=len(protected) for index in indexes):return None
        changed=INDEXED_MARKER.sub(lambda match:protected[int(match[1])],value)
        return changed if tokens(changed)==tokens(source) else None
    if key in CODE_TITLES and tokens(source)!=tokens(value) and code_only(source) and code_only(value):return source
    # Broken/unclosed markers or stacked fences need a separate contextual review.
    if '__' in prose(source) or '__' in prose(value) or '___' in source or '___' in value:return None
    expected=tokens(source);actual=tokens(value)
    missing=expected-actual;extra=actual-expected
    if not missing and not extra:return None
    mapping={}
    if sum(missing.values())==sum(extra.values())==1:
        old=next(iter(extra));new=next(iter(missing))
        # Repeated occurrences cannot tell us which argument was mistranslated.
        if actual[old]!=1:return None
        mapping[old]=new
    elif sum(missing.values())==sum(extra.values()) and extra:
        available=missing.copy()
        for old,count in extra.items():
            choices=[new for new in available if new.casefold()==old.casefold() and available[new]>=count]
            if len(choices)!=1 or expected[old]!=0:return None
            new=choices[0];mapping[old]=new;available[new]-=count
            if not available[new]:del available[new]
        if available:return None
    else:return None
    parts=[];at=0
    for start,end,token in spans(value):
        parts.extend([value[at:start],mapping.get(token,token)]);at=end
    changed=''.join(parts)+value[at:]
    if tokens(changed)!=expected or prose(changed)!=prose(value):
        raise ValueError('Token repair changed prose or left incompatible arguments')
    return changed
def pairs(items):
    result={}
    for key,value in items:
        if key in result:raise ValueError('Duplicate JSON key: '+key)
        result[key]=value
    return result
def load(path):
    result=json.loads(path.read_text(encoding='utf-8'),object_pairs_hook=pairs)
    if not isinstance(result,dict) or any(not isinstance(value,str) for value in result.values()):raise ValueError('Expected flat string dictionary: '+str(path))
    for key,value in result.items():key.encode('utf-8');value.encode('utf-8')
    return result
def plan(directory):
    english=load(directory/'en.jsn');changes={};deferred=0
    for path in sorted(directory.glob('*.jsn')):
        if path.name=='en.jsn' or path.is_symlink() or not path.is_file():continue
        original=load(path);updated=dict(original);keys=[]
        for key,source in english.items():
            if key not in original:continue
            value=original[key]
            if tokens(value)==tokens(source) and not INDEXED_MARKER.search(value):continue
            changed=repair(source,value,key)
            if changed is None:deferred+=1;continue
            updated[key]=changed;keys.append(key)
        if keys:changes[path]=(original,updated,keys)
    return english,changes,deferred
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data',type=Path,default=Path(__file__).resolve().parents[1]/'i18n/data')
    parser.add_argument('--apply',action='store_true');parser.add_argument('--record',type=Path)
    args=parser.parse_args()
    if args.record and not args.apply:parser.error('--record requires --apply')
    if args.record and args.record.resolve().parent==args.data.resolve():raise ValueError('Keep the repair record outside locale data')
    _,changes,deferred=plan(args.data)
    record={'version':1,'keys':{}}
    if args.record and args.record.exists():
        record=json.loads(args.record.read_text(encoding='utf-8'))
        if record.get('version')!=1 or not isinstance(record.get('keys'),dict):raise ValueError('Invalid repair record')
        for filename,keys in record['keys'].items():
            if Path(filename).name!=filename or not isinstance(keys,list) or any(not isinstance(key,str) for key in keys):raise ValueError('Invalid repair record entries')
    if args.apply:
        payloads={}
        for path,(_,updated,keys) in changes.items():
            payloads[path]=(json.dumps(updated,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
            if args.record:record['keys'][path.name]=list(dict.fromkeys(record['keys'].get(path.name,[])+keys))
        if args.record:
            payload=(json.dumps(record,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
            if not args.record.exists() or args.record.read_bytes()!=payload:payloads[args.record]=payload
        if payloads:
            temporary=os.environ.get('TMPDIR')
            if not temporary or not Path(temporary).is_dir():raise ValueError('Set TMPDIR to an existing task scratch directory')
            device=Path(temporary).stat().st_dev
            for path in payloads:
                if path.parent.stat().st_dev!=device:raise ValueError('TMPDIR must share the translation filesystem')
            # Prepare every UTF-8 payload before replacing any existing file.
            with tempfile.TemporaryDirectory(prefix='wltok-',dir=temporary) as work:
                staged=[]
                for index,(path,payload) in enumerate(payloads.items()):
                    stage=Path(work)/(f'{index:08x}'+'.jsn');stage.write_bytes(payload)
                    stage.chmod(stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644)
                    staged.append((stage,path))
                for stage,path in staged:
                    if path in changes and load(path)!=changes[path][0]:raise ValueError('Translation changed during repair: '+str(path))
                    os.replace(stage,path)
    count=sum(len(keys) for _,_,keys in changes.values())
    print(f'tokfix: {"repaired" if args.apply else "repairable"} {count} keys in {len(changes)} files; {deferred} ambiguous differences remain')
if __name__=='__main__':
    try:main()
    except (OSError,ValueError) as error:
        print('tokfix: '+str(error));raise SystemExit(1)
