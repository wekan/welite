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
    function Build(const FieldId:string;WriteAccess,DefinitionAccess,AdminRequired:Boolean;HistoryAccess:Boolean=False;CardOnly:Boolean=False;FieldColumn:Boolean=False;CardColumn:Boolean=False;AllowSiteAdmin:Boolean=False):string;
  public
    constructor Create(Db:TWLDb;const UserId,BoardId,CardId:string);
    function Expression(const FieldId:string;WriteAccess:Boolean):string;
    function Allowed(const FieldId:string;WriteAccess:Boolean):Boolean;
    function DefinitionExpression(const FieldId:string;AdminRequired:Boolean):string;
    function HistoryExpression(const FieldId:string):string;
    function ScopeWriteExpression(const FieldId:string):string;
    function CloneCardGuard:string;
    function ScopeBoardExpression(WriteAccess:Boolean):string;
    function ScopeAdminExpression(AllowSiteAdmin:Boolean=False):string;
    function Guard(const FieldId:string):string;
    procedure Redact(Fields:TJSONArray);
  end;
function BoardFieldExportAllowed(Db:TWLDb;const UserId,BoardId:string):Boolean;
function FieldExportRowsAllowed(Db:TWLDb;const UserId,BoardId:string;Rows:TJSONArray):Boolean;
implementation
uses wlcfspec,wlcfjson;
function FalseFlag(const Doc,Name:string):string;
begin
  Result:='COALESCE(json_type('+Doc+',''$.'+Name+''') IN (''null'',''false''),1)';
end;
function StringIdSql(const Alias,IdentitySql:string):string;
begin
  Result:='json_type('+Alias+'.d,''$._id'')=''text'' AND json_extract('+Alias+'.d,''$._id'')='+IdentitySql+
    ' AND json_extract('+Alias+'.s,''$."$s".p._id.t'')=''string''';
end;
function StringId(const Alias,Identity:string):string;
begin Result:=StringIdSql(Alias,QuotedStr(Identity));end;
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
function TFieldPolicy.Build(const FieldId:string;WriteAccess,DefinitionAccess,AdminRequired,HistoryAccess,CardOnly,FieldColumn,CardColumn,AllowSiteAdmin:Boolean):string;
const Roles:array[0..5] of string=('isReadOnly','isCommentOnly','isReadAssignedOnly','isCommentAssignedOnly','isNormalAssignedOnly','isWorker');
  Aliases:array[0..3] of string=('u','b','f','c');
