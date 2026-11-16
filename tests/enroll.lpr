program enroll;
{$mode objfpc}{$H+}
uses SysUtils,wldb,wlenroll,wlreplay;
var Db:TWLDb;Proof:TWLEnrollProof;Token,Secret:string;
begin
  Db:=nil;Proof:=nil;
  try
    Db:=TWLDb.Create(ParamStr(1));
    if ParamStr(2)='confirm' then
    begin if ConfirmOTPEnrollment(Db,ParamStr(3),ParamStr(4),ParamStr(5)) then Writeln('yes') else Writeln('no');end
    else if ParamStr(2)='ensure' then
    begin if EnsureEnrollment(Db) and EnsureOTPReplay(Db) then Writeln('yes') else Writeln('no');end
    else
    begin
      if not AuthenticateEnrollment(Db,ParamStr(3),ParamStr(4),Proof) then begin Writeln('no');Halt(0);end;
      if ParamStr(6)<>'' then Db.Exec(ParamStr(6));
      if ParamStr(2)='cross' then begin Db.Free;Db:=TWLDb.Create(ParamStr(7));end;
      if StartOTPEnrollment(Db,Proof,ParamStr(5),Token,Secret) then
      begin
        Writeln(Token);Writeln(Secret);
        if (ParamStr(2)='twice') and StartOTPEnrollment(Db,Proof,ParamStr(5),Token,Secret) then Writeln('unsafe');
      end else Writeln('no');
    end;
  except Writeln('no');end;
  Proof.Free;Db.Free;
end.
