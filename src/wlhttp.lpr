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
  {$IFDEF AMIGA} Sockets, {$ENDIF}
  SysUtils, Classes, DateUtils, wlattemp, wlenroll, wlpolicy, wlshared, wlmaint, wlstop, wli18n, wllocale, fphttpapp, httpdefs, httproute,
  wltenant, wlauth, wldb, wlhtml, wlbrowse, wldesign, wlmove, wlstatic, wlapi, wlpasswd, wladmin, wlaccess, wlboard,wlselect,wlentrop, wlwkweb, wlroutes, wlview, wlh5, wlrules, wlprob
  {$IFDEF WLEMBED}, wlassets {$ENDIF};   // wlassets registers the embedded-asset lookup

type
  TWLCleanRouter=class(THTTPRouter)
  protected
    procedure DoRouteRequest(Request:TRequest;Response:TResponse);override;
    procedure RouteRequest(Request:TRequest;Response:TResponse);
  end;

const
  DEFAULT_PORT  = 5500;       // wami used 5500; omi 3001. Override with WELITE_PORT.
  DATA_ROOT     = 'data';     // data/admin, data/domains/<domain>, data/certs
  DEFAULT_PUBLIC = 'public';  // static assets dir (disk mode). Override with WELITE_PUBLIC.
  DEFAULT_MOUNT = '/';        // URL the public/ tree is served under. Override WELITE_STATIC_URL.
  DEFAULT_I18N  = 'i18n';     // translations dir (i18n/langs.jsn + i18n/data). Override WELITE_I18N.
  I18N_MOUNT    = '/i18n';    // URL the i18n/ tree is served under (i18n/langs.jsn -> /i18n/langs.jsn).

// A shared store's scheduled rules for one minute (wlrules), as its tenant:
// <Dir>files/db/wekan.db.
procedure RunScheduledHook(Db:TWLDb;const Path:string;Local,Utc:TDateTime);
var T:TWLTenant;
begin
  T:=Default(TWLTenant);
  T.Db:=Db;T.DbPath:=Path;
  T.FilesDir:=ExtractFilePath(ExcludeTrailingPathDelimiter(ExtractFilePath(Path)));
  T.Dir:=ExtractFilePath(ExcludeTrailingPathDelimiter(T.FilesDir));
  RunScheduledRules(T,Local,Utc);
end;

procedure TWLCleanRouter.DoRouteRequest(Request:TRequest;Response:TResponse);
begin
  // A request that writes runs the board's rules before it answers (wlrules).
  ResetViewState;
  ArmRules(Request);
  try
    RouteRequest(Request,Response);
  finally
    FlushRules;
  end;
end;

procedure TWLCleanRouter.RouteRequest(Request:TRequest;Response:TResponse);
begin
  // The HTML5 view's own form posts (POST /b/:id/cards), before the WeKan
  // route below would read /b/:id/cards as a board (wlh5).
  if ServeHtml5Action(Request,Response) then begin CleanupUploads(Request);Exit;end;
  // WeKan's routes (/b/:id/:slug, /b/:boardId/:slug/:cardId, /sign-up) are
  // served by the WeLite pages they name (wlroutes).
  RewriteWeKanRoute(Request);
  // ?ui=html4|html5 from the header's toggle is remembered (wlview); a modern
  // browser's pages are the HTML5 view (wlh5), every other request the HTML4 one.
  RememberView(Request,Response);
  // The toggle's POST from the HTML4 view: its session into the HTML5 view's
  // cookie, and the same page again by GET (wlh5).
  if SwitchToHtml5(Request,Response) then begin CleanupUploads(Request);Exit;end;
  // The HTML4 view reads a session from the URL or the form; after the toggle
  // from the HTML5 view it is in the login cookie instead.
  if RequestView(Request)=wvHtml4 then CarryCookieSession(Request);
  if RequestView(Request)=wvHtml5 then
  try
    if ServeHtml5(Request,Response) then Exit;
  finally
    if Response.ContentSent then CleanupUploads(Request);
  end;
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
    aResponse.ContentType := 'text/html; charset=utf-8';
    aResponse.Content := LanguagePage(aResponse,ViewerLanguage(nil,Default(TWLSession),aRequest),
      'Not found','<p>Unknown domain</p>');
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

function AuthNavigation(Request:TRequest;const Path,Caption:string):string;forward;
function SignInForm(Request:TRequest;Response:TResponse;const Message:string=''):string;forward;

// GET / — board list for the resolved tenant (HTML 3.2 baseline; enhance later).
procedure ShowHome(aRequest:TRequest; aResponse:TResponse; const Session:TWLSession);
var
  T: TWLTenant;
  S: TWLSession;
  Rows: TWLRows;
  Body: string;
  i: Integer;
  IsGAdmin: Boolean;Language:TWLLanguage;Words:TWLTranslator;
begin
  if not RequireTenant(aRequest, aResponse, T) then Exit;

  // No accounts yet -> send the visitor to the login page (which links to register). The first
  // person to register becomes the Global Admin; everyone after is a Normal user.
  if NoUsersYet(T) then
  begin
    SendHtml(aResponse,SignInForm(aRequest,aResponse));
    Exit;
  end;

  // Greet the signed-in user and flag the Global Admin (users.isAdmin = 1).
  IsGAdmin := False;
  S:=Session;
  if (S.SessionId<>'') or ValidateSession(T.Db, aRequest, SessionIdFromRequest(aRequest), S) then
    IsGAdmin := IsTenantAdmin(T.Db, S)
  else S:=Default(TWLSession);
  S.LanguageTag:=RequestLanguageTag(aRequest);
  if S.SessionId<>'' then
  begin
    aResponse.SetCustomHeader('Cache-Control','no-store');
    aResponse.SetCustomHeader('Referrer-Policy','no-referrer');
  end;

  Language:=ViewerLanguage(T.Db,S,aRequest);
  Words:=TWLTranslator.Create(Language);
  try
    Body := '<h1>' + HtmlEncode(T.Host) + '</h1>' + LineEnding+
      MainNavigation(T.Db,S,Language.Tag,T.IsAdmin);
    if IsGAdmin then
      Body:=Body+'<p><b>'+HtmlEncode(Words.Text('admin','Admin'))+'</b> &mdash; '+HtmlEncode(S.Username)+'</p>'
    else if S.Username<>'' then
      Body:=Body+'<p>'+HtmlEncode(Words.Text('username','Username'))+': '+HtmlEncode(S.Username)+'</p>';

    Body:=Body+BoardListHtml(T.Db,S,Language.Tag)+
      AuthNavigation(aRequest,'/sign-in',Words.Text('log-in','Sign in'))+
      AuthNavigation(aRequest,'/sign-up',Words.Text('register','Register'));
    // detection is best-effort, never gates output (every page works on the HTML 3.2 baseline)
    Writeln('Client: ', BrowserName(DetectBrowser(RequestUserAgent(aRequest))));
    SendHtml(aResponse,LanguagePage(aResponse,Language,'WeKan-Lite',Body));
  finally Words.Free;end;
