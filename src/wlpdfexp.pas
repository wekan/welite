unit wlpdfexp;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface

uses Classes, Types, fppdf, fpparsettf, wlcsvexp;

type
  TPdfUpperRange = record
    First, Last: Cardinal;
    FontCode: Word;
  end;

  TPdfCardWriter = class
  private
    Document: TPDFDocument;
    Page: TPDFPage;
    BodyFont, HeadingFont, WrapWidth: Integer;
    EmbeddedFont: Boolean;
    BundledFontDir, BodyFontPath: string;
    UpperFont: Integer;
    UpperFontTried: Boolean;
    UpperRanges: array of TPdfUpperRange;
    BodyMetrics, UpperMetrics: TTFFileInfo;
    Y: Single;
    procedure LoadUpperFont;
    procedure WriteEmbedded(const Original, Fallback: UnicodeString; FontSize: Integer);
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

uses SysUtils, Math, FPReadPNG, ZStream, wltmp, FPFontTextMapping;

type
  TPdfExportDocument = class(TPDFDocument)
  private
    UpperMapId: Integer;
  protected
    procedure CreateToUnicode(const AFontNum: Integer); override;
  public
    UpperFontIndex: Integer;
    UpperMap: array of TPdfUpperRange;
    procedure SaveToStream(const AStream: TStream); override;
  end;

procedure TPdfExportDocument.CreateToUnicode(const AFontNum: Integer);
begin
  if AFontNum = UpperFontIndex then UpperMapId := GlobalXRefCount;
  inherited CreateToUnicode(AFontNum);
end;

procedure TPdfExportDocument.SaveToStream(const AStream: TStream);
const LF = #10;
var PDF: TMemoryStream; CMap, Tail, Entry: RawByteString; Mappings: TTextMappingList;
  I, J, Count, Code, Index: Integer; Point, Supplementary: Cardinal;
  OriginalXRef, ObjectOffset, NewXRef: Int64;
  procedure Write(const Value: RawByteString);
  begin
    PDF.WriteBuffer(Value[1], Length(Value));
  end;
