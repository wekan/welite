unit wltrelloexp;

{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface

uses fpjson, SysUtils;

function TrelloExport(Board: TJSONObject): string;

implementation

function TrelloExport(Board: TJSONObject): string;
const Epoch = '1970-01-01T00:00:00.000Z';
var Output, Source, Card, Check, Comment, Entry: TJSONObject;
  Cards, Lists, Labels, Checks, Items, Comments, OutLists, OutCards, OutLabels, OutChecks,
  Actions, CardChecks, CheckItems, Users, Members, CardMembers, IDs: TJSONArray;
  Data: TJSONData;
  I, J, K, Count: Integer;
  BoardId, CardId, CheckId, Title, Stamp, Name, State, Key, Username: string;
  UserNames, MemberNames: TJSONObject;
  AuthorId, Author: TJSONData;

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
  UserNames := TJSONObject.Create;
  MemberNames := TJSONObject.Create;
  Output := TJSONObject.Create(['name', Board.Get('title', ''), 'prefs',
    TJSONObject.Create(['background', 'blue', 'permissionLevel', 'private']),
    'members', Members, 'customFields', TJSONArray.Create,
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
      Card.Add('customFieldItems', TJSONArray.Create);
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
    MemberNames.Free;
    UserNames.Free;
    Output.Free;
  end;
end;

end.
