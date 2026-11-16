program maint;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF}SysUtils,wlmaint;
var Worker:TWLMaintainer;i:Integer;Line:string;
begin
  Worker:=TWLMaintainer.Create(50);
  try
    for i:=1 to ParamCount do begin Worker.AddPath(ParamStr(i));Worker.AddPath(ParamStr(i));end;
    Worker.Start;Writeln('ready');Flush(Output);
    repeat Readln(Line);
      if Line='status' then begin Writeln(Worker.FailedPasses);Flush(Output);end;
    until (Line='stop') or EOF(Input);
  finally Worker.Free;end;
  Writeln('stopped');
end.
