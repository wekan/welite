unit wlrevoke;
{$mode objfpc}{$H+}
interface
uses SysUtils,wldb,wlautsrc,wlenmeta;
// Append inside the caller's transaction; rollback all account changes on failure.
// This is not authorization. The caller must validate its account action/proof.
function RevokeUserTokensSQL(Db:TWLDb;const UserId:string):string;
implementation
function Id(const S:string):string;
begin Result:='"'+StringReplace(S,'"','""',[rfReplaceAll])+'"';end;
function RevokeUserTokensSQL(Db:TWLDb;const UserId:string):string;
var Rows:TWLRows;TableName,Doc,UserScope,Condition,TokenType,Empty,Value:string;
begin
  if UserId='' then raise Exception.Create('Missing revocation user');
  if not AuthSourceCurrent(Db) then raise Exception.Create('Authentication source changed');
  Rows:=Db.Query('SELECT type,sql FROM sqlite_master WHERE name=''_wl_enrol'';');
  if (Length(Rows)>0) and ((Length(Rows)<>1) or (Rows[0][0]<>'table') or (Rows[0][1]<>EnrollDDL)) then
    raise Exception.Create('Incompatible pending enrollment store');
  Result:=StringReplace(EnrollDDL,'CREATE TABLE ','CREATE TABLE IF NOT EXISTS ',[])+'; ';
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''users'';');
  if Length(Rows)<>1 then raise Exception.Create('Missing revocation source');
  if Rows[0][0]='view' then
  begin
    Rows:=Db.Query('SELECT userTable FROM _wl_authsrc WHERE id=1;');
    if Length(Rows)<>1 then raise Exception.Create('Missing shared revocation source');
    TableName:=Rows[0][0];Doc:=Id('_ferretdb_sjson');Condition:=AuthSourceCondition(Db);
    UserScope:='json_extract('+Doc+',''$."_id"'')='+QuotedStr(UserId);
    TokenType:='json_type('+Doc+',''$.services.resume.loginTokens'')';
    Value:='wl_resume(json('+Doc+'),''{"op":"clear"}'')';
    // A source switch after the initial read aborts the owning transaction.
    Result:=Result+'UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') THEN userUUID ELSE NULL END WHERE id=1; '+
      'UPDATE '+Id(TableName)+' SET '+Doc+'=CASE WHEN wl_storage('+QuotedStr(TableName)+')=''blob'' THEN jsonb('+Value+') ELSE '+Value+' END '+
      'WHERE '+UserScope+' AND '+TokenType+' IS NOT NULL; ';
    // Ignore/no-op triggers must not leave shared bearers valid while local rows
    // disappear. An absent token path means there were no shared records to clear.
    Empty:='NOT EXISTS(SELECT 1 FROM '+Id(TableName)+' WHERE '+UserScope+') OR EXISTS(SELECT 1 FROM '+Id(TableName)+
      ' WHERE '+UserScope+' AND ('+TokenType+' IS NULL OR ('+TokenType+'=''array'' AND json_array_length('+Doc+',''$.services.resume.loginTokens'')=0)))';
    Result:=Result+'UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') AND ('+Empty+') THEN userUUID ELSE NULL END WHERE id=1; ';
  end;
  Result:=Result+'DELETE FROM _wl_enrol WHERE userId='+QuotedStr(UserId)+'; '+
    'DELETE FROM authmeta WHERE hashedToken IN (SELECT hashedToken FROM login_tokens WHERE userId='+QuotedStr(UserId)+'); '+
    'DELETE FROM login_tokens WHERE userId='+QuotedStr(UserId)+'; ';
end;
end.
