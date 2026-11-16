unit wlstore;
{$mode objfpc}{$H+}
interface
uses SysUtils,wlcrypt;
// Full SHA-256 IDs split into 8-character components: stable across platforms,
// case-sensitive database IDs remain distinct on case-insensitive filesystems.
function StoreFilePath(const FilesDir,Kind,Id:string):string;
implementation
function StoreFilePath(const FilesDir,Kind,Id:string):string;
var Digest:string;i:Integer;
begin
  if (Id='') or not ((Kind='attachme') or (Kind='avatars')) then
    raise Exception.Create('Invalid file-store key');
  Digest:=Sha256Hex(RawByteString(Id));
  Result:=IncludeTrailingPathDelimiter(FilesDir)+Kind+PathDelim;
  for i:=0 to 6 do Result:=Result+Copy(Digest,i*8+1,8)+PathDelim;
  Result:=Result+Copy(Digest,57,8)+'.bin';
end;
end.
