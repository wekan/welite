unit wldisc;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,wldb;
// Discover existing managed paths only; never provision a tenant or use a host
// string as a directory. False reports a registry read failure, retaining local paths.
function DiscoverMaintenancePaths(const DataRoot:string;Paths:TStrings):Boolean;
implementation
uses wlregist,wldbfile;
function DiscoverMaintenancePaths(const DataRoot:string;Paths:TStrings):Boolean;
var Root,Admin,Path,DbDir:string;Db:TWLDb;Rows:TWLRows;i:Integer;Key:Int64;ValidPaths:Boolean;
  procedure Existing(const Value:string);
  begin if FileExists(Value) then Paths.Add(Value);end;
begin
  Result:=False;Paths.Clear;Db:=nil;ValidPaths:=True;
  if DataRoot='' then Exit;
  Root:=IncludeTrailingPathDelimiter(ExpandFileName(DataRoot));
  if SelectStoreFile(Root+'local'+PathDelim+'files'+PathDelim+'db',SharedStoresRequested,Path) then Existing(Path)
  else if DirectoryExists(Root+'local'+PathDelim+'files'+PathDelim+'db') then ValidPaths:=False;
  Admin:=Root+'admin'+PathDelim+'files'+PathDelim+'db'+PathDelim+'wekan.db';Existing(Admin);
  if not FileExists(Admin) then Exit(ValidPaths);
  try
    try
      Db:=TWLDb.Create(Admin);
      Rows:=Db.Query('SELECT 0 AS marker,0 AS key,'''' AS host UNION ALL SELECT 1,t.id,d.host FROM tenantdirs t JOIN domains d ON d.host=t.host WHERE d.enabled=1 ORDER BY marker,key;');
      if (Length(Rows)<1) or (Length(Rows[0])<>3) or (Rows[0][0]<>'0') then Exit;
      for i:=1 to High(Rows) do
      begin
        if (Length(Rows[i])<>3) or not TryStrToInt64(Rows[i][1],Key) or
          (Key<1) or (Key>268435455) or not RegistryValidHost(Rows[i][2]) then Continue;
        DbDir:=Root+'domains'+PathDelim+'d'+LowerCase(IntToHex(Key,7))+PathDelim+'files'+PathDelim+'db';
        if SelectStoreFile(DbDir,SharedStoresRequested,Path) then Existing(Path)
        else if DirectoryExists(Root+'domains'+PathDelim+'d'+LowerCase(IntToHex(Key,7))+PathDelim+'files'+PathDelim+'db') then ValidPaths:=False;
      end;
      Result:=ValidPaths;
    except Result:=False;end;
  finally Db.Free;end;
end;
end.
