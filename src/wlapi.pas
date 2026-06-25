unit wlapi;

{
  WeKan-Lite — REST API (subset of public/api/wekan.yml), so the WeKan Python CLI api.py works
  against the FreePascal server unchanged.

  Auth (as api.py does it):
    POST /users/login   JSON {username,password}     -> {"id","token","tokenExpires"}
    then every /api/... request sends  Authorization: Bearer <token>

  Tokens are persisted in schema.sql login_tokens (hashedToken = HashText(token)), the same
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

  v0.1 reference skeleton. Password check is still placeholder (same TODO as the web sign-in).
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, Classes, HTTPDefs, fpjson, jsonparser, DateUtils, base64,
  wldb, wltenant, wlauth, wlpassword;

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
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Now);
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

// Resolve the tenant for an API request, or send a JSON error. Static, no web session needed.
function ApiTenant(aRequest: TRequest; aResponse: TResponse; out T: TWLTenant): Boolean;
begin
  Result := ResolveTenant(aRequest, T) and TenantOpen(T);
  if not Result then
    SendError(aResponse, 404, 'Unknown domain');
end;

// Bearer token -> userId via login_tokens; sends 401 JSON if missing/invalid.
function ApiAuth(const T: TWLTenant; aRequest: TRequest; aResponse: TResponse;
  out UserId: string): Boolean;
var
  Hdr, Token: string;
  R: TWLRows;
begin
  Result := False; UserId := '';
  Hdr := aRequest.Authorization;
  if Hdr = '' then Hdr := aRequest.CustomHeaders.Values['Authorization'];
  if Pos('Bearer ', Hdr) = 1 then Token := Trim(Copy(Hdr, 8, Length(Hdr)))
  else Token := Trim(aRequest.QueryFields.Values['token']);   // ?token= fallback
  if Token = '' then begin SendError(aResponse, 401, 'No token'); Exit; end;

  R := T.Db.Query(Format(
    'SELECT userId FROM login_tokens WHERE hashedToken=%s AND ' +
    '(expiresAt IS NULL OR expiresAt > %s) LIMIT 1;',
    [QuotedStr(HashText(Token)), QuotedStr(NowIso)]));
  if (Length(R) = 0) or (Length(R[0]) = 0) then
  begin SendError(aResponse, 401, 'Invalid token'); Exit; end;
  UserId := R[0][0];
  Result := True;
end;

function IsSiteAdmin(Db: TWLDb; const UserId: string): Boolean;
var R: TWLRows;
begin
  R := Db.Query(Format('SELECT isAdmin FROM users WHERE id=%s LIMIT 1;', [QuotedStr(UserId)]));
  Result := (Length(R) > 0) and (Length(R[0]) > 0) and (R[0][0] = '1');
end;

// Authorize the user for a board: site admin → always; active member → yes (write blocked if
// read-only); public board → read only. Sends 403 and returns False otherwise.
function ApiAuthBoard(const T: TWLTenant; aResponse: TResponse;
  const UserId, BoardId: string; NeedWrite: Boolean): Boolean;
var R: TWLRows; ReadOnly: Boolean;
begin
  Result := False;
  if IsSiteAdmin(T.Db, UserId) then Exit(True);
  R := T.Db.Query(Format(
    'SELECT isReadOnly FROM board_members WHERE boardId=%s AND userId=%s AND isActive=1 LIMIT 1;',
    [QuotedStr(BoardId), QuotedStr(UserId)]));
  if Length(R) > 0 then
  begin
    ReadOnly := (Length(R[0]) > 0) and (R[0][0] = '1');
    if NeedWrite and ReadOnly then begin SendError(aResponse, 403, 'Read-only on this board'); Exit; end;
    Exit(True);
  end;
  if not NeedWrite then
  begin
    R := T.Db.Query(Format('SELECT 1 FROM boards WHERE id=%s AND permission=''public'' LIMIT 1;',
      [QuotedStr(BoardId)]));
    if Length(R) > 0 then Exit(True);
  end;
  SendError(aResponse, 403, 'Not a member of this board');
