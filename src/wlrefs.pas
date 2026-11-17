unit wlrefs;
{$mode objfpc}{$H+}
interface
uses SysUtils,Classes,fpjson;
function ReferenceChecks(Model:TJSONObject;const Document:string;Tables:TStrings):string;
function ColumnReferenceChecks(Model:TJSONObject;const ColumnName,Document:string;Tables:TStrings):string;
function DeleteCascades(Models:TJSONArray;const Parent:string;Tables:TStrings):string;
implementation
function Id(const S:string):string;
begin Result:='"'+StringReplace(S,'"','""',[rfReplaceAll])+'"';end;
function DataPath(const Path:string):string;
var Parts:TStringArray;i:Integer;
begin
  Parts:=Path.Split('.');Result:='$';
  for i:=0 to High(Parts) do Result:=Result+'."'+Parts[i]+'"';
end;
function TypePath(const Path:string):string;
var Parts:TStringArray;i:Integer;
begin
  Parts:=Path.Split('.');Result:='$';
  for i:=0 to High(Parts) do Result:=Result+'."$s".p."'+Parts[i]+'"';
  Result:=Result+'.t';
end;
function ValueOf(const Document,Path:string):string;
begin Result:='json_extract(('+Document+'),'+QuotedStr(DataPath(Path))+')';end;
function StringKey(const Document,Path:string):string;
begin
  Result:='COALESCE((json_type(('+Document+'),'+QuotedStr(DataPath(Path))+')=''text'' AND '+
    'json_extract(('+Document+'),'+QuotedStr(TypePath(Path))+')=''string'' AND '+ValueOf(Document,Path)+'<>''''),0)';
end;
function FieldPath(Model:TJSONObject;const ColumnName:string):string;
var Fields:TJSONArray;i:Integer;
begin
  Fields:=TJSONArray(Model.Find('fields'));Result:='';
  for i:=0 to Fields.Count-1 do
    if Fields.Objects[i].Get('name','')=ColumnName then Exit(Fields.Objects[i].Get('path',''));
  raise Exception.Create('Missing foreign-key field');
end;
function Physical(Tables:TStrings;const Model:string):string;
begin
  Result:=Tables.Values[Model];if Result='' then raise Exception.Create('Missing reference collection');
  Result:=Id(Result);
end;
function Check(Model,Ref:TJSONObject;const Document:string;Tables:TStrings):string;
var Path,Value,ParentDoc,ParentValue:string;
begin
  Path:=FieldPath(Model,Ref.Get('column',''));Value:=ValueOf(Document,Path);
  if Ref.Get('key','')<>'id' then raise Exception.Create('Unsupported reference key');
  ParentDoc:='rp._ferretdb_sjson';ParentValue:=ValueOf('wl_plain(json('+ParentDoc+'))','_id');
  Result:='SELECT CASE WHEN ('+Value+') IS NOT NULL AND NOT ('+StringKey(Document,Path)+
    ' AND EXISTS(SELECT 1 FROM '+Physical(Tables,Ref.Get('parent',''))+' rp WHERE '+ValueOf(ParentDoc,'_id')+'=('+Value+') AND '+
    ParentValue+'=('+Value+') AND '+StringKey(ParentDoc,'_id')+')) THEN RAISE(ABORT,''Missing referenced model'') END; ';
end;
function ColumnReferenceChecks(Model:TJSONObject;const ColumnName,Document:string;Tables:TStrings):string;
var Refs:TJSONArray;i:Integer;
begin
  Result:='';Refs:=TJSONArray(Model.Find('foreignKeys'));
  for i:=0 to Refs.Count-1 do
    if Refs.Objects[i].Get('column','')=ColumnName then Result:=Result+Check(Model,Refs.Objects[i],Document,Tables);
end;
function ReferenceChecks(Model:TJSONObject;const Document:string;Tables:TStrings):string;
var Refs:TJSONArray;i:Integer;
begin
  Result:='';Refs:=TJSONArray(Model.Find('foreignKeys'));
  for i:=0 to Refs.Count-1 do Result:=Result+Check(Model,Refs.Objects[i],Document,Tables);
end;
function DeleteCascades(Models:TJSONArray;const Parent:string;Tables:TStrings):string;
var Refs:TJSONArray;i,j:Integer;Ref,Model:TJSONObject;Path,OwnerDoc,ChildDoc,ChildName:string;
begin
  Result:='';OwnerDoc:='dp._ferretdb_sjson';ChildDoc:='dc._ferretdb_sjson';
  for i:=0 to Models.Count-1 do
  begin
    Model:=Models.Objects[i];Refs:=TJSONArray(Model.Find('foreignKeys'));ChildName:=Model.Get('table','');
    for j:=0 to Refs.Count-1 do
    begin
      Ref:=Refs.Objects[j];if Ref.Get('parent','')<>Parent then Continue;
      if (Ref.Get('delete','')<>'CASCADE') or (Ref.Get('key','')<>'id') then raise Exception.Create('Unsupported delete action');
      Path:=FieldPath(Model,Ref.Get('column',''));
      Result:=Result+'DELETE FROM '+Id(ChildName)+' WHERE '+Id(Ref.Get('column',''))+'=OLD.id '+
        'AND EXISTS(SELECT 1 FROM '+Physical(Tables,Parent)+' dp WHERE '+ValueOf(OwnerDoc,'_id')+'=OLD.id AND '+
        ValueOf('wl_plain(json('+OwnerDoc+'))','_id')+'=OLD.id AND '+StringKey(OwnerDoc,'_id')+') '+
        'AND EXISTS(SELECT 1 FROM '+Physical(Tables,ChildName)+' dc WHERE '+ValueOf(ChildDoc,'_id')+'='+Id(ChildName)+'.id AND '+
        ValueOf('wl_plain(json('+ChildDoc+'))',Path)+'=OLD.id AND '+StringKey(ChildDoc,Path)+'); ';
    end;
  end;
end;
end.
