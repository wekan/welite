program cfpres;
{$mode objfpc}{$H+}
uses SysUtils,fpjson,wldb,wlcfup,wlcfspec;
var Db:TWLDb;Doc:TJSONObject;
begin
  Db:=TWLDb.Create(ParamStr(1));
  try
    if ParamStr(2)='upgrade' then
    begin if EnsureDropdownColumn(Db) then Writeln('yes') else Writeln('no');end
    else begin
      Doc:=ReadDefinition(Db,ParamStr(2));
      try if Doc=nil then Writeln('null') else Writeln(Doc.AsJSON);finally Doc.Free;end;
    end;
  finally Db.Free;end;
end.
