program lifetime;
{$mode objfpc}{$H+}
uses SysUtils,wllife;
begin
  try Writeln(TokenExpirationMs(StrToInt64(ParamStr(1)),TokenLifetimeMs(ParamStr(2))));
  except Writeln('error');end;
end.
