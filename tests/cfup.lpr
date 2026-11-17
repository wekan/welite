program cfup;
{$mode objfpc}{$H+}
uses SysUtils,wldb,wlcfup;
var Db:TWLDb;
begin
  Db:=TWLDb.Create(ParamStr(1));
  try if EnsureSettingsColumn(Db) then Writeln('yes') else Writeln('no');
  finally Db.Free;end;
end.
