program session;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} SysUtils,Classes,HTTPDefs,wldb,wlauth;
type
  TAttempt=class(TThread)
    Initial:TWLSession;
    Accepted:Boolean;
    procedure Execute;override;
  end;
procedure Setup(R:TRequest);
begin R.RemoteAddress:='127.0.0.1'; R.UserAgent:='Unit UTF-8 日本語'; end;
procedure TAttempt.Execute;
var R:TRequest; Local:TWLSession;
begin
  R:=TRequest.Create;
  try
    Setup(R);Local:=Initial;
    R.ContentFields.Values['auth_action']:='test:write';
    R.ContentFields.Values['auth_counter']:=IntToStr(Local.Counter);
    R.ContentFields.Values['auth_hash']:=ActionHash(Local,'test:write');
    Accepted:=VerifyActionToken(R,Local,'test:write');
  finally R.Free; end;
end;
procedure Check(B:Boolean;const Message:string);
begin if not B then raise Exception.Create('FAIL: '+Message); end;
var Db,Other:TWLDb; R:TRequest; S,Seen:TWLSession; Workers:array[0..15] of TAttempt;
  i,Accepted:Integer; Rows:TWLRows;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  Db:=TWLDb.Create(ParamStr(1));Other:=TWLDb.Create(ParamStr(2));R:=TRequest.Create;
  try
    Setup(R);
    S:=CreateSession(Db,R,'u','user'+#2+'日本語',HashText('credential'),3600);
    Check(S.SessionId<>'','persist session');
    Check(ValidateSession(Db,R,S.SessionId,Seen),'valid session with delimiter/Unicode name');
    Check(not ValidateSession(Other,R,S.SessionId,Seen) and (Seen.UserId=''),'database binding');
    Other.Exec('INSERT INTO login_tokens(hashedToken,userId,createdAt,expiresAt) VALUES('+QuotedStr(HashText(S.SessionId))+',''u'',''now'',''2099-01-01'');');
    Check(not ValidateSession(Other,R,S.SessionId,Seen) and (Seen.UserId=''),'copied token and user IDs do not cross databases');
    R.UserAgent:='Wrong client';
    Check(not ValidateSession(Db,R,S.SessionId,Seen) and (Seen.UserId=''),'failed validation clears identity');
    Setup(R);
    Check(ValidateSession(Db,R,S.SessionId,Seen),'wrong client did not destroy the real session');
    Db.Exec('UPDATE login_tokens SET userId=''other'';');
    Check(not ValidateSession(Db,R,S.SessionId,Seen) and (Seen.UserId=''),'persisted identity mismatch');
    Db.Exec('UPDATE login_tokens SET userId=''u'';');
    Db.Exec('UPDATE users SET services_json=''{}'' WHERE id=''u'';');
    Check(not ValidateSession(Db,R,S.SessionId,Seen) and (Seen.UserId=''),'credential change');
    Db.Exec('UPDATE users SET services_json=''{"password":"credential"}'' WHERE id=''u'';');
    Check(ValidateSession(Db,R,S.SessionId,Seen),'credential fixture restored');
    for i:=0 to High(Workers) do begin Workers[i]:=TAttempt.Create(True);Workers[i].Initial:=Seen;end;
    for i:=0 to High(Workers) do Workers[i].Start;
    Accepted:=0;
    for i:=0 to High(Workers) do
    begin Workers[i].WaitFor; if Workers[i].Accepted then Inc(Accepted);Workers[i].Free;end;
    Check(Accepted=1,'concurrent action token accepted once');
    Check(ValidateSession(Db,R,S.SessionId,Seen) and (Seen.Counter=1),'counter was not overwritten by validation');
    Sleep(2100);
    Check(not ValidateSession(Db,R,S.SessionId,Seen) and (Seen.UserId=''),'idle timeout');
    Rows:=Db.Query('SELECT COUNT(*) FROM login_tokens;');
    Check(Rows[0][0]='0','idle expiry revoked durable token');
    Writeln('PASS: database/identity/credential/client binding, empty failure identity, single concurrent counter and idle expiry');
  finally R.Free;Other.Free;Db.Free;end;
end.
