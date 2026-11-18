unit wlrel;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,fpjson,jsonparser,wldb,wlmodels;
function RelationScript(Db:TWLDb;Tables:TStrings):string;
implementation
function Q(const S:string):string;
begin Result:=QuotedStr(S);end;
function Id(const S:string):string;
begin Result:='"'+StringReplace(S,'"','""',[rfReplaceAll])+'"';end;
function Path(const S:string):string;
var Parts:TStringArray;i:Integer;
begin
  Parts:=S.Split('.');Result:='$';
  for i:=0 to High(Parts) do Result:=Result+'."'+Parts[i]+'"';
end;
function RelationScript(Db:TWLDb;Tables:TStrings):string;
var Specs:TJSONArray;Spec,Field:TJSONObject;Fields:TJSONArray;
  Objects,Owners,Custom:TWLRows;Name,TableName,ParentKey,ReadExpr,Columns,
  OldKeys,Values,Body,Existing,Wrapped,Doc,FindParent,Seed,ColumnName,FieldPath:string;
  i,j,k:Integer;Owned:Boolean;
  function Wrap(const Expression:string):string;
  begin
    Result:='CASE WHEN wl_storage('+Q(TableName)+')=''blob'' THEN jsonb('+Expression+') ELSE '+Expression+' END';
  end;
  function Patch(const Op,PatchValues:string):string;
  var CustomType:string;
  begin
    CustomType:='';
    if (Name='card_custom_field_values') and ((Op='insert') or (Op='update')) then
      CustomType:=',''customCount'',(SELECT count(*) FROM custom_fields WHERE id=NEW.customFieldId),''customType'',(SELECT CASE WHEN count(*)=1 THEN min(type) ELSE NULL END FROM custom_fields WHERE id=NEW.customFieldId)';
    Result:='wl_relation(json('+Doc+'),json_object(''op'','+Q(Op)+CustomType+',''old'',json_object('+OldKeys+'),''values'',json('+PatchValues+')),'+Q(Spec.AsJSON)+')';
  end;
