unit wlautsrc;
{$mode objfpc}{$H+}
interface
uses SysUtils,wldb;
const AuthSourceDDL='CREATE TABLE _wl_authsrc(id INTEGER PRIMARY KEY CHECK(id=1),userTable TEXT NOT NULL,userUUID TEXT NOT NULL CHECK(length(userUUID)=36)) STRICT';
function AuthSourceCurrent(Db:TWLDb):Boolean;
function AuthSourceCondition(Db:TWLDb):string;
function AuthSourceScript(const Users:string):string;
implementation
function SourceMatch(const Users:string):string;
begin
  Result:='EXISTS(SELECT 1 FROM _wl_authsrc a JOIN _ferretdb_collections c ON c.table_name=a.userTable '+
    'WHERE a.id=1 AND c.name=''users'' AND c.table_name='+QuotedStr(Users)+
    ' AND json_type(c.settings,''$.uuid'')=''text'' AND a.userUUID=json_extract(c.settings,''$.uuid''))';
end;
function AuthSourceScript(const Users:string):string;
var Missing,Changed:string;
begin
  Missing:='NOT '+SourceMatch(Users);
  Changed:='EXISTS(SELECT 1 FROM _wl_authsrc) AND '+Missing;
  // Legacy unbound installations lose credentials and pending setup, but retain
  // replay boundaries conservatively. A known new collection gets a new ledger.
  Result:='DELETE FROM authmeta WHERE '+Missing+'; DELETE FROM login_tokens WHERE '+Missing+'; '+
    'DELETE FROM _wl_enrol WHERE '+Missing+'; DELETE FROM _wl_otp WHERE '+Changed+'; '+
    'INSERT INTO _wl_authsrc(id,userTable,userUUID) VALUES(1,'+QuotedStr(Users)+
    ',(SELECT CASE WHEN json_type(settings,''$.uuid'')=''text'' THEN json_extract(settings,''$.uuid'') ELSE NULL END '+
    'FROM _ferretdb_collections WHERE name=''users'' AND table_name='+QuotedStr(Users)+')) '+
    'ON CONFLICT(id) DO UPDATE SET userTable=excluded.userTable,userUUID=excluded.userUUID; ';
end;
function AuthSourceCurrent(Db:TWLDb):Boolean;
var Rows:TWLRows;
begin
  Result:=False;
  try
    Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''users'';');
    if Length(Rows)<>1 then Exit;
    if Rows[0][0]='table' then
    begin
      Rows:=Db.Query('SELECT count(*) FROM sqlite_master WHERE name=''_wl_authsrc'';');
      Exit((Length(Rows)=1) and (Rows[0][0]='0'));
    end;
    if Rows[0][0]<>'view' then Exit;
    Rows:=Db.Query('SELECT a.userTable FROM _wl_authsrc a JOIN _wl_models m ON m.name=''users'' AND m.table_name=a.userTable WHERE a.id=1;');
    if Length(Rows)<>1 then Exit;
    Rows:=Db.Query('SELECT 1 WHERE '+SourceMatch(Rows[0][0])+';');
    Result:=(Length(Rows)=1) and (Rows[0][0]='1');
  except Result:=False;end;
end;
function AuthSourceCondition(Db:TWLDb):string;
var Rows:TWLRows;
begin
  Result:='0';if not AuthSourceCurrent(Db) then Exit;
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''users'';');
  if Length(Rows)<>1 then Exit;
  if Rows[0][0]='table' then
    Exit('EXISTS(SELECT 1 FROM sqlite_master WHERE name=''users'' AND type=''table'') AND NOT EXISTS(SELECT 1 FROM sqlite_master WHERE name=''_wl_authsrc'')');
  Rows:=Db.Query('SELECT userTable,userUUID FROM _wl_authsrc WHERE id=1;');
  if Length(Rows)<>1 then Exit;
  Result:=SourceMatch(Rows[0][0])+' AND EXISTS(SELECT 1 FROM _wl_authsrc WHERE id=1 AND userTable='+QuotedStr(Rows[0][0])+' AND userUUID='+QuotedStr(Rows[0][1])+')';
end;

end.
