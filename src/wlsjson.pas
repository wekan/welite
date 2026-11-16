unit wlsjson;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses SysUtils,Classes,fpjson,jsonparser,jsonscanner,Math;
// FerretDB's SJSON: JSON data plus an ordered, recursive BSON type schema.
// NewJson is a complete plain document; OldJson supplies type metadata to retain.
// Hints is a tree of field names to explicit type names or full scalar schemas.
function TypedDocument(const NewJson,OldJson,Hints:string):string;
function PlainDocument(const Sjson:string):string;
// Strict parser retaining original numeric literals for other projection helpers.
function ExactObject(const Text:string):TJSONObject;
implementation
type
  TExactNumber=class(TJSONFloatNumber)
  private
    Literal:string;
  protected
    function GetAsJSON:TJSONStringType;override;
  public
    constructor Create(const Text:string;AValue:TJSONFloat);
    function Clone:TJSONData;override;
    function IntegralLiteral:Boolean;
  end;
constructor TExactNumber.Create(const Text:string;AValue:TJSONFloat);
begin inherited Create(AValue);Literal:=Text;end;
function TExactNumber.GetAsJSON:TJSONStringType;
begin Result:=Literal;end;
function TExactNumber.Clone:TJSONData;
begin Result:=TExactNumber.Create(Literal,AsFloat);end;
function TExactNumber.IntegralLiteral:Boolean;
begin Result:=(Pos('.',Literal)=0) and (Pos('e',LowerCase(Literal))=0);end;

const MaxBytes=16*1024*1024;MaxDepth=100;
procedure Invalid;
begin raise Exception.Create('Invalid or unsupported typed document');end;
procedure CheckUtf8(const Text:string);
var i,n,j,b,c:Integer;
begin
  i:=1;
  while i<=Length(Text) do
  begin
    b:=Ord(Text[i]);n:=0;
    if b<$80 then begin Inc(i);Continue;end;
    if (b>=$c2) and (b<=$df) then n:=1
    else if (b>=$e0) and (b<=$ef) then n:=2
    else if (b>=$f0) and (b<=$f4) then n:=3 else Invalid;
    if i+n>Length(Text) then Invalid;
    for j:=1 to n do
    begin c:=Ord(Text[i+j]);if (c<$80) or (c>$bf) then Invalid;end;
    c:=Ord(Text[i+1]);
    if ((b=$e0) and (c<$a0)) or ((b=$ed) and (c>$9f)) or
      ((b=$f0) and (c<$90)) or ((b=$f4) and (c>$8f)) then Invalid;
    Inc(i,n+1);
  end;
end;
procedure CheckInput(const Text:string);
var i,Depth:Integer;Quoted,Escaped:Boolean;
begin
  if (Text='') or (Length(Text)>MaxBytes) then Invalid;
  CheckUtf8(Text);Depth:=0;Quoted:=False;Escaped:=False;
  for i:=1 to Length(Text) do
    if Quoted then
    begin
      if Escaped then Escaped:=False
      else if Text[i]='\' then Escaped:=True
      else if Text[i]='"' then Quoted:=False;
    end
    else if Text[i]='"' then Quoted:=True
    else if Text[i] in ['{','['] then begin Inc(Depth);if Depth>512 then Invalid;end
    else if Text[i] in ['}',']'] then begin Dec(Depth);if Depth<0 then Invalid;end;
  if Quoted or (Depth<>0) then Invalid;
end;
function ParseObject(const Text:string):TJSONObject;
var Data:TJSONData;Parser:TJSONParser;Tokens:TStringList;Index,i,Start:Integer;Quoted,Escaped:Boolean;
  procedure PreserveNumbers(Parent:TJSONData);
  var j:Integer;Child:TJSONData;
  begin
    for j:=0 to Parent.Count-1 do
    begin
      Child:=Parent.Items[j];
      if Child.JSONType=jtNumber then
      begin
        if Index>=Tokens.Count then Invalid;
        if (Child is TJSONFloatNumber) or (Tokens[Index]='-0') then
          Parent.Items[j]:=TExactNumber.Create(Tokens[Index],Child.AsFloat);
        Inc(Index);
      end
      else if Child.JSONType in [jtObject,jtArray] then PreserveNumbers(Child);
    end;
  end;
