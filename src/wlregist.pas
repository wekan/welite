unit wlregist;

{
  WeKan-Lite — domain registry (docs/goals.md G8, the Global Admin's data store)

  Backed by data/admin/files/db/wekan.db. Holds the host -> tenant mapping that the Global Admin
  edits (create/rename/disable a domain, aliases). wltenant.pas consults this on every
  request to decide whether a Host: is a served tenant.

  The registry lives in the reserved `admin` tenant, NOT in any served domain's data.db, so
  one binary can route many domains while each domain's own data stays isolated.

  Schema (created on first run if absent):

    CREATE TABLE domains (
      host       TEXT PRIMARY KEY,   -- normalized: lowercase, no port, no leading www.
      enabled    INTEGER NOT NULL DEFAULT 1,
      createdAt  TEXT NOT NULL,
      modifiedAt TEXT
    );
    CREATE TABLE domain_aliases (
      alias  TEXT PRIMARY KEY,       -- alternate host that maps to canonical `host`
      host   TEXT NOT NULL REFERENCES domains(host) ON DELETE CASCADE
    );

  v0.1 reference skeleton. Uses wldb (same SQLite backend as tenants). A production build
  would cache the enabled-set in memory and invalidate on Global Admin edits; here every
  lookup hits the admin DB for simplicity.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, wldb;

// Open the admin registry DB and ensure its schema exists. Call once from TenantInit.
procedure RegistryInit(const AdminDbPath: string);

// True if `host` (already normalized) is a known, enabled tenant — directly or via an alias.
function RegistryHostEnabled(const Host: string): Boolean;

// Resolve an alias to its canonical host (returns Host unchanged if it is already canonical).
function RegistryCanonicalHost(const Host: string): string;

// Canonical DNS host only; never a path, loopback alias or reserved tenant name.
function RegistryValidHost(const Host: string): Boolean;

// Register / enable / disable a domain (Global Admin operations).
function RegistryAddDomain(const Host: string): Boolean;
function RegistrySetEnabled(const Host: string; Enabled: Boolean): Boolean;

// Stable short directory key of a canonical domain (aliases share its mapping).
function RegistryStorageKey(const Host:string):string;
// All registered domains as rows of (host, enabled, createdAt), for the Global Admin panel.
function RegistryListDomains: TWLRows;

implementation

uses
  DateUtils;

var
  AdminDb: TWLDb = nil;

function NowIso: string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Now);
end;

procedure RegistryInit(const AdminDbPath: string);
begin
  if AdminDb <> nil then
    Exit;
  // The admin tenant dir/db is expected to exist (created by the Global Admin bootstrap).
  AdminDb := TWLDb.Create(AdminDbPath);
  if AdminDb = nil then
    Exit;
  AdminDb.Exec(
    'CREATE TABLE IF NOT EXISTS domains (' +
    '  host TEXT PRIMARY KEY,' +
    '  enabled INTEGER NOT NULL DEFAULT 1,' +
    '  createdAt TEXT NOT NULL,' +
    '  modifiedAt TEXT);');
  AdminDb.Exec(
    'CREATE TABLE IF NOT EXISTS domain_aliases (' +
    '  alias TEXT PRIMARY KEY,' +
    '  host TEXT NOT NULL REFERENCES domains(host) ON DELETE CASCADE);');
  if not AdminDb.Exec('CREATE TABLE IF NOT EXISTS tenantdirs(id INTEGER PRIMARY KEY AUTOINCREMENT CHECK(id BETWEEN 1 AND 268435455),host TEXT NOT NULL UNIQUE); INSERT INTO tenantdirs(host) SELECT host FROM domains WHERE host NOT IN (SELECT host FROM tenantdirs) ORDER BY host;') then
    raise Exception.Create('Could not initialize tenant directory mapping');
end;

function RegistryCanonicalHost(const Host: string): string;
var
  Rows: TWLRows;
begin
  Result := Host;
  if AdminDb = nil then Exit;
  Rows := AdminDb.Query(Format(
    'SELECT host FROM domain_aliases WHERE alias=%s LIMIT 1;', [QuotedStr(Host)]));
  if (Length(Rows) > 0) and (Length(Rows[0]) > 0) and (Rows[0][0] <> '') then
    Result := Rows[0][0];
end;

function RegistryHostEnabled(const Host: string): Boolean;
var
  Canonical: string;
  Rows: TWLRows;
begin
  Result := False;
  if AdminDb = nil then Exit;
  Canonical := RegistryCanonicalHost(Host);
  Rows := AdminDb.Query(Format(
    'SELECT enabled FROM domains WHERE host=%s LIMIT 1;', [QuotedStr(Canonical)]));
  Result := (Length(Rows) > 0) and (Length(Rows[0]) > 0) and (Rows[0][0] = '1');
end;

function RegistryValidHost(const Host: string): Boolean;
var i, Start: Integer;
begin
  Result:=False;
  if (Host='') or (Length(Host)>253) or (Host<>LowerCase(Host)) or
    (Host='admin') or (Host='local') or (Host='localhost') or (Host='127.0.0.1') then Exit;
  Start:=1;
  for i:=1 to Length(Host)+1 do
  begin
    if (i>Length(Host)) or (Host[i]='.') then
    begin
      if (i=Start) or (i-Start>63) or (Host[Start]='-') or (Host[i-1]='-') then Exit;
      Start:=i+1;
    end
    else if not (Host[i] in ['a'..'z','0'..'9','-']) then Exit;
  end;
  Result:=True;
end;

function RegistryAddDomain(const Host: string): Boolean;
begin
  Result := False;
  if (AdminDb=nil) or not RegistryValidHost(Host) then Exit;
  Result := AdminDb.Exec(Format(
    'BEGIN IMMEDIATE; INSERT OR IGNORE INTO domains(host,enabled,createdAt) VALUES(%s,1,%s); INSERT INTO tenantdirs(host) VALUES(%s) ON CONFLICT(host) DO NOTHING; COMMIT;',
    [QuotedStr(Host), QuotedStr(NowIso),QuotedStr(Host)]));
  if not Result then AdminDb.Exec('ROLLBACK;');
end;

function RegistrySetEnabled(const Host: string; Enabled: Boolean): Boolean;
var
  Flag: Integer;
begin
  Result := False;
  if AdminDb = nil then Exit;
  if Enabled then Flag := 1 else Flag := 0;
  Result := AdminDb.Exec(Format(
    'UPDATE domains SET enabled=%d, modifiedAt=%s WHERE host=%s;',
    [Flag, QuotedStr(NowIso), QuotedStr(Host)]));
end;

function RegistryStorageKey(const Host:string):string;
var R:TWLRows; N:LongInt;
begin
  Result:='';if AdminDb=nil then Exit;
  R:=AdminDb.Query('SELECT id FROM tenantdirs WHERE host='+QuotedStr(RegistryCanonicalHost(Host))+';');
  if Length(R)<>1 then Exit;
  N:=StrToIntDef(R[0][0],0);if (N<1) or (N>268435455) then Exit;
  Result:='d'+LowerCase(IntToHex(N,7));
end;

function RegistryListDomains: TWLRows;
begin
  SetLength(Result, 0);
  if AdminDb = nil then Exit;
  Result := AdminDb.Query('SELECT host, enabled, createdAt FROM domains ORDER BY host;');
end;

finalization
  if Assigned(AdminDb) then
    WLDbClose(AdminDb);

end.
