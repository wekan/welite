program totp;
{$mode objfpc}{$H+}
uses SysUtils,wltotp;
var Counter:Int64;Hex,Bytes:string;i:Integer;
begin
  try
    if ParamStr(1)='encode' then
    begin
      Hex:=ParamStr(2);Bytes:='';if Length(Hex) mod 2<>0 then raise Exception.Create('hex');
      for i:=0 to Length(Hex) div 2-1 do Bytes:=Bytes+Chr(StrToInt('$'+Copy(Hex,i*2+1,2)));
      Writeln(OTPSecret(Bytes));
    end
    else if ParamStr(1)='match' then
    begin
      if OTPMatch(ParamStr(2),ParamStr(3),StrToInt64(ParamStr(4)),StrToInt(ParamStr(5)),StrToInt64(ParamStr(6)),Counter) then Writeln(Counter)
      else Writeln('no');
    end
    else Writeln(OTPCode(ParamStr(2),StrToQWord(ParamStr(3)),StrToInt(ParamStr(4))));
  except Writeln('error');end;
end.
