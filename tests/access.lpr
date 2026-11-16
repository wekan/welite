program access;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wldb, wlaccess;
var Db:TWLDb; P:TStringList;
procedure Check(B:Boolean; const Msg:string);
begin if not B then raise Exception.Create('FAIL: '+Msg); end;
begin
  Db:=TWLDb.Create(ParamStr(1)); P:=TStringList.Create;
  try
    Check(not BoardCanRead(Db,'','private'),'anonymous private');
    Check(BoardCanRead(Db,'','public'),'anonymous public');
    Check(not BoardCanWrite(Db,'','public'),'anonymous write');
    Check(BoardCanRead(Db,'editor','private'),'member read');
    Check(BoardCanWrite(Db,'editor','private'),'member write');
    Check(BoardCanRead(Db,'reader','private'),'reader read');
    Check(not BoardCanWrite(Db,'reader','private'),'reader write');
    Check(not BoardCanWrite(Db,'comment','private'),'comment write');
    Check(not BoardCanRead(Db,'assigned','private'),'assigned-only full-board read');
    Check(not BoardCanWrite(Db,'assigned','private'),'assigned-only full-board write');
    Check(not BoardCanRead(Db,'inactive','private'),'inactive member');
    Check(not BoardCanWrite(Db,'disabled','private'),'disabled admin');
    Check(BoardCanWrite(Db,'admin','private'),'admin write');
    Check(not BoardCanWrite(Db,'admin','missing'),'missing board');
    Check(not BoardCanWrite(Db,'admin','archived'),'archived board');
    P.Add('sel_card=c');
    Check(BoardSelectionAllowed(Db,'editor','private',P),'own selection');
    P.Add('sel_card=foreign');
    Check(not BoardSelectionAllowed(Db,'editor','private',P),'mixed board selection');
    P.Clear; P.Add('sel_card=missing');
    Check(not BoardSelectionAllowed(Db,'editor','private',P),'missing selection');
    P.Clear; P.Add('sel_list=archlist');
    Check(not BoardSelectionAllowed(Db,'editor','private',P),'archived selection');
    Check(SafeReturnPath('//evil.example')='/','protocol-relative redirect');
    Check(SafeReturnPath('/\evil.example')='/','backslash redirect');
    Check(SafeReturnPath('/ok'+#13+#10+'Header: evil')='/','header injection');
    Check(SafeReturnPath('https://evil.example')='/','absolute redirect');
    Check(SafeReturnPath('/board?id=private')='/board?id=private','local redirect');
    Writeln('PASS: board read/write roles, item isolation and safe return URLs');
  finally P.Free; Db.Free; end;
end.
