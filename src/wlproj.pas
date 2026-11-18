unit wlproj;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses SysUtils,Classes,fpjson,DateUtils,Math,wlsjson;
function ProjectDocument(const Previous,Columns,Model,Mode:string):string;
function RelationDocument(const Previous,Command,Model:string):string;
implementation
procedure Invalid;
begin raise Exception.Create('Invalid model projection');end;
function AtPath(Doc:TJSONObject;const Path:string):TJSONData;
var Parts:TStringArray;i:Integer;Value:TJSONData;
begin
  Parts:=Path.Split('.');Value:=Doc;
  for i:=0 to High(Parts) do
  begin
    if not (Value is TJSONObject) then Exit(nil);
    Value:=TJSONObject(Value).Find(Parts[i]);
  end;
  Result:=Value;
end;
procedure PutPath(Doc:TJSONObject;const Path:string;Value:TJSONData);
var Parts:TStringArray;i:Integer;Parent:TJSONObject;Child:TJSONData;
begin
  Parts:=Path.Split('.');Parent:=Doc;
  try
    for i:=0 to High(Parts)-1 do
    begin
      Child:=Parent.Find(Parts[i]);
      if Child=nil then begin Child:=TJSONObject.Create;Parent.Add(Parts[i],Child);end;
      if not (Child is TJSONObject) then Invalid;
      Parent:=TJSONObject(Child);
    end;
    i:=Parent.IndexOfName(Parts[High(Parts)]);
    if i>=0 then Parent.Items[i]:=Value else Parent.Add(Parts[High(Parts)],Value);Value:=nil;
  finally Value.Free;end;
end;
procedure RemovePath(Doc:TJSONObject;const Path:string);
var Parts:TStringArray;i:Integer;Parent:TJSONObject;Child:TJSONData;
begin
  Parts:=Path.Split('.');Parent:=Doc;
  for i:=0 to High(Parts)-1 do
  begin Child:=Parent.Find(Parts[i]);if not (Child is TJSONObject) then Exit;Parent:=TJSONObject(Child);end;
  Parent.Delete(Parts[High(Parts)]);
end;
function RootOf(const Path:string):string;
var N:Integer;
begin N:=Pos('.',Path);if N=0 then Result:=Path else Result:=Copy(Path,1,N-1);end;
function Coerce(Value:TJSONData;Field:TJSONObject):TJSONData;
var Kind,Text,Typ:string;Number:Int64;RealValue:Double;Date:TDateTime;Stamp,Epoch:TTimeStamp;Settings:TFormatSettings;
begin
  Result:=nil;Kind:=Field.Get('kind','scalar');Typ:=Field.Get('type','TEXT');
  if Value.JSONType=jtNull then Exit(Value.Clone);
  if Kind='json' then
  begin
    if Value.JSONType<>jtString then Invalid;
    Exit(ExactObject(Value.AsString));
  end;
  if Kind='bool' then
  begin
    if Value.JSONType=jtBoolean then Exit(Value.Clone);
    Text:=LowerCase(Trim(Value.AsString));
    if (Text='1') or (Text='true') then Exit(TJSONBoolean.Create(True));
    if (Text='0') or (Text='false') then Exit(TJSONBoolean.Create(False));
    Invalid;
  end;
  if Kind='date' then
  begin
    Text:=Trim(Value.AsString);
    if Text='' then Exit(TJSONNull.Create);
    if TryStrToInt64(Text,Number) then Exit(TJSONInt64Number.Create(Number));
    if not TryISO8601ToDate(Text,Date,True) then Invalid;
    Stamp:=DateTimeToTimeStamp(Date);Epoch:=DateTimeToTimeStamp(EncodeDate(1970,1,1));
    Number:=Int64(Stamp.Date-Epoch.Date)*86400000+Stamp.Time;
    Exit(TJSONInt64Number.Create(Number));
  end;
  if Typ='TEXT' then
  begin
    if Value.JSONType=jtNumber then Exit(TJSONString.Create(Value.AsJSON));
    if not (Value.JSONType in [jtString,jtBoolean]) then Invalid;
    Exit(TJSONString.Create(Value.AsString));
  end;
  if Value.JSONType=jtNumber then
  begin
    if IsNan(Value.AsFloat) or IsInfinite(Value.AsFloat) then Invalid;
    Exit(Value.Clone);
  end;
  if Value.JSONType=jtString then
  begin
    Text:=Trim(Value.AsString);
    if TryStrToInt64(Text,Number) then Exit(TJSONInt64Number.Create(Number));
    Settings:=DefaultFormatSettings;Settings.DecimalSeparator:='.';Settings.ThousandSeparator:=#0;
    if not TryStrToFloat(Text,RealValue,Settings) or IsNan(RealValue) or IsInfinite(RealValue) then Invalid;
    Exit(TJSONFloatNumber.Create(RealValue));
  end;
  Invalid;
