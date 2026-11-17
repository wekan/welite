unit wlstop;
{$mode objfpc}{$H+}
interface
// Unix signals only request shutdown. All object/thread work runs outside handlers.
procedure StartHTTPStop;
procedure FinishHTTPStop;
procedure DoneHTTPStop;
implementation
uses SysUtils,Classes,CustApp,fphttpapp
  {$IFDEF UNIX},BaseUnix,Sockets,SSockets,fphttpserver,custhttpapp,custweb{$ENDIF};
{$IFDEF UNIX}
type
  TWLConnection=class(TFPHTTPConnection)
    destructor Destroy;override;
  end;
  TWLServer=class(TEmbeddedHttpServer)
    function CreateConnection(Data:TSocketStream):TFPHTTPConnection;override;
    property ConnectionCount;
  end;
  TWLHandler=class(TFPHTTPServerHandler)
    function CreateServer:TEmbeddedHttpServer;override;
  end;
  TWLApplication=class(THTTPApplication)
    function InitializeWebHandler:TWebHandler;override;
  end;
  TStopEvents=class
  procedure Idle(Sender:TObject);
  procedure AllowConnect(Sender:TObject;Socket:LongInt;var Allow:Boolean);
end;
var Requested:LongInt=0;Events:TStopEvents=nil;
    OldTerm,OldInt:SigActionRec;TermInstalled,IntInstalled:Boolean;
    Connections:TThreadList;
destructor TWLConnection.Destroy;
var Items:TList;
begin
  Items:=Connections.LockList;
  try Items.Remove(Self);inherited Destroy;
  finally Connections.UnlockList;end;
end;
function TWLServer.CreateConnection(Data:TSocketStream):TFPHTTPConnection;
begin Result:=TWLConnection.Create(Self,Data);Connections.Add(Result);end;
function TWLHandler.CreateServer:TEmbeddedHttpServer;
begin Result:=TWLServer.Create(Self);end;
function TWLApplication.InitializeWebHandler:TWebHandler;
begin Result:=TWLHandler.Create(Self);end;
procedure ShutdownConnections;
var Items:TList;i:Integer;
begin
  Items:=Connections.LockList;
  try
    // Shutdown wakes a read in another thread; close alone need not do so.
    // Hold the lifecycle lock until all handles are used, preventing fd reuse.
    for i:=0 to Items.Count-1 do fpShutdown(TWLConnection(Items[i]).Socket.Handle,2);
  finally Connections.UnlockList;end;
end;
procedure StopSignal(Number:LongInt);cdecl;
begin Requested:=1;end;
procedure TStopEvents.Idle(Sender:TObject);
begin if Requested<>0 then Application.Terminate;end;
procedure TStopEvents.AllowConnect(Sender:TObject;Socket:LongInt;var Allow:Boolean);
begin
  if Requested<>0 then begin Allow:=False;Application.Terminate;end;
end;
procedure RestoreSignals;
begin
  if IntInstalled then begin fpSigAction(SIGINT,@OldInt,nil);IntInstalled:=False;end;
  if TermInstalled then begin fpSigAction(SIGTERM,@OldTerm,nil);TermInstalled:=False;end;
end;
{$ENDIF}
procedure StartHTTPStop;
{$IFDEF UNIX}var Action:SigActionRec;{$ENDIF}
begin
  {$IFDEF UNIX}
  Requested:=0;FillChar(Action,SizeOf(Action),0);
  Action.sa_handler:=SigActionHandler(@StopSignal);Action.sa_flags:=SA_RESTART;
  fpSigEmptySet(Action.sa_mask);
  if fpSigAction(SIGTERM,@Action,@OldTerm)<>0 then RaiseLastOSError;
  TermInstalled:=True;
  if fpSigAction(SIGINT,@Action,@OldInt)<>0 then
  begin RestoreSignals;RaiseLastOSError;end;
  IntInstalled:=True;
  Events:=TStopEvents.Create;
  Application.AcceptIdleTimeout:=100;
  Application.OnAcceptIdle:=@Events.Idle;
  Application.OnAllowConnect:=@Events.AllowConnect;
  {$ENDIF}
end;
procedure FinishHTTPStop;
{$IFDEF UNIX}var Deadline:QWord;{$ENDIF}
begin
  if Application<>nil then
  begin
    Application.Terminate;
    {$IFDEF UNIX}
    Deadline:=GetTickCount64+1000;
    while (TWLServer(Application.HTTPHandler.HTTPServer).ConnectionCount>0) and
      (GetTickCount64<Deadline) do Sleep(10);
    ShutdownConnections;
    {$ENDIF}
    // Drain framework threads before tenant database handles are finalized.
    if CustomApplication=Application then CustomApplication:=nil;
    FreeAndNil(Application);
  end;
end;
procedure DoneHTTPStop;
begin
  {$IFDEF UNIX}RestoreSignals;FreeAndNil(Events);{$ENDIF}
end;
{$IFDEF UNIX}
procedure InitApplication;
var Previous:THTTPApplication;
begin
  Connections:=TThreadList.Create;
  Previous:=Application;Application:=TWLApplication.Create(nil);
  if CustomApplication=Previous then CustomApplication:=Application;
  Previous.Free;
end;
initialization InitApplication;
finalization FinishHTTPStop;DoneHTTPStop;Connections.Free;
{$ENDIF}
end.
