unit wlcfjson;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses SysUtils,fpjson,wldb,wlsjson;
function JsonDate(Ms:Int64):TJSONData;
function DocumentJson(const Document:string):TJSONObject;
function ReadModelSjson(Db:TWLDb;const Model,Collection,Identity:string):string;
function CustomFieldsJson(const Document:string):TJSONArray;
function ReadCustomFields(Db:TWLDb;const CardId:string):TJSONArray;
procedure ValidateBoardCustomFields(Db:TWLDb;const BoardId:string);
implementation
procedure Invalid;
begin raise Exception.Create('Invalid custom-field source');end;
function Field(Value:TJSONData;const Name:string):TJSONData;
begin
  if Value is TJSONObject then Result:=TJSONObject(Value).Find(Name) else Result:=nil;
end;
function Pad(Value:Int64;Width:Integer):string;
begin
  Result:=IntToStr(Value);while Length(Result)<Width do Result:='0'+Result;
end;
function JsonDate(Ms:Int64):TJSONData;
var Days,Rest,Z,Era,YearEra,DayYear,MarchMonth,Year,Month,Day:Int64;YearText,Text:string;
begin
  // JSON.stringify(Date) uses TimeClip and proleptic Gregorian UTC, including
  // year zero and signed six-digit years beyond 0000..9999.
  if (Ms< -8640000000000000) or (Ms>8640000000000000) then Exit(TJSONNull.Create);
  Days:=Ms div 86400000;Rest:=Ms mod 86400000;
  if Rest<0 then begin Dec(Days);Inc(Rest,86400000);end;
  Z:=Days+719468;
  if Z>=0 then Era:=Z div 146097 else Era:=(Z-146096) div 146097;
  Z:=Z-Era*146097;
  YearEra:=(Z-Z div 1460+Z div 36524-Z div 146096) div 365;
  Year:=YearEra+Era*400;DayYear:=Z-(365*YearEra+YearEra div 4-YearEra div 100);
  MarchMonth:=(5*DayYear+2) div 153;Day:=DayYear-(153*MarchMonth+2) div 5+1;
  if MarchMonth<10 then Month:=MarchMonth+3 else Month:=MarchMonth-9;
  if Month<=2 then Inc(Year);
  if Year<0 then YearText:='-'+Pad(-Year,6)
  else if Year>9999 then YearText:='+'+Pad(Year,6) else YearText:=Pad(Year,4);
  Text:=YearText+'-'+Pad(Month,2)+'-'+Pad(Day,2)+'T'+Pad(Rest div 3600000,2)+':'+
    Pad((Rest div 60000) mod 60,2)+':'+Pad((Rest div 1000) mod 60,2)+'.'+Pad(Rest mod 1000,3)+'Z';
  Result:=TJSONString.Create(Text);
end;
function JsonValue(Value,Schema:TJSONData):TJSONData;
var Kind:string;Ms:Int64;i:Integer;Items,Props:TJSONData;ArrayValue:TJSONArray;ObjectValue:TJSONObject;
begin
  if not (Schema is TJSONObject) then Invalid;
  Kind:=TJSONObject(Schema).Get('t','');
  if Kind='date' then
  begin
    if not TryStrToInt64(Value.AsJSON,Ms) then Invalid;
    Exit(JsonDate(Ms));
  end;
  // SJSON represents non-finite BSON doubles as strings; JSON.stringify emits null.
  if (Kind='double') and (Value.JSONType=jtString) then Exit(TJSONNull.Create);
  if (Kind='double') and (Value.JSONType=jtNumber) and (Value.AsFloat=0) then
    Exit(TJSONInt64Number.Create(0));
  if Value is TJSONArray then
  begin
    Items:=Field(Schema,'i');if not (Items is TJSONArray) or (Items.Count<>Value.Count) then Invalid;
    ArrayValue:=TJSONArray.Create;
    try
      for i:=0 to Value.Count-1 do ArrayValue.Add(JsonValue(Value.Items[i],Items.Items[i]));
      Result:=ArrayValue;ArrayValue:=nil;
    finally ArrayValue.Free;end;
  end
  else if Value is TJSONObject then
  begin
    Props:=Field(Field(Schema,'$s'),'p');ObjectValue:=TJSONObject.Create;
    try
      for i:=0 to Value.Count-1 do ObjectValue.Add(TJSONObject(Value).Names[i],
        JsonValue(Value.Items[i],Field(Props,TJSONObject(Value).Names[i])));
      Result:=ObjectValue;ObjectValue:=nil;
    finally ObjectValue.Free;end;
  end else Result:=Value.Clone;
