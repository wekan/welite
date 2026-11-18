unit wlstore;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,HTTPDefs,wlcrypt;
// Full SHA-256 IDs split into 8-character components: stable across platforms,
// case-sensitive database IDs remain distinct on case-insensitive filesystems.
function StoreFilePath(const FilesDir,Kind,Id:string):string;
function SendStoredDownload(Response:TResponse;const Path:string;const Name:string=''):Boolean;
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
function SendStoredDownload(Response:TResponse;const Path,Name:string):Boolean;
var Stream:TFileStream;Header,Encoded:string;C:Char;
begin
  try Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  except on EFOpenError do Exit(False);end;
  Response.FreeContentStream:=True;
  Response.ContentStream:=Stream;
  Response.Code:=200;
  Response.ContentType:='application/octet-stream';
  Header:='attachment';
  if (Name<>'') and (Length(Name)<=255) then
  begin
    Encoded:='';
    for C in Name do
      case C of
        'A'..'Z','a'..'z','0'..'9','-','.','_':Encoded:=Encoded+C;
        #0..#31,#127,'/','\':Encoded:=Encoded+'_';
      else Encoded:=Encoded+'%'+IntToHex(Ord(C),2);end;
    Header:=Header+'; filename="attachment"; filename*=UTF-8'+Chr(39)+Chr(39)+Encoded;
  end;
  Response.SetCustomHeader('Content-Disposition',Header);
  Response.SetCustomHeader('Cache-Control','private, no-store');
  Response.SetCustomHeader('X-Content-Type-Options','nosniff');
  Response.SendContent;
  Result:=True;
end;
end.
