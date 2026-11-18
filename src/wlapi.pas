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
procedure ApiListEdit(aRequest:TRequest;aResponse:TResponse);
procedure ApiListArchive(aRequest: TRequest; aResponse: TResponse);
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
uses wlstore,wlsjson,Math,wlcfjson,wlcfpol,wlpath,wlcfspec,wlselscp,wlcolors,wlposhis;

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
    ' AND deletedAt IS NULL AND boardId='+QuotedStr(BoardId)+Scope+';') then Exit;
  Scope:='';
  if ListId<>'' then Scope:=Scope+' AND listId='+QuotedStr(ListId);
  if LaneId<>'' then Scope:=Scope+' AND swimlaneId='+QuotedStr(LaneId);
  if (CardId<>'') and not Exists('SELECT id FROM cards WHERE id='+QuotedStr(CardId)+
    ' AND deletedAt IS NULL AND boardId='+QuotedStr(BoardId)+Scope+';') then Exit;
  if (ChecklistId<>'') and not Exists('SELECT id FROM checklists WHERE id='+QuotedStr(ChecklistId)+
    ' AND cardId='+QuotedStr(CardId)+' AND (boardId IS NULL OR boardId='+QuotedStr(BoardId)+');') then Exit;
  if (ItemId<>'') and not Exists('SELECT id FROM checklist_items WHERE id='+QuotedStr(ItemId)+
    ' AND checklistId='+QuotedStr(ChecklistId)+' AND cardId='+QuotedStr(CardId)+
    ' AND (boardId IS NULL OR boardId='+QuotedStr(BoardId)+');') then Exit;
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
    Rows := T.Db.Query(Format('SELECT id,title,sort,swimlaneId FROM lists WHERE boardId=%s AND deletedAt IS NULL;', [QuotedStr(SrcId)]));
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
      'SELECT id,title,description,listId,swimlaneId,userId,color,sort FROM cards WHERE boardId=%s AND deletedAt IS NULL;',
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

// PUT board label — return the existing or newly created label ID as JSON.
procedure ApiCreateLabel(aRequest: TRequest; aResponse: TResponse);
const Colors='|white|green|yellow|orange|red|purple|blue|sky|lime|pink|black|silver|'+
  'peachpuff|crimson|plum|darkgreen|slateblue|magenta|gold|navy|gray|saddlebrown|paleturquoise|mistyrose|indigo|';
  Denied='Only a board admin can create or edit labels';
