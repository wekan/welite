program phc;
{$mode objfpc}{$H+}
uses SysUtils,wlphc,wlpasswd;
var Password,Stored,Hex,Reference:string;i:Integer;Ok:Boolean;
begin
  try
    Readln(Hex);Password:='';for i:=0 to Length(Hex) div 2-1 do Password:=Password+Chr(StrToInt('$'+Copy(Hex,i*2+1,2)));
    Readln(Stored);
    if ParamStr(1)='proof' then
    begin if VerifyCredential(Password,Stored,Reference) then Writeln(Reference) else Writeln('no');Halt(0);end
    else if ParamStr(1)='fingerprint' then
    begin Reference:=CredentialFingerprint(Stored);if Reference='' then Writeln('no') else Writeln(Reference);Halt(0);end
    else if ParamStr(1)='meteor' then Ok:=VerifyPassword(Password,Stored) else Ok:=VerifyArgonPHC(Password,Stored,ArgonVerifyLimits);
    if Ok then Writeln('yes') else Writeln('no');
  except Writeln('no');end;
end.
