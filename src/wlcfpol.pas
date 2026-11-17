unit wlcfpol;
{$mode objfpc}{$H+}
interface
uses SysUtils,fpjson,wldb;
type
  TFieldPolicy=class
  private
    FDb:TWLDb;
    FUser,FBoard,FCard,FBinding:string;
    FShared:Boolean;
    FTables:array[0..3] of string;
    function Source(const Model,Collection:string):string;
  public
    constructor Create(Db:TWLDb;const UserId,BoardId,CardId:string);
    function Expression(const FieldId:string;WriteAccess:Boolean):string;
    function Allowed(const FieldId:string;WriteAccess:Boolean):Boolean;
    function Guard(const FieldId:string):string;
    procedure Redact(Fields:TJSONArray);
  end;
implementation
function FalseFlag(const Doc,Name:string):string;
begin
  Result:='COALESCE(json_type('+Doc+',''$.'+Name+''') IN (''null'',''false''),1)';
end;
function StringId(const Alias,Identity:string):string;
begin
  Result:='json_type('+Alias+'.d,''$._id'')=''text'' AND json_extract('+Alias+'.d,''$._id'')='+QuotedStr(Identity)+
    ' AND json_extract('+Alias+'.s,''$."$s".p._id.t'')=''string''';
end;
function TFieldPolicy.Source(const Model,Collection:string):string;
var Rows:TWLRows;Name:string;
begin
  Rows:=FDb.Query('SELECT m.table_name FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name '+
    'WHERE m.name='+QuotedStr(Model)+' AND c.name='+QuotedStr(Collection)+';');
  if Length(Rows)<>1 then raise Exception.Create('Missing field policy source');
  Name:=Rows[0][0];
  FBinding:=FBinding+' AND (SELECT count(*) FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name WHERE m.name='+
    QuotedStr(Model)+' AND c.name='+QuotedStr(Collection)+')=1';
  FBinding:=FBinding+' AND (SELECT count(*) FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name WHERE m.name='+
    QuotedStr(Model)+' AND c.name='+QuotedStr(Collection)+' AND m.table_name='+QuotedStr(Name)+')=1';
  Result:='"'+StringReplace(Name,'"','""',[rfReplaceAll])+'"';
end;
constructor TFieldPolicy.Create(Db:TWLDb;const UserId,BoardId,CardId:string);
var Rows:TWLRows;
begin
  inherited Create;FDb:=Db;FUser:=UserId;FBoard:=BoardId;FCard:=CardId;
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''custom_fields'';');
  if (Length(Rows)<>1) or ((Rows[0][0]<>'table') and (Rows[0][0]<>'view')) then
    raise Exception.Create('Missing field policy definitions');
  FShared:=Rows[0][0]='view';FBinding:='1';
  if FShared then
  begin
    FTables[0]:=Source('users','users');FTables[1]:=Source('boards','boards');
    FTables[2]:=Source('custom_fields','customFields');FTables[3]:=Source('cards','cards');
  end;
end;
function TFieldPolicy.Expression(const FieldId:string;WriteAccess:Boolean):string;
const Roles:array[0..5] of string=('isReadOnly','isCommentOnly','isReadAssignedOnly','isCommentAssignedOnly','isNormalAssignedOnly','isWorker');
  Aliases:array[0..3] of string=('u','b','f','c');
