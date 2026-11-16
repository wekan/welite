unit wlfuncs;
{$mode objfpc}{$H+}
interface
uses SysUtils,ctypes,wlsjson,wlproj,wlresume {$IFNDEF WLSQLEXT},sqlite3{$ENDIF};
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
  TContextDb=function(Context:Pointer):Pointer;cdecl;
  TColumnMeta=function(Db:Pointer;Database,TableName,ColumnName:PAnsiChar;DataType,Collation:PPAnsiChar;NotNull,PrimaryKey,AutoInc:Pcint):cint;cdecl;
  TValueText=function(Value:Pointer):PAnsiChar;cdecl;
  TValueBytes=function(Value:Pointer):cint;cdecl;
  TResultText=procedure(Context:Pointer;Value:PAnsiChar;Count:cint;Destroy:Pointer);cdecl;
  TResultError=procedure(Context:Pointer;Value:PAnsiChar;Count:cint);cdecl;
  TArgs=array[0..3] of Pointer;PArgs=^TArgs;
  TApi=array[0..162] of Pointer;PApi=^TApi;
var
  CreateFunc:TCreateFunc;ValueText:TValueText;ValueBytes:TValueBytes;
  ResultText:TResultText;ResultError:TResultError;ContextDb:TContextDb;ColumnMeta:TColumnMeta;
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
procedure ModelFunc(Context:Pointer;Count:cint;Args:Pointer);cdecl;
var Value:string;
begin
  try
    if Count<>4 then raise Exception.Create('Invalid argument count');
    Value:=ProjectDocument(ReadArg(PArgs(Args)^[0]),ReadArg(PArgs(Args)^[1]),ReadArg(PArgs(Args)^[2]),ReadArg(PArgs(Args)^[3]));
    ResultText(Context,PAnsiChar(Value),Length(Value),Pointer(PtrInt(-1)));
  except ResultError(Context,'Invalid model projection',-1);end;
end;
procedure RelationFunc(Context:Pointer;Count:cint;Args:Pointer);cdecl;
var Value:string;
begin
  try
    if Count<>3 then raise Exception.Create('Invalid argument count');
    Value:=RelationDocument(ReadArg(PArgs(Args)^[0]),ReadArg(PArgs(Args)^[1]),ReadArg(PArgs(Args)^[2]));
    ResultText(Context,PAnsiChar(Value),Length(Value),Pointer(PtrInt(-1)));
  except ResultError(Context,'Invalid relation projection',-1);end;
end;
procedure ResumeFunc(Context:Pointer;Count:cint;Args:Pointer);cdecl;
var Value:string;
begin
  try
    if Count<>2 then raise Exception.Create('Invalid argument count');
    Value:=ResumeDocument(ReadArg(PArgs(Args)^[0]),ReadArg(PArgs(Args)^[1]));
    ResultText(Context,PAnsiChar(Value),Length(Value),Pointer(PtrInt(-1)));
  except ResultError(Context,'Invalid resume token document',-1);end;
end;
procedure ResumeCheckFunc(Context:Pointer;Count:cint;Args:Pointer);cdecl;
var Value:string;At,Life,Stamp,Expiration:Int64;
begin
  try
    if Count<>4 then raise Exception.Create('Invalid argument count');
    if not TryStrToInt64(ReadArg(PArgs(Args)^[2]),At) or not TryStrToInt64(ReadArg(PArgs(Args)^[3]),Life) then raise Exception.Create('Invalid time');
    Value:=ResumeStateName(CheckResumeToken(ReadArg(PArgs(Args)^[0]),ReadArg(PArgs(Args)^[1]),At,Life,Stamp,Expiration));
    ResultText(Context,PAnsiChar(Value),Length(Value),Pointer(PtrInt(-1)));
  except ResultError(Context,'Invalid resume token check',-1);end;
end;
procedure StorageFunc(Context:Pointer;Count:cint;Args:Pointer);cdecl;
var Name,Value:string;DataType:PAnsiChar;Db:Pointer;
begin
  try
    if Count<>1 then raise Exception.Create('Invalid argument count');
    Name:=ReadArg(PArgs(Args)^[0]);if (Name='') or (Pos(#0,Name)>0) then raise Exception.Create('Invalid table name');
    Db:=ContextDb(Context);DataType:=nil;
    if ColumnMeta(Db,'main',PAnsiChar(Name),'_ferretdb_sjson',@DataType,nil,nil,nil,nil)<>0 then
      raise Exception.Create('Missing document column');
    if DataType=nil then raise Exception.Create('Missing declared type');
    Value:=LowerCase(string(DataType));
    if (Value<>'blob') and (Value<>'text') then raise Exception.Create('Unsupported storage');
    ResultText(Context,PAnsiChar(Value),Length(Value),Pointer(PtrInt(-1)));
  except ResultError(Context,'Invalid document storage',-1);end;
end;
function RegisterAll(Db:Pointer):cint;
const Flags=1 or $800 or $200000; // UTF8, deterministic, innocuous (no external state)
begin
  Result:=CreateFunc(Db,'wl_sjson',3,Flags,nil,@TypedFunc,nil,nil,nil);
  if Result=0 then Result:=CreateFunc(Db,'wl_plain',1,Flags,nil,@PlainFunc,nil,nil,nil);
  if Result=0 then Result:=CreateFunc(Db,'wl_model',4,Flags,nil,@ModelFunc,nil,nil,nil);
  if Result=0 then Result:=CreateFunc(Db,'wl_relation',3,Flags,nil,@RelationFunc,nil,nil,nil);
  if Result=0 then Result:=CreateFunc(Db,'wl_resume',2,Flags,nil,@ResumeFunc,nil,nil,nil);
  if Result=0 then Result:=CreateFunc(Db,'wl_rescheck',4,Flags,nil,@ResumeCheckFunc,nil,nil,nil);
  // Schema state can change: innocuous, but deliberately NOT deterministic.
  if Result=0 then Result:=CreateFunc(Db,'wl_storage',1,1 or $200000,nil,@StorageFunc,nil,nil,nil);
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
  Pointer(ContextDb):=PApi(ApiTable)^[149];Pointer(ColumnMeta):=PApi(ApiTable)^[95];
  if not Assigned(CreateFunc) or not Assigned(ValueText) or not Assigned(ValueBytes) or
    not Assigned(ResultText) or not Assigned(ResultError) or not Assigned(ContextDb) or not Assigned(ColumnMeta) then Exit(1);
  Result:=RegisterAll(Db);
end;
{$ELSE}
function RegisterFunctions(Db:Pointer):Boolean;
begin Result:=RegisterAll(Db)=0;end;
initialization
  CreateFunc:=TCreateFunc(@sqlite3_create_function_v2);ValueText:=TValueText(@sqlite3_value_text);
  ValueBytes:=TValueBytes(@sqlite3_value_bytes);ResultText:=TResultText(@sqlite3_result_text);
  ResultError:=TResultError(@sqlite3_result_error);ContextDb:=TContextDb(@sqlite3_context_db_handle);
  ColumnMeta:=TColumnMeta(@sqlite3_table_column_metadata);
{$ENDIF}
end.
