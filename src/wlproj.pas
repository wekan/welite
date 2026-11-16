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
function ProjectDocument(const Previous,Columns,Model,Mode:string):string;
var Doc,Patch,Spec,Hints,Field,Extra:TJSONObject;Fields,Managed:TJSONArray;
  Known:TStringList;Value,Converted,OldValue:TJSONData;i,j:Integer;Name,Path,Kind:string;InsertMode:Boolean;
begin
  Doc:=nil;Patch:=nil;Spec:=nil;Hints:=nil;Known:=nil;Extra:=nil;
  if not ((Mode='insert') or (Mode='update')) then Invalid;
  InsertMode:=Mode='insert';
  try
    if Previous='' then Doc:=TJSONObject.Create else Doc:=ExactObject(PlainDocument(Previous));
    Patch:=ExactObject(Columns);Spec:=ExactObject(Model);Hints:=TJSONObject.Create;
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
    // A remainder column replaces only unmodeled root fields. Null values remain
    // actual nulls; RFC merge-patch's null-as-delete semantics would corrupt them.
    for i:=0 to Fields.Count-1 do
    begin
      Field:=Fields.Objects[i];if Field.Get('kind','')<>'extra' then Continue;
      Value:=Patch.Find(Field.Get('name',''));if Value=nil then Continue;
      if Value.JSONType=jtNull then
      begin
        if not InsertMode then Invalid;
        Continue;
      end;
      if Value.JSONType<>jtString then Invalid;
      Extra:=ExactObject(Value.AsString);
      try
        for j:=0 to Extra.Count-1 do
          if (Known.IndexOf(Extra.Names[j])>=0) or (Extra.Names[j]='$s') then Invalid;
        for j:=Doc.Count-1 downto 0 do if Known.IndexOf(Doc.Names[j])<0 then Doc.Delete(j);
        for j:=0 to Extra.Count-1 do Doc.Add(Extra.Names[j],Extra.Items[j].Clone);
      finally FreeAndNil(Extra);end;
    end;
    if InsertMode then for i:=0 to Managed.Count-1 do RemovePath(Doc,Managed.Strings[i]);
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
          if not InsertMode and ((OldValue=nil) or (OldValue.AsString<>Converted.AsString)) then Invalid;
        end;
        if InsertMode and (Converted.JSONType=jtNull) and (OldValue=nil) then Continue;
        PutPath(Doc,Path,Converted);Converted:=nil;
        if Kind='date' then PutPath(Hints,Path,TJSONString.Create('date'));
      finally Converted.Free;end;
    end;
    Result:=TypedDocument(Doc.AsJSON,Previous,Hints.AsJSON);
  finally Extra.Free;Known.Free;Hints.Free;Spec.Free;Patch.Free;Doc.Free;end;
end;
// Edit one embedded row without rebuilding its siblings from SQL projections.
// The caller supplies all key columns; unknown object fields remain in place.
function RelationDocument(const Previous,Command,Model:string):string;
var Doc,Cmd,Spec,Old,Values,Row,Field,Seen:TJSONObject;Fields,Keys,Rows:TJSONArray;
  Item,Value,Converted,Container:TJSONData;Path,Op,Name,Signature:string;
  i,j,Found:Integer;Scalar,Match:Boolean;
  function KeyOf(Entry:TJSONData):string;
  var k:Integer;Part:TJSONData;
  begin
    Result:='';
    for k:=0 to Keys.Count-1 do
    begin
      if Scalar then Part:=Entry
      else if Entry is TJSONObject then Part:=AtPath(TJSONObject(Entry),Keys.Strings[k])
      else begin Invalid;Part:=nil;end;
      if (Part=nil) or (Part.JSONType<>jtString) or (Part.AsString='') then Invalid;
      Result:=Result+IntToStr(Length(Part.AsString))+':'+Part.AsString;
    end;
  end;
begin
  Doc:=nil;Cmd:=nil;Spec:=nil;Row:=nil;Seen:=nil;
  try
    Doc:=ExactObject(PlainDocument(Previous));Cmd:=ExactObject(Command);Spec:=ExactObject(Model);
    Path:=Spec.Get('path','');Scalar:=Spec.Get('scalar',False);
    if (Path='') or (RootOf(Path)='$s') then Invalid;
    if not (Spec.Find('fields') is TJSONArray) or not (Spec.Find('keys') is TJSONArray) then Invalid;
    Fields:=TJSONArray(Spec.Find('fields'));Keys:=TJSONArray(Spec.Find('keys'));
    if (Keys.Count=0) or (Scalar and (Keys.Count<>1)) then Invalid;
    Op:=Cmd.Get('op','');if (Op<>'insert') and (Op<>'update') and (Op<>'delete') then Invalid;
    if not (Cmd.Find('old') is TJSONObject) or not (Cmd.Find('values') is TJSONObject) then Invalid;
    Old:=TJSONObject(Cmd.Find('old'));Values:=TJSONObject(Cmd.Find('values'));
    Container:=AtPath(Doc,Path);
    if Container=nil then begin PutPath(Doc,Path,TJSONArray.Create);Container:=AtPath(Doc,Path);end;
    if not (Container is TJSONArray) then Invalid;Rows:=TJSONArray(Container);
    Found:=-1;
    for i:=0 to Rows.Count-1 do
    begin
      Item:=Rows.Items[i];Match:=True;
      for j:=0 to Keys.Count-1 do
      begin
        Name:=Keys.Strings[j];Value:=Old.Find(Name);
        if Scalar then Converted:=Item
        else if Item is TJSONObject then Converted:=AtPath(TJSONObject(Item),Name)
        else begin Invalid;Converted:=nil;end;
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
        if (Value=nil) and (Op='update') then Continue;
        if Value=nil then Value:=Field.Find('default');if Value=nil then Invalid;
        Converted:=Coerce(Value,Field);
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
  finally Seen.Free;Row.Free;Spec.Free;Cmd.Free;Doc.Free;end;
end;
end.