end;

// Common guard for board-scoped endpoints: boardId from the route, write = non-GET.
function ApiBoardGuard(const T: TWLTenant; aRequest: TRequest; aResponse: TResponse;
  const UserId: string): Boolean;
begin
  Result := ApiAuthBoard(T, aResponse, UserId, aRequest.RouteParams['boardId'],
    aRequest.Method <> 'GET');
end;

// read a form OR json field from the request body
function BodyField(aRequest: TRequest; const Name: string): string;
var D: TJSONData;
begin
  Result := aRequest.ContentFields.Values[Name];
  if Result <> '' then Exit;
  if (aRequest.Content <> '') and (aRequest.Content[1] = '{') then
    try
      D := GetJSON(aRequest.Content);
      try
        if D is TJSONObject then Result := TJSONObject(D).Get(Name, '');
      finally D.Free; end;
    except end;
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
  Username, Password, Token, Hashed, UserId: string;
  R: TWLRows;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  Username := BodyField(aRequest, 'username');
  if Username = '' then Username := BodyField(aRequest, 'email');
  Password := BodyField(aRequest, 'password');

  R := T.Db.Query(Format(
    'SELECT id, COALESCE(json_extract(services_json,''$.password''),'''') ' +
    'FROM users WHERE username=%s LIMIT 1;', [QuotedStr(Username)]));
  if (Length(R) = 0) or (Length(R[0]) < 2) or (not VerifyPassword(Password, R[0][1])) then
  begin SendError(aResponse, 401, 'Incorrect username or password'); Exit; end;
  UserId := R[0][0];

  Token := NewId + NewId;                       // opaque bearer token
  Hashed := HashText(Token);
  T.Db.Exec(Format(
    'INSERT INTO login_tokens(hashedToken,userId,createdAt,expiresAt) VALUES(%s,%s,%s,%s);',
    [QuotedStr(Hashed), QuotedStr(UserId), QuotedStr(NowIso),
     QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', IncDay(Now, 90)))]));

  SendJson(aResponse, Format('{"id":%s,"token":%s,"tokenExpires":%s}',
    [AnsiQuotedStr(UserId, '"'), AnsiQuotedStr(Token, '"'),
     AnsiQuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', IncDay(Now, 90)), '"')]));
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

// GET board custom fields / POST create a custom field
procedure ApiCustomFields(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, Id, Name, Typ: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  if aRequest.Method = 'POST' then
  begin
    Name := BodyField(aRequest, 'name');
    Typ  := BodyField(aRequest, 'type'); if Typ = '' then Typ := 'text';
    Id := NewId;
    T.Db.Exec(Format(
      'INSERT INTO custom_fields(id,name,type,showOnCard,automaticallyOnCard,' +
      'showLabelOnMiniCard,showSumAtTopOfList,createdAt,modifiedAt) ' +
      'VALUES(%s,%s,%s,%d,%d,%d,%d,%s,%s);',
      [QuotedStr(Id), QuotedStr(Name), QuotedStr(Typ),
       BoolInt(BodyField(aRequest, 'showoncard')), BoolInt(BodyField(aRequest, 'automaticallyoncard')),
       BoolInt(BodyField(aRequest, 'showlabelonminicard')), BoolInt(BodyField(aRequest, 'showsumattopoflist')),
       QuotedStr(NowIso), QuotedStr(NowIso)]));
    T.Db.Exec(Format('INSERT INTO custom_field_boards(customFieldId,boardId) VALUES(%s,%s);',
      [QuotedStr(Id), QuotedStr(BoardId)]));
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
    Exit;
  end;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT cf.id, cf.name FROM custom_fields cf ' +
    'JOIN custom_field_boards b ON b.customFieldId=cf.id WHERE b.boardId=%s ORDER BY cf.name;',
    [QuotedStr(BoardId)]))));
end;

procedure ApiCustomField(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  R := T.Db.Query(Format('SELECT id,name,type FROM custom_fields WHERE id=%s LIMIT 1;',
    [QuotedStr(aRequest.RouteParams['customField'])]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'Custom field not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('name', R[0][1]); O.Add('type', R[0][2]);
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

// POST set a card's value for a custom field
procedure ApiCardCustomField(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, CardId, CfId, Value: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  CardId := aRequest.RouteParams['cardId'];
  CfId   := aRequest.RouteParams['customField'];
  Value  := BodyField(aRequest, 'value');
  T.Db.Exec(Format(
    'INSERT OR REPLACE INTO card_custom_field_values(cardId,customFieldId,value) VALUES(%s,%s,%s);',
    [QuotedStr(CardId), QuotedStr(CfId), QuotedStr(Value)]));
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(CardId, '"')]));
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
var T: TWLTenant; UserId, BoardId, ListId, Id, Author, Title, Descr, Swimlane: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  if aRequest.Method <> 'POST' then begin SendError(aResponse, 405, 'Use POST'); Exit; end;
  BoardId  := aRequest.RouteParams['boardId'];
  ListId   := aRequest.RouteParams['listId'];
  Author   := BodyField(aRequest, 'authorId'); if Author = '' then Author := UserId;
  Title    := BodyField(aRequest, 'title');
  Descr    := BodyField(aRequest, 'description');
  Swimlane := BodyField(aRequest, 'swimlaneId');
  Id := NewId;
  T.Db.Exec(Format(
    'INSERT INTO cards(id,boardId,listId,swimlaneId,title,description,userId,' +
    'dateLastActivity,createdAt,modifiedAt,sort) ' +
    'VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,0);',
    [QuotedStr(Id), QuotedStr(BoardId), QuotedStr(ListId), QuotedStr(Swimlane),
     QuotedStr(Title), QuotedStr(Descr), QuotedStr(Author),
     QuotedStr(NowIso), QuotedStr(NowIso), QuotedStr(NowIso)]));
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
end;

// Send one card as JSON (incl. its labelIds). Returns False (and sends 404) if missing.
function SendCardById(aResponse: TResponse; Db: TWLDb; const CardId: string): Boolean;
var R, L: TWLRows; O, CFO: TJSONObject; A: TJSONArray; i: Integer;
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
    A := TJSONArray.Create;                          // customFields: [{_id, value}]
    L := Db.Query(Format(
      'SELECT customFieldId,value FROM card_custom_field_values WHERE cardId=%s;', [QuotedStr(CardId)]));
    for i := 0 to High(L) do
      if Length(L[i]) >= 2 then
      begin
        CFO := TJSONObject.Create;
        CFO.Add('_id', L[i][0]); CFO.Add('value', L[i][1]);
        A.Add(CFO);
      end;
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
  SendCardById(aResponse, T.Db, aRequest.RouteParams['cardId']);
end;

// PUT card — update any of title/description/color and replace labelIds if given.
procedure ApiCardEdit(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; UserId, CardId, Title, Descr, Color, LabelIds, Sets: string;
  Parts: TStringArray; i: Integer;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  CardId := aRequest.RouteParams['cardId'];

  Title := BodyField(aRequest, 'title');
  Descr := BodyField(aRequest, 'description');
  Color := BodyField(aRequest, 'color');
  Sets  := 'modifiedAt=' + QuotedStr(NowIso) + ', dateLastActivity=' + QuotedStr(NowIso);
  if Title <> '' then Sets := Sets + ', title=' + QuotedStr(Title);
  if Descr <> '' then Sets := Sets + ', description=' + QuotedStr(Descr);
  if Color <> '' then Sets := Sets + ', color=' + QuotedStr(Color);
  T.Db.Exec(Format('UPDATE cards SET %s WHERE id=%s;', [Sets, QuotedStr(CardId)]));

  LabelIds := BodyField(aRequest, 'labelIds');
  if LabelIds <> '' then
  begin
    T.Db.Exec(Format('DELETE FROM card_labels WHERE cardId=%s;', [QuotedStr(CardId)]));
    Parts := StringReplace(LabelIds, ' ', '', [rfReplaceAll]).Split([',']);
    for i := 0 to High(Parts) do
      if Parts[i] <> '' then
        T.Db.Exec(Format('INSERT OR IGNORE INTO card_labels(cardId,labelId) VALUES(%s,%s);',
          [QuotedStr(CardId), QuotedStr(Parts[i])]));
  end;

  SendCardById(aResponse, T.Db, CardId);
end;

procedure ApiListCards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT id,title FROM cards WHERE listId=%s AND archived=0 ORDER BY sort;',
    [QuotedStr(aRequest.RouteParams['listId'])]))));
end;

function CountOf(Db: TWLDb; const WhereCol, Id: string): Integer;
var R: TWLRows;
begin
  R := Db.Query(Format('SELECT COUNT(*) FROM cards WHERE %s=%s AND archived=0;',
    [WhereCol, QuotedStr(Id)]));
  if (Length(R) > 0) and (Length(R[0]) > 0) then Result := StrToIntDef(R[0][0], 0) else Result := 0;
end;

procedure ApiListCardsCount(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, Format('{"list_cards_count":%d}',
    [CountOf(T.Db, 'listId', aRequest.RouteParams['listId'])]));
end;

procedure ApiBoardCardsCount(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, Format('{"board_cards_count":%d}',
    [CountOf(T.Db, 'boardId', aRequest.RouteParams['boardId'])]));
end;

procedure ApiSwimlaneCards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT id,title FROM cards WHERE swimlaneId=%s AND archived=0 ORDER BY sort;',
    [QuotedStr(aRequest.RouteParams['swimlaneId'])]))));
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
var T: TWLTenant; UserId, CardId, MemberId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  CardId := aRequest.RouteParams['cardId'];
  MemberId := aRequest.RouteParams['member'];
  if aRequest.Method = 'DELETE' then
    T.Db.Exec(Format('DELETE FROM card_members WHERE cardId=%s AND userId=%s;',
      [QuotedStr(CardId), QuotedStr(MemberId)]))
  else
    T.Db.Exec(Format('INSERT OR IGNORE INTO card_members(cardId,userId) VALUES(%s,%s);',
      [QuotedStr(CardId), QuotedStr(MemberId)]));
  SendCardById(aResponse, T.Db, CardId);
end;

// POST add / DELETE remove a card assignee (userId in the path).
procedure ApiCardAssignee(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, CardId, AssigneeId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  CardId := aRequest.RouteParams['cardId'];
  AssigneeId := aRequest.RouteParams['assignee'];
  if aRequest.Method = 'DELETE' then
    T.Db.Exec(Format('DELETE FROM card_assignees WHERE cardId=%s AND userId=%s;',
      [QuotedStr(CardId), QuotedStr(AssigneeId)]))
  else
    T.Db.Exec(Format('INSERT OR IGNORE INTO card_assignees(cardId,userId) VALUES(%s,%s);',
      [QuotedStr(CardId), QuotedStr(AssigneeId)]));
  SendCardById(aResponse, T.Db, CardId);
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
  SendCardById(aResponse, T.Db, CardId);
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
  T.Db.Exec(Format('DELETE FROM cards WHERE listId=%s;', [QuotedStr(ListId)]));
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
  T.Db.Exec(Format('DELETE FROM cards WHERE swimlaneId=%s;', [QuotedStr(SwimlaneId)]));
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

// ---- attachments: metadata in `attachments`, bytes in files/attachments/<id> --------------
function AttachDir(const T: TWLTenant): string;
begin
  Result := T.FilesDir + 'attachments' + PathDelim;
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
    Bytes := DecodeStringBase64(O.Get('fileData', ''));
    Id := NewId;
    ForceDirectories(AttachDir(T));
    WriteFileBytes(AttachDir(T) + Id, Bytes);
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
  Bytes := ReadFileBytes(AttachDir(T) + Id);
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
  if FileExists(AttachDir(T) + Id) then DeleteFile(AttachDir(T) + Id);
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
