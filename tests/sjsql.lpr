program sjsql;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,Classes,fpjson,wldb;
var Db:TWLDb;Sql,Line:string;Rows:TWLRows;OutputRows,Row:TJSONArray;i,j:Integer;
begin
  SetMultiByteConversionCodePage(CP_UTF8);Db:=nil;OutputRows:=nil;
  try
    Db:=TWLDb.Create(ParamStr(1));Sql:='';
    while not EOF(Input) do begin Readln(Line);Sql:=Sql+Line+#10;end;
    if ParamStr(2)='exec' then
    begin if Db.Exec(Sql) then Writeln('ok') else Writeln('error');end
    else
    begin
      Rows:=Db.Query(Sql);OutputRows:=TJSONArray.Create;
      for i:=0 to High(Rows) do
      begin Row:=TJSONArray.Create;OutputRows.Add(Row);for j:=0 to High(Rows[i]) do Row.Add(Rows[i][j]);end;
      Writeln(OutputRows.AsJSON);
    end;
  except on E:Exception do begin Writeln(StdErr,E.Message);Halt(1);end;end;
  OutputRows.Free;Db.Free;
end.
