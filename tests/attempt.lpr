program attempt;
{$mode objfpc}{$H+}
uses SysUtils,wldb,wlattemp;
var Db:TWLDb;
begin
  Db:=TWLDb.Create(ParamStr(1));
  try
    if ReserveLoginAttempt(Db,ParamStr(2),ParamStr(3),StrToInt64(ParamStr(4))) then Writeln('yes') else Writeln('no');
  finally Db.Free;end;
end.
