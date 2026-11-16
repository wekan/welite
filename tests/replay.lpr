program replay;
{$mode objfpc}{$H+}
uses SysUtils,wldb,wlreplay;
var Db:TWLDb;Counter:Int64;Sql,UserId,Key,Token:string;
begin
  Db:=nil;
  try
    Db:=TWLDb.Create(ParamStr(1));
    if ParamStr(2)='last' then
    begin if LastOTPCounter(Db,ParamStr(3),OTPFactorKey(ParamStr(4)),Counter) then Writeln(Counter) else Writeln('error');end
    else if ParamStr(2)='ensure' then
    begin if EnsureOTPReplay(Db) then Writeln('ok') else Writeln('error');end
    else
    begin
      if not EnsureOTPReplay(Db) then begin Writeln('error');Halt(0);end;
      UserId:=ParamStr(3);Key:=OTPFactorKey(ParamStr(4));Counter:=StrToInt64(ParamStr(5));Token:=ParamStr(6);
      Sql:='BEGIN IMMEDIATE; INSERT INTO login_tokens(hashedToken,userId,createdAt) VALUES('+QuotedStr(Token)+','+QuotedStr(UserId)+',''now''); '+
        'INSERT INTO authmeta(hashedToken,tenantKey,credentialRef,kind) VALUES('+QuotedStr(Token)+',''test'',''fixture'',''api''); '+
        OTPReplaySQL(UserId,Key,Token,Counter)+'COMMIT;';
      if ParamStr(2)='without' then Sql:='BEGIN IMMEDIATE; '+OTPReplaySQL(UserId,Key,Token,Counter)+'COMMIT;';
      if Db.Exec(Sql) then Writeln('ok') else begin Db.Exec('ROLLBACK;');Writeln('error');end;
    end;
  except Writeln('error');end;
  Db.Free;
end.
