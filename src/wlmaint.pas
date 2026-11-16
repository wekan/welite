unit wlmaint;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,wldb;
type TWLMaintainer=class(TThread)
  private
    FPaths:TStringList;
    FLock:TRTLCriticalSection;
    FWake:PRTLEvent;
    FPollMs:LongWord;
    FDataRoot:string;
    FFailures:LongInt;
  protected
    procedure Execute;override;
  public
    constructor Create(PollMs:LongWord=60000;const DataRoot:string='');
    destructor Destroy;override;
    procedure AddPath(const Path:string);
    function FailedPasses:LongInt;
  end;
procedure StartMaintenance(const DataRoot:string='');
procedure StopMaintenance;
procedure RegisterMaintenanceDb(Db:TWLDb);
implementation
uses wlshared,wlsweep,wldisc;
var Worker:TWLMaintainer=nil;WorkerLock:TRTLCriticalSection;
constructor TWLMaintainer.Create(PollMs:LongWord;const DataRoot:string);
begin
  inherited Create(True);FreeOnTerminate:=False;
  if DataRoot<>'' then FDataRoot:=ExpandFileName(DataRoot);
  InitCriticalSection(FLock);FPaths:=TStringList.Create;FPaths.CaseSensitive:=True;
  FPaths.Sorted:=True;FPaths.Duplicates:=dupIgnore;FWake:=RTLEventCreate;
  if PollMs=0 then FPollMs:=60000 else FPollMs:=PollMs;
end;
destructor TWLMaintainer.Destroy;
begin
  Terminate;RTLEventSetEvent(FWake);WaitFor;
  RTLEventDestroy(FWake);FPaths.Free;DoneCriticalSection(FLock);
  inherited Destroy;
end;
procedure TWLMaintainer.AddPath(const Path:string);
var Full:string;Added:Boolean;
begin
  if Path='' then Exit;Full:=ExpandFileName(Path);Added:=False;
  EnterCriticalSection(FLock);
  try if FPaths.IndexOf(Full)<0 then begin FPaths.Add(Full);Added:=True;end;
  finally LeaveCriticalSection(FLock);end;
  if Added then RTLEventSetEvent(FWake);
end;
function TWLMaintainer.FailedPasses:LongInt;
begin Result:=InterlockedCompareExchange(FFailures,0,0);end;
procedure TWLMaintainer.Execute;
var Paths:TStringList;i:Integer;Db:TWLDb;Rows:TWLRows;Succeeded:Boolean;
begin
  Paths:=TStringList.Create;
  try
    while not Terminated do
    begin
      if FDataRoot<>'' then
      begin
        if not DiscoverMaintenancePaths(FDataRoot,Paths) then InterlockedIncrement(FFailures);
      end
      else
      begin
        EnterCriticalSection(FLock);
        try Paths.Assign(FPaths);finally LeaveCriticalSection(FLock);end;
      end;
      for i:=0 to Paths.Count-1 do
      begin
        if Terminated then Break;
        if not FileExists(Paths[i]) then Continue;
        Db:=nil;
        try
          try
            Db:=TWLDb.Create(Paths[i]);
            Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''users'';');
            Succeeded:=True;
            if Length(Rows)=1 then
            begin
              if Rows[0][0]='view' then Succeeded:=SweepSharedTokens(Db,UnixMillis(Now))
              else if Rows[0][0]='table' then Succeeded:=SweepLegacyTokens(Db,UnixMillis(Now));
            end;
            if not Succeeded then InterlockedIncrement(FFailures);
          except InterlockedIncrement(FFailures);end;
        finally Db.Free;end;
      end;
      if not Terminated then RTLEventWaitFor(FWake,FPollMs);
      RTLEventResetEvent(FWake);
    end;
  finally Paths.Free;end;
end;
procedure StartMaintenance(const DataRoot:string);
begin
  EnterCriticalSection(WorkerLock);
  try if Worker=nil then begin Worker:=TWLMaintainer.Create(60000,DataRoot);Worker.Start;end;
  finally LeaveCriticalSection(WorkerLock);end;
end;
procedure StopMaintenance;
var Previous:TWLMaintainer;
begin
  EnterCriticalSection(WorkerLock);
  try Previous:=Worker;Worker:=nil;finally LeaveCriticalSection(WorkerLock);end;
  Previous.Free;
end;
procedure RegisterMaintenanceDb(Db:TWLDb);
var Rows:TWLRows;
begin
  EnterCriticalSection(WorkerLock);
  try
    if (Worker=nil) or (Db=nil) then Exit;
    try
      Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''users'';');
      if (Length(Rows)=1) and ((Rows[0][0]='table') or (Rows[0][0]='view')) then Worker.AddPath(Db.Path);
    except { Unsupported stores do not break a request. } end;
  finally LeaveCriticalSection(WorkerLock);end;
end;
initialization InitCriticalSection(WorkerLock);
finalization StopMaintenance;DoneCriticalSection(WorkerLock);
end.
