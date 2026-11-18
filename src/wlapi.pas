unit wlapi;

{
  WeKan-Lite — REST API (subset of public/api/wekan.yml), so the WeKan Python CLI api.py works
  against the FreePascal server unchanged.

  Auth (as api.py does it):
    POST /users/login   JSON {username,password,code?}     -> {"id","token","tokenExpires"}
    then every /api/... request sends  Authorization: Bearer <token>

  Tokens are persisted in schema.sql login_tokens (hashedToken = TokenHash(tenantDb,token)), the same
  table the no-cookie web sessions use. Responses use WeKan's "_id"/"title" JSON shapes.

  Implemented endpoints (the common api.py commands):
    POST /users/login
    GET  /api/user                                   current user
    GET  /api/users                                  all users
    GET  /api/boards                                 public boards
    GET  /api/users/:userId/boards                   a user's boards
    GET  /api/boards/:boardId                        board
    GET  /api/boards/:boardId/swimlanes              swimlanes
    GET  /api/boards/:boardId/lists                  lists
    POST /api/boards/:boardId/lists                  create list           -> {"_id"}
    GET  /api/boards/:boardId/lists/:listId          list
    POST /api/boards/:boardId/lists/:listId/cards    add card              -> {"_id"}
    GET  /api/boards/:boardId/lists/:listId/cards/:cardId   card
    GET  /api/boards/:boardId/swimlanes/:swimlaneId/cards   cards on a swimlane

  Password/OTP proofs and durable attempt limits are shared with the web sign-in.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, Classes, HTTPDefs, fpjson, jsonparser, DateUtils, base64,
  wldb, wltenant, wlauth, wlpasswd, wlaccess, wlattemp;

procedure ApiLogin(aRequest: TRequest; aResponse: TResponse);
procedure ApiUser(aRequest: TRequest; aResponse: TResponse);
procedure ApiUsers(aRequest: TRequest; aResponse: TResponse);
procedure ApiPublicBoards(aRequest: TRequest; aResponse: TResponse);
procedure ApiUserBoards(aRequest: TRequest; aResponse: TResponse);
procedure ApiBoard(aRequest: TRequest; aResponse: TResponse);
procedure ApiBoardTitle(aRequest: TRequest; aResponse: TResponse);    // PUT board title
procedure ApiBoardCopy(aRequest: TRequest; aResponse: TResponse);     // POST copy board
procedure ApiSwimlanes(aRequest: TRequest; aResponse: TResponse);
procedure ApiCreateLabel(aRequest: TRequest; aResponse: TResponse);    // PUT board label
procedure ApiCustomFields(aRequest: TRequest; aResponse: TResponse);   // GET list / POST create
procedure ApiCustomField(aRequest: TRequest; aResponse: TResponse);    // GET one
procedure ApiUpdateCustomField(aRequest:TRequest;aResponse:TResponse);
procedure ApiDeleteCustomField(aRequest:TRequest;aResponse:TResponse);
procedure ApiAppendDropdownItems(aRequest:TRequest;aResponse:TResponse);
procedure ApiDropdownItem(aRequest:TRequest;aResponse:TResponse);
procedure ApiCardCustomField(aRequest: TRequest; aResponse: TResponse);// POST set card value
procedure ApiLists(aRequest: TRequest; aResponse: TResponse);          // GET list / POST create
procedure ApiList(aRequest: TRequest; aResponse: TResponse);
procedure ApiCards(aRequest: TRequest; aResponse: TResponse);          // POST add card
procedure ApiCard(aRequest: TRequest; aResponse: TResponse);
procedure ApiCardEdit(aRequest: TRequest; aResponse: TResponse);      // PUT card (title/desc/color/labels)
procedure ApiListCards(aRequest: TRequest; aResponse: TResponse);     // GET cards in a list
procedure ApiListCardsCount(aRequest: TRequest; aResponse: TResponse);
procedure ApiBoardCardsCount(aRequest: TRequest; aResponse: TResponse);
procedure ApiSwimlaneCards(aRequest: TRequest; aResponse: TResponse);
procedure ApiCardChecklists(aRequest: TRequest; aResponse: TResponse); // GET list / POST create
procedure ApiChecklist(aRequest: TRequest; aResponse: TResponse);      // GET one + items
procedure ApiChecklistItems(aRequest: TRequest; aResponse: TResponse); // POST add item
procedure ApiChecklistItem(aRequest: TRequest; aResponse: TResponse);  // GET/PUT(toggle)/DELETE item
procedure ApiCardComments(aRequest: TRequest; aResponse: TResponse);   // GET list / POST add
procedure ApiCardComment(aRequest: TRequest; aResponse: TResponse);    // GET one / DELETE one
procedure ApiAttachmentUpload(aRequest: TRequest; aResponse: TResponse);   // POST /api/attachment/upload
procedure ApiAttachmentDownload(aRequest: TRequest; aResponse: TResponse); // GET  /api/attachment/download/:id
procedure ApiAttachmentInfo(aRequest: TRequest; aResponse: TResponse);     // GET  /api/attachment/info/:id
procedure ApiAttachmentDelete(aRequest: TRequest; aResponse: TResponse);   // DELETE /api/attachment/delete/:id
procedure ApiBoardAttachments(aRequest: TRequest; aResponse: TResponse);   // GET  /api/boards/:boardId/attachments
procedure ApiCardAttachmentsList(aRequest: TRequest; aResponse: TResponse);// GET /api/attachment/list/:b/:s/:l/:c
procedure ApiCardMember(aRequest: TRequest; aResponse: TResponse);     // POST/DELETE card member
procedure ApiCardAssignee(aRequest: TRequest; aResponse: TResponse);   // POST/DELETE card assignee
procedure ApiCardArchive(aRequest: TRequest; aResponse: TResponse);    // POST archive/unarchive
procedure ApiCardDelete(aRequest: TRequest; aResponse: TResponse);     // DELETE card
procedure ApiListDelete(aRequest: TRequest; aResponse: TResponse);     // DELETE list (+ its cards)
procedure ApiBoardDelete(aRequest: TRequest; aResponse: TResponse);    // DELETE board (cascade)
procedure ApiSwimlaneDelete(aRequest: TRequest; aResponse: TResponse); // DELETE swimlane (+ its cards)

implementation
uses wlstore,wlsjson,Math,wlcfjson,wlcfpol,wlpath,wlcfspec,wlselscp;

// 17-char Mongo-style id (schema.sql convention)
function NewId: string;
const A = '23456789ABCDEFGHJKLMNPQRSTWXYZabcdefghijkmnopqrstuvwxyz';
var i: Integer;
begin
  SetLength(Result, 17);
  for i := 1 to 17 do Result[i] := A[Random(Length(A)) + 1];
end;

function NowIso: string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(Now));
end;

procedure SendJson(aResponse: TResponse; const Json: string; Code: Integer = 200);
begin
  aResponse.Code := Code;
  aResponse.ContentType := 'application/json; charset=utf-8';
  aResponse.Content := Json;
  aResponse.ContentLength := Length(aResponse.Content);
  aResponse.SendContent;
end;

procedure SendError(aResponse: TResponse; Code: Integer; const Reason: string);
begin
  SendJson(aResponse, Format('{"error":%d,"reason":%s}', [Code, AnsiQuotedStr(Reason, '"')]), Code);
end;

function ApiBodyValid(Request:TRequest):Boolean;
var D:TJSONData;
begin
  Result:=True;
  if (Request.Method='GET') or (Request.Content='') or
    (Pos('application/json',LowerCase(Request.ContentType))<>1) then Exit;
  D:=nil;
  try
    try D:=GetJSON(Request.Content); Result:=D is TJSONObject; except Result:=False; end;
  finally D.Free; end;
end;

// Resolve the tenant for an API request, or send a JSON error. Static, no web session needed.
function ApiTenant(aRequest: TRequest; aResponse: TResponse; out T: TWLTenant): Boolean;
begin
  if not DecodeApiPath(aRequest) then
  begin Result:=False;SendError(aResponse,400,'Invalid encoded route identifier');Exit;end;
  Result := ResolveTenant(aRequest, T) and TenantOpen(T);
  if not Result then SendError(aResponse,404,'Unknown domain')
  else if not ApiBodyValid(aRequest) then
  begin Result:=False; SendError(aResponse,400,'Expected a valid JSON object'); end;
end;

// Bearer token -> userId via login_tokens; sends 401 JSON if missing/invalid.
function ApiAuth(const T: TWLTenant; aRequest: TRequest; aResponse: TResponse;
  out UserId: string): Boolean;
var
  Hdr,Token:string;
begin
  Result := False; UserId := '';
  Hdr := aRequest.Authorization;
  if Hdr = '' then Hdr := aRequest.CustomHeaders.Values['Authorization'];
  if Pos('Bearer ', Hdr) = 1 then Token := Trim(Copy(Hdr, 8, Length(Hdr)))
  else Token := Trim(aRequest.QueryFields.Values['token']);   // ?token= fallback
  if Token = '' then begin SendError(aResponse, 401, 'No token'); Exit; end;

  Result:=ValidateLoginToken(T.Db,aRequest,Token,UserId);
  if not Result then SendError(aResponse,401,'Invalid token');
end;

function IsSiteAdmin(Db: TWLDb; const UserId: string): Boolean;
var R: TWLRows;
begin
  R := Db.Query(Format('SELECT isAdmin FROM users WHERE id=%s AND COALESCE(loginDisabled,0)=0 LIMIT 1;', [QuotedStr(UserId)]));
  Result := (Length(R) > 0) and (Length(R[0]) > 0) and (R[0][0] = '1');
end;

// Authorize the user for a board: site admin → always; active member → yes (write blocked if
// read-only); public board → read only. Sends 403 and returns False otherwise.
function ApiAuthBoard(const T: TWLTenant; aResponse: TResponse;
  const UserId, BoardId: string; NeedWrite: Boolean): Boolean;
begin
  if NeedWrite then Result:=BoardCanWrite(T.Db,UserId,BoardId)
  else Result:=BoardCanRead(T.Db,UserId,BoardId);
  if not Result then SendError(aResponse,403,'Board access forbidden');
end;

// Common guard for board-scoped endpoints: boardId from the route, write = non-GET.
// Check the whole resource chain, even for site administrators: permission on board A
// never makes a card/list/checklist from board B a child of A.
function ApiChildrenBelong(Db:TWLDb; const BoardId, LaneId, ListId, CardId,
  ChecklistId, ItemId, CommentId, CustomFieldId:string):Boolean;
  function Exists(const Sql:string):Boolean;
  begin Result:=Length(Db.Query(Sql))>0; end;
