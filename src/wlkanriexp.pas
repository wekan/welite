unit wlkanriexp;

{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface

uses fpjson;

function KanriExport(Board: TJSONObject; const CreatedAt, ModifiedAt: string): string;

implementation

uses Classes, SysUtils, DateUtils, Math, wlcolors;

function KanriHex(const Raw: string): string;
var Color: TNamedColor;
begin
  Result := NormalizeHex(Raw);
  if Result <> '' then Exit;
  for Color in LABEL_COLORS do
    if SameText(Trim(Raw), Color.Name) then Exit(Color.Hex);
end;

function CardColor(const Raw: string): string;
var Color: string;
begin
  Color := LowerCase(Trim(Raw));
  case Color of
    'pink','red','yellow','orange','green','blue','purple': Result := 'bg-' + Color + '-600';
    '#0d9488': Result := 'bg-teal-600';
    else Result := KanriHex(Color);
  end;
  if Result = '' then Result := 'bg-elevation-2';
end;

function TagTextColor(const Hex: string): string;
const Weights: array[0..2] of Double = (0.2126, 0.7152, 0.0722);

  function Luminance(const Color: string): Double;
  var Index: Integer; Value: Double;
  begin
    Result := 0;
    for Index := 0 to 2 do
    begin
      Value := StrToInt('$' + Copy(Color, Index * 2 + 2, 2)) / 255;
      if Value <= 0.03928 then Value := Value / 12.92
      else Value := Power((Value + 0.055) / 1.055, 2.4);
      Result := Result + Value * Weights[Index];
    end;
  end;

  function Contrast(const Color: string): Double;
  var Left, Right: Double;
  begin
    Left := Luminance(Hex);
    Right := Luminance(Color);
    Result := (Max(Left, Right) + 0.05) / (Min(Left, Right) + 0.05);
  end;

begin
  if Contrast('#1e293b') >= Contrast('#f4f4f5') then Result := '#1e293b'
  else Result := '#f4f4f5';
  if Contrast(Result) >= 4.5 then Exit;
  if Contrast('#000000') >= Contrast('#ffffff') then Result := '#000000' else Result := '#ffffff';
end;

function ExportDate(const Value: string): string;
var At: TDateTime;
begin
  Result := '';
  if TryISO8601ToDate(Value, At, True) then
    Result := FormatDateTime('yyyy-mm-dd"T"hh":"nn":"ss"."zzz"Z"', At);
end;

function KanriExport(Board: TJSONObject; const CreatedAt, ModifiedAt: string): string;
var Output, Entry, Card, Checklist, Item, Definition, Tag, Column: TJSONObject;
  Columns, Cards, Lists, Checklists, Items, Labels, CardLabels, ColumnCards, Tasks, Tags, GlobalTags: TJSONArray;
  ListIndex, LabelIndex, Used: TStringList;
  CardId, ListId, Name, Hex, Due, Edited, Created: string;
  I, J, K, N, Index: Integer;

  function AddColumn(const Id, Title: string): TJSONArray;
  begin
    Result := TJSONArray.Create;
    Columns.Add(TJSONObject.Create(['id', Id, 'title', Title, 'cards', Result]));
    ListIndex.AddObject(Id, Result);
  end;

begin
  Created := ExportDate(CreatedAt);
  Edited := ExportDate(ModifiedAt);
  if Edited = '' then Edited := Created;
  if Edited = '' then Edited := ExportDate(DateToISO8601(Now, False));
  if Created = '' then Created := Edited;
  Name := Board.Get('title', '');
  if Name = '' then Name := 'WeKan board';
  Columns := TJSONArray.Create;
  GlobalTags := TJSONArray.Create;
  Output := TJSONObject.Create(['id', Board.Get('_id', 'wekan-board'), 'title', Name,
    'columns', Columns, 'background', TJSONNull.Create, 'globalTags', GlobalTags,
    'lastEdited', Edited, 'createdAt', Created]);
  ListIndex := TStringList.Create;
  LabelIndex := TStringList.Create;
  Used := TStringList.Create;
  try
    ListIndex.CaseSensitive := True;
    LabelIndex.CaseSensitive := True;
    Used.CaseSensitive := True;
    Lists := Board.Arrays['lists'];
    for I := 0 to Lists.Count - 1 do
    begin
      Entry := Lists.Objects[I];
      if not Entry.Get('archived', False) then AddColumn(Entry.Get('_id',''), Entry.Get('title',''));
    end;
    Labels := Board.Get('labels', TJSONArray(nil));
    if Labels <> nil then
      for I := 0 to Labels.Count - 1 do
      begin
        Definition := Labels.Objects[I];
        if Trim(Definition.Get('name','')) <> '' then
          LabelIndex.AddObject(Definition.Get('_id',''), Definition);
      end;
    Cards := Board.Arrays['cards'];
    Checklists := Board.Arrays['checklists'];
    Items := Board.Arrays['checklistItems'];
    for I := 0 to Cards.Count - 1 do
    begin
      Card := Cards.Objects[I];
      if Card.Get('archived', False) then Continue;
      CardId := Card.Get('_id','');
      ListId := Card.Get('listId','');
      if ListId = '' then ListId := 'no-list';
      Index := ListIndex.IndexOf(ListId);
      if Index < 0 then ColumnCards := AddColumn(ListId, 'Untitled')
      else ColumnCards := TJSONArray(ListIndex.Objects[Index]);
      Name := Trim(Card.Get('title',''));
      if Name = '' then Name := 'Untitled';
      Due := ExportDate(Card.Get('dueAt',''));
      Tasks := TJSONArray.Create;
      Tags := TJSONArray.Create;
      Entry := TJSONObject.Create(['id', CardId, 'name', Name, 'description', Card.Get('description',''),
        'color', CardColor(Card.Get('color',''))]);
      ColumnCards.Add(Entry);
      if Due = '' then Entry.Add('dueDate', TJSONNull.Create) else Entry.Add('dueDate', Due);
      Entry.Add('isDueDateCounterRelative', False);
      Entry.Add('isDueDateCompleted', (Due <> '') and Card.Get('dueComplete', False));
      Entry.Add('tasks', Tasks);
      Entry.Add('tags', Tags);
      for J := 0 to Checklists.Count - 1 do
      begin
        Checklist := Checklists.Objects[J];
        if Checklist.Get('cardId','') <> CardId then Continue;
        for K := 0 to Items.Count - 1 do
        begin
          Item := Items.Objects[K];
          if Item.Get('checklistId','') <> Checklist.Get('_id','') then Continue;
          Name := Trim(Item.Get('title',''));
          if Name <> '' then Tasks.Add(TJSONObject.Create(['id', CardId + '-task-' + IntToStr(Tasks.Count + 1),
            'name', Name, 'finished', Item.Get('isFinished', False)]));
        end;
      end;
      CardLabels := Card.Get('labelIds', TJSONArray(nil));
      if CardLabels = nil then Continue;
      for J := 0 to CardLabels.Count - 1 do
      begin
        Index := LabelIndex.IndexOf(CardLabels.Strings[J]);
        if Index < 0 then Continue;
        Definition := TJSONObject(LabelIndex.Objects[Index]);
        Name := Definition.Get('name','');
        Hex := KanriHex(Definition.Get('color',''));
        Tag := TJSONObject.Create(['id', Definition.Get('_id', Name), 'text', Name]);
        Tags.Add(Tag);
        if Hex <> '' then
        begin
          Tag.Add('color', Hex);
          Tag.Add('style', 'background-color: ' + Hex + '; color: ' + TagTextColor(Hex));
        end;
      end;
    end;
    for I := 0 to Columns.Count - 1 do
    begin
      Column := Columns.Objects[I];
      ColumnCards := Column.Arrays['cards'];
      for J := 0 to ColumnCards.Count - 1 do
      begin
        Tags := ColumnCards.Objects[J].Arrays['tags'];
        for N := 0 to Tags.Count - 1 do
        begin
          Tag := Tags.Objects[N];
          Name := Tag.Get('id','');
          if Used.IndexOf(Name) >= 0 then Continue;
          Used.Add(Name);
          GlobalTags.Add(Tag.Clone);
        end;
      end;
    end;
    Result := Output.FormatJSON(AsCompressedJSON);
  finally
    Used.Free;
    LabelIndex.Free;
    ListIndex.Free;
    Output.Free;
  end;
end;

end.
