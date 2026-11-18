unit wlboard;
{$mode objfpc}{$H+}
{$CODEPAGE UTF8}
interface
uses SysUtils, Classes, HTTPDefs, fpjson, jsonparser, wldb, wlauth, wltenant,
  wlhtml, wlcolors, wlmove, wlaccess, wldesign, wlenhanc, wlbrowse;
function BoardListHtml(Db:TWLDb; const S:TWLSession; const LanguageTag:string=''):string;
function BoardHtml(Db:TWLDb; const BoardId:string; const S:TWLSession; const Dir:string; X:Integer=1; Y:Integer=1; AllItems:Boolean=False; const OriginWidget:string=''; const OriginPath:string='';const LanguageTag:string='';const ExpandedList:string='';const SubtaskCard:string=''):string;
function BoardMoveDirection(Db:TWLDb;const S:TWLSession;Request:TRequest;out Rtl:Boolean):Boolean;
procedure BoardEndpoint(aRequest:TRequest; aResponse:TResponse);
procedure BoardCardEndpoint(aRequest:TRequest; aResponse:TResponse);
procedure BoardAttachmentEndpoint(aRequest:TRequest;aResponse:TResponse);
procedure BoardAttachmentUploadEndpoint(aRequest:TRequest;aResponse:TResponse);
implementation
uses wli18n,wllocale,wlcfpol,wlselscp,wlstore,wlferr,wlapi,wlcfjson,wlcfspec;
function CardUrl(const BoardId,CardId:string;const S:TWLSession):string;
begin
  Result:=SessionUrl('/board/card?id='+HTTPEncode(BoardId)+'&card='+HTTPEncode(CardId),S);
end;

function AttachmentUploadAction(const Board,Card:string):string;
begin
  Result:='board:attachment-upload:'+IntToStr(Length(Board))+':'+Board+Card;
end;

function ActiveCardAttachments(Db:TWLDb;Selector:TSelectionScope;const Board,Card:string):string;
begin
  Result:='boardId='+QuotedStr(Board)+' AND cardId='+QuotedStr(Card)+
    ' AND '+Selector.StringField('attachments','id')+' AND '+Selector.StringField('attachments','boardId')+
    ' AND '+Selector.StringField('attachments','cardId')+' AND '+LiveAttachmentSQL(Db);
end;

function BoardListHtml(Db:TWLDb; const S:TWLSession; const LanguageTag:string):string;
var R:TWLRows; i,Count:Integer;Words:TWLTranslator;Tag:string;
begin
  Tag:=LanguageTag;if Tag='' then Tag:=S.LanguageTag;
  Words:=TWLTranslator.Create(ResolveLanguage(Tag,SessionLanguage(Db,S),''));
  try
    R:=Db.Query('SELECT id,title,color FROM boards WHERE archived=0 ORDER BY sort,id;');
    Result:='<h2>'+HtmlEncode(Words.Text('boards','Boards'))+'</h2><ul>'; Count:=0;
    for i:=0 to High(R) do if BoardCanRead(Db,S.UserId,R[i][0]) then
    begin
      Inc(Count);
      Result:=Result+'<li><a href="'+HtmlAttr(SessionUrl('/board?id='+HTTPEncode(R[i][0]),S))+
        '">'+HtmlEncode(R[i][1])+'</a></li>';
    end;
    if Count=0 then Result:=Result+'<li>'+HtmlEncode(Words.Text('no-items-message','No items.'))+'</li>';
    Result:=Result+'</ul>';
  finally Words.Free;end;
end;
function MiniCardFieldValue(Definition:TJSONObject;Value:TJSONData;Words:TWLTranslator):string;
var Options,Selection,Parsed,Item:TJSONData;Kind,Display:string;I:Integer;
  function OptionName(const Id:string):string;
  var J:Integer;Option:TJSONData;
  begin
    Result:=Id;
    if not (Options is TJSONArray) then Exit;
    for J:=0 to TJSONArray(Options).Count-1 do
    begin
      Option:=TJSONArray(Options).Items[J];
      if (Option is TJSONObject) and (TJSONObject(Option).Get('_id','')=Id) then
        Exit(TJSONObject(Option).Get('name',Id));
    end;
  end;
begin
  Result:='';
  Kind:=Definition.Get('type','');
  Options:=Definition.FindPath('settings.dropdownItems');
  if Kind='dropdownMultiSelect' then
  begin
    Parsed:=nil;Selection:=Value;
    try
      if Value.JSONType=jtString then
      begin
        try Parsed:=GetJSON(Value.AsString);except Exit;end;
        Selection:=Parsed;
      end;
      if not (Selection is TJSONArray) then Exit;
      for I:=0 to TJSONArray(Selection).Count-1 do
      begin
        Item:=TJSONArray(Selection).Items[I];
        if Item.JSONType<>jtString then Continue;
        Display:=OptionName(Item.AsString);
        if Trim(Display)='' then Continue;
        if Result<>'' then Result:=Result+', ';
        Result:=Result+Display;
      end;
    finally Parsed.Free;end;
  end
  else if Value.JSONType in [jtString,jtNumber,jtBoolean] then
  begin
    Result:=Value.AsString;
    if (Kind='dropdown') and (Value.JSONType=jtString) then Result:=OptionName(Result);
    if Kind='checkbox' then
    begin
      if (Result='true') or (Result='1') then Result:=Words.Text('yes','Yes')
      else if (Result='false') or (Result='0') then Result:=Words.Text('no','No')
      else Result:='';
    end;
  end;
