unit wlclseed;
{$mode objfpc}{$H+}
interface
uses SysUtils,fpjson,wlsjson;
// Retain typed root data, excluding managed relations reconstructed by cloning.
function RootCloneSeed(const Source,Model:string):string;
function CloneReferenceTable(const Name,TableName:string):string;
function CloneRootPatch(const Source,Model:string;Before,After:TJSONObject;NewSort,NewNumber:Boolean):TJSONObject;
implementation
function CloneReferenceTable(const Name,TableName:string):string;
begin
  Result:='';
  case Name of
    'swimlaneId':Result:='swimlanes';
    'listId':Result:='lists';
    'cardId','targetCardId','linkedId':Result:='cards';
    'checklistId':Result:='checklists';
    'commentId':Result:='card_comments';
    'itemId':Result:='checklist_items';
    'coverId','attachmentId':Result:='attachments';
    'parentId':if TableName='card_comments' then Result:='card_comments' else Result:='cards';
  end;
end;
function SourceSchema(Doc:TJSONObject;const Path:string):TJSONData;
var Parts:TStringArray;i:Integer;Node:TJSONData;
begin
  Result:=nil;Parts:=Path.Split('.');Node:=Doc.Find('$s');
  for i:=0 to High(Parts) do
  begin
    if not (Node is TJSONObject) then Exit;
    Node:=TJSONObject(Node).Find('p');if not (Node is TJSONObject) then Exit;
    Node:=TJSONObject(Node).Find(Parts[i]);
    if i<High(Parts) then
    begin if not (Node is TJSONObject) then Exit;Node:=TJSONObject(Node).Find('$s');end;
  end;
  Result:=Node;
end;
function CloneRootPatch(const Source,Model:string;Before,After:TJSONObject;NewSort,NewNumber:Boolean):TJSONObject;
var Spec,Typed,Field:TJSONObject;Fields:TJSONArray;Value,Old,Schema:TJSONData;
  Name,TableName:string;i:Integer;Changed,CopyValue:Boolean;
begin
  Result:=nil;Spec:=nil;Typed:=nil;
  try
    try
    // Validate source metadata even when none of the optional references changed.
    Typed:=ExactObject(PlainDocument(Source));FreeAndNil(Typed);Typed:=ExactObject(Source);
    Spec:=CheckedJsonObject(Model);TableName:=Spec.Get('table','');
    if not (Spec.Find('fields') is TJSONArray) then raise Exception.Create('Missing clone fields');
    Fields:=TJSONArray(Spec.Find('fields'));Result:=TJSONObject.Create;
    for i:=0 to Fields.Count-1 do
    begin
      Field:=Fields.Objects[i];if Field.Get('kind','')='extra' then Continue;
      Name:=Field.Get('name','');Value:=After.Find(Name);if Value=nil then Continue;
      Old:=Before.Find(Name);Changed:=(Old=nil) or (Old.AsJSON<>Value.AsJSON);
      CopyValue:=(Name='id') or (Name='createdAt') or (Name='modifiedAt') or (Name='dateLastActivity') or
        ((Name='title') and Changed) or ((Name='sort') and NewSort) or ((Name='cardNumber') and NewNumber);
      if not CopyValue and Changed and (CloneReferenceTable(Name,TableName)<>'') then
      begin
        Schema:=SourceSchema(Typed,Field.Get('path',''));
        CopyValue:=(Schema is TJSONObject) and (TJSONObject(Schema).Get('t','')='string');
      end;
      if CopyValue then Result.Add(Name,Value.Clone);
    end;
    except FreeAndNil(Result);raise;end;
  finally Typed.Free;Spec.Free;end;
end;

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
