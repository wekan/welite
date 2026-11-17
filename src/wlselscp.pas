unit wlselscp;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,fpjson,jsonparser,wldb,wlmodels,wlsjson;
type
  TSelectionScope=class
  private
    FDb:TWLDb;FModels,FRelations:TJSONArray;FRoots,FRelationRoots:TJSONObject;FBindings:TStringList;
    function Model(const Name:string):TJSONObject;
    function Root(const Name:string):TJSONObject;
    function Relation(const Name:string):TJSONObject;
    function RelationRoot(const Name:string):TJSONObject;
    function RelationStringField(const Name,Column:string):string;
  public
    constructor Create(Db:TWLDb);
    destructor Destroy;override;
    function IsRoot(const Name:string):Boolean;
    function ParentKey(const Name:string):string;
    function StringField(const Name,Column:string):string;
    property Bindings:TStringList read FBindings;
  end;
implementation
function Q(const Text:string):string;
begin Result:=QuotedStr(Text);end;
function Id(const Text:string):string;
begin Result:='"'+StringReplace(Text,'"','""',[rfReplaceAll])+'"';end;
function Path(const Text:string;Schema:Boolean):string;
var Parts:TStringArray;i:Integer;
begin
  Parts:=Text.Split('.');Result:='$';
  for i:=0 to High(Parts) do
  begin
    if Schema then Result:=Result+'."$s".p';
    Result:=Result+'."'+Parts[i]+'"';
  end;
  if Schema then Result:=Result+'.t';
end;
function FieldPath(Spec:TJSONObject;const Column:string):string;
var Fields:TJSONArray;i,Found:Integer;
begin
  Result:='';Found:=0;if not (Spec.Find('fields') is TJSONArray) then raise Exception.Create('Missing scope fields');
  Fields:=TJSONArray(Spec.Find('fields'));
  for i:=0 to Fields.Count-1 do
  begin
    if not (Fields.Items[i] is TJSONObject) then raise Exception.Create('Invalid scope field mapping');
    if Fields.Objects[i].Get('name','')=Column then begin Inc(Found);Result:=Fields.Objects[i].Get('path','');end;
  end;
  if (Found<>1) or (Result='') then raise Exception.Create('Missing scope field mapping');
end;
constructor TSelectionScope.Create(Db:TWLDb);
begin
  inherited Create;FDb:=Db;FModels:=TJSONArray(GetJSON(ModelJson));FRelations:=TJSONArray(GetJSON(RelationJson));
  FRoots:=TJSONObject.Create;FRelationRoots:=TJSONObject.Create;FBindings:=TStringList.Create;
end;
destructor TSelectionScope.Destroy;
begin FBindings.Free;FRelationRoots.Free;FRoots.Free;FRelations.Free;FModels.Free;inherited Destroy;end;
function TSelectionScope.Model(const Name:string):TJSONObject;
var i:Integer;
begin
  Result:=nil;for i:=0 to FModels.Count-1 do if FModels.Objects[i].Get('table','')=Name then Exit(FModels.Objects[i]);
end;
function TSelectionScope.IsRoot(const Name:string):Boolean;
begin Result:=Model(Name)<>nil;end;
function TSelectionScope.Root(const Name:string):TJSONObject;
var Rows:TWLRows;Spec:TJSONObject;Collection,Test,ViewSql:string;
begin
  Result:=TJSONObject(FRoots.Find(Name));if Result<>nil then Exit;
  Spec:=Model(Name);if Spec=nil then raise Exception.Create('Unknown scope root');Collection:=Spec.Get('collection','');
  Rows:=FDb.Query('SELECT type,sql FROM sqlite_master WHERE name='+Q(Name)+';');
  if Length(Rows)<>1 then raise Exception.Create('Missing scope source');
  if Rows[0][0]='table' then
  begin Result:=TJSONObject.Create(['native',True]);FRoots.Add(Name,Result);Exit;end;
  if Rows[0][0]<>'view' then raise Exception.Create('Unsupported scope source');ViewSql:=Rows[0][1];
  Rows:=FDb.Query('SELECT m.table_name,m.spec,m.version,c.settings FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name '+
    'WHERE m.name='+Q(Name)+' AND c.name='+Q(Collection)+' AND json_extract(m.spec,''$.table'')='+Q(Name)+' AND json_extract(m.spec,''$.collection'')=c.name;');
  if Length(Rows)<>1 then raise Exception.Create('Missing scope ownership');
  Test:='EXISTS(SELECT 1 FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name WHERE m.name='+Q(Name)+
    ' AND m.table_name='+Q(Rows[0][0])+' AND m.spec='+Q(Rows[0][1])+' AND m.version='+Q(Rows[0][2])+' AND c.name='+Q(Collection)+' AND c.settings='+Q(Rows[0][3])+') AND EXISTS(SELECT 1 FROM sqlite_master v WHERE v.type=''view'' AND v.name='+Q(Name)+' AND v.sql='+Q(ViewSql)+')';
  Result:=TJSONObject.Create(['native',False,'table',Rows[0][0],'test',Test]);
  try Result.Add('spec',CheckedJsonObject(Rows[0][1]));except Result.Free;raise;end;
  FRoots.Add(Name,Result);FBindings.Add('SELECT CASE WHEN '+Test+' THEN 1 ELSE json(''Selection scope binding changed'') END;');