end;

function MiniCardFields(Db:TWLDb;const UserId,BoardId,CardId:string;Words:TWLTranslator):string;
var Values:TJSONArray;Field,Definition:TJSONObject;Value,ShowLabel:TJSONData;
  Policy:TFieldPolicy;Id,Caption,Display:string;I:Integer;Snapshot:Boolean;
begin
  Result:='';
  if (UserId='') or not Db.BeginRead then Exit;
  Values:=nil;Policy:=nil;
  try
    try
      Values:=ReadCustomFields(Db,CardId);
      Policy:=TFieldPolicy.Create(Db,UserId,BoardId,CardId);
      for I:=0 to Values.Count-1 do
      begin
        Field:=TJSONObject(Values.Items[I]);
        Id:=Field.Get('_id','');Value:=Field.Find('value');
        if (Value=nil) or (Value.JSONType=jtNull) or not Policy.Allowed(Id,False) then Continue;
        Definition:=ReadDefinition(Db,Id);
        if Definition=nil then Continue;
        try
          Display:=MiniCardFieldValue(Definition,Value,Words);
          if Trim(Display)='' then Continue;
          Caption:='';
          ShowLabel:=Definition.Find('showLabelOnMiniCard');
          if (ShowLabel<>nil) and (ShowLabel.JSONType=jtBoolean) and ShowLabel.AsBoolean then
            Caption:=HtmlEncode(Definition.Get('name',''))+': ';
          Result:=Result+'<p class="minicard-custom-field">'+Caption+HtmlEncode(Display)+'</p>';
        finally Definition.Free;end;
      end;
    except Result:='';end;
  finally
    Values.Free;Policy.Free;Snapshot:=Db.EndRead;
    if not Snapshot then Result:='';
  end;
end;

function BoardHtml(Db:TWLDb; const BoardId:string; const S:TWLSession; const Dir:string; X:Integer; Y:Integer; AllItems:Boolean;const OriginWidget,OriginPath,LanguageTag,ExpandedList,SubtaskCard:string):string;
var B,Lanes,Lists,Cards,MapLists,Subtasks,Permissions:TWLRows; i,j,k,c,m,Child,Width,MapX,MapY:Integer;
  Writable,ShowSpentTime,ShowCustomFields:Boolean; Back,BoardPath,Align,CellDir,Map,Url,Color,CellText,ViewDir:string; Occupied:TWLRows;Words:TWLTranslator;Tag:string;Language:TWLLanguage;Policy:TFieldPolicy;
  function Selection(const Kind,Id:string):string;
  begin
    if Writable then Result:=SelectCheckbox(Kind,Id)+' ' else Result:='';
  end;
