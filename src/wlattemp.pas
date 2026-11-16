unit wlattemp;
{$mode objfpc}{$H+}
interface
uses SysUtils,wldb,wlcrypt;
const AttemptDDL='CREATE TABLE _wl_attempt(bucket TEXT PRIMARY KEY,started INTEGER NOT NULL CHECK(started>=0),attempts INTEGER NOT NULL CHECK(attempts BETWEEN 1 AND 300)) STRICT';
// Reserve before credential verification. Caller supplies trusted server Unix time
// and the socket peer, never forwarded headers or a client-supplied timestamp.
// Successes also consume attempts; no account-existence or success reset oracle.
function ReserveLoginAttempt(Db:TWLDb;const Username,Peer:string;NowSeconds:Int64):Boolean;
implementation
function ReserveLoginAttempt(Db:TWLDb;const Username,Peer:string;NowSeconds:Int64):Boolean;
var Rows:TWLRows;Sql,Key,At:string;i,Limit:Integer;
begin
  Result:=False;
  if (NowSeconds<0) or (Username='') or (Length(Username)>4096) or (Peer='') or (Length(Peer)>256) then Exit;
  try
    if not Db.Exec(StringReplace(AttemptDDL,'CREATE TABLE ','CREATE TABLE IF NOT EXISTS ',[])) then Exit;
    Rows:=Db.Query('SELECT type,sql FROM sqlite_master WHERE name=''_wl_attempt'';');
    if (Length(Rows)<>1) or (Rows[0][0]<>'table') or (Rows[0][1]<>AttemptDDL) then Exit;
    At:=IntToStr(NowSeconds);
    Sql:='BEGIN IMMEDIATE; ';
    // Each bucket lasts 300 seconds from its first reservation. Keep its timestamp
    // on clock rollback: a backward clock cannot mint another allowance.
    for i:=0 to 2 do
    begin
      case i of
        0:begin Key:='tenant';Limit:=300;end;
        1:begin Key:='peer:'+Sha256Hex(Peer);Limit:=30;end;
        else begin Key:='account:'+Sha256Hex(Username);Limit:=5;end;
      end;
      Sql:=Sql+'INSERT INTO _wl_attempt(bucket,started,attempts) VALUES('+QuotedStr(Key)+','+At+',1) '+
        'ON CONFLICT(bucket) DO UPDATE SET attempts=CASE WHEN '+At+'<_wl_attempt.started THEN NULL '+
        'WHEN '+At+'-_wl_attempt.started>=300 THEN 1 WHEN _wl_attempt.attempts<'+IntToStr(Limit)+
        ' THEN _wl_attempt.attempts+1 ELSE NULL END,started=CASE WHEN '+At+'-_wl_attempt.started>=300 THEN '+At+' ELSE _wl_attempt.started END; ';
    end;
    // Tenant cap bounds live cardinality to 300 account + 300 peer + one tenant.
    // Only successful reservations clean up; failed attempts cannot alter counters.
    Sql:=Sql+'DELETE FROM _wl_attempt WHERE '+At+'-started>=300; COMMIT;';
    Result:=Db.Exec(Sql);
    if not Result then Db.Exec('ROLLBACK;');
  except Db.Exec('ROLLBACK;');Result:=False;end;
end;
end.
