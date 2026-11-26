unit wlflag;

{
  WeKan-Lite — WeKan's language flags (imports/i18n/languageFlags.js), for
  the HTML5 view's changeLanguagePopup: the flag of a language tag's
  language, the flag of its region, and a language's name split into the
  language and the region its name already says.

  Pure: tests/langflag.py checks it as plain data.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

// languageFlags(tag): the language's flag (🌐 for one with none) and, for a
// tag with a region (-, _ or @), the region's flag; '' for a tag without.
procedure LanguageFlags(const Tag: string; out Language, Country: string);

// languageLabelParts(name, country): "English (Brazil)" is English and
// Brazil, "Español de Colombia" Español and Colombia; a name with no region
// in it stays whole. Without a country flag the name is not split.
procedure LanguageLabelParts(const Name, Country: string; out LanguageName, RegionName: string);

implementation

uses SysUtils;

{$I wlflags.inc}

const
  GLOBE = #$f0#$9f#$8c#$90;

function Find(const Keys: array of string; const Key: string): Integer;
var Lo, Hi, Mid, C: Integer;
begin
  Lo := 0; Hi := High(Keys);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    C := CompareStr(Keys[Mid], Key);
    if C = 0 then Exit(Mid);
    if C < 0 then Lo := Mid + 1 else Hi := Mid - 1;
  end;
  Result := -1;
end;

// The first separator of a tag (-, _ or @), 0 when none.
function Separator(const Tag: string; From: Integer): Integer;
var i: Integer;
begin
  for i := From to Length(Tag) do
    if Tag[i] in ['-', '_', '@'] then Exit(i);
  Result := 0;
end;

// A regional indicator symbol's UTF-8 for an A..Z letter: U+1F1E6 + n.
function Indicator(Letter: Char): string;
var Code: Integer;
begin
  Code := $1F1E6 + Ord(Letter) - Ord('A');
  Result := Chr($F0) + Chr($80 or ((Code shr 12) and $3F)) + Chr($80 or ((Code shr 6) and $3F)) + Chr($80 or (Code and $3F));
end;

procedure LanguageFlags(const Tag: string; out Language, Country: string);
var At, Next, i: Integer; Base, Suffix: string;
begin
  At := Separator(Tag, 1);
  if At > 0 then Base := Copy(Tag, 1, At - 1) else Base := Tag;
  i := Find(TAG_LANGUAGE_FLAG_KEYS, Tag);
  if i >= 0 then Language := TAG_LANGUAGE_FLAG_FLAGS[i]
  else
  begin
    i := Find(LANGUAGE_FLAG_KEYS, Base);
    if i >= 0 then Language := LANGUAGE_FLAG_FLAGS[i] else Language := GLOBE;
  end;
  Country := '';
  if At = 0 then Exit;
  i := Find(TAG_COUNTRY_FLAG_KEYS, Tag);
  if i >= 0 then begin Country := TAG_COUNTRY_FLAG_FLAGS[i]; Exit; end;
  // The part between the first separator and the next one.
  Next := Separator(Tag, At + 1);
  if Next > 0 then Suffix := Copy(Tag, At + 1, Next - At - 1) else Suffix := Copy(Tag, At + 1, MaxInt);
  if (Suffix <> '') and (Pos(' ' + Suffix + ' ', FLAG_REGIONS) > 0) then
  begin
    for i := 1 to Length(Suffix) do Country := Country + Indicator(Suffix[i]);
  end
  else Country := Language;
end;

procedure LanguageLabelParts(const Name, Country: string; out LanguageName, RegionName: string);
const
  OpenWide = #$ef#$bc#$88;   // （
  CloseWide = #$ef#$bc#$89;  // ）
var Close, Open, i: Integer; Inner, Rest: string;
  function IsOpen(At: Integer): Integer;
  begin
    if Name[At] = '(' then Exit(1);
    if Copy(Name, At, 3) = OpenWide then Exit(3);
    Result := 0;
  end;
begin
  LanguageName := Name; RegionName := '';
  if Country = '' then Exit;
  // "Name (Region)": the last parenthesis at the end, with no other inside.
  Close := 0;
  if (Name <> '') and (Name[Length(Name)] = ')') then Close := Length(Name)
  else if (Length(Name) >= 3) and (Copy(Name, Length(Name) - 2, 3) = CloseWide) then Close := Length(Name) - 2;
  if Close > 0 then
  begin
    Open := 0;
    for i := Close - 1 downto 1 do
      if IsOpen(i) > 0 then begin Open := i; Break; end;
    if Open > 0 then
    begin
      Inner := Copy(Name, Open + IsOpen(Open), Close - Open - IsOpen(Open));
      if (Inner <> '') and (Pos('(', Inner) = 0) and (Pos(')', Inner) = 0) and (Pos(OpenWide, Inner) = 0) and
        (Pos(CloseWide, Inner) = 0) then
      begin
        LanguageName := Trim(Copy(Name, 1, Open - 1));
        RegionName := Inner;
        Exit;
      end;
    end;
  end;
  // "Español de Colombia", "Português do Brasil".
  for Rest in ['Español ', 'Português '] do
    if Copy(Name, 1, Length(Rest)) = Rest then
      for Inner in ['en ', 'de ', 'do '] do
        if (Copy(Name, Length(Rest) + 1, 3) = Inner) and (Length(Name) > Length(Rest) + 3) then
        begin
          LanguageName := Trim(Rest);
          RegionName := Copy(Name, Length(Rest) + 4, MaxInt);
          Exit;
        end;
end;

end.