var T:TWLTenant;UserId,BoardId,Color,Name,Id,Permission,Existing,Sql:string;
  Policy:TFieldPolicy;Body:TJSONObject;LabelData,Value:TJSONData;Rows:TWLRows;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=QuotedStr(aRequest.RouteParams['boardId']);
  if Length(T.Db.Query('SELECT id FROM boards WHERE id='+BoardId+';'))<>1 then
  begin SendError(aResponse,404,'Board not found');Exit;end;
  Policy:=TFieldPolicy.Create(T.Db,UserId,aRequest.RouteParams['boardId'],'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if Length(Rows)<>1 then begin SendError(aResponse,500,'Could not check label permission');Exit;end;
  if Rows[0][0]<>'1' then begin SendError(aResponse,403,Denied);Exit;end;
  Name:='';Color:='';Body:=nil;
  try
    try
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
      begin
        Body:=ExactObject(aRequest.Content);LabelData:=Body.Find('label');
        if LabelData=nil then raise Exception.Create('Missing label');
        if LabelData.JSONType=jtString then Name:=LabelData.AsString
        else if LabelData is TJSONObject then
        begin
          Value:=TJSONObject(LabelData).Find('name');
          if (Value<>nil) and (Value.JSONType<>jtNull) then Name:=Value.AsString;
          Value:=TJSONObject(LabelData).Find('color');
          if (Value<>nil) and (Value.JSONType<>jtNull) then Color:=Value.AsString;
        end else raise Exception.Create('Invalid label');
      end else
      begin
        Name:=aRequest.ContentFields.Values['label'];
        if Name='' then Name:=aRequest.ContentFields.Values['name'];
        Color:=aRequest.ContentFields.Values['color'];
        if (Name='') and (Color='') then raise Exception.Create('Missing label');
      end;
      Name:=Trim(Name);CheckUtf8(Name);
      if Pos(#0,Name)>0 then raise Exception.Create('Invalid label name');
      if Color='' then Color:='green';
      if (Pos('|',Color)>0) or (Pos('|'+Color+'|',Colors)=0) then
        raise Exception.Create('Invalid label color');
    except SendError(aResponse,400,'Invalid label');Exit;end;
  finally Body.Free;end;
  Existing:='SELECT id FROM board_labels WHERE boardId='+BoardId+' AND name='+QuotedStr(Name)+
    ' AND color='+QuotedStr(Color)+' ORDER BY id LIMIT 1';
  Rows:=T.Db.Query('SELECT lower(hex(randomblob(3)));');
  if Length(Rows)<>1 then begin SendError(aResponse,500,'Could not create label');Exit;end;
  Id:=Rows[0][0];
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+' THEN 1 ELSE json(''Label permission changed'') END; '+
    'INSERT INTO board_labels(boardId,id,name,color) SELECT '+BoardId+','+QuotedStr(Id)+','+
    QuotedStr(Name)+','+QuotedStr(Color)+' WHERE NOT EXISTS('+Existing+'); '+
    'SELECT CASE WHEN '+Permission+' AND EXISTS('+Existing+') THEN 1 ELSE json(''Label write failed'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create label');Exit;end;
  Rows:=T.Db.Query(Existing+';');
  if Length(Rows)<>1 then begin SendError(aResponse,500,'Could not find label');Exit;end;
  SendJson(aResponse,'"'+StringToJSONString(Rows[0][0])+'"');
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

const CustomFieldNotFound = '{"error":"Custom field not found"}';

procedure ApiCustomField(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId, CustomFieldNotFound) then Exit;
  O:=nil;
  try
    try O:=ReadDefinition(T.Db,aRequest.RouteParams['customField']);
    except SendError(aResponse,500,'Could not read custom-field definition');Exit;end;
    if O=nil then begin SendJson(aResponse,CustomFieldNotFound,404);Exit;end;
    SendJson(aResponse,O.AsJSON);
  finally O.Free;end;
end;

// Pin both the authorized boards and the exact size of the binding set.
procedure DefinitionWriteScope(Db:TWLDb;const UserId,FieldId,RouteBoardId:string;
  out BoardIds,Permission,AfterDelete:string);
var Rows:TWLRows;Row:TWLRow;Policy:TFieldPolicy;Previous:string;RouteFound:Boolean;
begin
  Rows:=Db.Query('SELECT boardId FROM custom_field_boards WHERE customFieldId='+QuotedStr(FieldId)+' ORDER BY boardId;');
  if Length(Rows)=0 then raise Exception.Create('Missing definition bindings');
  BoardIds:='';AfterDelete:='1';Previous:='';RouteFound:=False;
  Permission:='(SELECT count(*) FROM custom_field_boards WHERE customFieldId='+QuotedStr(FieldId)+')='+IntToStr(Length(Rows));
  for Row in Rows do
  begin
    if (Length(Row)<>1) or (Row[0]='') then raise Exception.Create('Invalid definition binding');
    if Row[0]=Previous then raise Exception.Create('Duplicate definition binding');
    Previous:=Row[0];RouteFound:=RouteFound or (Row[0]=RouteBoardId);
    if BoardIds<>'' then BoardIds:=BoardIds+',';
    BoardIds:=BoardIds+QuotedStr(Row[0]);
    Policy:=TFieldPolicy.Create(Db,UserId,Row[0],'');
    try
      Permission:=Permission+' AND '+Policy.ScopeWriteExpression(FieldId);
      AfterDelete:=AfterDelete+' AND '+Policy.DefinitionExpression('',False);
    finally Policy.Free;end;
  end;
  if not RouteFound then raise Exception.Create('Definition bindings changed');
  BoardIds:='('+BoardIds+')';
end;

procedure ApiUpdateCustomField(aRequest:TRequest;aResponse:TResponse);
const Keys:array[0..6] of string=('name','type','showOnCard','automaticallyOnCard','alwaysOnCard',
  'showLabelOnMiniCard','showSumAtTopOfList');
var T:TWLTenant;UserId,BoardId,FieldId,Permission,Sql,Changes,SettingsSql,Guards,ValueSql,TextValue,BackfillSql,BoardIds,AfterDelete:string;
  Scope:TSelectionScope;Rows:TWLRows;Doc,Settings,Reply:TJSONObject;
  Value:TJSONData;i,FlagValue:Integer;
  function Guard(const Condition:string):string;
  begin Result:='SELECT CASE WHEN '+Condition+' THEN 1 ELSE json(''Custom field update guard failed'') END; ';end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,CustomFieldNotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];FieldId:=aRequest.RouteParams['customField'];
  Doc:=nil;Settings:=nil;Scope:=nil;
  try
    try
      Scope:=TSelectionScope.Create(T.Db);
      Rows:=T.Db.Query('SELECT count(*) FROM custom_fields WHERE id='+QuotedStr(FieldId)+
        ' AND '+Scope.StringField('custom_fields','id')+' AND EXISTS(SELECT 1 FROM custom_field_boards WHERE customFieldId='+
        QuotedStr(FieldId)+' AND boardId='+QuotedStr(BoardId)+' AND '+Scope.StringField('custom_field_boards','boardId')+');');
      if Length(Rows)<>1 then raise Exception.Create('Could not validate scope');
      if Rows[0][0]='0' then begin SendJson(aResponse,CustomFieldNotFound,404);Exit;end;
      DefinitionWriteScope(T.Db,UserId,FieldId,BoardId,BoardIds,Permission,AfterDelete);
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
      Changes:='';BackfillSql:='';
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
          if (Keys[i]='alwaysOnCard') and (FlagValue=1) then
            BackfillSql:='INSERT INTO card_custom_field_values(cardId,customFieldId,value) SELECT id,'+
              QuotedStr(FieldId)+',NULL FROM cards WHERE boardId IN '+BoardIds+
              ' AND '+Scope.StringField('cards','boardId')+
              ' AND NOT EXISTS(SELECT 1 FROM card_custom_field_values WHERE cardId=cards.id AND customFieldId='+
              QuotedStr(FieldId)+'); ';
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
          'modifiedAt='+QuotedStr(NowIso)+' WHERE id='+QuotedStr(FieldId)+'; '+SettingsSql+BackfillSql+Guards+Guard(Permission)+'COMMIT;';
        if not T.Db.Exec(Sql) then
        begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not update custom field');Exit;end;
      end;
      Reply:=TJSONObject.Create(['_id',FieldId]);
      try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
    except SendError(aResponse,500,'Could not update custom field');end;
  finally Scope.Free;Settings.Free;Doc.Free;end;
end;

procedure ApiDeleteCustomField(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,FieldId,DefinitionRows,ValuesRows,ActivityRows,ActivitySource,Bindings,Permission,Sql,BoardIds,AfterDelete:string;
  Scope:TSelectionScope;Rows:TWLRows;Reply:TJSONObject;i:Integer;
  function Q(const Value:string):string;
  begin Result:=QuotedStr(Value);end;
  function Guard(const Condition:string):string;
  begin Result:='SELECT CASE WHEN '+Condition+' THEN 1 ELSE json(''Custom field deletion guard failed'') END; ';end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,CustomFieldNotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];FieldId:=aRequest.RouteParams['customField'];
  Scope:=nil;
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
      DefinitionWriteScope(T.Db,UserId,FieldId,BoardId,BoardIds,Permission,AfterDelete);
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin SendError(aResponse,403,'Custom field deletion forbidden');Exit;end;
      ValuesRows:=' FROM card_custom_field_values WHERE customFieldId='+Q(FieldId)+
        ' AND EXISTS(SELECT 1 FROM cards WHERE id=card_custom_field_values.cardId AND boardId IN '+BoardIds+
        ' AND '+Scope.StringField('cards','boardId')+') AND '+Scope.StringField('card_custom_field_values','customFieldId');
      ActivityRows:=' FROM activities WHERE boardId IN '+BoardIds+' AND '+
        'json_type(data_json,''$.customFieldId'')=''text'' AND json_extract(data_json,''$.customFieldId'')='+Q(FieldId)+
        ' AND '+Scope.StringField('activities','boardId');
      Rows:=T.Db.Query('SELECT type FROM sqlite_master WHERE name=''activities'';');
      if Length(Rows)<>1 then raise Exception.Create('Missing activity source');
      if Rows[0][0]='view' then
      begin
        Rows:=T.Db.Query('SELECT table_name FROM _wl_models WHERE name=''activities'';');
        if Length(Rows)<>1 then raise Exception.Create('Ambiguous activity source');
        ActivitySource:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
        ActivityRows:=ActivityRows+' AND EXISTS(SELECT 1 FROM '+ActivitySource+' a WHERE '+
          'json_extract(a._ferretdb_sjson,''$._id'')=activities.id AND '+
          'json_extract(a._ferretdb_sjson,''$.$s.p.customFieldId.t'')=''string'')';
      end
      else if Rows[0][0]<>'table' then raise Exception.Create('Invalid activity source');
      Bindings:='';for i:=0 to Scope.Bindings.Count-1 do Bindings:=Bindings+Scope.Bindings[i];
      Sql:='BEGIN IMMEDIATE; '+Bindings+Guard(Permission)+
        'DELETE'+ValuesRows+'; DELETE'+ActivityRows+'; '+Bindings+Guard(Permission+' AND NOT EXISTS(SELECT 1'+ValuesRows+')')+
        'DELETE'+DefinitionRows+'; '+Bindings+Guard('NOT EXISTS(SELECT 1'+DefinitionRows+
        ') AND NOT EXISTS(SELECT 1'+ValuesRows+') AND NOT EXISTS(SELECT 1'+ActivityRows+') AND '+AfterDelete)+'COMMIT;';
      if not T.Db.Exec(Sql) then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not delete custom field');Exit;end;
      Reply:=TJSONObject.Create(['_id',FieldId]);
      try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
    except SendError(aResponse,500,'Could not delete custom field');end;
  finally Scope.Free;end;
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
var T: TWLTenant; UserId, BoardId, Title, Id, BoardSql, Stamp, LaneId, LaneSql, Guard: string;Rows:TWLRows;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];BoardSql:=QuotedStr(BoardId);
  if aRequest.Method = 'POST' then
  begin
    Title:=BodyField(aRequest,'title');LaneId:=BodyField(aRequest,'swimlaneId');
    if (Trim(Title)='') or (Pos(#0,Title)>0) or (Pos(#0,LaneId)>0) then
    begin SendError(aResponse,400,'Invalid list title or swimlane');Exit;end;
    Guard:='';
    if LaneId<>'' then
    begin
      LaneSql:=QuotedStr(LaneId);
      Guard:='SELECT CASE WHEN (SELECT count(*) FROM swimlanes WHERE id='+LaneSql+
        ' AND boardId='+BoardSql+')=1 THEN 1 ELSE json(''List swimlane changed'') END; ';
      Rows:=T.Db.Query('SELECT id FROM swimlanes WHERE id='+LaneSql+' AND boardId='+BoardSql+';');
      if Length(Rows)<>1 then begin SendError(aResponse,400,'Swimlane does not belong to this board');Exit;end;
    end else
      LaneSql:='COALESCE((SELECT id FROM swimlanes WHERE boardId='+BoardSql+
        ' ORDER BY archived,sort,id LIMIT 1),'''')';
    Id:=NewId;Stamp:=QuotedStr(NowIso);
    if not T.Db.Exec('BEGIN IMMEDIATE; '+Guard+
      'INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt,modifiedAt) VALUES('+
      QuotedStr(Id)+','+BoardSql+','+LaneSql+','+QuotedStr(Title)+
      ',(SELECT count(*) FROM lists WHERE boardId='+BoardSql+' AND archived=0 AND deletedAt IS NULL),'+Stamp+','+Stamp+'); COMMIT;') then
    begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create list');Exit;end;
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
    Exit;
  end;
  Rows:=T.Db.Query('WITH card_dates AS (SELECT listId,'+
    'max(strftime(''%Y-%m-%dT%H:%M:%fZ'',modifiedAt)) edited,'+
    'max(strftime(''%Y-%m-%dT%H:%M:%fZ'',dateLastActivity)) activity FROM cards WHERE boardId='+BoardSql+
    ' GROUP BY listId) SELECT json_group_array(json(payload)) FROM (SELECT json_object(''_id'',l.id,''title'',l.title,'+
    '''modifiedAt'',strftime(''%Y-%m-%dT%H:%M:%fZ'',l.modifiedAt),'+
    '''cardsModifiedAt'',max(coalesce(d.edited,d.activity),coalesce(d.activity,d.edited))) payload '+
    'FROM lists l LEFT JOIN card_dates d ON d.listId=l.id WHERE l.boardId='+BoardSql+
    ' AND l.archived=0 AND l.deletedAt IS NULL ORDER BY l.sort,l.id);');
  if Length(Rows)=1 then SendJson(aResponse,Rows[0][0])
  else SendError(aResponse,500,'Could not read lists');
end;

procedure ApiList(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"List not found"}';
var T:TWLTenant;UserId,BoardId,ListId:string;Rows:TWLRows;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];ListId:=aRequest.RouteParams['listId'];
  Rows:=T.Db.Query('SELECT json_object(''_id'',id,''boardId'',boardId,''swimlaneId'',swimlaneId,'+
    '''title'',title,''type'',type,''color'',color,''sort'',sort,''width'',width,'+
    '''starred'',json(CASE WHEN starred=1 THEN ''true'' ELSE ''false'' END),''archived'',json(''false''),'+
    '''archivedAt'',archivedAt,''createdAt'',createdAt,''modifiedAt'',modifiedAt,''updatedAt'',updatedAt,'+
    '''wipLimit'',json_object(''value'',wip_value,''enabled'',json(CASE WHEN wip_enabled=1 THEN ''true'' ELSE ''false'' END),'+
    '''soft'',json(CASE WHEN wip_soft=1 THEN ''true'' ELSE ''false'' END))) FROM lists WHERE id='+
    QuotedStr(ListId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL;');
  if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
  SendJson(aResponse,Rows[0][0]);
end;

procedure ApiListEdit(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"List not found"}';
var T:TWLTenant;UserId,BoardId,ListId,Scope,Sets,Permission,Value,Sql:string;
  Body,Reply:TJSONObject;Field,Wip:TJSONData;Rows:TWLRows;Policy:TFieldPolicy;
  Flag,i:Integer;Limit:Int64;Wide:UnicodeString;
  procedure SetColumn(const Column,Literal:string);
  begin
    if Sets<>'' then Sets:=Sets+',';
    Sets:=Sets+Column+'='+Literal;
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];ListId:=aRequest.RouteParams['listId'];
  Scope:='id='+QuotedStr(ListId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL';
  Rows:=T.Db.Query('SELECT id FROM lists WHERE '+Scope+';');
  if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
  Body:=nil;Policy:=nil;Sets:='';Permission:='1';
  try
    try
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then Body:=ExactObject(aRequest.Content)
      else
      begin
        Body:=TJSONObject.Create;
        for i:=0 to aRequest.ContentFields.Count-1 do
          Body.Add(aRequest.ContentFields.Names[i],aRequest.ContentFields.ValueFromIndex[i]);
      end;
      Field:=Body.Find('title');
      if (Field<>nil) and (Field.JSONType<>jtNull) and (Field.AsString<>'') then
      begin
        Value:=Field.AsString;CheckUtf8(Value);
        if Pos(#0,Value)>0 then raise Exception.Create('Invalid title');
        Wide:=UTF8Decode(Value);
        if Length(Wide)>1000 then
        begin
          i:=1000;if Ord(Wide[i]) in [$D800..$DBFF] then Dec(i);
          Value:=UTF8Encode(Copy(Wide,1,i));
        end;
        SetColumn('title',QuotedStr(Value));
      end;
      Field:=Body.Find('color');
      if (Field<>nil) and (Field.JSONType<>jtNull) and (Field.AsString<>'') then
      begin
        Value:=Field.AsString;
        if (ResolveColor(Value)='') or ((Value[1]='#') and (Length(Value)<>7)) or
          ((Value[1]<>'#') and (NormalizeHex(Value)<>'')) then
        begin SendJson(aResponse,'{"error":"Invalid list color. Use a named palette color or a #rrggbb hex value."}',400);Exit;end;
        SetColumn('color',QuotedStr(Value));
      end;
      Field:=Body.Find('starred');
      if Field<>nil then
      begin
        if not DefinitionFlag(Field,Flag) then raise Exception.Create('Invalid starred value');
        SetColumn('starred',IntToStr(Flag));
      end;
      Wip:=Body.Find('wipLimit');
      if (Wip<>nil) and (Wip.JSONType<>jtNull) then
      begin
        if not (Wip is TJSONObject) then raise Exception.Create('Invalid WIP value');
        Field:=TJSONObject(Wip).Find('value');Limit:=1;
        if Field<>nil then
          if not TryStrToInt64(Field.AsJSON,Limit) then raise Exception.Create('Invalid WIP limit');
        SetColumn('wip_value',IntToStr(Limit));
        if not DefinitionFlag(TJSONObject(Wip).Find('enabled'),Flag) then raise Exception.Create('Invalid WIP enabled flag');
        SetColumn('wip_enabled',IntToStr(Flag));
        if not DefinitionFlag(TJSONObject(Wip).Find('soft'),Flag) then raise Exception.Create('Invalid WIP soft flag');
        SetColumn('wip_soft',IntToStr(Flag));
        Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
        Permission:=Policy.ScopeAdminExpression;
      end;
    except SendJson(aResponse,'{"error":"Invalid list update"}',400);Exit;end;
    if Sets='' then begin SendJson(aResponse,'{"message":"Error"}',404);Exit;end;
    SetColumn('modifiedAt',QuotedStr(NowIso));
    Rows:=T.Db.Query('SELECT '+Permission+';');
    if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
    begin SendError(aResponse,403,'Board administration required');Exit;end;
    Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+' AND (SELECT count(*) FROM lists WHERE '+
      Scope+')=1 THEN 1 ELSE json(''List edit scope changed'') END; UPDATE lists SET '+Sets+' WHERE '+Scope+
      '; SELECT CASE WHEN '+Permission+' AND (SELECT count(*) FROM lists WHERE '+Scope+
      ')=1 THEN 1 ELSE json(''List edit scope changed'') END; COMMIT;';
    if not T.Db.Exec(Sql) then
    begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not edit list');Exit;end;
    Reply:=TJSONObject.Create(['_id',ListId]);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  finally Policy.Free;Body.Free;end;
end;

procedure ApiListArchive(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"List not found"}';
var T:TWLTenant;UserId,BoardId,ListId,Scope,Predicate,Stamp,CardArchivedAt,Sql:string;
  Archive:Boolean;Target:string;Rows:TWLRows;Reply:TJSONObject;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  BoardId:=QuotedStr(aRequest.RouteParams['boardId']);ListId:=aRequest.RouteParams['listId'];
  Archive:=Copy(aRequest.PathInfo,Length(aRequest.PathInfo)-9,10)<>'/unarchive';
  Target:=IntToStr(Ord(Archive));
  Scope:='id='+QuotedStr(ListId)+' AND boardId='+BoardId+' AND deletedAt IS NULL';
  Predicate:=Scope+' AND archived='+IntToStr(Ord(not Archive));
  Rows:=T.Db.Query('SELECT id FROM lists WHERE '+Predicate+';');
  if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
  Stamp:=QuotedStr(NowIso);CardArchivedAt:='NULL';
  if Archive then CardArchivedAt:=Stamp;
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+Predicate+
    ')=1 THEN 1 ELSE json(''List archive scope changed'') END; '+
    'UPDATE cards SET archived='+Target+',archivedAt='+CardArchivedAt+' WHERE listId='+QuotedStr(ListId)+
    ' AND boardId='+BoardId+' AND deletedAt IS NULL AND archived<> '+Target+
    ' AND EXISTS(SELECT 1 FROM lists WHERE '+Predicate+' AND type=''template-list''); '+
    'UPDATE lists SET archived='+Target+',modifiedAt='+Stamp;
  if Archive then Sql:=Sql+',archivedAt='+Stamp;
  Sql:=Sql+' WHERE '+Predicate+'; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+Scope+
    ' AND archived='+Target+')=1 THEN 1 ELSE json(''List archive failed'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not change list archive state');Exit;end;
  Reply:=TJSONObject.Create(['_id',ListId,'archived',Archive]);
  try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
end;

procedure ApiCards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId,BoardId,ListId,Id,Author,Title,Descr,Swimlane,Relations,InitialFields:string;
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
  try InitialFields:=InitializeCardFields(T.Db,BoardId,Id);
  except SendError(aResponse,500,'Could not initialize custom fields');Exit;end;
  if not T.Db.Exec('BEGIN IMMEDIATE; '+Format(
    'INSERT INTO cards(id,boardId,listId,swimlaneId,title,description,userId,' +
    'dateLastActivity,createdAt,modifiedAt,sort) ' +
    'VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,0);',
    [QuotedStr(Id), QuotedStr(BoardId), QuotedStr(ListId), QuotedStr(Swimlane),
     QuotedStr(Title), QuotedStr(Descr), QuotedStr(Author),
     QuotedStr(NowIso),QuotedStr(NowIso),QuotedStr(NowIso)])+Relations+InitialFields+' COMMIT;') then
  begin T.Db.Exec('ROLLBACK;'); SendError(aResponse,500,'Could not create card'); Exit; end;
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
end;

// Send one card as JSON (incl. its labelIds). Returns False (and sends 404) if missing.
function ChecklistReadSql(const BoardId,CardId,ChecklistId:string):string;
begin
  Result:='SELECT json_object(''_id'',c.id,''cardId'',c.cardId,''title'',c.title,''sort'',c.sort,''dueAt'',c.dueAt,'+
    '''items'',json((SELECT json_group_array(json(item)) FROM (SELECT json_object(''_id'',i.id,''title'',i.title,'+
    '''isFinished'',json(CASE WHEN i.isFinished=1 THEN ''true'' ELSE ''false'' END),''dueAt'',i.dueAt) item '+
    'FROM checklist_items i WHERE i.checklistId=c.id AND i.cardId=c.cardId AND (i.boardId IS NULL OR i.boardId='+
    QuotedStr(BoardId)+') ORDER BY i.sort,i.id)))) AS payload FROM checklists c WHERE c.cardId='+QuotedStr(CardId)+
    ' AND (c.boardId IS NULL OR c.boardId='+QuotedStr(BoardId)+')';
  if ChecklistId<>'' then Result:=Result+' AND c.id='+QuotedStr(ChecklistId);
  Result:=Result+' ORDER BY c.sort,c.id';
end;

function ChecklistCollectionSql(const BoardId,CardId:string):string;
begin
  Result:='SELECT json_group_array(json(payload)) FROM ('+ChecklistReadSql(BoardId,CardId,'')+');';
end;

const CardNotFound = '{"error":"Card not found"}';

function SendCardById(aResponse: TResponse; Db: TWLDb; const CardId,UserId: string; IncludeChecklists:Boolean=False; const RequiredBoardId:string=''; const ActiveListId:string=''): Boolean;
var ReadSql:string; R, L: TWLRows; O: TJSONObject; A: TJSONArray; i: Integer;Policy:TFieldPolicy;
begin
  Result := False;
  ReadSql:='SELECT id,title,description,listId,swimlaneId,boardId,color FROM cards WHERE deletedAt IS NULL AND id='+QuotedStr(CardId);
  if RequiredBoardId<>'' then ReadSql:=ReadSql+' AND boardId='+QuotedStr(RequiredBoardId);
  if ActiveListId<>'' then ReadSql:=ReadSql+' AND listId='+QuotedStr(ActiveListId)+' AND archived=0';
  R:=Db.Query(ReadSql+' LIMIT 1;');
  if Length(R)=0 then begin SendJson(aResponse,CardNotFound,404);Exit;end;
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
    if IncludeChecklists then
    begin
      L:=Db.Query(ChecklistCollectionSql(R[0][5],CardId));
      if Length(L)<>1 then begin SendError(aResponse,500,'Could not read card checklists');Exit;end;
      O.Add('checklists',GetJSON(L[0][0]));
    end;
    SendJson(aResponse, O.AsJSON);
    Result := True;
  finally O.Free; end;
end;

procedure ApiCard(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId,BoardId,CardId,ListId: string; Rows:TWLRows;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];CardId:=aRequest.RouteParams['cardId'];
  ListId:=aRequest.RouteParams['listId'];
  if BoardId<>'' then
  begin
    if not ApiBoardGuard(T,aRequest,aResponse,UserId,CardNotFound) then Exit;
  end else
  begin
    Rows:=T.Db.Query('SELECT boardId FROM cards WHERE id='+QuotedStr(CardId)+' AND deletedAt IS NULL;');
    if Length(Rows)=0 then begin SendJson(aResponse,CardNotFound,404);Exit;end;
    if (Length(Rows)<>1) or (Rows[0][0]='') then begin SendError(aResponse,403,'Board access forbidden');Exit;end;
    BoardId:=Rows[0][0];
    if not ApiAuthBoard(T,aResponse,UserId,BoardId,False) then Exit;
  end;
  SendCardById(aResponse,T.Db,CardId,UserId,True,BoardId,ListId);
end;

// PUT card — update any of title/description/color and replace labelIds if given.
procedure ApiCardEdit(aRequest:TRequest; aResponse:TResponse);
var T:TWLTenant; UserId,CardId,BoardId,Sets,Relations,Scope,ArchiveSql,Stamp,Value:string;
  HasArchive,Archive,HasEdits:Boolean;Body:TJSONObject;Input:TJSONData;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  CardId:=aRequest.RouteParams['cardId'];BoardId:=aRequest.RouteParams['boardId'];
  HasArchive:=BodyHasField(aRequest,'archive');
  HasEdits:=BodyHasField(aRequest,'title') or BodyHasField(aRequest,'description') or
    BodyHasField(aRequest,'color') or BodyHasField(aRequest,'labelIds') or
    BodyHasField(aRequest,'members') or BodyHasField(aRequest,'assignees');
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  if HasArchive and not HasEdits then
  begin
    if not ApiAuthBoard(T,aResponse,UserId,BoardId,True) then Exit;
    if Length(T.Db.Query('SELECT id FROM cards WHERE '+Scope+';'))<>1 then
    begin SendJson(aResponse,CardNotFound,404);Exit;end;
  end else
  begin
    if not ApiBoardGuard(T,aRequest,aResponse,UserId,CardNotFound) then Exit;
    Scope:=Scope+' AND listId='+QuotedStr(aRequest.RouteParams['listId']);
  end;
  if not CardRelationSql(T,aRequest,aResponse,BoardId,CardId,Relations) then Exit;
  Stamp:=QuotedStr(NowIso);
  ArchiveSql:='';
  if HasArchive then
  begin
    Value:=aRequest.ContentFields.Values['archive'];
    if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
    begin
      Body:=nil;
      try
        try
          Body:=ExactObject(aRequest.Content);Input:=Body.Find('archive');
          if (Input<>nil) and (Input.JSONType in [jtString,jtBoolean]) then Value:=Input.AsString;
        except SendError(aResponse,400,'Invalid card update');Exit;end;
      finally Body.Free;end;
    end;
    Archive:=SameText(Value,'true');
    ArchiveSql:='UPDATE cards SET archived='+IntToStr(Ord(Archive))+' WHERE '+Scope+
      ' AND archived='+IntToStr(Ord(not Archive))+'; ';
  end;
  Sets:='';
  if not HasArchive or HasEdits then
  begin
    Sets:='modifiedAt='+Stamp+',dateLastActivity='+Stamp;
    if BodyHasField(aRequest,'title') then Sets:=Sets+',title='+QuotedStr(BodyField(aRequest,'title'));
    if BodyHasField(aRequest,'description') then Sets:=Sets+',description='+QuotedStr(BodyField(aRequest,'description'));
    if BodyHasField(aRequest,'color') then Sets:=Sets+',color='+QuotedStr(BodyField(aRequest,'color'));
    Sets:='UPDATE cards SET '+Sets+' WHERE '+Scope+'; ';
  end;
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+
    ')=1 THEN 1 ELSE json(''Card edit scope changed'') END; '+Sets+ArchiveSql+Relations+' COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not edit card');Exit;end;
  SendCardById(aResponse,T.Db,CardId,UserId,False,BoardId);
