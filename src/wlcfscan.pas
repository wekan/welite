unit wlcfscan;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,fpjson,wldb;
// Inspect encoded export payloads without changing their bytes or source data.
function ExportPayloadAllowed(Db:TWLDb;const UserId,BoardId:string;Data:TJSONData;AllowPublicGuest:Boolean=False):Boolean;
function PayloadCopyGuards(Db:TWLDb;const UserId,BoardId:string;Data:TJSONData;out Sql:string):Boolean;
implementation
uses wlcfpol,wlsjson;
type
  TPayloadPolicy=class
    Db:TWLDb;
    UserId,Guards:string;
    AllowPublicGuest:Boolean;
    WriteAccess,Collect:Boolean;
    Keys,Answers:TStringList;
    function Permitted(const BoardId,FieldId:string;Admin:Boolean):Boolean;
    function Visit(Data:TJSONData;const BoardId:string;Depth:Integer;Encoded:Boolean=True;Schema:TJSONData=nil;ScopeValid:Boolean=True):Boolean;
    function FieldArray(Data:TJSONData;const BoardId:string;Depth:Integer;Encoded:Boolean=True;Schema:TJSONData=nil;ScopeValid:Boolean=True):Boolean;
  end;
function ChildSchema(Schema:TJSONData;const Name:string):TJSONData;
var Node:TJSONData;
begin
  Result:=nil;if not (Schema is TJSONObject) then Exit;
  Node:=TJSONObject(Schema).Find('$s');if not (Node is TJSONObject) then Exit;
  Node:=TJSONObject(Node).Find('p');if Node is TJSONObject then Result:=TJSONObject(Node).Find(Name);
end;
function ItemSchema(Schema:TJSONData;Index:Integer):TJSONData;
var Node:TJSONData;
begin
  Result:=nil;if not (Schema is TJSONObject) then Exit;
  Node:=TJSONObject(Schema).Find('i');if (Node is TJSONArray) and (Index<Node.Count) then Result:=Node.Items[Index];
end;
function StringValue(Data,Schema:TJSONData):Boolean;
begin
  Result:=(Data<>nil) and (Data.JSONType=jtString);
  if Result and (Schema<>nil) then Result:=(Schema is TJSONObject) and (TJSONObject(Schema).Get('t','')='string');
end;
function FalsyScope(Data,Schema:TJSONData):Boolean;
var Kind:string;
begin
  Result:=Data.JSONType=jtNull;if Result then Exit;
  Kind:='';if Schema is TJSONObject then Kind:=TJSONObject(Schema).Get('t','');
  if (Kind<>'') and (Kind<>'bool') and (Kind<>'int') and (Kind<>'double') then Exit(False);
  if Data.JSONType=jtBoolean then Result:=not Data.AsBoolean
  else if Data.JSONType=jtNumber then Result:=Data.AsFloat=0
  else if (Kind='double') and (Data.JSONType=jtString) then Result:=Data.AsString='NaN';
end;
function SeedCoversExtra(Obj:TJSONObject):Boolean;
var Seed,Extra:TJSONData;Plain,Encoded:TJSONObject;Value:TJSONData;i:Integer;
begin
  Result:=False;Seed:=Obj.Find('_wl_source');Extra:=Obj.Find('extra_json');
  if (Seed=nil) or (Extra=nil) or (Seed.JSONType<>jtString) or (Extra.JSONType<>jtString) or (Seed.AsString='') then Exit;
  Plain:=nil;Encoded:=nil;
  try
    Plain:=ExactObject(PlainDocument(Seed.AsString));Encoded:=CheckedJsonObject(Extra.AsString);
    for i:=0 to Encoded.Count-1 do
    begin
      Value:=Plain.Find(Encoded.Names[i]);
      if (Value=nil) or (Value.AsJSON<>Encoded.Items[i].AsJSON) then Exit;
    end;
    Result:=True;
  finally Encoded.Free;Plain.Free;end;
