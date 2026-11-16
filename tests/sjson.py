"""Actual FerretDB SJSON oracle, Pascal type retention and linked/CLI JSONB writes."""
import copy
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
tools=root.parents[1]
ferret=Path(os.environ.get('FERRET_SRC',str(root.parent/'FerretDB')))
go=os.environ.get('GO','go')
fpc=os.environ.get('FPC','fpc')
def checked(command,**kwargs):
    result=subprocess.run(command,capture_output=True,text=True,**kwargs)
    if result.returncode:raise RuntimeError(str(command)+'\n'+result.stdout+result.stderr)
    return result.stdout

def quote(value):return "'"+value.replace("'","''")+"'"
with tempfile.TemporaryDirectory(prefix='wlsjson-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    env=dict(os.environ,GOTOOLCHAIN='local',GOPROXY='off',GOSUMDB='off')
    for key,subdir in [('GOMODCACHE','gomodcache'),('GOCACHE','gocache'),('GOPATH','gopath')]:
        env.setdefault(key,str(tools/'go'/subdir))
    # Overlay exposes this oracle inside the internal-package boundary. No files in
    # FerretDB are edited, and the oracle uses its working source, including patches.
    overlay=tmp/'overlay.json'
    overlay.write_text(json.dumps({'Replace':{str(ferret/'internal/wlprobe/main.go'):str(root/'tests/ferjson.go')}}))
    mod=(ferret/'go.mod').read_text()
    for package in ['github.com/AlekSi/pointer','golang.org/x/exp']:
        version=re.search(r'^\s*'+re.escape(package)+r'\s+(\S+)',mod,re.M).group(1)
        escaped=''.join('!'+c.lower() if c.isupper() else c for c in package)
        cached=Path(env['GOMODCACHE'])/(escaped+'@'+version)
        if cached.is_dir():mod+='\nreplace '+package+' => '+json.dumps(str(cached))+'\n'
    (tmp/'probe.mod').write_text(mod);shutil.copyfile(ferret/'go.sum',tmp/'probe.sum')
    checked([go,'build','-mod=mod','-modfile',str(tmp/'probe.mod'),'-overlay',str(overlay),'-o',str(tmp/'oracle'),'./internal/wlprobe'],cwd=ferret,env=env)
    oracle=tmp/'oracle'
    fixtures=checked([str(oracle),'seed']).splitlines()
    def oracle_bits(source):return json.loads(checked([str(oracle),'bits'],input=source+'\n'))
    def build(source,out,flags=(),name=None):
        out.mkdir(exist_ok=True)
        checked([fpc,*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),*(['-o'+str(out/name)] if name else []),str(source)])
    build(root/'tests/sjson.lpr',tmp/'codec')
    def codec(new='{}',old='',hints='{}',mode='encode'):
        command=json.dumps(dict(new=new,old=old,hints=hints,mode=mode),ensure_ascii=False)+'\n'
        return json.loads(checked([str(tmp/'codec/sjson')],input=command))
    def oracle_decode(value):
        data=json.dumps(value,ensure_ascii=False,separators=(',',':'))
        return json.loads(checked([str(oracle)],input=data+'\n'))
    for source in fixtures:
        old=json.loads(source);plain={k:v for k,v in old.items() if k!='$s'}
        assert codec(old=source,mode='plain')==plain
        plain['title']='Changed 日本語 <>& " \\ \0 😀'
        encoded=codec(json.dumps(plain,ensure_ascii=False),source)
        assert oracle_decode(encoded)==encoded,(old['_id'],encoded)
        assert encoded['$s']['$k']==list(plain)
        for key,kind in old['$s']['p'].items():
            if key!='title':assert encoded['$s']['p'][key]==kind,(key,kind,encoded)
        assert {k:v for k,v in encoded.items() if k!='$s'}==plain
    assert oracle_decode(codec('{}'))=={'$s':{}}
    nested=json.loads(fixtures[1]);plain={k:v for k,v in nested.items() if k!='$s'}
    plain['profile']['language']='ar';plain['profile']['array'].reverse()
    changed=codec(json.dumps(plain,ensure_ascii=False),fixtures[1])
    assert oracle_decode(changed)==changed
    schemas=changed['$s']['p']['profile']['$s']['p']['array']['i']
    assert [item['t'] for item in schemas]==['object','date','long','int']
    hinted=codec('{"createdAt":-1,"sequence":18446744073709551615,"rank":7,"binary":"AP8K","oid":"0102030405060708090a0b0c"}',hints=json.dumps({'createdAt':'date','sequence':'timestamp','rank':'int','binary':{'t':'binData','s':4},'oid':'objectId'}))
    assert oracle_decode(hinted)==hinted and hinted['$s']['p']['rank']['t']=='int'
    emoji=codec(r'{"x":"\uD83D\uDE00"}')
    assert emoji['x']=='😀' and oracle_decode(emoji)==emoji
    deep=codec('{"x":'+('['*99)+'0'+(']'*99)+'}')
    assert 'error' not in deep and oracle_decode(deep)==deep
    removed=codec('{"_id":"document"}',fixtures[0])
    assert removed['$s']['$k']==['_id'] and list(removed['$s']['p'])==['_id']
    for invalid in [
        '{} garbage','{"bad\\u0000key":1}','{"x":1,"x":2}','{"$s":{}}','[]','{"x":01}','{"x":1e999}',
        '{"x":18446744073709551616}','{"x":'+('['*102)+'0'+(']'*102)+'}',
    ]:assert codec(invalid)=={'error':'invalid'},invalid[:80]
    for value,hint in [('"bad"','date'),('2147483648','int'),('-1','timestamp'),('"short"','objectId'),('1','unsupported')]:
        assert codec('{"x":'+value+'}',hints=json.dumps({'x':hint}))=={'error':'invalid'}
    for bad in [
        {'$s':{'$k':['x'],'p':{'x':{'t':'bool'}}},'x':'true'},
        {'$s':{'$k':['x','x'],'p':{'x':{'t':'long'}}},'x':1},
        {'$s':{'$k':[],'p':{}},'extra':1},
        {'$s':{'$k':['x'],'p':{'x':{'t':'array','i':[]}}},'x':[1]},
    ]:assert codec(old=json.dumps(bad),mode='plain')=={'error':'invalid'}
    print('PASS: FerretDB source oracle, every BSON scalar, nested/reordered type retention, Unicode/NUL/order, explicit hints and malformed/deep document denial')
    extension=tmp/'extension';build(root/'src/wlfunc.lpr',extension,['-Cg','-dWLSQLEXT'],'wlfunc.so')
    # Verify the API-table offsets against the installed authoritative C header.
    (tmp/'abi.c').write_text('#include <stddef.h>\n#include <stdio.h>\n#include <sqlite3ext.h>\nint main(void){printf("%zu %zu %zu %zu %zu %zu",offsetof(sqlite3_api_routines,create_function_v2)/sizeof(void*),offsetof(sqlite3_api_routines,value_text)/sizeof(void*),offsetof(sqlite3_api_routines,value_bytes)/sizeof(void*),offsetof(sqlite3_api_routines,result_text)/sizeof(void*),offsetof(sqlite3_api_routines,result_error)/sizeof(void*),offsetof(sqlite3_api_routines,libversion_number)/sizeof(void*));return 0;}')
    checked([os.environ.get('CC','cc'),str(tmp/'abi.c'),'-o',str(tmp/'abi')])
    assert checked([str(tmp/'abi')])=='162 109 103 85 80 67'
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=tmp/backend;build(root/'tests/sjsql.lpr',out,flags)
        settings=dict(os.environ);settings.pop('WELITE_SQLITE_EXT',None)
        if backend=='cli':settings['WELITE_SQLITE_EXT']=str(extension/'wlfunc.so')
        db=out/'shared.db'
        def sql(query,execute=False):
            output=checked([str(out/'sjsql'),str(db),*(['exec'] if execute else [])],input=query,env=settings).strip()
            return output if execute else json.loads(output)
        assert sql('SELECT json_valid(wl_sjson(\'{"_id":"test"}\',\'\',\'{}\'));')==[['1']]
        # The exact physical document column and both old TEXT/new JSONB storage
        # forms are exercised; table names are discovered from FerretDB metadata.
        assert sql('CREATE TABLE _ferretdb_collections(name TEXT UNIQUE,table_name TEXT UNIQUE,settings TEXT);',True)=='ok'
        for storage in ['text','blob']:
            table='documents_'+storage
            assert sql('CREATE TABLE '+table+'(_ferretdb_sjson '+storage.upper()+' NOT NULL) STRICT;',True)=='ok'
            assert sql('INSERT INTO _ferretdb_collections VALUES('+quote(storage)+','+quote(table)+',\'{}\');',True)=='ok'
            for source in fixtures:
                expression=('jsonb('+quote(source)+')') if storage=='blob' else quote(source)
                assert sql('INSERT INTO '+table+' VALUES('+expression+');',True)=='ok'
            assert sql('CREATE VIEW '+storage+'_view AS SELECT rowid AS record,json_extract(_ferretdb_sjson,\'$._id\') AS id,json_extract(_ferretdb_sjson,\'$.title\') AS title FROM '+table+';',True)=='ok'
            assert sql('CREATE TRIGGER '+storage+'_edit INSTEAD OF UPDATE ON '+storage+'_view BEGIN UPDATE '+table+' SET _ferretdb_sjson='+('jsonb(' if storage=='blob' else '(')+'wl_sjson(json_set(wl_plain(json(_ferretdb_sjson)),\'$.title\',NEW.title),json(_ferretdb_sjson),\'{}\')) WHERE rowid=OLD.record; END;',True)=='ok'
            assert sql('UPDATE '+storage+'_view SET title=\'SQL edited 日本語\' WHERE id=\'document\';',True)=='ok'
            stored_raw=sql('SELECT json(_ferretdb_sjson) FROM '+table+' WHERE _ferretdb_sjson->>\'$._id\'=\'document\';')[0][0]
            stored=json.loads(stored_raw)
            assert oracle_bits(stored_raw)==oracle_bits(fixtures[0]),'Float bits changed, including negative zero'
            assert stored['title']=='SQL edited 日本語' and oracle_decode(stored)==stored
            original=json.loads(fixtures[0])
            assert all(stored['$s']['p'][key]==kind for key,kind in original['$s']['p'].items() if key!='title')
            count=sql('SELECT COUNT(*) FROM '+table+';')
            assert sql('BEGIN; INSERT INTO '+table+' VALUES('+('jsonb(' if storage=='blob' else '(')+"wl_sjson('{bad','','{}'))); COMMIT;",True)=='error'
            assert sql('SELECT COUNT(*) FROM '+table+';')==count
        assert sql("SELECT wl_sjson(CAST(X'7B2278223A22FF227D' AS TEXT),'','{}');")==[]
        if backend=='cli':
            broken=dict(settings,WELITE_SQLITE_EXT=str(tmp/'missing.so'))
            result=checked([str(out/'sjsql'),str(db)],input='SELECT 1;',env=broken)
            assert json.loads(result)==[],result
        print('PASS:',backend,'same Pascal SQL functions, actual TEXT/JSONB storage, typed view edits decoded by FerretDB, atomic failure and invalid extension/UTF-8 denial')
