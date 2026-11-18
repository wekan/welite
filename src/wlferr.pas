unit wlferr;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses SysUtils,Classes,StrUtils,fpjson,jsonparser,wldb,wlmodels,wlpasswd,wlrel,wlrefs,wlpriv,wluniq;
// Installs root and child projections. Application activation and shared-account
// compatibility remain separate gates before this is a finished store adapter.
function InstallRootModels(Db:TWLDb):Boolean;
function RootModelScript(Db:TWLDb):string;
function EnsurePositionHistoryCollection(Db:TWLDb):Boolean;
implementation
const DocCol='_ferretdb_sjson';
function Q(const Text:string):string;
begin Result:=QuotedStr(Text);end;
function Ident(const Text:string):string;
begin Result:='"'+StringReplace(Text,'"','""',[rfReplaceAll])+'"';end;
function JsonPath(const Path:string):string;
var Parts:TStringArray;i:Integer;
begin
  Parts:=Path.Split('.');Result:='$';
  for i:=0 to High(Parts) do Result:=Result+'."'+Parts[i]+'"';
end;
function RootOf(const Path:string):string;
var N:Integer;
begin N:=Pos('.',Path);if N=0 then Result:=Path else Result:=Copy(Path,1,N-1);end;
function Expr(const Path:string):string;
begin Result:='json_extract('+Ident(DocCol)+','+Q(JsonPath(Path))+')';end;
function Uuid:string;
var Hex:string;N:Integer;
begin
  Hex:=LowerCase(Copy(NewAuthToken,1,32));Hex[13]:='4';
  N:=StrToInt('$'+Hex[17]) and 3;Hex[17]:='89ab'[N+1];
  Result:=Copy(Hex,1,8)+'-'+Copy(Hex,9,4)+'-'+Copy(Hex,13,4)+'-'+Copy(Hex,17,4)+'-'+Copy(Hex,21,12);
end;
function Candidate(const Name:string;Hash:LongWord):string;
begin
  Result:=LowerCase(Name)+'_'+LowerCase(IntToHex(Hash,8));
  if Copy(Result,1,7)='sqlite_' then Result:='_'+Result;
end;
function NameHash(const Name:string):LongWord;
var i:Integer;
begin
  // FerretDB's collection-name FNV32, not an authentication digest.
  Result:=2166136261;
  for i:=1 to Length(Name) do Result:=LongWord((QWord(Result xor Ord(Name[i]))*16777619) and $ffffffff);
end;
function ColumnStorage(Db:TWLDb;const TableName:string):string;
var Rows:TWLRows;i:Integer;Found:Boolean;
begin
  Rows:=Db.Query('PRAGMA table_info('+Ident(TableName)+');');Result:='';Found:=False;
  for i:=0 to High(Rows) do
    if Rows[i][1]=DocCol then
    begin
      Found:=True;Result:=LowerCase(Rows[i][2]);
      if not ((Result='text') or (Result='blob')) then raise Exception.Create('Unsupported FerretDB document column');
    end
    else if (Rows[i][3]='1') and (Rows[i][4]='') and (Rows[i][5]='0') then
      raise Exception.Create('Additional required physical columns need an adapter');
  if not Found then raise Exception.Create('Missing FerretDB document column');
end;
function CreateCollectionSql(const Collection,TableName,Storage:string;ReuseTable:Boolean):string;
var Settings,IndexDef:TJSONObject;Indexes,Keys:TJSONArray;Reuse:string;
begin
  Reuse:='';if ReuseTable then Reuse:='IF NOT EXISTS ';
  Settings:=TJSONObject.Create;
  try
    Settings.Add('uuid',Uuid);Settings.Add('cappedSize',0);Settings.Add('cappedDocuments',0);
    Settings.Add('indexFormat',3);if Storage='blob' then Settings.Add('storage','jsonb');
    Indexes:=TJSONArray.Create;Settings.Add('indexes',Indexes);
    IndexDef:=TJSONObject.Create;Indexes.Add(IndexDef);
    IndexDef.Add('name','_id_');IndexDef.Add('unique',True);
    Keys:=TJSONArray.Create;IndexDef.Add('key',Keys);
    Keys.Add(TJSONObject.Create(['field','_id','descending',False]));
    Result:='CREATE TABLE '+Reuse+Ident(TableName)+'('+Ident(DocCol)+' '+UpperCase(Storage)+' NOT NULL) STRICT; '+
      'CREATE UNIQUE INDEX '+Reuse+Ident(TableName+'__id_')+' ON '+Ident(TableName)+'('+Ident(DocCol)+'->'+Q('_id')+'); '+
      'INSERT INTO _ferretdb_collections(name,table_name,settings) VALUES('+Q(Collection)+','+
      Q(TableName)+','+Q(Settings.AsJSON)+'); ';
  finally Settings.Free;end;
