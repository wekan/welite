program wlhttp;

{
  WeKan-Lite — program entry (v0.1 reference skeleton)

  Wires the pieces distilled from the prototypes into one multitenant server:
    fphttpapp + httproute   (stack used by both https://github.com/wekan/wami/blob/main/wekan.pas and https://github.com/wekan/omi/blob/main/public/server.pas)
    wltenant                Host: header -> data/domains/<key>/files/db/wekan.db   (docs/goals.md G8)
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
  SysUtils, Classes, DateUtils, wlattemp, wlenroll, wlpolicy, wlshared, wlmaint, wlstop, wli18n, fphttpapp, httpdefs, httproute,
  wltenant, wlauth, wldb, wlhtml, wlbrowse, wldesign, wlmove, wlstatic, wlapi, wlpasswd, wladmin, wlaccess, wlboard,wlselect,wlentrop
  {$IFDEF WLEMBED}, wlassets {$ENDIF};   // wlassets registers the embedded-asset lookup

type
  TWLCleanRouter=class(THTTPRouter)
  protected
    procedure DoRouteRequest(Request:TRequest;Response:TResponse);override;
  end;

const
  DEFAULT_PORT  = 5500;       // wami used 5500; omi 3001. Override with WELITE_PORT.
  DATA_ROOT     = 'data';     // data/admin, data/domains/<domain>, data/certs
  DEFAULT_PUBLIC = 'public';  // static assets dir (disk mode). Override with WELITE_PUBLIC.
  DEFAULT_MOUNT = '/';        // URL the public/ tree is served under. Override WELITE_STATIC_URL.
  DEFAULT_I18N  = 'i18n';     // translations dir (i18n/langs.jsn + i18n/data). Override WELITE_I18N.
  I18N_MOUNT    = '/i18n';    // URL the i18n/ tree is served under (i18n/langs.jsn -> /i18n/langs.jsn).

procedure TWLCleanRouter.DoRouteRequest(Request:TRequest;Response:TResponse);
begin
  try inherited DoRouteRequest(Request,Response);
  finally CleanupUploads(Request);end;
end;

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
    IsGAdmin := IsTenantAdmin(T.Db, S)
  else S:=Default(TWLSession);

  Body := '<h1>' + HtmlEncode(T.Host) + '</h1>' + LineEnding;
  if IsGAdmin then
    Body := Body + '<p><b>Tenant administrator</b> &mdash; ' + HtmlEncode(S.Username) + ' &mdash; ' +
            '<a href="' + HtmlAttr(WithSessionId('/admin', S.SessionId)) + '">Admin Panel</a></p>' + LineEnding
  else if S.Username <> '' then
    Body := Body + '<p>Signed in as ' + HtmlEncode(S.Username) + '.</p>' + LineEnding;

  Body:=Body+BoardListHtml(T.Db,S)+'<p><a href="/sign-in">Sign in</a> | <a href="/register">Register</a></p>';
  // detection is best-effort, never gates output (every page works on the HTML 3.2 baseline)
  Writeln('Client: ', BrowserName(DetectBrowser(RequestUserAgent(aRequest))));
  SendHtml(aResponse, Page32('WeKan-Lite', Body));
end;

// POST /sign-in — authenticate against schema.sql users, then issue a cookie-free session.
procedure SignInEndpoint(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  Username, Password: string;
  Proof: TWLLoginProof;
  S: TWLSession;
begin
  if not RequireTenant(aRequest, aResponse, T) then Exit;

  if aRequest.Method = 'POST' then
  begin
    Username := Trim(aRequest.ContentFields.Values['username']);
    Password := aRequest.ContentFields.Values['password'];
    if not ReserveLoginAttempt(T.Db,Username,aRequest.RemoteAddress,DateTimeToUnix(Now,False)) then
    begin
      aResponse.Code:=429;aResponse.SetCustomHeader('Retry-After','300');
      aResponse.Content:='Too many login attempts. Try again later.';aResponse.SendContent;Exit;
    end;
    Proof:=nil;
    if AuthenticateAccount(T.Db,Username,Password,aRequest.ContentFields.Values['code'],Proof) then
    try
      S:=CreateAuthenticatedSession(T.Db,aRequest,Proof,30*24*60*60);
      if S.SessionId='' then
      begin aResponse.Code:=500; aResponse.Content:='Could not create session'; aResponse.SendContent; Exit; end;
      aResponse.Code:=302;
      aResponse.SetCustomHeader('Location',WithSessionId('/',S.SessionId));
      aResponse.SendContent;Exit;
    finally Proof.Free;end;
    SendHtml(aResponse, Page32('Sign in',
      '<p>Invalid login.</p><p><a href="/sign-in">Try again</a>' +
      ' | <a href="/two-factor/setup">Set up one-time codes</a> | <a href="/register">Register</a></p>'));
    Exit;
  end;

  // GET — plain form, no JS, no cookie; session flows via URL/hidden field after login.
  SendHtml(aResponse, Page32('Sign in',
    '<h1>Sign in</h1>' + LineEnding +
    '<form method="POST" action="/sign-in">' + LineEnding +
    '  Username <input name="username"><br>' + LineEnding +
    '  Password <input type="password" name="password"><br>' + LineEnding +
    '  One-time code (if enabled) <input name="code" size="6" maxlength="6"><br>' + LineEnding +
    '  <input type="submit" value="Sign in">' + LineEnding +
    '</form>' + LineEnding +
    '<p><a href="/two-factor/setup">Set up one-time codes</a> | <a href="/register">Create an account (Register)</a></p>'));
end;

// Enrollment secrets and bearer tokens only travel in POST bodies/responses.
function EnrollmentBinding(Request:TRequest):string;
begin Result:=HashText('welite-enrol-client-v1'+#0+Request.RemoteAddress+#0+RequestUserAgent(Request));end;
procedure EnrollmentHeaders(Response:TResponse);
begin
  Response.SetCustomHeader('Cache-Control','no-store');
  Response.SetCustomHeader('Referrer-Policy','no-referrer');
end;
function EnrollmentAdmission(Db:TWLDb;Request:TRequest;Response:TResponse;const Username:string):Boolean;
begin
  Result:=ReserveLoginAttempt(Db,Username,Request.RemoteAddress,DateTimeToUnix(Now,False));
  if not Result then
  begin
    Response.Code:=429;Response.SetCustomHeader('Retry-After','300');
    Response.Content:='Too many login attempts. Try again later.';Response.SendContent;
  end;
end;
function ConfirmationForm(const Token,Message:string):string;
begin
  Result:='<h1>Confirm one-time codes</h1><p>'+HtmlEncode(Message)+'</p>'+
    '<form method="POST" action="/two-factor/confirm">'+
    '<input type="hidden" name="setupToken" value="'+HtmlEncode(Token)+'">'+
    'One-time code <input name="code" size="6" maxlength="6"><br>'+
    '<input type="submit" value="Confirm"></form>'+
    '<p><a href="/two-factor/setup">Start setup again</a> | <a href="/sign-in">Sign in</a></p>';
end;
procedure EnrollmentEndpoint(Request:TRequest;Response:TResponse);
var T:TWLTenant;Username,Token,Secret,Body:string;Proof:TWLEnrollProof;
begin
  EnrollmentHeaders(Response);
  if not RequireTenant(Request,Response,T) then Exit;
  if Request.Method='POST' then
  begin
    Username:=Trim(Request.ContentFields.Values['username']);
    if not EnrollmentAdmission(T.Db,Request,Response,Username) then Exit;
    Proof:=nil;
    if not AuthenticateEnrollment(T.Db,Username,Request.ContentFields.Values['password'],Proof) then
    begin
      SendHtml(Response,Page32('Set up one-time codes','<p>Cannot start setup. Check your credentials and whether one-time codes are already enabled.</p><p><a href="/two-factor/setup">Try again</a></p>'));Exit;
    end;
    try
      if not StartOTPEnrollment(T.Db,Proof,EnrollmentBinding(Request),Token,Secret) then
      begin Response.Code:=500;Response.Content:='Could not start setup';Response.SendContent;Exit;end;
      Body:='<h1>Set up one-time codes</h1><p>Account: '+HtmlEncode(Username)+'</p>'+
        '<p>Enter this secret in your authenticator: <code id="otp-secret">'+HtmlEncode(Secret)+'</code></p>'+
        '<p>Use time-based codes: SHA1, six digits, 30 seconds. Keep the secret private. This setup expires in five minutes.</p>'+
        ConfirmationForm(Token,'Enter a code from your authenticator to enable one-time codes.');
      SendHtml(Response,Page32('Set up one-time codes',Body));
    finally
      Proof.Free;
      if Secret<>'' then begin UniqueString(Secret);FillChar(Secret[1],Length(Secret),0);end;
    end;
    Exit;
  end;
  SendHtml(Response,Page32('Set up one-time codes','<h1>Set up one-time codes</h1>'+
    '<p>Confirm your password to start. This does not sign you in. An existing active factor cannot be replaced here.</p>'+
    '<form method="POST" action="/two-factor/setup">Username <input name="username"><br>'+
    'Password <input type="password" name="password"><br><input type="submit" value="Start setup"></form>'+
    '<p><a href="/sign-in">Sign in</a></p>'));
end;
procedure EnrollmentConfirmEndpoint(Request:TRequest;Response:TResponse);
var T:TWLTenant;Token,Binding,Username:string;Rows:TWLRows;At:Int64;
begin
  EnrollmentHeaders(Response);
  if not RequireTenant(Request,Response,T) then Exit;
  Token:=Request.ContentFields.Values['setupToken'];Binding:=EnrollmentBinding(Request);At:=DateTimeToUnix(Now,False);
  // Derive the admission account from server-side pending setup, never a posted
  // username. Invalid tokens still consume peer/tenant reservations before checking OTP.
  Username:='#enrol-invalid#'+HashText('welite-enrol-invalid-v1'+#0+Token);
  if Length(Token)=64 then
  begin
    Rows:=T.Db.Query('SELECT username FROM _wl_enrol WHERE tokenKey='+QuotedStr(TokenHash(T.Db,Token))+
      ' AND binding='+QuotedStr(Binding)+' AND created<='+IntToStr(At)+' AND expires>'+IntToStr(At)+';');
    if Length(Rows)=1 then Username:=Rows[0][0];
  end;
  if not EnrollmentAdmission(T.Db,Request,Response,Username) then Exit;
  if ConfirmOTPEnrollment(T.Db,Token,Binding,Request.ContentFields.Values['code']) then
    SendHtml(Response,Page32('One-time codes enabled','<h1>One-time codes enabled</h1><p>Wait for a new code in your authenticator, then <a href="/sign-in">sign in</a>. The confirmation code has been used.</p>'))
  else
  begin
    if Length(Token)<>64 then Token:='';
    SendHtml(Response,Page32('Confirm one-time codes',ConfirmationForm(Token,'Invalid code or setup. Try a new code, or start setup again if it has expired.')));
  end;
end;

// GET/POST /register — create an account. The first account in a tenant becomes the Global
// Admin (users.isAdmin = 1); subsequent accounts are Normal users. No-JS / no-cookie, like sign-in.
procedure RegisterEndpoint(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  S: TWLSession;
  Username, Password, Confirm, Uid, Hash, Iso, Body, PolicySecret, PolicyCondition: string;
  First: Boolean;RegistrationPolicy:TFactorPolicy;
begin
  if not RequireTenant(aRequest, aResponse, T) then Exit;
  if T.IsAdmin then
  begin
    aResponse.Code:=403; aResponse.Content:='Global Admin accounts are initialized locally; public registration is disabled.';
    aResponse.SendContent; Exit;
  end;


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
    Hash  := HashMeteorPassword(Password); // JSON object stored at services.password
    RegistrationPolicy:=ResolvedFactorPolicy(T.Db,'password','{"password":'+Hash+'}',First,PolicySecret,PolicyCondition);
    if not (RegistrationPolicy in [fpNone,fpRequired]) then
    begin SendHtml(aResponse,Page32('Register','<p>Registration with a password is unavailable.</p>'));Exit;end;
    Iso   := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Now);
    if not T.Db.Exec(Format(
      'INSERT INTO users(id,username,isAdmin,authenticationMethod,createdAt,modifiedAt,' +
      'services_json,profile_json) SELECT %s,%s,%d,''password'',%s,%s,%s,''{}'' WHERE (%s);',
      [QuotedStr(Uid), QuotedStr(Username), Ord(First), QuotedStr(Iso), QuotedStr(Iso),
       QuotedStr('{"password":' + Hash + '}'),PolicyCondition])) or
      (Length(T.Db.Query('SELECT id FROM users WHERE id='+QuotedStr(Uid)+';'))<>1) then
    begin
      SendHtml(aResponse, Page32('Register',
        '<p>Could not create the account.</p><p><a href="/register">Back</a></p>'));
      Exit;
    end;

    if RegistrationPolicy=fpRequired then
    begin
      SendHtml(aResponse,Page32('Account created','<h1>Account created</h1><p><a href="/two-factor/setup">Set up one-time codes</a> before signing in.</p>'));Exit;
    end;

    // Log the new user straight in (cookie-free session via URL), then go to the board list.
    S := CreateSession(T.Db, aRequest, Uid,Username,HashText(Hash),30*24*60*60);
    if S.SessionId='' then
    begin aResponse.Code:=500; aResponse.Content:='Account created; sign in to continue'; aResponse.SendContent; Exit; end;
    aResponse.Code := 302;
    aResponse.SetCustomHeader('Location', WithSessionId('/', S.SessionId));
    aResponse.SendContent;
    Exit;
  end;

  // GET — registration form.
  First := NoUsersYet(T);
  Body := '<h1>Register</h1>' + LineEnding;
  if First then
    Body := Body + '<p>This first account will be the <b>Domain Global Admin</b>.</p>' + LineEnding;
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
  if not ValidateSession(T.Db,aRequest,SessionIdFromRequest(aRequest),S) then
  begin
    aResponse.Code:=403; aResponse.Content:='Sign in required'; aResponse.SendContent; Exit;
  end;
  if ((aRequest.ContentFields.Values['action']='clear') and
      not BoardCanWrite(T.Db,S.UserId,aRequest.ContentFields.Values['boardId'])) or
    ((aRequest.ContentFields.Values['action']<>'clear') and
      not BoardSelectionAllowed(T.Db,S.UserId,aRequest.ContentFields.Values['boardId'],aRequest.ContentFields)) then
  begin
    aResponse.Code:=403; aResponse.Content:='Board selection forbidden'; aResponse.SendContent; Exit;
  end;
  if not VerifyActionToken(aRequest,S,'board:move',aRequest.ContentFields.Values['action']<>'export') then
  begin
    aResponse.Code := 403; aResponse.Content := 'Bad token'; aResponse.SendContent; Exit;
  end;
  if HandleSelection(T,S,aRequest,aResponse) then Exit;
  if aRequest.ContentFields.Values['dir']='drop' then
  begin
    if not ApplyCardDrop(T.Db,aRequest.ContentFields) then
    begin aResponse.Code:=400;aResponse.Content:='Invalid drop or database failure';aResponse.SendContent;Exit;end;
  end
  else ApplyMove(T.Db, aRequest.ContentFields);
  BackTo := SafeReturnPath(aRequest.ContentFields.Values['back']);
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
    if not ValidateSession(T.Db, aRequest, SessionIdFromRequest(aRequest), S) then
      S := Default(TWLSession);
    // direction mirrors RTL languages from one page definition (no separate files);
    // QueryFields carry table search/page/column-visibility state (no-JS, no cookies)
    if TryServePage(T, S, aRequest.PathInfo,
                    ResolveDir(aRequest, '',SessionLanguage(T.Db,S)), aRequest.QueryFields, aResponse) then
      Exit;
    aResponse.Code := 404;
    aResponse.ContentType := 'text/plain';
    aResponse.Content := 'Not found';
    aResponse.SendContent;
  end;
end;

// Local-only bootstrap: never expose first-Global-Admin registration over HTTP.
procedure InitGlobalAdmin;
var T: TWLTenant; R: TRequest; Uid,Username,Password,Hash,Iso: string;
begin
  Username:=Trim(ParamStr(2)); Password:=GetEnvironmentVariable('WELITE_ADMIN_PASSWORD');
  if (Username='') or (Password='') then
  begin Writeln(StdErr,'Usage: WELITE_ADMIN_PASSWORD=... welite initadmin <username>'); Halt(1); end;
  if not ProvisionTenant(ADMIN_TENANT) then
  begin Writeln(StdErr,'Could not provision the reserved admin tenant'); Halt(1); end;
  R:=TRequest.Create;
  try
    R.Host:=ADMIN_TENANT;
    if not (ResolveTenant(R,T) and TenantOpen(T)) then Halt(1);
    if not NoUsersYet(T) then
    begin Writeln(StdErr,'Global Admin is already initialized'); Halt(1); end;
    Uid:=NewId; Hash:=HashMeteorPassword(Password); Iso:=FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',Now);
    if not T.Db.Exec('INSERT INTO users(id,username,isAdmin,createdAt,modifiedAt,services_json) '+
      'SELECT '+QuotedStr(Uid)+','+QuotedStr(Username)+',1,'+QuotedStr(Iso)+','+QuotedStr(Iso)+','+
      QuotedStr('{"password":'+Hash+'}')+' WHERE NOT EXISTS(SELECT 1 FROM users);') or
      (Length(T.Db.Query('SELECT id FROM users WHERE id='+QuotedStr(Uid)+';'))=0) then
    begin Writeln(StdErr,'Global Admin initialization failed'); Halt(1); end;
    Writeln('Global Admin initialized. Sign in using the reserved admin host.');
  finally R.Free; end;
end;

var
  PortEnv, PublicDir, StaticUrl, I18nDir,DataDir: string;
begin
  // HTTP, SQLite text and JSON use UTF-8 even on hosts whose system codepage is unset.
  SetMultiByteConversionCodePage(CP_UTF8);
  Randomize;            // seed the RNG used by NewId (wlapi/wldesign) — else ids repeat per run

  if (ParamCount>=2) and (ParamStr(1)='entropy') then
  begin
    try
      CreateEntropyStock(ParamStr(2),StrToInt64Def(ParamStr(3),1024*1024));
      Writeln('Created one-use entropy stock. Keep it private and allocate it to one instance.');
      Halt(0);
    except on E:Exception do begin Writeln(StdErr,E.Message);Halt(1);end;end;
  end;

  // ops/seed helper: prints a Meteor services.password JSON object, not a quoted string.
  if (ParamCount >= 2) and (ParamStr(1) = 'hashpw') then
  begin
    Writeln(HashMeteorPassword(ParamStr(2)));
    Halt(0);
  end;

  DataDir:=GetEnvironmentVariable('WELITE_DATA');
  if DataDir='' then DataDir:=DATA_ROOT;
  TenantInit(DataDir);
  if (ParamCount>0) and (ParamStr(1)='initadmin') then
  begin InitGlobalAdmin; Halt(0); end;

  THTTPRouter.SetServiceClass(TWLCleanRouter);

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
  InitLanguages;

  HTTPRouter.RegisterRoute('/', rmGet, @HomeEndpoint);
  HTTPRouter.RegisterRoute('/sign-in', rmGet, @SignInEndpoint);
  HTTPRouter.RegisterRoute('/sign-in', rmPost, @SignInEndpoint);
  HTTPRouter.RegisterRoute('/two-factor/setup', rmGet, @EnrollmentEndpoint);
  HTTPRouter.RegisterRoute('/two-factor/setup', rmPost, @EnrollmentEndpoint);
  HTTPRouter.RegisterRoute('/two-factor/confirm', rmPost, @EnrollmentConfirmEndpoint);
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
  HTTPRouter.RegisterRoute('/designer/page/save', rmPost, @DesignerPageSave);
  HTTPRouter.RegisterRoute('/designer/widget/move', rmPost, @DesignerWidgetMove);
  HTTPRouter.RegisterRoute('/designer/widget/sort', rmPost, @DesignerWidgetSort);
  HTTPRouter.RegisterRoute('/designer/widget/save', rmPost, @DesignerWidgetSave);
  HTTPRouter.RegisterRoute('/designer/widget/delete', rmPost, @DesignerWidgetDelete);
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
  HTTPRouter.RegisterRoute('/board', rmGet, @BoardEndpoint);
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
  StartHTTPStop;
  try
    StartMaintenance(DataDir);
    Application.Run;
  finally
    try FinishHTTPStop;finally
      try StopMaintenance;Writeln('WeKan-Lite stopped');finally DoneHTTPStop;end;
    end;
  end;
end.