end;

procedure HomeEndpoint(aRequest:TRequest; aResponse:TResponse);
begin
  ShowHome(aRequest,aResponse,Default(TWLSession));
end;

function AuthLanguageField(Request:TRequest):string;
var S:TWLSession;
begin
  S:=Default(TWLSession);
  S.LanguageTag:=ResolveLanguage(RequestLanguageTag(Request),'',Request.AcceptLanguage).Tag;
  Result:=LanguageHiddenField(S);
end;

function AuthNavigation(Request:TRequest;const Path,Caption:string):string;
begin
  Result:='<form method="POST" action="'+HtmlAttr(Path)+'">'+AuthLanguageField(Request)+
    '<input type="hidden" name="auth_view" value="1">'+
    '<input type="submit" value="'+HtmlAttr(Caption)+'"></form>';
end;

function AuthPage(Request:TRequest;Response:TResponse;const Title,Body:string):string;
var S:TWLSession;Language:TWLLanguage;
begin
  S:=Default(TWLSession);Language:=ViewerLanguage(nil,S,Request);
  Result:=LanguagePage(Response,Language,Title,Body);
end;

function LanguagePicker(const Selected:TWLLanguage;Words:TWLTranslator;const Path:string='/sign-in'):string;
var i:Integer;Language:TWLLanguage;
begin
  Result:='<form method="POST" action="'+HtmlAttr(Path)+'"><input type="hidden" name="auth_view" value="1"><label>'+HtmlEncode(Words.Text('language','Language'))+
    ' <select name="lang">';
  for i:=0 to LanguageCount-1 do
  begin
    Language:=LanguageAt(i);
    Result:=Result+'<option value="'+HtmlAttr(Language.Tag)+'"';
    if Language.Tag=Selected.Tag then Result:=Result+' selected="selected"';
    Result:=Result+'>'+HtmlEncode(Language.Name)+'</option>';
  end;
  Result:=Result+'</select></label> <input type="submit" value="'+HtmlAttr(Words.Text('apply','Apply'))+'"></form>';
end;

function SignInForm(Request:TRequest;Response:TResponse;const Message:string):string;
var Language:TWLLanguage;Words:TWLTranslator;Title,Dir,Tag,Notice:string;
begin
  Language:=ResolveLanguage(RequestLanguageTag(Request),'',Request.AcceptLanguage);
  Words:=TWLTranslator.Create(Language);
  try
    Title:=Words.Text('log-in','Sign in');Tag:=Language.Tag;
    if Language.Rtl then Dir:='rtl' else Dir:='ltr';
    Response.SetCustomHeader('Content-Language',StringReplace(Tag,'_','-',[rfReplaceAll]));
    Response.SetCustomHeader('Vary','Accept-Language');
    Notice:='';if Message<>'' then Notice:='<p>'+HtmlEncode(Words.Text('invalid-credentials',Message))+'</p>';
    Result:=PageDir(Title,LanguagePicker(Language,Words)+'<h1>'+HtmlEncode(Title)+'</h1>'+LineEnding+
      Notice+LineEnding+
      '<form method="POST" action="/sign-in">'+AuthLanguageField(Request)+LineEnding+
      '  '+HtmlEncode(Words.Text('username','Username'))+' <input name="username"><br>'+LineEnding+
      '  '+HtmlEncode(Words.Text('password','Password'))+' <input type="password" name="password"><br>'+LineEnding+
      '  '+HtmlEncode(Words.Text('otp','One-time code (if enabled)'))+' <input name="code" size="6" maxlength="6"><br>'+LineEnding+
      '  <input type="submit" value="'+HtmlAttr(Title)+'">'+LineEnding+'</form>'+LineEnding+
      AuthNavigation(Request,'/two-factor/setup',Words.Text('two-factor-required-title','Set up two-factor authentication'))+
      AuthNavigation(Request,'/sign-up',Words.Text('create-account','Create an account (Register)'))+
      // The HTML4/HTML5 toggle (wlview): a plain link, as no session is carried yet.
      '<p><a class="html-view-toggle" href="/sign-in?ui=html5" title="'+
      HtmlAttr(Words.Text('html4-html5-toggle','Toggle between HTML4 and HTML5 view'))+'">HTML5</a></p>',Dir,Tag);
  finally Words.Free;end;
end;

procedure AuthError(Request:TRequest;Response:TResponse;Code:Integer;
  const TitleKey,Title,Message:string;const MessageKey:string='');
var Language:TWLLanguage;Words:TWLTranslator;
begin
  Language:=ViewerLanguage(nil,Default(TWLSession),Request);
  Words:=TWLTranslator.Create(Language);
  try
    Response.Code:=Code;Response.ContentType:='text/html; charset=utf-8';
    Response.Content:=LanguagePage(Response,Language,Words.Text(TitleKey,Title),
      '<p>'+HtmlEncode(Words.Text(MessageKey,Message))+'</p>');
  finally Words.Free;end;
  Response.SendContent;
end;

