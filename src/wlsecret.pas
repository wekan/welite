unit wlsecret;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes {$IFDEF UNIX},BaseUnix{$ENDIF};
function ArgonSecret:RawByteString;
procedure WipeSecret(var Value:RawByteString);
implementation
procedure WipeSecret(var Value:RawByteString);
begin if Value<>'' then begin UniqueString(Value);FillChar(Value[1],Length(Value),0);Value:='';end;end;
function ArgonSecret:RawByteString;
var Name:string;Stream:THandleStream;Size:Int64;Extra:Byte;
{$IFDEF UNIX}Handle:cint;Info,Before:Stat;{$ENDIF}
begin
  Result:='';Name:=GetEnvironmentVariable('WELITE_ARGON_SECRET_FILE');if Name='' then Exit;
  Stream:=nil;
  {$IFDEF UNIX}
  if (fpLStat(PChar(Name),Before)<>0) or ((Before.st_mode and S_IFMT)<>S_IFREG) then
    raise Exception.Create('Argon2 secret must be a regular file');
  Handle:=fpOpen(PChar(Name),O_RDONLY or O_NONBLOCK {$IF DECLARED(O_NOFOLLOW)}or O_NOFOLLOW{$ENDIF});
  if Handle<0 then raise Exception.Create('Argon2 secret is unavailable');
  try
    if (fpFStat(Handle,Info)<>0) or ((Info.st_mode and S_IFMT)<>S_IFREG) or ((Info.st_mode and &077)<>0) or (Info.st_dev<>Before.st_dev) or (Info.st_ino<>Before.st_ino) then
      raise Exception.Create('Argon2 secret must be a private regular file');
    Stream:=THandleStream.Create(Handle);
  {$ELSE}
  try
    Stream:=TFileStream.Create(Name,fmOpenRead or fmShareDenyWrite);
  {$ENDIF}
    try
      Size:=Stream.Size;
      if (Size<1) or (Size>65536) then raise Exception.Create('Invalid Argon2 secret size');
      SetLength(Result,Size);Stream.ReadBuffer(Result[1],Size);
      if Stream.Read(Extra,1)<>0 then raise Exception.Create('Argon2 secret changed during read');
    except WipeSecret(Result);raise;end;
  finally Stream.Free;{$IFDEF UNIX}fpClose(Handle);{$ENDIF}end;
end;
end.
