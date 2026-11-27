unit wlxlsxexp;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface
uses Classes, fpjson;
procedure WriteBoardExcel(Output: TStream; Board: TJSONObject; const Fields: string; Scoped: Boolean; OtherCards: TJSONArray; const LaneId, ListId: string);

implementation
uses SysUtils, Contnrs, zipper, wlcsvexp, wlselect;

const
  MainNs = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  OfficeRel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  PackageRel = 'http://schemas.openxmlformats.org/package/2006/relationships';

type
  TSheetWriter = class
    Output: TStream;
    Head: TBoardRow;
    RowNumber: Integer;
    CardDetails, ShowPoker, ShowStickers, ShowLocations: Boolean;
    Checklists, Items, Comments, Attachments, Subtasks, UsersById, Dependencies, CardsById: TFPHashObjectList;
    LaneRows, ListRows: TJSONArray;
    CurrentLane, NextLane, NextList: Integer;
    LaneScoped: Boolean;
    PageBreaks: TStringList;
    HasCard: Boolean;
    ShowLaneHeadings, ShowListHeadings: Boolean;
    procedure WriteHeading(const Text: string);
    procedure GroupHeadings(Card: TJSONObject);
    procedure LaneHeading(Position: Integer);
    procedure ListHeading(Position: Integer; Empty: Boolean);
    procedure FinishGroupHeadings;
    procedure EmptyListsBefore(Position: Integer);
    procedure PrintSetup;
    procedure Line(const Xml: string);
    procedure TableRow(const Row: TBoardRow; Heading: Boolean = False; LabelFirst: Boolean = False);
    destructor Destroy; override;
    procedure DetailRows(Card: TJSONObject);
    procedure Add(const Row: TBoardRow; Card: TJSONObject);
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

procedure GroupEntry(Groups: TFPHashObjectList; const Id: string; Entry: TJSONObject);
var Group: TFPList;
begin
  if Id = '' then Exit;
  Group := TFPList(Groups.Find(Id));
  if Group = nil then
  begin
    Group := TFPList.Create;
    Groups.Add(Id, Group);
  end;
  if Group.IndexOf(Entry) < 0 then Group.Add(Entry);
end;

function GroupRows(Board: TJSONObject; const Source, Key: string): TFPHashObjectList;
var Rows: TJSONArray; Entry: TJSONObject; I: Integer;
begin
  Result := TFPHashObjectList.Create(True);
  try
    Rows := Board.Arrays[Source];
    for I := 0 to Rows.Count - 1 do
    begin
      Entry := Rows.Objects[I];
      GroupEntry(Result, Entry.Get(Key, ''), Entry);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure GroupSubtasks(Groups: TFPHashObjectList; Cards: TJSONArray);
var I, J: Integer; Card: TJSONObject; Parents: TJSONData;
begin
  if Cards = nil then Exit;
  for I := 0 to Cards.Count - 1 do
  begin
    Card := Cards.Objects[I];
    if Card.Get('archived', False) or (Card.Get('linkedId', '') <> '') or
      (Card.Get('deletedAt', '') <> '') then Continue;
    GroupEntry(Groups, Card.Get('parentId', ''), Card);
    Parents := Card.Find('parentIds');
    if Parents is TJSONArray then
      for J := 0 to Parents.Count - 1 do
        if Parents.Items[J] is TJSONString then GroupEntry(Groups, Parents.Items[J].AsString, Card);
  end;
end;

destructor TSheetWriter.Destroy;
begin
  PageBreaks.Free;
  CardsById.Free;
  Dependencies.Free;
  UsersById.Free;
  Subtasks.Free;
  Attachments.Free;
  Comments.Free;
  Items.Free;
  Checklists.Free;
  inherited Destroy;
end;

