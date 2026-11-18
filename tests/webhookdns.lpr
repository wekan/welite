program webhookdns;
{$mode objfpc}{$H+}
uses wlwhurl;

procedure Check(const Url:string; Expected:Boolean);
begin
  if PublicWebhookUrl(Url)=Expected then Exit;
  WriteLn(StdErr,'Unexpected resolver result for ',Url);
  Halt(1);
end;

begin
  Check('https://1.1.1.1/path',True);
  Check('https://[2606:4700:4700::1111]:443/path',True);
  Check('http://127.0.0.1/path',False);
  Check('http://[::1]/path',False);
  Check('http://localhost./path',False);
  if ParamCount=1 then Check(ParamStr(1),True);
  WriteLn('PASS: public IPv4/IPv6 and rejected loopback webhook destinations');
end.
