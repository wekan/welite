unit wlauth;

{
  WeKan-Lite — no-cookie / no-JS authentication (docs/goals.md G4)

  Distilled from https://github.com/wekan/omi/blob/main/public/server.pas, which already solves "auth for IBrowse / NetSurf /
  Dillo / Lynx": the session id rides in the URL and in hidden <form> fields (never a required
  cookie), and every state-changing POST carries an action-token bound to the session.

  Sessions use an independent server-only HMAC-SHA-256 key and a canonical JSON context
  containing tenant, identity, client and counter. Token lookup uses a tenant-scoped SHA-256
  digest. Supplemental authmeta rows bind durable tokens to the current credential hash
  and distinguish API credentials from web sessions. Web tokens retain client/idle checks
  when used with API routes. No legacy FNV token fallback is accepted.

  v0.1 reference skeleton.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils,Classes,HTTPDefs,DateUtils,fpjson,jsonparser,wldb,wlpasswd,wlcrypt,wlpolicy,wlreplay,wltotp,wlautsrc,wlrevoke,wlshared,Sockets;

type
  TWLLoginProof=class
  private
    FUserId,FUsername,FCredentialRef,FTokenRef,FMethod,FServices,FAdmin,FFactorKey,FCode,FSource:string;
    FCounter,FAt:Int64;
    FVerified:Boolean;
    constructor Create;
  public
    destructor Destroy;override;
    property UserId:string read FUserId;
    property Username:string read FUsername;
    property TokenReference:string read FTokenRef;
  end;
  TWLSession = record
    TenantDb   : string;     // exact database binding; copied user IDs never cross tenants
    ActionKey  : string;     // independent, server-only HMAC secret
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
function ApiTokenLifetime(Db:TWLDb):Int64;
function HashText(const Value:string):string; // SHA-256, lowercase hex
function ActionHash(const S: TWLSession; const ActionName: string): string;

// Hidden fields to embed in every POST form: sessionId + action + counter + auth_hash.
function AuthHiddenFields(const S: TWLSession; const ActionName: string): string;

// Verify the action token; mutating operations consume it by default. Read-only downloads
// may opt out of consumption so the still-visible no-JS form remains usable afterward.
function VerifyActionToken(ARequest: TRequest; var S: TWLSession;
  const RequiredAction:string; Consume:Boolean=True):Boolean;

function AuthenticateAccount(Db:TWLDb;const Username,Password,Code:string;out Proof:TWLLoginProof):Boolean;
function IssueAccountToken(Db:TWLDb;Proof:TWLLoginProof;const Token,Kind:string;TtlSeconds:Int64):Boolean;
function CreateAuthenticatedSession(Db:TWLDb;Request:TRequest;Proof:TWLLoginProof;TtlSeconds:Int64):TWLSession;
function LoginAccount(Db:TWLDb;const Username:string):TWLRows;
function TokenHash(Db:TWLDb; const Token:string):string;
function IssueLoginToken(Db:TWLDb; const UserId,Token,CredentialRef,Kind:string; TtlSeconds:Int64):Boolean;
function ValidateLoginToken(Db:TWLDb; Request:TRequest; const Token:string; out UserId:string):Boolean;

// --- session lifecycle against schema.sql.login_tokens ------------------------------------
// Create a login token row (hashedToken, userId, createdAt, expiresAt) and return the session.
function CreateSession(Db: TWLDb; ARequest: TRequest;
  const UserId, Username, PasswordRef: string; TtlSeconds: Int64): TWLSession;
// Validate the bearer/session token: indexed lookup on login_tokens.hashedToken + checks.
function ValidateSession(Db: TWLDb; ARequest: TRequest;
  const SessionId: string; out S: TWLSession): Boolean;

implementation

constructor TWLLoginProof.Create;
begin inherited Create;FCounter:=-1;end;
destructor TWLLoginProof.Destroy;
begin
  if FCode<>'' then begin UniqueString(FCode);FillChar(FCode[1],Length(FCode),0);end;
  if FServices<>'' then begin UniqueString(FServices);FillChar(FServices[1],Length(FServices),0);end;
  inherited Destroy;
