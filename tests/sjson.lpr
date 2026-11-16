program sjson;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,Classes,fpjson,jsonparser,wlsjson;
var Line,Mode:string;Doc:TJSONObject;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  while not EOF(Input) do
  begin
    Readln(Line);Doc:=nil;
    try
      Doc:=TJSONObject(GetJSON(Line));Mode:=Doc.Get('mode','encode');
      if Mode='plain' then Writeln(PlainDocument(Doc.Get('old','')))
      else Writeln(TypedDocument(Doc.Get('new','{}'),Doc.Get('old',''),Doc.Get('hints','{}')));
    except on E:Exception do Writeln('{"error":"invalid"}');end;
    Doc.Free;
  end;
end.
