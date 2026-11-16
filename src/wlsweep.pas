unit wlsweep;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,DateUtils,Math,fpjson,wldb,wlshared,wlautsrc,wlenmeta;
const SweepDDL='CREATE TABLE _wl_sweep(id INTEGER PRIMARY KEY CHECK(id=1),lastAt INTEGER NOT NULL) STRICT';
  SweepIntervalMs=600000;
// One transaction owns the due timestamp and every shared typed-token edit.
// False means no work committed; retry later. This does not grant authentication.
function SweepSharedTokens(Db:TWLDb;NowMs:Int64):Boolean;
// Normalized legacy stores only; no shared records or history tables are created.
function SweepLegacyTokens(Db:TWLDb;NowMs:Int64):Boolean;
implementation
function Id(const S:string):string;
begin Result:='"'+StringReplace(S,'"','""',[rfReplaceAll])+'"';end;
function SweepLegacyTokens(Db:TWLDb;NowMs:Int64):Boolean;
var Rows:TWLRows;Last:Int64;HasMeta,HasPending:Boolean;
  Condition,NowIso,Expired,Sql,SchemaCondition:string;
  function Columns(const Name,Expected:string):Boolean;
  var Info:TWLRows;i:Integer;Names:TStringList;
  begin
    Result:=False;Names:=TStringList.Create;
    try
      Names.Delimiter:=',';Names.StrictDelimiter:=True;Names.DelimitedText:=Expected;
      Info:=Db.Query('PRAGMA table_info('+Id(Name)+');');
      if Length(Info)<>Names.Count then Exit;
      for i:=0 to High(Info) do
        if (Info[i][1]<>Names[i]) or (UpperCase(Info[i][2])<>'TEXT') or
          ((i=0) and (Info[i][5]<>'1')) or ((i>0) and (Info[i][5]<>'0')) then Exit;
      Info:=Db.Query('SELECT sql FROM sqlite_master WHERE type=''table'' AND name='+QuotedStr(Name)+';');
      if Length(Info)<>1 then Exit;
      SchemaCondition:=SchemaCondition+' AND EXISTS(SELECT 1 FROM sqlite_master WHERE type=''table'' AND name='+QuotedStr(Name)+' AND sql='+QuotedStr(Info[0][0])+')';
      Result:=True;
    finally Names.Free;end;
  end;
  function Require(const Test:string):string;
  begin
    // SQLite RAISE is trigger-only. Lazy CASE plus abs(INT64_MIN) provides a
    // side-effect-free assertion even if a checkpoint INSERT was ignored.
    Result:='SELECT CASE WHEN ('+Test+') THEN 1 ELSE abs(-9223372036854775808) END; ';
  end;
