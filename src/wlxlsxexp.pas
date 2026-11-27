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
    procedure TableRow(const Row: TBoardRow);
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

procedure TSheetWriter.TableRow(const Row: TBoardRow);
var I: Integer; Ref, Text: string; N: Double; Fmt: TFormatSettings;
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
    if not Row[I].LiteralText and TryStrToFloat(Text, N, Fmt) then
      Line('<c r="' + Ref + '"><v>' + XmlText(Text) + '</v></c>')
    else if not Row[I].LiteralText and ((Text = 'true') or (Text = 'false')) then
      Line('<c r="' + Ref + '" t="b"><v>' + IntToStr(Ord(Text = 'true')) + '</v></c>')
    else
      Line('<c r="' + Ref + '" t="inlineStr"><is><t xml:space="preserve">' + XmlText(Text) + '</t></is></c>');
  end;
  Line('</row>');
end;

procedure TSheetWriter.Add(const Row: TBoardRow);
var Pair: TBoardRow; I: Integer;
begin
  if not CardDetails then begin TableRow(Row); Exit; end;
  if Length(Head) = 0 then begin Head := Copy(Row); Exit; end;
  SetLength(Pair, 2);
  for I := 0 to High(Row) do
  begin
    Pair[0] := Head[I];
    Pair[1] := Row[I];
    TableRow(Pair);
  end;
  TableRow(nil);
end;

procedure WriteBoardExcel(Output: TStream; Board: TJSONObject; const Fields: string);
var Zip: TZipper; Writer: TSheetWriter; Streams: TList; Sheet: TMemoryStream; Part, Section: string;
  I: Integer; Known, CardDetails: Boolean; Banner: TBoardRow;
  procedure AddXml(const Path, Xml: string);
  var Data: TStringStream;
  begin
    Data := TStringStream.Create(Xml);
    Streams.Add(Data);
    Zip.Entries.AddFileEntry(Data, Path);
  end;
begin
  Known := False;
  CardDetails := False;
  for Part in Fields.Split([',']) do
  begin
    Section := Trim(Part);
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
    AddXml('[Content_Types].xml', '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="xml" ContentType="application/xml"/>' +
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>');
    AddXml('_rels/.rels', '<Relationships xmlns="' + PackageRel + '">' +
      '<Relationship Id="rId1" Type="' + OfficeRel + '/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    AddXml('xl/workbook.xml', '<workbook xmlns="' + MainNs + '" xmlns:r="' + OfficeRel +
      '"><sheets><sheet name="Cards" sheetId="1" r:id="rId1"/></sheets></workbook>');
    AddXml('xl/_rels/workbook.xml.rels', '<Relationships xmlns="' + PackageRel + '">' +
      '<Relationship Id="rId1" Type="' + OfficeRel + '/worksheet" Target="worksheets/sheet1.xml"/></Relationships>');
    Sheet := TMemoryStream.Create;
    Streams.Add(Sheet);
    Writer.Output := Sheet;
    Writer.CardDetails := CardDetails;
    Writer.Line('<worksheet xmlns="' + MainNs + '"><sheetData>');
    if CardDetails then
    begin
      SetLength(Banner, 1);
      Banner[0].Text := Board.Get('title', '');
      Banner[0].LiteralText := True;
      Writer.TableRow(Banner);
    end;
    ReadBoardRows(Board, Fields, @Writer.Add, CardDetails);
    Writer.Line('</sheetData></worksheet>');
    Sheet.Position := 0;
    Zip.Entries.AddFileEntry(Sheet, 'xl/worksheets/sheet1.xml');
    Zip.SaveToStream(Output);
  finally
    Writer.Free;
    Zip.Free;
    for I := 0 to Streams.Count - 1 do TObject(Streams[I]).Free;
    Streams.Free;
  end;
end;
end.
