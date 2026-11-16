unit wlcrypt;
{$mode objfpc}{$H+}
interface
uses SysUtils,fpsha256;
function Sha256Hex(const Value:RawByteString):string;
function TenantTokenHash(const DatabasePath,Token:string):string;
function Hmac256Hex(const Key,Value:RawByteString):string;
function ConstantEqual(const A,B:string):Boolean;
implementation
function Sha256Hex(const Value:RawByteString):string;
var C:TSHA256;
begin
  C.Init;
  if Length(Value)>0 then C.Update(PByte(Pointer(Value)),Length(Value));
  C.Final; C.OutputHexa(Result); Result:=LowerCase(Result);
end;
function TenantTokenHash(const DatabasePath,Token:string):string;
begin Result:=Sha256Hex('welite-token-v2'+#0+ExpandFileName(DatabasePath)+#0+Token);end;
function Hmac256Hex(const Key,Value:RawByteString):string;
var D:TSHA256Digest; i:Integer;
begin
  if not TSHA256.HMAC(PByte(Pointer(Key)),Length(Key),PByte(Pointer(Value)),Length(Value),D) then
    raise Exception.Create('HMAC generation failed');
  Result:=''; for i:=0 to High(D) do Result:=Result+LowerCase(IntToHex(D[i],2));
end;
function ConstantEqual(const A,B:string):Boolean;
var i,Diff:Integer;
begin
  if Length(A)<>Length(B) then Exit(False);
  Diff:=0; for i:=1 to Length(A) do Diff:=Diff or (Ord(A[i]) xor Ord(B[i]));
  Result:=Diff=0;
end;
end.
