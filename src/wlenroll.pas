unit wlenroll;
{$mode objfpc}{$H+}
interface
uses SysUtils,DateUtils,wldb,wlpasswd,wlcrypt,wlpolicy,wltotp,wlreplay,wlentrop,wlauth,wlautsrc,wlrevoke,wlenmeta;

type TWLEnrollProof=class
  private
    FDb,FUser,FUsername,FMethod,FServices,FAdmin,FRef,FSource:string;
    FAt:Int64;
    FVerified:Boolean;
    constructor Create;
  public
    destructor Destroy;override;
  end;
function EnsureEnrollment(Db:TWLDb):Boolean;
// This proof can only start setup: it is not a login proof or an application token.
function AuthenticateEnrollment(Db:TWLDb;const Username,Password:string;out Proof:TWLEnrollProof):Boolean;
// Bind to a server-derived client digest. Return bearer token and fresh base32 secret
// only after saving pending setup. Caller must throttle both setup and confirmation.
function StartOTPEnrollment(Db:TWLDb;Proof:TWLEnrollProof;const Binding:string;out Token,Secret:string):Boolean;
function ConfirmOTPEnrollment(Db:TWLDb;const Token,Binding,Code:string):Boolean;
implementation
const CleanupDDL='CREATE TRIGGER _wl_enrol_cleanup AFTER DELETE ON users BEGIN DELETE FROM _wl_enrol WHERE userId=OLD.id; END';
procedure Wipe(var S:string);
begin if S<>'' then begin UniqueString(S);FillChar(S[1],Length(S),0);S:='';end;end;
constructor TWLEnrollProof.Create;
begin inherited Create;end;
destructor TWLEnrollProof.Destroy;
begin Wipe(FServices);inherited Destroy;end;
function EnsureEnrollment(Db:TWLDb):Boolean;
var Rows:TWLRows;
begin
  Result:=False;
  if not Db.Exec(StringReplace(EnrollDDL,'CREATE TABLE ','CREATE TABLE IF NOT EXISTS ',[])) then Exit;
  Rows:=Db.Query('SELECT type,sql FROM sqlite_master WHERE name=''_wl_enrol'';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'table') or (Rows[0][1]<>EnrollDDL) then Exit;
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''users'';');
  if Length(Rows)<>1 then Exit;
  if Rows[0][0]='view' then Exit(True);
  if Rows[0][0]<>'table' then Exit;
  if not Db.Exec(StringReplace(CleanupDDL,'CREATE TRIGGER ','CREATE TRIGGER IF NOT EXISTS ',[])) then Exit;
  Rows:=Db.Query('SELECT sql FROM sqlite_master WHERE name=''_wl_enrol_cleanup'' AND type=''trigger'' AND tbl_name=''users'';');
  Result:=(Length(Rows)=1) and (Rows[0][0]=CleanupDDL);
end;
function Account(Db:TWLDb;const Username:string):TWLRows;
begin
  Result:=nil;if not AuthSourceCurrent(Db) then Exit;
  Result:=Db.Query('SELECT id,COALESCE(json_extract(services_json,''$.password''),''''),COALESCE(loginDisabled,0),COALESCE(authenticationMethod,''password''),services_json,COALESCE(isAdmin,0),username FROM users WHERE username='+QuotedStr(Username)+' COLLATE BINARY LIMIT 2;');
  if Length(Result)<>1 then begin Result:=nil;Exit;end;
  if Result[0][2]<>'0' then Result:=nil;
end;
function Allowed(const Row:TWLRow):Boolean;
var Secret:string;
begin
  try Result:=FactorPolicy(Row[3],Row[4],Row[5]='1',Secret) in [fpNone,fpRequired];
  finally Wipe(Secret);end;
end;
function Scope(const UserId,Username,Method,Services,Admin:string):string;
begin
  Result:='id='+QuotedStr(UserId)+' AND username='+QuotedStr(Username)+' AND COALESCE(loginDisabled,0)=0 '+
    'AND COALESCE(authenticationMethod,''password'')='+QuotedStr(Method)+' AND services_json='+QuotedStr(Services)+
    ' AND CAST(COALESCE(isAdmin,0) AS TEXT)='+QuotedStr(Admin);
end;
function ValidBinding(const Binding:string):Boolean;
var i:Integer;
begin
  Result:=False;if Length(Binding)<>64 then Exit;
  for i:=1 to 64 do if not (Binding[i] in ['a'..'f','0'..'9']) then Exit;
  Result:=True;
end;
function AuthenticateEnrollment(Db:TWLDb;const Username,Password:string;out Proof:TWLEnrollProof):Boolean;
var Rows:TWLRows;Pending:TWLEnrollProof;
begin
  Result:=False;Proof:=nil;Pending:=nil;
  try
    try
      Rows:=Account(Db,Username);if (Length(Rows)<>1) or not Allowed(Rows[0]) then Exit;
      Pending:=TWLEnrollProof.Create;Pending.FSource:=AuthSourceCondition(Db);
      if not VerifyCredential(Password,Rows[0][1],Pending.FRef) then Exit;
      Pending.FDb:=ExpandFileName(Db.Path);Pending.FUser:=Rows[0][0];Pending.FUsername:=Rows[0][6];
      Pending.FMethod:=Rows[0][3];Pending.FServices:=Rows[0][4];Pending.FAdmin:=Rows[0][5];
      Pending.FAt:=DateTimeToUnix(Now,False);Pending.FVerified:=True;
      Proof:=Pending;Pending:=nil;Result:=True;
    except Result:=False;end;
  finally Pending.Free;end;
end;
function StartOTPEnrollment(Db:TWLDb;Proof:TWLEnrollProof;const Binding:string;out Token,Secret:string):Boolean;
var Rows:TWLRows;At:Int64;Bytes:RawByteString;PendingToken,PendingSecret,Key,Sql:string;
begin
  Result:=False;Token:='';Secret:='';Bytes:='';PendingSecret:='';
  if (Proof=nil) or not Proof.FVerified or not ValidBinding(Binding) then Exit;
  try
    try
      At:=DateTimeToUnix(Now,False);
      if (Proof.FDb<>ExpandFileName(Db.Path)) or (Proof.FSource<>AuthSourceCondition(Db)) or (At<Proof.FAt) or (At-Proof.FAt>30) then Exit;
      Rows:=Account(Db,Proof.FUsername);
      if (Length(Rows)<>1) or not Allowed(Rows[0]) or (Rows[0][0]<>Proof.FUser) or
        (Rows[0][3]<>Proof.FMethod) or (Rows[0][4]<>Proof.FServices) or (Rows[0][5]<>Proof.FAdmin) or
        not CredentialMatches(Rows[0][1],Proof.FRef) then Exit;
      if not EnsureEnrollment(Db) then Exit;
      Bytes:=SecureBytes(20);PendingSecret:=OTPSecret(Bytes);PendingToken:=NewAuthToken;Key:=TokenHash(Db,PendingToken);
      Sql:='INSERT INTO _wl_enrol(userId,tokenKey,binding,secret,created,expires,credentialRef,username,method,services,admin) SELECT id,'+
        QuotedStr(Key)+','+QuotedStr(Binding)+','+QuotedStr(PendingSecret)+','+IntToStr(At)+','+IntToStr(At+300)+','+QuotedStr(Proof.FRef)+',username,'+
        QuotedStr(Proof.FMethod)+','+QuotedStr(Proof.FServices)+','+QuotedStr(Proof.FAdmin)+' FROM users WHERE '+
        Scope(Proof.FUser,Proof.FUsername,Proof.FMethod,Proof.FServices,Proof.FAdmin)+' AND ('+Proof.FSource+')'+
        ' ON CONFLICT(userId) DO UPDATE SET tokenKey=excluded.tokenKey,binding=excluded.binding,secret=excluded.secret,created=excluded.created,expires=excluded.expires,credentialRef=excluded.credentialRef,username=excluded.username,method=excluded.method,services=excluded.services,admin=excluded.admin RETURNING tokenKey;';
      Rows:=Db.Query(Sql);
      if (Length(Rows)<>1) or (Rows[0][0]<>Key) then Exit;
      Proof.FVerified:=False;Token:=PendingToken;Secret:=PendingSecret;Result:=True;
      // Expired rows are not usable even if this best-effort housekeeping fails.
      Db.Exec('DELETE FROM _wl_enrol WHERE expires<='+IntToStr(At)+';');
    except Result:=False;Token:='';Secret:='';end;
  finally if Bytes<>'' then begin UniqueString(Bytes);FillChar(Bytes[1],Length(Bytes),0);Bytes:='';end;Wipe(PendingSecret);end;
end;
function ConfirmOTPEnrollment(Db:TWLDb;const Token,Binding,Code:string):Boolean;
var Rows,Users:TWLRows;At,Created,Expires,Counter,Last:Int64;Key,Factor,Pending,UserScope,Sql,Secret:string;
begin
  Result:=False;Secret:='';
  if (Length(Token)<>64) or not ValidBinding(Binding) then Exit;
  try
    try
      if not EnsureEnrollment(Db) then Exit;
      Key:=TokenHash(Db,Token);At:=DateTimeToUnix(Now,False);
      Rows:=Db.Query('SELECT userId,secret,created,expires,credentialRef,username,method,services,admin FROM _wl_enrol WHERE tokenKey='+QuotedStr(Key)+' AND binding='+QuotedStr(Binding)+';');
      if Length(Rows)<>1 then Exit;
      if not TryStrToInt64(Rows[0][2],Created) or not TryStrToInt64(Rows[0][3],Expires) or (At<Created) or (At>=Expires) then Exit;
      Users:=Account(Db,Rows[0][5]);
      if (Length(Users)<>1) or not Allowed(Users[0]) or (Users[0][0]<>Rows[0][0]) or
        (Users[0][3]<>Rows[0][6]) or (Users[0][4]<>Rows[0][7]) or (Users[0][5]<>Rows[0][8]) or
        not CredentialMatches(Users[0][1],Rows[0][4]) then Exit;
      Secret:=OTPCanonicalSecret(Rows[0][1]);Factor:=OTPFactorKey(Secret);
      if not EnsureOTPReplay(Db) or not LastOTPCounter(Db,Rows[0][0],Factor,Last) or not OTPMatch(Secret,Code,At,10,Last,Counter) then Exit;
      UserScope:=Scope(Rows[0][0],Rows[0][5],Rows[0][6],Rows[0][7],Rows[0][8]);
      Pending:='EXISTS(SELECT 1 FROM _wl_enrol WHERE tokenKey='+QuotedStr(Key)+' AND binding='+QuotedStr(Binding)+
        ' AND userId='+QuotedStr(Rows[0][0])+' AND secret='+QuotedStr(Rows[0][1])+' AND credentialRef='+QuotedStr(Rows[0][4])+
        ' AND created<='+IntToStr(At)+' AND expires>'+IntToStr(At)+') AND EXISTS(SELECT 1 FROM users WHERE '+UserScope+') AND ('+AuthSourceCondition(Db)+')';
      if not Db.Exec('CREATE TABLE IF NOT EXISTS authmeta(hashedToken TEXT PRIMARY KEY REFERENCES login_tokens(hashedToken) ON DELETE CASCADE,tenantKey TEXT NOT NULL,credentialRef TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN (''web'',''api'')));') then Exit;
      // A stale setup or competing confirmer MUST abort, never silently update zero
      // users and then revoke tokens/consume a counter. NOT NULL is the assertion.
      Sql:='BEGIN IMMEDIATE; INSERT INTO _wl_otp(userId,factorKey,counter) VALUES('+QuotedStr(Rows[0][0])+','+QuotedStr(Factor)+
        ',CASE WHEN '+Pending+' THEN '+IntToStr(Counter)+' ELSE NULL END) ON CONFLICT(userId,factorKey) DO UPDATE SET counter=CASE WHEN excluded.counter>_wl_otp.counter THEN excluded.counter ELSE NULL END; '+
        'UPDATE users SET services_json=json_set(services_json,''$.twoFactorAuthentication'',json_set(CASE WHEN json_type(services_json,''$.twoFactorAuthentication'')=''object'' THEN json_extract(services_json,''$.twoFactorAuthentication'') ELSE ''{}'' END,''$.type'',''otp'',''$.secret'','+QuotedStr(Secret)+')) WHERE '+UserScope+'; '+
        // A user trigger may ignore the update without reporting an SQL error.
        // Assert the visible activation before deleting setup or existing tokens.
        'UPDATE _wl_enrol SET secret=CASE WHEN EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(Rows[0][0])+
        ' AND json_extract(services_json,''$.twoFactorAuthentication.type'')=''otp'' AND json_extract(services_json,''$.twoFactorAuthentication.secret'')='+QuotedStr(Secret)+
        ') THEN secret ELSE NULL END WHERE tokenKey='+QuotedStr(Key)+'; '+
        RevokeUserTokensSQL(Db,Rows[0][0])+'COMMIT;';
      Result:=Db.Exec(Sql);if not Result then Db.Exec('ROLLBACK;');
    except Db.Exec('ROLLBACK;');Result:=False;end;
  finally Wipe(Secret);end;
end;
end.
