program dbfile;
{$mode objfpc}{$H+}
uses SysUtils,wldbfile;
var Selected:string;
begin
  if SelectStoreFile(ParamStr(1),ParamStr(2)<>'native',Selected,ParamStr(2)='fresh-shared') then Writeln(Selected)
  else Writeln('refused');
end.
