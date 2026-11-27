unit wlfold;

{$mode objfpc}{$H+}

interface

// Compare a SQL text column with a title label using Unicode default case
// folding. The expression uses stock SQLite on both database backends.
function LabelFoldMatch(const Column, Name: string): string;

implementation

uses SysUtils;

type
  TFoldEntry = record
    Code: Cardinal;
    Folded: string;
  end;

{$I wlfold.inc}

function CaseFold(const Value: string): string;
var i, First, Count, n, Lo, Hi, Mid: Integer; Code, ByteValue: Cardinal;
begin
  Result := '';
  i := 1;
  while i <= Length(Value) do
  begin
    First := i;
    ByteValue := Ord(Value[i]);
    Inc(i);
    Count := 0;
    Code := ByteValue;
    if (ByteValue and $E0) = $C0 then begin Count := 1; Code := ByteValue and $1F; end
    else if (ByteValue and $F0) = $E0 then begin Count := 2; Code := ByteValue and $0F; end
    else if (ByteValue and $F8) = $F0 then begin Count := 3; Code := ByteValue and $07; end;
    for n := 1 to Count do
    begin
      if (i > Length(Value)) or ((Ord(Value[i]) and $C0) <> $80) then
      begin Code := ByteValue; i := First + 1; Break; end;
      Code := (Code shl 6) or (Ord(Value[i]) and $3F);
      Inc(i);
    end;
    Lo := Low(FoldMap); Hi := High(FoldMap);
    while Lo <= Hi do
    begin
      Mid := (Lo + Hi) div 2;
      if FoldMap[Mid].Code = Code then Break;
      if FoldMap[Mid].Code < Code then Lo := Mid + 1 else Hi := Mid - 1;
    end;
    if Lo <= Hi then Result := Result + FoldMap[Mid].Folded
    else Result := Result + Copy(Value, First, i - First);
  end;
end;

function LabelFoldMatch(const Column, Name: string): string;
var Needle, CharSql, Choices: string; Entry: TFoldEntry;
begin
  Needle := CaseFold(Name);
  CharSql := 'substr(' + Column + ',n,1)';
  Choices := '';
  // Any fold expansion in a matching label must occur in the folded name.
  for Entry in FoldMap do
    if Pos(Entry.Folded, Needle) > 0 then
      Choices := Choices + ' WHEN ' + IntToStr(Entry.Code) + ' THEN ' + QuotedStr(Entry.Folded);
  if Choices = '' then Exit(Column + '=' + QuotedStr(Needle));
  Result := '(WITH RECURSIVE folded(n,value) AS (VALUES(1,'''') UNION ALL SELECT n+1,' +
    ' value || CASE unicode(' + CharSql + ')' + Choices + ' ELSE ' + CharSql + ' END' +
    ' FROM folded WHERE n<=length(' + Column + ')) SELECT value FROM folded WHERE n=length(' +
    Column + ')+1)=' + QuotedStr(Needle);
end;

end.
