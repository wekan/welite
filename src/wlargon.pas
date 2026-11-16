unit wlargon;
{$mode objfpc}{$H+}
// Argon2 v16/v19 block processing, adapted from golang.org/x/crypto v0.59.0.
// Copyright 2017 The Go Authors. BSD license: docs/gocrypt.txt.
interface
uses SysUtils,wlblake;
type TArgonLimits=record MemoryKiB,Iterations,Lanes,KeyBytes:LongWord;end;
const DefaultArgonLimits:TArgonLimits=(MemoryKiB:65536;Iterations:16;Lanes:64;KeyBytes:1024);
function ArgonKey(Mode:Integer;const Password,Salt,Secret,Data:RawByteString;
  Iterations,MemoryKiB,Lanes,KeyBytes:LongWord;const Limits:TArgonLimits;Version:LongWord=19):RawByteString;
implementation
{$PUSH}{$Q-} // BlaMka additions/multiplications are modulo 2^64.
type TBlock=array[0..127] of QWord;TMemory=array of TBlock;TRound=array[0..15] of QWord;
function Rotate(X:QWord;N:Byte):QWord;inline;
begin Result:=(X shr N) or (X shl (64-N));end;
function Add(A,B:QWord):QWord;inline;
begin Result:=A+B+2*(A and $ffffffff)*(B and $ffffffff);end;
procedure Mix(var A,B,C,D:QWord);inline;
begin
  A:=Add(A,B);D:=Rotate(D xor A,32);C:=Add(C,D);B:=Rotate(B xor C,24);
  A:=Add(A,B);D:=Rotate(D xor A,16);C:=Add(C,D);B:=Rotate(B xor C,63);
end;
procedure Permute(var V:TRound);
begin
  Mix(V[0],V[4],V[8],V[12]);Mix(V[1],V[5],V[9],V[13]);Mix(V[2],V[6],V[10],V[14]);Mix(V[3],V[7],V[11],V[15]);
  Mix(V[0],V[5],V[10],V[15]);Mix(V[1],V[6],V[11],V[12]);Mix(V[2],V[7],V[8],V[13]);Mix(V[3],V[4],V[9],V[14]);
end;
procedure Process(var Dest:TBlock;const Left,Right:TBlock;XorOld:Boolean);
var R,T:TBlock;V:TRound;i,j:Integer;
begin
  for i:=0 to 127 do begin R[i]:=Left[i] xor Right[i];T[i]:=R[i];end;
  for i:=0 to 7 do
  begin
    for j:=0 to 15 do V[j]:=T[i*16+j];Permute(V);
    for j:=0 to 15 do T[i*16+j]:=V[j];
  end;
  for i:=0 to 7 do
  begin
    for j:=0 to 15 do V[j]:=T[(j div 2)*16+i*2+(j mod 2)];Permute(V);
    for j:=0 to 15 do T[(j div 2)*16+i*2+(j mod 2)]:=V[j];
  end;
  for i:=0 to 127 do
    if XorOld then Dest[i]:=Dest[i] xor R[i] xor T[i] else Dest[i]:=R[i] xor T[i];
  FillChar(R,SizeOf(R),0);FillChar(T,SizeOf(T),0);FillChar(V,SizeOf(V),0);
end;
function LE32(Value:LongWord):RawByteString;
var i:Integer;
begin SetLength(Result,4);for i:=0 to 3 do Result[i+1]:=Chr((Value shr (i*8)) and 255);end;
function Blob(const S:RawByteString):RawByteString;
begin Result:=LE32(Length(S))+S;end;
procedure LoadBlock(const Bytes:RawByteString;var Block:TBlock);
var i:Integer;
begin
  FillChar(Block,SizeOf(Block),0);
  for i:=0 to 1023 do Block[i div 8]:=Block[i div 8] or (QWord(Ord(Bytes[i+1])) shl ((i mod 8)*8));
end;
function BlockBytes(const Block:TBlock):RawByteString;
var i:Integer;
begin SetLength(Result,1024);for i:=0 to 1023 do Result[i+1]:=Chr((Block[i div 8] shr ((i mod 8)*8)) and 255);end;
function Reference(Random:QWord;LaneLength,SegmentLength,Lanes,Pass,Slice,Lane,Index:LongWord):LongWord;
var RefLane,M,Start:LongWord;P:QWord;
begin
  RefLane:=(Random shr 32) mod Lanes;if (Pass=0) and (Slice=0) then RefLane:=Lane;
  M:=3*SegmentLength;Start:=((Slice+1) mod 4)*SegmentLength;
  if Lane=RefLane then Inc(M,Index);
  if Pass=0 then
  begin M:=Slice*SegmentLength;Start:=0;if (Slice=0) or (Lane=RefLane) then Inc(M,Index);end;
  if (Index=0) or (Lane=RefLane) then Dec(M);
  P:=Random and $ffffffff;P:=(P*P) shr 32;P:=(P*QWord(M)) shr 32;
  Result:=RefLane*LaneLength+LongWord((QWord(Start)+M-(P+1)) mod LaneLength);
