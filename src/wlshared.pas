unit wlshared;
{$mode objfpc}{$H+}
interface
uses SysUtils,DateUtils,fpjson,wldb,wlautsrc,wlresume,wlcrypt,wlsjson,wlpolicy;
function AccountPolicyCondition(Db:TWLDb):string;
function ResolvedFactorPolicy(Db:TWLDb;const Method,Services:string;IsAdmin:Boolean;
  out Secret,Condition:string):TFactorPolicy;
function ResolvedPasswordAllowed(Db:TWLDb;const Method,Services:string;IsAdmin:Boolean):Boolean;
function SharedStore(Db:TWLDb):Boolean;
function ApiTokenLifetime(Db:TWLDb):Int64;
function UnixMillis(At:TDateTime):Int64;
function SharedIssueSQL(Db:TWLDb;const UserId,Token,Key:string;WhenMs:Int64):string;
function SharedBearerValid(Db:TWLDb;const UserId,Token:string):Boolean;
implementation
function Id(const S:string):string;
begin Result:='"'+StringReplace(S,'"','""',[rfReplaceAll])+'"';end;
function SharedStore(Db:TWLDb):Boolean;
var Rows:TWLRows;
begin
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''users'';');
  if Length(Rows)<>1 then raise Exception.Create('Missing account source');
  Result:=Rows[0][0]='view';
end;
function ReadSettings(Db:TWLDb;out Snapshot:string):TJSONObject;
var Rows:TWLRows;TableName:string;
begin
  Result:=nil;
  Rows:=Db.Query('SELECT count(*),COALESCE(max(table_name),'''') FROM _ferretdb_collections WHERE name=''settings'';');
  if Length(Rows)<>1 then raise Exception.Create('Cannot read shared settings registry');
  if Rows[0][0]='0' then
  begin
    Snapshot:='NOT EXISTS(SELECT 1 FROM _ferretdb_collections WHERE name=''settings'')';Exit(TJSONObject.Create);
  end;
  if Rows[0][0]<>'1' then raise Exception.Create('Ambiguous settings collection');
  TableName:=Rows[0][1];
  Snapshot:='EXISTS(SELECT 1 FROM _ferretdb_collections WHERE name=''settings'' AND table_name='+QuotedStr(TableName)+')';
  Rows:=Db.Query('SELECT count(*),COALESCE(min(document),'''') FROM (SELECT json(_ferretdb_sjson) AS document FROM '+Id(TableName)+' LIMIT 2);');
  if (Length(Rows)<>1) or ((Rows[0][0]<>'0') and (Rows[0][0]<>'1')) then raise Exception.Create('Ambiguous shared settings');
  if Rows[0][0]='0' then
  begin Snapshot:=Snapshot+' AND NOT EXISTS(SELECT 1 FROM '+Id(TableName)+')';Exit(TJSONObject.Create);end;
  Snapshot:=Snapshot+' AND (SELECT count(*) FROM '+Id(TableName)+')=1 AND EXISTS(SELECT 1 FROM '+Id(TableName)+' WHERE json(_ferretdb_sjson)='+QuotedStr(Rows[0][1])+')';
  Result:=ExactObject(PlainDocument(Rows[0][1]));
end;
function SettingValue(Doc:TJSONObject;const Section,Key,Fallback:string):string;
var Parent,Value:TJSONData;
begin
  Result:=Fallback;Parent:=Doc.Find(Section);
  if not (Parent is TJSONObject) then Exit;
  Value:=TJSONObject(Parent).Find(Key);if (Value=nil) or (Value.JSONType=jtNull) then Exit;
  if Value.JSONType=jtBoolean then Result:=LowerCase(Value.AsString) else Result:=Value.AsString;
  if Result='' then Result:=Fallback;
end;
function AccountPolicyCondition(Db:TWLDb):string;
var Doc:TJSONObject;Snapshot:string;
begin
  Result:=AuthSourceCondition(Db);if not SharedStore(Db) then Exit;
  Doc:=ReadSettings(Db,Snapshot);Doc.Free;Result:='('+Result+') AND ('+Snapshot+')';
end;
function ResolvedFactorPolicy(Db:TWLDb;const Method,Services:string;IsAdmin:Boolean;
  out Secret,Condition:string):TFactorPolicy;
