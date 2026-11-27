unit wlthumb;
{$mode objfpc}{$H+}
interface

uses HTTPDefs, Classes, Types;

function RenderAttachmentThumbnail(Output: TStream; const Path, MimeType: string;
  PreferWebP: Boolean; out Size: TPoint; out OutputType: string): Boolean;
function SendAttachmentThumbnail(Response: TResponse; const Path, MimeType: string): Boolean;

implementation

uses SysUtils, Math, FPImage, FPReadPNG, FPReadJPEG, FPReadBMP, FPWritePNG, Dynlibs, CTypes;

const
  MaxInputBytes = 32 * 1024 * 1024;
  MaxPixels = 16000000;
  Edge = 512;

type
  TWebPCodec = record
    Lib: TLibHandle;
    GetInfo: function(Data: PByte; Length: SizeUInt; W, H: Pcint): cint; cdecl;
    DecodeRGBA: function(Data: PByte; Length: SizeUInt; Pixels: PByte; Capacity: SizeUInt; Stride: cint): PByte; cdecl;
    EncodeRGBA: function(Pixels: PByte; W, H, Stride: cint; Quality: cfloat; out Data: PByte): SizeUInt; cdecl;
    Release: procedure(Data: Pointer); cdecl;
  end;

function LoadWebP: TWebPCodec;
begin
  Result := Default(TWebPCodec);
  {$IFDEF LINUX}
  Result.Lib := LoadLibrary('libwebp.so.7');
  if Result.Lib = NilHandle then Exit;
  Pointer(Result.GetInfo) := GetProcedureAddress(Result.Lib, 'WebPGetInfo');
  Pointer(Result.DecodeRGBA) := GetProcedureAddress(Result.Lib, 'WebPDecodeRGBAInto');
  Pointer(Result.EncodeRGBA) := GetProcedureAddress(Result.Lib, 'WebPEncodeRGBA');
  Pointer(Result.Release) := GetProcedureAddress(Result.Lib, 'WebPFree');
  if not (Assigned(Result.GetInfo) and Assigned(Result.DecodeRGBA) and Assigned(Result.EncodeRGBA) and Assigned(Result.Release)) then
  begin
    UnloadLibrary(Result.Lib);
    Result := Default(TWebPCodec);
  end;
  {$ENDIF}
end;

function ValidSize(const Size: TPoint): Boolean;
begin
  Result := (Size.X > 0) and (Size.Y > 0) and (Int64(Size.X) * Size.Y <= MaxPixels);
end;

function ReadWebP(const Codec: TWebPCodec; Stream: TStream; out Size: TPoint; out Pixels: TBytes): Boolean;
var Data: TBytes; W, H: cint;
begin
  Result := False;
  if Codec.Lib = NilHandle then Exit;
  SetLength(Data, Stream.Size);
  Stream.ReadBuffer(Data[0], Length(Data));
  if Codec.GetInfo(@Data[0], Length(Data), @W, @H) = 0 then Exit;
  Size := Point(W, H);
  if not ValidSize(Size) then Exit;
  SetLength(Pixels, W * H * 4);
  Result := Codec.DecodeRGBA(@Data[0], Length(Data), @Pixels[0], Length(Pixels), W * 4) <> nil;
end;

function WriteWebP(const Codec: TWebPCodec; Image: TFPMemoryImage; Output: TStream): Boolean;
var Pixels: TBytes; Color: TFPColor; Data: PByte; Count: SizeUInt; X, Y, Offset: Integer;
begin
  Result := False;
  if Codec.Lib = NilHandle then Exit;
  SetLength(Pixels, Image.Width * Image.Height * 4);
  Offset := 0;
  for Y := 0 to Image.Height - 1 do
    for X := 0 to Image.Width - 1 do
    begin
      Color := Image.Colors[X, Y];
      Pixels[Offset] := Color.Red shr 8;
      Pixels[Offset + 1] := Color.Green shr 8;
      Pixels[Offset + 2] := Color.Blue shr 8;
      Pixels[Offset + 3] := Color.Alpha shr 8;
      Inc(Offset, 4);
    end;
  Data := nil;
  try
    Count := Codec.EncodeRGBA(@Pixels[0], Image.Width, Image.Height, Image.Width * 4, 80, Data);
    if (Count = 0) or (Data = nil) then Exit;
    Output.WriteBuffer(Data^, Count);
    Result := True;
  finally
    if Data <> nil then Codec.Release(Data);
  end;
end;

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

// The common uncompressed, 24-bit Windows bitmap with a BITMAPINFOHEADER.
function BMPSize(Stream: TStream): TPoint;
var Header: array[0..53] of Byte; Width, Height: LongInt; Stride: Int64;
  function LE32(Offset: Integer): Cardinal;
  begin
    Result := Cardinal(Header[Offset]) or (Cardinal(Header[Offset+1]) shl 8) or
      (Cardinal(Header[Offset+2]) shl 16) or (Cardinal(Header[Offset+3]) shl 24);
  end;
