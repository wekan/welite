unit wltrelloexp;

{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface

uses fpjson;

function TrelloExport(Board: TJSONObject): string;

implementation

uses SysUtils, DateUtils;

function TrelloExport(Board: TJSONObject): string;
const Epoch = '1970-01-01T00:00:00.000Z';
var Output, Source, Card, Check, Comment, Entry: TJSONObject;
  Cards, Lists, Labels, Checks, Items, Comments, OutLists, OutCards, OutLabels, OutChecks,
  Actions, CardChecks, CheckItems, Users, Members, CardMembers, IDs, Fields, Values, FieldItems: TJSONArray;
  Data: TJSONData;
  I, J, K, Count: Integer;
  BoardId, CardId, CheckId, Title, Stamp, Name, State, Key, Username: string;
  UserNames, MemberNames, FieldsByName, CardFields: TJSONObject;
  AuthorId, Author: TJSONData;

  function DateValue(const Text: string): string;
  var At: TDateTime;
  begin
    Result := '';
    if (Length(Text) < 10) or (Text[5] <> '-') or (Text[8] <> '-') or
      ((Length(Text) > 10) and (Text[11] <> 'T')) then Exit;
    if TryISO8601ToDate(Text, At, True) then
      Result := FormatDateTime('yyyy-mm-dd"T"hh":"nn":"ss"."zzz"Z"', At);
  end;

  function AsText(Value: TJSONData): string;
  var Index: Integer;
  begin
    case Value.JSONType of
      jtNull: Result := '';
      jtBoolean, jtNumber: Result := Value.AsJSON;
      jtObject: Result := '[object Object]';
      jtArray:
        begin
          Result := '';
          for Index := 0 to Value.Count - 1 do
          begin
            if Index > 0 then Result := Result + ', ';
            Result := Result + AsText(Value.Items[Index]);
          end;
        end;
      else Result := Value.AsString;
    end;
  end;

  function FieldValues(Row: TJSONObject): TJSONObject;
  var Definitions, Entries, Options: TJSONArray;
    Definition, Field, Settings: TJSONObject;
    V, Resolved: TJSONData;
    N, M: Integer;
    FieldName, Combined: string;

    function OptionName(const Id: string): string;
    var Index: Integer;
    begin
      Result := Id;
      if Options = nil then Exit;
      for Index := 0 to Options.Count - 1 do
        if Options.Objects[Index].Get('_id','') = Id then Exit(Options.Objects[Index].Get('name',''));
    end;

  begin
    Result := TJSONObject.Create;
    Entries := Row.Get('customFields', TJSONArray(nil));
    if Entries = nil then Exit;
    Definitions := Board.Arrays['customFields'];
    for N := 0 to Definitions.Count - 1 do
    begin
      Definition := Definitions.Objects[N];
      V := nil;
      for M := 0 to Entries.Count - 1 do
      begin
        Field := Entries.Objects[M];
        if Field.Get('_id','') = Definition.Get('_id','') then
        begin
          V := Field.Find('value');
          Break;
        end;
      end;
      if (V = nil) or (V.JSONType = jtNull) then Continue;
      Options := nil;
      Settings := Definition.Get('settings', TJSONObject(nil));
      if Settings <> nil then Options := Settings.Get('dropdownItems', TJSONArray(nil));
      if Definition.Get('type','') = 'dropdownMultiSelect' then
      begin
        Combined := '';
        if V is TJSONArray then
          for M := 0 to V.Count - 1 do
          begin
            if M > 0 then Combined := Combined + ', ';
            Combined := Combined + OptionName(AsText(V.Items[M]));
          end;
        Resolved := TJSONString.Create(Combined);
      end else if (V.JSONType = jtString) and (Options <> nil) then
        Resolved := TJSONString.Create(OptionName(V.AsString))
      else Resolved := V.Clone;
      if (Resolved.JSONType = jtString) and (Resolved.AsString = '') then
      begin
        Resolved.Free;
        Continue;
      end;
      FieldName := Definition.Get('name','');
      Result.Delete(FieldName);
      Result.Add(FieldName, Resolved);
    end;
  end;

  function FieldType(Value: TJSONData): string;
  begin
    case Value.JSONType of
      jtBoolean: Exit('checkbox');
      jtNumber: Exit('number');
      jtString: if DateValue(Value.AsString) <> '' then Exit('date');
    end;
    Result := 'text';
  end;

  procedure DiscoverFields;
  var Row, Index, Position: Integer; Definition, ValuesByName: TJSONObject; FieldName, Kind, Id: string;
  begin
    for Row := 0 to Cards.Count - 1 do
    begin
      ValuesByName := FieldValues(Cards.Objects[Row]);
      Values.Add(ValuesByName);
      for Index := 0 to ValuesByName.Count - 1 do
      begin
        FieldName := ValuesByName.Names[Index];
        Kind := FieldType(ValuesByName.Items[Index]);
        Position := FieldsByName.Get(FieldName, 0);
        if Position = 0 then
        begin
          Position := Fields.Count + 1;
          Id := BoardId;
          if Id = '' then Id := 'board';
          Definition := TJSONObject.Create(['id', Id + '-field-' + IntToStr(Position),
            'idModel', BoardId, 'modelType', 'board', 'name', FieldName, 'type', Kind,
            'pos', Position, 'display', TJSONObject.Create(['cardFront', True])]);
          Fields.Add(Definition);
          FieldsByName.Add(FieldName, Position);
        end else if Fields.Objects[Position - 1].Get('type','') <> Kind then
          Fields.Objects[Position - 1].Strings['type'] := 'text';
      end;
    end;
  end;

  function WriteFieldValue(const Kind: string; Value: TJSONData): TJSONObject;
  begin
    case Kind of
      'checkbox': Result := TJSONObject.Create(['checked', AsText(Value)]);
      'number': Result := TJSONObject.Create(['number', AsText(Value)]);
      'date': Result := TJSONObject.Create(['date', DateValue(Value.AsString)]);
      else Result := TJSONObject.Create(['text', AsText(Value)]);
    end;
  end;

  function AddMember(const UserId: string): string;
  begin
    Result := UserNames.Get(UserId, '');
    if (Result = '') or (MemberNames.Find(Result) <> nil) then Exit;
    MemberNames.Add(Result, True);
    Members.Add(TJSONObject.Create(['id', Result, 'username', Result, 'fullName', Result]));
  end;

  procedure AppendUnique(ArrayValue: TJSONArray; const Value: string);
  var Index: Integer;
  begin
    if Value = '' then Exit;
    for Index := 0 to ArrayValue.Count - 1 do if ArrayValue.Strings[Index] = Value then Exit;
    ArrayValue.Add(Value);
  end;
begin
  BoardId := Board.Get('_id', '');
  OutLists := TJSONArray.Create;
  OutCards := TJSONArray.Create;
  OutLabels := TJSONArray.Create;
  OutChecks := TJSONArray.Create;
  Actions := TJSONArray.Create;
  Members := TJSONArray.Create;
  Fields := TJSONArray.Create;
  FieldsByName := TJSONObject.Create;
  Values := TJSONArray.Create;
  UserNames := TJSONObject.Create;
  MemberNames := TJSONObject.Create;
  Output := TJSONObject.Create(['name', Board.Get('title', ''), 'prefs',
    TJSONObject.Create(['background', 'blue', 'permissionLevel', 'private']),
    'members', Members, 'customFields', Fields,
    'labels', OutLabels, 'lists', OutLists, 'cards', OutCards, 'checklists', OutChecks, 'actions', Actions]);
  try
    Users := Board.Arrays['users'];
    for I := 0 to Users.Count - 1 do
      UserNames.Add(Users.Objects[I].Get('_id',''), Users.Objects[I].Get('username',''));
    Labels := Board.Get('labels', TJSONArray(nil));
    if Labels <> nil then
      for I := 0 to Labels.Count - 1 do
      begin
        Source := Labels.Objects[I];
        OutLabels.Add(TJSONObject.Create(['id', Source.Get('_id', ''), 'name', Source.Get('name', ''),
          'color', Source.Get('color', '')]));
      end;
    Lists := Board.Arrays['lists'];
    for I := 0 to Lists.Count - 1 do
    begin
      Source := Lists.Objects[I];
      OutLists.Add(TJSONObject.Create(['id', Source.Get('_id', ''), 'name', Source.Get('title', ''),
        'closed', Source.Get('archived', False), 'pos', I + 1]));
    end;
    Cards := Board.Arrays['cards'];
    DiscoverFields;
    Checks := Board.Arrays['checklists'];
    Items := Board.Arrays['checklistItems'];
    Comments := Board.Arrays['comments'];
    for I := 0 to Cards.Count - 1 do
    begin
      Source := Cards.Objects[I];
      CardId := Source.Get('_id', '');
      Title := Source.Get('title', '');
      Stamp := Source.Get('modifiedAt', '');
      if Stamp = '' then Stamp := Source.Get('createdAt', '');
      if Stamp = '' then Stamp := Epoch;
      Card := TJSONObject.Create(['id', CardId, 'name', Title, 'desc', Source.Get('description', ''),
        'pos', I + 1, 'dateLastActivity', Stamp, 'idList', Source.Get('listId', ''),
        'dueComplete', Source.Get('dueComplete', False), 'closed', Source.Get('archived', False)]);
      OutCards.Add(Card);
      Data := Source.Find('dueAt');
      if (Data <> nil) and (Data.JSONType = jtString) and (Data.AsString <> '') then Card.Add('due', Data.Clone)
      else Card.Add('due', TJSONNull.Create);
      Stamp := Source.Get('startAt', '');
      if Stamp <> '' then Card.Add('start', Stamp);
      Data := Source.Find('labelIds');
      if Data is TJSONArray then Card.Add('idLabels', Data.Clone)
      else Card.Add('idLabels', TJSONArray.Create);
      CardMembers := TJSONArray.Create;
      Card.Add('idMembers', CardMembers);
      for Key in ['assignees', 'members'] do
      begin
        IDs := Source.Get(Key, TJSONArray(nil));
        if IDs <> nil then
          for J := 0 to IDs.Count - 1 do AppendUnique(CardMembers, AddMember(IDs.Strings[J]));
      end;
      FieldItems := TJSONArray.Create;
      Card.Add('customFieldItems', FieldItems);
      CardFields := Values.Objects[I];
      for J := 0 to Fields.Count - 1 do
      begin
        Entry := Fields.Objects[J];
        Data := CardFields.Find(Entry.Get('name',''));
        if Data = nil then Continue;
        Key := Entry.Get('id','');
        FieldItems.Add(TJSONObject.Create(['id', CardId + '-' + Key, 'idCustomField', Key,
          'idModel', CardId, 'modelType', 'card', 'value', WriteFieldValue(Entry.Get('type',''), Data)]));
      end;
      CardChecks := TJSONArray.Create;
      Card.Add('idChecklists', CardChecks);
      for J := 0 to Checks.Count - 1 do
      begin
        Check := Checks.Objects[J];
        if Check.Get('cardId', '') <> CardId then Continue;
        CheckId := CardId + '-checklist-' + IntToStr(CardChecks.Count + 1);
        Name := Check.Get('title', '');
        if Name = '' then Name := 'Checklist';
        CheckItems := TJSONArray.Create;
        CardChecks.Add(CheckId);
        OutChecks.Add(TJSONObject.Create(['id', CheckId, 'idBoard', BoardId, 'idCard', CardId,
          'name', Name, 'pos', CardChecks.Count, 'checkItems', CheckItems]));
        for K := 0 to Items.Count - 1 do
        begin
          Entry := Items.Objects[K];
          if Entry.Get('checklistId', '') <> Check.Get('_id', '') then Continue;
          State := 'incomplete';
          if Entry.Get('isFinished', False) then State := 'complete';
          CheckItems.Add(TJSONObject.Create(['id', CheckId + '-item-' + IntToStr(CheckItems.Count + 1),
            'name', Entry.Get('title', ''), 'state', State, 'pos', CheckItems.Count + 1]));
        end;
      end;
      Count := 0;
      for J := 0 to Comments.Count - 1 do
      begin
        Comment := Comments.Objects[J];
        Name := Comment.Get('text', '');
        if (Comment.Get('cardId', '') <> CardId) or (Name = '') then Continue;
        Inc(Count);
        Stamp := Comment.Get('createdAt', '');
        if Stamp = '' then Stamp := Source.Get('createdAt', '');
        if Stamp = '' then Stamp := Epoch;
        Username := AddMember(Comment.Get('userId',''));
        if Username = '' then
        begin
          AuthorId := TJSONNull.Create;
          Author := TJSONNull.Create;
        end else
        begin
          AuthorId := TJSONString.Create(Username);
          Author := TJSONObject.Create(['username', Username, 'fullName', Username]);
        end;
        Actions.Add(TJSONObject.Create(['id', CardId + '-comment-' + IntToStr(Count),
          'type', 'commentCard', 'date', Stamp, 'idMemberCreator', AuthorId,
          'memberCreator', Author, 'data', TJSONObject.Create(['text', Name,
          'card', TJSONObject.Create(['id', CardId, 'name', Title]),
          'board', TJSONObject.Create(['id', BoardId])])]));
      end;
    end;
    Result := Output.FormatJSON(AsCompressedJSON);
  finally
    Values.Free;
    FieldsByName.Free;
    MemberNames.Free;
    UserNames.Free;
    Output.Free;
  end;
end;

end.