end;
function SameJson(A,B:TJSONData):Boolean;
var i,j:Integer;Found:Boolean;
begin
  Result:=False;if (A=nil) or (B=nil) then Exit(A=B);
  if A.JSONType<>B.JSONType then Exit;
  if A.JSONType=jtObject then
  begin
    if A.Count<>B.Count then Exit;
    for i:=0 to A.Count-1 do
    begin
      Found:=False;
      for j:=0 to B.Count-1 do if TJSONObject(A).Names[i]=TJSONObject(B).Names[j] then
      begin if not SameJson(A.Items[i],B.Items[j]) then Exit;Found:=True;Break;end;
      if not Found then Exit;
    end;
  end
  else if A.JSONType=jtArray then
  begin
    if A.Count<>B.Count then Exit;
    for i:=0 to A.Count-1 do if not SameJson(A.Items[i],B.Items[i]) then Exit;
  end
  else if A.AsJSON<>B.AsJSON then Exit;
  Result:=True;
end;
function TSelectionScope.Relation(const Name:string):TJSONObject;
var i:Integer;
begin
  Result:=nil;for i:=0 to FRelations.Count-1 do if FRelations.Objects[i].Get('table','')=Name then Exit(FRelations.Objects[i]);
end;
function TSelectionScope.ParentKey(const Name:string):string;
var Spec:TJSONObject;
begin
  Spec:=Relation(Name);if Spec=nil then raise Exception.Create('Unknown scope relation');
  Result:=Spec.Get('parentKey','');
end;
function TSelectionScope.RelationRoot(const Name:string):TJSONObject;
var Spec,Parent,Stored:TJSONObject;Rows:TWLRows;ParentName,ViewSql,Test:string;
begin
  Result:=TJSONObject(FRelationRoots.Find(Name));if Result<>nil then Exit;
  Spec:=Relation(Name);if Spec=nil then raise Exception.Create('Unknown scope relation');
  Rows:=FDb.Query('SELECT type,sql FROM sqlite_master WHERE name='+Q(Name)+';');
  if Length(Rows)<>1 then raise Exception.Create('Missing relation scope source');
  if Rows[0][0]='table' then
  begin Result:=TJSONObject.Create(['native',True]);FRelationRoots.Add(Name,Result);Exit;end;
  if Rows[0][0]<>'view' then raise Exception.Create('Unsupported relation scope source');ViewSql:=Rows[0][1];
  ParentName:=Spec.Get('parent','');Parent:=Root(ParentName);
  if Parent.Get('native',False) then raise Exception.Create('Missing shared relation parent');
  if FieldPath(TJSONObject(Parent.Find('spec')),'id')<>FieldPath(Model(ParentName),'id') then
    raise Exception.Create('Relation parent mapping changed');
  Rows:=FDb.Query('SELECT table_name,spec,version FROM _wl_models WHERE name='+Q(Name)+' AND table_name='+Q(Parent.Get('table',''))+';');
  if Length(Rows)<>1 then raise Exception.Create('Missing relation scope ownership');
  Stored:=CheckedJsonObject(Rows[0][1]);
  try if not SameJson(Spec,Stored) then raise Exception.Create('Relation scope mapping changed');finally Stored.Free;end;
  Test:=Parent.Get('test','')+' AND (SELECT count(*) FROM _wl_models WHERE name='+Q(Name)+')=1 AND '+
    'EXISTS(SELECT 1 FROM _wl_models WHERE name='+Q(Name)+' AND table_name='+Q(Rows[0][0])+' AND spec='+Q(Rows[0][1])+' AND version='+Q(Rows[0][2])+') '+
    'AND EXISTS(SELECT 1 FROM sqlite_master WHERE type=''view'' AND name='+Q(Name)+' AND sql='+Q(ViewSql)+')';
  Result:=TJSONObject.Create(['native',False,'parent',ParentName,'test',Test]);FRelationRoots.Add(Name,Result);
  FBindings.Add('SELECT CASE WHEN '+Test+' THEN 1 ELSE json(''Selection relation binding changed'') END;');
