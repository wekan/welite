unit wlthumb;
{$mode objfpc}{$H+}
interface

uses HTTPDefs;

function SendAttachmentThumbnail(Response: TResponse; const Path, MimeType: string): Boolean;

implementation

uses Classes, SysUtils, Types, Math, FPImage, FPReadPNG, FPReadJPEG, FPWritePNG;

const
  MaxInputBytes = 32 * 1024 * 1024;
  MaxPixels = 16000000;
  Edge = 512;

function ReadBE32(Stream: TStream): Cardinal;
var B: array[0..3] of Byte;
begin
  Stream.ReadBuffer(B, SizeOf(B));
  Result := (Cardinal(B[0]) shl 24) or (Cardinal(B[1]) shl 16) or (Cardinal(B[2]) shl 8) or B[3];
end;

// Check full-width dimensions and chunk sizes before the PNG reader allocates.
function PNGSize(Stream: TStream): TPoint;
const Signature: array[0..7] of Byte = (137, 80, 78, 71, 13, 10, 26, 10);
var Header: array[0..7] of Byte; Kind: string[4]; N, W, H: Cardinal; First: Boolean;
begin
  Result := Point(0, 0);
  Stream.ReadBuffer(Header, SizeOf(Header));
  if not CompareMem(@Header[0], @Signature[0], SizeOf(Header)) then Exit;
  First := True;
  repeat
    N := ReadBE32(Stream);
    SetLength(Kind, 4);
    Stream.ReadBuffer(Kind[1], 4);
    if Int64(N) + 4 > Stream.Size - Stream.Position then Exit(Point(0, 0));
    if First then
    begin
      if (Kind <> 'IHDR') or (N <> 13) then Exit;
      W := ReadBE32(Stream);
      H := ReadBE32(Stream);
      if (W = 0) or (H = 0) or (W > MaxPixels) or (H > MaxPixels) or
        (Int64(W) * H > MaxPixels) then Exit;
      Result := Point(W, H);
      Dec(N, 8);
      First := False;
    end
    else if Kind = 'IHDR' then Exit(Point(0, 0));
    Stream.Seek(Int64(N) + 4, soCurrent);
  until Kind = 'IEND';
end;

function SendAttachmentThumbnail(Response: TResponse; const Path, MimeType: string): Boolean;
var Input: TFileStream; Output: TMemoryStream; Source, Preview: TFPMemoryImage;
  Reader: TFPCustomImageReader; Writer: TFPWriterPNG; Size: TPoint; W, H, X, Y: Integer;
begin
  Result := False;
  if (MimeType <> 'image/png') and (MimeType <> 'image/jpeg') then Exit;
  Input := nil;
  Output := nil;
  Source := nil;
  Preview := nil;
  Reader := nil;
  Writer := nil;
  try
    try
      Input := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
      if (Input.Size = 0) or (Input.Size > MaxInputBytes) then Exit;
      if MimeType = 'image/png' then
      begin
        Size := PNGSize(Input);
        Reader := TFPReaderPNG.Create;
      end
      else
      begin
        Size := TFPReaderJPEG.ImageSize(Input);
        Reader := TFPReaderJPEG.Create;
      end;
      if (Size.X < 1) or (Size.Y < 1) or (Int64(Size.X) * Size.Y > MaxPixels) then Exit;
      Input.Position := 0;
      Source := TFPMemoryImage.Create(0, 0);
      Source.LoadFromStream(Input, Reader);
      if (Source.Width <> Size.X) or (Source.Height <> Size.Y) then Exit;
      W := Size.X;
      H := Size.Y;
      if Max(W, H) > Edge then
        if W >= H then
        begin H := Max(1, Int64(H) * Edge div W); W := Edge; end
        else
        begin W := Max(1, Int64(W) * Edge div H); H := Edge; end;
      Preview := TFPMemoryImage.Create(W, H);
      for Y := 0 to H - 1 do
        for X := 0 to W - 1 do
          Preview.Colors[X,Y] := Source.Colors[X * Int64(Size.X) div W, Y * Int64(Size.Y) div H];
      Writer := TFPWriterPNG.Create;
      Writer.UseAlpha := True;
      Output := TMemoryStream.Create;
      Preview.SaveToStream(Output, Writer);
    except
      Exit;
    end;
    Output.Position := 0;
    Response.ContentType := 'image/png';
    Response.Code := 200;
    Response.SetCustomHeader('Cache-Control', 'private, no-store');
    Response.SetCustomHeader('X-Content-Type-Options', 'nosniff');
    Response.SetCustomHeader('Content-Security-Policy', 'default-src ''none''; sandbox');
    Response.FreeContentStream := True;
    Response.ContentStream := Output;
    Output := nil;
    Response.SendContent;
    Result := True;
  finally
    Output.Free;
    Writer.Free;
    Reader.Free;
    Preview.Free;
    Source.Free;
    Input.Free;
  end;
end;

end.
