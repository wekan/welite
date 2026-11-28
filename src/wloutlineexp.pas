unit wloutlineexp;

{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface

uses fpjson;

function OutlineBoard(Board: TJSONObject; Opml: Boolean): string;

implementation

uses Classes, SysUtils, DateUtils, RegExpr;

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

function OutlineBoard(Board: TJSONObject; Opml: Boolean): string;
var Lines, ListTitles, ListNames, LabelNames: TStringList;
  Spaces, TagSeparators, ChecklistText, ClosedList: TRegExpr;
  Lists, Cards, Labels, Checklists, Items, CardLabels: TJSONArray;
  Entry, Card, Checklist, Item: TJSONObject;
  I, J, K, N, L, CardLine, CheckLine: Integer;
  Title, ListTitle, Task, Tag, Description, RawLine, DescriptionLine, Clock, Box, Category, Created, ListOfCard: string;
  Due: TDateTime;
  HasCards: Boolean;

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

  procedure CloseOutline(Index: Integer; const Indent: string);
  begin
    if Lines.Count = Index + 1 then Lines[Index] := Lines[Index] + '/>'
    else
    begin
      Lines[Index] := Lines[Index] + '>';
      Lines.Add(Indent + '</outline>');
    end;
  end;

const WhiteSpace = '\s| | | | | | | | | | | | | | | | | |　|﻿';
begin
  Lines := TStringList.Create;
  ListTitles := TStringList.Create;
  ListNames := TStringList.Create;
  LabelNames := TStringList.Create;
  Spaces := TRegExpr.Create('(' + WhiteSpace + ')+');
  TagSeparators := TRegExpr.Create('(' + WhiteSpace + '|#)+');
  ChecklistText := TRegExpr.Create('^((' + WhiteSpace + ')*)([-*+](' + WhiteSpace + ')+\[)');
  ClosedList := TRegExpr.Create('(?i)done|closed|complete|archiv|finished');
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

end.