end;
function DocumentJson(const Document:string):TJSONObject;
var Typed,Plain,Schema:TJSONObject;
begin
  Typed:=nil;Plain:=nil;Schema:=nil;
  try
    Plain:=ExactObject(PlainDocument(Document));Typed:=ExactObject(Document);
    Schema:=TJSONObject.Create(['t','object']);Schema.Add('$s',Typed.Find('$s').Clone);
    Result:=TJSONObject(JsonValue(Plain,Schema));
  finally Schema.Free;Plain.Free;Typed.Free;end;
end;
function ReadModelSjson(Db:TWLDb;const Model,Collection,Identity:string):string;
var Rows:TWLRows;Name:string;
begin
  Rows:=Db.Query('SELECT m.table_name FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name '+
    'WHERE m.name='+QuotedStr(Model)+' AND c.name='+QuotedStr(Collection)+';');
  if Length(Rows)<>1 then Invalid;
  Name:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
  Rows:=Db.Query('SELECT json(_ferretdb_sjson) FROM '+Name+' WHERE json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(Identity)+';');
  if Length(Rows)<>1 then Invalid;Result:=Rows[0][0];
end;
function CustomFieldsJson(const Document:string):TJSONArray;
var Typed,Plain,Row,Reply:TJSONObject;Rows,Schemas,Schema,Value,Id:TJSONData;i:Integer;
begin
  Result:=nil;Typed:=nil;Plain:=nil;Reply:=nil;
  try
    try
      // Validate the complete typed document before consuming any scalar metadata.
      Plain:=ExactObject(PlainDocument(Document));Typed:=ExactObject(Document);
      Result:=TJSONArray.Create;Rows:=Plain.Find('customFields');
      if Rows=nil then Exit;
      // Match the existing SQL projection's empty-array behavior for legacy {}.
      if not (Rows is TJSONArray) then Exit;
      Schemas:=Field(Field(Field(Typed,'$s'),'p'),'customFields');Schemas:=Field(Schemas,'i');
      if not (Schemas is TJSONArray) or (Schemas.Count<>Rows.Count) then Invalid;
      for i:=0 to Rows.Count-1 do
      begin
        if not (Rows.Items[i] is TJSONObject) then Invalid;
        Row:=TJSONObject(Rows.Items[i]);Id:=Row.Find('_id');
        if (Id<>nil) and (Id.JSONType<>jtString) then Invalid;
        Reply:=TJSONObject.Create;
        if Id=nil then Reply.Add('_id','') else Reply.Add('_id',Id.Clone);
        Value:=Row.Find('value');
        if Value<>nil then
        begin
          Schema:=Field(Field(Field(Schemas.Items[i],'$s'),'p'),'value');
          Reply.Add('value',JsonValue(Value,Schema));
        end;
        Result.Add(Reply);Reply:=nil;
      end;
    except FreeAndNil(Result);raise;end;
  finally Reply.Free;Plain.Free;Typed.Free;end;
end;
type
  TCardSourceScan=class
    SeenHeader:Boolean;
    procedure ReadRow(const Row:TWLRow);
  end;
procedure TCardSourceScan.ReadRow(const Row:TWLRow);
var Fields:TJSONArray;
begin
  if not SeenHeader then
  begin
    if (Length(Row)<>3) or (Row[0]<>'ok') then Invalid;
    SeenHeader:=True;Exit;
  end;
  if (Length(Row)<>3) or (Row[1]<>'1') then Invalid;
  // Validate every complete document, including missing/null customFields.
  Fields:=CustomFieldsJson(Row[2]);Fields.Free;
end;
procedure ValidateBoardCustomFields(Db:TWLDb;const BoardId:string);
var Rows:TWLRows;Name,Binding,Match,Sql:string;Reader:TCardSourceScan;
begin
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''cards'';');
  if Length(Rows)<>1 then Invalid;
  // Native TEXT values carry no BSON metadata to validate.
  if Rows[0][0]='table' then Exit;
  if Rows[0][0]<>'view' then Invalid;
  Rows:=Db.Query('SELECT m.table_name FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name '+
    'WHERE m.name=''cards'' AND c.name=''cards'';');
  if Length(Rows)<>1 then Invalid;
  Name:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
  Binding:='(SELECT count(*) FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name '+
    'WHERE m.name=''cards'' AND c.name=''cards'')=1 AND '+
    '(SELECT count(*) FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name '+
    'WHERE m.name=''cards'' AND c.name=''cards'' AND m.table_name='+QuotedStr(Rows[0][0])+')=1';
  // Concatenation removes CAST affinity: retain the old quoted-text lookup
  // instead of allowing SQLite to coerce a numeric source identity to text.
  Match:=' FROM '+Name+' s WHERE json_extract(s._ferretdb_sjson,''$."_id"'')=(CAST(v.id AS TEXT)||'''')';
  // One source batch, with an explicit cardinality per projected card. A LEFT
  // JOIN alone would silently drop missing sources or accept duplicate IDs.
  Sql:='SELECT CASE WHEN '+Binding+' THEN ''ok'' ELSE json(''Stale card source'') END,''0'','''' '+
    'UNION ALL SELECT v.id,(SELECT count(*)'+Match+'),'+
    '(SELECT json(s._ferretdb_sjson)'+Match+' LIMIT 1) FROM cards v WHERE v.boardId='+QuotedStr(BoardId)+';';
  Reader:=TCardSourceScan.Create;
  try
    if not Db.Scan(Sql,@Reader.ReadRow) or not Reader.SeenHeader then Invalid;
  finally Reader.Free;end;
end;
function ReadCustomFields(Db:TWLDb;const CardId:string):TJSONArray;
var Rows:TWLRows;Name:string;i:Integer;Row:TJSONObject;
begin
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''cards'';');
  if Length(Rows)<>1 then Invalid;
  if Rows[0][0]='view' then
  begin
    Rows:=Db.Query('SELECT m.table_name FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name '+
      'WHERE m.name=''cards'' AND c.name=''cards'';');
    if Length(Rows)<>1 then Invalid;
    Name:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
    Rows:=Db.Query('SELECT json(_ferretdb_sjson) FROM '+Name+' WHERE json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(CardId)+';');
    if Length(Rows)<>1 then Invalid;
    Exit(CustomFieldsJson(Rows[0][0]));
  end;
  if Rows[0][0]<>'table' then Invalid;
  // Native tables have no stored type discriminator. Keep their existing TEXT
  // contract until normalized typed migration establishes provenance.
  Rows:=Db.Query('SELECT customFieldId,value FROM card_custom_field_values WHERE cardId='+QuotedStr(CardId)+';');
  Result:=TJSONArray.Create;
  try
    for i:=0 to High(Rows) do
    begin
      if Length(Rows[i])<>2 then Invalid;
      Row:=TJSONObject.Create;Result.Add(Row);Row.Add('_id',Rows[i][0]);Row.Add('value',Rows[i][1]);
    end;
  except FreeAndNil(Result);raise;end;
end;
end.