end;
function TPayloadPolicy.Permitted(const BoardId,FieldId:string;Admin:Boolean):Boolean;
var Key,Sql:string;Index:Integer;Policy:TFieldPolicy;Rows:TWLRows;Tuple:TJSONArray;
begin
  Result:=False;if (BoardId='') or ((FieldId='') and not Admin) then Exit;
  Tuple:=TJSONArray.Create;try Tuple.Add(BoardId);Tuple.Add(FieldId);Tuple.Add(Admin);Key:=Tuple.AsJSON;finally Tuple.Free;end;
  Index:=Keys.IndexOf(Key);if Index>=0 then Exit(Answers[Index]='1');
  Policy:=TFieldPolicy.Create(Db,UserId,BoardId,'',AllowPublicGuest);
  try
    if Admin then Sql:=Policy.ScopeAdminExpression
    else if WriteAccess then Sql:=Policy.ScopeWriteExpression(FieldId) else Sql:=Policy.HistoryExpression(FieldId);
    Rows:=Db.Query('SELECT '+Sql+';');Result:=(Length(Rows)=1) and (Rows[0][0]='1');
    if Result and Collect then Guards:=Guards+'SELECT CASE WHEN '+Sql+' THEN 1 ELSE json(''Copied payload permission denied'') END; ';
  finally Policy.Free;end;
  Keys.Add(Key);if Result then Answers.Add('1') else Answers.Add('0');
end;
function TPayloadPolicy.FieldArray(Data:TJSONData;const BoardId:string;Depth:Integer;Encoded:Boolean;Schema:TJSONData;ScopeValid:Boolean):Boolean;
var i:Integer;Row:TJSONObject;Id,Value,RowSchema:TJSONData;
begin
  Result:=False;
  if Data.JSONType=jtNull then Exit(True);
  // Empty legacy objects contain no custom values; other malformed shapes deny.
  if Data is TJSONObject then Exit(Data.Count=0);
  if not (Data is TJSONArray) then Exit;
  for i:=0 to Data.Count-1 do
  begin
    if Data.Items[i] is TJSONObject then
    begin
      Row:=TJSONObject(Data.Items[i]);RowSchema:=ItemSchema(Schema,i);Id:=Row.Find('_id');Value:=Row.Find('value');
      if Value<>nil then
      begin
        if (Id=nil) or (Id.JSONType<>jtString) then Exit;
        if (Value.JSONType<>jtNull) or (Row.Count>2) then
        begin
          if not ScopeValid or not StringValue(Id,ChildSchema(RowSchema,'_id')) or
            not Permitted(BoardId,Id.AsString,False) then Exit;
        end;
      end;
    end;
    if not Visit(Data.Items[i],BoardId,Depth+1,Encoded,ItemSchema(Schema,i),ScopeValid) then Exit;
  end;
  Result:=True;
