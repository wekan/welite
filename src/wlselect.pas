unit wlselect;
{$mode objfpc}{$H+}
{$CODEPAGE UTF8}
interface
uses SysUtils,Classes,HTTPDefs,fpjson,jsonparser,base64,wldb,wltenant,wlauth,wlhtml,wlcolors,wlaccess;
// Called only after the endpoint validates session, every selected ID, and the action token.
// Returns true when it sent the action response; false for an ordinary arrow move.
function HandleSelection(const T:TWLTenant; const S:TWLSession;
  Request:TRequest; Response:TResponse):Boolean;
implementation
function q(const V:string):string;
begin Result:=QuotedStr(V); end;
function IdSet(Ids:TStrings):string;
var i:Integer;
begin
  Result:='NULL';
  if Ids.Count=0 then Exit;
  Result:='';
  for i:=0 to Ids.Count-1 do
  begin if i>0 then Result:=Result+','; Result:=Result+q(Ids[i]); end;
end;
procedure AddId(Ids:TStrings; const Id:string);
begin if Ids.IndexOf(Id)<0 then Ids.Add(Id); end;
procedure Collect(Params:TStrings; const Name:string; Ids:TStrings);
var i:Integer;
begin
  for i:=0 to Params.Count-1 do if SameText(Params.Names[i],Name) then AddId(Ids,Params.ValueFromIndex[i]);
end;
procedure AddQuery(Db:TWLDb; const Sql:string; Ids:TStrings);
var R:TWLRows; i:Integer;
begin R:=Db.Query(Sql); for i:=0 to High(R) do AddId(Ids,R[i][0]); end;
function RowsJson(Db:TWLDb; const TableName,WhereClause:string):TJSONArray;
var Columns,R:TWLRows; Sql:string; i:Integer;
begin
  Result:=TJSONArray.Create;
  Columns:=Db.Query('PRAGMA table_info('+TableName+');');
  Sql:='SELECT json_object(';
  for i:=0 to High(Columns) do
  begin
    if i>0 then Sql:=Sql+',';
    Sql:=Sql+q(Columns[i][1])+',"'+Columns[i][1]+'"';
  end;
  R:=Db.Query(Sql+') FROM '+TableName+' WHERE '+WhereClause+';');
  for i:=0 to High(R) do Result.Add(GetJSON(R[i][0]));
end;
function SelectionGraph(const T:TWLTenant; Params:TStrings):TJSONObject;
var Lanes,Lists,Cards,Checks:TStringList; BoardId,Scope,CardScope:string; Previous:Integer;
  Data:TJSONObject;
  procedure Table(const Name,WhereClause:string);
  begin Data.Add(Name,RowsJson(T.Db,Name,WhereClause)); end;
