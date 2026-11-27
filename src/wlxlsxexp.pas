unit wlxlsxexp;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface
uses Classes, fpjson;
procedure WriteBoardExcel(Output: TStream; Board: TJSONObject; const Fields: string);

implementation
uses SysUtils, zipper, wlcsvexp;

const
  MainNs = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  OfficeRel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  PackageRel = 'http://schemas.openxmlformats.org/package/2006/relationships';

type
  TSheetWriter = class
    Output: TStream;
    Head: TBoardRow;
    RowNumber: Integer;
    CardDetails: Boolean;
    procedure Line(const Xml: string);
    procedure TableRow(const Row: TBoardRow; Heading: Boolean = False; LabelFirst: Boolean = False);
    procedure Add(const Row: TBoardRow);
  end;

function XmlText(const Value: string): string;
var I, N: Integer; Ch: Char;
begin
  Result := '';
  N := Length(Value);
  if N > 32767 then
  begin
    N := 32767;
    while (Ord(Value[N + 1]) and $C0) = $80 do Dec(N);
  end;
  for I := 1 to N do
  begin
    Ch := Value[I];
    case Ch of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      #13: Result := Result + '&#13;';
    else
      if Ch in [#9, #10, #32..#255] then Result := Result + Ch;
    end;
  end;
end;

function ColumnName(Index: Integer): string;
begin
  Result := '';
  Inc(Index);
  while Index > 0 do
  begin
    Dec(Index);
    Result := Chr(Ord('A') + (Index mod 26)) + Result;
    Index := Index div 26;
  end;
end;

procedure TSheetWriter.Line(const Xml: string);
begin
  if Xml <> '' then Output.WriteBuffer(Xml[1], Length(Xml));
end;

procedure TSheetWriter.TableRow(const Row: TBoardRow; Heading, LabelFirst: Boolean);
var I: Integer; Ref, Text, Style: string; N: Double; Fmt: TFormatSettings;
begin
  Inc(RowNumber);
  if (RowNumber > 1048576) or (Length(Row) > 16384) then raise Exception.Create('Excel worksheet is too large');
  Line('<row r="' + IntToStr(RowNumber) + '">');
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  for I := 0 to High(Row) do
  begin
    Ref := ColumnName(I) + IntToStr(RowNumber);
    Text := Row[I].Text;
    if Heading then Style := ' s="1"'
    else if LabelFirst and (I = 0) then Style := ' s="2"'
    else Style := ' s="3"';
    if not Row[I].LiteralText and TryStrToFloat(Text, N, Fmt) then
      Line('<c r="' + Ref + '"' + Style + '><v>' + XmlText(Text) + '</v></c>')
    else if not Row[I].LiteralText and ((Text = 'true') or (Text = 'false')) then
      Line('<c r="' + Ref + '"' + Style + ' t="b"><v>' + IntToStr(Ord(Text = 'true')) + '</v></c>')
    else
      Line('<c r="' + Ref + '"' + Style + ' t="inlineStr"><is><t xml:space="preserve">' + XmlText(Text) + '</t></is></c>');
  end;
  Line('</row>');
end;

procedure TSheetWriter.Add(const Row: TBoardRow);
var Pair: TBoardRow; I: Integer;
begin
  if not CardDetails then begin TableRow(Row, RowNumber = 0); Exit; end;
  if Length(Head) = 0 then begin Head := Copy(Row); Exit; end;
  SetLength(Pair, 2);
  for I := 0 to High(Row) do
  begin
    Pair[0] := Head[I];
    Pair[1] := Row[I];
    TableRow(Pair, I = 0, True);
  end;
  TableRow(nil);
end;

procedure WriteBoardExcel(Output: TStream; Board: TJSONObject; const Fields: string);
var Zip: TZipper; Writer: TSheetWriter; Streams: TList; Sheet: TMemoryStream; Part, Section: string;
  I: Integer; Known, CardDetails, ActivitySheet: Boolean; Banner: TBoardRow;
  SheetNames, SheetRelationships, SheetTypes: string;
  SheetCount: Integer;
  procedure AddXml(const Path, Xml: string);
  var Data: TStringStream;
  begin
    Data := TStringStream.Create(Xml);
    Streams.Add(Data);
    Zip.Entries.AddFileEntry(Data, Path);
  end;
  procedure StartSheet(const Name: string);
  var Id, Path: string;
  begin
    Inc(SheetCount);
    Id := IntToStr(SheetCount);
    Path := 'worksheets/sheet' + Id + '.xml';
    SheetNames := SheetNames + '<sheet name="' + Name + '" sheetId="' + Id + '" r:id="rId' + Id + '"/>';
    SheetRelationships := SheetRelationships + '<Relationship Id="rId' + Id + '" Type="' +
      OfficeRel + '/worksheet" Target="' + Path + '"/>';
    SheetTypes := SheetTypes + '<Override PartName="/xl/' + Path +
      '" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>';
    Sheet := TMemoryStream.Create;
    Streams.Add(Sheet);
    Zip.Entries.AddFileEntry(Sheet, 'xl/' + Path);
    Writer.Output := Sheet;
    Writer.RowNumber := 0;
    Writer.Line('<worksheet xmlns="' + MainNs + '">');
  end;

  procedure EndSheet;
  begin
    Writer.Line('</sheetData></worksheet>');
    Sheet.Position := 0;
  end;

  procedure WriteActivity;
  const Captions: array[0..5] of string =
    ('Number', 'Activity', 'Card', 'Owner', 'Created at', 'Last modified at');
  var Cards, Users: TStringList; Comments: TJSONArray; Comment, Card, User: TJSONObject;
    Row: TBoardRow; J, Index, Number: Integer;
    procedure IndexRows(const Key: string; Rows: TStringList; LiveCards: Boolean);
    var Data: TJSONData; Entry: TJSONObject; K: Integer;
    begin
      Rows.CaseSensitive := True;
      Rows.Sorted := True;
      Data := Board.Find(Key);
      if not (Data is TJSONArray) then Exit;
      for K := 0 to Data.Count - 1 do
      begin
        Entry := TJSONArray(Data).Objects[K];
        if LiveCards and ((Entry.Get('linkedId', '') <> '') or
          (Entry.Get('deletedAt', '') <> '') or (CardDetails and Entry.Get('archived', False))) then Continue;
        Rows.AddObject(Entry.Get('_id', ''), Entry);
      end;
    end;
  begin
    StartSheet('Activity');
    Writer.Line('<cols><col min="1" max="1" width="12" customWidth="1"/>' +
      '<col min="2" max="2" width="60" customWidth="1"/>' +
      '<col min="3" max="6" width="28" customWidth="1"/></cols><sheetData>');
    SetLength(Row, Length(Captions));
    for J := Low(Captions) to High(Captions) do
    begin
      Row[J].Text := Captions[J];
      Row[J].LiteralText := True;
    end;
    Writer.TableRow(Row, True);
    Cards := TStringList.Create;
    Users := TStringList.Create;
    try
      IndexRows('cards', Cards, True);
      IndexRows('users', Users, False);
      Comments := Board.Arrays['comments'];
      Number := 0;
      for J := 0 to Comments.Count - 1 do
      begin
        Comment := Comments.Objects[J];
        if not Cards.Find(Comment.Get('cardId', ''), Index) then Continue;
        Card := TJSONObject(Cards.Objects[Index]);
        Inc(Number);
        Row[0].Text := IntToStr(Number);
        Row[0].LiteralText := False;
        Row[1].Text := Comment.Get('text', '');
        Row[2].Text := Card.Get('title', '');
        Row[3].Text := Comment.Get('userId', '');
        if Users.Find(Row[3].Text, Index) then
        begin
          User := TJSONObject(Users.Objects[Index]);
          Row[3].Text := User.Get('username', Row[3].Text);
        end;
        Row[4].Text := Comment.Get('createdAt', '');
        Row[5].Text := Comment.Get('modifiedAt', '');
        Writer.TableRow(Row);
      end;
    finally
      Users.Free;
      Cards.Free;
    end;
    EndSheet;
  end;

begin
  Known := False;
  ActivitySheet := False;
  SheetCount := 0;
  CardDetails := False;
  for Part in Fields.Split([',']) do
  begin
    Section := Trim(Part);
    if Section = 'activities' then ActivitySheet := True;
    if Section = 'card-details' then CardDetails := True;
    if Pos('|' + Section + '|', '|card-details|board-header|activities|labels|people|board-info|dates|' +
      'description|custom-fields|checklists|subtasks|comments|attachments|voting|poker|stickers|locations|dependencies|sort|scrum|') > 0 then
      Known := True;
  end;
  CardDetails := CardDetails or not Known;
  Zip := TZipper.Create;
  Streams := TList.Create;
  Writer := TSheetWriter.Create;
  try
    AddXml('xl/styles.xml', '<styleSheet xmlns="' + MainNs + '">' +
      '<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font>' +
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>' +
      '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
      '<fills count="3"><fill><patternFill patternType="none"/></fill>' +
      '<fill><patternFill patternType="gray125"/></fill>' +
      '<fill><patternFill patternType="solid"><fgColor rgb="FF24466B"/><bgColor indexed="64"/></patternFill></fill></fills>' +
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
      '<cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>' +
      '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>' +
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs>' +
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>');
    StartSheet('Cards');
    Writer.CardDetails := CardDetails;
    if CardDetails then
      Writer.Line('<cols><col min="1" max="1" width="28" customWidth="1"/>' +
        '<col min="2" max="2" width="72" customWidth="1"/></cols>')
    else
      Writer.Line('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" ' +
        'activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/>' +
        '</sheetView></sheetViews><sheetFormatPr defaultColWidth="22" defaultRowHeight="15"/>' +
        '<cols><col min="1" max="1" width="32" customWidth="1"/></cols>');
    Writer.Line('<sheetData>');
    if CardDetails then
    begin
      SetLength(Banner, 1);
      Banner[0].Text := Board.Get('title', '');
      Banner[0].LiteralText := True;
      Writer.TableRow(Banner, True);
    end;
    ReadBoardRows(Board, Fields, @Writer.Add, CardDetails);
    EndSheet;
    if ActivitySheet then WriteActivity;
    AddXml('[Content_Types].xml', '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="xml" ContentType="application/xml"/>' +
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
      SheetTypes + '</Types>');
    AddXml('_rels/.rels', '<Relationships xmlns="' + PackageRel + '">' +
      '<Relationship Id="rId1" Type="' + OfficeRel + '/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    AddXml('xl/workbook.xml', '<workbook xmlns="' + MainNs + '" xmlns:r="' + OfficeRel +
      '"><bookViews><workbookView/></bookViews><sheets>' + SheetNames + '</sheets></workbook>');
    AddXml('xl/_rels/workbook.xml.rels', '<Relationships xmlns="' + PackageRel + '">' +
      SheetRelationships +
      '<Relationship Id="styles" Type="' + OfficeRel + '/styles" Target="styles.xml"/></Relationships>');
    Zip.SaveToStream(Output);
  finally
    Writer.Free;
    Zip.Free;
    for I := 0 to Streams.Count - 1 do TObject(Streams[I]).Free;
    Streams.Free;
  end;
end;
end.