var Scope:string;
begin
  Result:=False;
  if (LaneId<>'') and not Exists('SELECT id FROM swimlanes WHERE id='+QuotedStr(LaneId)+
    ' AND boardId='+QuotedStr(BoardId)+';') then Exit;
  Scope:='';
  if LaneId<>'' then Scope:=' AND (swimlaneId='''' OR swimlaneId='+QuotedStr(LaneId)+')';
  if (ListId<>'') and not Exists('SELECT id FROM lists WHERE id='+QuotedStr(ListId)+
    ' AND boardId='+QuotedStr(BoardId)+Scope+';') then Exit;
  Scope:='';
  if ListId<>'' then Scope:=Scope+' AND listId='+QuotedStr(ListId);
  if LaneId<>'' then Scope:=Scope+' AND swimlaneId='+QuotedStr(LaneId);
  if (CardId<>'') and not Exists('SELECT id FROM cards WHERE id='+QuotedStr(CardId)+
    ' AND boardId='+QuotedStr(BoardId)+Scope+';') then Exit;
  if (ChecklistId<>'') and not Exists('SELECT id FROM checklists WHERE id='+QuotedStr(ChecklistId)+
    ' AND cardId='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+';') then Exit;
  if (ItemId<>'') and not Exists('SELECT id FROM checklist_items WHERE id='+QuotedStr(ItemId)+
    ' AND checklistId='+QuotedStr(ChecklistId)+' AND cardId='+QuotedStr(CardId)+
    ' AND boardId='+QuotedStr(BoardId)+';') then Exit;
  if (CommentId<>'') and not Exists('SELECT id FROM card_comments WHERE id='+QuotedStr(CommentId)+
    ' AND cardId='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+';') then Exit;
  if (CustomFieldId<>'') and not Exists('SELECT customFieldId FROM custom_field_boards WHERE customFieldId='+
    QuotedStr(CustomFieldId)+' AND boardId='+QuotedStr(BoardId)+';') then Exit;
  Result:=True;
end;

function ApiBoardGuard(const T: TWLTenant; aRequest: TRequest; aResponse: TResponse;
  const UserId: string; const ScopeErrorJson: string = ''): Boolean;
begin
  Result := ApiAuthBoard(T, aResponse, UserId, aRequest.RouteParams['boardId'],
    aRequest.Method <> 'GET');
  if not Result then Exit;
  Result:=ApiChildrenBelong(T.Db,aRequest.RouteParams['boardId'],aRequest.RouteParams['swimlaneId'],
    aRequest.RouteParams['listId'],aRequest.RouteParams['cardId'],aRequest.RouteParams['checklistId'],
    aRequest.RouteParams['item'],aRequest.RouteParams['commentId'],aRequest.RouteParams['customField']);
  if not Result then
    if ScopeErrorJson<>'' then SendJson(aResponse,ScopeErrorJson,404)
    else SendError(aResponse,404,'Resource does not belong to this board or parent');
end;

// read a form OR json field from the request body
function BodyField(aRequest: TRequest; const Name: string): string;
var D: TJSONData;
begin
  Result := aRequest.ContentFields.Values[Name];
  if Result <> '' then Exit;
  if aRequest.Content<>'' then
    try
      D := GetJSON(aRequest.Content);
      try
        if D is TJSONObject then Result := TJSONObject(D).Get(Name, '');
      finally D.Free; end;
    except end;
end;

function BodyHasField(Request:TRequest; const Name:string):Boolean;
var D:TJSONData;
begin
  Result:=Request.ContentFields.IndexOfName(Name)>=0;
  if Result or (Request.Content='') then Exit;
  D:=nil;
  try
    try D:=GetJSON(Request.Content); Result:=(D is TJSONObject) and (TJSONObject(D).Find(Name)<>nil); except Result:=False; end;
  finally D.Free; end;
end;
function EnabledBoardMember(Db:TWLDb; const BoardId,TargetId:string):Boolean;
begin
  Result:=Length(Db.Query('SELECT u.id FROM users u JOIN board_members m ON m.userId=u.id '+
    'WHERE u.id='+QuotedStr(TargetId)+' AND COALESCE(u.loginDisabled,0)=0 AND m.boardId='+QuotedStr(BoardId)+
    ' AND m.isActive=1;'))>0;
end;
function ValidAuthor(Db:TWLDb; const BoardId,Actor,Author:string):Boolean;
begin
  Result:=False;
  if Length(Db.Query('SELECT id FROM users WHERE id='+QuotedStr(Author)+' AND COALESCE(loginDisabled,0)=0;'))=0 then Exit;
  if Actor=Author then Exit(True);
  Result:=IsSiteAdmin(Db,Actor) and EnabledBoardMember(Db,BoardId,Author);
end;
function ReadBodyIds(Request:TRequest; const Name:string; Ids:TStrings):Boolean;
var D,V:TJSONData; A:TJSONArray; i:Integer; Text,Id:string; Parts:TStringArray;
begin
  Result:=False; D:=nil; Text:='';
  try
    try
      if Request.ContentFields.IndexOfName(Name)>=0 then Text:=Request.ContentFields.Values[Name]
      else
      begin
        D:=GetJSON(Request.Content);
        if not (D is TJSONObject) then Exit;
        V:=TJSONObject(D).Find(Name); if V=nil then Exit;
        if V is TJSONArray then
        begin
          A:=TJSONArray(V);
          for i:=0 to A.Count-1 do
          begin
            if A.Items[i].JSONType<>jtString then Exit;
            Id:=Trim(A.Items[i].AsString); if Id='' then Exit;
            if Ids.IndexOf(Id)<0 then Ids.Add(Id);
          end;
          Exit(True);
        end;
        if V.JSONType<>jtString then Exit;
        Text:=V.AsString;
      end;
      if Trim(Text)='' then Exit(True);
      Parts:=Text.Split([',']);
      for i:=0 to High(Parts) do
      begin
        Id:=Trim(Parts[i]); if Id='' then Exit;
        if Ids.IndexOf(Id)<0 then Ids.Add(Id);
      end;
      Result:=True;
    except Result:=False; end;
  finally D.Free; end;
end;
// Build relation changes only after validating all identifiers. The caller executes these
// changes with the card write in one transaction, so invalid data cannot partially edit it.
function CardRelationSql(const T:TWLTenant; Request:TRequest; Response:TResponse;
  const BoardId,CardId:string; out Sql:string):Boolean;
const Fields:array[0..2] of string=('labelIds','members','assignees');
  Tables:array[0..2] of string=('card_labels','card_members','card_assignees');
var Ids:TStringList; i,j:Integer; Column:string;
begin
  Result:=False; Sql:=''; Ids:=TStringList.Create; Ids.CaseSensitive:=True;
  try
    for i:=0 to High(Fields) do if BodyHasField(Request,Fields[i]) then
    begin
      Ids.Clear;
      if not ReadBodyIds(Request,Fields[i],Ids) then
      begin SendError(Response,400,'Expected an ID array or comma-separated string'); Exit; end;
      if i=0 then Column:='labelId' else Column:='userId';
      for j:=0 to Ids.Count-1 do
        if ((i=0) and (Length(T.Db.Query('SELECT id FROM board_labels WHERE boardId='+QuotedStr(BoardId)+
          ' AND id='+QuotedStr(Ids[j])+';'))=0)) or
          ((i>0) and not EnabledBoardMember(T.Db,BoardId,Ids[j])) then
        begin SendError(Response,400,'ID does not belong to an enabled board member or board label'); Exit; end;
      Sql:=Sql+'DELETE FROM '+Tables[i]+' WHERE cardId='+QuotedStr(CardId)+'; ';
      for j:=0 to Ids.Count-1 do Sql:=Sql+'INSERT INTO '+Tables[i]+'(cardId,'+Column+') VALUES('+
        QuotedStr(CardId)+','+QuotedStr(Ids[j])+'); ';
    end;
    Result:=True;
  finally Ids.Free; end;
end;

// ---- rows -> JSON array of {_id,title} ---------------------------------------------------
function RowsAsIdTitle(const R: TWLRows): string;
var A: TJSONArray; O: TJSONObject; i: Integer;
begin
  A := TJSONArray.Create;
  try
    for i := 0 to High(R) do
      if Length(R[i]) >= 2 then
      begin
        O := TJSONObject.Create;
        O.Add('_id', R[i][0]); O.Add('title', R[i][1]);
        A.Add(O);
      end;
    Result := A.AsJSON;
  finally A.Free; end;
end;

// ================================ endpoints ===============================================

procedure ApiLogin(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  Username, Password, Token:string;
  Proof:TWLLoginProof;
  O:TJSONObject;Ttl:Int64;Expires:TWLRows;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  Username:=Trim(BodyField(aRequest,'username'));
  if Username='' then Username:=Trim(BodyField(aRequest,'email'));
  Password:=BodyField(aRequest,'password');
  if not ReserveLoginAttempt(T.Db,Username,aRequest.RemoteAddress,DateTimeToUnix(Now,False)) then
  begin
    aResponse.SetCustomHeader('Retry-After','300');
    SendError(aResponse,429,'Too many login attempts. Try again later.');Exit;
  end;
  Proof:=nil;
  if not AuthenticateAccount(T.Db,Username,Password,BodyField(aRequest,'code'),Proof) then
  begin SendError(aResponse,401,'Incorrect credentials or one-time code');Exit;end;
  try
    Token:=NewAuthToken;Ttl:=ApiTokenLifetime(T.Db);
    if not IssueAccountToken(T.Db,Proof,Token,'api',Ttl) then
    begin SendError(aResponse,500,'Could not create login token');Exit;end;
    Expires:=T.Db.Query('SELECT expiresAt FROM login_tokens WHERE hashedToken='+QuotedStr(TokenHash(T.Db,Token))+';');
    if (Length(Expires)<>1) or (Expires[0][0]='') then begin SendError(aResponse,500,'Could not read token expiry');Exit;end;
    O:=TJSONObject.Create;
    try
      O.Add('id',Proof.UserId);O.Add('token',Token);
      O.Add('tokenExpires',Expires[0][0]);
      SendJson(aResponse,O.AsJSON);
    finally O.Free;end;
  finally Proof.Free;end;
end;

procedure ApiUser(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  R := T.Db.Query(Format('SELECT id,username FROM users WHERE id=%s LIMIT 1;', [QuotedStr(UserId)]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'User not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('username', R[0][1]);
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

procedure ApiUsers(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; R: TWLRows; A: TJSONArray; O: TJSONObject; i: Integer;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not IsSiteAdmin(T.Db, UserId) then begin SendError(aResponse, 403, 'Admin only'); Exit; end;
  R := T.Db.Query('SELECT id,username FROM users ORDER BY username;');
  A := TJSONArray.Create;
  try
    for i := 0 to High(R) do
      if Length(R[i]) >= 2 then
      begin
        O := TJSONObject.Create;
        O.Add('_id', R[i][0]); O.Add('username', R[i][1]);
        A.Add(O);
      end;
    SendJson(aResponse, A.AsJSON);
  finally A.Free; end;
end;

procedure ApiPublicBoards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(
    'SELECT id,title FROM boards WHERE permission=''public'' AND archived=0 ORDER BY title;')));
end;

procedure ApiUserBoards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if (UserId <> aRequest.RouteParams['userId']) and not IsSiteAdmin(T.Db, UserId) then begin SendError(aResponse, 403, 'Forbidden'); Exit; end;
  // boards the path's user is a member of
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT b.id,b.title FROM boards b JOIN board_members m ON m.boardId=b.id ' +
    'WHERE m.userId=%s AND b.archived=0 ORDER BY b.title;',
    [QuotedStr(aRequest.RouteParams['userId'])]))));
end;

procedure ApiBoard(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  R := T.Db.Query(Format('SELECT id,title,slug,permission,color FROM boards WHERE id=%s LIMIT 1;',
    [QuotedStr(aRequest.RouteParams['boardId'])]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'Board not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('title', R[0][1]); O.Add('slug', R[0][2]);
    O.Add('permission', R[0][3]); O.Add('color', R[0][4]);
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

procedure ApiBoardTitle(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, Title: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  Title := BodyField(aRequest, 'title');
  T.Db.Exec(Format('UPDATE boards SET title=%s, modifiedAt=%s WHERE id=%s;',
    [QuotedStr(Title), QuotedStr(NowIso), QuotedStr(BoardId)]));
  SendJson(aResponse, Format('{"_id":%s,"title":%s}',
    [AnsiQuotedStr(BoardId, '"'), AnsiQuotedStr(Title, '"')]));
end;

function Slugify(const S: string): string;
var i: Integer; c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if c in ['A'..'Z'] then c := Chr(Ord(c) + 32);
    if c in ['a'..'z', '0'..'9'] then Result := Result + c
    else if (Result <> '') and (Result[Length(Result)] <> '-') then Result := Result + '-';
  end;
  if Result = '' then Result := 'board';
end;

// POST copy board — structural deep copy: board + members + swimlanes + lists + cards, with
// remapped ids. (Labels/checklists/comments copy is TODO.)
procedure ApiBoardCopy(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; UserId, SrcId, Title, NewBoard: string;
  B, Rows: TWLRows;
  swMap, listMap: TStringList;
  i: Integer;
  newSw, newList, newCard: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiAuthBoard(T, aResponse, UserId, aRequest.RouteParams['boardId'], False) then Exit;
  SrcId := aRequest.RouteParams['boardId'];
  Title := BodyField(aRequest, 'title');

  B := T.Db.Query(Format('SELECT title,permission,type,color FROM boards WHERE id=%s LIMIT 1;',
    [QuotedStr(SrcId)]));
  if Length(B) = 0 then begin SendError(aResponse, 404, 'Board not found'); Exit; end;
  if Title = '' then Title := B[0][0] + ' Copy';
  NewBoard := NewId;
  T.Db.Exec(Format(
    'INSERT INTO boards(id,title,slug,permission,type,color,createdAt,modifiedAt) ' +
    'VALUES(%s,%s,%s,%s,%s,%s,%s,%s);',
    [QuotedStr(NewBoard), QuotedStr(Title), QuotedStr(Slugify(Title)),
     QuotedStr(B[0][1]), QuotedStr(B[0][2]), QuotedStr(B[0][3]),
     QuotedStr(NowIso), QuotedStr(NowIso)]));

  // members
  Rows := T.Db.Query(Format('SELECT userId,isAdmin FROM board_members WHERE boardId=%s;', [QuotedStr(SrcId)]));
  for i := 0 to High(Rows) do
    if Length(Rows[i]) >= 2 then
      T.Db.Exec(Format('INSERT INTO board_members(boardId,userId,isAdmin) VALUES(%s,%s,%s);',
        [QuotedStr(NewBoard), QuotedStr(Rows[i][0]), QuotedStr(Rows[i][1])]));

  swMap := TStringList.Create; swMap.CaseSensitive := True;
  listMap := TStringList.Create; listMap.CaseSensitive := True;
  try
    // swimlanes
    Rows := T.Db.Query(Format('SELECT id,title,sort FROM swimlanes WHERE boardId=%s;', [QuotedStr(SrcId)]));
    for i := 0 to High(Rows) do
      if Length(Rows[i]) >= 3 then
      begin
        newSw := NewId; swMap.Values[Rows[i][0]] := newSw;
        T.Db.Exec(Format('INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES(%s,%s,%s,%s,%s);',
          [QuotedStr(newSw), QuotedStr(NewBoard), QuotedStr(Rows[i][1]), QuotedStr(Rows[i][2]), QuotedStr(NowIso)]));
      end;
    // lists
    Rows := T.Db.Query(Format('SELECT id,title,sort,swimlaneId FROM lists WHERE boardId=%s;', [QuotedStr(SrcId)]));
    for i := 0 to High(Rows) do
      if Length(Rows[i]) >= 4 then
      begin
        newList := NewId; listMap.Values[Rows[i][0]] := newList;
        T.Db.Exec(Format('INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES(%s,%s,%s,%s,%s,%s);',
          [QuotedStr(newList), QuotedStr(NewBoard), QuotedStr(swMap.Values[Rows[i][3]]),
           QuotedStr(Rows[i][1]), QuotedStr(Rows[i][2]), QuotedStr(NowIso)]));
      end;
    // cards
    Rows := T.Db.Query(Format(
      'SELECT id,title,description,listId,swimlaneId,userId,color,sort FROM cards WHERE boardId=%s;',
      [QuotedStr(SrcId)]));
    for i := 0 to High(Rows) do
      if Length(Rows[i]) >= 8 then
      begin
        newCard := NewId;
        T.Db.Exec(Format(
          'INSERT INTO cards(id,boardId,listId,swimlaneId,title,description,userId,color,sort,' +
          'dateLastActivity,createdAt,modifiedAt) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);',
          [QuotedStr(newCard), QuotedStr(NewBoard),
           QuotedStr(listMap.Values[Rows[i][3]]), QuotedStr(swMap.Values[Rows[i][4]]),
           QuotedStr(Rows[i][1]), QuotedStr(Rows[i][2]), QuotedStr(Rows[i][5]),
           QuotedStr(Rows[i][6]), QuotedStr(Rows[i][7]),
           QuotedStr(NowIso), QuotedStr(NowIso), QuotedStr(NowIso)]));
      end;
  finally
    swMap.Free; listMap.Free;
  end;
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(NewBoard, '"')]));
end;

procedure ApiSwimlanes(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, Title, Id: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  if aRequest.Method = 'POST' then
  begin
    Title := BodyField(aRequest, 'title');
    if Title = '' then Title := 'Default';
    Id := NewId;
    T.Db.Exec(Format('INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES(%s,%s,%s,0,%s);',
      [QuotedStr(Id), QuotedStr(BoardId), QuotedStr(Title), QuotedStr(NowIso)]));
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
    Exit;
  end;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT id,title FROM swimlanes WHERE boardId=%s AND archived=0 ORDER BY sort;',
    [QuotedStr(BoardId)]))));
end;

// read label.<key> from a JSON body {"label":{...}}, falling back to a flat field
function LabelField(aRequest: TRequest; const Key: string): string;
var D: TJSONData; Lbl: TJSONData;
begin
  Result := BodyField(aRequest, Key);
  if Result <> '' then Exit;
  if (aRequest.Content <> '') and (aRequest.Content[1] = '{') then
    try
      D := GetJSON(aRequest.Content);
      try
        if D is TJSONObject then
        begin
          Lbl := TJSONObject(D).Find('label');
          if Lbl is TJSONObject then Result := TJSONObject(Lbl).Get(Key, '');
        end;
      finally D.Free; end;
    except end;
end;

// PUT board label — create a board_labels row, return its id.
procedure ApiCreateLabel(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; UserId, BoardId, Color, Name, Id: string; i: Integer;
const A = '23456789abcdefghjkmnpqrstwxyz';
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  Color := LabelField(aRequest, 'color');
  Name  := LabelField(aRequest, 'name');
  if Color = '' then Color := 'green';
  SetLength(Id, 6);                              // 6-char label id, unique within board
  for i := 1 to 6 do Id[i] := A[Random(Length(A)) + 1];
  T.Db.Exec(Format('INSERT INTO board_labels(boardId,id,name,color) VALUES(%s,%s,%s,%s);',
    [QuotedStr(BoardId), QuotedStr(Id), QuotedStr(Name), QuotedStr(Color)]));
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
end;

function BoolInt(const S: string): Integer;
begin
  if (LowerCase(Trim(S)) = 'true') or (Trim(S) = '1') then Result := 1 else Result := 0;
end;

type TDefinitionFlags=array[0..5] of Integer;
const DefinitionFlagNames:array[0..5] of string=('showOnCard','automaticallyOnCard',
  'showLabelOnMiniCard','showSumAtTopOfList','readOnly','adminOnly');
function ValidDefinitionType(const Kind:string):Boolean;
begin
  case Kind of 'text','number','currency','date','checkbox','dropdown','dropdownMultiSelect','stringtemplate': Result:=True;
  else Result:=False;end;
end;
function DefinitionFlag(Data:TJSONData;out Number:Integer):Boolean;
  var Text:string;
  begin
    Number:=0;if Data=nil then Exit(True);
    if Data.JSONType=jtBoolean then begin Number:=Ord(Data.AsBoolean);Exit(True);end;
    if Data.JSONType=jtString then Text:=LowerCase(Trim(Data.AsString))
    else if Data.JSONType=jtNumber then Text:=Data.AsJSON else Exit(False);
    Result:=True;
    if (Text='true') or (Text='1') then Number:=1
    else if (Text<>'false') and (Text<>'0') and (Text<>'') then Result:=False;
  end;
function DefinitionInput(Request:TRequest;out Name,Kind:string;out Flags:TDefinitionFlags;out Settings:TJSONObject):Boolean;
var Doc:TJSONObject;Value,Legacy:TJSONData;i,Other:Integer;Key:string;
begin
  Result:=False;Name:='';Kind:='';Doc:=nil;Settings:=nil;
  try
    try
      if Pos('application/json',LowerCase(Request.ContentType))=1 then Doc:=ExactObject(Request.Content)
      else begin
        Doc:=TJSONObject.Create;
        for i:=0 to Request.ContentFields.Count-1 do
        begin
          Key:=LowerCase(Request.ContentFields.Names[i]);
          if (Key='') or (Doc.Find(Key)<>nil) then Exit;
          Doc.Add(Key,Request.ContentFields.ValueFromIndex[i]);
        end;
      end;
      Value:=Doc.Find('name');if (Value=nil) or (Value.JSONType<>jtString) then Exit;
      Name:=Value.AsString;if (Trim(Name)='') or (Pos(#0,Name)>0) then Exit;CheckUtf8(Name);
      Kind:='text';Value:=Doc.Find('type');
      if Value<>nil then begin if Value.JSONType<>jtString then Exit;Kind:=Value.AsString;end;
      if Kind='' then Kind:='text';
      if not ValidDefinitionType(Kind) then Exit;
      if not SettingsInput(Doc.Find('settings'),Settings) then Exit;
      for i:=0 to High(Flags) do
      begin
        Value:=Doc.Find(DefinitionFlagNames[i]);Legacy:=Doc.Find(LowerCase(DefinitionFlagNames[i]));
        if Value=nil then Value:=Legacy;
        if not DefinitionFlag(Value,Flags[i]) then Exit;
        if (Value<>Legacy) and (Legacy<>nil) then
        begin if not DefinitionFlag(Legacy,Other) or (Other<>Flags[i]) then Exit;end;
      end;
      Result:=True;
    except Result:=False;end;
  finally if not Result then FreeAndNil(Settings);Doc.Free;end;
end;

// GET board custom fields / POST create a custom field
procedure ApiCustomFields(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, Id, Name, Typ,Stamp,Sql: string;Flags:TDefinitionFlags;Reply,Data,Settings:TJSONObject;Rows:TWLRows;Items:TJSONArray;Index:Integer;Policy:TFieldPolicy;GuardSql,DropdownSql,DropdownGuards:string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  if aRequest.Method = 'POST' then
  begin
    if not DefinitionInput(aRequest,Name,Typ,Flags,Settings) then
    begin SendError(aResponse,400,'Invalid custom-field name, type, options or unsupported settings');Exit;end;
    Policy:=nil;
    try
      try
        Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
        Rows:=T.Db.Query('SELECT '+Policy.DefinitionExpression('',Flags[5]=1)+';');
        if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
        begin SendError(aResponse,403,'Custom-field creation forbidden');Exit;end;
      except SendError(aResponse,403,'Custom-field creation forbidden');Exit;end;
      Id:=NewId;Stamp:=NowIso;
      try DropdownSql:=DropdownScript(T.Db,Id,Settings,DropdownGuards);
      except SendError(aResponse,500,'Could not prepare dropdown settings');Exit;end;
      GuardSql:='SELECT CASE WHEN '+Policy.DefinitionExpression('',Flags[5]=1)+' THEN 1 ELSE json(''Field creation forbidden'') END; ';
      Sql:='BEGIN IMMEDIATE; '+DropdownGuards+GuardSql+Format(
        'INSERT INTO custom_fields(id,name,type,showOnCard,automaticallyOnCard,'+
        'showLabelOnMiniCard,showSumAtTopOfList,readOnly,adminOnly,createdAt,modifiedAt,currencyCode,stringtemplateFormat,stringtemplateSeparator,settings_json) VALUES(%s,%s,%s,%d,%d,%d,%d,%d,%d,%s,%s,%s,%s,%s,%s);',
        [QuotedStr(Id),QuotedStr(Name),QuotedStr(Typ),Flags[0],Flags[1],Flags[2],Flags[3],Flags[4],Flags[5],QuotedStr(Stamp),QuotedStr(Stamp),SettingsLiteral(Settings,'currencyCode'),
         SettingsLiteral(Settings,'stringtemplateFormat'),SettingsLiteral(Settings,'stringtemplateSeparator'),SettingsRemainder(Settings)])+
        'INSERT INTO custom_field_boards(customFieldId,boardId) VALUES('+QuotedStr(Id)+','+QuotedStr(BoardId)+'); '+DropdownSql;
      Data:=TJSONObject.Create(['customFieldId',Id]);
      try
        Sql:=Sql+'INSERT INTO activities(id,activityType,userId,boardId,createdAt,modifiedAt,data_json) VALUES('+
          QuotedStr(NewId)+',''createCustomField'','+QuotedStr(UserId)+','+QuotedStr(BoardId)+','+
          QuotedStr(Stamp)+','+QuotedStr(Stamp)+','+QuotedStr(Data.AsJSON)+'); '+
          'SELECT CASE WHEN '+Policy.DefinitionExpression(Id,Flags[5]=1)+' THEN 1 ELSE json(''Field creation forbidden'') END; '+DropdownGuards+'COMMIT;';
      finally Data.Free;end;
      if not T.Db.Exec(Sql) then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create custom field');Exit;end;
      Reply:=TJSONObject.Create(['_id',Id]);
      try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
    finally Policy.Free;Settings.Free;end;
    Exit;
  end;
  Rows:=T.Db.Query(Format('SELECT cf.id,cf.name,cf.type FROM custom_fields cf '+
    'JOIN custom_field_boards b ON b.customFieldId=cf.id WHERE b.boardId=%s ORDER BY cf.name;',[QuotedStr(BoardId)]));
  Items:=TJSONArray.Create;
  try
    for Index:=0 to High(Rows) do
      Items.Add(TJSONObject.Create(['_id',Rows[Index][0],'name',Rows[Index][1],'type',Rows[Index][2]]));
    SendJson(aResponse,Items.AsJSON);
  finally Items.Free;end;
end;

procedure ApiCustomField(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  O:=nil;
  try
    try O:=ReadDefinition(T.Db,aRequest.RouteParams['customField']);
    except SendError(aResponse,500,'Could not read custom-field definition');Exit;end;
    if O=nil then begin SendError(aResponse,404,'Custom field not found');Exit;end;
    SendJson(aResponse,O.AsJSON);
  finally O.Free;end;
end;

const CustomFieldNotFound = '{"error":"Custom field not found"}';

procedure ApiUpdateCustomField(aRequest:TRequest;aResponse:TResponse);
const Keys:array[0..6] of string=('name','type','showOnCard','automaticallyOnCard','alwaysOnCard',
  'showLabelOnMiniCard','showSumAtTopOfList');
var T:TWLTenant;UserId,BoardId,FieldId,Permission,Sql,Changes,SettingsSql,Guards,ValueSql,TextValue:string;
  Scope:TSelectionScope;Policy:TFieldPolicy;Rows:TWLRows;Doc,Settings,Reply:TJSONObject;
  Value:TJSONData;i,FlagValue:Integer;
  function Guard(const Condition:string):string;
  begin Result:='SELECT CASE WHEN '+Condition+' THEN 1 ELSE json(''Custom field update guard failed'') END; ';end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,CustomFieldNotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];FieldId:=aRequest.RouteParams['customField'];
  Doc:=nil;Settings:=nil;Scope:=nil;Policy:=nil;
  try
    try
      Scope:=TSelectionScope.Create(T.Db);
      Rows:=T.Db.Query('SELECT count(*) FROM custom_fields WHERE id='+QuotedStr(FieldId)+
        ' AND '+Scope.StringField('custom_fields','id')+' AND EXISTS(SELECT 1 FROM custom_field_boards WHERE customFieldId='+
        QuotedStr(FieldId)+' AND boardId='+QuotedStr(BoardId)+' AND '+Scope.StringField('custom_field_boards','boardId')+');');
      if Length(Rows)<>1 then raise Exception.Create('Could not validate scope');
      if Rows[0][0]='0' then begin SendJson(aResponse,CustomFieldNotFound,404);Exit;end;
      Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
      Permission:=Policy.ScopeWriteExpression(FieldId)+
        ' AND (SELECT count(*) FROM custom_field_boards WHERE customFieldId='+QuotedStr(FieldId)+')=1';
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin SendError(aResponse,403,'Custom field update forbidden');Exit;end;
      if (aRequest.Content<>'') and (Pos('application/json',LowerCase(aRequest.ContentType))=1) then
        Doc:=ExactObject(aRequest.Content)
      else
      begin
        Doc:=TJSONObject.Create;
        for i:=0 to aRequest.ContentFields.Count-1 do
          Doc.Add(aRequest.ContentFields.Names[i],aRequest.ContentFields.ValueFromIndex[i]);
      end;
      Changes:='';
      for i:=0 to High(Keys) do
      begin
        Value:=Doc.Find(Keys[i]);if Value=nil then Continue;
        if i<2 then
        begin
          if not (Value is TJSONString) then raise Exception.Create('Invalid definition text');
          TextValue:=Value.AsString;CheckUtf8(TextValue);
          if (Trim(TextValue)='') or (Pos(#0,TextValue)>0) or ((i=1) and not ValidDefinitionType(TextValue)) then
            raise Exception.Create('Invalid definition text');
          ValueSql:=QuotedStr(TextValue);
        end else begin
          if not DefinitionFlag(Value,FlagValue) then raise Exception.Create('Invalid definition flag');
          ValueSql:=IntToStr(FlagValue);
        end;
        Changes:=Changes+Keys[i]+'='+ValueSql+',';
      end;
      SettingsSql:='';Guards:='';Value:=Doc.Find('settings');
      if Value<>nil then
      begin
        if ((Value is TJSONString) and (Pos('application/json',LowerCase(aRequest.ContentType))=1)) or
          not SettingsInput(Value,Settings) then raise Exception.Create('Invalid definition settings');
        SettingsSql:=ReplaceDefinitionSettings(T.Db,FieldId,Settings,Guards);
      end;
      for i:=0 to Scope.Bindings.Count-1 do Guards:=Guards+Scope.Bindings[i];
      if (Changes<>'') or (SettingsSql<>'') then
      begin
        Sql:='BEGIN IMMEDIATE; '+Guards+Guard(Permission)+'UPDATE custom_fields SET '+Changes+
          'modifiedAt='+QuotedStr(NowIso)+' WHERE id='+QuotedStr(FieldId)+'; '+SettingsSql+Guards+Guard(Permission)+'COMMIT;';
        if not T.Db.Exec(Sql) then
        begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not update custom field');Exit;end;
      end;
      Reply:=TJSONObject.Create(['_id',FieldId]);
      try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
    except SendError(aResponse,500,'Could not update custom field');end;
  finally Scope.Free;Policy.Free;Settings.Free;Doc.Free;end;
end;

procedure ApiDeleteCustomField(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,FieldId,DefinitionRows,ValuesRows,Bindings,Permission,Sql:string;
  Scope:TSelectionScope;Policy:TFieldPolicy;Rows:TWLRows;Reply:TJSONObject;i:Integer;
  function Q(const Value:string):string;
  begin Result:=QuotedStr(Value);end;
  function Guard(const Condition:string):string;
  begin Result:='SELECT CASE WHEN '+Condition+' THEN 1 ELSE json(''Custom field deletion guard failed'') END; ';end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,CustomFieldNotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];FieldId:=aRequest.RouteParams['customField'];
  Scope:=nil;Policy:=nil;
  try
    try
      Scope:=TSelectionScope.Create(T.Db);
      DefinitionRows:=' FROM custom_fields WHERE id='+Q(FieldId);
      Rows:=T.Db.Query('SELECT count(*)'+DefinitionRows+' AND '+Scope.StringField('custom_fields','id')+
        ' AND EXISTS(SELECT 1 FROM custom_field_boards WHERE customFieldId='+Q(FieldId)+
        ' AND boardId='+Q(BoardId)+' AND '+Scope.StringField('custom_field_boards','boardId')+');');
      if (Length(Rows)<>1) or (Length(Rows[0])<>1) then
      begin SendError(aResponse,500,'Could not validate custom field');Exit;end;
      if Rows[0][0]='0' then begin SendJson(aResponse,CustomFieldNotFound,404);Exit;end;
      Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
      // Deleting a definition affects every board that uses it. Limit this
      // scoped operation to a definition owned exclusively by this board.
      Permission:=Policy.ScopeWriteExpression(FieldId)+
        ' AND (SELECT count(*) FROM custom_field_boards WHERE customFieldId='+Q(FieldId)+')=1';
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin SendError(aResponse,403,'Custom field deletion forbidden');Exit;end;
      ValuesRows:=' FROM card_custom_field_values WHERE customFieldId='+Q(FieldId)+
        ' AND EXISTS(SELECT 1 FROM cards WHERE id=card_custom_field_values.cardId AND boardId='+Q(BoardId)+
        ' AND '+Scope.StringField('cards','boardId')+') AND '+Scope.StringField('card_custom_field_values','customFieldId');
      Bindings:='';for i:=0 to Scope.Bindings.Count-1 do Bindings:=Bindings+Scope.Bindings[i];
      Sql:='BEGIN IMMEDIATE; '+Bindings+Guard(Permission)+
        'DELETE'+ValuesRows+'; '+Bindings+Guard(Permission+' AND NOT EXISTS(SELECT 1'+ValuesRows+')')+
        'DELETE'+DefinitionRows+'; '+Bindings+Guard('NOT EXISTS(SELECT 1'+DefinitionRows+
        ') AND NOT EXISTS(SELECT 1'+ValuesRows+') AND '+Policy.DefinitionExpression('',False))+'COMMIT;';
      if not T.Db.Exec(Sql) then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not delete custom field');Exit;end;
      Reply:=TJSONObject.Create(['_id',FieldId]);
      try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
    except SendError(aResponse,500,'Could not delete custom field');end;
  finally Policy.Free;Scope.Free;end;
end;

const DropdownNotFound = '{"error":"Dropdown item not found"}';

function OptionNameInput(Request:TRequest;out Name:string;out Present:Boolean):Boolean;
var Doc:TJSONObject;Value:TJSONData;i:Integer;
begin
  Result:=False;Name:='';Present:=False;Doc:=nil;
  try
    try
      if Pos('application/json',LowerCase(Request.ContentType))=1 then Doc:=ExactObject(Request.Content)
      else
      begin
        Doc:=TJSONObject.Create;
        for i:=0 to Request.ContentFields.Count-1 do
        begin
          if Doc.Find(Request.ContentFields.Names[i])<>nil then Exit;
          Doc.Add(Request.ContentFields.Names[i],Request.ContentFields.ValueFromIndex[i]);
        end;
      end;
      Value:=Doc.Find('name');Present:=Value<>nil;
      if Present then
      begin
        if Value.JSONType<>jtString then Exit;
        Name:=Value.AsString;CheckUtf8(Name);
        if (Trim(Name)='') or (Pos(#0,Name)>0) then Exit;
      end;
      Result:=True;
    except Result:=False;end;
  finally Doc.Free;end;
end;

procedure ApiAppendDropdownItems(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,FieldId,Permission,Sql,Guards,Mutation,Name,CheckSql:string;
  Doc,Settings,Reply:TJSONObject;Value,Entry:TJSONData;Items:TJSONArray;
  Policy:TFieldPolicy;Scope:TSelectionScope;Rows:TWLRows;i:Integer;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,CustomFieldNotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];FieldId:=aRequest.RouteParams['customField'];
  Doc:=nil;Settings:=nil;Policy:=nil;Scope:=nil;
  try
    try
      if aRequest.Content<>'' then
        if Pos('application/json',LowerCase(aRequest.ContentType))=1 then Doc:=ExactObject(aRequest.Content)
        else if aRequest.ContentFields.IndexOfName('items')>=0 then
          Doc:=ExactObject('{"items":'+aRequest.ContentFields.Values['items']+'}');
      Settings:=TJSONObject.Create;
      Items:=TJSONArray.Create;Settings.Add('dropdownItems',Items);
      if Doc<>nil then
      begin
        Value:=Doc.Find('items');
        if Value is TJSONArray then
          for i:=0 to Value.Count-1 do
          begin
            Entry:=Value.Items[i];
            if Entry is TJSONString then
            begin
              Name:=Entry.AsString;CheckUtf8(Name);
              if (Trim(Name)='') or (Pos(#0,Name)>0) then raise Exception.Create('Invalid dropdown option name');
              Items.Add(TJSONObject.Create(['_id',NewId,'name',Name]));
            end;
          end;
      end;
    except SendError(aResponse,400,'Invalid dropdown options');Exit;end;
    try
      Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
      Permission:=Policy.ScopeWriteExpression(FieldId);
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin SendError(aResponse,403,'Dropdown mutation forbidden');Exit;end;
      if Items.Count>0 then
      begin
        Mutation:=DropdownScript(T.Db,FieldId,Settings,Guards,True);
        Scope:=TSelectionScope.Create(T.Db);
        CheckSql:='';
        for i:=0 to Items.Count-1 do
        begin
          Entry:=Items.Items[i];
          CheckSql:=CheckSql+' AND (SELECT count(*) FROM custom_field_dropdown_items WHERE customFieldId='+
            QuotedStr(FieldId)+' AND id='+QuotedStr(TJSONObject(Entry).Get('_id',''))+' AND name='+
            QuotedStr(TJSONObject(Entry).Get('name',''))+' AND '+Scope.StringField('custom_field_dropdown_items','id')+')=1';
        end;
        Sql:='BEGIN IMMEDIATE; '+Guards+
          'SELECT CASE WHEN '+Permission+' THEN 1 ELSE json(''Dropdown append forbidden'') END; '+
          'UPDATE custom_fields SET modifiedAt='+QuotedStr(NowIso)+' WHERE id='+QuotedStr(FieldId)+'; '+Mutation+Guards+
          'SELECT CASE WHEN '+Permission+CheckSql+' THEN 1 ELSE json(''Dropdown append failed'') END; COMMIT;';
        if not T.Db.Exec(Sql) then
        begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not append dropdown options');Exit;end;
      end;
      Reply:=TJSONObject.Create(['_id',FieldId]);
      try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
    except SendError(aResponse,500,'Could not append dropdown options');end;
  finally Scope.Free;Policy.Free;Settings.Free;Doc.Free;end;
end;

procedure ApiDropdownItem(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,FieldId,ItemId,Parent,Item,Bindings,Permission,BeforeSql,AfterSql,Sql,Name,Mutation,ReplyId:string;Rename,Present:Boolean;
  Scope:TSelectionScope;Policy:TFieldPolicy;Rows:TWLRows;i:Integer;Reply:TJSONObject;
  function Q(const Text:string):string;
  begin Result:=QuotedStr(Text);end;
  function Guard(const Condition:string):string;
  begin Result:='SELECT CASE WHEN '+Condition+' THEN 1 ELSE json(''Dropdown mutation guard failed'') END; ';end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];FieldId:=aRequest.RouteParams['customField'];ItemId:=aRequest.RouteParams['dropdownItem'];
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,DropdownNotFound) then Exit;
  Scope:=nil;Policy:=nil;Rename:=aRequest.Method='PUT';
  try
    try
      Scope:=TSelectionScope.Create(T.Db);Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
      Parent:='EXISTS(SELECT 1 FROM custom_fields WHERE id='+Q(FieldId)+' AND '+Scope.StringField('custom_fields','id')+') AND '+
        'EXISTS(SELECT 1 FROM custom_field_boards WHERE customFieldId='+Q(FieldId)+' AND boardId='+Q(BoardId)+' AND '+Scope.StringField('custom_field_boards','boardId')+')';
      Item:=' FROM custom_field_dropdown_items WHERE customFieldId='+Q(FieldId)+' AND id='+Q(ItemId);
      Rows:=T.Db.Query('SELECT CASE WHEN '+Parent+' THEN (SELECT count(*)'+Item+' AND '+Scope.StringField('custom_field_dropdown_items','id')+') ELSE 0 END;');
      if Length(Rows)<>1 then begin SendError(aResponse,500,'Could not validate dropdown item');Exit;end;
      if Rows[0][0]='0' then begin SendJson(aResponse,DropdownNotFound,404);Exit;end;
      if Rows[0][0]<>'1' then begin SendError(aResponse,500,'Ambiguous dropdown item');Exit;end;
      Permission:=Policy.ScopeWriteExpression(FieldId);
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then begin SendError(aResponse,403,'Dropdown mutation forbidden');Exit;end;
      if Rename then
      begin
        if not OptionNameInput(aRequest,Name,Present) then begin SendError(aResponse,400,'Invalid dropdown option name');Exit;end;
        if not Present then
        begin
          Reply:=TJSONObject.Create(['_id',ItemId]);
          try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;Exit;
        end;
      end;
      Bindings:='';for i:=0 to Scope.Bindings.Count-1 do Bindings:=Bindings+Scope.Bindings[i];
      BeforeSql:=Bindings+Guard(Permission+' AND '+Parent+' AND (SELECT count(*)'+Item+' AND '+Scope.StringField('custom_field_dropdown_items','id')+')=1');
      Sql:='BEGIN IMMEDIATE; '+BeforeSql;ReplyId:=FieldId;
      if Rename then
      begin
        Mutation:=DropdownRenameScript(T.Db,FieldId,ItemId,Name);ReplyId:=ItemId;
        AfterSql:=Bindings+Guard(Permission+' AND '+Parent+' AND (SELECT count(*)'+Item+' AND name='+Q(Name)+' AND '+Scope.StringField('custom_field_dropdown_items','id')+')=1');
      end
      else
      begin
        AfterSql:=Bindings+Guard(Permission+' AND '+Parent+' AND NOT EXISTS(SELECT 1'+Item+')');
        Rows:=T.Db.Query('SELECT type FROM sqlite_master WHERE name=''custom_fields'';');
        if (Length(Rows)=1) and (Rows[0][0]='table') then
          Sql:=Sql+'UPDATE custom_fields SET dropdownItemsPresent=1 WHERE id='+Q(FieldId)+'; ';
        Mutation:='DELETE'+Item+'; ';
      end;
      Sql:=Sql+'UPDATE custom_fields SET modifiedAt='+Q(NowIso)+' WHERE id='+Q(FieldId)+'; '+Mutation+AfterSql+'COMMIT;';
      if not T.Db.Exec(Sql) then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not change dropdown item');Exit;end;
      Reply:=TJSONObject.Create(['_id',ReplyId]);
      try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
    except SendError(aResponse,500,'Could not change dropdown item');end;
  finally Policy.Free;Scope.Free;end;
end;

// Keep JSON arrays as array text for the SQL relation contract. A JSON number
// or Boolean remains a SQL scalar; form values and JSON strings remain literal.
function CustomValueSql(Request:TRequest;out Value:string):Boolean;
var Doc:TJSONObject;Data:TJSONData;i,Count:Integer;
begin
  Result:=False;Value:='';Doc:=nil;
  try
    try
      if Pos('application/json',LowerCase(Request.ContentType))=1 then
      begin
        Doc:=ExactObject(Request.Content);Data:=Doc.Find('value');
        if Data=nil then Exit;
        case Data.JSONType of
          jtString:begin
            if Pos(#0,Data.AsString)>0 then Exit;
            Value:=QuotedStr(Data.AsString);
          end;
          jtNumber:begin
            if IsNan(Data.AsFloat) or IsInfinite(Data.AsFloat) then Exit;
            Value:=Data.AsJSON;
          end;
          jtBoolean:if Data.AsBoolean then Value:='1' else Value:='0';
          jtArray:begin
            for i:=0 to Data.Count-1 do
              if (Data.Items[i].JSONType<>jtString) or (Pos(#0,Data.Items[i].AsString)>0) then Exit;
            Value:=QuotedStr(Data.AsJSON);
          end;
        else Exit;
        end;
      end
      else
      begin
        Count:=0;
        for i:=0 to Request.ContentFields.Count-1 do
          if Request.ContentFields.Names[i]='value' then Inc(Count);
        if Count<>1 then Exit;
        if Pos(#0,Request.ContentFields.Values['value'])>0 then Exit;
        Value:=QuotedStr(Request.ContentFields.Values['value']);
      end;
      Result:=True;
    except Result:=False;end;
  finally Doc.Free;end;
end;

// POST set a card's value for a custom field. Do not delete an existing embedded
// row: its unknown properties and BSON type metadata belong to the source store.
procedure ApiCardCustomField(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, CardId, CfId, Value,Scope,GuardSql: string;Reply:TJSONObject;Policy:TFieldPolicy;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  CardId := aRequest.RouteParams['cardId'];
  CfId   := aRequest.RouteParams['customField'];
  if not CustomValueSql(aRequest,Value) then
  begin SendError(aResponse,400,'Expected one scalar or string-array value');Exit;end;
  Policy:=nil;
  try
    try
      Policy:=TFieldPolicy.Create(T.Db,UserId,aRequest.RouteParams['boardId'],CardId);
      if not Policy.Allowed(CfId,True) then
      begin SendError(aResponse,403,'Custom-field write forbidden');Exit;end;
      GuardSql:=Policy.Guard(CfId);
    except SendError(aResponse,403,'Custom-field write forbidden');Exit;end;
    Scope:='cardId='+QuotedStr(CardId)+' AND customFieldId='+QuotedStr(CfId);
    if not T.Db.Exec('BEGIN IMMEDIATE; '+GuardSql+'UPDATE card_custom_field_values SET value='+Value+
      ' WHERE '+Scope+'; INSERT INTO card_custom_field_values(cardId,customFieldId,value) SELECT '+
      QuotedStr(CardId)+','+QuotedStr(CfId)+','+Value+' WHERE NOT EXISTS(SELECT 1 FROM card_custom_field_values WHERE '+Scope+'); '+GuardSql+'COMMIT;') then
    begin
      T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not save custom-field value');Exit;
    end;
    Reply:=TJSONObject.Create(['_id',CardId]);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  finally Policy.Free;end;
end;

procedure ApiLists(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, Title, Id: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  if aRequest.Method = 'POST' then
  begin
    Title := BodyField(aRequest, 'title');
    Id := NewId;
    T.Db.Exec(Format(
      'INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES(%s,%s,'''',%s,0,%s);',
      [QuotedStr(Id), QuotedStr(BoardId), QuotedStr(Title), QuotedStr(NowIso)]));
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
    Exit;
  end;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT id,title FROM lists WHERE boardId=%s AND archived=0 ORDER BY sort;',
    [QuotedStr(BoardId)]))));
