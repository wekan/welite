unit wlphc;
{$mode objfpc}{$H+}
interface
uses SysUtils,wlargon,wlcrypt;
function ArgonVerifyLimits:TArgonLimits;
function VerifyArgonPHC(const Password,Stored:RawByteString;const Limits:TArgonLimits):Boolean;
implementation
procedure Invalid;
begin raise Exception.Create('Invalid Argon2 credential');end;
function Decimal(const Text:string):LongWord;
var i:Integer;N:QWord;
begin
  if (Text='') or ((Length(Text)>1) and (Text[1]='0')) then Invalid;
  N:=0;
  for i:=1 to Length(Text) do
  begin
    if not (Text[i] in ['0'..'9']) then Invalid;
    N:=N*10+Ord(Text[i])-Ord('0');if N>High(LongWord) then Invalid;
  end;
  Result:=N;
end;
function ArgonVerifyLimits:TArgonLimits;
  function ReadLimit(const Name:string;Default:LongWord):LongWord;
  var Text:string;
  begin
    Text:=GetEnvironmentVariable(Name);if Text='' then Exit(Default);
    Result:=Decimal(Text);if Result=0 then Invalid;
  end;
begin
  Result.MemoryKiB:=ReadLimit('WELITE_ARGON_MEMORY_KIB',DefaultArgonLimits.MemoryKiB);
  Result.Iterations:=ReadLimit('WELITE_ARGON_PASSES',DefaultArgonLimits.Iterations);
  Result.Lanes:=ReadLimit('WELITE_ARGON_LANES',DefaultArgonLimits.Lanes);
  Result.KeyBytes:=ReadLimit('WELITE_ARGON_KEY_BYTES',DefaultArgonLimits.KeyBytes);
end;
function Base64(const Text:string;MaxBytes:LongWord):RawByteString;
const Alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
var i,N,Bits,Offset,Size:Integer;Buffer:LongWord;
begin
  if (Length(Text) mod 4=1) or (QWord(Length(Text))*6 div 8>MaxBytes) then Invalid;
  Size:=Length(Text)*6 div 8;SetLength(Result,Size);Buffer:=0;Bits:=0;Offset:=0;
  for i:=1 to Length(Text) do
  begin
    N:=Pos(Text[i],Alphabet)-1;if N<0 then Invalid;
    Buffer:=(Buffer shl 6) or LongWord(N);Inc(Bits,6);
    if Bits>=8 then
    begin Dec(Bits,8);Inc(Offset);Result[Offset]:=Chr((Buffer shr Bits) and 255);end;
  end;
  if (Bits>0) and ((Buffer and ((LongWord(1) shl Bits)-1))<>0) then Invalid;
end;
function VerifyArgonPHC(const Password,Stored:RawByteString;const Limits:TArgonLimits):Boolean;
var Parts,Params,Pair:TStringArray;Mode,i,Count:Integer;M,T,P:LongWord;HaveM,HaveT,HaveP,HaveData:Boolean;
  Salt,Data,Expected,Actual:RawByteString;
begin
  Result:=False;Actual:='';
  try
    try
      if (Length(Stored)>1024*1024) or (Length(Stored)<20) then Invalid;
      Count:=0;for i:=1 to Length(Stored) do if Stored[i]='$' then Inc(Count);if Count<>5 then Invalid;
      Parts:=string(Stored).Split('$');if (Length(Parts)<>6) or (Parts[0]<>'') or (Parts[2]<>'v=19') then Invalid;
      if Parts[1]='argon2d' then Mode:=0 else if Parts[1]='argon2i' then Mode:=1
      else if Parts[1]='argon2id' then Mode:=2 else begin Invalid;Mode:=0;end;
      Count:=0;for i:=1 to Length(Parts[3]) do if Parts[3][i]=',' then Inc(Count);if (Count<2) or (Count>3) then Invalid;
      Params:=Parts[3].Split(',');if (Length(Params)<3) or (Length(Params)>4) then Invalid;
      HaveM:=False;HaveT:=False;HaveP:=False;HaveData:=False;Data:='';M:=0;T:=0;P:=0;
      for i:=0 to High(Params) do
      begin
        Pair:=Params[i].Split('=');if Length(Pair)<>2 then Invalid;
        case Pair[0] of
          'm':begin if HaveM then Invalid;HaveM:=True;M:=Decimal(Pair[1]);end;
          't':begin if HaveT then Invalid;HaveT:=True;T:=Decimal(Pair[1]);end;
          'p':begin if HaveP then Invalid;HaveP:=True;P:=Decimal(Pair[1]);end;
          'data':begin if HaveData then Invalid;HaveData:=True;Data:=Base64(Pair[1],65536);end;
          else Invalid;
        end;
      end;
      if not (HaveM and HaveT and HaveP) then Invalid;
      if (M>Limits.MemoryKiB) or (T>Limits.Iterations) or (P>Limits.Lanes) then Invalid;
      Salt:=Base64(Parts[4],65536);Expected:=Base64(Parts[5],Limits.KeyBytes);
      Actual:=ArgonKey(Mode,Password,Salt,'',Data,T,M,P,Length(Expected),Limits);
      Result:=ConstantEqual(Actual,Expected);
    except Result:=False;end;
  finally if Actual<>'' then begin UniqueString(Actual);FillChar(Actual[1],Length(Actual),0);end;end;
end;
end.
