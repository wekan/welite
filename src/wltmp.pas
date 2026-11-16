unit wltmp;
{$mode objfpc}{$H+}
interface
uses SysUtils {$IFDEF UNIX},BaseUnix{$ENDIF};
procedure SetTempRoot(const Root:string);
function NewTempDir:string;
implementation
var TempRoot:string='';Counter:LongInt=0;
procedure SetTempRoot(const Root:string);
begin TempRoot:=IncludeTrailingPathDelimiter(ExpandFileName(Root));end;
function NewTempDir:string;
var Root,Name:string;Number:LongInt;Created:Boolean;
begin
  Root:=TempRoot;
  if Root='' then Root:=IncludeTrailingPathDelimiter(GetTempDir)+'wlsql'+PathDelim;
  if not ForceDirectories(Root) and not DirectoryExists(Root) then raise Exception.Create('Could not create temporary root');
  repeat
    Number:=InterLockedIncrement(Counter);
    Name:='t'+LowerCase(IntToHex(Number and $0fffffff,7));
    Result:=Root+Name+PathDelim;
    {$IFDEF UNIX}Created:=fpMkdir(PChar(ExcludeTrailingPathDelimiter(Result)),&700)=0;
    {$ELSE}Created:=CreateDir(ExcludeTrailingPathDelimiter(Result));{$ENDIF}
    if Created then Exit;
    if not DirectoryExists(Result) then raise Exception.Create('Could not reserve private temporary directory');
  until False;
end;
end.