end;

procedure ApiListCards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT id,title FROM cards WHERE listId=%s AND boardId=%s AND archived=0 AND deletedAt IS NULL ORDER BY sort;',
    [QuotedStr(aRequest.RouteParams['listId']),QuotedStr(aRequest.RouteParams['boardId'])]))));
end;

function CountOf(Db: TWLDb; const WhereCol, Id, BoardId: string): Integer;
var R: TWLRows;
begin
  R := Db.Query(Format('SELECT COUNT(*) FROM cards WHERE %s=%s AND boardId=%s AND archived=0 AND deletedAt IS NULL;',
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
    'SELECT id,title FROM cards WHERE swimlaneId=%s AND boardId=%s AND archived=0 AND deletedAt IS NULL ORDER BY sort;',
    [QuotedStr(aRequest.RouteParams['swimlaneId']),QuotedStr(aRequest.RouteParams['boardId'])]))));
end;

function ChecklistDeadlineSql(Value:TJSONData;out Literal:string):Boolean;
const Prefix='0000-00-00T00:00:00';
var Text,Zone:string;Stamp:TDateTime;i,Offset:Integer;
begin
  if Value.JSONType=jtNull then begin Literal:='NULL';Exit(True);end;
  Result:=False;
  if Value.JSONType<>jtString then Exit;
  Text:=Value.AsString;
  if Length(Text)<20 then Exit;
  for i:=1 to Length(Prefix) do
    if Prefix[i]='0' then begin if not (Text[i] in ['0'..'9']) then Exit;end
    else if Text[i]<>Prefix[i] then Exit;
  Offset:=20;
  if Text[Offset]='.' then
  begin
    Inc(Offset);
    while (Offset<=Length(Text)) and (Text[Offset] in ['0'..'9']) do Inc(Offset);
    if (Offset<22) or (Offset>24) then Exit;
  end;
  Zone:=Copy(Text,Offset,MaxInt);
  if Zone<>'Z' then
  begin
    if Length(Zone)<>6 then Exit;
    if not (Zone[1] in ['+','-']) or (Zone[4]<>':') then Exit;
    for i in [2,3,5,6] do if not (Zone[i] in ['0'..'9']) then Exit;
    if (StrToInt(Copy(Zone,2,2))>23) or (StrToInt(Copy(Zone,5,2))>59) then Exit;
  end;
  try
    if not TryISO8601ToDate(Text,Stamp,True) then Exit;
    Literal:=QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',Stamp));
    Result:=True;
  except Result:=False;end;