begin
  if UpperFontIndex < 0 then
  begin
    inherited SaveToStream(AStream);
    Exit;
  end;
  PDF := TMemoryStream.Create;
  try
    inherited SaveToStream(PDF);
    if UpperMapId > 0 then
    begin
      // Replace the generated 16-bit CMap with an incremental PDF update.
      // The existing page streams, glyph IDs and cross-reference offsets stay valid.
      Count := Min(PDF.Size, 128);
      SetLength(Tail, Count);
      PDF.Position := PDF.Size - Count;
      PDF.ReadBuffer(Tail[1], Count);
      Index := Pos('startxref', Tail);
      if Index = 0 then raise EPDF.Create('Could not locate generated PDF cross-reference');
      Tail := Trim(Copy(Tail, Index + Length('startxref'), MaxInt));
      Index := Pos('%%EOF', Tail);
      OriginalXRef := StrToInt64(Trim(Copy(Tail, 1, Index - 1)));

      CMap := '/CIDInit /ProcSet findresource begin' + LF + '12 dict begin' + LF +
        'begincmap' + LF + '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def' + LF +
        '/CMapName /WeLiteUpper def' + LF + '/CMapType 2 def' + LF +
        '1 begincodespacerange' + LF + '<0000> <FFFF>' + LF + 'endcodespacerange' + LF;
      Mappings := Fonts[UpperFontIndex].TextMapping;
      Entry := '';
      Count := 0;
      for I := 0 to Mappings.Count - 1 do
      begin
        Code := Mappings[I].CharID;
        Point := 0;
        for J := 0 to High(UpperMap) do
          if (Code >= UpperMap[J].FontCode) and
            (Cardinal(Code - UpperMap[J].FontCode) <= UpperMap[J].Last - UpperMap[J].First) then
          begin
            Point := UpperMap[J].First + Cardinal(Code - UpperMap[J].FontCode);
            Break;
          end;
        if Point < $10000 then Continue;
        Supplementary := Point - $10000;
        Entry := Entry + '<' + IntToHex(Mappings[I].GlyphID, 4) + '> <' +
          IntToHex($D800 + (Supplementary shr 10), 4) + IntToHex($DC00 + (Supplementary and $3FF), 4) + '>' + LF;
        Inc(Count);
        if Count = 100 then
        begin
          CMap := CMap + IntToStr(Count) + ' beginbfchar' + LF + Entry + 'endbfchar' + LF;
          Entry := '';
          Count := 0;
        end;
      end;
      if Count > 0 then CMap := CMap + IntToStr(Count) + ' beginbfchar' + LF + Entry + 'endbfchar' + LF;
      CMap := CMap + 'endcmap' + LF + 'CMapName currentdict /CMap defineresource pop' + LF + 'end' + LF + 'end' + LF;
      PDF.Position := PDF.Size;
      Write(LF);
      ObjectOffset := PDF.Position;
      Write(IntToStr(UpperMapId) + ' 0 obj' + LF + '<< /Length ' + IntToStr(Length(CMap)) + ' >>' + LF +
        'stream' + LF + CMap + 'endstream' + LF + 'endobj' + LF);
      NewXRef := PDF.Position;
      Write('xref' + LF + IntToStr(UpperMapId) + ' 1' + LF +
        Format('%.10d 00000 n ', [ObjectOffset]) + LF + 'trailer' + LF +
        '<< /Size ' + IntToStr(GlobalXRefCount) + ' /Root ' + IntToStr(TPDFReference(Trailer.ValueByName('Root')).Value) +
        ' 0 R /Prev ' + IntToStr(OriginalXRef) + ' >>' + LF +
        'startxref' + LF + IntToStr(NewXRef) + LF + '%%EOF' + LF);
    end;
    PDF.Position := 0;
    AStream.Position := 0;
    AStream.CopyFrom(PDF, PDF.Size);
  finally PDF.Free; end;
end;

const
  Margin = 15;
  Bottom = 282;
  LineHeight = 5;
  BaseFontWrapWidth = 72;
  EmbeddedFontWrapWidth = 44;
  MaxBundledFontSize = 16 * 1024 * 1024;

function OpenBundledFont(const ResourceName, FileName: string): TStream;
begin
  try
    Result := TResourceStream.Create(HInstance, ResourceName, RT_RCDATA);
  except
    on EResNotFound do
      Result := TFileStream.Create(ExtractFilePath(ExpandFileName(ParamStr(0))) + FileName,
        fmOpenRead or fmShareDenyWrite);
  end;
end;

procedure ExtractBundledFont(Compressed: TStream; const Path: string);
var Font: TFileStream; Buffer: array[0..16383] of Byte; Count: LongInt;
begin
  Font := TFileStream.Create(Path, fmCreate);
  try
    repeat
      Count := Compressed.Read(Buffer, SizeOf(Buffer));
      if Font.Size + Count > MaxBundledFontSize then raise EReadError.Create('Bundled PDF font exceeds size limit');
      if Count > 0 then Font.WriteBuffer(Buffer, Count);
    until Count = 0;
  finally Font.Free; end;
end;

procedure TPdfCardWriter.LoadUpperFont;
var Resource: TStream; Compressed: TGZipDecompressionStream; Info: TTFFileInfo;
  I, Count: Integer; SavedFonts: Integer; Path: string;
  function ReadWord: Word;
  var B: array[0..1] of Byte;
  begin
    Compressed.ReadBuffer(B, SizeOf(B));
    Result := Word(B[0]) shl 8 or B[1];
  end;
  function ReadCardinal: Cardinal;
  var B: array[0..3] of Byte;
  begin
    Compressed.ReadBuffer(B, SizeOf(B));
    Result := Cardinal(B[0]) shl 24 or Cardinal(B[1]) shl 16 or Cardinal(B[2]) shl 8 or B[3];
  end;
