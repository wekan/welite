program cfscan;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,jsonparser,wldb,wlsjson,wlcfscan;
var Db:TWLDb;Line,Before,Guards,Hints:string;InputDoc,Wrapper:TJSONObject;Payload:TJSONData;Allowed:Boolean;
begin
  SetMultiByteConversionCodePage(CP_UTF8);Db:=TWLDb.Create(ParamStr(1));
  try
    while not EOF(Input) do
    begin
      Readln(Line);InputDoc:=TJSONObject(GetJSON(Line));Wrapper:=nil;
      try
        Payload:=InputDoc.Find('payload');
        if InputDoc.Get('typed',False) then
        begin
          Hints:='';if InputDoc.Find('hints')<>nil then Hints:=InputDoc.Find('hints').AsJSON;
          Wrapper:=TJSONObject.Create(['_wl_source',TypedDocument(Payload.AsJSON,'',Hints)]);Payload:=Wrapper;
        end;
        Before:=Payload.AsJSON;
        if InputDoc.Get('copy',False) then
        begin
          Allowed:=PayloadCopyGuards(Db,'u','board',Payload,Guards);
          if Allowed then
          begin
            if InputDoc.Get('revoke',False) then Guards:='UPDATE custom_fields SET readOnly=1 WHERE id=''f''; '+Guards;
            Allowed:=Db.Exec('BEGIN IMMEDIATE; '+Guards+'ROLLBACK;');if not Allowed then Db.Exec('ROLLBACK;');
          end;
        end
        else Allowed:=ExportPayloadAllowed(Db,'u','board',Payload);
        if Payload.AsJSON<>Before then raise Exception.Create('Payload changed');
        Writeln(Ord(Allowed));
      finally Wrapper.Free;InputDoc.Free;end;
    end;
  finally Db.Free;end;
end.
