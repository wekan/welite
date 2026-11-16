unit wlauth;

{
  WeKan-Lite — no-cookie / no-JS authentication (docs/goals.md G4)

  Distilled from https://github.com/wekan/omi/blob/main/public/server.pas, which already solves "auth for IBrowse / NetSurf /
  Dillo / Lynx": the session id rides in the URL and in hidden <form> fields (never a required
  cookie), and every state-changing POST carries an action-token bound to the session.

  Mechanism (unchanged from omi, retargeted onto schema.sql):
    * sessionId        : from ?sessionId= (query) or a hidden form field, not a cookie.
    * action-token     : Hash(action | username | passwordRef | ip | userAgent | loginAt |
                          counter | sessionId), placed in a hidden field on each form.
    * counter          : per-action, increments on every accepted token -> replay protection.
    * IP + User-Agent  : bound into the token; mismatch invalidates the session.
    * idle timeout     : session expires after N idle seconds.

  Difference from omi: the bearer/login token is persisted in schema.sql's login_tokens table
  (hashedToken, userId, createdAt, expiresAt) instead of RAM + flat files, matching
  docs/contract.md's auth flow. HashText below is omi's FNV-1a (pure Pascal, no crypto lib so
  it builds on 68k); swap in SHA-256 where a backend is linked.

  v0.1 reference skeleton.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils,Classes,HTTPDefs,DateUtils,fpjson,jsonparser,wldb,wlpasswd;

type
  TWLSession = record
    TenantDb   : string;     // exact database binding; copied user IDs never cross tenants
    SessionId  : string;
    UserId     : string;
    Username   : string;
    PasswordRef: string;     // a stable per-credential marker (e.g. hash of the stored hash)
    Ip         : string;
    UserAgent  : string;
    LoginAt    : Int64;      // unix seconds
    LastSeenAt : Int64;
    Counter    : Int64;      // monotonically increasing per accepted action
  end;

// --- request helpers (cookie-free) --------------------------------------------------------
function SessionIdFromRequest(ARequest: TRequest): string;
function ClientIp(ARequest: TRequest): string;
function RequestUserAgent(ARequest: TRequest): string;

// Append ?sessionId=.. (or &sessionId=..) to a link target, since we cannot rely on cookies.
function WithSessionId(const TargetPath, SessionId: string): string;

// --- token machinery ----------------------------------------------------------------------
function HashText(const Value: string): string;                       // FNV-1a, omi-compatible
function ActionHash(const S: TWLSession; const ActionName: string): string;

// Hidden fields to embed in every POST form: sessionId + action + counter + auth_hash.
function AuthHiddenFields(const S: TWLSession; const ActionName: string): string;

// Verify the action token; mutating operations consume it by default. Read-only downloads
// may opt out of consumption so the still-visible no-JS form remains usable afterward.
function VerifyActionToken(ARequest: TRequest; var S: TWLSession;
  const RequiredAction:string; Consume:Boolean=True):Boolean;

// --- session lifecycle against schema.sql.login_tokens ------------------------------------
// Create a login token row (hashedToken, userId, createdAt, expiresAt) and return the session.
function CreateSession(Db: TWLDb; ARequest: TRequest;
  const UserId, Username, PasswordRef: string; TtlSeconds: Int64): TWLSession;
// Validate the bearer/session token: indexed lookup on login_tokens.hashedToken + checks.
function ValidateSession(Db: TWLDb; ARequest: TRequest;
  const SessionId: string; out S: TWLSession): Boolean;

implementation

// In-memory session context (IP/UA/counter). The durable token lives in login_tokens; this
// holds the volatile per-session metadata the omi scheme binds into the action-token.
var
  SessionLock:TRTLCriticalSection;
  SessionMeta: TStringList = nil;   // sessionId -> packed TWLSession fields

function SessionIdFromRequest(ARequest: TRequest): string;
begin
  Result := Trim(ARequest.ContentFields.Values['sessionId']);
  if Result = '' then
    Result := Trim(ARequest.QueryFields.Values['sessionId']);
end;

function ClientIp(ARequest: TRequest): string;
begin
  Result := Trim(ARequest.CustomHeaders.Values['X-Forwarded-For']);
  if Result = '' then Result := Trim(ARequest.RemoteAddress);
  if Result = '' then Result := '0.0.0.0';
end;

function RequestUserAgent(ARequest: TRequest): string;
begin
  Result := Trim(ARequest.UserAgent);
  if Result = '' then
    Result := Trim(ARequest.CustomHeaders.Values['User-Agent']);
end;

