program bcrypt;
{$mode objfpc}{$H+}
uses SysUtils,wlbcrypt,wlpasswd;
var Password,Hex:string;i:Integer;
begin
  try
    Hex:=ParamStr(2);Password:='';for i:=0 to Length(Hex) div 2-1 do Password:=Password+Chr(StrToInt('$'+Copy(Hex,i*2+1,2)));
    if ParamStr(1)='meteor' then Writeln(HashMeteorPassword(Password))
    else if ParamStr(1)='legacy' then Writeln(HashPassword(Password))
    else if ParamStr(1)='password' then
    begin if VerifyPassword(Password,ParamStr(3)) then Writeln('yes') else Writeln('no');end
    else if ParamStr(1)='verify' then
    begin if BcryptVerify(Password,ParamStr(3)) then Writeln('yes') else Writeln('no');end
    else Writeln(BcryptHash(Password,ParamStr(3)));
  except Writeln('error');end;
end.