begin
  Result:='';
  if not BoardCanRead(Db,S.UserId,BoardId) then Exit;
  B:=Db.Query('SELECT title,color,CASE WHEN json_type(settings_json,''$.allowsSpentTimeOnMinicard'') IN (''true'',''false'') '+
    'THEN json_extract(settings_json,''$.allowsSpentTimeOnMinicard'') ELSE COALESCE(json_extract(settings_json,''$.allowsSpentTime''),1) END, '+
    'json_type(settings_json,''$.allowsCustomFieldsOnMinicard'')=''true'' '+
    'FROM boards WHERE id='+QuotedStr(BoardId)+';');
  if Length(B)<>1 then Exit;
  ShowSpentTime:=B[0][2]='1';
  ShowCustomFields:=B[0][3]='1';
  Writable:=BoardCanWrite(Db,S.UserId,BoardId);
  Tag:=LanguageTag;if Tag='' then Tag:=S.LanguageTag;
  Language:=ResolveLanguage(Tag,SessionLanguage(Db,S),'');
  Words:=TWLTranslator.Create(Language);
  try
  if SameText(Dir,'rtl') then begin Align:='right'; CellDir:='rtl'; end
  else begin Align:='left'; CellDir:='ltr'; end;
  Back:='/board?id='+HTTPEncode(BoardId);
  Result:='<h1>'+HtmlEncode(B[0][0])+'</h1><p><a href="'+
    HtmlAttr(SessionUrl('/',S))+'">'+HtmlEncode(Words.Text('all-boards','All boards'))+'</a></p>';
  if S.UserId<>'' then
  begin
    Url:='/board/export?id='+HTTPEncode(BoardId);
    Result:=Result+'<p><a href="'+HtmlAttr(SessionUrl(Url,S))+'">'+
      HtmlEncode(Words.Text('export-board','Export board')+' (JSON)')+'</a> &middot; <a href="'+
      HtmlAttr(SessionUrl(Url+'&attachments=false',S))+'">'+
      HtmlEncode(Words.Text('export-board','Export board')+' (JSON, '+
        Words.Text('export-board-without-attachments','without attachments')+')')+'</a></p>';
    Policy:=nil;
    try
      try
        Policy:=TFieldPolicy.Create(Db,S.UserId,BoardId,'');
        Permissions:=Db.Query('SELECT '+Policy.ScopeAdminExpression(True)+';');
      except Permissions:=nil;end;
    finally Policy.Free;end;
    if (Length(Permissions)=1) and (Permissions[0][0]='1') then
      Result:=Result+'<p><a href="'+HtmlAttr(SessionUrl('/board/webhooks?id='+HTTPEncode(BoardId),S))+
        '">'+HtmlEncode(Words.Text('outgoing-webhooks','Outgoing Webhooks'))+'</a></p>';
  end;
  Lanes:=Db.Query('SELECT id,title,color FROM swimlanes WHERE boardId='+QuotedStr(BoardId)+
    ' AND archived=0 ORDER BY sort,id;');
  if X<1 then X:=1;
  if Y<1 then Y:=1;
  if Length(Lanes)=0 then begin X:=1;Y:=1;end
  else if Y>Length(Lanes) then Y:=Length(Lanes);
  Width:=0;
  Map:='<table dir="ltr" data-board-map="'+HtmlAttr(BoardId)+'" align="right" border="1" cellpadding="3" cellspacing="0" summary="'+
    HtmlAttr(Words.Text('board','Board')+' / '+Words.Text('view','View'))+'">';
  for MapY:=0 to High(Lanes) do
  begin
    MapLists:=Db.Query('SELECT id,title FROM lists WHERE boardId='+QuotedStr(BoardId)+
      ' AND (swimlaneId='+QuotedStr(Lanes[MapY][0])+' OR swimlaneId='''') AND archived=0 AND deletedAt IS NULL ORDER BY sort,id;');
    if MapY=Y-1 then
    begin
      Width:=Length(MapLists);
      if Width=0 then X:=1 else if X>Width then X:=Width;
    end;
    Map:=Map+'<tr>';
    for j:=0 to High(MapLists) do
    begin
      if Align='right' then MapX:=High(MapLists)-j else MapX:=j;
      Occupied:=Db.Query('SELECT id FROM cards WHERE boardId='+QuotedStr(BoardId)+
        ' AND swimlaneId='+QuotedStr(Lanes[MapY][0])+' AND listId='+QuotedStr(MapLists[MapX][0])+
        ' AND archived=0 AND deletedAt IS NULL LIMIT 1;');
      if Length(Occupied)>0 then begin Color:='#cccccc'; CellText:='*'; end
      else begin Color:='#ffffff'; CellText:='-'; end;
      if (MapX=X-1) and (MapY=Y-1) then Color:='#ffff66';
      Url:='/board?id='+HTTPEncode(BoardId)+'&x='+IntToStr(MapX+1)+'&y='+IntToStr(MapY+1);
      Map:=Map+'<td bgcolor="'+Color+'"><a href="'+HtmlAttr(SessionUrl(Url,S))+
        '" title="'+HtmlAttr(Lanes[MapY][1]+' / '+MapLists[MapX][1])+'">'+CellText+'</a></td>';
    end;
    if Length(MapLists)=0 then
    begin
      Color:='#ffffff';if MapY=Y-1 then Color:='#ffff66';
      Url:='/board?id='+HTTPEncode(BoardId)+'&x=1&y='+IntToStr(MapY+1);
      Map:=Map+'<td bgcolor="'+Color+'"><a href="'+HtmlAttr(SessionUrl(Url,S))+
        '" title="'+HtmlAttr(Lanes[MapY][1]+' / '+Words.Text('no-items-message','No items.'))+'">-</a></td>';
    end;
    Map:=Map+'</tr>';
  end;
  Map:=Map+'</table>';
  Result:=Result+Map+'<p>X '+IntToStr(X)+' Y '+IntToStr(Y)+
    ' ('+HtmlEncode(Words.Text('color-yellow','yellow')+': '+Words.Text('current','current')+
    '; *: '+Words.Text('cards','Cards')+'; -: '+Words.Text('no-items-message','No items.'))+')</p><p>';
  for m:=0 to 3 do
  begin
    MapX:=X; MapY:=Y;
    case m of
      0: begin
        if Align='right' then Inc(MapX) else Dec(MapX);
        CellText:='<';ViewDir:='left';
      end;
      1: begin
        if Align='right' then Dec(MapX) else Inc(MapX);
        CellText:='>';ViewDir:='right';
      end;
      2: begin Dec(MapY); CellText:='^';ViewDir:='up'; end;
      3: begin Inc(MapY); CellText:='v';ViewDir:='down'; end;
    end;
    if (MapY>=1) and (MapY<=Length(Lanes)) and
      ((m>=2) or ((MapX>=1) and (MapX<=Width))) then
      Result:=Result+'<a dir="ltr" data-view-dir="'+ViewDir+'" href="'+HtmlAttr(SessionUrl('/board?id='+HTTPEncode(BoardId)+
        '&x='+IntToStr(MapX)+'&y='+IntToStr(MapY),S))+'">'+HtmlEncode(Words.Text('view','View')+' '+CellText)+'</a> ';
  end;
  Result:=Result+'<a href="'+HtmlAttr(SessionUrl('/board?id='+HTTPEncode(BoardId)+'&view=all',S))+
    '">'+HtmlEncode(Words.Text('view-all','View all'))+'</a></p><br clear="all">';
  Back:='/board?id='+HTTPEncode(BoardId);
  if AllItems then Back:=Back+'&view=all'
  else Back:=Back+'&x='+IntToStr(X)+'&y='+IntToStr(Y);
  BoardPath:=Back;
  if OriginWidget<>'' then Back:=SafeReturnPath(OriginPath);
  if Writable then Result:=Result+MoveFormBegin(S,'/board/move')+
    '<input type="hidden" name="boardWidget" value="'+HtmlAttr(OriginWidget)+'">'+
    '<input type="hidden" name="boardId" value="'+HtmlAttr(BoardId)+'">'+
    '<input type="hidden" name="back" value="'+HtmlAttr(Back)+'">';

  if Length(Lanes)=0 then Result:=Result+'<p>'+HtmlEncode(Words.Text('no-items-message','No items.'))+'</p>';
  for i:=0 to High(Lanes) do
  begin
    if not AllItems and (i<>Y-1) then Continue;
    Result:=Result+'<h2'+BgColorAttr(Lanes[i][2])+'>'+Selection('swimlane',Lanes[i][0])+
      HtmlEncode(Lanes[i][1])+'</h2>';
    Lists:=Db.Query('SELECT id,title,color,collapsed FROM lists WHERE boardId='+QuotedStr(BoardId)+
      ' AND (swimlaneId='+QuotedStr(Lanes[i][0])+' OR swimlaneId='''') AND archived=0 AND deletedAt IS NULL ORDER BY sort,id;');
    if Length(Lists)=0 then begin Result:=Result+'<p>'+HtmlEncode(Words.Text('no-items-message','No items.'))+'</p>'; Continue; end;
    Result:=Result+'<table dir="ltr" width="100%" border="1" cellpadding="5" cellspacing="0"><tr>';
    for j:=0 to High(Lists) do
    begin
      if Align='right' then c:=High(Lists)-j else c:=j;
      if not AllItems and (c<>X-1) then Continue;
      Result:=Result+'<th dir="'+CellDir+'" align="'+Align+'"'+BgColorAttr(Lists[c][2])+'>'+
        Selection('list',Lists[c][0])+HtmlEncode(Lists[c][1]);
      if Lists[c][3]='1' then
      begin
        Url:=BoardPath;
        if ExpandedList=Lists[c][0] then CellText:=Words.Text('collapse','Collapse')
        else
        begin
          CellText:=Words.Text('uncollapse','Expand');
          Url:=Url+'&expand='+HTTPEncode(Lists[c][0]);
        end;
        Result:=Result+' <a data-list-toggle="'+HtmlAttr(Lists[c][0])+'" href="'+
          HtmlAttr(SessionUrl(Url,S))+'">'+HtmlEncode(CellText)+'</a>';
      end;
      Result:=Result+'</th>';
    end;
    Result:=Result+'</tr><tr>';
    for j:=0 to High(Lists) do
    begin
      if Align='right' then c:=High(Lists)-j else c:=j;
      if not AllItems and (c<>X-1) then Continue;
      Result:=Result+'<td dir="'+CellDir+'" valign="top" align="'+Align+'" data-list="'+HtmlAttr(Lists[c][0])+'" data-lane="'+HtmlAttr(Lanes[i][0])+'">';
      if (Lists[c][3]='1') and (ExpandedList<>Lists[c][0]) then
      begin
        Result:=Result+'</td>';
        Continue;
      end;
      Cards:=Db.Query('SELECT c.id,c.title,c.color,EXISTS(SELECT 1 FROM cards child WHERE child.parentId=c.id'+
        ' AND child.boardId=c.boardId AND child.archived=0 AND child.deletedAt IS NULL),CASE WHEN c.spentTime<>0 THEN c.spentTime END,c.isOvertime FROM cards c WHERE c.boardId='+
        QuotedStr(BoardId)+' AND c.swimlaneId='+QuotedStr(Lanes[i][0])+' AND c.listId='+QuotedStr(Lists[c][0])+
        ' AND c.archived=0 AND c.deletedAt IS NULL ORDER BY c.sort,c.id;');
      for k:=0 to High(Cards) do
      begin
        Result:=Result+'<p'+DraggableAttrs('card',Cards[k][0],'/board/move')+
          BgColorAttr(Cards[k][2])+'>'+Selection('card',Cards[k][0])+
          '<a href="'+HtmlAttr(CardUrl(BoardId,Cards[k][0],S))+'">'+HtmlEncode(Cards[k][1])+'</a></p>';
        if ShowCustomFields then Result:=Result+MiniCardFields(Db,S.UserId,BoardId,Cards[k][0],Words);
        if ShowSpentTime and (Cards[k][4]<>'') then
        begin
          if Cards[k][5]='1' then CellText:=Words.Text('overtime-hours','Overtime (hours)')
          else CellText:=Words.Text('spent-time-hours','Spent time (hours)');
          Result:=Result+'<p data-card-time="'+HtmlAttr(Cards[k][0])+'">'+
            HtmlEncode(CellText+': '+Cards[k][4])+'</p>';
        end;
        if Cards[k][3]<>'1' then Continue;
        Url:=BoardPath;
        if ExpandedList<>'' then Url:=Url+'&expand='+HTTPEncode(ExpandedList);
        if SubtaskCard=Cards[k][0] then
        begin
          Result:=Result+'<a href="'+HtmlAttr(SessionUrl(Url,S))+'">'+
            HtmlEncode(Words.Text('collapse','Collapse')+' '+Words.Text('subtasks','Subtasks'))+'</a><ul>';
          Subtasks:=Db.Query('SELECT title FROM cards WHERE boardId='+QuotedStr(BoardId)+
            ' AND parentId='+QuotedStr(Cards[k][0])+' AND archived=0 AND deletedAt IS NULL ORDER BY sort,id;');
          for Child:=0 to High(Subtasks) do Result:=Result+'<li>'+HtmlEncode(Subtasks[Child][0])+'</li>';
          Result:=Result+'</ul>';
        end else
          Result:=Result+'<a href="'+HtmlAttr(SessionUrl(Url+'&subtasks='+HTTPEncode(Cards[k][0]),S))+
            '">'+HtmlEncode(Words.Text('subtasks','Subtasks'))+'</a>';
      end;
      if Length(Cards)=0 then Result:=Result+'<p>'+HtmlEncode(Words.Text('no-items-message','No items.'))+'</p>';
      Result:=Result+'</td>';
    end;
    Result:=Result+'</tr></table>';
  end;
  if Writable then
  begin
    Result:=Result+MoveKeypad(S,0,0,0,True,True,Language.Tag)+MoveFormEnd;
    Lists:=Db.Query('SELECT id,title,deleteBatchId FROM lists WHERE boardId='+QuotedStr(BoardId)+
      ' AND deletedAt IS NOT NULL ORDER BY deletedAt DESC,id;');
    for i:=0 to High(Lists) do
      Result:=Result+'<form method="POST" action="/board/restore-list">'+
        AuthHiddenFields(S,RestoreListAction(BoardId,Lists[i][0],Lists[i][2]))+
        '<input type="hidden" name="sessionId" value="'+HtmlAttr(S.SessionId)+'">'+
        '<input type="hidden" name="boardId" value="'+HtmlAttr(BoardId)+'">'+
        '<input type="hidden" name="listId" value="'+HtmlAttr(Lists[i][0])+'">'+
        '<input type="hidden" name="deleteBatchId" value="'+HtmlAttr(Lists[i][2])+'">'+
        '<input type="submit" value="'+HtmlAttr(Words.Text('restore','Restore')+' '+Lists[i][1])+'"></form>';
  end;
  finally Words.Free;end;
