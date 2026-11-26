unit wlsvg;

{
  WeKan-Lite — an SVG attachment shown as an image, as WeKan's
  models/lib/svgSanitizer.js and server/lib/svgResponse.js do it (Weddy's
  svg_sanitize.go): the file without what could run - script,
  foreignObject, the animation and frame elements and their content, any
  on* handler, a script URL (javascript:, vbscript:, livescript:, mocha:)
  however it is spelled with character references or spaces, a data: URL
  of a document type, a dangerous style, a processing instruction, a
  DOCTYPE and its entities.

  Read as XML token by token, by this unit itself: no XML library expands
  an entity here, so an entity loop has nothing to grow. A file that is not
  well-formed is not shown at all, but downloaded.

  Pure: tests/svgclean.py checks it as data.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

const
  MAX_SVG_BYTES = 32 * 1024 * 1024;
  // server/lib/svgResponse.js SVG_INLINE_HEADERS: nothing runs, nothing loads.
  SVG_POLICY = 'default-src ''none''; style-src ''unsafe-inline''; img-src data:; font-src data:; sandbox';

// The SVG without what could run: False for a file that is not well-formed
// XML (or too large). Changed when anything was taken out, and Removed a
// sample of what was.
function SanitizeSvg(const Input: string; out Output: string; out Changed: Boolean; out Removed: string): Boolean;

// svgResponse.js isSvg: by its type, or its name.
function IsSvg(const FileType, Name: string): Boolean;

implementation

uses SysUtils, StrUtils, RegExpr;

const
  DROP_ELEMENTS: array[0..18] of string = ('script', 'foreignobject', 'iframe', 'object', 'embed', 'handler', 'set',
    'animate', 'animatetransform', 'animatemotion', 'animatecolor', 'discard', 'meta', 'link', 'base', 'frame',
    'frameset', 'applet', 'listener');
  URL_ATTRIBUTES: array[0..8] of string = ('href', 'xlink:href', 'src', 'action', 'formaction', 'xml:base', 'data',
    'background', 'poster');

function InList(const Value: string; const List: array of string): Boolean;
var Item: string;
begin
  for Item in List do if Item = Value then Exit(True);
  Result := False;
end;

function IsSvg(const FileType, Name: string): Boolean;
var T, N: string; i: Integer;
begin
  T := FileType;
  i := Pos(';', T); if i > 0 then T := Copy(T, 1, i - 1);
  T := LowerCase(Trim(T));
  N := LowerCase(Name);
  i := Pos('?', N); if i > 0 then N := Copy(N, 1, i - 1);
  i := Pos('#', N); if i > 0 then N := Copy(N, 1, i - 1);
  Result := (T = 'image/svg+xml') or AnsiEndsStr('.svg', N);
end;

// A code point as UTF-8; '' for one XML does not allow.
function Utf8Of(Code: Cardinal): string;
begin
  if (Code = 0) or ((Code >= $D800) and (Code <= $DFFF)) or (Code > $10FFFF) then Exit('');
  if Code < $80 then Result := Chr(Code)
  else if Code < $800 then Result := Chr($C0 or (Code shr 6)) + Chr($80 or (Code and $3F))
  else if Code < $10000 then
    Result := Chr($E0 or (Code shr 12)) + Chr($80 or ((Code shr 6) and $3F)) + Chr($80 or (Code and $3F))
  else
    Result := Chr($F0 or (Code shr 18)) + Chr($80 or ((Code shr 12) and $3F)) + Chr($80 or ((Code shr 6) and $3F)) +
      Chr($80 or (Code and $3F));
end;

// XML's own five references and numeric ones decoded; any other (a DOCTYPE's
// entity) makes the file not well-formed, as a strict reader has it.
function Decode(const S: string; out Text: string): Boolean;
var i, j: Integer; Ref, Ch: string; Code: Int64;
begin
  Result := False; Text := ''; i := 1;
  while i <= Length(S) do
  begin
    if S[i] = '<' then Exit;
    if S[i] <> '&' then begin Text := Text + S[i]; Inc(i); Continue; end;
    j := PosEx(';', S, i + 1);
    if (j = 0) or (j - i > 12) then Exit;
    Ref := Copy(S, i + 1, j - i - 1);
    case Ref of
      'amp': Ch := '&'; 'lt': Ch := '<'; 'gt': Ch := '>'; 'quot': Ch := '"'; 'apos': Ch := '''';
    else
      if (Length(Ref) > 2) and (Ref[1] = '#') and (Ref[2] in ['x', 'X']) then
      begin
        if not TryStrToInt64('$' + Copy(Ref, 3, MaxInt), Code) then Exit;
      end
      else if (Length(Ref) > 1) and (Ref[1] = '#') then
      begin
        if not TryStrToInt64(Copy(Ref, 2, MaxInt), Code) or (Pos('-', Ref) > 0) or (Pos('+', Ref) > 0) then Exit;
      end
      else Exit;
      if (Code < 0) or (Code > $10FFFF) then Exit;
      Ch := Utf8Of(Code);
      if Ch = '' then Exit;
    end;
    Text := Text + Ch;
    i := j + 1;
  end;
  Result := True;
end;

// Go's xml.EscapeText: the text as it can stand in an attribute or between tags.
function Escape(const S: string): string;
var C: Char;
begin
  Result := '';
  for C in S do
    case C of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&#34;';
      '''': Result := Result + '&#39;';
      #9: Result := Result + '&#x9;';
      #10: Result := Result + '&#xA;';
      #13: Result := Result + '&#xD;';
    else Result := Result + C;
    end;
end;

// normalizedValue: the value as a browser reads a scheme in it - without the
// characters it ignores there (C0 controls and space, DEL to NBSP, the soft
// hyphen, zero-width ones, the line and paragraph separators, BOM) - lower case.
function Normalized(const V: string): string;
var i, n: Integer; Code: Cardinal; B: Byte;
begin
  Result := ''; i := 1;
  while i <= Length(V) do
  begin
    B := Ord(V[i]);
    if B < $80 then begin Code := B; n := 1; end
    else if (B and $E0) = $C0 then begin Code := B and $1F; n := 2; end
    else if (B and $F0) = $E0 then begin Code := B and $0F; n := 3; end
    else if (B and $F8) = $F0 then begin Code := B and $07; n := 4; end
    else begin Code := $FFFD; n := 1; end;
    if (n > 1) and (i + n - 1 <= Length(V)) then
    begin
      for B := 1 to n - 1 do Code := (Code shl 6) or (Ord(V[i + B]) and $3F);
    end;
    if not ((Code <= $20) or ((Code >= $7F) and (Code <= $A0)) or (Code = $AD) or ((Code >= $200B) and (Code <= $200F)) or
      (Code = $2028) or (Code = $2029) or (Code = $FEFF)) then
      Result := Result + Copy(V, i, n);
    Inc(i, n);
  end;
  Result := LowerCase(Result);
end;

function Matches(const Pattern, S: string): Boolean;
var R: TRegExpr;
begin
  R := TRegExpr.Create(Pattern);
  try
    Result := R.Exec(S);
  finally
    R.Free;
  end;
end;

const
  SCRIPT_SCHEMES = 'javascript:|vbscript:|livescript:|mocha:';
  DANGEROUS_DATA = '^data:(?:text/html|application/|text/xml|image/svg\+xml;[^,]*charset)';
  CSS_DANGER = 'javascript:|vbscript:|expression\(|-moz-binding|behavior:|@import|url\((?:''|")?(?:javascript|vbscript):';

// attributeIsDangerous.
function AttributeDangerous(const Name, Value: string): Boolean;
var Lower, Local, V: string; i: Integer;
begin
  Lower := LowerCase(Name);
  Local := Lower;
  i := Pos(':', Local); if i > 0 then Local := Copy(Local, i + 1, MaxInt);
  if Copy(Local, 1, 2) = 'on' then Exit(True);
  V := Normalized(Value);
  if Matches(SCRIPT_SCHEMES, V) then Exit(True);
  if (InList(Lower, URL_ATTRIBUTES) or (Local = 'href')) and Matches(DANGEROUS_DATA, V) then Exit(True);
  Result := (Local = 'style') and Matches(CSS_DANGER, V);
end;

function IsNameChar(C: Char; First: Boolean): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '_', ':']) or (Ord(C) >= $80) or (not First and (C in ['0'..'9', '.', '-']));
end;

