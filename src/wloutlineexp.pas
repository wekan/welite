unit wloutlineexp;

{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface

uses fpjson;

function OutlineBoard(Board: TJSONObject; Opml: Boolean): string;

function TodoTxtBoard(Board: TJSONObject): string;
function OrgModeBoard(Board: TJSONObject): string;

implementation

uses Classes, SysUtils, DateUtils, RegExpr, Character;

const WhiteSpace = '\s| | | | | | | | | | | | | | | | | |　|﻿';
  TerminalList = '(?i)done|closed|complete|archiv|finished';

function XmlText(const Value: string): string;
begin
  Result := StringReplace(Value, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, '&#10;', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '&#9;', [rfReplaceAll]);
end;

function RfcDate(const Value: string): string;
const Days: TWeekNameArray = ('Sun','Mon','Tue','Wed','Thu','Fri','Sat');
  Months: TMonthNameArray = ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');
var At: TDateTime; Settings: TFormatSettings;
begin
  Result := '';
  if not TryISO8601ToDate(Value, At, True) then Exit;
  Settings := DefaultFormatSettings;
  Settings.ShortDayNames := Days;
  Settings.ShortMonthNames := Months;
  Result := FormatDateTime('ddd, dd mmm yyyy hh":"nn":"ss "GMT"', At, Settings);
end;

procedure IndexNames(Output: TStringList; Rows: TJSONArray; const NameKey: string);
var Index: Integer; Row: TJSONObject;
begin
  if Rows = nil then Exit;
  for Index := 0 to Rows.Count - 1 do
  begin
    Row := Rows.Objects[Index];
    if not Row.Get('archived', False) then
      Output.Values[Row.Get('_id', '')] := Row.Get(NameKey, '');
  end;
end;

function OutlineBoard(Board: TJSONObject; Opml: Boolean): string;
var Lines, ListTitles, ListNames, LabelNames: TStringList;
  Spaces, TagSeparators, ChecklistText, ClosedList: TRegExpr;
  Lists, Cards, Labels, Checklists, Items, CardLabels: TJSONArray;
  Entry, Card, Checklist, Item: TJSONObject;
  I, J, K, N, L, CardLine, CheckLine: Integer;
  Title, ListTitle, Task, Tag, Description, RawLine, DescriptionLine, Clock, Box, Category, Created, ListOfCard: string;
  Due: TDateTime;
  HasCards: Boolean;

  procedure CloseOutline(Index: Integer; const Indent: string);
  begin
    if Lines.Count = Index + 1 then Lines[Index] := Lines[Index] + '/>'
    else
    begin
      Lines[Index] := Lines[Index] + '>';
      Lines.Add(Indent + '</outline>');
    end;
  end;

begin
  Lines := TStringList.Create;
  ListTitles := TStringList.Create;
  ListNames := TStringList.Create;
  LabelNames := TStringList.Create;
  Spaces := TRegExpr.Create('(' + WhiteSpace + ')+');
  TagSeparators := TRegExpr.Create('(' + WhiteSpace + '|#)+');
  ChecklistText := TRegExpr.Create('^((' + WhiteSpace + ')*)([-*+](' + WhiteSpace + ')+\[)');
  ClosedList := TRegExpr.Create(TerminalList);
  try
    ListTitles.CaseSensitive := True;
    ListNames.CaseSensitive := True;
    LabelNames.CaseSensitive := True;
    Lists := Board.Arrays['lists'];
    Cards := Board.Arrays['cards'];
    Labels := Board.Get('labels', TJSONArray(nil));
    Checklists := Board.Arrays['checklists'];
    Items := Board.Arrays['checklistItems'];
    IndexNames(ListNames, Lists, 'title');
    IndexNames(LabelNames, Labels, 'name');
    for I := 0 to Lists.Count - 1 do
    begin
      Entry := Lists.Objects[I];
      ListTitle := Entry.Get('title', '');
      if not Entry.Get('archived', False) and (ListTitles.IndexOf(ListTitle) < 0) then
        ListTitles.Add(ListTitle);
    end;

    Title := Board.Get('title', '');
    if Opml then
    begin
      for I := 0 to Cards.Count - 1 do
        if not Cards.Objects[I].Get('archived', False) and
          (ListNames.IndexOfName(Cards.Objects[I].Get('listId', '')) < 0) and (ListTitles.IndexOf('') < 0) then
          ListTitles.Add('');
      Lines.Add('<?xml version="1.0" encoding="UTF-8"?>');
      Lines.Add('<opml version="2.0">');
      Lines.Add('  <head>');
      Lines.Add('    <title>' + XmlText(Title) + '</title>');
      Lines.Add('  </head>');
      Lines.Add('  <body>');
    end else
    begin
      if Title = '' then Title := 'Imported board';
      Lines.Add('# ' + Title);
      Lines.Add('');
    end;
    for ListTitle in ListTitles do
    begin
      HasCards := False;
      for I := 0 to Cards.Count - 1 do
      begin
        Card := Cards.Objects[I];
        L := ListNames.IndexOfName(Card.Get('listId', ''));
        if Card.Get('archived', False) or ((L < 0) and not Opml) then Continue;
        ListOfCard := '';
        if L >= 0 then ListOfCard := ListNames.ValueFromIndex[L];
        if ListOfCard <> ListTitle then Continue;
        if not HasCards then
        begin
          if Opml then Lines.Add('    <outline text="' + XmlText(ListTitle) + '">')
          else
          begin
            Lines.Add('## ' + ListTitle);
            Lines.Add('');
          end;
          HasCards := True;
        end;
        Box := ' ';
        if ClosedList.Exec(ListTitle) then Box := 'x';
        Task := '- [' + Box + '] ' + Card.Get('title', '');
        Category := '';
        CardLabels := Card.Get('labelIds', TJSONArray(nil));
        if CardLabels <> nil then
          for J := 0 to CardLabels.Count - 1 do
          begin
            Tag := LabelNames.Values[CardLabels.Strings[J]];
            if Tag = 'done' then Continue;
            if Opml then
            begin
              Tag := Trim(StringReplace(Tag, ',', ' ', [rfReplaceAll]));
              if Tag = '' then Continue;
              if Category <> '' then Category := Category + ',';
              Category := Category + Tag;
            end else
            begin
              Tag := TagSeparators.Replace(Trim(Spaces.Replace(Tag, ' ')), '-');
              if (Tag <> '') and (Tag[1] in ['A'..'Z', 'a'..'z']) then Task := Task + ' #' + Tag;
            end;
          end;
        CardLine := Lines.Count;
        if Opml then
        begin
          Task := '      <outline text="' + XmlText(Card.Get('title', '')) + '"';
          Description := Card.Get('description', '');
          if Description <> '' then Task := Task + ' _note="' + XmlText(Description) + '"';
          if Box = 'x' then Task := Task + ' _complete="true"';
          Created := RfcDate(Card.Get('createdAt', ''));
          if Created <> '' then Task := Task + ' created="' + Created + '"';
          if Category <> '' then Task := Task + ' category="' + XmlText(Category) + '"';
          Lines.Add(Task);
        end else
        begin
          if TryISO8601ToDate(Card.Get('dueAt', ''), Due, True) then
          begin
            Task := Task + ' @{' + FormatDateTime('yyyy-mm-dd', Due) + '}';
            Clock := FormatDateTime('hh":"nn', Due);
            if Clock <> '00:00' then Task := Task + ' @@{' + Clock + '}';
          end;
          Lines.Add(Task);
          Description := Card.Get('description', '');
          for RawLine in Description.Split([#10]) do
            if RawLine <> '' then
            begin
              DescriptionLine := RawLine;
              if ChecklistText.Exec(DescriptionLine) then
                Insert('\', DescriptionLine, Length(ChecklistText.Match[1]) + 1);
              Lines.Add('  ' + DescriptionLine);
            end;
        end;
        for K := 0 to Checklists.Count - 1 do
        begin
          Checklist := Checklists.Objects[K];
          if Checklist.Get('cardId', '') <> Card.Get('_id', '') then Continue;
          CheckLine := Lines.Count;
          if Opml then Lines.Add('        <outline text="' + XmlText(Checklist.Get('title', '')) + '"');
          for N := 0 to Items.Count - 1 do
          begin
            Item := Items.Objects[N];
            if Item.Get('checklistId', '') <> Checklist.Get('_id', '') then Continue;
            Title := Trim(Spaces.Replace(Item.Get('title', ''), ' '));
            if Title = '' then Title := 'Item';
            Box := ' ';
            if Item.Get('isFinished', False) then Box := 'x';
            if Opml then
            begin
              Task := '          <outline text="' + XmlText(Item.Get('title', '')) + '"';
              if Box = 'x' then Task := Task + ' _complete="true"';
              Lines.Add(Task + '/>');
            end else Lines.Add('  - [' + Box + '] ' + Title);
          end;
          if Opml then CloseOutline(CheckLine, '        ');
        end;
        if Opml then CloseOutline(CardLine, '      ');
      end;
      if Opml then
        if HasCards then Lines.Add('    </outline>')
        else Lines.Add('    <outline text="' + XmlText(ListTitle) + '"/>')
      else if HasCards then Lines.Add('');
    end;
    if Opml then
    begin
      Lines.Add('  </body>');
      Lines.Add('</opml>');
      Lines.Add('');
    end;
    Lines.LineBreak := #10;
    Result := Lines.Text;
    Delete(Result, Length(Result), 1);
  finally
    ClosedList.Free;
    ChecklistText.Free;
    TagSeparators.Free;
    Spaces.Free;
    LabelNames.Free;
    ListNames.Free;
    ListTitles.Free;
    Lines.Free;
  end;
end;

function TodoTxtBoard(Board: TJSONObject): string;
var Lines, ListNames, LabelNames, Words, Tags: TStringList;
  Spaces, ClosedList: TRegExpr;
  Cards, CardLabels: TJSONArray;
  Card: TJSONObject;
  I, J: Integer;
  ListTitle, Title, Created, Finished, Due, StartDay, Tag, Priority: string;
  Done: Boolean;

  function Day(const Key: string): string;
  var At: TDateTime;
  begin
    Result := '';
    if TryISO8601ToDate(Card.Get(Key, ''), At, True) then Result := FormatDateTime('yyyy-mm-dd', At);
  end;

  function Respace(const Value: string): string;
  begin
    Result := StringReplace(Trim(Spaces.Replace(Value, ' ')), ' ', '_', [rfReplaceAll]);
  end;

begin
  Lines := TStringList.Create;
  ListNames := TStringList.Create;
  LabelNames := TStringList.Create;
  Words := TStringList.Create;
  Tags := TStringList.Create;
  Spaces := TRegExpr.Create('(' + WhiteSpace + ')+');
  ClosedList := TRegExpr.Create(TerminalList);
  try
    ListNames.CaseSensitive := True;
    LabelNames.CaseSensitive := True;
    IndexNames(ListNames, Board.Arrays['lists'], 'title');
    IndexNames(LabelNames, Board.Get('labels', TJSONArray(nil)), 'name');
    Cards := Board.Arrays['cards'];
    for I := 0 to Cards.Count - 1 do
    begin
      Card := Cards.Objects[I];
      if Card.Get('archived', False) then Continue;
      ListTitle := ListNames.Values[Card.Get('listId', '')];
      Done := ClosedList.Exec(ListTitle);
      Tags.Clear;
      Words.Clear;
      Priority := '';
      CardLabels := Card.Get('labelIds', TJSONArray(nil));
      if CardLabels <> nil then
        for J := 0 to CardLabels.Count - 1 do
        begin
          Tag := LabelNames.Values[CardLabels.Strings[J]];
          if Tag = '' then Continue;
          if (Length(Tag) = 10) and (Copy(Tag, 1, 9) = 'priority:') and (Tag[10] in ['A'..'Z']) then
          begin
            if Priority = '' then Priority := Tag[10];
          end else if Tag[1] = '@' then Tags.Add('@' + Respace(Copy(Tag, 2, Length(Tag))))
          else Tags.Add('+' + Respace(Tag));
        end;
      Created := Day('createdAt');
      Finished := Day('endAt');
      Due := Day('dueAt');
      StartDay := Day('startAt');
      if Done then
      begin
        Words.Add('x');
        if (Finished <> '') and (Created <> '') then Words.Add(Finished);
      end else if Priority <> '' then Words.Add('(' + Priority + ')');
      if Created <> '' then Words.Add(Created);
      Title := Trim(Spaces.Replace(Card.Get('title', ''), ' '));
      if Title = '' then Title := 'Untitled';
      Words.Add(Title);
      Words.AddStrings(Tags);
      if Done and (Priority <> '') then Words.Add('pri:' + Priority);
      if Due <> '' then Words.Add('due:' + Due);
      if StartDay <> '' then Words.Add('t:' + StartDay);
      if ListTitle <> '' then Words.Add('list:' + Respace(ListTitle));
      Title := Words[0];
      for J := 1 to Words.Count - 1 do Title := Title + ' ' + Words[J];
      Lines.Add(Title);
    end;
    Lines.LineBreak := #10;
    Result := Lines.Text;
  finally
    ClosedList.Free;
    Spaces.Free;
    Tags.Free;
    Words.Free;
    LabelNames.Free;
    ListNames.Free;
    Lines.Free;
  end;
end;

function OrgTag(const Value: string): string;
var Text, Tag: UnicodeString; I, Size: Integer; Gap: Boolean;
begin
  Text := UTF8Decode(Value);
  Tag := '';
  I := 1;
  Gap := False;
  while I <= Length(Text) do
  begin
    Size := 1;
    if TCharacter.IsSurrogatePair(Text, I) then Size := 2;
    if (Text[I] in ['_','@','#','%']) or
      TCharacter.IsLetter(Text, I) or TCharacter.IsNumber(Text, I) then
    begin
      if Gap then Tag := Tag + '_';
      Tag := Tag + Copy(Text, I, Size);
      Gap := False;
    end else Gap := True;
    Inc(I, Size);
  end;
  while (Tag <> '') and (Tag[1] = '_') do Delete(Tag, 1, 1);
  while (Tag <> '') and (Tag[Length(Tag)] = '_') do SetLength(Tag, Length(Tag) - 1);
  Result := UTF8Encode(Tag);
end;

function OrgStamp(const Value: string; Active: Boolean; const Repeater: string = ''): string;
const Days: array[1..7] of string = ('Sun','Mon','Tue','Wed','Thu','Fri','Sat');
var At: TDateTime; Clock: string;
begin
  Result := '';
  if not TryISO8601ToDate(Value, At, True) then Exit;
  Result := FormatDateTime('yyyy-mm-dd', At) + ' ' + Days[DayOfWeek(At)];
  Clock := FormatDateTime('hh":"nn', At);
  if Clock <> '00:00' then Result := Result + ' ' + Clock;
  if Repeater <> '' then Result := Result + ' ' + Repeater;
  if Active then Result := '<' + Result + '>' else Result := '[' + Result + ']';
end;

function OrgModeBoard(Board: TJSONObject): string;
var Lines, ListNames, LabelNames, ListTitles: TStringList;
  Spaces, ClosedList, PropertySeparators: TRegExpr;
  Lists, Cards, CardLabels, Checklists, Items, Fields, Values, Options: TJSONArray;
  Card, Checklist, Item, Field, Entry, Option, Settings: TJSONObject;
  Value: TJSONData;
  ListTitle, Title, Tag, Tags, Priority, State, Plan, Stamp, Repeater, Description, Line, Name, FieldText: string;
  I, J, K, N, L, FirstItem, PropertyStart: Integer;
  Done: Boolean;

  function OneLine(const Text: string; const Fallback: string = ''): string;
  begin
    Result := Trim(Spaces.Replace(Text, ' '));
    if Result = '' then Result := Fallback;
  end;

  procedure AddPlan(const Kind, Date: string);
  begin
    if Date = '' then Exit;
    if Plan <> '' then Plan := Plan + ' ';
    Plan := Plan + Kind + ': ' + Date;
  end;

begin
  Lines := TStringList.Create;
  ListNames := TStringList.Create;
  LabelNames := TStringList.Create;
  ListTitles := TStringList.Create;
  Spaces := TRegExpr.Create('(' + WhiteSpace + ')+');
  ClosedList := TRegExpr.Create(TerminalList);
  PropertySeparators := TRegExpr.Create('(' + WhiteSpace + '|:)+');
  try
    ListNames.CaseSensitive := True;
    LabelNames.CaseSensitive := True;
    ListTitles.CaseSensitive := True;
    Lists := Board.Arrays['lists'];
    Cards := Board.Arrays['cards'];
    Checklists := Board.Arrays['checklists'];
    Items := Board.Arrays['checklistItems'];
    Fields := Board.Arrays['customFields'];
    IndexNames(ListNames, Lists, 'title');
    IndexNames(LabelNames, Board.Get('labels', TJSONArray(nil)), 'name');
    for I := 0 to Lists.Count - 1 do
    begin
      Item := Lists.Objects[I];
      Title := Item.Get('title', '');
      if not Item.Get('archived', False) and (ListTitles.IndexOf(Title) < 0) then ListTitles.Add(Title);
    end;
    Lines.Add('#+TITLE: ' + OneLine(Board.Get('title', '')));
    Lines.Add('#+TODO: TODO | DONE');
    Lines.Add('');
    for I := 0 to ListTitles.Count do
    begin
      ListTitle := '';
      if I < ListTitles.Count then
      begin
        ListTitle := ListTitles[I];
        Lines.Add('* ' + OneLine(ListTitle, 'List'));
      end;
      for J := 0 to Cards.Count - 1 do
      begin
        Card := Cards.Objects[J];
        if Card.Get('archived', False) then Continue;
        L := ListNames.IndexOfName(Card.Get('listId', ''));
        if L < 0 then
        begin
          if I < ListTitles.Count then Continue;
        end else if (I = ListTitles.Count) or (ListNames.ValueFromIndex[L] <> ListTitle) then Continue;
        Done := ClosedList.Exec(ListTitle);
        Priority := '';
        Tags := '';
        CardLabels := Card.Get('labelIds', TJSONArray(nil));
        if CardLabels <> nil then
          for K := 0 to CardLabels.Count - 1 do
          begin
            Tag := LabelNames.Values[CardLabels.Strings[K]];
            if Tag = 'done' then Done := True
            else if (Length(Tag) = 10) and (Copy(Tag, 1, 9) = 'priority:') and (Tag[10] in ['A'..'Z','0'..'9']) then
            begin
              if Priority = '' then Priority := '[#' + Tag[10] + '] ';
            end else
            begin
              Tag := OrgTag(Tag);
              if Tag <> '' then Tags := Tags + ':' + Tag;
            end;
          end;
        if Tags <> '' then Tags := ' ' + Tags + ':';
        State := 'TODO';
        if Done then State := 'DONE';
        Lines.Add('** ' + State + ' ' + Priority + OneLine(Card.Get('title', ''), 'Untitled') + Tags);

        Repeater := '';
        if not Done then
          case Card.Get('recurrenceInterval', '') of
            'daily': Repeater := '+1d';
            'weekly': Repeater := '+1w';
            'monthly': Repeater := '+1m';
          end;
        Plan := '';
        AddPlan('SCHEDULED', OrgStamp(Card.Get('startAt',''), True));
        AddPlan('DEADLINE', OrgStamp(Card.Get('dueAt',''), True, Repeater));
        if Done then AddPlan('CLOSED', OrgStamp(Card.Get('endAt',''), False));
        if Plan <> '' then Lines.Add('   ' + Plan);
        PropertyStart := Lines.Count;
        Stamp := OrgStamp(Card.Get('createdAt', ''), False);
        if Stamp <> '' then Lines.Add('   :CREATED:  ' + Stamp);
        Values := Card.Get('customFields', TJSONArray(nil));
        if Values <> nil then
          for K := 0 to Values.Count - 1 do
          begin
            Entry := Values.Objects[K];
            Value := Entry.Find('value');
            if (Value = nil) or (Value.JSONType in [jtNull, jtArray, jtObject]) then Continue;
            for N := 0 to Fields.Count - 1 do
            begin
              Field := Fields.Objects[N];
              if Field.Get('_id','') <> Entry.Get('_id','') then Continue;
              Name := PropertySeparators.Replace(Trim(Field.Get('name','')), '_');
              if (Name = '') or SameText(Name, 'CREATED') or SameText(Name, 'ID') or SameText(Name, 'CUSTOM_ID') then Break;
              FieldText := Value.AsString;
              Settings := Field.Get('settings', TJSONObject(nil));
              Options := nil;
              if Settings <> nil then Options := Settings.Get('dropdownItems', TJSONArray(nil));
              if (Field.Get('type','') = 'dropdown') and (Options <> nil) then
                for L := 0 to Options.Count - 1 do
                begin
                  Option := Options.Objects[L];
                  if Option.Get('_id','') = FieldText then
                  begin
                    FieldText := Option.Get('name','');
                    Break;
                  end;
                end;
              FieldText := OneLine(FieldText);
              if FieldText <> '' then Lines.Add('   :' + Name + ': ' + FieldText);
              Break;
            end;
          end;
        if Lines.Count > PropertyStart then
        begin
          Lines.Insert(PropertyStart, '   :PROPERTIES:');
          Lines.Add('   :END:');
        end;
        Description := Card.Get('description','');
        if Description <> '' then
        begin
          Description := StringReplace(Description, #13#10, #10, [rfReplaceAll]);
          Description := StringReplace(Description, #13, #10, [rfReplaceAll]);
          for Line in Description.Split([#10]) do
            if Line = '' then Lines.Add('') else Lines.Add('   ' + Line);
        end;
        for K := 0 to Checklists.Count - 1 do
        begin
          Checklist := Checklists.Objects[K];
          if Checklist.Get('cardId','') <> Card.Get('_id','') then Continue;
          FirstItem := Lines.Count;
          for N := 0 to Items.Count - 1 do
          begin
            Item := Items.Objects[N];
            if Item.Get('checklistId','') <> Checklist.Get('_id','') then Continue;
            State := 'TODO';
            if Item.Get('isFinished', False) then State := 'DONE';
            Lines.Add('**** ' + State + ' ' + OneLine(Item.Get('title',''), 'Item'));
          end;
          if Lines.Count > FirstItem then
            Lines.Insert(FirstItem, '*** ' + OneLine(Checklist.Get('title',''), 'Checklist'));
        end;
      end;
    end;
    Lines.LineBreak := #10;
    Result := Lines.Text;
  finally
    PropertySeparators.Free;
    ClosedList.Free;
    Spaces.Free;
    ListTitles.Free;
    LabelNames.Free;
    ListNames.Free;
    Lines.Free;
  end;
end;

end.
