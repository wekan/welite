unit wltotp;
{$mode objfpc}{$H+}
interface
uses SysUtils,hmac;
function OTPSecret(const Bytes:RawByteString):string;
function OTPCode(const Secret:string;Counter:QWord;Digits:Integer=6):string;
// Meteor uses SHA1, 30-second steps, six digits and a window of ten steps.
// MinCounter=-1 means no prior use; callers must consume the result atomically.
function OTPMatch(const Secret,Code:string;UnixSeconds:Int64;Window:Integer;
  MinCounter:Int64;out Counter:Int64):Boolean;
implementation
const Alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
procedure Invalid;
begin raise Exception.Create('Invalid one-time-code input');end;
function OTPSecret(const Bytes:RawByteString):string;
var Buffer:LongWord;Bits,i:Integer;
begin
  if (Length(Bytes)<1) or (Length(Bytes)>1024) then Invalid;
  Result:='';Buffer:=0;Bits:=0;
  for i:=1 to Length(Bytes) do
  begin
    Buffer:=(Buffer shl 8) or Ord(Bytes[i]);Inc(Bits,8);
    while Bits>=5 do begin Dec(Bits,5);Result:=Result+Alphabet[((Buffer shr Bits) and 31)+1];end;
  end;
  if Bits>0 then Result:=Result+Alphabet[((Buffer shl (5-Bits)) and 31)+1];
end;
function Decode(const Secret:string):RawByteString;
var Text:string;Padding,Expected,FirstPad,BufferBits,BufferBytes,i,N:Integer;Buffer:LongWord;
begin
  if (Length(Secret)<2) or (Length(Secret)>1640) then Invalid;
  for i:=1 to Length(Secret) do if not (Secret[i] in ['A'..'Z','a'..'z','2'..'7','=']) then Invalid;
  Text:=UpperCase(Secret);FirstPad:=Pos('=',Text);Padding:=0;
  if FirstPad>0 then
  begin
    Padding:=Length(Text)-FirstPad+1;
    for i:=FirstPad to Length(Text) do if Text[i]<>'=' then Invalid;
    if Length(Text) mod 8<>0 then Invalid;
    Text:=Copy(Text,1,FirstPad-1);
  end;
  case Length(Text) mod 8 of
    0:Expected:=0;2:Expected:=6;4:Expected:=4;5:Expected:=3;7:Expected:=1;
    else begin Invalid;Expected:=0;end;
  end;
  if (FirstPad>0) and (Padding<>Expected) then Invalid;
  BufferBytes:=Length(Text)*5 div 8;
  if (BufferBytes<1) or (BufferBytes>1024) then Invalid;
  SetLength(Result,BufferBytes);Buffer:=0;BufferBits:=0;BufferBytes:=0;
  try
    for i:=1 to Length(Text) do
    begin
      N:=Pos(Text[i],Alphabet)-1;if N<0 then Invalid;
      Buffer:=(Buffer shl 5) or LongWord(N);Inc(BufferBits,5);
      if BufferBits>=8 then
      begin Dec(BufferBits,8);Inc(BufferBytes);Result[BufferBytes]:=Chr((Buffer shr BufferBits) and 255);end;
    end;
    if (BufferBits>0) and ((Buffer and ((LongWord(1) shl BufferBits)-1))<>0) then Invalid;
  except if Result<>'' then FillChar(Result[1],Length(Result),0);raise;end;
end;
function WithKey(const Key:RawByteString;Counter:QWord;Digits:Integer):string;
var Message:RawByteString;Digest:THMACSHA1Digest;Offset,i:Integer;Number,Divisor:LongWord;
begin
  if (Digits<>6) and (Digits<>8) then Invalid;
  SetLength(Message,8);
  for i:=0 to 7 do Message[i+1]:=Chr((Counter shr ((7-i)*8)) and 255);
  Digest:=HMACSHA1Digest(Key,Message);
  try
    Offset:=Digest[19] and 15;
    Number:=(LongWord(Digest[Offset] and 127) shl 24) or (LongWord(Digest[Offset+1]) shl 16) or
      (LongWord(Digest[Offset+2]) shl 8) or LongWord(Digest[Offset+3]);
    if Digits=6 then Divisor:=1000000 else Divisor:=100000000;
    Result:=IntToStr(Number mod Divisor);while Length(Result)<Digits do Result:='0'+Result;
  finally FillChar(Digest,SizeOf(Digest),0);end;
end;
function OTPCode(const Secret:string;Counter:QWord;Digits:Integer):string;
var Key:RawByteString;
begin
  Key:=Decode(Secret);
  try Result:=WithKey(Key,Counter,Digits);
  finally if Key<>'' then begin UniqueString(Key);FillChar(Key[1],Length(Key),0);end;end;
end;
function OTPMatch(const Secret,Code:string;UnixSeconds:Int64;Window:Integer;
  MinCounter:Int64;out Counter:Int64):Boolean;
var Key:RawByteString;Center,TestCounter,Found:Int64;i,j,Difference:Integer;Candidate:string;Replay:Boolean;
begin
  Result:=False;Counter:=-1;Key:='';
  if (UnixSeconds<0) or (Window<0) or (Window>10) or (MinCounter< -1) or (Length(Code)<>6) then Exit;
  for i:=1 to 6 do if not (Code[i] in ['0'..'9']) then Exit;
  try
    try
      Key:=Decode(Secret);Center:=UnixSeconds div 30;Found:=-1;Replay:=False;
      // Scan the entire fixed window; do not stop at a matching or used code.
      for i:=-Window to Window do
      begin
        TestCounter:=Center+i;if TestCounter<0 then Continue;
        Candidate:=WithKey(Key,QWord(TestCounter),6);Difference:=0;
        for j:=1 to 6 do Difference:=Difference or (Ord(Candidate[j]) xor Ord(Code[j]));
        if Difference=0 then
        begin
          if TestCounter<=MinCounter then Replay:=True;
          if TestCounter>Found then Found:=TestCounter;
        end;
      end;
      if (Found>MinCounter) and not Replay then begin Counter:=Found;Result:=True;end;
    except Result:=False;Counter:=-1;end;
  finally if Key<>'' then begin UniqueString(Key);FillChar(Key[1],Length(Key),0);end;end;
end;
end.
