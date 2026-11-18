unit wlchhash;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses fpjson;

// Hash a list lifecycle record after dates have been rendered as UTC ISO strings.
function ListLifecycleHash(Row:TJSONObject):string;
function HistoryBoardKey(const Prefix,BoardId:string):string;
function ListReservationHash(Row:TJSONObject):string;
procedure ReservationHashes(const Document:string;out RowHash,PendingHash:string);

implementation
uses SysUtils,Classes,wlcrypt,wlcfjson,wlsjson;

const ProtectedKeys:array[0..15] of string=(
  'batchId','boardId','cardId','changeType','createdAt','entityId','entityType',
  'group','listId','newContent','previousContent','previousHash','restoredByUserId',
  'restoredFromId','swimlaneId','userId');

function JsonString(const Value:string):string;
var i:Integer;C:Char;
begin
  Result:='"';
  for i:=1 to Length(Value) do
  begin
    C:=Value[i];
    case C of
      '"','\': Result:=Result+'\'+C;
      #8: Result:=Result+'\b';
      #9: Result:=Result+'\t';
      #10: Result:=Result+'\n';
      #12: Result:=Result+'\f';
      #13: Result:=Result+'\r';
      #0..#7,#11,#14..#31: Result:=Result+'\u'+LowerCase(IntToHex(Ord(C),4));
      else Result:=Result+C;
    end;
  end;
  Result:=Result+'"';
end;

function LifecycleValue(Value:TJSONData;const Key:string):string;
var Keys:TStringList;I:Integer;Obj:TJSONObject;
begin
  if Value=nil then Exit('{"$undefined":true}');
  case Value.JSONType of
    jtNull,jtBoolean: Result:=Value.AsJSON;
    jtString:
      if (Key='createdAt') or (Key='deletedAt') then
        Result:='{"$date":'+JsonString(Value.AsString)+'}'
      else Result:=JsonString(Value.AsString);
    jtObject:
    begin
      Obj:=TJSONObject(Value);
      Keys:=TStringList.Create;
      try
        Keys.CaseSensitive:=True;Keys.Sorted:=True;
        for I:=0 to Obj.Count-1 do Keys.Add(Obj.Names[I]);
        Result:='{';
        for I:=0 to Keys.Count-1 do
        begin
          if I<>0 then Result:=Result+',';
          Result:=Result+JsonString(Keys[I])+':'+LifecycleValue(Obj.Find(Keys[I]),Keys[I]);
        end;
        Result:=Result+'}';
      finally Keys.Free;end;
    end;
    else raise Exception.Create('Unsupported list lifecycle value');
  end;
end;

function ListLifecycleHash(Row:TJSONObject):string;
var I:Integer;Body:string;
begin
  Body:='{';
  for I:=Low(ProtectedKeys) to High(ProtectedKeys) do
  begin
    if I<>Low(ProtectedKeys) then Body:=Body+',';
    Body:=Body+JsonString(ProtectedKeys[I])+':'+LifecycleValue(Row.Find(ProtectedKeys[I]),ProtectedKeys[I]);
  end;
  Result:=Sha256Hex(Body+'}');
end;

function ListReservationHash(Row:TJSONObject):string;
begin
  Result:=Sha256Hex(LifecycleValue(Row,''));
end;

function CompareJsonKeys(Keys:TStringList;Left,Right:Integer):Integer;
var A,B:UnicodeString;I:Integer;
begin
  A:=UTF8Decode(Keys[Left]);B:=UTF8Decode(Keys[Right]);
  for I:=1 to Length(A) do
  begin
    if I>Length(B) then Exit(1);
    if A[I]<>B[I] then Exit(Ord(A[I])-Ord(B[I]));
  end;
  Result:=Length(A)-Length(B);
end;

function ReservationValue(Value,Schema:TJSONData):string;forward;

function ReservationObject(Obj,Props:TJSONObject;ProtectedOnly:Boolean):string;
var Keys:TStringList;I:Integer;Key:string;
begin
  Keys:=TStringList.Create;
  try
    if ProtectedOnly then
      for Key in ProtectedKeys do Keys.Add(Key)
    else
    begin
      if Props<>nil then
        for I:=0 to Props.Count-1 do Keys.Add(Props.Names[I]);
      Keys.CustomSort(@CompareJsonKeys);
    end;
    Result:='{';
    for I:=0 to Keys.Count-1 do
    begin
      if I<>0 then Result:=Result+',';
      Key:=Keys[I];
      Result:=Result+JsonString(Key)+':'+ReservationValue(Obj.Find(Key),Props.Find(Key));
    end;
    Result:=Result+'}';
  finally Keys.Free;end;
end;

function ReservationValue(Value,Schema:TJSONData):string;
var Kind:string;Items,Date:TJSONData;Number:Double;I:Integer;
begin
  if Value=nil then Exit('{"$undefined":true}');
  Kind:=TJSONObject(Schema).Get('t','');
  case Kind of
    'null','bool':Result:=Value.AsJSON;
    'string':Result:=JsonString(Value.AsString);
    'date':
      begin
        Date:=JsonDate(Value.AsInt64);
        try
          if Date.JSONType<>jtString then raise Exception.Create('Invalid history reservation date');
          Result:='{"$date":'+JsonString(Date.AsString)+'}';
        finally Date.Free;end;
      end;
    'int','long','double':
      begin
        // Exact safe integers have the same decimal spelling in Pascal and JavaScript.
        if Value.JSONType<>jtNumber then raise Exception.Create('Invalid history reservation number');
        Number:=Value.AsFloat;
        if (Abs(Number)>9007199254740991.0) or (Number<>Trunc(Number)) then
          raise Exception.Create('Unsupported history reservation number');
        Result:=IntToStr(Trunc(Number));
      end;
    'object':
      Result:=ReservationObject(TJSONObject(Value),TJSONObject(TJSONObject(Schema).Objects['$s'].Find('p')),False);
    'array':
      begin
        Items:=TJSONObject(Schema).Arrays['i'];
        Result:='[';
        for I:=0 to Value.Count-1 do
        begin
          if I<>0 then Result:=Result+',';
          Result:=Result+ReservationValue(Value.Items[I],Items.Items[I]);
        end;
        Result:=Result+']';
      end;
    else raise Exception.Create('Unsupported history reservation value');
  end;
end;

procedure ReservationHashes(const Document:string;out RowHash,PendingHash:string);
var Row,Props:TJSONObject;
begin
  // Validate the complete FerretDB value and its corresponding BSON metadata.
  PlainDocument(Document);
  Row:=ExactObject(Document);
  try
    Props:=Row.Objects['$s'].Objects['p'];
    RowHash:=Sha256Hex(ReservationObject(Row,Props,True));
    PendingHash:=Sha256Hex(ReservationObject(Row,Props,False));
  finally Row.Free;end;
end;

function HistoryBoardKey(const Prefix,BoardId:string):string;
begin
  Result:=Sha256Hex('['+JsonString(Prefix)+','+JsonString(BoardId)+']');
end;

end.
