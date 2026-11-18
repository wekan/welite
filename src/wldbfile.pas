unit wldbfile;
{$mode objfpc}{$H+}
interface
uses SysUtils;
function SharedStoresRequested:Boolean;
function AutoSharedStores:Boolean;
function ValidStoreMode:Boolean;
// Select one canonical file. Never copy/link/rename or create a database here.
// Shared creation selects the canonical .sqlite path. Native mode never shadows it.
function SelectStoreFile(const Directory:string;SharedOnly:Boolean;out Path:string;AllowSharedCreation:Boolean=False;AllowAuto:Boolean=True):Boolean;
implementation
{$IFNDEF WLDB_CLI}uses sqlite3;{$ENDIF}
function SharedStoresRequested:Boolean;
begin Result:=GetEnvironmentVariable('WELITE_SHARED')='1';end;
function AutoSharedStores:Boolean;
begin Result:=GetEnvironmentVariable('WELITE_SHARED')='';end;
function ValidStoreMode:Boolean;
var Value:string;
begin Value:=GetEnvironmentVariable('WELITE_SHARED');Result:=(Value='') or (Value='0') or (Value='1');end;
function SharedCreationAvailable:Boolean;
begin
  if GetEnvironmentVariable('WELITE_SHORT_NAMES')='1' then Exit(False);
  {$IFDEF WLDB_CLI}
  Result:=FileExists(GetEnvironmentVariable('WELITE_SQLITE_EXT'));
  {$ELSE}
  Result:=sqlite3_libversion_number()>=3045000;
  {$ENDIF}
end;

function SelectStoreFile(const Directory:string;SharedOnly:Boolean;out Path:string;AllowSharedCreation,AllowAuto:Boolean):Boolean;
var Dir,ShortFile,SourceFile:string;HasShort,HasSource,StrictNames,ShortSidecars,LongSidecars:Boolean;Search:TSearchRec;Code:Integer;
begin
  Result:=False;Path:='';if not ValidStoreMode then Exit;
  Dir:=IncludeTrailingPathDelimiter(ExpandFileName(Directory));ShortFile:=Dir+'wekan.db';SourceFile:=Dir+'wekan.sqlite';
  HasShort:=FileExists(ShortFile);HasSource:=FileExists(SourceFile);
  if HasShort and HasSource then Exit;
  if not HasSource and (FileExists(SourceFile+'-wal') or FileExists(SourceFile+'-shm') or FileExists(SourceFile+'-journal')) then Exit;
  StrictNames:=GetEnvironmentVariable('WELITE_SHORT_NAMES')='1';
  LongSidecars:=FileExists(ShortFile+'-wal') or FileExists(ShortFile+'-shm') or FileExists(ShortFile+'-journal');
  ShortSidecars:=FileExists(Dir+'wekan.wal') or FileExists(Dir+'wekan.shm') or FileExists(Dir+'wekan.nal');
  if not HasShort and (LongSidecars or ShortSidecars) then Exit;

  if HasSource then
  begin
    if not (SharedOnly or (AllowAuto and AutoSharedStores)) or (GetEnvironmentVariable('WELITE_SHORT_NAMES')='1') then Exit;
    Path:=SourceFile;Exit(True);
  end;
  if HasShort then
  begin
    if (StrictNames and LongSidecars) or (not StrictNames and ShortSidecars) then Exit;
    Path:=ShortFile;Exit(True);
  end;
  if SharedOnly and (not AllowSharedCreation or (GetEnvironmentVariable('WELITE_SHORT_NAMES')='1')) then Exit;
  // A differently named FerretDB file or orphan sidecars require explicit repair,
  // not a new normalized database beside possibly recoverable source data.
  Code:=FindFirst(Dir+'*.sqlite',faAnyFile,Search);
  if Code=0 then
  begin
    try
      repeat
        if (Search.Attr and faDirectory)=0 then Exit;
        Code:=FindNext(Search);
      until Code<>0;
    finally FindClose(Search);end;
  end;
  if FileExists(ShortFile+'-wal') or FileExists(ShortFile+'-shm') or FileExists(ShortFile+'-journal') or
    FileExists(SourceFile+'-wal') or FileExists(SourceFile+'-shm') or FileExists(SourceFile+'-journal') or
    FileExists(Dir+'wekan.wal') or FileExists(Dir+'wekan.shm') or FileExists(Dir+'wekan.nal') then Exit;
  if SharedOnly or (AllowSharedCreation and AllowAuto and AutoSharedStores and SharedCreationAvailable) then
    Path:=SourceFile else Path:=ShortFile;
  Result:=True;
end;
end.
