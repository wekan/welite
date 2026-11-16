program short;
{$mode objfpc}{$H+}
uses SysUtils,wltenant,wlregist,wlstore,wldb,HTTPDefs,Classes;
var T:TWLTenant;R:TRequest;Db:TWLDb;i:Integer;Path:string;
begin
  try
    TenantInit(ParamStr(1));
    if not RegistryAddDomain('a-very-long.customer.example') or not ProvisionTenant('a-very-long.customer.example') then Halt(2);
    if not RegistryAddDomain('a-very-long.customer.other') or not ProvisionTenant('a-very-long.customer.other') then Halt(3);
    R:=TRequest.Create;
    try
      R.Host:='a-very-long.customer.example';
      if not ResolveTenant(R,T) then Halt(4);
      Writeln(T.DbPath);Writeln(TenantCertDir(T.Host));
      for i:=1 to 2 do Writeln(WLTempDir('ignored-long-operation-label'));
      Writeln(GetTempFileName('ignored-long-system-dir','ignored-long-prefix'));
      Writeln(StoreFilePath(T.FilesDir,'attachme','Case-sensitive-attachment-ID'));
      Db:=TWLDb.Create(T.DbPath,ParamStr(2)='journal');
      try
        if not Db.Exec('CREATE TABLE IF NOT EXISTS durable(value TEXT); INSERT INTO durable VALUES(''retained'');') then Halt(5);
        if ParamStr(2)='journal' then
          if not Db.Exec('CREATE TABLE IF NOT EXISTS journalprobe(value TEXT); BEGIN IMMEDIATE; INSERT INTO journalprobe VALUES(''pending'');') then Halt(6);
        // Keep the linked WAL live long enough for the Python driver to inspect it.
        Writeln('READY');Flush(Output);Readln(Path);
        if ParamStr(2)='journal' then Db.Exec('ROLLBACK;');
      finally Db.Free;end;
    finally R.Free;end;
  except on E:Exception do begin Writeln(StdErr,E.Message);Halt(1);end;end;
end.
