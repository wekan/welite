program cfsbatch;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,wldb,wlcfjson;
var Db:TWLDb;
begin
  SetMultiByteConversionCodePage(CP_UTF8);Db:=TWLDb.Create(ParamStr(1));
  try
    try ValidateBoardCustomFields(Db,ParamStr(2));Writeln('1');
    except on E:Exception do begin Writeln(StdErr,E.Message);Writeln('0');end;end;
  finally Db.Free;end;
end.
