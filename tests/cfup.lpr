program cfup;
{$mode objfpc}{$H+}
uses SysUtils,wldb,wlcfup;
var Db:TWLDb;
begin
  Db:=TWLDb.Create(ParamStr(1));
  try
    if ParamStr(2)='deadline' then
    begin if EnsureChecklistDeadlineColumns(Db) then Writeln('yes') else Writeln('no');end
    else if ParamStr(2)='policy' then
    begin if EnsureFieldPolicyColumns(Db) then Writeln('yes') else Writeln('no');end
    else if EnsureSettingsColumn(Db) and EnsureFieldPolicyColumns(Db) then Writeln('yes') else Writeln('no');
  finally Db.Free;end;
end.
