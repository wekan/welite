unit wlselect;
{$mode objfpc}{$H+}
{$CODEPAGE UTF8}
interface
uses SysUtils,Classes,HTTPDefs,fpjson,jsonparser,base64,wldb,wltenant,wlauth,wlhtml,wlcolors,wlaccess,DateUtils;
// Called only after the endpoint validates session, every selected ID, and the action token.
// Returns true when it sent the action response; false for an ordinary arrow move.
function HandleSelection(const T:TWLTenant; const S:TWLSession;
  Request:TRequest; Response:TResponse):Boolean;
implementation
uses wlstore,wllocale,wli18n,wlcfpol,wlcfscan,wlclseed,wlselscp;
type EInvalidSelection=class(Exception);
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
var i:Integer;
begin
  for i:=0 to Ids.Count-1 do if Ids[i]=Id then Exit;
  Ids.Add(Id);
end;
procedure Collect(Params:TStrings; const Name:string; Ids:TStrings);
var i:Integer;
begin
  for i:=0 to Params.Count-1 do if SameText(Params.Names[i],Name) then AddId(Ids,Params.ValueFromIndex[i]);
end;
procedure AddQuery(Db:TWLDb; const Sql:string; Ids:TStrings);
var R:TWLRows; i:Integer;
begin
  R:=Db.Query('SELECT ''__wl_ids__'' UNION ALL '+Sql);
  if (Length(R)=0) or (R[0][0]<>'__wl_ids__') then raise Exception.Create('Could not collect selection IDs');
  for i:=1 to High(R) do AddId(Ids,R[i][0]);
end;
function RowsJson(Db:TWLDb; const TableName,WhereClause:string;const Action:string;out Binding:string;out Audit:TJSONArray):TJSONArray;
var Columns,R,Owner:TWLRows; Sql,Order,SeedExpr,Spec,Physical,OwnerTest,OwnerGuard,Collection,SourceTable:string; i:Integer; HasId,HasSort:Boolean;Row:TJSONObject;
begin
  Result:=TJSONArray.Create;Audit:=nil;Binding:='';OwnerGuard:='';
  if (Action='export') or ((Action='clone') and (TableName='cards')) then Audit:=TJSONArray.Create;
  try
  Columns:=Db.Query('PRAGMA table_info('+TableName+');');SeedExpr:='';Spec:='';SourceTable:='';
  if ((Action='clone') or (Action='export')) and ((TableName='cards') or (TableName='lists') or (TableName='swimlanes') or
    (TableName='checklists') or (TableName='checklist_items') or (TableName='card_comments') or (TableName='attachments') or
    ((Action='export') and ((TableName='boards') or (TableName='custom_fields') or (TableName='activities')))) then
  begin
    Owner:=Db.Query('SELECT type FROM sqlite_master WHERE name='+q(TableName)+';');
    if (Length(Owner)=1) and (Owner[0][0]='view') then
    begin
      Collection:=TableName;if TableName='checklist_items' then Collection:='checklistItems';
      if TableName='custom_fields' then Collection:='customFields';
      Owner:=Db.Query('SELECT m.table_name,m.spec,m.version,c.settings FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name '+
        'WHERE m.name='+q(TableName)+' AND c.name='+q(Collection)+' AND json_extract(m.spec,''$.table'')='+q(TableName)+' AND json_extract(m.spec,''$.collection'')=c.name;');
      if Length(Owner)<>1 then raise Exception.Create('Missing selection root ownership');
      SourceTable:=Owner[0][0];
      Physical:='"'+StringReplace(Owner[0][0],'"','""',[rfReplaceAll])+'"';Spec:=Owner[0][1];
      OwnerTest:='EXISTS(SELECT 1 FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name WHERE m.name='+q(TableName)+
        ' AND m.table_name='+q(Owner[0][0])+' AND m.spec='+q(Spec)+' AND m.version='+q(Owner[0][2])+
        ' AND c.settings='+q(Owner[0][3])+' AND json_extract(m.spec,''$.collection'')=c.name)';
      OwnerGuard:='SELECT CASE WHEN '+OwnerTest+' THEN 1 ELSE json(''Selection root binding changed'') END; ';
      // Scalar columns and the seed come from the same SQLite read snapshot.
      SeedExpr:='(SELECT CASE WHEN count(*)=1 AND '+OwnerTest+' THEN json(min(_ferretdb_sjson)) ELSE json(''Ambiguous selection source'') END FROM '+Physical+
        ' WHERE json_extract(_ferretdb_sjson,''$._id'')="'+TableName+'".id)';
    end;
  end;
  Sql:='SELECT json_object('; HasId:=False; HasSort:=False;
  for i:=0 to High(Columns) do
  begin
    if i>0 then Sql:=Sql+',';
    Sql:=Sql+q(Columns[i][1])+',';
    if (Columns[i][1]='_wl_source') and (SeedExpr<>'') then Sql:=Sql+'('+SeedExpr+'||'+q('')+')'
    else Sql:=Sql+'"'+Columns[i][1]+'"';
    HasId:=HasId or (Columns[i][1]='id'); HasSort:=HasSort or (Columns[i][1]='sort');
  end;
  Order:='';
  if HasSort then Order:=' ORDER BY sort';
  if HasId then
    if HasSort then Order:=Order+',id' else Order:=' ORDER BY id';
  R:=Db.Query('SELECT ''__wl_rows__'' UNION ALL SELECT row_json FROM ('+Sql+') AS row_json FROM '+TableName+' WHERE '+WhereClause+Order+');');
  if (Length(R)=0) or (R[0][0]<>'__wl_rows__') then raise Exception.Create('Could not read selection rows');
  for i:=1 to High(R) do
  begin
    Row:=TJSONObject(GetJSON(R[i][0]));Result.Add(Row);
    if SeedExpr<>'' then
    begin
      Physical:=Row.Get('_wl_source','');
      if Action='clone' then
      begin
        if TableName='cards' then Audit.Add(TJSONObject.Create(['id',Row.Get('id',''),'table',SourceTable,'_wl_source',Physical]));
        Physical:=RootCloneSeed(Physical,Spec);Row.Delete('_wl_source');Row.Add('_wl_source',Physical);
      end
      else
      begin
        // Audit the complete typed source, never a lossy SQL rendering of it.
        Audit.Add(TJSONObject.Create(['_wl_source',Physical]));
        Row.Delete('_wl_source');Row.Add('_wl_source',TJSONNull.Create);
      end;
    end
    else if Action='export' then Audit.Add(Row.Clone);
  end;
  if Result.Count>0 then Binding:=OwnerGuard;
  except Audit.Free;Audit:=nil;Result.Free;raise;end;
