unit wlpath;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses SysUtils,HTTPDefs,wlsjson;
const ApiPathKeys:array[0..18] of string=('boardId','cardId','listId','swimlaneId',
  'checklistId','commentId','customField','item','member','assignee','attachmentId','userId','dropdownItem','ruleId','intId','orgId','teamId','domain','targetId');
function DecodePathId(const Encoded:string;out Decoded:string):Boolean;
function DecodeApiPath(Request:TRequest):Boolean;
implementation
function HexDigit(Value:Char):Integer;
begin
  case Value of
    '0'..'9':Result:=Ord(Value)-Ord('0');
    'A'..'F':Result:=Ord(Value)-Ord('A')+10;
    'a'..'f':Result:=Ord(Value)-Ord('a')+10;
  else Result:=-1;
  end;
end;
function DecodePathId(const Encoded:string;out Decoded:string):Boolean;
var i,Count,A,B:Integer;Value:Char;Buffer:string;
begin
  Result:=False;Decoded:='';SetLength(Buffer,Length(Encoded));Count:=0;i:=1;
  while i<=Length(Encoded) do
  begin
    Value:=Encoded[i];
    if Value='%' then
    begin
      if i+2>Length(Encoded) then Exit;
      A:=HexDigit(Encoded[i+1]);B:=HexDigit(Encoded[i+2]);
      if (A<0) or (B<0) then Exit;
      Value:=Chr(A*16+B);Inc(i,2);
    end;
    // Path '+' is literal. Never apply form decoding or re-route decoded slashes.
    if (Ord(Value)<32) or (Ord(Value)=127) then Exit;
    Inc(Count);Buffer[Count]:=Value;Inc(i);
  end;
  SetLength(Buffer,Count);
  try CheckUtf8(Buffer);except Exit;end;
  Decoded:=Buffer;Result:=True;
end;
function DecodeApiPath(Request:TRequest):Boolean;
var Values:array[0..High(ApiPathKeys)] of string;i:Integer;
begin
  Result:=True;
  // Internal route state cannot be supplied through query fields or headers.
  if Request.RouteParams['_wl_path_decoded']='1' then Exit;
  // Stage every value before changing any parameter, so invalid input is atomic.
  for i:=0 to High(ApiPathKeys) do
    if not DecodePathId(Request.RouteParams[ApiPathKeys[i]],Values[i]) then Exit(False);
  for i:=0 to High(ApiPathKeys) do Request.RouteParams[ApiPathKeys[i]]:=Values[i];
  Request.RouteParams['_wl_path_decoded']:='1';
end;
end.
