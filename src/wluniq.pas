unit wluniq;
{$mode objfpc}{$H+}
interface
uses SysUtils,fpjson,wldb;
function UniqueChecks(Model:TJSONObject;const Document,ExcludeId,ChangedColumn:string):string;
procedure ValidateUnique(Db:TWLDb;Model:TJSONObject;const TableName:string);
function UniqueIndexScript(Db:TWLDb;Model:TJSONObject;const TableName:string):string;
implementation
function Id(const S:string):string;
begin Result:='"'+StringReplace(S,'"','""',[rfReplaceAll])+'"';end;
function FieldPath(Model:TJSONObject;const Name:string):string;
var Fields:TJSONArray;i:Integer;
begin
  Fields:=TJSONArray(Model.Find('fields'));
  for i:=0 to Fields.Count-1 do if Fields.Objects[i].Get('name','')=Name then
  begin
    Result:=Fields.Objects[i].Get('path','');
    if (Result='') or (Pos('.',Result)>0) then raise Exception.Create('Unsupported unique-key path');
    Exit;
  end;
  raise Exception.Create('Unknown unique-key column');
end;
function Extract(const Document,Path:string):string;
begin Result:='json_extract(('+Document+'),'+QuotedStr('$."'+Path+'"')+')';end;
function UniqueChecks(Model:TJSONObject;const Document,ExcludeId,ChangedColumn:string):string;
var Keys,Key:TJSONArray;i,j:Integer;Condition,Value,ColumnName:string;Changed:Boolean;
begin
  Result:='';Keys:=TJSONArray(Model.Find('uniqueKeys'));
  for i:=0 to Keys.Count-1 do
  begin
    Key:=TJSONArray(Keys.Items[i]);Condition:='';Changed:=ChangedColumn='';
    for j:=0 to Key.Count-1 do
    begin
      ColumnName:=Key.Strings[j];if ColumnName=ChangedColumn then Changed:=True;
      Value:=Extract(Document,FieldPath(Model,ColumnName));
      if Condition<>'' then Condition:=Condition+' AND ';
      Condition:=Condition+'('+Value+') IS NOT NULL AND '+Id(ColumnName)+' COLLATE BINARY=('+Value+')';
    end;
    if not Changed then Continue;
    if ExcludeId<>'' then Condition:=Condition+' AND id<>('+ExcludeId+')';
    Result:=Result+'SELECT CASE WHEN EXISTS(SELECT 1 FROM '+Id(Model.Get('table',''))+' WHERE '+Condition+
      ') THEN RAISE(ABORT,''Duplicate model key'') END; ';
  end;
end;
procedure ValidateUnique(Db:TWLDb;Model:TJSONObject;const TableName:string);
var Keys,Key:TJSONArray;i,j:Integer;Columns,Condition,Value:string;Rows:TWLRows;
begin
  Keys:=TJSONArray(Model.Find('uniqueKeys'));
  for i:=0 to Keys.Count-1 do
  begin
    Key:=TJSONArray(Keys.Items[i]);Columns:='';Condition:='';
    for j:=0 to Key.Count-1 do
    begin
      Value:=Extract('"_ferretdb_sjson"',FieldPath(Model,Key.Strings[j]));
      if Columns<>'' then begin Columns:=Columns+',';Condition:=Condition+' AND ';end;
      Columns:=Columns+Value+' COLLATE BINARY';Condition:=Condition+Value+' IS NOT NULL';
    end;
    Rows:=Db.Query('SELECT count(*) FROM '+Id(TableName)+' WHERE '+Condition+' GROUP BY '+Columns+' HAVING count(*)>1 LIMIT 1;');
    if Length(Rows)>0 then raise Exception.Create('Existing duplicate model keys require repair');
  end;
end;
function UniqueIndexScript(Db:TWLDb;Model:TJSONObject;const TableName:string):string;
var Keys,Key:TJSONArray;Description:TJSONObject;Owners,Objects:TWLRows;
  i,j:Integer;Name,Columns,DDL,Spec:string;Owned:Boolean;
begin
  Result:='';Keys:=TJSONArray(Model.Find('uniqueKeys'));
  for i:=0 to Keys.Count-1 do
  begin
    Key:=TJSONArray(Keys.Items[i]);if Key.Count=0 then raise Exception.Create('Empty model unique key');
    Name:='_wl_'+TableName+'_uq_'+IntToStr(i);Columns:='';
    for j:=0 to Key.Count-1 do
    begin
      if Columns<>'' then Columns:=Columns+',';
      Columns:=Columns+Extract('"_ferretdb_sjson"',FieldPath(Model,Key.Strings[j]))+' COLLATE BINARY';
    end;
    DDL:='CREATE UNIQUE INDEX '+Id(Name)+' ON '+Id(TableName)+' ('+Columns+')';
    Description:=TJSONObject.Create;
    try
      Description.Add('kind','unique-model-key');Description.Add('columns',Key.Clone);Spec:=Description.AsJSON;
    finally Description.Free;end;
    Owners:=Db.Query('SELECT table_name,spec,version FROM _wl_models WHERE name='+QuotedStr(Name)+';');
    Owned:=(Length(Owners)=1) and (Owners[0][0]=TableName) and (Owners[0][1]=Spec) and (Owners[0][2]='1');
    if (Length(Owners)>0) and not Owned then raise Exception.Create('Incompatible model unique-key owner');
    Objects:=Db.Query('SELECT type,tbl_name,sql FROM sqlite_master WHERE name='+QuotedStr(Name)+';');
    if Length(Objects)>0 then
    begin
      if not Owned or (Length(Objects)<>1) or (Objects[0][0]<>'index') or
        (Objects[0][1]<>TableName) or (Objects[0][2]<>DDL) then
        raise Exception.Create('Refusing incompatible model unique-key index');
    end
    else Result:=Result+DDL+'; ';
    Result:=Result+'INSERT OR REPLACE INTO _wl_models(name,table_name,spec,version) VALUES('+
      QuotedStr(Name)+','+QuotedStr(TableName)+','+QuotedStr(Spec)+',1); ';
  end;
end;

end.
