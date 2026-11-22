program wkdir;
{ Harness for src/wlwkdir.pas, driven by tests/wkdir.py. Prints one result per line. }
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils, fpjson, wldb, wlwkdir;
var Sites: TWKSites; Site: TWKSite; Db: TWKDb; Docs: TJSONArray; Names: TStringArray;
  Name, Reason, Found: string; I, Count: Integer; Bytes: Int64;
begin
  if ParamStr(1) = 'sites' then
  begin
    Sites := WKSites;
    for Site in Sites do
      Writeln(Site.Root, '|', Site.Domain, '|', Site.Base, '|', Site.FilesDir, '|',
        BoolToStr(Site.Listed, '1', '0'), '|', Site.StartDate, '|', Site.EndDate);
  end
  else if ParamStr(1) = 'dbs' then
  begin
    if not WKFindSite(StrToInt(ParamStr(2)), ParamStr(3), Site) then begin Writeln('nosite'); Halt(2); end;
    Names := WKDatabases(Site);
    for Name in Names do Writeln(Name);
    Writeln('default=', WKDefaultDatabase(Site));
  end
  else if ParamStr(1) = 'open' then
  begin
    if not WKFindSite(StrToInt(ParamStr(2)), ParamStr(3), Site) then begin Writeln('nosite'); Halt(2); end;
    try
      Db := TWKDb.Create(WKDatabaseFile(Site, ParamStr(4)));
    except
      on E: Exception do begin Writeln('unreadable|', E.Message); Halt(3); end;
    end;
    try
      Writeln('uri=', Db.Uri);
      Docs := Db.Docs(ParamStr(5), '', WKField('_id'));
      try
        for I := 0 to Docs.Count - 1 do
          Writeln(WKStr(Docs.Objects[I], '_id'), '|', WKStr(Docs.Objects[I], 'title'), '|',
            WKDate(WKValue(Docs.Objects[I], 'createdAt')));
      finally Docs.Free; end;
      Writeln('skipped=', Db.Skipped);
    finally Db.Free; end;
  end
  else if ParamStr(1) = 'file' then
  begin
    if not WKFindSite(StrToInt(ParamStr(2)), ParamStr(3), Site) then begin Writeln('nosite'); Halt(2); end;
    Db := WKOpen(Site, ParamStr(4));
    if Db = nil then begin Writeln('unreadable'); Halt(3); end;
    try
      Docs := Db.Docs('attachments', WKField('_id') + '=' + WKLit(ParamStr(5)));
      try
        if Docs.Count <> 1 then begin Writeln('nodoc'); Halt(4); end;
        Found := WKAttachmentFile(Site, Docs.Objects[0], Reason);
        if Found = '' then Writeln('none|', Reason) else Writeln('file|', Found);
      finally Docs.Free; end;
    finally Db.Free; end;
  end
  else if ParamStr(1) = 'folder' then
  begin
    WKFolderBytes(ParamStr(2), Count, Bytes);
    Writeln(Count, '|', Bytes);
  end
  else if ParamStr(1) = 'leaf' then
    Writeln(BoolToStr(WKSafeLeaf(ParamStr(2)), '1', '0'))
  else
    Halt(1);
end.
