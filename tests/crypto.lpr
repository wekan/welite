program crypto;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,HTTPDefs,wlcrypt,wlauth;
procedure Check(B:Boolean;const Message:string);
begin if not B then raise Exception.Create('FAIL: '+Message); end;
var S,T:TWLSession; H:string; R:TRequest;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  if ParamStr(1)='proxy' then
  begin
    R:=TRequest.Create;
    try R.RemoteAddress:=ParamStr(2);R.CustomHeaders.Values['X-Forwarded-For']:=ParamStr(3);Writeln(ClientIp(R));
    finally R.Free;end;
    Halt(0);
  end;
  Writeln(Sha256Hex(''));
  Writeln(Sha256Hex('abc'));
  Writeln(Sha256Hex('日本語'+#0+'tail'));
  Writeln(Hmac256Hex(StringOfChar(#$0b,20),'Hi There'));
  Writeln(Hmac256Hex('Jefe','what do ya want for nothing?'));
  Writeln(Hmac256Hex(StringOfChar(#$aa,131),'Test Using Larger Than Block-Size Key - Hash Key First'));
  Check(ConstantEqual('same','same') and not ConstantEqual('same','samf') and not ConstantEqual('a','aa'),'equality');
  S:=Default(TWLSession);S.TenantDb:='/tenant/a';S.UserId:='u';S.Username:='A|B';S.PasswordRef:='ref';
  S.Ip:='127.0.0.1';S.UserAgent:='client';S.LoginAt:=42;S.Counter:=0;S.SessionId:='token';S.ActionKey:='server-secret';
  H:=ActionHash(S,'write'); Check(Length(H)=64,'full HMAC');
  T:=S;T.TenantDb:='/tenant/b';Check(ActionHash(T,'write')<>H,'tenant context');
  T:=S;T.Counter:=1;Check(ActionHash(T,'write')<>H,'counter context');
  T:=S;T.ActionKey:='other-secret';Check(ActionHash(T,'write')<>H,'key context');
  Check(ActionHash(S,'other-action')<>H,'action context');
  Check(Pos(S.ActionKey,AuthHiddenFields(S,'write'))=0,'server-only action key');
  Writeln('PASS: context-bound HMAC and server-only key');
end.
