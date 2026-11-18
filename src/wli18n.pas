unit wli18n;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses SysUtils,Classes,fpjson;
type
  TWLLanguage=record Key,Code,Tag,Name,FileName:string;Rtl:Boolean;end;
  TWLTranslator=class
  private
    FLocal,FParent,FEnglish:TJSONObject;
    FParentFile:string;
  public
    constructor Create(const Language:TWLLanguage);
    destructor Destroy;override;
    function Text(const Key,Fallback:string):string;
  end;
// Initialize once before starting request threads. Failed catalogs retain English only.
function InitLanguages:Boolean;
function LanguageCount:Integer;
function LanguageAt(Index:Integer):TWLLanguage;
function FindLanguage(const Value:string;out Language:TWLLanguage):Boolean;
function ResolveLanguage(const Query,Profile,AcceptLanguage:string):TWLLanguage;
function LanguageIsRtl(const Value:string):Boolean;
implementation
uses jsonparser,wlstatic;
var Languages:array of TWLLanguage;
function English:TWLLanguage;
begin
  Result:=Default(TWLLanguage);Result.Key:='en';Result.Code:='en';
  Result.Tag:='en';Result.Name:='English';Result.FileName:='en.jsn';
end;
function Canonical(const Value:string):string;
begin
  Result:=LowerCase(StringReplace(Trim(Value),'_','-',[rfReplaceAll]));
  if Result='iw' then Result:='he'
  else if Copy(Result,1,3)='iw-' then Result:='he-'+Copy(Result,4,Length(Result));
end;
function SafeName(const Value:string):Boolean;
var i:Integer;
begin
  Result:=False;if (Value='') or (Length(Value)>64) or (Pos('..',Value)>0) then Exit;
  for i:=1 to Length(Value) do if not (Value[i] in ['A'..'Z','a'..'z','0'..'9','_','-','@','.']) then Exit;
  Result:=Value[1] in ['A'..'Z','a'..'z','0'..'9'];
end;
function InitLanguages:Boolean;
var Data:TBytes;Text:string;Root:TJSONData;Items:TJSONArray;Row:TJSONObject;
    Candidate:array of TWLLanguage;i,j:Integer;HasEnglish:Boolean;
  function Required(const Key:string):string;
  var Value:TJSONData;
  begin
    Value:=Row.Find(Key);
    if (Value=nil) or (Value.JSONType<>jtString) then raise Exception.Create('Invalid language field');
    Result:=Value.AsString;
  end;
begin
  Result:=False;SetLength(Languages,1);Languages[0]:=English;Root:=nil;
  if not ReadStaticAsset('/i18n','locales.jsn',Data) then Exit;
  if Length(Data)=0 then Exit;SetString(Text,PChar(@Data[0]),Length(Data));
  try
    try
      Root:=GetJSON(Text,True);
      if (Root.JSONType<>jtArray) or (Root.Count=0) or (Root.Count>1000) then Exit;
      Items:=TJSONArray(Root);SetLength(Candidate,Items.Count);HasEnglish:=False;
      for i:=0 to Items.Count-1 do
      begin
        if Items[i].JSONType<>jtObject then Exit;Row:=TJSONObject(Items[i]);
        Candidate[i].Key:=Required('key');Candidate[i].Code:=Required('code');
        Candidate[i].Tag:=Required('tag');Candidate[i].Name:=Required('name');Candidate[i].FileName:=Required('file');
        if not SafeName(Candidate[i].Key) or not SafeName(Candidate[i].Code) or
          not SafeName(Candidate[i].Tag) or not SafeName(Candidate[i].FileName) or
          (ExtractFileExt(Candidate[i].FileName)<>'.jsn') or (Candidate[i].Name='') or
          (Length(Candidate[i].Name)>1024) then Exit;
        if (Row.Find('rtl')=nil) or (Row.Find('rtl').JSONType<>jtBoolean) then Exit;
        Candidate[i].Rtl:=Row.Booleans['rtl'];
        for j:=0 to i-1 do if SameText(Candidate[j].Key,Candidate[i].Key) or
          SameText(Candidate[j].Tag,Candidate[i].Tag) then Exit;
        if Candidate[i].Tag='en' then HasEnglish:=True;
      end;
      if not HasEnglish then Exit;
      Languages:=Candidate;Result:=True;
    except Result:=False;end;
  finally Root.Free;end;
end;
function LanguageCount:Integer;
begin Result:=Length(Languages);end;
function LanguageAt(Index:Integer):TWLLanguage;
begin
  if (Index<0) or (Index>=Length(Languages)) then Result:=English else Result:=Languages[Index];
end;
function FindLanguage(const Value:string;out Language:TWLLanguage):Boolean;
var i,At:Integer;Want,Parent:string;
begin
  Result:=False;Language:=English;Want:=Trim(Value);
  if not SafeName(Want) then Exit;
  // Exact source aliases win before separator normalization.
  for i:=0 to High(Languages) do if SameText(Want,Languages[i].Tag) or SameText(Want,Languages[i].Key) then
  begin Language:=Languages[i];Exit(True);end;
  Want:=Canonical(Want);
  repeat
    for i:=0 to High(Languages) do if (Want=Canonical(Languages[i].Tag)) or (Want=Canonical(Languages[i].Key)) then
    begin Language:=Languages[i];Exit(True);end;
    At:=LastDelimiter('-',Want);if At=0 then Break;
    Parent:=Copy(Want,1,At-1);Want:=Parent;
  until False;
  for i:=0 to High(Languages) do if Want=Canonical(Languages[i].Code) then
  begin Language:=Languages[i];Exit(True);end;
