unit wlwkdir;

{
  WeKan-Lite — read-only reader for WeKan data folders (docs/wekandir.md)

  A WeKan data folder is what WeKan's WRITABLE_PATH holds (server/initializeDirs.js,
  models/lib/filesRoot.js, models/lib/attachmentStoragePath.js):

    <WRITABLE_PATH>/files/db/wekan.sqlite      FerretDB v1 SQLite (--sqlite-url=file:.../files/db/)
    <WRITABLE_PATH>/files/attachments/<id>.<ext> Meteor-Files filesystem storage
    <WRITABLE_PATH>/files/avatars/...

  A WRITABLE_PATH that already ends in "files" or "wekan-files" (Snap, single-file
  WeKan) is itself the files folder. A Weddy/caddy-wekan-plugin data folder has one
  such folder per customer domain: <data>/domains/<domain>/files/..., with the Cloud
  Panel's domain list in <data>/cloud/domains.json.

  FerretDB's SQLite backend (internal/backends/sqlite/metadata) keeps one file per
  database (<name>.sqlite, or <name>.db with dbext=db), the collection registry in
  _ferretdb_collections(name, table_name, settings), and each document as typed SJSON
  in the _ferretdb_sjson column: TEXT in older tables, SQLite JSONB BLOB in newer.

  Everything here is read-only: the database is opened with SQLite's read-only URI
  modes and never with a write, and files are only opened for reading. Every path
  built from a database value or a URL is a single checked name inside a folder this
  unit found itself, never a path taken from the data.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, Classes, fpjson, jsonparser, wldb
  {$IFDEF WLDB_CLI}, Process{$ELSE}, sqlite3{$ENDIF}
  {$IFDEF UNIX}, BaseUnix{$ENDIF};

type
  TWKSite = record
    Root: Integer;          // index into WKRoots
    Domain: string;         // '' for the root folder's own WeKan
    Base: string;           // the WRITABLE_PATH of this WeKan
    FilesDir: string;       // <Base>/files, or Base when Base is the files folder
    Listed: Boolean;        // named in <root>/cloud/domains.json
    StartDate, EndDate: string;
  end;
  TWKSites = array of TWKSite;

  TWKDb = class
  private
    FPath, FUri: string;
    FTables: TStringList;
    FSkipped: Integer;
    {$IFNDEF WLDB_CLI}FHandle: Pointer;{$ENDIF}
    function Run(const Sql: string; out Rows: TWLRows): Boolean;
  public
    // Raises when the file is missing, not SQLite, not a FerretDB database,
    // or cannot be opened without writing to its folder.
    constructor Create(const DbPath: string);
    destructor Destroy; override;
    function Query(const Sql: string): TWLRows;
    // Physical table of a collection, '' when the collection does not exist.
    function Table(const Collection: string): string;
    // The quoted table for a FROM clause, '' when the collection does not exist.
    function From(const Collection: string): string;
    // count(*) of a collection, 0 when it does not exist.
    function Count(const Collection, Where: string): Int64;
    // Plain documents (SJSON decoded by wlsjson) of a collection. The caller frees.
    function Docs(const Collection, Where: string; const Order: string = ''): TJSONArray;
    // Typed documents that could not be decoded are skipped and counted here.
    property Skipped: Integer read FSkipped;
    property Path: string read FPath;
    property Uri: string read FUri;
  end;

const
  WKDoc = '_ferretdb_sjson';

// Configured roots, from WELITE_WEKAN_ROOTS (';' or newline separated paths).
function WKRoots: TStringArray;
function WKConfigured: Boolean;
// Every WeKan found under the configured roots, root by root.
function WKSites: TWKSites;
// Look a site up by the values a URL carries; the domain must be one WKSites found.
function WKFindSite(RootIndex: Integer; const Domain: string; out Site: TWKSite): Boolean;
// Database names in <files>/db: FerretDB files with a .sqlite or .db extension.
function WKDatabases(const Site: TWKSite): TStringArray;
// The database a page opens when none is named: wekan when present, else the first.
function WKDefaultDatabase(const Site: TWKSite): string;
// The database file of a listed name, '' when the name is not one WKDatabases lists.
function WKDatabaseFile(const Site: TWKSite; const Name: string): string;
// Open a listed database read-only; nil when it is missing or unreadable.
function WKOpen(const Site: TWKSite; const Name: string): TWKDb;

