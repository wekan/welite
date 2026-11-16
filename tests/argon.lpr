program argon;
{$mode objfpc}{$H+}
uses SysUtils,wlargon;
function ReadBytes:RawByteString;
var Hex:string;i:Integer;
begin
  Readln(Hex);if Length(Hex) mod 2<>0 then raise Exception.Create('hex');SetLength(Result,Length(Hex) div 2);
  for i:=1 to Length(Result) do Result[i]:=Chr(StrToInt('$'+Copy(Hex,i*2-1,2)));
end;
var Password,Salt,Secret,Data,Key:RawByteString;Limits:TArgonLimits;i:Integer;
begin
  try
    Password:=ReadBytes;Salt:=ReadBytes;Secret:=ReadBytes;Data:=ReadBytes;Limits:=DefaultArgonLimits;
    Key:=ArgonKey(StrToInt(ParamStr(1)),Password,Salt,Secret,Data,StrToInt64(ParamStr(2)),StrToInt64(ParamStr(3)),StrToInt64(ParamStr(4)),StrToInt64(ParamStr(5)),Limits);
    for i:=1 to Length(Key) do Write(LowerCase(IntToHex(Ord(Key[i]),2)));Writeln;
  except Writeln('error');end;
end.