end;

function EnsurePositionHistoryCollection(Db:TWLDb):Boolean;
const Collection='userPositionHistory';
var Hash:LongWord;TableName:string;Rows:TWLRows;
  function Exists:Boolean;
  begin
    Result:=Length(Db.Query('SELECT r.table_name FROM _ferretdb_collections r JOIN sqlite_master m '+
      'ON m.name=r.table_name AND m.type=''table'' WHERE r.name='+Q(Collection)+';'))=1;
  end;
begin
  if Exists then Exit(True);
  Hash:=NameHash(Collection);
  repeat
    TableName:=Candidate(Collection,Hash);
    Rows:=Db.Query('SELECT name FROM sqlite_master WHERE name IN ('+Q(TableName)+','+
      Q(TableName+'__id_')+') UNION ALL SELECT table_name FROM _ferretdb_collections WHERE table_name='+Q(TableName)+';');
    Inc(Hash);
  until Length(Rows)=0;
  if not Db.Exec('BEGIN IMMEDIATE; '+CreateCollectionSql(Collection,TableName,'blob',False)+'COMMIT;') then
    Db.Exec('ROLLBACK;');
  Result:=Exists;
end;

function RootModelScript(Db:TWLDb):string;
var Models:TJSONArray;Model,Field,Settings:TJSONObject;Fields,Managed:TJSONArray;
  Registry,Rows,Owner,Objects,Custom:TWLRows;Used,Roots,Tables:TStringList;
  Sql,TableName,ViewName,Collection,Storage,Existing,ReadExpr,Columns,Spec,SettingsText,Body,Root,Incoming,DeferredCustom:string;
  Hash:LongWord;i,j,k:Integer;Fresh,MetadataExists,OwnerExists,Found:Boolean;
  function Wrapped(const Value:string):string;
  begin
    // FerretDB may upgrade an old TEXT collection on restart. Read the actual
    // column declaration at execution time instead of freezing the install format.
    Result:='CASE WHEN (SELECT wl_storage('+Q(TableName)+'))=''blob'' THEN jsonb('+Value+') ELSE ('+Value+') END';
  end;
  function HasObject(const Name:string):Boolean;
  var n:Integer;
  begin
    Result:=False;
    for n:=0 to High(Objects) do if SameText(Objects[n][0],Name) then Exit(True);
  end;