end;
function SelectionBindingsValid(Db:TWLDb;Bindings:TJSONArray):Boolean;
var i:Integer;Rows:TWLRows;
begin
  Result:=False;if Bindings=nil then Exit;
  for i:=0 to Bindings.Count-1 do
  begin
    if Bindings.Items[i].JSONType<>jtString then Exit;
    Rows:=Db.Query(Bindings.Strings[i]);
    if (Length(Rows)<>1) or (Rows[0][0]<>'1') then Exit;
  end;
  Result:=True;
end;
function SelectionGraph(const T:TWLTenant; Params:TStrings):TJSONObject;
var Lanes,Lists,Cards,Checks:TStringList; BoardId,Scope,CardScope:string; Previous,BindingIndex:Integer;TypedScope:TSelectionScope;
  Data,AuditData:TJSONObject;Bindings:TJSONArray;
  function Link(const Name,Column:string):string;
  begin Result:=TypedScope.StringField(Name,Column);end;
  function BoardScope(const Name:string):string;
  begin Result:='boardId='+q(BoardId)+' AND '+Link(Name,'boardId')+' AND '+Link(Name,'id');end;
  function CardOwner(const Name:string):string;
  begin Result:='cardId IN ('+IdSet(Cards)+') AND '+Link(Name,'cardId');end;
  procedure Resolve(const Name:string;Ids:TStringList);
  var Valid:TStringList;i,j:Integer;Found:Boolean;
  begin
    Valid:=TStringList.Create;
    try
      AddQuery(T.Db,'SELECT id FROM '+Name+' WHERE '+BoardScope(Name)+' AND id IN ('+IdSet(Ids)+');',Valid);
      if Valid.Count<>Ids.Count then raise EInvalidSelection.Create('Invalid selection root');
      for i:=0 to Valid.Count-1 do
      begin
        Found:=False;for j:=0 to Ids.Count-1 do if Valid[i]=Ids[j] then Found:=True;
        if not Found then raise EInvalidSelection.Create('Invalid selection identity');
      end;
      Ids.Assign(Valid);
    finally Valid.Free;end;
  end;
  procedure Table(const Name,WhereClause:string);
  var Binding:string;Audit:TJSONArray;
  begin
    if TypedScope.IsRoot(Name) then
      Data.Add(Name,RowsJson(T.Db,Name,'('+WhereClause+') AND '+Link(Name,'id'),Params.Values['action'],Binding,Audit))
    else Data.Add(Name,RowsJson(T.Db,Name,WhereClause,Params.Values['action'],Binding,Audit));
    if AuditData<>nil then AuditData.Add(Name,Audit)
    else if (Params.Values['action']='clone') and (Name='cards') then Result.Add('_clone_sources',Audit)
    else Audit.Free;
    if Binding<>'' then Bindings.Add(Binding);
  end;