end;
function Quality(const Value:string;out Weight:Integer):Boolean;
var i:Integer;Digits:string;
begin
  Result:=False;Weight:=0;
  if (Value='0') or (Value='1') then begin Weight:=StrToInt(Value)*1000;Exit(True);end;
  if (Length(Value)<2) or (Length(Value)>5) or not (Value[1] in ['0','1']) or (Value[2]<>'.') then Exit;
  Digits:=Copy(Value,3,3);
  for i:=1 to Length(Digits) do if not (Digits[i] in ['0'..'9']) then Exit;
  if Value[1]='1' then
  begin for i:=1 to Length(Digits) do if Digits[i]<>'0' then Exit;Weight:=1000;end
  else begin while Length(Digits)<3 do Digits:=Digits+'0';Weight:=StrToInt(Digits);end;
  Result:=True;
end;
function ResolveLanguage(const Query,Profile,AcceptLanguage:string):TWLLanguage;
var Parts:TStringList;i,At,Weight,Best:Integer;Part,Range,Param:string;Candidate:TWLLanguage;
begin
  if FindLanguage(Query,Result) or FindLanguage(Profile,Result) then Exit;
  Result:=English;Best:=-1;
  if Length(AcceptLanguage)>8192 then Exit;
  Parts:=TStringList.Create;
  try
    Parts.StrictDelimiter:=True;Parts.Delimiter:=',';Parts.QuoteChar:=#0;Parts.DelimitedText:=AcceptLanguage;
    for i:=0 to Parts.Count-1 do
    begin
      Part:=Trim(Parts[i]);At:=Pos(';',Part);Weight:=1000;
      if At>0 then
      begin
        Range:=Trim(Copy(Part,1,At-1));Param:=Trim(Copy(Part,At+1,Length(Part)));
        if (LowerCase(Copy(Param,1,2))<>'q=') or not Quality(Copy(Param,3,Length(Param)),Weight) then Continue;
      end else Range:=Part;
      if (Weight=0) or (Weight<=Best) then Continue;
      if Range='*' then Candidate:=English
      else if not FindLanguage(Range,Candidate) then Continue;
      Result:=Candidate;Best:=Weight;
    end;
  finally Parts.Free;end;
end;
function LanguageIsRtl(const Value:string):Boolean;
var Language:TWLLanguage;
begin Result:=FindLanguage(Value,Language) and Language.Rtl;end;
function LoadTranslation(const FileName:string):TJSONObject;
var Data:TBytes;Source:string;Root:TJSONData;
begin
  Result:=nil;Root:=nil;
  if not SafeName(FileName) or (ExtractFileExt(FileName)<>'.jsn') or
    not ReadStaticAsset('/i18n','data/'+FileName,Data) or (Length(Data)=0) then Exit;
  SetString(Source,PChar(@Data[0]),Length(Data));
  try
    try
      Root:=GetJSON(Source,True);
      if Root.JSONType=jtObject then begin Result:=TJSONObject(Root);Root:=nil;end;
    except Result:=nil;end;
  finally Root.Free;end;
end;
constructor TWLTranslator.Create(const Language:TWLLanguage);
var Selected,Parent,Fallback:TWLLanguage;Tag:string;At:Integer;
begin
  inherited Create;
  if not FindLanguage('en',Fallback) then Fallback:=English;
  FEnglish:=LoadTranslation(Fallback.FileName);
  if not FindLanguage(Language.Tag,Selected) or (Selected.FileName=Fallback.FileName) then Exit;
  FLocal:=LoadTranslation(Selected.FileName);
  Tag:=Canonical(Selected.Tag);
  At:=LastDelimiter('-',Tag);
  if (At>0) and FindLanguage(Copy(Tag,1,At-1),Parent) and
    (Parent.FileName<>Selected.FileName) and (Parent.FileName<>Fallback.FileName) then
    FParentFile:=Parent.FileName;
end;
destructor TWLTranslator.Destroy;
begin FLocal.Free;FParent.Free;FEnglish.Free;inherited Destroy;end;
function TWLTranslator.Text(const Key,Fallback:string):string;
var Value:TJSONData;
begin
  Result:=Fallback;Value:=nil;
  if FLocal<>nil then Value:=FLocal.Find(Key);
  if (Value<>nil) and (Value.JSONType=jtString) and (Value.AsString<>'') then Exit(Value.AsString);
  if FParentFile<>'' then
  begin
    FParent:=LoadTranslation(FParentFile);
    FParentFile:='';
  end;
  Value:=nil;if FParent<>nil then Value:=FParent.Find(Key);
  if (Value<>nil) and (Value.JSONType=jtString) and (Value.AsString<>'') then Exit(Value.AsString);
  Value:=nil;if FEnglish<>nil then Value:=FEnglish.Find(Key);
  if (Value<>nil) and (Value.JSONType=jtString) and (Value.AsString<>'') then Result:=Value.AsString;
end;
initialization SetLength(Languages,1);Languages[0]:=English;
end.
