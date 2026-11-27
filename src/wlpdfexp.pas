unit wlpdfexp;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface

uses Classes, Types, fppdf, wlcsvexp;

type
  TPdfCardWriter = class
  private
    Document: TPDFDocument;
    Page: TPDFPage;
    BodyFont, HeadingFont, WrapWidth: Integer;
    EmbeddedFont: Boolean;
    BundledFontDir: string;
    Y: Single;
    procedure RequireSpace(Height: Single);
  public
    constructor Create;
    destructor Destroy; override;
    procedure NewPage;
    procedure WriteRow(const Row: TBoardRow; Heading: Boolean);
    procedure WriteImage(Stream: TStream; Size: TPoint);
    procedure Save(Output: TStream);
  end;

implementation

uses SysUtils, Math, FPReadPNG, ZStream, wltmp;

const
  Margin = 15;
  Bottom = 282;
  LineHeight = 5;
  BaseFontWrapWidth = 72;
  EmbeddedFontWrapWidth = 44;

function AddBundledFont(Document: TPDFDocument; out Directory: string): Integer;
var Resource: TResourceStream; Compressed: TGZipDecompressionStream; Font: TFileStream;
  Buffer: array[0..16383] of Byte; Count: LongInt;
begin
  Resource := TResourceStream.Create(HInstance, 'WL_UNIFONT', RT_RCDATA);
  Compressed := nil;
  try
    Directory := NewTempDir;
    Compressed := TGZipDecompressionStream.Create(Resource);
    Font := TFileStream.Create(Directory + 'unifont.ttf', fmCreate);
    try
      repeat
        Count := Compressed.Read(Buffer, SizeOf(Buffer));
        if Count > 0 then Font.WriteBuffer(Buffer, Count);
      until Count = 0;
    finally Font.Free; end;
    Result := Document.AddFont(Directory + 'unifont.ttf', 'Unifont');
  finally
    Compressed.Free;
    Resource.Free;
  end;
end;

constructor TPdfCardWriter.Create;
var FontPath: string;
begin
  inherited Create;
  Document := TPDFDocument.Create(nil);
  Document.Options := [poPageOriginAtTop, poCompressImages, poUseImageTransparency];
  Document.DefaultPaperType := ptA4;
  Document.DefaultOrientation := ppoPortrait;
  FontPath := GetEnvironmentVariable('WELITE_PDF_TTF');
  Document.StartDocument;
  Document.Sections.AddSection;
  try
    if FontPath <> '' then BodyFont := Document.AddFont(ExpandFileName(FontPath), 'DocumentFont')
    else BodyFont := AddBundledFont(Document, BundledFontDir);
    EmbeddedFont := True;
  except
    // AddFont creates a definition before it attempts to parse the file.
    Document.Fonts.Clear;
  end;
  if EmbeddedFont then
  begin
    Document.Options := Document.Options + [poSubsetFont, poCompressFonts];
    HeadingFont := BodyFont;
    WrapWidth := EmbeddedFontWrapWidth;
  end
  else
  begin
    BodyFont := Document.AddFont('Courier');
    HeadingFont := Document.AddFont('Courier-Bold');
    WrapWidth := BaseFontWrapWidth;
  end;
  NewPage;
end;

destructor TPdfCardWriter.Destroy;
begin
  Document.Free;
  if BundledFontDir <> '' then
  begin
    DeleteFile(BundledFontDir + 'unifont.ttf');
    RemoveDir(BundledFontDir);
  end;
  inherited Destroy;
end;

procedure TPdfCardWriter.NewPage;
begin
  Page := Document.Pages.AddPage;
  Document.Sections[0].AddPage(Page);
  Y := Margin;
end;

procedure TPdfCardWriter.RequireSpace(Height: Single);
begin
  if Y + Height > Bottom then NewPage;
end;

// Standard PDF fonts use WinAnsi. Hex strings keep user text out of PDF syntax.
function WinAnsiHex(const Text: UnicodeString): string;
const Extended: array[0..31] of Word = (
  $20AC, 0, $201A, $0192, $201E, $2026, $2020, $2021, $02C6, $2030, $0160, $2039, $0152, 0, $017D, 0,
  0, $2018, $2019, $201C, $201D, $2022, $2013, $2014, $02DC, $2122, $0161, $203A, $0153, 0, $017E, $0178);
