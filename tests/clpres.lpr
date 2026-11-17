program clpres;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,jsonparser,wlclseed,wlproj;
var Line,Seed,Previous,Projected:string;InputDoc,Patch,Envelope,OutputDoc:TJSONObject;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  while not EOF(Input) do
  begin
    Readln(Line);InputDoc:=nil;Patch:=nil;Envelope:=nil;OutputDoc:=nil;
    try
      InputDoc:=TJSONObject(GetJSON(Line));Seed:=RootCloneSeed(InputDoc.Get('source',''),InputDoc.Find('model').AsJSON);
      if InputDoc.Find('patch') is TJSONObject then Patch:=TJSONObject(InputDoc.Find('patch').Clone)
      else Patch:=CloneRootPatch(Seed,InputDoc.Find('model').AsJSON,TJSONObject(InputDoc.Find('before')),TJSONObject(InputDoc.Find('after')),InputDoc.Get('sort',True),InputDoc.Get('number',True));
      if InputDoc.Find('envelope')<>nil then Previous:=InputDoc.Find('envelope').AsJSON
      else
      begin
        Envelope:=TJSONObject.Create(['_wl_clone',1,'source',Seed]);Envelope.Add('columns',Patch.Clone);Previous:=Envelope.AsJSON;
      end;
      if InputDoc.Get('ordinary',False) then Projected:=ProjectDocument(Seed,Patch.AsJSON,InputDoc.Find('model').AsJSON,'insert')
      else Projected:=ProjectDocument(Previous,InputDoc.Find('after').AsJSON,InputDoc.Find('model').AsJSON,'insert');
      OutputDoc:=TJSONObject.Create;OutputDoc.Add('patch',Patch.Clone);OutputDoc.Add('doc',GetJSON(Projected));Writeln(OutputDoc.AsJSON);
    except on E:Exception do Writeln('{"error":true}');end;
    OutputDoc.Free;Envelope.Free;Patch.Free;InputDoc.Free;
  end;
end.