procedure TSheetWriter.DetailRows(Card: TJSONObject);
var Pair: TBoardRow; CardId, State, Author, Created, Name: string; Group, Children: TFPList;
  Entry, Child, User: TJSONObject; Data: TJSONData; I, J: Integer;

  procedure AddDetail(const Caption, Value: string; LiteralText: Boolean = True);
  begin
    Pair[0].Text := Caption;
    Pair[1].Text := Value;
    Pair[1].LiteralText := LiteralText;
    TableRow(Pair, False, True);
  end;

  function UserName(const Id: string): string;
  begin
    Result := Id;
    User := TJSONObject(UsersById.Find(Id));
    if User <> nil then Result := User.Get('username', Id);
  end;

  procedure AddValue(Obj: TJSONObject; const Key, Caption: string);
  var Value: TJSONData;
  begin
    Value := Obj.Find(Key);
    if (Value <> nil) and (Value.JSONType in [jtString, jtNumber, jtBoolean]) and
      (Value.AsString <> '') then AddDetail(Caption, Value.AsString, Value.JSONType = jtString);
  end;


begin
  SetLength(Pair, 2);
  Pair[0].LiteralText := True;
  Pair[1].LiteralText := True;
  CardId := Card.Get('_id', '');
  if Checklists <> nil then
  begin
    Group := TFPList(Checklists.Find(CardId));
    if Group <> nil then
      for I := 0 to Group.Count - 1 do
      begin
        Entry := TJSONObject(Group[I]);
        AddDetail('Checklist', Entry.Get('title', ''));
        Children := TFPList(Items.Find(Entry.Get('_id', '')));
        if Children <> nil then
          for J := 0 to Children.Count - 1 do
          begin
            Child := TJSONObject(Children[J]);
            State := '[ ] ';
            if Child.Get('isFinished', False) or (Child.Get('isFinished', 0) = 1) then State := '[x] ';
            AddDetail('', State + Child.Get('title', ''));
          end;
      end;
  end;
  if Subtasks <> nil then
  begin
    Group := TFPList(Subtasks.Find(CardId));
    if Group <> nil then
      for I := 0 to Group.Count - 1 do
      begin
        Entry := TJSONObject(Group[I]);
        State := '[ ] ';
        if Entry.Get('dueComplete', False) or (Entry.Get('dueComplete', 0) = 1) then State := '[x] ';
        AddDetail('Subtask', State + Entry.Get('title', ''));
      end;
  end;
  if Comments <> nil then
  begin
    Group := TFPList(Comments.Find(CardId));
    if Group <> nil then
      for I := 0 to Group.Count - 1 do
      begin
        Entry := TJSONObject(Group[I]);
        Author := UserName(Entry.Get('userId', ''));
        Created := Entry.Get('createdAt', '');
        AddDetail('Comment', ExportPlainDescription(Entry.Get('text', '')));
        if Author <> '' then AddDetail('Author', Author);
        if Created <> '' then AddDetail('Created at', Created);
      end;
  end;
  if Attachments <> nil then
  begin
    Group := TFPList(Attachments.Find(CardId));
    if Group <> nil then
      for I := 0 to Group.Count - 1 do
      begin
        Entry := TJSONObject(Group[I]);
        AddValue(Entry, 'name', 'Attachment');
        AddValue(Entry, 'type', 'File type');
        AddValue(Entry, 'size', 'Size (bytes)');
        Created := Entry.Get('uploadedAt', '');
        if Created = '' then Created := Entry.Get('uploadedAtOstrio', '');
        if Created = '' then Created := Entry.Get('createdAt', '');
        if Created <> '' then AddDetail('Uploaded at', Created);
        Author := UserName(Entry.Get('userId', ''));
        if Author <> '' then AddDetail('Uploader', Author);
      end;
  end;
  if Dependencies <> nil then
  begin
    Group := TFPList(Dependencies.Find(CardId));
    if Group <> nil then
      for I := 0 to Group.Count - 1 do
      begin
        Entry := TJSONObject(Group[I]);
        Child := TJSONObject(CardsById.Find(Entry.Get('targetCardId', '')));
        if Child = nil then Continue;
        AddValue(Child, 'title', 'Dependency');
        AddValue(Entry, 'type', 'Relationship');
      end;
  end;
  if ShowPoker then
  begin
    Data := Card.Find('poker');
    if Data is TJSONObject then
    begin
      AddValue(TJSONObject(Data), 'question', 'Planning Poker');
      AddValue(TJSONObject(Data), 'estimation', 'Estimation');
    end;
  end;
  if ShowStickers then
  begin
    Data := Card.Find('stickers');
    if Data is TJSONArray then
      for I := 0 to Data.Count - 1 do
        if Data.Items[I] is TJSONObject then
        begin
          Entry := TJSONObject(Data.Items[I]);
          Name := Entry.Get('name', '');
          if Name = '' then Name := Entry.Get('icon', '');
          if Name <> '' then AddDetail('Sticker', Name);
        end;
  end;
  if ShowLocations then
  begin
    Data := Card.Find('locations');
    if (Data is TJSONArray) and (Data.Count > 0) then
    begin
      for I := 0 to Data.Count - 1 do
        if Data.Items[I] is TJSONObject then
        begin
          Entry := TJSONObject(Data.Items[I]);
          AddValue(Entry, 'name', 'Location');
          AddValue(Entry, 'address', 'Address');
          AddValue(Entry, 'latitude', 'Latitude');
          AddValue(Entry, 'longitude', 'Longitude');
        end;
    end
    else
    begin
      AddValue(Card, 'locationName', 'Location');
      AddValue(Card, 'locationAddress', 'Address');
      AddValue(Card, 'locationLatitude', 'Latitude');
      AddValue(Card, 'locationLongitude', 'Longitude');
    end;
  end;
