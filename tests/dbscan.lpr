program dbscan;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,jsonparser,wldb,wltmp;
type
  TReader=class
    Count,Bytes,FailAt:Int64;
    Keep:Boolean;
    Values:TJSONArray;
    procedure ReadRow(const Row:TWLRow);
  end;
procedure TReader.ReadRow(const Row:TWLRow);
var i:Integer;Value:TJSONArray;
begin
  Inc(Count);
  if (FailAt>0) and (Count=FailAt) then raise Exception.Create('Injected handler failure');
  for i:=0 to High(Row) do Inc(Bytes,Length(Row[i]));
  if Keep then
  begin Value:=TJSONArray.Create;for i:=0 to High(Row) do Value.Add(Row[i]);Values.Add(Value);end;
end;
var Db:TWLDb;Reader:TReader;Doc,Response:TJSONObject;Line:string;OK:Boolean;
begin
  SetMultiByteConversionCodePage(CP_UTF8);SetTempRoot(ParamStr(2));Db:=TWLDb.Create(ParamStr(1));
  try
    while not EOF(Input) do
    begin
      Readln(Line);Doc:=TJSONObject(GetJSON(Line));Reader:=TReader.Create;Response:=nil;
      try
        Reader.Keep:=Doc.Get('keep',True);Reader.FailAt:=Doc.Get('failAt',Int64(0));Reader.Values:=TJSONArray.Create;
        OK:=Db.Scan(Doc.Get('sql',''),@Reader.ReadRow);
        Response:=TJSONObject.Create(['ok',OK,'count',Reader.Count,'bytes',Reader.Bytes]);
        if OK then begin Response.Add('rows',Reader.Values);Reader.Values:=nil;end
        else Response.Add('rows',TJSONNull.Create);
        Writeln(Response.AsJSON);
      finally Response.Free;Reader.Values.Free;Reader.Free;Doc.Free;end;
    end;
  finally Db.Free;end;
end.