begin
  Result:=False;SchemaCondition:='1';
  try
    if (NowMs<0) or (NowMs>8640000000000000) or not AuthSourceCurrent(Db) then Exit;
    Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''users'';');
    if (Length(Rows)<>1) or (Rows[0][0]<>'table') then Exit;
    Rows:=Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';');
    if Length(Rows)>0 then Exit;
    Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''login_tokens'';');
    if Length(Rows)=0 then Exit(True); // Registry/minimal stores have no credentials.
    if (Length(Rows)<>1) or (Rows[0][0]<>'table') or not Columns('login_tokens','hashedToken,userId,createdAt,expiresAt') then Exit;
    Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''authmeta'';');HasMeta:=Length(Rows)>0;
    if HasMeta and ((Length(Rows)<>1) or (Rows[0][0]<>'table') or not Columns('authmeta','hashedToken,tenantKey,credentialRef,kind')) then Exit;
    if not HasMeta then SchemaCondition:=SchemaCondition+' AND NOT EXISTS(SELECT 1 FROM sqlite_master WHERE name=''authmeta'')';
    Rows:=Db.Query('SELECT type,sql FROM sqlite_master WHERE name=''_wl_enrol'';');HasPending:=Length(Rows)>0;
    if HasPending and ((Length(Rows)<>1) or (Rows[0][0]<>'table') or (Rows[0][1]<>EnrollDDL)) then Exit;
    if HasPending then SchemaCondition:=SchemaCondition+' AND EXISTS(SELECT 1 FROM sqlite_master WHERE name=''_wl_enrol'' AND type=''table'' AND sql='+QuotedStr(EnrollDDL)+')'
    else SchemaCondition:=SchemaCondition+' AND NOT EXISTS(SELECT 1 FROM sqlite_master WHERE name=''_wl_enrol'')';
    Rows:=Db.Query('SELECT type,sql FROM sqlite_master WHERE name=''_wl_sweep'';');Last:=-SweepIntervalMs;
    if Length(Rows)>0 then
    begin
      if (Length(Rows)<>1) or (Rows[0][0]<>'table') or (Rows[0][1]<>SweepDDL) then Exit;
      Rows:=Db.Query('SELECT lastAt FROM _wl_sweep WHERE id=1;');
      if (Length(Rows)>1) or ((Length(Rows)=1) and not TryStrToInt64(Rows[0][0],Last)) then Exit;
    end;
    if (Last< -SweepIntervalMs) or (NowMs<Last) then Exit;
    if NowMs-Last<SweepIntervalMs then Exit(True);
    Condition:='('+AuthSourceCondition(Db)+') AND NOT EXISTS(SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'')';
    NowIso:=FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',IncMilliSecond(UnixToDateTime(NowMs div 1000,True),NowMs mod 1000));
    Expired:='t.expiresAt IS NOT NULL AND t.expiresAt<='+QuotedStr(NowIso);
    Sql:='BEGIN IMMEDIATE; '+Require('('+Condition+') AND ('+SchemaCondition+')')+StringReplace(SweepDDL,'CREATE TABLE ','CREATE TABLE IF NOT EXISTS ',[])+'; '+
      Require('EXISTS(SELECT 1 FROM sqlite_master WHERE name=''_wl_sweep'' AND type=''table'' AND sql='+QuotedStr(SweepDDL)+')')+
      'INSERT INTO _wl_sweep VALUES(1,-600000) ON CONFLICT(id) DO NOTHING; '+
      Require('EXISTS(SELECT 1 FROM _wl_sweep WHERE id=1 AND lastAt='+IntToStr(Last)+')')+
      'UPDATE _wl_sweep SET lastAt='+IntToStr(NowMs)+' WHERE id=1; '+
      Require('EXISTS(SELECT 1 FROM _wl_sweep WHERE id=1 AND lastAt='+IntToStr(NowMs)+')');
    if HasMeta then Sql:=Sql+
      'DELETE FROM authmeta WHERE hashedToken IN(SELECT t.hashedToken FROM login_tokens t WHERE '+Expired+') OR NOT EXISTS(SELECT 1 FROM login_tokens t WHERE t.hashedToken=authmeta.hashedToken); '+
      Require('NOT EXISTS(SELECT 1 FROM authmeta m LEFT JOIN login_tokens t USING(hashedToken) WHERE t.hashedToken IS NULL OR ('+Expired+'))');
    Sql:=Sql+'DELETE FROM login_tokens AS t WHERE '+Expired+'; '+Require('NOT EXISTS(SELECT 1 FROM login_tokens t WHERE '+Expired+')');
    if HasPending then Sql:=Sql+'DELETE FROM _wl_enrol WHERE expires<='+IntToStr(NowMs div 1000)+'; '+Require('NOT EXISTS(SELECT 1 FROM _wl_enrol WHERE expires<='+IntToStr(NowMs div 1000)+')');
    Sql:=Sql+Require('('+Condition+') AND ('+SchemaCondition+')')+'COMMIT;';
    Result:=Db.Exec(Sql);if not Result then Db.Exec('ROLLBACK;');
  except Db.Exec('ROLLBACK;');Result:=False;end;
