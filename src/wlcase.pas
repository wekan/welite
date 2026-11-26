unit wlcase;

{
  WeKan-Lite — upper and lower case of UTF-8 text, without a unicodestring
  manager: WeLite installs none (a binary without cwstring writes "no string
  conversion support" and gives an empty string), so this maps the letters
  itself. ASCII, Latin-1, Latin Extended-A, Greek and Cyrillic: the letters
  of the languages WeKan's rule texts and card titles are written in; any
  other character stays as it is.

  Pure: tests/textcase.py checks it.
}

{$mode objfpc}{$H+}

interface

function Utf8Lower(const S: string): string;
function Utf8Upper(const S: string): string;
// The text with its first letter in capitals (ruleDetails.js).
function Utf8CapitalFirst(const S: string): string;

implementation

// The code point at S[i] and its byte length; a broken sequence is one byte.
function Decode(const S: string; i: Integer; out Len: Integer): LongWord;
var C: Byte;
begin
  C := Ord(S[i]);
  Len := 1;
  Result := C;
  if (C >= $C0) and (C < $E0) and (i + 1 <= Length(S)) and (Ord(S[i + 1]) and $C0 = $80) then
  begin
    Len := 2;
    Result := ((C and $1F) shl 6) or (Ord(S[i + 1]) and $3F);
  end
  else if (C >= $E0) and (C < $F0) and (i + 2 <= Length(S)) and (Ord(S[i + 1]) and $C0 = $80) and (Ord(S[i + 2]) and $C0 = $80) then
  begin
    Len := 3;
    Result := ((C and $0F) shl 12) or ((Ord(S[i + 1]) and $3F) shl 6) or (Ord(S[i + 2]) and $3F);
  end;
end;

function Encode(C: LongWord): string;
begin
  if C < $80 then Result := Chr(C)
  else if C < $800 then Result := Chr($C0 or (C shr 6)) + Chr($80 or (C and $3F))
  else Result := Chr($E0 or (C shr 12)) + Chr($80 or ((C shr 6) and $3F)) + Chr($80 or (C and $3F));
end;

function LowerOf(C: LongWord): LongWord;
begin
  Result := C;
  case C of
    $41..$5A: Result := C + $20;
    $C0..$D6, $D8..$DE: Result := C + $20;
    $100..$137, $14A..$177: if not Odd(C) then Result := C + 1;
    $139..$148, $179..$17E: if Odd(C) then Result := C + 1;
    $178: Result := $FF;
    $391..$3A1, $3A3..$3AB: Result := C + $20;
    $386: Result := $3AC;
    $388..$38A: Result := C + $25;
    $38C: Result := $3CC;
    $38E, $38F: Result := C + $3F;
    $400..$40F: Result := C + $50;
    $410..$42F: Result := C + $20;
    $460..$481, $48A..$4BF, $4D0..$52F: if not Odd(C) then Result := C + 1;
    $4C1..$4CE: if Odd(C) then Result := C + 1;
    $4C0: Result := $4CF;
  end;
end;

function UpperOf(C: LongWord): LongWord;
begin
  Result := C;
  case C of
    $61..$7A: Result := C - $20;
    $E0..$F6, $F8..$FE: Result := C - $20;
    $FF: Result := $178;
    $100..$137, $14A..$177: if Odd(C) then Result := C - 1;
    $139..$148, $179..$17E: if not Odd(C) then Result := C - 1;
    $3B1..$3C1, $3C3..$3CB: Result := C - $20;
    $3C2: Result := $3A3;
    $3AC: Result := $386;
    $3AD..$3AF: Result := C - $25;
    $3CC: Result := $38C;
    $3CD, $3CE: Result := C - $3F;
    $430..$44F: Result := C - $20;
    $450..$45F: Result := C - $50;
    $460..$481, $48A..$4BF, $4D0..$52F: if Odd(C) then Result := C - 1;
    $4C1..$4CE: if not Odd(C) then Result := C - 1;
    $4CF: Result := $4C0;
  end;
end;

function Map(const S: string; Upper: Boolean; FirstOnly: Boolean): string;
var i, Len: Integer; C: LongWord;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    C := Decode(S, i, Len);
    if (Len = 1) and (C >= $80) then Result := Result + S[i]
    else if Upper then Result := Result + Encode(UpperOf(C))
    else Result := Result + Encode(LowerOf(C));
    Inc(i, Len);
    if FirstOnly then
    begin
      Result := Result + Copy(S, i, MaxInt);
      Exit;
    end;
  end;
end;

function Utf8Lower(const S: string): string;
begin
  Result := Map(S, False, False);
end;

function Utf8Upper(const S: string): string;
begin
  Result := Map(S, True, False);
end;

function Utf8CapitalFirst(const S: string): string;
begin
  Result := Map(S, True, True);
end;

end.