end;
// A published widget may override viewer direction. Re-read its owned page and
// binding rather than trusting a posted direction flag or return URL.
function BoardMoveDirection(Db:TWLDb;const S:TWLSession;Request:TRequest;out Rtl:Boolean):Boolean;
var Id:string;Rows:TWLRows;P:TPage;Widgets:TWidgetArray;i:Integer;D:TJSONData;
  Language:TWLLanguage;
begin
  Language:=ViewerLanguage(Db,S,Request);Rtl:=Language.Rtl;Result:=True;
  Id:=Request.ContentFields.Values['boardWidget'];if Id='' then Exit;
  Result:=False;
  Rows:=Db.Query('SELECT pageId FROM page_widgets WHERE id='+QuotedStr(Id)+';');
  if (Length(Rows)<>1) or not LoadPageById(Db,Rows[0][0],P) then Exit;
  if not P.Enabled or not RoleAllows(Db,P.MinRole,S) then Exit;
  Widgets:=LoadWidgets(Db,P.Id);
  for i:=0 to High(Widgets) do if Widgets[i].Id=Id then
  begin
    if not SameText(Widgets[i].Typ,'dataview') or
      not (SameText(Widgets[i].Binding,'board') or SameText(Widgets[i].Binding,'swimlanes')) then Exit;
    D:=nil;
    try
      try
        D:=GetJSON(Widgets[i].OptionsJson);
        if not (D is TJSONObject) or
          (TJSONObject(D).Get('boardId','')<>Request.ContentFields.Values['boardId']) then Exit;
      except Exit;end;
    finally D.Free;end;
    Rtl:=ResolveDir(Request,P.Dir,SessionLanguage(Db,S))='rtl';Result:=True;Exit;
  end;
