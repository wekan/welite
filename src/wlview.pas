unit wlview;

{
  WeKan-Lite — which of the two views a request gets.

  WeLite has two user interfaces on one backend: the HTML4 view for retro
  browsers (IBrowse, NetSurf, Dillo, Lynx, w3m, old Internet Explorer...), and
  the HTML5 view - Weddy's, which is WeKan's own markup, class names, CSS and
  script - for modern browsers (wlh5.pas). The User-Agent chooses. The viewer
  can switch with the HTML4/HTML5 toggle in the top header, made like WeKan's
  mobile/desktop toggle (.js-mobile-mode-toggle in WeKan's header.jade): it
  links to the same page with ?ui=html4 or ?ui=html5, which is remembered in a
  `welite-ui` cookie where the browser keeps cookies. The HTML4 view never
  needs that cookie: it is what a browser without one gets anyway.

  Pure: tests/view.py checks the choice and the toggle as plain data.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, HTTPDefs;

type
  TWLView = (wvHtml4, wvHtml5);

const
  VIEW_COOKIE = 'welite-ui';

// The view a User-Agent gets when the viewer has not chosen: HTML5 for
// Chromium 90+, Firefox 90+ and Safari 14+ (and browsers built on them), HTML4
// for everything else - retro browsers, old versions and anything unknown.
function DefaultView(const UserAgent: string): TWLView;

// 'html4' or 'html5' -> the view; anything else is not a choice.
function ParseView(const Value: string; out View: TWLView): Boolean;
function ViewName(View: TWLView): string;

// The view of this request: ?ui= first, then the cookie, then the User-Agent.
function RequestView(Request: TRequest): TWLView;

// When the request chose a view with ?ui=, remember it in the cookie.
procedure RememberView(Request: TRequest; Response: TResponse);

// PathAndQuery with ui=<view> set: the target of the toggle.
function ViewSwitchUrl(const PathAndQuery: string; Target: TWLView): string;

// The toggle for the HTML5 view's header: WeKan's header button, its icon
// the view it switches to.
function Html5ViewToggle(const PathAndQuery, Title: string): string;

implementation

function VersionAfter(const UserAgent, Marker: string): Integer;
var At, i: Integer; Digits: string;
begin
  Result := -1;
  At := Pos(Marker, UserAgent);
  if At = 0 then Exit;
  i := At + Length(Marker);
  Digits := '';
  while (i <= Length(UserAgent)) and (UserAgent[i] in ['0'..'9']) do
  begin
    Digits := Digits + UserAgent[i];
    Inc(i);
  end;
  Result := StrToIntDef(Digits, -1);
end;

function DefaultView(const UserAgent: string): TWLView;
var V: Integer;
begin
  Result := wvHtml4;
  // Retro and text browsers first: some of them name a modern engine too.
  if (Pos('IBrowse', UserAgent) > 0) or (Pos('NetSurf', UserAgent) > 0) or
     (Pos('Dillo', UserAgent) > 0) or (Pos('Lynx', UserAgent) > 0) or
     (Pos('w3m', UserAgent) > 0) or (Pos('Links', UserAgent) > 0) or
     (Pos('MSIE', UserAgent) > 0) or (Pos('Trident/', UserAgent) > 0) or
     (Pos('PaleMoon', UserAgent) > 0) or (Pos('Goanna', UserAgent) > 0) then Exit;
  // Chromium and everything on it: Chrome, Edge, Brave, Opera, headless Chrome.
  V := VersionAfter(UserAgent, 'Chrome/');
  if V >= 90 then Exit(wvHtml5);
  V := VersionAfter(UserAgent, 'Firefox/');
  if V >= 90 then Exit(wvHtml5);
  // Safari reports its own version as Version/N beside Safari/.
  if (Pos('Safari/', UserAgent) > 0) and (Pos('Chrome/', UserAgent) = 0) then
  begin
    V := VersionAfter(UserAgent, 'Version/');
    if V >= 14 then Exit(wvHtml5);
  end;
end;

function ParseView(const Value: string; out View: TWLView): Boolean;
begin
  Result := True;
  if SameText(Value, 'html4') then View := wvHtml4
  else if SameText(Value, 'html5') then View := wvHtml5
  else Result := False;
end;

function ViewName(View: TWLView): string;
begin
  if View = wvHtml5 then Result := 'html5' else Result := 'html4';
end;

function RequestView(Request: TRequest): TWLView;
begin
  if ParseView(Request.QueryFields.Values['ui'], Result) then Exit;
  if ParseView(Request.CookieFields.Values[VIEW_COOKIE], Result) then Exit;
  Result := DefaultView(Request.UserAgent);
end;

procedure RememberView(Request: TRequest; Response: TResponse);
var View: TWLView; C: TCookie;
begin
  if not ParseView(Request.QueryFields.Values['ui'], View) then Exit;
  C := Response.Cookies.Add;
  C.Name := VIEW_COOKIE;
  C.Value := ViewName(View);
  C.Path := '/';
  C.HttpOnly := True;
  // A year: the viewer chose it, and nothing about it is secret.
  C.Expires := Now + 365;
end;

function ViewSwitchUrl(const PathAndQuery: string; Target: TWLView): string;
var Path, Query, Part, Rest: string; At: Integer;
begin
  At := Pos('?', PathAndQuery);
  if At = 0 then begin Path := PathAndQuery; Query := ''; end
  else begin Path := Copy(PathAndQuery, 1, At - 1); Query := Copy(PathAndQuery, At + 1, MaxInt); end;
  if (Path = '') or (Path[1] <> '/') or (Copy(Path, 1, 2) = '//') then Path := '/';
  // Drop an earlier ui= so the link says one view.
  Rest := '';
  while Query <> '' do
  begin
    At := Pos('&', Query);
    if At = 0 then begin Part := Query; Query := ''; end
    else begin Part := Copy(Query, 1, At - 1); Query := Copy(Query, At + 1, MaxInt); end;
    if (Part <> '') and (Copy(Part, 1, 3) <> 'ui=') then
    begin
      if Rest <> '' then Rest := Rest + '&';
      Rest := Rest + Part;
    end;
  end;
  if Rest <> '' then Rest := Rest + '&';
  Result := Path + '?' + Rest + 'ui=' + ViewName(Target);
end;

function Attr(const Value: string): string;
begin
  Result := StringReplace(Value, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

function Html5ViewToggle(const PathAndQuery, Title: string): string;
begin
  // WeKan's .mobile-mode-toggle markup: a header button whose class says the
  // current view and whose icon is the current one; it switches to HTML4.
  Result := '<div class="html-view-toggle js-header-collapsible-icon">' +
    '<a class="board-header-btn js-html-view-toggle html5-active" href="' +
    Attr(ViewSwitchUrl(PathAndQuery, wvHtml4)) + '" title="' + Attr(Title) +
    '" aria-label="' + Attr(Title) + '" data-view="html5">HTML5</a></div>';
end;

end.