end;
// Existing custom values retain their declared BSON type. Inserts select the
// conversion from the current custom-field definition.
function CustomUpdate(Value,Schema:TJSONData;Field:TJSONObject):TJSONData;
var Kind:string;Spec,Parsed:TJSONObject;Items:TJSONData;i:Integer;
begin
  if Schema=nil then Exit(Coerce(Value,Field));
  if not (Schema is TJSONObject) then Invalid;
  Kind:=TJSONObject(Schema).Get('t','');
  if Kind='array' then
  begin
    if Value.JSONType=jtNull then Exit(Value.Clone);
    if Value.JSONType<>jtString then Invalid;
    Parsed:=ExactObject('{"value":'+Value.AsString+'}');
    try
      if Parsed.Count<>1 then Invalid;
      Items:=Parsed.Find('value');if not (Items is TJSONArray) then Invalid;
      for i:=0 to Items.Count-1 do if Items.Items[i].JSONType<>jtString then Invalid;
      Result:=Items.Clone;
    finally Parsed.Free;end;
    Exit;
  end;
  Spec:=TJSONObject(Field.Clone);
  try
    Spec.Strings['kind']:='scalar';
    if (Kind='int') or (Kind='long') or (Kind='double') then Spec.Strings['type']:='NUMERIC'
    else if Kind='bool' then Spec.Strings['kind']:='bool'
    else if Kind='date' then Spec.Strings['kind']:='date'
    else if (Kind<>'string') and (Kind<>'null') then Invalid;
    Result:=Coerce(Value,Spec);
  finally Spec.Free;end;
end;
function CustomInsert(Value:TJSONData;const FieldType:string;Field:TJSONObject):TJSONData;
var Kind:string;Schema:TJSONObject;
begin
  if (FieldType='text') or (FieldType='dropdown') or (FieldType='stringtemplate') then Kind:='string'
  else if (FieldType='number') or (FieldType='currency') then Kind:='double'
  else if FieldType='checkbox' then Kind:='bool'
  else if FieldType='date' then Kind:='date'
  else if FieldType='dropdownMultiSelect' then Kind:='array'
  else begin Invalid;Exit(nil);end;
  Schema:=TJSONObject.Create(['t',Kind]);
  try Result:=CustomUpdate(Value,Schema,Field);finally Schema.Free;end;
end;
function ProjectDocument(const Previous,Columns,Model,Mode:string):string;
var Doc,Patch,Spec,Hints,Field,Extra,Seed:TJSONObject;Fields,Managed,References:TJSONArray;
  Known,Restricted:TStringList;Scope:TJSONObject;Value,Converted,OldValue,Target:TJSONData;i,j:Integer;Name,Path,Kind:string;InsertMode,CloneMode:Boolean;
