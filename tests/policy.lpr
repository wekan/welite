program policy;
{$mode objfpc}{$H+}
uses SysUtils,wlpolicy;
var Services:string;
begin
  Readln(Services);
  if PasswordOnlyAllowed(ParamStr(1),Services,ParamStr(2)='1') then Writeln('yes') else Writeln('no');
end.
