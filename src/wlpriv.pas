unit wlpriv;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,wldb,wlreplay,wlattemp,wlenroll;
function PrivateScript(Db:TWLDb;Tables:TStrings):string;
implementation
const
  TokenDDL='CREATE TABLE login_tokens(hashedToken TEXT PRIMARY KEY,userId TEXT NOT NULL,createdAt TEXT NOT NULL,expiresAt TEXT)';
  MetaDDL='CREATE TABLE authmeta(hashedToken TEXT PRIMARY KEY REFERENCES login_tokens(hashedToken) ON DELETE CASCADE,tenantKey TEXT NOT NULL,credentialRef TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN (''web'',''api'')))';
  Signature='{"kind":"private-auth","version":1}';
function Id(const S:string):string;
begin Result:='"'+StringReplace(S,'"','""',[rfReplaceAll])+'"';end;
function PrivateScript(Db:TWLDb;Tables:TStrings):string;
var Objects,Owners:TWLRows;Users,Name,DDL:string;i,j,k:Integer;Owned,Exists:Boolean;
begin
  Result:='';Users:=Tables.Values['users'];
  if Users='' then raise Exception.Create('Missing private-token user collection');
  Objects:=Db.Query('SELECT name,type,sql FROM sqlite_master WHERE type IN (''table'',''view'');');
  Owners:=nil;
  for i:=0 to High(Objects) do if Objects[i][0]='_wl_models' then
    Owners:=Db.Query('SELECT name,table_name,spec,version FROM _wl_models;');
  for k:=0 to 4 do
  begin
    if k=0 then begin Name:='login_tokens';DDL:=TokenDDL;end
    else if k=1 then begin Name:='authmeta';DDL:=MetaDDL;end
    else if k=2 then begin Name:='_wl_otp';DDL:=OTPReplayDDL;end
    else if k=3 then begin Name:='_wl_attempt';DDL:=AttemptDDL;end
    else begin Name:='_wl_enrol';DDL:=EnrollDDL;end;
    Exists:=False;Owned:=False;
    for i:=0 to High(Owners) do
      if (Owners[i][0]=Name) and (Owners[i][1]=Name) and (Owners[i][2]=Signature) and (Owners[i][3]='1') then Owned:=True;
    for j:=0 to High(Objects) do if SameText(Objects[j][0],Name) then
    begin
      Exists:=True;
      if not Owned or (Objects[j][1]<>'table') or (Objects[j][2]<>DDL) then
        raise Exception.Create('Refusing incompatible private-token object');
    end;
    if not Exists then Result:=Result+DDL+'; ';
    Result:=Result+'INSERT OR REPLACE INTO _wl_models VALUES('+QuotedStr(Name)+','+QuotedStr(Name)+','+QuotedStr(Signature)+',1); ';
  end;
  Result:=Result+'CREATE INDEX IF NOT EXISTS idx_login_tokens_user ON login_tokens(userId); '+
    'DROP TRIGGER IF EXISTS _wl_token_i; DROP TRIGGER IF EXISTS _wl_token_u; '+
    'DROP TRIGGER IF EXISTS _wl_token_d; DROP TRIGGER IF EXISTS _wl_user_tokens; '+
    'CREATE TRIGGER _wl_token_i BEFORE INSERT ON login_tokens BEGIN '+
      'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.userId) THEN RAISE(ABORT,''Missing token user'') END; END; '+
    'CREATE TRIGGER _wl_token_u BEFORE UPDATE OF userId ON login_tokens BEGIN '+
      'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.userId) THEN RAISE(ABORT,''Missing token user'') END; END; '+
    // Explicit cleanup also works on a Mongo connection with foreign_keys disabled.
    'CREATE TRIGGER _wl_token_d AFTER DELETE ON login_tokens BEGIN DELETE FROM authmeta WHERE hashedToken=OLD.hashedToken; END; '+
    'CREATE TRIGGER _wl_user_tokens AFTER DELETE ON '+Id(Users)+' BEGIN '+
      'DELETE FROM login_tokens WHERE userId=json_extract(OLD._ferretdb_sjson,''$."_id"''); '+
      'DELETE FROM _wl_otp WHERE userId=json_extract(OLD._ferretdb_sjson,''$."_id"''); '+
      'DELETE FROM _wl_enrol WHERE userId=json_extract(OLD._ferretdb_sjson,''$."_id"''); END; ';
end;
end.
