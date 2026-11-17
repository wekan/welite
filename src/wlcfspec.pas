unit wlcfspec;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses SysUtils,fpjson,wlsjson,wldb,wlcfjson;
function SettingsInput(Value:TJSONData;out Settings:TJSONObject):Boolean;
function SettingsLiteral(Settings:TJSONObject;const Name:string):string;
function SettingsRemainder(Settings:TJSONObject):string;
function ReadDefinition(Db:TWLDb;const Identity:string):TJSONObject;
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
function ReadDefinition(Db:TWLDb;const Identity:string):TJSONObject;
const Flags:array[0..6] of string=('showOnCard','automaticallyOnCard','alwaysOnCard','showLabelOnMiniCard','showSumAtTopOfList','readOnly','adminOnly');
  Keys:array[0..2] of string=('currencyCode','stringtemplateFormat','stringtemplateSeparator');
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
    'currencyCode IS NULL,stringtemplateFormat IS NULL,stringtemplateSeparator IS NULL FROM custom_fields WHERE id='+QuotedStr(Identity)+';');
  if Length(Rows)=0 then Exit;
  if (Length(Rows)<>1) or (Length(Rows[0])<>19) then raise Exception.Create('Ambiguous definition');
  try
    try
      Settings:=ExactObject(Rows[0][15]);
      for i:=0 to High(Keys) do
      begin
        if Settings.Find(Keys[i])<>nil then raise Exception.Create('Shadowed setting');
        if Rows[0][16+i]='0' then Settings.Add(Keys[i],Rows[0][12+i]);
      end;
      if Settings.Find('dropdownItems')<>nil then raise Exception.Create('Shadowed dropdown');
      Children:=Db.Query('SELECT id,name FROM custom_field_dropdown_items WHERE customFieldId='+QuotedStr(Identity)+' ORDER BY sort,id;');
      if Length(Children)>0 then
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
