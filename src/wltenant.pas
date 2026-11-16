unit wltenant;

{
  WeKan-Lite — tenant resolution (multitenancy by domain, docs/goals.md G8)

  Maps the HTTP Host: header to a per-tenant directory and SQLite database:

    data/admin/files/db/wekan.db                         reserved Global Admin tenant
    data/domains/<key>/files/db/wekan.db              one served tenant per domain
    data/domains/<key>/files/{attachme,avatars}/
    data/certs/<key>/                            TLS material (central, Caddy-style)

  A single WeKan-Lite binary serves every domain; the Global Admin (data/admin) manages
  them. There is no shared database — isolation is structural (one SQLite file per tenant).

  This unit is a v0.1 reference skeleton distilled from the single-tenant prototypes
  https://github.com/wekan/wami/blob/main/wekan.pas and https://github.com/wekan/omi/blob/main/public/server.pas, extended with the host->dir routing those
  prototypes lack. The DB handle type is intentionally opaque (TWLDb from wldb.pas).
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, Classes, HTTPDefs, wldb;

const
  ADMIN_TENANT = 'admin';   // reserved; never a served public domain
  LOCAL_TENANT = 'local';   // loopback (localhost/127.0.0.1/::1) -> data/local, no registry needed

type
  TWLTenant = record
    Host    : string;       // normalized host key, e.g. 'wekan.example.com' or 'admin'
    Dir     : string;       // data/domains/<key>/  (or data/admin/)
    DbPath  : string;       // <Dir>files/db/wekan.db
    FilesDir: string;       // <Dir>files/
    IsAdmin : Boolean;      // True for the data/admin tenant
    Db      : TWLDb;        // cached open handle (see TenantOpen)
  end;

// Normalize a raw Host header to a tenant key: lowercase, strip :port and leading 'www.'.
function NormalizeHost(const RawHost: string): string;

// Resolve a request's Host header to a tenant. Returns False for unknown/disabled domains
// (caller should answer 404 — never fall back into another tenant's data).
function ResolveTenant(ARequest: TRequest; out Tenant: TWLTenant): Boolean;

// Open (and cache) the tenant's SQLite handle. Idempotent; returns the cached handle.
function TenantOpen(var Tenant: TWLTenant): Boolean;

// Provision an explicitly enabled domain, or the reserved admin tenant for local bootstrap.
function ProvisionTenant(const Host: string): Boolean;

// Absolute path to the central TLS cert dir for a host: data/certs/<key>/
function TenantCertDir(const Host: string): string;

// Atomically allocate a new short directory data/temp/t<7 hex digits>/.
// Existing directories are skipped across process restarts; Op is retained for callers.
function WLTempDir(const Op: string = ''): string;

// Call once at startup to set the data/ root and load the domain registry.
procedure TenantInit(const ADataRoot: string);

implementation

uses
  wlregist;   // domain registry lookup (host -> enabled?), backed by data/admin/files/db/wekan.db

var
  DataRoot   : string;                 // absolute path to data/
  SchemaPath : string;                 // tenant schema applied when provisioning a fresh db
  HandleCache: TStringList = nil;      // host -> TWLDb (as Pointer), pooled across requests
  TempCounter: Integer = 0;            // process-global, atomically bumped per temp op

function WLTempDir(const Op: string = ''): string;
var
  Stamp: string;
  Root:string;
  N: Integer;
begin
  N := InterLockedIncrement(TempCounter);
  Root:=DataRoot+'temp'+PathDelim;
  if not ForceDirectories(Root) then raise Exception.Create('Could not create temporary root');
  repeat
    Stamp:='t'+LowerCase(IntToHex(N and $0fffffff,7));
    Result:=Root+Stamp+PathDelim;
    if CreateDir(ExcludeTrailingPathDelimiter(Result)) then Exit;
    if not DirectoryExists(Result) then raise Exception.Create('Could not create temporary directory');
    N:=InterLockedIncrement(TempCounter);
  until False;
end;

procedure TenantInit(const ADataRoot: string);
begin
  DataRoot := IncludeTrailingPathDelimiter(ExpandFileName(ADataRoot));
  if HandleCache = nil then
  begin
    HandleCache := TStringList.Create;
    HandleCache.CaseSensitive := False;
    HandleCache.Sorted := True;        // binary search on host key
  end;
  // Tenant schema (users/boards/...), applied once to provision a fresh tenant db. Configurable
  // so a release that ships schema.sql elsewhere still finds it; defaults to the repo layout.
  SchemaPath := GetEnvironmentVariable('WELITE_SCHEMA');
  if SchemaPath = '' then
  begin
    SchemaPath := 'src' + PathDelim + 'schema.sql';
    if not FileExists(SchemaPath) then SchemaPath := 'schema.sql';
  end;
  // The Global Admin registry lives in data/admin; ensure its dir exists before opening the db
  // (sqlite3_open creates the file, not the parent directory).
  if FileExists(DataRoot+'admin'+PathDelim+'db'+PathDelim+'data.db') or
    FileExists(DataRoot+'local'+PathDelim+'db'+PathDelim+'data.db') then
    raise Exception.Create('Legacy paths detected; stop the server and run releases/pathmove.py first');
  ForceDirectories(DataRoot+ADMIN_TENANT+PathDelim+'files'+PathDelim+'db');
  RegistryInit(DataRoot+ADMIN_TENANT+PathDelim+'files'+PathDelim+'db'+PathDelim+'wekan.db');
end;

function NormalizeHost(const RawHost: string): string;
var
  ColonPos: Integer;
begin
  Result := LowerCase(Trim(RawHost));
  // strip port (host:443) — but leave bracketed IPv6 literals alone
  if (Result <> '') and (Result[1] <> '[') then
  begin
    ColonPos := Pos(':', Result);
    if ColonPos > 0 then
      Result := Copy(Result, 1, ColonPos - 1);
  end;
  if (Copy(Result,1,1)='[') and (Pos(']',Result)>0) then
    Result:=Copy(Result,1,Pos(']',Result));
  // optional www. canonicalization
  if Copy(Result, 1, 4) = 'www.' then
    Result := Copy(Result, 5, Length(Result));
end;

function TenantDir(const Host: string): string;
var Key:string;
begin
  if SameText(Host, ADMIN_TENANT) then
    Result := DataRoot + ADMIN_TENANT + PathDelim
  else if SameText(Host, LOCAL_TENANT) then
    Result := DataRoot + LOCAL_TENANT + PathDelim   // data/local (not data/domains/local)
  else
  begin
    Key:=RegistryStorageKey(Host);
    if Key='' then raise Exception.Create('Missing tenant directory mapping');
    if FileExists(DataRoot+'domains'+PathDelim+Host+PathDelim+'db'+PathDelim+'data.db') then
      raise Exception.Create('Legacy domain paths detected; run releases/pathmove.py offline');
    Result:=DataRoot+'domains'+PathDelim+Key+PathDelim;
  end;
end;

// Loopback access (browsing http://localhost:5500/) maps to the single built-in `local` tenant,
// so a fresh checkout works without registering any domain in the Global Admin registry.
function IsLocalHost(const Host: string): Boolean;
begin
  Result:=SameText(Host,'localhost') or SameText(Host,LOCAL_TENANT) or
    (Host='127.0.0.1') or (Host='::1') or (Host='[::1]');
end;

function LoadSchemaSql: string;
var SL: TStringList;
begin
  Result := '';
  if (SchemaPath = '') or (not FileExists(SchemaPath)) then Exit;
  SL := TStringList.Create;
  try
    SL.LoadFromFile(SchemaPath);
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

// Create files/db/, files/attachme/ and files/avatars/ and, the first
// time, its SQLite db with the schema applied. Idempotent; safe to call on every request.
function EnsureTenantStore(const Tenant: TWLTenant): Boolean;
var Db: TWLDb; Sql: string; R: TWLRows;
begin
  Result:=False;
  ForceDirectories(Tenant.FilesDir+'db');
  ForceDirectories(Tenant.FilesDir+'attachme');
  ForceDirectories(Tenant.FilesDir+'avatars');
  Db:=WLDbOpen(Tenant.DbPath);
  if Db=nil then Exit;
  try
    R:=Db.Query('SELECT name FROM sqlite_master WHERE type=''table'' AND name=''users'';');
    if Length(R)>0 then Exit(True);
    Sql:=LoadSchemaSql;
    if Sql='' then Exit;
    Result:=Db.Exec('BEGIN IMMEDIATE; '+Sql+' COMMIT;');
    if not Result then Db.Exec('ROLLBACK;');
  finally WLDbClose(Db); end;
end;

function ProvisionTenant(const Host: string): Boolean;
var T: TWLTenant; Key: string;
begin
  Result:=False;
  Key:=NormalizeHost(Host);
  if (Key<>ADMIN_TENANT) and not RegistryHostEnabled(Key) then Exit;
  if Key<>ADMIN_TENANT then Key:=RegistryCanonicalHost(Key);
  T:=Default(TWLTenant);
  T.Host:=Key; T.Dir:=TenantDir(Key); T.FilesDir:=T.Dir+'files'+PathDelim;
  T.DbPath:=T.FilesDir+'db'+PathDelim+'wekan.db';
  Result:=EnsureTenantStore(T);
end;

function TenantCertDir(const Host: string): string;
begin
  if (Host=ADMIN_TENANT) or (Host=LOCAL_TENANT) then Result:=Host
  else Result:=RegistryStorageKey(Host);
  if Result='' then raise Exception.Create('Unknown certificate tenant');
  Result:=DataRoot+'certs'+PathDelim+Result+PathDelim;
end;

function ResolveTenant(ARequest: TRequest; out Tenant: TWLTenant): Boolean;
var
  Host, Key: string;
  AutoProvision: Boolean;
begin
  Result := False;
  FillChar(Tenant, SizeOf(Tenant), 0);

  Host := NormalizeHost(ARequest.Host);
  if Host = '' then
    Exit;

  AutoProvision := False;
  if SameText(Host, ADMIN_TENANT) then
    // 'admin' host is reserved for the Global Admin tenant; it must be configured, not guessed.
    Key := ADMIN_TENANT
  else if IsLocalHost(Host) then
    // loopback -> the built-in `local` tenant, created on demand (no registry entry required)
    begin Key := LOCAL_TENANT; AutoProvision := True; end
  else if RegistryHostEnabled(Host) then       // unknown or disabled -> 404, no fallback
    Key := RegistryCanonicalHost(Host)
  else
    Exit;

  Tenant.Host     := Key;
  Tenant.IsAdmin  := SameText(Key, ADMIN_TENANT);
  Tenant.Dir      := TenantDir(Key);
  Tenant.FilesDir := Tenant.Dir + 'files' + PathDelim;
  Tenant.DbPath:=Tenant.FilesDir+'db'+PathDelim+'wekan.db';

  if AutoProvision and not EnsureTenantStore(Tenant) then Exit;

  Result := DirectoryExists(Tenant.Dir) and FileExists(Tenant.DbPath);
end;

function TenantOpen(var Tenant: TWLTenant): Boolean;
var
  Idx: Integer;
begin
  // reuse a pooled handle if this tenant is already open (linked SQLite backend only;
  // the CLI backend in wldb.pas re-spawns per query and ignores the cache)
  Idx := HandleCache.IndexOf(Tenant.Host);
  if Idx >= 0 then
  begin
    Tenant.Db := TWLDb(HandleCache.Objects[Idx]);
    Exit(True);
  end;

  Tenant.Db := WLDbOpen(Tenant.DbPath);
  Result := Assigned(Tenant.Db);
  if Result then
    HandleCache.AddObject(Tenant.Host, TObject(Tenant.Db));
end;

initialization

finalization
  if Assigned(HandleCache) then
  begin
    // close pooled handles
    while HandleCache.Count > 0 do
    begin
      WLDbClose(TWLDb(HandleCache.Objects[0]));
      HandleCache.Delete(0);
    end;
    HandleCache.Free;
  end;

end.