end;

// GET checklists of a card / POST create a checklist
procedure ApiCardChecklists(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, CardId, Title, Id, Due, Sql, Stamp, ItemTitle: string;
  Body:TJSONObject;Value,Items,Item:TJSONData;i,Count:Integer;Rows:TWLRows;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  CardId  := aRequest.RouteParams['cardId'];
  if aRequest.Method = 'POST' then
  begin
    Body:=nil;
    try
      try
        if Pos('application/json',LowerCase(aRequest.ContentType))=1 then Body:=ExactObject(aRequest.Content)
        else
        begin
          Body:=TJSONObject.Create;
          for i:=0 to aRequest.ContentFields.Count-1 do
            Body.Add(aRequest.ContentFields.Names[i],aRequest.ContentFields.ValueFromIndex[i]);
        end;
        Title:='Checklist';Value:=Body.Find('title');
        if Value<>nil then
        begin
          if (Value.JSONType<>jtString) or (Trim(Value.AsString)='') or (Pos(#0,Value.AsString)>0) then
            raise Exception.Create('Invalid checklist title');
          Title:=Value.AsString;
        end;
        Due:='NULL';Value:=Body.Find('dueAt');
        if (Value<>nil) and not ChecklistDeadlineSql(Value,Due) then raise Exception.Create('Invalid deadline');
        Items:=Body.Find('items');Count:=0;
        if (Items<>nil) and (Items.JSONType<>jtNull) then
          case Items.JSONType of
            jtArray: Count:=Items.Count;
            jtString: if Items.AsString<>'' then Count:=1;
            else raise Exception.Create('Invalid checklist items');
          end;
        Id:=NewId;Stamp:=QuotedStr(NowIso);
        Sql:='BEGIN IMMEDIATE; INSERT INTO checklists(id,cardId,boardId,title,sort,createdAt,modifiedAt,dueAt) VALUES('+
          QuotedStr(Id)+','+QuotedStr(CardId)+','+QuotedStr(BoardId)+','+QuotedStr(Title)+',0,'+Stamp+','+Stamp+','+Due+'); ';
        for i:=0 to Count-1 do
        begin
          Item:=Items;if Items.JSONType=jtArray then Item:=Items.Items[i];
          if (Item.JSONType<>jtString) or (Pos(#0,Item.AsString)>0) then raise Exception.Create('Invalid checklist item');
          ItemTitle:=Item.AsString;
          Sql:=Sql+'INSERT INTO checklist_items(id,checklistId,cardId,boardId,title,sort,createdAt,modifiedAt) VALUES('+
            QuotedStr(NewId)+','+QuotedStr(Id)+','+QuotedStr(CardId)+','+QuotedStr(BoardId)+','+
            QuotedStr(ItemTitle)+','+IntToStr(i)+','+Stamp+','+Stamp+'); ';
        end;
      except SendJson(aResponse,'{"error":"Invalid checklist title, items or dueAt"}',400);Exit;end;
      if not T.Db.Exec(Sql+'COMMIT;') then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create checklist');Exit;end;
      SendJson(aResponse,Format('{"_id":%s}',[AnsiQuotedStr(Id,'"')]));
    finally Body.Free;end;
    Exit;
  end;
  Rows:=T.Db.Query(ChecklistCollectionSql(BoardId,CardId));
  if Length(Rows)=1 then SendJson(aResponse,Rows[0][0])
  else SendError(aResponse,500,'Could not read checklists');
end;

function ChecklistChanges(Request:TRequest;out Changes:string;ItemUpdate:Boolean=False):Boolean;
var Body:TJSONObject;Title,Deadline,Finished:TJSONData;Literal:string;
begin
  Changes:='';Result:=False;Body:=nil;
  try
    try
      if Pos('application/json',LowerCase(Request.ContentType))=1 then Body:=ExactObject(Request.Content)
      else
      begin
        Body:=TJSONObject.Create;
        if Request.ContentFields.IndexOfName('title')>=0 then Body.Add('title',Request.ContentFields.Values['title']);
        if Request.ContentFields.IndexOfName('isFinished')>=0 then Body.Add('isFinished',Request.ContentFields.Values['isFinished']);
        if Request.ContentFields.IndexOfName('dueAt')>=0 then Body.Add('dueAt',Request.ContentFields.Values['dueAt']);
      end;
      Title:=Body.Find('title');Deadline:=Body.Find('dueAt');
      if Title<>nil then
      begin
        if (Title.JSONType<>jtString) or (Trim(Title.AsString)='') or (Pos(#0,Title.AsString)>0) then Exit;
        Changes:='title='+QuotedStr(Title.AsString);
      end;
      if Deadline<>nil then
      begin
        if not ChecklistDeadlineSql(Deadline,Literal) then Exit;
        if Changes<>'' then Changes:=Changes+',';
        Changes:=Changes+'dueAt='+Literal;
      end;
      Finished:=Body.Find('isFinished');
      if ItemUpdate and (Finished<>nil) then
      begin
        if not (LowerCase(Finished.AsString)='true') and not (LowerCase(Finished.AsString)='false') and
          not (Finished.AsString='0') and not (Finished.AsString='1') then Exit;
        if Changes<>'' then Changes:=Changes+',';
        Changes:=Changes+'isFinished='+IntToStr(BoolInt(Finished.AsString));
      end;
      Result:=ItemUpdate or (Changes<>'');
    except Result:=False;end;
  finally Body.Free;end;
end;

// GET one checklist with its items
procedure ApiChecklist(aRequest: TRequest; aResponse: TResponse);
const NotFound = '{"error":"Checklist not found or does not belong to the specified card"}';
var T: TWLTenant; UserId, ChecklistId, Predicate, Changes, Statement, FinalCheck: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId, NotFound) then Exit;
  ChecklistId := aRequest.RouteParams['checklistId'];
  if aRequest.Method <> 'GET' then
  begin
    Predicate := 'id='+QuotedStr(ChecklistId)+' AND cardId='+QuotedStr(aRequest.RouteParams['cardId'])+
      ' AND (boardId IS NULL OR boardId='+QuotedStr(aRequest.RouteParams['boardId'])+')';
    if aRequest.Method='PUT' then
    begin
      if not ChecklistChanges(aRequest,Changes) then
      begin SendJson(aResponse,'{"error":"Valid title or dueAt is required"}',400);Exit;end;
      Statement:='UPDATE checklists SET '+Changes+' WHERE '+Predicate;
      FinalCheck:='(SELECT count(*) FROM checklists WHERE '+Predicate+')=1';
    end else
    begin
      Statement:='DELETE FROM checklists WHERE '+Predicate;
      FinalCheck:='NOT EXISTS(SELECT 1 FROM checklists WHERE '+Predicate+')';
    end;
    if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM checklists WHERE '+
      Predicate+')=1 THEN 1 ELSE json(''Checklist scope changed'') END; '+Statement+
      '; SELECT CASE WHEN '+FinalCheck+' THEN 1 ELSE json(''Checklist write failed'') END; COMMIT;') then
    begin T.Db.Exec('ROLLBACK;'); SendError(aResponse,500,'Could not change checklist');Exit;end;
    O:=TJSONObject.Create(['_id',ChecklistId]);
    try SendJson(aResponse,O.AsJSON);finally O.Free;end;
    Exit;
  end;
  R:=T.Db.Query(ChecklistReadSql(aRequest.RouteParams['boardId'],aRequest.RouteParams['cardId'],ChecklistId)+';');
  if Length(R)=1 then SendJson(aResponse,R[0][0])
  else SendJson(aResponse,NotFound,404);
end;

// POST add an item to a checklist
procedure ApiChecklistItems(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, CardId, ChecklistId, Title, Id, Due: string;
  Body:TJSONObject;Value:TJSONData;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId     := aRequest.RouteParams['boardId'];
  CardId      := aRequest.RouteParams['cardId'];
  ChecklistId := aRequest.RouteParams['checklistId'];
  Title:=BodyField(aRequest,'title');Due:='NULL';Body:=nil;
  try
    try
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
      begin
        Body:=ExactObject(aRequest.Content);
        Value:=Body.Find('title');
        if (Value=nil) or (Value.JSONType<>jtString) then raise Exception.Create('Invalid item title');
        Title:=Value.AsString;
        Value:=Body.Find('dueAt');
        if (Value<>nil) and not ChecklistDeadlineSql(Value,Due) then raise Exception.Create('Invalid deadline');
      end else if aRequest.ContentFields.IndexOfName('dueAt')>=0 then
      begin
        Value:=TJSONString.Create(aRequest.ContentFields.Values['dueAt']);
        try
          if not ChecklistDeadlineSql(Value,Due) then raise Exception.Create('Invalid deadline');
        finally Value.Free;end;
      end;
      if (Trim(Title)='') or (Pos(#0,Title)>0) then raise Exception.Create('Invalid item title');
    except SendJson(aResponse,'{"error":"Invalid item title or dueAt"}',400);Exit;end;
  finally Body.Free;end;
  Id := NewId;
  if not T.Db.Exec(Format(
    'BEGIN IMMEDIATE; INSERT INTO checklist_items(id,checklistId,cardId,boardId,title,sort,createdAt,modifiedAt,dueAt) ' +
    'VALUES(%s,%s,%s,%s,%s,0,%s,%s,%s); COMMIT;',
    [QuotedStr(Id), QuotedStr(ChecklistId), QuotedStr(CardId), QuotedStr(BoardId),
     QuotedStr(Title), QuotedStr(NowIso), QuotedStr(NowIso),Due])) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create checklist item');Exit;end;
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
end;

// GET item / PUT toggle-or-edit (isFinished/title) / DELETE a checklist item
procedure ApiChecklistItem(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, ItemId, Changes, Predicate: string; R: TWLRows; O: TJSONObject;
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
    if not ChecklistChanges(aRequest,Changes,True) then
    begin SendJson(aResponse,'{"error":"Invalid checklist item update"}',400);Exit;end;
    if Changes<>'' then
    begin
      Predicate:='id='+QuotedStr(ItemId)+' AND checklistId='+QuotedStr(aRequest.RouteParams['checklistId'])+
        ' AND cardId='+QuotedStr(aRequest.RouteParams['cardId'])+' AND (boardId IS NULL OR boardId='+QuotedStr(aRequest.RouteParams['boardId'])+')';
      if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM checklist_items WHERE '+
        Predicate+')=1 THEN 1 ELSE json(''Checklist item scope changed'') END; UPDATE checklist_items SET '+
        Changes+',modifiedAt='+QuotedStr(NowIso)+' WHERE '+Predicate+'; COMMIT;') then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not update checklist item');Exit;end;
    end;
    O:=TJSONObject.Create(['_id',ItemId]);
    try SendJson(aResponse,O.AsJSON);finally O.Free;end;
    Exit;
  end;
  R := T.Db.Query(Format('SELECT id,title,isFinished,dueAt FROM checklist_items WHERE id=%s LIMIT 1;',
    [QuotedStr(ItemId)]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'Item not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('title', R[0][1]); O.Add('isFinished', R[0][2] = '1');
    if R[0][3]='' then O.Add('dueAt',TJSONNull.Create) else O.Add('dueAt',R[0][3]);
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
var T:TWLTenant;UserId,CardId,BoardId,LegacyValue,Scope,Predicate,Stamp,ArchivedAt:string;
  Legacy,Archive:Boolean;Rows:TWLRows;Reply:TJSONObject;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,CardNotFound) then Exit;
  CardId:=aRequest.RouteParams['cardId'];BoardId:=aRequest.RouteParams['boardId'];
  Archive:=Copy(aRequest.PathInfo,Length(aRequest.PathInfo)-9,10)<>'/unarchive';
  LegacyValue:=BodyField(aRequest,'isArchive');Legacy:=Archive and (LegacyValue<>'');
  if Legacy then Archive:=BoolInt(LegacyValue)=1;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+
    ' AND listId='+QuotedStr(aRequest.RouteParams['listId']);
  Predicate:=Scope;
  if not Legacy then Predicate:=Predicate+' AND archived='+IntToStr(Ord(not Archive));
  Rows:=T.Db.Query('SELECT id FROM cards WHERE '+Predicate+';');
  if Length(Rows)<>1 then begin SendJson(aResponse,CardNotFound,404);Exit;end;
  Stamp:=NowIso;ArchivedAt:='NULL';
  if Archive then ArchivedAt:=QuotedStr(Stamp);
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Predicate+
    ')=1 THEN 1 ELSE json(''Archive scope changed'') END; UPDATE cards SET archived='+IntToStr(Ord(Archive))+
    ',archivedAt='+ArchivedAt+',modifiedAt='+QuotedStr(Stamp)+' WHERE '+Predicate+
    '; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+' AND archived='+IntToStr(Ord(Archive))+
    ')=1 THEN 1 ELSE json(''Archive write failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not change card archive state');Exit;end;
  if Legacy then SendCardById(aResponse,T.Db,CardId,UserId,False,BoardId)
  else
  begin
    Reply:=TJSONObject.Create(['_id',CardId,'archived',Archive]);
    try
      if Archive then Reply.Add('archivedAt',Stamp);
      SendJson(aResponse,Reply.AsJSON);
    finally Reply.Free;end;
  end;
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
procedure ApiListDelete(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"List not found"}';
var T:TWLTenant;UserId,ListId,BoardId,Scope,CardScope,Markers,Batch,BatchId,Sql,Stamp:string;Reply:TJSONObject;Position:TWLRows;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  ListId:=aRequest.RouteParams['listId'];BoardId:=QuotedStr(aRequest.RouteParams['boardId']);
  BatchId:=NewId;Batch:=QuotedStr(BatchId);Stamp:=NowIso;
  Markers:='deletedAt='+QuotedStr(Stamp)+',deletedBy='+QuotedStr(UserId)+',deleteBatchId='+Batch;
  Scope:='id='+QuotedStr(ListId)+' AND boardId='+BoardId;
  Position:=T.Db.Query('SELECT swimlaneId,sort FROM lists WHERE '+Scope+' AND deletedAt IS NULL;');
  CardScope:='listId='+QuotedStr(ListId)+' AND boardId='+BoardId+' AND deletedAt IS NULL';
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+Scope+
    ' AND deletedAt IS NULL)=1 THEN 1 ELSE json(''List delete scope changed'') END; '+
    'UPDATE cards SET '+Markers+' WHERE '+CardScope+'; UPDATE lists SET '+Markers+
    ' WHERE '+Scope+' AND deletedAt IS NULL; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+
    Scope+' AND deleteBatchId='+Batch+')=1 AND NOT EXISTS(SELECT 1 FROM cards WHERE '+CardScope+
    ') THEN 1 ELSE json(''Could not mark list and cards deleted'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not delete list');Exit;end;
  if Length(Position)=1 then
    try RecordListPosition(T.Db,UserId,aRequest.RouteParams['boardId'],ListId,BatchId,
      Stamp,Position[0],False);except end;
  Reply:=TJSONObject.Create(['_id',ListId]);
  try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
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
