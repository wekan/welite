unit wlstore;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,HTTPDefs,wlcrypt,wlsvg;
// Full SHA-256 IDs split into 8-character components: stable across platforms,
// case-sensitive database IDs remain distinct on case-insensitive filesystems.
function StoreFilePath(const FilesDir,Kind,Id:string):string;
function SendStoredDownload(Response:TResponse;const Path:string;const Name:string='';const PreviewType:string=''):Boolean;
function RasterAttachment(const FileType:string):Boolean;
// An SVG attachment as an image (server/lib/svgResponse.js): the whole file
// sanitized on its way out, whatever is stored, under a policy that lets
// nothing run or load, inline unless Download - a download is sanitized too.
// False when it is not a well-formed SVG (then it is only downloaded) or not
// there. Changed and Removed say whether the stored file had active content.
function SendSvgImage(Response:TResponse;const Path,Name:string;Download:Boolean;out Changed:Boolean;out Removed:string):Boolean;
implementation
function RasterAttachment(const FileType:string):Boolean;
begin
  Result:=(FileType='image/png') or (FileType='image/jpeg') or
    (FileType='image/gif') or (FileType='image/webp') or (FileType='image/bmp');
end;
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
function DispositionName(const Name:string):string;
var Encoded:string;C:Char;
begin
  Result:='';
  if (Name='') or (Length(Name)>255) then Exit;
  Encoded:='';
  for C in Name do
    case C of
      'A'..'Z','a'..'z','0'..'9','-','.','_':Encoded:=Encoded+C;
      #0..#31,#127,'/','\':Encoded:=Encoded+'_';
    else Encoded:=Encoded+'%'+IntToHex(Ord(C),2);end;
  Result:='; filename="attachment"; filename*=UTF-8'+Chr(39)+Chr(39)+Encoded;
end;
function SendSvgImage(Response:TResponse;const Path,Name:string;Download:Boolean;out Changed:Boolean;out Removed:string):Boolean;
var Stream:TFileStream;Raw,Clean:string;
begin
  Result:=False;Changed:=False;Removed:='';
  try Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  except on EFOpenError do Exit;end;
  try
    if Stream.Size>MAX_SVG_BYTES then Exit;
    SetLength(Raw,Stream.Size);
    if Length(Raw)>0 then Stream.ReadBuffer(Raw[1],Length(Raw));
  finally Stream.Free;end;
  if not SanitizeSvg(Raw,Clean,Changed,Removed) then Exit;
  Response.Code:=200;
  Response.ContentType:='image/svg+xml';
  Response.Content:=Clean;
  Response.ContentLength:=Length(Clean);
  if Download then Response.SetCustomHeader('Content-Disposition','attachment'+DispositionName(Name))
  else Response.SetCustomHeader('Content-Disposition','inline');
  Response.SetCustomHeader('Content-Security-Policy',SVG_POLICY);
  Response.SetCustomHeader('X-Content-Type-Options','nosniff');
  Response.SetCustomHeader('X-Frame-Options','DENY');
  Response.SetCustomHeader('Cache-Control','private, no-store');
  Response.SendContent;
  Result:=True;
end;
function SendStoredDownload(Response:TResponse;const Path,Name,PreviewType:string):Boolean;
var Stream:TFileStream;Header,Encoded:string;C:Char;
begin
  try Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  except on EFOpenError do Exit(False);end;
  Response.FreeContentStream:=True;
  Response.ContentStream:=Stream;
  Response.Code:=200;
  Response.ContentType:='application/octet-stream';
  Header:='attachment';
  if RasterAttachment(PreviewType) then
  begin
    Response.ContentType:=PreviewType;
    Header:='inline';
  end;
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