begin
  Result:='';DeferredCustom:='';Models:=nil;Used:=nil;Roots:=nil;Tables:=nil;
  Rows:=Db.Query('SELECT wl_model('''',''{}'',''{"fields":[],"managed":[]}'',''insert'') IS NOT NULL,json_valid(json(jsonb(''{}'')));');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') or (Rows[0][1]<>'1') then
    raise Exception.Create('Typed projection functions and SQLite JSONB are required');
  Objects:=Db.Query('SELECT name,type FROM sqlite_master WHERE type IN (''table'',''view'');');
  MetadataExists:=HasObject('_ferretdb_collections');OwnerExists:=HasObject('_wl_models');
  Registry:=nil;Owner:=nil;
  if MetadataExists then Registry:=Db.Query('SELECT name,table_name,settings FROM _ferretdb_collections;');
  if OwnerExists then Owner:=Db.Query('SELECT name,table_name FROM _wl_models;');
  try
    Models:=TJSONArray(GetJSON(ModelJson));Tables:=TStringList.Create;Used:=TStringList.Create;Used.CaseSensitive:=False;
    for i:=0 to High(Registry) do
    begin
      if Used.IndexOf(Registry[i][1])>=0 then raise Exception.Create('Duplicate physical collection mapping');
      Used.Add(Registry[i][1]);
    end;
    Sql:='BEGIN IMMEDIATE; CREATE TABLE IF NOT EXISTS _ferretdb_collections('+ 
      'name TEXT NOT NULL UNIQUE CHECK(name<>''''),table_name TEXT NOT NULL UNIQUE CHECK(table_name<>''''),'+
      'settings TEXT NOT NULL CHECK(settings<>'''')) STRICT; '+
      'CREATE TABLE IF NOT EXISTS _wl_models(name TEXT PRIMARY KEY,table_name TEXT NOT NULL,spec TEXT NOT NULL,version INTEGER NOT NULL) STRICT; ';
    for i:=0 to Models.Count-1 do
    begin
      Model:=Models.Objects[i];ViewName:=Model.Get('table','');Collection:=Model.Get('collection','');
      Fields:=TJSONArray(Model.Find('fields'));Managed:=TJSONArray(Model.Find('managed'));Spec:=Model.AsJSON;
      TableName:='';SettingsText:='';
      for j:=0 to High(Registry) do if Registry[j][0]=Collection then
      begin TableName:=Registry[j][1];SettingsText:=Registry[j][2];Break;end;
      Fresh:=TableName='';
      if Fresh then
      begin
        Hash:=NameHash(Collection);TableName:=Candidate(Collection,Hash);
        while Used.IndexOf(TableName)>=0 do begin Inc(Hash);TableName:=Candidate(Collection,Hash);end;
        Used.Add(TableName);
        if HasObject(TableName) then
        begin Storage:=ColumnStorage(Db,TableName);ValidateUnique(Db,Model,TableName);end
        else Storage:='blob';
        Sql:=Sql+CreateCollectionSql(Collection,TableName,Storage,True);
      end
      else
      begin
        ValidateUnique(Db,Model,TableName);
        Storage:=ColumnStorage(Db,TableName);Settings:=TJSONObject(GetJSON(SettingsText));
        try
          if (Settings.Get('cappedSize',Int64(0))<>0) or (Settings.Get('cappedDocuments',Int64(0))<>0) then
            raise Exception.Create('Capped domain collections are unsupported');
          if (Settings.Get('storage','')<>'') and (Settings.Get('storage','')<>IfThen(Storage='blob','jsonb','')) then
            raise Exception.Create('Collection storage metadata disagrees with its column');
        finally Settings.Free;end;
      end;
      Sql:=Sql+UniqueIndexScript(Db,Model,TableName);
      Tables.Values[ViewName]:=TableName;
      Existing:='';
      for j:=0 to High(Objects) do if SameText(Objects[j][0],ViewName) then Existing:=Objects[j][1];
      if Existing<>'' then
      begin
        Found:=False;
        for j:=0 to High(Owner) do if (Owner[j][0]=ViewName) and (Owner[j][1]=TableName) then Found:=True;
        if (Existing<>'view') or not Found then raise Exception.Create('Refusing to replace an unowned model object');
      end;
      Custom:=nil;
      if Existing='view' then Custom:=Db.Query('SELECT sql FROM sqlite_master WHERE type=''trigger'' AND tbl_name='+Q(ViewName)+
        ' AND substr(name,1,4)<>''_wl_'' AND sql IS NOT NULL ORDER BY name;');
      if Existing='view' then Sql:=Sql+'DROP VIEW '+Ident(ViewName)+'; ';
      Columns:='';Roots:=TStringList.Create;
      try
        Roots.Sorted:=True;Roots.Duplicates:=dupIgnore;Roots.CaseSensitive:=True;
        for j:=0 to Fields.Count-1 do if Fields.Objects[j].Get('path','')<>'' then Roots.Add(RootOf(Fields.Objects[j].Get('path','')));
        for j:=0 to Managed.Count-1 do Roots.Add(RootOf(Managed.Strings[j]));
        Body:='CREATE VIEW '+Ident(ViewName)+' AS SELECT ';
        for j:=0 to Fields.Count-1 do
        begin
          Field:=Fields.Objects[j];Root:=Field.Get('path','');
          if Field.Get('kind','')='extra' then
          begin
            if Root='' then
            begin
              ReadExpr:='json_remove(json('+Ident(DocCol)+'),''$."$s"''';
              for k:=0 to Roots.Count-1 do ReadExpr:=ReadExpr+','+Q(JsonPath(Roots[k]));
              ReadExpr:=ReadExpr+')';
            end
            else
            begin
              if not (Field.Find('exclude') is TJSONArray) then raise Exception.Create('Missing nested remainder exclusions');
              ReadExpr:='CASE WHEN json_type('+Ident(DocCol)+','+Q(JsonPath(Root))+')=''object'' THEN json_remove('+Expr(Root);
              for k:=0 to TJSONArray(Field.Find('exclude')).Count-1 do
                ReadExpr:=ReadExpr+','+Q(JsonPath(TJSONArray(Field.Find('exclude')).Strings[k]));
              ReadExpr:=ReadExpr+') ELSE ''{}'' END';
            end;
          end
          else
          begin
            ReadExpr:=Expr(Root);
            if Field.Get('kind','')='date' then ReadExpr:='CASE WHEN json_type('+Ident(DocCol)+','+Q(JsonPath(Root))+') IN (''integer'',''real'') THEN '+
              'COALESCE(strftime(''%Y-%m-%dT%H:%M:%fZ'','+ReadExpr+'/1000.0,''unixepoch''),CAST('+ReadExpr+' AS TEXT)) ELSE '+ReadExpr+' END';
            if Field.Find('default').JSONType<>jtNull then
              if Field.Find('default').JSONType=jtString then ReadExpr:='COALESCE('+ReadExpr+','+Q(Field.Find('default').AsString)+')'
              else ReadExpr:='COALESCE('+ReadExpr+','+Field.Find('default').AsJSON+')';
          end;
          if j>0 then begin Body:=Body+',';Columns:=Columns+',';end;
          Body:=Body+ReadExpr+' AS '+Ident(Field.Get('name',''));
          Incoming:='NEW.'+Ident(Field.Get('name',''));
          // JSON expressions carry SQLite's subtype through NEW. These projected
          // columns are TEXT; strip that subtype before wrapping patch JSON.
          if (Field.Get('kind','')='json') or (Field.Get('kind','')='extra') then Incoming:='('+Incoming+'||'+Q('')+')';
          Columns:=Columns+Q(Field.Get('name',''))+','+Incoming;
        end;
        Sql:=Sql+Body+',NULL AS _wl_source FROM '+Ident(TableName)+'; ';
      finally FreeAndNil(Roots);end;
      Sql:=Sql+'CREATE INDEX IF NOT EXISTS '+Ident('_wl_'+ViewName+'_id')+' ON '+Ident(TableName)+'('+Expr('_id')+'); '+
        'CREATE TRIGGER '+Ident('_wl_'+ViewName+'_i')+' INSTEAD OF INSERT ON '+Ident(ViewName)+' BEGIN '+
        ReferenceChecks(Model,'wl_model(COALESCE(NEW._wl_source,''''),json_object('+Columns+'),'+Q(Spec)+',''insert'')',Tables)+
        UniqueChecks(Model,'wl_model(COALESCE(NEW._wl_source,''''),json_object('+Columns+'),'+Q(Spec)+',''insert'')','','')+
        'INSERT INTO '+Ident(TableName)+'('+Ident(DocCol)+') VALUES('+Wrapped('wl_model(COALESCE(NEW._wl_source,''''),json_object('+Columns+'),'+Q(Spec)+',''insert'')')+'); END; ';
      for j:=0 to Fields.Count-1 do
      begin
        Field:=Fields.Objects[j];Root:=Field.Get('name','');
        Incoming:='NEW.'+Ident(Root);
        if (Field.Get('kind','')='json') or (Field.Get('kind','')='extra') then Incoming:='('+Incoming+'||'+Q('')+')';
        Sql:=Sql+'CREATE TRIGGER '+Ident('_wl_'+ViewName+'_u_'+Root)+' INSTEAD OF UPDATE OF '+Ident(Root)+' ON '+Ident(ViewName)+' BEGIN '+
          ColumnReferenceChecks(Model,Root,'(SELECT wl_model(json('+Ident(DocCol)+'),json_object('+Q(Root)+','+Incoming+'),'+Q(Spec)+',''update'') FROM '+Ident(TableName)+' WHERE '+Expr('_id')+'=OLD.id)',Tables)+
          UniqueChecks(Model,'(SELECT wl_model(json('+Ident(DocCol)+'),json_object('+Q(Root)+','+Incoming+'),'+Q(Spec)+',''update'') FROM '+Ident(TableName)+' WHERE '+Expr('_id')+'=OLD.id)','OLD.id',Root)+
          'UPDATE '+Ident(TableName)+' SET '+Ident(DocCol)+'='+Wrapped('wl_model(json('+Ident(DocCol)+'),json_object('+Q(Root)+','+Incoming+'),'+Q(Spec)+',''update'')')+
          ' WHERE '+Expr('_id')+'=OLD.id; END; ';
      end;
      Sql:=Sql+'CREATE TRIGGER '+Ident('_wl_'+ViewName+'_source')+' INSTEAD OF UPDATE OF _wl_source ON '+Ident(ViewName)+' BEGIN SELECT RAISE(ABORT,''Read-only source seed''); END; '+
        'INSERT OR REPLACE INTO _wl_models VALUES('+Q(ViewName)+','+Q(TableName)+','+Q(Spec)+',1); ';
      for j:=0 to High(Custom) do DeferredCustom:=DeferredCustom+Custom[j][0]+'; ';
    end;
    // Every physical root name is known before generating cascade predicates.
    for i:=0 to Models.Count-1 do
    begin
      ViewName:=Models.Objects[i].Get('table','');TableName:=Tables.Values[ViewName];
      Sql:=Sql+'CREATE TRIGGER '+Ident('_wl_'+ViewName+'_d')+' INSTEAD OF DELETE ON '+Ident(ViewName)+' BEGIN '+
        DeleteCascades(Models,ViewName,Tables)+'DELETE FROM '+Ident(TableName)+' WHERE '+Expr('_id')+'=OLD.id; END; ';
    end;
    Result:=Sql+DeferredCustom+RelationScript(Db,Tables)+PrivateScript(Db,Tables)+'COMMIT;';
  finally Tables.Free;Roots.Free;Used.Free;Models.Free;end;
end;
function InstallRootModels(Db:TWLDb):Boolean;
var Sql:string;
begin
  Result:=False;
  try
    Sql:=RootModelScript(Db);Result:=Db.Exec(Sql);
    if not Result then Db.Exec('ROLLBACK;');
  except Result:=False;end;
end;
end.
