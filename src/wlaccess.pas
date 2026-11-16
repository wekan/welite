unit wlaccess;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes, wldb;
function BoardCanRead(Db: TWLDb; const UserId, BoardId: string): Boolean;
function BoardCanWrite(Db: TWLDb; const UserId, BoardId: string): Boolean;
function BoardSelectionAllowed(Db: TWLDb; const UserId, BoardId: string; Params: TStrings): Boolean;
function SafeReturnPath(const Value: string): string;
implementation
function BoardAccess(Db: TWLDb; const UserId, BoardId: string; WriteAccess: Boolean): Boolean;
var B, U, M: TWLRows;
begin
  Result:=False;
  B:=Db.Query('SELECT permission FROM boards WHERE id='+QuotedStr(BoardId)+' AND archived=0;');
  if Length(B)=0 then Exit;
  U:=Db.Query('SELECT isAdmin FROM users WHERE id='+QuotedStr(UserId)+' AND loginDisabled=0;');
  if Length(U)>0 then
  begin
    if U[0][0]='1' then Exit(True);
    M:=Db.Query('SELECT COALESCE(isReadOnly,0),COALESCE(isCommentOnly,0),'+
      'COALESCE(isReadAssignedOnly,0),COALESCE(isCommentAssignedOnly,0),'+
      'COALESCE(isNormalAssignedOnly,0),COALESCE(isWorker,0) FROM board_members WHERE boardId='+
      QuotedStr(BoardId)+' AND userId='+QuotedStr(UserId)+' AND isActive=1;');
    if Length(M)>0 then
    begin
      if not WriteAccess then
        Exit((M[0][2]='0') and (M[0][3]='0') and (M[0][4]='0'));
      // Board-wide moves are reserved for full editors. Assignment/comment-only roles
      // need their own narrower operations; never grant them unrestricted mutations.
      Exit((M[0][0]='0') and (M[0][1]='0') and (M[0][2]='0') and
        (M[0][3]='0') and (M[0][4]='0') and (M[0][5]='0'));
    end;
  end;
  Result:=not WriteAccess and (B[0][0]='public');
end;
function BoardCanRead(Db: TWLDb; const UserId, BoardId: string): Boolean;
begin Result:=BoardAccess(Db,UserId,BoardId,False); end;
function BoardCanWrite(Db: TWLDb; const UserId, BoardId: string): Boolean;
begin Result:=BoardAccess(Db,UserId,BoardId,True); end;
function BoardSelectionAllowed(Db: TWLDb; const UserId, BoardId: string; Params: TStrings): Boolean;
var i: Integer; TableName, Id: string; R: TWLRows;
begin
  Result:=False;
  if (Params=nil) or not BoardCanWrite(Db,UserId,BoardId) then Exit;
  for i:=0 to Params.Count-1 do
  begin
    case LowerCase(Params.Names[i]) of
      'sel_card': TableName:='cards';
      'sel_list': TableName:='lists';
      'sel_swimlane': TableName:='swimlanes';
    else Continue;
    end;
    Id:=Params.ValueFromIndex[i];
    R:=Db.Query('SELECT id FROM '+TableName+' WHERE id='+QuotedStr(Id)+
      ' AND boardId='+QuotedStr(BoardId)+' AND archived=0;');
    if Length(R)=0 then Exit;
  end;
  Result:=True;
end;
function SafeReturnPath(const Value: string): string;
var i: Integer;
begin
  Result:='/';
  if (Value='') or (Value[1]<>'/') or (Copy(Value,1,2)='//') or (Pos('\',Value)>0) then Exit;
  for i:=1 to Length(Value) do if Ord(Value[i])<32 then Exit;
  Result:=Value;
end;
end.