begin
  Doc:=nil;Patch:=nil;Spec:=nil;Hints:=nil;Known:=nil;Extra:=nil;Seed:=nil;
  if not ((Mode='insert') or (Mode='update') or (Mode='clone')) then Invalid;
  InsertMode:=Mode='insert';CloneMode:=Mode='clone';
  try
    // An explicit insert-only envelope carries the partial clone patch through
    // existing root views, so their reference and unique checks still apply.
    if InsertMode and (Previous<>'') then
    begin
      Seed:=CheckedJsonObject(Previous);
      if (Seed.Find('$s')=nil) and (Seed.Find('_wl_clone')<>nil) then
      begin
        if (Seed.Count<>3) or (Seed.Find('_wl_clone').AsJSON<>'1') or
          not (Seed.Find('source') is TJSONString) or not (Seed.Find('columns') is TJSONObject) then Invalid;
        Result:=ProjectDocument(Seed.Get('source',''),Seed.Find('columns').AsJSON,Model,'clone');Exit;
      end;
      FreeAndNil(Seed);
    end;
    if Previous='' then Doc:=TJSONObject.Create else Doc:=ExactObject(PlainDocument(Previous));
    if CloneMode then Patch:=CheckedJsonObject(Columns) else Patch:=ExactObject(Columns);
    Spec:=ExactObject(Model);Hints:=TJSONObject.Create;
    if CloneMode then
    begin
      if Previous='' then Invalid;Seed:=ExactObject(Previous);
      Value:=Seed.FindPath('$s.p._id.t');OldValue:=Doc.Find('_id');Target:=Patch.Find('id');
      if (Value=nil) or (Value.AsString<>'string') or not (OldValue is TJSONString) or
        (OldValue.AsString='') or not (Target is TJSONString) or (Target.AsString='') or
        (Target.AsString=OldValue.AsString) then Invalid;
      FreeAndNil(Seed);
    end;
    if not (Spec.Find('fields') is TJSONArray) or not (Spec.Find('managed') is TJSONArray) then Invalid;
    Fields:=TJSONArray(Spec.Find('fields'));Managed:=TJSONArray(Spec.Find('managed'));
    Known:=TStringList.Create;Known.Sorted:=True;Known.CaseSensitive:=True;Known.Duplicates:=dupIgnore;
    for i:=0 to Fields.Count-1 do
    begin
      Field:=Fields.Objects[i];Path:=Field.Get('path','');
      if Path<>'' then Known.Add(RootOf(Path));
    end;
    for i:=0 to Managed.Count-1 do Known.Add(RootOf(Managed.Strings[i]));
    for i:=0 to Patch.Count-1 do
    begin
      Name:=Patch.Names[i];j:=0;
      while (j<Fields.Count) and (Fields.Objects[j].Get('name','')<>Name) do Inc(j);
      if j=Fields.Count then Invalid;
    end;
    // A remainder column replaces only unmodeled fields in its scope. Null values remain
    // actual nulls; RFC merge-patch's null-as-delete semantics would corrupt them.
    for i:=0 to Fields.Count-1 do
    begin
      Field:=Fields.Objects[i];if Field.Get('kind','')<>'extra' then Continue;
      Value:=Patch.Find(Field.Get('name',''));if Value=nil then Continue;
      if Value.JSONType=jtNull then
      begin
        if not InsertMode then Invalid;
        Path:=Field.Get('path','');
        if (Path='') or (AtPath(Doc,Path)<>nil) then Continue;
        Value:=Field.Find('default');
        if (Value=nil) or (Value.JSONType=jtNull) then Continue;
      end;
      if Value.JSONType<>jtString then Invalid;
      Extra:=ExactObject(Value.AsString);
      try
        Path:=Field.Get('path','');Restricted:=nil;
        try
          if Path='' then begin Scope:=Doc;Restricted:=Known;end
          else begin
            if not (Field.Find('exclude') is TJSONArray) then Invalid;
            Restricted:=TStringList.Create;Restricted.CaseSensitive:=True;
            for j:=0 to TJSONArray(Field.Find('exclude')).Count-1 do
              Restricted.Add(TJSONArray(Field.Find('exclude')).Strings[j]);
            Target:=AtPath(Doc,Path);
            if Target=nil then begin PutPath(Doc,Path,TJSONObject.Create);Target:=AtPath(Doc,Path);end;
            if not (Target is TJSONObject) then Invalid;Scope:=TJSONObject(Target);
          end;
          for j:=0 to Extra.Count-1 do
            if (Restricted.IndexOf(Extra.Names[j])>=0) or ((Path='') and (Extra.Names[j]='$s')) then Invalid;
          for j:=Scope.Count-1 downto 0 do if Restricted.IndexOf(Scope.Names[j])<0 then Scope.Delete(j);
          for j:=0 to Extra.Count-1 do Scope.Add(Extra.Names[j],Extra.Items[j].Clone);
        finally if Restricted<>Known then Restricted.Free;end;
      finally FreeAndNil(Extra);end;
    end;
    if InsertMode or CloneMode then for i:=0 to Managed.Count-1 do RemovePath(Doc,Managed.Strings[i]);
    for i:=0 to Fields.Count-1 do
    begin
      Field:=Fields.Objects[i];Name:=Field.Get('name','');Path:=Field.Get('path','');Kind:=Field.Get('kind','scalar');
      if Kind='extra' then Continue;
      Value:=Patch.Find(Name);OldValue:=AtPath(Doc,Path);
      if (Value=nil) and not InsertMode then Continue;
      if InsertMode and ((Value=nil) or (Value.JSONType=jtNull)) then
      begin
        if OldValue<>nil then
        begin
          if Field.Get('required',False) and (OldValue.JSONType=jtNull) then Invalid;
          if (Name='id') and ((OldValue.JSONType<>jtString) or (OldValue.AsString='')) then Invalid;
          Continue;
        end;
        Value:=Field.Find('default');
      end;
      if Value=nil then Invalid;
      Converted:=Coerce(Value,Field);
      try
        if Field.Get('required',False) and (Converted.JSONType=jtNull) then Invalid;
        if Name='id' then
        begin
          if (Converted.JSONType<>jtString) or (Converted.AsString='') then Invalid;
          if not (InsertMode or CloneMode) and ((OldValue=nil) or (OldValue.AsString<>Converted.AsString)) then Invalid;
        end;
        if InsertMode and (Converted.JSONType=jtNull) and (OldValue=nil) then Continue;
        // WeKan unsets lifecycle markers and cleared card dates. Preserve
        // field absence when SQL represents those operations as NULL.
        if (Converted.JSONType=jtNull) and
          ((Spec.Get('table','')='lists') or (Spec.Get('table','')='cards')) and
          ((Name='deletedAt') or (Name='deletedBy') or (Name='deleteBatchId') or
            ((Spec.Get('table','')='cards') and
             ((Name='receivedAt') or (Name='startAt') or (Name='dueAt') or (Name='endAt')))) then
        begin
          RemovePath(Doc,Path);
          Continue;
        end;
        PutPath(Doc,Path,Converted);Converted:=nil;
        if Kind='date' then PutPath(Hints,Path,TJSONString.Create('date'));
        // An explicit SQL write to a declared string reference establishes that
        // type, including repairs whose old Regex pattern has the same text.
        if (Spec.Find('foreignKeys') is TJSONArray) and (AtPath(Doc,Path).JSONType<>jtNull) then
        begin
          References:=TJSONArray(Spec.Find('foreignKeys'));
          for j:=0 to References.Count-1 do
            if References.Objects[j].Get('column','')=Name then PutPath(Hints,Path,TJSONString.Create('string'));
        end;
      finally Converted.Free;end;
    end;
    Result:=TypedDocument(Doc.AsJSON,Previous,Hints.AsJSON);
  finally Seed.Free;Extra.Free;Known.Free;Hints.Free;Spec.Free;Patch.Free;Doc.Free;end;
