"""Observe the real CLI boundary: private script input, path safety and cleanup."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
real=shutil.which('sqlite3')
assert real,'sqlite3 CLI is required'
with tempfile.TemporaryDirectory(prefix='wlinput-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory);build=tmp/'build';build.mkdir();wrapper=tmp/'wrapper';wrapper.mkdir()
    scratch=tmp/"temp path ' 日本語";scratch.mkdir();log=tmp/'calls.jsn'
    script=wrapper/'sqlite3'
    script.write_text('''#!/usr/bin/env python3
import json,os,stat,sys
from pathlib import Path
path=Path(sys.argv[sys.argv.index('-init')+1])
assert sys.argv[-1]=='.quit',sys.argv
assert Path.cwd()==Path(os.environ['WLCLI_CWD']),Path.cwd()
assert stat.S_IMODE(path.stat().st_mode)==0o600,path
assert stat.S_IMODE(path.parent.stat().st_mode)==0o700,path.parent
assert path.name=='query.sql' and len(path.parent.name)==8,path
with open(os.environ['WLCLI_LOG'],'a') as log:
 log.write(json.dumps({'bytes':path.stat().st_size,'args':sys.argv[1:]},ensure_ascii=False)+'\\n')
os.execv(os.environ['WLCLI_REAL'],[os.environ['WLCLI_REAL'],*sys.argv[1:]])
''')
    script.chmod(0o700)
    env=dict(os.environ,TMPDIR=str(scratch),PATH=str(wrapper)+os.pathsep+os.environ['PATH'],WLCLI_LOG=str(log),WLCLI_REAL=real,WLCLI_CWD=str(tmp))
    env.pop('WELITE_SQLITE_EXT',None)
    for source in ['dbtext','sjsql']:
        result=subprocess.run([os.environ.get('FPC','fpc'),'-B','-dWLDB_CLI','-Fu'+str(root/'src'),'-FU'+str(build),'-FE'+str(build),str(root/'tests'/f'{source}.lpr')],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
    database=tmp/"db path ' 日本語"/'data.db';database.parent.mkdir()
    subprocess.run([str(build/'dbtext'),str(database)],env=env,check=True,timeout=30,cwd=tmp)
    calls=[json.loads(line) for line in log.read_text().splitlines()]
    assert max(call['bytes'] for call in calls)>1024*1024
    assert all(len(call['args'])==8 for call in calls),calls[0]
    assert not list(scratch.rglob('query.sql')) and not list(scratch.rglob('t???????'))
    marker=tmp/'side.txt'
    forbidden='SELECT 1;\n.once '+json.dumps(str(marker))+'\nSELECT 2;'
    result=subprocess.run([str(build/'sjsql'),str(database),'exec'],input=forbidden,env=env,capture_output=True,text=True,cwd=tmp)
    assert result.returncode==0 and result.stdout.strip()=='error' and not marker.exists()
    assert not list(scratch.rglob('query.sql')) and not list(scratch.rglob('t???????'))
    # Failure to spawn the configured CLI must also remove the prepared SQL file.
    missing=dict(env,PATH=str(tmp/'missing'))
    result=subprocess.run([str(build/'sjsql'),str(tmp/'failed.db'),'exec'],input='SELECT 1;',env=missing,capture_output=True,text=True,cwd=tmp)
    if env.get('WELITE_SHORT_NAMES')=='1':
        assert result.returncode!=0 and 'SQLITE_ENABLE_8_3_NAMES=2' in result.stderr,(result.stdout,result.stderr)
    else:
        assert result.returncode==0 and result.stdout.strip()=='error',(result.stdout,result.stderr)
    assert not list(scratch.rglob('query.sql')) and not list(scratch.rglob('t???????'))
    print('PASS: CLI megabyte scripts, 0700/0600 scratch, Unicode/quoted paths, structured filename arguments and preserved CWD and failure cleanup')