function WithSessionId(const TargetPath, SessionId: string): string;
begin
  Result := TargetPath;
  if Trim(SessionId) = '' then Exit;
  if Pos('sessionId=', Result) > 0 then Exit;
  if Pos('?', Result) > 0 then
    Result := Result + '&sessionId=' + SessionId
  else
    Result := Result + '?sessionId=' + SessionId;
end;

function HashText(const Value: string): string;
var
  i: Integer;
  H: QWord;
begin
  H := QWord(1469598103934665603);          // FNV offset basis
  for i := 1 to Length(Value) do
  begin
    H := H xor Ord(Value[i]);
    H := H * QWord(1099511628211);           // FNV prime
  end;
  Result := IntToHex(H, 16);
end;

function ActionHash(const S: TWLSession; const ActionName: string): string;
begin
  Result := HashText(ActionName + '|' + S.Username + '|' + S.PasswordRef + '|' +
    S.Ip + '|' + S.UserAgent + '|' + IntToStr(S.LoginAt) + '|' +
    IntToStr(S.Counter) + '|' + S.SessionId);
end;

function HtmlAttr(const V: string): string;
begin
  Result := StringReplace(V, '"', '&quot;', [rfReplaceAll]);
end;

function AuthHiddenFields(const S: TWLSession; const ActionName: string): string;
begin
  if (S.SessionId = '') or (S.Username = '') then
    Exit('');
  Result :=
    '<input type="hidden" name="sessionId"    value="' + HtmlAttr(S.SessionId) + '">' +
    '<input type="hidden" name="auth_action"  value="' + HtmlAttr(ActionName) + '">' +
    '<input type="hidden" name="auth_counter" value="' + IntToStr(S.Counter) + '">' +
    '<input type="hidden" name="auth_hash"    value="' + HtmlAttr(ActionHash(S, ActionName)) + '">';
end;

// These helpers run under SessionLock. JSON preserves arbitrary user-agent/username
// bytes without delimiter injection into another session field.
procedure PackMeta(const S:TWLSession);
var O:TJSONObject;
begin
  O:=TJSONObject.Create;
  try
    O.Add('tenantDb',S.TenantDb); O.Add('userId',S.UserId); O.Add('username',S.Username);
    O.Add('passwordRef',S.PasswordRef); O.Add('ip',S.Ip); O.Add('userAgent',S.UserAgent);
    O.Add('loginAt',S.LoginAt); O.Add('lastSeenAt',S.LastSeenAt); O.Add('counter',S.Counter);
    SessionMeta.Values[S.SessionId]:=O.AsJSON;
  finally O.Free; end;
end;
function UnpackMeta(const SessionId:string; out S:TWLSession):Boolean;
var D:TJSONData; O:TJSONObject; Raw:string;
begin
  Result:=False; S:=Default(TWLSession); D:=nil;
  Raw:=SessionMeta.Values[SessionId]; if Raw='' then Exit;
  try
    try
      D:=GetJSON(Raw); if not (D is TJSONObject) then Exit;
      O:=TJSONObject(D); S.SessionId:=SessionId; S.TenantDb:=O.Get('tenantDb','');
      S.UserId:=O.Get('userId',''); S.Username:=O.Get('username','');
      S.PasswordRef:=O.Get('passwordRef',''); S.Ip:=O.Get('ip',''); S.UserAgent:=O.Get('userAgent','');
      S.LoginAt:=O.Get('loginAt',Int64(0)); S.LastSeenAt:=O.Get('lastSeenAt',Int64(0)); S.Counter:=O.Get('counter',Int64(0));
      Result:=(S.UserId<>'') and (S.TenantDb<>'');
    except S:=Default(TWLSession); end;
  finally D.Free; end;
end;

function VerifyActionToken(ARequest:TRequest; var S:TWLSession;
  const RequiredAction:string; Consume:Boolean):Boolean;
var PostedAction,PostedHash:string; PostedCounter:Int64; Current:TWLSession;
begin
  Result:=False;
  PostedAction:=Trim(ARequest.ContentFields.Values['auth_action']);
  PostedHash:=Trim(ARequest.ContentFields.Values['auth_hash']);
  PostedCounter:=StrToInt64Def(ARequest.ContentFields.Values['auth_counter'],-1);
  if PostedAction='' then PostedAction:=Trim(ARequest.CustomHeaders.Values['X-Welite-Action']);
  if PostedHash='' then PostedHash:=Trim(ARequest.CustomHeaders.Values['X-Welite-Hash']);
  if PostedCounter<0 then PostedCounter:=StrToInt64Def(ARequest.CustomHeaders.Values['X-Welite-Counter'],-1);
  if (S.UserId='') or (PostedAction='') or (PostedHash='') then Exit;
  EnterCriticalSection(SessionLock);
  try
    if not UnpackMeta(S.SessionId,Current) then Exit;
    if (Current.UserId<>S.UserId) or (Current.TenantDb<>S.TenantDb) then Exit;
    if not SameText(PostedAction,RequiredAction) or (PostedCounter<>Current.Counter) then Exit;
    if (Current.Ip<>ClientIp(ARequest)) or (Current.UserAgent<>RequestUserAgent(ARequest)) then Exit;
    if not SameText(ActionHash(Current,RequiredAction),PostedHash) then Exit;
    if Consume then
    begin
      Inc(Current.Counter); Current.LastSeenAt:=DateTimeToUnix(Now,False); PackMeta(Current);
    end;
    S:=Current; Result:=True;
  finally LeaveCriticalSection(SessionLock); end;