end;
// Edit one embedded row without rebuilding its siblings from SQL projections.
// The caller supplies all key columns; unknown object fields remain in place.
function RelationDocument(const Previous,Command,Model:string):string;
var Doc,Cmd,Spec,Old,Values,Row,Field,Seen,Typed,Hints:TJSONObject;Fields,Keys,Rows:TJSONArray;
  Item,Value,Converted,Container,Schema:TJSONData;Path,Op,Name,Signature:string;
  i,j,Found,DateRow:Integer;Scalar,Match,AppendMode,ForceName,LegacyDependency:Boolean;
  function KeyValue(Entry:TJSONData;const Key:string):TJSONData;
  var n:Integer;
  begin
    if Scalar then Exit(Entry);
    if LegacyDependency and (Entry is TJSONString) then
    begin
      if Key='cardId' then Exit(Entry);
      Entry:=nil;
    end
    else if not (Entry is TJSONObject) then Invalid;
    Result:=nil;if Entry<>nil then Result:=AtPath(TJSONObject(Entry),Key);
    if Result=nil then
      for n:=0 to Fields.Count-1 do
        if Fields.Objects[n].Get('path',Fields.Objects[n].Get('name',''))=Key then
          Exit(Fields.Objects[n].Find('default'));
  end;
  function KeyOf(Entry:TJSONData):string;
  var k:Integer;Part:TJSONData;
  begin
    Result:='';
    for k:=0 to Keys.Count-1 do
    begin
      Part:=KeyValue(Entry,Keys.Strings[k]);
      if (Part=nil) or (Part.JSONType<>jtString) or (Part.AsString='') then Invalid;
      Result:=Result+IntToStr(Length(Part.AsString))+':'+Part.AsString;
    end;
  end;
