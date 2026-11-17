program clrel;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,jsonparser,wlclrel;
var Line:string;Doc:TJSONObject;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  while not EOF(Input) do
  begin
    Readln(Line);Doc:=nil;
    try
      Doc:=TJSONObject(GetJSON(Line));
      Writeln(CloneCardRelations(Doc.Get('target',''),Doc.Get('source',''),Doc.Find('maps').AsJSON));
    except on E:Exception do Writeln('{"error":true}');end;
    Doc.Free;
  end;
end.
