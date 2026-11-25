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
  wlview, wlselscp, wlrevoke, wlapi;

const
  STATIC_HEAD =
    '<link rel="stylesheet" href="/static/unpoly.css">' +
    '<link rel="stylesheet" href="/static/wekan.css">' +
    '<link rel="stylesheet" href="/static/welite.css">' +
    '<script src="/static/unpoly.js"></script>' +
    '<script src="/static/interact.js"></script>' +
    '<script src="/static/weddy.js"></script>';

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

// layout.pug: the document, its head, and the header bar.
function Page(Request: TRequest; const Language: TWLLanguage; Words: TWLTranslator;
  const S: TWLSession; const Title, BoardTitle, Content: string): string;
var Dir, Header: string;
begin
  if Language.Rtl then Dir := 'rtl' else Dir := 'ltr';
  Header := '';
  if S.UserId <> '' then
  begin
    Header := '<div id="header" class="header-bar">' +
      '<a class="header-all-boards js-all-boards" href="/" up-follow>' + E(Words.Text('all-boards', 'All Boards')) + '</a>';
    if BoardTitle <> '' then
      Header := Header + '<div id="header-quick-access" class="nodragscroll"><span class="header-page-title" role="heading" aria-level="1" title="' +
        HtmlAttr(BoardTitle) + '">' + E(BoardTitle) + '</span></div>';
    Header := Header +
      Html5ViewToggle(PathAndQuery(Request), Words.Text('html4-html5-toggle', 'Toggle between HTML4 and HTML5 view')) +
      '<a class="header-user js-open-header-member-menu" href="/">' + E(S.Username) + '</a>' +
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
    '<div class="password-input-container"><input id="at-field-password" class="password-field" type="password" name="password" autocomplete="current-password" required></div>' +
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
  if (Sec <> 'starred') and (Sec <> 'remaining') then Sec := 'starred';
  StarredIds := StarredSet;
  try
    R := Db.Query('SELECT id,title,color,slug FROM boards WHERE archived=0 ORDER BY sort,id;');
    Starred := 0; Remaining := 0; Items := '';
    for i := 0 to High(R) do
      if BoardCanRead(Db, S.UserId, R[i][0]) then
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
function BoardContent(Db: TWLDb; const S: TWLSession; Words: TWLTranslator; const BoardId, CardId: string;
  out BoardTitle: string; out Found: Boolean): string;
var B, Lanes, Lists, Cards, Card: TWLRows; i, j, k: Integer; Route, Canvas, Details, Composer: string;
  Selector: TSelectionScope; Writable, Maximized: Boolean;
