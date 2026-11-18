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
procedure ApiLogout(aRequest:TRequest;aResponse:TResponse);
procedure ApiMyCards(aRequest:TRequest;aResponse:TResponse);
procedure ApiUser(aRequest: TRequest; aResponse: TResponse);
procedure ApiDeleteUser(aRequest:TRequest;aResponse:TResponse);
procedure ApiUsers(aRequest: TRequest; aResponse: TResponse);
procedure ApiPublicBoards(aRequest: TRequest; aResponse: TResponse);
procedure ApiUserBoards(aRequest: TRequest; aResponse: TResponse);
procedure ApiBoard(aRequest: TRequest; aResponse: TResponse);
procedure ApiAddBoardMember(aRequest:TRequest;aResponse:TResponse);
procedure ApiRemoveBoardMember(aRequest:TRequest;aResponse:TResponse);
procedure ApiBoardCardSettings(aRequest:TRequest;aResponse:TResponse);
procedure ApiBoardTitle(aRequest: TRequest; aResponse: TResponse);    // PUT board title
procedure ApiDeleteRule(aRequest:TRequest;aResponse:TResponse);
procedure ApiEditRule(aRequest:TRequest;aResponse:TResponse);
procedure ApiCreateRule(aRequest:TRequest;aResponse:TResponse);
procedure ApiBoardRules(aRequest:TRequest;aResponse:TResponse);
procedure ApiBoardExport(aRequest:TRequest;aResponse:TResponse);
procedure BrowserBoardExport(aRequest:TRequest;aResponse:TResponse);
procedure ApiImportBoard(aRequest:TRequest;aResponse:TResponse);
procedure ApiCreateBoard(aRequest:TRequest;aResponse:TResponse);
procedure ApiBoardCopy(aRequest: TRequest; aResponse: TResponse);     // POST copy board
procedure ApiSwimlane(aRequest:TRequest;aResponse:TResponse);
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
procedure ApiCopyCard(aRequest:TRequest;aResponse:TResponse);
procedure ApiBulkCards(aRequest:TRequest;aResponse:TResponse);
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
procedure ApiBulkCardLabels(aRequest:TRequest;aResponse:TResponse);
procedure ApiBulkCardDelete(aRequest:TRequest;aResponse:TResponse);
procedure ApiCardDelete(aRequest: TRequest; aResponse: TResponse);     // DELETE card
procedure ApiListDelete(aRequest: TRequest; aResponse: TResponse);     // DELETE list (+ its cards)
procedure ApiBoardDelete(aRequest: TRequest; aResponse: TResponse);    // DELETE board (cascade)
procedure ApiSwimlaneDelete(aRequest: TRequest; aResponse: TResponse); // DELETE swimlane (+ its cards)

implementation
uses wlstore,wlsjson,Math,wlcfjson,wlcfpol,wlpath,wlcfspec,wlselscp,wlcolors,wlposhis,wlrevoke,wlautsrc,wli18n,wllocale,wlselect,wlferr;

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

function BearerToken(Request:TRequest):string;
var Header:string;
begin
  Header:=Request.Authorization;
  if Header='' then Header:=Request.CustomHeaders.Values['Authorization'];
  Result:='';
  if Pos('Bearer ',Header)=1 then Result:=Trim(Copy(Header,8,Length(Header)));
end;

// Bearer token -> userId via login_tokens; sends 401 JSON if missing/invalid.
function ApiAuth(const T: TWLTenant; aRequest: TRequest; aResponse: TResponse;
  out UserId: string): Boolean;
var
  Token:string;
begin
  Result:=False;UserId:='';
  Token:=BearerToken(aRequest);
  if (Token='') and (Pos('Bearer ',aRequest.Authorization)<>1) and
    (Pos('Bearer ',aRequest.CustomHeaders.Values['Authorization'])<>1) then
    Token:=Trim(aRequest.QueryFields.Values['token']);
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
function ReadBodyIds(Request:TRequest; const Name:string; Ids:TStrings; AllowNull:Boolean=False;Entry:TJSONObject=nil):Boolean;
var D,V:TJSONData; A:TJSONArray; i:Integer; Text,Id:string; Parts:TStringArray;
begin
  Result:=False; D:=nil; Text:='';
  try
    try
      if (Entry=nil) and (Request.ContentFields.IndexOfName(Name)>=0) then Text:=Request.ContentFields.Values[Name]
      else
      begin
        if Entry=nil then
        begin
          D:=GetJSON(Request.Content);
          if not (D is TJSONObject) then Exit;
          Entry:=TJSONObject(D);
        end;
        V:=Entry.Find(Name); if V=nil then Exit;
        if AllowNull and (V.JSONType=jtNull) then Exit(True);
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
function InitializeSharedAssignments(Db:TWLDb;const BoardId,CardId:string;Members,Assignees:Boolean):string;
const Doc='_ferretdb_sjson';
var Rows:TWLRows;Scope:TSelectionScope;I:Integer;Name,TableName,Match,Path,Value:string;
begin
  Result:='';
  if not (Members or Assignees) then Exit;
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''cards'';');
  if Length(Rows)<>1 then raise Exception.Create('Missing card source');
  if Rows[0][0]='table' then Exit;
  Scope:=TSelectionScope.Create(Db);
  try
    Scope.StringField('cards','id');
    for I:=0 to Scope.Bindings.Count-1 do Result:=Result+Scope.Bindings[I];
  finally Scope.Free;end;
  Rows:=Db.Query('SELECT m.table_name FROM _wl_models m JOIN _ferretdb_collections c ON m.table_name=c.table_name '+
    'WHERE m.name=''cards'' AND c.name=''cards'';');
  if Length(Rows)<>1 then raise Exception.Create('Ambiguous card source');
  TableName:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
  Match:='json_extract('+Doc+',''$._id'')='+QuotedStr(CardId)+
    ' AND json_extract('+Doc+',''$.boardId'')='+QuotedStr(BoardId)+
    ' AND json_extract('+Doc+',''$.$s.p._id.t'')=''string'' AND json_extract('+Doc+',''$.$s.p.boardId.t'')=''string''';
  for Name in ['members','assignees'] do
  begin
    if ((Name='members') and not Members) or ((Name='assignees') and not Assignees) then Continue;
    Path:=QuotedStr('$.'+Name);
    Value:='wl_sjson(json_set(wl_plain(json('+Doc+')),'+Path+',json(''[]'')),json('+Doc+'),''{}'')';
    Result:=Result+'UPDATE '+TableName+' SET '+Doc+'=CASE WHEN wl_storage('+QuotedStr(Rows[0][0])+')=''blob'' '+
      'THEN jsonb('+Value+') ELSE '+Value+' END WHERE '+Match+' AND COALESCE(json_type('+Doc+','+Path+
      '),''null'')=''null''; ';
    Result:=Result+'SELECT CASE WHEN (SELECT count(*) FROM '+TableName+' WHERE '+Match+
      ' AND json_type('+Doc+','+Path+')=''array'')=1 THEN 1 ELSE json(''Invalid card assignment source'') END; ';
  end;
end;

// Build relation changes only after validating all identifiers. The caller executes these
// changes with the card write in one transaction, so invalid data cannot partially edit it.
function CardRelationSql(const T:TWLTenant; Request:TRequest; Response:TResponse;
  const BoardId,CardId:string; out Sql:string; Creating:Boolean=False;Entry:TJSONObject=nil):Boolean;
const Fields:array[0..2] of string=('labelIds','members','assignees');
  Tables:array[0..2] of string=('card_labels','card_members','card_assignees');
var Ids:TStringList; i,j:Integer; Column:string;
  function Present(const Field:string):Boolean;
  begin
    if Entry<>nil then Result:=Entry.Find(Field)<>nil
    else Result:=BodyHasField(Request,Field);
  end;
  procedure Reject(Code:Integer;const Reason:string);
  begin
    if Response<>nil then SendError(Response,Code,Reason);
  end;
begin
  Result:=False; Sql:=''; Ids:=TStringList.Create; Ids.CaseSensitive:=True;
  try
    for i:=0 to High(Fields) do if Present(Fields[i]) then
    begin
      Ids.Clear;
      if not ReadBodyIds(Request,Fields[i],Ids,i>0,Entry) then
      begin Reject(400,'Expected an ID array or comma-separated string'); Exit; end;
      if i=0 then Column:='labelId' else Column:='userId';
      for j:=0 to Ids.Count-1 do
        if ((i=0) and (Length(T.Db.Query('SELECT id FROM board_labels WHERE boardId='+QuotedStr(BoardId)+
          ' AND id='+QuotedStr(Ids[j])+';'))=0)) or
          ((i>0) and not EnabledBoardMember(T.Db,BoardId,Ids[j])) then
        begin Reject(400,'ID does not belong to an enabled board member or board label'); Exit; end;
      Sql:=Sql+'DELETE FROM '+Tables[i]+' WHERE cardId='+QuotedStr(CardId)+'; ';
      for j:=0 to Ids.Count-1 do Sql:=Sql+'INSERT INTO '+Tables[i]+'(cardId,'+Column+') VALUES('+
        QuotedStr(CardId)+','+QuotedStr(Ids[j])+'); ';
    end;
    try
      Sql:=InitializeSharedAssignments(T.Db,BoardId,CardId,Creating or Present('members'),
        Creating or Present('assignees'))+Sql;
    except Reject(500,'Could not initialize card assignments');Exit;end;
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

procedure ApiLogout(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;Token,UserId,Flag,Sql:string;Body,Value:TJSONData;AllSessions:Boolean;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  Token:=BearerToken(aRequest);
  if (Token='') or not ValidateLoginToken(T.Db,aRequest,Token,UserId) then
  begin SendError(aResponse,401,'Invalid bearer token');Exit;end;
  Flag:=aRequest.ContentFields.Values['all'];
  if (Pos('application/json',LowerCase(aRequest.ContentType))=1) and (aRequest.Content<>'') then
  begin
    Body:=GetJSON(aRequest.Content);
    try
      Flag:='';Value:=TJSONObject(Body).Find('all');
      if Value<>nil then
        case Value.JSONType of
          jtString: Flag:=Value.AsString;
          jtBoolean: if Value.AsBoolean then Flag:='true';
          jtNumber: if Value.AsFloat=1 then Flag:='1';
        end;
    finally Body.Free;end;
  end;
  Flag:=LowerCase(Trim(Flag));
  AllSessions:=(Flag='true') or (Flag='1') or (Flag='yes');
  try
    if AllSessions then Sql:=RevokeLoginSessionsSQL(T.Db,UserId)
    else Sql:=RevokeTokenSQL(T.Db,UserId,Token);
    if not T.Db.Exec('BEGIN IMMEDIATE; '+Sql+'COMMIT;') then
      raise Exception.Create('Logout transaction failed');
  except
    T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Logout failed');Exit;
  end;
  if AllSessions then SendJson(aResponse,'{"message":"All login tokens have been invalidated."}')
  else SendJson(aResponse,'{"message":"You''ve been logged out!"}');
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

procedure ApiDeleteUser(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"User not found"}';
var T:TWLTenant;Actor,Target,Scope,Admin,Bindings,Sql:string;Source:TSelectionScope;I:Integer;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  if not IsSiteAdmin(T.Db,Actor) then
  begin SendError(aResponse,403,'Site administration required');Exit;end;
  Target:=aRequest.RouteParams['userId'];
  try
    Source:=TSelectionScope.Create(T.Db);
    try
      Scope:='id='+QuotedStr(Target)+' AND '+Source.StringField('users','id');
      Admin:='EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(Actor)+
        ' AND isAdmin=1 AND COALESCE(loginDisabled,0)=0 AND '+Source.StringField('users','id')+')';
      Bindings:='';
      for I:=0 to Source.Bindings.Count-1 do Bindings:=Bindings+Source.Bindings[I];
    finally Source.Free;end;
    if Length(T.Db.Query('SELECT id FROM users WHERE '+Scope+';'))<>1 then
    begin SendJson(aResponse,NotFound,404);Exit;end;
    Sql:='BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+AuthSourceCondition(T.Db)+' AND '+Admin+
      ' AND (SELECT count(*) FROM users WHERE '+Scope+')=1 THEN 1 ELSE json(''User deletion scope changed'') END; '+
      RevokeUserTokensSQL(T.Db,Target)+'DELETE FROM users WHERE '+Scope+'; '+
      'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(Target)+
      ') THEN 1 ELSE json(''User deletion failed'') END; COMMIT;';
    if not T.Db.Exec(Sql) then raise Exception.Create('User deletion failed');
  except T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not delete user');Exit;end;
  SendJson(aResponse,'{"_id":"'+StringToJSONString(Target)+'"}');
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

procedure ApiBoardMembership(aRequest:TRequest;aResponse:TResponse;Add:Boolean);
const Flags:array[0..7] of string=('isAdmin','isNoComments','isCommentOnly','isWorker',
  'isNormalAssignedOnly','isCommentAssignedOnly','isReadOnly','isReadAssignedOnly');
  Roles:array[0..7] of string=('admin','nocomments','commentonly','worker',
  'normalassignedonly','commentassignedonly','readonly','readassignedonly');
var T:TWLTenant;Actor,BoardId,Board,Target,Scope,UserScope,Permission,Action,Role,Columns,Values,Sets,
  Bindings,Sql,AdminCheck,MemberKey:string;Policy:TFieldPolicy;Source:TSelectionScope;
  Body:TJSONObject;Value:TJSONData;Rows:TWLRows;I,RoleIndex:Integer;Enabled:Boolean;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];Board:=QuotedStr(BoardId);
  Rows:=T.Db.Query('SELECT id FROM boards WHERE id='+Board+';');
  if Length(Rows)<>1 then begin SendJson(aResponse,'{"error":"Board not found"}',404);Exit;end;
  Policy:=TFieldPolicy.Create(T.Db,Actor,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board administration required');Exit;end;
  if Add then Action:='add' else Action:='remove';
  if BodyField(aRequest,'action')<>Action then
  begin SendError(aResponse,400,'Invalid membership action');Exit;end;
  Body:=nil;Columns:='';Values:='';Sets:='';
  try
    try
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then Body:=ExactObject(aRequest.Content)
      else
      begin
        Body:=TJSONObject.Create;
        for I:=0 to aRequest.ContentFields.Count-1 do
          Body.Add(aRequest.ContentFields.Names[I],aRequest.ContentFields.ValueFromIndex[I]);
      end;
      if Add then
      begin
        RoleIndex:=-2;Value:=Body.Find('role');
        if Value<>nil then
        begin
          if not (Value is TJSONString) then raise Exception.Create('Invalid role');
          Role:=LowerCase(Trim(Value.AsString));if Role='comment' then Role:='commentonly';
          RoleIndex:=-1;
          for I:=0 to High(Roles) do if Role=Roles[I] then RoleIndex:=I;
          if (RoleIndex<0) and (Role<>'normal') and (Role<>'member') then raise Exception.Create('Invalid role');
        end;
        for I:=0 to High(Flags) do
        begin
          Enabled:=RoleIndex=I;
          if RoleIndex=-2 then
          begin
            Value:=Body.Find(Flags[I]);
            Enabled:=(Value<>nil) and (Value.JSONType in [jtString,jtBoolean]) and SameText(Value.AsString,'true');
          end;
          Columns:=Columns+','+Flags[I];Values:=Values+','+IntToStr(Ord(Enabled));
          Sets:=Sets+','+Flags[I]+'='+IntToStr(Ord(Enabled));
        end;
      end;
    except SendError(aResponse,400,'Invalid membership role');Exit;end;
  finally Body.Free;end;
  Target:=QuotedStr(aRequest.RouteParams['userId']);
  Source:=TSelectionScope.Create(T.Db);
  try
    UserScope:='id='+Target+' AND '+Source.StringField('users','id');
    MemberKey:=Source.StringField('board_members','userId');
    Scope:='boardId='+Board+' AND userId='+Target;
    Bindings:='';
    for I:=0 to Source.Bindings.Count-1 do Bindings:=Bindings+Source.Bindings[I];
  finally Source.Free;end;
  Rows:=T.Db.Query('SELECT COALESCE(loginDisabled,0) FROM users WHERE '+UserScope+';');
  if Length(Rows)<>1 then begin SendJson(aResponse,'{"error":"User not found"}',404);Exit;end;
  Sql:='BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+Permission+' AND '+
    '(SELECT count(*) FROM users WHERE '+UserScope;
  if Add then
  begin
    if Rows[0][0]<>'0' then begin SendError(aResponse,400,'User is disabled');Exit;end;
    Sql:=Sql+' AND COALESCE(loginDisabled,0)=0)=1 AND NOT EXISTS(SELECT 1 FROM board_members WHERE '+Scope+
      ' AND NOT '+MemberKey+') THEN 1 ELSE json(''Board membership scope changed'') END; '+
      'UPDATE board_members SET isActive=1'+Sets+' WHERE '+Scope+' AND COALESCE(isActive,0)=0; '+
      'INSERT INTO board_members(boardId,userId,isActive'+Columns+') SELECT '+Board+','+Target+',1'+Values+
      ' WHERE NOT EXISTS(SELECT 1 FROM board_members WHERE '+Scope+'); '+
      'SELECT CASE WHEN (SELECT count(*) FROM board_members WHERE '+Scope+
      ' AND isActive=1 AND '+MemberKey+')=1 THEN 1 ELSE json(''Board member add failed'') END; COMMIT;';
  end else
  begin
    Rows:=T.Db.Query('SELECT isAdmin FROM board_members WHERE '+Scope+' AND isActive=1 AND '+MemberKey+';');
    if Length(Rows)<>1 then begin SendJson(aResponse,'{"error":"Member not found"}',404);Exit;end;
    AdminCheck:='(isAdmin=0 OR (SELECT count(*) FROM board_members WHERE boardId='+Board+
      ' AND isActive=1 AND isAdmin=1 AND '+MemberKey+')>1)';
    if Length(T.Db.Query('SELECT 1 FROM board_members WHERE '+Scope+' AND '+AdminCheck+';'))<>1 then
    begin SendError(aResponse,409,'The last board admin cannot be removed');Exit;end;
    Sql:=Sql+')=1 AND (SELECT count(*) FROM board_members WHERE '+Scope+' AND isActive=1 AND '+MemberKey+' AND '+
      AdminCheck+')=1 THEN 1 ELSE json(''Board membership scope changed'') END; '+
      'UPDATE board_members SET isActive=0,isAdmin=0 WHERE '+Scope+'; SELECT CASE WHEN '+
      '(SELECT count(*) FROM board_members WHERE '+Scope+' AND isActive=0 AND isAdmin=0)=1 '+
      'THEN 1 ELSE json(''Board member removal failed'') END; COMMIT;';
  end;
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not change board membership');Exit;end;
  Rows:=T.Db.Query('SELECT json_array(json_object(''_id'',id,''title'',title)) FROM boards WHERE id='+Board+';');
  if Length(Rows)<>1 then begin SendError(aResponse,500,'Could not read board');Exit;end;
  SendJson(aResponse,Rows[0][0]);
end;

procedure ApiAddBoardMember(aRequest:TRequest;aResponse:TResponse);
begin ApiBoardMembership(aRequest,aResponse,True);end;

procedure ApiRemoveBoardMember(aRequest:TRequest;aResponse:TResponse);
begin ApiBoardMembership(aRequest,aResponse,False);end;

procedure ApiBoardCardSettings(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"Board not found"}';
  DefaultsJson=
    '{"allowsSwimlaneDragging":true,"allowsListDragging":true,"allowsCardDragging":true,'+
    '"allowsChecklistDragging":true,"allowsChecklistItemDragging":true,"allowsSubtaskDragging":true,'+
    '"allowsMinicardCollapse":true,"labelsAboveTitleOnMinicard":false,"allowsChecklistDueDate":true,'+
    '"allowsChecklistTitle":true,"allowsCardCounterList":false,"cardAging":false,'+
    '"askForMoveReason":false,"allowsBoardMemberList":false,"allowsShowLists":true,'+
    '"allowsAttachments":true,"allowsChecklists":true,"allowsComments":true,'+
    '"allowsCommentsOnMinicard":false,"allowsDescriptionTitle":true,"allowsDescriptionText":true,'+
    '"allowsActivities":true,"allowsLabels":true,"allowsCreator":true,"allowsAssignee":true,'+
    '"allowsMembers":true,"allowsRequestedBy":true,"allowsCardSortingByNumber":true,'+
    '"allowsCardNumber":false,"allowsAssignedBy":true,"allowsReceivedDate":true,"allowsSpentTime":true,'+
    '"allowsStartDate":true,"allowsEndDate":true,"allowsDueDate":true,"allowsSubtasks":true,'+
    '"allowsCreatorOnMinicard":false,"allowsAttachmentsOnMinicard":true,'+
    '"allowsChecklistsOnMinicard":true,"allowsChecklistAtMinicard":false,'+
    '"allowsCoverAttachmentOnMinicard":true,"allowsBadgeAttachmentOnMinicard":false,'+
    '"allowsCardSortingByNumberOnMinicard":false,"allowsCardNumberOnMinicard":false,'+
    '"allowsDescriptionTitleOnMinicard":true,"allowsDescriptionTextOnMinicard":false,'+
    '"allowsLabelsOnMinicard":true,"allowsAssigneeOnMinicard":true,"allowsMembersOnMinicard":true,'+
    '"allowsRequestedByOnMinicard":true,"allowsAssignedByOnMinicard":true,'+
    '"allowsReceivedDateOnMinicard":true,"allowsSpentTimeOnMinicard":true,'+
    '"allowsStartDateOnMinicard":true,"allowsEndDateOnMinicard":true,"allowsDueDateOnMinicard":true,'+
    '"allowsSubtasksOnMinicard":true,"allowsShowListsOnMinicard":false,'+
    '"allowsSwimlaneNameOnMinicard":false,"showLabelText":true,"allowsStickers":true,'+
    '"allowsStickersOnMinicard":true,"allowsLocation":true,"allowsDependencies":true,'+
    '"allowsDependenciesOnMinicard":true,"allowsFlowtime":true,"allowsPomodoro":true,"allowsVote":true,'+
    '"allowsVoteOnMinicard":true,"allowsPoker":true,"allowsPokerOnMinicard":true,"allowsTextNotes":true,'+
    '"allowsCommentCountOnMinicard":true,"allowsIssueTypeOnMinicard":true,"allowsCardColorOnCard":true,'+
    '"allowsCardColorOnMinicard":true,"allowsParentCardOnCard":true,"allowsParentCardOnMinicard":true,'+
    '"allowsLinkedCardOnCard":true,"allowsLinkedCardOnMinicard":true,"allowsCardButtonsOnCard":true,'+
    '"allowsDescriptionBadgeOnMinicard":true,"allowsUnreadCommentsOnMinicard":true,'+
    '"allowsCardButtonsOnMinicard":null,"allowsDescriptionBadgeOnCard":null,'+
    '"allowsUnreadCommentsOnCard":null,"allowsDueFromTitleOnCard":null,'+
    '"allowsDueFromTitleOnMinicard":null,"allowsSimilarCardsOnCard":null,'+
    '"allowsSimilarCardsOnMinicard":null,"allowsAtRiskOnCard":null,"allowsAtRiskOnMinicard":null,'+
    '"allowsSuggestedMembersOnCard":null,"allowsForecastOnCard":null,"allowsForecastOnMinicard":null,'+
    '"allowsChecklistFromDescriptionOnCard":null,"allowsActionItemsOnCard":null,'+
    '"allowsWhiteboardOnCard":null,"allowsAttachmentPreviewsOnCard":null,'+
    '"allowsAttachmentDetailsOnCard":null,"allowsCardCollapse":true,'+
    '"allowsChecklistTitleOnMinicard":true,"allowsLabelTextOnCard":true,"labelsAboveTitleOnCard":null,'+
    '"allowsChecklistDueDateOnMinicard":null,"allowsLocationOnMinicard":null,'+
    '"allowsSwimlaneNameOnCard":null,"allowsFlowtimeOnMinicard":null,"allowsPomodoroOnMinicard":null,'+
    '"allowsAttachmentListOnMinicard":null,"allowsTextNotesOnMinicard":null,'+
    '"allowsCommentCountOnCard":null,"allowsActivitiesOnMinicard":null,"cardAgingDays1":7,'+
    '"cardAgingDays2":14,"cardAgingDays3":28}';
var T:TWLTenant;UserId,BoardId,Scope,Permission,Key,Sql,Raw:string;Rows:TWLRows;
  Defaults,Stored,Body,Patch,Reply:TJSONObject;Value,Fallback:TJSONData;Policy:TFieldPolicy;
  I:Integer;Days:Int64;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];Scope:='id='+QuotedStr(BoardId);
  if Length(T.Db.Query('SELECT id FROM boards WHERE '+Scope+';'))<>1 then
  begin SendJson(aResponse,NotFound,404);Exit;end;
  Defaults:=ExactObject(DefaultsJson);Stored:=nil;Body:=nil;Patch:=nil;Reply:=nil;
  try
    if aRequest.Method='PUT' then
    begin
      Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
      try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin SendError(aResponse,403,'Board administration required');Exit;end;
      try
        if Pos('application/json',LowerCase(aRequest.ContentType))=1 then Body:=ExactObject(aRequest.Content)
        else
        begin
          Body:=TJSONObject.Create;
          for I:=0 to aRequest.ContentFields.Count-1 do
            Body.Add(aRequest.ContentFields.Names[I],aRequest.ContentFields.ValueFromIndex[I]);
        end;
        Patch:=TJSONObject.Create;
        for I:=0 to Defaults.Count-1 do
        begin
          Key:=Defaults.Names[I];Value:=Body.Find(Key);
          if Value=nil then Continue;
          if Defaults.Items[I].JSONType=jtNumber then
          begin
            if (Value.JSONType in [jtNumber,jtString]) and TryStrToInt64(Trim(Value.AsString),Days) and (Days>=0) then
              Patch.Add(Key,Days);
          end else
          begin
            Raw:='';
            if Value.JSONType in [jtBoolean,jtString] then Raw:=Value.AsString;
            Patch.Add(Key,SameText(Raw,'true'));
          end;
        end;
      except SendError(aResponse,400,'Invalid card settings');Exit;end;
      if Patch.Count=0 then begin SendError(aResponse,400,'No recognized card settings in body');Exit;end;
      Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+
        ' THEN 1 ELSE json(''Board card settings permission changed'') END; UPDATE boards SET settings_json='+
        'json_patch(settings_json,'+QuotedStr(Patch.AsJSON)+') WHERE '+Scope+'; COMMIT;';
      if not T.Db.Exec(Sql) then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not write board card settings');Exit;end;
    end else if not ApiAuthBoard(T,aResponse,UserId,BoardId,False) then Exit;
    Rows:=T.Db.Query('SELECT settings_json FROM boards WHERE '+Scope+';');
    if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
    Stored:=ExactObject(Rows[0][0]);Reply:=TJSONObject.Create;
    for I:=0 to Defaults.Count-1 do
    begin
      Key:=Defaults.Names[I];Fallback:=Defaults.Items[I];Value:=Stored.Find(Key);
      if Value=nil then Value:=Fallback;
      if Value.JSONType<>jtNull then Reply.Add(Key,Value.Clone);
    end;
    SendJson(aResponse,Reply.AsJSON);
  finally Reply.Free;Patch.Free;Body.Free;Stored.Free;Defaults.Free;end;
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