begin
  Result:=TJSONObject.Create; Data:=TJSONObject.Create; Result.Add('data',Data);Bindings:=nil;AuditData:=nil;
  if Params.Values['action']='clone' then begin Bindings:=TJSONArray.Create;Result.Add('_clone_bindings',Bindings);end;
  if Params.Values['action']='export' then
  begin
    Bindings:=TJSONArray.Create;Result.Add('_export_bindings',Bindings);
    AuditData:=TJSONObject.Create;Result.Add('_export_audit',AuditData);
  end;
  Lanes:=TStringList.Create; Lists:=TStringList.Create; Cards:=TStringList.Create; Checks:=TStringList.Create;TypedScope:=nil;
  try
    try
    TypedScope:=TSelectionScope.Create(T.Db);BoardId:=Params.Values['boardId'];Scope:='boardId='+q(BoardId);
    Result.Add('welite_selection',1); Result.Add('boardId',BoardId);
    Collect(Params,'sel_swimlane',Lanes); Collect(Params,'sel_list',Lists); Collect(Params,'sel_card',Cards);
    Resolve('swimlanes',Lanes);Resolve('lists',Lists);Resolve('cards',Cards);
    AddQuery(T.Db,'SELECT id FROM lists WHERE '+BoardScope('lists')+' AND swimlaneId IN ('+IdSet(Lanes)+') AND '+Link('lists','swimlaneId')+';',Lists);
    AddQuery(T.Db,'SELECT id FROM cards WHERE '+BoardScope('cards')+' AND ((listId IN ('+IdSet(Lists)+') AND '+Link('cards','listId')+
      ') OR (swimlaneId IN ('+IdSet(Lanes)+') AND '+Link('cards','swimlaneId')+'));',Cards);
    repeat
      Previous:=Cards.Count;
      AddQuery(T.Db,'SELECT id FROM cards WHERE '+BoardScope('cards')+' AND parentId IN ('+IdSet(Cards)+') AND '+Link('cards','parentId')+';',Cards);
    until Cards.Count=Previous;
    CardScope:='cardId IN ('+IdSet(Cards)+')';
    AddQuery(T.Db,'SELECT id FROM checklists WHERE '+CardOwner('checklists')+' AND '+Link('checklists','id')+';',Checks);
    Table('boards','id='+q(BoardId));
    if (TJSONArray(Data.Find('boards')).Count<>1) or (TJSONArray(Data.Find('boards')).Objects[0].Get('id','')<>BoardId) then
      raise EInvalidSelection.Create('Invalid selection board');
    Table('swimlanes',BoardScope('swimlanes')+' AND id IN ('+IdSet(Lanes)+')');
    Table('lists',BoardScope('lists')+' AND id IN ('+IdSet(Lists)+')');
    Table('cards',BoardScope('cards')+' AND id IN ('+IdSet(Cards)+')');
    Table('board_labels','boardId='+q(BoardId)+' AND id IN (SELECT labelId FROM card_labels WHERE '+CardScope+')');
    Table('custom_fields','id IN (SELECT customFieldId FROM custom_field_boards WHERE boardId='+q(BoardId)+
      ' AND customFieldId IN (SELECT customFieldId FROM card_custom_field_values WHERE '+CardScope+'))');
    Table('custom_field_boards',Scope+' AND customFieldId IN (SELECT customFieldId FROM card_custom_field_values WHERE '+CardScope+')');
    Table('custom_field_dropdown_items','customFieldId IN (SELECT customFieldId FROM custom_field_boards WHERE boardId='+q(BoardId)+
      ' AND customFieldId IN (SELECT customFieldId FROM card_custom_field_values WHERE '+CardScope+'))');
    Table('card_members',CardScope); Table('card_assignees',CardScope); Table('card_labels',CardScope);
    Table('card_custom_field_values',CardScope); Table('card_dependencies',CardScope);
    Table('card_comments',BoardScope('card_comments')+' AND '+CardOwner('card_comments'));
    Table('checklists','id IN ('+IdSet(Checks)+')');
    Table('checklist_items','checklistId IN ('+IdSet(Checks)+') AND '+Link('checklist_items','checklistId'));
    for Scope in ['attachments','activities'] do
      Table(Scope,BoardScope(Scope)+' AND (('+CardOwner(Scope)+') OR (listId IN ('+IdSet(Lists)+') AND '+Link(Scope,'listId')+
        ') OR (swimlaneId IN ('+IdSet(Lanes)+') AND '+Link(Scope,'swimlaneId')+'))');
    if Bindings<>nil then for BindingIndex:=0 to TypedScope.Bindings.Count-1 do Bindings.Add(TypedScope.Bindings[BindingIndex]);
    except FreeAndNil(Result);raise;end;
  finally TypedScope.Free;Lanes.Free; Lists.Free; Cards.Free; Checks.Free; end;
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
begin Result:=StoreFilePath(T.FilesDir,'attachme',Id);end;

procedure Error(const T:TWLTenant; const S:TWLSession; Request:TRequest;
  Response:TResponse; Code:Integer; const Message:string);
begin
  Response.Code:=Code; Response.ContentType:='text/html; charset=utf-8';
  Response.Content:=LanguagePage(Response,ViewerLanguage(T.Db,S,Request),
    'Board action','<p>'+HtmlEncode(Message)+'</p>'); Response.SendContent;
