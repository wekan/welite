unit wlresume;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses SysUtils,Classes,Math,fpjson,base64,wlcrypt,wlsjson,wllife;
// Meteor's shared token digest is SHA256(raw UTF-8 bytes), standard padded base64.
// It is deliberately distinct from WeLite's tenant-scoped private token digest.
function MeteorTokenHash(const Token:string):string;
function ValidMeteorTokenHash(const Hash:string):Boolean;
// Pure SJSON edit: append {hashedToken,when:BSON Date}, remove matching hashes,
// clear/expire records, revoke both forms, or convert a legacy raw bearer.
// This function does not authorize the caller.
function ResumeDocument(const Previous,Command:string):string;
type TResumeState=(rsAbsent,rsValid,rsExpired,rsInvalid);
function CheckResumeToken(const Previous,Hash:string;NowMs:Int64;LifetimeMs:Double;
  out WhenMs,ExpiresMs:Int64):TResumeState;
function ResumeStateName(State:TResumeState):string;
implementation
procedure Invalid;
begin raise Exception.Create('Invalid resume token document');end;
function Child(Value:TJSONData;const Name:string):TJSONData;
begin
  Result:=nil;if Value is TJSONObject then Result:=TJSONObject(Value).Find(Name);
end;
function ObjectField(Parent:TJSONObject;const Name:string;CreateMissing:Boolean):TJSONObject;
var Value:TJSONData;
begin
  Value:=Parent.Find(Name);
  if (Value=nil) and CreateMissing then begin Value:=TJSONObject.Create;Parent.Add(Name,Value);end;
  if (Value<>nil) and not (Value is TJSONObject) then Invalid;
  Result:=TJSONObject(Value);
end;
function MeteorTokenHash(const Token:string):string;
var Hex:string;Bytes:RawByteString;i:Integer;
begin
  if (Token='') or (Length(Token)>4096) then Invalid;
  Hex:=Sha256Hex(Token);SetLength(Bytes,32);
  try
    for i:=1 to 32 do Bytes[i]:=Chr(StrToInt('$'+Copy(Hex,2*i-1,2)));
    Result:=EncodeStringBase64(Bytes);
  finally UniqueString(Bytes);FillChar(Bytes[1],Length(Bytes),0);end;
end;
function ValidMeteorTokenHash(const Hash:string):Boolean;
var Bytes:RawByteString;
begin
  Result:=False;
  if Length(Hash)<>44 then Exit;
  try
    Bytes:=DecodeStringBase64(Hash);
    Result:=(Length(Bytes)=32) and (EncodeStringBase64(Bytes)=Hash);
  except Result:=False;end;
end;

procedure ValidateHash(const Hash:string);
begin
  if not ValidMeteorTokenHash(Hash) then Invalid;
end;

function TokenSchemas(Raw:TJSONData):TJSONData;
begin
  Result:=Child(Child(Child(Raw,'$s'),'p'),'services');
  Result:=Child(Child(Child(Result,'$s'),'p'),'resume');
  Result:=Child(Child(Child(Result,'$s'),'p'),'loginTokens');Result:=Child(Result,'i');
end;
function Timestamp(Entry,Schema:TJSONData;out Number:Double):Boolean;
var Value,TypeName:TJSONData;Kind:string;IntegerMs:Int64;
begin
  Result:=False;Number:=0;Value:=Child(Entry,'when');
  TypeName:=Child(Child(Child(Schema,'$s'),'p'),'when');TypeName:=Child(TypeName,'t');
  if (Value=nil) or (Value.JSONType<>jtNumber) or (TypeName=nil) then Exit;
  Kind:=TypeName.AsString;
  if (Kind='date') or (Kind='int') or (Kind='long') then
  begin if not TryStrToInt64(Value.AsJSON,IntegerMs) then Exit;Number:=IntegerMs;end
  else if Kind='double' then Number:=Value.AsFloat else Exit;
  Result:=not IsNan(Number) and not IsInfinite(Number);
end;
function ResumeStateName(State:TResumeState):string;
const Names:array[TResumeState] of string=('absent','valid','expired','invalid');
begin Result:=Names[State];end;
function CheckResumeToken(const Previous,Hash:string;NowMs:Int64;LifetimeMs:Double;
  out WhenMs,ExpiresMs:Int64):TResumeState;
