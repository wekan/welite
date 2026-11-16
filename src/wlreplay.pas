unit wlreplay;
{$mode objfpc}{$H+}
interface
uses SysUtils,wldb,wlcrypt,wltotp;
const OTPReplayDDL='CREATE TABLE _wl_otp(userId TEXT NOT NULL,factorKey TEXT NOT NULL,counter INTEGER NOT NULL CHECK(counter>=0),PRIMARY KEY(userId,factorKey)) STRICT';
function EnsureOTPReplay(Db:TWLDb):Boolean;
function OTPFactorKey(const Secret:string):string;
function LastOTPCounter(Db:TWLDb;const UserId,FactorKey:string;out Counter:Int64):Boolean;
// Append inside the same transaction as token/metadata insertion; caller MUST
// roll back the complete transaction if any statement fails. No token => no claim.
function OTPReplaySQL(const UserId,FactorKey,TokenKey:string;Counter:Int64):string;
implementation
const CleanupDDL='CREATE TRIGGER _wl_otp_cleanup AFTER DELETE ON users BEGIN DELETE FROM _wl_otp WHERE userId=OLD.id; END';
procedure Validate(const UserId,FactorKey:string);
var i:Integer;
begin
  if (UserId='') or (Length(FactorKey)<>64) then raise Exception.Create('Invalid OTP replay identity');
  for i:=1 to 64 do if not (FactorKey[i] in ['0'..'9','a'..'f']) then raise Exception.Create('Invalid OTP replay identity');
end;
function EnsureOTPReplay(Db:TWLDb):Boolean;
var Rows:TWLRows;
begin
  Result:=False;
  if not Db.Exec(StringReplace(OTPReplayDDL,'CREATE TABLE ','CREATE TABLE IF NOT EXISTS ',[])) then Exit;
  Rows:=Db.Query('SELECT type,sql FROM sqlite_master WHERE name=''_wl_otp'';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'table') or (Rows[0][1]<>OTPReplayDDL) then Exit;
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''users'';');
  if (Length(Rows)<>1) then Exit;
  if Rows[0][0]='view' then Exit(True); // the shared adapter owns its physical cleanup hook
  if Rows[0][0]<>'table' then Exit;
  if not Db.Exec(StringReplace(CleanupDDL,'CREATE TRIGGER ','CREATE TRIGGER IF NOT EXISTS ',[])) then Exit;
  Rows:=Db.Query('SELECT sql FROM sqlite_master WHERE type=''trigger'' AND name=''_wl_otp_cleanup'' AND tbl_name=''users'';');
  Result:=(Length(Rows)=1) and (Rows[0][0]=CleanupDDL);
end;
function OTPFactorKey(const Secret:string):string;
var Canonical:string;
begin
  Canonical:=OTPCanonicalSecret(Secret);
  try Result:=Sha256Hex('welite-otp-factor-v1'+#0+Canonical);
  finally if Canonical<>'' then begin UniqueString(Canonical);FillChar(Canonical[1],Length(Canonical),0);end;end;
end;
function LastOTPCounter(Db:TWLDb;const UserId,FactorKey:string;out Counter:Int64):Boolean;
var Rows:TWLRows;Scope:string;
begin
  Result:=False;Counter:=-1;
  try
    Validate(UserId,FactorKey);
    // The sentinel exists even for a new key. Query/schema errors cannot masquerade
    // as a missing replay record and therefore cannot reset the boundary.
    Scope:='userId='+QuotedStr(UserId)+' AND factorKey='+QuotedStr(FactorKey);
    Rows:=Db.Query('SELECT counter,1 FROM _wl_otp WHERE '+Scope+
      ' UNION ALL SELECT -1,0 WHERE NOT EXISTS(SELECT 1 FROM _wl_otp WHERE '+Scope+');');
    if (Length(Rows)<>1) or (Length(Rows[0])<>2) or not TryStrToInt64(Rows[0][0],Counter) or
      ((Rows[0][1]='1') and (Counter<0)) or ((Rows[0][1]='0') and (Counter<> -1)) then
    begin Counter:=-1;Exit;end;
    Result:=True;
  except Counter:=-1;end;
end;
function OTPReplaySQL(const UserId,FactorKey,TokenKey:string;Counter:Int64):string;
begin
  Validate(UserId,FactorKey);
  if (TokenKey='') or (Counter<0) then raise Exception.Create('Invalid OTP replay claim');
  // NOT NULL aborts a stale/duplicate claim. A preceding successful token insert
  // must be rolled back by the owner of the transaction, never committed alone.
  Result:='INSERT INTO _wl_otp(userId,factorKey,counter) SELECT '+QuotedStr(UserId)+','+QuotedStr(FactorKey)+','+IntToStr(Counter)+
    ' WHERE EXISTS(SELECT 1 FROM login_tokens WHERE hashedToken='+QuotedStr(TokenKey)+' AND userId='+QuotedStr(UserId)+') '+
    'ON CONFLICT(userId,factorKey) DO UPDATE SET counter=CASE WHEN excluded.counter>_wl_otp.counter THEN excluded.counter ELSE NULL END; ';
end;
end.
