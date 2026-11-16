unit wlbcrypt;
{$mode objfpc}{$H+}
// EksBlowfish expansion adapted from golang.org/x/crypto v0.59.0.
// Copyright 2010 The Go Authors. BSD license: docs/gocrypt.txt.
interface
uses SysUtils;
function BcryptSalt(const Bytes:string;Cost:Integer=10):string;
function BcryptHash(const Password,SaltToken:string):string;
function BcryptVerify(const Password,Stored:string):Boolean;
implementation
{$PUSH}{$Q-}{$R-} // Blowfish arithmetic is explicitly modulo 2^32.
{$I bfconst.inc}
const Alphabet='./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
type TState=record P:array[0..17] of LongWord;S:array[0..3,0..255] of LongWord;end;
procedure Invalid;
begin raise Exception.Create('Invalid bcrypt credential');end;
function Encode(const Bytes:string):string;
var i,Bits:Integer;Buffer:LongWord;
begin
  Result:='';Buffer:=0;Bits:=0;
  for i:=1 to Length(Bytes) do
  begin
    Buffer:=(Buffer shl 8) or Ord(Bytes[i]);Inc(Bits,8);
    while Bits>=6 do begin Dec(Bits,6);Result:=Result+Alphabet[((Buffer shr Bits) and 63)+1];end;
  end;
  if Bits>0 then Result:=Result+Alphabet[((Buffer shl (6-Bits)) and 63)+1];
end;
function Decode(const Text:string;Count:Integer):string;
var i,N,Bits:Integer;Buffer:LongWord;
begin
  Result:='';Buffer:=0;Bits:=0;
  for i:=1 to Length(Text) do
  begin
    N:=Pos(Text[i],Alphabet)-1;if N<0 then Invalid;
    Buffer:=(Buffer shl 6) or LongWord(N);Inc(Bits,6);
    if Bits>=8 then begin Dec(Bits,8);Result:=Result+Chr((Buffer shr Bits) and 255);end;
  end;
  if (Length(Result)<>Count) or (Encode(Result)<>Text) then Invalid;
end;
function F(var C:TState;X:LongWord):LongWord;inline;
begin Result:=((C.S[0,X shr 24]+C.S[1,(X shr 16) and 255]) xor C.S[2,(X shr 8) and 255])+C.S[3,X and 255];end;
procedure Encrypt(var C:TState;var L,R:LongWord);inline;
var i:Integer;T:LongWord;
begin
  L:=L xor C.P[0];
  for i:=1 to 16 do
  begin R:=R xor F(C,L) xor C.P[i];T:=L;L:=R;R:=T;end;
  R:=R xor C.P[17];T:=L;L:=R;R:=T;
end;
function WordAt(const Bytes:string;var Index:Integer):LongWord;inline;
var k:Integer;
begin
  Result:=0;
  for k:=1 to 4 do
  begin Result:=(Result shl 8) or Ord(Bytes[Index]);Inc(Index);if Index>Length(Bytes) then Index:=1;end;
end;
procedure Expand(var C:TState;const Key,Salt:string);
var i,j,Index:Integer;L,R:LongWord;
  procedure Next;
  begin
    if Salt<>'' then begin L:=L xor WordAt(Salt,Index);R:=R xor WordAt(Salt,Index);end;
    Encrypt(C,L,R);
  end;
begin
  Index:=1;for i:=0 to 17 do C.P[i]:=C.P[i] xor WordAt(Key,Index);
  L:=0;R:=0;Index:=1;
  i:=0;while i<18 do begin Next;C.P[i]:=L;C.P[i+1]:=R;Inc(i,2);end;
  for j:=0 to 3 do
  begin i:=0;while i<256 do begin Next;C.S[j,i]:=L;C.S[j,i+1]:=R;Inc(i,2);end;end;
end;
function BcryptSalt(const Bytes:string;Cost:Integer):string;
begin
  if (Length(Bytes)<>16) or (Cost<4) or (Cost>31) then Invalid;
  Result:='$2b$'+Format('%.2d',[Cost])+'$'+Encode(Bytes);
end;
function BcryptHash(const Password,SaltToken:string):string;
var C:TState;Salt,Key,Bytes,Prefix:string;Cost,i,j,k,Index:Integer;Rounds,Round:QWord;L,R:LongWord;
begin
  if (Length(SaltToken)<>29) or (SaltToken[1]<>'$') or (SaltToken[2]<>'2') or
    not (SaltToken[3] in ['a','b','y']) or (SaltToken[4]<>'$') or (SaltToken[7]<>'$') or
    not (SaltToken[5] in ['0'..'9']) or not (SaltToken[6] in ['0'..'9']) then Invalid;
  Cost:=StrToInt(Copy(SaltToken,5,2));if (Cost<4) or (Cost>31) or (Length(Password)>72) then Invalid;
  Salt:=Decode(Copy(SaltToken,8,22),16);Key:=Password+#0;UniqueString(Key);
  Move(Initp,C.P,SizeOf(C.P));Move(Inits0,C.S[0],SizeOf(C.S[0]));Move(Inits1,C.S[1],SizeOf(C.S[1]));
  Move(Inits2,C.S[2],SizeOf(C.S[2]));Move(Inits3,C.S[3],SizeOf(C.S[3]));
  try
    Expand(C,Key,Salt);Rounds:=QWord(1) shl Cost;Round:=0;
    while Round<Rounds do begin Expand(C,Key,'');Expand(C,Salt,'');Inc(Round);end;
    Bytes:='OrpheanBeholderScryDoubt';
    for i:=0 to 2 do
    begin
      Index:=i*8+1;L:=WordAt(Bytes,Index);R:=WordAt(Bytes,Index);
      for j:=1 to 64 do Encrypt(C,L,R);
      for k:=0 to 3 do
      begin Bytes[i*8+k+1]:=Chr((L shr (24-k*8)) and 255);Bytes[i*8+k+5]:=Chr((R shr (24-k*8)) and 255);end;
    end;
    Prefix:=Copy(SaltToken,1,7);Result:=Prefix+Encode(Salt)+Encode(Copy(Bytes,1,23));
  finally FillChar(C,SizeOf(C),0);if Key<>'' then FillChar(Key[1],Length(Key),0);end;
end;
function BcryptVerify(const Password,Stored:string):Boolean;
var Actual:string;i,Difference:Integer;
begin
  Result:=False;
  if Length(Stored)<>60 then Exit;
  try
    Decode(Copy(Stored,30,31),23);Actual:=BcryptHash(Password,Copy(Stored,1,29));Difference:=0;
    for i:=1 to 60 do Difference:=Difference or (Ord(Actual[i]) xor Ord(Stored[i]));
    Result:=Difference=0;
  except Result:=False;end;
end;
{$POP}
end.