end;
procedure Redirect(Response:TResponse; const S:TWLSession; Params:TStrings);
begin
  Response.Code:=302;
  Response.SetCustomHeader('Location',SessionUrl(SafeReturnPath(Params.Values['back']),S));
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
function EditSelection(Db:TWLDb; Params:TStrings; const S:TWLSession;Words:TWLTranslator):string;
var i:Integer; Name,Kind,Id,TableName,Key,FieldId:string; R:TWLRows;
begin
  Result:='<h1>'+HtmlEncode(Words.Text('edit','Edit')+' / '+Words.Text('multi-selection','Multi-Selection'))+'</h1><form method="POST" action="/board/move">'+
    AuthHiddenFields(S,'board:move')+SelectionFields(Params);
  for i:=0 to Params.Count-1 do
  begin
    Name:=LowerCase(Params.Names[i]);
    if Copy(Name,1,4)<>'sel_' then Continue;
    Kind:=Copy(Name,5,Length(Name)); TableName:=ItemTable(Kind); if TableName='' then Continue;
    Id:=Params.ValueFromIndex[i]; Key:=Kind+'_'+Id;
    R:=Db.Query('SELECT title,color FROM '+TableName+' WHERE id='+q(Id)+';');
    Result:=Result+'<fieldset><legend>'+HtmlEncode(Words.Text(Kind,Kind))+'</legend><label>'+HtmlEncode(Words.Text('title','Title'))+' <input name="title_'+HtmlAttr(Key)+
      '" value="'+HtmlAttr(R[0][0])+'" required="required"></label> <label>'+HtmlEncode(Words.Text('allboards.workspace-color','Color'))+' '+
      RenderColorInput('color_'+Key,R[0][1],'hex',False)+'</label> <code>#ffee22</code>';
    if Kind='card' then
    begin
      R:=Db.Query('SELECT description FROM cards WHERE id='+q(Id)+';');
      // Stored IDs can contain Unicode/punctuation; label targets stay HTML4-safe.
      FieldId:='desc_'+HashText(Key);
      Result:=Result+'<br><label for="'+FieldId+'">'+HtmlEncode(Words.Text('description','Description'))+'</label> <textarea id="'+FieldId+'" name="description_'+HtmlAttr(Key)+'">'+HtmlEncode(R[0][0])+'</textarea>';
    end;
    Result:=Result+'</fieldset>';
  end;
  Result:=Result+'<input type="submit" name="action_save" value="'+HtmlAttr(Words.Text('save','Save'))+'"></form>';
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
function NewCloneId(Db:TWLDb; const T:TWLTenant; const TableName:string; Used:TStrings):string;
const Alphabet='23456789ABCDEFGHJKLMNPQRSTWXYZabcdefghijkmnopqrstuvwxyz';
var i:Integer;
begin
  repeat
    SetLength(Result,17);
    for i:=1 to 17 do Result[i]:=Alphabet[Random(Length(Alphabet))+1];
  until (Used.IndexOf(Result)<0) and
    (Length(Db.Query('SELECT id FROM '+TableName+' WHERE id='+q(Result)+';'))=0) and
    ((TableName<>'attachments') or not FileExists(AttachmentPath(T,Result)));
  Used.Add(Result);
end;
function CloneRef(Maps:TJSONObject; const TableName,Id:string):string;
var Map:TJSONObject;
begin
  Map:=TJSONObject(Maps.Find(TableName));
  if Map=nil then Exit(Id);
  Result:=Map.Get(Id,Id);
end;
procedure PutString(Row:TJSONObject; const Name,Value:string);
begin
  Row.Delete(Name); Row.Add(Name,Value);
end;
function RefTable(const Name,TableName:string):string;
begin Result:=CloneReferenceTable(Name,TableName);end;
procedure RemapJson(D:TJSONData; Maps:TJSONObject; const TableName:string);
var O:TJSONObject; A:TJSONArray; i:Integer; Key,Target,Value:string;
begin
  if D is TJSONObject then
  begin
    O:=TJSONObject(D);
    // Replacing values does not change member count; walk backward as keys move to the end.
    for i:=O.Count-1 downto 0 do
    begin
      Key:=O.Names[i]; Target:=RefTable(Key,TableName);
      if (Target<>'') and (O.Items[i].JSONType=jtString) then
      begin
        Value:=CloneRef(Maps,Target,O.Items[i].AsString);
        PutString(O,Key,Value);
      end
      else RemapJson(O.Items[i],Maps,TableName);
    end;
  end
  else if D is TJSONArray then
  begin
    A:=TJSONArray(D);
    for i:=0 to A.Count-1 do RemapJson(A.Items[i],Maps,TableName);
  end;
