unit wlcfspec;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses SysUtils,fpjson,wlsjson,wldb,wlcfjson;
function SettingsInput(Value:TJSONData;out Settings:TJSONObject):Boolean;
function SettingsLiteral(Settings:TJSONObject;const Name:string):string;
function SettingsRemainder(Settings:TJSONObject):string;
function ReadDefinition(Db:TWLDb;const Identity:string):TJSONObject;
function BoardDefinitionAdminRequired(Db:TWLDb;const BoardId:string):Boolean;
implementation
function Utf16Length(const Text:string):Integer;
var i,N:Integer;B:Byte;
begin
  i:=1;Result:=0;
  while i<=Length(Text) do
  begin
    B:=Ord(Text[i]);N:=1;
    if B>=$f0 then begin N:=4;Inc(Result);end
    else if B>=$e0 then N:=3 else if B>=$c0 then N:=2;
    Inc(Result);Inc(i,N);
  end;
end;
function SettingsInput(Value:TJSONData;out Settings:TJSONObject):Boolean;
const Strings:array[0..5] of string=('currencyCode','stringtemplateFormat','stringtemplateSeparator',
  'jiraTimeField','jiraEstimateFieldId','jiraEstimateUnit');
var Data:TJSONData;Text:string;i,j:Integer;
begin
  Result:=False;Settings:=nil;
  try
    try
      if Value=nil then Settings:=TJSONObject.Create
      else if Value is TJSONObject then Settings:=TJSONObject(Value.Clone)
      else if Value.JSONType=jtString then Settings:=ExactObject(Value.AsString)
      else Exit;
      // Reuse strict recursive UTF-8, key, finite-number and depth validation.
      TypedDocument('{"settings":'+Settings.AsJSON+'}','','{}');
      // Managed dropdown-array creation needs an explicit presence contract.
      if Settings.Find('dropdownItems')<>nil then Exit;
      for i:=0 to High(Strings) do
      begin
        Data:=Settings.Find(Strings[i]);if Data=nil then Continue;
        if Data.JSONType<>jtString then Exit;
        Text:=Data.AsString;if Pos(#0,Text)>0 then Exit;
        if Strings[i]='jiraTimeField' then
          if (Text<>'original') and (Text<>'remaining') then Exit;
        if Strings[i]='jiraEstimateFieldId' then
        begin
          if (Copy(Text,1,12)<>'customfield_') or (Length(Text)<13) or (Length(Text)>32) then Exit;
          for j:=13 to Length(Text) do if not (Text[j] in ['0'..'9']) then Exit;
        end;
        if (Strings[i]='jiraEstimateUnit') and (Utf16Length(Text)>80) then Exit;
      end;
      Result:=True;
    except Result:=False;end;
  finally if not Result then FreeAndNil(Settings);end;
end;
function SettingsLiteral(Settings:TJSONObject;const Name:string):string;
var Value:TJSONData;
begin
  Value:=Settings.Find(Name);if Value=nil then Exit('NULL');Result:=QuotedStr(Value.AsString);
end;
function SettingsRemainder(Settings:TJSONObject):string;
var CopyValue:TJSONObject;
begin
  CopyValue:=TJSONObject(Settings.Clone);
  try
    CopyValue.Delete('currencyCode');CopyValue.Delete('stringtemplateFormat');CopyValue.Delete('stringtemplateSeparator');
    Result:=QuotedStr(CopyValue.AsJSON);
  finally CopyValue.Free;end;
end;
function DefinitionSettings(const Stored:string;const Columns,Nulls:array of string):TJSONObject;
const Keys:array[0..2] of string=('currencyCode','stringtemplateFormat','stringtemplateSeparator');
var i:Integer;
begin
  Result:=ExactObject(Stored);
  try
    for i:=0 to High(Keys) do
    begin
      if Result.Find(Keys[i])<>nil then raise Exception.Create('Shadowed setting');
      if Nulls[i]='0' then Result.Add(Keys[i],Columns[i]);
    end;
    if Result.Find('dropdownItems')<>nil then raise Exception.Create('Shadowed dropdown');
  except Result.Free;raise;end;
end;
type
  TDefinitionScan=class
    Shared,SeenHeader,AdminRequired:Boolean;
    procedure ReadRow(const Row:TWLRow);
  end;
procedure TDefinitionScan.ReadRow(const Row:TWLRow);
var Doc:TJSONObject;Flag:TJSONData;Width:Integer;
begin
  Width:=11;if Shared then Width:=3;
  if not SeenHeader then
  begin
    if (Length(Row)<>Width) or (Row[0]<>'ok') then raise Exception.Create('Missing definition batch');
    SeenHeader:=True;Exit;
  end;
  if Length(Row)<>Width then raise Exception.Create('Invalid definition batch');
  if Shared then
  begin
    if Row[1]<>'1' then raise Exception.Create('Ambiguous definition');
    // Inspect storage truth before JSON Date/special-double null conversion.
    Doc:=ExactObject(PlainDocument(Row[2]));
    try
      Flag:=Doc.Find('adminOnly');
      if (Flag<>nil) and (Flag.JSONType<>jtNull) then
      begin
        if Flag.JSONType<>jtBoolean then raise Exception.Create('Invalid definition flag');
        AdminRequired:=AdminRequired or Flag.AsBoolean;
      end;
    finally Doc.Free;end;
  end
  else
  begin
    if Row[9]<>'1' then raise Exception.Create('Ambiguous definition');
    if (Row[10]<>'integer') or ((Row[1]<>'0') and (Row[1]<>'1')) then
      raise Exception.Create('Invalid definition flag');
    Doc:=DefinitionSettings(Row[2],[Row[3],Row[4],Row[5]],[Row[6],Row[7],Row[8]]);
    Doc.Free;AdminRequired:=AdminRequired or (Row[1]='1');
  end;
end;
function BoardDefinitionAdminRequired(Db:TWLDb;const BoardId:string):Boolean;
var Rows:TWLRows;Name,Binding,Match,Sql,Kind:string;Reader:TDefinitionScan;
begin
  Result:=False;
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''custom_fields'';');
  if Length(Rows)<>1 then raise Exception.Create('Missing definition source');
  Kind:=Rows[0][0];
  if Kind='view' then
  begin
    Rows:=Db.Query('SELECT m.table_name FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name '+
      'WHERE m.name=''custom_fields'' AND c.name=''customFields'';');
    if Length(Rows)<>1 then raise Exception.Create('Missing definition ownership');
    Name:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
    Binding:='(SELECT count(*) FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name '+
      'WHERE m.name=''custom_fields'' AND c.name=''customFields'')=1 AND '+
      '(SELECT count(*) FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name '+
      'WHERE m.name=''custom_fields'' AND c.name=''customFields'' AND m.table_name='+QuotedStr(Rows[0][0])+')=1';
    // Preserve quoted-text lookup semantics without CAST comparison affinity.
    Match:=' FROM '+Name+' s WHERE json_extract(s._ferretdb_sjson,''$."_id"'')=(CAST(v.id AS TEXT)||'''')';
    Sql:='SELECT CASE WHEN '+Binding+' THEN ''ok'' ELSE json(''Stale definition source'') END,''0'','''' '+
      'UNION ALL SELECT v.id,(SELECT count(*)'+Match+'),(SELECT json(s._ferretdb_sjson)'+Match+' LIMIT 1) '+
      'FROM (SELECT DISTINCT f.id FROM custom_fields f JOIN custom_field_boards x ON x.customFieldId=f.id '+
      'WHERE x.boardId='+QuotedStr(BoardId)+') v;';
  end
  else if Kind='table' then
  begin
    Sql:='SELECT ''ok'','''','''','''','''','''','''','''','''','''','''' UNION ALL '+
      'SELECT f.id,f.adminOnly,f.settings_json,f.currencyCode,f.stringtemplateFormat,f.stringtemplateSeparator,'+
      'f.currencyCode IS NULL,f.stringtemplateFormat IS NULL,f.stringtemplateSeparator IS NULL,'+
      '(SELECT count(*) FROM custom_fields q WHERE q.id=f.id),typeof(f.adminOnly) FROM custom_fields f '+
      'WHERE f.id IN (SELECT customFieldId FROM custom_field_boards WHERE boardId='+QuotedStr(BoardId)+');';
  end else raise Exception.Create('Invalid definition source');
  Reader:=TDefinitionScan.Create;
  try
    Reader.Shared:=Kind='view';
    if not Db.Scan(Sql,@Reader.ReadRow) or not Reader.SeenHeader then
      raise Exception.Create('Invalid definition batch');
    Result:=Reader.AdminRequired;
  finally Reader.Free;end;
end;
function ReadDefinition(Db:TWLDb;const Identity:string):TJSONObject;
const Flags:array[0..6] of string=('showOnCard','automaticallyOnCard','alwaysOnCard','showLabelOnMiniCard','showSumAtTopOfList','readOnly','adminOnly');
var Rows,Children:TWLRows;Settings:TJSONObject;Boards,Items:TJSONArray;TypeName:string;i:Integer;
begin
  Result:=nil;Settings:=nil;Boards:=nil;Items:=nil;
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''custom_fields'';');
  if Length(Rows)<>1 then raise Exception.Create('Missing definition source');
  TypeName:=Rows[0][0];
  if TypeName='view' then Exit(DocumentJson(ReadModelSjson(Db,'custom_fields','customFields',Identity)));
  if TypeName<>'table' then raise Exception.Create('Invalid definition source');
  Rows:=Db.Query('SELECT id,name,type,showOnCard,automaticallyOnCard,alwaysOnCard,showLabelOnMiniCard,showSumAtTopOfList,'+
    'readOnly,adminOnly,createdAt,modifiedAt,currencyCode,stringtemplateFormat,stringtemplateSeparator,settings_json,'+
    'currencyCode IS NULL,stringtemplateFormat IS NULL,stringtemplateSeparator IS NULL,dropdownItemsPresent,typeof(dropdownItemsPresent) FROM custom_fields WHERE id='+QuotedStr(Identity)+';');
  if Length(Rows)=0 then Exit;
  if (Length(Rows)<>1) or (Length(Rows[0])<>21) then raise Exception.Create('Ambiguous definition');
  try
    try
      Settings:=DefinitionSettings(Rows[0][15],[Rows[0][12],Rows[0][13],Rows[0][14]],
        [Rows[0][16],Rows[0][17],Rows[0][18]]);
      Children:=Db.Query('SELECT id,name FROM custom_field_dropdown_items WHERE customFieldId='+QuotedStr(Identity)+' ORDER BY sort,id;');
      if (Rows[0][20]<>'integer') or ((Rows[0][19]<>'0') and (Rows[0][19]<>'1')) then raise Exception.Create('Invalid dropdown presence');
      if (Length(Children)>0) or (Rows[0][19]='1') then
      begin
        Items:=TJSONArray.Create;
        for i:=0 to High(Children) do Items.Add(TJSONObject.Create(['_id',Children[i][0],'name',Children[i][1]]));
        Settings.Add('dropdownItems',Items);Items:=nil;
      end;
      Result:=TJSONObject.Create(['_id',Rows[0][0],'name',Rows[0][1],'type',Rows[0][2]]);
      for i:=0 to High(Flags) do Result.Add(Flags[i],StrToIntDef(Rows[0][3+i],0)<>0);
      if Rows[0][10]<>'' then Result.Add('createdAt',Rows[0][10]);
      if Rows[0][11]<>'' then Result.Add('modifiedAt',Rows[0][11]);
      Result.Add('settings',Settings);Settings:=nil;
      Boards:=TJSONArray.Create;Children:=Db.Query('SELECT boardId FROM custom_field_boards WHERE customFieldId='+QuotedStr(Identity)+' ORDER BY boardId;');
      for i:=0 to High(Children) do Boards.Add(Children[i][0]);Result.Add('boardIds',Boards);Boards:=nil;
    except FreeAndNil(Result);raise;end;
  finally Items.Free;Boards.Free;Settings.Free;end;
end;
end.