end;
function ArgonKey(Mode:Integer;const Password,Salt,Secret,Data:RawByteString;
  Iterations,MemoryKiB,Lanes,KeyBytes:LongWord;const Limits:TArgonLimits;Version:LongWord):RawByteString;
var B:TMemory;H0,Bytes:RawByteString;Addresses,Input,Zero,FinalBlock:TBlock;
  Memory,LaneLength,SegmentLength,Pass,Slice,Lane,Index,Offset,Prev,Ref:LongWord;
  Random:QWord;i:Integer;Independent:Boolean;
  procedure NextAddresses;
  begin Inc(Input[6]);Process(Addresses,Input,Zero,False);Process(Addresses,Addresses,Zero,False);end;
  procedure Wipe(var S:RawByteString);
  begin if S<>'' then begin UniqueString(S);FillChar(S[1],Length(S),0);end;end;
begin
  if not (Version in [16,19]) or (Mode<0) or (Mode>2) or (Iterations<1) or (Iterations>Limits.Iterations) or
    (Lanes<1) or (Lanes>Limits.Lanes) or (KeyBytes<4) or (KeyBytes>Limits.KeyBytes) or
    (KeyBytes>LongWord(High(Integer))) or (Length(Salt)<8) or (MemoryKiB>Limits.MemoryKiB) or
    (QWord(MemoryKiB)<8*QWord(Lanes)) or (QWord(MemoryKiB)*1024>QWord(High(SizeInt))) or
    (QWord(Length(Password))>High(LongWord)) or (QWord(Length(Salt))>High(LongWord)) or
    (QWord(Length(Secret))>High(LongWord)) or (QWord(Length(Data))>High(LongWord)) then
      raise Exception.Create('Invalid or over-budget Argon2 parameters');
  B:=nil;H0:='';Bytes:='';
  FillChar(Addresses,SizeOf(Addresses),0);FillChar(Input,SizeOf(Input),0);FillChar(Zero,SizeOf(Zero),0);FillChar(FinalBlock,SizeOf(FinalBlock),0);
  try
    H0:=Blake2b(LE32(Lanes)+LE32(KeyBytes)+LE32(MemoryKiB)+LE32(Iterations)+LE32(Version)+LE32(Mode)+
      Blob(Password)+Blob(Salt)+Blob(Secret)+Blob(Data),64);
    Memory:=MemoryKiB div (4*Lanes)*(4*Lanes);LaneLength:=Memory div Lanes;SegmentLength:=LaneLength div 4;
    SetLength(B,Memory);
    for Lane:=0 to Lanes-1 do
    begin
      Bytes:=ArgonHash(H0+LE32(0)+LE32(Lane),1024);LoadBlock(Bytes,B[Lane*LaneLength]);
      Bytes:=ArgonHash(H0+LE32(1)+LE32(Lane),1024);LoadBlock(Bytes,B[Lane*LaneLength+1]);
    end;
    for Pass:=0 to Iterations-1 do
      for Slice:=0 to 3 do
        for Lane:=0 to Lanes-1 do
        begin
          // Lanes execute sequentially within each synchronized slice. Cross-lane
          // references never address unfinished blocks in the current slice.
          Independent:=(Mode=1) or ((Mode=2) and (Pass=0) and (Slice<2));
          FillChar(Input,SizeOf(Input),0);FillChar(Addresses,SizeOf(Addresses),0);
          if Independent then
          begin Input[0]:=Pass;Input[1]:=Lane;Input[2]:=Slice;Input[3]:=Memory;Input[4]:=Iterations;Input[5]:=Mode;end;
          Index:=0;
          if (Pass=0) and (Slice=0) then begin Index:=2;if Independent then NextAddresses;end;
          Offset:=Lane*LaneLength+Slice*SegmentLength+Index;
          while Index<SegmentLength do
          begin
            if (Index=0) and (Slice=0) then Prev:=Offset+LaneLength-1 else Prev:=Offset-1;
            if Independent then
            begin if (Index mod 128)=0 then NextAddresses;Random:=Addresses[Index mod 128];end
            else Random:=B[Prev][0];
            Ref:=Reference(Random,LaneLength,SegmentLength,Lanes,Pass,Slice,Lane,Index);
            Process(B[Offset],B[Prev],B[Ref],(Version=19) and (Pass>0));Inc(Index);Inc(Offset);
          end;
        end;
    FinalBlock:=B[Memory-1];
    if Lanes>1 then for Lane:=0 to Lanes-2 do
      for i:=0 to 127 do FinalBlock[i]:=FinalBlock[i] xor B[Lane*LaneLength+LaneLength-1][i];
    Bytes:=BlockBytes(FinalBlock);Result:=ArgonHash(Bytes,KeyBytes);
  finally
    if Length(B)>0 then FillChar(B[0],SizeInt(Length(B))*SizeOf(TBlock),0);B:=nil;
    Wipe(H0);Wipe(Bytes);FillChar(Addresses,SizeOf(Addresses),0);FillChar(Input,SizeOf(Input),0);FillChar(FinalBlock,SizeOf(FinalBlock),0);
  end;
end;
{$POP}
end.
