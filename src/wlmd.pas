unit wlmd;

{
  WeKan-Lite — WeKan's viewer (packages/markdown, +viewer): a text written
  in Markdown, shown as HTML in the HTML5 view.

  Safe by construction: every character the user typed is escaped first,
  and only Markdown's own syntax becomes markup - paragraphs, headings,
  quotes, lists, fenced code, **strong**, *emphasis*, ~~strike~~, `code`,
  [links](https://...) and bare http(s) addresses. A link goes only to an
  http, https or mailto address or a path of this site; anything else
  (javascript:, data:, //host) is shown as its text. Literal HTML is escaped
  except for paired, attribute-free <strong> tags.

  Pure: tests/markdown.py checks it as plain data.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

// The text as HTML: blocks, each paragraph a <p>.
function MarkdownHtml(const Text: string): string;

// WeKan's +viewer: a one-paragraph text inline in <span class="viewer">,
// anything more in <div class="viewer">. Admin Panel's text display: with
// PlainLinks no link is drawn (renderLinksAsPlainText), with PlainSource the
// source itself is shown (alwaysShowCodeAsText).
function MarkdownViewer(const Text: string; PlainLinks: Boolean = False; PlainSource: Boolean = False): string;

// markdown-it-emoji's emoji for a shortcode (without its colons), or ''.
function EmojiOf(const Code: string): string;

// Whether an address may be a link's target.
function SafeLinkUrl(const Url: string): Boolean;

implementation

uses SysUtils, StrUtils;

{$I wlemoji.inc}

function EmojiOf(const Code: string): string;
var Lo, Hi, Mid, C: Integer;
begin
  Result := '';
  Lo := 0; Hi := EMOJI_COUNT - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    C := CompareStr(EMOJI_CODES[Mid], Code);
    if C = 0 then Exit(EMOJI_CHARS[Mid]);
    if C < 0 then Lo := Mid + 1 else Hi := Mid - 1;
  end;
end;

threadvar
  // Admin Panel's renderLinksAsPlainText, for the Markdown this thread draws
  // (the server answers requests on threads of its own).
  NoLinks: Boolean;

function Esc(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&#39;', [rfReplaceAll]);
end;

function SafeLinkUrl(const Url: string): Boolean;
var i: Integer; L: string;
begin
  Result := False;
  if (Url = '') or (Length(Url) > 2048) then Exit;
  for i := 1 to Length(Url) do
    if (Url[i] <= ' ') or (Url[i] = #127) or (Url[i] = '\') then Exit;
  L := LowerCase(Url);
  if (Copy(L, 1, 7) = 'http://') or (Copy(L, 1, 8) = 'https://') or (Copy(L, 1, 7) = 'mailto:') then Exit(True);
  // A path of this site, never //host.
  Result := ((L[1] = '/') and (Copy(L, 1, 2) <> '//')) or (L[1] = '#');
end;

function Link(const Url, InnerHtml: string): string;
begin
  if NoLinks then Exit(InnerHtml);
  Result := '<a href="' + Esc(Url) + '" rel="nofollow noopener" target="_blank">' + InnerHtml + '</a>';
end;

function Inline(const S: string): string; forward;

// The closing Marker after position From, on the same text; 0 when none.
function Closing(const S, Marker: string; From: Integer): Integer;
begin
  Result := PosEx(Marker, S, From);
end;

function Inline(const S: string): string;
var i, j, k: Integer; Text, Url: string;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    // `code`: its text exactly, escaped.
    if S[i] = '`' then
    begin
      j := Closing(S, '`', i + 1);
      if j > i + 1 then
      begin
        Result := Result + '<code>' + Esc(Copy(S, i + 1, j - i - 1)) + '</code>';
        i := j + 1; Continue;
      end;
    end;
    // [text](url)
    if S[i] = '[' then
    begin
      j := Closing(S, '](', i + 1);
      if j > i then
      begin
        k := Closing(S, ')', j + 2);
        if k > j + 2 then
        begin
          Text := Copy(S, i + 1, j - i - 1);
          Url := Copy(S, j + 2, k - j - 2);
          if SafeLinkUrl(Url) then Result := Result + Link(Url, Inline(Text))
          else Result := Result + Inline(Text);
          i := k + 1; Continue;
        end;
      end;
    end;
    // A bare http(s) address, up to the next space.
    if ((S[i] = 'h') or (S[i] = 'H')) and ((i = 1) or (S[i - 1] in [' ', #9, '(', '"'])) and
      ((LowerCase(Copy(S, i, 7)) = 'http://') or (LowerCase(Copy(S, i, 8)) = 'https://')) then
    begin
      j := i;
      while (j <= Length(S)) and not (S[j] in [' ', #9, '<', '>', '"']) do Inc(j);
      // A sentence's last stop is not part of the address.
      while (j - 1 > i) and (S[j - 1] in ['.', ',', ';', ':', '!', '?', ')']) do Dec(j);
      Url := Copy(S, i, j - i);
      if SafeLinkUrl(Url) then
      begin
        Result := Result + Link(Url, Esc(Url));
        i := j; Continue;
      end;
    end;
    // :shortcode: (markdown-it-emoji), never inside code.
    if S[i] = ':' then
    begin
      j := i + 1;
      while (j <= Length(S)) and (S[j] in ['a'..'z', '0'..'9', '_', '+', '-']) do Inc(j);
      if (j <= Length(S)) and (S[j] = ':') and (j > i + 1) then
      begin
        Text := EmojiOf(Copy(S, i + 1, j - i - 1));
        if Text <> '' then
        begin
          Result := Result + Text;
          i := j + 1; Continue;
        end;
      end;
    end;
    if Copy(S, i, 8) = '<strong>' then
    begin
      j := Closing(S, '</strong>', i + 8);
      if j > 0 then
      begin
        Result := Result + '<strong>' + Inline(Copy(S, i + 8, j - i - 8)) + '</strong>';
        i := j + 9; Continue;
      end;
    end;
    // **strong**, ~~strike~~, *emphasis*
    if (Copy(S, i, 2) = '**') or (Copy(S, i, 2) = '__') then
    begin
      j := Closing(S, Copy(S, i, 2), i + 2);
      if j > i + 2 then
      begin
        Result := Result + '<strong>' + Inline(Copy(S, i + 2, j - i - 2)) + '</strong>';
        i := j + 2; Continue;
      end;
    end;
    if Copy(S, i, 2) = '~~' then
    begin
      j := Closing(S, '~~', i + 2);
      if j > i + 2 then
      begin
        Result := Result + '<del>' + Inline(Copy(S, i + 2, j - i - 2)) + '</del>';
        i := j + 2; Continue;
      end;
    end;
    if (S[i] = '*') and (i < Length(S)) and (S[i + 1] <> ' ') then
    begin
      j := Closing(S, '*', i + 1);
      if (j > i + 1) and (S[j - 1] <> ' ') then
      begin
        Result := Result + '<em>' + Inline(Copy(S, i + 1, j - i - 1)) + '</em>';
        i := j + 1; Continue;
      end;
    end;
    Result := Result + Esc(S[i]);
    Inc(i);
  end;
end;

function IsBullet(const Line: string; out Rest: string): Boolean;
begin
  Result := (Length(Line) >= 2) and (Line[1] in ['-', '*', '+']) and (Line[2] = ' ');
  if Result then Rest := Copy(Line, 3, MaxInt);
end;

function IsNumbered(const Line: string; out Rest: string): Boolean;
var i: Integer;
begin
  Result := False;
  i := 1;
  while (i <= Length(Line)) and (Line[i] in ['0'..'9']) do Inc(i);
  if (i = 1) or (i > 10) or (i + 1 > Length(Line)) or (Line[i] <> '.') or (Line[i + 1] <> ' ') then Exit;
  Rest := Copy(Line, i + 2, MaxInt);
  Result := True;
end;

function MarkdownHtml(const Text: string): string;
var Lines: TStringArray; i, Level: Integer; Line, Trimmed, Rest, Para, Code: string;
  InCode: Boolean; ListKind: Char;
  procedure EndPara;
  begin
    if Para <> '' then Result := Result + '<p>' + Para + '</p>';
    Para := '';
  end;
  procedure EndList;
  begin
    if ListKind = 'u' then Result := Result + '</ul>'
    else if ListKind = 'o' then Result := Result + '</ol>';
    ListKind := ' ';
  end;
begin
  Result := ''; Para := ''; Code := ''; InCode := False; ListKind := ' ';
  Lines := StringReplace(StringReplace(Text, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]).Split([#10]);
  for i := 0 to High(Lines) do
  begin
    Line := Lines[i];
    Trimmed := Trim(Line);
    if Copy(Trimmed, 1, 3) = '```' then
    begin
      if InCode then
      begin
        Result := Result + '<pre><code>' + Esc(Code) + '</code></pre>';
        Code := ''; InCode := False;
      end
      else begin EndPara; EndList; InCode := True; end;
      Continue;
    end;
    if InCode then
    begin
      if Code <> '' then Code := Code + #10;
      Code := Code + Line;
      Continue;
    end;
    if Trimmed = '' then begin EndPara; EndList; Continue; end;
    if Trimmed[1] = '#' then
    begin
      Level := 0;
      while (Level < Length(Trimmed)) and (Trimmed[Level + 1] = '#') do Inc(Level);
      if (Level <= 6) and (Level < Length(Trimmed)) and (Trimmed[Level + 1] = ' ') then
      begin
        EndPara; EndList;
        Result := Result + '<h' + IntToStr(Level) + '>' + Inline(Trim(Copy(Trimmed, Level + 2, MaxInt))) +
          '</h' + IntToStr(Level) + '>';
        Continue;
      end;
    end;
    if Trimmed[1] = '>' then
    begin
      EndPara; EndList;
      Result := Result + '<blockquote><p>' + Inline(Trim(Copy(Trimmed, 2, MaxInt))) + '</p></blockquote>';
      Continue;
    end;
    if IsBullet(Trimmed, Rest) then
    begin
      EndPara;
      if ListKind <> 'u' then begin EndList; Result := Result + '<ul>'; ListKind := 'u'; end;
      Result := Result + '<li>' + Inline(Rest) + '</li>';
      Continue;
    end;
    if IsNumbered(Trimmed, Rest) then
    begin
      EndPara;
      if ListKind <> 'o' then begin EndList; Result := Result + '<ol>'; ListKind := 'o'; end;
      Result := Result + '<li>' + Inline(Rest) + '</li>';
      Continue;
    end;
    EndList;
    // WeKan's Markdown keeps a line break as one (breaks: true).
    if Para <> '' then Para := Para + '<br>';
    Para := Para + Inline(Trimmed);
  end;
  if InCode then Result := Result + '<pre><code>' + Esc(Code) + '</code></pre>';
  EndPara; EndList;
end;

function MarkdownViewer(const Text: string; PlainLinks: Boolean; PlainSource: Boolean): string;
var Html: string;
begin
  if PlainSource then Exit('<div class="viewer"><pre>' + Esc(Text) + '</pre></div>');
  NoLinks := PlainLinks;
  try
    Html := MarkdownHtml(Text);
  finally
    NoLinks := False;
  end;
  if (Copy(Html, 1, 3) = '<p>') and (Copy(Html, Length(Html) - 3, 4) = '</p>') and (PosEx('<p>', Html, 2) = 0) then
    Result := '<span class="viewer">' + Copy(Html, 4, Length(Html) - 7) + '</span>'
  else
    Result := '<div class="viewer">' + Html + '</div>';
end;

end.
