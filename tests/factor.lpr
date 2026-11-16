program factor;
{$mode objfpc}{$H+}
uses SysUtils,HTTPDefs,wldb,wlauth,wlpasswd;
var Db:TWLDb;Proof:TWLLoginProof;Request:TRequest;Session,Seen:TWLSession;UserId,Mode:string;Ok:Boolean;
begin
  Db:=nil;Proof:=nil;Request:=nil;
  try
    Db:=TWLDb.Create(ParamStr(1));Mode:=ParamStr(2);Request:=TRequest.Create;
    Request.RemoteAddress:='127.0.0.1';Request.UserAgent:='factor-test';
    if Mode='ttl' then begin Writeln(ApiTokenLifetime(Db));Halt(0);end;
    if Mode='check' then Ok:=ValidateLoginToken(Db,Request,ParamStr(3),UserId)
    else if not AuthenticateAccount(Db,ParamStr(3),ParamStr(4),ParamStr(5),Proof) then Ok:=False
    else if Mode='web' then
    begin Session:=CreateAuthenticatedSession(Db,Request,Proof,3600);Ok:=(Session.SessionId<>'') and ValidateSession(Db,Request,Session.SessionId,Seen);end
    else
    begin
      if Mode='mutate' then Db.Exec(ParamStr(7));
      Ok:=IssueAccountToken(Db,Proof,ParamStr(6),'api',ApiTokenLifetime(Db));
      if Ok and (Mode='twice') then Ok:=not IssueAccountToken(Db,Proof,'reuse-proof','api',ApiTokenLifetime(Db));
    end;
    if Ok then Writeln('yes') else Writeln('no');
  except Writeln('error');end;
  Proof.Free;Request.Free;Db.Free;
end.
