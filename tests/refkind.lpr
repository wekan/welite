program refkind;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,Classes,fpjson,jsonparser,wlrefs;
var Line,Sql:string;Doc,OutDoc,Map:TJSONObject;Tables:TStringList;i:Integer;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  while not EOF(Input) do
  begin
    Readln(Line);Doc:=nil;Tables:=nil;OutDoc:=nil;
    try
      Doc:=TJSONObject(GetJSON(Line));Tables:=TStringList.Create;Map:=TJSONObject(Doc.Find('tables'));
      for i:=0 to Map.Count-1 do Tables.Values[Map.Names[i]]:=Map.Items[i].AsString;
      if Doc.Get('mode','check')='check' then Sql:=ReferenceChecks(TJSONObject(Doc.Find('model')),'NEW._ferretdb_sjson',Tables)
      else Sql:=DeleteCascades(TJSONArray(Doc.Find('models')),'boards',Tables);
      OutDoc:=TJSONObject.Create(['sql',Sql]);Writeln(OutDoc.AsJSON);
    except on E:Exception do Writeln('{"error":true}');end;
    OutDoc.Free;Tables.Free;Doc.Free;
  end;
end.