end;
function TSelectionScope.RelationStringField(const Name,Column:string):string;
var Info,Spec,Parent,Field:TJSONObject;Fields,Keys:TJSONArray;
  Owner,Match,Items,ArrayPath,ArraySchema,SchemaExpr,KeyPath,Value,ValueType,Kind,Canonical,KeyMatch,KeyCanonical,DefaultValue,Missing,Projected:string;
  i,j:Integer;Scalar,FoundColumn:Boolean;
begin
  Info:=RelationRoot(Name);Result:='1';if Info.Get('native',False) then Exit;
  Spec:=Relation(Name);Parent:=Root(Info.Get('parent',''));Fields:=TJSONArray(Spec.Find('fields'));Keys:=TJSONArray(Spec.Find('keys'));
  Scalar:=Spec.Get('scalar',False);Owner:=Id(Name)+'.'+Id(Spec.Get('parentKey',''));FoundColumn:=Column=Spec.Get('parentKey','');
  ArrayPath:=Path(Spec.Get('path',''),False);ArraySchema:=Path(Spec.Get('path',''),True);SetLength(ArraySchema,Length(ArraySchema)-2);
  Items:='json_each(CASE WHEN json_type(rs._ferretdb_sjson,'+Q(ArrayPath)+')=''array'' THEN json_extract(rs._ferretdb_sjson,'+Q(ArrayPath)+') ELSE ''[]'' END) re';
  Canonical:='typeof('+Owner+')=''text'' AND json_type(rs._ferretdb_sjson,''$."_id"'')=''text'' '+
    'AND json_extract(rs._ferretdb_sjson,''$."$s".p."_id".t'')=''string'' AND '+Owner+'<>'''' '+
    'AND json_extract(rs._ferretdb_sjson,'+Q(ArraySchema+'.t')+')=''array''';
  Match:='json_extract(rs._ferretdb_sjson,''$."_id"'')='+Owner;KeyMatch:='1';KeyCanonical:='1';
  if not Scalar then KeyCanonical:=KeyCanonical+' AND re.type=''object'' AND json_extract(rs._ferretdb_sjson,'+
    Q(ArraySchema+'.i[')+'||re.key||'+Q('].t')+')=''object''';
  for i:=0 to Keys.Count-1 do
  begin
    Field:=nil;for j:=0 to Fields.Count-1 do if Fields.Objects[j].Get('path','')=Keys.Strings[i] then Field:=Fields.Objects[j];
    if Field=nil then raise Exception.Create('Missing relation scope key');
    if Field.Get('name','')=Column then FoundColumn:=True;
    KeyPath:=Field.Get('path','');Projected:=Id(Name)+'.'+Id(Field.Get('name',''));
    if Scalar then
    begin
      Value:='re.value';ValueType:='re.type';
      SchemaExpr:=Q(ArraySchema+'.i[')+'||re.key||'+Q('].t');
    end
    else
    begin
      Value:='json_extract(CASE WHEN re.type=''object'' THEN re.value ELSE ''{}'' END,'+Q(Path(KeyPath,False))+')';
      ValueType:='json_type(CASE WHEN re.type=''object'' THEN re.value ELSE ''{}'' END,'+Q(Path(KeyPath,False))+')';
      SchemaExpr:=Q(ArraySchema+'.i[')+'||re.key||'+Q(']'+Copy(Path(KeyPath,True),2,MaxInt));
    end;
    Kind:='json_extract(rs._ferretdb_sjson,'+SchemaExpr+')';
    Missing:='';DefaultValue:='';
    if Field.Find('default').JSONType<>jtNull then
    begin
      if (Field.Find('default').JSONType<>jtString) or (Field.Get('default','')='') then raise Exception.Create('Unsupported relation scope key default');
      DefaultValue:=Q(Field.Get('default',''));
      Missing:=' OR (('+ValueType+' IS NULL AND '+Kind+' IS NULL) OR ('+ValueType+'=''null'' AND '+Kind+'=''null''))';
    end;
    KeyCanonical:=KeyCanonical+' AND typeof('+Projected+')=''text'' AND (('+ValueType+'=''text'' AND '+Kind+'=''string'' AND '+Value+'<>'''')'+Missing+')';
    if DefaultValue<>'' then Value:='COALESCE('+Value+','+DefaultValue+')';
    KeyMatch:=KeyMatch+' AND '+Value+' IS '+Projected;
  end;
  if not FoundColumn then raise Exception.Create('Unknown relation scope key column');
  Result:='(CASE WHEN '+Info.Get('test','')+' THEN CASE WHEN '+Owner+' IS NULL THEN 0 '+
    'WHEN (SELECT count(*) FROM '+Id(Parent.Get('table',''))+' rs WHERE '+Match+')=1 THEN '+
    '(SELECT CASE WHEN '+Canonical+' THEN CASE WHEN (SELECT count(*) FROM '+Items+' WHERE '+KeyMatch+')=1 '+
    'THEN EXISTS(SELECT 1 FROM '+Items+' WHERE '+KeyMatch+' AND '+KeyCanonical+') '+
    'ELSE json(''Ambiguous selection relation key'') END ELSE 0 END FROM '+Id(Parent.Get('table',''))+' rs WHERE '+Match+') '+
    'ELSE json(''Ambiguous selection relation owner'') END ELSE json(''Selection relation binding changed'') END)';
end;
function TSelectionScope.StringField(const Name,Column:string):string;
var Info:TJSONObject;Mapped,Identity,Match:string;
  function Canonical(const SourcePath:string):string;
  begin
    Result:='json_type(ss._ferretdb_sjson,'+Q(Path(SourcePath,False))+')=''text'' AND '+
      'json_extract(ss._ferretdb_sjson,'+Q(Path(SourcePath,True))+')=''string'' AND '+
      'json_extract(ss._ferretdb_sjson,'+Q(Path(SourcePath,False))+')<>''''';
  end;
