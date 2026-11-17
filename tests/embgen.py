"""Generated resources skip missing aliases and preserve real embedded bytes."""
import os
import json
import shutil
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
fpc=os.environ.get('FPC','fpc')
resource=os.environ.get('FPCRES',str(Path(fpc).with_name('fpcres')))
env=dict(os.environ)
if Path(fpc).is_absolute():env['PATH']=str(Path(fpc).parent)+os.pathsep+env.get('PATH','')
def run(args,**kwargs):
    result=subprocess.run(args,env=env,capture_output=True,text=True,**kwargs)
    assert result.returncode==0,result.stdout+result.stderr
    return result
with tempfile.TemporaryDirectory(prefix='wlembed-',dir=os.environ['TMPDIR']) as directory:
    out=Path(directory);web=out/'web';web.mkdir()
    text='Embedded UTF-8: ää / 中文\n'.encode();binary=bytes([0,1,127,128,255])
    (web/'robots.txt').write_bytes(text);(web/'thing.bin').write_bytes(binary)
    (web/'alias.txt').symlink_to('robots.txt');(web/'lost.txt').symlink_to('missing.txt')
    run(['python3',str(root/'releases/genasset.py'),str(out/'wlassets.pas'),str(out/'wlpublic.rc'),str(web)])
    index=(out/'wlassets.pas').read_text();rc=(out/'wlpublic.rc').read_text()
    assert 'lost.txt' not in index and 'lost.txt' not in rc
    assert 'alias.txt' in index and 'robots.txt' in index and 'thing.bin' in index
    run([resource,'wlpublic.rc','-o','wlpublic.res','-of','res'],cwd=out)
    (out/'embgen.lpr').write_text("""program embgen;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wlstatic,wlseed,wlassets;
var Data:TBytes;i:Integer;SQL:string;
begin
  StaticInit('/','absent');
  if ParamStr(1)='seed' then
  begin
    if not LoadSeedSQL('schema.sql','',[],SQL) then Halt(3);
    Writeln(Length(SQL));Halt(0);
  end;
  if not ReadStaticAsset('/',ParamStr(1),Data) then Halt(2);
  for i:=0 to High(Data) do Write(IntToHex(Data[i],2));
  Writeln;
end.
""")
    run([fpc,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(out/'embgen.lpr')])
    for name,expected in [('robots.txt',text),('alias.txt',text),('thing.bin',binary)]:
        assert run([str(out/'embgen'),name],cwd=out).stdout.strip()==expected.hex().upper()
    assert subprocess.run([str(out/'embgen'),'lost.txt'],cwd=out,env=env,capture_output=True).returncode==2
    assert int(run([str(out/'embgen'),'seed'],cwd=out).stdout)==(root/'src/schema.sql').stat().st_size
    empty=out/'empty';empty.mkdir();emptyroot=empty/'web';emptyroot.mkdir()
    run(['python3',str(root/'releases/genasset.py'),str(empty/'wlassets.pas'),str(empty/'wlpublic.rc'),str(emptyroot)])
    run([resource,'wlpublic.rc','-o','wlpublic.res','-of','res'],cwd=empty)
    shutil.copyfile(out/'embgen.lpr',empty/'embgen.lpr')
    run([fpc,'-B','-Fu'+str(root/'src'),'-FU'+str(empty),'-FE'+str(empty),str(empty/'embgen.lpr')])
    assert int(run([str(empty/'embgen'),'seed'],cwd=empty).stdout)==(root/'src/schema.sql').stat().st_size
    assert subprocess.run([str(empty/'embgen'),'robots.txt'],cwd=empty,env=env,capture_output=True).returncode==2
    full=out/'full';full.mkdir()
    run(['python3',str(root/'releases/genasset.py'),str(full/'wlassets.pas'),str(full/'wlpublic.rc')],cwd=root)
    index=(full/'wlassets.pas').read_text()
    assert 'i18n/locales.jsn' in index
    for row in json.loads((root/'i18n/locales.jsn').read_text()):assert 'i18n/data/'+row['file'] in index
    for name in ['km-KH.jsn','pt-PT.jsn','ru-RU.jsn']:
        if not (root/'i18n/data'/name).is_file():assert 'i18n/data/'+name not in index
    run([resource,'wlpublic.rc','-o','wlpublic.res','-of','res'],cwd=full)
    assert (full/'wlpublic.res').stat().st_size>0
print('PASS: embedded generator skips dangling aliases, preserves real alias/UTF-8/binary lookup, supports SQL-only bundles and compiles the full public/i18n/private-SQL resource bundle')
