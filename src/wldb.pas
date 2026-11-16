unit wldb;

{
  WeKan-Lite — SQLite access behind one interface (see docs/sqlite.md)

  Two backends, chosen at compile time, so endpoints never care which is built in:

    default          : linked SQLite via FPC's `sqlite3` binding (single binary, G1/G3)
    {$DEFINE WLDB_CLI}: shell out to the `sqlite3` CLI via TProcess (omi-style bootstrap)

  Surface kept deliberately tiny: open/close, an Exec for writes, and a Query that returns
  rows as arrays of text cells. v0.1 reference skeleton — the linked path
  shows intent (real code uses sqlite3_prepare_v2 / bound params; the CLI path mirrors
  https://github.com/wekan/omi/blob/main/public/server.pas ExecSqlOnDb).
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, Classes
  {$IFDEF WLDB_CLI}, Process {$ELSE}, sqlite3 {$ENDIF};

type
  TWLDb = class;                       // opaque to callers (tenant just holds a reference)

  TWLRow   = array of string;
  TWLRows  = array of TWLRow;

  TWLDb = class
  private
    FPath: string;
    {$IFNDEF WLDB_CLI}
    FHandle: Pointer;                  // psqlite3
    {$ENDIF}
  public
    constructor Create(const APath: string);
    destructor Destroy; override;
    // Parameterless write (DDL/INSERT/UPDATE). Returns False on error.
    function Exec(const Sql: string): Boolean;
    // Read query. SQL must already be a complete statement; returns rows of text cells.
    function Query(const Sql: string): TWLRows;
    property Path: string read FPath;
  end;

function WLDbOpen(const APath: string): TWLDb;
procedure WLDbClose(Db: TWLDb);

// SQL string-literal escaping. ONLY for the CLI backend; the linked backend uses bound
// params and must not call this (kept here so callers building ad-hoc SQL share one impl).
function SqlEscape(const Value: string): string;

implementation

function SqlEscape(const Value: string): string;
begin
  Result := StringReplace(Value, '''', '''''', [rfReplaceAll]);
end;

function WLDbOpen(const APath: string): TWLDb;
begin
  try
    Result := TWLDb.Create(APath);
  except
    Result := nil;
  end;
end;

procedure WLDbClose(Db: TWLDb);
begin
  Db.Free;
end;

{ TWLDb }

constructor TWLDb.Create(const APath: string);
begin
  inherited Create;
  FPath := APath;
  {$IFNDEF WLDB_CLI}
  if sqlite3_open(PChar(FPath), @FHandle) <> SQLITE_OK then
    raise Exception.CreateFmt('wldb: cannot open %s', [FPath]);
  // recommended pragmas for a single-writer embedded server
  Exec('PRAGMA foreign_keys = ON;');
  // WAL needs shared-memory/mmap, which classic Amiga filesystems don't provide; fall back to
  // the portable rollback journal there (see docs/sqlite.md).
  {$IF DEFINED(AMIGA) or DEFINED(MORPHOS) or DEFINED(AROS)}
  Exec('PRAGMA journal_mode = DELETE;');
  {$ELSE}
  Exec('PRAGMA journal_mode = WAL;');
  {$ENDIF}
  {$ENDIF}
end;

destructor TWLDb.Destroy;
begin
  {$IFNDEF WLDB_CLI}
  if FHandle <> nil then
    sqlite3_close(FHandle);
  {$ENDIF}
  inherited Destroy;
end;

{$IFDEF WLDB_CLI}
// --- Backend A: external sqlite3 CLI (mirrors omi ExecSqlOnDb) -----------------------------
function RunSqlite(const DbPath, Sql: string; out Output: string): Boolean;
begin
  Output := '';
  try
    // RunCommand drains both pipes while the child is running, avoiding deadlocks on
    // large query output. It checks the child exit status and keeps stderr separate.
    // Leading whitespace keeps schema comments (-- ...) from becoming CLI options.
    Result := RunCommand('sqlite3', ['-batch', '-bail', '-csv', '-noheader',
      '-cmd', 'PRAGMA foreign_keys=ON', ExpandFileName(DbPath), ' '+Sql], Output);
  except
    Result := False;
  end;
  if not Result then Output := '';
end;

function TWLDb.Exec(const Sql: string): Boolean;
var Ignored: string;
begin
  Result := RunSqlite(FPath, Sql, Ignored);
end;

function TWLDb.Query(const Sql: string): TWLRows;
var Raw, Cell: string; Row: TWLRow; i, n: Integer; InQuotes: Boolean;
  procedure AddCell;
  begin
    n:=Length(Row); SetLength(Row,n+1); Row[n]:=Cell; Cell:='';
  end;
  procedure AddRow;
  begin
    AddCell;
    n:=Length(Result); SetLength(Result,n+1); Result[n]:=Row;
    Row:=nil;
  end;
begin
  Result:=nil; Row:=nil;
  if not RunSqlite(FPath,Sql,Raw) or (Raw='') then Exit;
  // SQLite CSV quotes commas, quotes and embedded newlines. Preserve bytes inside
  // quotes, including CRLF: text must round-trip identically to the linked backend.
  i:=1; Cell:=''; InQuotes:=False;
  while i<=Length(Raw) do
  begin
    case Raw[i] of
      '"':
        if InQuotes and (i<Length(Raw)) and (Raw[i+1]='"') then
        begin Cell:=Cell+'"'; Inc(i); end
        else InQuotes:=not InQuotes;
      ',': if InQuotes then Cell:=Cell+Raw[i] else AddCell;
      #10,#13:
        if InQuotes then Cell:=Cell+Raw[i]
        else
        begin
          AddRow;
          if (Raw[i]=#13) and (i<Length(Raw)) and (Raw[i+1]=#10) then Inc(i);
        end;
    else Cell:=Cell+Raw[i];
    end;
    Inc(i);
  end;
  if (Length(Cell)>0) or (Length(Row)>0) then AddRow;
end;
{$ELSE}
// --- Backend B: linked SQLite (production default) ----------------------------------------
function TWLDb.Exec(const Sql: string): Boolean;
var
  ErrMsg: PChar;
begin
  ErrMsg := nil;
  Result := sqlite3_exec(FHandle, PChar(Sql), nil, nil, @ErrMsg) = SQLITE_OK;
  if ErrMsg <> nil then
    sqlite3_free(ErrMsg);
end;

function TWLDb.Query(const Sql: string): TWLRows;
var
  Stmt: Pointer;
  Cols, c, n: Integer;
begin
  SetLength(Result, 0);
  // Real code prepares once and binds params; this skeleton runs a literal statement.
  if sqlite3_prepare_v2(FHandle, PChar(Sql), -1, @Stmt, nil) <> SQLITE_OK then
    Exit;
  try
    Cols := sqlite3_column_count(Stmt);
    n := 0;
    while sqlite3_step(Stmt) = SQLITE_ROW do
    begin
      SetLength(Result, n + 1);
      SetLength(Result[n], Cols);
      for c := 0 to Cols - 1 do
        Result[n][c] := string(sqlite3_column_text(Stmt, c));
      Inc(n);
    end;
  finally
    sqlite3_finalize(Stmt);
  end;
end;
{$ENDIF}

end.
