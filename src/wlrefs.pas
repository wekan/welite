unit wlrefs;
{$mode objfpc}{$H+}
interface
uses SysUtils,fpjson;
function ReferenceChecks(Model:TJSONObject;const Document:string):string;
function ColumnReferenceChecks(Model:TJSONObject;const ColumnName,Value:string):string;
function DeleteCascades(Models:TJSONArray;const Parent:string):string;
implementation
function Id(const S:string):string;
begin Result:='"'+StringReplace(S,'"','""',[rfReplaceAll])+'"';end;
function Check(Ref:TJSONObject;const Value:string):string;
begin
  Result:='SELECT CASE WHEN ('+Value+') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM '+
    Id(Ref.Get('parent',''))+' WHERE '+Id(Ref.Get('key',''))+'=('+Value+')) THEN '+
    'RAISE(ABORT,''Missing referenced model'') END; ';
end;
function ColumnReferenceChecks(Model:TJSONObject;const ColumnName,Value:string):string;
var Refs:TJSONArray;i:Integer;
begin
  Result:='';Refs:=TJSONArray(Model.Find('foreignKeys'));
  for i:=0 to Refs.Count-1 do
    if Refs.Objects[i].Get('column','')=ColumnName then Result:=Result+Check(Refs.Objects[i],Value);
end;
function ReferenceChecks(Model:TJSONObject;const Document:string):string;
var Refs,Fields:TJSONArray;i,j:Integer;Path:string;
begin
  Result:='';Refs:=TJSONArray(Model.Find('foreignKeys'));Fields:=TJSONArray(Model.Find('fields'));
  for i:=0 to Refs.Count-1 do
    for j:=0 to Fields.Count-1 do
      if Fields.Objects[j].Get('name','')=Refs.Objects[i].Get('column','') then
      begin
        // All declared root foreign keys currently address flat fields.
        Path:=Fields.Objects[j].Get('path','');
        if (Path='') or (Pos('.',Path)>0) then raise Exception.Create('Unsupported foreign-key path');
        Result:=Result+Check(Refs.Objects[i],'json_extract(('+Document+'),'+QuotedStr('$."'+Path+'"')+')');
      end;
end;
function DeleteCascades(Models:TJSONArray;const Parent:string):string;
var Refs:TJSONArray;i,j:Integer;Ref:TJSONObject;
begin
  Result:='';
  for i:=0 to Models.Count-1 do
  begin
    Refs:=TJSONArray(Models.Objects[i].Find('foreignKeys'));
    for j:=0 to Refs.Count-1 do
    begin
      Ref:=Refs.Objects[j];if Ref.Get('parent','')<>Parent then Continue;
      if Ref.Get('delete','')<>'CASCADE' then raise Exception.Create('Unsupported delete action');
      Result:=Result+'DELETE FROM '+Id(Models.Objects[i].Get('table',''))+' WHERE '+
        Id(Ref.Get('column',''))+'=OLD.'+Id(Ref.Get('key',''))+'; ';
    end;
  end;
end;
end.
