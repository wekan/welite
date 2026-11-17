program clseed;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,jsonparser,wlclseed,wlproj;
var Line,Seed:string;Doc:TJSONObject;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  while not EOF(Input) do
  begin
    Readln(Line);Doc:=nil;
    try
      Doc:=TJSONObject(GetJSON(Line));Seed:=RootCloneSeed(Doc.Get('source',''),Doc.Find('model').AsJSON);
      if Doc.Get('mode','seed')='project' then Seed:=ProjectDocument(Seed,Doc.Find('patch').AsJSON,Doc.Find('model').AsJSON,'insert');
      Writeln(Seed);
    except on E:Exception do Writeln('{"error":true}');end;
    Doc.Free;
  end;
end.