end;
function AccountRows(Db:TWLDb;const Username:string):TWLRows;
begin
  Result:=nil;if not AuthSourceCurrent(Db) then Exit;
  Result:=Db.Query('SELECT id,COALESCE(json_extract(services_json,''$.password''),''''),COALESCE(loginDisabled,0),COALESCE(authenticationMethod,''password''),services_json,COALESCE(isAdmin,0),username '+
    'FROM users WHERE username='+QuotedStr(Username)+' COLLATE BINARY LIMIT 2;');
  if Length(Result)<>1 then begin Result:=nil;Exit;end;
  if Result[0][2]<>'0' then Result:=nil;
end;
function LoginAccount(Db:TWLDb;const Username:string):TWLRows;
begin
  Result:=AccountRows(Db,Username);
  if (Length(Result)=1) and not PasswordOnlyAllowed(Result[0][3],Result[0][4],Result[0][5]='1') then Result:=nil;
end;
function FactorReference(const Base,Key:string):string;
begin Result:=Sha256Hex('welite-otp-session-v1'+#0+Base+#0+Key);end;
function AccountMatches(const Method,Services,Password,Reference:string;IsAdmin:Boolean):Boolean;
var Secret,Base,Expected:string;Policy:TFactorPolicy;
begin
  Result:=False;Secret:='';
  try
    try
      Policy:=FactorPolicy(Method,Services,IsAdmin,Secret);
      if Policy=fpNone then Exit(CredentialMatches(Password,Reference));
      if Policy<>fpOTP then Exit;
      Base:=CredentialFingerprint(Password);if Base='' then Exit;
      Expected:=FactorReference(Base,OTPFactorKey(Secret));
      Result:=ConstantEqual(Expected,Reference);
    except Result:=False;end;
  finally if Secret<>'' then begin UniqueString(Secret);FillChar(Secret[1],Length(Secret),0);end;end;
end;
function AuthenticateAccount(Db:TWLDb;const Username,Password,Code:string;out Proof:TWLLoginProof):Boolean;
var Rows:TWLRows;Secret:string;Policy:TFactorPolicy;Pending:TWLLoginProof;Last:Int64;
begin
  Result:=False;Proof:=nil;Pending:=nil;Secret:='';
  try
    try
      Rows:=AccountRows(Db,Username);if Length(Rows)<>1 then Exit;
      Policy:=FactorPolicy(Rows[0][3],Rows[0][4],Rows[0][5]='1',Secret);
      if not (Policy in [fpNone,fpOTP]) then Exit;
      Pending:=TWLLoginProof.Create;Pending.FSource:=AuthSourceCondition(Db);
      if not VerifyCredential(Password,Rows[0][1],Pending.FCredentialRef) then Exit;
      Pending.FUserId:=Rows[0][0];Pending.FUsername:=Rows[0][6];Pending.FMethod:=Rows[0][3];Pending.FServices:=Rows[0][4];Pending.FAdmin:=Rows[0][5];
      Pending.FAt:=DateTimeToUnix(Now,False);Pending.FTokenRef:=Pending.FCredentialRef;
      if Policy=fpOTP then
      begin
        if not EnsureOTPReplay(Db) then Exit;
        Pending.FFactorKey:=OTPFactorKey(Secret);
        if not LastOTPCounter(Db,Pending.FUserId,Pending.FFactorKey,Last) then Exit;
        if not OTPMatch(Secret,Code,Pending.FAt,10,Last,Pending.FCounter) then Exit;
        Pending.FCode:=Code;Pending.FTokenRef:=FactorReference(Pending.FCredentialRef,Pending.FFactorKey);
      end;
      Pending.FVerified:=True;Proof:=Pending;Pending:=nil;Result:=True;
    except Result:=False;end;
  finally Pending.Free;if Secret<>'' then begin UniqueString(Secret);FillChar(Secret[1],Length(Secret),0);end;end;
end;

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

function NormalIp(const Value:string):string;
var V:string; V4:in_addr; V6:in6_addr;
begin
  V:=Trim(Value); Result:='';
  if (Copy(V,1,1)='[') and (Copy(V,Length(V),1)=']') then V:=Copy(V,2,Length(V)-2);
  if TryStrToHostAddr(V,V4) then Exit(HostAddrToStr(V4));
  if TryStrToHostAddr6(V,V6) then Result:=LowerCase(HostAddrToStr6(V6));
end;
function ClientIp(ARequest:TRequest):string;
var Trusted,Hops:TStringArray; Peer,Header,Hop:string; i:Integer;
  function TrustedIp(const Value:string):Boolean;
  var n:Integer;
  begin
    Result:=False;
    for n:=0 to High(Trusted) do if (NormalIp(Trusted[n])<>'') and (NormalIp(Trusted[n])=Value) then Exit(True);
  end;
begin
  Peer:=NormalIp(ARequest.RemoteAddress); if Peer='' then Peer:='0.0.0.0';
  Result:=Peer; Trusted:=GetEnvironmentVariable('WELITE_TRUSTED_PROXIES').Split([',']);
  if not TrustedIp(Peer) then Exit;
  Header:=Trim(ARequest.CustomHeaders.Values['X-Forwarded-For']); if Header='' then Exit;
  Hops:=Header.Split([',']);
  // Walk from the nearest hop. Untrusted callers cannot choose the effective client by
  // prepending an address to a chain that a real proxy appended to.
  for i:=High(Hops) downto 0 do
  begin
    if not TrustedIp(Result) then Break;
    Hop:=NormalIp(Hops[i]);
    if Hop='' then Exit(Peer);
    Result:=Hop;
  end;
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

function HashText(const Value:string):string;
begin Result:=Sha256Hex(Value); end;
function ApiTokenLifetime(Db:TWLDb):Int64;
begin Result:=wlshared.ApiTokenLifetime(Db);end;
function TokenHash(Db:TWLDb; const Token:string):string;
begin
  Result:=TenantTokenHash(Db.Path,Token);
end;
function ActionHash(const S:TWLSession; const ActionName:string):string;
var Context:TJSONArray;
begin
  Context:=TJSONArray.Create;
  try
    Context.Add('welite-action-v2'); Context.Add(ActionName); Context.Add(S.TenantDb);
    Context.Add(S.UserId); Context.Add(S.Username); Context.Add(S.PasswordRef);
    Context.Add(S.Ip); Context.Add(S.UserAgent); Context.Add(S.LoginAt); Context.Add(S.Counter); Context.Add(S.SessionId);
    Result:=Hmac256Hex(S.ActionKey,Context.AsJSON);
  finally Context.Free; end;
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
    O.Add('actionKey',S.ActionKey); O.Add('tenantDb',S.TenantDb); O.Add('userId',S.UserId); O.Add('username',S.Username);
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
      O:=TJSONObject(D); S.ActionKey:=O.Get('actionKey',''); S.SessionId:=SessionId; S.TenantDb:=O.Get('tenantDb','');
      S.UserId:=O.Get('userId',''); S.Username:=O.Get('username','');
      S.PasswordRef:=O.Get('passwordRef',''); S.Ip:=O.Get('ip',''); S.UserAgent:=O.Get('userAgent','');
      S.LoginAt:=O.Get('loginAt',Int64(0)); S.LastSeenAt:=O.Get('lastSeenAt',Int64(0)); S.Counter:=O.Get('counter',Int64(0));
      Result:=(S.UserId<>'') and (S.TenantDb<>'') and (S.ActionKey<>'');
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
    if not ConstantEqual(ActionHash(Current,RequiredAction),LowerCase(PostedHash)) then Exit;
    if Consume then
    begin
      Inc(Current.Counter); Current.LastSeenAt:=DateTimeToUnix(Now,False); PackMeta(Current);
    end;
    S:=Current; Result:=True;
  finally LeaveCriticalSection(SessionLock); end;
end;

function IssueLoginToken(Db:TWLDb; const UserId,Token,CredentialRef,Kind:string; TtlSeconds:Int64):Boolean;
const Schema='CREATE TABLE IF NOT EXISTS authmeta ('+
  'hashedToken TEXT PRIMARY KEY REFERENCES login_tokens(hashedToken) ON DELETE CASCADE,'+
  'tenantKey TEXT NOT NULL,credentialRef TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN (''web'',''api'')));';
var Rows:TWLRows; Key,TenantKey,NowIso,Expires,SharedSql:string;At:TDateTime;
begin
  Result:=False;
  if not AuthSourceCurrent(Db) then Exit;
  if (Token='') or ((Kind<>'web') and (Kind<>'api')) or (TtlSeconds<1) then Exit;
  if (Kind='api') and SharedStore(Db) and (TtlSeconds<>ApiTokenLifetime(Db)) then Exit;
  Rows:=Db.Query('SELECT COALESCE(json_extract(services_json,''$.password''),''''),COALESCE(authenticationMethod,''password''),services_json,COALESCE(isAdmin,0) FROM users '+
    'WHERE id='+QuotedStr(UserId)+' AND COALESCE(loginDisabled,0)=0;');
  if (Length(Rows)=0) or not PasswordOnlyAllowed(Rows[0][1],Rows[0][2],Rows[0][3]='1') or not CredentialMatches(Rows[0][0],CredentialRef) then Exit;
  Key:=TokenHash(Db,Token); TenantKey:=HashText(ExpandFileName(Db.Path));
  At:=Now;NowIso:=FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(At));
  Expires:=FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',IncSecond(LocalTimeToUniversal(At),TtlSeconds));
  SharedSql:='';if Kind='api' then SharedSql:=SharedIssueSQL(Db,UserId,Token,Key,UnixMillis(At));
  if not Db.Exec(Schema) then Exit;
  if not Db.Exec('BEGIN IMMEDIATE; INSERT INTO login_tokens(hashedToken,userId,createdAt,expiresAt) '+
    'SELECT '+QuotedStr(Key)+',id,'+QuotedStr(NowIso)+','+QuotedStr(Expires)+' FROM users WHERE id='+QuotedStr(UserId)+
    ' AND COALESCE(loginDisabled,0)=0 AND COALESCE(json_extract(services_json,''$.password''),'''')='+QuotedStr(Rows[0][0])+
    ' AND COALESCE(authenticationMethod,''password'')='+QuotedStr(Rows[0][1])+' AND services_json='+QuotedStr(Rows[0][2])+' AND CAST(COALESCE(isAdmin,0) AS TEXT)='+QuotedStr(Rows[0][3])+' AND ('+AuthSourceCondition(Db)+'); '+
    'INSERT INTO authmeta(hashedToken,tenantKey,credentialRef,kind) SELECT hashedToken,'+QuotedStr(TenantKey)+','+
    QuotedStr(CredentialRef)+','+QuotedStr(Kind)+' FROM login_tokens WHERE hashedToken='+QuotedStr(Key)+'; '+SharedSql+'COMMIT;') then
  begin Db.Exec('ROLLBACK;'); Exit; end;
  Result:=Length(Db.Query('SELECT hashedToken FROM authmeta WHERE hashedToken='+QuotedStr(Key)+';'))=1;
end;

function IssueAccountToken(Db:TWLDb;Proof:TWLLoginProof;const Token,Kind:string;TtlSeconds:Int64):Boolean;
var Rows:TWLRows;Secret,Key,Sql,NowIso,Expires:string;Policy:TFactorPolicy;Last,Matched,NowAt:Int64;At:TDateTime;
begin
  Result:=False;Secret:='';
  if (Proof=nil) or not Proof.FVerified or (Token='') or ((Kind<>'web') and (Kind<>'api')) or (TtlSeconds<1) then Exit;
  try
    try
      NowAt:=DateTimeToUnix(Now,False);if (Proof.FSource<>AuthSourceCondition(Db)) or (NowAt<Proof.FAt) or (NowAt-Proof.FAt>30) then Exit;
      Rows:=AccountRows(Db,Proof.FUsername);
      if (Length(Rows)<>1) or (Rows[0][0]<>Proof.FUserId) or (Rows[0][3]<>Proof.FMethod) or
        (Rows[0][4]<>Proof.FServices) or (Rows[0][5]<>Proof.FAdmin) or not CredentialMatches(Rows[0][1],Proof.FCredentialRef) then Exit;
      Policy:=FactorPolicy(Rows[0][3],Rows[0][4],Rows[0][5]='1',Secret);
      if Policy=fpNone then
      begin
        if (Proof.FFactorKey<>'') or (Proof.FCounter<> -1) then Exit;
        Result:=IssueLoginToken(Db,Proof.FUserId,Token,Proof.FCredentialRef,Kind,TtlSeconds);
        if Result then Proof.FVerified:=False;Exit;
      end;
      if (Policy<>fpOTP) or (OTPFactorKey(Secret)<>Proof.FFactorKey) or not EnsureOTPReplay(Db) then Exit;
      if not LastOTPCounter(Db,Proof.FUserId,Proof.FFactorKey,Last) then Exit;
      if not OTPMatch(Secret,Proof.FCode,NowAt,10,Last,Matched) or (Matched<>Proof.FCounter) then Exit;
      if (Kind='api') and SharedStore(Db) and (TtlSeconds<>ApiTokenLifetime(Db)) then Exit;
      Key:=TokenHash(Db,Token);At:=Now;
      NowIso:=FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(At));
      Expires:=FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',IncSecond(LocalTimeToUniversal(At),TtlSeconds));
      if not Db.Exec('CREATE TABLE IF NOT EXISTS authmeta(hashedToken TEXT PRIMARY KEY REFERENCES login_tokens(hashedToken) ON DELETE CASCADE,tenantKey TEXT NOT NULL,credentialRef TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN (''web'',''api'')));') then Exit;
      Sql:='BEGIN IMMEDIATE; INSERT INTO login_tokens(hashedToken,userId,createdAt,expiresAt) SELECT '+QuotedStr(Key)+',id,'+QuotedStr(NowIso)+','+QuotedStr(Expires)+
        ' FROM users WHERE id='+QuotedStr(Proof.FUserId)+' AND username='+QuotedStr(Proof.FUsername)+' AND COALESCE(loginDisabled,0)=0 '+
        'AND services_json='+QuotedStr(Proof.FServices)+' AND COALESCE(authenticationMethod,''password'')='+QuotedStr(Proof.FMethod)+
        ' AND CAST(COALESCE(isAdmin,0) AS TEXT)='+QuotedStr(Proof.FAdmin)+' AND ('+Proof.FSource+'); '+
        'INSERT INTO authmeta(hashedToken,tenantKey,credentialRef,kind) SELECT hashedToken,'+QuotedStr(HashText(ExpandFileName(Db.Path)))+','+QuotedStr(Proof.FTokenRef)+','+QuotedStr(Kind)+
        ' FROM login_tokens WHERE hashedToken='+QuotedStr(Key)+'; '+OTPReplaySQL(Proof.FUserId,Proof.FFactorKey,Key,Proof.FCounter);
      if Kind='api' then Sql:=Sql+SharedIssueSQL(Db,Proof.FUserId,Token,Key,UnixMillis(At));
      Sql:=Sql+'COMMIT;';
      if not Db.Exec(Sql) then begin Db.Exec('ROLLBACK;');Exit;end;
      Result:=Length(Db.Query('SELECT hashedToken FROM authmeta WHERE hashedToken='+QuotedStr(Key)+';'))=1;
      if Result then Proof.FVerified:=False;
    except Result:=False;end;
  finally if Secret<>'' then begin UniqueString(Secret);FillChar(Secret[1],Length(Secret),0);end;end;
end;
function CreateAuthenticatedSession(Db:TWLDb;Request:TRequest;Proof:TWLLoginProof;TtlSeconds:Int64):TWLSession;
begin
  Result:=Default(TWLSession);if (Proof=nil) or not Proof.FVerified then Exit;
  Result.SessionId:=NewAuthToken;Result.ActionKey:=NewAuthToken;Result.TenantDb:=ExpandFileName(Db.Path);
  Result.UserId:=Proof.FUserId;Result.Username:=Proof.FUsername;Result.PasswordRef:=Proof.FTokenRef;
  Result.Ip:=ClientIp(Request);Result.UserAgent:=RequestUserAgent(Request);
  Result.LoginAt:=DateTimeToUnix(Now,False);Result.LastSeenAt:=Result.LoginAt;Result.Counter:=0;
  if not IssueAccountToken(Db,Proof,Result.SessionId,'web',TtlSeconds) then begin Result:=Default(TWLSession);Exit;end;
  EnterCriticalSection(SessionLock);try PackMeta(Result);finally LeaveCriticalSection(SessionLock);end;
end;


function CreateSession(Db: TWLDb; ARequest: TRequest;
  const UserId, Username, PasswordRef: string; TtlSeconds: Int64): TWLSession;
var
  NowTs: Int64;
begin
  NowTs:=DateTimeToUnix(Now,False);
  FillChar(Result, SizeOf(Result), 0);
  // A fresh token prevents login collisions and reuse after disable/re-enable.
  Result.SessionId:=NewAuthToken; Result.ActionKey:=NewAuthToken;
  Result.TenantDb:=ExpandFileName(Db.Path);
  Result.UserId      := UserId;
  Result.Username    := Username;
  Result.PasswordRef := PasswordRef;
  Result.Ip          := ClientIp(ARequest);
  Result.UserAgent   := RequestUserAgent(ARequest);
  Result.LoginAt     := NowTs;
  Result.LastSeenAt  := NowTs;
  Result.Counter     := 0;


  if not IssueLoginToken(Db,UserId,Result.SessionId,PasswordRef,'web',TtlSeconds) then
  begin Result:=Default(TWLSession); Exit; end;
  EnterCriticalSection(SessionLock);
  try PackMeta(Result); finally LeaveCriticalSection(SessionLock); end;
end;

function RevokeStoredToken(Db:TWLDb;const Token:string):Boolean;
var Rows:TWLRows;Key,Sql:string;
begin
  Result:=False;Key:=TokenHash(Db,Token);
  try
    Rows:=Db.Query('SELECT userId FROM login_tokens WHERE hashedToken='+QuotedStr(Key)+';');
    if Length(Rows)=0 then Exit(True);
    if Length(Rows)<>1 then Exit;
    if AuthSourceCurrent(Db) then Sql:=RevokeTokenSQL(Db,Rows[0][0],Token)
    else Sql:='DELETE FROM authmeta WHERE hashedToken='+QuotedStr(Key)+'; DELETE FROM login_tokens WHERE hashedToken='+QuotedStr(Key)+';';
    Result:=Db.Exec('BEGIN IMMEDIATE; '+Sql+'COMMIT;');
    if not Result then Db.Exec('ROLLBACK;');
  except Db.Exec('ROLLBACK;');Result:=False;end;
end;

function ValidateSession(Db:TWLDb; ARequest:TRequest; const SessionId:string; out S:TWLSession):Boolean;
var Rows:TWLRows; Current:TWLSession; NowTs,IdleSeconds:Int64;
begin
  Result:=False; S:=Default(TWLSession);
  EnterCriticalSection(SessionLock);
  try
    if not UnpackMeta(SessionId,Current) then Exit;
    if Current.TenantDb<>ExpandFileName(Db.Path) then Exit;
    if not AuthSourceCurrent(Db) then
    begin
      RevokeStoredToken(Db,SessionId);
      SessionMeta.Delete(SessionMeta.IndexOfName(SessionId));Exit;
    end;
    Rows:=Db.Query('SELECT u.id,u.username,COALESCE(json_extract(u.services_json,''$.password''),''''),'+
      'COALESCE(u.authenticationMethod,''password''),u.services_json,COALESCE(u.isAdmin,0) '+
      'FROM login_tokens t JOIN users u ON u.id=t.userId JOIN authmeta m ON m.hashedToken=t.hashedToken '+
      'WHERE ('+AuthSourceCondition(Db)+') AND m.kind=''web'' AND m.tenantKey='+QuotedStr(HashText(ExpandFileName(Db.Path)))+
      ' AND m.credentialRef='+QuotedStr(Current.PasswordRef)+' AND t.hashedToken='+QuotedStr(TokenHash(Db,SessionId))+
      ' AND COALESCE(u.loginDisabled,0)=0 AND (t.expiresAt IS NULL OR t.expiresAt>'+
      QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(Now)))+') LIMIT 1;');
    if (Length(Rows)=0) or (Rows[0][0]<>Current.UserId) or (Rows[0][1]<>Current.Username) then
    begin RevokeStoredToken(Db,SessionId);SessionMeta.Delete(SessionMeta.IndexOfName(SessionId));Exit;end;
    if not AccountMatches(Rows[0][3],Rows[0][4],Rows[0][2],Current.PasswordRef,Rows[0][5]='1') then
    begin
      RevokeStoredToken(Db,SessionId);
      SessionMeta.Delete(SessionMeta.IndexOfName(SessionId));Exit;
    end;
    if (Current.Ip<>ClientIp(ARequest)) or (Current.UserAgent<>RequestUserAgent(ARequest)) then Exit;
    NowTs:=DateTimeToUnix(Now,False);
    IdleSeconds:=StrToInt64Def(GetEnvironmentVariable('WELITE_SESSION_IDLE'),1800);
    if IdleSeconds<1 then IdleSeconds:=1800;
    if (NowTs<Current.LastSeenAt) or (NowTs-Current.LastSeenAt>IdleSeconds) then
    begin
      RevokeStoredToken(Db,SessionId);
      SessionMeta.Delete(SessionMeta.IndexOfName(SessionId)); Exit;
    end;
    Current.LastSeenAt:=NowTs; PackMeta(Current); S:=Current; Result:=True;
  finally LeaveCriticalSection(SessionLock); end;