end;

function PositionOf(Rows: TJSONArray; const Id: string): Integer;
var I: Integer;
begin
  for I := 0 to Rows.Count - 1 do
    if Rows.Objects[I].Get('_id', '') = Id then Exit(I);
  Result := Rows.Count;
end;

function TitleOf(Rows: TJSONArray; const Id: string): string;
var Position: Integer;
begin
  Position := PositionOf(Rows, Id);
  if Position < Rows.Count then Result := Rows.Objects[Position].Get('title', '') else Result := '';
end;

procedure TSheetWriter.WriteHeading(const Text: string);
var Row: TBoardRow;
begin
  SetLength(Row, 1);
  Row[0].Text := Text;
  Row[0].LiteralText := True;
  TableRow(Row, True);
end;

procedure TSheetWriter.LaneHeading(Position: Integer);
var Lane: TJSONObject;
begin
  if Position >= LaneRows.Count then Exit;
  Lane := LaneRows.Objects[Position];
  if not ShowLaneHeadings or Lane.Get('archived', False) or
    (Lane.Get('type', '') = 'template-swimlane') then Exit;
  WriteHeading('Swimlane: ' + Lane.Get('title', ''));
end;

procedure TSheetWriter.ListHeading(Position: Integer; Empty: Boolean);
var List, Lane: TJSONObject; Home: string;
begin
  if not ShowListHeadings or (Position >= ListRows.Count) then Exit;
  List := ListRows.Objects[Position];
  if List.Get('archived', False) then Exit;
  if Empty then
  begin
    if CurrentLane >= LaneRows.Count then Exit;
    Lane := LaneRows.Objects[CurrentLane];
    if Lane.Get('archived', False) or (Lane.Get('type', '') = 'template-swimlane') then Exit;
    Home := List.Get('swimlaneId', '');
    if (Home <> '') and (Home <> Lane.Get('_id', '')) then Exit;
  end;
  WriteHeading('List: ' + List.Get('title', ''));
end;

procedure TSheetWriter.EmptyListsBefore(Position: Integer);
begin
  while NextList < Position do
  begin
    ListHeading(NextList, True);
    Inc(NextList);
  end;
