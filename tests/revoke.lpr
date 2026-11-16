program revoke;
{$mode objfpc}{$H+}
uses SysUtils,wldb,wlrevoke;
var Db:TWLDb;Sql:string;
begin
  Db:=nil;
  try
    Db:=TWLDb.Create(ParamStr(1));
    if ParamStr(3)='one' then Sql:='BEGIN IMMEDIATE; '+RevokeTokenSQL(Db,ParamStr(2),ParamStr(5))
    else Sql:='BEGIN IMMEDIATE; '+RevokeUserTokensSQL(Db,ParamStr(2));
    if ParamStr(3)='disable' then Sql:=Sql+'UPDATE users SET loginDisabled=1 WHERE id='+QuotedStr(ParamStr(2))+'; ';
    Sql:=Sql+'COMMIT;';
    if ParamStr(4)<>'' then Db.Exec(ParamStr(4));
    if Db.Exec(Sql) then Writeln('yes') else begin Db.Exec('ROLLBACK;');Writeln('no');end;
  except if Db<>nil then Db.Exec('ROLLBACK;');Writeln('no');end;
  Db.Free;
end.