end;

function ValidateLoginToken(Db:TWLDb; Request:TRequest; const Token:string; out UserId:string):Boolean;
var Rows:TWLRows; S:TWLSession; Key:string;
begin
  Result:=False; UserId:=''; if Token='' then Exit;
  Key:=TokenHash(Db,Token);
  if not AuthSourceCurrent(Db) then
  begin RevokeStoredToken(Db,Token);Exit;end;
  Rows:=Db.Query('SELECT t.userId,COALESCE(json_extract(u.services_json,''$.password''),''''),'+
    'm.credentialRef,m.kind,COALESCE(u.authenticationMethod,''password''),u.services_json,COALESCE(u.isAdmin,0) FROM login_tokens t JOIN users u ON u.id=t.userId '+
    'JOIN authmeta m ON m.hashedToken=t.hashedToken WHERE ('+AuthSourceCondition(Db)+') AND t.hashedToken='+QuotedStr(Key)+
    ' AND m.tenantKey='+QuotedStr(HashText(ExpandFileName(Db.Path)))+
    ' AND COALESCE(u.loginDisabled,0)=0 AND (t.expiresAt IS NULL OR t.expiresAt>'+
    QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(Now)))+') LIMIT 1;');
  if Length(Rows)=0 then begin RevokeStoredToken(Db,Token);Exit;end;
  if not AccountMatches(Rows[0][4],Rows[0][5],Rows[0][1],Rows[0][2],Rows[0][6]='1') then
  begin RevokeStoredToken(Db,Token); Exit; end;
  if Rows[0][3]='web' then
  begin
    if not ValidateSession(Db,Request,Token,S) then Exit;
    UserId:=S.UserId; Exit(True);
  end;
  if Rows[0][3]<>'api' then Exit;
  if not SharedBearerValid(Db,Rows[0][0],Token) then begin RevokeStoredToken(Db,Token);Exit;end;
  UserId:=Rows[0][0]; Result:=True;
end;

initialization
  InitCriticalSection(SessionLock);
  SessionMeta := TStringList.Create;
  SessionMeta.CaseSensitive := True;

finalization
  SessionMeta.Free;
  DoneCriticalSection(SessionLock);

end.