begin
  Result := Point(0, 0);
  Stream.ReadBuffer(Header, SizeOf(Header));
  if (Header[0] <> Ord('B')) or (Header[1] <> Ord('M')) or (LE32(10) <> SizeOf(Header)) or (LE32(14) <> 40) or
    (LE32(26) <> $00180001) or (LE32(30) <> 0) then Exit;
  Width := LongInt(LE32(18));
  Height := LongInt(LE32(22));
  if (Width <= 0) or (Height = 0) or (Height = Low(LongInt)) then Exit;
  Height := Abs(Height);
  if not ValidSize(Point(Width, Height)) then Exit;
  Stride := (Int64(Width) * 3 + 3) and not Int64(3);
  if Stride * Height <= Stream.Size - SizeOf(Header) then Result := Point(Width, Height);
end;

function RenderAttachmentThumbnail(Output: TStream; const Path, MimeType: string;
  PreferWebP: Boolean; out Size: TPoint; out OutputType: string): Boolean;
var Input: TFileStream; Source, Preview: TFPMemoryImage;
  Reader: TFPCustomImageReader; Writer: TFPWriterPNG; W, H, X, Y, SX, SY, Offset: Integer;
  Codec: TWebPCodec; Pixels: TBytes; Color: TFPColor;
begin
  Result := False;
  if (MimeType <> 'image/png') and (MimeType <> 'image/jpeg') and (MimeType <> 'image/pjpeg') and
    (MimeType <> 'image/webp') and (MimeType <> 'image/bmp') then Exit;
  Input := nil;
  Source := nil;
  Preview := nil;
  Reader := nil;
  Writer := nil;
  Codec := Default(TWebPCodec);
  if PreferWebP or (MimeType = 'image/webp') then Codec := LoadWebP;
  try
    try
      Input := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
      if (Input.Size = 0) or (Input.Size > MaxInputBytes) then Exit;
      if MimeType = 'image/webp' then
      begin
        if not ReadWebP(Codec, Input, Size, Pixels) then Exit;
      end
      else
      begin
        if MimeType = 'image/png' then
        begin
          Size := PNGSize(Input);
          Reader := TFPReaderPNG.Create;
        end
        else if MimeType = 'image/bmp' then
        begin
          Size := BMPSize(Input);
          Reader := TFPReaderBMP.Create;
        end
        else
        begin
          Size := TFPReaderJPEG.ImageSize(Input);
          Reader := TFPReaderJPEG.Create;
        end;
        if not ValidSize(Size) then Exit;
        Input.Position := 0;
        Source := TFPMemoryImage.Create(0, 0);
        Source.LoadFromStream(Input, Reader);
        // The JPEG reader already applies EXIF orientation. Its header-size
        // probe reports the unrotated dimensions.
        if (Reader is TFPReaderJPEG) and (Source.Width = Size.Y) and (Source.Height = Size.X) then
          Size := Point(Source.Width, Source.Height);
        if (Source.Width <> Size.X) or (Source.Height <> Size.Y) then Exit;
      end;
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
        begin
          SX := X * Int64(Size.X) div W;
          SY := Y * Int64(Size.Y) div H;
          if Source <> nil then Color := Source.Colors[SX, SY]
          else
          begin
            Offset := (SY * Size.X + SX) * 4;
            Color.Red := Pixels[Offset] * 257;
            Color.Green := Pixels[Offset + 1] * 257;
            Color.Blue := Pixels[Offset + 2] * 257;
            Color.Alpha := Pixels[Offset + 3] * 257;
          end;
          Preview.Colors[X, Y] := Color;
        end;
      if PreferWebP and WriteWebP(Codec, Preview, Output) then OutputType := 'image/webp'
      else
      begin
        OutputType := 'image/png';
        Writer := TFPWriterPNG.Create;
        Writer.UseAlpha := True;
        Preview.SaveToStream(Output, Writer);
      end;
    except
      Exit;
    end;
    Size := Point(W, H);
    Output.Position := 0;
    Result := True;
  finally
    Writer.Free;
    Reader.Free;
    Preview.Free;
    Source.Free;
    Input.Free;
    if Codec.Lib <> NilHandle then UnloadLibrary(Codec.Lib);
  end;
end;

function SendAttachmentThumbnail(Response: TResponse; const Path, MimeType: string): Boolean;
var Output: TMemoryStream; Size: TPoint; OutputType: string;
begin
  Output := TMemoryStream.Create;
  try
    if not RenderAttachmentThumbnail(Output, Path, MimeType, True, Size, OutputType) then Exit(False);
    Output.Position := 0;
    Response.ContentType := OutputType;
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
  end;
end;

end.
