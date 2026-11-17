"""Test-only CLI proxy forces an independent writer between graph read commands."""
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import threading
from urllib.parse import urlencode,urlsplit,parse_qs
from layout import Forms


def configure(env,out):
    directory=out/'snapbin';directory.mkdir();control=out/'snap.ctl';control.write_text('{}')
    real=shutil.which('sqlite3',path=env['PATH']);assert real
    script=directory/'sqlite3'
    script.write_text('#!'+sys.executable+'\nimport sys\nsys.path.insert(0,'+repr(str(Path(__file__).parent))+')\nfrom graphsnp import proxy\nproxy()\n');script.chmod(0o700)
    env.update(PATH=str(directory)+os.pathsep+env['PATH'],WELITE_SNAP_TEST=str(control),WELITE_SNAP_SQLITE=real)
    return control


def proxy():
    real=os.environ['WELITE_SNAP_SQLITE'];control=Path(os.environ['WELITE_SNAP_TEST'])
    settings=json.loads(control.read_text())
    if '-readonly' not in sys.argv or not settings.get('active'):os.execv(real,[real,*sys.argv[1:]])
    child=subprocess.Popen([real,*sys.argv[1:]],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    def pump(source,dest):
        while True:
            data=os.read(source.fileno(),8192)
            if not data:return
            while data:
                written=os.write(dest.fileno(),data);data=data[written:]
    threads=[threading.Thread(target=pump,args=pair) for pair in [(child.stdout,sys.stdout),(child.stderr,sys.stderr)]]
    for thread in threads:thread.start()
    seen_board=False
    try:
        for line in sys.stdin.buffer:
            if line.startswith(b'.read '):
                script=Path(json.loads(line[6:].decode().strip()));sql=script.read_text()
                if seen_board and not Path(settings['done']).exists():
                    con=sqlite3.connect(settings['database'],timeout=10)
                    try:
                        con.enable_load_extension(True);con.load_extension(os.environ['WELITE_SQLITE_EXT'])
                        with con:
                            for model,identity in [('boards',settings['board']),('cards',settings['card'])]:
                                table=con.execute('SELECT table_name FROM _wl_models WHERE name=?',(model,)).fetchone()[0]
                                quoted='"'+table.replace('"','""')+'"'
                                con.execute('UPDATE '+quoted+" SET _ferretdb_sjson=CASE WHEN typeof(_ferretdb_sjson)='blob' THEN jsonb(json_set(_ferretdb_sjson,'$.title',?)) ELSE json_set(_ferretdb_sjson,'$.title',?) END WHERE json_extract(_ferretdb_sjson,'$._id')=?",('new','new',identity))
                        Path(settings['done']).write_text('committed')
                    finally:con.close()
                if 'AS row_json FROM boards WHERE' in sql and settings['board'] in sql:seen_board=True
            child.stdin.write(line);child.stdin.flush()
    finally:
        child.stdin.close();status=child.wait()
        for thread in threads:thread.join()
    raise SystemExit(status)


def run_shared(request,client,db,control):
    if control is None:return
    board='snapshot-board';card='snapshot-card'
    for collection,documents in [('boards',[dict(_id=board,title='old',slug=board,permission='private',members=[dict(userId='u',isAdmin=True,isActive=True)])]),('lists',[dict(_id='snapshot-list',boardId=board,title='List')]),('cards',[dict(_id=card,boardId=board,listId='snapshot-list',title='old')])]:
        assert client.command({'insert':collection,'documents':documents})['n']==len(documents)
    status,headers,body=request('POST','/sign-in',urlencode(dict(username='user',password='test-password')));assert status in [302,303],(status,body)
    session=parse_qs(urlsplit(headers['Location']).query)['sessionId'][0];done=control.with_suffix('.done')
    try:
        for action in ['export','clone']:
            for collection,identity in [('boards',board),('cards',card)]:
                assert client.command({'update':collection,'updates':[dict(q=dict(_id=identity),u={'$set':dict(title='old')})]})['n']==1
            status,_,body=request('GET','/board?'+urlencode(dict(id=board,sessionId=session)));assert status==200
            parser=Forms();parser.feed(body.decode());form=parser.forms[-1][1]
            done.unlink(missing_ok=True)
            old={row['_id'] for row in client.command({'find':'cards','filter':dict(boardId=board)})['cursor']['firstBatch']}
            control.write_text(json.dumps(dict(active=True,database=str(db),done=str(done),board=board,card=card)))
            status,headers,body=request('POST','/board/move',urlencode(dict(form,action=action,sel_card=card)),timeout=30)
            control.write_text('{}')
            assert done.read_text()=='committed','Independent writer did not run between board/card reads'
            assert client.find('boards',board)[0]['title']=='new' and client.find('cards',card)[0]['title']=='new'
            if action=='export':
                assert status==200,(status,body)
                data=json.loads(body)['data'];assert data['boards'][0]['title']=='old' and data['cards'][0]['title']=='old',data
            else:
                assert status==302,(status,body)
                added=[row for row in client.command({'find':'cards','filter':dict(boardId=board)})['cursor']['firstBatch'] if row['_id'] not in old]
                assert len(added)==1 and added[0]['title']=='old Copy',added
        print('PASS: independent WAL writer between board/card reads cannot mix clone/export graph versions; live sources retain the writer update')
    finally:control.write_text('{}')
