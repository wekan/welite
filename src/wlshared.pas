unit wlshared;
{$mode objfpc}{$H+}
interface
uses SysUtils,DateUtils,Math,wllife,fpjson,wldb,wlautsrc,wlresume,wlcrypt,wlsjson,wlpolicy,wlpair;
function AccountPolicyCondition(Db:TWLDb):string;
function ResolvedFactorPolicy(Db:TWLDb;const Method,Services:string;IsAdmin:Boolean;
  out Secret,Condition:string):TFactorPolicy;
function ResolvedPasswordAllowed(Db:TWLDb;const Method,Services:string;IsAdmin:Boolean):Boolean;
function SharedStore(Db:TWLDb):Boolean;
// WeKan's passwordPolicyConfig (server/lib/passwordPolicy.js): the minimum
// length - a shared store's settings.loginOptions.passwordMinLength, else
// PASSWORD_MIN_LENGTH, else 8, at most 256 - and whether it is enforced
// (passwordMinLengthEnforce, else PASSWORD_MIN_LENGTH_ENFORCE=true).
procedure PasswordPolicy(Db:TWLDb;out MinLength:Integer;out Enforce:Boolean);
// A top-level boolean of a shared store's site settings (Admin Panel's
// renderLinksAsPlainText, alwaysShowCodeAsText...); False without one.
function SharedSettingOn(Db:TWLDb;const Key:string):Boolean;
function ApiTokenLifetime(Db:TWLDb):Int64;
function ApiTokenLifetimeMs(Db:TWLDb;out Condition:string):Double;
function ApiTokenExpiration(Db:TWLDb;WhenMs,TtlSeconds:Int64;out Condition:string):Int64;
function UnixMillis(At:TDateTime):Int64;
function SharedIssueSQL(Db:TWLDb;const UserId,Token,Key:string;WhenMs:Int64):string;
function SharedBearerValid(Db:TWLDb;const UserId,Token:string):Boolean;
function SharedResumeCandidate(Db:TWLDb;const Token:string;out UserId,Condition,ConversionSQL:string;
  out WhenMs,ExpiresMs:Int64):Boolean;
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
function SharedSettingOn(Db:TWLDb;const Key:string):Boolean;
var Doc:TJSONObject;Snapshot:string;Value:TJSONData;
begin
  Result:=False;Doc:=nil;
  try
    try
      if SharedStore(Db) then Doc:=ReadSettings(Db,Snapshot);
    except Doc:=nil;end;
    if Doc=nil then Exit;
    Value:=Doc.Find(Key);
    Result:=(Value<>nil) and (Value.JSONType=jtBoolean) and Value.AsBoolean;
  finally Doc.Free;end;
end;

procedure PasswordPolicy(Db:TWLDb;out MinLength:Integer;out Enforce:Boolean);
var Doc:TJSONObject;Snapshot,Raw,Flag:string;N:Double;
begin
  MinLength:=8;
  Raw:=Trim(GetEnvironmentVariable('PASSWORD_MIN_LENGTH'));
  Flag:=Trim(GetEnvironmentVariable('PASSWORD_MIN_LENGTH_ENFORCE'));
  Doc:=nil;
  try
    try
      if SharedStore(Db) then Doc:=ReadSettings(Db,Snapshot);
    except Doc:=nil;end;
    if Doc<>nil then
    begin
      Raw:=SettingValue(Doc,'loginOptions','passwordMinLength',Raw);
      Flag:=SettingValue(Doc,'loginOptions','passwordMinLengthEnforce',Flag);
    end;
  finally Doc.Free;end;
  N:=StrToFloatDef(Raw,0,DefaultFormatSettings);
  if (N>=1) and (Frac(N)=0) then MinLength:=Round(Min(N,256));
  Enforce:=Flag='true';
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
function ApiTokenLifetimeMs(Db:TWLDb;out Condition:string):Double;
var Setting,Snapshot:string;Doc:TJSONObject;
begin
  Result:=90.0*86400000;Condition:=AuthSourceCondition(Db);if not SharedStore(Db) then Exit;
  Doc:=ReadSettings(Db,Snapshot);
  try
    Setting:=SettingValue(Doc,'loginOptions','loginExpirationInDays',GetEnvironmentVariable('ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS'));
    Result:=TokenLifetimeMs(Setting);Condition:='('+Condition+') AND ('+Snapshot+')';
  finally Doc.Free;end;
end;
function ApiTokenLifetime(Db:TWLDb):Int64;
var Condition:string;
begin
  // The existing caller contract is seconds; this is a request marker only.
  // Shared expiry always uses the original binary64 milliseconds below.
  Result:=Ceil(ApiTokenLifetimeMs(Db,Condition)/1000.0);
