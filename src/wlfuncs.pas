unit wlfuncs;
{$mode objfpc}{$H+}
interface
uses SysUtils,ctypes,wlsjson {$IFNDEF WLSQLEXT},sqlite3{$ENDIF};
{$IFDEF WLSQLEXT}
function LoadFunctions(Db,ApiTable:Pointer):cint;
{$ELSE}
function RegisterFunctions(Db:Pointer):Boolean;
{$ENDIF}
implementation
type
  TFunc=procedure(Context:Pointer;Count:cint;Args:Pointer);cdecl;
  TCreateFunc=function(Db:Pointer;Name:PAnsiChar;Count,Flags:cint;App:Pointer;
    Func:TFunc;Step,Final,Destroy:Pointer):cint;cdecl;
  TVersion=function:cint;cdecl;
  TValueText=function(Value:Pointer):PAnsiChar;cdecl;
  TValueBytes=function(Value:Pointer):cint;cdecl;
  TResultText=procedure(Context:Pointer;Value:PAnsiChar;Count:cint;Destroy:Pointer);cdecl;
  TResultError=procedure(Context:Pointer;Value:PAnsiChar;Count:cint);cdecl;
  TArgs=array[0..2] of Pointer;PArgs=^TArgs;
  TApi=array[0..162] of Pointer;PApi=^TApi;
var
  CreateFunc:TCreateFunc;ValueText:TValueText;ValueBytes:TValueBytes;
  ResultText:TResultText;ResultError:TResultError;
function ReadArg(Value:Pointer):string;
var Text:PAnsiChar;Count:cint;
begin
  Text:=ValueText(Value);Count:=ValueBytes(Value);
  if Count>16*1024*1024 then raise Exception.Create('Oversized typed document');
  if Text=nil then Result:='' else SetString(Result,Text,Count);
end;
procedure TypedFunc(Context:Pointer;Count:cint;Args:Pointer);cdecl;
var Value:string;
begin
  try
    if Count<>3 then raise Exception.Create('Invalid argument count');
    Value:=TypedDocument(ReadArg(PArgs(Args)^[0]),ReadArg(PArgs(Args)^[1]),ReadArg(PArgs(Args)^[2]));
    ResultText(Context,PAnsiChar(Value),Length(Value),Pointer(PtrInt(-1))); // SQLITE_TRANSIENT
  except ResultError(Context,'Invalid typed document',-1);end;
end;
procedure PlainFunc(Context:Pointer;Count:cint;Args:Pointer);cdecl;
var Value:string;
begin
  try
    if Count<>1 then raise Exception.Create('Invalid argument count');
    Value:=PlainDocument(ReadArg(PArgs(Args)^[0]));
    ResultText(Context,PAnsiChar(Value),Length(Value),Pointer(PtrInt(-1)));
  except ResultError(Context,'Invalid typed document',-1);end;
end;
function RegisterAll(Db:Pointer):cint;
const Flags=1 or $800 or $200000; // UTF8, deterministic, innocuous (no external state)
begin
  Result:=CreateFunc(Db,'wl_sjson',3,Flags,nil,@TypedFunc,nil,nil,nil);
  if Result=0 then Result:=CreateFunc(Db,'wl_plain',1,Flags,nil,@PlainFunc,nil,nil,nil);
end;
{$IFDEF WLSQLEXT}
function LoadFunctions(Db,ApiTable:Pointer):cint;
var Version:TVersion;
begin
  if ApiTable=nil then Exit(1);
  Pointer(Version):=PApi(ApiTable)^[67];
  if not Assigned(Version) then Exit(1);
  if Version()<3035000 then Exit(1);
  // Stable sqlite3_api_routines offsets from sqlite3ext.h, verified by the C ABI test.
  // Use the host table, never a separately linked SQLite library on its connection.
  Pointer(CreateFunc):=PApi(ApiTable)^[162];Pointer(ValueText):=PApi(ApiTable)^[109];
  Pointer(ValueBytes):=PApi(ApiTable)^[103];Pointer(ResultText):=PApi(ApiTable)^[85];
  Pointer(ResultError):=PApi(ApiTable)^[80];
  if not Assigned(CreateFunc) or not Assigned(ValueText) or not Assigned(ValueBytes) or
    not Assigned(ResultText) or not Assigned(ResultError) then Exit(1);
  Result:=RegisterAll(Db);
end;
{$ELSE}
function RegisterFunctions(Db:Pointer):Boolean;
begin Result:=RegisterAll(Db)=0;end;
initialization
  CreateFunc:=TCreateFunc(@sqlite3_create_function_v2);ValueText:=TValueText(@sqlite3_value_text);
  ValueBytes:=TValueBytes(@sqlite3_value_bytes);ResultText:=TResultText(@sqlite3_result_text);
  ResultError:=TResultError(@sqlite3_result_error);
{$ENDIF}
end.
