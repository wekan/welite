unit wlpair;
{$mode objfpc}{$H+}
interface
uses SysUtils,wldb,wlautsrc,wlcrypt,wlresume;
const PairDDL='CREATE TABLE _wl_pair(hashedToken TEXT PRIMARY KEY NOT NULL,userId TEXT NOT NULL,sharedHash TEXT CHECK(sharedHash IS NULL OR length(sharedHash)=44),sourceUUID TEXT NOT NULL CHECK(length(sourceUUID)=36)) STRICT';
// Append to an authorized shared issuance/adoption transaction. No raw bearer is
// persisted. Retain source-bound identity after local deletion for later revocation.
function StorePairSQL(Db:TWLDb;const UserId,Token:string):string;
// Metadata maintenance after successful local/shared validation; not authentication.
// Opens a transaction only when upgrading a missing or unknown link.
function EnsurePair(Db:TWLDb;const UserId,Token:string):Boolean;
implementation
function StorePairSQL(Db:TWLDb;const UserId,Token:string):string;
var Key,Hash,Condition,Issued,Present:string;
begin
  if UserId='' then raise Exception.Create('Missing paired account');
  Key:=TenantTokenHash(Db.Path,Token);Hash:=MeteorTokenHash(Token);Condition:=AuthSourceCondition(Db);
  Issued:='EXISTS(SELECT 1 FROM login_tokens t JOIN authmeta m USING(hashedToken) WHERE t.hashedToken='+QuotedStr(Key)+' AND t.userId='+QuotedStr(UserId)+' AND m.kind=''api'')';
  Result:='INSERT INTO _wl_pair SELECT '+QuotedStr(Key)+','+QuotedStr(UserId)+','+QuotedStr(Hash)+',userUUID FROM _wl_authsrc WHERE id=1 AND ('+Condition+') AND ('+Issued+') '+
    'ON CONFLICT(hashedToken) DO UPDATE SET userId=excluded.userId,sharedHash=excluded.sharedHash,sourceUUID=excluded.sourceUUID; ';
  Present:='EXISTS(SELECT 1 FROM _wl_pair p JOIN _wl_authsrc a ON p.sourceUUID=a.userUUID WHERE a.id=1 AND p.hashedToken='+QuotedStr(Key)+' AND p.userId='+QuotedStr(UserId)+' AND p.sharedHash='+QuotedStr(Hash)+')';
  Result:=Result+'UPDATE _wl_authsrc SET userUUID=CASE WHEN ('+Condition+') AND (NOT ('+Issued+') OR ('+Present+')) THEN userUUID ELSE NULL END WHERE id=1; ';
end;
function EnsurePair(Db:TWLDb;const UserId,Token:string):Boolean;
var Rows:TWLRows;Match,Key,Hash:string;
begin
  Result:=False;
  try
    if not AuthSourceCurrent(Db) then Exit;
    Key:=TenantTokenHash(Db.Path,Token);Hash:=MeteorTokenHash(Token);
    Match:='SELECT 1 FROM _wl_pair p JOIN _wl_authsrc a ON p.sourceUUID=a.userUUID WHERE a.id=1 AND p.hashedToken='+QuotedStr(Key)+' AND p.userId='+QuotedStr(UserId)+' AND p.sharedHash='+QuotedStr(Hash)+';';
    Rows:=Db.Query(Match);if Length(Rows)=1 then Exit(True);
    if not Db.Exec('BEGIN IMMEDIATE; '+StorePairSQL(Db,UserId,Token)+'COMMIT;') then
    begin Db.Exec('ROLLBACK;');Exit;end;
    Result:=Length(Db.Query(Match))=1;
  except Db.Exec('ROLLBACK;');Result:=False;end;
end;
end.