begin
  CheckInput(Text);Tokens:=TStringList.Create;Data:=nil;
  try
    Quoted:=False;Escaped:=False;i:=1;
    while i<=Length(Text) do
    begin
      if Quoted then
      begin
        if Escaped then Escaped:=False
        else if Text[i]='\' then Escaped:=True
        else if Text[i]='"' then Quoted:=False;
      end
      else if Text[i]='"' then Quoted:=True
      else if Text[i] in ['-','0'..'9'] then
      begin
        Start:=i;
        while (i<=Length(Text)) and (Text[i] in ['-','+','0'..'9','.','e','E']) do Inc(i);
        Tokens.Add(Copy(Text,Start,i-Start));Continue;
      end;
      Inc(i);
    end;
    Parser:=TJSONParser.Create(Text,[joUTF8,joStrict]);
    try Data:=Parser.Parse;finally Parser.Free;end;
    if not (Data is TJSONObject) then Invalid;
    Index:=0;PreserveNumbers(Data);if Index<>Tokens.Count then Invalid;
    Result:=TJSONObject(Data);Data:=nil;
  finally Data.Free;Tokens.Free;end;
end;

function ExactObject(const Text:string):TJSONObject;
begin Result:=ParseObject(Text);end;
function Field(Data:TJSONData;const Name:string):TJSONData;
begin Result:=nil;if Data is TJSONObject then Result:=TJSONObject(Data).Find(Name);end;
function Kind(Schema:TJSONData):string;
var V:TJSONData;
begin
  Result:='';if Schema is TJSONString then Exit(Schema.AsString);
  V:=Field(Schema,'t');if V is TJSONString then Result:=V.AsString;