begin
  Result:='';Specs:=TJSONArray(GetJSON(RelationJson));
  try
    Objects:=Db.Query('SELECT name,type FROM sqlite_master WHERE type IN (''table'',''view'');');
    Owners:=nil;
    for i:=0 to High(Objects) do if Objects[i][0]='_wl_models' then
      Owners:=Db.Query('SELECT name,table_name FROM _wl_models;');
    Doc:=Id('_ferretdb_sjson');
    for i:=0 to Specs.Count-1 do
    begin
      Spec:=Specs.Objects[i];Name:=Spec.Get('table','');ParentKey:=Spec.Get('parentKey','');
      TableName:=Tables.Values[Spec.Get('parent','')];
      if TableName='' then raise Exception.Create('Missing relation parent collection');
      Fields:=TJSONArray(Spec.Find('fields'));Existing:='';Owned:=False;
      for j:=0 to High(Objects) do if SameText(Objects[j][0],Name) then Existing:=Objects[j][1];
      for j:=0 to High(Owners) do if (Owners[j][0]=Name) and (Owners[j][1]=TableName) then Owned:=True;
      if (Existing<>'') and ((Existing<>'view') or not Owned) then
        raise Exception.Create('Refusing to replace an unowned relation object');
      Custom:=nil;
      if Existing='view' then
      begin
        Custom:=Db.Query('SELECT sql FROM sqlite_master WHERE type=''trigger'' AND tbl_name='+Q(Name)+
          ' AND substr(name,1,4)<>''_wl_'' AND sql IS NOT NULL ORDER BY name;');
        Result:=Result+'DROP VIEW '+Id(Name)+'; ';
      end;
      Body:='CREATE VIEW '+Id(Name)+' AS SELECT json_extract(p.'+Doc+',''$."_id"'') AS '+Id(ParentKey);
      Columns:='';OldKeys:='';
      for j:=0 to Fields.Count-1 do
      begin
        Field:=Fields.Objects[j];ColumnName:=Field.Get('name','');FieldPath:=Field.Get('path','');
        if Spec.Get('scalar',False) then ReadExpr:='e.value'
        else if Name='card_dependencies' then
        begin
          ReadExpr:='CASE WHEN e.type=''object'' THEN json_extract(e.value,'+Q(Path(FieldPath))+')';
          if FieldPath='cardId' then ReadExpr:=ReadExpr+' WHEN e.type=''text'' AND json_extract(p.'+Doc+
            ',''$."$s".p.cardDependencies.i[''||e.key||''].t'')=''string'' THEN e.value';
          ReadExpr:=ReadExpr+' END';
        end
        else ReadExpr:='json_extract(e.value,'+Q(Path(FieldPath))+')';
        Seed:='NEW.'+Id(ColumnName);
        if Field.Find('default').JSONType<>jtNull then
        begin
          if Field.Find('default').JSONType=jtString then Wrapped:=Q(Field.Find('default').AsString)
          else Wrapped:=Field.Find('default').AsJSON;
          ReadExpr:='COALESCE('+ReadExpr+','+Wrapped+')';
          Seed:='COALESCE('+Seed+','+Wrapped+')';
        end;
        Body:=Body+','+ReadExpr+' AS '+Id(ColumnName);
        if Columns<>'' then Columns:=Columns+',';
        Columns:=Columns+Q(ColumnName)+','+Seed;
        for k:=0 to TJSONArray(Spec.Find('keys')).Count-1 do
          if TJSONArray(Spec.Find('keys')).Strings[k]=FieldPath then
          begin
            if OldKeys<>'' then OldKeys:=OldKeys+',';
            OldKeys:=OldKeys+Q(FieldPath)+',OLD.'+Id(ColumnName);
          end;
      end;
      Result:=Result+Body+' FROM '+Id(TableName)+' p,json_each(CASE WHEN json_type(p.'+Doc+','+Q(Path(Spec.Get('path','')))+
        ')=''array'' THEN json_extract(p.'+Doc+','+Q(Path(Spec.Get('path','')))+') ELSE ''[]'' END) e; ';
      FindParent:='json_extract('+Doc+',''$."_id"'')=';
      // INSERT has no OLD context; keep the command's key selector empty.
      Wrapped:=OldKeys;OldKeys:='';
      Result:=Result+'CREATE TRIGGER '+Id('_wl_'+Name+'_i')+' INSTEAD OF INSERT ON '+Id(Name)+' BEGIN '+
        'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM '+Id(TableName)+' WHERE '+FindParent+'NEW.'+Id(ParentKey)+') THEN RAISE(ABORT,''Missing relation parent'') END; '+
        'UPDATE '+Id(TableName)+' SET '+Doc+'='+Wrap(Patch('insert','json_object('+Columns+')'))+' WHERE '+FindParent+'NEW.'+Id(ParentKey)+'; END; ';
      OldKeys:=Wrapped;
      Result:=Result+'CREATE TRIGGER '+Id('_wl_'+Name+'_parent')+' INSTEAD OF UPDATE OF '+Id(ParentKey)+' ON '+Id(Name)+
        ' WHEN NEW.'+Id(ParentKey)+' IS NOT OLD.'+Id(ParentKey)+' BEGIN SELECT RAISE(ABORT,''Immutable relation parent''); END; ';
      Values:='';
      for j:=0 to Fields.Count-1 do
      begin
        ColumnName:=Fields.Objects[j].Get('name','');
        if Values<>'' then Values:=Values+' UNION ALL ';
        Values:=Values+'SELECT '+Q(ColumnName)+' k,NEW.'+Id(ColumnName)+' v WHERE NEW.'+Id(ColumnName)+' IS NOT OLD.'+Id(ColumnName);
      end;
      Values:='(SELECT json_group_object(k,v) FROM ('+Values+'))';
      Result:=Result+'CREATE TRIGGER '+Id('_wl_'+Name+'_u')+' INSTEAD OF UPDATE ON '+Id(Name)+' BEGIN '+
        'UPDATE '+Id(TableName)+' SET '+Doc+'='+Wrap(Patch('update',Values))+
        ' WHERE '+FindParent+'OLD.'+Id(ParentKey)+'; END; ';
      Result:=Result+'CREATE TRIGGER '+Id('_wl_'+Name+'_d')+' INSTEAD OF DELETE ON '+Id(Name)+' BEGIN UPDATE '+Id(TableName)+' SET '+Doc+'='+
        Wrap(Patch('delete','''{}'''))+' WHERE '+FindParent+'OLD.'+Id(ParentKey)+'; END; '+
        'INSERT OR REPLACE INTO _wl_models VALUES('+Q(Name)+','+Q(TableName)+','+Q(Spec.AsJSON)+',1); ';
      for j:=0 to High(Custom) do Result:=Result+Custom[j][0]+'; ';
    end;
  finally Specs.Free;end;
end;
end.
