program cfspec;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,jsonparser,wlcfspec,wlcfjson,wldb;
var Line:string;Doc,Settings,Response:TJSONObject;OK:Boolean;Db:TWLDb;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  while not EOF(Input) do
  begin
    Readln(Line);Doc:=nil;Settings:=nil;Response:=nil;
    try
      Doc:=TJSONObject(GetJSON(Line));
      if Doc.Get('mode','input')='read' then
      begin
        Db:=TWLDb.Create(Doc.Get('path',''));
        try Response:=ReadDefinition(Db,Doc.Get('id',''));finally Db.Free;end;
      end
      else if Doc.Get('mode','input')='document' then Response:=DocumentJson(Doc.Get('document',''))
      else begin
        OK:=SettingsInput(Doc.Find('settings'),Settings);Response:=TJSONObject.Create(['ok',OK]);
        if OK then begin Response.Add('settings',Settings);Settings:=nil;end;
      end;
      if Response=nil then Writeln('null') else Writeln(Response.AsJSON);
    except on E:Exception do Writeln('{"error":"invalid"}');end;
    Response.Free;Settings.Free;Doc.Free;
  end;
end.
