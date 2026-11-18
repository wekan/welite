program dbfile;
{$mode objfpc}{$H+}
uses SysUtils,wldbfile;
var Selected:string;
begin
  if SelectStoreFile(ParamStr(1),(ParamStr(2)='shared') or (ParamStr(2)='fresh-shared'),Selected,
    (ParamStr(2)='fresh-shared') or (ParamStr(2)='auto-fresh')) then Writeln(Selected)
  else Writeln('refused');
end.
