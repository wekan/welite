program wlhttp;

{
  WeKan-Lite — program entry (v0.1 reference skeleton)

  Wires the pieces distilled from the prototypes into one multitenant server:
    fphttpapp + httproute   (stack used by both https://github.com/wekan/wami/blob/main/wekan.pas and https://github.com/wekan/omi/blob/main/public/server.pas)
    wltenant                Host: header -> data/domains/<domain>/db/data.db   (docs/goals.md G8)
    wlauth                  no-cookie / no-JS sessions + action-tokens          (docs/goals.md G4)
    wldb                    SQLite behind one interface                         (docs/sqlite.md)

  Build (see https://github.com/wekan/omi/blob/main/docs/SERVER_FREEPASCAL.md for per-platform flags):
    fpc -O3 -Xs -o welite wlhttp.lpr            # linked SQLite (default); serves ./public + ./i18n from disk
    fpc -dWLDB_CLI -o welite wlhttp.lpr         # bootstrap: external sqlite3 CLI
    fpc -Pm68k -Tamiga -o welite wlhttp.lpr     # classic Amiga 68k
    # single binary with public/ + i18n/ embedded (docs/static.md):
    #   python3 releases/genasset.py   # writes src/wlassets.pas + src/wlpublic.rc
    #   cd src && fpcres wlpublic.rc -o wlpublic.res -of res
    #   fpc -dWLEMBED -O3 -Xs -o ../welite wlhttp.lpr

  TLS stays out of the binary (docs/webstack.md Decision 5): terminate at Caddy/proxy,
  or load AmiSSL/OpenSSL dynamically. Run plain HTTP here.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

uses
  // cthreads for the threaded server; NOT cmem — FPC's `hmac` unit (used by wlpasswd)
  // corrupts the heap under cmem ("free(): invalid pointer"), and the default FPC memory
  // manager is already thread-safe, so cmem is unnecessary here.
  {$IFDEF UNIX} cthreads, {$ENDIF}
  SysUtils, Classes, fphttpapp, httpdefs, httproute,
  wltenant, wlauth, wldb, wlhtml, wlbrowse, wldesign, wlmove, wlstatic, wlapi, wlpasswd, wladmin
  {$IFDEF WLEMBED}, wlassets {$ENDIF};   // wlassets registers the embedded-asset lookup

const
  DEFAULT_PORT  = 5500;       // wami used 5500; omi 3001. Override with WELITE_PORT.
  DATA_ROOT     = 'data';     // data/admin, data/domains/<domain>, data/certs
  DEFAULT_PUBLIC = 'public';  // static assets dir (disk mode). Override with WELITE_PUBLIC.
  DEFAULT_MOUNT = '/';        // URL the public/ tree is served under. Override WELITE_STATIC_URL.
  DEFAULT_I18N  = 'i18n';     // translations dir (i18n/langs.jsn + i18n/data). Override WELITE_I18N.
  I18N_MOUNT    = '/i18n';    // URL the i18n/ tree is served under (i18n/langs.jsn -> /i18n/langs.jsn).

// Resolve the tenant for this request or answer 404 (never fall back into another tenant).
function RequireTenant(aRequest: TRequest; aResponse: TResponse; out T: TWLTenant): Boolean;
begin
  Result := ResolveTenant(aRequest, T) and TenantOpen(T);
  if not Result then
  begin
    aResponse.Code := 404;
    aResponse.ContentType := 'text/plain';
    aResponse.Content := 'Unknown domain';
    aResponse.SendContent;
  end;
end;

procedure SendHtml(aResponse: TResponse; const Body: string);
begin
  aResponse.Code := 200;
  aResponse.ContentType := 'text/html; charset=utf-8';
  aResponse.Content := Body;
  aResponse.ContentLength := Length(aResponse.Content);
  aResponse.SendContent;
end;

// 17-char Mongo-style id (schema.sql convention; same alphabet as wlapi.NewId). Seeded by the
// Randomize at program start.
function NewId: string;
const A = '23456789ABCDEFGHJKLMNPQRSTWXYZabcdefghijkmnopqrstuvwxyz';
var i: Integer;
begin
  SetLength(Result, 17);
  for i := 1 to 17 do Result[i] := A[Random(Length(A)) + 1];
end;

// True when the tenant has no accounts yet — the first person to register becomes Global Admin.
function NoUsersYet(T: TWLTenant): Boolean;
var Rows: TWLRows;
begin
  Rows := T.Db.Query('SELECT COUNT(*) FROM users;');
  Result := (Length(Rows) > 0) and (Length(Rows[0]) > 0) and (Rows[0][0] = '0');
end;

// GET / — board list for the resolved tenant (HTML 3.2 baseline; enhance later).
procedure HomeEndpoint(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  S: TWLSession;
  Rows: TWLRows;
  Body: string;
  i: Integer;
  IsGAdmin: Boolean;
begin
  if not RequireTenant(aRequest, aResponse, T) then Exit;

  // No accounts yet -> send the visitor to the login page (which links to register). The first
  // person to register becomes the Global Admin; everyone after is a Normal user.
  if NoUsersYet(T) then
  begin
    aResponse.Code := 302;
    aResponse.SetCustomHeader('Location', '/sign-in');
    aResponse.SendContent;
    Exit;
  end;

  // Greet the signed-in user and flag the Global Admin (users.isAdmin = 1).
  IsGAdmin := False;
  if ValidateSession(T.Db, aRequest, SessionIdFromRequest(aRequest), S) then
    IsGAdmin := IsGlobalAdmin(T.Db, S);

  Body := '<h1>' + HtmlEncode(T.Host) + '</h1>' + LineEnding;
  if IsGAdmin then
    Body := Body + '<p><b>Global Admin</b> &mdash; ' + HtmlEncode(S.Username) + ' &mdash; ' +
            '<a href="' + HtmlAttr(WithSessionId('/admin', S.SessionId)) + '">Admin Panel</a></p>' + LineEnding
  else if S.Username <> '' then
    Body := Body + '<p>Signed in as ' + HtmlEncode(S.Username) + '.</p>' + LineEnding;

  Rows := T.Db.Query('SELECT title FROM boards WHERE archived=0 ORDER BY sort;');
  Body := Body + '<h2>Boards</h2><ul>' + LineEnding;
  for i := 0 to High(Rows) do
    if Length(Rows[i]) > 0 then
      Body := Body + '<li>' + HtmlEncode(Rows[i][0]) + '</li>' + LineEnding;
  if Length(Rows) = 0 then
    Body := Body + '<li><i>No boards yet.</i></li>' + LineEnding;
  Body := Body + '</ul>' + LineEnding +
          '<p><a href="/sign-in">Sign in</a> | <a href="/register">Register</a></p>';
  // detection is best-effort, never gates output (every page works on the HTML 3.2 baseline)
  Writeln('Client: ', BrowserName(DetectBrowser(RequestUserAgent(aRequest))));
  SendHtml(aResponse, Page32('WeKan-Lite', Body));
end;

// POST /sign-in — authenticate against schema.sql users, then issue a cookie-free session.
procedure SignInEndpoint(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  Username, Password: string;
  Rows: TWLRows;
  S: TWLSession;
begin
  if not RequireTenant(aRequest, aResponse, T) then Exit;

  if aRequest.Method = 'POST' then
  begin
    Username := Trim(aRequest.ContentFields.Values['username']);
    Password := aRequest.ContentFields.Values['password'];
    Rows := T.Db.Query(Format(
      'SELECT id, COALESCE(json_extract(services_json,''$.password''),'''') ' +
      'FROM users WHERE username=%s LIMIT 1;', [QuotedStr(Username)]));
    if (Length(Rows) > 0) and (Length(Rows[0]) >= 2) and VerifyPassword(Password, Rows[0][1]) then
    begin
      S := CreateSession(T.Db, aRequest, Rows[0][0], Username,
                         HashText(Username), 30 * 24 * 60 * 60);
      aResponse.Code := 302;
      aResponse.SetCustomHeader('Location', WithSessionId('/', S.SessionId));
      aResponse.SendContent;
      Exit;
    end;
    SendHtml(aResponse, Page32('Sign in',
      '<p>Invalid login.</p><p><a href="/sign-in">Try again</a>' +
      ' | <a href="/register">Register</a></p>'));
    Exit;
  end;

  // GET — plain form, no JS, no cookie; session flows via URL/hidden field after login.
  SendHtml(aResponse, Page32('Sign in',
    '<h1>Sign in</h1>' + LineEnding +
    '<form method="POST" action="/sign-in">' + LineEnding +
    '  Username <input name="username"><br>' + LineEnding +
    '  Password <input type="password" name="password"><br>' + LineEnding +
    '  <input type="submit" value="Sign in">' + LineEnding +
    '</form>' + LineEnding +
    '<p><a href="/register">Create an account (Register)</a></p>'));
end;

// GET/POST /register — create an account. The first account in a tenant becomes the Global
// Admin (users.isAdmin = 1); subsequent accounts are Normal users. No-JS / no-cookie, like sign-in.
procedure RegisterEndpoint(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  S: TWLSession;
  Username, Password, Confirm, Uid, Hash, Iso, Body: string;
  First: Boolean;
begin
  if not RequireTenant(aRequest, aResponse, T) then Exit;

  if aRequest.Method = 'POST' then
  begin
    Username := Trim(aRequest.ContentFields.Values['username']);
    Password := aRequest.ContentFields.Values['password'];
    Confirm  := aRequest.ContentFields.Values['confirm'];

    if (Username = '') or (Password = '') then
    begin
      SendHtml(aResponse, Page32('Register',
        '<p>Username and password are required.</p><p><a href="/register">Back</a></p>'));
      Exit;
    end;
    if Password <> Confirm then
    begin
      SendHtml(aResponse, Page32('Register',
        '<p>Passwords do not match.</p><p><a href="/register">Back</a></p>'));
      Exit;
    end;
    if Length(T.Db.Query(Format('SELECT id FROM users WHERE username=%s LIMIT 1;',
                                [QuotedStr(Username)]))) > 0 then
    begin
      SendHtml(aResponse, Page32('Register',
        '<p>That username is taken.</p><p><a href="/register">Back</a></p>'));
      Exit;
    end;

    First := NoUsersYet(T);                 // first account -> Global Admin
    Uid   := NewId;
    Hash  := HashPassword(Password);        // pbkdf2_sha1$...; stored under services.password
    Iso   := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Now);
    if not T.Db.Exec(Format(
      'INSERT INTO users(id,username,isAdmin,authenticationMethod,createdAt,modifiedAt,' +
      'services_json,profile_json) VALUES(%s,%s,%d,''password'',%s,%s,%s,''{}'');',
      [QuotedStr(Uid), QuotedStr(Username), Ord(First), QuotedStr(Iso), QuotedStr(Iso),
       QuotedStr('{"password":"' + Hash + '"}')])) then
    begin
      SendHtml(aResponse, Page32('Register',
        '<p>Could not create the account.</p><p><a href="/register">Back</a></p>'));
      Exit;
    end;

    // Log the new user straight in (cookie-free session via URL), then go to the board list.
    S := CreateSession(T.Db, aRequest, Uid, Username, HashText(Username), 30 * 24 * 60 * 60);
    aResponse.Code := 302;
    aResponse.SetCustomHeader('Location', WithSessionId('/', S.SessionId));
    aResponse.SendContent;
    Exit;
  end;

  // GET — registration form.
  First := NoUsersYet(T);
  Body := '<h1>Register</h1>' + LineEnding;
  if First then
    Body := Body + '<p>This first account will be the <b>Global Admin</b>.</p>' + LineEnding;
  Body := Body +
    '<form method="POST" action="/register">' + LineEnding +
    '  Username <input name="username"><br>' + LineEnding +
    '  Password <input type="password" name="password"><br>' + LineEnding +
    '  Confirm <input type="password" name="confirm"><br>' + LineEnding +
    '  <input type="submit" value="Register">' + LineEnding +
    '</form>' + LineEnding +
    '<p><a href="/sign-in">Already have an account? Sign in</a></p>';
  SendHtml(aResponse, Page32('Register', Body));
end;

// Catch-all: after the fixed routes, try the tenant's designer pages table (pages.url),
// then 404. This is what makes custom Designer pages and remapped builtin URLs resolve.
// POST /board/move — the no-JS combined move component (wlmove). Reads dir + sel_* selections,
// reorders/relocates, then PRG-redirects back to the page the move came from.
procedure BoardMoveEndpoint(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  S: TWLSession;
  BackTo: string;
begin
  if not RequireTenant(aRequest, aResponse, T) then Exit;
  ValidateSession(T.Db, aRequest, SessionIdFromRequest(aRequest), S);
  if not VerifyActionToken(aRequest, S, 'board:move') then
  begin
    aResponse.Code := 403; aResponse.Content := 'Bad token'; aResponse.SendContent; Exit;
  end;
  ApplyMove(T.Db, aRequest.ContentFields);
  BackTo := aRequest.ContentFields.Values['back'];
  if BackTo = '' then BackTo := '/';
  aResponse.Code := 302;
  aResponse.SetCustomHeader('Location', WithSessionId(BackTo, S.SessionId));
  aResponse.SendContent;
end;

procedure CatchAll(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  S: TWLSession;
begin
  // Static assets (global, tenant-independent): public/robots.txt -> /robots.txt,
  // public/js/interact.js -> /js/interact.js, i18n/langs.jsn -> /i18n/langs.jsn,
  // etc. Tried before tenant pages.
  if ServeStatic(aRequest, aResponse) then Exit;
  if RequireTenant(aRequest, aResponse, T) then
  begin
    ValidateSession(T.Db, aRequest, SessionIdFromRequest(aRequest), S);
    // direction mirrors RTL languages from one page definition (no separate files);
    // QueryFields carry table search/page/column-visibility state (no-JS, no cookies)
    if TryServePage(T, S, aRequest.PathInfo,
                    ResolveDir(aRequest, ''), aRequest.QueryFields, aResponse) then
      Exit;
    aResponse.Code := 404;
    aResponse.ContentType := 'text/plain';
    aResponse.Content := 'Not found';
    aResponse.SendContent;
  end;
end;

var
  PortEnv, PublicDir, StaticUrl, I18nDir: string;
begin
  Randomize;            // seed the RNG used by NewId (wlapi/wldesign) — else ids repeat per run

  // ops/seed helper: `welite hashpw <plain>` prints a PBKDF2 hash for users.services_json
  if (ParamCount >= 2) and (ParamStr(1) = 'hashpw') then
  begin
    Writeln(HashPassword(ParamStr(2)));
    Halt(0);
  end;

  TenantInit(DATA_ROOT);

  // static assets: configurable mount + disk dir (embedded build ignores the disk dir)
  PublicDir := GetEnvironmentVariable('WELITE_PUBLIC');
  if PublicDir = '' then PublicDir := DEFAULT_PUBLIC;
  StaticUrl := GetEnvironmentVariable('WELITE_STATIC_URL');
  if StaticUrl = '' then StaticUrl := DEFAULT_MOUNT;
  StaticInit(StaticUrl, PublicDir);
  // translations: i18n/ tree (i18n/langs.jsn + i18n/data/*.jsn) served at /i18n
  I18nDir := GetEnvironmentVariable('WELITE_I18N');
  if I18nDir = '' then I18nDir := DEFAULT_I18N;
  StaticAddRoot(I18N_MOUNT, 'i18n/', I18nDir);

  HTTPRouter.RegisterRoute('/', rmGet, @HomeEndpoint);
  HTTPRouter.RegisterRoute('/sign-in', rmGet, @SignInEndpoint);
  HTTPRouter.RegisterRoute('/sign-in', rmPost, @SignInEndpoint);
  HTTPRouter.RegisterRoute('/register', rmGet, @RegisterEndpoint);
  HTTPRouter.RegisterRoute('/register', rmPost, @RegisterEndpoint);

  // Global Admin Panel (Domains / Designer / People) — see wladmin; Designer lives at /designer
  HTTPRouter.RegisterRoute('/admin', rmGet, @AdminIndex);
  HTTPRouter.RegisterRoute('/admin/domains', rmGet, @AdminDomains);
  HTTPRouter.RegisterRoute('/admin/domains', rmPost, @AdminDomains);
  HTTPRouter.RegisterRoute('/admin/people', rmGet, @AdminPeople);
  HTTPRouter.RegisterRoute('/admin/people', rmPost, @AdminPeople);

  // Designer (Domain Global Admin; no-JS/no-cookie) — see docs/designer.md
  HTTPRouter.RegisterRoute('/designer', rmGet, @DesignerIndex);
  HTTPRouter.RegisterRoute('/designer/page', rmGet, @DesignerEditPage);
  HTTPRouter.RegisterRoute('/designer/widget/move', rmPost, @DesignerWidgetMove);
  HTTPRouter.RegisterRoute('/designer/widget/save', rmPost, @DesignerWidgetSave);
  HTTPRouter.RegisterRoute('/designer/page/export', rmGet, @DesignerPageExport);
  HTTPRouter.RegisterRoute('/designer/page/import', rmPost, @DesignerPageImport);
  HTTPRouter.RegisterRoute('/designer/export', rmGet, @DesignerExportAll);
  HTTPRouter.RegisterRoute('/designer/import', rmPost, @DesignerImportAll);

  // Attachments (api.py /api/attachment/* surface; bytes on disk in files/attachments/)
  HTTPRouter.RegisterRoute('/api/attachment/upload', rmPost, @ApiAttachmentUpload);
  HTTPRouter.RegisterRoute('/api/attachment/download/:attachmentId', rmGet, @ApiAttachmentDownload);
  HTTPRouter.RegisterRoute('/api/attachment/info/:attachmentId', rmGet, @ApiAttachmentInfo);
  HTTPRouter.RegisterRoute('/api/attachment/delete/:attachmentId', rmDelete, @ApiAttachmentDelete);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/attachments', rmGet, @ApiBoardAttachments);
  HTTPRouter.RegisterRoute('/api/attachment/list/:boardId/:swimlaneId/:listId/:cardId', rmGet, @ApiCardAttachmentsList);

  // Combined no-JS move component (arrows keypad) — see docs/move.md
  HTTPRouter.RegisterRoute('/board/move', rmPost, @BoardMoveEndpoint);

  // REST API (subset of public/api/wekan.yml) so the WeKan Python CLI api.py works — see wlapi
  HTTPRouter.RegisterRoute('/users/login', rmPost, @ApiLogin);
  HTTPRouter.RegisterRoute('/api/user', rmGet, @ApiUser);
  HTTPRouter.RegisterRoute('/api/users', rmGet, @ApiUsers);
  HTTPRouter.RegisterRoute('/api/boards', rmGet, @ApiPublicBoards);
  HTTPRouter.RegisterRoute('/api/users/:userId/boards', rmGet, @ApiUserBoards);
  HTTPRouter.RegisterRoute('/api/boards/:boardId', rmGet, @ApiBoard);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/title', rmPut, @ApiBoardTitle);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/copy', rmPost, @ApiBoardCopy);
  HTTPRouter.RegisterRoute('/api/boards/:boardId', rmDelete, @ApiBoardDelete);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/labels', rmPut, @ApiCreateLabel);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/custom-fields', rmGet, @ApiCustomFields);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/custom-fields', rmPost, @ApiCustomFields);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/custom-fields/:customField', rmGet, @ApiCustomField);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/customFields/:customField', rmPost, @ApiCardCustomField);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/swimlanes', rmGet, @ApiSwimlanes);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/swimlanes', rmPost, @ApiSwimlanes);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/swimlanes/:swimlaneId', rmDelete, @ApiSwimlaneDelete);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/swimlanes/:swimlaneId/cards', rmGet, @ApiSwimlaneCards);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists', rmGet, @ApiLists);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists', rmPost, @ApiLists);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId', rmGet, @ApiList);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId', rmDelete, @ApiListDelete);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards', rmGet, @ApiListCards);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards', rmPost, @ApiCards);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards_count', rmGet, @ApiListCardsCount);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards_count', rmGet, @ApiBoardCardsCount);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId', rmGet, @ApiCard);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId', rmPut, @ApiCardEdit);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId', rmDelete, @ApiCardDelete);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/archive', rmPost, @ApiCardArchive);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/members/:member', rmPost, @ApiCardMember);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/members/:member', rmDelete, @ApiCardMember);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/assignees/:assignee', rmPost, @ApiCardAssignee);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/assignees/:assignee', rmDelete, @ApiCardAssignee);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/checklists', rmGet, @ApiCardChecklists);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/checklists', rmPost, @ApiCardChecklists);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/checklists/:checklistId', rmGet, @ApiChecklist);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/checklists/:checklistId/items', rmPost, @ApiChecklistItems);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/checklists/:checklistId/items/:item', rmGet, @ApiChecklistItem);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/checklists/:checklistId/items/:item', rmPut, @ApiChecklistItem);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/checklists/:checklistId/items/:item', rmDelete, @ApiChecklistItem);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/comments', rmGet, @ApiCardComments);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/comments', rmPost, @ApiCardComments);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/comments/:commentId', rmGet, @ApiCardComment);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/comments/:commentId', rmDelete, @ApiCardComment);

  // Everything else: tenant designer pages (pages.url) then 404
  HTTPRouter.RegisterRoute('/*', rmAll, @CatchAll, True);

  PortEnv := GetEnvironmentVariable('WELITE_PORT');
  Application.Port := StrToIntDef(PortEnv, DEFAULT_PORT);
  Application.Threaded := True;
  Application.Initialize;
  Writeln('WeKan-Lite listening on :', Application.Port, ' (data root: ', DATA_ROOT, ')');
  Application.Run;
end.