begin
  Result:=TJSONObject.Create; Data:=TJSONObject.Create; Result.Add('data',Data);
  Lanes:=TStringList.Create; Lists:=TStringList.Create; Cards:=TStringList.Create; Checks:=TStringList.Create;
  try
    BoardId:=Params.Values['boardId']; Scope:='boardId='+q(BoardId);
    Result.Add('welite_selection',1); Result.Add('boardId',BoardId);
    Collect(Params,'sel_swimlane',Lanes); Collect(Params,'sel_list',Lists); Collect(Params,'sel_card',Cards);
    AddQuery(T.Db,'SELECT id FROM lists WHERE '+Scope+' AND swimlaneId IN ('+IdSet(Lanes)+');',Lists);
    AddQuery(T.Db,'SELECT id FROM cards WHERE '+Scope+' AND (listId IN ('+IdSet(Lists)+
      ') OR swimlaneId IN ('+IdSet(Lanes)+'));',Cards);
    repeat
      Previous:=Cards.Count;
      AddQuery(T.Db,'SELECT id FROM cards WHERE '+Scope+' AND parentId IN ('+IdSet(Cards)+');',Cards);
    until Cards.Count=Previous;
    CardScope:='cardId IN ('+IdSet(Cards)+')';
    AddQuery(T.Db,'SELECT id FROM checklists WHERE '+CardScope+';',Checks);
    Table('boards','id='+q(BoardId));
    Table('swimlanes',Scope+' AND id IN ('+IdSet(Lanes)+')');
    Table('lists',Scope+' AND id IN ('+IdSet(Lists)+')');
    Table('cards',Scope+' AND id IN ('+IdSet(Cards)+')');
    Table('board_labels','boardId='+q(BoardId)+' AND id IN (SELECT labelId FROM card_labels WHERE '+CardScope+')');
    Table('custom_fields','id IN (SELECT customFieldId FROM custom_field_boards WHERE boardId='+q(BoardId)+
      ' AND customFieldId IN (SELECT customFieldId FROM card_custom_field_values WHERE '+CardScope+'))');
    Table('custom_field_boards',Scope+' AND customFieldId IN (SELECT customFieldId FROM card_custom_field_values WHERE '+CardScope+')');
    Table('custom_field_dropdown_items','customFieldId IN (SELECT customFieldId FROM custom_field_boards WHERE boardId='+q(BoardId)+
      ' AND customFieldId IN (SELECT customFieldId FROM card_custom_field_values WHERE '+CardScope+'))');
    Table('card_members',CardScope); Table('card_assignees',CardScope); Table('card_labels',CardScope);
    Table('card_custom_field_values',CardScope); Table('card_dependencies',CardScope);
    Table('card_comments',Scope+' AND '+CardScope);
    Table('checklists','id IN ('+IdSet(Checks)+')');
    Table('checklist_items','checklistId IN ('+IdSet(Checks)+')');
    Scope:=Scope+' AND ('+CardScope+' OR listId IN ('+IdSet(Lists)+') OR swimlaneId IN ('+IdSet(Lanes)+'))';
    Table('attachments',Scope); Table('activities',Scope);
  finally Lanes.Free; Lists.Free; Cards.Free; Checks.Free; end;
end;
function ArrayIds(Data:TJSONObject; const TableName:string):string;
var A:TJSONArray; Ids:TStringList; i:Integer;
begin
  Ids:=TStringList.Create;
  try
    A:=TJSONArray(Data.Find(TableName));
    for i:=0 to A.Count-1 do Ids.Add(A.Objects[i].Get('id',''));
    Result:=IdSet(Ids);
  finally Ids.Free; end;
end;
function AttachmentPath(const T:TWLTenant; const Id:string):string;
var i:Integer;
begin
  if Id='' then raise Exception.Create('Invalid attachment ID');
  for i:=1 to Length(Id) do if not (Id[i] in ['a'..'z','A'..'Z','0'..'9','-','_']) then
    raise Exception.Create('Invalid attachment ID');
  Result:=T.FilesDir+'attachments'+PathDelim+Id;
end;
procedure Error(Response:TResponse; Code:Integer; const Message:string);
begin
  Response.Code:=Code; Response.ContentType:='text/html; charset=utf-8';
  Response.Content:=Page32('Board action','<p>'+HtmlEncode(Message)+'</p>'); Response.SendContent;
end;
procedure Redirect(Response:TResponse; const S:TWLSession; Params:TStrings);
begin
  Response.Code:=302;
  Response.SetCustomHeader('Location',WithSessionId(SafeReturnPath(Params.Values['back']),S.SessionId));
  Response.SendContent;
end;
function SelectionFields(Params:TStrings):string;
var i:Integer; Name:string;
begin
  Result:='';
  for i:=0 to Params.Count-1 do
  begin
    Name:=LowerCase(Params.Names[i]);
    if Name='boardid' then Name:='boardId';
    if (Name='boardId') or (Name='back') or (Name='sel_card') or (Name='sel_list') or (Name='sel_swimlane') then
      Result:=Result+'<input type="hidden" name="'+Name+'" value="'+HtmlAttr(Params.ValueFromIndex[i])+'">';
  end;
end;
function ItemTable(const Kind:string):string;
begin
  case Kind of 'card':Result:='cards'; 'list':Result:='lists'; 'swimlane':Result:='swimlanes'; else Result:=''; end;
