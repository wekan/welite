unit wlselscp;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,fpjson,jsonparser,wldb,wlmodels,wlsjson;
type
  TSelectionScope=class
  private
    FDb:TWLDb;FModels:TJSONArray;FRoots:TJSONObject;FBindings:TStringList;
    function Model(const Name:string):TJSONObject;
    function Root(const Name:string):TJSONObject;
  public
    constructor Create(Db:TWLDb);
    destructor Destroy;override;
    function IsRoot(const Name:string):Boolean;
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
  inherited Create;FDb:=Db;FModels:=TJSONArray(GetJSON(ModelJson));FRoots:=TJSONObject.Create;FBindings:=TStringList.Create;
end;
destructor TSelectionScope.Destroy;
begin FBindings.Free;FRoots.Free;FModels.Free;inherited Destroy;end;
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
function TSelectionScope.StringField(const Name,Column:string):string;
var Info:TJSONObject;Mapped,Identity,Match:string;
  function Canonical(const SourcePath:string):string;
  begin
    Result:='json_type(ss._ferretdb_sjson,'+Q(Path(SourcePath,False))+')=''text'' AND '+
      'json_extract(ss._ferretdb_sjson,'+Q(Path(SourcePath,True))+')=''string'' AND '+
      'json_extract(ss._ferretdb_sjson,'+Q(Path(SourcePath,False))+')<>''''';
  end;
begin
  Info:=Root(Name);Result:='1';if Info.Get('native',False) then Exit;
  Mapped:=FieldPath(Model(Name),Column);
  if FieldPath(TJSONObject(Info.Find('spec')),Column)<>Mapped then raise Exception.Create('Scope source mapping changed');
  Identity:=Canonical('_id');if Column<>'id' then Identity:=Identity+' AND '+Canonical(Mapped);
  Match:='json_extract(ss._ferretdb_sjson,'+Q(Path('_id',False))+')='+Id(Name)+'.id';
  Identity:=Identity+' AND json_extract(ss._ferretdb_sjson,'+Q(Path(Mapped,False))+')='+Id(Name)+'.'+Id(Column);
  Result:='(CASE WHEN '+Info.Get('test','')+' THEN CASE WHEN '+Id(Name)+'.id IS NULL THEN 0 '+
    'WHEN (SELECT count(*) FROM '+Id(Info.Get('table',''))+' ss WHERE '+Match+')=1 THEN '+
    'EXISTS(SELECT 1 FROM '+Id(Info.Get('table',''))+' ss WHERE '+Match+' AND '+Identity+') '+
    'ELSE json(''Ambiguous selection identity'') END ELSE json(''Selection scope binding changed'') END)';
end;
end.