var Doc:TJSONObject;Snapshot:string;Settings:TFactorSettings;
begin
  Result:=fpDenied;Secret:='';Condition:='0';Doc:=nil;
  try
    try
      Settings:=EnvironmentFactorSettings;Condition:=AuthSourceCondition(Db);
      if SharedStore(Db) then
      begin
        Doc:=ReadSettings(Db,Snapshot);Condition:='('+Condition+') AND ('+Snapshot+')';
        Settings.Mode:=SettingValue(Doc,'loginOptions','require2fa',Settings.Mode);
        Settings.LDAPEnabled:=SettingValue(Doc,'ldap','enabled',Settings.LDAPEnabled);
        Settings.LDAPFallback:=SettingValue(Doc,'ldap','loginFallback',Settings.LDAPFallback);
        Settings.LDAPMigration:=SettingValue(Doc,'ldap','migrationAllowPasswordLogin',Settings.LDAPMigration);
        Settings.PasswordEnabled:=SettingValue(Doc,'loginOptions','passwordLoginEnabled',GetEnvironmentVariable('PASSWORD_LOGIN_ENABLED'));
      end;
      Result:=FactorPolicyWithSettings(Method,Services,IsAdmin,Settings,Secret);
    except Result:=fpDenied;Secret:='';Condition:='0';end;
  finally Doc.Free;end;
end;
function ResolvedPasswordAllowed(Db:TWLDb;const Method,Services:string;IsAdmin:Boolean):Boolean;
var Secret,Condition:string;
begin
  Result:=ResolvedFactorPolicy(Db,Method,Services,IsAdmin,Secret,Condition)=fpNone;
  if Secret<>'' then begin UniqueString(Secret);FillChar(Secret[1],Length(Secret),0);end;
end;
function ApiTokenLifetime(Db:TWLDb):Int64;
var Days:Int64;Setting,Snapshot:string;Doc:TJSONObject;
begin
  Result:=90*86400;if not SharedStore(Db) then Exit;
  Doc:=ReadSettings(Db,Snapshot);
  try
    Setting:=Trim(SettingValue(Doc,'loginOptions','loginExpirationInDays',GetEnvironmentVariable('ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS')));
  finally Doc.Free;end;
  if (Setting='') or (Setting='0') then Days:=90
  else if not TryStrToInt64(Setting,Days) or (Days<1) or (Days>36500) then raise Exception.Create('Unsupported shared token lifetime');
  Result:=Days*86400;
end;
function UnixMillis(At:TDateTime):Int64;
begin Result:=DateTimeToUnix(At,False)*1000+MilliSecondOf(At);end;
function UsersTable(Db:TWLDb):string;
var Rows:TWLRows;
begin
  if not AuthSourceCurrent(Db) then raise Exception.Create('Account source changed');
  Rows:=Db.Query('SELECT userTable FROM _wl_authsrc WHERE id=1;');
  if Length(Rows)<>1 then raise Exception.Create('Missing shared source');
  Result:=Rows[0][0];
end;
function MatchSQL(const Token,Hash:string):string;
var Cmd:TJSONObject;Encoded:string;
begin
  Cmd:=TJSONObject.Create;
  try Cmd.Add('token',Token);Encoded:=QuotedStr(Cmd.AsJSON);finally Cmd.Free;end;
  Result:='CASE WHEN j.type=''object'' THEN (json_extract(j.value,''$.hashedToken'')='+QuotedStr(Hash)+
    ' OR json_extract(j.value,''$.token'')=json_extract('+Encoded+',''$.token'')) ELSE 0 END';
