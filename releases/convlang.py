#!/usr/bin/env python3
"""Generate browser and data-only language catalogs without executing JavaScript.

Usage: convlang.py [languages.js] [langs.jsn]
Only installed data/<filename>.jsn translations are advertised. Existing translation
bytes are never changed. Supports literal-object and compact WeKan source formats.
"""
import json
from pathlib import Path
import re
import sys
HERE=Path(__file__).resolve().parent
DEFAULT_DST=HERE.parent/'i18n/langs.jsn'
STRING=r'"(?:\\.|[^"\\])*"'
LOCAL_FILES={'ca@valencia.jsn':'cavalenc.jsn','km-KH.jsn':'km_KH.jsn','ru-RU.jsn':'ru_RU.jsn','pt-PT.jsn':'pt_PT.jsn'}
SAFE=re.compile(r'^[A-Za-z0-9][A-Za-z0-9_@.-]*$')
def compact(text):
    match=re.search(r'\bconst\s+languageMetadata\s*=\s*\[',text)
    if not match:return None
    decoder=json.JSONDecoder();at=match.end();rows=[]
    while True:
        while at<len(text) and text[at].isspace():at+=1
        if text[at:at+1]==']':break
        row,at=decoder.raw_decode(text,at);rows.append(row)
        while at<len(text) and text[at].isspace():at+=1
        if text[at:at+1]==',':at+=1
        elif text[at:at+1]!=']':raise ValueError('Malformed metadata separator')
    loaders={}
    for key,file in re.findall(r'('+STRING+r')\s*:\s*\(\)\s*=>\s*import\("\./data/([^"/]+)\.i18n\.json"\)',text):
        key=json.loads(key)
        if key in loaders:raise ValueError('Duplicate language loader')
        loaders[key]=file+'.jsn'
    result=[]
    for row in rows:
        if not isinstance(row,list) or len(row)!=5:raise ValueError('Malformed metadata row')
        key,code,tag,name,rtl=row
        if key not in loaders:raise ValueError('Missing language loader: '+str(key))
        result.append(dict(key=key,code=code,tag=tag,name=name,rtl=rtl,file=loaders[key]))
    if set(loaders)!={r['key'] for r in result}:raise ValueError('Unmatched loader')
    return result
def literal(text):
    entries=[]
    for key,body in re.findall(r'('+STRING+r')\s*:\s*\{([^{}]*)\}',text):
        fields={}
        for field in ['code','tag','name']:
            match=re.search(r'\b'+field+r'\s*:\s*('+STRING+r')',body)
            if not match:raise ValueError('Missing '+field)
            fields[field]=json.loads(match.group(1))
        rtl=re.search(r'\brtl\s*:\s*(true|false)\b',body)
        file=re.search(r'''\bload\s*:\s*\(\)\s*=>\s*import\(['"]\./data/([^/'"]+)['"]\)''',body)
        if not rtl or not file:raise ValueError('Missing direction or loader')
        entries.append(dict(key=json.loads(key),**fields,rtl=rtl.group(1)=='true',file=file.group(1)))
    return entries
def parse(text):
    entries=compact(text)
    if entries is None:entries=literal(text)
    if not entries:raise ValueError('No supported language metadata')
    keys=set();tags=set()
    for row in entries:
        for field in ['key','code','tag','file']:
            value=row[field]
            if not isinstance(value,str) or not SAFE.fullmatch(value) or '..' in value:raise ValueError('Unsafe '+field)
        if not row['file'].endswith('.jsn') or not isinstance(row['name'],str) or not row['name'] or type(row['rtl']) is not bool:raise ValueError('Invalid language metadata')
        key=row['key'];tag=row['tag']
        if key in keys or tag in tags:raise ValueError('Duplicate language identity')
        keys.add(key);tags.add(tag)
    return entries
def render(entries):
    lines=['{']
    for row in entries:
        lines.append('  '+json.dumps(row['key'])+': {')
        for field in ['code','tag','name']:lines.append('    '+field+': '+json.dumps(row[field],ensure_ascii=False)+',')
        lines.append('    load: () => import('+json.dumps('./data/'+row['file'])+'),')
        lines.append('    rtl: '+str(row['rtl']).lower()+',\n  },')
    return '\n'.join(lines)+'\n}\n'
def default_source():
    for parent in HERE.parents:
        source=parent/'imports/i18n/languages.js'
        if source.is_file():return source
    return HERE.parent.parent/'wekan/imports/i18n/languages.js'
def main():
    source=Path(sys.argv[1]) if len(sys.argv)>1 else default_source()
    destination=Path(sys.argv[2]) if len(sys.argv)>2 else DEFAULT_DST
    entries=parse(source.read_text(encoding='utf-8-sig'))
    # Preserve established local asset names instead of copying or renaming text.
    for row in entries:
        row['file']=LOCAL_FILES.get(row['file'],row['file'])
    installed=[r for r in entries if (destination.parent/'data'/r['file']).is_file()]
    if not installed:raise ValueError('No installed translations; refusing empty catalog')
    if not any(r['tag']=='en' for r in installed):raise ValueError('English fallback is missing')
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(render(installed),encoding='utf-8')
    (destination.parent/'locales.jsn').write_text(json.dumps(installed,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'convlang: {len(installed)} installed languages; {len(entries)-len(installed)} source languages await translation files')
if __name__=='__main__':
    try:main()
    except (OSError,ValueError,TypeError,IndexError) as error:
        print('convlang: '+str(error),file=sys.stderr);raise SystemExit(1)