procedure NormalizeRuleTrigger(Trigger:TJSONObject);
const
  TriggerFields=
    '"createCard":["boardId","listName","userId","swimlaneName","cardTitle"],'+
    '"moveCard":["boardId","listName","oldListName","userId","swimlaneName","cardTitle"],'+
    '"archivedCard":["boardId","userId","cardTitle"],'+
    '"addComment":["boardId","userId","cardTitle"],'+
    '"restoredCard":["boardId","userId","cardTitle"],'+
    '"joinMember":["boardId","username","userId"],'+
    '"unjoinMember":["boardId","username","userId"],'+
    '"joinAssignee":["boardId","username","userId"],'+
    '"unjoinAssignee":["boardId","username","userId"],'+
    '"addChecklist":["boardId","checklistName","userId"],'+
    '"removeChecklist":["boardId","checklistName","userId"],'+
    '"completeChecklist":["boardId","checklistName","userId"],'+
    '"uncompleteChecklist":["boardId","checklistName","userId"],'+
    '"addedChecklistItem":["boardId","checklistItemName","userId"],'+
    '"removedChecklistItem":["boardId","checklistItemName","userId"],'+
    '"checkedItem":["boardId","checklistItemName","userId"],'+
    '"uncheckedItem":["boardId","checklistItemName","userId"],'+
    '"addAttachment":["boardId","userId"],'+
    '"deleteAttachment":["boardId","userId"],'+
    '"addedLabel":["boardId","labelId","userId"],'+
    '"removedLabel":["boardId","labelId","userId"],'+
    '"a-receivedAt":["boardId","userId"],'+
    '"a-startAt":["boardId","userId"],'+
    '"a-dueAt":["boardId","userId"],'+
    '"a-endAt":["boardId","userId"]';
var Fields:TJSONObject;MatchFields,Value:TJSONData;I:Integer;Name:string;
begin
  Fields:=ExactObject('{'+TriggerFields+'}');
  try
    MatchFields:=Fields.Find(Trigger.Get('activityType',''));
    if MatchFields is TJSONArray then
      for I:=0 to MatchFields.Count-1 do
      begin
        Name:=MatchFields.Items[I].AsString;Value:=Trigger.Find(Name);
        if (Value=nil) or (Value.JSONType=jtNull) or ((Value is TJSONString) and (Value.AsString='')) then
        begin Trigger.Delete(Name);Trigger.Add(Name,'*');end;
      end;
  finally Fields.Free;end;
end;

procedure ApiCreateRule(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,Permission,RuleId,TriggerId,ActionId,Title,Sql,Guards:string;
  Body,Rule,Trigger,Action,Reply:TJSONObject;Rows:TWLRows;
  Policy:TFieldPolicy;
  function WorkflowInsert(const Collection:string;Doc:TJSONObject):string;
  var Found:TWLRows;TableName,QuotedTable,Payload:string;
  begin
    if not EnsureSharedCollection(T.Db,Collection) then raise Exception.Create('Workflow collection unavailable');
    Found:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(Collection)+';');
    if Length(Found)<>1 then raise Exception.Create('Ambiguous workflow collection');
    TableName:=Found[0][0];QuotedTable:='"'+StringReplace(TableName,'"','""',[rfReplaceAll])+'"';
    Guards:=Guards+' AND (SELECT count(*) FROM _ferretdb_collections WHERE table_name='+QuotedStr(TableName)+
      ' AND name='+QuotedStr(Collection)+')=1';
    Payload:=QuotedStr(TypedDocument(Doc.AsJSON,'','{}'));
    Result:='INSERT INTO '+QuotedTable+'(_ferretdb_sjson) VALUES(CASE WHEN wl_storage('+QuotedStr(TableName)+
      ')=''blob'' THEN jsonb('+Payload+') ELSE '+Payload+' END); '+
      'SELECT CASE WHEN (SELECT count(*) FROM '+QuotedTable+' WHERE json_extract(_ferretdb_sjson,''$._id'')='+
      QuotedStr(Doc.Get('_id',''))+')=1 THEN 1 ELSE json(''Workflow insert failed'') END; ';
  end;
  function PreparePart(const Part,Kind,Id:string):TJSONObject;
  var Raw:TJSONData;Key:string;
  begin
    Raw:=Body.Find(Part);
    if not (Raw is TJSONObject) then raise Exception.Create('Missing workflow part');
    Raw:=TJSONObject(Raw).Find(Kind);
    if not (Raw is TJSONString) or (Trim(Raw.AsString)='') then raise Exception.Create('Missing workflow part type');
    Result:=TJSONObject(Body.Find(Part));
    for Key in ['_id','boardId','createdAt','modifiedAt','updatedAt'] do Result.Delete(Key);
    Result.Add('_id',Id);Result.Add('boardId',BoardId);
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];
  Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board administration required');Exit;end;
  if Length(T.Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))<>1 then
  begin SendError(aResponse,501,'Rule creation requires shared workflow storage');Exit;end;
  Body:=nil;Rule:=nil;
  try
    RuleId:=NewId;TriggerId:=NewId;ActionId:=NewId;
    try
      Body:=ExactObject(aRequest.Content);
      Trigger:=PreparePart('trigger','activityType',TriggerId);
      Action:=PreparePart('action','actionType',ActionId);
      NormalizeRuleTrigger(Trigger);
      Title:=Body.Get('title','');if Title='' then Title:='API rule';
      Rule:=TJSONObject.Create(['_id',RuleId,'title',Title,'triggerId',TriggerId,
        'actionId',ActionId,'boardId',BoardId,'enabled',True]);
      if Trigger.Get('activityType','')='button' then
      begin
        Rule.Add('buttonType',Trigger.Get('buttonType','card'));
        Rule.Add('buttonLabel',Trigger.Get('buttonLabel',Title));
      end;
    except SendError(aResponse,400,'Invalid workflow definition');Exit;end;
    try
      Guards:='';Sql:=WorkflowInsert('triggers',Trigger)+WorkflowInsert('actions',Action)+WorkflowInsert('rules',Rule);
      if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+Guards+
        ' THEN 1 ELSE json(''Workflow scope changed'') END; '+Sql+'COMMIT;') then
        raise Exception.Create('Rule creation failed');
    except T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create rule');Exit;end;
    Reply:=TJSONObject.Create(['_id',RuleId,'triggerId',TriggerId,'actionId',ActionId]);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  finally Rule.Free;Body.Free;end;
end;

procedure ApiEditRule(aRequest:TRequest;aResponse:TResponse);
const Doc='_ferretdb_sjson';
var T:TWLTenant;UserId,BoardId,RuleId,Permission,Guard,RuleTable,RuleScope,RuleRaw,Sql,Bindings:string;
  Rows:TWLRows;Body,Rule:TJSONObject;Value:TJSONData;Policy:TFieldPolicy;
  function Bind(const Collection:string;out Storage:string):string;
  var Found:TWLRows;
  begin
    Found:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(Collection)+';');
    if Length(Found)<>1 then raise Exception.Create('Missing workflow collection');
    Storage:=Found[0][0];Result:='"'+StringReplace(Storage,'"','""',[rfReplaceAll])+'"';
    Bindings:=Bindings+' AND (SELECT count(*) FROM _ferretdb_collections WHERE name='+QuotedStr(Collection)+
      ' AND table_name='+QuotedStr(Storage)+')=1';
  end;
  function KeyMatch(const Id:string):string;
  begin
    Result:='json_extract('+Doc+',''$._id'')='+QuotedStr(Id)+
      ' AND json_extract('+Doc+',''$.$s.p._id.t'')=''string''';
  end;
  procedure SetValue(Obj:TJSONObject;const Name:string;Item:TJSONData);
  begin Obj.Delete(Name);Obj.Add(Name,Item);end;
  procedure EditPart(const Part,Collection,Kind,Extra:string);
  var Patch,Stored:TJSONObject;Item:TJSONData;CurrentId,NewPartId,IdKey,TableName,Storage,Scope,Previous,
    Reference,ReferenceCheck,Encoded,Literal,Key:string;Found:TWLRows;I:Integer;SharedPart:Boolean;
  begin
    Item:=Body.Find(Part);if Item=nil then Exit;
    if not (Item is TJSONObject) then raise EConvertError.Create('Invalid workflow part');
    Patch:=TJSONObject(Item);Item:=Patch.Find(Kind);
    if not (Item is TJSONString) or (Trim(Item.AsString)='') then raise EConvertError.Create('Invalid workflow type');
    for Key in ['_id','boardId','createdAt','modifiedAt','updatedAt'] do Patch.Delete(Key);
    if Part='trigger' then NormalizeRuleTrigger(Patch);
    TableName:=Bind(Collection,Storage);IdKey:=Part+'Id';CurrentId:=Rule.Get(IdKey,'');
    Scope:=KeyMatch(CurrentId)+' AND (json_type('+Doc+',''$.boardId'') IS NULL OR '+
      'json_extract('+Doc+',''$.boardId'')='+QuotedStr(BoardId)+')';
    Found:=T.Db.Query('SELECT json('+Doc+') FROM '+TableName+' WHERE '+Scope+';');
    if Length(Found)>1 then raise Exception.Create('Ambiguous workflow part');
    Previous:='';if Length(Found)=1 then Previous:=Found[0][0];
    Reference:='EXISTS(SELECT 1 FROM '+RuleTable+' WHERE NOT ('+RuleScope+') AND ('+
      'json_extract('+Doc+','+QuotedStr('$.'+IdKey)+')='+QuotedStr(CurrentId)+
      ' OR EXISTS(SELECT 1 FROM json_each('+Doc+','+QuotedStr('$.'+Extra)+') WHERE type=''text'' AND value='+
      QuotedStr(CurrentId)+')))';
    Found:=T.Db.Query('SELECT '+Reference+';');
    if Length(Found)<>1 then raise Exception.Create('Could not read workflow references');
    SharedPart:=Found[0][0]='1';ReferenceCheck:=Reference;
    if not SharedPart then ReferenceCheck:='NOT '+Reference;
    Stored:=nil;
    try
      if Previous='' then Stored:=TJSONObject.Create else Stored:=ExactObject(PlainDocument(Previous));
      NewPartId:=CurrentId;
      if SharedPart or (Previous='') then NewPartId:=NewId;
      for I:=0 to Patch.Count-1 do SetValue(Stored,Patch.Names[I],Patch.Items[I].Clone);
      SetValue(Stored,'_id',TJSONString.Create(NewPartId));
      SetValue(Stored,'boardId',TJSONString.Create(BoardId));
      Encoded:=QuotedStr(TypedDocument(Stored.AsJSON,Previous,'{}'));
      Literal:='CASE WHEN wl_storage('+QuotedStr(Storage)+')=''blob'' THEN jsonb('+Encoded+') ELSE '+Encoded+' END';
      if Previous<>'' then
        Guard:=Guard+' AND '+ReferenceCheck+' AND (SELECT count(*) FROM '+TableName+' WHERE '+Scope+
          ' AND json('+Doc+')='+QuotedStr(Previous)+')=1'
      else Guard:=Guard+' AND NOT EXISTS(SELECT 1 FROM '+TableName+' WHERE '+Scope+')';
      if NewPartId=CurrentId then
        Sql:=Sql+'UPDATE '+TableName+' SET '+Doc+'='+Literal+' WHERE '+Scope+'; '
      else
        Sql:=Sql+'INSERT INTO '+TableName+'('+Doc+') VALUES('+Literal+'); ';
      Sql:=Sql+'SELECT CASE WHEN EXISTS(SELECT 1 FROM '+TableName+' WHERE '+KeyMatch(NewPartId)+
        ' AND json('+Doc+')=json('+Encoded+')) THEN 1 ELSE json(''Workflow part edit failed'') END; ';
      SetValue(Rule,IdKey,TJSONString.Create(NewPartId));
      if Part='trigger' then
      begin
        Rule.Delete('buttonType');Rule.Delete('buttonLabel');
        if Stored.Get('activityType','')='button' then
        begin
          Rule.Add('buttonType',Stored.Get('buttonType','card'));
          Rule.Add('buttonLabel',Stored.Get('buttonLabel',Rule.Get('title','Rule')));
        end;
      end;
    finally Stored.Free;end;
  end;