function SanitizeSvg(const Input: string; out Output: string; out Changed: Boolean; out Removed: string): Boolean;
var i, j, k, Depth, Drop, Notes: Integer; Name, Local, AttrName, Raw, Value, Tag, Text, Style, StyleOpen: string;
  Stack: array of string; InStyle, SelfClose: Boolean; Quote: Char;
  procedure Note(const S: string);
  begin
    Changed := True;
    if Notes < 8 then
    begin
      if Removed <> '' then Removed := Removed + ' ';
      Removed := Removed + S;
      Inc(Notes);
    end;
  end;
  procedure Emit(const S: string);
  begin
    if InStyle then Style := Style + S else Output := Output + S;
  end;
  function LocalOf(const Q: string): string;
  var p: Integer;
  begin
    Result := LowerCase(Q);
    p := Pos(':', Result); if p > 0 then Result := Copy(Result, p + 1, MaxInt);
  end;
  function ReadName(var At: Integer): string;
  var Start: Integer;
  begin
    Start := At;
    if (At > Length(Input)) or not IsNameChar(Input[At], True) then Exit('');
    while (At <= Length(Input)) and IsNameChar(Input[At], False) do Inc(At);
    Result := Copy(Input, Start, At - Start);
  end;
  procedure SkipSpace(var At: Integer);
  begin
    while (At <= Length(Input)) and (Input[At] in [' ', #9, #10, #13]) do Inc(At);
  end;
  procedure CloseElement(const Q: string);
  begin
    if Drop > 0 then begin Dec(Drop); Exit; end;
    if (LowerCase(Q) = 'style') and InStyle then
    begin
      InStyle := False;
      // A sheet that could run or load something goes whole.
      if Matches(CSS_DANGER, Normalized(Style)) then Note('<style>')
      else Output := Output + StyleOpen + Style + '</' + Q + '>';
      Style := '';
      Exit;
    end;
    Emit('</' + Q + '>');
  end;
begin
  Result := False; Output := ''; Changed := False; Removed := ''; Notes := 0;
  if Length(Input) > MAX_SVG_BYTES then Exit;
  Stack := nil; Depth := 0; Drop := 0; InStyle := False; Style := ''; StyleOpen := '';
  i := 1;
  while i <= Length(Input) do
  begin
    if Input[i] <> '<' then
    begin
      j := PosEx('<', Input, i);
      if j = 0 then j := Length(Input) + 1;
      if not Decode(Copy(Input, i, j - i), Text) then Exit;
      // Text outside the root is space only, as XML has it.
      if (Depth = 0) and (Trim(Text) <> '') then Exit;
      if (Drop = 0) and (Depth > 0) then Emit(Escape(Text));
      i := j;
      Continue;
    end;
    if Copy(Input, i, 4) = '<!--' then
    begin
      // Not carried: nothing in a comment draws.
      j := PosEx('-->', Input, i + 4);
      if j = 0 then Exit;
      i := j + 3;
      Continue;
    end;
    if Copy(Input, i, 9) = '<![CDATA[' then
    begin
      j := PosEx(']]>', Input, i + 9);
      if (j = 0) or (Depth = 0) then Exit;
      if Drop = 0 then Emit(Escape(Copy(Input, i + 9, j - i - 9)));
      i := j + 3;
      Continue;
    end;
    if Copy(Input, i, 2) = '<!' then
    begin
      // A DOCTYPE (and its internal subset of entities): never carried.
      if Depth > 0 then Exit;
      j := i + 2; k := 0;
      while (j <= Length(Input)) and not ((Input[j] = '>') and (k = 0)) do
      begin
        if Input[j] = '[' then Inc(k) else if Input[j] = ']' then Dec(k);
        if Input[j] in ['"', ''''] then
        begin
          Quote := Input[j];
          j := PosEx(Quote, Input, j + 1);
          if j = 0 then Exit;
        end;
        Inc(j);
      end;
      if j > Length(Input) then Exit;
      Note('<!' + ExtractWord(1, Copy(Input, i + 2, j - i - 2), [' ', #9, #10, #13, '[', '>']));
      i := j + 1;
      Continue;
    end;
    if Copy(Input, i, 2) = '<?' then
    begin
      j := PosEx('?>', Input, i + 2);
      if j = 0 then Exit;
      k := i + 2;
      Name := ReadName(k);
      if Name = '' then Exit;
      if (Name = 'xml') and (Drop = 0) then Output := Output + Copy(Input, i, j + 2 - i)
      else if Drop = 0 then Note('<?' + Name + '?>');
      i := j + 2;
      Continue;
    end;
    if Copy(Input, i, 2) = '</' then
    begin
      j := i + 2;
      Name := ReadName(j);
      SkipSpace(j);
      if (Name = '') or (j > Length(Input)) or (Input[j] <> '>') then Exit;
      if (Depth = 0) or (Stack[Depth - 1] <> Name) then Exit;
      Dec(Depth);
      CloseElement(Name);
      if Depth = 0 then begin SetLength(Stack, 1); Stack[0] := #0; end;
      i := j + 1;
      Continue;
    end;
    // A start tag and its attributes.
    j := i + 1;
    Name := ReadName(j);
    if Name = '' then Exit;
    // One root element.
    if (Depth = 0) and (Length(Stack) > 0) and (Stack[0] = #0) then Exit;
    Local := LocalOf(Name);
    Tag := '<' + Name;
    SelfClose := False;
    while True do
    begin
      k := j;
      SkipSpace(j);
      if j > Length(Input) then Exit;
      if Input[j] = '>' then begin Inc(j); Break; end;
      if Copy(Input, j, 2) = '/>' then begin SelfClose := True; Inc(j, 2); Break; end;
      if j = k then Exit;   // attributes are separated by space
      AttrName := ReadName(j);
      if AttrName = '' then Exit;
      SkipSpace(j);
      if (j > Length(Input)) or (Input[j] <> '=') then Exit;
      Inc(j);
      SkipSpace(j);
      if (j > Length(Input)) or not (Input[j] in ['"', '''']) then Exit;
      Quote := Input[j];
      k := PosEx(Quote, Input, j + 1);
      if k = 0 then Exit;
      Raw := Copy(Input, j + 1, k - j - 1);
      if not Decode(Raw, Value) then Exit;
      j := k + 1;
      if Drop > 0 then Continue;
      if AttributeDangerous(AttrName, Value) then Note(AttrName + '="' + Value + '"')
      else Tag := Tag + ' ' + AttrName + '="' + Escape(Value) + '"';
    end;
    Tag := Tag + '>';
    i := j;
    if Length(Stack) <= Depth then SetLength(Stack, Depth + 1);
    Stack[Depth] := Name;
    Inc(Depth);
    if Drop > 0 then Inc(Drop)
    else if InList(Local, DROP_ELEMENTS) then
    begin
      Note('<' + Name + '>');
      Drop := 1;
    end
    else if (Local = 'style') and not InStyle then
    begin
      InStyle := True; StyleOpen := Tag; Style := '';
    end
    else Emit(Tag);
    if SelfClose then
    begin
      Dec(Depth);
      CloseElement(Name);
    end;
    // The root is closed: nothing but space, comments and PIs may follow.
    if Depth = 0 then
    begin
      SetLength(Stack, 1); Stack[0] := #0;
    end;
  end;
  if (Depth > 0) or (Drop > 0) or InStyle or (Length(Stack) = 0) then Exit;
  Result := True;
end;

end.
