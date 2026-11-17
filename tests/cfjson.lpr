program cfjson;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,wlcfjson;
var Line:string;Rows:TJSONArray;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  while not EOF(Input) do
  begin
    Readln(Line);Rows:=nil;
    try
      Rows:=CustomFieldsJson(Line);Writeln(Rows.AsJSON);
    except on E:Exception do Writeln('{"error":"invalid"}');end;
    Rows.Free;
  end;
end.