end;
procedure UniqueKeys(Obj:TJSONObject);
var Names:TStringList;i:Integer;
begin
  Names:=TStringList.Create;
  try
    Names.CaseSensitive:=True;Names.Sorted:=True;
    for i:=0 to Obj.Count-1 do
    begin
      CheckUtf8(Obj.Names[i]);if Pos(#0,Obj.Names[i])>0 then Invalid;
      if Names.IndexOf(Obj.Names[i])>=0 then Invalid;
      Names.Add(Obj.Names[i]);
    end;
  finally Names.Free;end;
end;
function SignedInteger(Value:TJSONData;out Number:Int64):Boolean;
begin
  Result:=(Value is TJSONNumber) and ((TJSONNumber(Value).NumberType<>ntFloat) or
    ((Value is TExactNumber) and TExactNumber(Value).IntegralLiteral));
  if Result then Result:=TryStrToInt64(Value.AsJSON,Number);
end;
function UnsignedInteger(Value:TJSONData):Boolean;
var Number:QWord;
begin
  Result:=(Value is TJSONNumber) and ((TJSONNumber(Value).NumberType<>ntFloat) or
    ((Value is TExactNumber) and TExactNumber(Value).IntegralLiteral));
  if Result then Result:=TryStrToQWord(Value.AsJSON,Number);
end;
function IsBase64(const Text:string):Boolean;
var i,Padding:Integer;
begin
  Result:=False;if Length(Text) mod 4<>0 then Exit;
  Padding:=0;
  for i:=1 to Length(Text) do
    if Text[i]='=' then begin Inc(Padding);if (Padding>2) or (i<Length(Text)-1) then Exit;end
    else if (Padding<>0) or not (Text[i] in ['A'..'Z','a'..'z','0'..'9','+','/']) then Exit;
  Result:=True;
end;
function ScalarFits(Value,Schema:TJSONData):Boolean;
var Name,Text:string;Number:Int64;i:Integer;Extra:TJSONData;
begin
  Result:=False;if Value=nil then Exit;Name:=Kind(Schema);
  case Name of
    'null':Result:=Value.JSONType=jtNull;
    'bool':Result:=Value.JSONType=jtBoolean;
    'string':Result:=Value.JSONType=jtString;
    'double':
      if Value.JSONType=jtNumber then Result:=not IsNan(Value.AsFloat) and not IsInfinite(Value.AsFloat)
      else if Value.JSONType=jtString then Result:=(Value.AsString='NaN') or (Value.AsString='Infinity') or (Value.AsString='-Infinity');
    'date','long':Result:=SignedInteger(Value,Number);
    'int':Result:=SignedInteger(Value,Number) and (Number>=Low(LongInt)) and (Number<=High(LongInt));
    'timestamp':Result:=UnsignedInteger(Value);
    'objectId':
      if Value.JSONType=jtString then
      begin
        Text:=Value.AsString;Result:=Length(Text)=24;
        for i:=1 to Length(Text) do if not (Text[i] in ['0'..'9','a'..'f','A'..'F']) then Result:=False;
      end;
    'binData':
      begin
        Extra:=Field(Schema,'s');
        Result:=(Value.JSONType=jtString) and IsBase64(Value.AsString) and
          SignedInteger(Extra,Number) and (Number>=0) and (Number<=255);
      end;
    'regex':Result:=(Value.JSONType=jtString) and (Field(Schema,'o') is TJSONString);
  end;
end;
procedure Validate(Value,Schema:TJSONData;Depth:Integer);forward;
procedure ValidateObject(Value:TJSONObject;Schema:TJSONData;Depth:Integer);
var Keys,Props,Entry:TJSONData;i:Integer;Name:string;Seen:TStringList;
begin
  if Depth>MaxDepth then Invalid;UniqueKeys(Value);
  if not (Schema is TJSONObject) then Invalid;
  UniqueKeys(TJSONObject(Schema));
  if (Value.Count=0) and (TJSONObject(Schema).Count=0) then Exit;
  if TJSONObject(Schema).Count<>2 then Invalid;
  Keys:=Field(Schema,'$k');Props:=Field(Schema,'p');
  if not (Keys is TJSONArray) or not (Props is TJSONObject) then Invalid;
  UniqueKeys(TJSONObject(Props));
  if (Keys.Count<>Value.Count) or (Props.Count<>Value.Count) then Invalid;
  Seen:=TStringList.Create;
  try
    Seen.Sorted:=True;Seen.CaseSensitive:=True;
    for i:=0 to Keys.Count-1 do
    begin
      Entry:=Keys.Items[i];if not (Entry is TJSONString) then Invalid;Name:=Entry.AsString;
      if Seen.IndexOf(Name)>=0 then Invalid;Seen.Add(Name);
      Entry:=Value.Find(Name);if Entry=nil then Invalid;
      Validate(Entry,Field(Props,Name),Depth+1);
    end;
  finally Seen.Free;end;
end;
procedure Validate(Value,Schema:TJSONData;Depth:Integer);
var Name:string;Items:TJSONData;i:Integer;
begin
  if (Depth>MaxDepth) or not (Schema is TJSONObject) then Invalid;
  UniqueKeys(TJSONObject(Schema));Name:=Kind(Schema);
  for i:=0 to Schema.Count-1 do
    if TJSONObject(Schema).Names[i]<>'t' then
    begin
      if (TJSONObject(Schema).Names[i]<>'$s') and (TJSONObject(Schema).Names[i]<>'i') and
        (TJSONObject(Schema).Names[i]<>'o') and (TJSONObject(Schema).Names[i]<>'s') then Invalid;
    end;
  if Name='object' then
  begin
    if not (Value is TJSONObject) then Invalid;
    ValidateObject(TJSONObject(Value),Field(Schema,'$s'),Depth);
  end
  else if Name='array' then
  begin
    if not (Value is TJSONArray) then Invalid;Items:=Field(Schema,'i');
    if not (Items is TJSONArray) or (Items.Count<>Value.Count) then Invalid;
    for i:=0 to Value.Count-1 do Validate(Value.Items[i],Items.Items[i],Depth+1);
  end
  else if not ScalarFits(Value,Schema) then Invalid;
  if Value.JSONType=jtString then CheckUtf8(Value.AsString);
end;
function OldPlain(Obj:TJSONObject):TJSONObject;
var S:TJSONData;
begin
  UniqueKeys(Obj);S:=Obj.Find('$s');if S=nil then Invalid;
  Result:=TJSONObject(Obj.Clone);
  try
    Result.Delete('$s');ValidateObject(Result,S,0);
  except Result.Free;raise;end;
end;
function MakeSchema(Value,OldValue,OldSchema,Hint:TJSONData;Depth:Integer):TJSONObject;
var Name,Key:string;i,j:Integer;Keys,Items:TJSONArray;Props,S:TJSONObject;
  Child,OldChild,ChildSchema,ChildHint:TJSONData;Number:Int64;
begin
  if (Value=nil) or (Depth>MaxDepth) then Invalid;
  if Value is TJSONObject then UniqueKeys(TJSONObject(Value));
  if (Hint=nil) and (OldValue<>nil) and (OldSchema<>nil) and (Value.AsJSON=OldValue.AsJSON) then
    Exit(TJSONObject(OldSchema.Clone));
  Name:=Kind(Hint);
  if Value.JSONType=jtNull then Name:='null';
  if Name<>'' then
  begin
    if Hint is TJSONObject then Result:=TJSONObject(Hint.Clone)
    else Result:=TJSONObject.Create(['t',Name]);
    if Value.JSONType=jtNull then begin Result.Free;Result:=TJSONObject.Create(['t','null']);end;
    try Validate(Value,Result,Depth);except Result.Free;raise;end;
    Exit;
  end;
  if (Value.JSONType in [jtString,jtNumber,jtBoolean,jtNull]) and ScalarFits(Value,OldSchema) then
    Exit(TJSONObject(OldSchema.Clone));
  case Value.JSONType of
    jtNull:Name:='null';jtBoolean:Name:='bool';jtString:Name:='string';
    jtNumber:if (TJSONNumber(Value).NumberType=ntFloat) and not
      ((Value is TExactNumber) and TExactNumber(Value).IntegralLiteral) then Name:='double'
      else if SignedInteger(Value,Number) then Name:='long' else Invalid;
    jtObject:Name:='object';jtArray:Name:='array';
  else Invalid;
  end;
  Result:=TJSONObject.Create(['t',Name]);
  try
    if Name='object' then
    begin
      S:=TJSONObject.Create;Result.Add('$s',S);
      if Value.Count=0 then Exit;
      Keys:=TJSONArray.Create;S.Add('$k',Keys);Props:=TJSONObject.Create;S.Add('p',Props);
      for i:=0 to Value.Count-1 do
      begin
        Key:=TJSONObject(Value).Names[i];Keys.Add(Key);Child:=Value.Items[i];
        OldChild:=Field(OldValue,Key);ChildSchema:=Field(Field(Field(OldSchema,'$s'),'p'),Key);
        ChildHint:=Field(Hint,Key);
        Props.Add(Key,MakeSchema(Child,OldChild,ChildSchema,ChildHint,Depth+1));
      end;
    end
    else if Name='array' then
    begin
      Items:=TJSONArray.Create;Result.Add('i',Items);
      for i:=0 to Value.Count-1 do
      begin
        OldChild:=nil;ChildSchema:=nil;Child:=Value.Items[i];
        if OldValue is TJSONArray then
        begin
          j:=i;
          if (j>=OldValue.Count) or (OldValue.Items[j].AsJSON<>Child.AsJSON) then
          begin
            j:=0;
            while (j<OldValue.Count) and (OldValue.Items[j].AsJSON<>Child.AsJSON) do Inc(j);
            if j>=OldValue.Count then j:=i;
          end;
          if (j<OldValue.Count) and (Field(OldSchema,'i') is TJSONArray) and (j<Field(OldSchema,'i').Count) then
          begin OldChild:=OldValue.Items[j];ChildSchema:=Field(OldSchema,'i').Items[j];end;
        end;
        Items.Add(MakeSchema(Child,OldChild,ChildSchema,nil,Depth+1));
      end;
    end;
    Validate(Value,Result,Depth);
  except Result.Free;raise;end;
end;
function TypedDocument(const NewJson,OldJson,Hints:string):string;
var NewDoc,OldDoc,OldData,HintDoc,OutDoc:TJSONObject;Schema,OldSchema:TJSONObject;i:Integer;
begin
  NewDoc:=nil;OldDoc:=nil;OldData:=nil;HintDoc:=nil;OutDoc:=nil;Schema:=nil;OldSchema:=nil;
  try
    NewDoc:=ParseObject(NewJson);if NewDoc.Find('$s')<>nil then Invalid;
    if OldJson<>'' then
    begin
      OldDoc:=ParseObject(OldJson);OldData:=OldPlain(OldDoc);
      OldSchema:=TJSONObject.Create;OldSchema.Add('t','object');OldSchema.Add('$s',OldDoc.Find('$s').Clone);
    end;
    if Hints<>'' then HintDoc:=ParseObject(Hints);
    Schema:=MakeSchema(NewDoc,OldData,OldSchema,HintDoc,0);
    OutDoc:=TJSONObject.Create;OutDoc.Add('$s',Schema.Find('$s').Clone);
    // SJSON stores schema keys in data order. Reusing an unchanged object schema
    // preserves its original order, even if plain JSON arrived in a different order.
    for i:=0 to NewDoc.Count-1 do
      OutDoc.Add(Schema.Find('$s').FindPath('$k').Items[i].AsString,NewDoc.Find(Schema.Find('$s').FindPath('$k').Items[i].AsString).Clone);
    Result:=OutDoc.AsJSON;if Length(Result)>MaxBytes then Invalid;
  finally
    OldSchema.Free;Schema.Free;OutDoc.Free;HintDoc.Free;OldData.Free;OldDoc.Free;NewDoc.Free;
  end;
end;
function PlainDocument(const Sjson:string):string;
var Doc,Plain:TJSONObject;
begin
  Doc:=ParseObject(Sjson);Plain:=nil;
  try Plain:=OldPlain(Doc);Result:=Plain.AsJSON;finally Plain.Free;Doc.Free;end;
end;
end.
