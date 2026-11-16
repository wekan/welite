unit wldisc;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,wldb;
// Discover existing managed paths only; never provision a tenant or use a host
// string as a directory. False reports a registry read failure, retaining local paths.
function DiscoverMaintenancePaths(const DataRoot:string;Paths:TStrings):Boolean;
implementation
uses wlregist;
function DiscoverMaintenancePaths(const DataRoot:string;Paths:TStrings):Boolean;
var Root,Admin,Path:string;Db:TWLDb;Rows:TWLRows;i:Integer;Key:Int64;
  procedure Existing(const Value:string);
  begin if FileExists(Value) then Paths.Add(Value);end;
begin
  Result:=False;Paths.Clear;Db:=nil;
  if DataRoot='' then Exit;
  Root:=IncludeTrailingPathDelimiter(ExpandFileName(DataRoot));
  Existing(Root+'local'+PathDelim+'files'+PathDelim+'db'+PathDelim+'wekan.db');
  Admin:=Root+'admin'+PathDelim+'files'+PathDelim+'db'+PathDelim+'wekan.db';Existing(Admin);
  if not FileExists(Admin) then Exit(True);
  try
    try
      Db:=TWLDb.Create(Admin);
      Rows:=Db.Query('SELECT 0 AS marker,0 AS key,'''' AS host UNION ALL SELECT 1,t.id,d.host FROM tenantdirs t JOIN domains d ON d.host=t.host WHERE d.enabled=1 ORDER BY marker,key;');
      if (Length(Rows)<1) or (Length(Rows[0])<>3) or (Rows[0][0]<>'0') then Exit;
      for i:=1 to High(Rows) do
      begin
        if (Length(Rows[i])<>3) or not TryStrToInt64(Rows[i][1],Key) or
          (Key<1) or (Key>268435455) or not RegistryValidHost(Rows[i][2]) then Continue;
        Path:=Root+'domains'+PathDelim+'d'+LowerCase(IntToHex(Key,7))+PathDelim+'files'+PathDelim+'db'+PathDelim+'wekan.db';
        Existing(Path);
      end;
      Result:=True;
    except Result:=False;end;
  finally Db.Free;end;
end;
end.