end;
procedure BoardEndpoint(aRequest:TRequest; aResponse:TResponse);
var T:TWLTenant; S:TWLSession; Body,Dir,Title:string;Language:TWLLanguage;Words:TWLTranslator;
begin
  if not (ResolveTenant(aRequest,T) and TenantOpen(T)) then
  begin
    aResponse.Code:=404; aResponse.ContentType:='text/html; charset=utf-8';
    aResponse.Content:=LanguagePage(aResponse,ViewerLanguage(nil,Default(TWLSession),aRequest),
      'Not found','<p>Unknown domain</p>','','html4'); aResponse.SendContent; Exit;
  end;
  if not ValidateSession(T.Db,aRequest,SessionIdFromRequest(aRequest),S) then S:=Default(TWLSession);
  S.LanguageTag:=RequestLanguageTag(aRequest);
  Language:=ViewerLanguage(T.Db,S,aRequest);
  if Language.Rtl then Dir:='rtl' else Dir:='ltr';
  Words:=TWLTranslator.Create(Language);
  try
  Title:=Words.Text('board','Board');
  Body:=BoardHtml(T.Db,aRequest.QueryFields.Values['id'],S,Dir,
    StrToIntDef(aRequest.QueryFields.Values['x'],1),StrToIntDef(aRequest.QueryFields.Values['y'],1),
    aRequest.QueryFields.Values['view']='all','','',Language.Tag,aRequest.QueryFields.Values['expand'],aRequest.QueryFields.Values['subtasks']);
  if Body='' then begin
    aResponse.Code:=404;
    aResponse.Content:=LanguagePage(aResponse,Language,Title,'<p>'+HtmlEncode(Words.Text('board-not-found','Board not found'))+'</p>','','html4');
  end
  else begin aResponse.Code:=200; aResponse.Content:=LanguagePage(aResponse,Language,Title,Body+EnhancementScripts(wbUnknown),Dir,'html4'); end;
  aResponse.ContentType:='text/html; charset=utf-8'; aResponse.SendContent;
  finally Words.Free;end;