end;
function EditSelection(Db:TWLDb; Params:TStrings; const S:TWLSession):string;
var i:Integer; Name,Kind,Id,TableName,Key:string; R:TWLRows;
begin
  Result:='<h1>Edit selected items</h1><form method="POST" action="/board/move">'+
    AuthHiddenFields(S,'board:move')+SelectionFields(Params);
  for i:=0 to Params.Count-1 do
  begin
    Name:=LowerCase(Params.Names[i]);
    if Copy(Name,1,4)<>'sel_' then Continue;
    Kind:=Copy(Name,5,Length(Name)); TableName:=ItemTable(Kind); if TableName='' then Continue;
    Id:=Params.ValueFromIndex[i]; Key:=Kind+'_'+Id;
    R:=Db.Query('SELECT title,color FROM '+TableName+' WHERE id='+q(Id)+';');
    Result:=Result+'<fieldset><legend>'+HtmlEncode(Kind)+'</legend>Title <input name="title_'+HtmlAttr(Key)+
      '" value="'+HtmlAttr(R[0][0])+'" required="required"> Color '+RenderColorInput('color_'+Key,R[0][1],'hex');
    if Kind='card' then
    begin
      R:=Db.Query('SELECT description FROM cards WHERE id='+q(Id)+';');
      Result:=Result+'<br>Description <textarea name="description_'+HtmlAttr(Key)+'">'+HtmlEncode(R[0][0])+'</textarea>';
    end;
    Result:=Result+'</fieldset>';
  end;
  Result:=Result+'<input type="submit" name="action" value="save"></form>';
end;
function SaveSelection(Db:TWLDb; Params:TStrings):Boolean;
var i:Integer; Name,Kind,Id,TableName,Key,Title,Color,Sql:string;
begin
  Result:=False; Sql:='BEGIN IMMEDIATE; ';
  for i:=0 to Params.Count-1 do
  begin
    Name:=LowerCase(Params.Names[i]); if Copy(Name,1,4)<>'sel_' then Continue;
    Kind:=Copy(Name,5,Length(Name)); TableName:=ItemTable(Kind); if TableName='' then Continue;
    Id:=Params.ValueFromIndex[i]; Key:=Kind+'_'+Id;
    Title:=Trim(Params.Values['title_'+Key]); Color:=Trim(Params.Values['color_'+Key]);
    if (Title='') or ((Color<>'') and (ResolveColor(Color)='')) then Exit;
    Sql:=Sql+'UPDATE '+TableName+' SET title='+q(Title)+',color='+q(Color)+
      ',modifiedAt=strftime(''%Y-%m-%dT%H:%M:%fZ'',''now'')';
    if Kind='card' then Sql:=Sql+',description='+q(Params.Values['description_'+Key]);
    Sql:=Sql+' WHERE id='+q(Id)+' AND boardId='+q(Params.Values['boardId'])+'; ';
  end;
  Result:=Db.Exec(Sql+'COMMIT;'); if not Result then Db.Exec('ROLLBACK;');
end;
procedure ExportSelection(const T:TWLTenant; Graph:TJSONObject);
var Data:TJSONObject; A,Files:TJSONArray; i:Integer; Row,F:TJSONObject; Bytes:TStringStream; Source:TFileStream;
begin
  Data:=TJSONObject(Graph.Find('data')); A:=TJSONArray(Data.Find('attachments'));
  Files:=TJSONArray.Create; Graph.Add('files',Files);
  for i:=0 to A.Count-1 do
  begin
    Row:=A.Objects[i]; F:=TJSONObject.Create; Files.Add(F);
    F.Add('id',Row.Get('id','')); F.Add('storageBackend',Row.Get('storageBackend','filesystem'));
    if Row.Get('storageBackend','filesystem')='filesystem' then
    begin
      Bytes:=TStringStream.Create('');
      try
        Source:=TFileStream.Create(AttachmentPath(T,Row.Get('id','')),fmOpenRead or fmShareDenyNone);
        try Bytes.CopyFrom(Source,0); finally Source.Free; end;
        F.Add('base64Data',EncodeStringBase64(Bytes.DataString));
      finally Bytes.Free; end;
    end;
  end;
end;
function DeleteSelection(const T:TWLTenant; Graph:TJSONObject; const BoardId:string):Boolean;
var Data:TJSONObject; CardIds,ListIds,LaneIds,AttachmentIds,ActivityIds,Sql:string;
  A:TJSONArray; i:Integer;
