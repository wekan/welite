unit wlcfscan;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,fpjson,wldb;
// Inspect encoded export payloads without changing their bytes or source data.
function ExportPayloadAllowed(Db:TWLDb;const UserId,BoardId:string;Data:TJSONData):Boolean;
function PayloadCopyGuards(Db:TWLDb;const UserId,BoardId:string;Data:TJSONData;out Sql:string):Boolean;
implementation
uses wlcfpol,wlsjson;
type
  TPayloadPolicy=class
    Db:TWLDb;
    UserId,Guards:string;
    WriteAccess,Collect:Boolean;
    Keys,Answers:TStringList;
    function Permitted(const BoardId,FieldId:string;Admin:Boolean):Boolean;
    function Visit(Data:TJSONData;const BoardId:string;Depth:Integer):Boolean;
    function FieldArray(Data:TJSONData;const BoardId:string;Depth:Integer):Boolean;
  end;
function TPayloadPolicy.Permitted(const BoardId,FieldId:string;Admin:Boolean):Boolean;
var Key,Sql:string;Index:Integer;Policy:TFieldPolicy;Rows:TWLRows;Tuple:TJSONArray;
begin
  Result:=False;if (BoardId='') or ((FieldId='') and not Admin) then Exit;
  Tuple:=TJSONArray.Create;try Tuple.Add(BoardId);Tuple.Add(FieldId);Tuple.Add(Admin);Key:=Tuple.AsJSON;finally Tuple.Free;end;
  Index:=Keys.IndexOf(Key);if Index>=0 then Exit(Answers[Index]='1');
  Policy:=TFieldPolicy.Create(Db,UserId,BoardId,'');
  try
    if Admin then Sql:=Policy.ScopeAdminExpression
    else if WriteAccess then Sql:=Policy.ScopeWriteExpression(FieldId) else Sql:=Policy.HistoryExpression(FieldId);
    Rows:=Db.Query('SELECT '+Sql+';');Result:=(Length(Rows)=1) and (Rows[0][0]='1');
    if Result and Collect then Guards:=Guards+'SELECT CASE WHEN '+Sql+' THEN 1 ELSE json(''Copied payload permission denied'') END; ';
  finally Policy.Free;end;
  Keys.Add(Key);if Result then Answers.Add('1') else Answers.Add('0');
end;
function TPayloadPolicy.FieldArray(Data:TJSONData;const BoardId:string;Depth:Integer):Boolean;
var i:Integer;Row:TJSONObject;Id,Value:TJSONData;
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
      Row:=TJSONObject(Data.Items[i]);Id:=Row.Find('_id');Value:=Row.Find('value');
      if Value<>nil then
      begin
        if (Id=nil) or (Id.JSONType<>jtString) then Exit;
        if not Permitted(BoardId,Id.AsString,False) and
          ((Value.JSONType<>jtNull) or (Row.Count>2)) then Exit;
      end;
    end;
    if not Visit(Data.Items[i],BoardId,Depth+1) then Exit;
  end;
  Result:=True;
end;
function TPayloadPolicy.Visit(Data:TJSONData;const BoardId:string;Depth:Integer):Boolean;
var Obj,Decoded:TJSONObject;Item,ScopeValue,FieldId,Marker:TJSONData;Scope,Name,Text:string;i:Integer;
begin
  Result:=False;if (Data=nil) or (Depth>256) then Exit;
  if Data is TJSONArray then
  begin
    for i:=0 to Data.Count-1 do if not Visit(Data.Items[i],BoardId,Depth+1) then Exit;
    Exit(True);
  end;
  if not (Data is TJSONObject) then Exit(True);
  Obj:=TJSONObject(Data);Scope:=BoardId;ScopeValue:=Obj.Find('boardId');
  if (ScopeValue<>nil) and (ScopeValue.JSONType<>jtNull) then
  begin
    if ScopeValue.JSONType<>jtString then Exit;
    if ScopeValue.AsString<>'' then Scope:=ScopeValue.AsString;
  end;
  FieldId:=Obj.Find('customFieldId');Marker:=Obj.Find('field');
  for i:=0 to Obj.Count-1 do
  begin
    Name:=Obj.Names[i];Item:=Obj.Items[i];
    if ((Name='integrityHash') or (Name='previousHash')) and (Item.JSONType<>jtNull) then
    begin if not Permitted(Scope,'',True) then Exit;end
    else if (Name='customFields') or (((Name='value') or (Name='oldValue') or (Name='newValue') or (Name='customFieldValue')) and (Marker<>nil) and (Marker.JSONType=jtString) and (Marker.AsString='customFields')) then
    begin if not FieldArray(Item,Scope,Depth+1) then Exit;Continue;end
    else if ((Name='value') or (Name='oldValue') or (Name='newValue') or (Name='customFieldValue')) and
      (FieldId<>nil) and (Item.JSONType<>jtNull) then
    begin
      if (FieldId.JSONType<>jtString) or not Permitted(Scope,FieldId.AsString,False) then Exit;
    end;
    if (Name='_wl_source') or (Copy(Name,Length(Name)-4,5)='_json') then
    begin
      if Item.JSONType=jtNull then Continue;
      if Item.JSONType<>jtString then Exit;
      Text:=Item.AsString;Decoded:=nil;
      try
        if Name='_wl_source' then Decoded:=ExactObject(PlainDocument(Text))
        else Decoded:=ExactObject(PlainDocument(TypedDocument('{"payload":'+Text+'}','','')));
        if Name='_wl_source' then
        begin if not Visit(Decoded,Scope,Depth+1) then Exit;end
        else if not Visit(Decoded.Find('payload'),Scope,Depth+1) then Exit;
      finally Decoded.Free;end;
    end
    else if not Visit(Item,Scope,Depth+1) then Exit;
  end;
  Result:=True;
end;
function InspectPayload(Db:TWLDb;const UserId,BoardId:string;Data:TJSONData;CopyAccess:Boolean;out Sql:string):Boolean;
var Policy:TPayloadPolicy;
begin
  Result:=False;Sql:='';Policy:=TPayloadPolicy.Create;
  Policy.Keys:=TStringList.Create;Policy.Keys.CaseSensitive:=True;Policy.Answers:=TStringList.Create;
  try
    Policy.Db:=Db;Policy.UserId:=UserId;Policy.WriteAccess:=CopyAccess;Policy.Collect:=CopyAccess;
    try Result:=Policy.Visit(Data,BoardId,0);if Result then Sql:=Policy.Guards;except Result:=False;end;
  finally Policy.Answers.Free;Policy.Keys.Free;Policy.Free;end;
end;
function ExportPayloadAllowed(Db:TWLDb;const UserId,BoardId:string;Data:TJSONData):Boolean;
var Ignored:string;
begin Result:=InspectPayload(Db,UserId,BoardId,Data,False,Ignored);end;
function PayloadCopyGuards(Db:TWLDb;const UserId,BoardId:string;Data:TJSONData;out Sql:string):Boolean;
begin Result:=InspectPayload(Db,UserId,BoardId,Data,True,Sql);end;
end.
