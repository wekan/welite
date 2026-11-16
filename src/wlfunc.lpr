library wlfunc;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} SysUtils,ctypes,wlfuncs;
function sqlite3_wlfunc_init(Db:Pointer;Error:PPAnsiChar;Api:Pointer):cint;cdecl;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  Result:=LoadFunctions(Db,Api);
end;
exports sqlite3_wlfunc_init;
begin
end.