begin
  Data:=TJSONObject(Graph.Find('data')); CardIds:=ArrayIds(Data,'cards'); ListIds:=ArrayIds(Data,'lists');
  LaneIds:=ArrayIds(Data,'swimlanes'); AttachmentIds:=ArrayIds(Data,'attachments'); ActivityIds:=ArrayIds(Data,'activities');
  Sql:='BEGIN IMMEDIATE; DELETE FROM card_dependencies WHERE targetCardId IN ('+CardIds+
    ') AND cardId IN (SELECT id FROM cards WHERE boardId='+q(BoardId)+'); '+
    'DELETE FROM cards WHERE boardId='+q(BoardId)+' AND id IN ('+CardIds+'); '+
    'DELETE FROM lists WHERE boardId='+q(BoardId)+' AND id IN ('+ListIds+'); '+
    'DELETE FROM swimlanes WHERE boardId='+q(BoardId)+' AND id IN ('+LaneIds+'); '+
    'DELETE FROM attachments WHERE boardId='+q(BoardId)+' AND id IN ('+AttachmentIds+'); '+
    'DELETE FROM activities WHERE boardId='+q(BoardId)+' AND id IN ('+ActivityIds+'); COMMIT;';
  Result:=T.Db.Exec(Sql);
  if not Result then begin T.Db.Exec('ROLLBACK;'); Exit; end;
  // Metadata commits first: failed unlinks leave only unreachable files, never live rows
  // whose bytes were removed by a transaction that later rolled back.
  A:=TJSONArray(Data.Find('attachments'));
  for i:=0 to A.Count-1 do if A.Objects[i].Get('storageBackend','filesystem')='filesystem' then
    try DeleteFile(AttachmentPath(T,A.Objects[i].Get('id',''))); except end;
end;
function HandleSelection(const T:TWLTenant; const S:TWLSession; Request:TRequest; Response:TResponse):Boolean;
var Action,Body:string; Graph,Data:TJSONObject; Count:Integer;
begin
  Action:=Request.ContentFields.Values['action']; Result:=Action<>'';
  if not Result then Exit;
  if Action='clear' then begin Redirect(Response,S,Request.ContentFields); Exit; end;
  Graph:=SelectionGraph(T,Request.ContentFields);
  try
    Data:=TJSONObject(Graph.Find('data'));
    Count:=TJSONArray(Data.Find('cards')).Count+TJSONArray(Data.Find('lists')).Count+TJSONArray(Data.Find('swimlanes')).Count;
    if Count=0 then begin Error(Response,400,'Select at least one item'); Exit; end;
    if Action='edit' then
    begin
      Response.Content:=Page32('Edit selection',EditSelection(T.Db,Request.ContentFields,S));
      Response.ContentType:='text/html; charset=utf-8'; Response.SendContent; Exit;
    end;
    if Action='save' then
    begin
      if not SaveSelection(T.Db,Request.ContentFields) then Error(Response,400,'Invalid fields or save failed; selection is unchanged')
      else Redirect(Response,S,Request.ContentFields);
      Exit;
    end;
    if Action='delete' then
    begin
      Body:='<h1>Delete selected items?</h1><p>This includes '+IntToStr(Count)+' items and their related data.</p>'+
        '<form method="POST" action="/board/move">'+AuthHiddenFields(S,'board:move')+SelectionFields(Request.ContentFields)+
        '<input type="submit" name="action" value="confirm-delete"></form>'+
        '<p><a href="'+HtmlAttr(WithSessionId(SafeReturnPath(Request.ContentFields.Values['back']),S.SessionId))+'">Cancel</a></p>';
      Response.Content:=Page32('Confirm deletion',Body); Response.ContentType:='text/html; charset=utf-8'; Response.SendContent; Exit;
    end;
    if Action='confirm-delete' then
    begin
      if not DeleteSelection(T,Graph,Request.ContentFields.Values['boardId']) then Error(Response,500,'Delete failed; selection is unchanged')
      else Redirect(Response,S,Request.ContentFields);
      Exit;
    end;
    if Action='export' then
    begin
      try ExportSelection(T,Graph);
      except Error(Response,500,'Could not export attachment content'); Exit; end;
      Response.ContentType:='application/json';
      Response.SetCustomHeader('Content-Disposition','attachment; filename="select.jsn"');
      Response.Content:=Graph.AsJSON; Response.SendContent; Exit;
    end;
    Error(Response,400,'Unknown selection action');
  finally Graph.Free; end;
end;
end.