// POST /sign-in — authenticate against schema.sql users, then issue a cookie-free session.
procedure SignInEndpoint(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  Username, Password, Token: string;
  Proof: TWLLoginProof;
  S: TWLSession;

begin
  if not RequireTenant(aRequest, aResponse, T) then Exit;

  if (aRequest.Method = 'POST') and (aRequest.ContentFields.Values['auth_view']<>'1') then
  begin
    Username := Trim(aRequest.ContentFields.Values['username']);
    Password := aRequest.ContentFields.Values['password'];
    if not ReserveLoginAttempt(T.Db,Username,aRequest.RemoteAddress,DateTimeToUnix(Now,False)) then
    begin
      aResponse.Code:=429;aResponse.SetCustomHeader('Retry-After','300');
      AuthError(aRequest,aResponse,429,'log-in','Sign in','Too many login attempts. Try again later.','auth-too-many-attempts');Exit;
    end;
    Proof:=nil;
    if AuthenticateAccount(T.Db,Username,Password,aRequest.ContentFields.Values['code'],Proof) then
    try
      // Admin Panel / Problems / Password length: a shorter password reported (wlprob).
      NoteSignInPassword(T.Db,Proof.UserId,Proof.Username,Password,aRequest.RemoteAddress);
      // The HTML5 view of a shared store signs in as WeKan does: a Meteor
      // login token, in the user's services.resume.loginTokens, so that
      // WeKan and the store's other readers see the session (and a password
      // change or Admin Panel's sign-out ends it everywhere).
      if (RequestView(aRequest)=wvHtml5) and SharedStore(T.Db) then
      begin
        Token:=NewAuthToken;
        if not IssueAccountToken(T.Db,Proof,Token,'api',ApiTokenLifetime(T.Db)) then
        begin AuthError(aRequest,aResponse,500,'log-in','Sign in','Could not create session','auth-session-create-failed');Exit; end;
        Html5SignedIn(aResponse,Token);Exit;
      end;
      S:=CreateAuthenticatedSession(T.Db,aRequest,Proof,30*24*60*60);
      if S.SessionId='' then
      begin AuthError(aRequest,aResponse,500,'log-in','Sign in','Could not create session','auth-session-create-failed');Exit; end;
      // The HTML5 view keeps the session in WeKan's login cookie (wlh5).
      if RequestView(aRequest)=wvHtml5 then begin Html5SignedIn(aResponse,S.SessionId);Exit;end;
      ShowHome(aRequest,aResponse,S);Exit;
    finally Proof.Free;end;
    if RequestView(aRequest)=wvHtml5 then begin Html5SignInFailed(aRequest,aResponse,Username);Exit;end;
    SendHtml(aResponse,SignInForm(aRequest,aResponse,'Invalid login.'));
    Exit;
  end;

  // GET — translated form with the selected language in the POST body.
  SendHtml(aResponse,SignInForm(aRequest,aResponse));
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
    AuthError(Request,Response,429,'two-factor-required-title','One-time codes','Too many login attempts. Try again later.','auth-too-many-attempts');
  end;
end;
function ConfirmationForm(Request:TRequest;const Token,Message:string;Words:TWLTranslator):string;
var Notice:string;
begin
  Notice:='';
  if Message<>'' then Notice:='<p>'+HtmlEncode(Message)+'</p>';
  Result:='<h1>'+HtmlEncode(Words.Text('twoFactorCode-prompt','Enter your 6-digit authentication code'))+'</h1>'+LineEnding+
    Notice+
    '<form method="POST" action="/two-factor/confirm">'+AuthLanguageField(Request)+
    '<input type="hidden" name="setupToken" value="'+HtmlEncode(Token)+'">'+
    '<label for="enrol-code">'+HtmlEncode(Words.Text('otp','One-time code'))+'</label> <input id="enrol-code" name="code" size="6" maxlength="6"><br>'+
    '<input type="submit" value="'+HtmlAttr(Words.Text('confirm','Confirm'))+'"></form>'+
    AuthNavigation(Request,'/two-factor/setup',Words.Text('two-factor-required-title','Set up two-factor authentication'))+
    AuthNavigation(Request,'/sign-in',Words.Text('log-in','Sign in'));
end;
procedure EnrollmentEndpoint(Request:TRequest;Response:TResponse);
var T:TWLTenant;Username,Token,Secret,Body,Title:string;Proof:TWLEnrollProof;Words:TWLTranslator;
begin
  EnrollmentHeaders(Response);
  if not RequireTenant(Request,Response,T) then Exit;
  Words:=TWLTranslator.Create(ResolveLanguage(RequestLanguageTag(Request),'',Request.AcceptLanguage));
  try
  Title:=Words.Text('two-factor-required-title','Set up two-factor authentication');
  if (Request.Method='POST') and (Request.ContentFields.Values['auth_view']<>'1') then
  begin
    Username:=Trim(Request.ContentFields.Values['username']);
    if not EnrollmentAdmission(T.Db,Request,Response,Username) then Exit;
    Proof:=nil;
    if not AuthenticateEnrollment(T.Db,Username,Request.ContentFields.Values['password'],Proof) then
    begin
      SendHtml(Response,AuthPage(Request,Response,Title,'<p>'+HtmlEncode(Words.Text('enrollment-setup-denied','Cannot start setup. Check your credentials and whether one-time codes are already enabled.'))+'</p>'+AuthNavigation(Request,'/two-factor/setup',Title)));Exit;
    end;
    try
      if not StartOTPEnrollment(T.Db,Proof,EnrollmentBinding(Request),Token,Secret) then
      begin AuthError(Request,Response,500,'two-factor-required-title','One-time codes','Could not start setup','enrollment-setup-failed');Exit;end;
      Body:='<h1>'+HtmlEncode(Title)+'</h1><p>'+HtmlEncode(Words.Text('username','Username'))+
        ': '+HtmlEncode(Username)+'</p>'+
        '<p>'+HtmlEncode(Words.Text('twoFactorAuth-manual-entry','Or enter this code manually: '))+'<code id="otp-secret">'+HtmlEncode(Secret)+'</code></p>'+
        '<p>'+HtmlEncode(Words.Text('enrollment-code-instructions','Use time-based codes: SHA1, six digits, 30 seconds. Keep the secret private. This setup expires in five minutes.'))+'</p>'+
        ConfirmationForm(Request,Token,'',Words);
      SendHtml(Response,AuthPage(Request,Response,Title,Body));
    finally
      Proof.Free;
      if Secret<>'' then begin UniqueString(Secret);FillChar(Secret[1],Length(Secret),0);end;
    end;
    Exit;
  end;
  SendHtml(Response,AuthPage(Request,Response,Title,'<h1>'+HtmlEncode(Title)+'</h1>'+
    '<p>'+HtmlEncode(Words.Text('enrollment-password-instructions','Confirm your password to start. This does not sign you in. An existing active factor cannot be replaced here.'))+'</p>'+
    '<form method="POST" action="/two-factor/setup">'+AuthLanguageField(Request)+'<label for="enrol-username">'+HtmlEncode(Words.Text('username','Username'))+'</label> <input id="enrol-username" name="username"><br>'+
    '<label for="enrol-password">'+HtmlEncode(Words.Text('password','Password'))+'</label> <input id="enrol-password" type="password" name="password"><br><input type="submit" value="'+HtmlAttr(Words.Text('start','Start setup'))+'"></form>'+
    AuthNavigation(Request,'/sign-in',Words.Text('log-in','Sign in'))));
  finally Words.Free;end;
end;
procedure EnrollmentConfirmEndpoint(Request:TRequest;Response:TResponse);
var T:TWLTenant;Token,Binding,Username,Title:string;Rows:TWLRows;At:Int64;Words:TWLTranslator;
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
  Words:=TWLTranslator.Create(ResolveLanguage(RequestLanguageTag(Request),'',Request.AcceptLanguage));
  try
  if ConfirmOTPEnrollment(T.Db,Token,Binding,Request.ContentFields.Values['code']) then
  begin
    Title:=Words.Text('twoFactorAuth-enabled','Two-factor authentication is enabled for your account.');
    SendHtml(Response,AuthPage(Request,Response,Title,'<h1>'+HtmlEncode(Title)+'</h1>'+
      '<p>'+HtmlEncode(Words.Text('enrollment-confirmed-instructions',
      'The confirmation code has been used. Wait for a new code in your authenticator before signing in.'))+
      '</p>'+AuthNavigation(Request,'/sign-in',Words.Text('log-in','Sign in'))));
  end
  else
  begin
    if Length(Token)<>64 then Token:='';
    Title:=Words.Text('twoFactorCode-prompt','Enter your 6-digit authentication code');
    SendHtml(Response,AuthPage(Request,Response,Title,ConfirmationForm(Request,Token,
      Words.Text('twoFactorCode-invalid','Invalid authentication code. Please try again.'),Words)));
  end;
  finally Words.Free;end;
end;

function RegisterForm(Request:TRequest;Response:TResponse;First:Boolean;
  const MessageKey:string='';const Message:string=''):string;
var Language:TWLLanguage;Words:TWLTranslator;Body,Title:string;
begin
  Language:=ResolveLanguage(RequestLanguageTag(Request),'',Request.AcceptLanguage);
  Words:=TWLTranslator.Create(Language);
  try
    Title:=Words.Text('register','Register');
    Body:=LanguagePicker(Language,Words,'/sign-up')+'<h1>'+HtmlEncode(Title)+'</h1>';
    if Message<>'' then Body:=Body+'<p>'+HtmlEncode(Words.Text(MessageKey,Message))+'</p>';
    if First then Body:=Body+'<p>'+HtmlEncode(Words.Text('registration-first-admin',
      'This first account will be the Domain Global Admin.'))+'</p>';
    Body:=Body+'<form method="POST" action="/register">'+AuthLanguageField(Request)+
      '<label for="register-username">'+HtmlEncode(Words.Text('username','Username'))+'</label> '+
      '<input id="register-username" name="username"><br>'+
      '<label for="register-password">'+HtmlEncode(Words.Text('password','Password'))+'</label> '+
      '<input id="register-password" type="password" name="password"><br>'+
      '<label for="register-confirm">'+HtmlEncode(Words.Text('password-again','Confirm'))+'</label> '+
      '<input id="register-confirm" type="password" name="confirm"><br>'+
      '<input type="submit" value="'+HtmlAttr(Title)+'"></form>'+
      AuthNavigation(Request,'/sign-in',Words.Text('log-in','Sign in'));
    Result:=AuthPage(Request,Response,Title,Body);
  finally Words.Free;end;
end;

// GET/POST /register — create an account. The first account in a tenant becomes the Global
// Admin (users.isAdmin = 1); subsequent accounts are Normal users. No-JS / no-cookie, like sign-in.
procedure RegisterEndpoint(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  S: TWLSession;
  Username, Password, Confirm, Uid, Hash, Iso, PolicySecret, PolicyCondition, Title, Email: string;
  First, Html5, Enforce: Boolean; MinLength: Integer;RegistrationPolicy:TFactorPolicy;Words:TWLTranslator;
begin
  if not RequireTenant(aRequest, aResponse, T) then Exit;
  if T.IsAdmin then
  begin
    AuthError(aRequest,aResponse,403,'register','Register',
      'Global Admin accounts are initialized locally. Public registration is disabled.',
      'registration-global-admin-disabled');Exit;
  end;


  if (aRequest.Method = 'POST') and (aRequest.ContentFields.Values['auth_view']<>'1') then
  begin
    Username := Trim(aRequest.ContentFields.Values['username']);
    Password := aRequest.ContentFields.Values['password'];
    Confirm  := aRequest.ContentFields.Values['confirm'];
    // The HTML5 view's form (wlh5) also takes WeKan's address, kept as the
    // account's email; its errors are shown in that form.
    Email := LowerCase(Trim(aRequest.ContentFields.Values['email']));
    Html5 := RequestView(aRequest)=wvHtml5;

    if (Username = '') or (Password = '') then
    begin
      if Html5 then Html5SignUpPage(aRequest,aResponse,400,'username-password-required','Username and password are required.',Username,Email) else
      SendHtml(aResponse, RegisterForm(aRequest,aResponse,NoUsersYet(T),'username-password-required','Username and password are required.'));
      Exit;
    end;
    // WeKan's password policy: an enforced minimum, and never over 512.
    PasswordPolicy(T.Db,MinLength,Enforce);
    if (Enforce and (Length(UTF8Decode(Password))<MinLength)) or (Length(UTF8Decode(Password))>512) then
    begin
      if Html5 then Html5SignUpPage(aRequest,aResponse,400,'password-too-short','The password is too short.',Username,Email) else
      SendHtml(aResponse, RegisterForm(aRequest,aResponse,NoUsersYet(T),'password-too-short','The password is too short.'));
      Exit;
    end;
    if Password <> Confirm then
    begin
      if Html5 then Html5SignUpPage(aRequest,aResponse,400,'password-mismatch','Passwords do not match.',Username,Email) else
      SendHtml(aResponse, RegisterForm(aRequest,aResponse,NoUsersYet(T),'password-mismatch','Passwords do not match.'));
      Exit;
    end;
    if Length(T.Db.Query(Format('SELECT id FROM users WHERE username=%s LIMIT 1;',
                                [QuotedStr(Username)]))) > 0 then
    begin
      if Html5 then Html5SignUpPage(aRequest,aResponse,400,'error-username-taken','That username is taken.',Username,Email) else
      SendHtml(aResponse, RegisterForm(aRequest,aResponse,NoUsersYet(T),'error-username-taken','That username is taken.'));
      Exit;
    end;

    if Html5 and ((Email='') or (Length(Email)>254) or (Pos('@',Email)<2) or (Pos(' ',Email)>0) or (Pos(#0,Email)>0)) then
    begin Html5SignUpPage(aRequest,aResponse,400,'error-user-notCreated','Could not create the account.',Username,Email);Exit;end;
    if (Email<>'') and (Length(T.Db.Query('SELECT 1 FROM user_emails WHERE lower(address)='+QuotedStr(Email)+';'))>0) then
    begin
      if Html5 then Html5SignUpPage(aRequest,aResponse,409,'error-email-taken','Email has already been taken',Username,Email)
      else SendHtml(aResponse, RegisterForm(aRequest,aResponse,NoUsersYet(T),'error-email-taken','Email has already been taken'));
      Exit;
    end;
    First := NoUsersYet(T);                 // first account -> Global Admin
    Uid   := NewId;
    Hash  := HashMeteorPassword(Password); // JSON object stored at services.password
    RegistrationPolicy:=ResolvedFactorPolicy(T.Db,'password','{"password":'+Hash+'}',First,PolicySecret,PolicyCondition);
    if not (RegistrationPolicy in [fpNone,fpRequired]) then
    begin
      AuthError(aRequest,aResponse,200,'register','Register',
        'Registration with a password is unavailable.','registration-password-unavailable');
      Exit;
    end;
    Iso   := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Now);
    if not T.Db.Exec(Format(
      'INSERT INTO users(id,username,isAdmin,authenticationMethod,createdAt,modifiedAt,' +
      'services_json,profile_json) SELECT %s,%s,%d,''password'',%s,%s,%s,''{}'' WHERE (%s);',
      [QuotedStr(Uid), QuotedStr(Username), Ord(First), QuotedStr(Iso), QuotedStr(Iso),
       QuotedStr('{"password":' + Hash + '}'),PolicyCondition])) or
      (Length(T.Db.Query('SELECT id FROM users WHERE id='+QuotedStr(Uid)+';'))<>1) then
    begin
      if Html5 then Html5SignUpPage(aRequest,aResponse,400,'error-user-notCreated','Could not create the account.',Username,Email) else
      SendHtml(aResponse, RegisterForm(aRequest,aResponse,NoUsersYet(T),'error-user-notCreated','Could not create the account.'));
      Exit;
    end;

    if (Email<>'') and not T.Db.Exec('INSERT INTO user_emails(userId,address,verified) VALUES('+QuotedStr(Uid)+','+QuotedStr(Email)+',0);') then
    begin AuthError(aRequest,aResponse,500,'register','Register','Could not create the account.','error-user-notCreated');Exit;end;
    if RegistrationPolicy=fpRequired then
    begin
      Words:=TWLTranslator.Create(ResolveLanguage(RequestLanguageTag(aRequest),'',aRequest.AcceptLanguage));
      try
        Title:=Words.Text('enrollment-account-created','Account created');
        SendHtml(aResponse,AuthPage(aRequest,aResponse,Title,'<h1>'+HtmlEncode(Title)+'</h1><p>'+
          HtmlEncode(Words.Text('two-factor-required-text','This site requires two-factor authentication for your account. Set it up to continue.'))+
          '</p>'+AuthNavigation(aRequest,'/two-factor/setup',Words.Text('two-factor-required-title','Set up two-factor authentication'))));
      finally
        Words.Free;
      end;
      Exit;
    end;

    // Log the new user in and render the board list without a redirect.
    S := CreateSession(T.Db, aRequest, Uid,Username,HashText(Hash),30*24*60*60);
    if S.SessionId='' then
    begin AuthError(aRequest,aResponse,500,'register','Register','Account created! You can now sign in.','account-created');Exit; end;
    if Html5 then begin Html5SignedIn(aResponse,S.SessionId);Exit;end;
    ShowHome(aRequest,aResponse,S);
    Exit;
  end;

  // GET — translated registration form with no credential values.
  SendHtml(aResponse,RegisterForm(aRequest,aResponse,NoUsersYet(T)));
end;

// Catch-all: after the fixed routes, try the tenant's designer pages table (pages.url),
// then 404. This is what makes custom Designer pages and remapped builtin URLs resolve.
// POST /board/move — the no-JS combined move component (wlmove). Reads dir + sel_* selections,
// reorders/relocates, then PRG-redirects back to the page the move came from.
procedure BoardRestoreListEndpoint(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;S:TWLSession;BoardId,ListId,BatchId:string;
begin
  if not RequireTenant(aRequest,aResponse,T) then Exit;
  BoardId:=aRequest.ContentFields.Values['boardId'];
  ListId:=aRequest.ContentFields.Values['listId'];
  BatchId:=aRequest.ContentFields.Values['deleteBatchId'];
  if not ValidateSession(T.Db,aRequest,SessionIdFromRequest(aRequest),S) or
    not BoardCanWrite(T.Db,S.UserId,BoardId) or
    not VerifyActionToken(aRequest,S,RestoreListAction(BoardId,ListId,BatchId),True) then
  begin aResponse.Code:=403;aResponse.SendContent;Exit;end;
  if not RestoreDeletedList(T.Db,S.UserId,BoardId,ListId,BatchId) then
  begin aResponse.Code:=409;aResponse.SendContent;Exit;end;
  S.LanguageTag:=RequestLanguageTag(aRequest);
  aResponse.Code:=302;
  aResponse.SetCustomHeader('Location',SessionUrl(BoardRoute(BoardId,BoardSlug(T.Db,BoardId)),S));
  aResponse.SendContent;
end;

procedure BoardMoveEndpoint(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  S: TWLSession;
  BackTo,ViewCommand,ViewId,Field,Direction:string;
  MoveRtl,Edge,HasSelection:Boolean;
  I,ViewCount:Integer;
  procedure PrepareBoardView;
  var Name:string;
  begin
    aRequest.QueryFields.Clear;
    aRequest.QueryFields.Values['id']:=aRequest.ContentFields.Values['boardId'];
    for Name in ['x','y','cols','rows'] do
      aRequest.QueryFields.Values[Name]:=aRequest.ContentFields.Values['view_'+Name];
    aRequest.QueryFields.Values['view']:=aRequest.ContentFields.Values['view_all'];
    aRequest.QueryFields.Values['expand']:=aRequest.ContentFields.Values['view_list'];
    aRequest.QueryFields.Values['subtasks']:=aRequest.ContentFields.Values['view_subtask'];
  end;
  procedure Fail(Code:Integer;const Message:string);
  begin
    aResponse.Code:=Code;aResponse.ContentType:='text/html; charset=utf-8';
    aResponse.Content:=LanguagePage(aResponse,ViewerLanguage(T.Db,S,aRequest),
      'Board action','<p>'+HtmlEncode(Message)+'</p>');
    aResponse.SendContent;
  end;
begin
  if not RequireTenant(aRequest, aResponse, T) then Exit;
  if not ValidateSession(T.Db,aRequest,SessionIdFromRequest(aRequest),S) then
  begin
    S:=Default(TWLSession);Fail(403,'Sign in required');Exit;
  end;
  if not NormalizeMoveSubmit(aRequest.ContentFields) then
  begin Fail(400,'Ambiguous movement command');Exit;end;
  ViewCount:=0; ViewCommand:=''; ViewId:=''; HasSelection:=False;
  for I:=0 to aRequest.ContentFields.Count-1 do
  begin
    Field:=aRequest.ContentFields.Names[I];
    if SameText(Field,'sel_card') or SameText(Field,'sel_list') or SameText(Field,'sel_swimlane') then
      HasSelection:=True;
    if (Field='view_card') or (Field='view_expand') or (Field='view_tasks') or
      (Field='view_map') or (Field='view_resize') then
    begin
      Inc(ViewCount);
      ViewCommand:=Field;
      ViewId:=aRequest.ContentFields.ValueFromIndex[I];
    end;
  end;
  if ViewCount<>0 then
  begin
    if (ViewCount<>1) or (ViewId='') or (Pos(#0,ViewId)>0) or
      (aRequest.ContentFields.IndexOfName('action')>=0) or
      (aRequest.ContentFields.IndexOfName('dir')>=0) then
    begin Fail(400,'Ambiguous board navigation');Exit;end;
    PrepareBoardView;
    if ViewCommand='view_card' then
    begin
      aRequest.QueryFields.Values['card']:=ViewId;
      BoardCardEndpoint(aRequest,aResponse);
    end
    else if (ViewCommand='view_map') or (ViewCommand='view_resize') then
      BoardEndpoint(aRequest,aResponse)
    else
    begin
      if ViewCommand='view_expand' then Field:='expand' else Field:='subtasks';
      if aRequest.QueryFields.Values[Field]=ViewId then aRequest.QueryFields.Values[Field]:=''
      else aRequest.QueryFields.Values[Field]:=ViewId;
      BoardEndpoint(aRequest,aResponse);
    end;
    Exit;
  end;
  if not HasSelection and (aRequest.ContentFields.IndexOfName('action')<0) and
    ArrowDirection(aRequest.ContentFields.Values['dir'],Direction,Edge) then
  begin
    PrepareBoardView;
    aRequest.QueryFields.Values['viewport_dir']:=aRequest.ContentFields.Values['dir'];
    BoardEndpoint(aRequest,aResponse);
    Exit;
  end;
  if ((aRequest.ContentFields.Values['action']='clear') and
      not BoardCanWrite(T.Db,S.UserId,aRequest.ContentFields.Values['boardId'])) or
    ((aRequest.ContentFields.Values['action']<>'clear') and
      not BoardSelectionAllowed(T.Db,S.UserId,aRequest.ContentFields.Values['boardId'],aRequest.ContentFields)) then
  begin
    Fail(403,'Board selection forbidden');Exit;
  end;
  if not VerifyActionToken(aRequest,S,'board:move',aRequest.ContentFields.Values['action']<>'export') then
  begin
    Fail(403,'Bad token');Exit;
  end;
  if not BoardMoveDirection(T.Db,S,aRequest,MoveRtl) then
  begin Fail(400,'Invalid board widget context');Exit;end;
  if HandleSelection(T,S,aRequest,aResponse) then Exit;
  if aRequest.ContentFields.Values['dir']='drop' then
  begin
    if not ApplyCardDrop(T.Db,aRequest.ContentFields) then
    begin Fail(400,'Invalid drop or database failure');Exit;end;
  end
  else begin
    ApplyMove(T.Db,aRequest.ContentFields,MoveRtl);
  end;
  if (aRequest.ContentFields.Values['boardWidget']='') and
    (aRequest.ContentFields.IndexOfName('view_x')>=0) then
  begin
    PrepareBoardView;
    BoardEndpoint(aRequest,aResponse);
    Exit;
  end;
  BackTo := SafeReturnPath(aRequest.ContentFields.Values['back']);
  aResponse.Code := 302;
  aResponse.SetCustomHeader('Location', SessionUrl(BackTo,S));
  aResponse.SendContent;
end;

procedure CatchAll(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  S: TWLSession;Language:TWLLanguage;Dir,Message:string;
  Words:TWLTranslator;
begin
  // Static assets (global, tenant-independent): public/robots.txt -> /robots.txt,
  // public/js/interact.js -> /js/interact.js, i18n/langs.jsn -> /i18n/langs.jsn,
  // etc. Tried before tenant pages.
  if ServeStatic(aRequest, aResponse) then Exit;
  if RequireTenant(aRequest, aResponse, T) then
  begin
    if not ValidateSession(T.Db, aRequest, SessionIdFromRequest(aRequest), S) then
      S := Default(TWLSession);
    S.LanguageTag:=RequestLanguageTag(aRequest);
    // direction mirrors RTL languages from one page definition (no separate files);
    // QueryFields carry table search/page/column-visibility state (no-JS, no cookies)
    Language:=ViewerLanguage(T.Db,S,aRequest);
    if Language.Rtl then Dir:='rtl' else Dir:='ltr';
    if TryServePage(T,S,aRequest.PathInfo,Dir,aRequest.QueryFields,aResponse,Language.Tag) then
      Exit;
    aResponse.Code := 404;
    aResponse.ContentType := 'text/html; charset=utf-8';
    Words:=TWLTranslator.Create(Language);
    try
      Message:=Words.Text('page-not-found','Page not found.');
    finally
      Words.Free;
    end;
    aResponse.Content := LanguagePage(aResponse,Language,Message,'<p>'+HtmlEncode(Message)+'</p>');
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

  {$IFDEF AMIGA}
  if (ParamStr(1)<>'initadmin') and
    ((Sockets.SocketBase=nil) {$IFDEF AMIGAOS4}or (Sockets.ISocket=nil){$ENDIF}) then
  begin
    Writeln(StdErr,'WeKan-Lite requires bsdsocket.library version 4. Start the Amiga TCP/IP stack first.');
    Halt(1);
  end;
  {$ENDIF}

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
  HTTPRouter.RegisterRoute('/', rmPost, @HomeEndpoint);
  HTTPRouter.RegisterRoute('/sign-in', rmGet, @SignInEndpoint);
  HTTPRouter.RegisterRoute('/sign-in', rmPost, @SignInEndpoint);
  HTTPRouter.RegisterRoute('/two-factor/setup', rmGet, @EnrollmentEndpoint);
  HTTPRouter.RegisterRoute('/two-factor/setup', rmPost, @EnrollmentEndpoint);
  HTTPRouter.RegisterRoute('/two-factor/confirm', rmPost, @EnrollmentConfirmEndpoint);
  HTTPRouter.RegisterRoute('/logout', rmPost, @Html5LogoutEndpoint);
  HTTPRouter.RegisterRoute('/register', rmGet, @RegisterEndpoint);
  HTTPRouter.RegisterRoute('/register', rmPost, @RegisterEndpoint);

  // Global Admin Panel (Domains / Designer / People) — see wladmin; Designer lives at /designer
  HTTPRouter.RegisterRoute('/admin', rmGet, @AdminIndex);
  HTTPRouter.RegisterRoute('/admin', rmPost, @AdminIndex);
  HTTPRouter.RegisterRoute('/admin/domains', rmGet, @AdminDomains);
  HTTPRouter.RegisterRoute('/admin/domains', rmPost, @AdminDomains);
  HTTPRouter.RegisterRoute('/admin/people', rmGet, @AdminPeople);
  HTTPRouter.RegisterRoute('/admin/people', rmPost, @AdminPeople);
  // Read-only WeKan data folders (WELITE_WEKAN_ROOTS) — see docs/wekandir.md
  HTTPRouter.RegisterRoute('/wekan', rmGet, @WeKanDataEndpoint);
  HTTPRouter.RegisterRoute('/wekan', rmPost, @WeKanDataEndpoint);
  HTTPRouter.RegisterRoute('/wekan/boards', rmGet, @WeKanBoardsEndpoint);
  HTTPRouter.RegisterRoute('/wekan/boards', rmPost, @WeKanBoardsEndpoint);
  HTTPRouter.RegisterRoute('/wekan/board', rmGet, @WeKanBoardEndpoint);
  HTTPRouter.RegisterRoute('/wekan/board', rmPost, @WeKanBoardEndpoint);
  HTTPRouter.RegisterRoute('/wekan/card', rmGet, @WeKanCardEndpoint);
  HTTPRouter.RegisterRoute('/wekan/card', rmPost, @WeKanCardEndpoint);
  HTTPRouter.RegisterRoute('/wekan/file', rmGet, @WeKanFileEndpoint);

  // Designer (Domain Global Admin; no-JS/no-cookie) — see docs/designer.md
  HTTPRouter.RegisterRoute('/designer', rmGet, @DesignerIndex);
  HTTPRouter.RegisterRoute('/designer', rmPost, @DesignerIndex);
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
  HTTPRouter.RegisterRoute('/api/attachment/list/:boardId', rmGet, @ApiCardAttachmentsList);
  HTTPRouter.RegisterRoute('/api/attachment/list/:boardId/:swimlaneId', rmGet, @ApiCardAttachmentsList);
  HTTPRouter.RegisterRoute('/api/attachment/list/:boardId/:swimlaneId/:listId', rmGet, @ApiCardAttachmentsList);
  HTTPRouter.RegisterRoute('/api/attachment/list/:boardId/:swimlaneId/:listId/:cardId', rmGet, @ApiCardAttachmentsList);

  // Combined no-JS move component (arrows keypad) — see docs/move.md
  HTTPRouter.RegisterRoute('/board', rmGet, @BoardEndpoint);
  HTTPRouter.RegisterRoute('/board', rmPost, @BoardEndpoint);
  HTTPRouter.RegisterRoute('/board/card', rmGet, @BoardCardEndpoint);
  HTTPRouter.RegisterRoute('/board/card', rmPost, @BoardCardEndpoint);
  HTTPRouter.RegisterRoute('/board/calendar', rmGet, @BoardCalendarEndpoint);
  HTTPRouter.RegisterRoute('/board/calendar', rmPost, @BoardCalendarEndpoint);
  HTTPRouter.RegisterRoute('/board/card/dropdown', rmPost, @BoardDropdownEndpoint);
  HTTPRouter.RegisterRoute('/board/attachment/upload', rmPost, @BoardAttachmentUploadEndpoint);
  HTTPRouter.RegisterRoute('/board/attachment/rename', rmPost, @BoardAttachmentRenameEndpoint);
  HTTPRouter.RegisterRoute('/board/attachment/delete', rmPost, @BoardAttachmentDeleteEndpoint);
  HTTPRouter.RegisterRoute('/board/attachment', rmGet, @BoardAttachmentEndpoint);
  HTTPRouter.RegisterRoute('/board/attachments', rmGet, @BoardAttachmentsEndpoint);
  HTTPRouter.RegisterRoute('/board/attachments', rmPost, @BoardAttachmentsEndpoint);
  HTTPRouter.RegisterRoute('/board/export', rmGet, @BrowserBoardExport);
  HTTPRouter.RegisterRoute('/board/export', rmPost, @BrowserBoardExport);
  HTTPRouter.RegisterRoute('/board/webhooks', rmGet, @BrowserIntegrations);
  HTTPRouter.RegisterRoute('/board/webhooks', rmPost, @BrowserIntegrations);
  HTTPRouter.RegisterRoute('/board/move', rmPost, @BoardMoveEndpoint);
  HTTPRouter.RegisterRoute('/board/restore-list', rmPost, @BoardRestoreListEndpoint);

  // REST API (subset of public/api/wekan.yml) so the WeKan Python CLI api.py works — see wlapi
  HTTPRouter.RegisterRoute('/users/login', rmPost, @ApiLogin);
  HTTPRouter.RegisterRoute('/users/logout', rmPost, @ApiLogout);
  HTTPRouter.RegisterRoute('/api/createtoken/:userId', rmPost, @ApiCreateToken);
  HTTPRouter.RegisterRoute('/api/deletetoken', rmPost, @ApiDeleteToken);
  HTTPRouter.RegisterRoute('/api/user', rmGet, @ApiUser);
  HTTPRouter.RegisterRoute('/api/user/cards', rmGet, @ApiMyCards);
  HTTPRouter.RegisterRoute('/api/users', rmGet, @ApiUsers);
  HTTPRouter.RegisterRoute('/api/admin/orgs', rmGet, @ApiOrgFeatures);
  HTTPRouter.RegisterRoute('/api/admin/teams', rmGet, @ApiTeamFeatures);
  HTTPRouter.RegisterRoute('/api/admin/orgs/features', rmPut, @ApiOrgFeatures);
  HTTPRouter.RegisterRoute('/api/admin/teams/features', rmPut, @ApiTeamFeatures);
  HTTPRouter.RegisterRoute('/api/admin/orgs/:orgId/features', rmPut, @ApiOrgFeatures);
  HTTPRouter.RegisterRoute('/api/admin/teams/:teamId/features', rmPut, @ApiTeamFeatures);
  HTTPRouter.RegisterRoute('/api/users/:userId', rmDelete, @ApiChangeUser);
  HTTPRouter.RegisterRoute('/api/users/:userId', rmPut, @ApiChangeUser);
  HTTPRouter.RegisterRoute('/api/boards', rmGet, @ApiPublicBoards);
  HTTPRouter.RegisterRoute('/api/boards', rmPost, @ApiCreateBoard);
  HTTPRouter.RegisterRoute('/import/github', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/gitlab', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/gitea', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/forgejo', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/asana', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/openproject', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/zenkit', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/jira', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/kanri', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/markdown', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/wekan', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/trello', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/pivotal', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/redmine', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/tasksorg', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/superproductivity', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/clickup', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/ticktick', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/linear', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/quire', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/obsidian', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/meistertask', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/nullboard', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/monday', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/wrike', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/teamwork', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/businessmap', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/opml', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/todotxt', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/taskwarrior', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/orgmode', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/focalboard', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/todoist', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/csv', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/excel', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/planner', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/vikunja', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/notion', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/plane', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/taiga', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/deck', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/import/kanboard', rmGet, @Html5ExternalImport);
  HTTPRouter.RegisterRoute('/api/boards/import', rmPost, @ApiImportBoard);
  HTTPRouter.RegisterRoute('/api/import/zip', rmPost, @ApiImportBoard);
  HTTPRouter.RegisterRoute('/api/users/:userId/boards', rmGet, @ApiUserBoards);
  HTTPRouter.RegisterRoute('/api/boards/:boardId', rmGet, @ApiBoard);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/export', rmGet, @ApiBoardExport);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/calendar.ics', rmGet, @ApiBoardCalendar);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/export/csv', rmGet, @ApiBoardCsv);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/exportZip', rmGet, @ApiBoardZip);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/charts/burndown/exportPDF', rmGet, @ApiBoardBurnReport);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/charts/burndown/exportExcel', rmGet, @ApiBoardBurnReport);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/charts/burnup/exportPDF', rmGet, @ApiBoardBurnReport);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/charts/burnup/exportExcel', rmGet, @ApiBoardBurnReport);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/charts/scrumVelocity/exportExcel', rmGet, @ApiScrumVelocityReport);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/charts/scrumVelocity/exportPDF', rmGet, @ApiScrumVelocityReport);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/charts/time/exportExcel', rmGet, @ApiBoardTimeReport);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/charts/time/exportPDF', rmGet, @ApiBoardTimeReport);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/exportExcel', rmGet, @ApiBoardDocument);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/export/planner', rmGet, @ApiBoardDocument);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/export/vikunja', rmGet, @ApiBoardVikunja);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/exportExcel', rmGet, @ApiBoardDocument);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/exportPDF', rmGet, @ApiBoardDocument);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/exportPDF', rmGet, @ApiBoardDocument);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/domains', rmGet, @ApiBoardDomains);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/domains', rmPost, @ApiBoardDomains);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/domains/:domain', rmDelete, @ApiBoardDomains);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/integrations', rmGet, @ApiIntegration);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/integrations', rmPost, @ApiIntegration);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/integrations/:intId', rmGet, @ApiIntegration);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/integrations/:intId', rmDelete, @ApiIntegration);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/integrations/:intId', rmPut, @ApiIntegration);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/rules', rmGet, @ApiBoardRules);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/rules', rmPost, @ApiCreateRule);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/rules/:ruleId', rmGet, @ApiBoardRules);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/rules/:ruleId', rmPut, @ApiEditRule);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/rules/:ruleId', rmDelete, @ApiDeleteRule);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cardSettings', rmGet, @ApiBoardCardSettings);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cardSettings', rmPut, @ApiBoardCardSettings);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/members/:userId/add', rmPost, @ApiAddBoardMember);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/members/:userId/remove', rmPost, @ApiRemoveBoardMember);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/title', rmPut, @ApiBoardTitle);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/copy', rmPost, @ApiBoardCopy);
  HTTPRouter.RegisterRoute('/api/boards/:boardId', rmDelete, @ApiBoardDelete);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/labels', rmPut, @ApiCreateLabel);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/custom-fields', rmGet, @ApiCustomFields);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/custom-fields', rmPost, @ApiCustomFields);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/custom-fields/:customField', rmGet, @ApiCustomField);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/custom-fields/:customField', rmPut, @ApiUpdateCustomField);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/custom-fields/:customField', rmDelete, @ApiDeleteCustomField);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/custom-fields/:customField/dropdown-items', rmPost, @ApiAppendDropdownItems);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/custom-fields/:customField/dropdown-items/:dropdownItem', rmDelete, @ApiDropdownItem);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/custom-fields/:customField/dropdown-items/:dropdownItem', rmPut, @ApiDropdownItem);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/archive', rmPost, @ApiListArchive);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/unarchive', rmPost, @ApiListArchive);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/customFields/:customField', rmPost, @ApiCardCustomField);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/swimlanes', rmGet, @ApiSwimlanes);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/swimlanes', rmPost, @ApiSwimlanes);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/swimlanes/:swimlaneId', rmGet, @ApiSwimlane);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/swimlanes/:swimlaneId', rmPut, @ApiSwimlane);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/swimlanes/:swimlaneId', rmDelete, @ApiSwimlaneDelete);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/swimlanes/:swimlaneId/cards', rmGet, @ApiSwimlaneCards);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists', rmGet, @ApiLists);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists', rmPost, @ApiLists);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId', rmGet, @ApiList);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId', rmPut, @ApiListEdit);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId', rmDelete, @ApiListDelete);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards', rmGet, @ApiListCards);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/bulk', rmPost, @ApiBulkCards);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards', rmPost, @ApiCards);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards_count', rmGet, @ApiListCardsCount);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards_count', rmGet, @ApiBoardCardsCount);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/bulk', rmDelete, @ApiBulkCardDelete);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/labels', rmPost, @ApiBulkCardLabels);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId', rmGet, @ApiCard);
  HTTPRouter.RegisterRoute('/api/cards/:cardId', rmGet, @ApiCard);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId', rmPut, @ApiCardEdit);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId', rmDelete, @ApiCardDelete);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/copy', rmPost, @ApiCopyCard);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/archive', rmPost, @ApiCardArchive);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/unarchive', rmPost, @ApiCardArchive);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/members/:member', rmPost, @ApiCardMember);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/members/:member', rmDelete, @ApiCardMember);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/assignees/:assignee', rmPost, @ApiCardAssignee);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/lists/:listId/cards/:cardId/assignees/:assignee', rmDelete, @ApiCardAssignee);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/dependencies', rmGet, @ApiDependencies);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/dependencies', rmGet, @ApiDependencies);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/dependencies', rmPost, @ApiDependencies);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/dependencies/:targetId', rmPut, @ApiDependencies);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/dependencies/:targetId', rmDelete, @ApiDependencies);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/checklists', rmGet, @ApiCardChecklists);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/checklists', rmPost, @ApiCardChecklists);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/checklists/:checklistId', rmGet, @ApiChecklist);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/checklists/:checklistId', rmDelete, @ApiChecklist);
  HTTPRouter.RegisterRoute('/api/boards/:boardId/cards/:cardId/checklists/:checklistId', rmPut, @ApiChecklist);
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
  Application.Address := GetEnvironmentVariable('WELITE_ADDRESS');
  Application.Threaded := True;
  Application.Initialize;
  Writeln('WeKan-Lite listening on :', Application.Port, ' (data root: ', DataDir, ')');
  StartHTTPStop;
  try
    // The scheduled rules of every shared store, from the maintenance pass.
    ScheduledHook:=@RunScheduledHook;
    StartMaintenance(DataDir);
    Application.Run;
  finally
    try FinishHTTPStop;finally
      try StopMaintenance;Writeln('WeKan-Lite stopped');finally DoneHTTPStop;end;
    end;
  end;
end.