end;
function SharedIssueSQL(Db:TWLDb;const UserId,Token,Key:string;WhenMs:Int64):string;
var TableName,Doc,Hash,Condition,Issued,Collides,Value,Present,Snapshot,Restrictions:string;Cmd,Settings:TJSONObject;Enabled:TJSONData;
begin
  Result:='';if not SharedStore(Db) then Exit;
  TableName:=UsersTable(Db);Doc:=Id('_ferretdb_sjson');Hash:=MeteorTokenHash(Token);Condition:=AuthSourceCondition(Db);
  Settings:=ReadSettings(Db,Snapshot);
  try
    Enabled:=Settings.Find('sqrlEnabled');
    Restrictions:='1';
    if (Enabled<>nil) and (Enabled.JSONType=jtBoolean) and Enabled.AsBoolean then
    begin
      // Canonical SQRL identity fields only; malformed restrictions fail closed.
      Restrictions:='NOT EXISTS(SELECT 1 FROM '+Id(TableName)+' WHERE json_extract('+Doc+',''$."_id"'')='+QuotedStr(UserId)+
        ' AND json_type('+Doc+',''$.sqrl'') IS NOT NULL AND json_type('+Doc+',''$.sqrl'')<>''null'' AND NOT ('+
        'json_type('+Doc+',''$.sqrl'')=''object'' AND COALESCE(json_type('+Doc+',''$.sqrl.idk''),''null'') IN (''null'',''text'') '+
        'AND COALESCE(json_type('+Doc+',''$.sqrl.disabled''),''null'') IN (''null'',''true'',''false'') '+
        'AND COALESCE(json_type('+Doc+',''$.sqrl.sqrlOnly''),''null'') IN (''null'',''true'',''false'') '+
        'AND NOT (COALESCE(length(json_extract('+Doc+',''$.sqrl.idk'')),0)>0 AND COALESCE(json_type('+Doc+',''$.sqrl.disabled''),''null'')<>''true'' AND COALESCE(json_type('+Doc+',''$.sqrl.sqrlOnly''),''null'')=''true'')))';
    end;
    Condition:='('+Condition+') AND ('+Snapshot+') AND ('+Restrictions+')';
  finally Settings.Free;end;
  Issued:='EXISTS(SELECT 1 FROM login_tokens WHERE hashedToken='+QuotedStr(Key)+' AND userId='+QuotedStr(UserId)+')';
  Collides:='EXISTS(SELECT 1 FROM '+Id(TableName)+' p,json_each(p.'+Doc+',''$.services.resume.loginTokens'') j WHERE '+MatchSQL(Token,Hash)+')';
  Cmd:=TJSONObject.Create;
  try Cmd.Add('op','append');Cmd.Add('hashedToken',Hash);Cmd.Add('when',WhenMs);Value:='wl_resume(json('+Doc+'),'+QuotedStr(Cmd.AsJSON)+')';finally Cmd.Free;end;
  Result:='UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') AND (NOT ('+Issued+') OR NOT ('+Collides+')) THEN userUUID ELSE NULL END WHERE id=1; '+
    'UPDATE '+Id(TableName)+' SET '+Doc+'=CASE WHEN wl_storage('+QuotedStr(TableName)+')=''blob'' THEN jsonb('+Value+') ELSE '+Value+' END '+
    'WHERE json_extract('+Doc+',''$."_id"'')='+QuotedStr(UserId)+' AND '+Issued+'; ';
  Present:='EXISTS(SELECT 1 FROM '+Id(TableName)+' WHERE json_extract('+Doc+',''$."_id"'')='+QuotedStr(UserId)+
    ' AND wl_rescheck(json('+Doc+'),'+QuotedStr(Hash)+','+IntToStr(WhenMs)+',1)=''valid'')';
  Result:=Result+'UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') AND (NOT ('+Issued+') OR ('+Present+')) THEN userUUID ELSE NULL END WHERE id=1; ';
end;
function SharedBearerValid(Db:TWLDb;const UserId,Token:string):Boolean;
var Rows:TWLRows;TableName,Doc,Hash:string;Stamp,Expiration:Int64;
begin
  Result:=False;
  try
    if not SharedStore(Db) then Exit(True);
    TableName:=UsersTable(Db);Doc:=Id('_ferretdb_sjson');Hash:=MeteorTokenHash(Token);
    Rows:=Db.Query('SELECT json_extract(p.'+Doc+',''$."_id"''),json(p.'+Doc+') FROM '+Id(TableName)+' p WHERE ('+AuthSourceCondition(Db)+
      ') AND EXISTS(SELECT 1 FROM json_each(p.'+Doc+',''$.services.resume.loginTokens'') j WHERE '+MatchSQL(Token,Hash)+') LIMIT 2;');
    if (Length(Rows)<>1) or (Rows[0][0]<>UserId) then Exit;
    Result:=CheckResumeToken(Rows[0][1],Hash,UnixMillis(Now),ApiTokenLifetime(Db)*1000,Stamp,Expiration)=rsValid;
  except Result:=False;end;
end;
end.