var Admin,Member,Access,Flags,Prefix,Ids,Value,UserSchema,Tables,WhereSql,FieldSql,ValueSql,CardSql:string;i,Last:Integer;HasField:Boolean;
begin
  HasField:=not CardOnly and (not DefinitionAccess or (FieldId<>''));
  FieldSql:=QuotedStr(FieldId);if FieldColumn then FieldSql:='v.customFieldId';
  CardSql:=QuotedStr(FCard);if CardColumn then CardSql:='v.cardId';
  if not FShared then
  begin
    Admin:='EXISTS(SELECT 1 FROM board_members m WHERE m.boardId=b.id AND m.userId=u.id AND m.isActive=1 AND m.isAdmin=1)';
    Member:='EXISTS(SELECT 1 FROM board_members m WHERE m.boardId=b.id AND m.userId=u.id AND m.isActive=1';
    for i:=0 to High(Roles) do if WriteAccess or (i in [2,3,4]) then Member:=Member+' AND COALESCE(m.'+Roles[i]+',0)=0';
    Member:=Member+')';Access:='(u.isAdmin=1 OR '+Member;
    if not WriteAccess then Access:=Access+' OR b.permission=''public''';Access:=Access+')';
    Flags:='typeof(f.adminOnly)=''integer'' AND f.adminOnly IN (0,1) AND (f.adminOnly=0 OR '+Admin+')';
    if WriteAccess then Flags:=Flags+' AND typeof(f.readOnly)=''integer'' AND f.readOnly IN (0,1) AND (f.readOnly=0 OR '+Admin+')';
    Tables:='boards b,users u';WhereSql:='b.id='+QuotedStr(FBoard)+' AND b.archived=0 AND u.id='+QuotedStr(FUser)+' AND u.loginDisabled=0 AND '+Access;
    if HasField then
    begin
      Tables:=Tables+',custom_fields f';WhereSql:=WhereSql+' AND f.id='+FieldSql+
        ' AND EXISTS(SELECT 1 FROM custom_field_boards x WHERE x.customFieldId=f.id AND x.boardId=b.id)';
      if DefinitionAccess then Flags:='typeof(f.adminOnly)=''integer'' AND f.adminOnly IN (0,1) AND (f.adminOnly=0 OR '+Admin+')'+
        ' AND (SELECT count(*) FROM custom_field_boards x WHERE x.customFieldId=f.id)=1';
      WhereSql:=WhereSql+' AND '+Flags;
    end;
    if AllowSiteAdmin then Admin:='(u.isAdmin=1 OR '+Admin+')';
    if DefinitionAccess then
    begin if AdminRequired then WhereSql:=WhereSql+' AND '+Admin;end
    else if not HistoryAccess then begin Tables:=Tables+',cards c';WhereSql:=WhereSql+' AND c.id='+CardSql+' AND c.boardId=b.id';end;
    Exit('(SELECT count(*)=1 FROM '+Tables+' WHERE '+WhereSql+')');
  end;
  Last:=High(Aliases);if DefinitionAccess then begin Last:=1;if HasField then Last:=2;end else if HistoryAccess then Last:=2;
  Prefix:='WITH ';
  for i:=0 to Last do
  begin
    if CardOnly and (i=2) then Continue;
    case i of 0:Value:=FUser;1:Value:=FBoard;2:Value:=FieldId;3:Value:=FCard;end;
    ValueSql:=QuotedStr(Value);if (i=2) and FieldColumn then ValueSql:=FieldSql;
    if (i=3) and CardColumn then ValueSql:=CardSql;
    if i>0 then Prefix:=Prefix+',';
    Prefix:=Prefix+Aliases[i]+' AS MATERIALIZED(SELECT json(_ferretdb_sjson) s,wl_plain(json(_ferretdb_sjson)) d FROM '+
      FTables[i]+' WHERE json_extract(_ferretdb_sjson,''$._id'')='+ValueSql+')';
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
  Ids:=StringId('u',FUser)+' AND '+StringId('b',FBoard);Tables:='u,b';
  WhereSql:=Ids+' AND '+FalseFlag('u.d','loginDisabled')+' AND '+FalseFlag('b.d','archived')+' AND '+Access;
  if HasField then
  begin
    Tables:=Tables+',f';
    if DefinitionAccess then Flags:='json_type(f.d,''$.readOnly'') IN (''true'',''false'') AND '+
      'json_type(f.d,''$.adminOnly'') IN (''true'',''false'') AND ('+FalseFlag('f.d','adminOnly')+' OR '+Admin+') AND json_array_length(f.d,''$.boardIds'')=1';
    WhereSql:=WhereSql+' AND '+StringIdSql('f',FieldSql)+' AND '+Flags+
      ' AND EXISTS(SELECT 1 FROM json_each(CASE WHEN json_type(f.d,''$.boardIds'')=''array'' THEN json_extract(f.d,''$.boardIds'') ELSE ''[]'' END) x '+
      'WHERE x.type=''text'' AND x.value='+QuotedStr(FBoard)+' AND json_extract(f.s,''$."$s".p.boardIds.i[''||x.key||''].t'')=''string'')';
  end;
  if AllowSiteAdmin then Admin:='(json_type(u.d,''$.isAdmin'')=''true'' OR '+Admin+')';
  if DefinitionAccess then
  begin if AdminRequired then WhereSql:=WhereSql+' AND '+Admin;end
  else if not HistoryAccess then begin
    Tables:=Tables+',c';WhereSql:=WhereSql+' AND '+StringIdSql('c',CardSql)+
      ' AND json_type(c.d,''$.boardId'')=''text'' AND json_extract(c.s,''$."$s".p.boardId.t'')=''string'' AND json_extract(c.d,''$.boardId'')='+QuotedStr(FBoard);
    if HasField then WhereSql:=WhereSql+
      ' AND NOT EXISTS(SELECT 1 FROM json_each(CASE WHEN json_type(c.d,''$.customFields'')=''array'' THEN json_extract(c.d,''$.customFields'') ELSE ''[]'' END) cf '+
      'WHERE json_extract(CASE WHEN cf.type=''object'' THEN cf.value ELSE ''{}'' END,''$._id'')='+FieldSql+
      ' AND (json_type(CASE WHEN cf.type=''object'' THEN cf.value ELSE ''{}'' END,''$._id'') IS NOT ''text'' OR '+
      'COALESCE(json_extract(c.s,''$."$s".p.customFields.i[''||cf.key||'']."$s".p._id.t''),'''')<>''string''))';

  end;
  Result:='('+Prefix+' SELECT '+FBinding;
  for i:=0 to Last do if not (CardOnly and (i=2)) then Result:=Result+' AND (SELECT count(*) FROM '+Aliases[i]+')=1';
  Result:=Result+' AND EXISTS(SELECT 1 FROM '+Tables+' WHERE '+WhereSql+'))';
end;
function TFieldPolicy.Expression(const FieldId:string;WriteAccess:Boolean):string;
begin Result:=Build(FieldId,WriteAccess,False,False);end;
function TFieldPolicy.DefinitionExpression(const FieldId:string;AdminRequired:Boolean):string;
begin Result:=Build(FieldId,True,True,AdminRequired);end;
function TFieldPolicy.HistoryExpression(const FieldId:string):string;
begin Result:=Build(FieldId,False,False,False,True);end;
function TFieldPolicy.ScopeWriteExpression(const FieldId:string):string;
begin Result:=Build(FieldId,True,False,False,True);end;
function TFieldPolicy.CloneCardGuard:string;
begin
  Result:='SELECT CASE WHEN '+Build('',True,False,False,False,True)+
    ' AND NOT EXISTS(SELECT 1 FROM card_custom_field_values v WHERE v.cardId='+QuotedStr(FCard)+
    ' AND v.value IS NOT NULL AND NOT '+Build('',True,False,False,False,False,True)+
    ') THEN 1 ELSE json(''Clone field permission denied'') END; ';
end;
function TFieldPolicy.ScopeBoardExpression(WriteAccess:Boolean):string;
begin Result:=Build('',WriteAccess,True,False);end;
function TFieldPolicy.ScopeAdminExpression(AllowSiteAdmin:Boolean):string;
begin Result:=Build('',False,True,True,True,False,False,False,AllowSiteAdmin);end;
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
function BoardFieldExportAllowed(Db:TWLDb;const UserId,BoardId:string):Boolean;
var Policy:TFieldPolicy;Values:TWLRows;
begin
  Result:=False;Policy:=nil;
  try
    try
      Policy:=TFieldPolicy.Create(Db,UserId,BoardId,'');
      Values:=Db.Query('SELECT '+Policy.DefinitionExpression('',False)+';');
      if (Length(Values)<>1) or (Values[0][0]<>'1') then Exit;
      if BoardDefinitionAdminRequired(Db,BoardId) then
      begin
        Values:=Db.Query('SELECT '+Policy.DefinitionExpression('',True)+';');
        if (Length(Values)<>1) or (Values[0][0]<>'1') then Exit;
      end;
      ValidateBoardCustomFields(Db,BoardId);
      // Trusted correlation aliases let one statement check every assigned value.
      // Keep storage NULL semantics: JSON conversion can turn nonnull BSON into null.
      Values:=Db.Query('SELECT NOT EXISTS(SELECT 1 FROM card_custom_field_values v '+
        'WHERE v.cardId IN (SELECT id FROM cards WHERE boardId='+QuotedStr(BoardId)+') '+
        'AND v.value IS NOT NULL AND (v.customFieldId IS NULL OR v.customFieldId='''' OR NOT '+
        Policy.Build('',False,False,False,False,False,True,True)+'));');
      if (Length(Values)<>1) or (Values[0][0]<>'1') then Exit;
      Result:=True;
    except Result:=False;end;
  finally Policy.Free;end;
