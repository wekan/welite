unit wlresume;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses SysUtils,Math,fpjson,base64,wlcrypt,wlsjson;
// Meteor's shared token digest is SHA256(raw UTF-8 bytes), standard padded base64.
// It is deliberately distinct from WeLite's tenant-scoped private token digest.
function MeteorTokenHash(const Token:string):string;
// Pure SJSON edit: append {hashedToken,when:BSON Date}, remove matching hashes,
// clear all records, expire old records, or revoke both forms of one raw bearer.
// This function does not authorize the caller.
function ResumeDocument(const Previous,Command:string):string;
type TResumeState=(rsAbsent,rsValid,rsExpired,rsInvalid);
function CheckResumeToken(const Previous,Hash:string;NowMs,LifetimeMs:Int64;
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
procedure ValidateHash(const Hash:string);
var Bytes:RawByteString;
begin
  if Length(Hash)<>44 then Invalid;
  Bytes:=DecodeStringBase64(Hash);
  if (Length(Bytes)<>32) or (EncodeStringBase64(Bytes)<>Hash) then Invalid;
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
function CheckResumeToken(const Previous,Hash:string;NowMs,LifetimeMs:Int64;
  out WhenMs,ExpiresMs:Int64):TResumeState;
const MaxDateMs:Int64=8640000000000000; // JavaScript Date TimeClip limit
var Doc,Raw,Services,Resume:TJSONObject;Tokens,Schemas,Value:TJSONData;
  i,Found:Integer;Number:Double;Stamp,Expiration:Int64;
begin
  Result:=rsInvalid;WhenMs:=0;ExpiresMs:=0;Doc:=nil;Raw:=nil;
  try
    try
      ValidateHash(Hash);
      if (NowMs< -MaxDateMs) or (NowMs>MaxDateMs) or (LifetimeMs<=0) or (LifetimeMs>2*MaxDateMs) then Exit;
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
      if Stamp>MaxDateMs-LifetimeMs then Exit;
      Expiration:=Stamp+LifetimeMs;
      if NowMs>=Expiration then Exit(rsExpired);
      WhenMs:=Stamp;ExpiresMs:=Expiration;Result:=rsValid;
    except Result:=rsInvalid;WhenMs:=0;ExpiresMs:=0;end;
  finally Raw.Free;Doc.Free;end;
end;
function ResumeDocument(const Previous,Command:string):string;
var Doc,Raw,Cmd,Services,Resume,Hints,HintServices,HintResume,ArraySchema,Entry:TJSONObject;
  Tokens,Types:TJSONArray;Value,OldTypes:TJSONData;Op,Hash,Name,RawToken:string;
  i:Integer;WhenMs,BeforeMs:Int64;Number:Double;CreateMissing:Boolean;
begin
  Doc:=nil;Raw:=nil;Cmd:=nil;Hints:=nil;Types:=nil;Entry:=nil;
  try
    Doc:=ExactObject(PlainDocument(Previous));Raw:=ExactObject(Previous);Cmd:=ExactObject(Command);
    Value:=Cmd.Find('op');if (Value=nil) or (Value.JSONType<>jtString) then Invalid;Op:=Value.AsString;
    if (Op<>'append') and (Op<>'remove') and (Op<>'clear') and (Op<>'expire') and (Op<>'revoke') then Invalid;
    for i:=0 to Cmd.Count-1 do
    begin
      Name:=Cmd.Names[i];if Name='op' then Continue;
      if (Name='hashedToken') and ((Op='append') or (Op='remove')) then Continue;
      if (Name='token') and (Op='revoke') then Continue;
      if (Name='before') and (Op='expire') then Continue;
      if (Name='when') and (Op='append') then Continue;
      Invalid;
    end;
    if (Op='append') or (Op='remove') then
    begin
      Value:=Cmd.Find('hashedToken');if (Value=nil) or (Value.JSONType<>jtString) then Invalid;
      Hash:=Value.AsString;ValidateHash(Hash);
    end;
    RawToken:='';
    if Op='revoke' then
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
    else
      for i:=Tokens.Count-1 downto 0 do
      begin
        if Op='expire' then
        begin
          if Timestamp(Tokens.Items[i],Types.Items[i],Number) and (Number<BeforeMs) then
          begin Tokens.Delete(i);Types.Delete(i);end;
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
  finally Entry.Free;Types.Free;Hints.Free;Cmd.Free;Raw.Free;Doc.Free;end;
end;
end.