end;

procedure TSheetWriter.GroupHeadings(Card: TJSONObject);
var Lane, List: Integer;
begin
  if not ShowListHeadings then Exit;
  Lane := PositionOf(LaneRows, Card.Get('swimlaneId', ''));
  List := PositionOf(ListRows, Card.Get('listId', ''));
  if Lane <> CurrentLane then
  begin
    if CurrentLane >= 0 then EmptyListsBefore(ListRows.Count);
    while ShowLaneHeadings and (NextLane < Lane) do
    begin
      CurrentLane := NextLane;
      LaneHeading(NextLane);
      NextList := 0;
      EmptyListsBefore(ListRows.Count);
      Inc(NextLane);
    end;
    CurrentLane := Lane;
    LaneHeading(Lane);
    NextLane := Lane + 1;
    NextList := 0;
  end;
  EmptyListsBefore(List);
  if NextList = List then
  begin
    ListHeading(List, False);
    Inc(NextList);
  end;
end;

procedure TSheetWriter.FinishGroupHeadings;
begin
  if not ShowListHeadings then Exit;
  if (CurrentLane >= 0) and (CurrentLane < LaneRows.Count) then EmptyListsBefore(ListRows.Count);
  if LaneScoped then Exit;
  while ShowLaneHeadings and (NextLane < LaneRows.Count) do
  begin
    CurrentLane := NextLane;
    LaneHeading(NextLane);
    NextList := 0;
    EmptyListsBefore(ListRows.Count);
    Inc(NextLane);
  end;
end;

procedure TSheetWriter.PrintSetup;
var Boundary: string;
begin
  Line('<pageMargins left="0.3" right="0.3" top="0.5" bottom="0.5" header="0.2" footer="0.2"/>' +
    '<pageSetup paperSize="9" orientation="portrait"/>');
  if PageBreaks.Count = 0 then Exit;
  Line('<rowBreaks count="' + IntToStr(PageBreaks.Count) +
    '" manualBreakCount="' + IntToStr(PageBreaks.Count) + '">');
  for Boundary in PageBreaks do
    Line('<brk id="' + Boundary + '" min="0" max="16383" man="1"/>');
  Line('</rowBreaks>');
end;

procedure TSheetWriter.Add(const Row: TBoardRow; Card: TJSONObject);
var Pair: TBoardRow; I: Integer;
begin
  if not CardDetails then begin TableRow(Row, RowNumber = 0); Exit; end;
  if Card = nil then begin Head := Copy(Row); Exit; end;
  if HasCard then PageBreaks.Add(IntToStr(RowNumber));
  HasCard := True;
  GroupHeadings(Card);
  SetLength(Pair, 2);
  for I := 0 to High(Row) do
  begin
    Pair[0] := Head[I];
    Pair[1] := Row[I];
    TableRow(Pair, I = 0, True);
  end;
  DetailRows(Card);
  TableRow(nil);
end;

