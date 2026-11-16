program entropy;
{$mode objfpc}{$H+}
uses SysUtils,wlentrop;
var Value:RawByteString;i:Integer;
begin
  try
    if ParamStr(1)='create' then CreateEntropyStock(ParamStr(2),StrToInt64(ParamStr(3)))
    else begin
      Value:=SecureBytes(32);
      for i:=1 to Length(Value) do Write(IntToHex(Ord(Value[i]),2));
      Writeln;
    end;
  except on E:Exception do begin Writeln(StdErr,E.Message);Halt(1);end;end;
end.