end;
function SweepSharedTokens(Db:TWLDb;NowMs:Int64):Boolean;
const MaxDateMs:Int64=8640000000000000;
var Rows:TWLRows;Last,Before:Int64;Life,Cutoff:Double;
  Condition,TableName,Doc,Command,Edited,Sql,Due,NowIso,Expired,MapScope,Candidates,RetireCommand,Retired,PairDoc,RetireScope:string;Cmd:TJSONObject;
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
    NowIso:=FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',IncMilliSecond(UnixToDateTime(NowMs div 1000,True),NowMs mod 1000));
    Expired:='t.expiresAt IS NOT NULL AND t.expiresAt<='+QuotedStr(NowIso);
    PairDoc:='s.'+Doc;
    MapScope:='p.sourceUUID=(SELECT userUUID FROM _wl_authsrc WHERE id=1) AND p.userId=t.userId AND '+Expired;
    Candidates:='SELECT CASE WHEN j.type=''object'' THEN CASE WHEN json_type(j.value,''$.hashedToken'')=''text'' THEN json_extract(j.value,''$.hashedToken'') END END FROM json_each('+PairDoc+',''$.services.resume.loginTokens'') j UNION '+
      'SELECT CASE WHEN j.type=''object'' THEN CASE WHEN json_type(j.value,''$.token'')=''text'' THEN wl_methash(json_extract(j.value,''$.token'')) END END FROM json_each('+PairDoc+',''$.services.resume.loginTokens'') j';
    // Limit the command to distinct hashes actually present in this source array,
    // rather than accumulating an unbounded private-session history into JSON.
    RetireCommand:='json_object(''op'',''retire'',''hashes'',json((SELECT json_group_array(DISTINCT p.sharedHash) FROM _wl_pair p JOIN login_tokens t USING(hashedToken) WHERE '+MapScope+
      ' AND p.userId=json_extract('+PairDoc+',''$."_id"'') AND p.sharedHash IN ('+Candidates+'))))';
    Retired:='wl_resume(json('+PairDoc+'),'+RetireCommand+')';
    RetireScope:='json_type('+PairDoc+',''$.services.resume.loginTokens'')=''array''';

    Sql:='BEGIN IMMEDIATE; UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') AND ('+Due+') THEN userUUID ELSE NULL END WHERE id=1; '+
      'UPDATE _wl_sweep SET lastAt='+IntToStr(NowMs)+' WHERE id=1; '+
      'INSERT INTO _wl_pair SELECT t.hashedToken,t.userId,NULL,a.userUUID FROM login_tokens t CROSS JOIN _wl_authsrc a WHERE a.id=1 AND '+Expired+' ON CONFLICT(hashedToken) DO NOTHING; '+
      'UPDATE _wl_authsrc SET userUUID=CASE WHEN NOT EXISTS(SELECT 1 FROM login_tokens t WHERE '+Expired+' AND NOT EXISTS(SELECT 1 FROM _wl_pair p WHERE p.hashedToken=t.hashedToken AND p.userId=t.userId AND p.sourceUUID=_wl_authsrc.userUUID)) THEN userUUID ELSE NULL END WHERE id=1; '+
      'UPDATE '+Id(TableName)+' SET '+Doc+'=CASE WHEN wl_storage('+QuotedStr(TableName)+')=''blob'' THEN jsonb('+Edited+') ELSE '+Edited+' END '+
      'WHERE json_type('+Doc+',''$.services.resume.loginTokens'')=''array''; '+
      'UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') AND NOT EXISTS(SELECT 1 FROM '+Id(TableName)+
      ' WHERE json_type('+Doc+',''$.services.resume.loginTokens'')=''array'' AND json('+Doc+')<>json('+Edited+')) '+
      'AND EXISTS(SELECT 1 FROM _wl_sweep WHERE id=1 AND lastAt='+IntToStr(NowMs)+') THEN userUUID ELSE NULL END WHERE id=1; '+
      'UPDATE '+Id(TableName)+' AS s SET '+Doc+'=CASE WHEN wl_storage('+QuotedStr(TableName)+')=''blob'' THEN jsonb('+Retired+') ELSE '+Retired+' END WHERE '+RetireScope+'; '+
      'UPDATE _wl_authsrc SET userUUID=CASE WHEN NOT EXISTS(SELECT 1 FROM '+Id(TableName)+' AS s WHERE '+RetireScope+' AND json('+PairDoc+')<>json('+Retired+')) THEN userUUID ELSE NULL END WHERE id=1; '+
      'DELETE FROM authmeta WHERE hashedToken IN(SELECT t.hashedToken FROM login_tokens t WHERE '+Expired+') OR NOT EXISTS(SELECT 1 FROM login_tokens t WHERE t.hashedToken=authmeta.hashedToken); '+
      'UPDATE _wl_authsrc SET userUUID=CASE WHEN NOT EXISTS(SELECT 1 FROM authmeta m LEFT JOIN login_tokens t USING(hashedToken) WHERE t.hashedToken IS NULL OR ('+Expired+')) THEN userUUID ELSE NULL END WHERE id=1; '+
      'DELETE FROM login_tokens AS t WHERE '+Expired+'; '+
      'UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') AND NOT EXISTS(SELECT 1 FROM login_tokens t WHERE '+Expired+') THEN userUUID ELSE NULL END WHERE id=1; '+
      'DELETE FROM _wl_enrol WHERE expires<='+IntToStr(NowMs div 1000)+'; '+
      'UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') AND NOT EXISTS(SELECT 1 FROM _wl_enrol WHERE expires<='+IntToStr(NowMs div 1000)+') THEN userUUID ELSE NULL END WHERE id=1; COMMIT;';
    Result:=Db.Exec(Sql);if not Result then Db.Exec('ROLLBACK;');
  except Db.Exec('ROLLBACK;');Result:=False;end;
end;
end.
