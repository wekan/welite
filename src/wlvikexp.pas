unit wlvikexp;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses Classes, fpjson;
procedure WriteVikunjaArchive(Output:TStream; Board:TJSONObject);
implementation
uses SysUtils, DateUtils, StrUtils, Math, Contnrs, zipper, wlhtml;

const PositionStep=65536;
  EmptyDate='0001-01-01T00:00:00Z';
  ViewKinds:array[0..3] of string=('list','gantt','table','kanban');

function ExportTime(const Text,Fallback:string):string;
var At:TDateTime;
begin
  Result:=Fallback;
  if (Text<>'') and not AnsiStartsStr('0001-01-01',Text) and TryISO8601ToDate(Text,At,True) then
    Result:=FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',At);
end;

function Paragraphs(const Text:string):string;
var Line,Input:string; Lines:TStringArray; I:Integer; Open:Boolean;
begin
  Input:=StringReplace(Text,#13#10,#10,[rfReplaceAll]);
  Input:=StringReplace(Input,#13,#10,[rfReplaceAll]);
  Lines:=Trim(Input).Split([#10]);
  Result:=''; Open:=False;
  for I:=0 to High(Lines) do
  begin
    Line:=Lines[I];
    if Trim(Line)='' then
    begin
      if Open then Result:=Result+'</p>';
      Open:=False;
      Continue;
    end;
    if Open then Result:=Result+'<br>' else Result:=Result+'<p>';
    Result:=Result+HtmlEncode(Line);
    Open:=True;
  end;
  if Open then Result:=Result+'</p>';
end;

procedure WriteVikunjaArchive(Output:TStream; Board:TJSONObject);
var Projects,Lists,Lanes,Cards,Views,Buckets,Tasks,Labels,People,Comments:TJSONArray;
  Zip:TZipper;
  DataStream,FiltersStream,VersionStream:TStringStream;
  ActiveCards:TFPList;
  UserMap,LabelMap,LaneMap,ListMap,TaskMap,CheckMap,ItemMap,CommentMap:TFPHashObjectList;
  Project,Task,Card,View,Entry,Other:TJSONObject;
  Stamp,BoardTitle,Id,LaneId,ListId,Name,Creator,Description,DoneAt:string;
  I,J,K,ParentId,ProjectId,ViewId,BucketId,NextBucket,DefaultBucket,DoneBucket,Position,Limit,
    CommentId:Integer;
  Several,Done:Boolean;
  Serialized:string;

  function Active(Entry:TJSONObject):Boolean;
  begin
    Result:=not Entry.Get('archived',False) and (Entry.Get('deletedAt','')='');
  end;

  procedure IndexRows(Index:TFPHashObjectList; Rows:TJSONArray);
  var N:Integer;
  begin
    for N:=0 to Rows.Count-1 do Index.Add(Rows.Objects[N].Get('_id',''),Rows.Objects[N]);
  end;

  procedure Group(Index:TFPHashObjectList; Rows:TJSONArray; const Key:string);
  var N:Integer; Items:TFPList; Entry:TJSONObject; Id:string;
  begin
    for N:=0 to Rows.Count-1 do
    begin
      Entry:=Rows.Objects[N]; Id:=Entry.Get(Key,'');
      if Id='' then Continue;
      Items:=TFPList(Index.Find(Id));
      if Items=nil then
      begin Items:=TFPList.Create; Index.Add(Id,Items); end;
      Items.Add(Entry);
    end;
  end;

  function TitleOf(const Text,Fallback:string):string;
  begin
    Result:=Trim(Text);
    if Result='' then Result:=Fallback;
  end;

  function NewProject(const Title:string; Id,Parent,Position:Integer):TJSONObject;
  begin
    Result:=TJSONObject.Create(['id',Id,'title',Title,'description','','identifier','','hex_color','',
      'parent_project_id',Parent,'is_archived',False,'position',Position,'background_file_id',0,
      'created',Stamp,'updated',Stamp]);
    Projects.Add(Result);
    Result.Add('background_information',TJSONNull.Create);
    Result.Add('child_projects',TJSONNull.Create);
    Result.Add('views',TJSONArray.Create);
    Result.Add('buckets',TJSONArray.Create);
    Result.Add('tasks',TJSONArray.Create);
    Result.Add('task_buckets',TJSONArray.Create);
    Result.Add('positions',TJSONArray.Create);
  end;

  function ExportUser(const Id:string):TJSONObject;
  var Source:TJSONObject;
  begin
    Result:=nil;
    if Id='' then Exit;
    Source:=TJSONObject(UserMap.Find(Id));
    if Source=nil then Exit;
    Result:=TJSONObject.Create(['id',UserMap.FindIndexOf(Id)+1,'name','',
      'username',Source.Get('username',''),'created',Stamp,'updated',Stamp]);
  end;

  procedure AddPerson(People:TJSONArray; const Id:string);
  var Person:TJSONObject; N:Integer;
  begin
    Person:=ExportUser(Id);
    if Person=nil then Exit;
    for N:=0 to People.Count-1 do
      if People.Objects[N].Get('id',0)=Person.Get('id',0) then
      begin Person.Free; Exit; end;
    People.Add(Person);
  end;

  function TaskHtml(const Text,Id:string):string;
  var Checks, Children:TFPList; Check, Child:TJSONObject; N,M:Integer; Name:string;
  begin
    Result:=Paragraphs(Text);
    Checks:=TFPList(CheckMap.Find(Id));
    if Checks=nil then Exit;
    for N:=0 to Checks.Count-1 do
    begin
      Check:=TJSONObject(Checks[N]);
      Children:=TFPList(ItemMap.Find(Check.Get('_id','')));
      if (Children=nil) or (Children.Count=0) then Continue;
      Name:=Trim(Check.Get('title',''));
      if (Name<>'') and ((Checks.Count>1) or (Name<>'Checklist')) then
        Result:=Result+'<h3>'+HtmlEncode(Name)+'</h3>';
      Result:=Result+'<ul data-type="taskList">';
      for M:=0 to Children.Count-1 do
      begin
        Child:=TJSONObject(Children[M]);
        Result:=Result+'<li data-type="taskItem" data-checked="'+
          IfThen(Child.Get('isFinished',False),'true','false')+'"><p>'+
          HtmlEncode(Trim(Child.Get('title','')))+'</p></li>';
      end;
      Result:=Result+'</ul>';
    end;
  end;

  procedure WriteComments(Task,Card:TJSONObject);
  var Rows:TFPList; Source,Comment,User:TJSONObject; N:Integer; At,Text:string;
  begin
    Comments:=TJSONArray.Create; Task.Add('comments',Comments);
    Rows:=TFPList(CommentMap.Find(Card.Get('_id','')));
    if Rows=nil then Exit;
    for N:=0 to Rows.Count-1 do
    begin
      Source:=TJSONObject(Rows[N]);
      Text:=Paragraphs(Source.Get('text',''));
      if Text='' then Continue;
      Inc(CommentId);
      At:=ExportTime(Source.Get('createdAt',''),Stamp);
      Comment:=TJSONObject.Create(['id',CommentId,'comment',Text,'created',At,'updated',At]);
      Comments.Add(Comment);
      User:=ExportUser(Source.Get('userId',''));
      if User<>nil then Comment.Add('author',User);
    end;
  end;

  function ListTitle(Entry:TJSONObject):string;
  var List:TJSONObject;
  begin
    List:=TJSONObject(ListMap.Find(Entry.Get('listId','')));
    if List=nil then Exit('Untitled');
    Result:=TitleOf(List.Get('title',''),'Untitled');
  end;

  function FindBucket(Buckets:TJSONArray; const Title:string):Integer;
  var N:Integer;
  begin
    Result:=0;
    for N:=0 to Buckets.Count-1 do
      if Buckets.Objects[N].Get('title','')=Title then Exit(Buckets.Objects[N].Get('id',0));
  end;

  procedure AddBucket(const Title:string; Limit:Integer);
  begin
    if FindBucket(Buckets,Title)<>0 then Exit;
    Inc(NextBucket);
    Buckets.Add(TJSONObject.Create(['id',NextBucket,'title',Title,'project_view_id',ViewId,
      'position',(Buckets.Count+1)*PositionStep,'limit',Limit,'created',Stamp,'updated',Stamp]));
  end;

  function TaskInProject(Entry:TJSONObject; const Lane:string):Boolean;
  var RawLane:string;
  begin
    if not Several then Exit(True);
    RawLane:=Entry.Get('swimlaneId','');
    Result:=(RawLane=Lane) or ((Lane=Lanes.Objects[0].Get('_id','')) and (LaneMap.Find(RawLane)=nil));
  end;

  procedure AddCardLabels(Task,Card:TJSONObject);
  var Ids:TJSONArray; Source:TJSONObject; N:Integer;
  begin
    Labels:=TJSONArray.Create; Task.Add('labels',Labels);
    if not (Card.Find('labelIds') is TJSONArray) then Exit;
    Ids:=Card.Arrays['labelIds'];
    for N:=0 to Ids.Count-1 do
    begin
      Source:=TJSONObject(LabelMap.Find(Ids.Strings[N]));
      if (Source=nil) or (Trim(Source.Get('name',''))='') then Continue;
      Labels.Add(TJSONObject.Create(['id',LabelMap.FindIndexOf(Ids.Strings[N])+1,'title',Source.Get('name',''),
        'description','','hex_color','','created',Stamp,'updated',Stamp]));
    end;
  end;

  function LinkRows(Task:TJSONObject; const Name:string):TJSONArray;
  var Links:TJSONObject;
  begin
    Links:=Task.Objects['related_tasks'];
    if Links.Find(Name) is TJSONArray then Exit(Links.Arrays[Name]);
    Result:=TJSONArray.Create; Links.Add(Name,Result);
  end;

begin
  Stamp:=FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(Now));
  BoardTitle:=TitleOf(Board.Get('title',''),'WeKan board');
  Projects:=TJSONArray.Create;
  ActiveCards:=TFPList.Create;
  UserMap:=TFPHashObjectList.Create(False); LabelMap:=TFPHashObjectList.Create(False);
  LaneMap:=TFPHashObjectList.Create(False); ListMap:=TFPHashObjectList.Create(False);
  TaskMap:=TFPHashObjectList.Create(False);
  CheckMap:=TFPHashObjectList.Create(True); ItemMap:=TFPHashObjectList.Create(True); CommentMap:=TFPHashObjectList.Create(True);
  try
    Lists:=Board.Arrays['lists']; Lanes:=TJSONArray.Create;
    try
      Cards:=Board.Arrays['swimlanes'];
      for I:=0 to Cards.Count-1 do if Active(Cards.Objects[I]) then Lanes.Add(Cards.Objects[I].Clone);
      IndexRows(LaneMap,Lanes); IndexRows(ListMap,Lists);
      Cards:=Board.Arrays['cards'];
      for I:=0 to Cards.Count-1 do
      begin
        Card:=Cards.Objects[I];
        if Active(Card) and (Card.Get('linkedId','')='') then ActiveCards.Add(Card);
      end;
      Cards:=Board.Arrays['users'];
      IndexRows(UserMap,Cards);
      Cards:=Board.Arrays['labels'];
      IndexRows(LabelMap,Cards);
      Group(CheckMap,Board.Arrays['checklists'],'cardId');
      Group(ItemMap,Board.Arrays['checklistItems'],'checklistId');
      Group(CommentMap,Board.Arrays['comments'],'cardId');
      Several:=Lanes.Count>1; ParentId:=0; NextBucket:=0; CommentId:=0;
      if Several then
      begin ParentId:=1; NewProject(BoardTitle,1,0,PositionStep); end;
      for I:=0 to Max(1,Lanes.Count)-1 do
      begin
        LaneId:=''; Name:=BoardTitle;
        if Several then
        begin LaneId:=Lanes.Objects[I].Get('_id',''); Name:=TitleOf(Lanes.Objects[I].Get('title',''),'Default'); end;
        ProjectId:=Projects.Count+1;
        Project:=NewProject(Name,ProjectId,ParentId,(I+1)*PositionStep);
        Views:=Project.Arrays['views']; Buckets:=Project.Arrays['buckets']; Tasks:=Project.Arrays['tasks'];
        for J:=Low(ViewKinds) to High(ViewKinds) do
        begin
          ViewId:=I*Length(ViewKinds)+J+1;
          Name:=ViewKinds[J];
          View:=TJSONObject.Create(['id',ViewId,'title',UpperCase(Name[1])+Copy(Name,2,MaxInt),
            'project_id',ProjectId,'view_kind',Name,'position',(J+1)*100,
            'bucket_configuration_mode',IfThen(Name='kanban','manual','none'),
            'default_bucket_id',0,'done_bucket_id',0,'created',Stamp,'updated',Stamp]);
          View.Add('filter',TJSONNull.Create); View.Add('bucket_configuration',TJSONNull.Create);
          Views.Add(View);
        end;
        for J:=0 to Lists.Count-1 do
        begin
          Entry:=Lists.Objects[J];
          if not Active(Entry) then Continue;
          Limit:=0;
          if Entry.Find('wipLimit') is TJSONObject then
          begin
            Other:=Entry.Objects['wipLimit'];
            if Other.Get('enabled',False) then Limit:=Max(0,Other.Get('value',0));
          end;
          AddBucket(TitleOf(Entry.Get('title',''),'Untitled'),Limit);
        end;
        for J:=0 to ActiveCards.Count-1 do
        begin
          Card:=TJSONObject(ActiveCards[J]);
          if not TaskInProject(Card,LaneId) then Continue;
          AddBucket(ListTitle(Card),0);
        end;
        DefaultBucket:=0; DoneBucket:=0;
        if Buckets.Count>0 then DefaultBucket:=Buckets.Objects[0].Get('id',0);
        for J:=0 to Buckets.Count-1 do
          if SameText(Buckets.Objects[J].Get('title',''),'Done') then
          begin DoneBucket:=Buckets.Objects[J].Get('id',0); Break; end;
        View.Integers['default_bucket_id']:=DefaultBucket;
        View.Integers['done_bucket_id']:=DoneBucket;
        for J:=0 to ActiveCards.Count-1 do
        begin
          Card:=TJSONObject(ActiveCards[J]);
          if not TaskInProject(Card,LaneId) then Continue;
          Id:=Card.Get('_id','');
          BucketId:=FindBucket(Buckets,ListTitle(Card));
          Done:=(BucketId<>0) and (BucketId=DoneBucket);
          DoneAt:=EmptyDate;
          if Done then DoneAt:=ExportTime(Card.Get('endAt',''),Stamp);
          Position:=(Tasks.Count+1)*PositionStep;
          Task:=TJSONObject.Create(['id',J+1,'title',TitleOf(Card.Get('title',''),'Untitled'),
            'description',TaskHtml(Card.Get('description',''),Id),'done',Done,'done_at',DoneAt,
            'due_date',ExportTime(Card.Get('dueAt',''),EmptyDate),'start_date',ExportTime(Card.Get('startAt',''),EmptyDate),
            'end_date',ExportTime(Card.Get('endAt',''),EmptyDate),'repeat_after',0,'repeat_mode',0,'priority',0,
            'hex_color','','percent_done',0,'identifier','','index',Tasks.Count+1,'project_id',ProjectId,
            'cover_image_attachment_id',0,'is_favorite',False,'bucket_id',BucketId,'position',Position,
            'created',ExportTime(Card.Get('createdAt',''),Stamp),'updated',Stamp]);
          Tasks.Add(Task); TaskMap.Add(Id,Task);
          Task.Add('related_tasks',TJSONObject.Create); Task.Add('reminders',TJSONArray.Create); Task.Add('attachments',TJSONArray.Create);
          Creator:=Card.Get('userId','');
          Entry:=ExportUser(Creator); if Entry<>nil then Task.Add('created_by',Entry);
          People:=TJSONArray.Create; Task.Add('assignees',People);
          AddPerson(People,Creator);
          if Card.Find('assignees') is TJSONArray then
            for K:=0 to Card.Arrays['assignees'].Count-1 do AddPerson(People,Card.Arrays['assignees'].Strings[K]);
          AddCardLabels(Task,Card);
          WriteComments(Task,Card);
          if BucketId<>0 then Project.Arrays['task_buckets'].Add(TJSONObject.Create(['bucket_id',BucketId,
            'task_id',J+1,'project_view_id',ViewId]));
          Project.Arrays['positions'].Add(TJSONObject.Create(['task_id',J+1,'project_view_id',ViewId,'position',Position]));
        end;
      end;
      for J:=0 to ActiveCards.Count-1 do
      begin
        Card:=TJSONObject(ActiveCards[J]);
        Task:=TJSONObject(TaskMap.Find(Card.Get('_id','')));
        Id:=Card.Get('parentId','');
        if (Id='') or (Task=nil) then Continue;
        Other:=TJSONObject(TaskMap.Find(Id));
        if (Other=nil) or (Other=Task) then Continue;
        LinkRows(Task,'parenttask').Add(TJSONObject.Create(['id',Other.Get('id',0)]));
        LinkRows(Other,'subtask').Add(TJSONObject.Create(['id',Task.Get('id',0)]));
      end;
    finally Lanes.Free; end;
    Serialized:=Projects.AsJSON;
    Zip:=TZipper.Create;
    DataStream:=TStringStream.Create(Serialized);
    FiltersStream:=TStringStream.Create('[]');
    VersionStream:=TStringStream.Create('v1.0.0');
    try
      Zip.Entries.AddFileEntry(DataStream,'data.json');
      Zip.Entries.AddFileEntry(FiltersStream,'filters.json');
      Zip.Entries.AddFileEntry(VersionStream,'VERSION');
      Zip.SaveToStream(Output);
    finally Zip.Free; VersionStream.Free; FiltersStream.Free; DataStream.Free; end;
  finally
    CommentMap.Free; ItemMap.Free; CheckMap.Free; TaskMap.Free;
    ListMap.Free; LaneMap.Free; LabelMap.Free; UserMap.Free; ActiveCards.Free; Projects.Free;
  end;
end;
end.