end;
function SqlJsonValue(D:TJSONData):string;
var V,Hex:string; i:Integer;
begin
  case D.JSONType of
    jtNull:Result:='NULL';
    jtBoolean:if D.AsBoolean then Result:='1' else Result:='0';
    jtNumber:Result:=D.AsJSON;
  else
    V:=D.AsString;
    if Pos(#0,V)=0 then Result:=q(V)
    else
    begin
      Hex:=''; for i:=1 to Length(V) do Hex:=Hex+IntToHex(Ord(V[i]),2);
      Result:='CAST(X'+q(Hex)+' AS TEXT)';
    end;
  end;
end;
function EqualField(Row:TJSONObject; const Name:string):string;
var D:TJSONData;
begin
  D:=Row.Find(Name);
  if (D=nil) or (D.JSONType=jtNull) then Result:='"'+Name+'" IS NULL'
  else Result:='"'+Name+'"='+SqlJsonValue(D);
end;
const CloneTables:array[0..11] of string=('swimlanes','lists','cards','checklists','checklist_items',
  'card_members','card_assignees','card_labels','card_custom_field_values','card_dependencies',
  'card_comments','attachments');
function ClonePermissionGuards(const T:TWLTenant;const S:TWLSession;Graph:TJSONObject;out Guards:string):Boolean;
var Data:TJSONObject;Cards,Bindings:TJSONArray;Policy:TFieldPolicy;Rows:TWLRows;Part,BoardId:string;i:Integer;
begin
  Result:=False;Guards:='';Policy:=nil;Data:=TJSONObject(Graph.Find('data'));BoardId:=Graph.Get('boardId','');
  try
    try
      Policy:=TFieldPolicy.Create(T.Db,S.UserId,BoardId,'');
      Part:=Policy.DefinitionExpression('',False);Rows:=T.Db.Query('SELECT '+Part+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then Exit;
      Guards:='SELECT CASE WHEN '+Part+' THEN 1 ELSE json(''Clone board permission denied'') END; ';FreeAndNil(Policy);
      Bindings:=TJSONArray(Graph.Find('_clone_bindings'));
      if Bindings<>nil then for i:=0 to Bindings.Count-1 do
      begin
        Part:=Bindings.Strings[i];Rows:=T.Db.Query(Part);
        if (Length(Rows)<>1) or (Rows[0][0]<>'1') then Exit;
        Guards:=Guards+Part;
      end;
      for i:=0 to High(CloneTables) do
      begin
        if not PayloadCopyGuards(T.Db,S.UserId,BoardId,Data.Find(CloneTables[i]),Part) then Exit;
        Guards:=Guards+Part;
      end;
      if not PayloadCopyGuards(T.Db,S.UserId,BoardId,Graph.Find('_clone_sources'),Part) then Exit;
      Guards:=Guards+Part;
      Cards:=TJSONArray(Data.Find('cards'));
      for i:=0 to Cards.Count-1 do
      begin
        Policy:=TFieldPolicy.Create(T.Db,S.UserId,BoardId,Cards.Objects[i].Get('id',''));
        Part:=Policy.CloneCardGuard;Rows:=T.Db.Query(Part);
        if (Length(Rows)<>1) or (Rows[0][0]<>'1') then Exit;
        Guards:=Guards+Part;FreeAndNil(Policy);
      end;
      Result:=True;
    except Result:=False;end;
  finally Policy.Free;end;
end;
function CloneSelection(const T:TWLTenant; const S:TWLSession; Graph:TJSONObject; Params:TStrings;const Guards:string):Boolean;
var Data,Maps,Map,Original,Row,Activity,Seed:TJSONObject; A:TJSONArray;
  Used,Copied,Models:TStringList; i,j,k:Integer;
  TableName,Id,Sql,Scope,Expr,Stamp,SourcePath,DestPath,Backend,DestGuards,RelationSql,Physical,Expression:string;Policy:TFieldPolicy;
  Source,Dest:TFileStream;
  function CardSource(const OldId:string):TJSONObject;
  var Sources:TJSONArray;n:Integer;
  begin
    Result:=nil;Sources:=TJSONArray(Graph.Find('_clone_sources'));if Sources=nil then Exit;
    for n:=0 to Sources.Count-1 do
      if Sources.Objects[n].Get('id','')=OldId then
      begin if Result<>nil then raise Exception.Create('Ambiguous clone card source');Result:=Sources.Objects[n];end;
  end;
  function IsRoot(const Kind,OldId:string):Boolean;
  var n:Integer;
  begin
    Result:=False;
    for n:=0 to Params.Count-1 do
      if SameText(Params.Names[n],'sel_'+Kind) and (Params.ValueFromIndex[n]=OldId) then Exit(True);
  end;
  function InsertRow(const Into:string; O:TJSONObject; const SortExpr:string;Before:TJSONObject=nil):string;
  var n:Integer; Cols,Vals,Key,Model,PatchSql,Envelope:string;Patch:TJSONObject;Rows:TWLRows;
    function ValueSql(const Name:string;Value:TJSONData):string;
    begin
      if (Name='sort') and (SortExpr<>'') then Exit(SortExpr);
      if (Into='cards') and (Name='cardNumber') then
        Exit('(SELECT COALESCE(MAX(cardNumber),0)+1 FROM cards WHERE '+EqualField(O,'boardId')+')');
      Result:=SqlJsonValue(Value);
    end;
  begin
    Cols:='';Vals:='';Envelope:='';Patch:=nil;
    try
      if (Before<>nil) and (Before.Find('_wl_source') is TJSONString) then
      begin
        Model:=Models.Values[Into];
        if Model='' then
        begin
          Rows:=T.Db.Query('SELECT spec FROM _wl_models WHERE name='+q(Into)+';');
          if Length(Rows)<>1 then raise Exception.Create('Missing clone model');
          Model:=Rows[0][0];Models.Values[Into]:=Model;
        end;
        Patch:=CloneRootPatch(Before.Get('_wl_source',''),Model,Before,O,SortExpr<>'',Into='cards');
        PatchSql:='json_object(';
        for n:=0 to Patch.Count-1 do
        begin
          if n>0 then PatchSql:=PatchSql+',';
          PatchSql:=PatchSql+q(Patch.Names[n])+','+ValueSql(Patch.Names[n],Patch.Items[n]);
        end;
        PatchSql:=PatchSql+')';
        Envelope:='json_object(''_wl_clone'',1,''source'','+SqlJsonValue(O.Find('_wl_source'))+',''columns'','+PatchSql+')';
      end;
      for n:=0 to O.Count-1 do
      begin
        if n>0 then begin Cols:=Cols+',';Vals:=Vals+',';end;
        Key:=O.Names[n];Cols:=Cols+'"'+StringReplace(Key,'"','""',[rfReplaceAll])+'"';
        if (Key='_wl_source') and (Envelope<>'') then Vals:=Vals+Envelope
        else Vals:=Vals+ValueSql(Key,O.Items[n]);
      end;
      Result:='INSERT INTO '+Into+'('+Cols+') VALUES('+Vals+'); ';
    finally Patch.Free;end;
  end;
begin
  Result:=False; Data:=TJSONObject(Graph.Find('data')); Maps:=TJSONObject.Create;
  Used:=TStringList.Create; Copied:=TStringList.Create;Models:=TStringList.Create;
  try
    try
      // Allocate every map before inserting any row so forward/parent/cover references work.
      for i:=0 to High(CloneTables) do
      begin
        TableName:=CloneTables[i];
        A:=TJSONArray(Data.Find(TableName)); Map:=TJSONObject.Create; Maps.Add(TableName,Map);
        for j:=0 to A.Count-1 do if A.Objects[j].Find('id')<>nil then
          Map.Add(A.Objects[j].Get('id',''),NewCloneId(T.Db,T,TableName,Used));
      end;
      DestGuards:='';A:=TJSONArray(Data.Find('cards'));
      for j:=0 to A.Count-1 do
      begin
        Policy:=TFieldPolicy.Create(T.Db,S.UserId,Graph.Get('boardId',''),CloneRef(Maps,'cards',A.Objects[j].Get('id','')));
        try DestGuards:=DestGuards+Policy.CloneCardGuard;finally Policy.Free;end;
      end;
      RelationSql:='';A:=TJSONArray(Data.Find('cards'));
      for j:=0 to A.Count-1 do
      begin
        Original:=A.Objects[j];Seed:=CardSource(Original.Get('id',''));
        if Seed=nil then
        begin
          if (Original.Find('_wl_source')<>nil) and (Original.Find('_wl_source').JSONType<>jtNull) then
            raise Exception.Create('Missing typed clone card source');
          Continue;
        end;
        Physical:='"'+StringReplace(Seed.Get('table',''),'"','""',[rfReplaceAll])+'"';
        Expression:='wl_clone_rel(json(_ferretdb_sjson),'+q(Seed.Get('_wl_source',''))+','+q(Maps.AsJSON)+')';
        RelationSql:=RelationSql+'UPDATE '+Physical+' SET _ferretdb_sjson=CASE WHEN typeof(_ferretdb_sjson)=''blob'' THEN jsonb('+Expression+') ELSE '+Expression+' END '+
          'WHERE json_extract(_ferretdb_sjson,''$._id'')='+q(CloneRef(Maps,'cards',Original.Get('id','')))+'; '+
          'SELECT CASE WHEN changes()=1 THEN 1 ELSE json(''Missing cloned card'') END; ';
      end;
      A:=TJSONArray(Data.Find('attachments'));
      for j:=0 to A.Count-1 do
      begin
        Original:=A.Objects[j]; Backend:=Original.Get('storageBackend','filesystem');
        if Backend='' then Backend:='filesystem';
        if Backend<>'filesystem' then raise Exception.Create('Attachment backend cannot be cloned');
        SourcePath:=AttachmentPath(T,Original.Get('id',''));
        DestPath:=AttachmentPath(T,CloneRef(Maps,'attachments',Original.Get('id','')));
        Source:=TFileStream.Create(SourcePath,fmOpenRead or fmShareDenyNone);
        try
          if FileExists(DestPath) then raise Exception.Create('Attachment destination exists');
          if not ForceDirectories(ExtractFileDir(DestPath)) then raise Exception.Create('Could not create attachment directory');
          Copied.Add(DestPath);
          Dest:=TFileStream.Create(DestPath,fmCreate);
          try Dest.CopyFrom(Source,0); finally Dest.Free; end;
        finally Source.Free; end;
      end;
      Stamp:=FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(Now));
      Sql:='BEGIN IMMEDIATE; '+Guards;
      for i:=0 to High(CloneTables) do
      begin
        TableName:=CloneTables[i];
        A:=TJSONArray(Data.Find(TableName));
        for j:=0 to A.Count-1 do
        begin
          Original:=A.Objects[j];
          if ((TableName='card_members') or (TableName='card_assignees') or (TableName='card_labels') or
            (TableName='card_custom_field_values') or (TableName='card_dependencies')) and
            (CardSource(Original.Get('cardId',''))<>nil) then Continue;
          Row:=TJSONObject(Original.Clone);
          try
            Id:=Original.Get('id','');
            if Row.Find('id')<>nil then PutString(Row,'id',CloneRef(Maps,TableName,Id));
            RemapJson(Row,Maps,TableName);
            if Row.Find('createdAt')<>nil then PutString(Row,'createdAt',Stamp);
            if Row.Find('modifiedAt')<>nil then PutString(Row,'modifiedAt',Stamp);
            if Row.Find('dateLastActivity')<>nil then PutString(Row,'dateLastActivity',Stamp);
            if ((TableName='cards') and IsRoot('card',Id)) or
              ((TableName='lists') and IsRoot('list',Id)) or
              ((TableName='swimlanes') and IsRoot('swimlane',Id)) then
              PutString(Row,'title',Original.Get('title','')+' Copy');
            Scope:='';
            if (TableName='swimlanes') or (TableName='lists') or (TableName='cards') then Scope:=EqualField(Row,'boardId');
            if TableName='lists' then Scope:=Scope+' AND '+EqualField(Row,'swimlaneId');
            if TableName='cards' then Scope:=Scope+' AND '+EqualField(Row,'listId')+' AND '+EqualField(Row,'swimlaneId');
            if TableName='checklists' then Scope:=EqualField(Row,'cardId');
            if TableName='checklist_items' then Scope:=EqualField(Row,'checklistId');
            Expr:='';
            if (Scope<>'') and (Row.Find('sort')<>nil) then
              Expr:='(SELECT COALESCE(MAX(sort),-1)+1 FROM '+TableName+' WHERE '+Scope+')';
            Sql:=Sql+InsertRow(TableName,Row,Expr,Original);
            if (TableName='cards') or (TableName='lists') or (TableName='swimlanes') then
            begin
              Activity:=TJSONObject.Create;
              try
                Activity.Add('id',NewCloneId(T.Db,T,'activities',Used));
                Activity.Add('activityType','clone'); Activity.Add('userId',S.UserId);
                Activity.Add('boardId',Graph.Get('boardId','')); Activity.Add('createdAt',Stamp);
                if TableName='cards' then Activity.Add('cardId',Row.Get('id',''));
                if TableName='lists' then Activity.Add('listId',Row.Get('id',''));
                if TableName='swimlanes' then Activity.Add('swimlaneId',Row.Get('id',''));
                Map:=TJSONObject.Create;
                try
                  Map.Add('sourceId',Id); Map.Add('sourceType',TableName); Activity.Add('data_json',Map.AsJSON);
                finally Map.Free; end;
                Sql:=Sql+InsertRow('activities',Activity,'');
              finally Activity.Free; end;
            end;
          finally Row.Free; end;
        end;
      end;
      Result:=T.Db.Exec(Sql+Guards+DestGuards+RelationSql+Guards+DestGuards+'COMMIT;');
      if not Result then T.Db.Exec('ROLLBACK;');
    except Result:=False; end;
  finally
    if not Result then for k:=0 to Copied.Count-1 do DeleteFile(Copied[k]);
    Models.Free;Copied.Free; Used.Free; Maps.Free;
  end;
end;

function DeletionDetails(Db:TWLDb;Data:TJSONObject;const BoardId:string;
  Words:TWLTranslator;out Body:string):Boolean;
var CardIds,Scope,Sql:string;Rows:TWLRows;Counts:array[0..7] of Int64;i:Integer;
  function CountQuery(const TableName,WhereClause:string):string;
  begin Result:='(SELECT COUNT(*) FROM '+TableName+' WHERE '+WhereClause+')';end;
  procedure Row(const Kind,Caption:string;N:Int64;Always:Boolean=False);
  begin
    if Always or (N>0) then Body:=Body+'<dt data-delete-kind="'+Kind+'">'+HtmlEncode(Caption)+
      '</dt><dd data-delete-count="'+Kind+'">'+IntToStr(N)+'</dd>';
  end;
  procedure RootRow(const Kind,Key,Fallback:string;Always:Boolean=False);
  begin Row(Kind,Words.Text(Key,Fallback),TJSONArray(Data.Find(Kind)).Count,Always);end;
begin
  Result:=False;Body:='';CardIds:=ArrayIds(Data,'cards');Scope:='cardId IN ('+CardIds+')';
  // Count actual card cascades, not retained label/custom-field definitions from
  // the export graph. Include same-board inbound dependency links removed explicitly.
  Sql:='SELECT '+CountQuery('card_members',Scope)+','+CountQuery('card_assignees',Scope)+','+
    CountQuery('card_labels',Scope)+','+CountQuery('card_custom_field_values',Scope)+','+
    CountQuery('card_dependencies',Scope+' OR (targetCardId IN ('+CardIds+
      ') AND cardId IN (SELECT id FROM cards WHERE boardId='+q(BoardId)+'))')+','+
    CountQuery('card_comments',Scope)+','+CountQuery('checklists',Scope)+','+
    CountQuery('checklist_items','checklistId IN (SELECT id FROM checklists WHERE '+Scope+')')+';';
  Rows:=Db.Query(Sql);
  if (Length(Rows)<>1) or (Length(Rows[0])<>8) then Exit;
  for i:=0 to 7 do
  begin Counts[i]:=StrToInt64Def(Rows[0][i],-1);if Counts[i]<0 then Exit;end;
  Body:='<h2>'+HtmlEncode(Words.Text('details','Details'))+'</h2><dl>';
  RootRow('swimlanes','swimlanes','Swimlanes',True);
  RootRow('lists','lists','Lists',True);RootRow('cards','cards','Cards',True);
  RootRow('attachments','attachments','Attachments');RootRow('activities','activities','Activities');
  Row('card_members',Words.Text('cards','Cards')+' / '+Words.Text('members','Members'),Counts[0]);
  Row('card_assignees',Words.Text('cards','Cards')+' / '+Words.Text('assignees','Assignees'),Counts[1]);
  Row('card_labels',Words.Text('cards','Cards')+' / '+Words.Text('labels','Labels'),Counts[2]);
  Row('card_custom_field_values',Words.Text('cards','Cards')+' / '+Words.Text('custom-fields','Custom Fields'),Counts[3]);
  Row('card_dependencies',Words.Text('card-dependencies','Dependencies'),Counts[4]);
  Row('card_comments',Words.Text('comments','Comments'),Counts[5]);
  Row('checklists',Words.Text('checklists','Checklists'),Counts[6]);
  Row('checklist_items',Words.Text('checklists','Checklists')+' / '+Words.Text('r-item','item'),Counts[7]);
  Body:=Body+'</dl>';Result:=True;
end;

function HandleSelection(const T:TWLTenant; const S:TWLSession; Request:TRequest; Response:TResponse):Boolean;
var Action,Body,CloneGuards:string; Graph,Data:TJSONObject; Count:Integer;Words:TWLTranslator;Language:TWLLanguage;
begin
  Action:=Request.ContentFields.Values['action']; Result:=Action<>'';
  if not Result then Exit;
  if Action='clear' then begin Redirect(Response,S,Request.ContentFields); Exit; end;
  if (Action='export') and not BoardFieldExportAllowed(T.Db,S.UserId,Request.ContentFields.Values['boardId']) then
  begin Error(T,S,Request,Response,403,'Export requires access to every custom-field value on this board');Exit;end;
  try Graph:=SelectionGraph(T,Request.ContentFields);
  except
    on E:EInvalidSelection do begin Error(T,S,Request,Response,400,'Invalid selection');Exit;end;
    else begin Error(T,S,Request,Response,500,'Could not collect selection source');Exit;end;
  end;
  try
    Data:=TJSONObject(Graph.Find('data'));
    Count:=TJSONArray(Data.Find('cards')).Count+TJSONArray(Data.Find('lists')).Count+TJSONArray(Data.Find('swimlanes')).Count;
    if Count=0 then begin Error(T,S,Request,Response,400,'Select at least one item'); Exit; end;
    if Action='edit' then
    begin
      Language:=ViewerLanguage(T.Db,S,Request);Words:=TWLTranslator.Create(Language);
      try
        Response.Content:=LanguagePage(Response,Language,Words.Text('edit','Edit')+' / '+Words.Text('multi-selection','Multi-Selection'),EditSelection(T.Db,Request.ContentFields,S,Words));
        Response.ContentType:='text/html; charset=utf-8'; Response.SendContent;
      finally Words.Free;end;
      Exit;
    end;
    if Action='save' then
    begin
      if not SaveSelection(T.Db,Request.ContentFields) then Error(T,S,Request,Response,400,'Invalid fields or save failed; selection is unchanged')
      else Redirect(Response,S,Request.ContentFields);
      Exit;
    end;
    if Action='delete' then
    begin
      Language:=ViewerLanguage(T.Db,S,Request);Words:=TWLTranslator.Create(Language);
      try
        if not DeletionDetails(T.Db,Data,Request.ContentFields.Values['boardId'],Words,Body) then
        begin Error(T,S,Request,Response,500,'Could not prepare deletion details');Exit;end;
        Body:='<h1 data-delete-confirm="1">'+HtmlEncode(Words.Text('confirm','Confirm')+' / '+Words.Text('r-delete-selected','Delete selected'))+'</h1>'+Body+
          '<form method="POST" action="/board/move">'+AuthHiddenFields(S,'board:move')+SelectionFields(Request.ContentFields)+
          '<input type="submit" name="action_confirm-delete" value="'+HtmlAttr(Words.Text('confirm','Confirm'))+'"></form>'+
          '<p><a href="'+HtmlAttr(SessionUrl(SafeReturnPath(Request.ContentFields.Values['back']),S))+'">'+HtmlEncode(Words.Text('cancel','Cancel'))+'</a></p>';
        Response.Content:=LanguagePage(Response,Language,Words.Text('confirm','Confirm')+' / '+Words.Text('r-delete-selected','Delete selected'),Body);
        Response.ContentType:='text/html; charset=utf-8'; Response.SendContent;
      finally Words.Free;end;
      Exit;
    end;
    if Action='confirm-delete' then
    begin
      if not DeleteSelection(T,Graph,Request.ContentFields.Values['boardId']) then Error(T,S,Request,Response,500,'Delete failed; selection is unchanged')
      else Redirect(Response,S,Request.ContentFields);
      Exit;
    end;
    if Action='clone' then
    begin
      if not ClonePermissionGuards(T,S,Graph,CloneGuards) then
      begin Error(T,S,Request,Response,403,'Clone requires permission to copy custom-field values');Exit;end;
      if not CloneSelection(T,S,Graph,Request.ContentFields,CloneGuards) then Error(T,S,Request,Response,500,'Clone failed; originals are unchanged')
      else Redirect(Response,S,Request.ContentFields);
      Exit;
    end;
    if Action='export' then
    begin
      try ExportSelection(T,Graph);
      except Error(T,S,Request,Response,500,'Could not export attachment content'); Exit; end;
      if not BoardFieldExportAllowed(T.Db,S.UserId,Request.ContentFields.Values['boardId']) or
        not ExportPayloadAllowed(T.Db,S.UserId,Request.ContentFields.Values['boardId'],Graph.Find('_export_audit')) or
        not FieldExportRowsAllowed(T.Db,S.UserId,Request.ContentFields.Values['boardId'],TJSONArray(Data.Find('card_custom_field_values'))) then
      begin Error(T,S,Request,Response,403,'Export requires access to every custom-field value on this board');Exit;end;
      if not SelectionBindingsValid(T.Db,TJSONArray(Graph.Find('_export_bindings'))) then
      begin Error(T,S,Request,Response,500,'Selection source binding changed');Exit;end;
      Graph.Delete('_export_bindings');Graph.Delete('_export_audit');
      Response.ContentType:='application/json';
      Response.SetCustomHeader('Content-Disposition','attachment; filename="select.jsn"');
      Response.Content:=Graph.AsJSON; Response.SendContent; Exit;
    end;
    Error(T,S,Request,Response,400,'Unknown selection action');
  finally Graph.Free; end;
end;
end.
