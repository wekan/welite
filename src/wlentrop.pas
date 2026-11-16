unit wlentrop;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,wldb {$IFDEF UNIX},BaseUnix{$ENDIF} {$IFDEF MSWINDOWS},Dynlibs{$ENDIF};
function SecureBytes(Count:Integer):RawByteString;
procedure CreateEntropyStock(const FileName:string; ByteCount:Int64);
implementation
function HexBytes(const Value:RawByteString):string;
var i:Integer;
begin
  Result:='';for i:=1 to Length(Value) do Result:=Result+IntToHex(Ord(Value[i]),2);
end;
function NativeBytes(Count:Integer):RawByteString;
{$IFDEF MSWINDOWS}
type
  TBCryptRandom=function(Algorithm:Pointer; Buffer:Pointer; Size,Flags:LongWord):LongInt;stdcall;
  TRtlRandom=function(Buffer:Pointer; Size:LongWord):Byte;stdcall;
var Lib:TLibHandle; Bcrypt:TBCryptRandom; Rtl:TRtlRandom; Ok:Boolean;
{$ELSE}
{$IFDEF UNIX}var Source:TFileStream;{$ENDIF}
{$ENDIF}
begin
  if (Count<1) or (Count>4096) then raise Exception.Create('Invalid entropy request');
  SetLength(Result,Count);
  {$IFNDEF WLNOOSRAND}
  {$IFDEF MSWINDOWS}
  Ok:=False;Lib:=LoadLibrary('bcrypt.dll');
  if Lib<>NilHandle then
  try
    Pointer(Bcrypt):=GetProcedureAddress(Lib,'BCryptGenRandom');
    if Assigned(Bcrypt) then Ok:=Bcrypt(nil,@Result[1],Count,2)=0;
  finally UnloadLibrary(Lib);end;
  if not Ok then
  begin
    Lib:=LoadLibrary('advapi32.dll');
    if Lib<>NilHandle then
    try
      Pointer(Rtl):=GetProcedureAddress(Lib,'SystemFunction036');
      if Assigned(Rtl) then Ok:=Rtl(@Result[1],Count)<>0;
    finally UnloadLibrary(Lib);end;
  end;
  if Ok then Exit;
  {$ELSE}
  {$IFDEF UNIX}
  try
    Source:=TFileStream.Create('/dev/urandom',fmOpenRead or fmShareDenyNone);
    try Source.ReadBuffer(Result[1],Count);finally Source.Free;end;
    Exit;
  except end;
  {$ENDIF}
  {$ENDIF}
  {$ENDIF}
  Result:='';
  raise Exception.Create('Secure OS entropy is unavailable; configure WELITE_ENTROPY_FILE');
end;
function StockBytes(const FileName:string; Count:Integer):RawByteString;
var Db:TWLDb; Rows:TWLRows; Value:string; i,Hi,Lo:Integer;
begin
  Result:='';
  if not FileExists(FileName) then raise Exception.Create('Entropy stock is unavailable');
  Db:=TWLDb.Create(FileName,True);
  try
    if not Db.Exec('PRAGMA synchronous=FULL;') then raise Exception.Create('Entropy stock synchronization failed');
    // DELETE RETURNING is one atomic operation. Query exposes values only after the final
    // SQLITE_DONE/commit succeeds, so concurrent processes cannot receive the same block.
    Rows:=Db.Query('DELETE FROM entropy WHERE id=(SELECT MIN(id) FROM entropy) RETURNING hex(value);');
    if (Length(Rows)<>1) or (Length(Rows[0])<>1) then raise Exception.Create('Entropy stock exhausted or commit failed');
    Value:=Rows[0][0];
    if Length(Value)<>64 then raise Exception.Create('Invalid entropy stock block');
    SetLength(Result,Count);
    for i:=1 to Count do
    begin
      Hi:=StrToIntDef('$'+Value[2*i-1],-1); Lo:=StrToIntDef('$'+Value[2*i],-1);
      if (Hi<0) or (Lo<0) then raise Exception.Create('Invalid entropy stock block');
      Result[i]:=Chr(Hi*16+Lo);
    end;
  finally Db.Free;end;
end;
function SecureBytes(Count:Integer):RawByteString;
var FileName:string;
begin
  if (Count<1) or (Count>32) then raise Exception.Create('Invalid entropy request');
  FileName:=GetEnvironmentVariable('WELITE_ENTROPY_FILE');
  if FileName<>'' then Result:=StockBytes(FileName,Count) else Result:=NativeBytes(Count);
end;
procedure CreateEntropyStock(const FileName:string; ByteCount:Int64);
var Db:TWLDb; Lock,Sql:string; Bytes:RawByteString; Remaining:Int64; i,Amount:Integer; Created,Complete:Boolean; Empty:TFileStream;
begin
  if (ByteCount<32) or (ByteCount mod 32<>0) or (ByteCount>64*1024*1024) then
    raise Exception.Create('Entropy stock size must be a multiple of 32 between 32 bytes and 64 MiB');
  if LowerCase(ExtractFileExt(FileName))<>'.db' then raise Exception.Create('Entropy stock needs a .db filename');
  if not ForceDirectories(ExtractFileDir(ExpandFileName(FileName))) then raise Exception.Create('Could not create entropy directory');
  Lock:=ChangeFileExt(FileName,'.lck');
  if not CreateDir(Lock) then raise Exception.Create('Entropy stock creation is locked');
  Created:=False;Complete:=False;Db:=nil;
  try
    if FileExists(FileName) then raise Exception.Create('Entropy stock already exists; choose a fresh filename');
    // Check OS availability before creating any stock file. This never draws from a stock.
    Bytes:=NativeBytes(32);
    Empty:=TFileStream.Create(FileName,fmCreate);Empty.Free;Created:=True;
    {$IFDEF UNIX}
    if fpChmod(PChar(FileName),&600)<>0 then raise Exception.Create('Could not protect entropy stock permissions');
    {$ENDIF}
    Db:=TWLDb.Create(FileName,True);
    if not Db.Exec('PRAGMA synchronous=FULL; CREATE TABLE entropy(id INTEGER PRIMARY KEY,value BLOB NOT NULL CHECK(length(value)=32));') then
      raise Exception.Create('Could not create entropy stock');
    Remaining:=ByteCount;
    while Remaining>0 do
    begin
      Amount:=4096;if Remaining<Amount then Amount:=Remaining;
      Bytes:=NativeBytes(Amount);Sql:='BEGIN IMMEDIATE; ';
      i:=1;
      while i<=Length(Bytes) do
      begin
        Sql:=Sql+'INSERT INTO entropy(value) VALUES(X'+QuotedStr(HexBytes(Copy(Bytes,i,32)))+'); ';
        Inc(i,32);
      end;
      if not Db.Exec(Sql+'COMMIT;') then
      begin Db.Exec('ROLLBACK;');raise Exception.Create('Could not write entropy stock');end;
      Dec(Remaining,Amount);
    end;
    Complete:=True;
  finally
    Db.Free;
    if Created and not Complete then DeleteFile(FileName);
    RemoveDir(Lock);
  end;
end;
end.
