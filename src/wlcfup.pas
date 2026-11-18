unit wlcfup;
{$mode objfpc}{$H+}
interface
uses SysUtils,wldb;
function EnsureSettingsColumn(Db:TWLDb):Boolean;
function EnsureFieldPolicyColumns(Db:TWLDb):Boolean;
function EnsureDropdownColumn(Db:TWLDb):Boolean;
function EnsureChecklistDeadlineColumns(Db:TWLDb):Boolean;
function EnsureDeleteMarkers(Db:TWLDb):Boolean;
function EnsureListCollapseColumn(Db:TWLDb):Boolean;
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

function EnsureDropdownColumn(Db:TWLDb):Boolean;
var Rows,Data:TWLRows;Found:Boolean;
  function Inspect:Boolean;
  var j:Integer;
  begin
    Result:=False;Found:=False;Rows:=Db.Query('PRAGMA table_info(custom_fields);');
    for j:=0 to High(Rows) do if Rows[j][1]='dropdownItemsPresent' then
    begin
      Found:=True;
      if (UpperCase(Rows[j][2])<>'INTEGER') or (Rows[j][3]<>'1') or
        (Rows[j][4]<>'0') or (Rows[j][5]<>'0') then Exit;
      Data:=Db.Query('SELECT count(*) FROM custom_fields WHERE dropdownItemsPresent IS NULL OR '+
        'typeof(dropdownItemsPresent)<>''integer'' OR dropdownItemsPresent NOT IN (0,1);');
      Exit((Length(Data)=1) and (Data[0][0]='0'));
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
  if Found then Exit(True);
  if not Db.Exec('BEGIN IMMEDIATE; ALTER TABLE custom_fields ADD COLUMN dropdownItemsPresent '+
    'INTEGER NOT NULL DEFAULT 0 CHECK(dropdownItemsPresent IN (0,1)); COMMIT;') then Db.Exec('ROLLBACK;');
  Result:=Inspect and Found;
end;

function EnsureNullableTextColumns(Db:TWLDb;const Tables,Columns:array of string):Boolean;
var Sql:string;
  function Inspect(out AlterSql:string):Boolean;
  var TableName,ColumnName:string;Rows:TWLRows;Row:TWLRow;Found:Boolean;
  begin
    AlterSql:='';
    for TableName in Tables do
    begin
      Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name='+QuotedStr(TableName)+';');
      if Length(Rows)=0 then Continue;
      if (Length(Rows)<>1) or (Rows[0][0]<>'table') then Exit(False);
      Rows:=Db.Query('PRAGMA table_info('+TableName+');');
      if Length(Rows)=0 then Exit(False);
      for ColumnName in Columns do
      begin
        Found:=False;
        for Row in Rows do if SameText(Row[1],ColumnName) then
        begin
          if (UpperCase(Row[2])<>'TEXT') or (Row[3]<>'0') or (Row[4]<>'') or (Row[5]<>'0') then Exit(False);
          Found:=True;
        end;
        if not Found then AlterSql:=AlterSql+'ALTER TABLE '+TableName+' ADD COLUMN '+ColumnName+' TEXT; ';
      end;
    end;
    Result:=True;
  end;
begin
  if not Inspect(Sql) then Exit(False);
  if Sql='' then Exit(True);
  if not Db.Exec('BEGIN IMMEDIATE; '+Sql+'COMMIT;') then Db.Exec('ROLLBACK;');
  Result:=Inspect(Sql) and (Sql='');
end;
function EnsureChecklistDeadlineColumns(Db:TWLDb):Boolean;
begin
  Result:=EnsureNullableTextColumns(Db,['checklists','checklist_items'],['dueAt']);
end;

function EnsureDeleteMarkers(Db:TWLDb):Boolean;
begin
  Result:=EnsureNullableTextColumns(Db,['lists','cards'],['deletedAt','deletedBy','deleteBatchId']);
end;
function EnsureListCollapseColumn(Db:TWLDb):Boolean;
var Rows:TWLRows;Row:TWLRow;Found:Boolean;
  function Inspect:Boolean;
  begin
    Found:=False;
    Rows:=Db.Query('PRAGMA table_info(lists);');
    if Length(Rows)=0 then Exit(False);
    for Row in Rows do if SameText(Row[1],'collapsed') then
    begin
      Found:=True;
      Exit((UpperCase(Row[2])='INTEGER') and (Row[3]='0') and (Row[4]='') and (Row[5]='0'));
    end;
    Result:=True;
  end;
begin
  if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))>0 then Exit(False);
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''lists'';');
  if Length(Rows)=0 then Exit(True);
  if (Length(Rows)<>1) or (Rows[0][0]<>'table') or not Inspect then Exit(False);
  if Found then Exit(True);
  if not Db.Exec('BEGIN IMMEDIATE; ALTER TABLE lists ADD COLUMN collapsed INTEGER '+
    'CHECK(collapsed IN (0,1)); COMMIT;') then Db.Exec('ROLLBACK;');
  Result:=Inspect and Found;
end;
end.
