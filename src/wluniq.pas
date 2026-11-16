unit wluniq;
{$mode objfpc}{$H+}
interface
uses SysUtils,fpjson,wldb;
function UniqueChecks(Model:TJSONObject;const Document,ExcludeId,ChangedColumn:string):string;
procedure ValidateUnique(Db:TWLDb;Model:TJSONObject;const TableName:string);
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
end.