const MaxDateMs:Int64=8640000000000000; // JavaScript Date TimeClip limit
var Doc,Raw,Services,Resume:TJSONObject;Tokens,Schemas,Value:TJSONData;
  i,Found:Integer;Number:Double;Stamp,Expiration:Int64;
begin
  Result:=rsInvalid;WhenMs:=0;ExpiresMs:=0;Doc:=nil;Raw:=nil;
  try
    try
      ValidateHash(Hash);
      if (NowMs< -MaxDateMs) or (NowMs>MaxDateMs) or IsNan(LifetimeMs) or IsInfinite(LifetimeMs) or (LifetimeMs<=0) or (LifetimeMs>2*MaxDateMs) then Exit;
      Doc:=ExactObject(PlainDocument(Previous));Raw:=ExactObject(Previous);
      Services:=ObjectField(Doc,'services',False);if Services=nil then Exit(rsAbsent);
      Resume:=ObjectField(Services,'resume',False);if Resume=nil then Exit(rsAbsent);
      Tokens:=Resume.Find('loginTokens');if Tokens=nil then Exit(rsAbsent);
      if not (Tokens is TJSONArray) then Exit;
      Schemas:=TokenSchemas(Raw);
      if not (Schemas is TJSONArray) or (Schemas.Count<>Tokens.Count) then Exit;
      Found:=-1;
      for i:=0 to Tokens.Count-1 do
      begin
        Value:=Child(Tokens.Items[i],'hashedToken');
        if (Value=nil) or (Value.JSONType<>jtString) or (Value.AsString<>Hash) then Continue;
        if Found>=0 then Exit;Found:=i;
      end;
      if Found<0 then Exit(rsAbsent);
      if not Timestamp(Tokens.Items[Found],Schemas.Items[Found],Number) or (Number< -MaxDateMs) or (Number>MaxDateMs) then Exit;
      Stamp:=Trunc(Number); // Date(number) truncates fractional legacy milliseconds
      Expiration:=TokenExpirationMs(Stamp,Double(LifetimeMs));
      if NowMs>=Expiration then Exit(rsExpired);
      WhenMs:=Stamp;ExpiresMs:=Expiration;Result:=rsValid;
    except Result:=rsInvalid;WhenMs:=0;ExpiresMs:=0;end;
  finally Raw.Free;Doc.Free;end;
end;
procedure ConvertLegacy(Tokens,Types:TJSONArray;const RawToken,Hash:string);
var i,OldIndex,HashIndex,OldCount,HashCount:Integer;Value,Schema:TJSONData;
  Entry,Hints,Typed,Item:TJSONObject;Number:Double;
begin
  OldIndex:=-1;HashIndex:=-1;OldCount:=0;HashCount:=0;
  for i:=0 to Tokens.Count-1 do
  begin
    Value:=Child(Tokens.Items[i],'hashedToken');
    if (Value<>nil) and (Value.JSONType=jtString) and (Value.AsString=Hash) then
    begin Inc(HashCount);HashIndex:=i;end;
    Value:=Child(Tokens.Items[i],'token');
    if (Value<>nil) and (Value.JSONType=jtString) and (Value.AsString=RawToken) then
    begin
      // A hybrid record can otherwise be removed after selecting its hash.
      if Child(Tokens.Items[i],'hashedToken')<>nil then Invalid;
      Inc(OldCount);OldIndex:=i;
    end;
  end;
  if (HashCount>1) or ((HashCount=0) and (OldCount>1)) then Invalid;
  if HashCount=1 then
  begin
    if not Timestamp(Tokens.Items[HashIndex],Types.Items[HashIndex],Number) or
      (Number< -8640000000000000) or (Number>8640000000000000) then Invalid;
  end
  else if OldCount=1 then
  begin
    if not Timestamp(Tokens.Items[OldIndex],Types.Items[OldIndex],Number) or
      (Number< -8640000000000000) or (Number>8640000000000000) then Invalid;
    Entry:=nil;Hints:=nil;Typed:=nil;Item:=nil;
    try
      // Keep unknown fields and their complete BSON schemas. Replace only the
      // raw bearer field; never mint a new timestamp or infer a legacy number.
      Entry:=TJSONObject(Tokens.Items[OldIndex].Clone);Entry.Delete('token');Entry.Add('hashedToken',Hash);
      Schema:=Child(Child(Types.Items[OldIndex],'$s'),'p');
      if not (Schema is TJSONObject) then Invalid;
      Hints:=TJSONObject(Schema.Clone);Hints.Delete('token');
      Hints.Add('hashedToken','string');
      Typed:=ExactObject(TypedDocument(Entry.AsJSON,'',Hints.AsJSON));
      Item:=TJSONObject.Create;Item.Add('t','object');Item.Add('$s',Child(Typed,'$s').Clone);
      Tokens.Items[OldIndex]:=Entry;Entry:=nil;Types.Items[OldIndex]:=Item;Item:=nil;
      Exit;
    finally Item.Free;Typed.Free;Hints.Free;Entry.Free;end;
  end;
  // If another converter already installed the hash, retain that record and
  // remove matching raw records atomically, without changing its timestamp.
  for i:=Tokens.Count-1 downto 0 do
  begin
    Value:=Child(Tokens.Items[i],'token');
    if (Value<>nil) and (Value.JSONType=jtString) and (Value.AsString=RawToken) then
    begin Tokens.Delete(i);Types.Delete(i);end;
  end;
