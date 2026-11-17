program cfpol;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,jsonparser,wldb,wlcfpol;
var Db:TWLDb;Policy:TFieldPolicy;Line:string;Data:TJSONObject;Fields:TJSONArray;Rows:TWLRows;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  Db:=TWLDb.Create(ParamStr(1));Policy:=nil;
  try
    Policy:=TFieldPolicy.Create(Db,ParamStr(2),ParamStr(3),ParamStr(4));
    while not EOF(Input) do
    begin
      Readln(Line);Data:=TJSONObject(GetJSON(Line));
      try
        Fields:=TJSONArray(Data.Find('fields'));
        if Fields<>nil then begin Policy.Redact(Fields);Writeln(Fields.AsJSON);end
        else if Data.Get('export',False) then
        begin
          if Data.Find('rows')<>nil then Writeln(Ord(FieldExportRowsAllowed(Db,ParamStr(2),ParamStr(3),TJSONArray(Data.Find('rows')))))
          else Writeln(Ord(BoardFieldExportAllowed(Db,ParamStr(2),ParamStr(3))));
        end
        else if Data.Get('definition',False) then
        begin
          Rows:=Db.Query('SELECT '+Policy.DefinitionExpression(Data.Get('field',''),Data.Get('admin',False))+';');
          if Length(Rows)=1 then Writeln(Rows[0][0]) else Writeln('0');
        end
        else Writeln(Ord(Policy.Allowed(Data.Get('field',''),Data.Get('write',False))));
      finally Data.Free;end;
    end;
  finally Policy.Free;Db.Free;end;
end.
