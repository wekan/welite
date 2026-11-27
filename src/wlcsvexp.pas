unit wlcsvexp;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses Classes, fpjson;
procedure WriteBoardCsv(Stream: TStream; Board: TJSONObject; const Fields, Separator: string);

implementation
uses SysUtils, StrUtils;

procedure WriteBoardCsv(Stream: TStream; Board: TJSONObject; const Fields, Separator: string);
const
  Captions: array[0..19] of string = ('Title','Description','List','Swimlane','Owner','Requested By','Assigned By',
    'Members','Assignee','Labels','Start','Due','End','Overtime (hours)','Spent time (hours)',
    'Created at','Last modified at','Last activity','Voting','Archived');
  Parts: array[0..19] of string = ('','description','board-info','board-info','people','people','people',
    'people','people','labels','dates','dates','dates','dates','dates','dates','dates','dates','voting','');
var Selected: TStringArray; All: Boolean; Row: string; Cells: array[0..19] of string;
  Cards, Definitions, Users, Lists, Lanes, Labels, Values: TJSONData;
  Card, Def, Field, Setting, Vote: TJSONObject; I, J, F: Integer;

  function ObjectAt(Values: TJSONData; const Id: string): TJSONObject;
  var K: Integer; Entry: TJSONData;
  begin
    Result := nil;
    if not (Values is TJSONArray) or (Id = '') then Exit;
    for K := 0 to Values.Count - 1 do
    begin
      Entry := Values.Items[K];
      if (Entry is TJSONObject) and (TJSONObject(Entry).Get('_id', '') = Id) then Exit(TJSONObject(Entry));
    end;
  end;

  function Lookup(Values: TJSONData; const Id, Key: string): string;
  var Entry: TJSONObject;
  begin
    Entry := ObjectAt(Values, Id);
    if Entry = nil then Result := '' else Result := Entry.Get(Key, '');
  end;

  function Includes(const Part: string): Boolean;
  var S: string;
  begin
    if All or (Part = '') then Exit(True);
    for S in Selected do if Trim(S) = Part then Exit(True);
    Result := False;
  end;

  procedure Add(const Text: string; EscapeFormula: Boolean = True);
  var Cell: string;
  begin
    Cell := Text;
    if EscapeFormula and (Cell <> '') and (Cell[1] in ['=', '+', '-', '@', #9, #13]) then Cell := '''' + Cell;
    if Row <> '' then Row := Row + Separator;
    Row := Row + '"' + StringReplace(Cell, '"', '""', [rfReplaceAll]) + '"';
  end;

  procedure Flush;
  begin
    Row := Row + #13#10;
    Stream.WriteBuffer(Row[1], Length(Row));
    Row := '';
  end;

  function GetText(Obj: TJSONObject; const Key, Fallback: string): string;
  var V: TJSONData;
  begin
    V := Obj.Find(Key);
    if (V = nil) or (V.JSONType = jtNull) then Result := Fallback else Result := V.AsString;
  end;

  function JoinNames(Ids, Source: TJSONData; const PropertyName, Joiner: string; WithColor: Boolean = False): string;
  var K: Integer; Id, Name: string;
  begin
    Result := '';
    if not (Ids is TJSONArray) then Exit;
    for K := 0 to Ids.Count - 1 do
    begin
      if Ids.Items[K].JSONType <> jtString then Continue;
      Id := Ids.Items[K].AsString;
      Name := Lookup(Source, Id, PropertyName);
      if WithColor and (ObjectAt(Source, Id) <> nil) then Name := Name + '-' + Lookup(Source, Id, 'color');
      if Name = '' then Continue;
      if Result <> '' then Result := Result + Joiner;
      Result := Result + Name;
    end;
  end;

  function Identity(const Key, TextKey: string): string;
  var Text: string;
  begin
    Result := JoinNames(Card.Find(Key), Users, 'username', ', ');
    Text := Card.Get(TextKey, '');
    if Text <> '' then
    begin
      if Result <> '' then Result := Result + ', ';
      Result := Result + Text;
    end;
    if Result = '' then Result := ' ';
  end;

  function OptionsText(Items: TJSONData): string;
  var K: Integer;
  begin
    Result := '';
    if not (Items is TJSONArray) then Exit;
    for K := 0 to Items.Count - 1 do
    begin
      if K > 0 then Result := Result + '/';
      Result := Result + TJSONArray(Items).Objects[K].Get('name', '');
    end;
  end;

  procedure AddCustom(Def: TJSONObject; Field: TJSONObject);
  var V, Items: TJSONData; Kind, Text: string;
  begin
    if Field = nil then begin Add(' '); Exit; end;
    V := Field.Find('value');
    if (V = nil) or (V.JSONType = jtNull) then begin Add(' '); Exit; end;
    Kind := Def.Get('type', '');
    if (Kind = 'dropdown') or (Kind = 'dropdownMultiSelect') then
    begin
      Items := Def.FindPath('settings.dropdownItems');
      if V.JSONType = jtString then Text := Lookup(Items, V.AsString, 'name')
      else Text := JoinNames(V, Items, 'name', ', ');
      Add(Text);
    end
    else if V.JSONType in [jtString, jtNumber, jtBoolean] then Add(V.AsString, V.JSONType = jtString)
    else Add(V.AsJSON);
  end;

  function CountItems(Obj: TJSONObject; const Key: string): Integer;
  var V: TJSONData;
  begin
    V := Obj.Find(Key);
    if V is TJSONArray then Result := V.Count else Result := 0;
  end;

  function VoteSummary: string;
  var Question: string;
  begin
    Result := ' ';
    if not (Card.Find('vote') is TJSONObject) then Exit;
    Vote := Card.Objects['vote'];
    Question := Vote.Get('question', '');
    if Question = '' then Exit;
    Result := Question + '-yes-' + IntToStr(CountItems(Vote, 'positive'));
    if Vote.Get('public', False) then Result := Result + '-' + JoinNames(Vote.Find('positive'), Users, 'username', ' ');
    Result := Result + '-no-' + IntToStr(CountItems(Vote, 'negative'));
    if Vote.Get('public', False) then Result := Result + '-' + JoinNames(Vote.Find('negative'), Users, 'username', ' ');
  end;

var Heading, Kind, Key: string;
begin
  All := False;
  Selected := Fields.Split([',']);
  All := not (Includes('description') or Includes('board-info') or Includes('people') or Includes('labels') or
    Includes('dates') or Includes('voting') or Includes('custom-fields') or Includes('attachments') or
    Includes('checklists') or Includes('comments') or Includes('subtasks') or Includes('card-details') or
    Includes('board-header') or Includes('activities') or Includes('poker') or Includes('stickers') or
    Includes('locations') or Includes('dependencies') or Includes('sort') or Includes('scrum'));
  Row := '';
  if Separator <> #9 then Stream.WriteBuffer(#$EF#$BB#$BF, 3);
  Cards := Board.Find('cards'); Lists := Board.Find('lists'); Lanes := Board.Find('swimlanes');
  Labels := Board.Find('labels'); Users := Board.Find('users'); Definitions := Board.Find('customFields');
  for I := Low(Captions) to High(Captions) do if Includes(Parts[I]) then Add(Captions[I]);
  if (Definitions is TJSONArray) and Includes('custom-fields') then
    for F := 0 to Definitions.Count - 1 do
    begin
      Def := TJSONArray(Definitions).Objects[F];
      Kind := Def.Get('type', '');
      Heading := 'CustomField-' + Def.Get('name', '') + '-' + Kind;
      if (Kind = 'dropdown') or (Kind = 'dropdownMultiSelect') then
        Heading := Heading + '-' + OptionsText(Def.FindPath('settings.dropdownItems'))
      else if Kind = 'currency' then
      begin
        Setting := nil;
        if Def.Find('settings') is TJSONObject then Setting := Def.Objects['settings'];
        Heading := Heading + '-';
        if Setting <> nil then Heading := Heading + Setting.Get('currencyCode', '');
      end;
      Add(Heading);
    end;
  Flush;
  if not (Cards is TJSONArray) then Exit;
  for I := 0 to Cards.Count - 1 do
  begin
    Card := TJSONArray(Cards).Objects[I];
    if (Card.Get('linkedId', '') <> '') or (GetText(Card, 'deletedAt', '') <> '') then Continue;
    Cells[0] := Card.Get('title', '');
    Cells[1] := Card.Get('description', '');
    Cells[2] := Lookup(Lists, Card.Get('listId', ''), 'title');
    Cells[3] := Lookup(Lanes, Card.Get('swimlaneId', ''), 'title');
    Cells[4] := Lookup(Users, Card.Get('userId', ''), 'username');
    Cells[5] := Identity('requesters', 'requestedBy');
    Cells[6] := Identity('assigners', 'assignedBy');
    Cells[7] := JoinNames(Card.Find('members'), Users, 'username', ' ');
    Cells[8] := JoinNames(Card.Find('assignees'), Users, 'username', ' ');
    Cells[9] := JoinNames(Card.Find('labelIds'), Labels, 'name', ' ', True);
    J := 10;
    for Key in ['startAt','dueAt','endAt','isOvertime','spentTime','createdAt','modifiedAt','dateLastActivity'] do
    begin
      Cells[J] := GetText(Card, Key, ' ');
      Inc(J);
    end;
    Cells[18] := VoteSummary;
    Cells[19] := LowerCase(BoolToStr(Card.Get('archived', False), True));
    for J := Low(Cells) to High(Cells) do
      if Includes(Parts[J]) then Add(Cells[J], (J <> 14) or not (Card.Find('spentTime') is TJSONNumber));
    if (Definitions is TJSONArray) and Includes('custom-fields') then
    begin
      Values := Card.Find('customFields');
      for F := 0 to Definitions.Count - 1 do
      begin
        Def := TJSONArray(Definitions).Objects[F];
        Field := ObjectAt(Values, Def.Get('_id', ''));
        AddCustom(Def, Field);
      end;
    end;
    Flush;
  end;
end;
end.