var RuleStorage,Encoded:string;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];RuleId:=aRequest.RouteParams['ruleId'];
  Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board administration required');Exit;end;
  Body:=nil;Rule:=nil;Bindings:='';Guard:='';Sql:='';
  try
    try
      try Body:=ExactObject(aRequest.Content);
      except raise EConvertError.Create('Invalid workflow update');end;
      RuleTable:=Bind('rules',RuleStorage);
      RuleScope:=KeyMatch(RuleId)+' AND json_extract('+Doc+',''$.boardId'')='+QuotedStr(BoardId)+
        ' AND json_extract('+Doc+',''$.$s.p.boardId.t'')=''string''';
      Rows:=T.Db.Query('SELECT json('+Doc+') FROM '+RuleTable+' WHERE '+RuleScope+';');
      if Length(Rows)<>1 then begin SendJson(aResponse,'{"error":"Rule not found"}',404);Exit;end;
      RuleRaw:=Rows[0][0];Rule:=ExactObject(PlainDocument(RuleRaw));
      Value:=Body.Find('title');if Value is TJSONString then SetValue(Rule,'title',Value.Clone);
      Value:=Body.Find('enabled');
      if Value<>nil then SetValue(Rule,'enabled',TJSONBoolean.Create(
        ((Value is TJSONBoolean) and Value.AsBoolean) or ((Value is TJSONString) and (Value.AsString='true'))));
      EditPart('trigger','triggers','activityType','extraTriggerIds');
      EditPart('action','actions','actionType','extraActionIds');
      Encoded:=QuotedStr(TypedDocument(Rule.AsJSON,RuleRaw,'{}'));
      Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+Bindings+Guard+
        ' AND (SELECT count(*) FROM '+RuleTable+' WHERE '+RuleScope+' AND json('+Doc+')='+QuotedStr(RuleRaw)+
        ')=1 THEN 1 ELSE json(''Workflow scope changed'') END; '+Sql+
        'UPDATE '+RuleTable+' SET '+Doc+'=CASE WHEN wl_storage('+QuotedStr(RuleStorage)+')=''blob'' THEN jsonb('+
        Encoded+') ELSE '+Encoded+' END WHERE '+RuleScope+'; '+
        'SELECT CASE WHEN EXISTS(SELECT 1 FROM '+RuleTable+' WHERE '+RuleScope+' AND json('+Doc+')=json('+Encoded+
        ')) THEN 1 ELSE json(''Workflow edit failed'') END; COMMIT;';
      if not T.Db.Exec(Sql) then raise Exception.Create('Workflow edit failed');
    except
      on E:EConvertError do begin SendError(aResponse,400,'Invalid workflow update');Exit;end;
      on E:Exception do begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not edit rule');Exit;end;
    end;
    SendJson(aResponse,'{"_id":"'+StringToJSONString(RuleId)+'"}');
  finally Rule.Free;Body.Free;end;
end;