end;

function CreateSession(Db: TWLDb; ARequest: TRequest;
  const UserId, Username, PasswordRef: string; TtlSeconds: Int64): TWLSession;
var
  NowTs: Int64;
  Hashed: string;
begin
  NowTs:=DateTimeToUnix(Now,False);
  FillChar(Result, SizeOf(Result), 0);
  // A fresh token prevents login collisions and reuse after disable/re-enable.
  Result.SessionId:=NewAuthToken;
  Result.TenantDb:=ExpandFileName(Db.Path);
  Result.UserId      := UserId;
  Result.Username    := Username;
  Result.PasswordRef := PasswordRef;
  Result.Ip          := ClientIp(ARequest);
  Result.UserAgent   := RequestUserAgent(ARequest);
  Result.LoginAt     := NowTs;
  Result.LastSeenAt  := NowTs;
  Result.Counter     := 0;


  // persist the bearer token (schema.sql: login_tokens). hashedToken = hash of the session id.
  Hashed := HashText(Result.SessionId);
  if not Db.Exec(Format(
    'INSERT INTO login_tokens(hashedToken,userId,createdAt,expiresAt) ' +
    'VALUES(%s,%s,%s,%s);',
    [ QuotedStr(Hashed), QuotedStr(UserId),
      QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(Now))),
      QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',IncSecond(LocalTimeToUniversal(Now),TtlSeconds))) ])) then
  begin Result:=Default(TWLSession); Exit; end;
  EnterCriticalSection(SessionLock);
  try PackMeta(Result); finally LeaveCriticalSection(SessionLock); end;
end;

function ValidateSession(Db:TWLDb; ARequest:TRequest; const SessionId:string; out S:TWLSession):Boolean;
var Rows:TWLRows; Current:TWLSession; NowTs,IdleSeconds:Int64;
begin
  Result:=False; S:=Default(TWLSession);
  EnterCriticalSection(SessionLock);
  try
    if not UnpackMeta(SessionId,Current) then Exit;
    if Current.TenantDb<>ExpandFileName(Db.Path) then Exit;
    Rows:=Db.Query('SELECT u.id,u.username,COALESCE(json_extract(u.services_json,''$.password''),'''') '+
      'FROM login_tokens t JOIN users u ON u.id=t.userId WHERE t.hashedToken='+QuotedStr(HashText(SessionId))+
      ' AND COALESCE(u.loginDisabled,0)=0 AND (t.expiresAt IS NULL OR t.expiresAt>'+
      QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(Now)))+') LIMIT 1;');
    if (Length(Rows)=0) or (Rows[0][0]<>Current.UserId) or (Rows[0][1]<>Current.Username) or
      (HashText(Rows[0][2])<>Current.PasswordRef) then Exit;
    if (Current.Ip<>ClientIp(ARequest)) or (Current.UserAgent<>RequestUserAgent(ARequest)) then Exit;
    NowTs:=DateTimeToUnix(Now,False);
    IdleSeconds:=StrToInt64Def(GetEnvironmentVariable('WELITE_SESSION_IDLE'),1800);
    if IdleSeconds<1 then IdleSeconds:=1800;
    if (NowTs<Current.LastSeenAt) or (NowTs-Current.LastSeenAt>IdleSeconds) then
    begin
      Db.Exec('DELETE FROM login_tokens WHERE hashedToken='+QuotedStr(HashText(SessionId))+';');
      SessionMeta.Delete(SessionMeta.IndexOfName(SessionId)); Exit;
    end;
    Current.LastSeenAt:=NowTs; PackMeta(Current); S:=Current; Result:=True;
  finally LeaveCriticalSection(SessionLock); end;
end;

initialization
  InitCriticalSection(SessionLock);
  SessionMeta := TStringList.Create;
  SessionMeta.CaseSensitive := True;

finalization
  SessionMeta.Free;
  DoneCriticalSection(SessionLock);

end.