end;
function TPayloadPolicy.Visit(Data:TJSONData;const BoardId:string;Depth:Integer;Encoded:Boolean;Schema:TJSONData;ScopeValid:Boolean):Boolean;
var Obj,Decoded,Typed,DecodedSchema:TJSONObject;Item,ScopeValue,FieldId,Marker:TJSONData;Scope,Name,Text:string;i:Integer;TypedExtra:Boolean;
begin
  Result:=False;if (Data=nil) or (Depth>256) then Exit;
  if Data is TJSONArray then
  begin
    for i:=0 to Data.Count-1 do if not Visit(Data.Items[i],BoardId,Depth+1,Encoded,ItemSchema(Schema,i),ScopeValid) then Exit;
    Exit(True);
  end;
  if not (Data is TJSONObject) then Exit(True);
  Obj:=TJSONObject(Data);Scope:=BoardId;ScopeValue:=Obj.Find('boardId');
  if (ScopeValue<>nil) and (ScopeValue.JSONType<>jtNull) then
  begin
    if StringValue(ScopeValue,ChildSchema(Schema,'boardId')) then
    begin if ScopeValue.AsString<>'' then begin Scope:=ScopeValue.AsString;ScopeValid:=True;end;end
    else if not FalsyScope(ScopeValue,ChildSchema(Schema,'boardId')) then ScopeValid:=False;
  end;
  FieldId:=Obj.Find('customFieldId');Marker:=Obj.Find('field');
  TypedExtra:=Encoded and SeedCoversExtra(Obj);
  for i:=0 to Obj.Count-1 do
  begin
    Name:=Obj.Names[i];Item:=Obj.Items[i];
    // A matching typed seed is authoritative for the root remainder. Its BSON
    // identity must not be replaced by the lossy plain SQL JSON projection.
    if TypedExtra and (Name='extra_json') then Continue;
    if ((Name='integrityHash') or (Name='previousHash')) and (Item.JSONType<>jtNull) then
    begin if not ScopeValid or not Permitted(Scope,'',True) then Exit;end
    else if (Name='customFields') or (((Name='value') or (Name='oldValue') or (Name='newValue') or (Name='customFieldValue')) and (Marker<>nil) and StringValue(Marker,ChildSchema(Schema,'field')) and (Marker.AsString='customFields')) then
    begin if not FieldArray(Item,Scope,Depth+1,Encoded,ChildSchema(Schema,Name),ScopeValid) then Exit;Continue;end
    else if ((Name='value') or (Name='oldValue') or (Name='newValue') or (Name='customFieldValue')) and
      (FieldId<>nil) and (Item.JSONType<>jtNull) then
    begin
      if not ScopeValid or not StringValue(FieldId,ChildSchema(Schema,'customFieldId')) or not Permitted(Scope,FieldId.AsString,False) then Exit;
    end;
    if Encoded and ((Name='_wl_source') or (Copy(Name,Length(Name)-4,5)='_json')) then
    begin
      if Item.JSONType=jtNull then Continue;
      if Item.JSONType<>jtString then Exit;
      Text:=Item.AsString;Decoded:=nil;Typed:=nil;DecodedSchema:=nil;
      try
        if Name='_wl_source' then
        begin
          Decoded:=ExactObject(PlainDocument(Text));Typed:=ExactObject(Text);
          DecodedSchema:=TJSONObject.Create(['t','object']);DecodedSchema.Add('$s',Typed.Find('$s').Clone);
        end
        else Decoded:=CheckedJsonObject('{"payload":'+Text+'}');
        if Name='_wl_source' then
        begin if not Visit(Decoded,Scope,Depth+1,False,DecodedSchema,ScopeValid) then Exit;end
        else if not Visit(Decoded.Find('payload'),Scope,Depth+1,False,nil,ScopeValid) then Exit;
      finally DecodedSchema.Free;Typed.Free;Decoded.Free;end;
    end
    else if not Visit(Item,Scope,Depth+1,Encoded,ChildSchema(Schema,Name),ScopeValid) then Exit;
  end;
  Result:=True;
end;
function InspectPayload(Db:TWLDb;const UserId,BoardId:string;Data:TJSONData;CopyAccess,AllowPublicGuest:Boolean;out Sql:string):Boolean;
var Policy:TPayloadPolicy;
begin
  Result:=False;Sql:='';Policy:=TPayloadPolicy.Create;
  Policy.Keys:=TStringList.Create;Policy.Keys.CaseSensitive:=True;Policy.Answers:=TStringList.Create;
  try
    Policy.Db:=Db;Policy.UserId:=UserId;Policy.AllowPublicGuest:=AllowPublicGuest;Policy.WriteAccess:=CopyAccess;Policy.Collect:=CopyAccess;
    try Result:=Policy.Visit(Data,BoardId,0);if Result then Sql:=Policy.Guards;except Result:=False;end;
  finally Policy.Answers.Free;Policy.Keys.Free;Policy.Free;end;
end;
function ExportPayloadAllowed(Db:TWLDb;const UserId,BoardId:string;Data:TJSONData;AllowPublicGuest:Boolean):Boolean;
var Ignored:string;
begin Result:=InspectPayload(Db,UserId,BoardId,Data,False,AllowPublicGuest,Ignored);end;
function PayloadCopyGuards(Db:TWLDb;const UserId,BoardId:string;Data:TJSONData;out Sql:string):Boolean;
begin Result:=InspectPayload(Db,UserId,BoardId,Data,True,False,Sql);end;
end.