end;
procedure BoardCardEndpoint(aRequest:TRequest; aResponse:TResponse);
var T:TWLTenant;S:TWLSession;Language:TWLLanguage;Words:TWLTranslator;Selector:TSelectionScope;
  Board,Card,BoardKey,CardKey,ChecklistKey,Scope,Title,Body,Dir,TimeLabel:string;
  Rows,Subtasks,Checklists,Items,Files:TWLRows;Subtask,Checklist,Item,Attached:TWLRow;Open,Snapshot:Boolean;
  function Assignments(const TableName,Caption:string):string;
  var Names:TWLRows;Name:TWLRow;
  begin
    Result:='';
    Names:=T.Db.Query('SELECT DISTINCT users.username FROM '+TableName+' JOIN users ON users.id='+TableName+
      '.userId WHERE '+TableName+'.cardId='+CardKey+' AND '+Selector.StringField(TableName,'userId')+
      ' AND '+Selector.StringField('users','id')+' ORDER BY users.username;');
    if Length(Names)=0 then Exit;
    Result:='<h2>'+HtmlEncode(Caption)+'</h2><ul>';
    for Name in Names do Result:=Result+'<li>'+HtmlEncode(Name[0])+'</li>';
    Result:=Result+'</ul>';
  end;
begin
  T:=Default(TWLTenant);S:=Default(TWLSession);
  Open:=ResolveTenant(aRequest,T) and TenantOpen(T);
  if Open and not ValidateSession(T.Db,aRequest,SessionIdFromRequest(aRequest),S) then S:=Default(TWLSession);
  S.LanguageTag:=RequestLanguageTag(aRequest);
  Language:=ViewerLanguage(T.Db,S,aRequest);
  if Language.Rtl then Dir:='rtl' else Dir:='ltr';
  Words:=TWLTranslator.Create(Language);
  try
    Title:=Words.Text('card','Card');Body:='';aResponse.Code:=404;
    Board:=aRequest.QueryFields.Values['id'];Card:=aRequest.QueryFields.Values['card'];
    if Open and (Board<>'') and (Card<>'') and (Pos(#0,Board+Card)=0) and T.Db.BeginRead then
    begin
      try
        if BoardCanRead(T.Db,S.UserId,Board) then
        begin
          BoardKey:=QuotedStr(Board);CardKey:=QuotedStr(Card);
          Selector:=TSelectionScope.Create(T.Db);
          try
            Rows:=T.Db.Query('SELECT title,description,CASE WHEN spentTime<>0 AND EXISTS(SELECT 1 FROM boards '+
              'WHERE id='+BoardKey+' AND COALESCE(json_extract(settings_json,''$.allowsSpentTime''),1)=1) '+
              'THEN spentTime END,isOvertime FROM cards WHERE id='+CardKey+' AND boardId='+BoardKey+
              ' AND archived=0 AND deletedAt IS NULL AND '+Selector.StringField('cards','id')+
              ' AND '+Selector.StringField('cards','boardId')+';');
            if Length(Rows)=1 then
            begin
              Title:=Rows[0][0];
              Body:='<p><a href="'+HtmlAttr(SessionUrl('/board?id='+HTTPEncode(Board),S))+'">'+
                HtmlEncode(Words.Text('board','Board'))+'</a></p><h1>'+HtmlEncode(Title)+'</h1>';
              if Rows[0][1]<>'' then Body:=Body+'<p>'+HtmlEncode(Rows[0][1])+'</p>';
              if Rows[0][2]<>'' then
              begin
                if Rows[0][3]='1' then TimeLabel:=Words.Text('overtime-hours','Overtime (hours)')
                else TimeLabel:=Words.Text('spent-time-hours','Spent time (hours)');
                Body:=Body+'<h2>'+HtmlEncode(TimeLabel)+'</h2><p>'+HtmlEncode(Rows[0][2])+'</p>';
              end;
              Body:=Body+Assignments('card_members',Words.Text('members','Members'))+
                Assignments('card_assignees',Words.Text('assignees','Assignees'));
              Subtasks:=T.Db.Query('SELECT id,title FROM cards WHERE boardId='+BoardKey+
                ' AND parentId='+CardKey+' AND id<>'+CardKey+' AND archived=0 AND deletedAt IS NULL AND '+
                Selector.StringField('cards','id')+' AND '+Selector.StringField('cards','boardId')+
                ' AND '+Selector.StringField('cards','parentId')+' ORDER BY sort,id;');
              if Length(Subtasks)>0 then
              begin
                Body:=Body+'<h2>'+HtmlEncode(Words.Text('subtasks','Subtasks'))+'</h2><ul>';
                for Subtask in Subtasks do
                  Body:=Body+'<li><a href="'+HtmlAttr(CardUrl(Board,Subtask[0],S))+'">'+
                    HtmlEncode(Subtask[1])+'</a></li>';
                Body:=Body+'</ul>';
              end;
              Files:=nil;
              if S.UserId<>'' then Files:=T.Db.Query('SELECT id,name FROM attachments WHERE '+ActiveCardAttachments(T.Db,Selector,Board,Card)+
                ' ORDER BY createdAt,id;');
              if Length(Files)>0 then
              begin
                Body:=Body+'<h2>'+HtmlEncode(Words.Text('attachments','Attachments'))+'</h2><ul>';
                for Attached in Files do
                  Body:=Body+'<li><a href="'+HtmlAttr(SessionUrl('/board/attachment?id='+HTTPEncode(Board)+
                    '&card='+HTTPEncode(Card)+'&file='+HTTPEncode(Attached[0]),S))+'">'+HtmlEncode(Attached[1])+'</a></li>';
                Body:=Body+'</ul>';
              end;
              if (S.UserId<>'') and BoardCanWrite(T.Db,S.UserId,Board) then
                Body:=Body+'<form method="POST" enctype="multipart/form-data" action="/board/attachment/upload?id='+
                  HtmlAttr(HTTPEncode(Board)+'&card='+HTTPEncode(Card))+'">'+
                  AuthHiddenFields(S,AttachmentUploadAction(Board,Card))+
                  '<label for="attachment-file">'+HtmlEncode(Words.Text('attachment','Attachment'))+'</label> '+
                  '<input id="attachment-file" type="file" name="file"> <input type="submit" value="'+
                  HtmlAttr(Words.Text('upload','Upload'))+'"></form>';
              Scope:='cardId='+CardKey+' AND '+Selector.StringField('checklists','cardId')+
                ' AND (COALESCE(boardId,'''')='''' OR (boardId='+BoardKey+' AND '+
                Selector.StringField('checklists','boardId')+'))';
              Checklists:=T.Db.Query('SELECT id,title FROM checklists WHERE '+Scope+' AND '+
                Selector.StringField('checklists','id')+' ORDER BY sort,id;');
              if Length(Checklists)>0 then
                Body:=Body+'<h2>'+HtmlEncode(Words.Text('checklists','Checklists'))+'</h2>';
              for Checklist in Checklists do
              begin
                ChecklistKey:=QuotedStr(Checklist[0]);
                Items:=T.Db.Query('SELECT title,isFinished FROM checklist_items WHERE checklistId='+ChecklistKey+
                  ' AND '+Selector.StringField('checklist_items','checklistId')+
                  ' AND cardId='+CardKey+' AND '+Selector.StringField('checklist_items','cardId')+
                  ' AND (COALESCE(boardId,'''')='''' OR (boardId='+BoardKey+' AND '+
                  Selector.StringField('checklist_items','boardId')+')) ORDER BY sort,id;');
                Body:=Body+'<h3>'+HtmlEncode(Checklist[1])+'</h3>';
                if Length(Items)>0 then Body:=Body+'<ul>';
                for Item in Items do
                begin
                  Body:=Body+'<li>';
                  if Item[1]='1' then Body:=Body+'<s>'+HtmlEncode(Item[0])+'</s>'
                  else Body:=Body+HtmlEncode(Item[0]);
                  Body:=Body+'</li>';
                end;
                if Length(Items)>0 then Body:=Body+'</ul>';
              end;
            end;
          finally Selector.Free;end;
        end;
      finally Snapshot:=T.Db.EndRead;end;
      if not Snapshot then Body:='';
    end;
    if Body='' then
    begin
      Title:=Words.Text('card','Card');
      Body:='<p>'+HtmlEncode(Words.Text('field-link-not-found','Card not found.'))+'</p>';
    end
    else aResponse.Code:=200;
    aResponse.ContentType:='text/html; charset=utf-8';
    aResponse.Content:=LanguagePage(aResponse,Language,Title,Body,Dir,'html4');
    aResponse.SendContent;
  finally Words.Free;end;
end;

procedure BoardAttachmentUploadEndpoint(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;S:TWLSession;Board,Card,FileType,Id:string;
  Rows:TWLRows;Upload:TUploadedFile;Stream:TStream;Selector:TSelectionScope;
  procedure Reject(Status:Integer;const Key,Message:string);
  var Language:TWLLanguage;Words:TWLTranslator;
  begin
    Language:=ViewerLanguage(T.Db,S,aRequest);
    Words:=TWLTranslator.Create(Language);
    try
      aResponse.Code:=Status;
      aResponse.ContentType:='text/html; charset=utf-8';
      aResponse.Content:=LanguagePage(aResponse,Language,Words.Text(Key,Message),
        '<p>'+HtmlEncode(Words.Text(Key,Message))+'</p>');
      aResponse.SendContent;
    finally Words.Free;end;
  end;
begin
  T:=Default(TWLTenant);S:=Default(TWLSession);
  if not (ResolveTenant(aRequest,T) and TenantOpen(T)) then
  begin Reject(404,'page-not-found','Page not found.');Exit;end;
  if not ValidateSession(T.Db,aRequest,SessionIdFromRequest(aRequest),S) then
  begin Reject(403,'upload-failed','Upload failed');Exit;end;
  S.LanguageTag:=RequestLanguageTag(aRequest);
  Board:=aRequest.QueryFields.Values['id'];Card:=aRequest.QueryFields.Values['card'];
  if (Board='') or (Card='') or (Pos(#0,Board+Card)>0) or not BoardCanWrite(T.Db,S.UserId,Board) then
  begin Reject(403,'upload-failed','Upload failed');Exit;end;
  Selector:=TSelectionScope.Create(T.Db);
  try
    Rows:=T.Db.Query('SELECT swimlaneId,listId FROM cards WHERE id='+QuotedStr(Card)+
      ' AND boardId='+QuotedStr(Board)+' AND archived=0 AND deletedAt IS NULL AND '+
      Selector.StringField('cards','id')+' AND '+Selector.StringField('cards','boardId')+
      ' AND '+Selector.StringField('cards','swimlaneId')+' AND '+Selector.StringField('cards','listId')+';');
  finally Selector.Free;end;
  if Length(Rows)<>1 then
  begin Reject(404,'field-link-not-found','Card not found.');Exit;end;
  if aRequest.Files.Count<>1 then
  begin Reject(400,'upload-failed','Upload failed');Exit;end;
  Upload:=aRequest.Files[0];
  if (Upload.FieldName<>'file') or (Upload.FileName='') or
    (Pos(#0,Upload.FileName+Upload.ContentType)>0) or (Pos(#13,Upload.ContentType)>0) or
    (Pos(#10,Upload.ContentType)>0) then
  begin Reject(400,'upload-failed','Upload failed');Exit;end;
  if not VerifyActionToken(aRequest,S,AttachmentUploadAction(Board,Card)) then
  begin Reject(403,'upload-failed','Upload failed');Exit;end;
  try
    Stream:=Upload.Stream;
  except
    Reject(400,'upload-failed','Upload failed');Exit;
  end;
  FileType:=Upload.ContentType;
  if FileType='' then FileType:='application/octet-stream';
  if not StoreAttachment(T,S.UserId,Board,Rows[0][0],Rows[0][1],Card,Upload.FileName,FileType,Stream,Id,True) then
  begin Reject(500,'upload-failed','Upload failed');Exit;end;
  aResponse.Code:=303;
  aResponse.SetCustomHeader('Location',CardUrl(Board,Card,S));
  aResponse.SendContent;
end;

procedure BoardAttachmentEndpoint(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;S:TWLSession;Board,Card,Id,Scope:string;
  Selector:TSelectionScope;Rows:TWLRows;Readable,Snapshot,Open:Boolean;Language:TWLLanguage;Words:TWLTranslator;
begin
  Board:=aRequest.QueryFields.Values['id'];Card:=aRequest.QueryFields.Values['card'];Id:=aRequest.QueryFields.Values['file'];
  T:=Default(TWLTenant);S:=Default(TWLSession);
  Open:=ResolveTenant(aRequest,T) and TenantOpen(T);
  if Open and not ValidateSession(T.Db,aRequest,SessionIdFromRequest(aRequest),S) then S:=Default(TWLSession);
  Readable:=False;
  if Open and (S.UserId<>'') and (Board<>'') and (Card<>'') and (Id<>'') and (Pos(#0,Board+Card+Id)=0) and T.Db.BeginRead then
  begin
    try
      if BoardCanRead(T.Db,S.UserId,Board) then
      begin
        Selector:=TSelectionScope.Create(T.Db);
        try
          Scope:='id='+QuotedStr(Card)+' AND boardId='+QuotedStr(Board)+' AND archived=0 AND deletedAt IS NULL'+
            ' AND '+Selector.StringField('cards','id')+' AND '+Selector.StringField('cards','boardId');
          if Length(T.Db.Query('SELECT 1 FROM cards WHERE '+Scope+';'))=1 then
          begin
            Rows:=T.Db.Query('SELECT id,name FROM attachments WHERE id='+QuotedStr(Id)+
              ' AND '+ActiveCardAttachments(T.Db,Selector,Board,Card)+';');
            Readable:=Length(Rows)=1;
          end;
        finally Selector.Free;end;
      end;
    finally Snapshot:=T.Db.EndRead;end;
    if Snapshot and Readable and SendStoredDownload(aResponse,StoreFilePath(T.FilesDir,'attachme',Id),Rows[0][1]) then Exit;
  end;
  aResponse.Code:=404;
  Language:=ViewerLanguage(T.Db,S,aRequest);
  Words:=TWLTranslator.Create(Language);
  try
    aResponse.ContentType:='text/html; charset=utf-8';
    aResponse.Content:=LanguagePage(aResponse,Language,Words.Text('attachments','Attachments'),
      '<p>'+HtmlEncode(Words.Text('attachment-repair-broken','Not found'))+'</p>','','html4');
    aResponse.SendContent;
  finally Words.Free;end;
end;

function BoardsView(Db:TWLDb; const W:TWidget; const S:TWLSession;const Dir,PageUrl:string):string;
begin Result:=BoardListHtml(Db,S); end;
function BoardView(Db:TWLDb; const W:TWidget; const S:TWLSession;const Dir,PageUrl:string):string;
var D:TJSONData; Id:string;Words:TWLTranslator;
begin
  Id:=''; D:=nil;
  try
    try D:=GetJSON(W.OptionsJson); if D is TJSONObject then Id:=TJSONObject(D).Get('boardId',''); except end;
  finally D.Free; end;
  Result:=BoardHtml(Db,Id,S,Dir,1,1,True,W.Id,PageUrl);
  if Result='' then
  begin
    Words:=TWLTranslator.Create(ResolveLanguage(S.LanguageTag,SessionLanguage(Db,S),''));
    try Result:='<p>'+HtmlEncode(Words.Text('board-not-found','Board not found'))+'</p>';
    finally Words.Free;end;
  end;
end;
initialization
  RegisterDataView('boards',@BoardsView);
  RegisterDataView('swimlanes',@BoardView);
  RegisterDataView('board',@BoardView);
end.