end;
function FieldExportRowsAllowed(Db:TWLDb;const UserId,BoardId:string;Rows:TJSONArray):Boolean;
var Policy:TFieldPolicy;Row:TJSONObject;Card,Field,Value:TJSONData;LastCard:string;i:Integer;
begin
  Result:=False;Policy:=nil;LastCard:='';
  try
    try
      if Rows=nil then Exit;
      for i:=0 to Rows.Count-1 do
      begin
        if not (Rows.Items[i] is TJSONObject) then Exit;
        Row:=TJSONObject(Rows.Items[i]);Value:=Row.Find('value');
        if (Value=nil) or (Value.JSONType=jtNull) then Continue;
        Card:=Row.Find('cardId');Field:=Row.Find('customFieldId');
        if (Card=nil) or (Field=nil) or (Card.JSONType<>jtString) or (Field.JSONType<>jtString) or
          (Card.AsString='') or (Field.AsString='') then Exit;
        if (Policy=nil) or (Card.AsString<>LastCard) then
        begin
          FreeAndNil(Policy);LastCard:=Card.AsString;
          Policy:=TFieldPolicy.Create(Db,UserId,BoardId,LastCard);
        end;
        if not Policy.Allowed(Field.AsString,False) then Exit;
      end;
      Result:=True;
    except Result:=False;end;
  finally Policy.Free;end;
end;
end.
