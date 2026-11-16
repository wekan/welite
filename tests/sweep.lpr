program sweep;
{$mode objfpc}{$H+}
uses SysUtils,wldb,wlsweep;
var Db:TWLDb;
begin
  Db:=nil;
  try Db:=TWLDb.Create(ParamStr(1));
    if ParamStr(3)='legacy' then
    begin if SweepLegacyTokens(Db,StrToInt64(ParamStr(2))) then Writeln('yes') else Writeln('no');end
    else if SweepSharedTokens(Db,StrToInt64(ParamStr(2))) then Writeln('yes') else Writeln('no');
  except Writeln('error');end;
  Db.Free;
end.