// SQL helpers over the document column.
function WKField(const Path: string): string;   // json_extract(_ferretdb_sjson,'$."a"."b"')
function WKLit(const Value: string): string;     // SQL string literal; refuses NUL
function WKNotDeleted: string;                   // attachments.deletedAt unset or null

// JSON helpers for plain documents.
function WKStr(Obj: TJSONObject; const Path: string): string;
function WKBool(Obj: TJSONObject; const Path: string): Boolean;
function WKNum(Obj: TJSONObject; const Path: string): Double;
function WKArr(Obj: TJSONObject; const Path: string): TJSONArray;
function WKValue(Obj: TJSONObject; const Path: string): TJSONData;
// A date WeKan stored as a BSON date (epoch milliseconds in SJSON) or a string.
function WKDate(Value: TJSONData): string;
// Sort documents in place by numeric "sort", then title, then _id.
procedure WKSortDocs(Docs: TJSONArray);

// A URL/database identifier: nonempty, at most 200 bytes, no control characters.
function WKValidId(const Value: string): Boolean;
// A single file name that cannot leave its folder.
function WKSafeLeaf(const Value: string): Boolean;
// Where an attachment's bytes are, strictly inside <files>/attachments.
// Returns '' with Reason 'storage' (not on the filesystem) or 'missing'.
function WKAttachmentFile(const Site: TWKSite; Doc: TJSONObject; out Reason: string): string;
// Regular, non-symlink files directly inside a folder: count and bytes.
procedure WKFolderBytes(const Dir: string; out Count: Integer; out Bytes: Int64);
function WKFileBytes(const FileName: string): Int64;
// Database file plus its live WAL, in bytes.
function WKDatabaseBytes(const DbFile: string): Int64;

implementation

uses StrUtils, DateUtils, wlsjson{$IFNDEF WLDB_CLI}, ctypes{$ENDIF};

{$IFNDEF WLDB_CLI}
// SQLite 3.7.4+; not in FPC's binding. True only for a statement that cannot write.
function sqlite3_stmt_readonly(Stmt: Pointer): cint; cdecl; external Sqlite3Lib;
{$ENDIF}

{ ---------------------------------------------------------------- file checks }

function PlainDir(const Dir: string): Boolean;
{$IFDEF UNIX}var Info: Stat;{$ENDIF}
begin
  {$IFDEF UNIX}
  Result := (fpLstat(PChar(ExcludeTrailingPathDelimiter(Dir)), Info) = 0) and fpS_ISDIR(Info.st_mode);
  {$ELSE}
  Result := DirectoryExists(Dir) and ((FileGetAttr(Dir) and faSymLink) = 0);
  {$ENDIF}
end;

function PlainFile(const FileName: string; out Size: Int64): Boolean;
{$IFDEF UNIX}var Info: Stat;{$ELSE}var Search: TSearchRec;{$ENDIF}
begin
  Size := 0;
  {$IFDEF UNIX}
  Result := (fpLstat(PChar(FileName), Info) = 0) and fpS_ISREG(Info.st_mode);
  if Result then Size := Info.st_size;
  {$ELSE}
  Result := (FindFirst(FileName, faAnyFile, Search) = 0);
  if Result then
  begin
    Result := (Search.Attr and (faDirectory or faSymLink)) = 0;
    Size := Search.Size;
    FindClose(Search);
  end;
  {$ENDIF}
end;

function Exists(const FileName: string): Boolean;
var Size: Int64;
begin
  Result := PlainFile(FileName, Size) or FileExists(FileName);
end;

function WKFileBytes(const FileName: string): Int64;
begin
  if not PlainFile(FileName, Result) then Result := 0;
end;

procedure WKFolderBytes(const Dir: string; out Count: Integer; out Bytes: Int64);
var Search: TSearchRec; Size: Int64; Folder: string;
begin
  Count := 0; Bytes := 0;
  if not PlainDir(Dir) then Exit;
  Folder := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(Folder + '*', faAnyFile, Search) = 0 then
  try
    repeat
      if (Search.Name = '.') or (Search.Name = '..') then Continue;
      if PlainFile(Folder + Search.Name, Size) then
      begin
        Inc(Count); Inc(Bytes, Size);
      end;
    until FindNext(Search) <> 0;
  finally
    FindClose(Search);
  end;
