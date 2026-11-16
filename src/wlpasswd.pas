unit wlpasswd;

{
  Portable password credentials: new Meteor bcrypt objects, legacy PBKDF2 strings,
  and bounded Argon2 v16/v19 verification over the SHA256 plaintext digest.
  Optional Argon2 secret files bind both password proof and durable token validation.
  Salt/token entropy comes from wlentrop; there is no weak random fallback.
}

{$mode objfpc}{$H+}

interface

uses
  SysUtils,Classes,hmac,wlentrop,wlcrypt,wlbcrypt,fpjson,wlsjson,wlphc,wlsecret;

// Legacy fixture/import utility; new accounts use HashMeteorPassword.
function HashPassword(const Plain: string): string;

// Meteor services.password object, bcrypt(SHA256(plaintext)) with a fresh salt.
function HashMeteorPassword(const Plain:string):string;

// 256-bit random token using the configured platform salt source. OS randomness or a committed one-use stock block is required.
function NewAuthToken:string;

// Verify legacy PBKDF2 or Meteor bcrypt/Argon2 JSON over SHA256(plaintext). False on mismatch
// or malformed/empty stored value (so accounts with no real hash cannot be logged into).
function VerifyPassword(const Plain, Stored: string): Boolean;

// Return a binding captured with the same secret snapshot as password verification.
function VerifyCredential(const Plain,Stored:string;out Reference:string):Boolean;
// Token issuance/validation rechecks current secret policy; unavailable policy returns empty.
function CredentialFingerprint(const Stored:string):string;
function CredentialMatches(const Stored,Reference:string):Boolean;

implementation

const
  DEFAULT_ITERS = 50000;
  SALT_BYTES    = 16;
  DK_BYTES      = 20;   // one SHA-1 block

function ToHex(const S: string): string;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do Result := Result + LowerCase(IntToHex(Ord(S[i]), 2));
end;

function FromHex(const H: string): string;
var i: Integer;
begin
  Result := '';
  i := 1;
  while i + 1 <= Length(H) do
  begin
    Result := Result + Chr(StrToIntDef('$' + Copy(H, i, 2), 0));
    Inc(i, 2);
  end;
end;

function DigestToStr(const D: THMACSHA1Digest): string;
var i: Integer;
begin
  SetLength(Result, Length(D));
  for i := 0 to High(D) do Result[i + 1] := Chr(D[i]);
end;

// PBKDF2(password, salt, iters) for one SHA-1 block (dkLen = 20).
function Pbkdf2Sha1(const Password, Salt: string; Iters: Integer): string;
var
  U, T: THMACSHA1Digest;
  i, j: Integer;
begin
  // block index 1, big-endian 4 bytes
  U := HMACSHA1Digest(Password, Salt + #0#0#0#1);
  T := U;
  for i := 2 to Iters do
  begin
    U := HMACSHA1Digest(Password, DigestToStr(U));
    for j := 0 to High(T) do T[j] := T[j] xor U[j];
  end;
  Result := DigestToStr(T);
end;

function RandomBytes(N:Integer):string;
begin Result:=SecureBytes(N);end;

function NewAuthToken:string;
begin Result:=ToHex(RandomBytes(32)); end;

function HashPassword(const Plain: string): string;
var Salt, DK: string;
begin
  Salt := RandomBytes(SALT_BYTES);
  DK := Pbkdf2Sha1(Plain, Salt, DEFAULT_ITERS);
  Result := Format('pbkdf2_sha1$%d$%s$%s', [DEFAULT_ITERS, ToHex(Salt), ToHex(DK)]);
end;

// constant-time-ish hex compare
function SameHex(const A, B: string): Boolean;
var i, d: Integer;
begin
  if Length(A) <> Length(B) then Exit(False);
  d := 0;
  for i := 1 to Length(A) do d := d or (Ord(A[i]) xor Ord(B[i]));   // both already lowercase hex
  Result := d = 0;
end;

function VerifyLegacyPassword(const Plain, Stored: string): Boolean;
var
  P: TStringArray;
  Iters: Integer;
  Salt, DKHex: string;
begin
  Result := False;
  if Stored = '' then Exit;
  P := Stored.Split(['$']);
  if (Length(P) <> 4) or (P[0] <> 'pbkdf2_sha1') then Exit;
  Iters := StrToIntDef(P[1], 0);
  if Iters < 1 then Exit;
  Salt := FromHex(P[2]);
  DKHex := ToHex(Pbkdf2Sha1(Plain, Salt, Iters));
  Result := SameHex(DKHex, P[3]);
end;

function HashMeteorPassword(const Plain:string):string;
begin
  Result:='{"bcrypt":"'+BcryptHash(Sha256Hex(Plain),BcryptSalt(RandomBytes(16),10))+'"}';
end;
function ArgonField(const Stored:string;out Hash:string):Boolean;
var Password:TJSONObject;Value:TJSONData;Text:string;
begin
  Result:=False;Hash:='';Text:=Trim(Stored);
  if (Text='') or (Text[1]<>'{') then Exit;
  Password:=ExactObject(Text);
  try
    Value:=Password.Find('argon2');if (Value=nil) or (Value.JSONType=jtNull) then Exit;
    if Value.JSONType<>jtString then raise Exception.Create('Invalid Argon2 field');
    Hash:=Value.AsString;Result:=Hash<>'';
  finally Password.Free;end;
end;
function Fingerprint(const Stored:string;const Secret:RawByteString):string;
begin
  if Secret='' then Result:=Sha256Hex(Stored)
  else Result:=Hmac256Hex(Secret,'welite-argon-secret-v1'+#0+Stored);
end;
function CredentialFingerprint(const Stored:string):string;
var Hash:string;Secret:RawByteString;
begin
  Result:='';Secret:='';
  try
    try
      if ArgonField(Stored,Hash) then Secret:=ArgonSecret;
      Result:=Fingerprint(Stored,Secret);
    except Result:='';end;
  finally WipeSecret(Secret);end;
end;
function CredentialMatches(const Stored,Reference:string):Boolean;
var Current:string;
begin
  Current:=CredentialFingerprint(Stored);
  Result:=(Current<>'') and (Reference<>'') and ConstantEqual(Current,Reference);
end;
function VerifyCredential(const Plain,Stored:string;out Reference:string):Boolean;
var Password:TJSONObject;Value:TJSONData;Text,Hash:string;Secret:RawByteString;
begin
  Result:=False;Reference:='';Password:=nil;Secret:='';Text:=Trim(Stored);
  try
    try
      if ArgonField(Stored,Hash) then
      begin
        Secret:=ArgonSecret;
        Result:=VerifyArgonPHC(Sha256Hex(Plain),Hash,ArgonVerifyLimits,Secret);
      end
      else if (Text='') or (Text[1]<>'{') then Result:=VerifyLegacyPassword(Plain,Stored)
      else
      begin
        Password:=ExactObject(Text);Value:=Password.Find('bcrypt');
        if (Value<>nil) and (Value.JSONType=jtString) then Result:=BcryptVerify(Sha256Hex(Plain),Value.AsString);
      end;
      // The proof and binding use the very same secret snapshot. Issuance checks
      // this reference against current policy again before creating a token.
      if Result then Reference:=Fingerprint(Stored,Secret);
    except Result:=False;Reference:='';end;
  finally Password.Free;WipeSecret(Secret);end;
end;
function VerifyPassword(const Plain,Stored:string):Boolean;
var Reference:string;
begin Result:=VerifyCredential(Plain,Stored,Reference);end;

end.