var Admin,Member,Access,Flags,Prefix,Ids,Value,UserSchema:string;i:Integer;
begin
  if not FShared then
  begin
    Admin:='EXISTS(SELECT 1 FROM board_members m WHERE m.boardId=b.id AND m.userId=u.id AND m.isActive=1 AND m.isAdmin=1)';
    Member:='EXISTS(SELECT 1 FROM board_members m WHERE m.boardId=b.id AND m.userId=u.id AND m.isActive=1';
    for i:=0 to High(Roles) do if WriteAccess or (i in [2,3,4]) then Member:=Member+' AND COALESCE(m.'+Roles[i]+',0)=0';
    Member:=Member+')';Access:='(u.isAdmin=1 OR '+Member;
    if not WriteAccess then Access:=Access+' OR b.permission=''public''';Access:=Access+')';
    Flags:='typeof(f.adminOnly)=''integer'' AND f.adminOnly IN (0,1) AND (f.adminOnly=0 OR '+Admin+')';
    if WriteAccess then Flags:=Flags+' AND typeof(f.readOnly)=''integer'' AND f.readOnly IN (0,1) AND (f.readOnly=0 OR '+Admin+')';
    Exit('(SELECT count(*)=1 FROM custom_fields f,boards b,users u,cards c WHERE f.id='+QuotedStr(FieldId)+
      ' AND b.id='+QuotedStr(FBoard)+' AND b.archived=0 AND u.id='+QuotedStr(FUser)+' AND u.loginDisabled=0'+
      ' AND c.id='+QuotedStr(FCard)+' AND c.boardId=b.id AND '+Access+' AND '+Flags+
      ' AND EXISTS(SELECT 1 FROM custom_field_boards x WHERE x.customFieldId=f.id AND x.boardId=b.id))');
  end;
  Prefix:='WITH ';
  for i:=0 to High(Aliases) do
  begin
    case i of 0:Value:=FUser;1:Value:=FBoard;2:Value:=FieldId;3:Value:=FCard;end;
    if i>0 then Prefix:=Prefix+',';
    Prefix:=Prefix+Aliases[i]+' AS MATERIALIZED(SELECT json(_ferretdb_sjson) s,wl_plain(json(_ferretdb_sjson)) d FROM '+
      FTables[i]+' WHERE json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(Value)+')';
  end;
  // wl_plain validates the complete BSON metadata; the schema checks below also
  // distinguish a BSON string ID from ObjectID and a boolean from numeric/date data.
  UserSchema:='json_extract(b.s,''$."$s".p.members.i[''||m.key||'']."$s".p.userId.t'')=''string''';
  Member:='EXISTS(SELECT 1 FROM json_each(CASE WHEN json_type(b.d,''$.members'')=''array'' THEN json_extract(b.d,''$.members'') ELSE ''[]'' END) m '+
    'WHERE m.type=''object'' AND json_type(CASE WHEN m.type=''object'' THEN m.value ELSE ''{}'' END,''$.userId'')=''text'''+
    ' AND json_extract(CASE WHEN m.type=''object'' THEN m.value ELSE ''{}'' END,''$.userId'')='+QuotedStr(FUser)+' AND '+UserSchema+
    ' AND json_type(CASE WHEN m.type=''object'' THEN m.value ELSE ''{}'' END,''$.isActive'')=''true''';
  Admin:=Member+' AND json_type(CASE WHEN m.type=''object'' THEN m.value ELSE ''{}'' END,''$.isAdmin'')=''true'')';
  for i:=0 to High(Roles) do if WriteAccess or (i in [2,3,4]) then
    Member:=Member+' AND '+FalseFlag('CASE WHEN m.type=''object'' THEN m.value ELSE ''{}'' END',Roles[i]);
  Member:=Member+')';Access:='(json_type(u.d,''$.isAdmin'')=''true'' OR '+Member;
  if not WriteAccess then Access:=Access+' OR json_extract(b.d,''$.permission'')=''public''';Access:=Access+')';
  Flags:='('+FalseFlag('f.d','adminOnly')+' OR (json_type(f.d,''$.adminOnly'')=''true'' AND '+Admin+'))';
  if WriteAccess then Flags:=Flags+' AND ('+FalseFlag('f.d','readOnly')+' OR (json_type(f.d,''$.readOnly'')=''true'' AND '+Admin+'))';
  Ids:=StringId('u',FUser)+' AND '+StringId('b',FBoard)+' AND '+StringId('f',FieldId)+' AND '+StringId('c',FCard);
  Result:='('+Prefix+' SELECT '+FBinding;
  for i:=0 to High(Aliases) do Result:=Result+' AND (SELECT count(*) FROM '+Aliases[i]+')=1';
  Result:=Result+' AND EXISTS(SELECT 1 FROM u,b,f,c WHERE '+Ids+' AND '+FalseFlag('u.d','loginDisabled')+' AND '+FalseFlag('b.d','archived')+
    ' AND json_type(c.d,''$.boardId'')=''text'' AND json_extract(c.s,''$."$s".p.boardId.t'')=''string'' AND json_extract(c.d,''$.boardId'')='+QuotedStr(FBoard)+
    ' AND '+Access+' AND '+Flags+' AND EXISTS(SELECT 1 FROM json_each(CASE WHEN json_type(f.d,''$.boardIds'')=''array'' THEN json_extract(f.d,''$.boardIds'') ELSE ''[]'' END) x '+
    'WHERE x.type=''text'' AND x.value='+QuotedStr(FBoard)+' AND json_extract(f.s,''$."$s".p.boardIds.i[''||x.key||''].t'')=''string'')))';
end;
function TFieldPolicy.Allowed(const FieldId:string;WriteAccess:Boolean):Boolean;
var Rows:TWLRows;
begin
  Rows:=FDb.Query('SELECT '+Expression(FieldId,WriteAccess)+';');
  Result:=(Length(Rows)=1) and (Length(Rows[0])=1) and (Rows[0][0]='1');
end;
function TFieldPolicy.Guard(const FieldId:string):string;
begin
  // A failed guard must be a SQL error, so the entire enclosing write rolls back
  // on either backend. RAISE() is available only inside triggers.
  Result:='SELECT CASE WHEN '+Expression(FieldId,True)+' THEN 1 ELSE json(''Field permission denied'') END; ';
end;
procedure TFieldPolicy.Redact(Fields:TJSONArray);
var i,j,Last:Integer;Sql:string;Rows:TWLRows;Field:TJSONObject;
begin
  i:=0;
  while i<Fields.Count do
  begin
    Last:=i+63;if Last>=Fields.Count then Last:=Fields.Count-1;Sql:='';
    for j:=i to Last do
    begin
      if Sql<>'' then Sql:=Sql+' UNION ALL ';
      Field:=TJSONObject(Fields.Items[j]);Sql:=Sql+'SELECT '+Expression(Field.Get('_id',''),False);
    end;
    Rows:=FDb.Query(Sql+';');
    for j:=i to Last do
      if (Length(Rows)<>Last-i+1) or (Length(Rows[j-i])<>1) or (Rows[j-i][0]<>'1') then
      begin
        Field:=TJSONObject(Fields.Items[j]);
        if Field.Find('value')<>nil then begin Field.Delete('value');Field.Add('value',TJSONNull.Create);end;
      end;
    i:=Last+1;
  end;
end;
end.
