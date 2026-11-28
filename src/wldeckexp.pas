unit wldeckexp;

{$mode objfpc}{$H+}{$CODEPAGE UTF8}

interface

uses fpjson;

function DeckExport(Board: TJSONObject): string;

implementation

function DeckExport(Board: TJSONObject): string;
var Output, Stack, Card, Source, Row, People, Labels: TJSONObject;
  Stacks, Lists, Cards, Users, Comments, LabelsSource, StackCards, CardLabels, Assigned, CardComments: TJSONArray;
  Values: TJSONData;
  I, J, K, N: Integer;
  ListId, CardId, Name, Key: string;

begin
  Stacks:=TJSONArray.Create;
  Output:=TJSONObject.Create(['title',Board.Get('title',''),'stacks',Stacks]);
  People:=TJSONObject.Create;
  Labels:=TJSONObject.Create;
  try
    Users:=Board.Arrays['users'];
    for I:=0 to Users.Count-1 do
    begin
      Row:=Users.Objects[I];
      People.Add(Row.Get('_id',''),Row.Get('username',''));
    end;
    LabelsSource:=Board.Get('labels',TJSONArray(nil));
    if LabelsSource<>nil then
      for I:=0 to LabelsSource.Count-1 do
      begin
        Row:=LabelsSource.Objects[I];
        Labels.Add(Row.Get('_id',''),Row.Get('name',''));
      end;
    Lists:=Board.Arrays['lists']; Cards:=Board.Arrays['cards']; Comments:=Board.Arrays['comments'];
    for I:=0 to Lists.Count-1 do
    begin
      Source:=Lists.Objects[I];
      if Source.Get('archived',False) then Continue;
      ListId:=Source.Get('_id','');
      StackCards:=TJSONArray.Create;
      Stack:=TJSONObject.Create(['title',Source.Get('title',''),'cards',StackCards]);
      Stacks.Add(Stack);
      for J:=0 to Cards.Count-1 do
      begin
        Source:=Cards.Objects[J];
        if (Source.Get('listId','')<>ListId) or Source.Get('archived',False) then Continue;
        CardId:=Source.Get('_id','');
        Card:=TJSONObject.Create(['title',Source.Get('title',''),'description',Source.Get('description','')]);
        StackCards.Add(Card);
        Name:=Source.Get('dueAt','');
        if Name<>'' then Card.Add('duedate',Name);
        CardLabels:=TJSONArray.Create; Card.Add('labels',CardLabels);
        Values:=Source.Find('labelIds');
        if Values is TJSONArray then
          for K:=0 to Values.Count-1 do
          begin
            Name:=Labels.Get(Values.Items[K].AsString,'');
            if Name<>'' then CardLabels.Add(TJSONObject.Create(['title',Name]));
          end;
        Name:=Source.Get('createdAt','');
        if Name<>'' then Card.Add('createdAt',Name);
        Name:=Source.Get('endAt','');
        if Name<>'' then Card.Add('done',Name)
        else if Source.Get('dueComplete',False) then Card.Add('done',True);
        Assigned:=TJSONArray.Create;
        for Key in ['assignees','members'] do
        begin
          Values:=Source.Find(Key);
          if Values is TJSONArray then
            for K:=0 to Values.Count-1 do
            begin
              Name:=People.Get(Values.Items[K].AsString,'');
              if Name<>'' then Assigned.Add(TJSONObject.Create(['participant',TJSONObject.Create(['uid',Name])]));
            end;
        end;
        if Assigned.Count>0 then Card.Add('assignedUsers',Assigned) else Assigned.Free;
        Name:=People.Get(Source.Get('userId',''),'');
        if Name<>'' then Card.Add('owner',TJSONObject.Create(['uid',Name]));
        CardComments:=TJSONArray.Create;
        for N:=0 to Comments.Count-1 do
        begin
          Row:=Comments.Objects[N];
          if Row.Get('cardId','')<>CardId then Continue;
          CardComments.Add(TJSONObject.Create(['message',Row.Get('text',''),
            'actorId',People.Get(Row.Get('userId',''),''),
            'creationDateTime',Row.Get('createdAt','')]));
        end;
        if CardComments.Count>0 then Card.Add('comments',CardComments) else CardComments.Free;
      end;
    end;
    Result:=Output.FormatJSON(AsCompressedJSON);
  finally
    Labels.Free; People.Free; Output.Free;
  end;
end;

end.