begin
  UpperFontTried := True;
  Resource := nil;
  Compressed := nil;
  Info := nil;
  SavedFonts := Document.Fonts.Count;
  try
    try
      Resource := OpenBundledFont('WL_UNIFONT_UPPER', 'unifup.gz');
      Compressed := TGZipDecompressionStream.Create(Resource);
      Count := ReadWord;
      if (Count < 1) or (Count > 1024) then Exit;
      SetLength(UpperRanges, Count);
      for I := 0 to Count - 1 do
      begin
        UpperRanges[I].First := ReadCardinal;
        UpperRanges[I].Last := ReadCardinal;
        UpperRanges[I].FontCode := ReadWord;
      end;
      if BundledFontDir = '' then BundledFontDir := NewTempDir;
      Path := BundledFontDir + 'unifup.ttf';
      ExtractBundledFont(Compressed, Path);
      BodyMetrics := TTFFileInfo.Create;
      BodyMetrics.LoadFromFile(BodyFontPath);
      Info := TTFFileInfo.Create;
      Info.LoadFromFile(Path);
      UpperFont := Document.AddFont(Path, 'UnifontUpper');
      TPdfExportDocument(Document).UpperFontIndex := UpperFont;
      TPdfExportDocument(Document).UpperMap := UpperRanges;
      UpperMetrics := Info;
      Info := nil;
    except
      while Document.Fonts.Count > SavedFonts do Document.Fonts.Delete(Document.Fonts.Count - 1);
    end;
  finally
    Info.Free;
    Compressed.Free;
    Resource.Free;
  end;
end;

constructor TPdfCardWriter.Create;
var FontPath: string; Resource: TStream; Compressed: TGZipDecompressionStream;
begin
  inherited Create;
  UpperFont := -1;
  Document := TPdfExportDocument.Create(nil);
  TPdfExportDocument(Document).UpperFontIndex := -1;
  Document.Options := [poPageOriginAtTop, poCompressImages, poUseImageTransparency];
  Document.DefaultPaperType := ptA4;
  Document.DefaultOrientation := ppoPortrait;
  FontPath := GetEnvironmentVariable('WELITE_PDF_TTF');
  Document.StartDocument;
  Document.Sections.AddSection;
  try
    if FontPath <> '' then BodyFontPath := ExpandFileName(FontPath)
    else
    begin
      Resource := OpenBundledFont('WL_UNIFONT', 'unifont.gz');
      try
        BundledFontDir := NewTempDir;
        BodyFontPath := BundledFontDir + 'unifont.ttf';
        Compressed := TGZipDecompressionStream.Create(Resource);
        try ExtractBundledFont(Compressed, BodyFontPath); finally Compressed.Free; end;
      finally Resource.Free; end;
    end;
    if FontPath = '' then BodyFont := Document.AddFont(BodyFontPath, 'Unifont')
    else BodyFont := Document.AddFont(BodyFontPath, 'DocumentFont');
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
  BodyMetrics.Free;
  UpperMetrics.Free;
  if BundledFontDir <> '' then
  begin
    DeleteFile(BundledFontDir + 'unifont.ttf');
    DeleteFile(BundledFontDir + 'unifup.ttf');
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

function PlainPDFGlyphs(const Text: UnicodeString; out HasSupplementary: Boolean): UnicodeString;
var I, N: Integer;
begin
  HasSupplementary := False;
  SetLength(Result, Length(Text));
  I := 1;
  N := 0;
  while I <= Length(Text) do
  begin
    Inc(N);
    if (I < Length(Text)) and (Ord(Text[I]) >= $D800) and (Ord(Text[I]) <= $DBFF) and
      (Ord(Text[I + 1]) >= $DC00) and (Ord(Text[I + 1]) <= $DFFF) then
    begin
      HasSupplementary := True;
      Result[N] := '?';
      Inc(I);
    end
    else Result[N] := Text[I];
    Inc(I);
  end;
  SetLength(Result, N);
