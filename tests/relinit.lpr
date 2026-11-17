program relinit;
{$mode objfpc}{$H+}
uses SysUtils,fpjson,jsonparser,wlproj,wlsjson;
var Line:string;Doc:TJSONObject;
begin
  while not EOF(Input) do
  begin
    Readln(Line);Doc:=nil;
    try
      Doc:=TJSONObject(GetJSON(Line));
      Writeln(RelationDocument(Doc.Get('source',''),Doc.Get('command',''),Doc.Get('model','')));
    except on E:Exception do Writeln('{"error":"invalid"}');end;
    Doc.Free;
  end;
end.
