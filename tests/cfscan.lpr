program cfscan;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,jsonparser,wldb,wlsjson,wlcfscan;
var Db:TWLDb;Line,Before:string;InputDoc,Wrapper:TJSONObject;Payload:TJSONData;Allowed:Boolean;
begin
  SetMultiByteConversionCodePage(CP_UTF8);Db:=TWLDb.Create(ParamStr(1));
  try
    while not EOF(Input) do
    begin
      Readln(Line);InputDoc:=TJSONObject(GetJSON(Line));Wrapper:=nil;
      try
        Payload:=InputDoc.Find('payload');
        if InputDoc.Get('typed',False) then
        begin Wrapper:=TJSONObject.Create(['_wl_source',TypedDocument(Payload.AsJSON,'','')]);Payload:=Wrapper;end;
        Before:=Payload.AsJSON;Allowed:=ExportPayloadAllowed(Db,'u','board',Payload);
        if Payload.AsJSON<>Before then raise Exception.Create('Payload changed');
        Writeln(Ord(Allowed));
      finally Wrapper.Free;InputDoc.Free;end;
    end;
  finally Db.Free;end;
end.
