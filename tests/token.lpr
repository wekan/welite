program token;
{$mode objfpc}{$H+}
uses SysUtils,HTTPDefs,wldb,wlauth;
var Db:TWLDb; R:TRequest; UserId:string; S:TWLSession; Ok:Boolean;
begin
  Db:=TWLDb.Create(ParamStr(2)); R:=TRequest.Create;
  try
    R.RemoteAddress:='127.0.0.1';R.UserAgent:='token-test';
    if ParamStr(1)='issue' then Ok:=IssueLoginToken(Db,'u','api-test-token',HashText('credential'),'api',3600)
    else if ParamStr(1)='web' then
    begin
      S:=CreateSession(Db,R,'u','user',HashText('credential'),3600);Writeln(S.SessionId);Halt(0);
    end
    else Ok:=ValidateLoginToken(Db,R,ParamStr(3),UserId);
    if Ok then Writeln('yes') else Writeln('no');
  finally R.Free;Db.Free;end;
end.
