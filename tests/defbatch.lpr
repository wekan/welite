program defbatch;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,wldb,wlcfspec;
var Db:TWLDb;
begin
  SetMultiByteConversionCodePage(CP_UTF8);Db:=TWLDb.Create(ParamStr(1));
  try
    try Writeln(Ord(BoardDefinitionAdminRequired(Db,ParamStr(2))));
    except on E:Exception do begin Writeln(StdErr,E.Message);Writeln('error');end;end;
  finally Db.Free;end;
end.
