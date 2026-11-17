unit wlclrel;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,fpjson,wlsjson;
// Copy typed card relations after root creation, remapping selected dependencies.
function CloneCardRelations(const Target,Source,MapJson:string):string;
implementation
procedure Invalid;
begin raise Exception.Create('Invalid clone relations');end;
function PropertySchema(Schema:TJSONData;const Key:string):TJSONData;
var Props:TJSONData;
begin
  Result:=nil;if not (Schema is TJSONObject) then Exit;
  Props:=TJSONObject(Schema).Find('$s');if not (Props is TJSONObject) then Exit;
  Props:=TJSONObject(Props).Find('p');if Props is TJSONObject then Result:=TJSONObject(Props).Find(Key);
end;
function CanonicalString(Value,Schema:TJSONData):Boolean;
begin
  Result:=(Value<>nil) and (Value.JSONType=jtString) and (Value.AsString<>'') and
    (Schema is TJSONObject) and (TJSONObject(Schema).Get('t','')='string');
end;
function CloneCardRelations(const Target,Source,MapJson:string):string;
const Paths:array[0..4] of string=('members','assignees','labelIds','customFields','cardDependencies');
var Doc,Original,Typed,DestTyped,Maps,CardMap,Hints:TJSONObject;
  Values,Schema,Items,Row,RowSchema,Key,KeySchema,Kind:TJSONData;
  Keys:TStringList;Name,Identity,Signature,OldId,NewId:string;i,j:Integer;
begin
  Doc:=nil;Original:=nil;Typed:=nil;DestTyped:=nil;Maps:=nil;Hints:=nil;Keys:=nil;
  try
    Doc:=ExactObject(PlainDocument(Target));Original:=ExactObject(PlainDocument(Source));
    Typed:=ExactObject(Source);DestTyped:=ExactObject(Target);Maps:=CheckedJsonObject(MapJson);
    if not (Maps.Find('cards') is TJSONObject) then Invalid;CardMap:=TJSONObject(Maps.Find('cards'));
    for i:=0 to CardMap.Count-1 do
      if (CardMap.Names[i]='') or (CardMap.Items[i].JSONType<>jtString) or (CardMap.Items[i].AsString='') then Invalid;
    if not CanonicalString(Original.Find('_id'),TJSONObject(Typed.Find('$s')).Find('p').FindPath('_id')) then Invalid;
    OldId:=Original.Get('_id','');NewId:=CardMap.Get(OldId,'');
    if (NewId='') or (NewId=OldId) or (Doc.Get('_id','')<>NewId) then Invalid;
    if not CanonicalString(Doc.Find('_id'),TJSONObject(DestTyped.Find('$s')).Find('p').FindPath('_id')) then Invalid;
    if not CanonicalString(Original.Find('boardId'),TJSONObject(Typed.Find('$s')).Find('p').FindPath('boardId')) or
      not CanonicalString(Doc.Find('boardId'),TJSONObject(DestTyped.Find('$s')).Find('p').FindPath('boardId')) or
      (Original.Get('boardId','')<>Doc.Get('boardId','')) then Invalid;
    Hints:=TJSONObject.Create;Keys:=TStringList.Create;Keys.CaseSensitive:=True;Keys.Sorted:=True;
    for i:=0 to High(Paths) do
    begin
      Name:=Paths[i];Values:=Original.Find(Name);Doc.Delete(Name);if Values=nil then Continue;
      Schema:=TJSONObject(Typed.Find('$s')).Find('p').FindPath(Name);if Schema=nil then Invalid;
      Values:=Values.Clone;Doc.Add(Name,Values);
      if Values is TJSONArray then
      begin
        Items:=TJSONObject(Schema).Find('i');if not (Items is TJSONArray) or (Items.Count<>Values.Count) then Invalid;
        Keys.Clear;
        for j:=0 to Values.Count-1 do
        begin
          Row:=Values.Items[j];RowSchema:=Items.Items[j];
          if i<3 then begin Key:=Row;KeySchema:=RowSchema;end
          else
          begin
            if not (Row is TJSONObject) then Invalid;
            if i=3 then Identity:='_id' else Identity:='cardId';
            Key:=TJSONObject(Row).Find(Identity);KeySchema:=PropertySchema(RowSchema,Identity);
          end;
          if not CanonicalString(Key,KeySchema) then Invalid;
          Identity:=Key.AsString;
          if i=4 then
          begin
            NewId:=CardMap.Get(Identity,Identity);
            TJSONObject(Row).Strings['cardId']:=NewId;Identity:=NewId;
          end;
          Signature:=IntToStr(Length(Identity))+':'+Identity;
          if i=4 then
          begin
            Kind:=TJSONObject(Row).Find('type');KeySchema:=PropertySchema(RowSchema,'type');
            if (Kind=nil) or (Kind.JSONType=jtNull) then Identity:='related-to'
            else begin if not CanonicalString(Kind,KeySchema) then Invalid;Identity:=Kind.AsString;end;
            Signature:=Signature+IntToStr(Length(Identity))+':'+Identity;
          end;
          if Keys.IndexOf(Signature)>=0 then Invalid;Keys.Add(Signature);
        end;
      end;
      Hints.Add(Name,Schema.Clone);
    end;
    Result:=TypedDocument(Doc.AsJSON,Target,Hints.AsJSON);
  finally Keys.Free;Hints.Free;Maps.Free;DestTyped.Free;Typed.Free;Original.Free;Doc.Free;end;
end;
end.
