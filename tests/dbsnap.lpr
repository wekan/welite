program dbsnap;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses {$IFDEF UNIX}cthreads,{$ENDIF}SysUtils,Classes,fpjson,jsonparser,wldb,wltmp;
type
  TWriter=class(TThread)
    Db:TWLDb;Started,DoneFlag:LongInt;OK:Boolean;
    procedure Execute;override;
  end;
  TReader=class
    Count:Integer;
    procedure ReadRow(const Row:TWLRow);
  end;
procedure TWriter.Execute;
begin InterlockedExchange(Started,1);OK:=Db.Exec('UPDATE t SET x=''thread'';');InterlockedExchange(DoneFlag,1);end;
procedure TReader.ReadRow(const Row:TWLRow);
begin Inc(Count);if Count=1 then raise Exception.Create('Injected validation failure');end;
var Db:TWLDb;Writer:TWriter;Reader:TReader;Doc,Answer:TJSONObject;Values,Row:TJSONArray;
  Rows:TWLRows;Line,Op:string;i,j:Integer;
begin
  SetMultiByteConversionCodePage(CP_UTF8);SetTempRoot(ParamStr(2));Db:=TWLDb.Create(ParamStr(1));Writer:=nil;
  try
    while not EOF(Input) do
    begin
      Readln(Line);Doc:=TJSONObject(GetJSON(Line));Answer:=TJSONObject.Create;
      try
        Op:=Doc.Get('op','read');
        if Op='begin' then Answer.Add('ok',Db.BeginRead)
        else if Op='end' then Answer.Add('ok',Db.EndRead)
        else if Op='exec' then Answer.Add('ok',Db.Exec(Doc.Get('sql','')))
        else if Op='scan-fail' then
        begin
          Reader:=TReader.Create;
          try Answer.Add('ok',Db.Scan('SELECT x FROM t;',@Reader.ReadRow));finally Reader.Free;end;
        end
        else if Op='writer-start' then
        begin Writer:=TWriter.Create(True);Writer.Db:=Db;Writer.Start;Answer.Add('ok',True);end
        else if Op='writer-state' then
        begin Answer.Add('started',InterlockedCompareExchange(Writer.Started,0,0));Answer.Add('done',InterlockedCompareExchange(Writer.DoneFlag,0,0));end
        else
        begin
          Rows:=Db.Query(Doc.Get('sql','SELECT x FROM t;'));Values:=TJSONArray.Create;Answer.Add('rows',Values);
          for i:=0 to High(Rows) do
          begin Row:=TJSONArray.Create;for j:=0 to High(Rows[i]) do Row.Add(Rows[i][j]);Values.Add(Row);end;
        end;
        Writeln(Answer.AsJSON);Flush(Output);
      finally Answer.Free;Doc.Free;end;
    end;
  finally
    Db.EndRead;
    if Writer<>nil then begin Writer.WaitFor;Writer.Free;end;
    Db.Free;
  end;
end.
