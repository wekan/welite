unit wldb;

{
  WeKan-Lite — SQLite access behind one interface (see docs/sqlite.md)

  Two backends, chosen at compile time, so endpoints never care which is built in:

    default          : linked SQLite via FPC's `sqlite3` binding (single binary, G1/G3)
    {$DEFINE WLDB_CLI}: shell out to the `sqlite3` CLI via TProcess (omi-style bootstrap)

  Surface kept small: open/close, Exec for writes, Query for collected text rows,
  and Scan for provisional rows consumed without collecting a complete result.
  The CLI path uses private SQL scripts and TProcess; its bootstrap origin is
  https://github.com/wekan/omi/blob/main/public/server.pas ExecSqlOnDb.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, Classes
  {$IFDEF WLDB_CLI}, Process,wltmp {$IFDEF UNIX},BaseUnix{$ENDIF} {$ELSE}, sqlite3,wlfuncs {$ENDIF};

type
  TWLDb = class;                       // opaque to callers (tenant just holds a reference)

  TWLRow   = array of string;
  TWLRows  = array of TWLRow;
  TWLRowHandler = procedure(const Row:TWLRow) of object;

  TWLDb = class
  private
    FPath: string;
    FGate:TRTLCriticalSection;
    FGateReady,FRead,FBroken:Boolean;
    FOldQueryOnly:string;
    {$IFDEF WLDB_CLI}FReadSession:TObject;{$ENDIF}
    {$IFNDEF WLDB_CLI}
    FHandle: Pointer;                  // psqlite3
    {$ENDIF}
  public
    constructor Create(const APath:string; Portable:Boolean=False);
    destructor Destroy; override;
    // Parameterless write (DDL/INSERT/UPDATE). Returns False on error.
    function Exec(const Sql: string): Boolean;
    // Read query. SQL must already be a complete statement; returns rows of text cells.
    function Query(const Sql: string): TWLRows;
    // Rows are provisional until True: SQL/CSV/handler failures return False.
    // Row storage is reused: consume/copy cells during the callback.
    // A bounded handler must not retain rows or issue writes.
    function Scan(const Sql:string;Handler:TWLRowHandler):Boolean;
    // A successful begin holds the handle gate until EndRead on this thread.
    function BeginRead:Boolean;
    function EndRead:Boolean;
    property Path: string read FPath;
  end;

function ShortDbName(const Path:string):Boolean;
function WLDbOpen(const APath: string): TWLDb;
procedure WLDbClose(Db: TWLDb);

// SQL string-literal escaping. ONLY for the CLI backend; the linked backend uses bound
// params and must not call this (kept here so callers building ad-hoc SQL share one impl).
function SqlEscape(const Value: string): string;

implementation
{$IFDEF WLDB_CLI}uses wlentrop;{$ENDIF}

function ReadStatement(const Sql:string):Boolean;
type TState=(normal,quoted,identifier,backtick,bracket,linecomment,blockcomment);
var State:TState;I,J:SizeInt;C:Char;Ended:Boolean;Verb,PragmaName:string;
  function Token:string;
  var Start:SizeInt;
  begin
    repeat
      while (I<=Length(Sql)) and (Sql[I] in [#9,#10,#13,' ']) do Inc(I);
      if (I<Length(Sql)) and (Copy(Sql,I,2)='--') then
      begin while (I<=Length(Sql)) and not (Sql[I] in [#10,#13]) do Inc(I);end
      else if (I<Length(Sql)) and (Copy(Sql,I,2)='/*') then
      begin Inc(I,2);while (I<Length(Sql)) and (Copy(Sql,I,2)<>'*/') do Inc(I);Inc(I,2);end
      else Break;
    until False;
    Start:=I;while (I<=Length(Sql)) and (Sql[I] in ['a'..'z','A'..'Z','_']) do Inc(I);
    Result:=UpperCase(Copy(Sql,Start,I-Start));
  end;
begin
  Result:=False;I:=1;Verb:=Token;
  if Verb='PRAGMA' then
  begin
    PragmaName:=Token;
    if (PragmaName<>'TABLE_INFO') and (PragmaName<>'TABLE_XINFO') and
      (PragmaName<>'INDEX_INFO') and (PragmaName<>'INDEX_XINFO') and
      (PragmaName<>'INDEX_LIST') and (PragmaName<>'FOREIGN_KEY_LIST') then Exit;
  end else if (Verb<>'SELECT') and (Verb<>'WITH') then Exit;
  State:=normal;Ended:=False;I:=1;
  while I<=Length(Sql) do
  begin
    C:=Sql[I];
    case State of
      normal:
      begin
        if (C='-') and (I<Length(Sql)) and (Sql[I+1]='-') then begin State:=linecomment;Inc(I);end
        else if (C='/') and (I<Length(Sql)) and (Sql[I+1]='*') then begin State:=blockcomment;Inc(I);end
        else if C=';' then Ended:=True
        else if Ended and not (C in [#9,#10,#13,' ']) then Exit
        else case C of '''':State:=quoted;'"':State:=identifier;'`':State:=backtick;'[':State:=bracket;end;
      end;
      quoted,identifier,backtick:
      begin
        J:=0;
        if ((State=quoted) and (C='''')) or ((State=identifier) and (C='"')) or ((State=backtick) and (C='`')) then
          if (I<Length(Sql)) and (Sql[I+1]=C) then J:=1 else State:=normal;
        Inc(I,J);
      end;
      bracket:if C=']' then State:=normal;
      linecomment:if C in [#10,#13] then State:=normal;
      blockcomment:if (C='*') and (I<Length(Sql)) and (Sql[I+1]='/') then begin State:=normal;Inc(I);end;
    end;
    Inc(I);
  end;
  Result:=State in [normal,linecomment];
end;

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

function ShortDbName(const Path:string):Boolean;
var Base,Ext,Text:string;i:Integer;
begin
  Base:=ChangeFileExt(ExtractFileName(Path),'');Ext:=Copy(ExtractFileExt(Path),2,MaxInt);
  Result:=(Length(Base)>=1) and (Length(Base)<=8) and (Length(Ext)>=1) and (Length(Ext)<=3);
  Text:=Base+Ext;
  for i:=1 to Length(Text) do if not (Text[i] in ['a'..'z','A'..'Z','0'..'9','-','_']) then Result:=False;
end;

constructor TWLDb.Create(const APath:string; Portable:Boolean);
var Options:TWLRows;
begin
  inherited Create;InitCriticalSection(FGate);FGateReady:=True;
  FPath := APath;
  if (GetEnvironmentVariable('WELITE_SHORT_NAMES')='1') and not ShortDbName(APath) then
    raise Exception.Create('Strict mode requires an 8.3 database filename with an extension');
  {$IFNDEF WLDB_CLI}
  if sqlite3_open(PChar(FPath), @FHandle) <> SQLITE_OK then
    raise Exception.CreateFmt('wldb: cannot open %s', [FPath]);
  if not RegisterFunctions(FHandle) then raise Exception.Create('Could not register typed-document SQL functions');
  Exec('PRAGMA busy_timeout=5000;');
  {$ENDIF}
  if GetEnvironmentVariable('WELITE_SHORT_NAMES')='1' then
  begin
    Options:=Query('SELECT sqlite_compileoption_used(''ENABLE_8_3_NAMES=2'');');
    if (Length(Options)<>1) or (Options[0][0]<>'1') then
      raise Exception.Create('Short filenames require SQLite built with SQLITE_ENABLE_8_3_NAMES=2 for every database tool');
    if not Exec('PRAGMA temp_store=MEMORY;') then raise Exception.Create('Could not configure short-name temporary storage');
  end;
  {$IFNDEF WLDB_CLI}
  // recommended pragmas for a single-writer embedded server
  Exec('PRAGMA foreign_keys = ON;');
  // WAL needs shared-memory/mmap, which classic Amiga filesystems don't provide; fall back to
  // the portable rollback journal there (see docs/sqlite.md).
  {$IF DEFINED(AMIGA) or DEFINED(MORPHOS) or DEFINED(AROS)}
  Exec('PRAGMA journal_mode = DELETE;');
  {$ELSE}
  if Portable then Exec('PRAGMA journal_mode=DELETE;') else Exec('PRAGMA journal_mode=WAL;');
  {$ENDIF}
  {$ENDIF}

end;

destructor TWLDb.Destroy;
begin
  if FGateReady then EnterCriticalSection(FGate);
  try
    if FRead then EndRead;
    {$IFDEF WLDB_CLI}FReadSession.Free;FReadSession:=nil;{$ELSE}
    if FHandle<>nil then sqlite3_close(FHandle);
    {$ENDIF}
  finally
    if FGateReady then begin LeaveCriticalSection(FGate);DoneCriticalSection(FGate);end;
  end;
  inherited Destroy;
end;

{$IFDEF WLDB_CLI}
// --- Backend A: external sqlite3 CLI (mirrors omi ExecSqlOnDb) -----------------------------
function ScriptSql(const Sql:string):string;
type TState=(normal,quoted,identifier,backtick,bracket,linecomment,blockcomment);
var State:TState;i,j,k:Integer;C:Char;Part:string;Pieces:TStringList;Control,LineStart:Boolean;
  procedure Add(const Value:string);
  begin
    Part:=Part+Value;
    if Length(Part)>=8192 then begin Pieces.Add(Part);Part:='';end;
  end;
begin
  // SQLite .read normalizes physical CRLF lines, even inside literals. A literal
  // containing control bytes becomes one parenthesized hex-to-TEXT expression.
  // This also handles large newline-rich values without deep concatenation trees.
  State:=normal;Pieces:=TStringList.Create;
  try
    Part:='';i:=1;LineStart:=True;
    while i<=Length(Sql) do
    begin
      C:=Sql[i];
      if LineStart and (State=normal) and (C='.') then
        raise Exception.Create('CLI input accepts SQL, not shell dot commands');
      if (State=normal) and (C='''') then
      begin
        j:=i+1;Control:=False;
        while j<=Length(Sql) do
        begin
          if Sql[j]='''' then
          begin
            if (j<Length(Sql)) and (Sql[j+1]='''') then Inc(j) else Break;
          end;
          if Sql[j] in [#0,#10,#13] then Control:=True;
          Inc(j);
        end;
        if Control and (j<=Length(Sql)) then
        begin
          Add('(CAST(X'+'''');k:=i+1;
          while k<j do
          begin
            Add(IntToHex(Ord(Sql[k]),2));
            if (Sql[k]='''') and (k+1<j) and (Sql[k+1]='''') then Inc(k);
            Inc(k);
          end;
          Add(''''+ ' AS TEXT))');i:=j+1;LineStart:=False;Continue;
        end;
      end;
      if (State in [identifier,backtick,bracket]) and (C in [#0,#10,#13]) then
        raise Exception.Create('Multiline SQL identifiers are not supported by the CLI script reader');
      Add(C);
      case State of
        normal:case C of
          '''':State:=quoted;'"':State:=identifier;'`':State:=backtick;'[':State:=bracket;
          '-':if (i<Length(Sql)) and (Sql[i+1]='-') then begin Add('-');Inc(i);State:=linecomment;end;
          '/':if (i<Length(Sql)) and (Sql[i+1]='*') then begin Add('*');Inc(i);State:=blockcomment;end;
        end;
        quoted:if C='''' then
          if (i<Length(Sql)) and (Sql[i+1]='''') then begin Add('''');Inc(i);end else State:=normal;
        identifier:if C='"' then
          if (i<Length(Sql)) and (Sql[i+1]='"') then begin Add('"');Inc(i);end else State:=normal;
        backtick:if C='`' then State:=normal;
        bracket:if C=']' then State:=normal;
        linecomment:if C=#10 then State:=normal;
        blockcomment:if (C='*') and (i<Length(Sql)) and (Sql[i+1]='/') then
          begin Add('/');Inc(i);State:=normal;end;
      end;
      LineStart:=C=#10;Inc(i);
    end;
    Pieces.Add(Part);Result:='';for i:=0 to Pieces.Count-1 do Result:=Result+Pieces[i];
  finally Pieces.Free;end;
end;

procedure WriteSqliteScript(const Sql,Extension:string;out Directory,Script:string);
var InitSql,Text:string;Stream:TFileStream;
begin
  Directory:='';Script:='';InitSql:='';
  if Extension<>'' then InitSql:='SELECT load_extension('+QuotedStr(ExpandFileName(Extension))+'); ';
  Directory:=NewTempDir;Script:=Directory+'query.sql';
  Stream:=TFileStream.Create(Script,fmCreate);
  try
    {$IFDEF UNIX}
    if fpChmod(PChar(Script),&600)<>0 then raise Exception.Create('Could not protect SQL scratch permissions');
    {$ENDIF}
    Text:='.bail on'+#10+'.timeout 5000'+#10+'.mode csv'+#10+'.headers off'+#10+'PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL; PRAGMA temp_store=MEMORY; '+ScriptSql(InitSql+Sql);
    if Text<>'' then Stream.WriteBuffer(Text[1],Length(Text));
  finally Stream.Free;end;
end;

function RunSqlite(const DbPath, Sql: string; out Output: string): Boolean;
var Extension,Directory,Script,Database:string;
begin
  Result:=False;Output:='';Directory:='';Script:='';
  Extension:=GetEnvironmentVariable('WELITE_SQLITE_EXT');
  Database:=ExpandFileName(DbPath);
  try
    try
      WriteSqliteScript(Sql,Extension,Directory,Script);
      // -init takes a structured filename argument: no shell/meta-command quoting.
      // Retain the caller's CWD so relative ATTACH/VACUUM paths keep their meaning.
      // RunCommand drains stdout/stderr concurrently and checks the child exit code.
      Result:=RunCommand('sqlite3',['-batch','-bail','-csv','-noheader',
        '-init',Script,Database,'.quit'],Output);
      if Result and (Extension<>'') then
      begin
        if Copy(Output,1,2)=#13#10 then Delete(Output,1,2)
        else if Copy(Output,1,1)=#10 then Delete(Output,1,1)
        else begin Result:=False;Output:='';end;
      end;
    except Result:=False;Output:='';end;
  finally
    if Script<>'' then DeleteFile(Script);
    if Directory<>'' then RemoveDir(ExcludeTrailingPathDelimiter(Directory));
  end;
end;

type
  TScanCsv=class
  private
    FHandler:TWLRowHandler;
    FRow:TWLRow;
    FCell:string;
    FUsed:SizeInt;
    FState:Byte; // 0: field start; 1: unquoted; 2: quoted; 3: closing quote
    FPrefix:Byte; // 0: complete; 1: extension newline; 2: extension LF after CR
    FSkipLF:Boolean;
    procedure AddByte(C:Char);
    procedure AddCell;
    procedure AddRow;
  public
    constructor Create(Handler:TWLRowHandler;Extension:Boolean);
    procedure Feed(const Buffer;Count:SizeInt);
    procedure Finish;
  end;
constructor TScanCsv.Create(Handler:TWLRowHandler;Extension:Boolean);
begin inherited Create;FHandler:=Handler;if Extension then FPrefix:=1;end;
procedure TScanCsv.AddByte(C:Char);
var Capacity:SizeInt;
begin
  if FUsed=Length(FCell) then
  begin
    Capacity:=Length(FCell)*2;if Capacity<256 then Capacity:=256;
    SetLength(FCell,Capacity);
  end;
  Inc(FUsed);FCell[FUsed]:=C;
end;
procedure TScanCsv.AddCell;
var N:SizeInt;
begin
  N:=Length(FRow);SetLength(FRow,N+1);SetString(FRow[N],PChar(FCell),FUsed);
  FUsed:=0;FState:=0;
end;
procedure TScanCsv.AddRow;
begin AddCell;FHandler(FRow);FRow:=nil;end;
procedure TScanCsv.Feed(const Buffer;Count:SizeInt);
var Bytes:PByte;i:SizeInt;C:Char;
begin
  Bytes:=@Buffer;
  for i:=0 to Count-1 do
  begin
    C:=Char(Bytes[i]);
    if FPrefix<>0 then
    begin
      if (FPrefix=1) and (C=#13) then FPrefix:=2
      else if C=#10 then FPrefix:=0
      else raise Exception.Create('Invalid extension output');
      Continue;
    end;
    if FSkipLF then begin FSkipLF:=False;if C=#10 then Continue;end;
    if FState=2 then
    begin if C='"' then FState:=3 else AddByte(C);Continue;end;
    if FState=3 then
    begin
      if C='"' then begin AddByte(C);FState:=2;Continue;end;
      if not (C in [',',#10,#13]) then raise Exception.Create('Invalid quoted CSV field');
    end;
    case C of
      '"':begin
        if FState<>0 then raise Exception.Create('Invalid CSV quote');
        FState:=2;
      end;
      ',':AddCell;
      #10,#13:begin AddRow;FSkipLF:=C=#13;end;
    else AddByte(C);FState:=1;
    end;
  end;
end;
procedure TScanCsv.Finish;
begin
  if (FPrefix<>0) or (FState=2) then raise Exception.Create('Incomplete CSV output');
  if (FState<>0) or (FUsed>0) or (Length(FRow)>0) then AddRow;
end;
type
  TReadFrame=class
    Marker:string;
    Done,Failed:Boolean;
    Handler:TWLRowHandler;
    procedure ReadRow(const Row:TWLRow);
  end;
  TReadRows=class
    Rows:TWLRows;
    procedure Add(const Row:TWLRow);
  end;
  TReadSession=class
  private
    FProc:TProcess;FInitDir,FInitScript,FKey:string;
    FSequence:LongWord;FStarted,FDead,FPrefix:Boolean;
    procedure Ignore(const Row:TWLRow);
  public
    function Open(const DbPath:string):Boolean;
    function Read(const Sql:string;Handler:TWLRowHandler):Boolean;
    function Close:Boolean;
    destructor Destroy;override;
  end;
procedure TReadRows.Add(const Row:TWLRow);
var N:SizeInt;
begin N:=Length(Rows);SetLength(Rows,N+1);Rows[N]:=Copy(Row);end;
procedure TReadFrame.ReadRow(const Row:TWLRow);
begin
  if Done then raise Exception.Create('Unexpected snapshot output');
  if (Length(Row)=1) and (Row[0]=Marker) then begin Done:=True;Exit;end;
  if not Failed then try Handler(Row);except Failed:=True;end;
end;
procedure TReadSession.Ignore(const Row:TWLRow);
begin end;
function DotPath(const Value:string):string;
var I:SizeInt;
begin
  Result:='"';
  for I:=1 to Length(Value) do case Value[I] of
    #0:raise Exception.Create('Invalid snapshot script path');
    #10:Result:=Result+'\n';#13:Result:=Result+'\r';#9:Result:=Result+'\t';
    '"':Result:=Result+'\"';'\':Result:=Result+'\\';
  else Result:=Result+Value[I];end;
  Result:=Result+'"';
end;
function TReadSession.Open(const DbPath:string):Boolean;
var Bytes:RawByteString;I:Integer;Extension:string;
begin
  Result:=False;
  try
    Bytes:=SecureBytes(16);FKey:='__wl_read_';
    for I:=1 to Length(Bytes) do FKey:=FKey+LowerCase(IntToHex(Ord(Bytes[I]),2));
    Extension:=GetEnvironmentVariable('WELITE_SQLITE_EXT');FPrefix:=Extension<>'';
    WriteSqliteScript('',Extension,FInitDir,FInitScript);
    FProc:=TProcess.Create(nil);FProc.Executable:='sqlite3';FProc.Options:=[poUsePipes];
    FProc.Parameters.Add('-batch');FProc.Parameters.Add('-bail');FProc.Parameters.Add('-readonly');
    FProc.Parameters.Add('-csv');FProc.Parameters.Add('-noheader');
    FProc.Parameters.Add('-init');FProc.Parameters.Add(FInitScript);FProc.Parameters.Add(ExpandFileName(DbPath));
    FProc.Execute;FStarted:=True;
    Result:=Read('PRAGMA query_only=ON; BEGIN; SELECT count(*) FROM sqlite_master;',@Ignore);
  except FDead:=True;end;
end;
function TReadSession.Read(const Sql:string;Handler:TWLRowHandler):Boolean;
var Frame:TReadFrame;Parser:TScanCsv;Directory,Script,Text,Command:string;Stream:TFileStream;
  Buffer:array of Byte;Count:LongInt;Progress:Boolean;
begin
  Result:=False;if FDead or not FStarted or not Assigned(Handler) then Exit;
  Directory:='';Script:='';Frame:=nil;Parser:=nil;
  try
    try
      if FSequence=High(LongWord) then raise Exception.Create('Snapshot sequence exhausted');
      Inc(FSequence);Frame:=TReadFrame.Create;Frame.Marker:=FKey+'_'+IntToStr(FSequence);Frame.Handler:=Handler;
      Parser:=TScanCsv.Create(@Frame.ReadRow,FPrefix);FPrefix:=False;SetLength(Buffer,8192);
      Directory:=NewTempDir;Script:=Directory+'query.sql';Stream:=TFileStream.Create(Script,fmCreate);
      try
        {$IFDEF UNIX}
        if fpChmod(PChar(Script),&600)<>0 then raise Exception.Create('Could not protect snapshot script');
        {$ENDIF}
        Text:=ScriptSql(Sql)+#10+';'+#10;
        if Text<>'' then Stream.WriteBuffer(Text[1],Length(Text));
      finally Stream.Free;end;
      // The boundary is outside .read: receiving it proves that file is closed.
      Command:='.read '+DotPath(ExpandFileName(Script))+#10+'SELECT '+QuotedStr(Frame.Marker)+';'+#10;
      FProc.Input.WriteBuffer(Command[1],Length(Command));
      repeat
        Progress:=False;Count:=FProc.Output.NumBytesAvailable;
        if Count>Length(Buffer) then Count:=Length(Buffer);
        if Count>0 then
        begin
          Count:=FProc.Output.Read(Buffer[0],Count);
          if Count<=0 then raise EReadError.Create('Could not read snapshot output');
          Progress:=True;Parser.Feed(Buffer[0],Count);
        end;
        Count:=FProc.Stderr.NumBytesAvailable;
        if Count>Length(Buffer) then Count:=Length(Buffer);
        if Count>0 then
        begin FProc.Stderr.Read(Buffer[0],Count);raise Exception.Create('Snapshot statement failed');end;
        if Frame.Done then Break;
        if not FProc.Running and (FProc.Output.NumBytesAvailable=0) then raise Exception.Create('Incomplete snapshot response');
        if not Progress then Sleep(1);
      until False;
      Parser.Finish;
      if not FProc.Running then raise Exception.Create('Snapshot reader exited');
      Result:=not Frame.Failed;
    except FDead:=True;Close;Result:=False;end;
  finally
    Parser.Free;Frame.Free;
    if Script<>'' then DeleteFile(Script);
    if Directory<>'' then RemoveDir(ExcludeTrailingPathDelimiter(Directory));
  end;
end;
function TReadSession.Close:Boolean;
var Buffer:array of Byte;Count:LongInt;Progress:Boolean;
begin
  Result:=False;
  try
    try
      if FProc<>nil then
      begin
    if FStarted then
    begin
      SetLength(Buffer,8192);Result:=not FDead and FProc.Running;
      if FProc.Running then
        if FDead then FProc.Terminate(1) else FProc.CloseInput;
      repeat
        Progress:=False;Count:=FProc.Output.NumBytesAvailable;
        if Count>Length(Buffer) then Count:=Length(Buffer);
        if Count>0 then begin FProc.Output.Read(Buffer[0],Count);Progress:=True;Result:=False;end;
        Count:=FProc.Stderr.NumBytesAvailable;
        if Count>Length(Buffer) then Count:=Length(Buffer);
        if Count>0 then begin FProc.Stderr.Read(Buffer[0],Count);Progress:=True;Result:=False;end;
        if not FProc.Running and (FProc.Output.NumBytesAvailable=0) and (FProc.Stderr.NumBytesAvailable=0) then Break;
        if not Progress then Sleep(1);
      until False;
      FProc.WaitOnExit;Result:=Result and (FProc.ExitStatus=0);
    end;
      end;
    except Result:=False;end;
  finally
    if FProc<>nil then
    begin
      try if FProc.Running then begin FProc.Terminate(1);FProc.WaitOnExit;end;
      except Result:=False;end;
      FProc.Free;FProc:=nil;
    end;
    FStarted:=False;FDead:=True;
    if FInitScript<>'' then begin DeleteFile(FInitScript);FInitScript:='';end;
    if FInitDir<>'' then begin RemoveDir(ExcludeTrailingPathDelimiter(FInitDir));FInitDir:='';end;
  end;
end;
destructor TReadSession.Destroy;
begin Close;inherited Destroy;end;

function TWLDb.Scan(const Sql:string;Handler:TWLRowHandler):Boolean;
var Proc:TProcess;Parser:TScanCsv;Extension,Directory,Script:string;
  Buffer:array of Byte;Count:LongInt;Failed,Progress:Boolean;
begin
  EnterCriticalSection(FGate);
  try
    Result:=False;if FBroken or (FRead and not ReadStatement(Sql)) then Exit;
    if FRead then Exit(TReadSession(FReadSession).Read(Sql,Handler));
  Result:=False;if not Assigned(Handler) then Exit;
  Proc:=nil;Parser:=nil;Directory:='';Script:='';
  try
    try
      // Keep the fixed pipe buffer off small retro-target stacks.
      SetLength(Buffer,8192);
      Extension:=GetEnvironmentVariable('WELITE_SQLITE_EXT');
      WriteSqliteScript(Sql,Extension,Directory,Script);
      Parser:=TScanCsv.Create(Handler,Extension<>'');Proc:=TProcess.Create(nil);
      Proc.Executable:='sqlite3';Proc.Options:=[poUsePipes];
      Proc.Parameters.Add('-batch');Proc.Parameters.Add('-bail');
      Proc.Parameters.Add('-csv');Proc.Parameters.Add('-noheader');
      Proc.Parameters.Add('-init');Proc.Parameters.Add(Script);
      Proc.Parameters.Add(ExpandFileName(FPath));Proc.Parameters.Add('.quit');
      Proc.Execute;Failed:=False;
      repeat
        Progress:=False;
        Count:=Proc.Output.NumBytesAvailable;
        if Count>Length(Buffer) then Count:=Length(Buffer);
        if Count>0 then
        begin
          Count:=Proc.Output.Read(Buffer[0],Count);
          if Count<=0 then raise EReadError.Create('Could not read SQLite output');
          Progress:=True;
          if not Failed and (Count>0) then
            try Parser.Feed(Buffer[0],Count);except Failed:=True;end;
        end;
        Count:=Proc.Stderr.NumBytesAvailable;
        if Count>Length(Buffer) then Count:=Length(Buffer);
        if Count>0 then
        begin
          Count:=Proc.Stderr.Read(Buffer[0],Count);
          if Count<=0 then raise EReadError.Create('Could not read SQLite error output');
          Failed:=True;Progress:=True;
        end;
        if not Proc.Running and (Proc.Output.NumBytesAvailable=0) and
          (Proc.Stderr.NumBytesAvailable=0) then Break;
        if not Progress then Sleep(1);
      until False;
      Proc.WaitOnExit;
      if not Failed and (Proc.ExitStatus=0) then begin Parser.Finish;Result:=True;end;
    except Result:=False;end;
  finally
    if Proc<>nil then
    begin
      if Proc.Running then begin Proc.Terminate(1);Proc.WaitOnExit;end;
      Proc.Free;
    end;
    Parser.Free;
    if Script<>'' then DeleteFile(Script);
    if Directory<>'' then RemoveDir(ExcludeTrailingPathDelimiter(Directory));
  end;
  finally LeaveCriticalSection(FGate);end;
end;

function TWLDb.Exec(const Sql: string): Boolean;
var Ignored: string;
begin
  EnterCriticalSection(FGate);
  try
    Result:=False;if FBroken or FRead then Exit;
  Result := RunSqlite(FPath, Sql, Ignored);
  finally LeaveCriticalSection(FGate);end;
end;

function TWLDb.Query(const Sql: string): TWLRows;
var Raw, Cell:string;Row:TWLRow;i,n,CellLength,Capacity:SizeInt;InQuotes:Boolean;
  procedure AddByte(C:Char);
  begin
    if CellLength=Length(Cell) then
    begin
      Capacity:=Length(Cell)*2;if Capacity<256 then Capacity:=256;SetLength(Cell,Capacity);
    end;
    Inc(CellLength);Cell[CellLength]:=C;
  end;
  procedure AddCell;
  begin
    n:=Length(Row);SetLength(Row,n+1);SetString(Row[n],PChar(Cell),CellLength);CellLength:=0;
  end;
  procedure AddRow;
  begin
    AddCell;
    n:=Length(Result); SetLength(Result,n+1); Result[n]:=Row;
    Row:=nil;
  end;
  function ReadRows:TWLRows;
  var Collector:TReadRows;
  begin
    Collector:=TReadRows.Create;
    try if TReadSession(FReadSession).Read(Sql,@Collector.Add) then Result:=Collector.Rows else Result:=nil;
    finally Collector.Free;end;
  end;
begin
  EnterCriticalSection(FGate);
  try
    Result:=nil;if FBroken or (FRead and not ReadStatement(Sql)) then Exit;
    if FRead then Exit(ReadRows);
  Result:=nil; Row:=nil;
  if not RunSqlite(FPath,Sql,Raw) or (Raw='') then Exit;
  // SQLite CSV quotes commas, quotes and embedded newlines. Preserve bytes inside
  // quotes, including CRLF: text must round-trip identically to the linked backend.
  i:=1;Cell:='';CellLength:=0;InQuotes:=False;
  while i<=Length(Raw) do
  begin
    case Raw[i] of
      '"':
        if InQuotes and (i<Length(Raw)) and (Raw[i+1]='"') then
        begin AddByte('"');Inc(i);end
        else InQuotes:=not InQuotes;
      ',': if InQuotes then AddByte(Raw[i]) else AddCell;
      #10,#13:
        if InQuotes then AddByte(Raw[i])
        else
        begin
          AddRow;
          if (Raw[i]=#13) and (i<Length(Raw)) and (Raw[i+1]=#10) then Inc(i);
        end;
    else AddByte(Raw[i]);
    end;
    Inc(i);
  end;
  if (CellLength>0) or (Length(Row)>0) then AddRow;
  finally LeaveCriticalSection(FGate);end;
end;
{$ELSE}
// --- Backend B: linked SQLite (production default) ----------------------------------------
function TWLDb.Exec(const Sql: string): Boolean;
var
  ErrMsg: PChar;
begin
  EnterCriticalSection(FGate);
  try
    Result:=False;if FBroken or FRead then Exit;
  ErrMsg := nil;
  Result := sqlite3_exec(FHandle, PChar(Sql), nil, nil, @ErrMsg) = SQLITE_OK;
  if ErrMsg <> nil then
    sqlite3_free(ErrMsg);
  finally LeaveCriticalSection(FGate);end;
end;

function TWLDb.Scan(const Sql:string;Handler:TWLRowHandler):Boolean;
var Stmt:Pointer;Row:TWLRow;Cols,C,StepCode:Integer;
begin
  EnterCriticalSection(FGate);
  try
    Result:=False;if FBroken or (FRead and not ReadStatement(Sql)) then Exit;
  Result:=False;if not Assigned(Handler) then Exit;
  if sqlite3_prepare_v2(FHandle,PChar(Sql),-1,@Stmt,nil)<>SQLITE_OK then Exit;
  try
    try
      Cols:=sqlite3_column_count(Stmt);SetLength(Row,Cols);
      StepCode:=sqlite3_step(Stmt);
      while StepCode=SQLITE_ROW do
      begin
        for C:=0 to Cols-1 do Row[C]:=string(sqlite3_column_text(Stmt,C));
        Handler(Row);StepCode:=sqlite3_step(Stmt);
      end;
      Result:=StepCode=SQLITE_DONE;
    except Result:=False;end;
  finally sqlite3_finalize(Stmt);end;
  finally LeaveCriticalSection(FGate);end;
end;

function TWLDb.Query(const Sql: string): TWLRows;
var
  Stmt: Pointer;
  Cols,c,n,StepCode:Integer;
begin
  EnterCriticalSection(FGate);
  try
    Result:=nil;if FBroken or (FRead and not ReadStatement(Sql)) then Exit;
  SetLength(Result, 0);
  // Real code prepares once and binds params; this skeleton runs a literal statement.
  if sqlite3_prepare_v2(FHandle, PChar(Sql), -1, @Stmt, nil) <> SQLITE_OK then
    Exit;
  try
    Cols := sqlite3_column_count(Stmt);
    n := 0;
    StepCode:=sqlite3_step(Stmt);
    while StepCode=SQLITE_ROW do
    begin
      SetLength(Result, n + 1);
      SetLength(Result[n], Cols);
      for c := 0 to Cols - 1 do
        Result[n][c] := string(sqlite3_column_text(Stmt, c));
      Inc(n); StepCode:=sqlite3_step(Stmt);
    end;
    if StepCode<>SQLITE_DONE then Result:=nil;
  finally
    sqlite3_finalize(Stmt);
  end;
  finally LeaveCriticalSection(FGate);end;
end;
{$ENDIF}

function TWLDb.BeginRead:Boolean;
var Rows:TWLRows;Started:Boolean;
begin
  Result:=False;Started:=False;EnterCriticalSection(FGate);
  try
    if FBroken or FRead then Exit;
    {$IFDEF WLDB_CLI}
    FReadSession:=TReadSession.Create;
    if not TReadSession(FReadSession).Open(FPath) then begin FreeAndNil(FReadSession);Exit;end;
    {$ELSE}
    if sqlite3_get_autocommit(FHandle)=0 then Exit;
    Rows:=Query('PRAGMA query_only;');
    if (Length(Rows)<>1) or ((Rows[0][0]<>'0') and (Rows[0][0]<>'1')) then Exit;
    FOldQueryOnly:=Rows[0][0];
    if not Exec('PRAGMA query_only=ON; BEGIN;') then
    begin
      if sqlite3_get_autocommit(FHandle)=0 then Exec('ROLLBACK;');
      Exec('PRAGMA query_only='+FOldQueryOnly+';');Exit;
    end;
    Rows:=Query('SELECT count(*) FROM sqlite_master;');
    if Length(Rows)<>1 then
    begin Exec('ROLLBACK;');Exec('PRAGMA query_only='+FOldQueryOnly+';');Exit;end;
    {$ENDIF}
    FRead:=True;Started:=True;Result:=True;
  finally if not Started then LeaveCriticalSection(FGate);end;
end;
function TWLDb.EndRead:Boolean;
var Held,Restored:Boolean;
begin
  Result:=False;Held:=False;EnterCriticalSection(FGate);
  try
    if not FRead then Exit;
    Held:=True;FRead:=False;
    {$IFDEF WLDB_CLI}
    Result:=TReadSession(FReadSession).Close;FreeAndNil(FReadSession);
    {$ELSE}
    Result:=Exec('ROLLBACK;');Restored:=Exec('PRAGMA query_only='+FOldQueryOnly+';');
    Result:=Result and Restored and (sqlite3_get_autocommit(FHandle)<>0);
    if not Result then FBroken:=True;
    {$ENDIF}
  finally LeaveCriticalSection(FGate);if Held then LeaveCriticalSection(FGate);end;
end;

end.
