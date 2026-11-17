unit wlcfup;
{$mode objfpc}{$H+}
interface
uses SysUtils,wldb;
function EnsureSettingsColumn(Db:TWLDb):Boolean;
function EnsureFieldPolicyColumns(Db:TWLDb):Boolean;
implementation
const ValidSettings='CASE WHEN json_valid(settings_json) THEN json_type(settings_json)=''object'' AND '+
  'json_type(settings_json,''$.currencyCode'') IS NULL AND json_type(settings_json,''$.stringtemplateFormat'') IS NULL AND '+
  'json_type(settings_json,''$.stringtemplateSeparator'') IS NULL AND json_type(settings_json,''$.dropdownItems'') IS NULL ELSE 0 END';
function EnsureSettingsColumn(Db:TWLDb):Boolean;
var Rows:TWLRows;i:Integer;Found:Boolean;
  function ValidColumn:Boolean;
  var j:Integer;Data:TWLRows;
  begin
    Result:=False;
    for j:=0 to High(Rows) do if Rows[j][1]='settings_json' then
    begin
      if (UpperCase(Rows[j][2])<>'TEXT') or (Rows[j][3]<>'1') or (Rows[j][4]<>'''{}''') or (Rows[j][5]<>'0') then Exit;
      Data:=Db.Query('SELECT count(*) FROM custom_fields WHERE NOT ('+ValidSettings+');');
      Exit((Length(Data)=1) and (Data[0][0]='0'));
    end;
  end;
begin
  Result:=False;
  if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))>0 then Exit;
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''custom_fields'';');
  if Length(Rows)=0 then Exit(True); // An unrelated minimal legacy store owns no definitions.
  if (Length(Rows)<>1) or (Rows[0][0]<>'table') then Exit;
  Rows:=Db.Query('PRAGMA table_info(custom_fields);');Found:=False;
  for i:=0 to High(Rows) do if Rows[i][1]='settings_json' then Found:=True;
  if Found then Exit(ValidColumn);
  if not Db.Exec('BEGIN IMMEDIATE; ALTER TABLE custom_fields ADD COLUMN settings_json TEXT NOT NULL DEFAULT ''{}'' CHECK('+ValidSettings+'); COMMIT;') then
    Db.Exec('ROLLBACK;');
  // A concurrent opener may have added the same valid column while this one waited.
  Rows:=Db.Query('PRAGMA table_info(custom_fields);');Result:=ValidColumn;
end;
function EnsureFieldPolicyColumns(Db:TWLDb):Boolean;
const Names:array[0..1] of string=('readOnly','adminOnly');
var Rows,Data:TWLRows;i:Integer;Found:array[0..1] of Boolean;Sql:string;
  function Inspect:Boolean;
  var n,k:Integer;
  begin
    Result:=False;Rows:=Db.Query('PRAGMA table_info(custom_fields);');
    for n:=0 to High(Names) do
    begin
      Found[n]:=False;
      for k:=0 to High(Rows) do if Rows[k][1]=Names[n] then
      begin
        Found[n]:=True;
        if (UpperCase(Rows[k][2])<>'INTEGER') or (Rows[k][3]<>'1') or (Rows[k][4]<>'0') or (Rows[k][5]<>'0') then Exit;
        Data:=Db.Query('SELECT count(*) FROM custom_fields WHERE '+Names[n]+' IS NULL OR typeof('+Names[n]+')<>''integer'' OR '+Names[n]+' NOT IN (0,1);');
        if (Length(Data)<>1) or (Data[0][0]<>'0') then Exit;
      end;
    end;
    Result:=True;
  end;
begin
  Result:=False;
  if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))>0 then Exit;
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''custom_fields'';');
  if Length(Rows)=0 then Exit(True);
  if (Length(Rows)<>1) or (Rows[0][0]<>'table') then Exit;
  if not Inspect then Exit;
  Sql:='';for i:=0 to High(Names) do if not Found[i] then
    Sql:=Sql+'ALTER TABLE custom_fields ADD COLUMN '+Names[i]+' INTEGER NOT NULL DEFAULT 0 CHECK('+Names[i]+' IN (0,1)); ';
  if Sql='' then Exit(True);
  if not Db.Exec('BEGIN IMMEDIATE; '+Sql+'COMMIT;') then Db.Exec('ROLLBACK;');
  Result:=Inspect and Found[0] and Found[1];
end;

end.
