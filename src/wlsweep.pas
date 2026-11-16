unit wlsweep;
{$mode objfpc}{$H+}
interface
uses SysUtils,Math,fpjson,wldb,wlshared,wlautsrc;
const SweepDDL='CREATE TABLE _wl_sweep(id INTEGER PRIMARY KEY CHECK(id=1),lastAt INTEGER NOT NULL) STRICT';
  SweepIntervalMs=600000;
// One transaction owns the due timestamp and every shared typed-token edit.
// False means no work committed; retry later. This does not grant authentication.
function SweepSharedTokens(Db:TWLDb;NowMs:Int64):Boolean;
implementation
function Id(const S:string):string;
begin Result:='"'+StringReplace(S,'"','""',[rfReplaceAll])+'"';end;
function SweepSharedTokens(Db:TWLDb;NowMs:Int64):Boolean;
const MaxDateMs:Int64=8640000000000000;
var Rows:TWLRows;Last,Before:Int64;Life,Cutoff:Double;
  Condition,TableName,Doc,Command,Edited,Sql,Due:string;Cmd:TJSONObject;
begin
  Result:=False;
  try
    if (NowMs<0) or (NowMs>MaxDateMs) or not SharedStore(Db) or not AuthSourceCurrent(Db) then Exit;
    Rows:=Db.Query('SELECT lastAt FROM _wl_sweep WHERE id=1;');
    if (Length(Rows)<>1) or not TryStrToInt64(Rows[0][0],Last) or (Last< -SweepIntervalMs) or (NowMs<Last) then Exit;
    if NowMs-Last<SweepIntervalMs then Exit(True);
    Life:=ApiTokenLifetimeMs(Db,Condition);Cutoff:=Double(NowMs)-Life;
    if IsNan(Cutoff) or IsInfinite(Cutoff) or (Cutoff< -MaxDateMs) or (Cutoff>MaxDateMs) then Exit;
    Before:=Trunc(Cutoff); // Meteor constructs a Date before its strict $lt sweep.
    Rows:=Db.Query('SELECT userTable FROM _wl_authsrc WHERE id=1;');
    if Length(Rows)<>1 then Exit;TableName:=Rows[0][0];Doc:=Id('_ferretdb_sjson');
    Cmd:=TJSONObject.Create;
    try Cmd.Add('op','expire');Cmd.Add('before',Before);Command:=QuotedStr(Cmd.AsJSON);finally Cmd.Free;end;
    Edited:='wl_resume(json('+Doc+'),'+Command+')';
    Due:='EXISTS(SELECT 1 FROM _wl_sweep WHERE id=1 AND lastAt='+IntToStr(Last)+')';
    Sql:='BEGIN IMMEDIATE; UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') AND ('+Due+') THEN userUUID ELSE NULL END WHERE id=1; '+
      'UPDATE _wl_sweep SET lastAt='+IntToStr(NowMs)+' WHERE id=1; '+
      'UPDATE '+Id(TableName)+' SET '+Doc+'=CASE WHEN wl_storage('+QuotedStr(TableName)+')=''blob'' THEN jsonb('+Edited+') ELSE '+Edited+' END '+
      'WHERE json_type('+Doc+',''$.services.resume.loginTokens'')=''array''; '+
      'UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') AND NOT EXISTS(SELECT 1 FROM '+Id(TableName)+
      ' WHERE json_type('+Doc+',''$.services.resume.loginTokens'')=''array'' AND json('+Doc+')<>json('+Edited+')) '+
      'AND EXISTS(SELECT 1 FROM _wl_sweep WHERE id=1 AND lastAt='+IntToStr(NowMs)+') THEN userUUID ELSE NULL END WHERE id=1; COMMIT;';
    Result:=Db.Exec(Sql);if not Result then Db.Exec('ROLLBACK;');
  except Db.Exec('ROLLBACK;');Result:=False;end;
end;
end.