begin
  Doc:=nil;Cmd:=nil;Spec:=nil;Row:=nil;Seen:=nil;Typed:=nil;Hints:=nil;DateRow:=-1;
  try
    Doc:=ExactObject(PlainDocument(Previous));Cmd:=ExactObject(Command);Spec:=ExactObject(Model);
    Path:=Spec.Get('path','');Scalar:=Spec.Get('scalar',False);
    LegacyDependency:=(Path='cardDependencies') and (Spec.Get('table','')='card_dependencies');
    if (Path='') or (RootOf(Path)='$s') then Invalid;
    if not (Spec.Find('fields') is TJSONArray) or not (Spec.Find('keys') is TJSONArray) then Invalid;
    Fields:=TJSONArray(Spec.Find('fields'));Keys:=TJSONArray(Spec.Find('keys'));
    if (Keys.Count=0) or (Scalar and (Keys.Count<>1)) then Invalid;
    Op:=Cmd.Get('op','');if (Op<>'insert') and (Op<>'update') and (Op<>'delete') and (Op<>'init') and (Op<>'append') then Invalid;
    if not (Cmd.Find('old') is TJSONObject) or not (Cmd.Find('values') is TJSONObject) then Invalid;
    Old:=TJSONObject(Cmd.Find('old'));Values:=TJSONObject(Cmd.Find('values'));
    // API append preserves missing optional fields; ordinary SQL inserts retain
    // their existing default/null projection semantics.
    ForceName:=(Op='update') and (Spec.Get('table','')='custom_field_dropdown_items') and (Values.Find('name') is TJSONString);
    AppendMode:=Op='append';
    if AppendMode then begin if (Cmd.Count<>3) or (Old.Count<>0) then Invalid;Op:='insert';end;
    // Initialization cannot reset an existing array or replace a null/scalar.
    if Op='init' then
    begin
      if (Cmd.Count<>3) or (Old.Count<>0) or (Values.Count<>0) or (AtPath(Doc,Path)<>nil) then Invalid;
      PutPath(Doc,Path,TJSONArray.Create);
      Result:=TypedDocument(Doc.AsJSON,Previous,'{}');Exit;
    end;
    Container:=AtPath(Doc,Path);
    if (Container=nil) or (LegacyDependency and (Op='insert') and (Container.JSONType=jtNull)) then
    begin PutPath(Doc,Path,TJSONArray.Create);Container:=AtPath(Doc,Path);end;
    if not (Container is TJSONArray) then Invalid;Rows:=TJSONArray(Container);
    Found:=-1;
    for i:=0 to Rows.Count-1 do
    begin
      Item:=Rows.Items[i];Match:=True;
      if LegacyDependency and (Item is TJSONString) then
      begin
        if Typed=nil then Typed:=ExactObject(Previous);
        Schema:=AtPath(Typed,'$s.p.cardDependencies');
        if not (Schema is TJSONObject) then Invalid;
        Schema:=TJSONObject(Schema).Find('i');
        if not (Schema is TJSONArray) or (i>=Schema.Count) then Invalid;
        Schema:=Schema.Items[i];
        if not (Schema is TJSONObject) or (TJSONObject(Schema).Get('t','')<>'string') then Invalid;
      end;
      for j:=0 to Keys.Count-1 do
      begin
        Name:=Keys.Strings[j];Value:=Old.Find(Name);
        Converted:=KeyValue(Item,Name);
        if (Value=nil) or (Converted=nil) then Match:=False
        else if (Value.JSONType<>jtString) or (Converted.JSONType<>jtString) or
          (Value.AsString<>Converted.AsString) then Match:=False;
      end;
      if Match then begin if Found>=0 then Invalid;Found:=i;end;
    end;
    if Op='insert' then begin if Found>=0 then Invalid;Row:=TJSONObject.Create;end
    else begin
      if Found<0 then Invalid;
      if Scalar then begin Row:=TJSONObject.Create;Row.Add(Keys.Strings[0],Rows.Items[Found].Clone);end
      else if Rows.Items[Found] is TJSONObject then Row:=TJSONObject(Rows.Items[Found].Clone)
      else if LegacyDependency and (Rows.Items[Found] is TJSONString) then
        Row:=TJSONObject.Create(['cardId',Rows.Items[Found].AsString,'type','related-to','color','#eb144c','icon','link'])
      else Invalid;
    end;
    if Op='delete' then Rows.Delete(Found)
    else
    begin
      for i:=0 to Values.Count-1 do
      begin
        j:=0;while (j<Fields.Count) and (Fields.Objects[j].Get('name','')<>Values.Names[i]) do Inc(j);
        if j=Fields.Count then Invalid;
      end;
      for i:=0 to Fields.Count-1 do
      begin
        Field:=Fields.Objects[i];Name:=Field.Get('name','');Value:=Values.Find(Name);
        if (Value=nil) and ((Op='update') or (AppendMode and not Field.Get('required',False))) then Continue;
        if Value=nil then Value:=Field.Find('default');if Value=nil then Invalid;
        if (Spec.Get('table','')='card_custom_field_values') and (Name='value') and (Op='update') then
        begin
          if Typed=nil then Typed:=ExactObject(Previous);
          Schema:=AtPath(Typed,'$s.p.customFields');
          if not (Schema is TJSONObject) then Invalid;
          Schema:=TJSONObject(Schema).Find('i');
          if not (Schema is TJSONArray) or (Found>=Schema.Count) then Invalid;
          if not (Schema.Items[Found] is TJSONObject) then Invalid;
          Schema:=AtPath(TJSONObject(Schema.Items[Found]),'$s.p.value');
          if ((Schema=nil) or ((Schema is TJSONObject) and (TJSONObject(Schema).Get('t','')='null'))) and
            (Cmd.Get('customCount',0)>0) then
          begin
            Converted:=CustomInsert(Value,Cmd.Get('customType',''),Field);
            if (Cmd.Get('customType','')='date') and (Converted.JSONType<>jtNull) then DateRow:=Found;
          end else Converted:=CustomUpdate(Value,Schema,Field);
        end else if (Spec.Get('table','')='card_custom_field_values') and (Name='value') and (Op='insert') then
        begin
          Converted:=CustomInsert(Value,Cmd.Get('customType',''),Field);
          if (Cmd.Get('customType','')='date') and (Converted.JSONType<>jtNull) then DateRow:=Rows.Count;
        end else Converted:=Coerce(Value,Field);
        try
          if Field.Get('required',False) and (Converted.JSONType=jtNull) then Invalid;
          PutPath(Row,Field.Get('path',Name),Converted);Converted:=nil;
        finally Converted.Free;end;
      end;
      if Scalar then
      begin
        Value:=Row.Find(Keys.Strings[0]);if Value=nil then Invalid;Item:=Value.Clone;
      end else Item:=Row.Clone;
      if Op='insert' then Rows.Add(Item) else Rows.Items[Found]:=Item;
    end;
    // Refuse ambiguous source arrays as well as duplicate newly inserted keys.
    Seen:=TJSONObject.Create;
    for i:=0 to Rows.Count-1 do
    begin
      Signature:=KeyOf(Rows.Items[i]);if Seen.IndexOfName(Signature)>=0 then Invalid;
      Seen.Add(Signature,True);
    end;
    Result:=TypedDocument(Doc.AsJSON,Previous,'{}');
    if ForceName then
    begin
      // An explicit option-name write establishes a BSON string even when a
      // legacy Regex has exactly the same plain-text rendering.
      Typed:=ExactObject(Result);Schema:=AtPath(Typed,'$s.p.settings.$s.p.dropdownItems');
      if not (Schema is TJSONObject) then Invalid;
      Container:=TJSONObject(Schema).Find('i');
      if not (Container is TJSONArray) or (Found<0) or (Found>=Container.Count) then Invalid;
      Item:=Container.Items[Found];if not (Item is TJSONObject) then Invalid;
      PutPath(TJSONObject(Item),'$s.p.name',TJSONObject.Create(['t','string']));
      Hints:=TJSONObject.Create;PutPath(Hints,'settings.dropdownItems',Schema.Clone);
      Result:=TypedDocument(Doc.AsJSON,Previous,Hints.AsJSON);FreeAndNil(Hints);
    end;
    if DateRow>=0 then
    begin
      // Supply the complete validated array schema as a hint so the
      // selected value receives Date metadata without rebuilding sibling schemas.
      FreeAndNil(Typed);Typed:=ExactObject(Result);Schema:=AtPath(Typed,'$s.p.customFields');
      if not (Schema is TJSONObject) then Invalid;
      Container:=TJSONObject(Schema).Find('i');
      if not (Container is TJSONArray) or (Container.Count<>Rows.Count) then Invalid;
      if DateRow>=Container.Count then Invalid;
      Item:=Container.Items[DateRow];
      if not (Item is TJSONObject) then Invalid;
      Value:=AtPath(TJSONObject(Item),'$s.p.value');
      if not (Value is TJSONObject) then Invalid;
      TJSONObject(Value).Strings['t']:='date';
      Hints:=TJSONObject.Create;Hints.Add('customFields',Schema.Clone);
      Result:=TypedDocument(Doc.AsJSON,Previous,Hints.AsJSON);
    end;
  finally Hints.Free;Typed.Free;Seen.Free;Row.Free;Spec.Free;Cmd.Free;Doc.Free;end;
end;
end.
