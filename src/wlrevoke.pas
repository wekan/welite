unit wlrevoke;
{$mode objfpc}{$H+}
interface
uses SysUtils,StrUtils,fpjson,wldb,wlautsrc,wlenmeta,wlcrypt,wlresume;
// Append inside the caller's transaction; rollback the owning action on failure.
// These fragments do not authorize the caller.
function RevokeLoginSessionsSQL(Db:TWLDb;const UserId:string):string;
function RevokeUserTokensSQL(Db:TWLDb;const UserId:string):string;
function RevokeTokenSQL(Db:TWLDb;const UserId,Token:string):string;
implementation
function Id(const S:string):string;
begin Result:='"'+StringReplace(S,'"','""',[rfReplaceAll])+'"';end;
function SharedTokenEdit(Db:TWLDb;const UserId,Token:string;All:Boolean):string;
var Rows:TWLRows;TableName,Doc,UserScope,Condition,TokenType,Empty,Value,Command,Hash,Matches:string;Cmd:TJSONObject;
begin
  Result:='';Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''users'';');
  if Length(Rows)<>1 then raise Exception.Create('Missing revocation source');
  if Rows[0][0]<>'view' then Exit;
  Rows:=Db.Query('SELECT userTable FROM _wl_authsrc WHERE id=1;');
  if Length(Rows)<>1 then raise Exception.Create('Missing shared revocation source');
  TableName:=Rows[0][0];Doc:=Id('_ferretdb_sjson');Condition:=AuthSourceCondition(Db);
  UserScope:='json_extract('+Doc+',''$."_id"'')='+QuotedStr(UserId);
  TokenType:='json_type('+Doc+',''$.services.resume.loginTokens'')';
  Cmd:=TJSONObject.Create;
  try
    if All then Cmd.Add('op','clear')
    else begin Cmd.Add('op','revoke');Cmd.Add('token',Token);end;
    Command:=QuotedStr(Cmd.AsJSON);
  finally Cmd.Free;end;
  Value:='wl_resume(json('+Doc+'),'+Command+')';
  Result:='UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') THEN userUUID ELSE NULL END WHERE id=1; '+
    'UPDATE '+Id(TableName)+' SET '+Doc+'=CASE WHEN wl_storage('+QuotedStr(TableName)+')=''blob'' THEN jsonb('+Value+') ELSE '+Value+' END '+
    'WHERE '+UserScope+' AND '+TokenType+IfThen(All,' IS NOT NULL','=''array''')+'; ';
  if All then
    Empty:='NOT EXISTS(SELECT 1 FROM '+Id(TableName)+' WHERE '+UserScope+') OR EXISTS(SELECT 1 FROM '+Id(TableName)+
      ' WHERE '+UserScope+' AND ('+TokenType+' IS NULL OR ('+TokenType+'=''array'' AND json_array_length('+Doc+',''$.services.resume.loginTokens'')=0)))'
  else
  begin
    Hash:=MeteorTokenHash(Token);
    // The raw form is extracted from escaped JSON, so NUL/control bytes never
    // enter the SQL text. CASE avoids parsing scalar array entries as JSON.
    Matches:='CASE WHEN j.type=''object'' THEN (json_extract(j.value,''$.hashedToken'')='+QuotedStr(Hash)+
      ' OR json_extract(j.value,''$.token'')=json_extract('+Command+',''$.token'')) ELSE 0 END';
    Empty:='NOT EXISTS(SELECT 1 FROM '+Id(TableName)+' p,json_each(p.'+Doc+',''$.services.resume.loginTokens'') j WHERE json_extract(p.'+Doc+',''$."_id"'')='+QuotedStr(UserId)+' AND ('+Matches+'))';
  end;
  // Reject ignored updates; never drop local state while a shared match survives.
  Result:=Result+'UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') AND ('+Empty+') THEN userUUID ELSE NULL END WHERE id=1; ';
end;
function RevokeLoginSessionsSQL(Db:TWLDb;const UserId:string):string;
begin
  if UserId='' then raise Exception.Create('Missing revocation user');
  if not AuthSourceCurrent(Db) then raise Exception.Create('Authentication source changed');
  Result:=SharedTokenEdit(Db,UserId,'',True)+
    'DELETE FROM authmeta WHERE hashedToken IN (SELECT hashedToken FROM login_tokens WHERE userId='+QuotedStr(UserId)+'); '+
    'DELETE FROM login_tokens WHERE userId='+QuotedStr(UserId)+'; ';
end;
function RevokeUserTokensSQL(Db:TWLDb;const UserId:string):string;
var Rows:TWLRows;
begin
  Rows:=Db.Query('SELECT type,sql FROM sqlite_master WHERE name=''_wl_enrol'';');
  if (Length(Rows)>0) and ((Length(Rows)<>1) or (Rows[0][0]<>'table') or (Rows[0][1]<>EnrollDDL)) then
    raise Exception.Create('Incompatible pending enrollment store');
  Result:=RevokeLoginSessionsSQL(Db,UserId)+
    StringReplace(EnrollDDL,'CREATE TABLE ','CREATE TABLE IF NOT EXISTS ',[])+'; '+
    'DELETE FROM _wl_enrol WHERE userId='+QuotedStr(UserId)+'; ';
end;
function RevokeTokenSQL(Db:TWLDb;const UserId,Token:string):string;
var Scope:string;
begin
  if (UserId='') or (Token='') then raise Exception.Create('Missing revocation identity');
  if not AuthSourceCurrent(Db) then raise Exception.Create('Authentication source changed');
  Scope:='userId='+QuotedStr(UserId)+' AND hashedToken='+QuotedStr(TenantTokenHash(Db.Path,Token));
  Result:=SharedTokenEdit(Db,UserId,Token,False)+
    'DELETE FROM authmeta WHERE hashedToken IN (SELECT hashedToken FROM login_tokens WHERE '+Scope+'); '+
    'DELETE FROM login_tokens WHERE '+Scope+'; ';
end;
end.
