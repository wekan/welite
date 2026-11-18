program chhash;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,wlsjson,wlchhash;
var Line:string;Row:TJSONObject;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  while not EOF do
  begin
    ReadLn(Line);
    Row:=ExactObject(Line);
    try WriteLn(ListLifecycleHash(Row));finally Row.Free;end;
  end;
end.
