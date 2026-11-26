unit wlh5;

{
  WeKan-Lite — the HTML5 view: Weddy's pages, which are WeKan's own markup,
  class names, CSS and script (caddy-wekan-plugin's web/templates/*.pug and
  web/static), rendered from WeLite's data. A modern browser gets these; a
  retro one gets the HTML4 view (wlview.pas chooses).

  What is here, page by page, as Weddy has it:

    layout.pug    the header: All Boards, the board's title, the HTML4/HTML5
                  toggle, the user and Log Out
    signin.pug    the sign-in form (useraccounts' #at-pwd-form)
    boards.pug    All Boards with its sections (Starred, Remaining)
    board.pug     the board: .board-wrapper, its header, the canvas with
                  swimlanes, lists and minicards, and the opened card's
                  details (.js-card-details)
    notfound.pug  "Board not found"

  Everything is read with the same queries and the same access checks as the
  HTML4 view (wlboard.pas): a board the viewer may not read is not found.
  The static files are Weddy's, under 8.3 names in public/static/.

  The HTML5 view signs in with the meteor_login_token cookie, as WeKan and
  Weddy do: a WeLite session, or a Meteor login token of a shared store.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, Classes, HTTPDefs, wldb, wlauth;

const
  LOGIN_COOKIE = 'meteor_login_token';

// The signed-in user of an HTML5 request, from the login cookie. S.SessionId
// is set when the cookie is a WeLite session (it may then also do actions).
function Html5User(Db: TWLDb; Request: TRequest; out S: TWLSession): Boolean;

// Serve a GET of the HTML5 view: /, /allboards/:section, /sign-in, a board and
// a card. Returns False when the request is not one of these, so the HTML4
// view serves it instead.
function ServeHtml5(Request: TRequest; Response: TResponse): Boolean;

// A POST of the HTML5 view's forms and of weddy.js's /_methods/ calls, by a
// viewer signed in with the login cookie and carrying no WeLite form session
// (the HTML4 view's forms always do): POST /b/:id/cards adds a card, and the
// board is drawn again for Unpoly to take its .board-wrapper. Returns False
// when the request is not one of these.
function ServeHtml5Action(Request: TRequest; Response: TResponse): Boolean;

// After a successful sign-in in the HTML5 view: the login cookie, and back to
// All Boards.
procedure Html5SignedIn(Response: TResponse; const SessionId: string);

// A sign-in refused in the HTML5 view: the sign-in form again, with WeKan's
// error and the username that was typed.
procedure Html5SignInFailed(Request: TRequest; Response: TResponse; const Username: string);

// The HTML4 view's toggle is a POST of ?ui=html5 with the page's session: put
// that session into the login cookie and send the viewer to the same page by
// GET, now in the HTML5 view. Returns True when it answered.
function SwitchToHtml5(Request: TRequest; Response: TResponse): Boolean;

// The HTML4 view after the toggle from the HTML5 view: the login cookie's
// WeLite session, when the request carries none of its own.
procedure CarryCookieSession(Request: TRequest);

// POST /logout, the HTML5 header's Log Out: the cookie's token is revoked as
// the REST API's logout revokes it, the cookie is cleared, and the viewer is
// sent to the sign-in page.
procedure Html5LogoutEndpoint(Request: TRequest; Response: TResponse);

implementation

uses
  StrUtils, fpjson, wltenant, wlhtml, wli18n, wllocale, wlaccess, wlroutes,
  wlview, wlselscp, wlrevoke, wlapi, wlferr, wlstore, wlmd;

const
  STATIC_HEAD =
    '<link rel="stylesheet" href="/static/unpoly.css">' +
    '<link rel="stylesheet" href="/static/wekan.css">' +
    '<link rel="stylesheet" href="/static/welite.css">' +
    '<script src="/static/unpoly.js"></script>' +
    '<script src="/static/interact.js"></script>' +
    '<script src="/static/weddy.js"></script>' +
    '<script src="/static/welite.js"></script>';

function E(const Value: string): string;
begin
  Result := HtmlEncode(Value);
end;

function UserName(Db: TWLDb; const UserId: string): string;
var R: TWLRows;
begin
  Result := '';
  R := Db.Query('SELECT username FROM users WHERE id=' + QuotedStr(UserId) +
    ' AND COALESCE(loginDisabled,0)=0 LIMIT 1;');
  if (Length(R) = 1) and (Length(R[0]) = 1) then Result := R[0][0];
end;

function Html5User(Db: TWLDb; Request: TRequest; out S: TWLSession): Boolean;
var Token, UserId: string;
begin
  S := Default(TWLSession);
  Token := Trim(Request.CookieFields.Values[LOGIN_COOKIE]);
  Result := False;
  if Token = '' then Exit;
  if ValidateSession(Db, Request, Token, S) then Exit(True);
  S := Default(TWLSession);
  if ValidateLoginToken(Db, Request, Token, UserId) then
  begin
    S.UserId := UserId;
    S.Username := UserName(Db, UserId);
    // The token is this tenant's: its user's profile (their language) is read here.
    S.TenantDb := ExpandFileName(Db.Path);
    Result := S.Username <> '';
  end;
end;

procedure Html5SignedIn(Response: TResponse; const SessionId: string);
var C: TCookie;
begin
  C := Response.Cookies.Add;
  C.Name := LOGIN_COOKIE;
  C.Value := SessionId;
  C.Path := '/';
  C.HttpOnly := True;
  C.SameSite := ssLax;
  Response.Code := 302;
  Response.SetCustomHeader('Location', '/');
  Response.SetCustomHeader('Cache-Control', 'no-store');
  Response.SendContent;
end;

function SwitchToHtml5(Request: TRequest; Response: TResponse): Boolean;
var T: TWLTenant; S: TWLSession; Target, Query, Slug: string; C: TCookie; i: Integer; Open: Boolean;
begin
  Result := False;
  if (Request.Method <> 'POST') or (Request.QueryFields.Values['ui'] <> 'html5') or
    (Request.ContentFields.Values['nav_view'] <> '1') then Exit;
  Result := True;
  Open := ResolveTenant(Request, T) and TenantOpen(T);
  if Open and ValidateSession(T.Db, Request, Trim(Request.ContentFields.Values['sessionId']), S) then
  begin
    C := Response.Cookies.Add;
    C.Name := LOGIN_COOKIE;
    C.Value := S.SessionId;
    C.Path := '/';
    C.HttpOnly := True;
    C.SameSite := ssLax;
  end;
  // The same page: its path and query, without the toggle's ui=.
  Target := Request.PathInfo;
  if Target = '' then Target := '/';
  Query := '';
  for i := 0 to Request.QueryFields.Count - 1 do
    if (Request.QueryFields.Names[i] <> 'ui') and (Request.QueryFields.Names[i] <> 'sessionId') and
      (Request.QueryFields.Names[i] <> '') then
    begin
      if Query <> '' then Query := Query + '&';
      Query := Query + HTTPEncode(Request.QueryFields.Names[i]) + '=' + HTTPEncode(Request.QueryFields.ValueFromIndex[i]);
    end;
  // A board or a card is shown by its WeKan route again.
  if (Target = '/board') or (Target = '/board/card') then
  begin
    if Open then Slug := BoardSlug(T.Db, Request.QueryFields.Values['id']) else Slug := 'board';
    if Target = '/board/card' then
      Target := CardRoute(Request.QueryFields.Values['id'], Slug, Request.QueryFields.Values['card'])
    else
      Target := BoardRoute(Request.QueryFields.Values['id'], Slug);
    Query := '';
  end;
  if Query <> '' then Target := Target + '?' + Query;
  Response.Code := 303;
  Response.SetCustomHeader('Location', Target);
  Response.SetCustomHeader('Cache-Control', 'no-store');
  Response.SendContent;
end;

procedure CarryCookieSession(Request: TRequest);
var Token: string;
begin
  if SessionIdFromRequest(Request) <> '' then Exit;
  Token := Trim(Request.CookieFields.Values[LOGIN_COOKIE]);
  // Only a WeLite session id: 64 hex digits. A Meteor login token is not one,
  // and the HTML4 view never treats it as a session.
  if (Length(Token) <> 64) or (Token <> LowerCase(Token)) then Exit;
  Request.QueryFields.Values['sessionId'] := Token;
end;

procedure Html5LogoutEndpoint(Request: TRequest; Response: TResponse);
var T: TWLTenant; S: TWLSession; Token: string; C: TCookie;
begin
  if (ResolveTenant(Request, T) and TenantOpen(T)) and Html5User(T.Db, Request, S) then
  begin
    Token := Trim(Request.CookieFields.Values[LOGIN_COOKIE]);
    try
      if not T.Db.Exec('BEGIN IMMEDIATE; ' + RevokeTokenSQL(T.Db, S.UserId, Token) + 'COMMIT;') then
        T.Db.Exec('ROLLBACK;');
    except
      T.Db.Exec('ROLLBACK;');
    end;
  end;
  C := Response.Cookies.Add;
  C.Name := LOGIN_COOKIE;
  C.Value := '';
  C.Path := '/';
  C.HttpOnly := True;
  C.SameSite := ssLax;
  C.Expires := EncodeDate(1970, 1, 2);
  Response.Code := 302;
  Response.SetCustomHeader('Location', '/sign-in');
  Response.SetCustomHeader('Cache-Control', 'no-store');
  Response.SendContent;
end;

function PathAndQuery(Request: TRequest): string;
begin
  Result := Request.URI;
  if Result = '' then Result := Request.PathInfo;
end;

// header.jade's quick access: Home, the toggle that collapses the header's
// icons and the page's title, in that order; then the mobile/desktop toggle,
// the first of the icons it collapses. weddy.js keeps both choices: the
// collapse for this session, the mode in localStorage's wekan-mobile-mode and
// in the user's profile.mobileMode (WeKan's setMobileMode), given here as
// data-profile.
function QuickAccessBar(Words: TWLTranslator; const TitleHtml, MobileChoice: string): string;
begin
  Result := '<div id="header-quick-access" class="nodragscroll" role="navigation" aria-label="' +
    HtmlAttr(Words.Text('all-boards', 'All Boards')) + '"><span class="home-icon allBoards">' +
    '<a class="header-home-link" href="/" up-follow title="' + HtmlAttr(Words.Text('all-boards', 'All Boards')) +
    '" aria-label="' + HtmlAttr(Words.Text('all-boards', 'All Boards')) + '"><i class="fa fa-home"></i></a>' +
    '<a class="board-header-btn js-toggle-header-icons-collapsed" href="#" title="' +
    HtmlAttr(Words.Text('toggle-header-icons-collapsed', 'Collapse/expand header icons (mobile/desktop toggle to notifications)')) +
    '" aria-label="' + HtmlAttr(Words.Text('toggle-header-icons-collapsed',
    'Collapse/expand header icons (mobile/desktop toggle to notifications)')) + '"><i class="fa fa-angle-double-left"></i></a>' +
    TitleHtml + '</span><div class="mobile-mode-toggle js-header-collapsible-icon"><a class="board-header-btn js-mobile-mode-toggle desktop-active" ' +
    'href="#" title="' + HtmlAttr(Words.Text('mobile-desktop-toggle', 'Toggle between Mobile and Desktop Mode')) + '" aria-label="' +
    HtmlAttr(Words.Text('mobile-desktop-toggle', 'Toggle between Mobile and Desktop Mode')) + '" data-profile="' + HtmlAttr(MobileChoice) +
    '"><i class="desktop-icon"><i class="fa fa-desktop"></i></i></a></div></div>';
end;

// The user's profile.mobileMode: 'true', 'false', or '' when never chosen.
function MobileModeChoice(Db: TWLDb; const UserId: string): string;
var R: TWLRows;
begin
  Result := '';
  if (Db = nil) or (UserId = '') then Exit;
  R := Db.Query('SELECT CASE json_type(profile_json,''$.mobileMode'') WHEN ''true'' THEN ''true'' WHEN ''false'' THEN ''false'' ' +
    'ELSE '''' END FROM users WHERE id=' + QuotedStr(UserId) + ' AND json_valid(profile_json);');
  if Length(R) = 1 then Result := R[0][0];
end;

// layout.pug: the document, its head, and the header bar.
function Page(Request: TRequest; const Language: TWLLanguage; Words: TWLTranslator;
  const S: TWLSession; const Title, BoardTitle, Content: string; const QuickAccess: string = ''): string;
var Dir, Header: string; SiteAdmin: Boolean; T: TWLTenant;
begin
  SiteAdmin := (S.UserId <> '') and ResolveTenant(Request, T) and TenantOpen(T) and IsSiteAdmin(T.Db, S.UserId);
  if Language.Rtl then Dir := 'rtl' else Dir := 'ltr';
  Header := '';
  if S.UserId <> '' then
  begin
    Header := '<div id="header" class="header-bar">' +
      '<a class="header-all-boards js-all-boards" href="/" up-follow>' + E(Words.Text('all-boards', 'All Boards')) + '</a>';
    // header.jade's quick access: the board's title, renamed by its admin.
    if QuickAccess <> '' then Header := Header + QuickAccess
    else if BoardTitle <> '' then
      Header := Header + QuickAccessBar(Words, '<span class="header-page-title" role="heading" aria-level="1" title="' +
        HtmlAttr(BoardTitle) + '">' + E(BoardTitle) + '</span>', '');
    Header := Header +
      Html5ViewToggle(PathAndQuery(Request), Words.Text('html4-html5-toggle', 'Toggle between HTML4 and HTML5 view')) +
      // layout.pug: the notifications indicator and its drawer. weddy.js keeps
      // the signed-in user fresh from it (refreshUser, GET /api/user).
      '<div id="notifications" class="notifications"><a class="notifications-drawer-toggle js-toggle-notifications-drawer" href="#" title="' +
      HtmlAttr(Words.Text('notifications', 'Notifications')) + '" aria-label="' + HtmlAttr(Words.Text('notifications', 'Notifications')) +
      '" data-unread="0">&#128276;<span class="notifications-count"></span></a></div>' +
      '<section id="notifications-drawer" class="is-hidden"><div class="header"><h5>' + E(Words.Text('notifications', 'Notifications')) +
      '</h5><a class="close" href="#" title="' + HtmlAttr(Words.Text('close', 'Close')) + '">&times;</a></div><ul class="notifications"></ul></section>' +
      '<a class="header-user js-open-header-member-menu" href="/">' + E(S.Username) + '</a>' +
      // The sidebar hamburger, on a board (header.jade).
      IfThen(BoardTitle <> '', '<div class="board-header-btns header-sidebar-toggle"><div class="separator"></div>' +
        '<a class="board-header-btn js-toggle-page-sidebar" href="#" title="' + HtmlAttr(Words.Text('sidebar-open', 'Open Sidebar')) +
        '" aria-label="' + HtmlAttr(Words.Text('sidebar-open', 'Open Sidebar')) + '">&#9776;</a></div>', '') +
      // WeKan's memberMenuPopup: what the HTML5 view has of it.
      '<template class="js-pop-over-template" data-pop="member-menu" data-title="' +
      HtmlAttr(Words.Text('memberMenuPopup-title', 'Member Settings')) + '"><div class="content"><ul class="pop-over-list">' +
      '<li><a href="/" up-follow><i class="fa fa-home"></i> ' + E(Words.Text('all-boards', 'All Boards')) + '</a></li><hr>' +
      '<li><a class="board-header-btn js-open-archived-board" href="/allboards/archive"><i class="fa fa-archive"></i> ' +
      E(Words.Text('archives', 'Archives')) + '</a></li>' +
      // The Admin Panel, for a site admin (memberMenuPopup's js-go-setting).
      IfThen(SiteAdmin, '<li><a class="js-go-setting" href="/admin/people"><i class="fa fa-lock"></i> ' +
        E(Words.Text('admin-panel', 'Admin Panel')) + '</a></li>', '') + '</ul></div></template>' +
      '<form class="js-logout" method="post" action="/logout"><button class="js-logout-button" type="submit">' +
      E(Words.Text('log-out', 'Log Out')) + '</button></form></div>';
  end
  else
    Header := '<div id="header" class="header-bar">' +
      Html5ViewToggle(PathAndQuery(Request), Words.Text('html4-html5-toggle', 'Toggle between HTML4 and HTML5 view')) + '</div>';
  Result := '<!DOCTYPE html>' + LineEnding +
    '<html lang="' + HtmlAttr(StringReplace(Language.Tag, '_', '-', [rfReplaceAll])) + '" dir="' + Dir + '">' +
    '<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<title>' + E(Title) + ' - WeKan</title>' + STATIC_HEAD + '</head>' +
    '<body>' + Header + '<main id="content">' + Content + '</main></body></html>' + LineEnding;
end;

// signin.pug
function SignInContent(Words: TWLTranslator; const Error, Username: string): string;
begin
  Result := '<div class="auth-layout"><div class="auth-dialog at-form">' +
    '<h1 class="at-title">' + E(Words.Text('log-in', 'Log In')) + '</h1>';
  if Error <> '' then
    Result := Result + '<div class="at-error js-login-error">' + E(Error) + '</div>';
  Result := Result +
    '<form id="at-pwd-form" method="post" action="/sign-in">' +
    '<label for="at-field-username_and_email">' + E(Words.Text('username', 'Username')) + '</label>' +
    '<input id="at-field-username_and_email" type="text" name="username" value="' + HtmlAttr(Username) +
    '" autocomplete="username" required>' +
    '<label for="at-field-password">' + E(Words.Text('password', 'Password')) + '</label>' +
    '<div class="password-input-container"><input id="at-field-password" class="password-field" type="password" name="password" autocomplete="current-password" required>' +
    '<button class="password-toggle-btn primary" type="button" aria-label="' + HtmlAttr(Words.Text('password', 'Password') + ': ' +
    Words.Text('visibility', 'Visibility')) + '" title="' + HtmlAttr(Words.Text('password', 'Password') + ': ' + Words.Text('visibility', 'Visibility')) +
    '">&#128065;</button></div>' +
    '<button id="at-btn" class="at-btn submit primary" type="submit">' + E(Words.Text('log-in', 'Log In')) + '</button>' +
    '</form>' +
    '<p class="at-signup-link"><a class="js-sign-up" href="/sign-up">' + E(Words.Text('register', 'Register')) + '</a></p>' +
    '</div></div>';
end;

// notfound.pug
function NotFoundContent(Words: TWLTranslator): string;
begin
  Result := '<div class="big-message quiet board-not-found js-board-not-found"><h1>' +
    E(Words.Text('board-not-found', 'Board not found')) + '</h1><a href="/" up-follow>' +
    E(Words.Text('all-boards', 'All Boards')) + '</a></div>';
end;

// boards.pug: All Boards, by section. Starred are the user's favorites
// (users.profile.starredBoards), Remaining the readable boards that are not.
function BoardsContent(Db: TWLDb; const S: TWLSession; Words: TWLTranslator; const Section: string): string;
var R: TWLRows; i, Starred, Remaining: Integer; Sec, Items: string; IsStarred: Boolean;
  StarredIds: TStringList;
  function StarredSet: TStringList;
  var P: TWLRows; Data: TJSONData; Arr: TJSONArray; k: Integer;
  begin
    Result := TStringList.Create;
    Result.Sorted := True;
    try
      P := Db.Query('SELECT COALESCE(json_extract(profile_json,''$.starredBoards''),''[]'') FROM users WHERE id=' +
        QuotedStr(S.UserId) + ' LIMIT 1;');
    except
      P := nil;
    end;
    if (Length(P) <> 1) or (Length(P[0]) <> 1) then Exit;
    try
      Data := GetJSON(P[0][0]);
    except
      Exit;
    end;
    try
      if Data is TJSONArray then
      begin
        Arr := TJSONArray(Data);
        for k := 0 to Arr.Count - 1 do
          if Arr.Items[k].JSONType = jtString then Result.Add(Arr.Items[k].AsString);
      end;
    finally
      Data.Free;
    end;
  end;
  function MenuItem(const Kind, Icon, Key, Caption: string; Count: Integer): string;
  begin
    Result := '<li class="menu-item' + IfThen(Sec = Kind, ' active', '') + '">' +
      '<a class="js-select-menu" href="/allboards/' + Kind + '" data-type="' + Kind + '">' +
      '<span class="menu-label"><i class="fa ' + Icon + '"></i> ' + E(Words.Text(Key, Caption)) + '</span>' +
      '<span class="menu-count">' + IntToStr(Count) + '</span></a></li>';
  end;
begin
  Sec := Section;
  if (Sec <> 'starred') and (Sec <> 'remaining') and (Sec <> 'archive') then Sec := 'starred';
  StarredIds := StarredSet;
  try
    // WeKan's Archive (#allboards/archive): the archived boards the user is an
    // active member of - every one for a site admin. (BoardCanRead answers for
    // a board that is not archived.)
    if Sec = 'archive' then
      R := Db.Query('SELECT b.id,b.title,b.color,b.slug FROM boards b WHERE b.archived=1 AND (EXISTS(SELECT 1 FROM board_members m ' +
        'WHERE m.boardId=b.id AND m.userId=' + QuotedStr(S.UserId) + ' AND m.isActive=1) OR EXISTS(SELECT 1 FROM users u WHERE u.id=' +
        QuotedStr(S.UserId) + ' AND u.isAdmin=1 AND COALESCE(u.loginDisabled,0)=0)) ORDER BY b.sort,b.id;')
    else
      R := Db.Query('SELECT id,title,color,slug FROM boards WHERE archived=0 ORDER BY sort,id;');
    Starred := 0; Remaining := 0; Items := '';
    for i := 0 to High(R) do
      if Sec = 'archive' then
        Items := Items + '<li class="js-board ' + HtmlAttr(R[i][0]) + ' archived" data-id="' + HtmlAttr(R[i][0]) +
          '"><span class="board-list-item board-color-' + HtmlAttr(R[i][2]) + '"><span class="board-list-item-name">' + E(R[i][1]) +
          '</span></span></li>'
      else if (Sec <> 'archive') and BoardCanRead(Db, S.UserId, R[i][0]) then
      begin
        IsStarred := StarredIds.IndexOf(R[i][0]) >= 0;
        if IsStarred then Inc(Starred) else Inc(Remaining);
        if IsStarred = (Sec = 'starred') then
          Items := Items + '<li class="js-board ' + HtmlAttr(R[i][0]) + IfThen(IsStarred, ' starred', '') +
            '" data-id="' + HtmlAttr(R[i][0]) + '"><a class="board-list-item board-color-' + HtmlAttr(R[i][2]) +
            '" href="' + HtmlAttr(BoardRoute(R[i][0], R[i][3])) + '" up-follow><span class="board-list-item-name">' +
            E(R[i][1]) + '</span></a></li>';
      end;
  finally
    StarredIds.Free;
  end;
  Result := '<div class="board-list-wrapper"><h1 class="board-list-title">' + E(Words.Text('all-boards', 'All Boards')) + '</h1>' +
    '<ul class="board-list-menu js-board-sections">' +
    MenuItem('starred', 'fa-star', 'starred-boards', 'Starred Boards', Starred) +
    MenuItem('remaining', 'fa-th-large', 'remaining', 'Remaining', Remaining) +
    '</ul><ul class="board-list js-boards">' + Items + '</ul></div>';
end;

// The user's own profile flag (users.profile.<Name>), as WeKan's profile keeps it.
function ProfileFlag(Db: TWLDb; const UserId, Name: string): Boolean;
var R: TWLRows;
begin
  Result := False;
  if UserId = '' then Exit;
  R := Db.Query('SELECT CASE WHEN json_valid(profile_json) AND json_extract(profile_json,''$.' + Name +
    ''')=1 THEN 1 ELSE 0 END FROM users WHERE id=' + QuotedStr(UserId) + ' LIMIT 1;');
  Result := (Length(R) = 1) and (Length(R[0]) = 1) and (R[0][0] = '1');
end;

// _cardsec_checklists.pug: the opened card's checklists, each with its
// progress and items; for whoever may change the card, a checklist added (the
// title line's "+" before there is one, the bottom one after), an item added
// under its checklist, an item checked, and the checklist's menu.
function ChecklistsSection(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId: string; Writable: Boolean): string;
var Lists, Items: TWLRows; i, k, Done, Percent: Integer; Base, Checklist, ItemsHtml, Finished: string;
  function InlinedForm(const Cls, Action, Label_: string): string;
  begin
    // Its fields are on the page only while it is open (WeKan's inlinedForm).
    Result := '<form class="' + Cls + ' js-inlined-form is-hidden" method="post" action="' + HtmlAttr(Action) +
      '" up-submit up-target=".board-wrapper"><template class="js-inlined-form-body">' +
      '<textarea class="js-add-checklist-item" name="title" rows="1" aria-label="' + HtmlAttr(Label_) + '" required></textarea>' +
      '<div class="edit-controls clearfix"><button class="primary confirm js-submit-add-checklist-item-form" type="submit">' +
      E(Words.Text('save', 'Save')) + '</button><a class="js-close-inlined-form" href="#" aria-label="' +
      HtmlAttr(Words.Text('close', 'Close')) + '">&times;</a></div></template></form>';
  end;
begin
  Result := '';
  Base := '/b/' + HTTPEncode(BoardId) + '/cards/' + HTTPEncode(CardId) + '/checklists';
  Lists := Db.Query('SELECT id,title FROM checklists WHERE cardId=' + QuotedStr(CardId) +
    ' AND (boardId IS NULL OR boardId=' + QuotedStr(BoardId) + ') ORDER BY sort,id;');
  if (Length(Lists) = 0) and not Writable then Exit;
  Result := '<div class="card-checklist-attachmentGallery card-checklists js-checklists-section"><div class="checklists-title">' +
    '<h3 class="card-details-item-title"><i class="fa fa-check"></i> ' + E(Words.Text('checklists', 'Checklists'));
  if Writable and (Length(Lists) = 0) then
    Result := Result + '<a class="add-checklist-top js-open-inlined-form" href="#" data-opens="add-checklist" title="' +
      HtmlAttr(Words.Text('add-checklist', 'Add Checklist')) + '" aria-label="' + HtmlAttr(Words.Text('add-checklist', 'Add Checklist')) +
      '"><i class="fa fa-plus"></i></a>';
  Result := Result + '</h3></div><div class="card-checklist-items">';
  for i := 0 to High(Lists) do
  begin
    Items := Db.Query('SELECT id,title,COALESCE(isFinished,0) FROM checklist_items WHERE checklistId=' + QuotedStr(Lists[i][0]) +
      ' AND cardId=' + QuotedStr(CardId) + ' ORDER BY sort,id;');
    Done := 0;
    ItemsHtml := '';
    for k := 0 to High(Items) do
    begin
      if Items[k][2] = '1' then begin Inc(Done); Finished := ' is-checked'; end else Finished := '';
      ItemsHtml := ItemsHtml + '<div class="js-checklist-item checklist-item' + Finished + '" data-item="' + HtmlAttr(Items[k][0]) +
        '" role="checkbox" aria-checked="' + IfThen(Finished <> '', 'true', 'false') + '" aria-readonly="' +
        IfThen(Writable, 'false', 'true') + '" tabindex="' + IfThen(Writable, '0', '-1') + '">';
      if Writable then
        ItemsHtml := ItemsHtml + '<form class="check-box-container js-toggle-checklist-item" method="post" action="' +
          HtmlAttr(Base + '/' + HTTPEncode(Lists[i][0]) + '/items/' + HTTPEncode(Items[k][0]) + '/toggle') +
          '" up-submit up-target=".board-wrapper"><button class="check-box materialCheckBox' + Finished +
          '" type="submit" aria-label="' + HtmlAttr(Items[k][1]) + '"></button></form>'
      else
        ItemsHtml := ItemsHtml + '<div class="check-box-container"><div class="check-box materialCheckBox' + Finished + '"></div></div>';
      ItemsHtml := ItemsHtml + '<div class="item-title' + Finished + '">' + E(Items[k][1]) + '</div></div>';
    end;
    Checklist := '<div class="js-checklist checklist" data-checklist="' + HtmlAttr(Lists[i][0]) + '"><div class="checklist-title">';
    if Writable then
      Checklist := Checklist + '<a class="fa fa-navicon checklist-details-menu js-open-checklist-details-menu" href="#" data-checklist="' +
        HtmlAttr(Lists[i][0]) + '" title="' + HtmlAttr(Words.Text('checklistActionsPopup-title', 'Checklist Actions')) +
        '" aria-label="' + HtmlAttr(Words.Text('checklistActionsPopup-title', 'Checklist Actions')) + '"></a>';
    Checklist := Checklist + '<h4 class="title">' + E(Lists[i][1]) + '</h4></div>';
    // WeKan's progress: the share of its items checked, shown once one is.
    if (Length(Items) > 0) and (Done > 0) then
    begin
      Percent := (Done * 100) div Length(Items);
      Checklist := Checklist + '<div class="checklist-progress-bar-container"><div class="checklist-progress-text">' +
        IntToStr(Percent) + '%</div><div class="checklist-progress-bar" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="' +
        IntToStr(Percent) + '" aria-label="' + HtmlAttr(Lists[i][1]) + '"><div class="checklist-progress" style="width:' +
        IntToStr(Percent) + '%"></div></div></div>';
    end;
    Checklist := Checklist + '<div class="checklist-items js-checklist-items">' + ItemsHtml + '</div>';
    if Writable then
      Checklist := Checklist + '<a class="add-checklist-item js-open-inlined-form" href="#" data-opens="add-checklist-item" title="' +
        HtmlAttr(Words.Text('add-checklist-item', 'Add an item to checklist')) + '" aria-label="' +
        HtmlAttr(Words.Text('add-checklist-item', 'Add an item to checklist')) + '"><i class="fa fa-plus"></i></a>' +
        InlinedForm('js-add-checklist-item', Base + '/' + HTTPEncode(Lists[i][0]) + '/items',
          Words.Text('add-checklist-item', 'Add an item to checklist'));
    Result := Result + Checklist + '</div>';
  end;
  Result := Result + '</div>';
  if Writable then
  begin
    Result := Result + '<div class="checklists-bottom-actions">';
    if Length(Lists) > 0 then
      Result := Result + '<a class="add-checklist js-open-inlined-form" href="#" data-opens="add-checklist" title="' +
        HtmlAttr(Words.Text('add-checklist', 'Add Checklist')) + '" aria-label="' + HtmlAttr(Words.Text('add-checklist', 'Add Checklist')) +
        '"><i class="fa fa-plus"></i></a>';
    Result := Result + InlinedForm('js-add-checklist', Base, Words.Text('add-checklist', 'Add Checklist')) + '</div>';
  end;
  Result := Result + '</div>';
end;

// _cardsec_comments.pug: the card's comments, newest last, and the form for
// whoever may comment on the board.
function CommentsSection(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId: string; CanComment: Boolean): string;
var R: TWLRows; i: Integer; Shown: string;
begin
  Result := '<h3 class="card-details-item-title js-toggle-card-section" data-section="comments" role="button" tabindex="0">' +
    '<i class="fa fa-comment-o" aria-hidden="true"></i> ' + E(Words.Text('comments', 'Comments')) + '</h3><div class="comments">';
  if CanComment then
    Result := Result + '<div class="new-comment js-new-comment"><form class="js-new-comment-form" method="post" action="/b/' +
      HtmlAttr(HTTPEncode(BoardId)) + '/cards/' + HtmlAttr(HTTPEncode(CardId)) + '/comments" up-submit up-target=".board-wrapper">' +
      '<textarea class="editor js-new-comment-input" name="comment" aria-label="' + HtmlAttr(Words.Text('comment', 'Comment')) +
      '" required></textarea><button class="primary confirm js-add-comment" type="submit">' + E(Words.Text('comment', 'Comment')) +
      '</button></form></div>';
  R := Db.Query('SELECT c.id,c.text,COALESCE(c.createdAt,''''),COALESCE(u.username,'''') FROM card_comments c LEFT JOIN users u ON u.id=c.userId ' +
    'WHERE c.cardId=' + QuotedStr(CardId) + ' AND (c.boardId IS NULL OR c.boardId=' + QuotedStr(BoardId) + ') ORDER BY c.createdAt,c.id;');
  for i := 0 to High(R) do
  begin
    // The stored time, as minutes: 2026-11-26T01:02:03.456Z -> 2026-11-26 01:02.
    Shown := StringReplace(Copy(R[i][2], 1, 16), 'T', ' ', []);
    Result := Result + '<div class="comment" data-id="' + HtmlAttr(R[i][0]) + '"><span class="comment-member">' + E(R[i][3]) +
      '</span><div class="comment-text"><div class="viewer">' + E(R[i][1]) + '</div></div><time class="activity-time" datetime="' +
      HtmlAttr(R[i][2]) + '">' + E(Shown) + '</time></div>';
  end;
  Result := Result + '</div>';
end;

// board.pug's checklistActionsPopup and checklistDeletePopup, for the opened card.
function ChecklistPopups(Words: TWLTranslator; const BoardId, CardId: string): string;
begin
  Result := '<template class="js-pop-over-template" data-pop="checklist-actions" data-title="' +
    HtmlAttr(Words.Text('checklistActionsPopup-title', 'Checklist Actions')) + '"><div class="content"><ul class="pop-over-list"><li>' +
    '<a class="js-delete-checklist delete-checklist" href="#"><i class="fa fa-trash"></i> ' + E(Words.Text('delete', 'Delete')) +
    ' ...</a></li></ul></div></template>' +
    '<template class="js-pop-over-template" data-pop="checklist-delete" data-title="' +
    HtmlAttr(Words.Text('checklistActionsPopup-title', 'Checklist Actions')) + '" data-board="' + HtmlAttr(BoardId) +
    '" data-card="' + HtmlAttr(CardId) + '"><div class="content"><p>' +
    E(Words.Text('confirm-checklist-delete-popup', 'Are you sure you want to delete the checklist?')) +
    '</p><form class="js-checklist-delete-form" method="post" action="#" up-submit up-target=".board-wrapper">' +
    '<button class="js-confirm negate full" type="submit">' + E(Words.Text('delete', 'Delete')) + '</button></form></div></template>';
end;

// board.pug: the board, and when CardId is given, its opened card.
// _cardsec_date.pug: Received, Start, Due and End, as the board allows them -
// a badge, or a "+" for whoever may set them, opening the date picker.
function DatesSection(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId: string; const Values: array of string;
  CanSet: Boolean): string;
const
  Kinds: array[0..3] of string = ('received', 'start', 'due', 'end');
  Icons: array[0..3] of string = ('fa-sign-out', 'fa-hourglass-start', 'fa-clock-o', 'fa-hourglass-end');
  Captions: array[0..3] of string = ('Received', 'Start', 'Due', 'End');
  Titles: array[0..3] of string = ('editCardReceivedDatePopup-title', 'editCardStartDatePopup-title',
    'editCardDueDatePopup-title', 'editCardEndDatePopup-title');
  TitleCaptions: array[0..3] of string = ('Change received date', 'Change start date', 'Change due date', 'Change end date');
  Defaults: array[0..3] of string = ('now', 'now', '17:00', 'now');
var i: Integer; Field, Setting, Label_, Url, Common, Shown: string;
begin
  Result := '';
  for i := 0 to 3 do
  begin
    ViewDateKindField(Kinds[i], Field, Setting);
    if not BoardAllows(Db, BoardId, Setting) then Continue;
    Label_ := Words.Text('card-' + Kinds[i], Captions[i]);
    Url := '/b/' + HTTPEncode(BoardId) + '/cards/' + HTTPEncode(CardId) + '/dates/' + Kinds[i];
    Common := ' title="' + HtmlAttr(Label_) + '" data-url="' + HtmlAttr(Url) + '" data-default-time="' + Defaults[i] +
      '" data-title="' + HtmlAttr(Words.Text(Titles[i], TitleCaptions[i])) + '"';
    Result := Result + '<div class="card-details-item card-details-item-' + Kinds[i] + '"><h3 class="card-details-item-title">' +
      '<i class="fa ' + Icons[i] + '"></i> ' + E(Label_) + '</h3>';
    if Values[i] <> '' then
    begin
      // The stored time, to the minute: 2026-08-20T17:00:00.000Z -> 2026-08-20 17:00.
      Shown := StringReplace(Copy(Values[i], 1, 16), 'T', ' ', []);
      if CanSet then
        Result := Result + '<a class="js-edit-date card-date ' + Kinds[i] + '-date" href="#"' + Common + ' data-date="' +
          HtmlAttr(Values[i]) + '"><time datetime="' + HtmlAttr(Values[i]) + '">' + E(Shown) + '</time></a>'
      else
        Result := Result + '<a class="card-date ' + Kinds[i] + '-date" title="' + HtmlAttr(Label_) + '"><time datetime="' +
          HtmlAttr(Values[i]) + '">' + E(Shown) + '</time></a>';
    end
    else if CanSet then
      Result := Result + '<a class="card-label add-label js-' + Kinds[i] + '-date" href="#"' + Common +
        '><i class="fa fa-plus"></i></a>';
    Result := Result + '</div>';
  end;
end;

// board.pug's date picker (WeKan's editCard*DatePopup and calendarDateInput):
// weddy.js draws the month and sends the time made of the day and time picked.
function DatePopup(Words: TWLTranslator): string;
  function T(const Key, Caption: string): string;
  begin
    Result := HtmlAttr(Words.Text(Key, Caption));
  end;
begin
  Result := '<template class="js-pop-over-template" data-pop="edit-date" data-title="' +
    T('editCardDueDatePopup-title', 'Change due date') + '"><div class="header"><span class="header-title">' +
    T('editCardDueDatePopup-title', 'Change due date') + '</span><a class="close-btn js-close-pop-over" href="#" aria-label="' +
    T('close', 'Close') + '">&times;</a></div>' +
    '<button class="js-date-popup-resize" type="button" aria-label="' + T('size', 'Size') + '" title="' + T('size', 'Size') +
    '"><span aria-hidden="true">&#9698;</span></button>' +
    '<div class="datepicker-container"><form class="edit-date" method="post" action="#" up-submit up-target=".board-wrapper">' +
    '<input type="hidden" name="at"><input type="hidden" name="delete" value="">' +
    '<div class="fields"><div class="left"><div class="calendar-date-input">' +
    '<input class="js-calendar-native-value js-date-field" id="date" type="hidden" name="date">' +
    '<div class="selected-calendar-picker"><div class="selected-calendar-heading">' +
    '<button class="primary js-calendar-year-previous" type="button" aria-label="' + T('previous', 'Previous') + ' ' +
    T('predicate-year', 'year') + '">&laquo;</button>' +
    '<button class="primary js-calendar-previous" type="button" aria-label="' + T('previous', 'Previous') + ' ' +
    T('month', 'Month') + '">&lsaquo;</button>' +
    '<span class="js-calendar-month-label" aria-live="polite"></span>' +
    '<button class="primary js-calendar-today" type="button" aria-label="' + T('today', 'Today') + '">' + T('today', 'Today') +
    '</button><button class="primary js-calendar-next" type="button" aria-label="' + T('next', 'Next') + ' ' +
    T('month', 'Month') + '">&rsaquo;</button>' +
    '<button class="primary js-calendar-year-next" type="button" aria-label="' + T('next', 'Next') + ' ' +
    T('predicate-year', 'year') + '">&raquo;</button></div>' +
    '<table><thead><tr class="js-calendar-weekdays"></tr></thead><tbody class="js-calendar-weeks"></tbody></table>' +
    '<div class="selected-calendar-selects"><input class="js-calendar-year" type="number" step="1" inputmode="numeric" aria-label="' +
    T('predicate-year', 'year') + '"><select class="js-calendar-month" aria-label="' + T('month', 'Month') +
    '"></select><select class="js-calendar-day-select" aria-label="' + T('day', 'Day') + '"></select></div></div></div></div>' +
    '<div class="right"><label>' + T('time', 'Time') + '</label><div class="calendar-time-input">' +
    '<input class="js-calendar-native-time js-time-field" id="time" type="hidden" name="time">' +
    '<select class="js-calendar-hour" aria-label="' + T('hours', 'hours') + '"></select><span aria-hidden="true">:</span>' +
    '<select class="js-calendar-minute" aria-label="' + T('minutes', 'minutes') + '"></select></div></div></div>' +
    '<div class="warning js-date-error" hidden data-invalid-date="' + T('invalid-date', 'Invalid date') +
    '" data-invalid-time="' + T('invalid-time', 'Invalid time') + '" data-invalid-year="' + T('invalid-year', 'Invalid year') +
    '"></div><button class="primary wide left js-submit-date" type="submit">' + T('save', 'Save') +
    '</button><button class="js-delete-date negate wide right" type="button">' + T('delete', 'Delete') +
    '</button></form></div></template>';
end;

// _cardsec_customFields.pug: for whoever may change the card, on a board that
// uses custom fields, one section - its hamburger the picker of the board's
// fields (cardCustomFieldsPopup), its layout toggle (toggleCustomFieldsGrid)
// - and each field of the card the user may see, with its cardCustomField-*
// editor, whose fields are on the page only while it is open.
function CustomFieldsSection(Db: TWLDb; Words: TWLTranslator; const S: TWLSession; const BoardId, CardId: string;
  Writable: Boolean): string;
var R, Items: TWLRows; i, j: Integer; Id, Name, Kind, Value, Shown, Action, Editor, Body, Close, Copy_: string;
  Editable, Checked: Boolean; Parsed: TJSONData; Arr: TJSONArray;
  function ItemName(const ItemId: string): string;
  var k: Integer;
  begin
    Result := '';
    for k := 0 to High(Items) do if Items[k][0] = ItemId then Exit(Items[k][1]);
  end;
begin
  Result := '';
  if not (Writable and BoardAllows(Db, BoardId, 'allowsCustomFields')) then Exit;
  R := Db.Query('SELECT f.id,f.name,f.type,COALESCE(v.value,''''),COALESCE(f.currencyCode,''''),' +
    'COALESCE(f.stringtemplateFormat,''''),COALESCE(f.stringtemplateSeparator,'''') FROM card_custom_field_values v ' +
    'JOIN custom_fields f ON f.id=v.customFieldId JOIN custom_field_boards b ON b.customFieldId=f.id AND b.boardId=' +
    QuotedStr(BoardId) + ' WHERE v.cardId=' + QuotedStr(CardId) + ' ORDER BY f.name,f.id;');
  Result := '<div class="card-details-group card-details-group-custom-fields">' +
    '<h3 class="card-details-item-title js-toggle-card-section" data-section="customFields" role="button" tabindex="0">' +
    '<i class="fa fa-caret-down"></i><i class="fa fa-list-alt"></i> ' + E(Words.Text('custom-fields', 'Custom Fields')) +
    '<a class="card-details-section-menu js-open-custom-fields-settings" href="#" title="' +
    HtmlAttr(Words.Text('custom-fields', 'Custom Fields')) + '" aria-label="' + HtmlAttr(Words.Text('custom-fields', 'Custom Fields')) +
    '"><i class="fa fa-navicon"></i></a><button class="custom-fields-layout-toggle js-section-open-only" id="toggleCustomFieldsGridButton" ' +
    'type="button" title="' + HtmlAttr(Words.Text('change', 'Change') + ' ' + Words.Text('custom-fields', 'Custom Fields') + ' ' +
    Words.Text('layout', 'Layout')) + '" aria-label="' + HtmlAttr(Words.Text('change', 'Change') + ' ' +
    Words.Text('custom-fields', 'Custom Fields') + ' ' + Words.Text('layout', 'Layout')) + '"><i class="fa fa-th-large"></i></button></h3>' +
    '<div class="card-details-group-body ' + IfThen(ProfileFlag(Db, S.UserId, 'customFieldsGrid'), 'custom-fields-one-per-row',
    'custom-fields-grid') + '">';
  Close := '<div class="edit-controls clearfix"><button class="primary" type="submit">' + E(Words.Text('save', 'Save')) +
    '</button><a class="fa fa-times-thin js-close-inlined-form" href="#" title="' + HtmlAttr(Words.Text('close', 'Close')) + '"></a></div>';
  for i := 0 to High(R) do
  begin
    Id := R[i][0]; Name := R[i][1]; Kind := R[i][2]; Value := R[i][3];
    if not ViewFieldAllowed(Db, S.UserId, BoardId, CardId, Id, False) then Continue;
    Editable := ViewFieldAllowed(Db, S.UserId, BoardId, CardId, Id, True);
    Items := Db.Query('SELECT id,name FROM custom_field_dropdown_items WHERE customFieldId=' + QuotedStr(Id) + ' ORDER BY sort,id;');
    // The value as it is shown.
    Shown := Value;
    Arr := nil;
    if (Kind = 'dropdownMultiSelect') or (Kind = 'stringtemplate') then
    begin
      Shown := '';
      try
        Parsed := GetJSON(Value);
        if Parsed is TJSONArray then Arr := TJSONArray(Parsed) else Parsed.Free;
      except
        Arr := nil;
      end;
      if Arr <> nil then
        for j := 0 to Arr.Count - 1 do
        begin
          if Kind = 'dropdownMultiSelect' then
            Shown := Shown + IfThen(Shown <> '', ', ', '') + ItemName(Arr.Items[j].AsString)
          else
            Shown := Shown + IfThen(Shown <> '', IfThen(R[i][6] <> '', R[i][6], ' '), '') +
              StringReplace(IfThen(R[i][5] <> '', R[i][5], '%{value}'), '%{value}', Arr.Items[j].AsString, [rfReplaceAll]);
        end;
    end
    else if Kind = 'dropdown' then Shown := ItemName(Value)
    else if Kind = 'currency' then begin if Value <> '' then Shown := Value + IfThen(R[i][4] <> '', ' ' + R[i][4], ''); end
    else if Kind = 'date' then Shown := StringReplace(Copy(Value, 1, 16), 'T', ' ', []);
    Checked := (Value = '1') or (Value = 'true');
    Action := '/b/' + HTTPEncode(BoardId) + '/cards/' + HTTPEncode(CardId) + '/custom-fields/' + HTTPEncode(Id);
    Copy_ := '<span class="custom-field-copy-control"><a class="fa fa-copy js-copy-custom-field" href="#" title="' +
      HtmlAttr(Words.Text('copy-text-to-clipboard', 'Copy text to clipboard')) + '" data-value="' + HtmlAttr(Shown) + '"></a></span>';
    Result := Result + '<div class="card-details-item card-details-item-customfield" data-field="' + HtmlAttr(Id) + '" data-type="' +
      HtmlAttr(Kind) + '"><h3 class="card-details-item-title' + IfThen(Editable, ' js-edit-card-custom-field-value is-editable', '') +
      '"' + IfThen(Editable, ' role="button" tabindex="0" title="' + HtmlAttr(Words.Text('edit', 'Edit')) + '"', ' tabindex="-1"') +
      '><i class="fa fa-list"></i> ' + E(Name) + '</h3>';
    if (Kind = 'date') and Editable then
    begin
      Result := Result + '<a class="js-edit-date js-custom-field-edit-trigger" href="#" title="' + HtmlAttr(Name + ': ' + Shown) +
        '" aria-label="' + HtmlAttr(Words.Text('edit', 'Edit')) + '" data-url="' + HtmlAttr(Action) + '" data-date="' + HtmlAttr(Value) +
        '" data-default-time="now" data-title="' + HtmlAttr(Name) + '">';
      if Value <> '' then
        Result := Result + '<div class="card-date"><time datetime="' + HtmlAttr(Value) + '">' + E(Shown) + '</time></div>'
      else
        Result := Result + '<i class="fa fa-pencil-square-o" aria-hidden="true"></i>';
      Result := Result + '</a>';
    end
    else if (Kind = 'checkbox') and Editable then
      Result := Result + '<form class="js-card-custom-field-checkbox-toggle" method="post" action="' + HtmlAttr(Action) +
        '" up-submit up-target=".board-wrapper"><input type="hidden" name="value" value="' + IfThen(Checked, 'false', 'true') +
        '"></form><div class="js-card-custom-field-checkbox js-edit-card-custom-field-value checklist-item' +
        IfThen(Checked, ' is-checked', '') + '" title="' + HtmlAttr(Words.Text('edit', 'Edit')) + '" aria-label="' +
        HtmlAttr(Words.Text('edit', 'Edit')) + '" role="button" tabindex="0"><div class="check-box-container"><div class="check-box materialCheckBox' +
        IfThen(Checked, ' is-checked', '') + '"></div></div></div>' +
        '<form class="js-inlined-form is-hidden js-card-customfield-checkbox-editor" method="post" action="' + HtmlAttr(Action) +
        '" up-submit up-target=".board-wrapper"><template class="js-inlined-form-body">' + Copy_ +
        '<label class="check-box-container"><input class="js-card-customfield-checkbox-input" type="checkbox" name="value" value="true"' +
        IfThen(Checked, ' checked', '') + '><div class="check-box materialCheckBox' + IfThen(Checked, ' is-checked', '') +
        '"></div></label><input type="hidden" name="value" value="false">' + Close + '</template></form>'
    else if Editable then
    begin
      Result := Result + '<a class="js-edit-card-custom-field-value" href="#" title="' + HtmlAttr(Words.Text('edit', 'Edit')) +
        '" aria-label="' + HtmlAttr(Words.Text('edit', 'Edit')) + '">' +
        IfThen(Shown <> '', E(Shown), '<i class="fa fa-pencil-square-o" aria-hidden="true"></i>') + '</a>';
      if Kind = 'text' then
        Editor := '<textarea class="editor" name="value" dir="auto" aria-label="' + HtmlAttr(Name) + '">' + E(Value) + '</textarea>'
      else if Kind = 'number' then
        Editor := '<input type="number" step="any" name="value" value="' + HtmlAttr(Value) + '" aria-label="' + HtmlAttr(Name) + '">'
      else if Kind = 'dropdown' then
      begin
        Editor := '<select class="inline" name="value" aria-label="' + HtmlAttr(Name) + '"><option value="">&ndash;</option>';
        for j := 0 to High(Items) do
          Editor := Editor + '<option value="' + HtmlAttr(Items[j][0]) + '"' + IfThen(Items[j][0] = Value, ' selected', '') + '>' +
            E(Items[j][1]) + '</option>';
        Editor := Editor + '</select>';
      end
      else if Kind = 'dropdownMultiSelect' then
      begin
        Editor := '<div class="js-card-customfield-dropdown-multi-select-items"><input type="hidden" name="value" value="">';
        for j := 0 to High(Items) do
          Editor := Editor + '<label class="custom-field-multi-select-item"><input type="checkbox" name="value" value="' +
            HtmlAttr(Items[j][0]) + '"' + IfThen((Arr <> nil) and (Pos('"' + Items[j][0] + '"', Value) > 0), ' checked', '') + '> ' +
            E(Items[j][1]) + '</label>';
        Editor := Editor + '</div>';
      end
      else if Kind = 'stringtemplate' then
      begin
        Editor := '';
        if Arr <> nil then
          for j := 0 to Arr.Count - 1 do
            Editor := Editor + '<input class="js-card-customfield-stringtemplate-item" type="text" name="value" value="' +
              HtmlAttr(Arr.Items[j].AsString) + '" autocomplete="off">';
        Editor := Editor + '<input class="js-card-customfield-stringtemplate-item last" type="text" name="value" value="" placeholder="' +
          HtmlAttr(Words.Text('custom-field-stringtemplate-item-placeholder', 'Press enter to add more items')) + '" autocomplete="off">';
      end
      else
        Editor := '<input type="text" name="value" value="' + HtmlAttr(Value) + '" aria-label="' + HtmlAttr(Name) + '" autocomplete="off">';
      Body := Copy_ + Editor + Close;
      Result := Result + '<form class="js-inlined-form is-hidden js-card-customfield-' + HtmlAttr(Kind) + '" method="post" action="' +
        HtmlAttr(Action) + '" up-submit up-target=".board-wrapper"><template class="js-inlined-form-body">' + Body + '</template></form>';
    end
    else if Shown <> '' then
      Result := Result + '<div class="viewer">' + E(Shown) + '</div>';
    Arr.Free;
    Result := Result + '</div>';
  end;
  Result := Result + '</div></div>';
end;

// cardCustomFieldsPopup: every field of the board the user may see, ticked
// when it is on this card; a click puts it on or takes it off.
function CustomFieldsPopup(Db: TWLDb; Words: TWLTranslator; const S: TWLSession; const BoardId, CardId: string): string;
var R: TWLRows; i: Integer;
begin
  R := Db.Query('SELECT f.id,f.name,EXISTS(SELECT 1 FROM card_custom_field_values v WHERE v.cardId=' + QuotedStr(CardId) +
    ' AND v.customFieldId=f.id) FROM custom_fields f JOIN custom_field_boards b ON b.customFieldId=f.id AND b.boardId=' +
    QuotedStr(BoardId) + ' ORDER BY f.name,f.id;');
  Result := '<template class="js-pop-over-template" data-pop="card-custom-fields" data-title="' +
    HtmlAttr(Words.Text('custom-fields', 'Custom Fields')) + '"><ul class="pop-over-list">';
  for i := 0 to High(R) do
    if ViewFieldAllowed(Db, S.UserId, BoardId, CardId, R[i][0], False) then
      Result := Result + '<li class="item"><form method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) + '/cards/' +
        HtmlAttr(HTTPEncode(CardId)) + '/custom-fields/' + HtmlAttr(HTTPEncode(R[i][0])) + '/toggle" up-submit up-target=".board-wrapper">' +
        '<button class="name js-select-field" type="submit" title="' + HtmlAttr(Words.Text('show-field-on-card', 'Show this field on card')) +
        '"><div class="materialCheckBox' + IfThen(R[i][2] = '1', ' is-checked', '') + '"></div><span class="full-name">' +
        E(R[i][1]) + '</span></button></form></li>';
  Result := Result + '</ul><div class="card-custom-fields-more">' + IfThen(Length(R) > 0, '<hr>', '') +
    '<a class="quiet-button full js-open-create-custom-field" href="#"><i class="fa fa-plus"></i><span> ' +
    E(Words.Text('createCustomField', 'Create Field')) + '</span></a></div></template>' +
    // createCustomFieldPopup: a field's name and type, shown on cards.
    '<template class="js-pop-over-template" data-pop="create-custom-field" data-title="' +
    HtmlAttr(Words.Text('createCustomFieldPopup-title', 'Create Field')) + '"><form class="create-custom-field" method="post" action="/b/' +
    HtmlAttr(HTTPEncode(BoardId)) + '/custom-fields" up-submit up-target=".board-wrapper"><input type="hidden" name="card" value="' +
    HtmlAttr(CardId) + '"><label>' + E(Words.Text('name', 'Name')) +
    '<input class="js-field-name" type="text" name="name" required maxlength="200" autocomplete="off"></label><label>' +
    E(Words.Text('type', 'Type')) + '<select class="js-field-type" name="type">' +
    '<option value="text">' + E(Words.Text('custom-field-text', 'Text')) + '</option>' +
    '<option value="number">' + E(Words.Text('custom-field-number', 'Number')) + '</option>' +
    '<option value="date">' + E(Words.Text('custom-field-date', 'Date')) + '</option>' +
    '<option value="checkbox">' + E(Words.Text('custom-field-checkbox', 'Checkbox')) + '</option>' +
    '<option value="currency">' + E(Words.Text('custom-field-currency', 'Currency')) + '</option>' +
    '<option value="dropdown">' + E(Words.Text('custom-field-dropdown', 'Dropdown List')) + '</option>' +
    '</select></label><button class="primary wide" type="submit">' + E(Words.Text('create', 'Create')) + '</button></form></template>';
end;

// The kind of preview WeKan's attachmentViewer gives a file: a raster image
// in the overlay, as the file route serves only those inline
// (SendStoredDownload); anything else is opened, and so downloaded, in its own tab.
function AttachmentPreviewKind(const MimeType: string): string;
begin
  if (MimeType = 'image/png') or (MimeType = 'image/jpeg') or (MimeType = 'image/gif') or (MimeType = 'image/webp') then
    Result := 'image'
  else Result := 'none';
end;

function SizeText(const Bytes: string): string;
var N: Int64;
begin
  N := StrToInt64Def(Bytes, 0);
  if N >= 1048576 then Result := FormatFloat('0.0', N / 1048576) + ' MB'
  else if N >= 1024 then Result := FormatFloat('0.0', N / 1024) + ' kB'
  else Result := IntToStr(N) + ' B';
end;

// _cardsec_attachments.pug: WeKan's attachmentGallery - a "+" opening
// cardAttachmentsPopup for whoever may change the card, and each attachment
// as a tile, its thumbnail or its extension opening attachmentViewer, with
// its name, size, download and delete.
function AttachmentsSection(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId: string; Writable, Admin: Boolean): string;
var R, C: TWLRows; i: Integer; Id, Name, Kind, Src, Ext, Act, Cover, Background: string;
begin
  C := Db.Query('SELECT COALESCE((SELECT coverId FROM cards WHERE id=' + QuotedStr(CardId) + '),''''),' +
    'COALESCE((SELECT backgroundImageURL FROM boards WHERE id=' + QuotedStr(BoardId) + '),'''');');
  Cover := ''; Background := '';
  if Length(C) = 1 then begin Cover := C[0][0]; Background := C[0][1]; end;
  R := Db.Query('SELECT id,COALESCE(name,''''),COALESCE(type,''''),COALESCE(size,0) FROM attachments WHERE boardId=' +
    QuotedStr(BoardId) + ' AND cardId=' + QuotedStr(CardId) + ' AND ' + LiveAttachmentSQL(Db) + ' ORDER BY createdAt,id;');
  Result := '<div class="card-checklist-attachmentGallery card-attachmentGallery">' +
    '<h3 class="card-details-item-title js-toggle-card-section" data-section="attachments" role="button" tabindex="0">' +
    '<i class="fa fa-caret-down"></i><i class="fa fa-paperclip"></i> ' + E(Words.Text('attachments', 'Attachments')) + '</h3>' +
    '<div class="attachment-gallery attachments js-attachments">';
  if Writable then
    Result := Result + '<a class="card-label add-label add-attachment js-add-attachment" href="#" title="' +
      HtmlAttr(Words.Text('add-attachment', 'Add Attachment')) + '" aria-label="' +
      HtmlAttr(Words.Text('add-attachment', 'Add Attachment')) + '"><i class="fa fa-plus"></i></a>';
  for i := 0 to High(R) do
  begin
    Id := R[i][0]; Name := R[i][1]; Kind := AttachmentPreviewKind(R[i][2]);
    Src := '/cdn/storage/attachments/' + HTTPEncode(Id) + '/original/' + HTTPEncode(Name);
    Ext := LowerCase(ExtractFileExt(Name));
    if Ext <> '' then Delete(Ext, 1, 1);
    Result := Result + '<div class="attachment-item js-attachment" data-attachment="' + HtmlAttr(Id) + '">' +
      '<button class="attachment-thumbnail-container open-preview" type="button" aria-label="' +
      HtmlAttr(Words.Text('preview', 'Preview') + ': ' + Name) + '" data-attachment-id="' + HtmlAttr(Id) + '" data-kind="' + Kind +
      '" data-name="' + HtmlAttr(Name) + '" data-src="' + HtmlAttr(Src) + '">';
    if Kind = 'image' then
      Result := Result + '<img class="attachment-thumbnail" src="/cdn/storage/attachments/' + HtmlAttr(HTTPEncode(Id)) +
        '/thumbnail" alt="' + HtmlAttr(Name) + '" title="' + HtmlAttr(Name) + '" loading="lazy">'
    else
      Result := Result + '<span class="attachment-thumbnail-text">' + E(Ext) + '</span>';
    Result := Result + '</button><div class="attachment-details-container"><div class="attachment-details"><div>' +
      '<b class="attachment-name">' + E(Name) + '</b> <span class="file-size">(' + E(SizeText(R[i][3])) + ')</span></div>' +
      '<div class="attachment-actions"><a class="js-download" href="' + HtmlAttr(Src) + '?download=true" download="' +
      HtmlAttr(Name) + '" title="' + HtmlAttr(Words.Text('download', 'Download')) + '" aria-label="' +
      HtmlAttr(Words.Text('download', 'Download')) + '"><i class="fa fa-arrow-down"></i></a>';
    if Writable then
      Result := Result + '<form class="js-attachment-delete" method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) + '/cards/' +
        HtmlAttr(HTTPEncode(CardId)) + '/attachments/' + HtmlAttr(HTTPEncode(Id)) + '/delete" up-submit up-target=".board-wrapper">' +
        '<button class="js-confirm-delete" type="submit" title="' + HtmlAttr(Words.Text('delete', 'Delete')) + '" aria-label="' +
        HtmlAttr(Words.Text('delete', 'Delete')) + '"><i class="fa fa-trash"></i></button></form>';
    // attachmentActionsPopup: the card's cover, and the board's background
    // for a board admin.
    if Writable and (Kind = 'image') then
    begin
      Act := '/b/' + HtmlAttr(HTTPEncode(BoardId)) + '/cards/' + HtmlAttr(HTTPEncode(CardId)) + '/attachments/' + HtmlAttr(HTTPEncode(Id));
      Result := Result + '<a class="js-open-attachment-menu" href="#" data-attachment="' + HtmlAttr(Id) + '" title="' +
        HtmlAttr(Words.Text('attachmentActionsPopup-title', 'Attachment Actions')) + '" aria-label="' +
        HtmlAttr(Words.Text('attachmentActionsPopup-title', 'Attachment Actions')) + '"><i class="fa fa-bars"></i></a>' +
        '<template class="js-pop-over-template" data-pop="attachment-actions-' + HtmlAttr(Id) + '" data-title="' +
        HtmlAttr(Words.Text('attachmentActionsPopup-title', 'Attachment Actions')) + '"><ul class="pop-over-list"><li><form method="post" action="' +
        Act + '/cover" up-submit up-target=".board-wrapper">' + IfThen(Id = Cover,
        '<button class="js-remove-cover" type="submit">' + E(Words.Text('remove-cover', 'Remove cover image from minicard')) + '</button>',
        '<button class="js-add-cover" type="submit">' + E(Words.Text('add-cover', 'Add cover image to minicard')) + '</button>') + '</form></li>';
      if Admin then
        Result := Result + '<li><form method="post" action="' + Act + '/background" up-submit up-target=".board-wrapper">' +
          IfThen('/cdn/storage/attachments/' + Id = Background,
          '<button class="js-remove-background-image" type="submit">' + E(Words.Text('remove-background-image', 'Remove background image')) + '</button>',
          '<button class="js-add-background-image" type="submit">' + E(Words.Text('add-background-image', 'Add background image')) + '</button>') +
          '</form></li>';
      Result := Result + '</ul></template>';
    end;
    Result := Result + '</div></div></div></div>';
  end;
  Result := Result + '</div></div>';
end;

// board.pug's cardAttachmentsPopup (a file from the computer) and
// attachmentViewer, hidden until a tile is opened.
function AttachmentsPopups(Words: TWLTranslator; const BoardId, CardId: string; Writable: Boolean): string;
begin
  Result := '';
  if Writable then
    Result := '<template class="js-pop-over-template" data-pop="card-attachments" data-title="' +
      HtmlAttr(Words.Text('cardAttachmentsPopup-title', 'Attach From…')) + '"><form class="js-attachment-upload" method="post" action="/b/' +
      HtmlAttr(HTTPEncode(BoardId)) + '/cards/' + HtmlAttr(HTTPEncode(CardId)) + '/attachments" enctype="multipart/form-data" ' +
      'up-submit up-target=".board-wrapper"><ul class="pop-over-list"><li><input class="js-attach-file hide" type="file" name="file" aria-label="' +
      HtmlAttr(Words.Text('add-attachment', 'Add Attachment')) + '" required><a class="js-computer-upload" href="#">' +
      E(Words.Text('computer', 'Computer')) + '</a></li></ul></form></template>';
  Result := Result + '<div class="hidden" id="viewer-overlay" role="dialog" aria-modal="true" aria-labelledby="attachment-name">' +
    '<div id="viewer-top-bar"><span id="attachment-name"></span><button id="viewer-close" type="button" aria-label="' +
    HtmlAttr(Words.Text('close', 'Close')) + '"><i class="fa fa-times-thin"></i></button></div><div id="viewer-container">' +
    '<div id="viewer-content"><img class="hidden" id="image-viewer" alt="' + HtmlAttr(Words.Text('preview', 'Preview')) + '">' +
    '<video class="hidden" id="video-viewer" controls></video><audio class="hidden" id="audio-viewer" controls></audio>' +
    '<object class="hidden" id="pdf-viewer" type="application/pdf"><span class="pdf-preview-error">' +
    E(Words.Text('preview-pdf-not-supported', 'Your device does not support previewing PDF. Try downloading instead.')) +
    '</span></object><object class="hidden" id="txt-viewer" type="text/plain"></object><div class="hidden" id="office-viewer"></div>' +
    '</div></div></div>';
end;

function BoardTitleOf(Db: TWLDb; const BoardId: string): string;
var R: TWLRows;
begin
  R := Db.Query('SELECT title FROM boards WHERE id=' + QuotedStr(BoardId) + ';');
  if Length(R) = 1 then Result := R[0][0] else Result := '';
end;

// The lists of the card's swimlane on its board (every swimlane's, and that
// one's), for the list picker and the move and copy pop-overs, numbered as
// WeKan's selects number them.
function BoardPlaces(Db: TWLDb; const BoardId, LaneId: string; out Lanes, Lists: TWLRows): Boolean;
begin
  Lanes := Db.Query('SELECT id,title FROM swimlanes WHERE boardId=' + QuotedStr(BoardId) + ' AND archived=0 ORDER BY sort,id;');
  Lists := Db.Query('SELECT id,title FROM lists WHERE boardId=' + QuotedStr(BoardId) + ' AND archived=0 AND deletedAt IS NULL' +
    IfThen(LaneId <> '', ' AND (COALESCE(swimlaneId,'''')='''' OR swimlaneId=' + QuotedStr(LaneId) + ')', '') + ' ORDER BY sort,id;');
  Result := True;
end;

function PlaceOptions(const Rows: TWLRows; const Selected: string): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(Rows) do
    Result := Result + '<option value="' + HtmlAttr(Rows[i][0]) + '"' + IfThen(Rows[i][0] = Selected, ' selected', '') + '>' +
      IntToStr(i + 1) + '. ' + E(Rows[i][1]) + '</option>';
end;

// _cardsec_card.pug: the card's list, and the picker of another of its board.
function ListPickerSection(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId, LaneId, ListId: string; Writable: Boolean): string;
var Lanes, Lists: TWLRows; i: Integer; Current: string;
begin
  BoardPlaces(Db, BoardId, LaneId, Lanes, Lists);
  Current := '';
  for i := 0 to High(Lists) do if Lists[i][0] = ListId then Current := Lists[i][1];
  Result := '<div class="card-details-item card-details-item-list"><h3 class="card-details-item-title">' +
    E(Words.Text('list', 'List')) + '</h3>';
  if not Writable then Exit(Result + '<span>' + E(Current) + '</span></div>');
  Result := Result + '<details class="card-details-list-picker"><summary>' + E(Current) + '</summary>' +
    '<div class="card-details-list-options" role="listbox" aria-label="' + HtmlAttr(Words.Text('list', 'List')) + '">';
  for i := 0 to High(Lists) do
    Result := Result + '<form method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) + '/cards/' + HtmlAttr(HTTPEncode(CardId)) +
      '/move-to" up-submit up-target=".board-wrapper"><input type="hidden" name="boardId" value="' + HtmlAttr(BoardId) +
      '"><input type="hidden" name="swimlaneId" value="' + HtmlAttr(LaneId) + '"><input type="hidden" name="listId" value="' +
      HtmlAttr(Lists[i][0]) + '"><button class="js-select-card-details-list-option" type="submit" role="option" data-list-id="' +
      HtmlAttr(Lists[i][0]) + '" aria-selected="' + IfThen(Lists[i][0] = ListId, 'true', 'false') + '">' + E(Lists[i][1]) +
      '</button></form>';
  Result := Result + '</div></details></div>';
end;

// board.pug's cardDetailsActionsPopup - copy link, move, copy, archive - and
// the moveCardPopup, copyCardPopup and cardArchivePopup it opens.
function CardMenuPopups(Db: TWLDb; Words: TWLTranslator; const S: TWLSession; const BoardId, Slug, CardId, Title,
  LaneId, ListId: string): string;
var Lanes, Lists, Boards: TWLRows; Base, BoardOptions, CopyBoards: string; i: Integer;
  function Target(const Kind, Action, Extra, ButtonText: string; const Choices: string): string;
  begin
    Result := '<template class="js-pop-over-template" data-pop="' + Kind + '" data-title="' + HtmlAttr(ButtonText) + '">' +
      '<form class="js-card-target" method="post" action="' + HtmlAttr(Base + Action) + '" up-submit up-target=".board-wrapper">' + Extra +
      '<label>' + E(Words.Text('boards', 'Boards')) + '</label><select class="js-select-boards" name="boardId">' + Choices + '</select>' +
      '<label>' + E(Words.Text('swimlane', 'Swimlane')) + '</label><select class="js-select-swimlanes" name="swimlaneId">' +
      PlaceOptions(Lanes, LaneId) + '</select><label>' + E(Words.Text('list', 'List')) + '</label><select class="js-select-lists" name="listId">' +
      PlaceOptions(Lists, ListId) + '</select><button class="primary confirm js-done" type="submit">' + E(Words.Text('done', 'Done')) +
      '</button></form></template>';
  end;
begin
  BoardPlaces(Db, BoardId, '', Lanes, Lists);
  Base := '/b/' + HTTPEncode(BoardId) + '/cards/' + HTTPEncode(CardId);
  BoardOptions := '<option value="' + HtmlAttr(BoardId) + '" selected>' + E(BoardTitleOf(Db, BoardId)) + '</option>';
  // A copy may go to any board the user may change, this one first.
  CopyBoards := BoardOptions;
  Boards := Db.Query('SELECT b.id,b.title FROM boards b JOIN board_members m ON m.boardId=b.id AND m.userId=' + QuotedStr(S.UserId) +
    ' AND m.isActive=1 WHERE b.archived=0 AND b.id<>' + QuotedStr(BoardId) + ' AND COALESCE(b.type,''board'')=''board'' ORDER BY b.title,b.id;');
  for i := 0 to High(Boards) do
    if BoardCanWrite(Db, S.UserId, Boards[i][0]) then
      CopyBoards := CopyBoards + '<option value="' + HtmlAttr(Boards[i][0]) + '">' + E(Boards[i][1]) + '</option>';
  Result := '<template class="js-pop-over-template" data-pop="card-actions" data-title="' +
    HtmlAttr(Words.Text('cardDetailsActionsPopup-title', 'Card Actions')) + '"><ul class="pop-over-list">' +
    '<li><a class="js-copy-card-link" href="#" data-path="' + HtmlAttr(CardRoute(BoardId, Slug, CardId)) + '"><i class="fa fa-link"></i> ' +
    E(Words.Text('copy-card-link-to-clipboard', 'Copy card link to clipboard')) + '</a></li>' +
    '<li><a class="js-move-card" href="#"><i class="fa fa-arrow-right"></i> ' + E(Words.Text('moveCardPopup-title', 'Move Card')) + '</a></li>' +
    '<li><a class="js-copy-card" href="#"><i class="fa fa-copy"></i> ' + E(Words.Text('copyCardPopup-title', 'Copy Card')) + '</a></li>' +
    '<li><a class="js-archive" href="#"><i class="fa fa-archive"></i> ' + E(Words.Text('archive', 'Archive')) + '</a></li></ul></template>' +
    Target('move-card', '/move-to', '', Words.Text('moveCardPopup-title', 'Move Card'), BoardOptions) +
    Target('copy-card', '/copy-to', '<label for="copy-card-title">' + E(Words.Text('title', 'Title')) +
      '</label><textarea id="copy-card-title" name="title" rows="2">' + E(Title) + '</textarea>',
      Words.Text('copyCardPopup-title', 'Copy Card'), CopyBoards) +
    '<template class="js-pop-over-template" data-pop="card-archive" data-title="' + HtmlAttr(Words.Text('archive', 'Archive')) + '">' +
    '<form method="post" action="' + HtmlAttr(Base + '/archive') + '" up-submit up-target=".board-wrapper" up-history="true"><p>' +
    E(Words.Text('card-archive-pop', 'The card will not be visible in this list after archiving it.')) + '</p><p>' +
    E(Words.Text('card-archive-suggest-cancel', 'You can later restore card from Archive.')) +
    '</p><button class="js-confirm negate full" type="submit">' + E(Words.Text('archive', 'Archive')) + '</button></form></template>';
end;

// GET /b/:id/places (weddy.js, another board chosen in the move or copy
// pop-over): that board's swimlanes and lists, for a user who may change it.
function PlacesJson(Db: TWLDb; const UserId, BoardId: string; out Json: string): Boolean;
var Lanes, Lists: TWLRows; i: Integer; Part: string;
begin
  Result := (UserId <> '') and (BoardId <> '') and (Pos(#0, BoardId) = 0) and BoardCanWrite(Db, UserId, BoardId);
  if not Result then Exit;
  BoardPlaces(Db, BoardId, '', Lanes, Lists);
  Json := '{"swimlanes":[';
  for i := 0 to High(Lanes) do
    Json := Json + IfThen(i > 0, ',', '') + '{"_id":"' + StringToJSONString(Lanes[i][0]) + '","n":' + IntToStr(i + 1) +
      ',"title":"' + StringToJSONString(Lanes[i][1]) + '"}';
  Part := '';
  for i := 0 to High(Lists) do
    Part := Part + IfThen(i > 0, ',', '') + '{"_id":"' + StringToJSONString(Lists[i][0]) + '","n":' + IntToStr(i + 1) +
      ',"title":"' + StringToJSONString(Lists[i][1]) + '"}';
  Json := Json + '],"lists":[' + Part + ']}';
end;

// header.jade's quick access on a board: its title, which opens the rename
// pop-over (boardChangeTitlePopup) for a board admin.
function BoardQuickAccess(Db: TWLDb; Words: TWLTranslator; const S: TWLSession; const BoardId, Title: string): string;
begin
  if not BoardCanAdmin(Db, S.UserId, BoardId) then
    Exit(QuickAccessBar(Words, '<span class="header-page-title" role="heading" aria-level="1" title="' +
      HtmlAttr(Title) + '">' + E(Title) + '</span>', MobileModeChoice(Db, S.UserId)));
  Result := QuickAccessBar(Words, '<span class="header-page-title js-edit-board-title is-editable" ' +
    'role="heading" aria-level="1" title="' + HtmlAttr(Title) + '">' + E(Title) + '</span>' +
    '<template class="js-pop-over-template" data-pop="board-title" data-title="' + HtmlAttr(Words.Text('rename', 'Rename')) + '">' +
    '<form method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) + '/title"><label>' + E(Words.Text('title', 'Title')) +
    '<textarea class="js-board-name" name="title" rows="2" dir="auto" required>' + E(Title) + '</textarea></label>' +
    '<input class="primary wide" type="submit" value="' + HtmlAttr(Words.Text('rename', 'Rename')) + '"></form></template>',
    MobileModeChoice(Db, S.UserId));
end;

// The board's star (boardStarButton), the user's own (profile.starredBoards).
function BoardStarButton(Db: TWLDb; Words: TWLTranslator; const S: TWLSession; const BoardId: string): string;
var R: TWLRows; Starred: Boolean;
begin
  Result := '';
  if S.UserId = '' then Exit;
  R := Db.Query('SELECT EXISTS(SELECT 1 FROM json_each(COALESCE(json_extract(CASE WHEN json_valid(profile_json) THEN profile_json ' +
    'ELSE ''{}'' END,''$.starredBoards''),''[]'')) WHERE value=' + QuotedStr(BoardId) + ') FROM users WHERE id=' + QuotedStr(S.UserId) + ';');
  Starred := (Length(R) = 1) and (R[0][0] = '1');
  Result := '<a class="board-header-btn js-star-board' + IfThen(Starred, ' is-active', '') + '" href="#" title="' +
    HtmlAttr(IfThen(Starred, Words.Text('click-to-unstar', 'Click to unstar this board.'), Words.Text('click-to-star', 'Click to star this board.'))) +
    '" data-star="' + HtmlAttr(Words.Text('click-to-star', 'Click to star this board.')) + '" data-unstar="' +
    HtmlAttr(Words.Text('click-to-unstar', 'Click to unstar this board.')) + '"><i class="fa ' + IfThen(Starred, 'fa-star', 'fa-star-o') + '"></i></a>';
end;

// The board's watch level (boardHeader.jade's js-watch-board) and
// boardChangeWatchPopup's three levels, the user's own.
function BoardWatchButton(Db: TWLDb; Words: TWLTranslator; const S: TWLSession; const BoardId: string): string;
const Levels: array[0..2] of string = ('watching', 'tracking', 'muted');
var Level: string; i: Integer;
begin
  Result := '';
  if S.UserId = '' then Exit;
  Level := BoardWatchLevel(Db, S.UserId, BoardId);
  Result := '<a class="board-header-btn js-watch-board" href="#" title="' + HtmlAttr(Words.Text(Level, Level)) +
    '"><span class="board-header-btn-label">' + E(Words.Text(Level, Level)) + '</span></a>' +
    '<template class="js-pop-over-template" data-pop="watch" data-title="' +
    HtmlAttr(Words.Text('boardChangeWatchPopup-title', 'Change Watch')) + '"><div class="header"><span class="header-title">' +
    E(Words.Text('boardChangeWatchPopup-title', 'Change Watch')) + '</span><a class="close-btn js-close-pop-over" href="#" aria-label="' +
    HtmlAttr(Words.Text('close', 'Close')) + '">&times;</a></div><div class="content"><ul class="pop-over-list described-list">';
  for i := 0 to High(Levels) do
    Result := Result + '<li><a class="js-select-watch" href="/b/' + HtmlAttr(HTTPEncode(BoardId)) + '/watch?level=' + Levels[i] +
      '" up-method="post" up-target=".board-wrapper" data-level="' + Levels[i] + '">' + E(Words.Text(Levels[i], Levels[i])) +
      IfThen(Level = Levels[i], ' &#10003;', '') + '</a><span class="sub-name">' +
      E(Words.Text(Levels[i] + '-info', '')) + '</span></li>';
  Result := Result + '</ul></div></template>';
end;

// The card's watch (cardDetails.jade's js-toggle-watch-card), as Weddy
// places it: under the card's header.
function CardWatchLink(Db: TWLDb; Words: TWLTranslator; const S: TWLSession; const BoardId, CardId: string): string;
var Watching: Boolean;
begin
  Result := '';
  if S.UserId = '' then Exit;
  Watching := CardWatching(Db, S.UserId, CardId);
  Result := '<a class="js-toggle-watch-card' + IfThen(Watching, ' is-checked', '') + '" href="/b/' + HtmlAttr(HTTPEncode(BoardId)) +
    '/cards/' + HtmlAttr(HTTPEncode(CardId)) + '/watch" up-method="post" up-target=".board-wrapper">' +
    IfThen(Watching, E(Words.Text('watching', 'Watching')) + ' &#10003;', E(Words.Text('watch', 'Watch'))) + '</a>';
end;

// The Filter sidebar's card text and label filters (WeKan's
// client/lib/filter.js; board_filter.go in Weddy), kept in the board's URL
// by weddy.js and applied here, by the board drawn with only the cards they
// match. A display filter of a board the viewer already reads, never an
// access check:
//   ?text=      the card text (#3361): title, description, comments,
//               checklist and item titles, case-insensitive
//   ?labels=    labels a card must carry, comma separated; __none__ is no label
//   ?xlabels=   labels a card must not carry (#2886: exclusion wins)
//   ?labelMode=and   every chosen label instead of any (#2044)
const
  MAX_FILTER_TEXT = 512; // sidebarFilters.jade's maxlength
  NO_LABEL = '__none__';
type
  TBoardFilter = record
    Text: string;
    Labels, Excluded: TStringArray;
    NoLabel, AndMode: Boolean;
  end;

function HasString(const Items: TStringArray; const Value: string): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to High(Items) do if Items[i] = Value then Exit(True);
end;

// The board's own label ids named in Raw, each once; NoLabel says whether
// __none__ was among them.
function FilterLabelIds(const Known: TWLRows; const Raw: string; out NoLabel: Boolean): TStringArray;
var Parts: TStringArray; i, j: Integer;
begin
  Result := nil; NoLabel := False;
  if Raw = '' then Exit;
  Parts := Raw.Split([',']);
  for i := 0 to High(Parts) do
  begin
    if Parts[i] = NO_LABEL then begin NoLabel := True; Continue; end;
    for j := 0 to High(Known) do
      if (Known[j][0] = Parts[i]) and not HasString(Result, Known[j][0]) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Known[j][0];
      end;
  end;
end;

function ParseBoardFilter(Db: TWLDb; const BoardId: string; Query: TStrings): TBoardFilter;
var Known: TWLRows; Unused: Boolean; Wide: UnicodeString;
begin
  Result := Default(TBoardFilter);
  if Query = nil then Exit;
  Result.Text := Trim(Query.Values['text']);
  Wide := UTF8Decode(Result.Text);
  if Length(Wide) > MAX_FILTER_TEXT then Result.Text := UTF8Encode(Copy(Wide, 1, MAX_FILTER_TEXT));
  if Pos(#0, Result.Text) > 0 then Result.Text := '';
  Result.AndMode := Query.Values['labelMode'] = 'and';
  Known := Db.Query('SELECT id FROM board_labels WHERE boardId=' + QuotedStr(BoardId) + ';');
  Result.Labels := FilterLabelIds(Known, Query.Values['labels'], Result.NoLabel);
  Result.Excluded := FilterLabelIds(Known, Query.Values['xlabels'], Unused);
end;

function FilterActive(const F: TBoardFilter): Boolean;
begin
  Result := (F.Text <> '') or (Length(F.Labels) > 0) or F.NoLabel or (Length(F.Excluded) > 0);
end;

function SqlList(const Items: TStringArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(Items) do
  begin
    if Result <> '' then Result := Result + ',';
    Result := Result + QuotedStr(Items[i]);
  end;
end;

// ' AND ...' on cards c: the cards the filter matches; '' for no filter.
function BoardFilterSql(const F: TBoardFilter): string;
var Alts, Q, Has: string;
  function Contains(const Column: string): string;
  begin
    Result := 'instr(lower(COALESCE(' + Column + ','''')),lower(' + Q + '))>0';
  end;
begin
  Result := '';
  Alts := '';
  if Length(F.Labels) > 0 then
  begin
    Has := 'SELECT count(DISTINCT labelId) FROM card_labels WHERE cardId=c.id AND labelId IN (' + SqlList(F.Labels) + ')';
    if F.AndMode then Alts := '(' + Has + ')=' + IntToStr(Length(F.Labels))
    else Alts := '(' + Has + ')>0';
  end;
  if F.NoLabel then
  begin
    if Alts <> '' then Alts := Alts + ' OR ';
    Alts := Alts + 'NOT EXISTS(SELECT 1 FROM card_labels WHERE cardId=c.id)';
  end;
  if Alts <> '' then Result := Result + ' AND (' + Alts + ')';
  if Length(F.Excluded) > 0 then
    Result := Result + ' AND NOT EXISTS(SELECT 1 FROM card_labels WHERE cardId=c.id AND labelId IN (' + SqlList(F.Excluded) + '))';
  if F.Text <> '' then
  begin
    Q := QuotedStr(F.Text);
    Result := Result + ' AND (' + Contains('c.title') + ' OR ' + Contains('c.description') +
      ' OR EXISTS(SELECT 1 FROM card_comments m WHERE m.cardId=c.id AND ' + Contains('m.text') + ')' +
      ' OR EXISTS(SELECT 1 FROM checklists l WHERE l.cardId=c.id AND ' + Contains('l.title') + ')' +
      ' OR EXISTS(SELECT 1 FROM checklist_items i WHERE i.cardId=c.id AND ' + Contains('i.title') + '))';
  end;
end;

// boardHeader.jade's Filter button - on, with its reset, while a filter is -
// and filterSidebar's card text and label filters.
function FilterButton(Words: TWLTranslator; const F: TBoardFilter): string;
begin
  if FilterActive(F) then
    Result := '<a class="board-header-btn js-open-filter-view js-filter-active" href="#" title="' +
      HtmlAttr(Words.Text('filter-on-desc', 'You are filtering cards on this board. Click here to edit filter.')) +
      '"><i class="fa fa-filter"></i><span class="board-header-btn-label">' +
      E(Words.Text('filter-on-desc', 'You are filtering cards on this board. Click here to edit filter.')) + '</span></a>' +
      '<a class="board-header-btn-close js-filter-reset" href="#" title="' + HtmlAttr(Words.Text('filter-clear', 'Clear filter')) +
      '">&#10005;</a>'
  else
    Result := '<a class="board-header-btn js-open-filter-view" href="#" title="' + HtmlAttr(Words.Text('filter', 'Filter')) +
      '"><i class="fa fa-filter"></i><span class="board-header-btn-label">' + E(Words.Text('filter', 'Filter')) + '</span></a>';
end;

function FilterSidebar(Db: TWLDb; Words: TWLTranslator; const BoardId: string; const F: TBoardFilter): string;
var R: TWLRows; i: Integer; Chosen, Excluded: Boolean;
begin
  Result := '<div class="filter-sidebar js-filter-view is-hidden"><h3><i class="fa fa-list"></i> ' +
    E(Words.Text('filter-card-text-label', 'Filter by card text')) + '</h3>' +
    '<input class="js-field-card-filter" type="text" maxlength="' + IntToStr(MAX_FILTER_TEXT) + '" value="' + HtmlAttr(F.Text) +
    '" aria-label="' + HtmlAttr(Words.Text('filter-card-text-label', 'Filter by card text')) + '"><hr>' +
    '<h3><i class="fa fa-tag"></i> ' + E(Words.Text('filter-labels-label', 'Filter by labels')) + '</h3>' +
    '<select class="js-label-filter-mode" aria-label="' + HtmlAttr(Words.Text('filter-labels-label', 'Filter by labels')) + '">' +
    IfThen(F.AndMode, '<option value="or">OR</option><option value="and" selected>AND</option>',
      '<option value="or" selected>OR</option><option value="and">AND</option>') + '</select>' +
    '<ul class="sidebar-list js-label-filters"><li' + IfThen(F.NoLabel, ' class="active"', '') + '>' +
    '<label class="name filter-native-choice js-toggle-label-filter" data-filter-id="' + NO_LABEL + '" data-state="' +
    IfThen(F.NoLabel, 'in', '') + '"><input type="checkbox"' + IfThen(F.NoLabel, ' checked', '') +
    '><span class="sidebar-list-item-description">' + E(Words.Text('filter-no-label', 'No label')) + '</span></label></li>';
  R := Db.Query('SELECT id,COALESCE(name,''''),color FROM board_labels WHERE boardId=' + QuotedStr(BoardId) + ';');
  for i := 0 to High(R) do
  begin
    Chosen := HasString(F.Labels, R[i][0]);
    Excluded := HasString(F.Excluded, R[i][0]);
    Result := Result + '<li class="' + IfThen(Chosen, 'active', '') + IfThen(Excluded, ' excluded', '') + '">' +
      '<label class="name filter-native-choice js-toggle-label-filter" data-filter-id="' + HtmlAttr(R[i][0]) + '" data-state="' +
      IfThen(Chosen, 'in', IfThen(Excluded, 'out', '')) + '"><input type="checkbox"' +
      IfThen(Chosen, ' checked', IfThen(Excluded, ' data-indeterminate="true"', '')) +
      '><span class="card-label square card-label-' + HtmlAttr(R[i][2]) + '"></span><span class="sidebar-list-item-description">' +
      E(R[i][1]) + '</span></label></li>';
  end;
  Result := Result + '</ul></div>';
end;

// WeKan's Sort Cards (cardsSortPopup; board_sort.go in Weddy): a display
// order of each list's cards, kept in the board's URL (?sort=) by weddy.js.
// No card's sort changes, and ties keep the manual order.
const
  CARD_SORTS: array[0..5] of string = ('due', 'title', 'created-desc', 'created-asc', 'votes', 'label-order');
  CARD_SORT_ICONS: array[0..5] of string = ('fa-calendar', 'fa-sort-alpha-asc', 'fa-arrow-down', 'fa-arrow-up',
    'fa-thumbs-o-up', 'fa-tags');
  CARD_SORT_LABELS: array[0..5] of string = ('due-date', 'title-alphabetically', 'created-at-newest-first',
    'created-at-oldest-first', 'sort-by-votes', 'sort-by-label-order');
  CARD_SORT_FALLBACKS: array[0..5] of string = ('Due Date', 'Title (Alphabetically)', 'Created At (Newest First)',
    'Created At (Oldest First)', 'Sort by votes', 'Label order');

// The ?sort= of the URL when it is one of WeKan's, else ''.
function ParseCardSort(Query: TStrings): string;
var i: Integer;
begin
  Result := '';
  if Query = nil then Exit;
  for i := 0 to High(CARD_SORTS) do
    if Query.Values['sort'] = CARD_SORTS[i] then Exit(CARD_SORTS[i]);
end;

// The ORDER BY of the board's cards c for the order: WeKan's {dueAt: 1} puts
// cards without a due date first; votes are positive minus negative (#3050);
// the label order is where a card's first label comes in the board's labels,
// cards without one last (#2040).
function CardSortSql(Db: TWLDb; const BoardId, Key: string): string;
var R: TWLRows; i: Integer; Rank: string;
begin
  if Key = 'due' then Result := 'CASE WHEN COALESCE(c.dueAt,'''')='''' THEN 0 ELSE 1 END,c.dueAt,'
  else if Key = 'title' then Result := 'c.title,'
  else if Key = 'created-desc' then Result := 'c.createdAt DESC,'
  else if Key = 'created-asc' then Result := 'c.createdAt,'
  else if Key = 'votes' then
    Result := '(SELECT count(*) FROM json_each(CASE WHEN json_valid(c.extra_json) THEN c.extra_json ELSE ''{}'' END,''$.vote.positive''))-' +
      '(SELECT count(*) FROM json_each(CASE WHEN json_valid(c.extra_json) THEN c.extra_json ELSE ''{}'' END,''$.vote.negative'')) DESC,'
  else if Key = 'label-order' then
  begin
    R := Db.Query('SELECT id FROM board_labels WHERE boardId=' + QuotedStr(BoardId) + ';');
    Rank := '';
    for i := 0 to High(R) do Rank := Rank + ' WHEN ' + QuotedStr(R[i][0]) + ' THEN ' + IntToStr(i);
    if Rank = '' then Result := ''
    else Result := 'COALESCE((SELECT min(CASE l.labelId' + Rank + ' END) FROM card_labels l WHERE l.cardId=c.id),' +
      IntToStr(Length(R) + 1) + '),';
  end
  else Result := '';
end;

// boardHeader.jade's Sort Cards - Sort is on, with its reset, while an order
// is - and cardsSortPopup.
function SortButton(Words: TWLTranslator; const Key: string): string;
var i: Integer;
begin
  if Key <> '' then
    Result := '<a class="board-header-btn js-sort-cards emphasis" href="#" title="' + HtmlAttr(Words.Text('sort-is-on', 'Sort is on')) +
      '"><i class="fa fa-sort"></i><span class="board-header-btn-label">' + E(Words.Text('sort-is-on', 'Sort is on')) + '</span></a>' +
      '<a class="board-header-btn-close js-sort-reset" href="#" title="' + HtmlAttr(Words.Text('remove-sort', 'Remove sort')) + '">&#10005;</a>'
  else
    Result := '<a class="board-header-btn js-sort-cards" href="#" title="' + HtmlAttr(Words.Text('sort-cards', 'Sort Cards')) +
      '"><i class="fa fa-sort"></i><span class="board-header-btn-label">' + E(Words.Text('sort-cards', 'Sort Cards')) + '</span></a>';
  Result := Result + '<template class="js-pop-over-template" data-pop="cards-sort" data-title="' +
    HtmlAttr(Words.Text('sort-cards', 'Sort Cards')) + '"><div class="header"><span class="header-title">' +
    E(Words.Text('sort-cards', 'Sort Cards')) + '</span><a class="close-btn js-close-pop-over" href="#" aria-label="' +
    HtmlAttr(Words.Text('close', 'Close')) + '">&times;</a></div><div class="content"><ul class="pop-over-list">';
  for i := 0 to High(CARD_SORTS) do
    Result := Result + '<li><a class="js-sort-card-order js-sort-' + CARD_SORTS[i] + IfThen(Key = CARD_SORTS[i], ' is-active', '') +
      '" href="#" data-sort="' + CARD_SORTS[i] + '"><i class="fa ' + CARD_SORT_ICONS[i] + '"></i> ' +
      E(Words.Text(CARD_SORT_LABELS[i], CARD_SORT_FALLBACKS[i])) + IfThen(Key = CARD_SORTS[i], ' &#10003;', '') + '</a><hr></li>';
  Result := Result + '</ul></div></template>';
end;

// The role flags of a plain member (no role), as ChangeBoardMembership takes them.
procedure PlainMemberFlags(out Columns, Values, Sets: string);
const Flags: array[0..7] of string = ('isAdmin', 'isNoComments', 'isCommentOnly', 'isWorker',
  'isNormalAssignedOnly', 'isCommentAssignedOnly', 'isReadOnly', 'isReadAssignedOnly');
var i: Integer;
begin
  Columns := ''; Values := ''; Sets := '';
  for i := 0 to High(Flags) do
  begin
    Columns := Columns + ',' + Flags[i]; Values := Values + ',0'; Sets := Sets + ',' + Flags[i] + '=0';
  end;
end;

// addMemberPopup's search (members.go's searchMembers in Weddy): for a board
// admin, up to ten enabled users whose username, full name or address starts
// with Q, case-insensitive, who are not active members yet.
function MemberSearchJson(Db: TWLDb; const UserId, BoardId, Q: string; out Json: string): Boolean;
var R: TWLRows; i: Integer; Text, Starts: string;
  function Prefix(const Column: string): string;
  begin
    Result := 'substr(lower(COALESCE(' + Column + ','''')),1,' + IntToStr(Length(Text)) + ')=lower(' + QuotedStr(Text) + ')';
  end;
begin
  Json := '[]';
  Result := (UserId <> '') and (Pos(#0, BoardId + Q) = 0) and BoardCanAdmin(Db, UserId, BoardId);
  if not Result then Exit;
  Text := Trim(Q);
  if (Text = '') or (Length(Text) > 100) then Exit;
  Starts := '(' + Prefix('u.username') + ' OR ' + Prefix('CASE WHEN json_valid(u.profile_json) THEN json_extract(u.profile_json,''$.fullname'') END') +
    ' OR EXISTS(SELECT 1 FROM user_emails e WHERE e.userId=u.id AND ' + Prefix('e.address') + '))';
  R := Db.Query('SELECT u.id,u.username,COALESCE(CASE WHEN json_valid(u.profile_json) THEN json_extract(u.profile_json,''$.fullname'') END,'''') ' +
    'FROM users u WHERE COALESCE(u.loginDisabled,0)=0 AND ' + Starts + ' AND NOT EXISTS(SELECT 1 FROM board_members m WHERE m.boardId=' +
    QuotedStr(BoardId) + ' AND m.userId=u.id AND m.isActive=1) ORDER BY u.username LIMIT 10;');
  Json := '[';
  for i := 0 to High(R) do
  begin
    if i > 0 then Json := Json + ',';
    Json := Json + '{"_id":"' + StringToJSONString(R[i][0]) + '","username":"' + StringToJSONString(R[i][1]) +
      '","fullname":"' + StringToJSONString(R[i][2]) + '"}';
  end;
  Json := Json + ']';
end;

// membersWidget's memberPopup and removeMemberPopup for each active member,
// and addMemberPopup, for a board admin (board.pug in Weddy).
function MemberPopups(Db: TWLDb; Words: TWLTranslator; const S: TWLSession; const BoardId: string): string;
var R: TWLRows; i: Integer; Admin: Boolean;
begin
  Result := '';
  Admin := (S.UserId <> '') and BoardCanAdmin(Db, S.UserId, BoardId);
  R := Db.Query('SELECT u.id,u.username,COALESCE(CASE WHEN json_valid(u.profile_json) THEN json_extract(u.profile_json,''$.fullname'') END,'''') ' +
    'FROM board_members m JOIN users u ON u.id=m.userId WHERE m.boardId=' + QuotedStr(BoardId) +
    ' AND m.isActive=1 AND COALESCE(u.loginDisabled,0)=0 ORDER BY u.username;');
  for i := 0 to High(R) do
  begin
    Result := Result + '<template class="js-pop-over-template" data-pop="member-' + HtmlAttr(R[i][0]) + '" data-title="' +
      HtmlAttr(IfThen(R[i][2] <> '', R[i][2], R[i][1])) + '"><div class="board-member-menu"><div class="miniprofile-header"><div class="info"><h3>' +
      '<div class="js-profile">' + E(R[i][2]) + '</div></h3><p class="quiet">@' + E(R[i][1]) + '</p></div></div><ul class="pop-over-list">';
    if Admin and (R[i][0] <> S.UserId) then
      Result := Result + '<li><a class="js-remove-member" href="#" data-user="' + HtmlAttr(R[i][0]) + '">' +
        E(Words.Text('remove-from-board', 'Remove from Board')) + '</a></li>';
    Result := Result + '</ul></div></template>';
    if Admin then
      Result := Result + '<template class="js-pop-over-template" data-pop="remove-member-' + HtmlAttr(R[i][0]) + '" data-title="' +
        HtmlAttr(Words.Text('remove-member', 'Remove Member')) + '"><form method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) +
        '/members/' + HtmlAttr(HTTPEncode(R[i][0])) + '/remove" up-submit up-target=".board-wrapper"><p>' +
        E(Words.Text('remove-member', 'Remove Member')) + ': ' + E(R[i][2]) + ' (@' + E(R[i][1]) + ')</p>' +
        '<button class="js-confirm negate full" type="submit">' + E(Words.Text('remove-member', 'Remove Member')) + '</button></form></template>';
  end;
  if Admin then
    Result := Result + '<template class="js-pop-over-template" data-pop="add-member" data-title="' +
      HtmlAttr(Words.Text('add-members', 'Add Members')) + '"><div class="js-search-member"><input class="js-search-member-input" type="text" placeholder="' +
      HtmlAttr(Words.Text('email-address', 'Email Address')) + '" aria-label="' + HtmlAttr(Words.Text('add-members', 'Add Members')) +
      '"></div><ul class="pop-over-list js-member-search-results"></ul></template>';
end;

// Admin Panel / People (peopleBody.jade, Weddy's people.pug): its tabs, its
// left menu and the People pane - the users, edited in editUserPopup, with
// Admin and Active switched in the table - for a site admin.
function PeopleContent(Db: TWLDb; const S: TWLSession; Words: TWLTranslator; const ErrorKey: string): string;
var R: TWLRows; i: Integer; Id, YesNo: string;
  function Opt(const Value, Caption: string; Selected: Boolean): string;
  begin
    Result := '<option value="' + Value + '"' + IfThen(Selected, ' selected', '') + '>' + E(Caption) + '</option>';
  end;
begin
  R := Db.Query('SELECT u.id,u.username,COALESCE(CASE WHEN json_valid(u.profile_json) THEN json_extract(u.profile_json,''$.fullname'') END,''''),' +
    'COALESCE(CASE WHEN json_valid(u.profile_json) THEN json_extract(u.profile_json,''$.initials'') END,''''),' +
    'COALESCE((SELECT group_concat(address,'' '') FROM user_emails e WHERE e.userId=u.id),''''),COALESCE(u.isAdmin,0),COALESCE(u.loginDisabled,0) ' +
    'FROM users u ORDER BY u.username LIMIT 1000;');
  Result := '<div class="setting-content people"><div class="admin-panel-tabs"><a class="people is-active" href="/admin/people">' +
    E(Words.Text('people', 'People')) + '</a></div><div class="content-body"><div class="side-menu"><ul>' +
    '<li class="active"><a class="js-left-menu-item" href="/admin/people" data-id="people-setting">' + E(Words.Text('people', 'People')) +
    '</a></li></ul></div><div class="main-body"><h2 class="pane-title">' + E(Words.Text('people', 'People')) + '</h2>';
  if ErrorKey <> '' then Result := Result + '<p class="at-error js-people-error">' + E(Words.Text(ErrorKey, ErrorKey)) + '</p>';
  Result := Result + '<p>' + E(Words.Text('people-number', 'The number of people is:')) + ' ' + IntToStr(Length(R)) + '</p>' +
    '<table class="people-table"><thead><tr><th>' + E(Words.Text('edit', 'Edit')) + '</th><th>' + E(Words.Text('username', 'Username')) +
    '</th><th>' + E(Words.Text('fullname', 'Full Name')) + '</th><th>' + E(Words.Text('email', 'Email')) + '</th><th>' +
    E(Words.Text('admin', 'Admin')) + '</th><th>' + E(Words.Text('active', 'Active')) + '</th></tr></thead><tbody>';
  for i := 0 to High(R) do
  begin
    Id := R[i][0];
    Result := Result + '<tr class="js-person" data-user="' + HtmlAttr(Id) + '"><td><a class="edit-user" href="#" data-user-id="' + HtmlAttr(Id) +
      '"><i class="fa fa-pencil-square-o"></i> ' + E(Words.Text('edit', 'Edit')) + '</a>' +
      '<template class="js-pop-over-template" data-pop="edit-user-' + HtmlAttr(Id) + '" data-title="' + HtmlAttr(Words.Text('edit', 'Edit')) + '">' +
      '<form class="js-edit-user" method="post" action="/admin/people/' + HtmlAttr(HTTPEncode(Id)) + '/edit">' +
      '<label>' + E(Words.Text('username', 'Username')) + '<input class="js-profile-username" type="text" name="username" value="' +
      HtmlAttr(R[i][1]) + '" required></label><label>' + E(Words.Text('fullname', 'Full Name')) +
      '<textarea class="js-profile-fullname" name="fullname" rows="2">' + E(R[i][2]) + '</textarea></label><label>' +
      E(Words.Text('initials', 'Initials')) + '<input class="js-profile-initials" type="text" name="initials" maxlength="8" value="' +
      HtmlAttr(R[i][3]) + '"></label>';
    if Id <> S.UserId then
      Result := Result + '<label>' + E(Words.Text('admin', 'Admin')) + '<select class="select-role js-profile-isadmin" name="isAdmin">' +
        Opt('false', Words.Text('no', 'No'), R[i][5] <> '1') + Opt('true', Words.Text('yes', 'Yes'), R[i][5] = '1') + '</select></label>';
    Result := Result + '<label>' + E(Words.Text('email', 'Email')) + '<input class="js-profile-email" type="email" name="email" value="' +
      HtmlAttr(Trim(Copy(R[i][4], 1, Pos(' ', R[i][4] + ' ') - 1))) + '"></label>';
    if Id <> S.UserId then
      Result := Result + '<label>' + E(Words.Text('active-person', 'Active')) + '<select class="select-active js-profile-isactive" name="loginDisabled">' +
        Opt('false', Words.Text('yes', 'Yes'), R[i][6] <> '1') + Opt('true', Words.Text('no', 'No'), R[i][6] = '1') + '</select></label>';
    Result := Result + '<label>' + E(Words.Text('password', 'Password')) +
      '<input class="js-profile-password" type="password" name="password" autocomplete="new-password"></label>' +
      '<div class="buttonsContainer"><input class="primary wide" type="submit" value="' + HtmlAttr(Words.Text('save', 'Save')) +
      '"></div></form></template></td><td class="username">' + E(R[i][1]) + '</td><td>' + E(R[i][2]) + '</td><td>' + E(R[i][4]) + '</td><td>';
    YesNo := IfThen(R[i][5] = '1', Words.Text('yes', 'Yes'), Words.Text('no', 'No'));
    if Id <> S.UserId then
      Result := Result + '<form method="post" action="/admin/people/' + HtmlAttr(HTTPEncode(Id)) + '"><input type="hidden" name="isAdmin" value="' +
        IfThen(R[i][5] = '1', 'false', 'true') + '"><button class="js-toggle-admin" type="submit">' + E(YesNo) + '</button></form>'
    else Result := Result + E(Words.Text('yes', 'Yes'));
    Result := Result + '</td><td class="account-active-status">';
    if Id = S.UserId then Result := Result + E(Words.Text('yes', 'Yes'))
    else if R[i][6] = '1' then
      Result := Result + '<span class="text-red js-toggle-active-status" data-user-id="' + HtmlAttr(Id) + '" data-is-active="false" title="' +
        HtmlAttr(Words.Text('admin-people-user-inactive', 'User is inactive - click to activate')) + '" role="button" tabindex="0">&#10005;</span>'
    else
      Result := Result + '<span class="text-green js-toggle-active-status" data-user-id="' + HtmlAttr(Id) + '" data-is-active="true" title="' +
        HtmlAttr(Words.Text('admin-people-user-active', 'User is active - click to deactivate')) + '" role="button" tabindex="0">&#10003;</span>';
    Result := Result + '</td></tr>';
  end;
  Result := Result + '</tbody></table></div></div></div>';
end;

// board.pug's sidebar: the board's members, the board menu (boardMenuPopup,
// its Archived Items) and the Archive (archivesSidebar) with its restore.
function BoardSidebar(Db: TWLDb; Words: TWLTranslator; const S: TWLSession; const BoardId: string; Writable: Boolean;
  const FilterView: string): string;
var R: TWLRows; i: Integer; Archived: string;
  function Item(const Kind, Id, Title: string; Card: Boolean): string;
  var Restore: string;
  begin
    Restore := '';
    if Writable then
      Restore := '<form class="js-restore-form" method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) +
        '/archive/restore" up-submit up-target=".board-wrapper"><input type="hidden" name="kind" value="' + Kind +
        '"><input type="hidden" name="id" value="' + HtmlAttr(Id) + '"><a class="' + IfThen(Card, 'js-restore-card', 'js-restore') +
        '" href="#">' + E(Words.Text('restore', 'Restore')) + '</a></form>';
    if Card then
      Result := '<div class="minicard-wrapper archived-item archived-card-item" data-kind="cards" data-id="' + HtmlAttr(Id) +
        '"><div class="minicard"><div class="minicard-title">' + E(Title) + '</div></div>' + Restore + '</div>'
    else
      Result := '<div class="archived-item" data-kind="' + Kind + '" data-id="' + HtmlAttr(Id) + '"><span class="archived-item-title">' +
        E(Title) + '</span>' + Restore + '</div>';
  end;
begin
  Archived := '';
  R := Db.Query('SELECT id,title FROM cards WHERE boardId=' + QuotedStr(BoardId) + ' AND archived=1 AND deletedAt IS NULL ORDER BY archivedAt DESC,id;');
  for i := 0 to High(R) do Archived := Archived + Item('cards', R[i][0], R[i][1], True);
  R := Db.Query('SELECT id,title FROM lists WHERE boardId=' + QuotedStr(BoardId) + ' AND archived=1 AND deletedAt IS NULL ORDER BY sort,id;');
  for i := 0 to High(R) do Archived := Archived + Item('lists', R[i][0], R[i][1], False);
  R := Db.Query('SELECT id,title FROM swimlanes WHERE boardId=' + QuotedStr(BoardId) + ' AND archived=1 ORDER BY sort,id;');
  for i := 0 to High(R) do Archived := Archived + Item('swimlanes', R[i][0], R[i][1], False);
  if Archived = '' then
    Archived := '<p class="no-items-message">' + E(Words.Text('no-archived-cards', 'No archived cards.')) + '</p>';
  Result := '<div class="board-sidebar sidebar"><a class="sidebar-xmark js-close-sidebar" href="#" aria-label="' +
    HtmlAttr(Words.Text('close', 'Close')) + '">&#10005;</a><div class="sidebar-content js-board-sidebar-content">' +
    FilterView +
    '<div class="archives-sidebar js-archives-view is-hidden"><h3>' + E(Words.Text('archives', 'Archives')) + '</h3>' + Archived + '</div>' +
    '<div class="board-widget board-widget-members membersWidget"><h3 class="board-widget-title">' + E(Words.Text('members', 'Members')) +
    '</h3><div class="board-widget-content">';
  R := Db.Query('SELECT u.id,u.username FROM board_members m JOIN users u ON u.id=m.userId WHERE m.boardId=' + QuotedStr(BoardId) +
    ' AND m.isActive=1 AND COALESCE(u.loginDisabled,0)=0 ORDER BY u.username;');
  for i := 0 to High(R) do
    Result := Result + '<a class="member js-member" href="#" data-user="' + HtmlAttr(R[i][0]) + '" title="' + HtmlAttr(R[i][1]) +
      '" aria-label="' + HtmlAttr(R[i][1]) + '"><span class="member-initials">' + E(R[i][1]) + '</span></a>';
  // membersWidget's add, for whoever may invite: a board admin.
  if (S.UserId <> '') and BoardCanAdmin(Db, S.UserId, BoardId) then
    Result := Result + '<a class="member add-member js-manage-board-members" href="#" title="' +
      HtmlAttr(Words.Text('add-members', 'Add Members')) + '" aria-label="' + HtmlAttr(Words.Text('add-members', 'Add Members')) +
      '"><i class="fa fa-plus"></i></a>';
  Result := Result + '</div></div><h3><a class="board-header-btn js-open-board-menu" href="#" title="' +
    HtmlAttr(Words.Text('boardMenuPopup-title', 'Board Settings')) + '">' + E(Words.Text('boardMenuPopup-title', 'Board Settings')) +
    '</a></h3></div></div>' +
    '<template class="js-pop-over-template" data-pop="board-menu" data-title="' + HtmlAttr(Words.Text('boardMenuPopup-title', 'Board Settings')) +
    '"><div class="header"><span class="header-title">' + E(Words.Text('boardMenuPopup-title', 'Board Settings')) +
    '</span><a class="close-btn js-close-pop-over" href="#" aria-label="' + HtmlAttr(Words.Text('close', 'Close')) + '">&times;</a></div>' +
    '<div class="content"><ul class="pop-over-list"><li><a class="js-open-archives" href="#"><i class="fa fa-archive"></i> ' +
    E(Words.Text('archived-items', 'Archived Items')) + '</a></li></ul></div></template>';
end;

// _cardsec_labels.pug: the card's labels, and the "+" that opens
// cardLabelsPopup for whoever may change the card.
function LabelsSection(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId: string; Writable: Boolean): string;
var R: TWLRows; i: Integer;
begin
  R := Db.Query('SELECT l.id,COALESCE(l.name,''''),l.color FROM card_labels c JOIN board_labels l ON l.id=c.labelId AND ' +
    'l.boardId=' + QuotedStr(BoardId) + ' WHERE c.cardId=' + QuotedStr(CardId) + ';');
  Result := '<div class="card-details-item card-details-item-labels"><h3 class="card-details-item-title">' +
    E(Words.Text('labels', 'Labels')) + '</h3>';
  for i := 0 to High(R) do
    Result := Result + '<span class="card-label card-label-' + HtmlAttr(R[i][2]) + '" data-label="' + HtmlAttr(R[i][0]) +
      '">' + E(R[i][1]) + '</span>';
  if Writable then
    Result := Result + '<a class="card-details-item-add-button js-add-labels" href="#" title="' +
      HtmlAttr(Words.Text('cardLabelsPopup-title', 'Labels')) + '" aria-label="' +
      HtmlAttr(Words.Text('cardLabelsPopup-title', 'Labels')) + '">+</a>';
  Result := Result + '</div>';
end;

// board.pug's cardLabelsPopup - every label of the board, each a form that
// puts it on the card or takes it off - and, for a board admin,
// createLabelPopup: a name and a color of WeKan's label palette.
function LabelsPopups(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId: string; CanCreate: Boolean): string;
const Palette: array[0..23] of string = ('green', 'yellow', 'orange', 'red', 'purple', 'blue', 'sky', 'lime', 'pink',
  'black', 'silver', 'peachpuff', 'crimson', 'plum', 'darkgreen', 'slateblue', 'magenta', 'gold', 'navy', 'gray',
  'saddlebrown', 'paleturquoise', 'mistyrose', 'indigo');
var R: TWLRows; i: Integer; Selected: Boolean; Name: string;
begin
  R := Db.Query('SELECT l.id,COALESCE(l.name,''''),l.color,EXISTS(SELECT 1 FROM card_labels c WHERE c.cardId=' +
    QuotedStr(CardId) + ' AND c.labelId=l.id) FROM board_labels l WHERE l.boardId=' + QuotedStr(BoardId) + ';');
  Result := '<template class="js-pop-over-template" data-pop="card-labels" data-title="' +
    HtmlAttr(Words.Text('cardLabelsPopup-title', 'Labels')) + '"><ul class="edit-labels-pop-over">';
  for i := 0 to High(R) do
  begin
    Selected := R[i][3] = '1';
    Name := R[i][1];
    if Selected then Name := Name + ' ' + #$E2#$9C#$93;
    Result := Result + '<li class="js-card-label-item"><form method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) +
      '/cards/' + HtmlAttr(HTTPEncode(CardId)) + '/labels/' + HtmlAttr(HTTPEncode(R[i][0])) +
      '" up-submit up-target=".board-wrapper"><button class="card-label card-label-selectable js-select-label card-label-' +
      HtmlAttr(R[i][2]) + IfThen(Selected, ' active', '') + '" type="submit">' + E(Name) + '</button></form></li>';
  end;
  Result := Result + '</ul>';
  if CanCreate then
    Result := Result + '<a class="quiet-button full js-add-label" href="#">' +
      E(Words.Text('createLabelPopup-title', 'Create Label')) + '</a>';
  Result := Result + '</template>';
  if not CanCreate then Exit;
  Result := Result + '<template class="js-pop-over-template" data-pop="create-label" data-title="' +
    HtmlAttr(Words.Text('createLabelPopup-title', 'Create Label')) + '"><form class="create-label" method="post" action="/b/' +
    HtmlAttr(HTTPEncode(BoardId)) + '/labels" up-submit up-target=".board-wrapper"><input type="hidden" name="card" value="' +
    HtmlAttr(CardId) + '"><label for="labelName">' + E(Words.Text('name', 'Name')) + '</label>' +
    '<textarea class="js-label-name" id="labelName" rows="2" name="name"></textarea><label>' +
    E(Words.Text('select-color', 'Select a color')) + '</label><div class="palette-colors">';
  for i := 0 to High(Palette) do
    Result := Result + '<label class="card-label palette-color js-palette-color card-label-' + Palette[i] + '" title="' +
      Palette[i] + '"><input type="radio" name="color" value="' + Palette[i] + '"></label>';
  Result := Result + '</div><button class="primary wide" type="submit">' + E(Words.Text('create', 'Create')) +
    '</button></form></template>';
end;

// _cardsec_members.pug: the card's members, and the "+" that opens the
// card-members pop-over (cardMembersPopup) for whoever may change the card.
function MembersSection(Db: TWLDb; Words: TWLTranslator; const CardId: string; Writable: Boolean): string;
var R: TWLRows; i: Integer;
begin
  R := Db.Query('SELECT u.id,u.username FROM card_members c JOIN users u ON u.id=c.userId WHERE c.cardId=' +
    QuotedStr(CardId) + ' ORDER BY u.username;');
  Result := '<div class="card-details-item card-details-item-members"><h3 class="card-details-item-title">' +
    E(Words.Text('members', 'Members')) + '</h3>';
  for i := 0 to High(R) do
    Result := Result + '<span class="card-member js-member member" data-user="' + HtmlAttr(R[i][0]) + '">' +
      E(R[i][1]) + '</span>';
  if Writable then
    Result := Result + '<a class="card-details-item-add-button js-add-members" href="#" title="' +
      HtmlAttr(Words.Text('add-members', 'Add Members')) + '" aria-label="' +
      HtmlAttr(Words.Text('add-members', 'Add Members')) + '">+</a>';
  Result := Result + '</div>';
end;

function MembersPopup(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId: string): string;
var R: TWLRows; i: Integer; Selected: Boolean; Name: string;
begin
  R := Db.Query('SELECT u.id,u.username,COALESCE(json_extract(u.profile_json,''$.fullname''),''''),' +
    'EXISTS(SELECT 1 FROM card_members c WHERE c.cardId=' + QuotedStr(CardId) + ' AND c.userId=u.id) ' +
    'FROM board_members m JOIN users u ON u.id=m.userId WHERE m.boardId=' + QuotedStr(BoardId) +
    ' AND m.isActive=1 AND COALESCE(u.loginDisabled,0)=0 ORDER BY u.username;');
  Result := '<template class="js-pop-over-template" data-pop="card-members" data-title="' +
    HtmlAttr(Words.Text('cardMembersPopup-title', 'Members')) + '"><div class="header"><span class="header-title">' +
    E(Words.Text('cardMembersPopup-title', 'Members')) + '</span><a class="close-btn js-close-pop-over" href="#" aria-label="' +
    HtmlAttr(Words.Text('close', 'Close')) + '">&times;</a></div><div class="content"><ul class="pop-over-list js-card-member-list">';
  for i := 0 to High(R) do
  begin
    Selected := R[i][3] = '1';
    Name := R[i][1];
    if R[i][2] <> '' then Name := Name + ' (' + R[i][2] + ')';
    if Selected then Name := Name + ' ' + #$E2#$9C#$93;
    Result := Result + '<li><form method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) + '/cards/' +
      HtmlAttr(HTTPEncode(CardId)) + '/members/' + HtmlAttr(HTTPEncode(R[i][0])) + '" up-submit up-target=".board-wrapper">' +
      '<button class="js-select-member' + IfThen(Selected, ' is-active', '') + '" type="submit" data-user="' +
      HtmlAttr(R[i][0]) + '">' + E(Name) + '</button></form></li>';
  end;
  Result := Result + '</ul></div></template>';
end;

// _cardsec_members.pug's people: WeKan's Requested By and Assigned By, free
// text, each on a board that shows it; Edit when set, Add when empty.
function PeopleSection(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId, RequestedBy, AssignedBy: string;
  Editable: Boolean): string;
  function Person(const Field, Setting, Key, Caption, Icon, Value: string): string;
  var Label_: string;
  begin
    Result := '';
    if not BoardAllows(Db, BoardId, Setting) then Exit;
    Label_ := Words.Text(Key, Caption);
    Result := '<div class="card-details-item card-details-item-name card-details-item-' + Key +
      '"><h3 class="card-details-item-title"><i class="fa ' + Icon + '"></i> ' + E(Label_) + '</h3>';
    if Value <> '' then Result := Result + '<div class="viewer">' + E(Value) + '</div>';
    if Editable then
    begin
      Result := Result + '<div class="card-details-person-controls">';
      if Value <> '' then
        Result := Result + '<a class="js-open-inlined-form" href="#" title="' + HtmlAttr(Words.Text('edit', 'Edit')) +
          '" aria-label="' + HtmlAttr(Words.Text('edit', 'Edit')) + '"><i class="fa fa-pencil-square-o" aria-hidden="true"></i></a>'
      else
        Result := Result + '<a class="js-open-inlined-form" href="#" title="' + HtmlAttr(Words.Text('add', 'Add')) +
          '" aria-label="' + HtmlAttr(Words.Text('add', 'Add')) + '"><i class="fa fa-plus" aria-hidden="true"></i></a>';
      Result := Result + '</div><form class="js-inlined-form is-hidden" method="post" action="/b/' +
        HtmlAttr(HTTPEncode(BoardId)) + '/cards/' + HtmlAttr(HTTPEncode(CardId)) + '/people" up-submit up-target=".board-wrapper">' +
        '<input type="hidden" name="field" value="' + Field + '"><input type="text" name="value" value="' + HtmlAttr(Value) +
        '" aria-label="' + HtmlAttr(Label_) + '"><button class="primary" type="submit">' + E(Words.Text('save', 'Save')) +
        '</button><a class="js-close-inlined-form" href="#" aria-label="' + HtmlAttr(Words.Text('close', 'Close')) +
        '">&times;</a></form>';
    end;
    Result := Result + '</div>';
  end;
begin
  Result := Person('requestedBy', 'allowsRequestedBy', 'requested-by', 'Requested By', 'fa-shopping-cart', RequestedBy) +
    Person('assignedBy', 'allowsAssignedBy', 'assigned-by', 'Assigned By', 'fa-user-plus', AssignedBy);
end;

// _cardsec_description.pug: the description, and for whoever may change it
// the pencil - and the text - that open its editor, whose field is on the
// page only while open (weddy.js clones it from the template).
// The card's vote (cardDetails.jade's vote section, _cardsec_vote.pug in
// Weddy): the counts - names to see when the vote is public - the question,
// and the two buttons for whoever showVotingButtons lets vote.
function VoteSection(Db: TWLDb; Words: TWLTranslator; const UserId, BoardId, CardId: string): string;
var V: TCardVote; Tag: string;
begin
  Result := '';
  V := ReadCardVote(Db, UserId, BoardId, CardId);
  if not V.Present then Exit;
  if V.IsPublic then Tag := 'a' else Tag := 'div';
  Result := '<div class="card-details-group card-details-group-vote">' +
    '<h3 class="card-details-item-title js-toggle-card-section" data-section="vote" role="button" tabindex="0">' +
    '<i class="fa fa-caret-down"></i> ' + E(Words.Text('vote-question', 'Voting question')) + '</h3>' +
    '<div class="card-details-section" data-section="vote"><div class="vote-result">' +
    '<' + Tag + ' class="card-label card-label-green' + IfThen(V.IsPublic, ' js-show-positive-votes', '') + '">' +
    IntToStr(V.Positive) + '</' + Tag + '>' +
    '<' + Tag + ' class="card-label card-label-red' + IfThen(V.IsPublic, ' js-show-negative-votes', '') + '">' +
    IntToStr(V.Negative) + '</' + Tag + '></div>' +
    '<div class="viewer">' + E(V.Question) + '</div>';
  if V.CanVote then
    Result := Result + '<form class="js-vote-form" method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) + '/cards/' +
      HtmlAttr(HTTPEncode(CardId)) + '/vote" up-submit up-target=".board-wrapper">' +
      '<button class="card-details-green js-vote js-vote-positive' + IfThen(V.ForIt, ' voted', '') +
      '" type="submit" name="vote" value="positive">' + E(Words.Text('vote-for-it', 'for it')) + '</button>' +
      '<button class="card-details-red js-vote js-vote-negative' + IfThen(V.Against, ' voted', '') +
      '" type="submit" name="vote" value="negative">' + E(Words.Text('vote-against', 'against')) + '</button></form>';
  Result := Result + '</div></div>';
end;

// The card's Planning Poker (_cardsec_poker.pug in Weddy): the question and
// WeKan's deck, the user's card marked, for whoever may play.
function PokerSection(Db: TWLDb; Words: TWLTranslator; const UserId, BoardId, CardId: string): string;
const Classes: array[0..9] of string = ('one', 'two', 'three', 'five', 'eight', 'thirteen', 'twenty', 'forty',
  'one-hundred', 'unsure');
  Fallbacks: array[0..9] of string = ('1', '2', '3', '5', '8', '13', '20', '40', '100', '?');
var P: TCardPoker; i: Integer;
begin
  Result := '';
  P := ReadCardPoker(Db, UserId, BoardId, CardId);
  if not P.Present then Exit;
  Result := '<div class="card-details-group card-details-group-poker">' +
    '<h3 class="card-details-item-title js-toggle-card-section" data-section="poker" role="button" tabindex="0">' +
    '<i class="fa fa-caret-down"></i> ' + E(Words.Text('poker-question', 'Planning Poker')) + '</h3>' +
    '<div class="card-details-section" data-section="poker"><div class="viewer">' + E(P.Question) + '</div>';
  if P.CanVote then
  begin
    Result := Result + '<form class="poker-result" method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) + '/cards/' +
      HtmlAttr(HTTPEncode(CardId)) + '/poker" up-submit up-target=".board-wrapper">';
    for i := 0 to High(POKER_FIELDS) do
      Result := Result + '<div class="poker-deck"><div class="poker-card"><button class="inner js-poker js-poker-vote-' + Classes[i] +
        IfThen(P.Voted = POKER_FIELDS[i], ' poker-voted', '') + '" type="submit" name="state" value="' + POKER_FIELDS[i] + '">' +
        E(Words.Text('poker-' + POKER_FIELDS[i], Fallbacks[i])) + '</button></div></div>';
    Result := Result + '</form>';
  end;
  Result := Result + '</div></div>';
end;

function DescriptionSection(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId, Text: string; CanEdit: Boolean): string;
var Viewer: string;
begin
  Result := '';
  if not CanEdit and (Text = '') then Exit;
  Result := '<div class="card-details-group card-details-group-description">';
  if BoardAllows(Db, BoardId, 'allowsDescriptionTitle') then
    Result := Result + '<h3 class="card-details-item-title"><i class="fa fa-file-text-o"></i> ' +
      E(Words.Text('description', 'Description')) + '</h3>';
  Viewer := '';
  if Text <> '' then Viewer := MarkdownViewer(Text);
  if BoardAllows(Db, BoardId, 'allowsDescriptionText') then
  begin
    if CanEdit then
      Result := Result + '<a class="js-open-inlined-form" href="#" data-opens="edit-description" title="' +
        HtmlAttr(Words.Text('edit', 'Edit')) + '" aria-label="' + HtmlAttr(Words.Text('edit', 'Edit')) +
        '"><i class="fa fa-pencil-square-o" aria-hidden="true"></i></a>' +
        '<a class="js-open-inlined-form card-description-view" href="#" data-opens="edit-description" title="' +
        HtmlAttr(Words.Text('edit', 'Edit')) + '">' + Viewer + '</a>' +
        '<form class="card-description js-card-description js-inlined-form is-hidden" method="post" action="/b/' +
        HtmlAttr(HTTPEncode(BoardId)) + '/cards/' + HtmlAttr(HTTPEncode(CardId)) + '/description" up-submit up-target=".board-wrapper">' +
        '<template class="js-inlined-form-body"><div class="new-description js-new-description is-open">' +
        '<textarea class="editor js-new-description-input" name="description" dir="auto" aria-label="' +
        HtmlAttr(Words.Text('description', 'Description')) + '">' + E(Text) + '</textarea></div>' +
        '<div class="edit-controls clearfix"><button class="primary" type="submit">' + E(Words.Text('save', 'Save')) +
        '</button><a class="js-close-inlined-form" href="#" aria-label="' + HtmlAttr(Words.Text('close', 'Close')) +
        '">&times;</a></div></template></form>'
    else if Text <> '' then
      Result := Result + '<div class="card-description">' + Viewer + '</div>';
  end;
  Result := Result + '</div>';
end;

// What WeKan's minicard shows of its card, each where the board shows it on
// the minicard (Card Settings' *OnMinicard): its labels, its dates - for
// whoever may set them, opening the date picker, as WeKan's minicard dates -
// and its members.
type
  TMinicardShows = record
    Labels, Members: Boolean;
    Dates: array[0..3] of Boolean;
    SetDates: Boolean;
  end;

function MinicardShows(Db: TWLDb; const BoardId: string; SetDates: Boolean): TMinicardShows;
const Settings: array[0..3] of string = ('allowsReceivedDate', 'allowsStartDate', 'allowsDueDate', 'allowsEndDate');
var i: Integer;
begin
  Result.Labels := BoardAllows(Db, BoardId, 'allowsLabels') and BoardAllows(Db, BoardId, 'allowsLabelsOnMinicard');
  Result.Members := BoardAllows(Db, BoardId, 'allowsMembers') and BoardAllows(Db, BoardId, 'allowsMembersOnMinicard');
  for i := 0 to 3 do
    Result.Dates[i] := BoardAllows(Db, BoardId, Settings[i]) and
      BoardAllows(Db, BoardId, StringReplace(Settings[i], 'Date', 'DateOnMinicard', []));
  Result.SetDates := SetDates;
end;

function MinicardBadges(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId: string; const Shows: TMinicardShows;
  const Dates: array of string): string;
const
  Kinds: array[0..3] of string = ('received', 'start', 'due', 'end');
  Icons: array[0..3] of string = ('fa-sign-out', 'fa-hourglass-start', 'fa-clock-o', 'fa-hourglass-end');
  Captions: array[0..3] of string = ('Received', 'Start', 'Due', 'End');
  Titles: array[0..3] of string = ('editCardReceivedDatePopup-title', 'editCardStartDatePopup-title',
    'editCardDueDatePopup-title', 'editCardEndDatePopup-title');
  TitleCaptions: array[0..3] of string = ('Change received date', 'Change start date', 'Change due date', 'Change end date');
  Defaults: array[0..3] of string = ('now', 'now', '17:00', 'now');
var R: TWLRows; i: Integer; Line, Shown, Label_, Cls: string;
begin
  Result := '';
  if Shows.Labels then
  begin
    R := Db.Query('SELECT COALESCE(l.name,''''),l.color FROM card_labels c JOIN board_labels l ON l.id=c.labelId AND l.boardId=' +
      QuotedStr(BoardId) + ' WHERE c.cardId=' + QuotedStr(CardId) + ';');
    if Length(R) > 0 then
    begin
      Result := Result + '<div class="minicard-labels">';
      for i := 0 to High(R) do
        Result := Result + '<span class="card-label card-label-' + HtmlAttr(R[i][1]) + '" title="' + HtmlAttr(R[i][0]) +
          '">' + E(R[i][0]) + '</span>';
      Result := Result + '</div>';
    end;
  end;
  Line := '';
  for i := 0 to 3 do
    if Shows.Dates[i] and (Dates[i] <> '') then
    begin
      Label_ := Words.Text('card-' + Kinds[i], Captions[i]);
      Shown := StringReplace(Copy(Dates[i], 1, 16), 'T', ' ', []);
      Cls := 'badge minicard-date minicard-date-' + Kinds[i] + ' date ' + Kinds[i] + '-date';
      if Shows.SetDates then
        Line := Line + '<a class="' + Cls + ' js-edit-date js-' + Kinds[i] + '-date" href="#" title="' + HtmlAttr(Label_) +
          '" data-url="' + HtmlAttr('/b/' + HTTPEncode(BoardId) + '/cards/' + HTTPEncode(CardId) + '/dates/' + Kinds[i]) +
          '" data-date="' + HtmlAttr(Dates[i]) + '" data-default-time="' + Defaults[i] + '" data-title="' +
          HtmlAttr(Words.Text(Titles[i], TitleCaptions[i])) + '">'
      else
        Line := Line + '<span class="' + Cls + '" title="' + HtmlAttr(Label_) + '">';
      Line := Line + '<i class="fa ' + Icons[i] + '"></i> <time datetime="' + HtmlAttr(Dates[i]) + '">' + E(Shown) + '</time>' +
        IfThen(Shows.SetDates, '</a>', '</span>');
    end;
  if Line <> '' then Result := Result + '<div class="dates">' + Line + '</div>';
  if Shows.Members then
  begin
    R := Db.Query('SELECT u.username FROM card_members c JOIN users u ON u.id=c.userId WHERE c.cardId=' + QuotedStr(CardId) +
      ' ORDER BY u.username;');
    if Length(R) > 0 then
    begin
      Result := Result + '<div class="minicard-members js-minicard-members">';
      for i := 0 to High(R) do
        Result := Result + '<span class="member" title="' + HtmlAttr(R[i][0]) + '">' + E(UpperCase(Copy(R[i][0], 1, 2))) + '</span>';
      Result := Result + '</div>';
    end;
  end;
end;

// The board's background (Weddy's BackgroundStyle): only ever one of its own
// raster image attachments, by its address.
function BackgroundStyle(Db: TWLDb; const BoardId, Url: string): string;
const Prefix = '/cdn/storage/attachments/';
var Id: string; i: Integer;
begin
  Result := '';
  if Copy(Url, 1, Length(Prefix)) <> Prefix then Exit;
  Id := Copy(Url, Length(Prefix) + 1, MaxInt);
  if (Id = '') or (Length(Id) > 64) then Exit;
  for i := 1 to Length(Id) do if not (Id[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then Exit;
  if Length(Db.Query('SELECT 1 FROM attachments WHERE id=' + QuotedStr(Id) + ' AND boardId=' + QuotedStr(BoardId) +
    ' AND type IN (''image/png'',''image/jpeg'',''image/gif'',''image/webp'') AND ' + LiveAttachmentSQL(Db) + ';')) <> 1 then Exit;
  Result := ' style="background-image: url(' + Prefix + Id + '); background-size: cover;"';
end;

function BoardContent(Db: TWLDb; const S: TWLSession; Words: TWLTranslator; const BoardId, CardId: string;
  out BoardTitle: string; out Found: Boolean; Query: TStrings = nil): string;
var B, Lanes, Lists, Cards, Card: TWLRows; i, j, k: Integer; Route, Canvas, Details, Composer: string;
  Selector: TSelectionScope; Writable, Maximized, TextEditor, CanCreateLabel, BoardDates, Folded, ListFolded: Boolean;
  Shows: TMinicardShows; Header, FilterCond, CardSort, SortSql: string; Filter: TBoardFilter;
begin
  Result := ''; BoardTitle := ''; Found := False;
  if (BoardId = '') or (Pos(#0, BoardId + CardId) > 0) then Exit;
  if not BoardCanRead(Db, S.UserId, BoardId) then Exit;
  B := Db.Query('SELECT title,color,slug,COALESCE(backgroundImageURL,'''') FROM boards WHERE id=' + QuotedStr(BoardId) + ' AND archived=0 LIMIT 1;');
  if Length(B) <> 1 then Exit;
  BoardTitle := B[0][0];
  Route := BoardRoute(BoardId, B[0][2]);
  Writable := (S.UserId <> '') and BoardCanWrite(Db, S.UserId, BoardId);
  BoardDates := Writable and BoardCanEditCardText(Db, S.UserId, BoardId);
  Shows := MinicardShows(Db, BoardId, BoardDates);
  Filter := ParseBoardFilter(Db, BoardId, Query);
  FilterCond := BoardFilterSql(Filter);
  CardSort := ParseCardSort(Query);
  SortSql := CardSortSql(Db, BoardId, CardSort);
  Canvas := '';
  Lanes := Db.Query('SELECT id,title,color FROM swimlanes WHERE boardId=' + QuotedStr(BoardId) +
    ' AND archived=0 ORDER BY sort,id;');
  for i := 0 to High(Lanes) do
  begin
    // swimlaneHeader.jade: the caret folds the swimlane, for this user
    // (setSwimlaneCollapsedState); the "+" opens swimlaneAddPopup. A folded
    // swimlane keeps its header and shows nothing of its lists: it is no
    // .js-swimlane, and has no id.
    Folded := (S.UserId <> '') and ProfileFold(Db, S.UserId, 'collapsedSwimlanes', BoardId, Lanes[i][0]);
    Header := '<div class="swimlane-header js-swimlane-header" data-swimlane="' + HtmlAttr(Lanes[i][0]) + '">';
    if S.UserId <> '' then
      Header := Header + '<a class="swimlane-collapse-indicator js-collapse-swimlane swimlane-header-collapse" href="#" data-swimlane="' +
        HtmlAttr(Lanes[i][0]) + '" data-collapsed="' + IfThen(Folded, 'true', '') + '" title="' +
        HtmlAttr(Words.Text('collapse', 'Collapse')) + '" aria-label="' + HtmlAttr(Words.Text('collapse', 'Collapse')) +
        '"><i class="fa ' + IfThen(Folded, 'fa-caret-right', 'fa-caret-down') + '"></i></a>';
    Header := Header + '<span class="swimlane-header-name title">' + E(Lanes[i][1]) + '</span>';
    if Writable then
      Header := Header + '<a class="js-open-add-swimlane-menu swimlane-header-plus-icon" href="#" data-swimlane="' +
        HtmlAttr(Lanes[i][0]) + '" title="' + HtmlAttr(Words.Text('add-swimlane', 'Add Swimlane')) + '" aria-label="' +
        HtmlAttr(Words.Text('add-swimlane', 'Add Swimlane')) + '"><i class="fa fa-plus"></i></a>';
    Header := Header + '</div>';
    if Folded then
    begin
      Canvas := Canvas + '<div class="swimlane swimlane-collapsed" data-swimlane="' + HtmlAttr(Lanes[i][0]) + '">' + Header + '</div>';
      Continue;
    end;
    Canvas := Canvas + '<div class="swimlane js-swimlane" id="swimlane-' + HtmlAttr(Lanes[i][0]) + '" data-swimlane="' +
      HtmlAttr(Lanes[i][0]) + '">' + Header + '<div class="list-group js-lists">';
    Lists := Db.Query('SELECT id,title,color,collapsed FROM lists WHERE boardId=' + QuotedStr(BoardId) +
      ' AND (swimlaneId=' + QuotedStr(Lanes[i][0]) + ' OR swimlaneId='''') AND archived=0 AND deletedAt IS NULL ORDER BY sort,id;');
    for j := 0 to High(Lists) do
    begin
      Composer := '';
      if Writable then
        // board.pug: the list header's "+" (Add card to top of list), and the
        // composer weddy.js clones from its template into the list.
        Composer := '<a class="js-add-card list-header-plus-top" href="#" data-list="' + HtmlAttr(Lists[j][0]) +
          '" data-swimlane="' + HtmlAttr(Lanes[i][0]) + '" title="' +
          HtmlAttr(Words.Text('add-card-to-top-of-list', 'Add card to top of list')) + '" aria-label="' +
          HtmlAttr(Words.Text('add-card-to-top-of-list', 'Add card to top of list')) + '">+</a>' +
          '<a class="js-open-list-menu" href="#" data-list="' + HtmlAttr(Lists[j][0]) + '" data-swimlane="' +
          HtmlAttr(Lanes[i][0]) + '" title="' + HtmlAttr(Words.Text('listActionPopup-title', 'List Actions')) +
          '" aria-label="' + HtmlAttr(Words.Text('listActionPopup-title', 'List Actions')) + '">&#9776;</a>' +
          // listHeader.jade: the inline Add List composer after this list (#6465).
          '<a class="js-add-list-here list-header-add-list" href="#" data-list="' + HtmlAttr(Lists[j][0]) + '" data-swimlane="' +
          HtmlAttr(Lanes[i][0]) + '" title="' + HtmlAttr(Words.Text('add-list', 'Add list')) + '" aria-label="' +
          HtmlAttr(Words.Text('add-list', 'Add list')) + '"><i class="fa fa-plus-square-o"></i></a>';
      // listHeader.jade's caret: per user, per list in this swimlane (#6712).
      ListFolded := ProfileFold(Db, S.UserId, 'collapsedLists', BoardId, Lists[j][0] + ':' + Lanes[i][0]) or
        ProfileFold(Db, S.UserId, 'collapsedLists', BoardId, Lists[j][0]);
      Canvas := Canvas + '<div class="list js-list' + IfThen(ListFolded, ' list-collapsed', '') + '" id="js-list-' + HtmlAttr(Lists[j][0]) +
        '" data-list="' + HtmlAttr(Lists[j][0]) + '" data-swimlane="' + HtmlAttr(Lanes[i][0]) + '"><div class="list-header">' +
        IfThen(S.UserId <> '', '<a class="list-collapse-indicator js-collapse" href="#" data-collapse="' + HtmlAttr(Words.Text('collapse', 'Collapse')) +
          '" data-uncollapse="' + HtmlAttr(Words.Text('uncollapse', 'Uncollapse')) + '" title="' +
          HtmlAttr(IfThen(ListFolded, Words.Text('uncollapse', 'Uncollapse'), Words.Text('collapse', 'Collapse'))) + '" aria-label="' +
          HtmlAttr(IfThen(ListFolded, Words.Text('uncollapse', 'Uncollapse'), Words.Text('collapse', 'Collapse'))) + '"><i class="fa ' +
          IfThen(ListFolded, 'fa-caret-right', 'fa-caret-down') + '"></i></a>', '') +
        '<span class="list-header-name">' + E(Lists[j][1]) + '</span>' + Composer + '</div>' +
        '<div class="list-body js-minicards" data-list="' + HtmlAttr(Lists[j][0]) + '" data-swimlane="' + HtmlAttr(Lanes[i][0]) + '">';
      Cards := Db.Query('SELECT c.id,c.title,c.sort,COALESCE(c.receivedAt,''''),COALESCE(c.startAt,''''),' +
        'COALESCE(c.dueAt,''''),COALESCE(c.endAt,''''),COALESCE((SELECT attachments.id FROM attachments WHERE attachments.id=c.coverId AND ' +
        'attachments.cardId=c.id AND attachments.type IN (''image/png'',''image/jpeg'',''image/gif'',''image/webp'') AND ' +
        // LiveAttachmentSQL names the table attachments, unaliased.
        LiveAttachmentSQL(Db) + '),'''') FROM cards c WHERE c.boardId=' + QuotedStr(BoardId) +
        ' AND c.swimlaneId=' + QuotedStr(Lanes[i][0]) + ' AND c.listId=' + QuotedStr(Lists[j][0]) +
        ' AND c.archived=0 AND c.deletedAt IS NULL' + FilterCond + ' ORDER BY ' + SortSql + 'c.sort,c.id;');
      for k := 0 to High(Cards) do
        // A block that opens the card, as Weddy's and WeKan's minicard.
        Canvas := Canvas + '<div class="minicard-wrapper js-minicard" up-href="' +
          HtmlAttr(CardRoute(BoardId, B[0][2], Cards[k][0])) + '" up-follow up-clickable up-target=".board-wrapper" data-card="' +
          HtmlAttr(Cards[k][0]) + '" data-card-id="' + HtmlAttr(Cards[k][0]) + '" data-sort="' + HtmlAttr(Cards[k][2]) +
          '"><div class="minicard">' +
          // WeKan's minicard cover: the card's cover image.
          IfThen(Cards[k][7] <> '', '<div class="minicard-cover"><img src="/cdn/storage/attachments/' + HtmlAttr(HTTPEncode(Cards[k][7])) +
            '" alt="" loading="lazy"></div>', '') + '<div class="minicard-title"><span class="minicard-title-text">' +
          MarkdownViewer(Cards[k][1]) + '</span></div>' + MinicardBadges(Db, Words, BoardId, Cards[k][0], Shows,
          [Cards[k][3], Cards[k][4], Cards[k][5], Cards[k][6]]) + '</div></div>';
      Canvas := Canvas + '</div>';
      if Writable then
        Canvas := Canvas + '<template class="js-card-composer-template">' +
          '<form class="js-inlined-form js-card-composer" method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) +
          '/cards" up-submit up-target=".board-wrapper">' +
          '<input type="hidden" name="listId" value="' + HtmlAttr(Lists[j][0]) + '">' +
          '<input type="hidden" name="swimlaneId" value="' + HtmlAttr(Lanes[i][0]) + '">' +
          '<input class="js-card-position" type="hidden" name="position" value="bottom">' +
          '<div class="minicard minicard-composer js-composer"><textarea class="minicard-composer-textarea js-card-title" name="title" dir="auto" aria-label="' +
          HtmlAttr(Words.Text('title', 'Title')) + '" required></textarea></div>' +
          '<div class="add-controls clearfix"><button class="primary confirm" type="submit">' +
          E(Words.Text('add-card', 'Add Card')) + '</button><a class="js-close-inlined-form" href="#" aria-label="' +
          HtmlAttr(Words.Text('close', 'Close')) + '">&times;</a></div></form></template>' +
          '<a class="open-minicard-composer js-card-composer js-open-inlined-form" href="#" title="' +
          HtmlAttr(Words.Text('add-card-to-bottom-of-list', 'Add card to bottom of list')) + '"><i class="fa fa-plus"></i> ' +
          E(Words.Text('add-card', 'Add Card')) + '</a>';
      Canvas := Canvas + '</div>';
    end;
    if Writable then
      // board.pug: WeKan's addListInline, cloned after the list whose header +
      // was clicked (weddy.js, createListAfter), and the Add list composer
      // after the swimlane's lists.
      Canvas := Canvas + '<template class="js-add-list-inline-template"><div class="list list-composer js-list-composer js-add-list-inline">' +
        '<div class="list-header-add"><form class="js-add-list-inline-form"><textarea class="list-name-input full-line" rows="2" dir="auto" placeholder="' +
        HtmlAttr(Words.Text('add-list', 'Add list')) + '" aria-label="' + HtmlAttr(Words.Text('add-list', 'Add list')) +
        '" autocomplete="off" required></textarea><div class="edit-controls clearfix"><button class="primary confirm" type="submit">' +
        E(Words.Text('save', 'Save')) + '</button><a class="js-close-add-list-inline" href="#" title="' + HtmlAttr(Words.Text('close', 'Close')) +
        '" aria-label="' + HtmlAttr(Words.Text('close', 'Close')) + '">&times;</a></div></form></div></div></template>' +
        '<div class="list js-list-composer"><form class="js-inlined-form js-list-form" method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) +
        '/lists" up-submit up-target=".board-wrapper"><input type="hidden" name="swimlaneId" value="' + HtmlAttr(Lanes[i][0]) + '">' +
        '<input class="list-name-input" type="text" name="title" aria-label="' + HtmlAttr(Words.Text('add-list', 'Add list')) +
        '" placeholder="' + HtmlAttr(Words.Text('add-list', 'Add list')) + '" required><button class="primary" type="submit">' +
        E(Words.Text('add-list', 'Add list')) + '</button></form></div>';
    Canvas := Canvas + '</div></div>';
  end;
  Details := '';
  if CardId <> '' then
  begin
    Selector := TSelectionScope.Create(Db);
    try
      Card := Db.Query('SELECT title,description,COALESCE(requestedBy,''''),COALESCE(assignedBy,''''),COALESCE(receivedAt,''''),' +
        'COALESCE(startAt,''''),COALESCE(dueAt,''''),COALESCE(endAt,''''),swimlaneId,listId FROM cards WHERE id=' + QuotedStr(CardId) + ' AND boardId=' +
        QuotedStr(BoardId) + ' AND archived=0 AND deletedAt IS NULL AND ' + Selector.StringField('cards', 'id') +
        ' AND ' + Selector.StringField('cards', 'boardId') + ';');
    finally
      Selector.Free;
    end;
    if Length(Card) <> 1 then Exit;
    Maximized := ProfileFlag(Db, S.UserId, 'cardMaximized');
    Details := '<div class="card-details js-card-details' + IfThen(Maximized, ' card-details-maximized', '') +
      '" data-card="' + HtmlAttr(CardId) + '">' +
      '<div class="card-details-header"><h2 class="card-details-title js-card-title">' +
      '<span class="card-details-title-edit-zone js-open-inlined-form">' + MarkdownViewer(Card[0][0]) + '</span></h2>';
    // board.pug: the title's editor, opened by its leading part (weddy.js).
    if Writable then
      Details := Details + '<form class="js-card-details-title js-inlined-form is-hidden" method="post" action="/b/' +
        HtmlAttr(HTTPEncode(BoardId)) + '/cards/' + HtmlAttr(HTTPEncode(CardId)) + '/title" up-submit up-target=".board-wrapper">' +
        '<textarea class="js-edit-card-title" name="title" rows="2" dir="auto" aria-label="' + HtmlAttr(Words.Text('title', 'Title')) +
        '" required>' + E(Card[0][0]) + '</textarea><button class="primary" type="submit">' + E(Words.Text('save', 'Save')) +
        '</button></form>';
    // The user's own full-screen card (WeKan's toggleCardMaximized, /_methods/).
    if Maximized then
      Details := Details + '<a class="js-minimize-card-details" href="#" title="' +
        HtmlAttr(Words.Text('minimize-card', 'Minimize Card')) + '" aria-label="' +
        HtmlAttr(Words.Text('minimize-card', 'Minimize Card')) + '">&#128471;</a>'
    else
      Details := Details + '<a class="js-maximize-card-details" href="#" title="' +
        HtmlAttr(Words.Text('maximize-card', 'Maximize Card')) + '" aria-label="' +
        HtmlAttr(Words.Text('maximize-card', 'Maximize Card')) + '">&#128470;</a>';
    // cardDetails.jade's hamburger: cardDetailsActionsPopup.
    if Writable then
      Details := Details + '<a class="card-details-menu js-open-card-details-menu" href="#" title="' +
        HtmlAttr(Words.Text('cardDetailsActionsPopup-title', 'Card Actions')) + '" aria-label="' +
        HtmlAttr(Words.Text('cardDetailsActionsPopup-title', 'Card Actions')) + '">&#9776;</a>';
    Details := Details +
      '<a class="js-close-card-details" href="' + HtmlAttr(Route) + '" aria-label="' + HtmlAttr(Words.Text('close', 'Close')) +
      '" up-follow up-target=".board-wrapper">&times;</a></div>';
    Details := Details + CardWatchLink(Db, Words, S, BoardId, CardId);
    Details := Details + ListPickerSection(Db, Words, BoardId, CardId, Card[0][8], Card[0][9], Writable);
    if BoardAllows(Db, BoardId, 'allowsLabels') then
      Details := Details + LabelsSection(Db, Words, BoardId, CardId, Writable);
    if BoardAllows(Db, BoardId, 'allowsMembers') then
      Details := Details + MembersSection(Db, Words, CardId, Writable);
    TextEditor := Writable and BoardCanEditCardText(Db, S.UserId, BoardId);
    CanCreateLabel := Writable and BoardCanCreateLabel(Db, S.UserId, BoardId);
    Details := Details + DatesSection(Db, Words, BoardId, CardId, [Card[0][4], Card[0][5], Card[0][6], Card[0][7]], TextEditor);
    Details := Details + PeopleSection(Db, Words, BoardId, CardId, Card[0][2], Card[0][3], TextEditor) +
      DescriptionSection(Db, Words, BoardId, CardId, Card[0][1], TextEditor);
    Details := Details + VoteSection(Db, Words, S.UserId, BoardId, CardId) + PokerSection(Db, Words, S.UserId, BoardId, CardId);
    Details := Details + CustomFieldsSection(Db, Words, S, BoardId, CardId, Writable) +
      AttachmentsSection(Db, Words, BoardId, CardId, Writable, Writable and BoardCanAdmin(Db, S.UserId, BoardId));
    Details := Details + ChecklistsSection(Db, Words, BoardId, CardId, Writable) +
      CommentsSection(Db, Words, BoardId, CardId, (S.UserId <> '') and BoardCanComment(Db, S.UserId, BoardId)) + '</div>';
    if Writable then Details := Details + ChecklistPopups(Words, BoardId, CardId) + MembersPopup(Db, Words, BoardId, CardId) +
      LabelsPopups(Db, Words, BoardId, CardId, CanCreateLabel) + CustomFieldsPopup(Db, Words, S, BoardId, CardId);
    Details := Details + AttachmentsPopups(Words, BoardId, CardId, Writable);
    if Writable then
      Details := Details + CardMenuPopups(Db, Words, S, BoardId, B[0][2], CardId, Card[0][0], Card[0][8], Card[0][9]);
  end;
  Details := Details + MemberPopups(Db, Words, S, BoardId);
  // swimlaneAddPopup, drawn once: weddy.js sets the swimlane it was opened from.
  if Writable then
    Details := Details + '<template class="js-pop-over-template" data-pop="add-swimlane" data-title="' +
      HtmlAttr(Words.Text('swimlaneAddPopup-title', 'Add Swimlane')) + '"><form class="js-add-swimlane-form" method="post" action="/b/' +
      HtmlAttr(HTTPEncode(BoardId)) + '/swimlanes" up-submit up-target=".board-wrapper">' +
      '<input class="js-swimlane-after" type="hidden" name="after"><textarea class="swimlane-name-input full-line" name="title" rows="2" ' +
      'dir="auto" placeholder="' + HtmlAttr(Words.Text('add-swimlane', 'Add Swimlane')) + '" aria-label="' +
      HtmlAttr(Words.Text('add-swimlane', 'Add Swimlane')) + '" autocomplete="off" required></textarea>' +
      '<label class="swimlane-placement-option"><input class="js-swimlane-placement" type="radio" name="placement" value="below" checked>' +
      '<span dir="auto">' + E(Words.Text('below-selected-swimlane', 'Below selected swimlane')) + '</span></label>' +
      '<label class="swimlane-placement-option"><input class="js-swimlane-placement" type="radio" name="placement" value="above">' +
      '<span dir="auto">' + E(Words.Text('above-selected-swimlane', 'Above selected swimlane')) + '</span></label>' +
      '<div class="edit-controls clearfix"><button class="primary confirm" type="submit">' + E(Words.Text('add', 'Add')) +
      '</button></div></form></template>';
  // The date picker, drawn once: the opened card's dates and the minicards'
  // open it (weddy.js).
  if BoardDates then Details := Details + DatePopup(Words);
  // board.pug's list menu, drawn once; weddy.js opens it for the list whose
  // menu button was clicked.
  if Writable then
    Details := Details + '<template class="js-pop-over-template" data-pop="list-menu" data-title="' +
      HtmlAttr(Words.Text('listActionPopup-title', 'List Actions')) + '"><ul class="pop-over-list">' +
      '<li><a class="js-add-card list-header-plus-top" href="#">&uarr; ' +
      E(Words.Text('add-card-to-top-of-list', 'Add card to top of list')) + '</a></li>' +
      '<li><a class="js-add-card list-header-plus-bottom" href="#">&darr; ' +
      E(Words.Text('add-card-to-bottom-of-list', 'Add card to bottom of list')) + '</a></li></ul></template>';
  Result := '<div class="board-wrapper board-color-' + HtmlAttr(B[0][1]) + '"' + BackgroundStyle(Db, BoardId, B[0][3]) +
    ' data-board="' + HtmlAttr(BoardId) + '">' +
    '<div class="board-header"><h1 class="header-board-name js-board-title">' + E(BoardTitle) + '</h1>' +
    BoardStarButton(Db, Words, S, BoardId) + BoardWatchButton(Db, Words, S, BoardId) + FilterButton(Words, Filter) + SortButton(Words, CardSort) + '</div>' +
    BoardSidebar(Db, Words, S, BoardId, Writable, FilterSidebar(Db, Words, BoardId, Filter)) +
    '<div class="board-canvas" id="board-canvas">' + Canvas + '</div>' + Details + '</div>';
  Found := True;
end;

procedure SendPage(Response: TResponse; Code: Integer; const Html: string);
begin
  Response.Code := Code;
  Response.ContentType := 'text/html; charset=utf-8';
  Response.SetCustomHeader('Cache-Control', 'no-store');
  Response.Content := Html;
  Response.ContentLength := Length(Response.Content);
  Response.SendContent;
end;

procedure SendJsonAnswer(Response: TResponse; Code: Integer; const Json: string);
begin
  Response.Code := Code;
  Response.ContentType := 'application/json; charset=utf-8';
  Response.SetCustomHeader('Cache-Control', 'no-store');
  Response.Content := Json;
  Response.ContentLength := Length(Response.Content);
  Response.SendContent;
end;

// weddy.js's callAsync(name, ...args): POST /_methods/<name> with the
// arguments as a JSON array, answered {"result": ...} or, as Meteor answers a
// method error, {"error": code, "reason": text}. The methods are WeKan's
// Meteor methods of the same name, each with WeKan's own meaning.
procedure ServeMethod(Request: TRequest; Response: TResponse; const Name: string);
var T: TWLTenant; S: TWLSession; Args: TJSONData; Selector: TJSONObject; Id, Error: string; R: TWLRows; Code, n: Integer; Lang: TWLLanguage;
begin
  if not (ResolveTenant(Request, T) and TenantOpen(T)) then
  begin SendJsonAnswer(Response, 404, '{"error":404,"reason":"Unknown domain"}'); Exit; end;
  if not Html5User(T.Db, Request, S) then
  begin SendJsonAnswer(Response, 401, '{"error":401,"reason":"Must be logged in"}'); Exit; end;
  if Name = 'toggleCardMaximized' then
  begin
    // models/users.js: profile.cardMaximized becomes the opposite of what it was.
    if not T.Db.Exec('UPDATE users SET profile_json=json_set(CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END,' +
      '''$.cardMaximized'',json(CASE WHEN json_valid(profile_json) AND json_extract(profile_json,''$.cardMaximized'')=1 ' +
      'THEN ''false'' ELSE ''true'' END)) WHERE id=' + QuotedStr(S.UserId) + ';') then
    begin SendJsonAnswer(Response, 500, '{"error":500,"reason":"Could not save"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":1}');
    Exit;
  end;
  if Name = 'toggleBoardStar' then
  begin
    // models/users.js: [boardId], the board in the user's starredBoards or out of it.
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 1) and (TJSONArray(Args).Items[0].JSONType = jtString)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Code := ToggleViewBoardStar(T.Db, S.UserId, TJSONArray(Args).Items[0].AsString, Error);
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":' + IntToStr(Code) + ',"reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":1}');
    Exit;
  end;
  if Name = 'setCreateUser' then
  begin
    // WeKan's setCreateUser: [fullname, username, initials, password, isAdmin,
    // isActive (the form's inverted select: loginDisabled), email, orgs,
    // teams, boards], by a site admin; it answers nothing.
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      Code := 400;
      if (Args is TJSONArray) and (TJSONArray(Args).Count = 10) then
      begin
        Code := 200;
        for n := 0 to 6 do if TJSONArray(Args).Items[n].JSONType <> jtString then Code := 400;
        for n := 7 to 9 do if TJSONArray(Args).Items[n].JSONType <> jtArray then Code := 400;
      end;
      if Code <> 200 then begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Code := AdminCreateViewUser(T, S.UserId, TJSONArray(Args).Items[0].AsString, TJSONArray(Args).Items[1].AsString,
        TJSONArray(Args).Items[2].AsString, TJSONArray(Args).Items[3].AsString, TJSONArray(Args).Items[4].AsString,
        TJSONArray(Args).Items[5].AsString, TJSONArray(Args).Items[6].AsString, Id, Error);
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":"' + StringToJSONString(Id) + '"}');
    Exit;
  end;
  if Name = 'setMobileMode' then
  begin
    // server/models/users.js: [enabled], a boolean, as profile.mobileMode.
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 1) and (TJSONArray(Args).Items[0].JSONType = jtBoolean)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Id := IfThen(TJSONArray(Args).Items[0].AsBoolean, 'true', 'false');
    finally
      Args.Free;
    end;
    if not T.Db.Exec('UPDATE users SET profile_json=json_set(CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END,' +
      '''$.mobileMode'',json(' + QuotedStr(Id) + ')) WHERE id=' + QuotedStr(S.UserId) + ';') then
    begin SendJsonAnswer(Response, 500, '{"error":500,"reason":"Could not save"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":null}');
    Exit;
  end;
  if Name = 'setLanguage' then
  begin
    // server/models/users.js: [language], a supported one, as profile.language.
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 1) and (TJSONArray(Args).Items[0].JSONType = jtString)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      if not FindLanguage(TJSONArray(Args).Items[0].AsString, Lang) then
      begin SendJsonAnswer(Response, 400, '{"error":"invalid-language","reason":"Language is not supported"}'); Exit; end;
    finally
      Args.Free;
    end;
    if not T.Db.Exec('UPDATE users SET profile_json=json_set(CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END,' +
      '''$.language'',' + QuotedStr(Lang.Tag) + ') WHERE id=' + QuotedStr(S.UserId) + ';') then
    begin SendJsonAnswer(Response, 500, '{"error":500,"reason":"Could not save"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":null}');
    Exit;
  end;
  if Name = 'toggleCustomFieldsGrid' then
  begin
    // models/users.js toggleFieldsGrid: profile.customFieldsGrid becomes the opposite.
    if not T.Db.Exec('UPDATE users SET profile_json=json_set(CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END,' +
      '''$.customFieldsGrid'',json(CASE WHEN json_valid(profile_json) AND json_extract(profile_json,''$.customFieldsGrid'')=1 ' +
      'THEN ''false'' ELSE ''true'' END)) WHERE id=' + QuotedStr(S.UserId) + ';') then
    begin SendJsonAnswer(Response, 500, '{"error":500,"reason":"Could not save"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":1}');
    Exit;
  end;
  if Name = 'setListCollapsedState' then
  begin
    // server/models/users.js: [boardId, "listId:swimlaneId" or listId,
    // collapsed], the user's own profile.collapsedLists[boardId][key] (#6712).
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 3) and (TJSONArray(Args).Items[0].JSONType = jtString) and
        (TJSONArray(Args).Items[1].JSONType = jtString) and (TJSONArray(Args).Items[2].JSONType = jtBoolean)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Code := SetViewProfileFold(T, S.UserId, 'collapsedLists', TJSONArray(Args).Items[0].AsString,
        TJSONArray(Args).Items[1].AsString, TJSONArray(Args).Items[2].AsBoolean, Error);
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":' + IntToStr(Code) + ',"reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":null}');
    Exit;
  end;
  if Name = 'setSwimlaneCollapsedState' then
  begin
    // server/models/users.js: [boardId, swimlaneId, collapsed], the user's own
    // profile.collapsedSwimlanes[boardId][swimlaneId]; keys are ids only
    // (assertSafeMapKey), and of a board the user may read.
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 3) and (TJSONArray(Args).Items[0].JSONType = jtString) and
        (TJSONArray(Args).Items[1].JSONType = jtString) and (TJSONArray(Args).Items[2].JSONType = jtBoolean)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Code := SetViewProfileFold(T, S.UserId, 'collapsedSwimlanes', TJSONArray(Args).Items[0].AsString,
        TJSONArray(Args).Items[1].AsString, TJSONArray(Args).Items[2].AsBoolean, Error);
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":' + IntToStr(Code) + ',"reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":null}');
    Exit;
  end;
  if Name = 'createListAfter' then
  begin
    // server/models/lists.js: {title, boardId, swimlaneId, afterListId, type};
    // it answers the new list's id.
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count >= 1) and (TJSONArray(Args).Items[0] is TJSONObject)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Selector := TJSONObject(TJSONArray(Args).Items[0]);
      if (Selector.Find('title') = nil) or (Selector.Find('title').JSONType <> jtString) or
        (Selector.Find('boardId') = nil) or (Selector.Find('boardId').JSONType <> jtString) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Code := CreateViewList(T, S.UserId, Selector.Get('boardId', ''),
        Selector.Get('swimlaneId', ''), Selector.Get('afterListId', ''), Selector.Get('title', ''), Id, Error);
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":' + IntToStr(Code) + ',"reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":"' + StringToJSONString(Id) + '"}');
    Exit;
  end;
  if Name = '/checklists/remove' then
  begin
    // The collection's own method (server/permissions/checklists.js): a
    // checklist by its id only, removed by whoever may change its card, with
    // its items and nobody else's (#6816); it answers how many it removed.
    Id := '';
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if (Args is TJSONArray) and (TJSONArray(Args).Count >= 1) and (TJSONArray(Args).Items[0] is TJSONObject) then
      begin
        Selector := TJSONObject(TJSONArray(Args).Items[0]);
        if (Selector.Count = 1) and (Selector.Names[0] = '_id') and (Selector.Items[0].JSONType = jtString) then
          Id := Selector.Items[0].AsString;
      end;
    finally
      Args.Free;
    end;
    if (Id = '') or (Pos(#0, Id) > 0) then
    begin
      SendJsonAnswer(Response, 403, '{"error":403,"reason":"Not permitted. Untrusted code may only remove documents by ID."}');
      Exit;
    end;
    R := T.Db.Query('SELECT l.cardId,c.boardId FROM checklists l JOIN cards c ON c.id=l.cardId WHERE l.id=' + QuotedStr(Id) + ' LIMIT 1;');
    if Length(R) <> 1 then begin SendJsonAnswer(Response, 200, '{"result":0}'); Exit; end;
    Code := DeleteViewChecklist(T, S.UserId, R[0][1], R[0][0], Id, Error);
    if Code = 403 then
    begin SendJsonAnswer(Response, 403, '{"error":403,"reason":"Access denied"}'); Exit; end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":' + IntToStr(Code) + ',"reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":1}');
    Exit;
  end;
  SendJsonAnswer(Response, 404, '{"error":404,"reason":"Method ''' + StringToJSONString(Name) + ''' not found"}');
end;

// The parts of a path, each decoded: /b/x/cards/y -> b, x, cards, y.
function PathParts(const Path: string): TStringArray;
var Rest: string; At: Integer;
begin
  Result := nil;
  Rest := Path;
  if (Rest <> '') and (Rest[1] = '/') then Delete(Rest, 1, 1);
  while Rest <> '' do
  begin
    At := Pos('/', Rest);
    if At = 0 then At := Length(Rest) + 1;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := HTTPDecode(Copy(Rest, 1, At - 1));
    Delete(Rest, 1, At);
  end;
end;

// The signed-in user as WeKan's client knows it: _id, username, profile.
function UserJson(Db: TWLDb; const UserId: string): string;
var R: TWLRows; Profile: string;
begin
  R := Db.Query('SELECT id,username,CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END FROM users WHERE id=' +
    QuotedStr(UserId) + ' LIMIT 1;');
  if Length(R) <> 1 then Exit('{}');
  Profile := R[0][2];
  if (Profile = '') or (Profile[1] <> '{') then Profile := '{}';
  Result := '{"_id":"' + StringToJSONString(R[0][0]) + '","username":"' + StringToJSONString(R[0][1]) + '","profile":' + Profile + '}';
end;

// cardAttachmentsPopup's upload: one file, onto a live card of a board the
// user may change, stored as the HTML4 view's upload stores it.
function AddViewAttachment(const T: TWLTenant; const UserId, BoardId, CardId: string; Request: TRequest;
  out Error: string): Integer;
var Rows: TWLRows; Upload: TUploadedFile; FileType, Id: string;
begin
  Error := '';
  if (BoardId = '') or (CardId = '') or (Pos(#0, BoardId + CardId) > 0) then begin Error := 'Card not found'; Exit(404); end;
  if not BoardCanWrite(T.Db, UserId, BoardId) then begin Error := 'Board access forbidden'; Exit(403); end;
  Rows := T.Db.Query('SELECT swimlaneId,listId FROM cards WHERE id=' + QuotedStr(CardId) + ' AND boardId=' + QuotedStr(BoardId) +
    ' AND archived=0 AND deletedAt IS NULL;');
  if Length(Rows) <> 1 then begin Error := 'Card not found'; Exit(404); end;
  if Request.Files.Count <> 1 then begin Error := 'Upload failed'; Exit(400); end;
  Upload := Request.Files[0];
  if (Upload.FieldName <> 'file') or (Upload.FileName = '') or (Pos(#0, Upload.FileName + Upload.ContentType) > 0) or
    (Pos(#13, Upload.ContentType) > 0) or (Pos(#10, Upload.ContentType) > 0) then
  begin Error := 'Upload failed'; Exit(400); end;
  FileType := Upload.ContentType;
  if FileType = '' then FileType := 'application/octet-stream';
  if not StoreAttachment(T, UserId, BoardId, Rows[0][0], Rows[0][1], CardId, ExtractFileName(Upload.FileName), FileType,
    Upload.Stream, Id, True) then
  begin Error := 'Upload failed'; Exit(500); end;
  Result := 200;
end;

// The attachment's delete, by whoever may change the board, of that card only.
function DeleteViewAttachment(const T: TWLTenant; const UserId, BoardId, CardId, AttachmentId: string; out Error: string): Integer;
begin
  Error := '';
  if (AttachmentId = '') or (Pos(#0, BoardId + CardId + AttachmentId) > 0) then begin Error := 'Attachment not found'; Exit(404); end;
  if not BoardCanWrite(T.Db, UserId, BoardId) then begin Error := 'Board access forbidden'; Exit(403); end;
  if Length(T.Db.Query('SELECT 1 FROM attachments WHERE id=' + QuotedStr(AttachmentId) + ' AND boardId=' + QuotedStr(BoardId) +
    ' AND cardId=' + QuotedStr(CardId) + ';')) <> 1 then begin Error := 'Attachment not found'; Exit(404); end;
  if not DeleteStoredAttachment(T, UserId, BoardId, AttachmentId, CardId) then begin Error := 'Could not delete attachment'; Exit(500); end;
  Result := 200;
end;

// WeKan's file route, /cdn/storage/attachments/:id[/original/:name or
// /thumbnail]: an attachment of a live card on a board the signed-in user may
// read. Only a raster image is shown inline (SendStoredDownload); ?download=
// and every other file come as a download, with nosniff.
function ServeAttachmentFile(Request: TRequest; Response: TResponse; const Path: string): Boolean;
var T: TWLTenant; S: TWLSession; P: TStringArray; Rows: TWLRows; Preview: string;
begin
  Result := False;
  P := PathParts(Path);
  if (Length(P) < 4) or (P[0] <> 'cdn') or (P[1] <> 'storage') or (P[2] <> 'attachments') or (P[3] = '') then Exit;
  if not ((Length(P) = 4) or ((Length(P) = 5) and (P[4] = 'thumbnail')) or ((Length(P) = 6) and (P[4] = 'original'))) then Exit;
  if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
  Result := True;
  Rows := nil;
  if Html5User(T.Db, Request, S) and (Pos(#0, P[3]) = 0) then
  begin
    Rows := T.Db.Query('SELECT a.boardId,COALESCE(a.name,''''),COALESCE(a.type,'''') FROM attachments a JOIN cards c ON c.id=a.cardId ' +
      'AND c.boardId=a.boardId AND c.archived=0 AND c.deletedAt IS NULL WHERE a.id=' + QuotedStr(P[3]) + ' AND ' +
      LiveAttachmentSQL(T.Db) + ';');
    if (Length(Rows) = 1) and not BoardCanRead(T.Db, S.UserId, Rows[0][0]) then Rows := nil;
  end;
  Preview := '';
  if (Length(Rows) = 1) and (Request.QueryFields.Values['download'] = '') then Preview := Rows[0][2];
  if (Length(Rows) = 1) and SendStoredDownload(Response, StoreFilePath(T.FilesDir, 'attachme', P[3]), Rows[0][1], Preview) then Exit;
  SendJsonAnswer(Response, 404, '{"error":"Attachment not found"}');
end;

function ServeHtml5Action(Request: TRequest; Response: TResponse): Boolean;
var T: TWLTenant; S: TWLSession; Language: TWLLanguage; Words: TWLTranslator;
  Path, BoardId, CardId, ChecklistId, ItemId, NewId, Action, Error, Content, BoardTitle, Title, Back, Columns, Values, Sets: string;
  P: TStringArray; Code, n: Integer; Found: Boolean;
begin
  Result := False;
  // weddy.js's GET /b/:id/places (the move and copy pop-overs' other board),
  // before WeKan's routes take /b/:id/:slug: the board's swimlanes and lists.
  if (Request.Method = 'GET') and (Copy(Request.PathInfo, 1, 3) = '/b/') and (Request.CookieFields.Values[LOGIN_COOKIE] <> '') then
  begin
    P := PathParts(Request.PathInfo);
    if (Length(P) = 3) and (P[2] = 'places') and ResolveTenant(Request, T) and TenantOpen(T) and Html5User(T.Db, Request, S) then
    begin
      Result := True;
      if PlacesJson(T.Db, S.UserId, P[1], Content) then SendJsonAnswer(Response, 200, Content)
      else SendJsonAnswer(Response, 403, '{"error":"Board access forbidden"}');
    end;
    // addMemberPopup's search: GET /b/:id/members/search?q=, for a board admin.
    if (Length(P) = 4) and (P[2] = 'members') and (P[3] = 'search') and ResolveTenant(Request, T) and TenantOpen(T) and
      Html5User(T.Db, Request, S) then
    begin
      Result := True;
      if MemberSearchJson(T.Db, S.UserId, P[1], Request.QueryFields.Values['q'], Content) then SendJsonAnswer(Response, 200, Content)
      else SendJsonAnswer(Response, 404, '{"error":"not found"}');
    end;
    Exit;
  end;
  if Request.Method <> 'POST' then Exit;
  if (Request.ContentFields.Values['sessionId'] <> '') or (Request.QueryFields.Values['sessionId'] <> '') then Exit;
  Path := Request.PathInfo;
  // Admin Panel / People's forms: /admin/people/:id/edit (editUserPopup) and
  // /admin/people/:id (the table's Admin and Active), back to People.
  if Copy(Path, 1, 14) = '/admin/people/' then
  begin
    P := PathParts(Path);
    n := Length(P);
    if not (((n = 3) or ((n = 4) and (P[3] = 'edit'))) and (P[2] <> '')) then Exit;
    if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
    if not Html5User(T.Db, Request, S) then Exit;
    Result := True;
    Code := AdminUpdateViewUser(T, S.UserId, P[2], Request.ContentFields, n = 3, Error);
    if Code = 404 then
    begin
      Response.Code := 404;
      Response.Content := 'not found';
      Response.SendContent;
      Exit;
    end;
    Response.Code := 303;
    if Code = 200 then Response.SetCustomHeader('Location', '/admin/people')
    else Response.SetCustomHeader('Location', '/admin/people?error=' + HTTPEncode(Error));
    Response.SendContent;
    Exit;
  end;
  if Copy(Path, 1, 10) = '/_methods/' then
  begin
    Result := True;
    // weddy.js encodes the name (encodeURIComponent): a collection's own
    // method such as /checklists/remove arrives as %2Fchecklists%2Fremove.
    ServeMethod(Request, Response, HTTPDecode(Copy(Path, 11, MaxInt)));
    Exit;
  end;
  // The HTML5 view's forms (board.pug, _cardsec_*.pug), all under /b/:id/cards:
  //   /b/:id/cards                                    add a card
  //   /b/:id/cards/:card/title                        rename it
  //   /b/:id/cards/:card/checklists                   add a checklist
  //   /b/:id/cards/:card/checklists/:cl/items         add an item to it
  //   /b/:id/cards/:card/checklists/:cl/items/:it/toggle   check or uncheck the item
  //   /b/:id/cards/:card/checklists/:cl/delete        delete the checklist and its items
  //   /b/:id/cards/:card/comments                     comment on the card
  //   /b/:id/cards/:card/people                       its Requested By or Assigned By
  //   /b/:id/cards/:card/description                  its description
  //   /b/:id/cards/:card/members/:user                a board member on or off it
  //   /b/:id/cards/:card/labels/:label                one of the board's labels on or off it
  //   /b/:id/labels                                   a new board label (card= to return to)
  //   /b/:id/swimlanes                                a swimlane below (or above) after=
  //   /b/:id/custom-fields                            a new custom field of the board (card= to return to)
  //   /b/:id/title                                    the board renamed, by its admin (a page form: answered 303)
  //   /b/:id/archive/restore                          an archived card, list or swimlane back (kind=, id=)
  //   /b/:id/cards/:card/dates/:kind                  its received, start, due or end date (delete=1 clears)
  //   /b/:id/cards/:card/custom-fields/:field         a custom field's value
  //   /b/:id/cards/:card/custom-fields/:field/toggle  the field onto the card or off it
  //   /b/:id/cards/:card/attachments                  a file onto the card (multipart, "file")
  //   /b/:id/cards/:card/move-to                      another list or swimlane of its board
  //   /b/:id/cards/:card/copy-to                      a copy, here or on another board
  //   /b/:id/cards/:card/archive                      archived
  //   /b/:id/cards/:card/attachments/:att/delete      the attachment off it
  //   /b/:id/cards/:card/vote                         vote=positive|negative (cards.vote)
  //   /b/:id/cards/:card/poker                        state=one|two|...|unsure (cards.pokerVote)
  //   /b/:id/cards/:card/watch                        the user watching the card, or not (watch)
  //   /b/:id/watch?level=watching|tracking|muted      the user's level on the board (watch)
  // Each is also the shape of a WeKan route (/b/:id/:slug/...), so only a
  // POST of this view, signed in by the cookie, is taken as one of these.
  P := PathParts(Path);
  n := Length(P);
  if (n < 3) or (P[0] <> 'b') or (P[1] = '') or
    not ((P[2] = 'cards') or ((P[2] = 'archive') and (n = 4) and (P[3] = 'restore')) or ((P[2] = 'title') and (n = 3)) or ((P[2] = 'watch') and (n = 3)) or ((P[2] = 'members') and ((n = 3) or ((n = 5) and (P[4] = 'remove')))) or (((P[2] = 'lists') or (P[2] = 'labels') or (P[2] = 'swimlanes') or (P[2] = 'custom-fields')) and (n = 3))) then Exit;
  BoardId := P[1]; CardId := ''; ChecklistId := ''; ItemId := '';
  Title := Request.ContentFields.Values['title'];
  if (n = 3) and (P[2] = 'lists') then Action := 'add-list'
  else if (n = 3) and (P[2] = 'labels') then Action := 'add-label'
  else if (n = 3) and (P[2] = 'title') then Action := 'rename-board'
  else if (n = 4) and (P[2] = 'archive') then Action := 'restore'
  else if (n = 3) and (P[2] = 'swimlanes') then Action := 'add-swimlane'
  else if (n = 3) and (P[2] = 'custom-fields') then Action := 'add-custom-field'
  else if (n = 3) and (P[2] = 'watch') then Action := 'watch-board'
  else if (n = 3) and (P[2] = 'members') then Action := 'add-member'
  else if (n = 5) and (P[2] = 'members') then Action := 'remove-member'
  else if n = 3 then Action := 'add-card'
  else if (n = 5) and (P[4] = 'title') then Action := 'rename-card'
  else if (n = 5) and (P[4] = 'checklists') then Action := 'add-checklist'
  else if (n = 5) and (P[4] = 'comments') then Action := 'add-comment'
  else if (n = 5) and (P[4] = 'people') then Action := 'set-person'
  else if (n = 5) and (P[4] = 'description') then Action := 'set-description'
  else if (n = 6) and (P[4] = 'members') then Action := 'toggle-member'
  else if (n = 6) and (P[4] = 'labels') then Action := 'toggle-label'
  else if (n = 6) and (P[4] = 'dates') then Action := 'set-date'
  else if (n = 6) and (P[4] = 'custom-fields') then Action := 'set-field'
  else if (n = 5) and (P[4] = 'attachments') then Action := 'add-attachment'
  else if (n = 5) and (P[4] = 'move-to') then Action := 'move-card'
  else if (n = 5) and (P[4] = 'copy-to') then Action := 'copy-card'
  else if (n = 5) and (P[4] = 'archive') then Action := 'archive-card'
  else if (n = 5) and (P[4] = 'vote') then Action := 'vote'
  else if (n = 5) and (P[4] = 'poker') then Action := 'poker'
  else if (n = 5) and (P[4] = 'watch') then Action := 'watch-card'
  else if (n = 7) and (P[4] = 'attachments') and (P[6] = 'delete') then Action := 'delete-attachment'
  else if (n = 7) and (P[4] = 'attachments') and (P[6] = 'cover') then Action := 'attachment-cover'
  else if (n = 7) and (P[4] = 'attachments') and (P[6] = 'background') then Action := 'attachment-background'
  else if (n = 7) and (P[4] = 'custom-fields') and (P[6] = 'toggle') then Action := 'toggle-field'
  else if (n = 7) and (P[4] = 'checklists') and (P[6] = 'items') then Action := 'add-item'
  else if (n = 7) and (P[4] = 'checklists') and (P[6] = 'delete') then Action := 'delete-checklist'
  else if (n = 9) and (P[4] = 'checklists') and (P[6] = 'items') and (P[8] = 'toggle') then Action := 'toggle-item'
  else Exit;
  if (n >= 4) and (P[2] = 'cards') then CardId := P[3];
  if n >= 6 then ChecklistId := P[5];
  if n >= 8 then ItemId := P[7];
  if (CardId = '') and (n >= 4) and (P[2] = 'cards') then Exit;
  if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
  if not Html5User(T.Db, Request, S) then Exit;
  Result := True;
  if Action = 'add-list' then
    Code := CreateViewList(T, S.UserId, BoardId, Request.ContentFields.Values['swimlaneId'], '', Title, NewId, Error)
  else if Action = 'add-card' then
    Code := CreateViewCard(T, S.UserId, BoardId, Request.ContentFields.Values['listId'],
      Request.ContentFields.Values['swimlaneId'], Title, Request.ContentFields.Values['position'], NewId, Error)
  else if Action = 'rename-card' then
    Code := RenameViewCard(T, S.UserId, BoardId, CardId, Title, Error)
  else if Action = 'set-person' then
    Code := SetViewCardPerson(T, S.UserId, BoardId, CardId, Request.ContentFields.Values['field'],
      Request.ContentFields.Values['value'], Error)
  else if Action = 'set-description' then
    Code := SetViewCardDescription(T, S.UserId, BoardId, CardId, Request.ContentFields.Values['description'], Error)
  else if Action = 'rename-board' then
    Code := RenameBoard(T, S.UserId, BoardId, Title, Error)
  else if Action = 'restore' then
    Code := RestoreViewItem(T, S.UserId, BoardId, Request.ContentFields.Values['kind'], Request.ContentFields.Values['id'], Error)
  else if Action = 'add-custom-field' then
  begin
    Code := CreateViewCustomField(T, S.UserId, BoardId, Request.ContentFields.Values['name'],
      Request.ContentFields.Values['type'], NewId, Error);
    // Opened from a card: back to it, open.
    CardId := Request.ContentFields.Values['card'];
    if (CardId <> '') and (Length(T.Db.Query('SELECT 1 FROM cards WHERE id=' + QuotedStr(CardId) + ' AND boardId=' +
      QuotedStr(BoardId) + ' AND deletedAt IS NULL;')) <> 1) then CardId := '';
  end
  else if Action = 'add-swimlane' then
    Code := CreateViewSwimlane(T, S.UserId, BoardId, Request.ContentFields.Values['after'],
      Request.ContentFields.Values['placement'] = 'above', Title, NewId, Error)
  else if Action = 'add-label' then
  begin
    Code := CreateViewLabel(T, S.UserId, BoardId, Request.ContentFields.Values['name'],
      Request.ContentFields.Values['color'], NewId, Error);
    // createLabelPopup was opened from a card: back to it, open.
    CardId := Request.ContentFields.Values['card'];
    if (CardId <> '') and (Length(T.Db.Query('SELECT 1 FROM cards WHERE id=' + QuotedStr(CardId) + ' AND boardId=' +
      QuotedStr(BoardId) + ' AND deletedAt IS NULL;')) <> 1) then CardId := '';
  end
  else if Action = 'move-card' then
    Code := MoveViewCard(T, S.UserId, BoardId, CardId, Request.ContentFields.Values['boardId'],
      Request.ContentFields.Values['swimlaneId'], Request.ContentFields.Values['listId'], Error)
  else if Action = 'copy-card' then
    Code := CopyViewCard(T, S.UserId, BoardId, CardId, Request.ContentFields.Values['boardId'],
      Request.ContentFields.Values['swimlaneId'], Request.ContentFields.Values['listId'], Title, NewId, Error)
  else if Action = 'archive-card' then
  begin
    Code := ArchiveViewCard(T, S.UserId, BoardId, CardId, Error);
    // The archived card is no longer on the board: the board without it.
    if Code = 200 then CardId := '';
  end
  else if (Action = 'add-member') or (Action = 'remove-member') then
  begin
    PlainMemberFlags(Columns, Values, Sets);
    if Action = 'add-member' then
      Code := ChangeBoardMembership(T, S.UserId, BoardId, Request.ContentFields.Values['userId'], True, Columns, Values, Sets, Error)
    else
      Code := ChangeBoardMembership(T, S.UserId, BoardId, P[3], False, Columns, Values, Sets, Error);
    // Only a board admin changes members; to anybody else the board's
    // membership is not there to change.
    if Code = 403 then Code := 404;
  end
  else if Action = 'watch-card' then
    Code := WatchViewCard(T, S.UserId, BoardId, CardId, Error)
  else if Action = 'watch-board' then
    Code := WatchViewBoard(T, S.UserId, BoardId, Request.QueryFields.Values['level'], Error)
  else if Action = 'poker' then
    Code := PokerViewCard(T, S.UserId, BoardId, CardId, Request.ContentFields.Values['state'], Error)
  else if Action = 'vote' then
    Code := VoteViewCard(T, S.UserId, BoardId, CardId, Request.ContentFields.Values['vote'], Error)
  else if Action = 'add-attachment' then
    Code := AddViewAttachment(T, S.UserId, BoardId, CardId, Request, Error)
  else if Action = 'attachment-cover' then
    Code := SetViewCardCover(T, S.UserId, BoardId, CardId, P[5], Error)
  else if Action = 'attachment-background' then
    Code := SetViewBoardBackground(T, S.UserId, BoardId, CardId, P[5], Error)
  else if Action = 'delete-attachment' then
    Code := DeleteViewAttachment(T, S.UserId, BoardId, CardId, P[5], Error)
  else if (Action = 'set-field') or (Action = 'toggle-field') then
    Code := SetViewCardField(T, S.UserId, BoardId, CardId, P[5], Request.ContentFields, Action = 'toggle-field', Error)
  else if Action = 'set-date' then
    Code := SetViewCardDate(T, S.UserId, BoardId, CardId, P[5], Request.ContentFields.Values['at'],
      Request.ContentFields.Values['delete'] = '1', Error)
  else if Action = 'toggle-label' then
    Code := ToggleViewCardLabel(T, S.UserId, BoardId, CardId, P[5], Error)
  else if Action = 'toggle-member' then
    Code := ToggleViewCardMember(T, S.UserId, BoardId, CardId, P[5], Error)
  else if Action = 'add-comment' then
    Code := AddViewComment(T, S.UserId, BoardId, CardId, Request.ContentFields.Values['comment'], NewId, Error)
  else if Action = 'add-checklist' then
    Code := CreateViewChecklist(T, S.UserId, BoardId, CardId, Title, NewId, Error)
  else if Action = 'add-item' then
    Code := AddViewChecklistItem(T, S.UserId, BoardId, CardId, ChecklistId, Title, NewId, Error)
  else if Action = 'toggle-item' then
    Code := ToggleViewChecklistItem(T, S.UserId, BoardId, CardId, ChecklistId, ItemId, Error)
  else
    Code := DeleteViewChecklist(T, S.UserId, BoardId, CardId, ChecklistId, Error);
  Language := ViewerLanguage(T.Db, S, Request);
  Words := TWLTranslator.Create(Language);
  try
    if Code <> 200 then
    begin
      SendPage(Response, Code, Page(Request, Language, Words, S, Error, '',
        '<div class="big-message quiet"><h1>' + E(Error) + '</h1></div>'));
      Exit;
    end;
    // boardChangeTitlePopup is a plain form: back to the board, renamed.
    if Action = 'rename-board' then
    begin
      Response.Code := 303;
      Response.SetCustomHeader('Location', BoardRoute(BoardId, BoardSlug(T.Db, BoardId)));
      Response.SendContent;
      Exit;
    end;
    // The board again - with the card open when the action was on a card -
    // for Unpoly to take its .board-wrapper.
    Content := '';
    Found := False;
    if T.Db.BeginRead then
    try
      Content := BoardContent(T.Db, S, Words, BoardId, CardId, BoardTitle, Found);
    finally
      T.Db.EndRead;
    end;
    if CardId <> '' then Back := CardRoute(BoardId, BoardSlug(T.Db, BoardId), CardId)
    else Back := BoardRoute(BoardId, BoardSlug(T.Db, BoardId));
    Response.SetCustomHeader('X-Up-Location', Back);
    SendPage(Response, 200, Page(Request, Language, Words, S, BoardTitle, BoardTitle, Content,
      BoardQuickAccess(T.Db, Words, S, BoardId, BoardTitle)));
  finally
    Words.Free;
  end;
end;

function ServeHtml5(Request: TRequest; Response: TResponse): Boolean;
var T: TWLTenant; S: TWLSession; Language: TWLLanguage; Words: TWLTranslator;
  Path, Title, BoardTitle, Content, Section: string; Found, SignedIn: Boolean;
  procedure Send(Code: Integer; const Html: string);
  begin
    Response.Code := Code;
    Response.ContentType := 'text/html; charset=utf-8';
    Response.SetCustomHeader('Cache-Control', 'no-store');
    Response.Content := Html;
    Response.ContentLength := Length(Response.Content);
    Response.SendContent;
  end;
begin
  Result := False;
  if Request.Method <> 'GET' then Exit;
  Path := Request.PathInfo;
  // weddy.js's refreshUser: GET /api/user, same-origin, with the login cookie
  // and no bearer token - the signed-in user, read only. Every other /api/
  // route keeps the REST API's bearer token.
  // weddy.js's look at its session every few seconds: 401 once it is gone.
  if Path = '/_session' then
  begin
    if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
    Result := True;
    if Html5User(T.Db, Request, S) then SendJsonAnswer(Response, 200, '{}')
    else SendJsonAnswer(Response, 401, '{"error":"Unauthorized"}');
    Exit;
  end;
  if (Path = '/api/user') and (Request.Authorization = '') and (Request.CookieFields.Values[LOGIN_COOKIE] <> '') then
  begin
    if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
    Result := True;
    if not Html5User(T.Db, Request, S) then
    begin SendJsonAnswer(Response, 401, '{"error":"Unauthorized"}'); Exit; end;
    SendJsonAnswer(Response, 200, UserJson(T.Db, S.UserId));
    Exit;
  end;
  if Copy(Path, 1, 25) = '/cdn/storage/attachments/' then
  begin
    Result := ServeAttachmentFile(Request, Response, Path);
    Exit;
  end;
  // The root arrives as an empty PathInfo.
  if Path = '' then Path := '/';
  if not ((Path = '/') or (Path = '/sign-in') or (Path = '/board') or (Path = '/board/card') or
    (Path = '/allboards') or (Copy(Path, 1, 11) = '/allboards/') or (Path = '/people') or (Path = '/admin/people')) then Exit;
  // A session in the URL is the HTML4 view's: that page keeps its own view.
  if Request.QueryFields.Values['sessionId'] <> '' then Exit;
  if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
  Result := True;
  SignedIn := Html5User(T.Db, Request, S);
  Language := ViewerLanguage(T.Db, S, Request);
  Words := TWLTranslator.Create(Language);
  try
    if Path = '/sign-in' then
    begin
      Send(200, Page(Request, Language, Words, Default(TWLSession), Words.Text('log-in', 'Log In'), '',
        SignInContent(Words, '', '')));
      Exit;
    end;
    if not SignedIn then
    begin
      Response.Code := 302;
      Response.SetCustomHeader('Location', '/sign-in');
      Response.SendContent;
      Exit;
    end;
    if (Path = '/people') or (Path = '/admin/people') then
    begin
      if not IsSiteAdmin(T.Db, S.UserId) then
        Send(404, Page(Request, Language, Words, S, Words.Text('error-notAuthorized', 'You are not authorized to view this page.'), '',
          '<div class="big-message quiet"><h1>' + E(Words.Text('error-notAuthorized', 'You are not authorized to view this page.')) + '</h1></div>'))
      else
        Send(200, Page(Request, Language, Words, S, Words.Text('people', 'People'), '',
          PeopleContent(T.Db, S, Words, Request.QueryFields.Values['error'])));
      Exit;
    end;
    if (Path = '/') or (Path = '/allboards') or (Copy(Path, 1, 11) = '/allboards/') then
    begin
      Section := Copy(Path, 12, MaxInt);
      if Pos('/', Section) > 0 then Section := Copy(Section, 1, Pos('/', Section) - 1);
      Send(200, Page(Request, Language, Words, S, Words.Text('all-boards', 'All Boards'), '',
        BoardsContent(T.Db, S, Words, Section)));
      Exit;
    end;
    Content := '';
    Found := False;
    if T.Db.BeginRead then
    try
      Content := BoardContent(T.Db, S, Words, Request.QueryFields.Values['id'],
        IfThen(Path = '/board/card', Request.QueryFields.Values['card'], ''), BoardTitle, Found, Request.QueryFields);
    finally
      T.Db.EndRead;
    end;
    if not Found then
    begin
      Send(404, Page(Request, Language, Words, S, Words.Text('board-not-found', 'Board not found'), '', NotFoundContent(Words)));
      Exit;
    end;
    Title := BoardTitle;
    Send(200, Page(Request, Language, Words, S, Title, BoardTitle, Content,
      BoardQuickAccess(T.Db, Words, S, Request.QueryFields.Values['id'], BoardTitle)));
  finally
    Words.Free;
  end;
end;

procedure Html5SignInFailed(Request: TRequest; Response: TResponse; const Username: string);
var Language: TWLLanguage; Words: TWLTranslator;
begin
  Language := ViewerLanguage(nil, Default(TWLSession), Request);
  Words := TWLTranslator.Create(Language);
  try
    SendPage(Response, 403, Page(Request, Language, Words, Default(TWLSession), Words.Text('log-in', 'Log In'), '',
      SignInContent(Words, Words.Text('error-ldap-login', 'An error occurred while trying to login'), Username)));
  finally
    Words.Free;
  end;
end;

end.