procedure ApiDeleteRule(aRequest:TRequest;aResponse:TResponse);
const Doc='_ferretdb_sjson';NotFound='{"error":"Rule not found"}';
var T:TWLTenant;Actor,BoardId,RuleId,Permission,Scope,Source,Original,Bindings,Sql:string;
  Rows:TWLRows;Rule:TJSONObject;Policy:TFieldPolicy;
  function Bind(const Collection:string):string;
  var Found:TWLRows;
  begin
    Result:='';
    Found:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(Collection)+';');
    if Length(Found)>1 then raise Exception.Create('Ambiguous workflow collection');
    if Length(Found)=0 then
    begin Bindings:=Bindings+' AND NOT EXISTS(SELECT 1 FROM _ferretdb_collections WHERE name='+QuotedStr(Collection)+')';Exit;end;
    Result:='"'+StringReplace(Found[0][0],'"','""',[rfReplaceAll])+'"';
    Bindings:=Bindings+' AND (SELECT count(*) FROM _ferretdb_collections WHERE name='+QuotedStr(Collection)+
      ' AND table_name='+QuotedStr(Found[0][0])+')=1';
  end;
  function UnusedParts(const Collection,Primary,Extra:string):string;
  var TableName,Id,Targets,Reference,Predicate:string;Value:TJSONData;Ids:TStringList;I:Integer;
    procedure Add(Value:TJSONData);
    begin
      if (Value is TJSONString) and (Value.AsString<>'') and (Pos(#0,Value.AsString)=0) then Ids.Add(Value.AsString);
    end;
  begin
    Result:='';TableName:=Bind(Collection);if TableName='' then Exit;
    Ids:=TStringList.Create;
    try
      Ids.CaseSensitive:=True;Ids.Sorted:=True;Ids.Duplicates:=dupIgnore;
      Add(Rule.Find(Primary));Value:=Rule.Find(Extra);
      if Value is TJSONArray then for I:=0 to Value.Count-1 do Add(Value.Items[I]);
      if Ids.Count=0 then Exit;
      Targets:='';
      for I:=0 to Ids.Count-1 do
      begin
        if I>0 then Targets:=Targets+',';
        Targets:=Targets+QuotedStr(Ids[I]);
      end;
      Id:='json_extract('+TableName+'.'+Doc+',''$._id'')';
      Reference:='EXISTS(SELECT 1 FROM '+Source+' r WHERE json_extract(r.'+Doc+','+QuotedStr('$.'+Primary)+')='+Id+
        ' OR EXISTS(SELECT 1 FROM json_each(r.'+Doc+','+QuotedStr('$.'+Extra)+') WHERE type=''text'' AND value='+Id+'))';
      Predicate:=Id+' IN ('+Targets+') AND json_extract('+Doc+',''$.$s.p._id.t'')=''string'' AND '+
        '(json_type('+Doc+',''$.boardId'') IS NULL OR json_extract('+Doc+',''$.boardId'')='+QuotedStr(BoardId)+
        ') AND NOT '+Reference;
      Result:='DELETE FROM '+TableName+' WHERE '+Predicate+'; '+
        'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM '+TableName+' WHERE '+Predicate+
        ') THEN 1 ELSE json(''Workflow part removal failed'') END; ';
    finally Ids.Free;end;
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];RuleId:=aRequest.RouteParams['ruleId'];
  Policy:=TFieldPolicy.Create(T.Db,Actor,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board administration required');Exit;end;
  if Length(T.Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))=0 then
  begin SendJson(aResponse,NotFound,404);Exit;end;
  Rule:=nil;Bindings:='';
  try
    try
      Source:=Bind('rules');
      if Source='' then begin SendJson(aResponse,NotFound,404);Exit;end;
      Scope:='json_extract('+Doc+',''$._id'')='+QuotedStr(RuleId)+
        ' AND json_extract('+Doc+',''$.boardId'')='+QuotedStr(BoardId)+
        ' AND json_extract('+Doc+',''$.$s.p._id.t'')=''string'''+
        ' AND json_extract('+Doc+',''$.$s.p.boardId.t'')=''string''';
      Rows:=T.Db.Query('SELECT json('+Doc+') FROM '+Source+' WHERE '+Scope+';');
      if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
      Original:=Rows[0][0];Rule:=ExactObject(PlainDocument(Original));
      Sql:=UnusedParts('triggers','triggerId','extraTriggerIds')+UnusedParts('actions','actionId','extraActionIds');
      Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+Bindings+
        ' AND (SELECT count(*) FROM '+Source+' WHERE '+Scope+' AND json('+Doc+')='+QuotedStr(Original)+
        ')=1 THEN 1 ELSE json(''Workflow scope changed'') END; DELETE FROM '+Source+' WHERE '+Scope+
        '; SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM '+Source+' WHERE '+Scope+
        ') THEN 1 ELSE json(''Workflow removal failed'') END; '+Sql+'COMMIT;';
      if not T.Db.Exec(Sql) then raise Exception.Create('Rule removal failed');
    except T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not delete rule');Exit;end;
    SendJson(aResponse,'{"_id":"'+StringToJSONString(RuleId)+'"}');
  finally Rule.Free;end;
end;

procedure ApiBoardRules(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,RuleId,Id:string;Graph,Rule,Item:TJSONObject;
  Rules,Reply,Triggers,Actions:TJSONArray;Flag:TJSONData;I:Integer;
  function Part(Parts:TJSONArray;const Key:string):TJSONData;
  var J:Integer;Entry:TJSONObject;
  begin
    Result:=nil;if Key='' then Exit;
    for J:=0 to Parts.Count-1 do
      if Parts.Objects[J].Get('_id','')=Key then
      begin
        Entry:=TJSONObject(Parts.Objects[J].Clone);
        Entry.Delete('_id');Entry.Delete('boardId');Entry.Delete('createdAt');Entry.Delete('modifiedAt');Entry.Delete('updatedAt');
        Result:=Entry;Exit;
      end;
  end;
  procedure Embed(const Name,Primary,Extra:string;Parts:TJSONArray);
  var Value,Entry:TJSONData;Items:TJSONArray;J:Integer;
  begin
    Value:=Part(Parts,Rule.Get(Primary,''));
    if Value=nil then Value:=TJSONNull.Create;
    Item.Add(Name,Value);
    Value:=Rule.Find(Extra);
    if not (Value is TJSONArray) or (Value.Count=0) then Exit;
    Items:=TJSONArray.Create;
    if Name='trigger' then Item.Add('extraTriggers',Items) else Item.Add('extraActions',Items);
    for J:=0 to Value.Count-1 do
      if Value.Items[J] is TJSONString then
      begin
        Entry:=Part(Parts,Value.Items[J].AsString);
        if Entry<>nil then Items.Add(Entry);
      end;
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];RuleId:=aRequest.RouteParams['ruleId'];
  Graph:=TJSONObject.Create;Reply:=TJSONArray.Create;
  try
    try
      if not T.Db.BeginRead then raise Exception.Create('Could not pin board rule snapshot');
      try
        if not ApiAuthBoard(T,aResponse,UserId,BoardId,False) then Exit;
        ReadExportWorkflows(T.Db,BoardId,Graph);
      finally
        if not T.Db.EndRead then raise Exception.Create('Could not close board rule snapshot');
      end;
      Rules:=TJSONArray(Graph.Find('rules'));Triggers:=TJSONArray(Graph.Find('triggers'));Actions:=TJSONArray(Graph.Find('actions'));
      for I:=0 to Rules.Count-1 do
      begin
        Rule:=Rules.Objects[I];Id:=Rule.Get('_id','');
        if (RuleId<>'') and (Id<>RuleId) then Continue;
        Flag:=Rule.Find('enabled');
        Item:=TJSONObject.Create(['_id',Id,'title',Rule.Get('title',''),
          'enabled',not ((Flag is TJSONBoolean) and not Flag.AsBoolean)]);
        Reply.Add(Item);
        Embed('trigger','triggerId','extraTriggerIds',Triggers);
        Embed('action','actionId','extraActionIds',Actions);
      end;
    except SendError(aResponse,500,'Could not read board rules');Exit;end;
    if RuleId='' then SendJson(aResponse,Reply.AsJSON)
    else if Reply.Count=1 then SendJson(aResponse,Reply.Items[0].AsJSON)
    else SendJson(aResponse,'{"error":"Rule not found"}',404);
  finally Reply.Free;Graph.Free;end;
end;

procedure BoardExport(aRequest:TRequest;aResponse:TResponse;Browser:Boolean);
var T:TWLTenant;UserId,BoardId,Key,TableName:string;Payload:TJSONObject;Rows:TWLRows;Session:TWLSession;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if Browser then
  begin
    if not ValidateSession(T.Db,aRequest,SessionIdFromRequest(aRequest),Session) then
    begin SendError(aResponse,401,'Sign in to download a board');Exit;end;
    UserId:=Session.UserId;BoardId:=aRequest.QueryFields.Values['id'];
    if (BoardId='') or (Pos(#0,BoardId)>0) then
    begin SendError(aResponse,400,'Invalid board ID');Exit;end;
  end else
  begin
    if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
    BoardId:=aRequest.RouteParams['boardId'];
  end;
  if not ApiAuthBoard(T,aResponse,UserId,BoardId,False) then Exit;
  for Key in ['swimlaneId','listId','cardId','checklistId','fields'] do
    if aRequest.QueryFields.IndexOfName(Key)>=0 then
    begin SendError(aResponse,400,'Scoped export is unavailable');Exit;end;
  if Length(T.Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))=1 then
  begin
    Rows:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''settings'';');
    if Length(Rows)=1 then
    begin
      TableName:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
      Rows:=T.Db.Query('SELECT count(*) FROM '+TableName+' WHERE json_type(_ferretdb_sjson,''$.disableAllExport'')=''true'''+
        ' OR json_type(_ferretdb_sjson,''$.anonymizeExportUsers'')=''true'';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'0') then
      begin SendError(aResponse,403,'Board export restricted by instance settings');Exit;end;
    end else if Length(Rows)>1 then
    begin SendError(aResponse,500,'Ambiguous export settings source');Exit;end;
  end;
  try
    Payload:=ReadRestBoardExport(T,UserId,BoardId,aRequest.QueryFields.Values['attachments']<>'false');
  except SendError(aResponse,500,'Could not export board');Exit;end;
  if Payload=nil then begin SendError(aResponse,403,'Board export forbidden');Exit;end;
  try
    if Browser then
    begin
      aResponse.SetCustomHeader('Content-Disposition','attachment; filename="board.json"');
      aResponse.SetCustomHeader('Cache-Control','private, no-store');
      aResponse.SetCustomHeader('Referrer-Policy','no-referrer');
    end;
    SendJson(aResponse,Payload.AsJSON);
  finally Payload.Free;end;
end;

procedure ApiBoardExport(aRequest:TRequest;aResponse:TResponse);
begin BoardExport(aRequest,aResponse,False);end;

procedure BrowserBoardExport(aRequest:TRequest;aResponse:TResponse);
begin BoardExport(aRequest,aResponse,True);end;

procedure BoardCreationSettings(Db:TWLDb;out AdminOnly,PrivateOnly,RegistryGuard:string);
var Registry,TableName:string;Rows:TWLRows;
  function Setting(const Name:string):string;
  begin
    Result:='EXISTS(SELECT 1 FROM '+TableName+' WHERE json_extract(_ferretdb_sjson,''$._id'')='+
      QuotedStr('tableVisibilityMode-'+Name)+' AND json_type(_ferretdb_sjson,''$.booleanValue'')=''true'')';
  end;
begin
  AdminOnly:='0';PrivateOnly:='0';RegistryGuard:='1';
  if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))=1 then
  begin
    Registry:=' FROM _ferretdb_collections WHERE name=''tableVisibilityModeSettings''';
    Rows:=Db.Query('SELECT table_name'+Registry+';');
    if Length(Rows)=1 then
    begin
      TableName:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
      AdminOnly:=Setting('boardCreationAdminOnly');PrivateOnly:=Setting('allowPrivateOnly');
      RegistryGuard:='(SELECT count(*)'+Registry+' AND table_name='+QuotedStr(Rows[0][0])+')=1';
    end else if Length(Rows)=0 then RegistryGuard:='NOT EXISTS(SELECT 1'+Registry+')'
    else raise Exception.Create('Ambiguous board creation policy');
  end;
end;

procedure ApiCreateBoard(aRequest:TRequest;aResponse:TResponse);
const Colors='|belize|nephritis|pomegranate|pumpkin|wisteria|moderatepink|strongcyan|limegreen|midnight|dark|'+
  'relax|corteza|appleglasspastel|clearblue|cleargreen|clearorange|clearpink|clearpurple|clearred|natural|modern|moderndark|exodark|cleandark|cleanlight|';
var T:TWLTenant;Actor,Title,Visibility,Color,Board,Lane,ActorScope,AdminOnly,PrivateOnly,RegistryGuard,
  Stamp,Sql,Permission,DefaultTitle,BoardId,LaneId:string;Rows:TWLRows;Reply:TJSONObject;
  Words:TWLTranslator;Body:TJSONObject;Value:TJSONData;

begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  Title:=BodyField(aRequest,'title');Visibility:=BodyField(aRequest,'permission');Color:=BodyField(aRequest,'color');
  Body:=nil;
  try
    try
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
      begin
        Body:=ExactObject(aRequest.Content);Value:=Body.Find('title');
        if not (Value is TJSONString) then raise Exception.Create('Missing board title');
        Title:=Value.AsString;
      end;
      CheckUtf8(Title);
      if (Trim(Title)='') or (Pos(#0,Title)>0) then raise Exception.Create('Invalid board title');
      if Visibility='' then Visibility:='private';
      if (Visibility<>'private') and (Visibility<>'public') then raise Exception.Create('Invalid board permission');
      if Color='' then Color:='belize';
      if (Pos('|',Color)>0) or (Pos('|'+Color+'|',Colors)=0) then raise Exception.Create('Invalid board color');
    except SendError(aResponse,400,'Invalid board settings');Exit;end;
  finally Body.Free;end;
  try BoardCreationSettings(T.Db,AdminOnly,PrivateOnly,RegistryGuard);
  except SendError(aResponse,500,'Could not read board creation policy');Exit;end;
  Actor:=QuotedStr(Actor);ActorScope:='id='+Actor+' AND COALESCE(loginDisabled,0)=0';
  Permission:='EXISTS(SELECT 1 FROM users WHERE '+ActorScope+' AND (isAdmin=1 OR NOT '+AdminOnly+'))';
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board creation is restricted to admins');Exit;end;
  BoardId:=NewId;LaneId:=NewId;Board:=QuotedStr(BoardId);Lane:=QuotedStr(LaneId);Stamp:=QuotedStr(NowIso);
  Words:=TWLTranslator.Create(ViewerLanguage(T.Db,Default(TWLSession),aRequest));
  try DefaultTitle:=QuotedStr(Words.Text('default','Default'));finally Words.Free;end;
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+AuthSourceCondition(T.Db)+' AND '+RegistryGuard+' AND '+Permission+
    ' THEN 1 ELSE json(''Board creation policy changed'') END; '+
    'INSERT INTO boards(id,title,slug,permission,color,createdAt,modifiedAt) VALUES('+Board+','+
    QuotedStr(Title)+','+QuotedStr(Slugify(Title))+',CASE WHEN '+PrivateOnly+' THEN ''private'' ELSE '+QuotedStr(Visibility)+
    ' END,'+QuotedStr(Color)+','+Stamp+','+Stamp+'); '+
    'INSERT INTO board_members(boardId,userId,isAdmin,isActive,isNoComments,isCommentOnly,isWorker) VALUES('+
    Board+','+Actor+',1,1,0,0,0); '+
    'INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES('+Lane+','+Board+','+DefaultTitle+',0,'+Stamp+'); '+
    'SELECT CASE WHEN EXISTS(SELECT 1 FROM board_members WHERE boardId='+Board+' AND userId='+Actor+
    ' AND isAdmin=1 AND isActive=1) AND EXISTS(SELECT 1 FROM swimlanes WHERE id='+Lane+
    ' AND boardId='+Board+') THEN 1 ELSE json(''Board creation incomplete'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create board');Exit;end;
  Reply:=TJSONObject.Create(['_id',BoardId,'defaultSwimlaneId',LaneId]);
  try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
end;

function CardDateSql(Value:TJSONData;out Literal:string):Boolean; forward;

procedure WriteFileBytes(const Path,Data:string); forward;

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
function CustomValueLiteral(Data:TJSONData;out Value:string):Boolean;
var i:Integer;
begin
  Result:=False;Value:='';
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
  Result:=True;
end;

procedure ApiImportBoard(aRequest:TRequest;aResponse:TResponse);
const Collections:array[0..11] of string=('swimlanes','lists','cards','triggers','actions','rules',
  'comments','checklists','checklistItems','attachments','customFields','labels');
var T:TWLTenant;Actor,BoardId,Board,Title,AdminOnly,PrivateOnly,RegistryGuard,Permission,Stamp,Guard,Sql,Name,CardId,CardAuthor,CardCreated,DefaultLane,DefaultList,ListId,LaneId:string;
  Body,Input,Row,Reply,MemberMap,CardCreations,ImportedListLanes:TJSONObject;Maps:array[0..11] of TJSONObject;Arrays:array[0..11] of TJSONArray;
  Value:TJSONData;Rows:TWLRows;CardNumbers:array of Int64;I,J:Integer;Files,ImportedMembers:TStringList;Committed:Boolean;
  function Text(Obj:TJSONObject;const Key:string;const Fallback:string=''):string;
  var Field:TJSONData;
  begin
    Field:=Obj.Find(Key);
    if (Field=nil) or (Field.JSONType=jtNull) then Exit(Fallback);
    if not (Field is TJSONString) or (Pos(#0,Field.AsString)>0) then
      raise EConvertError.Create('Invalid import text field');
    Result:=Field.AsString;
  end;
  function ImportedAuthor(Obj:TJSONObject):string;
  begin Result:=MemberMap.Get(Text(Obj,'userId'),Actor);end;
  procedure ReadMemberMapping;
  var Mapping,Target:TJSONData;Source:TSelectionScope;FindUser,Identity,SourceId:string;Found:TWLRows;K:Integer;
  begin
    Mapping:=Body.Find('membersMapping');
    if Mapping=nil then Exit;
    if not (Mapping is TJSONObject) then raise EConvertError.Create('Invalid member mapping');
    Source:=TSelectionScope.Create(T.Db);
    try
      FindUser:=Source.StringField('users','id');
      for K:=0 to Mapping.Count-1 do
      begin
        Target:=Mapping.Items[K];SourceId:=TJSONObject(Mapping).Names[K];
        if not (Target is TJSONString) or (Target.AsString='') or (Pos(#0,Target.AsString)>0) or
          (SourceId='') or (Pos(#0,SourceId)>0) then raise EConvertError.Create('Invalid member identity');
        Identity:='(SELECT count(*) FROM users WHERE id='+QuotedStr(Target.AsString)+
          ' AND COALESCE(loginDisabled,0)=0 AND '+FindUser+')=1';
        Found:=T.Db.Query('SELECT '+Identity+';');
        if (Length(Found)<>1) or (Found[0][0]<>'1') then raise EConvertError.Create('Invalid mapped account');
        Guard:=Guard+' AND '+Identity;
        MemberMap.Add(SourceId,Target.AsString);
      end;
    finally Source.Free;end;
  end;
  procedure ImportInactiveMembers;
  var Members,Entry:TJSONData;LocalId:string;K:Integer;
  begin
    Members:=Input.Find('members');
    if not (Members is TJSONArray) then Exit;
    for K:=0 to Members.Count-1 do
    begin
      Entry:=Members.Items[K];if not (Entry is TJSONObject) then Continue;
      LocalId:=MemberMap.Get(Text(TJSONObject(Entry),'userId',Text(TJSONObject(Entry),'id')),'');
      if (LocalId='') or (LocalId=Actor) or (ImportedMembers.IndexOf(LocalId)>=0) then Continue;
      ImportedMembers.Add(LocalId);
      Sql:=Sql+'INSERT INTO board_members(boardId,userId,isActive,isAdmin) VALUES('+Board+','+
        QuotedStr(LocalId)+',0,0); ';
    end;
  end;
  procedure ImportCardPeople(Entry:TJSONObject;const Id:string);
  var Source:TJSONData;Selected:TStringList;Extra:TJSONObject;Items:TJSONArray;
    Field,LocalId,Column:string;K:Integer;
  begin
    Selected:=TStringList.Create;Selected.CaseSensitive:=True;Extra:=TJSONObject.Create;
    try
      Sql:=Sql+InitializeSharedAssignments(T.Db,BoardId,Id,True,True);
      for Field in ['members','assignees','requesters','assigners'] do
      begin
        Selected.Clear;Source:=Entry.Find(Field);
        if (Source=nil) or (Source.JSONType=jtNull) then Continue;
        if not (Source is TJSONArray) then raise EConvertError.Create('Invalid card participant list');
        for K:=0 to Source.Count-1 do
        begin
          if not (Source.Items[K] is TJSONString) then raise EConvertError.Create('Invalid card participant');
          LocalId:=MemberMap.Get(Source.Items[K].AsString,'');
          if (LocalId<>'') and (Selected.IndexOf(LocalId)<0) then Selected.Add(LocalId);
        end;
        if (Field='members') or (Field='assignees') then
        begin
          if Field='members' then Column:='card_members' else Column:='card_assignees';
          for K:=0 to Selected.Count-1 do
            Sql:=Sql+'INSERT INTO '+Column+'(cardId,userId) VALUES('+QuotedStr(Id)+','+QuotedStr(Selected[K])+'); ';
        end else
        begin
          Items:=TJSONArray.Create;Extra.Add(Field,Items);
          for K:=0 to Selected.Count-1 do Items.Add(Selected[K]);
        end;
      end;
      if Extra.Count>0 then
        Sql:=Sql+'UPDATE cards SET extra_json=json_patch(extra_json,'+QuotedStr(Extra.AsJSON)+
          ') WHERE id='+QuotedStr(Id)+' AND boardId='+Board+'; ';
    finally Extra.Free;Selected.Free;end;
  end;
  function Mapped(Index:Integer;const Id:string;Required:Boolean=False):string;
  begin
    Result:=Maps[Index].Get(Id,'');
    if Required and (Result='') then raise EConvertError.Create('Invalid import reference');
  end;
  procedure ImportLabels;
  var Entry:TJSONObject;K:Integer;
  begin
    if Arrays[11]=nil then Exit;
    for K:=0 to Arrays[11].Count-1 do
    begin
      Entry:=Arrays[11].Objects[K];
      Sql:=Sql+'INSERT INTO board_labels(boardId,id,name,color) VALUES('+Board+','+
        QuotedStr(Mapped(11,Text(Entry,'_id'),True))+','+QuotedStr(Text(Entry,'name'))+','+
        QuotedStr(Text(Entry,'color','green'))+'); ';
    end;
  end;
  procedure ImportCardLabels(Entry:TJSONObject;const CardKey:string);
  var Labels:TJSONData;LabelKey:string;K:Integer;
  begin
    Labels:=Entry.Find('labelIds');
    if (Labels=nil) or (Labels.JSONType=jtNull) then Exit;
    if not (Labels is TJSONArray) then raise EConvertError.Create('Invalid imported card labels');
    for K:=0 to Labels.Count-1 do
    begin
      if not (Labels.Items[K] is TJSONString) then raise EConvertError.Create('Invalid imported card label');
      LabelKey:=QuotedStr(Mapped(11,Labels.Items[K].AsString,True));
      Sql:=Sql+'INSERT INTO card_labels(cardId,labelId) SELECT '+QuotedStr(CardKey)+','+LabelKey+
        ' WHERE NOT EXISTS(SELECT 1 FROM card_labels WHERE cardId='+QuotedStr(CardKey)+' AND labelId='+LabelKey+'); ';
    end;
  end;
  procedure ImportAttachedCards(Entry:TJSONObject;const CardKey:string);
  var Source:TJSONData;Targets:TJSONArray;Seen:TStringList;Target:string;K:Integer;
  begin
    Source:=Entry.Find('attachedCardIds');
    if not (Source is TJSONArray) then Exit;
    Targets:=TJSONArray.Create;Seen:=TStringList.Create;
    try
      Seen.CaseSensitive:=True;
      for K:=0 to Source.Count-1 do
      begin
        if not (Source.Items[K] is TJSONString) then Continue;
        Target:=Mapped(2,Source.Items[K].AsString);
        if (Target='') or (Target=CardKey) or (Seen.IndexOf(Target)>=0) then Continue;
        Seen.Add(Target);Targets.Add(Target);
      end;
      if Targets.Count>0 then
        Sql:=Sql+'UPDATE cards SET extra_json=json_set(extra_json,''$.attachedCardIds'',json('+
          QuotedStr(Targets.AsJSON)+')) WHERE id='+QuotedStr(CardKey)+' AND boardId='+Board+'; ';
    finally Seen.Free;Targets.Free;end;
  end;
  procedure ImportCardDependencies(Entry:TJSONObject;const CardKey:string);
  var Dependencies,Item:TJSONData;Link:TJSONObject;K:Integer;Target,Kind,Color,Icon,Source:string;
  begin
    Dependencies:=Entry.Find('cardDependencies');
    if (Dependencies=nil) or (Dependencies.JSONType=jtNull) then Exit;
    if not (Dependencies is TJSONArray) then raise EConvertError.Create('Invalid imported card dependencies');
    Source:=QuotedStr(CardKey);
    for K:=0 to Dependencies.Count-1 do
    begin
      Item:=Dependencies.Items[K];
      Kind:='related-to';Color:='#eb144c';Icon:='link';
      if Item is TJSONString then Target:=Mapped(2,Item.AsString)
      else if Item is TJSONObject then
      begin
        Link:=TJSONObject(Item);Target:=Mapped(2,Text(Link,'cardId'));
        if Target='' then Continue;
        Kind:=Text(Link,'type',Kind);Color:=Text(Link,'color',Color);Icon:=Text(Link,'icon',Icon);
      end else raise EConvertError.Create('Invalid imported card dependency');
      if Target='' then Continue;
      Target:=QuotedStr(Target);Kind:=QuotedStr(Kind);
      Sql:=Sql+'INSERT INTO card_dependencies(cardId,targetCardId,type,color,icon) SELECT '+
        Source+','+Target+','+Kind+','+QuotedStr(Color)+','+QuotedStr(Icon)+
        ' WHERE NOT EXISTS(SELECT 1 FROM card_dependencies WHERE cardId='+Source+' AND targetCardId='+Target+
        ' AND type='+Kind+'); ';
    end;
  end;
  procedure ImportDefinitions;
  var Entry,Settings:TJSONObject;Id,FieldName,Kind,Dropdown,DropdownGuard:string;
    Flags:TDefinitionFlags;AlwaysOn,K,L:Integer;
  begin
    if Arrays[10]=nil then Exit;
    for K:=0 to Arrays[10].Count-1 do
    begin
      Entry:=Arrays[10].Objects[K];
      Id:=QuotedStr(Mapped(10,Text(Entry,'_id'),True));
      FieldName:=Text(Entry,'name');Kind:=Text(Entry,'type','text');
      if (Trim(FieldName)='') or not ValidDefinitionType(Kind) then
        raise EConvertError.Create('Invalid imported custom-field definition');
      for L:=0 to High(Flags) do
        if not DefinitionFlag(Entry.Find(DefinitionFlagNames[L]),Flags[L]) then
          raise EConvertError.Create('Invalid imported custom-field flag');
      if not DefinitionFlag(Entry.Find('alwaysOnCard'),AlwaysOn) then
        raise EConvertError.Create('Invalid imported custom-field flag');
      if not SettingsInput(Entry.Find('settings'),Settings) then
        raise EConvertError.Create('Invalid imported custom-field settings');
      try
        Dropdown:=DropdownScript(T.Db,Mapped(10,Text(Entry,'_id'),True),Settings,DropdownGuard);
        Sql:=Sql+Format('INSERT INTO custom_fields(id,name,type,showOnCard,automaticallyOnCard,'+
          'showLabelOnMiniCard,showSumAtTopOfList,readOnly,adminOnly,alwaysOnCard,createdAt,modifiedAt,'+
          'currencyCode,stringtemplateFormat,stringtemplateSeparator,settings_json) '+
          'VALUES(%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%s,%s,%s,%s,%s,%s); ',
          [Id,QuotedStr(FieldName),QuotedStr(Kind),Flags[0],Flags[1],Flags[2],Flags[3],Flags[4],Flags[5],
           AlwaysOn,Stamp,Stamp,SettingsLiteral(Settings,'currencyCode'),SettingsLiteral(Settings,'stringtemplateFormat'),
           SettingsLiteral(Settings,'stringtemplateSeparator'),SettingsRemainder(Settings)])+
          'INSERT INTO custom_field_boards(customFieldId,boardId) VALUES('+Id+','+Board+'); '+Dropdown+DropdownGuard;
      finally Settings.Free;end;
    end;
  end;
  procedure ImportCardFields(Entry:TJSONObject;const Id:string);
  var Fields,Data:TJSONData;Field:TJSONObject;Seen:TStringList;FieldId,Literal:string;K:Integer;
  begin
    Fields:=Entry.Find('customFields');
    if (Fields=nil) or (Fields.JSONType=jtNull) then Exit;
    if not (Fields is TJSONArray) then raise EConvertError.Create('Invalid imported custom-field values');
    Seen:=TStringList.Create;
    try
      Seen.CaseSensitive:=True;
      for K:=0 to Fields.Count-1 do
      begin
        if not (Fields.Items[K] is TJSONObject) then raise EConvertError.Create('Invalid imported custom-field value');
        Field:=TJSONObject(Fields.Items[K]);FieldId:=Mapped(10,Text(Field,'_id'),True);
        if Seen.IndexOf(FieldId)>=0 then raise EConvertError.Create('Duplicate imported custom-field value');
        Seen.Add(FieldId);Data:=Field.Find('value');
        if (Data=nil) or (Data.JSONType=jtNull) then Literal:='NULL'
        else if not CustomValueLiteral(Data,Literal) then raise EConvertError.Create('Invalid imported custom-field value');
        Sql:=Sql+'INSERT INTO card_custom_field_values(cardId,customFieldId,value) VALUES('+
          QuotedStr(Id)+','+QuotedStr(FieldId)+','+Literal+'); ';
      end;
    finally Seen.Free;end;
  end;
  function Optional(const TextValue:string):string;
  begin
    if TextValue='' then Result:='NULL' else Result:=QuotedStr(TextValue);
  end;
  procedure CardPlacement(Obj:TJSONObject;out ListKey,LaneKey:string);
  begin
    ListKey:=Mapped(1,Text(Obj,'listId'));
    if ListKey='' then ListKey:=DefaultList;
    LaneKey:=ImportedListLanes.Get(ListKey,'');
    if LaneKey='' then LaneKey:=Mapped(0,Text(Obj,'swimlaneId'));
    if LaneKey='' then LaneKey:=DefaultLane;
  end;
  function SortValue(Obj:TJSONObject):string;
  var Field:TJSONData;
  begin
    Result:='0';Field:=Obj.Find('sort');
    if (Field<>nil) and (Field.JSONType=jtNumber) and not IsNan(Field.AsFloat) and not IsInfinite(Field.AsFloat) then
      Result:=Field.AsJSON;
  end;
  function ImportedDate(Obj:TJSONObject;const Key,Fallback:string):string;
  var Field:TJSONData;
  begin
    Result:=Fallback;Field:=Obj.Find(Key);
    if (Field=nil) or (Field.JSONType=jtNull) then Exit;
    if not CardDateSql(Field,Result) then raise EConvertError.Create('Invalid imported date');
    if Result='NULL' then Result:=Fallback;
  end;
  function BooleanValue(Obj:TJSONObject;const Key:string):string;
  var Field:TJSONData;
  begin
    Field:=Obj.Find(Key);
    Result:=IntToStr(Ord((Field is TJSONBoolean) and Field.AsBoolean));
  end;
  function ImportedCollapse(Entry:TJSONObject):string;
  var Field:TJSONData;
  begin
    Field:=Entry.Find('collapsed');
    if not (Field is TJSONBoolean) then Exit('NULL');
    Result:=BooleanValue(Entry,'collapsed');
  end;
  function ImportedColor(Entry:TJSONObject):string;
  var Field:TJSONData;Color:string;
  begin
    Field:=Entry.Find('color');
    if not (Field is TJSONString) then Exit('NULL');
    Color:=Field.AsString;
    if ResolveColor(Color)='' then Exit('NULL');
    Result:=QuotedStr(Color);
  end;
  function ImportedListWidth(Entry:TJSONObject):string;
  var Field:TJSONData;Width:Double;
  begin
    Field:=Entry.Find('width');
    if (Field=nil) or (Field.JSONType<>jtNumber) then Exit('272');
    Width:=Field.AsFloat;
    if IsNan(Width) or (Width<100) or (Width>1000) or (Width<>Trunc(Width)) then Exit('272');
    Result:=IntToStr(Trunc(Width));
  end;
  procedure AllocateCardNumbers;
  const MaxSequence=9007199254740990;
  var Used:TStringList;Field:TJSONData;Number:Double;K:Integer;Next:Int64;Key:string;
  begin
    if Arrays[2]=nil then Exit;
    SetLength(CardNumbers,Arrays[2].Count);
    Used:=TStringList.Create;
    try
      Used.Sorted:=True;
      for K:=0 to High(CardNumbers) do
      begin
        Field:=Arrays[2].Objects[K].Find('cardNumber');
        if (Field=nil) or (Field.JSONType<>jtNumber) then Continue;
        Number:=Field.AsFloat;
        if IsNan(Number) or (Number<1) or (Number>MaxSequence) or (Number<>Trunc(Number)) then Continue;
        Key:=IntToStr(Trunc(Number));
        if Used.IndexOf(Key)>=0 then Continue;
        Used.Add(Key);
        CardNumbers[K]:=Trunc(Number);
      end;
      Next:=1;
      for K:=0 to High(CardNumbers) do if CardNumbers[K]=0 then
      begin
        while Used.IndexOf(IntToStr(Next))>=0 do Inc(Next);
        CardNumbers[K]:=Next;
        Inc(Next);
      end;
    finally Used.Free;end;
  end;
  procedure IndexCardCreations;
  var Activities,Item,Kind,SourceId:TJSONData;Entry:TJSONObject;Id:string;K:Integer;
  begin
    Activities:=Input.Find('activities');
    if (Activities=nil) or (Activities.JSONType=jtNull) then Exit;
    if not (Activities is TJSONArray) then raise EConvertError.Create('Invalid imported activities');
    for K:=0 to Activities.Count-1 do
    begin
      Item:=Activities.Items[K];
      if not (Item is TJSONObject) then Continue;
      Entry:=TJSONObject(Item);Kind:=Entry.Find('activityType');SourceId:=Entry.Find('cardId');
      if not (Kind is TJSONString) or (Kind.AsString<>'createCard') or not (SourceId is TJSONString) then Continue;
      Id:=Mapped(2,SourceId.AsString);
      if Id='' then Continue;
      CardCreations.Delete(Id);CardCreations.Add(Id,K);
    end;
  end;
  procedure CardCreation(Entry:TJSONObject;const Id:string;out Author,Created:string);
  var Activities:TJSONArray;Event:TJSONObject;Field,Index:TJSONData;Literal:string;
  begin
    Author:=ImportedAuthor(Entry);Created:='';
    Index:=CardCreations.Find(Id);
    if Index<>nil then
    begin
      Activities:=TJSONArray(Input.Find('activities'));Event:=Activities.Objects[Index.AsInteger];
      Field:=Event.Find('userId');
      if (Field is TJSONString) and (Field.AsString<>'') then Author:=MemberMap.Get(Field.AsString,Actor);
      Field:=Event.Find('createdAt');
      if (Field<>nil) and CardDateSql(Field,Literal) and (Literal<>'NULL') then Created:=Literal;
    end;
    if Created='' then Created:=ImportedDate(Entry,'createdAt',Stamp);
  end;
  function ImportedSpentTime(Entry:TJSONObject):string;
  var Field:TJSONData;
  begin
    Field:=Entry.Find('spentTime');
    if (Field=nil) or (Field.JSONType=jtNull) then Exit('NULL');
    if (Field.JSONType<>jtNumber) or IsNan(Field.AsFloat) or IsInfinite(Field.AsFloat) then
      raise EConvertError.Create('Invalid imported spent time');
    Result:=Field.AsJSON;
  end;
  procedure ImportCardChildren;
  var K,L:Integer;Entry,Checklist:TJSONObject;Id,CardKey,CheckKey,OriginalCheck,Parent:string;
  begin
    if Arrays[6]<>nil then for K:=0 to Arrays[6].Count-1 do
    begin
      Entry:=Arrays[6].Objects[K];
      Id:=QuotedStr(Mapped(6,Text(Entry,'_id'),True));
      CardKey:=QuotedStr(Mapped(2,Text(Entry,'cardId'),True));
      Parent:=Mapped(6,Text(Entry,'parentId'));
      Sql:=Sql+'INSERT INTO card_comments(id,boardId,cardId,userId,text,parentId,createdAt,modifiedAt) VALUES('+
        Id+','+Board+','+CardKey+','+QuotedStr(ImportedAuthor(Entry))+','+QuotedStr(Text(Entry,'text'))+','+QuotedStr(Parent)+','+
        ImportedDate(Entry,'createdAt',Stamp)+','+ImportedDate(Entry,'modifiedAt',Stamp)+'); ';
    end;
    if Arrays[7]<>nil then for K:=0 to Arrays[7].Count-1 do
    begin
      Entry:=Arrays[7].Objects[K];
      Id:=QuotedStr(Mapped(7,Text(Entry,'_id'),True));
      CardKey:=QuotedStr(Mapped(2,Text(Entry,'cardId'),True));
      Sql:=Sql+'INSERT INTO checklists(id,boardId,cardId,title,sort,finishedAt,dueAt,hideCheckedChecklistItems,'+
        'hideAllChecklistItems,showChecklistAtMinicard,createdAt,modifiedAt) VALUES('+
        Id+','+Board+','+CardKey+','+QuotedStr(Text(Entry,'title','Checklist'))+','+SortValue(Entry)+','+
        ImportedDate(Entry,'finishedAt','NULL')+','+ImportedDate(Entry,'dueAt','NULL')+','+
        BooleanValue(Entry,'hideCheckedChecklistItems')+','+BooleanValue(Entry,'hideAllChecklistItems')+','+
        BooleanValue(Entry,'showChecklistAtMinicard')+','+ImportedDate(Entry,'createdAt',Stamp)+','+
        ImportedDate(Entry,'modifiedAt',Stamp)+'); ';
    end;
    if Arrays[8]<>nil then for K:=0 to Arrays[8].Count-1 do
    begin
      Entry:=Arrays[8].Objects[K];
      Id:=QuotedStr(Mapped(8,Text(Entry,'_id'),True));
      OriginalCheck:=Text(Entry,'checklistId');
      CheckKey:=QuotedStr(Mapped(7,OriginalCheck,True));
      Checklist:=nil;
      for L:=0 to Arrays[7].Count-1 do
        if Text(Arrays[7].Objects[L],'_id')=OriginalCheck then begin Checklist:=Arrays[7].Objects[L];Break;end;
      if Checklist=nil then raise EConvertError.Create('Invalid imported checklist');
      CardKey:=Text(Checklist,'cardId');
      if Text(Entry,'cardId',CardKey)<>CardKey then raise EConvertError.Create('Invalid checklist item card');
      CardKey:=QuotedStr(Mapped(2,CardKey,True));
      Sql:=Sql+'INSERT INTO checklist_items(id,boardId,checklistId,cardId,title,sort,isFinished,createdAt,dueAt,'+
        'modifiedAt) VALUES('+Id+','+Board+','+CheckKey+','+CardKey+','+QuotedStr(Text(Entry,'title'))+','+
        SortValue(Entry)+','+BooleanValue(Entry,'isFinished')+','+ImportedDate(Entry,'createdAt','NULL')+','+
        ImportedDate(Entry,'dueAt','NULL')+','+ImportedDate(Entry,'modifiedAt',Stamp)+'); ';
    end;
  end;
  procedure ImportAttachments;
  var K,L:Integer;Entry,Card:TJSONObject;FileField:TJSONData;Id,CardId,CardKey,ListKey,LaneKey,Filename,
    Mime,Encoded,Bytes,Path:string;
  begin
    if Arrays[9]=nil then Exit;
    for K:=0 to Arrays[9].Count-1 do
    begin
      Entry:=Arrays[9].Objects[K];Id:=Mapped(9,Text(Entry,'_id'),True);
      Card:=nil;CardId:=Text(Entry,'cardId');CardKey:='NULL';ListKey:='NULL';LaneKey:='NULL';
      if CardId<>'' then
      begin
        CardKey:=QuotedStr(Mapped(2,CardId,True));
        for L:=0 to Arrays[2].Count-1 do
          if Text(Arrays[2].Objects[L],'_id')=CardId then begin Card:=Arrays[2].Objects[L];Break;end;
        if Card=nil then raise EConvertError.Create('Invalid attachment card');
        CardPlacement(Card,ListKey,LaneKey);
        ListKey:=QuotedStr(ListKey);LaneKey:=QuotedStr(LaneKey);
      end;
      Filename:=Text(Entry,'name','file');Mime:=Text(Entry,'type','application/octet-stream');
      if Filename='' then Filename:='file';
      if Mime='' then Mime:='application/octet-stream';
      if (Pos(#13,Filename+Mime)>0) or (Pos(#10,Filename+Mime)>0) then
        raise EConvertError.Create('Invalid attachment name or type');
      FileField:=Entry.Find('file');
      if not (FileField is TJSONString) then raise EConvertError.Create('Attachment bytes missing');
      Encoded:=FileField.AsString;
      try Bytes:=DecodeStringBase64(Encoded,True);
      except raise EConvertError.Create('Invalid attachment encoding');end;
      if EncodeStringBase64(Bytes)<>Encoded then raise EConvertError.Create('Invalid attachment encoding');
      Path:=StoreFilePath(T.FilesDir,'attachme',Id);
      if FileExists(Path) or not ForceDirectories(ExtractFileDir(Path)) then
        raise Exception.Create('Attachment destination unavailable');
      Files.Add(Path);WriteFileBytes(Path,Bytes);
      Sql:=Sql+'INSERT INTO attachments(id,boardId,swimlaneId,listId,cardId,name,type,size,storageBackend,userId,createdAt) VALUES('+
        QuotedStr(Id)+','+Board+','+LaneKey+','+ListKey+','+CardKey+','+QuotedStr(Filename)+','+QuotedStr(Mime)+
        ','+IntToStr(Length(Bytes))+',''filesystem'','+QuotedStr(ImportedAuthor(Entry))+','+Stamp+'); ';
      Sql:=Sql+'SELECT CASE WHEN EXISTS(SELECT 1 FROM attachments WHERE id='+QuotedStr(Id)+' AND boardId='+Board+
        ' AND size='+IntToStr(Length(Bytes))+') THEN 1 ELSE json(''Attachment import failed'') END; ';
      if (Card<>nil) and (Text(Card,'coverId')=Text(Entry,'_id')) then
        Sql:=Sql+'UPDATE cards SET coverId='+QuotedStr(Id)+' WHERE id='+CardKey+' AND boardId='+Board+'; ';
    end;
  end;
  procedure PutString(Obj:TJSONObject;const Key,Content:string);
  begin Obj.Delete(Key);Obj.Add(Key,Content);end;
  procedure RemapExtras(Obj:TJSONObject;const Key:string;Index:Integer);
  var Items:TJSONArray;Parts:TJSONData;K:Integer;
  begin
    Parts:=Obj.Find(Key);if Parts=nil then Exit;
    if not (Parts is TJSONArray) then raise EConvertError.Create('Invalid workflow extras');
    Items:=TJSONArray.Create;
    try
      for K:=0 to Parts.Count-1 do
      begin
        if not (Parts.Items[K] is TJSONString) then raise EConvertError.Create('Invalid workflow extra');
        Items.Add(Mapped(Index,Parts.Items[K].AsString,True));
      end;
      Obj.Delete(Key);Obj.Add(Key,Items);Items:=nil;
    finally Items.Free;end;
  end;
  procedure ImportWorkflow(Index:Integer);
  var Source,TableName,Payload,Id,Key:string;Found:TWLRows;K:Integer;Part:TJSONObject;
  begin
    if (Arrays[Index]=nil) or (Arrays[Index].Count=0) then Exit;
    Name:=Collections[Index];
    if not EnsureSharedCollection(T.Db,Name) then raise Exception.Create('Workflow collection unavailable');
    Found:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(Name)+';');
    if Length(Found)<>1 then raise Exception.Create('Ambiguous workflow collection');
    Source:=Found[0][0];TableName:='"'+StringReplace(Source,'"','""',[rfReplaceAll])+'"';
    Guard:=Guard+' AND (SELECT count(*) FROM _ferretdb_collections WHERE name='+QuotedStr(Name)+
      ' AND table_name='+QuotedStr(Source)+')=1';
    for K:=0 to Arrays[Index].Count-1 do
    begin
      Part:=TJSONObject(Arrays[Index].Objects[K].Clone);
      try
        Id:=Mapped(Index,Text(Part,'_id'),True);
        for Key in ['createdAt','modifiedAt','updatedAt'] do Part.Delete(Key);
        PutString(Part,'_id',Id);PutString(Part,'boardId',BoardId);
        if (Index in [3,4]) and (Text(Part,'labelId')<>'') then
          PutString(Part,'labelId',Mapped(11,Text(Part,'labelId'),True));
        case Index of
          3: begin
            if Text(Part,'activityType')='' then raise EConvertError.Create('Invalid imported trigger');
            NormalizeRuleTrigger(Part);
          end;
          4: if Text(Part,'actionType')='' then raise EConvertError.Create('Invalid imported action');
          5: begin
            PutString(Part,'triggerId',Mapped(3,Text(Part,'triggerId'),True));
            PutString(Part,'actionId',Mapped(4,Text(Part,'actionId'),True));
            RemapExtras(Part,'extraTriggerIds',3);RemapExtras(Part,'extraActionIds',4);
          end;
        end;
        Payload:=QuotedStr(TypedDocument(Part.AsJSON,'','{}'));
        Sql:=Sql+'INSERT INTO '+TableName+'(_ferretdb_sjson) VALUES(CASE WHEN wl_storage('+QuotedStr(Source)+
          ')=''blob'' THEN jsonb('+Payload+') ELSE '+Payload+' END); ';
      finally Part.Free;end;
    end;
  end;
  procedure ReadImportPolicy;
  var Found:TWLRows;Physical,Registry:string;
  begin
    if Length(T.Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))<>1 then Exit;
    Registry:=' FROM _ferretdb_collections WHERE name=''settings''';
    Found:=T.Db.Query('SELECT table_name'+Registry+';');
    if Length(Found)=0 then
    begin Guard:=Guard+' AND NOT EXISTS(SELECT 1'+Registry+')';Exit;end;
    if Length(Found)<>1 then raise Exception.Create('Ambiguous import settings');
    Physical:='"'+StringReplace(Found[0][0],'"','""',[rfReplaceAll])+'"';
    Guard:=Guard+' AND (SELECT count(*)'+Registry+' AND table_name='+QuotedStr(Found[0][0])+')=1';
    Permission:=Permission+' AND NOT EXISTS(SELECT 1 FROM '+Physical+
      ' WHERE json_type(_ferretdb_sjson,''$.disableAllImport'')=''true'')';
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  Body:=nil;Guard:='1';Committed:=False;Files:=TStringList.Create;
  MemberMap:=TJSONObject.Create;CardCreations:=TJSONObject.Create;ImportedListLanes:=TJSONObject.Create;ImportedMembers:=TStringList.Create;ImportedMembers.CaseSensitive:=True;
  for I:=0 to High(Maps) do Maps[I]:=nil;
  try
    try
      try Body:=ExactObject(aRequest.Content);
      except raise EConvertError.Create('Invalid board export JSON');end;
      Value:=Body.Find('board');
      if not (Value is TJSONObject) then raise EConvertError.Create('Missing board export');
      Input:=TJSONObject(Value);
      Name:=Text(Input,'_format');
      if (Name<>'') and (Name<>'wekan-board-1.0.0') then raise EConvertError.Create('Invalid board export format');
      Title:=Text(Input,'title');
      if Trim(Title)='' then raise EConvertError.Create('Missing board title');
      for I:=0 to High(Maps) do
      begin
        Maps[I]:=TJSONObject.Create;Arrays[I]:=nil;
        Value:=Input.Find(Collections[I]);if Value=nil then Continue;
        if not (Value is TJSONArray) then raise EConvertError.Create('Invalid board export array');
        Arrays[I]:=TJSONArray(Value);
        for J:=0 to Arrays[I].Count-1 do
        begin
          if not (Arrays[I].Items[J] is TJSONObject) then raise EConvertError.Create('Invalid board export row');
          Name:=Text(Arrays[I].Objects[J],'_id');
          if (Name='') or (Maps[I].Find(Name)<>nil) then raise EConvertError.Create('Invalid export identity');
          Maps[I].Add(Name,NewId);
        end;
      end;
      AllocateCardNumbers;
      IndexCardCreations;
      BoardCreationSettings(T.Db,AdminOnly,PrivateOnly,RegistryGuard);
      Permission:='EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(Actor)+
        ' AND COALESCE(loginDisabled,0)=0 AND (isAdmin=1 OR NOT '+AdminOnly+'))';
      ReadImportPolicy;
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin SendError(aResponse,403,'Board import is restricted');Exit;end;
      ReadMemberMapping;
      BoardId:=NewId;Board:=QuotedStr(BoardId);Stamp:=QuotedStr(NowIso);
      Name:=Text(Input,'color','belize');if Name='' then Name:='belize';
      Sql:='INSERT INTO boards(id,title,slug,description,permission,color,createdAt,modifiedAt) VALUES('+
        Board+','+QuotedStr(Title)+','+QuotedStr(Slugify(Title))+','+QuotedStr(Text(Input,'description'))+
        ',''private'','+QuotedStr(Name)+','+Stamp+','+Stamp+'); '+
        'INSERT INTO board_members(boardId,userId,isActive,isAdmin) VALUES('+Board+','+QuotedStr(Actor)+',1,1); ';
      ImportInactiveMembers;
      ImportDefinitions;
      ImportLabels;
      DefaultLane:='';DefaultList:='';
      if Arrays[0]<>nil then for J:=0 to Arrays[0].Count-1 do
      begin
        Row:=Arrays[0].Objects[J];LaneId:=Mapped(0,Text(Row,'_id'),True);
        if DefaultLane='' then DefaultLane:=LaneId;
        Sql:=Sql+'INSERT INTO swimlanes(id,boardId,title,sort,createdAt,color,archived) VALUES('+QuotedStr(LaneId)+
          ','+Board+','+QuotedStr(Text(Row,'title','Default'))+','+SortValue(Row)+','+Stamp+','+
          ImportedColor(Row)+','+BooleanValue(Row,'archived')+'); ';
      end;
      if DefaultLane='' then
      begin
        DefaultLane:=NewId;
        Sql:=Sql+'INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES('+QuotedStr(DefaultLane)+
          ','+Board+',''Default'',0,'+Stamp+'); ';
      end;
      if Arrays[1]<>nil then for J:=0 to Arrays[1].Count-1 do
      begin
        Row:=Arrays[1].Objects[J];ListId:=Mapped(1,Text(Row,'_id'),True);
        LaneId:=Mapped(0,Text(Row,'swimlaneId'));
        if DefaultList='' then DefaultList:=ListId;
        ImportedListLanes.Add(ListId,LaneId);
        Sql:=Sql+'INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt,color,width,archived,collapsed) VALUES('+
          QuotedStr(ListId)+','+Board+','+QuotedStr(LaneId)+','+
          QuotedStr(Text(Row,'title'))+','+SortValue(Row)+','+Stamp+','+ImportedColor(Row)+','+
          ImportedListWidth(Row)+','+BooleanValue(Row,'archived')+','+ImportedCollapse(Row)+'); ';
      end;
      if (DefaultList='') and (Arrays[2]<>nil) and (Arrays[2].Count>0) then
      begin
        DefaultList:=NewId;
        Sql:=Sql+'INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES('+QuotedStr(DefaultList)+
          ','+Board+','''',''Default'',0,'+Stamp+'); ';
      end;
      if Arrays[2]<>nil then for J:=0 to Arrays[2].Count-1 do
      begin
        Row:=Arrays[2].Objects[J];CardId:=Mapped(2,Text(Row,'_id'),True);
        CardCreation(Row,CardId,CardAuthor,CardCreated);
        CardPlacement(Row,ListId,LaneId);
        Sql:=Sql+'INSERT INTO cards(id,boardId,listId,swimlaneId,parentId,title,description,userId,sort,cardNumber,'+
          'createdAt,modifiedAt,dateLastActivity,receivedAt,startAt,dueAt,endAt,spentTime,isOvertime,requestedBy,assignedBy,archived,color) VALUES('+
          QuotedStr(CardId)+','+Board+','+
          QuotedStr(ListId)+','+QuotedStr(LaneId)+','+
          Optional(Mapped(2,Text(Row,'parentId')))+','+QuotedStr(Text(Row,'title'))+','+
          QuotedStr(Text(Row,'description'))+','+QuotedStr(CardAuthor)+','+SortValue(Row)+','+IntToStr(CardNumbers[J])+
          ','+CardCreated+','+Stamp+','+Stamp+','+
          ImportedDate(Row,'receivedAt','NULL')+','+ImportedDate(Row,'startAt','NULL')+','+
          ImportedDate(Row,'dueAt','NULL')+','+ImportedDate(Row,'endAt','NULL')+','+
          ImportedSpentTime(Row)+','+BooleanValue(Row,'isOvertime')+','+QuotedStr(Text(Row,'requestedBy'))+','+
          QuotedStr(Text(Row,'assignedBy'))+','+BooleanValue(Row,'archived')+','+ImportedColor(Row)+'); ';
        ImportCardPeople(Row,CardId);
        ImportCardFields(Row,CardId);
        ImportCardLabels(Row,CardId);
        ImportCardDependencies(Row,CardId);
        ImportAttachedCards(Row,CardId);
      end;
      ImportCardChildren;
      ImportAttachments;
      for I:=3 to 5 do ImportWorkflow(I);
      if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN '+AuthSourceCondition(T.Db)+' AND '+RegistryGuard+
        ' AND '+Guard+' AND '+Permission+' THEN 1 ELSE json(''Board import policy changed'') END; '+Sql+'COMMIT;') then
        raise Exception.Create('Board import failed');
      Committed:=True;
    except
      on E:EConvertError do begin SendError(aResponse,400,'Invalid board export');Exit;end;
      on E:Exception do begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not import board');Exit;end;
    end;
    Reply:=TJSONObject.Create(['_id',BoardId]);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  finally
    if not Committed then for I:=0 to Files.Count-1 do DeleteFile(Files[I]);
    ImportedMembers.Free;ImportedListLanes.Free;CardCreations.Free;MemberMap.Free;Files.Free;
    for I:=0 to High(Maps) do Maps[I].Free;
    Body.Free;
  end;
end;

function CopyBoardWorkflows(Db:TWLDb;const Source,Destination,Actor:string):string;
const Collections:array[0..3] of string=('triggers','actions','rules','integrations');
var Graph,Part:TJSONObject;Copies:TJSONArray;Rows:TWLRows;Raw,TableName,Physical,Storage,Payload,
  Key,Mapped,Guards:string;Maps:array[0..1] of TJSONObject;I,J:Integer;
  procedure SetString(Obj:TJSONObject;const Name,Text:string);
  begin Obj.Delete(Name);Obj.Add(Name,Text);end;
  procedure WriteRow(Row:TJSONObject;const Previous:string);
  begin
    Payload:=QuotedStr(TypedDocument(Row.AsJSON,Previous,'{}'));
    Result:=Result+'INSERT INTO '+Physical+'(_ferretdb_sjson) VALUES(CASE WHEN wl_storage('+QuotedStr(Storage)+
      ')=''blob'' THEN jsonb('+Payload+') ELSE '+Payload+' END); ';
  end;
  procedure RemapParts(Row:TJSONObject;const Primary,Extra:string;IdMap:TJSONObject);
  var Parts:TJSONArray;V:TJSONData;N:Integer;Id:string;
  begin
    Id:=IdMap.Get(Row.Get(Primary,''),'');
    if Id='' then raise Exception.Create('Missing workflow component');
    SetString(Row,Primary,Id);
    V:=Row.Find(Extra);if not (V is TJSONArray) then Exit;
    Parts:=TJSONArray.Create;
    for N:=0 to V.Count-1 do
      if V.Items[N] is TJSONString then
      begin
        Id:=IdMap.Get(V.Items[N].AsString,'');if Id<>'' then Parts.Add(Id);
      end;
    Row.Delete(Extra);Row.Add(Extra,Parts);
  end;
begin
  Result:='';
  if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))=0 then Exit;
  Graph:=TJSONObject.Create;Maps[0]:=nil;Maps[1]:=nil;Guards:='';
  try
    if not Db.BeginRead then raise Exception.Create('Could not pin board workflow source');
    try
      ReadExportWorkflows(Db,Source,Graph);
      for I:=0 to High(Collections) do
      begin
        TableName:=Collections[I];
        Rows:=Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(TableName)+';');
        if Length(Rows)>1 then raise Exception.Create('Ambiguous board workflow source');
        if Length(Rows)=0 then
        begin
          Guards:=Guards+' AND NOT EXISTS(SELECT 1 FROM _ferretdb_collections WHERE name='+QuotedStr(TableName)+')';
          Continue;
        end;
        Storage:=Rows[0][0];Physical:='"'+StringReplace(Storage,'"','""',[rfReplaceAll])+'"';
        Guards:=Guards+' AND (SELECT count(*) FROM _ferretdb_collections WHERE name='+QuotedStr(TableName)+
          ' AND table_name='+QuotedStr(Storage)+')=1';
        if TableName='integrations' then
        begin
          Rows:=Db.Query('SELECT json(_ferretdb_sjson) FROM '+Physical+
            ' WHERE json_extract(_ferretdb_sjson,''$.boardId'')='+QuotedStr(Source)+
            ' AND json_extract(_ferretdb_sjson,''$.$s.p.boardId.t'')=''string'''+
            ' AND json_extract(_ferretdb_sjson,''$.$s.p._id.t'')=''string'';');
          for J:=0 to High(Rows) do
          begin
            Raw:=Rows[J][0];Part:=ExactObject(PlainDocument(Raw));
            try
              SetString(Part,'_id',NewId);SetString(Part,'boardId',Destination);SetString(Part,'userId',Actor);
              WriteRow(Part,Raw);
            finally Part.Free;end;
          end;
          Continue;
        end;
        Copies:=TJSONArray(Graph.Find(TableName));
        if I<2 then Maps[I]:=TJSONObject.Create;
        for J:=0 to Copies.Count-1 do
        begin
          Key:=Copies.Objects[J].Get('_id','');Mapped:=NewId;
          if I<2 then Maps[I].Add(Key,Mapped);
          Rows:=Db.Query('SELECT json(_ferretdb_sjson) FROM '+Physical+
            ' WHERE json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(Key)+
            ' AND json_extract(_ferretdb_sjson,''$.$s.p._id.t'')=''string'';');
          if Length(Rows)<>1 then raise Exception.Create('Workflow source changed');
          Raw:=Rows[0][0];Part:=ExactObject(PlainDocument(Raw));
          try
            SetString(Part,'_id',Mapped);SetString(Part,'boardId',Destination);
            if TableName='rules' then
            begin
              if (Maps[0]=nil) or (Maps[1]=nil) then raise Exception.Create('Missing workflow components');
              RemapParts(Part,'triggerId','extraTriggerIds',Maps[0]);
              RemapParts(Part,'actionId','extraActionIds',Maps[1]);
            end;
            WriteRow(Part,Raw);
          finally Part.Free;end;
        end;
      end;
    finally
      if not Db.EndRead then raise Exception.Create('Could not close board workflow source');
    end;
    if Guards<>'' then Result:='SELECT CASE WHEN 1'+Guards+' THEN 1 ELSE json(''Workflow source changed'') END; '+Result;
  finally Maps[1].Free;Maps[0].Free;Graph.Free;end;
end;

// POST copy board — structural deep copy: board + members + swimlanes + lists + cards, with
// remapped ids. (Labels/checklists/comments copy is TODO.)
procedure ApiBoardCopy(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; UserId, SrcId, Title, NewBoard,Sql,Permission,AdminOnly,PrivateOnly,RegistryGuard,Visibility: string;
  Policy:TFieldPolicy;
  B, Rows: TWLRows;
  swMap, listMap: TStringList;
  i: Integer;
  newSw, newList, newCard: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  SrcId := aRequest.RouteParams['boardId'];
  Policy:=TFieldPolicy.Create(T.Db,UserId,SrcId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board administration required');Exit;end;
  try BoardCreationSettings(T.Db,AdminOnly,PrivateOnly,RegistryGuard);
  except SendError(aResponse,500,'Could not read board creation policy');Exit;end;
  Permission:=Permission+' AND (NOT '+AdminOnly+' OR EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(UserId)+
    ' AND isAdmin=1 AND COALESCE(loginDisabled,0)=0))';
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board creation is restricted to admins');Exit;end;
  Title := BodyField(aRequest, 'title');

  B := T.Db.Query(Format('SELECT title,permission,type,color FROM boards WHERE id=%s LIMIT 1;',
    [QuotedStr(SrcId)]));
  if Length(B) = 0 then begin SendError(aResponse, 404, 'Board not found'); Exit; end;
  if Title = '' then Title := B[0][0] + ' Copy';
  if Pos(#0,Title)>0 then begin SendError(aResponse,400,'Invalid board title');Exit;end;
  NewBoard := NewId;
  Visibility:='CASE WHEN '+PrivateOnly+' THEN ''private'' ELSE '+QuotedStr(B[0][1])+' END';
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+' AND '+RegistryGuard+' THEN 1 ELSE json(''Copy permission changed'') END; '+Format(
    'INSERT INTO boards(id,title,slug,permission,type,color,createdAt,modifiedAt) ' +
    'VALUES(%s,%s,%s,%s,%s,%s,%s,%s);',
    [QuotedStr(NewBoard), QuotedStr(Title), QuotedStr(Slugify(Title)),
     Visibility, QuotedStr(B[0][2]), QuotedStr(B[0][3]),
     QuotedStr(NowIso), QuotedStr(NowIso)]);

  // members
  Rows := T.Db.Query(Format('SELECT userId,isAdmin FROM board_members WHERE boardId=%s AND isActive=1;', [QuotedStr(SrcId)]));
  for i := 0 to High(Rows) do
    if Length(Rows[i]) >= 2 then
      Sql:=Sql+Format('INSERT INTO board_members(boardId,userId,isAdmin) VALUES(%s,%s,%s);',
        [QuotedStr(NewBoard), QuotedStr(Rows[i][0]), QuotedStr(Rows[i][1])]);

  swMap := TStringList.Create; swMap.CaseSensitive := True;
  listMap := TStringList.Create; listMap.CaseSensitive := True;
  try
    // swimlanes
    Rows := T.Db.Query(Format('SELECT id,title,COALESCE(sort,0) FROM swimlanes WHERE boardId=%s;', [QuotedStr(SrcId)]));
    for i := 0 to High(Rows) do
      if Length(Rows[i]) >= 3 then
      begin
        newSw := NewId; swMap.Values[Rows[i][0]] := newSw;
        Sql:=Sql+Format('INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES(%s,%s,%s,%s,%s);',
          [QuotedStr(newSw), QuotedStr(NewBoard), QuotedStr(Rows[i][1]), QuotedStr(Rows[i][2]), QuotedStr(NowIso)]);
      end;
    // lists
    Rows := T.Db.Query(Format('SELECT id,title,COALESCE(sort,0),swimlaneId FROM lists WHERE boardId=%s AND deletedAt IS NULL;', [QuotedStr(SrcId)]));
    for i := 0 to High(Rows) do
      if Length(Rows[i]) >= 4 then
      begin
        newList := NewId; listMap.Values[Rows[i][0]] := newList;
        Sql:=Sql+Format('INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES(%s,%s,%s,%s,%s,%s);',
          [QuotedStr(newList), QuotedStr(NewBoard), QuotedStr(swMap.Values[Rows[i][3]]),
           QuotedStr(Rows[i][1]), QuotedStr(Rows[i][2]), QuotedStr(NowIso)]);
      end;
    // cards
    Rows := T.Db.Query(Format(
      'SELECT id,title,description,listId,swimlaneId,userId,color,COALESCE(sort,0) FROM cards WHERE boardId=%s AND deletedAt IS NULL;',
      [QuotedStr(SrcId)]));
    for i := 0 to High(Rows) do
      if Length(Rows[i]) >= 8 then
      begin
        newCard := NewId;
        Sql:=Sql+Format(
          'INSERT INTO cards(id,boardId,listId,swimlaneId,title,description,userId,color,sort,' +
          'dateLastActivity,createdAt,modifiedAt) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);',
          [QuotedStr(newCard), QuotedStr(NewBoard),
           QuotedStr(listMap.Values[Rows[i][3]]), QuotedStr(swMap.Values[Rows[i][4]]),
           QuotedStr(Rows[i][1]), QuotedStr(Rows[i][2]), QuotedStr(Rows[i][5]),
           QuotedStr(Rows[i][6]), QuotedStr(Rows[i][7]),
           QuotedStr(NowIso), QuotedStr(NowIso), QuotedStr(NowIso)]);
      end;
  finally
    swMap.Free; listMap.Free;
  end;
  try
    Sql:=Sql+CopyBoardWorkflows(T.Db,SrcId,NewBoard,UserId)+'COMMIT;';
    if not T.Db.Exec(Sql) then raise Exception.Create('Board copy failed');
  except T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not copy board');Exit;end;
  SendJson(aResponse,'"'+StringToJSONString(NewBoard)+'"');
end;

procedure ApiSwimlane(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"Swimlane not found"}';
var T:TWLTenant;UserId,BoardId,LaneId,Scope,Title,Permission,Sql:string;
  Rows:TWLRows;Body:TJSONObject;Value:TJSONData;Policy:TFieldPolicy;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];LaneId:=aRequest.RouteParams['swimlaneId'];
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  Scope:='id='+QuotedStr(LaneId)+' AND boardId='+QuotedStr(BoardId);
  if aRequest.Method='GET' then
  begin
    Rows:=T.Db.Query('SELECT json_object(''_id'',id,''boardId'',boardId,''title'',title,''type'',type,'+
      '''color'',color,''sort'',sort,''height'',height,''archived'',json(''false''),''createdAt'',createdAt,'+
      '''modifiedAt'',modifiedAt,''updatedAt'',updatedAt) FROM swimlanes WHERE '+Scope+' AND archived=0;');
    if Length(Rows)<>1 then SendJson(aResponse,NotFound,404)
    else SendJson(aResponse,Rows[0][0]);
    Exit;
  end;
  if Length(T.Db.Query('SELECT id FROM swimlanes WHERE '+Scope+';'))<>1 then
  begin SendJson(aResponse,NotFound,404);Exit;end;
  Body:=nil;
  try
    try
      Title:=aRequest.ContentFields.Values['title'];
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
      begin
        Body:=ExactObject(aRequest.Content);Value:=Body.Find('title');
        if not (Value is TJSONString) then raise Exception.Create('Invalid title');
        Title:=Value.AsString;
      end;
      CheckUtf8(Title);
      if (Trim(Title)='') or (Pos(#0,Title)>0) then raise Exception.Create('Invalid title');
    except SendError(aResponse,400,'Invalid swimlane title');Exit;end;
  finally Body.Free;end;
  Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
  try Permission:=Policy.ScopeBoardExpression(True);finally Policy.Free;end;
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+' AND (SELECT count(*) FROM swimlanes WHERE '+Scope+
    ')=1 THEN 1 ELSE json(''Swimlane scope changed'') END; UPDATE swimlanes SET title='+QuotedStr(Title)+
    ' WHERE '+Scope+'; SELECT CASE WHEN EXISTS(SELECT 1 FROM swimlanes WHERE '+Scope+
    ' AND title='+QuotedStr(Title)+') THEN 1 ELSE json(''Swimlane update failed'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not edit swimlane');Exit;end;
  SendJson(aResponse,'{"_id":"'+StringToJSONString(LaneId)+'"}');
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
        if not CustomValueLiteral(Data,Value) then Exit;
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

function CardCreateSql(const BoardId,ListId,Lane,CardId,Author,Title,Descr,Parent,Sort:string;const LinkedId:string=''):string;
var Stamp,Board:string;
begin
  Stamp:=QuotedStr(NowIso);Board:=QuotedStr(BoardId);
  Result:='INSERT INTO cards(id,boardId,listId,swimlaneId,title,description,userId,parentId,'+
    'dateLastActivity,createdAt,modifiedAt,sort,cardNumber,type,linkedId) SELECT '+QuotedStr(CardId)+','+Board+','+
    QuotedStr(ListId)+','+QuotedStr(Lane)+','+QuotedStr(Title)+','+QuotedStr(Descr)+','+
    QuotedStr(Author)+','+Parent+','+Stamp+','+Stamp+','+Stamp+','+Sort+
    ',(SELECT max(0,coalesce(max(cardNumber),0))+1 FROM cards WHERE boardId='+Board+'),';
  if LinkedId='' then Result:=Result+'''cardType-card'',NULL; '
  else Result:=Result+'''cardType-linkedCard'','+QuotedStr(LinkedId)+'; ';
end;

procedure RecordParentDenial(Db:TWLDb;const UserId:string);
const Hints='{"at":"date","firstAt":"date"}';
  Identity='json_extract(_ferretdb_sjson,''$.stream'')=''security'''+
    ' AND json_extract(_ferretdb_sjson,''$.bleed'')=''ParentBleed'''+
    ' AND json_extract(_ferretdb_sjson,''$.source'')=''parentId'''+
    ' AND json_extract(_ferretdb_sjson,''$.category'')=''authz'''+
    ' AND json_extract(_ferretdb_sjson,''$.action'')=''blocked''';
var Rows:TWLRows;Event:TJSONObject;TableName,Physical,AtSql,Payload,Updated,Sql:string;
  Stamp:TDateTime;AtMs:Int64;
  function Stored(const Data:string):string;
  begin
    Result:='CASE WHEN wl_storage('+QuotedStr(TableName)+')=''blob'' THEN jsonb('+Data+') ELSE '+Data+' END';
  end;
begin
  try
    if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))<>1 then Exit;
    if not EnsureSharedCollection(Db,'eventlog') then Exit;
    Rows:=Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''eventlog'';');
    if Length(Rows)<>1 then Exit;
    TableName:=Rows[0][0];Physical:='"'+StringReplace(TableName,'"','""',[rfReplaceAll])+'"';
    Stamp:=LocalTimeToUniversal(Now);
    AtMs:=DateTimeToUnix(Stamp,True)*1000+MilliSecondOf(Stamp);AtSql:=IntToStr(AtMs);
    Event:=TJSONObject.Create(['_id',NewId,'stream','security','at',AtMs,'firstAt',AtMs,
      'severity','high','category','authz','bleed','ParentBleed','action','blocked','source','parentId',
      'cwe','CWE-862','count',1,'userId',UserId,'detail','A card on a board the user cannot see was named as a parent.']);
    try Payload:=QuotedStr(TypedDocument(Event.AsJSON,'',Hints));finally Event.Free;end;
    Updated:='wl_sjson(json_set(wl_plain(json(_ferretdb_sjson)),''$.at'','+AtSql+
      ',''$.userId'','+QuotedStr(UserId)+',''$.count'',MIN(9007199254740991,MAX(0,'+
      'COALESCE(json_extract(_ferretdb_sjson,''$.count''),0))+1)),json(_ferretdb_sjson),''{"at":"date"}'')';
    Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM _ferretdb_collections WHERE name=''eventlog'''+
      ' AND table_name='+QuotedStr(TableName)+')=1 THEN 1 ELSE json(''Event log source changed'') END; '+
      'UPDATE '+Physical+' SET _ferretdb_sjson='+Stored(Updated)+' WHERE rowid=(SELECT MIN(rowid) FROM '+Physical+
      ' WHERE '+Identity+'); INSERT INTO '+Physical+'(_ferretdb_sjson) SELECT '+Stored(Payload)+
      ' WHERE NOT EXISTS(SELECT 1 FROM '+Physical+' WHERE '+Identity+'); COMMIT;';
    if not Db.Exec(Sql) then Db.Exec('ROLLBACK;');
  except Db.Exec('ROLLBACK;');end;
end;

procedure ApiBulkCards(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,ListId,Lane,DefaultLane,Parent,ParentSql,ParentGuard,CardId,Relations,Sql,Guard,WritePermission,LaneGuard:string;
  Body,Entry,Item:TJSONObject;Input:TJSONData;Items,Reply:TJSONArray;Rows:TWLRows;I:Integer;
  function Permission(const Board:string;WriteAccess:Boolean):string;
  var Policy:TFieldPolicy;
  begin
    Policy:=TFieldPolicy.Create(T.Db,UserId,Board,'');
    try Result:=Policy.ScopeBoardExpression(WriteAccess);finally Policy.Free;end;
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];ListId:=aRequest.RouteParams['listId'];
  if not ApiAuthBoard(T,aResponse,UserId,BoardId,True) then Exit;
  Guard:='id='+QuotedStr(ListId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL';
  if Length(T.Db.Query('SELECT id FROM lists WHERE '+Guard+';'))<>1 then
  begin SendError(aResponse,400,'Invalid card list');Exit;end;
  WritePermission:=Permission(BoardId,True);
  Body:=nil;Reply:=TJSONArray.Create;
  try
    try Body:=ExactObject(aRequest.Content);
    except SendError(aResponse,400,'Expected a valid JSON object');Exit;end;
    Input:=Body.Find('cards');
    if not (Input is TJSONArray) or (Input.Count=0) or (Input.Count>500) then
    begin SendError(aResponse,400,'cards must contain between 1 and 500 entries');Exit;end;
    Items:=TJSONArray(Input);DefaultLane:=Body.Get('swimlaneId','');
    for I:=0 to Items.Count-1 do
    begin
      Item:=TJSONObject.Create(['index',I]);Reply.Add(Item);
      if not (Items.Items[I] is TJSONObject) then
      begin Item.Add('error','Invalid card');Continue;end;
      Entry:=Items.Objects[I];Lane:=Entry.Get('swimlaneId',DefaultLane);
      if Lane='' then Lane:=DefaultLane;
      if not ApiChildrenBelong(T.Db,BoardId,Lane,ListId,'','','','','') or
        ((Lane<>'') and (Length(T.Db.Query('SELECT id FROM lists WHERE '+Guard+
          ' AND (swimlaneId='''' OR swimlaneId='+QuotedStr(Lane)+');'))<>1)) then
      begin Item.Add('error','Invalid card placement');Continue;end;
      LaneGuard:='';
      if Lane<>'' then LaneGuard:=' AND EXISTS(SELECT 1 FROM swimlanes WHERE id='+QuotedStr(Lane)+
        ' AND boardId='+QuotedStr(BoardId)+' AND archived=0)';
      Parent:=Entry.Get('parentId','');ParentSql:='NULL';ParentGuard:='';
      if Parent<>'' then
      begin
        Rows:=T.Db.Query('SELECT boardId FROM cards WHERE id='+QuotedStr(Parent)+' AND deletedAt IS NULL AND archived=0;');
        if Length(Rows)<>1 then begin Item.Add('error','Forbidden');Continue;end;
        if not BoardCanRead(T.Db,UserId,Rows[0][0]) then
        begin RecordParentDenial(T.Db,UserId);Item.Add('error','Forbidden');Continue;end;
        ParentSql:=QuotedStr(Parent);
        ParentGuard:=' AND EXISTS(SELECT 1 FROM cards WHERE id='+ParentSql+
          ' AND boardId='+QuotedStr(Rows[0][0])+' AND archived=0 AND deletedAt IS NULL) AND '+Permission(Rows[0][0],False);
      end;
      CardId:=NewId;
      if not CardRelationSql(T,nil,nil,BoardId,CardId,Relations,True,Entry) then
      begin Item.Add('error','Invalid card assignments');Continue;end;
      try
        Sql:=CardCreateSql(BoardId,ListId,Lane,CardId,UserId,Entry.Get('title',''),Entry.Get('description',''),
          ParentSql,'(SELECT count(*) FROM cards WHERE boardId='+QuotedStr(BoardId)+' AND listId='+QuotedStr(ListId)+
          ' AND archived=0 AND deletedAt IS NULL)')+Relations+InitializeCardFields(T.Db,BoardId,CardId);
        if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN '+WritePermission+' AND EXISTS(SELECT 1 FROM lists WHERE '+Guard+')'+
          LaneGuard+ParentGuard+' THEN 1 ELSE json(''Card placement changed'') END; '+Sql+'COMMIT;') then
          raise Exception.Create('Bulk card creation failed');
        Item.Add('_id',CardId);
      except
        T.Db.Exec('ROLLBACK;');Item.Add('error','Could not create card');
      end;
    end;
    SendJson(aResponse,Reply.AsJSON);
  finally Body.Free;Reply.Free;end;
end;

procedure CreateLinkedRestCard(Db:TWLDb;Response:TResponse;const Actor,BoardId,ListId,Lane,LinkedId:string);
var Rows:TWLRows;Source,Title,Id,Board,ListKey,LaneKey,Scope,Placement,Permission,Stamp,Sql,Bindings:string;
  Policy:TFieldPolicy;Selector:TSelectionScope;I:Integer;
  function WritePermission(const BoardKey:string):string;
  begin
    Policy:=TFieldPolicy.Create(Db,Actor,BoardKey,'');
    try Result:=Policy.ScopeBoardExpression(True);finally Policy.Free;end;
  end;
begin
  if (Lane='') or (Pos(#0,LinkedId)>0) then
  begin SendError(Response,400,'Invalid linked card placement');Exit;end;
  Board:=QuotedStr(BoardId);ListKey:=QuotedStr(ListId);LaneKey:=QuotedStr(Lane);
  Selector:=TSelectionScope.Create(Db);
  try
    Scope:='id='+QuotedStr(LinkedId)+' AND '+Selector.StringField('cards','id')+
      ' AND '+Selector.StringField('cards','boardId');
    Placement:='EXISTS(SELECT 1 FROM lists WHERE id='+ListKey+' AND boardId='+Board+
      ' AND archived=0 AND deletedAt IS NULL AND (COALESCE(swimlaneId,'''')='''' OR swimlaneId='+LaneKey+') AND '+
      Selector.StringField('lists','id')+' AND '+Selector.StringField('lists','boardId')+')'+
      ' AND EXISTS(SELECT 1 FROM swimlanes WHERE id='+LaneKey+' AND boardId='+Board+' AND archived=0 AND '+
      Selector.StringField('swimlanes','id')+' AND '+Selector.StringField('swimlanes','boardId')+')';
    Bindings:='';
    for I:=0 to Selector.Bindings.Count-1 do Bindings:=Bindings+Selector.Bindings[I];
  finally Selector.Free;end;
  Rows:=Db.Query('SELECT boardId,title FROM cards WHERE '+Scope+';');
  if Length(Rows)<>1 then begin SendJson(Response,'{"error":"Card not found"}',404);Exit;end;
  Source:=Rows[0][0];Title:=Rows[0][1];
  if not BoardCanWrite(Db,Actor,Source) then
  begin SendError(Response,403,'Source board write access required');Exit;end;
  Scope:=Scope+' AND boardId='+QuotedStr(Source)+' AND archived=0 AND deletedAt IS NULL AND '+
    'COALESCE(linkedId,'''')='''' AND type NOT IN (''template-card'',''cardType-linkedCard'',''cardType-linkedBoard'')';
  Rows:=Db.Query('SELECT 1 WHERE '+Placement+' AND EXISTS(SELECT 1 FROM cards WHERE '+Scope+');');
  if Length(Rows)<>1 then begin SendError(Response,400,'Invalid linked card');Exit;end;
  Permission:=WritePermission(Source)+' AND '+WritePermission(BoardId);
  Id:=NewId;Stamp:=QuotedStr(NowIso);
  Sql:='BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+Permission+' AND '+Placement+
    ' AND EXISTS(SELECT 1 FROM cards WHERE '+Scope+' AND COALESCE(title,'''')='+QuotedStr(Title)+
    ') THEN 1 ELSE json(''Linked card scope changed'') END; '+
    CardCreateSql(BoardId,ListId,Lane,Id,Actor,Title,'','NULL',
      '(SELECT count(*) FROM cards WHERE listId='+ListKey+' AND boardId='+Board+
      ' AND archived=0 AND deletedAt IS NULL)',LinkedId)+InitializeSharedAssignments(Db,BoardId,Id,True,True)+
    'INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt) VALUES('+
    QuotedStr(NewId)+',''createCard'','+QuotedStr(Actor)+','+Board+','+QuotedStr(Id)+','+
    ListKey+','+LaneKey+','+Stamp+','+Stamp+'); COMMIT;';
  if not Db.Exec(Sql) then
  begin Db.Exec('ROLLBACK;');SendError(Response,500,'Could not create linked card');Exit;end;
  SendJson(Response,'{"_id":"'+StringToJSONString(Id)+'"}');
end;

procedure ApiCopyCard(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;Actor,BoardId,ListId,CardId,DestBoard,DestList,DestLane,Raw,NewCard:string;
  Position:Int64;Body:TJSONObject;Value:TJSONData;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,Actor,'{"error":"Card not found"}') then Exit;
  BoardId:=aRequest.RouteParams['boardId'];ListId:=aRequest.RouteParams['listId'];CardId:=aRequest.RouteParams['cardId'];
  DestBoard:=BodyField(aRequest,'toBoardId');if DestBoard='' then DestBoard:=BoardId;
  DestList:=BodyField(aRequest,'toListId');if DestList='' then DestList:=ListId;
  DestLane:=BodyField(aRequest,'toSwimlaneId');
  if (DestLane='') or (Pos(#0,DestBoard+DestList+DestLane)>0) then
  begin SendError(aResponse,400,'Invalid card copy destination');Exit;end;
  if not ApiAuthBoard(T,aResponse,Actor,DestBoard,True) then Exit;
  if not ApiChildrenBelong(T.Db,DestBoard,DestLane,DestList,'','','','','') then
  begin SendError(aResponse,400,'Invalid card copy destination');Exit;end;
  Raw:=aRequest.ContentFields.Values['position'];Position:=-1;
  if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
  begin
    Body:=ExactObject(aRequest.Content);
    try
      Value:=Body.Find('position');
      if (Value<>nil) and (Value.JSONType in [jtNumber,jtString]) then Raw:=Value.AsString;
    finally Body.Free;end;
  end;
  if TryStrToInt64(Raw,Position) then
  begin if Position<0 then Position:=0;end else Position:=-1;
  try
    if not CopyRestCard(T,Actor,BoardId,ListId,CardId,DestBoard,DestList,DestLane,Position,NewCard) then
      raise Exception.Create('Card copy failed');
  except SendError(aResponse,500,'Could not copy card');Exit;end;
  SendJson(aResponse,'{"_id":"'+StringToJSONString(NewCard)+'"}');
end;

procedure ApiCards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId,BoardId,ListId,Id,Author,Title,Descr,Swimlane,Relations,InitialFields,LinkedId:string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  if aRequest.Method <> 'POST' then begin SendError(aResponse, 405, 'Use POST'); Exit; end;
  BoardId  := aRequest.RouteParams['boardId'];
  ListId   := aRequest.RouteParams['listId'];
  LinkedId:=BodyField(aRequest,'linkedId');
  if LinkedId<>'' then
  begin
    CreateLinkedRestCard(T.Db,aResponse,UserId,BoardId,ListId,BodyField(aRequest,'swimlaneId'),LinkedId);
    Exit;
  end;
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
  if not CardRelationSql(T,aRequest,aResponse,BoardId,Id,Relations,True) then Exit;
  try InitialFields:=InitializeCardFields(T.Db,BoardId,Id);
  except SendError(aResponse,500,'Could not initialize custom fields');Exit;end;
  if not T.Db.Exec('BEGIN IMMEDIATE; '+CardCreateSql(BoardId,ListId,Swimlane,Id,Author,Title,Descr,'NULL','0')+
    Relations+InitialFields+' COMMIT;') then
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
  ReadSql:='SELECT id,title,description,listId,swimlaneId,boardId,color,isOvertime,json_quote(sort) FROM cards WHERE deletedAt IS NULL AND id='+QuotedStr(CardId);
  if RequiredBoardId<>'' then ReadSql:=ReadSql+' AND boardId='+QuotedStr(RequiredBoardId);
  if ActiveListId<>'' then ReadSql:=ReadSql+' AND listId='+QuotedStr(ActiveListId)+' AND archived=0';
  R:=Db.Query(ReadSql+' LIMIT 1;');
  if Length(R)=0 then begin SendJson(aResponse,CardNotFound,404);Exit;end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('title', R[0][1]); O.Add('description', R[0][2]);
    O.Add('listId', R[0][3]); O.Add('swimlaneId', R[0][4]); O.Add('boardId', R[0][5]);
    O.Add('color', R[0][6]); O.Add('isOvertime', R[0][7]='1'); O.Add('sort',GetJSON(R[0][8]));
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
function ChecklistDeadlineSql(Value:TJSONData;out Literal:string):Boolean; forward;

function CardDateSql(Value:TJSONData;out Literal:string):Boolean;
const TimeClip=8640000000000000;
var Text:string;Ms:Int64;I:Integer;Number:Double;Formatted,Input:TJSONData;
begin
  if Value.JSONType=jtNull then begin Literal:='NULL';Exit(True);end;
  Text:='';Result:=False;
  if Value.JSONType=jtString then
  begin
    Text:=Trim(Value.AsString);
    if (Value.AsString='') or (Value.AsString='null') then
    begin Literal:='NULL';Exit(True);end;
    I:=1;
    if (Text<>'') and (Text[1]='-') then Inc(I);
    while (I<=Length(Text)) and (Text[I] in ['0'..'9']) do Inc(I);
    if not ((I>1) and (I>Length(Text)) and TryStrToInt64(Text,Ms)) then
    begin
      if (Length(Text)=10) then Text:=Text+'T00:00:00Z';
      Input:=TJSONString.Create(Text);
      try Exit(ChecklistDeadlineSql(Input,Literal));finally Input.Free;end;
    end;
  end else if Value.JSONType=jtNumber then
  begin
    Number:=Value.AsFloat;
    if IsNan(Number) or IsInfinite(Number) or (Abs(Number)>TimeClip) then Exit;
    Ms:=Trunc(Number);
  end else Exit;
  if (Ms< -TimeClip) or (Ms>TimeClip) then Exit;
  Formatted:=JsonDate(Ms);
  try
    Text:=Formatted.AsString;
    if (Length(Text)=24) and (Copy(Text,1,4)<>'0000') then Literal:=QuotedStr(Text)
    else Literal:=QuotedStr(IntToStr(Ms));
  finally Formatted.Free;end;
  Result:=True;
end;

procedure ApiMyCards(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;Source:TSelectionScope;UserId,UserSql,Members,Assignees,Assigned,Related,BoardMember,
  Scope,Due,FromDate,ToDate,Sql,CardScope:string;Rows:TWLRows;
  function DateNumber(const Value:string):string;
  begin
    Result:='CASE WHEN instr('+Value+',''T'')>0 THEN unixepoch('+Value+
      ',''subsec'')*1000 ELSE CAST('+Value+' AS INTEGER) END';
  end;
  function Bound(const Name:string;out Literal:string):Boolean;
  var Raw:string;Input:TJSONData;
  begin
    Raw:=aRequest.QueryFields.Values[Name];Literal:='';
    if Raw='' then Exit(True);
    Input:=TJSONString.Create(Raw);
    try Result:=CardDateSql(Input,Literal) and (Literal<>'NULL');finally Input.Free;end;
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not Bound('from',FromDate) or not Bound('to',ToDate) then
  begin SendError(aResponse,400,'Invalid due date range');Exit;end;
  UserSql:=QuotedStr(UserId);Source:=TSelectionScope.Create(T.Db);
  try
    CardScope:=Source.StringField('cards','id')+' AND '+Source.StringField('cards','boardId');
    Members:='SELECT userId FROM card_members WHERE cardId=cards.id AND '+Source.StringField('card_members','userId');
    Assignees:='SELECT userId FROM card_assignees WHERE cardId=cards.id AND '+Source.StringField('card_assignees','userId');
    Assigned:=UserSql+' IN ('+Assignees+')';
    Related:='('+Assigned+' OR '+UserSql+' IN ('+Members+') OR EXISTS(SELECT 1 FROM json_each(cards.extra_json) relation '+
      'JOIN json_each(CASE WHEN relation.type=''array'' THEN relation.value ELSE ''[]'' END) participant '+
      'WHERE relation.key IN (''requesters'',''assigners'') AND participant.type=''text'' AND participant.value='+UserSql+'))';
    BoardMember:='EXISTS(SELECT 1 FROM board_members WHERE boardId=cards.boardId AND userId='+UserSql+
      ' AND isActive=1 AND '+Source.StringField('board_members','userId')+
      ' AND ((COALESCE(isReadAssignedOnly,0)=0 AND COALESCE(isCommentAssignedOnly,0)=0 AND '+
      'COALESCE(isNormalAssignedOnly,0)=0) OR '+Assigned+'))';
  finally Source.Free;end;
  Scope:='cards.archived=0 AND cards.deletedAt IS NULL AND '+CardScope+
    ' AND EXISTS(SELECT 1 FROM boards WHERE id=cards.boardId AND archived=0) AND '+Related+' AND '+BoardMember;
  Due:=DateNumber('cards.dueAt');
  if (LowerCase(aRequest.QueryFields.Values['due'])='true') or
    (LowerCase(aRequest.QueryFields.Values['due'])='yes') or
    (aRequest.QueryFields.Values['due']='1') or (FromDate<>'') or (ToDate<>'') then
    Scope:=Scope+' AND cards.dueAt IS NOT NULL AND cards.dueAt<>''''';
  if FromDate<>'' then Scope:=Scope+' AND ('+Due+')>=('+DateNumber(FromDate)+')';
  if ToDate<>'' then Scope:=Scope+' AND ('+Due+')<=('+DateNumber(ToDate)+')';
  Sql:='SELECT json_group_array(json(card)) FROM (SELECT json_patch(''{}'',json_object(''_id'',cards.id,'+
    '''title'',cards.title,''boardId'',cards.boardId,''swimlaneId'',cards.swimlaneId,''listId'',cards.listId,'+
    '''dueAt'',cards.dueAt,''startAt'',cards.startAt,''endAt'',cards.endAt,'+
    '''members'',json((SELECT json_group_array(userId) FROM ('+Members+'))),'+
    '''assignees'',json((SELECT json_group_array(userId) FROM ('+Assignees+'))))) card FROM cards WHERE '+Scope+
    ' ORDER BY '+Due+',cards.id);';
  Rows:=T.Db.Query(Sql);
  if Length(Rows)<>1 then begin SendError(aResponse,500,'Could not read user cards');Exit;end;
  SendJson(aResponse,Rows[0][0]);
end;

function CardDecorations(Value:TJSONData;const Key:string):TJSONArray;
var Parsed:TJSONObject;Entry,Item:TJSONObject;Field:TJSONData;I:Integer;
  Name,Text:string;Number:Double;Format:TFormatSettings;
begin
  Result:=TJSONArray.Create;Parsed:=nil;
  try
    try
      if Value.JSONType=jtString then
      begin
        Parsed:=ExactObject('{"array":'+Value.AsString+'}');
        Value:=Parsed.Find('array');
      end;
      if not (Value is TJSONArray) then raise Exception.Create('Invalid card decoration array');
      Format:=DefaultFormatSettings;Format.DecimalSeparator:='.';
      for I:=0 to Value.Count-1 do
      begin
        if not (Value.Items[I] is TJSONObject) then raise Exception.Create('Invalid card decoration entry');
        Entry:=TJSONObject(Value.Items[I]);Item:=TJSONObject.Create;Result.Add(Item);
        if Key='stickers' then
        begin
          for Name in ['icon','name','highlight'] do
          begin
            Field:=Entry.Find(Name);
            if Field=nil then Continue;
            if Field.JSONType<>jtString then raise Exception.Create('Invalid sticker field');
            Text:=Field.AsString;
            if (Name='highlight') and (Text<>'underline') and (Text<>'round') then
              raise Exception.Create('Invalid sticker highlight');
            Item.Add(Name,Text);
          end;
        end else
        begin
          Text:=Entry.Get('_id','');if Text='' then Text:=NewId;Item.Add('_id',Text);
          Item.Add('name',Entry.Get('name',''));Item.Add('address',Entry.Get('address',''));
          for Name in ['latitude','longitude'] do
          begin
            Field:=Entry.Find(Name);
            if (Field=nil) or ((Field.JSONType=jtString) and (Field.AsString='')) then Continue;
            if not (Field.JSONType in [jtNumber,jtString]) or
              not TryStrToFloat(Field.AsString,Number,Format) or IsNan(Number) or IsInfinite(Number) then
              raise Exception.Create('Invalid location coordinate');
            Item.Add(Name,Number);
          end;
        end;
      end;
    except FreeAndNil(Result);raise;end;
  finally Parsed.Free;end;
end;

procedure ApiCardEdit(aRequest:TRequest; aResponse:TResponse);
var T:TWLTenant; UserId,CardId,BoardId,Sets,Relations,Scope,ArchiveSql,Stamp,Value:string;
  HasArchive,Archive,HasEdits,HasOvertime,HasSort:Boolean;Body,Decorations:TJSONObject;Input:TJSONData;
  FieldName,FieldSets,Literal:string;HasDate:Boolean;SortNumber:Double;NumberFormat:TFormatSettings;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  CardId:=aRequest.RouteParams['cardId'];BoardId:=aRequest.RouteParams['boardId'];
  HasArchive:=BodyHasField(aRequest,'archive');
  HasEdits:=BodyHasField(aRequest,'title') or BodyHasField(aRequest,'description') or
    BodyHasField(aRequest,'color') or BodyHasField(aRequest,'labelIds') or
    BodyHasField(aRequest,'members') or BodyHasField(aRequest,'assignees');
  FieldSets:='';HasDate:=False;Body:=nil;Decorations:=nil;
  try
    try
      if (Pos('application/json',LowerCase(aRequest.ContentType))=1) and (aRequest.Content<>'') then
        Body:=ExactObject(aRequest.Content)
      else
      begin
        Body:=TJSONObject.Create;
        for FieldName in ['receivedAt','startAt','dueAt','endAt','dueComplete','stickers','locations','isOverTime','sort'] do
          if aRequest.ContentFields.IndexOfName(FieldName)>=0 then
            Body.Add(FieldName,aRequest.ContentFields.Values[FieldName]);
      end;
      for FieldName in ['receivedAt','startAt','dueAt','endAt'] do
      begin
        Input:=Body.Find(FieldName);
        if Input=nil then Continue;
        HasDate:=True;
        if CardDateSql(Input,Literal) then FieldSets:=FieldSets+','+FieldName+'='+Literal;
      end;
      Input:=Body.Find('sort');HasSort:=Input<>nil;
      if HasSort then
      begin
        NumberFormat:=DefaultFormatSettings;NumberFormat.DecimalSeparator:='.';NumberFormat.ThousandSeparator:=#0;
        if not (Input.JSONType in [jtNumber,jtString]) or (Trim(Input.AsString)='') or
          not TryStrToFloat(Trim(Input.AsString),SortNumber,NumberFormat) or IsNan(SortNumber) or IsInfinite(SortNumber) then
        begin SendJson(aResponse,'{"error":"Invalid sort"}',400);Exit;end;
        FieldSets:=FieldSets+',sort='+FloatToStrF(SortNumber,ffGeneral,17,0,NumberFormat);
      end;
      Input:=Body.Find('isOverTime');
      HasOvertime:=Input<>nil;
      if HasOvertime then
      begin
        if not (Input.JSONType in [jtBoolean,jtString]) or
          ((Input.AsString<>'true') and (Input.AsString<>'false')) then
        begin SendJson(aResponse,'{"error":"Invalid isOverTime"}',400);Exit;end;
        FieldSets:=FieldSets+',isOvertime='+IntToStr(Ord(Input.AsString='true'));
      end;
      Input:=Body.Find('dueComplete');
      if Input<>nil then
      begin
        Value:='';
        if Input.JSONType in [jtBoolean,jtString] then Value:=Input.AsString;
        FieldSets:=FieldSets+',dueComplete='+IntToStr(Ord(SameText(Value,'true')));
      end;
      Decorations:=TJSONObject.Create;
      for FieldName in ['stickers','locations'] do
      begin
        Input:=Body.Find(FieldName);
        if Input<>nil then Decorations.Add(FieldName,CardDecorations(Input,FieldName));
      end;
      if Decorations.Count>0 then
        FieldSets:=FieldSets+',extra_json=json_patch(extra_json,'+QuotedStr(Decorations.AsJSON)+')';
    except SendError(aResponse,400,'Invalid card update');Exit;end;
  finally Decorations.Free;Body.Free;end;
  HasEdits:=HasEdits or (FieldSets<>'');
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
  if HasDate and (FieldSets='') and not (HasArchive or HasEdits) then
  begin SendJson(aResponse,'{"message":"Error"}',404);Exit;end;
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
    Sets:='modifiedAt='+Stamp+',dateLastActivity='+Stamp+FieldSets;
    if BodyHasField(aRequest,'title') then Sets:=Sets+',title='+QuotedStr(BodyField(aRequest,'title'));
    if BodyHasField(aRequest,'description') then Sets:=Sets+',description='+QuotedStr(BodyField(aRequest,'description'));
    if BodyHasField(aRequest,'color') then Sets:=Sets+',color='+QuotedStr(BodyField(aRequest,'color'));
    Sets:='UPDATE cards SET '+Sets+' WHERE '+Scope+'; ';
  end;
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+
    ')=1 THEN 1 ELSE json(''Card edit scope changed'') END; '+Sets+ArchiveSql+Relations+' COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not edit card');Exit;end;
  if HasSort or HasOvertime then SendJson(aResponse,'{"_id":"'+StringToJSONString(CardId)+'"}')
  else SendCardById(aResponse,T.Db,CardId,UserId,False,BoardId);
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
const CardScopeError = '{"error":"Card not found or does not belong to the specified board"}';
  NotFound = '{"error":"Checklist not found or does not belong to the specified card"}';
var T: TWLTenant; UserId, BoardId, CardId, ChecklistId, Predicate, Changes, Statement, FinalCheck: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];CardId:=aRequest.RouteParams['cardId'];
  if aRequest.Method='GET' then
  begin
    if not ApiAuthBoard(T,aResponse,UserId,BoardId,False) then Exit;
    if (CardId='') or not ApiChildrenBelong(T.Db,BoardId,'','',CardId,'','','','') then
    begin SendJson(aResponse,CardScopeError,404);Exit;end;
  end
  else if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
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
  R:=T.Db.Query(ChecklistReadSql(BoardId,CardId,ChecklistId)+';');
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

// Dedicated member and assignee routes record history only for actual changes.
procedure ChangeCardAssignment(aRequest:TRequest;aResponse:TResponse;
  const RouteKey,TableName,ActivityNoun,ActivityKey:string);
var T:TWLTenant;Actor,CardId,BoardId,ListId,TargetId,Target,Scope,Pair,Present,Changing,
  ActivityType,ActivityId,Stamp,Sql,Mutation,FinalState,TargetGuard:string;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,Actor,CardNotFound) then Exit;
  CardId:=aRequest.RouteParams['cardId'];BoardId:=aRequest.RouteParams['boardId'];
  ListId:=aRequest.RouteParams['listId'];TargetId:=aRequest.RouteParams[RouteKey];Target:=QuotedStr(TargetId);
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+
    ' AND listId='+QuotedStr(ListId)+' AND deletedAt IS NULL';
  Pair:='cardId='+QuotedStr(CardId)+' AND userId='+Target;
  Present:='EXISTS(SELECT 1 FROM '+TableName+' WHERE '+Pair+')';
  TargetGuard:='';
  if aRequest.Method='DELETE' then
  begin
    ActivityType:='unjoin'+ActivityNoun;Changing:=Present;FinalState:='NOT '+Present;
    Mutation:='DELETE FROM '+TableName+' WHERE '+Pair+'; ';
  end
  else
  begin
    if not EnabledBoardMember(T.Db,BoardId,TargetId) then
    begin SendJson(aResponse,'{"error":"userId is not an active member of this board"}',400);Exit;end;
    TargetGuard:='SELECT CASE WHEN EXISTS(SELECT 1 FROM users u JOIN board_members m ON m.userId=u.id '+
      'WHERE u.id='+Target+' AND COALESCE(u.loginDisabled,0)=0 AND m.boardId='+QuotedStr(BoardId)+
      ' AND m.isActive=1) THEN 1 ELSE json(''Assignment target changed'') END; ';
    ActivityType:='join'+ActivityNoun;Changing:='NOT '+Present;FinalState:=Present;
    Mutation:='INSERT INTO '+TableName+'(cardId,userId) SELECT '+QuotedStr(CardId)+','+Target+
      ' WHERE '+Changing+'; ';
  end;
  ActivityId:=QuotedStr(NewId);Stamp:=QuotedStr(NowIso);
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+
    ')=1 THEN 1 ELSE json(''Card scope changed'') END; '+TargetGuard+
    'INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) SELECT '+
    ActivityId+','+QuotedStr(ActivityType)+','+QuotedStr(Actor)+',boardId,id,listId,swimlaneId,'+Stamp+','+Stamp+
    ',json_patch(json_object('+QuotedStr(ActivityKey)+','+Target+'),json_object(''username'',(SELECT username FROM users WHERE id='+Target+
    '))) FROM cards WHERE '+Scope+' AND '+Changing+'; '+
    'SELECT CASE WHEN NOT ('+Changing+') OR EXISTS(SELECT 1 FROM activities WHERE id='+ActivityId+
    ') THEN 1 ELSE json(''Assignment activity missing'') END; '+Mutation+
    'SELECT CASE WHEN '+FinalState+' THEN 1 ELSE json(''Assignment change failed'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not update card membership');Exit;end;
  SendCardById(aResponse,T.Db,CardId,Actor,False,BoardId);
end;

procedure ApiCardMember(aRequest:TRequest;aResponse:TResponse);
begin
  ChangeCardAssignment(aRequest,aResponse,'member','card_members','Member','memberId');
end;

procedure ApiCardAssignee(aRequest:TRequest;aResponse:TResponse);
begin
  ChangeCardAssignment(aRequest,aResponse,'assignee','card_assignees','Assignee','assigneeId');
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
// The activity records the claimed delete in the same transaction as the cascade.
function DeleteRestCard(Db:TWLDb;const UserId,BoardId,ListId,CardId:string;out Removed:Boolean):Boolean;
var Scope,Claim,Actor,Stamp,Sql,Permission,Bindings:string;Policy:TFieldPolicy;Source:TSelectionScope;I:Integer;
begin
  Result:=False;Removed:=False;Claim:=QuotedStr(NewId);Actor:=QuotedStr(UserId);Stamp:=QuotedStr(NowIso);
  try
    Policy:=TFieldPolicy.Create(Db,UserId,BoardId,'');
    try Permission:=Policy.ScopeBoardExpression(True);finally Policy.Free;end;
    Source:=TSelectionScope.Create(Db);
    try
      Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+
        ' AND '+Source.StringField('cards','id')+' AND '+Source.StringField('cards','boardId');
      Bindings:='';
      for I:=0 to Source.Bindings.Count-1 do Bindings:=Bindings+Source.Bindings[I];
    finally Source.Free;end;
    if ListId<>'' then Scope:=Scope+' AND listId='+QuotedStr(ListId);
    Sql:='BEGIN IMMEDIATE; '+Bindings+
      'SELECT CASE WHEN '+Permission+' THEN 1 ELSE json(''Card deletion permission changed'') END; '+
      'INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) '+
      'SELECT '+Claim+',''deleteCard'','+Actor+',boardId,id,listId,swimlaneId,'+Stamp+','+Stamp+
      ',json_object(''cardTitle'',title) FROM cards WHERE '+Scope+'; '+
      'DELETE FROM cards WHERE '+Scope+' AND EXISTS(SELECT 1 FROM activities WHERE id='+Claim+'); '+
      'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM cards WHERE '+Scope+
      ') THEN 1 ELSE json(''Card deletion failed'') END; COMMIT;';
    if not Db.Exec(Sql) then begin Db.Exec('ROLLBACK;');Exit;end;
    Removed:=Length(Db.Query('SELECT id FROM activities WHERE id='+Claim+';'))=1;
    Result:=True;
  except Db.Exec('ROLLBACK;');end;
end;

procedure ApiCardDelete(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,CardId:string;Removed:Boolean;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,CardNotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];CardId:=aRequest.RouteParams['cardId'];
  if not DeleteRestCard(T.Db,UserId,BoardId,aRequest.RouteParams['listId'],CardId,Removed) then
  begin SendError(aResponse,500,'Could not delete card');Exit;end;
  if not Removed then begin SendJson(aResponse,CardNotFound,404);Exit;end;
  SendJson(aResponse,'{"_id":"'+StringToJSONString(CardId)+'"}');
end;

procedure ApiBulkCardLabels(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,Cards,AddIds,RemoveIds,CardScope,LabelCheck,Permission,Bindings,Sql,CardId:string;
  Body,Reply,Item:TJSONObject;Input:TJSONData;Updated,NotFound,Labels:TJSONArray;
  Source:TSelectionScope;Policy:TFieldPolicy;Rows:TWLRows;I,J:Integer;
  function ReadIds(const Name:string;Required:Boolean):string;
  var Value:TJSONData;K:Integer;
  begin
    Result:='[]';Value:=Body.Find(Name);
    if (Value=nil) and not Required then Exit;
    if not (Value is TJSONArray) or (Value.Count>500) or (Required and (Value.Count=0)) then
      raise Exception.Create('Invalid ID list');
    for K:=0 to Value.Count-1 do
      if (Value.Items[K].JSONType<>jtString) or (Value.Items[K].AsString='') or
        (Pos(#0,Value.Items[K].AsString)>0) then raise Exception.Create('Invalid ID');
    if Value.Count<>0 then Result:=Value.AsJSON;
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];
  if not ApiAuthBoard(T,aResponse,UserId,BoardId,True) then Exit;
  Body:=nil;Reply:=nil;
  try
    try
      Body:=ExactObject(aRequest.Content);
      Cards:=ReadIds('cardIds',True);AddIds:=ReadIds('addLabelIds',False);RemoveIds:=ReadIds('removeLabelIds',False);
      if (AddIds='[]') and (RemoveIds='[]') then raise Exception.Create('Missing label changes');
    except SendError(aResponse,400,'Invalid card or label IDs');Exit;end;
    Cards:=QuotedStr(Cards);AddIds:=QuotedStr(AddIds);RemoveIds:=QuotedStr(RemoveIds);
    Source:=TSelectionScope.Create(T.Db);
    try
      CardScope:='boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL AND '+
        Source.StringField('cards','id')+' AND '+Source.StringField('cards','boardId');
      LabelCheck:='NOT EXISTS(SELECT 1 FROM json_each('+AddIds+') wanted WHERE NOT EXISTS(SELECT 1 FROM board_labels'+
        ' WHERE boardId='+QuotedStr(BoardId)+' AND id=wanted.value AND '+Source.StringField('board_labels','id')+'))';
      Bindings:='';
      for I:=0 to Source.Bindings.Count-1 do Bindings:=Bindings+Source.Bindings[I];
    finally Source.Free;end;
    Rows:=T.Db.Query('SELECT '+LabelCheck+';');
    if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
    begin SendError(aResponse,400,'addLabelIds contains labels not on this board');Exit;end;
    Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
    try Permission:=Policy.ScopeBoardExpression(True);finally Policy.Free;end;
    CardScope:=CardScope+' AND id IN (SELECT value FROM json_each('+Cards+'))';
    Sql:='BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+Permission+' AND '+LabelCheck+
      ' THEN 1 ELSE json(''Card label scope changed'') END; '+
      'DELETE FROM card_labels WHERE cardId IN (SELECT id FROM cards WHERE '+CardScope+
      ') AND labelId IN (SELECT value FROM json_each('+RemoveIds+')); '+
      'INSERT INTO card_labels(cardId,labelId) SELECT c.id,l.value FROM (SELECT id FROM cards WHERE '+CardScope+
      ') c CROSS JOIN (SELECT value,min(key) position FROM json_each('+AddIds+') GROUP BY value) l '+
      'WHERE NOT EXISTS(SELECT 1 FROM card_labels WHERE cardId=c.id AND labelId=l.value) ORDER BY c.id,l.position; COMMIT;';
    if not T.Db.Exec(Sql) then
    begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not update card labels');Exit;end;
    Reply:=TJSONObject.Create;Updated:=TJSONArray.Create;Reply.Add('updated',Updated);
    NotFound:=TJSONArray.Create;Reply.Add('notFound',NotFound);
    Input:=Body.Find('cardIds');
    for I:=0 to Input.Count-1 do
    begin
      CardId:=Input.Items[I].AsString;
      if Length(T.Db.Query('SELECT id FROM cards WHERE '+CardScope+' AND id='+QuotedStr(CardId)+';'))=0 then
      begin NotFound.Add(CardId);Continue;end;
      Item:=TJSONObject.Create(['_id',CardId]);Updated.Add(Item);
      Labels:=TJSONArray.Create;Item.Add('labelIds',Labels);
      Rows:=T.Db.Query('SELECT labelId FROM card_labels WHERE cardId='+QuotedStr(CardId)+';');
      for J:=0 to High(Rows) do Labels.Add(Rows[J][0]);
    end;
    SendJson(aResponse,Reply.AsJSON);
  finally Reply.Free;Body.Free;end;
end;

procedure ApiBulkCardDelete(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,CardId:string;Body,Reply:TJSONObject;
  Value:TJSONData;Cards,Deleted,NotFound:TJSONArray;Removed:Boolean;I:Integer;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];
  if not ApiAuthBoard(T,aResponse,UserId,BoardId,True) then Exit;
  Body:=nil;Reply:=TJSONObject.Create;
  try
    try Body:=ExactObject(aRequest.Content);
    except SendError(aResponse,400,'Expected a valid JSON object');Exit;end;
    Value:=Body.Find('cardIds');
    if not (Value is TJSONArray) or (Value.Count=0) or (Value.Count>500) then
    begin SendError(aResponse,400,'cardIds must contain between 1 and 500 entries');Exit;end;
    Cards:=TJSONArray(Value);
    for I:=0 to Cards.Count-1 do
      if (Cards.Items[I].JSONType<>jtString) or (Cards.Items[I].AsString='') or
        (Pos(#0,Cards.Items[I].AsString)>0) then
      begin SendError(aResponse,400,'Invalid card ID');Exit;end;
    Deleted:=TJSONArray.Create;Reply.Add('deleted',Deleted);
    NotFound:=TJSONArray.Create;Reply.Add('notFound',NotFound);
    for I:=0 to Cards.Count-1 do
    begin
      CardId:=Cards.Strings[I];
      if not DeleteRestCard(T.Db,UserId,BoardId,'',CardId,Removed) then
      begin SendError(aResponse,500,'Could not delete card');Exit;end;
      if Removed then Deleted.Add(CardId) else NotFound.Add(CardId);
    end;
    SendJson(aResponse,Reply.AsJSON);
  finally Reply.Free;Body.Free;end;
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
procedure ApiBoardDelete(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,Board,Permission,Sql,Guards,Collection,Registry,Physical,Scope:string;
  Policy:TFieldPolicy;Rows:TWLRows;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];Board:=QuotedStr(BoardId);
  Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board administration required');Exit;end;
  Guards:='';Sql:='';
  if Length(T.Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))=1 then
    for Collection in ['rules','triggers','actions','integrations'] do
    begin
      Registry:=' FROM _ferretdb_collections WHERE name='+QuotedStr(Collection);
      Rows:=T.Db.Query('SELECT table_name'+Registry+';');
      if Length(Rows)>1 then begin SendError(aResponse,500,'Ambiguous board source');Exit;end;
      if Length(Rows)=0 then
      begin Guards:=Guards+' AND NOT EXISTS(SELECT 1'+Registry+')';Continue;end;
      Guards:=Guards+' AND (SELECT count(*)'+Registry+' AND table_name='+QuotedStr(Rows[0][0])+')=1';
      Physical:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
      Scope:='json_extract(_ferretdb_sjson,''$.boardId'')='+Board+
        ' AND json_extract(_ferretdb_sjson,''$.$s.p.boardId.t'')=''string''';
      Sql:=Sql+'DELETE FROM '+Physical+' WHERE '+Scope+'; '+
        'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM '+Physical+' WHERE '+Scope+
        ') THEN 1 ELSE json(''Board workflow deletion failed'') END; ';
    end;
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+Guards+
    ' THEN 1 ELSE json(''Board deletion permission changed'') END; '+Sql+
    'DELETE FROM boards WHERE id='+Board+'; SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM boards WHERE id='+Board+
    ') THEN 1 ELSE json(''Board deletion failed'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not delete board');Exit;end;
  SendJson(aResponse,'{"_id":"'+StringToJSONString(BoardId)+'"}');
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