end;

function WKDatabaseBytes(const DbFile: string): Int64;
begin
  Result := WKFileBytes(DbFile) + WKFileBytes(DbFile + '-wal');
end;

function WKValidId(const Value: string): Boolean;
var C: Char;
begin
  Result := (Value <> '') and (Length(Value) <= 200);
  if Result then
    for C in Value do
      if (C < ' ') or (C = #127) then Exit(False);
end;

function WKSafeLeaf(const Value: string): Boolean;
var C: Char;
begin
  Result := WKValidId(Value) and (Value <> '.') and (Value <> '..');
  if Result then
    for C in Value do
      if C in ['/', '\', ':'] then Exit(False);
end;

function Inside(const Folder, FileName: string): Boolean;
var Base: string;
begin
  Base := IncludeTrailingPathDelimiter(ExpandFileName(Folder));
  Result := (Length(ExpandFileName(FileName)) > Length(Base)) and
    (Copy(ExpandFileName(FileName), 1, Length(Base)) = Base);
end;

{ ---------------------------------------------------------------- roots and sites }

function WKRoots: TStringArray;
var Text, Part: string; Parts: TStringArray; N: Integer;
begin
  Result := nil;
  Text := StringReplace(GetEnvironmentVariable('WELITE_WEKAN_ROOTS'), #13, '', [rfReplaceAll]);
  Text := StringReplace(Text, #10, ';', [rfReplaceAll]);
  Parts := Text.Split([';']);
  for Part in Parts do
    if Trim(Part) <> '' then
    begin
      N := Length(Result); SetLength(Result, N + 1);
      Result[N] := ExcludeTrailingPathDelimiter(ExpandFileName(Trim(Part)));
    end;
end;

function WKConfigured: Boolean;
begin
  Result := Length(WKRoots) > 0;
end;

// models/lib/filesRoot.js isFilesRoot: WRITABLE_PATH already is the files folder.
function IsFilesRoot(const Base: string): Boolean;
var Name: string;
begin
  Name := ExtractFileName(ExcludeTrailingPathDelimiter(Base));
  Result := (Name = 'files') or (Name = 'wekan-files');
end;

// caddy-wekan-plugin ValidDomain: a lowercase host name, so a folder name can never
// be a path. Anything else under domains/ is not a domain and is not listed.
function ValidDomain(const Value: string): Boolean;
var C: Char; I: Integer;
begin
  Result := (Value <> '') and (Length(Value) <= 253) and (Pos('..', Value) = 0) and
    not (Value[1] in ['.', '-']) and not (Value[Length(Value)] in ['.', '-']);
  if Result then
    for I := 1 to Length(Value) do
    begin
      C := Value[I];
      if not (C in ['a'..'z', '0'..'9', '.', '-']) then Exit(False);
    end;
end;

function HasData(const FilesDir: string): Boolean;
var Dir: string;
begin
  Dir := IncludeTrailingPathDelimiter(FilesDir);
  Result := PlainDir(Dir + 'db') or PlainDir(Dir + 'attachments') or PlainDir(Dir + 'avatars');
end;

procedure AddSite(var Sites: TWKSites; RootIndex: Integer; const Domain, Base, FilesDir: string);
var N: Integer;
begin
  N := Length(Sites); SetLength(Sites, N + 1);
  Sites[N] := Default(TWKSite);
  Sites[N].Root := RootIndex; Sites[N].Domain := Domain;
  Sites[N].Base := Base; Sites[N].FilesDir := ExcludeTrailingPathDelimiter(FilesDir);
end;

// <data>/cloud/domains.json: {"cloudPanelDomain":..., "domains":[{"domain","startDate","endDate"}]}
procedure ReadCloudDomains(const Root: string; var Sites: TWKSites; First: Integer);
var Stream: TFileStream; Text: string; Data: TJSONData; List: TJSONArray; Entry: TJSONData;
  I, J: Integer; Name: string; Size: Int64;
begin
  Text := IncludeTrailingPathDelimiter(Root) + 'cloud' + PathDelim + 'domains.json';
  if not PlainFile(Text, Size) or (Size > 4 * 1024 * 1024) then Exit;
  Data := nil;
  try
    Stream := TFileStream.Create(Text, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Text, Stream.Size);
      if Length(Text) > 0 then Stream.ReadBuffer(Text[1], Length(Text));
    finally Stream.Free; end;
    Data := GetJSON(Text);
    if not (Data is TJSONObject) then Exit;
    List := TJSONObject(Data).Get('domains', TJSONArray(nil));
    if List = nil then Exit;
    for I := 0 to List.Count - 1 do
    begin
      Entry := List.Items[I];
      if not (Entry is TJSONObject) then Continue;
      Name := LowerCase(TJSONObject(Entry).Get('domain', ''));
      for J := First to High(Sites) do
        if Sites[J].Domain = Name then
        begin
          Sites[J].Listed := True;
          Sites[J].StartDate := TJSONObject(Entry).Get('startDate', '');
          Sites[J].EndDate := TJSONObject(Entry).Get('endDate', '');
        end;
    end;
  except
    // A broken domains.json lists nothing; the folders are still shown.
  end;
  Data.Free;
end;

function WKSites: TWKSites;
var Roots, Names: TStringArray; I, First: Integer; Root, Domains: string; Search: TSearchRec;
  List: TStringList;
begin
  Result := nil;
  Roots := WKRoots;
  for I := 0 to High(Roots) do
  begin
    Root := Roots[I];
    if not DirectoryExists(Root) then Continue;
    if IsFilesRoot(Root) then AddSite(Result, I, '', Root, Root)
    else if HasData(IncludeTrailingPathDelimiter(Root) + 'files') then
      AddSite(Result, I, '', Root, IncludeTrailingPathDelimiter(Root) + 'files');
    Domains := IncludeTrailingPathDelimiter(Root) + 'domains';
    if not PlainDir(Domains) then Continue;
    List := TStringList.Create;
    try
      List.Sorted := True;
      if FindFirst(IncludeTrailingPathDelimiter(Domains) + '*', faDirectory, Search) = 0 then
      try
        repeat
          if ValidDomain(Search.Name) and
            PlainDir(IncludeTrailingPathDelimiter(Domains) + Search.Name) and
            PlainDir(IncludeTrailingPathDelimiter(Domains) + Search.Name + PathDelim + 'files') then
            List.Add(Search.Name);
        until FindNext(Search) <> 0;
      finally FindClose(Search); end;
      First := Length(Result);
      Names := List.ToStringArray;
    finally List.Free; end;
    for Root in Names do
      AddSite(Result, I, Root, Domains + PathDelim + Root, Domains + PathDelim + Root + PathDelim + 'files');
    ReadCloudDomains(Roots[I], Result, First);
  end;
end;

function WKFindSite(RootIndex: Integer; const Domain: string; out Site: TWKSite): Boolean;
var Sites: TWKSites; Each: TWKSite;
begin
  Site := Default(TWKSite);
  Sites := WKSites;
  for Each in Sites do
    if (Each.Root = RootIndex) and (Each.Domain = Domain) then
    begin
      Site := Each; Exit(True);
    end;
  Result := False;
end;

function WKDatabases(const Site: TWKSite): TStringArray;
var Dir, Name, Ext: string; Search: TSearchRec; List: TStringList; Size: Int64;
begin
  Result := nil;
  Dir := IncludeTrailingPathDelimiter(Site.FilesDir) + 'db' + PathDelim;
  if not PlainDir(Dir) then Exit;
  List := TStringList.Create;
  try
    List.Sorted := True; List.Duplicates := dupIgnore;
    if FindFirst(Dir + '*', faAnyFile, Search) = 0 then
    try
      repeat
        Ext := LowerCase(ExtractFileExt(Search.Name));
        Name := ChangeFileExt(Search.Name, '');
        // FerretDB pool.go: <name>.sqlite, or <name>.db with dbext=db. local is the
        // oplog's database (server/lib/continuousBackup/sqlite.js leaves it out too).
        if ((Ext = '.sqlite') or (Ext = '.db')) and (Name <> 'local') and WKSafeLeaf(Name) and
          (Name[1] <> '.') and PlainFile(Dir + Search.Name, Size) then
          List.Add(Name);
      until FindNext(Search) <> 0;
    finally FindClose(Search); end;
    Result := List.ToStringArray;
  finally List.Free; end;
end;

function WKDefaultDatabase(const Site: TWKSite): string;
var Names: TStringArray; Name: string;
begin
  Result := '';
  Names := WKDatabases(Site);
  for Name in Names do if Name = 'wekan' then Exit(Name);
  if Length(Names) > 0 then Result := Names[0];
end;

function WKDatabaseFile(const Site: TWKSite; const Name: string): string;
var Names: TStringArray; Each, Dir: string; Size: Int64;
begin
  Result := '';
  Names := WKDatabases(Site);
  Dir := IncludeTrailingPathDelimiter(Site.FilesDir) + 'db' + PathDelim;
  for Each in Names do
    if Each = Name then
    begin
      if PlainFile(Dir + Name + '.sqlite', Size) then Exit(Dir + Name + '.sqlite');
      if PlainFile(Dir + Name + '.db', Size) then Exit(Dir + Name + '.db');
    end;
end;

function WKOpen(const Site: TWKSite; const Name: string): TWKDb;
var FileName: string;
begin
  Result := nil;
  FileName := WKDatabaseFile(Site, Name);
  if FileName = '' then Exit;
  try
    Result := TWKDb.Create(FileName);
  except
    Result := nil;
  end;
end;

{ ---------------------------------------------------------------- read-only database }

function UriPath(const FileName: string): string;
var C: Char; Text: string;
begin
  Text := StringReplace(ExpandFileName(FileName), '\', '/', [rfReplaceAll]);
  if (Text = '') or (Text[1] <> '/') then Text := '/' + Text;
  Result := '';
  for C in Text do
    if C in ['A'..'Z', 'a'..'z', '0'..'9', '/', '.', '_', '-', '~'] then Result := Result + C
    else Result := Result + '%' + IntToHex(Ord(C), 2);
end;

// The read-only URI that opens this file without creating or changing any file
// beside it. FerretDB runs SQLite in WAL mode: while it runs, <db>-wal and <db>-shm
// exist and a mode=ro reader shares them like any other reader. When no WAL exists
// nobody is writing, and immutable=1 reads the file with no locks and no sidecars.
// A hot rollback journal or 8.3 short-name sidecars (wekan.wal) need a recovery or
// an SQLite build this reader may not have, so they are refused rather than guessed.
function ReadOnlyUri(const FileName: string): string;
var Wal, Shm: Boolean;
begin
  if Exists(FileName + '-journal') then
    raise Exception.Create('A rollback journal needs recovery by the writer');
  if Exists(ChangeFileExt(FileName, '.wal')) and not Exists(FileName + '-wal') then
    raise Exception.Create('Short-name WAL sidecars need a matching SQLite build');
  Wal := Exists(FileName + '-wal'); Shm := Exists(FileName + '-shm');
  if Wal and Shm then Result := 'file:' + UriPath(FileName) + '?mode=ro'
  else Result := 'file:' + UriPath(FileName) + '?immutable=1';
end;

function WKLit(const Value: string): string;
begin
  if Pos(#0, Value) > 0 then raise Exception.Create('NUL in an SQL literal');
  Result := '''' + StringReplace(Value, '''', '''''', [rfReplaceAll]) + '''';
end;

function WKField(const Path: string): string;
var Parts: TStringArray; Part, Json: string;
begin
  Parts := Path.Split(['.']);
  Json := '$';
  for Part in Parts do
  begin
    if (Part = '') or (Pos('"', Part) > 0) then raise Exception.Create('Invalid field path');
    Json := Json + '."' + Part + '"';
  end;
  Result := 'json_extract(' + WKDoc + ',' + WKLit(Json) + ')';
end;

function WKNotDeleted: string;
begin
  Result := 'COALESCE(json_type(' + WKDoc + ',''$."deletedAt"''),''null'')=''null''';
end;

function Ident(const Name: string): string;
begin
  Result := '"' + StringReplace(Name, '"', '""', [rfReplaceAll]) + '"';
end;

constructor TWKDb.Create(const DbPath: string);
var Rows: TWLRows; Row: TWLRow; Size: Int64; Head: array[0..15] of Char; Magic: string; Stream: TFileStream;
  {$IFNDEF WLDB_CLI}Code: Integer;{$ENDIF}
begin
  inherited Create;
  FTables := TStringList.Create;
  FTables.Sorted := True; FTables.CaseSensitive := True; FTables.Duplicates := dupIgnore;
  FPath := DbPath;
  if not PlainFile(DbPath, Size) or (Size < 512) then
    raise Exception.Create('Not a database file');
  // Refuse anything that is not an SQLite file before SQLite sees it.
  Stream := TFileStream.Create(DbPath, fmOpenRead or fmShareDenyNone);
  try
    Stream.ReadBuffer(Head, SizeOf(Head));
  finally Stream.Free; end;
  SetString(Magic, PChar(@Head[0]), SizeOf(Head));
  if Magic <> 'SQLite format 3'#0 then raise Exception.Create('Not an SQLite database');
  FUri := ReadOnlyUri(DbPath);
  {$IFNDEF WLDB_CLI}
  Code := sqlite3_open_v2(PChar(FUri), @FHandle, SQLITE_OPEN_READONLY or SQLITE_OPEN_URI, nil);
  if Code <> SQLITE_OK then raise Exception.Create('Cannot open the database read-only');
  sqlite3_busy_timeout(FHandle, 3000);
  {$ENDIF}
  {$IFNDEF WLDB_CLI}
  if sqlite3_exec(FHandle, 'PRAGMA query_only=ON;', nil, nil, nil) <> SQLITE_OK then
    raise Exception.Create('Cannot make the connection query-only');
  {$ENDIF}
  if not Run('SELECT name AS n,table_name AS t FROM _ferretdb_collections WHERE table_name IN ' +
    '(SELECT name FROM sqlite_master WHERE type=''table'');', Rows) then
    raise Exception.Create('Not a FerretDB SQLite database');
  for Row in Rows do
    if (Length(Row) = 2) and (Row[0] <> '') and (Row[1] <> '') then
      FTables.Values[Row[0]] := Row[1];
end;

destructor TWKDb.Destroy;
begin
  {$IFNDEF WLDB_CLI}
  if FHandle <> nil then sqlite3_close(FHandle);
  {$ENDIF}
  FTables.Free;
  inherited Destroy;
end;

{$IFDEF WLDB_CLI}
function CellText(Value: TJSONData): string;
begin
  case Value.JSONType of
    jtNull: Result := '';
    jtBoolean: if Value.AsBoolean then Result := '1' else Result := '0';
    jtNumber:
      if Value is TJSONFloatNumber then Result := FloatToStr(Value.AsFloat)
      else Result := IntToStr(Value.AsInt64);
  else
    Result := Value.AsString;
  end;
end;

function TWKDb.Run(const Sql: string; out Rows: TWLRows): Boolean;
var Output: string; Data: TJSONData; I, J: Integer; Obj: TJSONObject;
begin
  Rows := nil; Result := False;
  if FUri = '' then Exit;
  // -init with an empty file keeps a user's ~/.sqliterc out of the output format.
  try
    if not RunCommand('sqlite3', ['-init', {$IFDEF UNIX}'/dev/null'{$ELSE}'NUL'{$ENDIF},
      '-readonly', '-batch', '-bail', '-json', FUri, Sql], Output, [poNoConsole]) then Exit;
  except
    Exit;
  end;
  if Trim(Output) = '' then Exit(True);
  Data := nil;
  try
    try
      Data := GetJSON(Output);
      if not (Data is TJSONArray) then Exit;
      SetLength(Rows, Data.Count);
      for I := 0 to Data.Count - 1 do
      begin
        if not (Data.Items[I] is TJSONObject) then Exit;
        Obj := TJSONObject(Data.Items[I]);
        SetLength(Rows[I], Obj.Count);
        for J := 0 to Obj.Count - 1 do Rows[I][J] := CellText(Obj.Items[J]);
      end;
      Result := True;
    except
      Rows := nil; Result := False;
    end;
  finally Data.Free; end;
end;
{$ELSE}
function TWKDb.Run(const Sql: string; out Rows: TWLRows): Boolean;
var Stmt: Pointer; Cols, C, N, Step: Integer; Text: PAnsiChar;
begin
  Rows := nil; Result := False;
  if FHandle = nil then Exit;
  if sqlite3_prepare_v2(FHandle, PChar(Sql), -1, @Stmt, nil) <> SQLITE_OK then Exit;
  try
    // The connection is read-only and query-only; refuse a writer all the same.
    if sqlite3_stmt_readonly(Stmt) = 0 then Exit;
    Cols := sqlite3_column_count(Stmt);
    N := 0;
    Step := sqlite3_step(Stmt);
    while Step = SQLITE_ROW do
    begin
      SetLength(Rows, N + 1); SetLength(Rows[N], Cols);
      for C := 0 to Cols - 1 do
      begin
        Text := sqlite3_column_text(Stmt, C);
        if Text = nil then Rows[N][C] := ''
        else SetString(Rows[N][C], Text, sqlite3_column_bytes(Stmt, C));
      end;
      Inc(N);
      Step := sqlite3_step(Stmt);
    end;
    Result := Step = SQLITE_DONE;
  finally
    sqlite3_finalize(Stmt);
  end;
end;
{$ENDIF}

function TWKDb.Query(const Sql: string): TWLRows;
begin
  if not Run(Sql, Result) then raise Exception.Create('The WeKan database could not be read');
end;

function TWKDb.Table(const Collection: string): string;
begin
  Result := FTables.Values[Collection];
end;

function TWKDb.From(const Collection: string): string;
begin
  Result := Table(Collection);
  if Result <> '' then Result := Ident(Result);
end;

function TWKDb.Count(const Collection, Where: string): Int64;
var Sql: string; Rows: TWLRows;
begin
  Result := 0;
  if Table(Collection) = '' then Exit;
  Sql := 'SELECT count(*) AS n FROM ' + From(Collection);
  if Where <> '' then Sql := Sql + ' WHERE ' + Where;
  Rows := Query(Sql + ';');
  if (Length(Rows) = 1) and (Length(Rows[0]) = 1) then Result := StrToInt64Def(Rows[0][0], 0);
end;

function TWKDb.Docs(const Collection, Where: string; const Order: string): TJSONArray;
var TableName, Sql: string; Rows: TWLRows; Row: TWLRow; Data: TJSONData;
begin
  Result := TJSONArray.Create;
  TableName := Table(Collection);
  if TableName = '' then Exit;
  Sql := 'SELECT json(' + WKDoc + ') AS d FROM ' + Ident(TableName);
  if Where <> '' then Sql := Sql + ' WHERE ' + Where;
  if Order <> '' then Sql := Sql + ' ORDER BY ' + Order;
  try
    Rows := Query(Sql + ';');
  except
    Result.Free; raise;
  end;
  for Row in Rows do
  begin
    Data := nil;
    try
      Data := GetJSON(PlainDocument(Row[0]));
      if Data is TJSONObject then begin Result.Add(Data); Data := nil; end
      else Inc(FSkipped);
    except
      Inc(FSkipped);
    end;
    Data.Free;
  end;
end;

{ ---------------------------------------------------------------- JSON helpers }

function WKValue(Obj: TJSONObject; const Path: string): TJSONData;
var Parts: TStringArray; Part: string; Current: TJSONData;
begin
  Result := nil;
  if Obj = nil then Exit;
  Current := Obj;
  Parts := Path.Split(['.']);
  for Part in Parts do
  begin
    if not (Current is TJSONObject) then Exit(nil);
    Current := TJSONObject(Current).Find(Part);
    if Current = nil then Exit(nil);
  end;
  Result := Current;
end;

function WKStr(Obj: TJSONObject; const Path: string): string;
var Value: TJSONData;
begin
  Value := WKValue(Obj, Path);
  if (Value <> nil) and (Value.JSONType = jtString) then Result := Value.AsString else Result := '';
end;

function WKBool(Obj: TJSONObject; const Path: string): Boolean;
var Value: TJSONData;
begin
  Value := WKValue(Obj, Path);
  Result := (Value <> nil) and (Value.JSONType = jtBoolean) and Value.AsBoolean;
end;

function WKNum(Obj: TJSONObject; const Path: string): Double;
var Value: TJSONData;
begin
  Value := WKValue(Obj, Path);
  if (Value <> nil) and (Value.JSONType = jtNumber) then Result := Value.AsFloat else Result := 0;
end;

function WKArr(Obj: TJSONObject; const Path: string): TJSONArray;
var Value: TJSONData;
begin
  Value := WKValue(Obj, Path);
  if Value is TJSONArray then Result := TJSONArray(Value) else Result := nil;
end;

function WKDate(Value: TJSONData): string;
var Ms: Int64;
begin
  Result := '';
  if Value = nil then Exit;
  case Value.JSONType of
    jtNumber:
      begin
        Ms := Trunc(Value.AsFloat);
        Result := FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(Ms div 1000, True)) + ' UTC';
      end;
    jtString: Result := Copy(Value.AsString, 1, 64);
  end;
end;

function DocCompare(A, B: TJSONObject): Integer;
var X, Y: Double;
begin
  X := WKNum(A, 'sort'); Y := WKNum(B, 'sort');
  if X < Y then Exit(-1);
  if X > Y then Exit(1);
  Result := CompareStr(WKStr(A, 'title'), WKStr(B, 'title'));
  if Result = 0 then Result := CompareStr(WKStr(A, '_id'), WKStr(B, '_id'));
end;

procedure WKSortDocs(Docs: TJSONArray);
var I, J: Integer;
begin
  // Insertion sort with swaps keeps ownership inside the array.
  for I := 1 to Docs.Count - 1 do
  begin
    J := I;
    while (J > 0) and (DocCompare(Docs.Objects[J - 1], Docs.Objects[J]) > 0) do
    begin
      Docs.Exchange(J - 1, J);
      Dec(J);
    end;
  end;
end;

{ ---------------------------------------------------------------- attachments }

function WKAttachmentFile(const Site: TWKSite; Doc: TJSONObject; out Reason: string): string;
var Dir, Id, Name, Ext, Storage, Recorded, Leaf, Candidate: string; Leaves: TStringList;
  Search: TSearchRec; Size: Int64; I: Integer;
  procedure Add(const Value: string);
  begin
    if WKSafeLeaf(Value) and (Leaves.IndexOf(Value) < 0) then Leaves.Add(Value);
  end;
  function LeafOf(const Value: string): string;
  var At: Integer;
  begin
    Result := StringReplace(Value, '\', '/', [rfReplaceAll]);
    At := RPos('/', Result);
    if At > 0 then Result := Copy(Result, At + 1, MaxInt);
  end;
begin
  Result := ''; Reason := 'missing';
  Storage := WKStr(Doc, 'versions.original.storage');
  // fileStoreStrategy.js: 'fs' is the filesystem; gridfs, s3 and the cloud
  // strategies keep the bytes in the database or object storage.
  if (Storage <> '') and (Storage <> 'fs') then begin Reason := 'storage'; Exit; end;
  Dir := IncludeTrailingPathDelimiter(Site.FilesDir) + 'attachments';
  if not PlainDir(Dir) then Exit;
  Dir := IncludeTrailingPathDelimiter(Dir);
  Id := WKStr(Doc, '_id'); Name := WKStr(Doc, 'name'); Ext := WKStr(Doc, 'extension');
  Recorded := WKStr(Doc, 'versions.original.path');
  Leaves := TStringList.Create;
  try
    Leaves.CaseSensitive := True;
    // The candidates of fileStoreStrategy.js candidatePaths(), as names in this
    // folder only: the recorded path's base name, <id>.<ext>, <id>, and the old
    // <id>-original-<name>; a recorded absolute path is the origin server's own.
    if Recorded <> '' then Add(LeafOf(Recorded));
    if WKStr(Doc, 'path') <> '' then Add(LeafOf(WKStr(Doc, 'path')));
    if WKSafeLeaf(Id) then
    begin
      if Ext <> '' then Add(Id + '.' + Ext);
      Add(Id);
      if Name <> '' then Add(Id + '-original-' + LeafOf(Name));
      if (Pos('*', Id) = 0) and (Pos('?', Id) = 0) and (Pos('[', Id) = 0) and
        (FindFirst(Dir + Id + '-original-*', faAnyFile, Search) = 0) then
      try
        if Copy(Search.Name, 1, Length(Id) + 10) = Id + '-original-' then Add(Search.Name);
      finally FindClose(Search); end;
    end;
    for I := 0 to Leaves.Count - 1 do
    begin
      Leaf := Leaves[I];
      Candidate := Dir + Leaf;
      if Inside(Dir, Candidate) and PlainFile(Candidate, Size) then Exit(Candidate);
    end;
  finally Leaves.Free; end;
end;

end.
