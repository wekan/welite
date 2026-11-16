unit wlblake;
{$mode objfpc}{$H+}
// Unkeyed BLAKE2b (RFC 7693) and Argon2 H' (RFC 9106 section 3.3).
interface
uses SysUtils;
function Blake2b(const Data:RawByteString;DigestBytes:Integer):RawByteString;
function ArgonHash(const Data:RawByteString;DigestBytes:Integer):RawByteString;
implementation
{$PUSH}{$Q-} // The compression additions are modulo 2^64.
type TWords=array[0..7] of QWord;TBlock=array[0..15] of QWord;
const IV:TWords=(QWord($6a09e667f3bcc908),QWord($bb67ae8584caa73b),QWord($3c6ef372fe94f82b),QWord($a54ff53a5f1d36f1),
  QWord($510e527fade682d1),QWord($9b05688c2b3e6c1f),QWord($1f83d9abfb41bd6b),QWord($5be0cd19137e2179));
  Sigma:array[0..9,0..15] of Byte=(
    (0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15),
    (14,10,4,8,9,15,13,6,1,12,0,2,11,7,5,3),
    (11,8,12,0,5,2,15,13,10,14,3,6,7,1,9,4),
    (7,9,3,1,13,12,11,14,2,6,5,10,4,0,15,8),
    (9,0,5,7,2,4,10,15,14,1,11,12,6,8,3,13),
    (2,12,6,10,0,11,8,3,4,13,7,5,15,14,1,9),
    (12,5,1,15,14,13,4,10,0,7,6,3,9,2,8,11),
    (13,11,7,14,12,1,3,9,5,0,15,4,8,6,2,10),
    (6,15,14,9,11,3,0,8,12,2,13,7,1,4,10,5),
    (10,2,8,4,7,6,1,5,15,11,9,14,3,12,13,0));
function Rotate(X:QWord;N:Byte):QWord;inline;
begin Result:=(X shr N) or (X shl (64-N));end;
procedure Mix(var A,B,C,D:QWord;X,Y:QWord);inline;
begin
  A:=A+B+X;D:=Rotate(D xor A,32);C:=C+D;B:=Rotate(B xor C,24);
  A:=A+B+Y;D:=Rotate(D xor A,16);C:=C+D;B:=Rotate(B xor C,63);
end;
procedure Compress(var H:TWords;const Block:TBlock;Low,High:QWord;Last:Boolean);
var V:TBlock;r,s,i:Integer;
begin
  for i:=0 to 7 do begin V[i]:=H[i];V[i+8]:=IV[i];end;
  V[12]:=V[12] xor Low;V[13]:=V[13] xor High;
  if Last then V[14]:=not V[14];
  for r:=0 to 11 do
  begin
    s:=r mod 10;
    Mix(V[0],V[4],V[8],V[12],Block[Sigma[s,0]],Block[Sigma[s,1]]);
    Mix(V[1],V[5],V[9],V[13],Block[Sigma[s,2]],Block[Sigma[s,3]]);
    Mix(V[2],V[6],V[10],V[14],Block[Sigma[s,4]],Block[Sigma[s,5]]);
    Mix(V[3],V[7],V[11],V[15],Block[Sigma[s,6]],Block[Sigma[s,7]]);
    Mix(V[0],V[5],V[10],V[15],Block[Sigma[s,8]],Block[Sigma[s,9]]);
    Mix(V[1],V[6],V[11],V[12],Block[Sigma[s,10]],Block[Sigma[s,11]]);
    Mix(V[2],V[7],V[8],V[13],Block[Sigma[s,12]],Block[Sigma[s,13]]);
    Mix(V[3],V[4],V[9],V[14],Block[Sigma[s,14]],Block[Sigma[s,15]]);
  end;
  for i:=0 to 7 do H[i]:=H[i] xor V[i] xor V[i+8];
  FillChar(V,SizeOf(V),0);
end;
function Blake2b(const Data:RawByteString;DigestBytes:Integer):RawByteString;
var H:TWords;Block:TBlock;Offset,Remaining:SizeInt;Low,High:QWord;i,Count:Integer;Last:Boolean;
begin
  if (DigestBytes<1) or (DigestBytes>64) then raise Exception.Create('Invalid BLAKE2b length');
  H:=IV;H[0]:=H[0] xor ($01010000 or QWord(DigestBytes));Low:=0;High:=0;Offset:=0;
  try
    repeat
      Remaining:=Length(Data)-Offset;Last:=Remaining<=128;
      if Last then Count:=Remaining else Count:=128;
      FillChar(Block,SizeOf(Block),0);
      // Explicit byte order also works on the big-endian retro targets.
      for i:=0 to Count-1 do Block[i div 8]:=Block[i div 8] or (QWord(Ord(Data[Offset+i+1])) shl ((i mod 8)*8));
      Low:=Low+QWord(Count);if Low<QWord(Count) then Inc(High);
      Compress(H,Block,Low,High,Last);Inc(Offset,Count);
    until Last;
    SetLength(Result,DigestBytes);
    for i:=0 to DigestBytes-1 do Result[i+1]:=Chr((H[i div 8] shr ((i mod 8)*8)) and 255);
  finally FillChar(H,SizeOf(H),0);FillChar(Block,SizeOf(Block),0);end;
end;
function ArgonHash(const Data:RawByteString;DigestBytes:Integer):RawByteString;
var Prefix,Buffer:RawByteString;Offset,Remaining,i:Integer;
begin
  if DigestBytes<1 then raise Exception.Create('Invalid Argon2 hash length');
  SetLength(Prefix,4);for i:=0 to 3 do Prefix[i+1]:=Chr((LongWord(DigestBytes) shr (i*8)) and 255);
  if DigestBytes<=64 then Exit(Blake2b(Prefix+Data,DigestBytes));
  Buffer:=Blake2b(Prefix+Data,64);SetLength(Result,DigestBytes);Offset:=0;Remaining:=DigestBytes;
  try
    while Remaining>64 do
    begin
      Move(Buffer[1],Result[Offset+1],32);Inc(Offset,32);Dec(Remaining,32);
      if Remaining>64 then Buffer:=Blake2b(Buffer,64);
    end;
    Buffer:=Blake2b(Buffer,Remaining);Move(Buffer[1],Result[Offset+1],Remaining);
  finally if Buffer<>'' then begin UniqueString(Buffer);FillChar(Buffer[1],Length(Buffer),0);end;end;
end;
{$POP}
end.
