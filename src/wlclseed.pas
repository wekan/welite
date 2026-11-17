unit wlclseed;
{$mode objfpc}{$H+}
interface
uses SysUtils,fpjson,wlsjson;
// Retain typed root data, excluding managed relations reconstructed by cloning.
function RootCloneSeed(const Source,Model:string):string;
implementation
function RootCloneSeed(const Source,Model:string):string;
var Plain,Spec,Parent:TJSONObject;Managed:TJSONData;Parts:TStringArray;Path:string;i,j:Integer;Child:TJSONData;
begin
  Plain:=nil;Spec:=nil;
  try
    Plain:=ExactObject(PlainDocument(Source));Spec:=ExactObject(Model);Managed:=Spec.Find('managed');
    if not (Managed is TJSONArray) then raise Exception.Create('Missing clone relation contract');
    for i:=0 to Managed.Count-1 do
    begin
      if Managed.Items[i].JSONType<>jtString then raise Exception.Create('Invalid clone relation path');
      Path:=Managed.Items[i].AsString;if Path='' then raise Exception.Create('Empty clone relation path');
      Parts:=Path.Split('.');Parent:=Plain;
      for j:=0 to High(Parts)-1 do
      begin
        if Parts[j]='' then raise Exception.Create('Invalid clone relation path');
        Child:=Parent.Find(Parts[j]);
        if Child=nil then begin Parent:=nil;Break;end;
        if not (Child is TJSONObject) then raise Exception.Create('Invalid clone relation parent');
        Parent:=TJSONObject(Child);
      end;
      if Parts[High(Parts)]='' then raise Exception.Create('Invalid clone relation path');
      if Parent<>nil then Parent.Delete(Parts[High(Parts)]);
    end;
    Result:=TypedDocument(Plain.AsJSON,Source,'{}');
  finally Spec.Free;Plain.Free;end;
end;
end.