end;

procedure ApiList(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  R := T.Db.Query(Format('SELECT id,title FROM lists WHERE id=%s LIMIT 1;',
    [QuotedStr(aRequest.RouteParams['listId'])]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'List not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('title', R[0][1]);
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

procedure ApiCards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId,BoardId,ListId,Id,Author,Title,Descr,Swimlane,Relations:string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  if aRequest.Method <> 'POST' then begin SendError(aResponse, 405, 'Use POST'); Exit; end;
  BoardId  := aRequest.RouteParams['boardId'];
  ListId   := aRequest.RouteParams['listId'];
  Author   := BodyField(aRequest, 'authorId'); if Author = '' then Author := UserId;
  if not ValidAuthor(T.Db,BoardId,UserId,Author) then
  begin SendError(aResponse,403,'Invalid author attribution'); Exit; end;
  Title    := BodyField(aRequest, 'title');
  Descr    := BodyField(aRequest, 'description');
  Swimlane := BodyField(aRequest, 'swimlaneId');
  if not ApiChildrenBelong(T.Db,BoardId,Swimlane,ListId,'','','','','') then
  begin SendError(aResponse,400,'Invalid card parent'); Exit; end;
  if (Swimlane<>'') and (Length(T.Db.Query('SELECT id FROM lists WHERE id='+QuotedStr(ListId)+
    ' AND (swimlaneId='''' OR swimlaneId='+QuotedStr(Swimlane)+');'))=0) then
  begin SendError(aResponse,400,'List is in another swimlane'); Exit; end;
  Id := NewId;
  if not CardRelationSql(T,aRequest,aResponse,BoardId,Id,Relations) then Exit;
  if not T.Db.Exec('BEGIN IMMEDIATE; '+Format(
    'INSERT INTO cards(id,boardId,listId,swimlaneId,title,description,userId,' +
    'dateLastActivity,createdAt,modifiedAt,sort) ' +
    'VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,0);',
    [QuotedStr(Id), QuotedStr(BoardId), QuotedStr(ListId), QuotedStr(Swimlane),
     QuotedStr(Title), QuotedStr(Descr), QuotedStr(Author),
     QuotedStr(NowIso),QuotedStr(NowIso),QuotedStr(NowIso)])+Relations+' COMMIT;') then
  begin T.Db.Exec('ROLLBACK;'); SendError(aResponse,500,'Could not create card'); Exit; end;
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
end;

// Send one card as JSON (incl. its labelIds). Returns False (and sends 404) if missing.
function SendCardById(aResponse: TResponse; Db: TWLDb; const CardId,UserId: string): Boolean;
var R, L: TWLRows; O: TJSONObject; A: TJSONArray; i: Integer;Policy:TFieldPolicy;
begin
  Result := False;
  R := Db.Query(Format(
    'SELECT id,title,description,listId,swimlaneId,boardId,color FROM cards WHERE id=%s LIMIT 1;',
    [QuotedStr(CardId)]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'Card not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('title', R[0][1]); O.Add('description', R[0][2]);
    O.Add('listId', R[0][3]); O.Add('swimlaneId', R[0][4]); O.Add('boardId', R[0][5]);
    O.Add('color', R[0][6]);
    A := TJSONArray.Create;
    L := Db.Query(Format('SELECT labelId FROM card_labels WHERE cardId=%s;', [QuotedStr(CardId)]));
    for i := 0 to High(L) do if Length(L[i]) > 0 then A.Add(L[i][0]);
    O.Add('labelIds', A);
    A := TJSONArray.Create;
    L := Db.Query(Format('SELECT userId FROM card_members WHERE cardId=%s;', [QuotedStr(CardId)]));
    for i := 0 to High(L) do if Length(L[i]) > 0 then A.Add(L[i][0]);
    O.Add('members', A);
    A := TJSONArray.Create;
    L := Db.Query(Format('SELECT userId FROM card_assignees WHERE cardId=%s;', [QuotedStr(CardId)]));
    for i := 0 to High(L) do if Length(L[i]) > 0 then A.Add(L[i][0]);
    O.Add('assignees', A);
    try A:=ReadCustomFields(Db,CardId);
    except
      SendError(aResponse,500,'Could not read custom-field values');Exit;
    end;
    Policy:=nil;
    try
      try
        Policy:=TFieldPolicy.Create(Db,UserId,R[0][5],CardId);Policy.Redact(A);
      except
        // Failure to resolve policy never returns the unredacted array.
        for i:=0 to A.Count-1 do if TJSONObject(A.Items[i]).Find('value')<>nil then
        begin TJSONObject(A.Items[i]).Delete('value');TJSONObject(A.Items[i]).Add('value',TJSONNull.Create);end;
      end;
    finally Policy.Free;end;
    O.Add('customFields', A);
    SendJson(aResponse, O.AsJSON);
    Result := True;
  finally O.Free; end;
end;

procedure ApiCard(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendCardById(aResponse,T.Db,aRequest.RouteParams['cardId'],UserId);
end;

// PUT card — update any of title/description/color and replace labelIds if given.
procedure ApiCardEdit(aRequest:TRequest; aResponse:TResponse);
var T:TWLTenant; UserId,CardId,Sets,Relations:string;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId) then Exit;
  CardId:=aRequest.RouteParams['cardId'];
  if not CardRelationSql(T,aRequest,aResponse,aRequest.RouteParams['boardId'],CardId,Relations) then Exit;
  Sets:='modifiedAt='+QuotedStr(NowIso)+',dateLastActivity='+QuotedStr(NowIso);
  if BodyHasField(aRequest,'title') then Sets:=Sets+',title='+QuotedStr(BodyField(aRequest,'title'));
  if BodyHasField(aRequest,'description') then Sets:=Sets+',description='+QuotedStr(BodyField(aRequest,'description'));
  if BodyHasField(aRequest,'color') then Sets:=Sets+',color='+QuotedStr(BodyField(aRequest,'color'));
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET '+Sets+' WHERE id='+QuotedStr(CardId)+'; '+
    Relations+' COMMIT;') then
  begin T.Db.Exec('ROLLBACK;'); SendError(aResponse,500,'Could not edit card'); Exit; end;
  SendCardById(aResponse,T.Db,CardId,UserId);
end;

procedure ApiListCards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT id,title FROM cards WHERE listId=%s AND boardId=%s AND archived=0 ORDER BY sort;',
    [QuotedStr(aRequest.RouteParams['listId']),QuotedStr(aRequest.RouteParams['boardId'])]))));
end;

function CountOf(Db: TWLDb; const WhereCol, Id, BoardId: string): Integer;
var R: TWLRows;
begin
  R := Db.Query(Format('SELECT COUNT(*) FROM cards WHERE %s=%s AND boardId=%s AND archived=0;',
    [WhereCol, QuotedStr(Id),QuotedStr(BoardId)]));
  if (Length(R) > 0) and (Length(R[0]) > 0) then Result := StrToIntDef(R[0][0], 0) else Result := 0;
end;

procedure ApiListCardsCount(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, Format('{"list_cards_count":%d}',
    [CountOf(T.Db, 'listId', aRequest.RouteParams['listId'],aRequest.RouteParams['boardId'])]));
end;

procedure ApiBoardCardsCount(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, Format('{"board_cards_count":%d}',
    [CountOf(T.Db, 'boardId', aRequest.RouteParams['boardId'],aRequest.RouteParams['boardId'])]));
end;

procedure ApiSwimlaneCards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT id,title FROM cards WHERE swimlaneId=%s AND boardId=%s AND archived=0 ORDER BY sort;',
    [QuotedStr(aRequest.RouteParams['swimlaneId']),QuotedStr(aRequest.RouteParams['boardId'])]))));
end;

// GET checklists of a card / POST create a checklist
procedure ApiCardChecklists(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, CardId, Title, Id: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  CardId  := aRequest.RouteParams['cardId'];
  if aRequest.Method = 'POST' then
  begin
    Title := BodyField(aRequest, 'title');
    if Title = '' then Title := 'Checklist';
    Id := NewId;
    T.Db.Exec(Format(
      'INSERT INTO checklists(id,cardId,boardId,title,sort,createdAt,modifiedAt) ' +
      'VALUES(%s,%s,%s,%s,0,%s,%s);',
      [QuotedStr(Id), QuotedStr(CardId), QuotedStr(BoardId), QuotedStr(Title),
       QuotedStr(NowIso), QuotedStr(NowIso)]));
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
    Exit;
  end;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT id,title FROM checklists WHERE cardId=%s ORDER BY sort;', [QuotedStr(CardId)]))));
end;

// GET one checklist with its items
procedure ApiChecklist(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; R, It: TWLRows; O, IO: TJSONObject; A: TJSONArray; i: Integer;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  R := T.Db.Query(Format('SELECT id,title FROM checklists WHERE id=%s LIMIT 1;',
    [QuotedStr(aRequest.RouteParams['checklistId'])]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'Checklist not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('title', R[0][1]);
    A := TJSONArray.Create;
    It := T.Db.Query(Format(
      'SELECT id,title,isFinished FROM checklist_items WHERE checklistId=%s ORDER BY sort;',
      [QuotedStr(R[0][0])]));
    for i := 0 to High(It) do
      if Length(It[i]) >= 3 then
      begin
        IO := TJSONObject.Create;
        IO.Add('_id', It[i][0]); IO.Add('title', It[i][1]); IO.Add('isFinished', It[i][2] = '1');
        A.Add(IO);
      end;
    O.Add('items', A);
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

// POST add an item to a checklist
procedure ApiChecklistItems(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, CardId, ChecklistId, Title, Id: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId     := aRequest.RouteParams['boardId'];
  CardId      := aRequest.RouteParams['cardId'];
  ChecklistId := aRequest.RouteParams['checklistId'];
  Title := BodyField(aRequest, 'title');
  Id := NewId;
  T.Db.Exec(Format(
    'INSERT INTO checklist_items(id,checklistId,cardId,boardId,title,sort,createdAt,modifiedAt) ' +
    'VALUES(%s,%s,%s,%s,%s,0,%s,%s);',
    [QuotedStr(Id), QuotedStr(ChecklistId), QuotedStr(CardId), QuotedStr(BoardId),
     QuotedStr(Title), QuotedStr(NowIso), QuotedStr(NowIso)]));
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
end;

// GET item / PUT toggle-or-edit (isFinished/title) / DELETE a checklist item
procedure ApiChecklistItem(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, ItemId, Sets, V: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  ItemId := aRequest.RouteParams['item'];
  if aRequest.Method = 'DELETE' then
  begin
    T.Db.Exec(Format('DELETE FROM checklist_items WHERE id=%s;', [QuotedStr(ItemId)]));
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(ItemId, '"')]));
    Exit;
  end;
  if aRequest.Method = 'PUT' then
  begin
    Sets := 'modifiedAt=' + QuotedStr(NowIso);
    V := BodyField(aRequest, 'title');      if V <> '' then Sets := Sets + ', title=' + QuotedStr(V);
    V := BodyField(aRequest, 'isFinished'); if V <> '' then Sets := Sets + Format(', isFinished=%d', [BoolInt(V)]);
    T.Db.Exec(Format('UPDATE checklist_items SET %s WHERE id=%s;', [Sets, QuotedStr(ItemId)]));
  end;
  R := T.Db.Query(Format('SELECT id,title,isFinished FROM checklist_items WHERE id=%s LIMIT 1;',
    [QuotedStr(ItemId)]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'Item not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('title', R[0][1]); O.Add('isFinished', R[0][2] = '1');
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

// GET comments of a card / POST add a comment
procedure ApiCardComments(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; UserId, BoardId, CardId, Author, Text1, Id: string;
  R: TWLRows; A: TJSONArray; O: TJSONObject; i: Integer;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  CardId  := aRequest.RouteParams['cardId'];
  if aRequest.Method = 'POST' then
  begin
    Author := BodyField(aRequest, 'authorId'); if Author = '' then Author := UserId;
    if not ValidAuthor(T.Db,BoardId,UserId,Author) then
    begin SendError(aResponse,403,'Invalid author attribution'); Exit; end;
    Text1  := BodyField(aRequest, 'comment');
    Id := NewId;
    T.Db.Exec(Format(
      'INSERT INTO card_comments(id,boardId,cardId,userId,text,createdAt,modifiedAt) ' +
      'VALUES(%s,%s,%s,%s,%s,%s,%s);',
      [QuotedStr(Id), QuotedStr(BoardId), QuotedStr(CardId), QuotedStr(Author),
       QuotedStr(Text1), QuotedStr(NowIso), QuotedStr(NowIso)]));
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
    Exit;
  end;
  R := T.Db.Query(Format(
    'SELECT id,text FROM card_comments WHERE cardId=%s ORDER BY createdAt;', [QuotedStr(CardId)]));
  A := TJSONArray.Create;
  try
    for i := 0 to High(R) do
      if Length(R[i]) >= 2 then
      begin
        O := TJSONObject.Create;
        O.Add('_id', R[i][0]); O.Add('comment', R[i][1]);
        A.Add(O);
      end;
    SendJson(aResponse, A.AsJSON);
  finally A.Free; end;
end;

// GET one comment / DELETE one comment
procedure ApiCardComment(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, CommentId: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  CommentId := aRequest.RouteParams['commentId'];
  if aRequest.Method = 'DELETE' then
  begin
    T.Db.Exec(Format('DELETE FROM card_comments WHERE id=%s;', [QuotedStr(CommentId)]));
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(CommentId, '"')]));
    Exit;
  end;
  R := T.Db.Query(Format('SELECT id,text,userId FROM card_comments WHERE id=%s LIMIT 1;',
    [QuotedStr(CommentId)]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'Comment not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('comment', R[0][1]); O.Add('authorId', R[0][2]);
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

// POST add / DELETE remove a card member (userId in the path).
procedure ApiCardMember(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, CardId, MemberId:string; Ok:Boolean;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  CardId := aRequest.RouteParams['cardId'];
  MemberId := aRequest.RouteParams['member'];
  if (aRequest.Method<>'DELETE') and not EnabledBoardMember(T.Db,aRequest.RouteParams['boardId'],MemberId) then
  begin SendError(aResponse,400,'Target is not an enabled board member'); Exit; end;
  if aRequest.Method = 'DELETE' then
    Ok:=T.Db.Exec(Format('DELETE FROM card_members WHERE cardId=%s AND userId=%s;',
      [QuotedStr(CardId), QuotedStr(MemberId)]))
  else
    Ok:=T.Db.Exec(Format('INSERT OR IGNORE INTO card_members(cardId,userId) VALUES(%s,%s);',
      [QuotedStr(CardId), QuotedStr(MemberId)]));
  if not Ok then begin SendError(aResponse,500,'Could not update card membership'); Exit; end;
  SendCardById(aResponse,T.Db,CardId,UserId);
end;

// POST add / DELETE remove a card assignee (userId in the path).
procedure ApiCardAssignee(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, CardId, AssigneeId:string; Ok:Boolean;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  CardId := aRequest.RouteParams['cardId'];
  AssigneeId := aRequest.RouteParams['assignee'];
  if (aRequest.Method<>'DELETE') and not EnabledBoardMember(T.Db,aRequest.RouteParams['boardId'],AssigneeId) then
  begin SendError(aResponse,400,'Target is not an enabled board member'); Exit; end;
  if aRequest.Method = 'DELETE' then
    Ok:=T.Db.Exec(Format('DELETE FROM card_assignees WHERE cardId=%s AND userId=%s;',
      [QuotedStr(CardId), QuotedStr(AssigneeId)]))
  else
    Ok:=T.Db.Exec(Format('INSERT OR IGNORE INTO card_assignees(cardId,userId) VALUES(%s,%s);',
      [QuotedStr(CardId), QuotedStr(AssigneeId)]));
  if not Ok then begin SendError(aResponse,500,'Could not update card membership'); Exit; end;
  SendCardById(aResponse,T.Db,CardId,UserId);
end;

// POST card archive — archives by default; body isArchive=false unarchives.
procedure ApiCardArchive(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, CardId, V: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  CardId := aRequest.RouteParams['cardId'];
  V := BodyField(aRequest, 'isArchive');
  if (V = '') or (BoolInt(V) = 1) then
    T.Db.Exec(Format('UPDATE cards SET archived=1, archivedAt=%s, modifiedAt=%s WHERE id=%s;',
      [QuotedStr(NowIso), QuotedStr(NowIso), QuotedStr(CardId)]))
  else
    T.Db.Exec(Format('UPDATE cards SET archived=0, archivedAt=NULL, modifiedAt=%s WHERE id=%s;',
      [QuotedStr(NowIso), QuotedStr(CardId)]));
  SendCardById(aResponse,T.Db,CardId,UserId);
end;

// DELETE card — children (labels/members/comments/checklists/…) cascade via FK.
procedure ApiCardDelete(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, CardId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  CardId := aRequest.RouteParams['cardId'];
  T.Db.Exec(Format('DELETE FROM cards WHERE id=%s;', [QuotedStr(CardId)]));
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(CardId, '"')]));
end;

// DELETE list — its cards have no FK on listId, so remove them first (their children cascade).
procedure ApiListDelete(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, ListId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  ListId := aRequest.RouteParams['listId'];
  T.Db.Exec(Format('DELETE FROM cards WHERE listId=%s AND boardId=%s;', [QuotedStr(ListId),QuotedStr(aRequest.RouteParams['boardId'])]));
  T.Db.Exec(Format('DELETE FROM lists WHERE id=%s;', [QuotedStr(ListId)]));
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(ListId, '"')]));
end;

// DELETE swimlane — its cards have no FK on swimlaneId, so remove them first.
procedure ApiSwimlaneDelete(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, SwimlaneId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SwimlaneId := aRequest.RouteParams['swimlaneId'];
  T.Db.Exec(Format('DELETE FROM cards WHERE swimlaneId=%s AND boardId=%s;', [QuotedStr(SwimlaneId),QuotedStr(aRequest.RouteParams['boardId'])]));
  T.Db.Exec(Format('DELETE FROM swimlanes WHERE id=%s;', [QuotedStr(SwimlaneId)]));
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(SwimlaneId, '"')]));
end;

// DELETE board — swimlanes/lists/cards/labels/members cascade via boardId FKs (and card
// children transitively); list/swimlane-scoped cards also go via the board cascade on cards.
procedure ApiBoardDelete(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  T.Db.Exec(Format('DELETE FROM boards WHERE id=%s;', [QuotedStr(BoardId)]));
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(BoardId, '"')]));
end;

// ---- attachments: metadata in `attachments`, bytes in files/attachme/<digest components> --------------
function AttachDir(const T: TWLTenant): string;
begin
  Result := T.FilesDir + 'attachme' + PathDelim;
end;

function ReadFileBytes(const Path: string): string;
var fs: TFileStream;
begin
  Result := '';
  if not FileExists(Path) then Exit;
  fs := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then fs.ReadBuffer(Result[1], fs.Size);
  finally fs.Free; end;
end;

procedure WriteFileBytes(const Path, Data: string);
var fs: TFileStream;
begin
  fs := TFileStream.Create(Path, fmCreate);
  try
    if Length(Data) > 0 then fs.WriteBuffer(Data[1], Length(Data));
  finally fs.Free; end;
end;

// POST /api/attachment/upload — JSON {boardId,swimlaneId,listId,cardId,fileData(b64),fileName,fileType}
procedure ApiAttachmentUpload(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; UserId: string;
  D: TJSONData; O: TJSONObject;
  BoardId, Sw, Lst, Crd, FileName, FileType, Id, Bytes: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  try D := GetJSON(aRequest.Content); except SendError(aResponse, 400, 'Bad JSON'); Exit; end;
  try
    if not (D is TJSONObject) then begin SendError(aResponse, 400, 'Bad body'); Exit; end;
    O := TJSONObject(D);
    BoardId  := O.Get('boardId', '');  Sw  := O.Get('swimlaneId', '');
    Lst      := O.Get('listId', '');   Crd := O.Get('cardId', '');
    FileName := O.Get('fileName', 'file');
    FileType := O.Get('fileType', 'application/octet-stream');
    if not ApiAuthBoard(T, aResponse, UserId, BoardId, True) then Exit;
    if not ApiChildrenBelong(T.Db,BoardId,Sw,Lst,Crd,'','','','') then
    begin SendError(aResponse,400,'Invalid attachment parent'); Exit; end;
    Bytes := DecodeStringBase64(O.Get('fileData', ''));
    Id := NewId;
    ForceDirectories(ExtractFileDir(StoreFilePath(T.FilesDir,'attachme',Id)));
    WriteFileBytes(StoreFilePath(T.FilesDir,'attachme',Id), Bytes);
    T.Db.Exec(Format(
      'INSERT INTO attachments(id,boardId,swimlaneId,listId,cardId,name,type,size,' +
      'storageBackend,userId,createdAt) VALUES(%s,%s,%s,%s,%s,%s,%s,%d,''filesystem'',%s,%s);',
      [QuotedStr(Id), QuotedStr(BoardId), QuotedStr(Sw), QuotedStr(Lst), QuotedStr(Crd),
       QuotedStr(FileName), QuotedStr(FileType), Length(Bytes), QuotedStr(UserId), QuotedStr(NowIso)]));
    SendJson(aResponse, Format(
      '{"success":true,"attachmentId":%s,"fileName":%s,"fileSize":%d,"storageBackend":"filesystem"}',
      [AnsiQuotedStr(Id, '"'), AnsiQuotedStr(FileName, '"'), Length(Bytes)]));
  finally D.Free; end;
end;

// look up an attachment row; returns False (and 404 json) if missing
function LoadAttachment(aResponse: TResponse; Db: TWLDb; const Id: string; out R: TWLRows): Boolean;
begin
  R := Db.Query(Format(
    'SELECT boardId,swimlaneId,listId,cardId,name,type,size,createdAt FROM attachments WHERE id=%s LIMIT 1;',
    [QuotedStr(Id)]));
  Result := Length(R) > 0;
  if not Result then SendJson(aResponse, '{"success":false,"message":"Attachment not found"}', 404);
end;

procedure ApiAttachmentDownload(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, Id: string; R: TWLRows; Bytes: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  Id := aRequest.RouteParams['attachmentId'];
  if not LoadAttachment(aResponse, T.Db, Id, R) then Exit;
  if not ApiAuthBoard(T, aResponse, UserId, R[0][0], False) then Exit;
  Bytes := ReadFileBytes(StoreFilePath(T.FilesDir,'attachme',Id));
  SendJson(aResponse, Format(
    '{"success":true,"base64Data":%s,"fileName":%s,"fileSize":%d,"storageBackend":"filesystem"}',
    [AnsiQuotedStr(EncodeStringBase64(Bytes), '"'), AnsiQuotedStr(R[0][4], '"'), Length(Bytes)]));
end;

procedure ApiAttachmentInfo(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, Id: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  Id := aRequest.RouteParams['attachmentId'];
  if not LoadAttachment(aResponse, T.Db, Id, R) then Exit;
  if not ApiAuthBoard(T, aResponse, UserId, R[0][0], False) then Exit;
  O := TJSONObject.Create;
  try
    O.Add('success', True);          O.Add('attachmentId', Id);
    O.Add('boardId', R[0][0]);       O.Add('swimlaneId', R[0][1]);
    O.Add('listId', R[0][2]);        O.Add('cardId', R[0][3]);
    O.Add('fileName', R[0][4]);      O.Add('fileType', R[0][5]);
    O.Add('fileSize', StrToIntDef(R[0][6], 0));
    O.Add('storageBackend', 'filesystem');
    O.Add('createdAt', R[0][7]);
    O.Add('isImage', Copy(R[0][5], 1, 6) = 'image/');
    O.Add('versions', TJSONArray.Create);
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

procedure ApiAttachmentDelete(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, Id: string; R: TWLRows;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  Id := aRequest.RouteParams['attachmentId'];
  if not LoadAttachment(aResponse, T.Db, Id, R) then Exit;
  if not ApiAuthBoard(T, aResponse, UserId, R[0][0], True) then Exit;
  if FileExists(StoreFilePath(T.FilesDir,'attachme',Id)) then DeleteFile(StoreFilePath(T.FilesDir,'attachme',Id));
  T.Db.Exec(Format('DELETE FROM attachments WHERE id=%s;', [QuotedStr(Id)]));
  SendJson(aResponse, Format('{"success":true,"attachmentId":%s,"fileName":%s}',
    [AnsiQuotedStr(Id, '"'), AnsiQuotedStr(R[0][4], '"')]));
end;

// GET /api/boards/:boardId/attachments — list a board's attachments
procedure ApiBoardAttachments(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; R: TWLRows; A: TJSONArray; O: TJSONObject; i: Integer;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  R := T.Db.Query(Format(
    'SELECT id,name,cardId FROM attachments WHERE boardId=%s ORDER BY createdAt;',
    [QuotedStr(aRequest.RouteParams['boardId'])]));
  A := TJSONArray.Create;
  try
    for i := 0 to High(R) do
      if Length(R[i]) >= 3 then
      begin
        O := TJSONObject.Create;
        O.Add('_id', R[i][0]); O.Add('name', R[i][1]); O.Add('cardId', R[i][2]);
        A.Add(O);
      end;
    SendJson(aResponse, A.AsJSON);
  finally A.Free; end;
end;

// GET /api/attachment/list/:boardId/:swimlaneId/:listId/:cardId — a card's attachments
procedure ApiCardAttachmentsList(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; R: TWLRows; A: TJSONArray; O: TJSONObject; i: Integer;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;   // boardId is in the route
  R := T.Db.Query(Format(
    'SELECT id,name,type,size,createdAt FROM attachments WHERE cardId=%s ORDER BY createdAt;',
    [QuotedStr(aRequest.RouteParams['cardId'])]));
  // api.py listcardattachments expects {success, attachments:[{attachmentId,fileName,...}]}
  O := TJSONObject.Create;
  try
    O.Add('success', True);
    A := TJSONArray.Create;
    for i := 0 to High(R) do
      if Length(R[i]) >= 5 then
        A.Add(TJSONObject.Create([
          'attachmentId', R[i][0], 'fileName', R[i][1], 'fileType', R[i][2],
          'fileSize', StrToIntDef(R[i][3], 0), 'storageBackend', 'filesystem',
          'createdAt', R[i][4]]));
    O.Add('attachments', A);
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

end.