procedure WriteBoardExcel(Output: TStream; Board: TJSONObject; const Fields: string; Scoped: Boolean; OtherCards: TJSONArray; const LaneId, ListId: string);
var Zip: TZipper; Writer: TSheetWriter; Streams: TList; Sheet: TMemoryStream; Part, Section: string;
  I: Integer; Known, CardDetails, ActivitySheet, BoardHeader, WithChecklists, WithComments, WithAttachments, WithSubtasks, WithPoker, WithStickers, WithLocations, WithDependencies: Boolean;
  Users: TJSONArray; User: TJSONObject;
  SheetNames, SheetRelationships, SheetTypes: string;
  SheetCount: Integer;
  SortedCards: TStringList;
  CardOrder: TFPList;
  procedure IndexCards(Cards: TJSONArray);
  var J: Integer; Card: TJSONObject;
  begin
    if Cards = nil then Exit;
    for J := 0 to Cards.Count - 1 do
    begin
      Card := Cards.Objects[J];
      if Card.Get('archived', False) or (Card.Get('deletedAt', '') <> '') or
        (Card.Get('linkedId', '') <> '') then Continue;
      Writer.CardsById.Add(Card.Get('_id', ''), Card);
    end;
  end;

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

  procedure EndSheet(CardPrintLayout: Boolean = False);
  begin
    Writer.Line('</sheetData>');
    if CardPrintLayout then Writer.PrintSetup;
    Writer.Line('</worksheet>');
    Sheet.Position := 0;
  end;

  procedure BoardColumns;
  begin
    Writer.Line('<cols><col min="1" max="1" width="28" customWidth="1"/>' +
      '<col min="2" max="2" width="72" customWidth="1"/></cols>');
  end;

  procedure WriteBoardTitle;
  var Title: string;
  begin
    if ListId <> '' then
    begin
      Title := TitleOf(Writer.ListRows, ListId);
      if Title = '' then Title := 'List' else Title := 'List: ' + Title;
    end
    else if LaneId <> '' then
    begin
      Title := TitleOf(Writer.LaneRows, LaneId);
      if Title = '' then Title := 'Swimlane' else Title := 'Swimlane: ' + Title;
    end
    else Title := Board.Get('title', '');
    Writer.WriteHeading(Title);
  end;

  procedure OrderCards;
  var Cards: TJSONArray; Card: TJSONObject; J, Lane, List: Integer;
  begin
    Cards := Board.Arrays['cards'];
    for J := 0 to Cards.Count - 1 do
    begin
      Card := Cards.Objects[J];
      Lane := PositionOf(Writer.LaneRows, Card.Get('swimlaneId', ''));
      List := PositionOf(Writer.ListRows, Card.Get('listId', ''));
      SortedCards.AddObject(Format('%.10d/%.10d/%.10d', [Lane, List, J]), Card);
    end;
    SortedCards.Sort;
    CardOrder := TFPList.Create;
    for J := 0 to SortedCards.Count - 1 do CardOrder.Add(SortedCards.Objects[J]);
  end;

  procedure WriteBoardHeader;
  var Row: TBoardRow; Members, Users: TJSONArray; Member, User: TJSONObject;
    Names, Id, Name: string; J, K: Integer;

    procedure Field(const LabelText, Value: string);
    begin
      if Value = '' then Exit;
      Row[0].Text := LabelText;
      Row[1].Text := Value;
      Writer.TableRow(Row, False, True);
    end;

  begin
    SetLength(Row, 2);
    Row[0].LiteralText := True;
    Row[1].LiteralText := True;
    Members := Board.Arrays['members'];
    Users := Board.Arrays['users'];
    Names := '';
    for J := 0 to Members.Count - 1 do
    begin
      Member := Members.Objects[J];
      Id := Member.Get('userId', '');
      if Id = '' then Continue;
      Name := Id;
      for K := 0 to Users.Count - 1 do
      begin
        User := Users.Objects[K];
        if User.Get('_id', '') <> Id then Continue;
        Name := User.Get('username', Id);
        Break;
      end;
      if Names <> '' then Names := Names + ', ';
      Names := Names + Name;
    end;
    Field('Members', Names);
    Field('Created at', Board.Get('createdAt', ''));
    Field('Last modified at', Board.Get('modifiedAt', ''));
    Field('Description', ExportPlainDescription(Board.Get('description', '')));
    Writer.TableRow(nil);
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
  BoardHeader := False;
  WithChecklists := False;
  WithComments := False;
  WithAttachments := False;
  WithSubtasks := False;
  WithPoker := False;
  WithStickers := False;
  WithLocations := False;
  WithDependencies := False;
  SheetCount := 0;
  CardDetails := False;
  for Part in Fields.Split([',']) do
  begin
    Section := Trim(Part);
    if Section = 'checklists' then WithChecklists := True;
    if Section = 'comments' then WithComments := True;
    if Section = 'poker' then WithPoker := True;
    if Section = 'stickers' then WithStickers := True;
    if Section = 'dependencies' then WithDependencies := True;
    if Section = 'locations' then WithLocations := True;
    if Section = 'subtasks' then WithSubtasks := True;
    if Section = 'attachments' then WithAttachments := True;
    if Section = 'board-header' then BoardHeader := True;
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
  SortedCards := TStringList.Create;
  CardOrder := nil;
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
    Writer.LaneRows := Board.Arrays['swimlanes'];
    Writer.ListRows := Board.Arrays['lists'];
    Writer.ShowLaneHeadings := not Scoped;
    Writer.CurrentLane := -1;
    Writer.LaneScoped := LaneId <> '';
    if Writer.LaneScoped then Writer.CurrentLane := PositionOf(Writer.LaneRows, LaneId);
    Writer.ShowListHeadings := not Scoped or ((LaneId <> '') and (ListId = ''));
    Writer.ShowPoker := WithPoker or not Known;
    Writer.ShowStickers := WithStickers or not Known;
    Writer.ShowLocations := WithLocations or not Known;
    if CardDetails then
    begin
      Writer.PageBreaks := TStringList.Create;
      BoardColumns;
    end
    else
      Writer.Line('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" ' +
        'activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/>' +
        '</sheetView></sheetViews><sheetFormatPr defaultColWidth="22" defaultRowHeight="15"/>' +
        '<cols><col min="1" max="1" width="32" customWidth="1"/></cols>');
    Writer.Line('<sheetData>');
    if CardDetails then
    begin
      if WithChecklists or not Known then
      begin
        Writer.Checklists := GroupRows(Board, 'checklists', 'cardId');
        Writer.Items := GroupRows(Board, 'checklistItems', 'checklistId');
      end;
      if WithComments or not Known then Writer.Comments := GroupRows(Board, 'comments', 'cardId');
      if WithComments or WithAttachments or not Known then
      begin
        Writer.UsersById := TFPHashObjectList.Create(False);
        Users := Board.Arrays['users'];
        for I := 0 to Users.Count - 1 do
        begin
          User := Users.Objects[I];
          Writer.UsersById.Add(User.Get('_id', ''), User);
        end;
      end;
      if WithSubtasks or not Known then
      begin
        Writer.Subtasks := TFPHashObjectList.Create(True);
        GroupSubtasks(Writer.Subtasks, Board.Arrays['cards']);
        GroupSubtasks(Writer.Subtasks, OtherCards);
      end;
      if WithAttachments or not Known then Writer.Attachments := GroupRows(Board, 'attachments', 'cardId');
      if WithDependencies or not Known then
      begin
        Writer.Dependencies := GroupRows(Board, 'cardDependencies', 'cardId');
        Writer.CardsById := TFPHashObjectList.Create(False);
        IndexCards(Board.Arrays['cards']);
        IndexCards(OtherCards);
      end;
      if Writer.ShowLaneHeadings or Writer.ShowListHeadings then OrderCards;
      WriteBoardTitle;
      if not Scoped and (BoardHeader or not Known) then WriteBoardHeader;
    end;
    ReadBoardRows(Board, Fields, @Writer.Add, CardDetails, CardOrder);
    if CardDetails then Writer.FinishGroupHeadings;
    EndSheet(CardDetails);
    if not CardDetails and not Scoped and BoardHeader then
    begin
      StartSheet('Board');
      BoardColumns;
      Writer.Line('<sheetData>');
      WriteBoardTitle;
      WriteBoardHeader;
      EndSheet;
    end;
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
    CardOrder.Free;
    SortedCards.Free;
    Writer.Free;
    Zip.Free;
    for I := 0 to Streams.Count - 1 do TObject(Streams[I]).Free;
    Streams.Free;
  end;
end;
end.