begin
  if Model(Name)=nil then Exit(RelationStringField(Name,Column));
  Info:=Root(Name);Result:='1';if Info.Get('native',False) then Exit;
  Mapped:=FieldPath(Model(Name),Column);
  if FieldPath(TJSONObject(Info.Find('spec')),Column)<>Mapped then raise Exception.Create('Scope source mapping changed');
  Identity:=Canonical('_id')+' AND typeof('+Id(Name)+'.id)=''text''';if Column<>'id' then Identity:=Identity+' AND '+Canonical(Mapped);
  Match:='json_extract(ss._ferretdb_sjson,'+Q(Path('_id',False))+')='+Id(Name)+'.id';
  Identity:=Identity+' AND typeof('+Id(Name)+'.'+Id(Column)+')=''text'' AND json_extract(ss._ferretdb_sjson,'+Q(Path(Mapped,False))+')='+Id(Name)+'.'+Id(Column);
  Result:='(CASE WHEN '+Info.Get('test','')+' THEN CASE WHEN '+Id(Name)+'.id IS NULL THEN 0 '+
    'WHEN (SELECT count(*) FROM '+Id(Info.Get('table',''))+' ss WHERE '+Match+')=1 THEN '+
    'EXISTS(SELECT 1 FROM '+Id(Info.Get('table',''))+' ss WHERE '+Match+' AND '+Identity+') '+
    'ELSE json(''Ambiguous selection identity'') END ELSE json(''Selection scope binding changed'') END)';
end;
end.