end;
function ApiTokenExpiration(Db:TWLDb;WhenMs,TtlSeconds:Int64;out Condition:string):Int64;
var Life:Double;
begin
  Life:=ApiTokenLifetimeMs(Db,Condition);
  if TtlSeconds<>Ceil(Life/1000.0) then raise Exception.Create('Shared token lifetime changed');
  Result:=TokenExpirationMs(WhenMs,Life);
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
  Result:=Result+StorePairSQL(Db,UserId,Token);
end;
function SharedResumeCandidate(Db:TWLDb;const Token:string;out UserId,Condition,ConversionSQL:string;
  out WhenMs,ExpiresMs:Int64):Boolean;
var Rows:TWLRows;TableName,Doc,Hash,Match,Converted,Command,SettingsCondition,Scope,Present:string;
  Cmd:TJSONObject;Life:Double;
begin
  Result:=False;UserId:='';Condition:='0';ConversionSQL:='';WhenMs:=0;ExpiresMs:=0;
  try
    if not SharedStore(Db) or not AuthSourceCurrent(Db) then Exit;
    TableName:=UsersTable(Db);Doc:=Id('_ferretdb_sjson');Hash:=MeteorTokenHash(Token);Match:=MatchSQL(Token,Hash);
    Scope:='EXISTS(SELECT 1 FROM json_each(p.'+Doc+',''$.services.resume.loginTokens'') j WHERE '+Match+')';
    Rows:=Db.Query('SELECT json_extract(p.'+Doc+',''$."_id"''),json(p.'+Doc+') FROM '+Id(TableName)+' p WHERE '+Scope+' LIMIT 2;');
    if (Length(Rows)<>1) or (Rows[0][0]='') then Exit;
    Cmd:=TJSONObject.Create;
    try Cmd.Add('op','convert');Cmd.Add('token',Token);Command:=Cmd.AsJSON;finally Cmd.Free;end;
    Converted:=ResumeDocument(Rows[0][1],Command);
    Life:=ApiTokenLifetimeMs(Db,SettingsCondition);
    if CheckResumeToken(Converted,Hash,UnixMillis(Now),Life,WhenMs,ExpiresMs)<>rsValid then Exit;
    UserId:=Rows[0][0];
    Condition:='('+SettingsCondition+') AND (SELECT count(*) FROM '+Id(TableName)+' p WHERE '+Scope+')=1 AND EXISTS(SELECT 1 FROM '+Id(TableName)+
      ' WHERE json_extract('+Doc+',''$."_id"'')='+QuotedStr(UserId)+' AND json('+Doc+')='+QuotedStr(Rows[0][1])+')';
    ConversionSQL:='UPDATE '+Id(TableName)+' SET '+Doc+'=CASE WHEN wl_storage('+QuotedStr(TableName)+')=''blob'' THEN jsonb(wl_resume(json('+Doc+'),'+QuotedStr(Command)+')) ELSE wl_resume(json('+Doc+'),'+QuotedStr(Command)+') END '+
      'WHERE json_extract('+Doc+',''$."_id"'')='+QuotedStr(UserId)+'; ';
    Present:='EXISTS(SELECT 1 FROM '+Id(TableName)+' WHERE json_extract('+Doc+',''$."_id"'')='+QuotedStr(UserId)+
      ' AND json('+Doc+')=json('+QuotedStr(Converted)+'))';
    ConversionSQL:=ConversionSQL+'UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+SettingsCondition+') AND ('+Present+') THEN userUUID ELSE NULL END WHERE id=1; ';
    Result:=True;
  except UserId:='';Condition:='0';ConversionSQL:='';Result:=False;end;
end;
function SharedBearerValid(Db:TWLDb;const UserId,Token:string):Boolean;
var Rows:TWLRows;TableName,Doc,Hash:string;Stamp,Expiration:Int64;Life:Double;Condition:string;
begin
  Result:=False;
  try
    if not SharedStore(Db) then Exit(True);
    TableName:=UsersTable(Db);Doc:=Id('_ferretdb_sjson');Hash:=MeteorTokenHash(Token);
    Rows:=Db.Query('SELECT json_extract(p.'+Doc+',''$."_id"''),json(p.'+Doc+') FROM '+Id(TableName)+' p WHERE ('+AuthSourceCondition(Db)+
      ') AND EXISTS(SELECT 1 FROM json_each(p.'+Doc+',''$.services.resume.loginTokens'') j WHERE '+MatchSQL(Token,Hash)+') LIMIT 2;');
    if (Length(Rows)<>1) or (Rows[0][0]<>UserId) then Exit;
    Life:=ApiTokenLifetimeMs(Db,Condition);
    Result:=CheckResumeToken(Rows[0][1],Hash,UnixMillis(Now),Life,Stamp,Expiration)=rsValid;
  except Result:=False;end;
end;
end.
