unit wlpasswd;

{
  WeKan-Lite — password hashing (PBKDF2-HMAC-SHA1, RTL-only, portable)

  Replaces the placeholder "any non-empty password" check. Stored form (in
  users.services_json under "password"):

      pbkdf2_sha1$<iterations>$<saltHex>$<derivedKeyHex>

  Legacy hashes use the portable RTL HMAC-SHA1 implementation. Meteor bcrypt
  verification uses the portable wlbcrypt kernel over a SHA256 plaintext digest;
  HashMeteorPassword returns a services.password JSON object. Argon2 remains unsupported.

  Salt/token entropy comes from wlentrop: OS random sources, or a configured one-use
  SQLite stock for targets without a kernel random source. There is no Random fallback.

  v0.1 reference skeleton.
}

{$mode objfpc}{$H+}

interface

uses
  SysUtils,Classes,hmac,wlentrop,wlcrypt,wlbcrypt,fpjson,wlsjson;

// Hash a plaintext password -> "pbkdf2_sha1$iters$saltHex$dkHex".
function HashPassword(const Plain: string): string;

// Meteor services.password object, bcrypt(SHA256(plaintext)) with a fresh salt.
function HashMeteorPassword(const Plain:string):string;

// 256-bit random token using the configured platform salt source. OS randomness or a committed one-use stock block is required.
function NewAuthToken:string;

// Verify legacy PBKDF2 strings or Meteor password JSON with bcrypt(SHA256(plaintext)). False on mismatch
// or malformed/empty stored value (so accounts with no real hash cannot be logged into).
function VerifyPassword(const Plain, Stored: string): Boolean;

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
function VerifyPassword(const Plain,Stored:string):Boolean;
var Password:TJSONObject;Value:TJSONData;Text:string;
begin
  Text:=Trim(Stored);
  if (Text='') or (Text[1]<>'{') then Exit(VerifyLegacyPassword(Plain,Stored));
  Result:=False;Password:=nil;
  try
    try
      Password:=ExactObject(Text);Value:=Password.Find('argon2');
      // Meteor chooses Argon2 first. Never accept a stale bcrypt fallback.
      if (Value<>nil) and (Value.JSONType<>jtNull) then
        if (Value.JSONType<>jtString) or (Value.AsString<>'') then Exit;
      Value:=Password.Find('bcrypt');
      if (Value=nil) or (Value.JSONType<>jtString) then Exit;
      Result:=BcryptVerify(Sha256Hex(Plain),Value.AsString);
    except Result:=False;end;
  finally Password.Free;end;
end;

end.
