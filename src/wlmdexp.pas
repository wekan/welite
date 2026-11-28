unit wlmdexp;

{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface

uses fpjson;

function MarkdownBoard(Board: TJSONObject): string;

implementation

uses Classes, SysUtils, DateUtils, RegExpr;

function MarkdownBoard(Board: TJSONObject): string;
var Lines, ListTitles, ListNames, LabelNames: TStringList;
  Spaces, TagSeparators, ChecklistText, ClosedList: TRegExpr;
  Lists, Cards, Labels, Checklists, Items, CardLabels: TJSONArray;
  Entry, Card, Checklist, Item: TJSONObject;
  I, J, K, N, L: Integer;
  Title, ListTitle, Task, Tag, Description, RawLine, DescriptionLine, Clock, Box: string;
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
    if Title = '' then Title := 'Imported board';
    Lines.Add('# ' + Title);
    Lines.Add('');
    for ListTitle in ListTitles do
    begin
      HasCards := False;
      for I := 0 to Cards.Count - 1 do
      begin
        Card := Cards.Objects[I];
        L := ListNames.IndexOfName(Card.Get('listId', ''));
        if (L < 0) or (ListNames.ValueFromIndex[L] <> ListTitle) or Card.Get('archived', False) then Continue;
        if not HasCards then
        begin
          Lines.Add('## ' + ListTitle);
          Lines.Add('');
          HasCards := True;
        end;
        Box := ' ';
        if ClosedList.Exec(ListTitle) then Box := 'x';
        Task := '- [' + Box + '] ' + Card.Get('title', '');
        CardLabels := Card.Get('labelIds', TJSONArray(nil));
        if CardLabels <> nil then
          for J := 0 to CardLabels.Count - 1 do
          begin
            Tag := LabelNames.Values[CardLabels.Strings[J]];
            if Tag = 'done' then Continue;
            Tag := TagSeparators.Replace(Trim(Spaces.Replace(Tag, ' ')), '-');
            if (Tag <> '') and (Tag[1] in ['A'..'Z', 'a'..'z']) then Task := Task + ' #' + Tag;
          end;
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
        for K := 0 to Checklists.Count - 1 do
        begin
          Checklist := Checklists.Objects[K];
          if Checklist.Get('cardId', '') <> Card.Get('_id', '') then Continue;
          for N := 0 to Items.Count - 1 do
          begin
            Item := Items.Objects[N];
            if Item.Get('checklistId', '') <> Checklist.Get('_id', '') then Continue;
            Title := Trim(Spaces.Replace(Item.Get('title', ''), ' '));
            if Title = '' then Title := 'Item';
            Box := ' ';
            if Item.Get('isFinished', False) then Box := 'x';
            Lines.Add('  - [' + Box + '] ' + Title);
          end;
        end;
      end;
      if HasCards then Lines.Add('');
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