end;

function PDFActualText(const Text: UnicodeString): string;
var I: Integer;
begin
  Result := '/Span << /ActualText <FEFF';
  for I := 1 to Length(Text) do Result := Result + IntToHex(Ord(Text[I]), 4);
  Result := Result + '> >> BDC' + LineEnding;
end;

procedure TPdfCardWriter.WriteEmbedded(const Original, Fallback: UnicodeString; FontSize: Integer);
var I, K, RunFont, NextFont: Integer; CodePoint: Cardinal; Letter: WideChar;
  Run: UnicodeString; Metrics: TTFFileInfo; X, RunWidth: Single;
  procedure Flush;
  begin
    if Run = '' then Exit;
    Page.SetFont(RunFont, FontSize);
    Page.WriteText(X, Y + 4, UTF8Encode(Run));
    X := X + RunWidth * FontSize * 25.4 / 72000;
    Run := '';
    RunWidth := 0;
  end;
begin
  if not UpperFontTried then LoadUpperFont;
  if UpperFont < 0 then
  begin
    Page.WriteText(Margin, Y + 4, UTF8Encode(Fallback));
    Exit;
  end;
  X := Margin;
  RunWidth := 0;
  RunFont := BodyFont;
  I := 1;
  while I <= Length(Original) do
  begin
    Letter := Original[I];
    NextFont := BodyFont;
    if (I < Length(Original)) and (Ord(Letter) >= $D800) and (Ord(Letter) <= $DBFF) and
      (Ord(Original[I + 1]) >= $DC00) and (Ord(Original[I + 1]) <= $DFFF) then
    begin
      CodePoint := $10000 + (Cardinal(Ord(Letter) - $D800) shl 10) + Ord(Original[I + 1]) - $DC00;
      Inc(I);
      Letter := '?';
      for K := 0 to High(UpperRanges) do
        if (CodePoint >= UpperRanges[K].First) and (CodePoint <= UpperRanges[K].Last) then
        begin
          Letter := WideChar(UpperRanges[K].FontCode + CodePoint - UpperRanges[K].First);
          NextFont := UpperFont;
          Break;
        end;
    end;
    if NextFont <> RunFont then
    begin
      Flush;
      RunFont := NextFont;
    end;
    if RunFont = UpperFont then Metrics := UpperMetrics else Metrics := BodyMetrics;
    Run := Run + Letter;
    RunWidth := RunWidth + Round(Metrics.GetAdvanceWidth(Metrics.GetGlyphIndex(Ord(Letter))) * 1000.0 / Max(1, Metrics.Head.UnitsPerEm));
    Inc(I);
  end;
  Flush;
end;

procedure TPdfCardWriter.WriteRow(const Row: TBoardRow; Heading: Boolean);
var Text, Chunk, Display: UnicodeString; Font, FontSize, I, Count, Offset: Integer;
  HasSupplementary: Boolean;
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
    begin
      Display := PlainPDFGlyphs(Chunk, HasSupplementary);
      if HasSupplementary then
        Page.AddObject(TPDFFreeFormString.Create(Document, PDFActualText(Chunk)));
      if EmbeddedFont then
      begin
        if HasSupplementary then WriteEmbedded(Chunk, Display, FontSize)
        else Page.WriteText(Margin, Y + 4, UTF8Encode(Display));
      end
      else Page.AddObject(TPDFFreeFormString.Create(Document,
        Format('BT %.3f %.3f Td <%s> Tj ET', [mmToPDF(Margin), Page.Paper.H - mmToPDF(Y + 4), WinAnsiHex(Display)], Fmt) + LineEnding));
      if HasSupplementary then
        Page.AddObject(TPDFFreeFormString.Create(Document, 'EMC' + LineEnding));
    end;
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
