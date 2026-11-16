program dbfile;
{$mode objfpc}{$H+}
uses SysUtils,wldbfile;
var Selected:string;
begin
  if SelectStoreFile(ParamStr(1),ParamStr(2)='shared',Selected) then Writeln(Selected)
  else Writeln('refused');
end.
