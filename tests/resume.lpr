program resume;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,jsonparser,wlresume;
var Line:string;Cmd,Output:TJSONObject;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  while not EOF(Input) do
  begin
    Readln(Line);Cmd:=nil;
    try
      Cmd:=TJSONObject(GetJSON(Line));
      if Cmd.Get('mode','')='hash' then
      begin Output:=TJSONObject.Create;try Output.Add('hash',MeteorTokenHash(Cmd.Get('token','')));Writeln(Output.AsJSON);finally Output.Free;end;end
      else Writeln(ResumeDocument(Cmd.Get('old',''),Cmd.Get('command','')));
    except Writeln('{"error":"invalid"}');end;
    Cmd.Free;
  end;
end.
