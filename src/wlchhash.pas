unit wlchhash;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses fpjson;

// Hash a list lifecycle record after dates have been rendered as UTC ISO strings.
function ListLifecycleHash(Row:TJSONObject):string;
function HistoryBoardKey(const Prefix,BoardId:string):string;

implementation
uses SysUtils,Classes,wlcrypt;

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
const ProtectedKeys:array[0..15] of string=(
  'batchId','boardId','cardId','changeType','createdAt','entityId','entityType',
  'group','listId','newContent','previousContent','previousHash','restoredByUserId',
  'restoredFromId','swimlaneId','userId');
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

function HistoryBoardKey(const Prefix,BoardId:string):string;
begin
  Result:=Sha256Hex('['+JsonString(Prefix)+','+JsonString(BoardId)+']');
end;

end.