begin
  Result := ''; BoardTitle := ''; Found := False;
  if (BoardId = '') or (Pos(#0, BoardId + CardId) > 0) then Exit;
  if not BoardCanRead(Db, S.UserId, BoardId) then Exit;
  B := Db.Query('SELECT title,color,slug FROM boards WHERE id=' + QuotedStr(BoardId) + ' AND archived=0 LIMIT 1;');
  if Length(B) <> 1 then Exit;
  BoardTitle := B[0][0];
  Route := BoardRoute(BoardId, B[0][2]);
  Writable := (S.UserId <> '') and BoardCanWrite(Db, S.UserId, BoardId);
  Canvas := '';
  Lanes := Db.Query('SELECT id,title,color FROM swimlanes WHERE boardId=' + QuotedStr(BoardId) +
    ' AND archived=0 ORDER BY sort,id;');
  for i := 0 to High(Lanes) do
  begin
    Canvas := Canvas + '<div class="swimlane js-swimlane" id="swimlane-' + HtmlAttr(Lanes[i][0]) + '" data-swimlane="' +
      HtmlAttr(Lanes[i][0]) + '"><div class="swimlane-header js-swimlane-header" data-swimlane="' + HtmlAttr(Lanes[i][0]) +
      '"><span class="swimlane-header-name title">' + E(Lanes[i][1]) + '</span></div><div class="list-group js-lists">';
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
          '" aria-label="' + HtmlAttr(Words.Text('listActionPopup-title', 'List Actions')) + '">&#9776;</a>';
      Canvas := Canvas + '<div class="list js-list" id="js-list-' + HtmlAttr(Lists[j][0]) + '" data-list="' +
        HtmlAttr(Lists[j][0]) + '" data-swimlane="' + HtmlAttr(Lanes[i][0]) + '"><div class="list-header">' +
        '<span class="list-header-name">' + E(Lists[j][1]) + '</span>' + Composer + '</div>' +
        '<div class="list-body js-minicards" data-list="' + HtmlAttr(Lists[j][0]) + '" data-swimlane="' + HtmlAttr(Lanes[i][0]) + '">';
      Cards := Db.Query('SELECT c.id,c.title,c.sort FROM cards c WHERE c.boardId=' + QuotedStr(BoardId) +
        ' AND c.swimlaneId=' + QuotedStr(Lanes[i][0]) + ' AND c.listId=' + QuotedStr(Lists[j][0]) +
        ' AND c.archived=0 AND c.deletedAt IS NULL ORDER BY c.sort,c.id;');
      for k := 0 to High(Cards) do
        // A block that opens the card, as Weddy's and WeKan's minicard.
        Canvas := Canvas + '<div class="minicard-wrapper js-minicard" up-href="' +
          HtmlAttr(CardRoute(BoardId, B[0][2], Cards[k][0])) + '" up-follow up-clickable up-target=".board-wrapper" data-card="' +
          HtmlAttr(Cards[k][0]) + '" data-card-id="' + HtmlAttr(Cards[k][0]) + '" data-sort="' + HtmlAttr(Cards[k][2]) +
          '"><div class="minicard"><div class="minicard-title"><span class="minicard-title-text">' +
          E(Cards[k][1]) + '</span></div></div></div>';
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
    Canvas := Canvas + '</div></div>';
  end;
  Details := '';
  if CardId <> '' then
  begin
    Selector := TSelectionScope.Create(Db);
    try
      Card := Db.Query('SELECT title,description FROM cards WHERE id=' + QuotedStr(CardId) + ' AND boardId=' +
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
      '<span class="card-details-title-edit-zone js-open-inlined-form">' + E(Card[0][0]) + '</span></h2>';
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
    Details := Details +
      '<a class="js-close-card-details" href="' + HtmlAttr(Route) + '" aria-label="' + HtmlAttr(Words.Text('close', 'Close')) +
      '" up-follow up-target=".board-wrapper">&times;</a></div>';
    if Card[0][1] <> '' then
      Details := Details + '<div class="card-details-item card-details-item-description"><div class="viewer">' +
        E(Card[0][1]) + '</div></div>';
    Details := Details + ChecklistsSection(Db, Words, BoardId, CardId, Writable) + '</div>';
    if Writable then Details := Details + ChecklistPopups(Words, BoardId, CardId);
  end;
  // board.pug's list menu, drawn once; weddy.js opens it for the list whose
  // menu button was clicked.
  if Writable then
    Details := Details + '<template class="js-pop-over-template" data-pop="list-menu" data-title="' +
      HtmlAttr(Words.Text('listActionPopup-title', 'List Actions')) + '"><ul class="pop-over-list">' +
      '<li><a class="js-add-card list-header-plus-top" href="#">&uarr; ' +
      E(Words.Text('add-card-to-top-of-list', 'Add card to top of list')) + '</a></li>' +
      '<li><a class="js-add-card list-header-plus-bottom" href="#">&darr; ' +
      E(Words.Text('add-card-to-bottom-of-list', 'Add card to bottom of list')) + '</a></li></ul></template>';
  Result := '<div class="board-wrapper board-color-' + HtmlAttr(B[0][1]) + '" data-board="' + HtmlAttr(BoardId) + '">' +
    '<div class="board-header"><h1 class="header-board-name js-board-title">' + E(BoardTitle) + '</h1></div>' +
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
var T: TWLTenant; S: TWLSession; Args: TJSONData; Selector: TJSONObject; Id, Error: string; R: TWLRows; Code: Integer;
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

function ServeHtml5Action(Request: TRequest; Response: TResponse): Boolean;
var T: TWLTenant; S: TWLSession; Language: TWLLanguage; Words: TWLTranslator;
  Path, BoardId, CardId, ChecklistId, ItemId, NewId, Action, Error, Content, BoardTitle, Title, Back: string;
  P: TStringArray; Code, n: Integer; Found: Boolean;
begin
  Result := False;
  if Request.Method <> 'POST' then Exit;
  if (Request.ContentFields.Values['sessionId'] <> '') or (Request.QueryFields.Values['sessionId'] <> '') then Exit;
  Path := Request.PathInfo;
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
  // Each is also the shape of a WeKan route (/b/:id/:slug/...), so only a
  // POST of this view, signed in by the cookie, is taken as one of these.
  P := PathParts(Path);
  n := Length(P);
  if (n < 3) or (P[0] <> 'b') or (P[2] <> 'cards') or (P[1] = '') then Exit;
  BoardId := P[1]; CardId := ''; ChecklistId := ''; ItemId := '';
  Title := Request.ContentFields.Values['title'];
  if n = 3 then Action := 'add-card'
  else if (n = 5) and (P[4] = 'title') then Action := 'rename-card'
  else if (n = 5) and (P[4] = 'checklists') then Action := 'add-checklist'
  else if (n = 7) and (P[4] = 'checklists') and (P[6] = 'items') then Action := 'add-item'
  else if (n = 7) and (P[4] = 'checklists') and (P[6] = 'delete') then Action := 'delete-checklist'
  else if (n = 9) and (P[4] = 'checklists') and (P[6] = 'items') and (P[8] = 'toggle') then Action := 'toggle-item'
  else Exit;
  if n >= 4 then CardId := P[3];
  if n >= 6 then ChecklistId := P[5];
  if n >= 8 then ItemId := P[7];
  if (CardId = '') and (n >= 4) then Exit;
  if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
  if not Html5User(T.Db, Request, S) then Exit;
  Result := True;
  if Action = 'add-card' then
    Code := CreateViewCard(T, S.UserId, BoardId, Request.ContentFields.Values['listId'],
      Request.ContentFields.Values['swimlaneId'], Title, Request.ContentFields.Values['position'], NewId, Error)
  else if Action = 'rename-card' then
    Code := RenameViewCard(T, S.UserId, BoardId, CardId, Title, Error)
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
    SendPage(Response, 200, Page(Request, Language, Words, S, BoardTitle, BoardTitle, Content));
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
  // The root arrives as an empty PathInfo.
  if Path = '' then Path := '/';
  if not ((Path = '/') or (Path = '/sign-in') or (Path = '/board') or (Path = '/board/card') or
    (Path = '/allboards') or (Copy(Path, 1, 11) = '/allboards/')) then Exit;
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
        IfThen(Path = '/board/card', Request.QueryFields.Values['card'], ''), BoardTitle, Found);
    finally
      T.Db.EndRead;
    end;
    if not Found then
    begin
      Send(404, Page(Request, Language, Words, S, Words.Text('board-not-found', 'Board not found'), '', NotFoundContent(Words)));
      Exit;
    end;
    Title := BoardTitle;
    Send(200, Page(Request, Language, Words, S, Title, BoardTitle, Content));
  finally
    Words.Free;
  end;
end;

end.