end;
function ResumeDocument(const Previous,Command:string):string;
var Doc,Raw,Cmd,Services,Resume,Hints,HintServices,HintResume,ArraySchema,Entry:TJSONObject;
  Tokens,Types:TJSONArray;Value,OldTypes:TJSONData;Op,Hash,Name,RawToken:string;
  i,j:Integer;WhenMs,BeforeMs:Int64;Number:Double;CreateMissing,Matched:Boolean;Hashes:TStringList;
begin
  Doc:=nil;Raw:=nil;Cmd:=nil;Hints:=nil;Types:=nil;Entry:=nil;Hashes:=nil;
  try
    Doc:=ExactObject(PlainDocument(Previous));Raw:=ExactObject(Previous);Cmd:=ExactObject(Command);
    Value:=Cmd.Find('op');if (Value=nil) or (Value.JSONType<>jtString) then Invalid;Op:=Value.AsString;
    if (Op<>'append') and (Op<>'remove') and (Op<>'clear') and (Op<>'expire') and (Op<>'revoke') and (Op<>'convert') and (Op<>'retire') then Invalid;
    for i:=0 to Cmd.Count-1 do
    begin
      Name:=Cmd.Names[i];if Name='op' then Continue;
      if (Name='hashedToken') and ((Op='append') or (Op='remove')) then Continue;
      if (Name='token') and ((Op='revoke') or (Op='convert')) then Continue;
      if (Name='before') and (Op='expire') then Continue;
      if (Name='hashes') and (Op='retire') then Continue;
      if (Name='when') and (Op='append') then Continue;
      Invalid;
    end;
    if (Op='append') or (Op='remove') then
    begin
      Value:=Cmd.Find('hashedToken');if (Value=nil) or (Value.JSONType<>jtString) then Invalid;
      Hash:=Value.AsString;ValidateHash(Hash);
    end;
    if Op='retire' then
    begin
      Value:=Cmd.Find('hashes');if not (Value is TJSONArray) then Invalid;
      Hashes:=TStringList.Create;Hashes.Sorted:=True;Hashes.CaseSensitive:=True;Hashes.Duplicates:=dupIgnore;
      for j:=0 to Value.Count-1 do
      begin
        if Value.Items[j].JSONType<>jtString then Invalid;
        Hash:=Value.Items[j].AsString;ValidateHash(Hash);Hashes.Add(Hash);
      end;
    end;
    RawToken:='';
    if (Op='revoke') or (Op='convert') then
    begin
      Value:=Cmd.Find('token');if (Value=nil) or (Value.JSONType<>jtString) then Invalid;
      RawToken:=Value.AsString;Hash:=MeteorTokenHash(RawToken);
    end;
    WhenMs:=0;
    if Op='append' then
    begin
      Value:=Cmd.Find('when');
      if (Value=nil) or (Value.JSONType<>jtNumber) or not TryStrToInt64(Value.AsJSON,WhenMs) then Invalid;
    end;
    BeforeMs:=0;
    if Op='expire' then
    begin
      Value:=Cmd.Find('before');
      if (Value=nil) or (Value.JSONType<>jtNumber) or not TryStrToInt64(Value.AsJSON,BeforeMs) then Invalid;
      if (BeforeMs< -8640000000000000) or (BeforeMs>8640000000000000) then Invalid;
    end;
    CreateMissing:=(Op='append') or (Op='clear');
    Services:=ObjectField(Doc,'services',CreateMissing);if Services=nil then Exit(Previous);
    Resume:=ObjectField(Services,'resume',CreateMissing);if Resume=nil then Exit(Previous);
    Value:=Resume.Find('loginTokens');
    if (Op='clear') and (Value<>nil) then
    begin Resume.Items[Resume.IndexOfName('loginTokens')]:=TJSONArray.Create;Value:=Resume.Find('loginTokens');end;
    if Value=nil then
    begin
      if not CreateMissing then Exit(Previous);
      Value:=TJSONArray.Create;Resume.Add('loginTokens',Value);
    end;
    if not (Value is TJSONArray) then Invalid;Tokens:=TJSONArray(Value);
    // Clone each original array item's complete schema. Removal shifts positions;
    // inferring types again would lose BSON dates and unknown scalar type metadata.
    OldTypes:=TokenSchemas(Raw);
    Types:=TJSONArray.Create;
    if Tokens.Count>0 then
    begin
      if not (OldTypes is TJSONArray) or (OldTypes.Count<>Tokens.Count) then Invalid;
      for i:=0 to Tokens.Count-1 do Types.Add(OldTypes.Items[i].Clone);
    end;
    if Op='clear' then begin Tokens.Clear;Types.Clear;end
    else if Op='convert' then ConvertLegacy(Tokens,Types,RawToken,Hash)
    else
      for i:=Tokens.Count-1 downto 0 do
      begin
        if Op='expire' then
        begin
          if Timestamp(Tokens.Items[i],Types.Items[i],Number) and (Number<BeforeMs) then
          begin Tokens.Delete(i);Types.Delete(i);end;
          Continue;
        end;
        if Op='retire' then
        begin
          Matched:=False;Value:=Child(Tokens.Items[i],'hashedToken');
          if (Value<>nil) and (Value.JSONType=jtString) then Matched:=Hashes.IndexOf(Value.AsString)>=0;
          if not Matched then
          begin
            Value:=Child(Tokens.Items[i],'token');
            if (Value<>nil) and (Value.JSONType=jtString) and (Value.AsString<>'') and (Length(Value.AsString)<=4096) then
              Matched:=Hashes.IndexOf(MeteorTokenHash(Value.AsString))>=0;
          end;
          if Matched then begin Tokens.Delete(i);Types.Delete(i);end;
          Continue;
        end;
        Value:=Child(Tokens.Items[i],'hashedToken');
        if (Value=nil) or (Value.JSONType<>jtString) or (Value.AsString<>Hash) then
        begin
          if Op<>'revoke' then Continue;
          Value:=Child(Tokens.Items[i],'token');
          if (Value=nil) or (Value.JSONType<>jtString) or (Value.AsString<>RawToken) then Continue;
        end;
        if Op='append' then Invalid;
        Tokens.Delete(i);Types.Delete(i);
      end;
    if Op='append' then
    begin
      Entry:=TJSONObject.Create;Entry.Add('hashedToken',Hash);Entry.Add('when',WhenMs);
      Tokens.Add(Entry);Entry:=nil;
      // Ask the same typed codec to generate the new record's exact Date schema.
      Value:=ExactObject(TypedDocument(Tokens.Items[Tokens.Count-1].AsJSON,'','{"when":"date"}'));
      try
        Entry:=TJSONObject.Create;Entry.Add('t','object');Entry.Add('$s',Child(Value,'$s').Clone);
        Types.Add(Entry);Entry:=nil;
      finally Value.Free;end;
    end;
    Hints:=TJSONObject.Create;HintServices:=TJSONObject.Create;Hints.Add('services',HintServices);
    HintResume:=TJSONObject.Create;HintServices.Add('resume',HintResume);
    ArraySchema:=TJSONObject.Create;HintResume.Add('loginTokens',ArraySchema);
    ArraySchema.Add('t','array');ArraySchema.Add('i',Types);Types:=nil;
    Result:=TypedDocument(Doc.AsJSON,Previous,Hints.AsJSON);
  finally Hashes.Free;Entry.Free;Types.Free;Hints.Free;Cmd.Free;Raw.Free;Doc.Free;end;
end;
end.