var I, J, Point, Code: Integer;
begin
  Result := '';
  for I := 1 to Length(Text) do
  begin
    Point := Ord(Text[I]);
    if (Point >= $DC00) and (Point <= $DFFF) and (I > 1) and
      (Ord(Text[I - 1]) >= $D800) and (Ord(Text[I - 1]) <= $DBFF) then Continue;
    Code := Ord('?');
    if (Point >= 32) and ((Point <= 126) or ((Point >= 160) and (Point <= 255))) then Code := Point
    else
      for J := Low(Extended) to High(Extended) do
        if (Extended[J] <> 0) and (Extended[J] = Point) then
        begin
          Code := J + $80;
          Break;
        end;
    Result := Result + IntToHex(Code, 2);
  end;
end;

procedure TPdfCardWriter.WriteRow(const Row: TBoardRow; Heading: Boolean);
var Text, Chunk: UnicodeString; Font, FontSize, I, Count, Offset: Integer;
  Fmt: TFormatSettings;
begin
  if Length(Row) = 0 then
  begin
    Y := Y + LineHeight;
    Exit;
  end;
  Text := UTF8Decode(Row[0].Text);
  if Length(Row) > 1 then
  begin
    if Text <> '' then Text := Text + ': ';
    Text := Text + UTF8Decode(Row[1].Text);
  end;
  Font := BodyFont;
  FontSize := 10;
  if Heading then
  begin
    Font := HeadingFont;
    FontSize := 11;
  end;
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  Offset := 1;
  while Offset <= Length(Text) do
  begin
    Count := 0;
    while (Offset + Count <= Length(Text)) and (Count < WrapWidth) and
      not (Text[Offset + Count] in [#10, #13]) do Inc(Count);
    if Count = WrapWidth then
    begin
      I := Count;
      while (I > 0) and (Text[Offset + I - 1] <> ' ') do Dec(I);
      if I > 0 then Count := I
      else if (Offset + Count <= Length(Text)) and
        (Ord(Text[Offset + Count - 1]) >= $D800) and (Ord(Text[Offset + Count - 1]) <= $DBFF) and
        (Ord(Text[Offset + Count]) >= $DC00) and (Ord(Text[Offset + Count]) <= $DFFF) then Dec(Count);
    end;
    Chunk := Copy(Text, Offset, Count);
    for I := 1 to Length(Chunk) do
      if Ord(Chunk[I]) < 32 then Chunk[I] := ' ';
    RequireSpace(LineHeight);
    Page.SetFont(Font, FontSize);
    if Chunk <> '' then
      if EmbeddedFont then Page.WriteText(Margin, Y + 4, UTF8Encode(Chunk))
      else Page.AddObject(TPDFFreeFormString.Create(Document,
        Format('BT %.3f %.3f Td <%s> Tj ET', [mmToPDF(Margin), Page.Paper.H - mmToPDF(Y + 4), WinAnsiHex(Chunk)], Fmt) + LineEnding));
    Y := Y + LineHeight;
    Inc(Offset, Count);
    if (Offset <= Length(Text)) and (Text[Offset] = #13) then Inc(Offset);
    if (Offset <= Length(Text)) and (Text[Offset] = #10) then Inc(Offset);
  end;
end;

procedure TPdfCardWriter.WriteImage(Stream: TStream; Size: TPoint);
var Scale, W, H: Single; Index: Integer;
begin
  Scale := Min(0.265, 110 / Max(Size.X, Size.Y));
  W := Size.X * Scale;
  H := Size.Y * Scale;
  RequireSpace(H + 5);
  Index := Document.Images.AddFromStream(Stream, TFPReaderPNG, False);
  Page.DrawImage(Margin, Y + H, W, H, Index);
  Y := Y + H + 5;
end;

procedure TPdfCardWriter.Save(Output: TStream);
begin
  Document.SaveToStream(Output);
end;

end.
