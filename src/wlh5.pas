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

// The Filter sidebar's Advanced Filter over a board's cards: the ids of the
// cards it selects; False when the filter does not parse. wlrules' advanced
// filter trigger reads a card with it.
function AdvancedFilterCards(Db: TWLDb; const BoardId, Filter: string; out Ids: TStringArray): Boolean;

// After a successful sign-in in the HTML5 view: the login cookie, and back to
// All Boards.
procedure Html5SignedIn(Response: TResponse; const SessionId: string);

// A sign-in refused in the HTML5 view: the sign-in form again, with WeKan's
// error and the username that was typed.
procedure Html5SignInFailed(Request: TRequest; Response: TResponse; const Username: string);

// The HTML5 view's sign-up form (Weddy's signup.pug), with an error by its
// translation key when there is one, and what was typed.
procedure Html5SignUpPage(Request: TRequest; Response: TResponse; Code: Integer; const ErrorKey, Fallback, Username, Email: string);

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

// A request starts with no board's date format or board of its own: a
// thread's earlier request leaves none behind.
procedure ResetViewState;

implementation

uses
  StrUtils, fpjson, wltenant, wlhtml, wli18n, wllocale, wlaccess, wlroutes,
  wlview, wlselscp, wlrevoke, wlapi, wlferr, wlstore, wlmd, wlshared, wlpasswd, wlattemp, DateUtils, wlflag, wladvf, wlsvg, wlrules, fphttpserver, ssockets, wlcfpol, wlprob, wlavatar, wldatef, wlcardst;

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

// allowIsBoardAdmin: an admin of the board's own (WeKan's Boards allow rule).
function BoardOwnAdmin(Db: TWLDb; const UserId, BoardId: string): Boolean;
begin
  Result := (UserId <> '') and (BoardId <> '') and (Pos(#0, BoardId) = 0) and
    (Length(Db.Query('SELECT 1 FROM board_members WHERE boardId=' + QuotedStr(BoardId) + ' AND userId=' + QuotedStr(UserId) +
      ' AND isActive=1 AND isAdmin=1;')) > 0);
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
  SendResponse(Response);
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
  SendResponse(Response);
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

// The login cookie, cleared.
procedure Html5ClearLoginCookie(Response: TResponse);
var C: TCookie;
begin
  C := Response.Cookies.Add;
  C.Name := LOGIN_COOKIE;
  C.Value := '';
  C.Path := '/';
  C.HttpOnly := True;
  C.SameSite := ssLax;
  C.Expires := EncodeDate(1970, 1, 2);
end;

procedure Html5LogoutEndpoint(Request: TRequest; Response: TResponse);
var T: TWLTenant; S: TWLSession; Token: string;
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
  Html5ClearLoginCookie(Response);
  Response.Code := 302;
  Response.SetCustomHeader('Location', '/sign-in');
  Response.SetCustomHeader('Cache-Control', 'no-store');
  SendResponse(Response);
end;

function PathAndQuery(Request: TRequest): string;
begin
  Result := Request.URI;
  if Result = '' then Result := Request.PathInfo;
end;

// WeKan's editProfilePopup (Weddy's layout.pug): the full name and initials,
// the username and the address editable when Admin Panel allows changing
// them - for a site admin always.
function EditProfilePopup(Db: TWLDb; Words: TWLTranslator; const UserId: string): string;
var R: TWLRows; Admin, Names, Mails: Boolean;
begin
  Result := '';
  R := Db.Query('SELECT u.username,COALESCE(CASE WHEN json_valid(u.profile_json) THEN json_extract(u.profile_json,''$.fullname'') END,''''),' +
    'COALESCE(CASE WHEN json_valid(u.profile_json) THEN json_extract(u.profile_json,''$.initials'') END,''''),' +
    'COALESCE((SELECT address FROM user_emails e WHERE e.userId=u.id LIMIT 1),'''') FROM users u WHERE u.id=' + QuotedStr(UserId) + ';');
  if Length(R) <> 1 then Exit;
  Admin := IsSiteAdmin(Db, UserId);
  Names := Admin or AccountSettingOn(Db, 'accounts-allowUserNameChange');
  Mails := Admin or AccountSettingOn(Db, 'accounts-allowEmailChange');
  Result := '<template class="js-pop-over-template" data-pop="edit-profile" data-title="' + HtmlAttr(Words.Text('editProfilePopup-title', 'Edit Profile')) +
    '"><form class="js-edit-profile-form" method="post" action="/profile"><label>' + E(Words.Text('fullname', 'Full Name')) +
    '<textarea class="js-profile-fullname" name="fullname" rows="2">' + E(R[0][1]) + '</textarea></label><label>' +
    E(Words.Text('username', 'Username')) + '<input class="js-profile-username" type="text" ' + IfThen(Names, 'name="username" ', '') +
    'value="' + HtmlAttr(R[0][0]) + '"' + IfThen(Names, '', ' readonly') + '></label><label>' + E(Words.Text('initials', 'Initials')) +
    '<input class="js-profile-initials" type="text" name="initials" maxlength="8" value="' + HtmlAttr(R[0][2]) + '"></label><label>' +
    E(Words.Text('email', 'Email')) + '<input class="js-profile-email" type="email" ' + IfThen(Mails, 'name="email" ', '') + 'value="' +
    HtmlAttr(R[0][3]) + '"' + IfThen(Mails, '', ' readonly') + '></label><div class="buttonsContainer"><input class="primary wide" type="submit" value="' +
    HtmlAttr(Words.Text('save', 'Save')) + '"></div></form></template>';
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
// WeKan's changeLanguagePopup (userHeader.jade): every language, by its
// name, each with its language's flag, its region's flag and name, and (RTL)
// for one written right to left; the language now checked. Sent when the
// member menu's Change Language is opened, not on every page.
function LanguagePopup(Words: TWLTranslator; const Current: TWLLanguage): string;
var i, j: Integer; L: TWLLanguage; Order: array of TWLLanguage; Flag, Country, Name, Region, Dir: string;
begin
  SetLength(Order, LanguageCount);
  for i := 0 to LanguageCount - 1 do Order[i] := LanguageAt(i);
  // By name, as WeKan sorts them; a tag breaks a tie, for a stable order.
  for i := 1 to High(Order) do
  begin
    L := Order[i]; j := i - 1;
    while (j >= 0) and ((CompareStr(Order[j].Name, L.Name) > 0) or
      ((Order[j].Name = L.Name) and (CompareStr(Order[j].Tag, L.Tag) > 0))) do
    begin
      Order[j + 1] := Order[j]; Dec(j);
    end;
    Order[j + 1] := L;
  end;
  Dir := IfThen(Current.Rtl, 'rtl', 'ltr');
  Result := '<template class="js-pop-over-template" data-pop="change-language" data-popup="changeLanguagePopup" data-title="' +
    E(Words.Text('changeLanguagePopup-title', 'Change Language')) + '"><div class="header"><span class="header-title">' +
    E(Words.Text('changeLanguagePopup-title', 'Change Language')) + '</span><a class="close-btn js-close-pop-over" href="#" aria-label="' +
    E(Words.Text('close', 'Close')) + '">&times;</a></div><div class="content"><ul class="pop-over-list">';
  for i := 0 to High(Order) do
  begin
    L := Order[i];
    LanguageFlags(L.Tag, Flag, Country);
    LanguageLabelParts(L.Name, Country, Name, Region);
    Result := Result + '<li' + IfThen(L.Tag = Current.Tag, ' class="active"', '') + '><a class="js-set-language" href="#" dir="' + Dir +
      '" data-language="' + E(L.Tag) + '"><span class="language-label"><span class="language-main-line">' +
      '<span class="emoji-icon language-flags" dir="ltr" aria-hidden="true">' + Flag + '</span><bdi class="language-name">' + E(Name) +
      '</bdi>' + IfThen(L.Rtl, '<span class="language-rtl" dir="ltr">(RTL)</span>', '') + '</span>';
    if Country <> '' then
      Result := Result + '<span class="language-region">(<span class="emoji-icon language-country-flag" dir="ltr" aria-hidden="true">' +
        Country + '</span>' + IfThen(Region <> '', '&nbsp;<bdi>' + E(Region) + '</bdi>', '') + ')</span>';
    Result := Result + '</span>' + IfThen(L.Tag = Current.Tag, '<i class="fa fa-check"></i>', '') + '</a></li>';
  end;
  Result := Result + '</ul></div></template>';
end;

// Member Settings' Change Password (WeKan's changePasswordPopup, with
// AccountsTemplates' fields as Weddy's profile.pug has them): the password
// now, the new one twice, within the password policy's minimum.
function ChangePasswordContent(Db: TWLDb; Words: TWLTranslator; const ErrorKey: string): string;
var MinLength: Integer; Enforce: Boolean; Shown: string;
begin
  PasswordPolicy(Db, MinLength, Enforce);
  Shown := '';
  if ErrorKey = 'error-password-policy' then
    Shown := StringReplace(Words.Text('password-too-short', 'The password must be at least __min__ characters long.'),
      '__min__', IntToStr(MinLength), [rfReplaceAll])
  else if ErrorKey = 'password-mismatch' then Shown := Words.Text('password-mismatch', 'Passwords do not match')
  else if ErrorKey = 'login-refused-bad-password' then Shown := Words.Text('login-refused-bad-password', 'Wrong password')
  else if ErrorKey = 'login-refused-braked' then Shown := Words.Text('login-refused-braked', 'Too many failed attempts')
  else if ErrorKey <> '' then Shown := Words.Text('error-undefined', 'Something went wrong');
  Result := '<div class="setting-content profile"><h2>' + E(Words.Text('changePasswordPopup-title', 'Change Password')) + '</h2>' +
    IfThen(Shown <> '', '<p class="at-error js-profile-error">' + E(Shown) + '</p>', '') +
    '<form class="js-password-form at-form" method="post" action="/profile/password">' +
    '<label for="at-field-current_password">' + E(Words.Text('password', 'Password')) + '</label>' +
    '<input id="at-field-current_password" type="password" name="oldPassword" autocomplete="current-password" required>' +
    '<label for="at-field-password">' + E(Words.Text('change-password', 'Change password')) + '</label>' +
    '<input id="at-field-password" type="password" name="newPassword" autocomplete="new-password"' +
    IfThen(Enforce, ' minlength="' + IntToStr(MinLength) + '"', '') + ' required>' +
    '<label for="at-field-password_again">' + E(Words.Text('password-again', 'Password (again)')) + '</label>' +
    '<input id="at-field-password_again" type="password" name="newPassword2" autocomplete="new-password"' +
    IfThen(Enforce, ' minlength="' + IntToStr(MinLength) + '"', '') + ' required>' +
    '<button id="at-btn" class="at-btn primary" type="submit">' + E(Words.Text('change-password', 'Change password')) + '</button>' +
    '</form></div>';
end;

// Every language tag the view has, space-separated, for welite.js to
// choose among the browser's own as WeKan's matchBrowserLanguage does.
function LanguageTags: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to LanguageCount - 1 do
  begin
    if Result <> '' then Result := Result + ' ';
    Result := Result + LanguageAt(i).Tag;
  end;
end;

// WeKan's notificationsDrawer, as Weddy's notifications_drawer.go: the
// activity types whose act-* sentence a notification shows.
const
  DRAWER_SENTENCES: array[0..53] of string = (
    'createCard', 'moveCard', 'archivedCard', 'restoredCard', 'addComment', 'joinMember', 'unjoinMember',
    'joinAssignee', 'unjoinAssignee', 'addChecklist', 'addAttachment', 'createList', 'createSwimlane', 'createBoard',
    'addedLabel', 'removedLabel', 'addBoardMember', 'removeBoardMember', 'deleteCard', 'checkedItem', 'uncheckedItem',
    'addChecklistItem', 'addLabel', 'addSubtask', 'archivedBoard', 'archivedList', 'archivedSwimlane',
    'changedBoardTitle', 'changedListTitle', 'changedSwimlaneTitle', 'completeChecklist', 'createCustomField',
    'deleteAttachment', 'deleteBoard', 'deleteComment', 'deleteCustomField', 'editCard', 'editComment',
    'importBoard', 'importCard', 'importList', 'moveCardBoard', 'moveCardToOtherBoard', 'removeBoard',
    'removeChecklist', 'removeChecklistItem', 'removedChecklistItem', 'removeLabel', 'removeList', 'removeSwimlane',
    'restoredList', 'restoredSwimlane', 'setCustomField', 'uncompleteChecklist');
  // The names an act-* sentence may hold, in the order DrawerItems reads them.
  DRAWER_PARAMS: array[0..14] of string = ('board', 'user', 'card', 'list', 'swimlane', 'oldList', 'oldSwimlane',
    'oldBoard', 'checklist', 'checklistItem', 'attachment', 'comment', 'customField', 'customFieldValue', 'label');

// WeKan's renderNotificationItem: the board, the actor, then the sentence
// with each name in bold and quoted - the card's a link to it - and a name
// that is not there left out. Everything but the markup is escaped.
function ClearNotificationItem(const Sentence: string; const Params: array of string; const CardUrl: string): string;
var i, j, k: Integer; Body, Key, Value, Head: string; Escaped: string;
begin
  Escaped := E(Sentence); Body := ''; i := 1;
  while i <= Length(Escaped) do
  begin
    if (Copy(Escaped, i, 2) = '__') then
    begin
      j := i + 2;
      while (j <= Length(Escaped)) and (Escaped[j] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) and (Copy(Escaped, j, 2) <> '__') do Inc(j);
      if (j > i + 2) and (Copy(Escaped, j, 2) = '__') then
      begin
        Key := Copy(Escaped, i + 2, j - i - 2); Value := '';
        for k := 0 to High(DRAWER_PARAMS) do
          if (DRAWER_PARAMS[k] = Key) and (k <= High(Params)) then Value := Params[k];
        if Value <> '' then
        begin
          if (Key = 'card') and (CardUrl <> '') then
            Body := Body + '<b><a href="' + E(CardUrl) + '">' + E('"' + Value + '"') + '</a></b>'
          else Body := Body + '<b>' + E('"' + Value + '"') + '</b>';
        end;
        i := j + 2; Continue;
      end;
    end;
    Body := Body + Escaped[i]; Inc(i);
  end;
  Head := '';
  if Params[0] <> '' then Head := Head + '<b>' + E(Params[0]) + '</b>: ';
  if Params[1] <> '' then Head := Head + '<b>' + E(Params[1]) + '</b> ';
  Result := '<div class="wekan-notification-item">' + Head + Trim(Body) + '</div>';
end;

// WeKan's trayDeliveryFor(boardId).grouping: the member's tray setting, else
// the board's, else Admin Panel's, else none.
function TrayGrouping(Db: TWLDb; const UserId, BoardId: string): string;
var R: TWLRows;
  function Valid(const G: string): Boolean;
  begin
    Result := (G = 'none') or (G = 'card') or (G = 'board');
  end;
begin
  R := Db.Query('SELECT COALESCE(CASE WHEN json_valid(profile_json) THEN json_extract(profile_json,''$.notificationDelivery.tray.grouping'') END,'''') ' +
    'FROM users WHERE id=' + QuotedStr(UserId) + ';');
  if (Length(R) = 1) and Valid(R[0][0]) then Exit(R[0][0]);
  if BoardId <> '' then
  begin
    R := Db.Query('SELECT COALESCE(CASE WHEN json_valid(settings_json) THEN json_extract(settings_json,''$.notificationDelivery.tray.grouping'') END,'''') ' +
      'FROM boards WHERE id=' + QuotedStr(BoardId) + ';');
    if (Length(R) = 1) and Valid(R[0][0]) then Exit(R[0][0]);
  end;
  Result := SharedSettingText(Db, 'notificationDelivery.tray.grouping');
  if not Valid(Result) then Result := 'none';
end;

threadvar
  // The date format of the page being drawn (wldatef): set where a board's
  // page starts, '' (YYYY-MM-DD) elsewhere.
  ViewDateFormat: string;
  // The board whose page is being drawn, for the member menu's Date.
  ViewBoardId: string;
  // The order of the minicard's pieces and of the card's dates on this
  // board (Card Settings' panes, wlcardst).
  ViewMinicardPieces, ViewCardDates: TStringArray;
  // The Archive's answer to the restore just made (#6772): the card whose
  // list was full - its "restore to another list" opened at once - and how
  // many cards Restore all left out.
  ViewRestoreBlocked: string;
  ViewRestoreSkipped: Integer;

// WeKan's resolveDateFormat for this viewer on this board: the member's own
// format while their override is on, the board's, Admin Panel's.
function ViewDateFor(Db: TWLDb; const UserId, BoardId: string): string;
var U, B: TWLRows; Member, Board: string; MemberOn, BoardOn: Boolean;
begin
  Member := ''; Board := ''; MemberOn := False; BoardOn := False;
  if UserId <> '' then
  begin
    U := Db.Query('SELECT COALESCE(CASE WHEN json_valid(profile_json) THEN json_extract(profile_json,''$.dateFormat'') END,''''),' +
      'CASE WHEN json_valid(profile_json) AND json_type(profile_json,''$.dateFormatOverride'')=''true'' THEN 1 ELSE 0 END ' +
      'FROM users WHERE id=' + QuotedStr(UserId) + ' LIMIT 1;');
    if Length(U) = 1 then begin Member := U[0][0]; MemberOn := U[0][1] = '1'; end;
  end;
  if BoardId <> '' then
  begin
    B := Db.Query('SELECT COALESCE(CASE WHEN json_valid(settings_json) THEN json_extract(settings_json,''$.dateFormat'') END,''''),' +
      'CASE WHEN json_valid(settings_json) AND json_type(settings_json,''$.dateFormatOverride'')=''true'' THEN 1 ELSE 0 END ' +
      'FROM boards WHERE id=' + QuotedStr(BoardId) + ' LIMIT 1;');
    if Length(B) = 1 then begin Board := B[0][0]; BoardOn := B[0][1] = '1'; end;
  end;
  Result := ResolveDateFormat(Member, MemberOn, Board, BoardOn, SharedSettingText(Db, 'globalDateFormat'),
    SharedSettingOn(Db, 'hideDateFormat'));
end;

// The drawer's rows: the user's notifications, newest first, at most 100, of
// boards the user may still read (a board left keeps none of its activity
// here), an entry scheduled for later (#5171 showAt) not before its time;
// and - #5171, when the tray grouping says so - one card's or one board's
// entries in one row, its first shown until the row is opened.
function DrawerItems(Db: TWLDb; Words: TWLTranslator; const UserId: string): string;
type TItem = record Html, Read, Activity, Shown, Board, Card, BoardTitle, CardTitle, Key: string; end;
var R: TWLRows; i, j, k, n, Count: Integer; Items: array of TItem; Params: array of string;
  Sentence, CardUrl, Grouping, Key, Label_: string; Known: Boolean; Keys: TStringList;
  function Data(const Field: string): string;
  begin
    Result := 'CASE WHEN json_valid(a.data_json) THEN json_extract(a.data_json,''$.' + Field + ''') END';
  end;
  function Title(const Table, IdSql: string): string;
  begin
    Result := 'COALESCE((SELECT title FROM ' + Table + ' WHERE id=' + IdSql + '),'''')';
  end;
begin
  Result := '';
  R := Db.Query('SELECT json_extract(n.value,''$.activity''),CASE WHEN json_extract(n.value,''$.read'') IS NULL THEN 0 ELSE 1 END,' +
    'a.activityType,COALESCE(a.boardId,''''),COALESCE(a.cardId,''''),COALESCE(a.createdAt,''''),' +
    Title('boards', 'a.boardId') + ',COALESCE((SELECT slug FROM boards WHERE id=a.boardId),''''),' +
    'COALESCE((SELECT COALESCE(NULLIF(CASE WHEN json_valid(x.profile_json) THEN json_extract(x.profile_json,''$.fullname'') END,''''),x.username) FROM users x WHERE x.id=a.userId),''''),' +
    'COALESCE(NULLIF(' + Data('cardTitle') + ',''''),(SELECT title FROM cards WHERE id=a.cardId),''''),' +
    Title('lists', 'a.listId') + ',' + Title('swimlanes', 'a.swimlaneId') + ',' +
    Title('lists', Data('oldListId')) + ',' + Title('swimlanes', Data('oldSwimlaneId')) + ',' + Title('boards', Data('oldBoardId')) + ',' +
    Title('checklists', Data('checklistId')) + ',' + Title('checklist_items', Data('checklistItemId')) + ',' +
    'COALESCE(' + Data('attachmentName') + ',''''),' +
    'COALESCE((SELECT text FROM card_comments WHERE id=' + Data('commentId') + '),''''),' +
    'COALESCE((SELECT name FROM custom_fields WHERE id=' + Data('customFieldId') + '),''''),' +
    // #3141: an admin-only field's value reaches only board admins.
    'CASE WHEN COALESCE((SELECT adminOnly FROM custom_fields WHERE id=' + Data('customFieldId') + '),0)=0 OR EXISTS(SELECT 1 FROM board_members m ' +
    'WHERE m.boardId=a.boardId AND m.userId=' + QuotedStr(UserId) + ' AND m.isAdmin=1) THEN COALESCE(CAST(' + Data('value') + ' AS TEXT),'''') ELSE '''' END,' +
    'COALESCE((SELECT COALESCE(NULLIF(l.name,''''),l.color) FROM board_labels l WHERE l.boardId=a.boardId AND l.id=' + Data('labelId') + '),'''') ' +
    'FROM users u, json_each(CASE WHEN json_valid(u.profile_json) AND json_type(u.profile_json,''$.notifications'')=''array'' ' +
    'THEN json_extract(u.profile_json,''$.notifications'') ELSE ''[]'' END) n ' +
    'JOIN activities a ON a.id=json_extract(n.value,''$.activity'') ' +
    'WHERE u.id=' + QuotedStr(UserId) + ' AND (COALESCE(json_type(n.value,''$.showAt''),'''') NOT IN (''integer'',''real'') OR ' +
    'json_extract(n.value,''$.showAt'')<=CAST((julianday(''now'')-2440587.5)*86400000 AS INTEGER)) ' +
    'ORDER BY n.key DESC LIMIT 500;');
  SetLength(Items, 0);
  for i := 0 to High(R) do
  begin
    if Length(Items) >= 100 then Break;
    if (R[i][3] <> '') and not BoardCanRead(Db, UserId, R[i][3]) then Continue;
    SetLength(Params, Length(DRAWER_PARAMS));
    Params[0] := R[i][6]; Params[1] := R[i][8];
    Params[2] := IfThen(R[i][4] <> '', R[i][9], '');
    for k := 3 to 14 do Params[k] := R[i][k + 7];
    CardUrl := '';
    if (R[i][3] <> '') and (R[i][4] <> '') then
      CardUrl := '/b/' + HTTPEncode(R[i][3]) + '/' + HTTPEncode(R[i][7]) + '/' + HTTPEncode(R[i][4]);
    Known := False;
    for k := 0 to High(DRAWER_SENTENCES) do
      if DRAWER_SENTENCES[k] = R[i][2] then Known := True;
    Sentence := '';
    if Known then Sentence := Words.Text('act-' + R[i][2], '');
    n := Length(Items); SetLength(Items, n + 1);
    if Sentence <> '' then Items[n].Html := ClearNotificationItem(Sentence, Params, CardUrl)
    // An activity with no sentence of its own shows its type, as WeKan's.
    else Items[n].Html := E(R[i][2]);
    Items[n].Read := R[i][1]; Items[n].Activity := R[i][0];
    Items[n].Shown := FormatShownDate(R[i][5], ViewDateFormat);
    Items[n].Board := R[i][3]; Items[n].Card := R[i][4];
    Items[n].BoardTitle := R[i][6]; Items[n].CardTitle := R[i][9];
  end;
  // WeKan's groupEntries: the grouping key of each entry, by its board's grouping.
  Keys := TStringList.Create;
  try
    for i := 0 to High(Items) do
    begin
      Grouping := TrayGrouping(Db, UserId, Items[i].Board);
      if (Grouping = 'card') and (Items[i].Card <> '') then Items[i].Key := 'card:' + Items[i].Card
      else if (Grouping = 'card') or (Grouping = 'board') then Items[i].Key := 'board:' + Items[i].Board
      else Items[i].Key := 'single:' + IntToStr(i);
      if Keys.IndexOf(Items[i].Key) < 0 then Keys.Add(Items[i].Key);
    end;
    for j := 0 to Keys.Count - 1 do
    begin
      Key := Keys[j]; Count := 0;
      for i := 0 to High(Items) do if Items[i].Key = Key then Inc(Count);
      Label_ := '';
      if Count > 1 then
      begin
        for i := 0 to High(Items) do
          if Items[i].Key = Key then
          begin
            if Copy(Key, 1, 5) = 'card:' then
              Label_ := StringReplace(StringReplace(Words.Text('notification-group-card', '__count__ notifications on card __card__'),
                '__count__', IntToStr(Count), [rfReplaceAll]), '__card__', Items[i].CardTitle, [rfReplaceAll])
            else
              Label_ := StringReplace(StringReplace(Words.Text('notification-group-board', '__count__ notifications on board __board__'),
                '__count__', IntToStr(Count), [rfReplaceAll]), '__board__', Items[i].BoardTitle, [rfReplaceAll]);
            Break;
          end;
        Result := Result + '<li class="notification-group" data-key="' + E(Key) + '"><a class="js-toggle-notification-group" href="#" ' +
          'data-key="' + E(Key) + '" aria-expanded="false">&#9656; ' + E(Label_) + '</a></li>';
      end;
      n := 0;
      for i := 0 to High(Items) do
        if Items[i].Key = Key then
        begin
          Result := Result + '<li class="notification' + IfThen(Items[i].Read = '1', ' is-read', '') +
            IfThen((Count > 1) and (n > 0), ' is-group-rest', '') + '" data-activity="' + E(Items[i].Activity) +
            '" data-group="' + IfThen(Count > 1, E(Key), '') + '"><div class="notification-clear-item">' + Items[i].Html +
            '</div><div class="notification-date"><small class="quiet">' + E(Items[i].Shown) + '</small></div></li>';
          Inc(n);
        end;
    end;
  finally
    Keys.Free;
  end;
end;

// The user's own profile field Key (a plain name) set to a JSON value, or
// removed with JsonValue ''.
function SetProfileField(Db: TWLDb; const UserId, Key, JsonValue: string): Boolean;
var Profile: string;
begin
  Profile := 'CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END';
  if JsonValue = '' then
    Result := Db.Exec('UPDATE users SET profile_json=json_remove(' + Profile + ',''$.' + Key + ''') WHERE id=' + QuotedStr(UserId) + ';')
  else
    Result := Db.Exec('UPDATE users SET profile_json=json_set(' + Profile + ',''$.' + Key + ''',json(' + QuotedStr(JsonValue) +
      ')) WHERE id=' + QuotedStr(UserId) + ';');
end;

// The profile field Key as SQLite gives it ('' when missing).
function ProfileField(Db: TWLDb; const UserId, Key: string): string;
var R: TWLRows;
begin
  R := Db.Query('SELECT COALESCE(CASE WHEN json_valid(profile_json) THEN json_extract(profile_json,''$.' + Key + ''') END,'''') ' +
    'FROM users WHERE id=' + QuotedStr(UserId) + ' LIMIT 1;');
  if Length(R) = 1 then Result := R[0][0] else Result := '';
end;

const
  // dateFormatSettings.js weekDays: Sunday first, as profile.startDayOfWeek counts.
  WEEKDAY_KEYS: array[0..6] of string = ('sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday');
  // WeKan's imports/lib/calendarSystems.js CALENDAR_SYSTEM_IDS.
  CALENDAR_SYSTEMS: array[0..17] of string = ('gregorian', 'jalali', 'buddhist', 'chinese', 'coptic', 'dangi',
    'ethioaa', 'ethiopic', 'hebrew', 'indian', 'islamic', 'islamic-civil', 'islamic-rgsa', 'islamic-tbla',
    'islamic-umalqura', 'iso8601', 'japanese', 'roc');
  // Member Settings / Change Settings (userHeader.jade changeSettingsPopup):
  // each toggle's method, its profile field, and whether it is shown unless
  // turned off (hideFocusOutline stores the hiding).
  SETTING_TOGGLES: array[0..7] of array[0..1] of string = (
    ('toggleKeepTitleTags', 'keepTitleTags'), ('toggleHideFocusOutline', 'hideFocusOutline'),
    ('toggleKeepAddCardFormOpen', 'keepAddCardFormOpen'), ('toggleTitleBracketLabel', 'titleBracketLabel'),
    ('toggleSubmitOnEnter', 'submitOnEnter'), ('toggleOpenManyCardsAtOnce', 'openManyCardsAtOnce'),
    ('toggleChecklistDingSound', 'checklistDingSound'), ('toggleShowWeekOfYear', 'showWeekOfYear'));

function KnownCalendar(const Id: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(CALENDAR_SYSTEMS) do if CALENDAR_SYSTEMS[i] = Id then Exit(True);
  Result := False;
end;

// The member's date and display preferences, as WeKan's server/models/users.js
// and boards.js answer them: 200, or a Meteor error's code and reason.
function PreferenceMethod(const T: TWLTenant; const UserId, Name: string; Args: TJSONArray; out Error: string): Integer;
var i: Integer; Flag: Boolean; R: TWLRows;
  function Str(k: Integer): Boolean;
  begin Result := (Args.Count > k) and (Args.Items[k].JSONType = jtString); end;
  function Bool(k: Integer): Boolean;
  begin Result := (Args.Count > k) and (Args.Items[k].JSONType = jtBoolean); end;
begin
  Error := 'Match failed';
  Result := 400;
  if Name = 'changeDateFormat' then
  begin
    // [format, override = true]: one of WeKan's six formats.
    if not Str(0) or ((Args.Count > 1) and not Bool(1)) or (Args.Count > 2) then Exit;
    if not ValidDateFormat(Args.Strings[0]) then begin Error := 'invalid-date-format'; Exit; end;
    Flag := (Args.Count < 2) or Args.Booleans[1];
    if not (SetProfileField(T.Db, UserId, 'dateFormat', '"' + Args.Strings[0] + '"') and
      SetProfileField(T.Db, UserId, 'dateFormatOverride', IfThen(Flag, 'true', 'false'))) then begin Error := 'Could not save'; Exit(500); end;
  end
  else if Name = 'changeStartDayOfWeek' then
  begin
    if (Args.Count <> 1) or (Args.Items[0].JSONType <> jtNumber) or (Frac(Args.Items[0].AsFloat) <> 0) or
      (Args.Items[0].AsFloat < 0) or (Args.Items[0].AsFloat > 6) then Exit;
    if not SetProfileField(T.Db, UserId, 'startDayOfWeek', IntToStr(Round(Args.Items[0].AsFloat))) then begin Error := 'Could not save'; Exit(500); end;
  end
  else if Name = 'changeCalendarSystem' then
  begin
    if (Args.Count <> 1) or not Str(0) then Exit;
    if not KnownCalendar(Args.Strings[0]) then begin Error := 'invalid-calendar-system'; Exit; end;
    if not SetProfileField(T.Db, UserId, 'calendarSystem', '"' + Args.Strings[0] + '"') then begin Error := 'Could not save'; Exit(500); end;
  end
  else if Name = 'setBoardDateFormat' then
  begin
    // server/models/boards.js: [boardId, format, override], for a board admin.
    if (Args.Count <> 3) or not Str(0) or not Str(1) or not Bool(2) then Exit;
    // allowIsBoardAdmin: an admin of this board's own, not the site admin.
    if (Pos(#0, Args.Strings[0]) > 0) or (Length(T.Db.Query('SELECT 1 FROM board_members WHERE boardId=' + QuotedStr(Args.Strings[0]) +
      ' AND userId=' + QuotedStr(UserId) + ' AND isActive=1 AND isAdmin=1;')) = 0) then
    begin
      // Board Settings / Date is offered to the board's admins only.
      if Length(T.Db.Query('SELECT 1 FROM boards WHERE id=' + QuotedStr(Args.Strings[0]) + ';')) = 1 then
        try
          RecordSecurityEvent(T.Db, UserId, 'AuthBleed', 'method:setBoardDateFormat', 'authz', 'high', 'CWE-862', 'blocked',
            'Board date format change refused: not an admin of the board');
        except
          // logging must never break the guard
        end;
      Error := 'not-authorized'; Exit(403);
    end;
    if not ValidDateFormat(Args.Strings[1]) then begin Error := 'invalid-date-format'; Exit; end;
    if not T.Db.Exec('UPDATE boards SET settings_json=json_set(CASE WHEN json_valid(settings_json) THEN settings_json ELSE ''{}'' END,' +
      '''$.dateFormat'',' + QuotedStr(Args.Strings[1]) + ',''$.dateFormatOverride'',json(''' + IfThen(Args.Booleans[2], 'true', 'false') +
      ''')),modifiedAt=' + QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', LocalTimeToUniversal(Now))) + ' WHERE id=' + QuotedStr(Args.Strings[0]) + ';') then begin Error := 'Could not save'; Exit(500); end;
  end
  else if Name = 'toggleDesktopDragHandles' then
  begin
    // [show]: shown or hidden as asked, else the other way round.
    if (Args.Count > 1) or ((Args.Count = 1) and not Bool(0) and (Args.Items[0].JSONType <> jtNull)) then Exit;
    if (Args.Count = 1) and Bool(0) then Flag := Args.Booleans[0]
    else Flag := ProfileField(T.Db, UserId, 'showDesktopDragHandles') <> '1';
    if not SetProfileField(T.Db, UserId, 'showDesktopDragHandles', IfThen(Flag, 'true', 'false')) then begin Error := 'Could not save'; Exit(500); end;
  end
  else if Name = 'setCardCollapsed' then
  begin
    // [value]: the user's own fold of the card's details.
    if (Args.Count <> 1) or not Bool(0) then Exit;
    if not SetProfileField(T.Db, UserId, 'cardCollapsed', IfThen(Args.Booleans[0], 'true', 'false')) then begin Error := 'Could not save'; Exit(500); end;
  end
  else if Name = 'toggleUnreadChanges' then
  begin
    // On records since when, so cards never opened are not all marked.
    if Args.Count <> 0 then Exit;
    if ProfileField(T.Db, UserId, 'unreadChangesSince') <> '' then Flag := SetProfileField(T.Db, UserId, 'unreadChangesSince', '')
    else Flag := SetProfileField(T.Db, UserId, 'unreadChangesSince',
      '"' + FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', LocalTimeToUniversal(Now)) + '"');
    if not Flag then begin Error := 'Could not save'; Exit(500); end;
  end
  else
  begin
    if Args.Count <> 0 then Exit;
    Error := 'Method not found';
    for i := 0 to High(SETTING_TOGGLES) do
      if SETTING_TOGGLES[i][0] = Name then
      begin
        R := nil;
        Flag := ProfileField(T.Db, UserId, SETTING_TOGGLES[i][1]) <> '1';
        if not SetProfileField(T.Db, UserId, SETTING_TOGGLES[i][1], IfThen(Flag, 'true', 'false')) then begin Error := 'Could not save'; Exit(500); end;
        Error := '';
        Exit(200);
      end;
    Exit(404);
  end;
  Error := '';
  Result := 200;
end;

// The methods PreferenceMethod answers.
function IsPreferenceMethod(const Name: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(SETTING_TOGGLES) do if SETTING_TOGGLES[i][0] = Name then Exit(True);
  Result := (Name = 'changeDateFormat') or (Name = 'changeStartDayOfWeek') or (Name = 'changeCalendarSystem') or
    (Name = 'setBoardDateFormat') or (Name = 'toggleDesktopDragHandles') or (Name = 'toggleUnreadChanges') or
    (Name = 'setCardCollapsed');
end;

// dateFormatSettings.js formatLabel: a format's name, and " · Time" unless it
// is date-only; an unknown one is the first.
function DateFormatLabel(Words: TWLTranslator; const Format: string): string;
var F: string;
begin
  F := Format;
  if not ValidDateFormat(F) then F := DATE_FORMATS[0];
  if Copy(F, Length(F) - 9, 10) = '-date-only' then
    Result := Words.Text('date-format-' + LowerCase(Copy(F, 1, Length(F) - 10)), Copy(F, 1, Length(F) - 10))
  else
    Result := Words.Text('date-format-' + LowerCase(F), F) + ' '#$C2#$B7' ' + Words.Text('time', 'Time');
end;

// dateFormatSettings.jade dateFormatEditor: Admin Panel's format and the
// board's as they stand, then the form for this scope - the board's (Board
// Settings / Date), or the member's with the first day of the week and the
// calendar (Member Settings / Date).
function DateFormatEditor(Db: TWLDb; Words: TWLTranslator; const UserId, BoardId: string; Member: Boolean): string;
var R: TWLRows; Format, Day, Calendar: string; Enabled: Boolean; i: Integer;
  function Status(const Cls, Heading: string; On_: Boolean; const F: string): string;
  begin
    Result := '<div class="' + Cls + '"><strong>' + E(Heading) + '</strong><p><span>' +
      E(IfThen(On_, Words.Text('r-rule-enabled', 'Enabled'), Words.Text('r-rule-disabled', 'Disabled'))) + '</span>: ' +
      E(DateFormatLabel(Words, F)) + '</p></div>';
  end;
  function Opt(const Value, Name: string; Selected: Boolean): string;
  begin
    Result := '<option value="' + HtmlAttr(Value) + '"' + IfThen(Selected, ' selected', '') + '>' + E(Name) + '</option>';
  end;
begin
  Format := ''; Enabled := False; Day := '1'; Calendar := 'gregorian';
  if Member then
    R := Db.Query('SELECT COALESCE(json_extract(p,''$.dateFormat''),''''),CASE WHEN json_type(p,''$.dateFormatOverride'')=''true'' THEN 1 ELSE 0 END,' +
      'COALESCE(json_extract(p,''$.startDayOfWeek''),1),COALESCE(json_extract(p,''$.calendarSystem''),''gregorian'') ' +
      'FROM (SELECT CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END p FROM users WHERE id=' + QuotedStr(UserId) + ' LIMIT 1);')
  else
    R := Db.Query('SELECT COALESCE(json_extract(p,''$.dateFormat''),''''),CASE WHEN json_type(p,''$.dateFormatOverride'')=''true'' THEN 1 ELSE 0 END,1,''gregorian'' ' +
      'FROM (SELECT CASE WHEN json_valid(settings_json) THEN settings_json ELSE ''{}'' END p FROM boards WHERE id=' + QuotedStr(BoardId) + ' LIMIT 1);');
  if Length(R) = 1 then
  begin
    Format := R[0][0]; Enabled := R[0][1] = '1'; Day := R[0][2]; Calendar := R[0][3];
  end;
  if not ValidDateFormat(Format) then Format := DATE_FORMATS[0];
  if not KnownCalendar(Calendar) then Calendar := 'gregorian';
  Result := '<div class="date-format-inherited">' +
    Status('js-global-date-format-status', Words.Text('date-format-for-everyone', 'Date Format for everyone'),
      SharedSettingOn(Db, 'hideDateFormat'), SharedSettingText(Db, 'globalDateFormat'));
  if Member then
  begin
    // The board's line on a board's page only.
    if BoardId <> '' then
    begin
      R := Db.Query('SELECT COALESCE(json_extract(p,''$.dateFormat''),''''),CASE WHEN json_type(p,''$.dateFormatOverride'')=''true'' THEN 1 ELSE 0 END ' +
        'FROM (SELECT CASE WHEN json_valid(settings_json) THEN settings_json ELSE ''{}'' END p FROM boards WHERE id=' + QuotedStr(BoardId) + ' LIMIT 1);');
      if Length(R) = 1 then
        Result := Result + Status('js-board-date-format-status', Words.Text('board', 'Board') + ': ' + Words.Text('date-format', 'Date Format'),
          R[0][1] = '1', R[0][0]);
    end;
  end
  else Result := Result + '<hr>';
  Result := Result + '</div><form class="js-date-format-form"' + IfThen(Member, '', ' data-board="' + HtmlAttr(BoardId) + '"') + '>';
  if Member then
    Result := Result + '<strong class="js-member-date-format-heading">' + E(Words.Text('memberMenuPopup-title', 'Member Settings')) + ': ' +
      E(Words.Text('date-format', 'Date Format')) + '</strong>';
  Result := Result + '<label class="flex"><input class="js-date-format-override" type="checkbox"' + IfThen(Enabled, ' checked', '') + '>';
  if Member then
    Result := Result + '<span class="js-member-date-format-enabled" data-enabled="' + HtmlAttr(Words.Text('r-rule-enabled', 'Enabled')) +
      '" data-disabled="' + HtmlAttr(Words.Text('r-rule-disabled', 'Disabled')) + '">' +
      E(IfThen(Enabled, Words.Text('r-rule-enabled', 'Enabled'), Words.Text('r-rule-disabled', 'Disabled'))) + '</span>'
  else
    Result := Result + E(Words.Text('date-format', 'Date Format'));
  Result := Result + '</label><select class="js-date-format-select" aria-label="' + HtmlAttr(Words.Text('date-format', 'Date Format')) + '">';
  for i := 0 to High(DATE_FORMATS) do Result := Result + Opt(DATE_FORMATS[i], DateFormatLabel(Words, DATE_FORMATS[i]), DATE_FORMATS[i] = Format);
  Result := Result + '</select>';
  if Member then
  begin
    Result := Result + '<hr><label class="bold clear" for="start-day-of-week"><i class="fa fa-calendar"></i> ' +
      E(Words.Text('start-day-of-week', 'Set day of the week start')) + '</label><select id="start-day-of-week">';
    for i := 0 to 6 do
      Result := Result + Opt(IntToStr(i), Words.Text(WEEKDAY_KEYS[i], WEEKDAY_KEYS[i]), IntToStr(i) = Day);
    Result := Result + '</select><hr><label class="bold clear" for="calendar-system"><i class="fa fa-calendar-check-o"></i> ' +
      E(Words.Text('calendar-system', 'Calendar system (date display)')) + '</label><select id="calendar-system">';
    for i := 0 to High(CALENDAR_SYSTEMS) do
      Result := Result + Opt(CALENDAR_SYSTEMS[i], Words.Text('calendar-system-' + CALENDAR_SYSTEMS[i], CALENDAR_SYSTEMS[i]),
        CALENDAR_SYSTEMS[i] = Calendar);
    Result := Result + '</select>';
  end;
  Result := Result + '<p class="error js-date-format-error" hidden></p><button class="primary" type="submit">' +
    E(Words.Text('save', 'Save')) + '</button></form>';
end;

// boardDateSettingsPopup: the board's date format, and the week of the year
// (the member's own) under it.
function BoardDateSettingsPopup(Db: TWLDb; Words: TWLTranslator; const UserId, BoardId: string): string;
begin
  Result := '<template class="js-pop-over-template" data-pop="board-date-settings" data-popup="boardDateSettingsPopup" data-title="' + HtmlAttr(Words.Text('date', 'Date')) + '">' +
    '<div class="content">' + DateFormatEditor(Db, Words, UserId, BoardId, False) +
    '<hr><ul class="show-week-of-year-toggle"><a class="flex js-show-week-of-year-toggle" href="#" title="' +
    HtmlAttr(Words.Text('show-week-of-year', 'Show week of year (ISO 8601)')) + '"><i class="fa ' +
    IfThen(ProfileField(Db, UserId, 'showWeekOfYear') = '1', 'fa-check', 'fa-square-o') + '"></i><span>' +
    E(Words.Text('show-week-of-year', 'Show week of year (ISO 8601)')) + '</span></a></ul></div></template>';
end;

// The member menu's Date and Change Settings pop-overs (memberDateSettingsPopup,
// changeSettingsPopup): each row of Change Settings a toggle, its check mark
// while on.
function MemberSettingsPopups(Db: TWLDb; Words: TWLTranslator; const UserId, BoardId: string): string;
type TRow = record Cls, Icon, Key, Fallback, Hint, Method, Field: string; Shown: Boolean; end;
const ROWS: array[0..8] of TRow = (
  (Cls: 'js-toggle-desktop-drag-handles'; Icon: 'fa-arrows'; Key: 'show-desktop-drag-handles'; Fallback: 'Show desktop drag handles'; Hint: ''; Method: 'toggleDesktopDragHandles'; Field: 'showDesktopDragHandles'; Shown: False),
  (Cls: 'js-toggle-unread-changes'; Icon: 'fa-circle'; Key: 'show-unread-changes'; Fallback: 'Mark cards changed since I last opened them'; Hint: 'show-unread-changes-desc'; Method: 'toggleUnreadChanges'; Field: 'unreadChangesSince'; Shown: False),
  (Cls: 'js-toggle-keep-title-tags'; Icon: 'fa-hashtag'; Key: 'keep-title-tags'; Fallback: 'Keep #label and @member in new card titles'; Hint: 'keep-title-tags-description'; Method: 'toggleKeepTitleTags'; Field: 'keepTitleTags'; Shown: False),
  (Cls: 'js-toggle-hide-focus-outline'; Icon: 'fa-square-o'; Key: 'show-focus-outline'; Fallback: 'Show focus outline'; Hint: ''; Method: 'toggleHideFocusOutline'; Field: 'hideFocusOutline'; Shown: True),
  (Cls: 'js-toggle-keep-add-card-form-open'; Icon: 'fa-plus-square'; Key: 'keep-add-card-form-open'; Fallback: 'Keep the Add card form open after adding a card'; Hint: 'keep-add-card-form-open-description'; Method: 'toggleKeepAddCardFormOpen'; Field: 'keepAddCardFormOpen'; Shown: False),
  (Cls: 'js-toggle-title-bracket-label'; Icon: 'fa-tag'; Key: 'title-bracket-label'; Fallback: 'Turn [label] at the start of a new card title into a label'; Hint: 'title-bracket-label-description'; Method: 'toggleTitleBracketLabel'; Field: 'titleBracketLabel'; Shown: False),
  (Cls: 'js-toggle-submit-on-enter'; Icon: 'fa-level-down'; Key: 'submit-on-enter'; Fallback: 'Submit editors with Enter'; Hint: 'submit-on-enter-description'; Method: 'toggleSubmitOnEnter'; Field: 'submitOnEnter'; Shown: False),
  (Cls: 'js-toggle-open-many-cards-at-once'; Icon: 'fa-clone'; Key: 'open-many-cards-at-once'; Fallback: 'Open many cards at once'; Hint: 'open-many-cards-at-once-description'; Method: 'toggleOpenManyCardsAtOnce'; Field: 'openManyCardsAtOnce'; Shown: False),
  (Cls: 'js-toggle-checklist-ding-sound'; Icon: 'fa-bell'; Key: 'checklist-ding-sound'; Fallback: 'Play a sound when a checklist item is completed'; Hint: 'checklist-ding-sound-description'; Method: 'toggleChecklistDingSound'; Field: 'checklistDingSound'; Shown: False));
var i: Integer; Value: string; On_: Boolean; P: TWLRows; Profile: TJSONData; V: TJSONData;
begin
  // The user's profile, read once for every row.
  Profile := nil;
  P := Db.Query('SELECT CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END FROM users WHERE id=' + QuotedStr(UserId) + ' LIMIT 1;');
  if Length(P) = 1 then
    try
      Profile := GetJSON(P[0][0]);
    except
      Profile := nil;
    end;
  try
  Result := '<template class="js-pop-over-template" data-pop="member-date-settings" data-popup="memberDateSettingsPopup" data-title="' +
    HtmlAttr(Words.Text('date-format', 'Date Format')) + '"><div class="content">' +
    DateFormatEditor(Db, Words, UserId, BoardId, True) + '</div></template>' +
    '<template class="js-pop-over-template" data-pop="change-settings" data-popup="changeSettingsPopup" data-title="' +
    HtmlAttr(Words.Text('changeSettingsPopup-title', 'Change Settings')) + '"><div class="content"><ul class="pop-over-list change-settings-list">';
  for i := 0 to High(ROWS) do
  begin
    Value := '';
    if Profile is TJSONObject then
    begin
      V := TJSONObject(Profile).Find(ROWS[i].Field);
      if V <> nil then
        case V.JSONType of
          jtBoolean: Value := IfThen(V.AsBoolean, '1', '0');
          jtString: Value := V.AsString;
          jtNumber: Value := V.AsString;
        end;
    end;
    if ROWS[i].Field = 'unreadChangesSince' then On_ := Value <> ''
    else if ROWS[i].Shown then On_ := Value <> '1'
    else On_ := Value = '1';
    // The submit-on-enter check keeps weddy.js's own class: it toggles it.
    Result := Result + '<li><a class="' + ROWS[i].Cls + IfThen(ROWS[i].Method = 'toggleSubmitOnEnter', '', ' js-welite-setting') +
      '" href="#" data-method="' + ROWS[i].Method + '"' +
      IfThen(ROWS[i].Hint <> '', ' title="' + HtmlAttr(Words.Text(ROWS[i].Hint, '')) + '"', '') + '><i class="fa ' + ROWS[i].Icon + '"></i>' +
      E(Words.Text(ROWS[i].Key, ROWS[i].Fallback)) + '<i class="fa fa-check' +
      IfThen(ROWS[i].Method = 'toggleSubmitOnEnter', ' js-submit-on-enter-check', ' js-setting-check') + '"' +
      IfThen(On_, '', ' hidden') + '></i></a></li>';
  end;
  Result := Result + '</ul><button class="primary js-apply-user-settings" type="button">' + E(Words.Text('apply', 'Apply')) +
    '</button></div></template>';
  finally
    Profile.Free;
  end;
end;

// Admin Panel / Settings / Appearance (settingBody.jade): what the HTML5 view
// has of it - Hide Logo as it stands, and the date format for everyone with
// its own Save (js-visibility-date-save), which writes only those two.
function AppearanceContent(Db: TWLDb; Words: TWLTranslator): string;
var Doc: TJSONData; Id, Format: string; DateOn, Logo: Boolean; i: Integer;
  function Flag(const Name: string): Boolean;
  var V: TJSONData;
  begin
    V := TJSONObject(Doc).Find(Name);
    Result := (V <> nil) and (V.JSONType = jtBoolean) and V.AsBoolean;
  end;
begin
  Id := ''; Format := ''; DateOn := False; Logo := False;
  Doc := nil;
  try
    try
      Doc := GetJSON(SharedFirstDocument(Db, 'settings'));
    except
      Doc := nil;
    end;
    if Doc is TJSONObject then
    begin
      Id := TJSONObject(Doc).Get('_id', '');
      Format := TJSONObject(Doc).Get('globalDateFormat', '');
      DateOn := Flag('hideDateFormat');
      Logo := Flag('hideLogo');
    end;
  finally
    Doc.Free;
  end;
  if not ValidDateFormat(Format) then Format := DATE_FORMATS[0];
  Result := '<div class="setting-content admin-appearance" data-setting="' + HtmlAttr(Id) + '"><h1>' +
    E(Words.Text('admin-panel', 'Admin Panel')) + ': ' + E(Words.Text('layout', 'Layout')) + '</h1><ul class="admin-pane-list">' +
    '<li class="tableVisibilityMode-form"><a class="flex js-toggle-hide-logo" href="#"><div class="materialCheckBox' +
    IfThen(Logo, ' is-checked', '') + '" id="hide-logo"></div><span>' + E(Words.Text('hide-logo', 'Hide Logo')) + '</span></a></li>' +
    '<li class="admin-pane-group-separator"><hr></li><li><h2 class="admin-pane-group-title">' + E(Words.Text('date', 'Date')) + '</h2></li>' +
    '<li class="tableVisibilityMode-form"><a class="flex js-toggle-date-format" href="#"><div class="materialCheckBox' +
    IfThen(DateOn, ' is-checked', '') + '" id="global-date-format-enabled"></div><span>' + E(Words.Text('date-format', 'Date Format')) +
    ':</span></a><select class="wekan-form-control" id="global-date-format" aria-label="' + HtmlAttr(Words.Text('date-format', 'Date Format')) + '">';
  for i := 0 to High(DATE_FORMATS) do
    Result := Result + '<option value="' + DATE_FORMATS[i] + '"' + IfThen(DATE_FORMATS[i] = Format, ' selected', '') + '>' +
      E(DateFormatLabel(Words, DATE_FORMATS[i])) + '</option>';
  Result := Result + '</select></li><li><button class="js-visibility-date-save primary" type="button">' + E(Words.Text('save', 'Save')) +
    '</button></li></ul></div>';
end;

// WeKan's /settings/update for a site admin, as Settings' allow rule lets it
// through: the one settings document by its _id, $set or $unset of the
// fields the HTML5 view's Admin Panel writes - the date format for everyone
// (one of WeKan's six) and whether it is on, and Hide Logo. Anything else is
// refused, nothing written.
function SettingsUpdate(Db: TWLDb; const UserId: string; Args: TJSONArray; out Error: string): Integer;
var Selector, Modifier, Fields: TJSONObject; Part: TJSONData; i, k: Integer; Name, Op: string; Doc: TJSONData;
begin
  Error := 'Match failed';
  Result := 400;
  if not IsSiteAdmin(Db, UserId) then
  begin
    // Nothing on a page sends it for anybody else: an attempt.
    try
      RecordSecurityEvent(Db, UserId, 'AuthBleed', 'method:/settings/update', 'authz', 'high', 'CWE-862', 'blocked',
        'Admin Panel settings change refused: not the site admin');
    except
      // logging must never break the guard
    end;
    Error := 'Access denied'; Exit(403);
  end;
  if (Args.Count <> 2) or not (Args.Items[0] is TJSONObject) or not (Args.Items[1] is TJSONObject) then Exit;
  Selector := TJSONObject(Args.Items[0]); Modifier := TJSONObject(Args.Items[1]);
  if (Selector.Count <> 1) or (Selector.Find('_id') = nil) or (Selector.Find('_id').JSONType <> jtString) or (Modifier.Count = 0) then Exit;
  Doc := nil;
  try
    try
      Doc := GetJSON(SharedFirstDocument(Db, 'settings'));
    except
      Doc := nil;
    end;
    if not (Doc is TJSONObject) or (TJSONObject(Doc).Get('_id', '') <> Selector.Get('_id', '')) then
    begin Error := 'Not found'; Exit(404); end;
  finally
    Doc.Free;
  end;
  Fields := TJSONObject.Create;
  try
    for i := 0 to Modifier.Count - 1 do
    begin
      Op := Modifier.Names[i]; Part := Modifier.Items[i];
      if ((Op <> '$set') and (Op <> '$unset')) or not (Part is TJSONObject) then Exit;
      for k := 0 to TJSONObject(Part).Count - 1 do
      begin
        Name := TJSONObject(Part).Names[k];
        if (Name <> 'hideDateFormat') and (Name <> 'globalDateFormat') and (Name <> 'hideLogo') then
        begin Error := 'Access denied'; Exit(403); end;
        if Op = '$unset' then Fields.Add(Name, TJSONNull.Create)
        else if Name = 'globalDateFormat' then
        begin
          if (TJSONObject(Part).Items[k].JSONType <> jtString) or not ValidDateFormat(TJSONObject(Part).Items[k].AsString) then
          begin Error := 'invalid-date-format'; Exit(400); end;
          Fields.Add(Name, TJSONObject(Part).Items[k].AsString);
        end
        else
        begin
          if TJSONObject(Part).Items[k].JSONType <> jtBoolean then Exit;
          Fields.Add(Name, TJSONObject(Part).Items[k].AsBoolean);
        end;
      end;
    end;
    if not SaveSettingsFields(Db, Selector.Get('_id', ''), Fields) then begin Error := 'Could not save'; Exit(500); end;
  finally
    Fields.Free;
  end;
  Error := '';
  Result := 200;
end;

// WeKan's changeAvatarPopup (below, with the avatar upload).
function ChangeAvatarPopup(Db: TWLDb; Words: TWLTranslator; const UserId, Error: string): string; forward;

function Page(Request: TRequest; const Language: TWLLanguage; Words: TWLTranslator;
  const S: TWLSession; const Title, BoardTitle, Content: string; const QuickAccess: string = ''): string;
var Dir, Header, ProfilePopup, Drawer: string; SiteAdmin: Boolean; T: TWLTenant;
begin
  SiteAdmin := (S.UserId <> '') and ResolveTenant(Request, T) and TenantOpen(T) and IsSiteAdmin(T.Db, S.UserId);
  ProfilePopup := ''; Drawer := '';
  if (S.UserId <> '') and ResolveTenant(Request, T) and TenantOpen(T) then
  begin
    ProfilePopup := EditProfilePopup(T.Db, Words, S.UserId) + MemberSettingsPopups(T.Db, Words, S.UserId, ViewBoardId) +
      ChangeAvatarPopup(T.Db, Words, S.UserId, Request.QueryFields.Values['avatarError']);
    Drawer := DrawerItems(T.Db, Words, S.UserId);
  end;
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
      '<section id="notifications-drawer" class="is-hidden"><div class="header"><a class="notification-menu-toggle" href="#" title="' +
      HtmlAttr(Words.Text('menu', 'Menu')) + '">&#9776;</a><div class="notification-menu is-hidden">' +
      '<a class="menu-item js-filter-unread selected" href="#">' + E(Words.Text('filter-by-unread', 'Filter by unread')) + '</a>' +
      '<a class="menu-item js-view-all" href="#">' + E(Words.Text('view-all', 'View All')) + '</a>' +
      '<a class="menu-item mark-all-read" href="#">' + E(Words.Text('mark-all-as-read', 'Mark all as read')) + '</a>' +
      '<a class="menu-item delete-all" href="#" data-confirm="' + E(Words.Text('delete-all-notifications-confirm',
      'Are you sure you want to delete all notifications? This action cannot be undone.')) + '">' +
      E(Words.Text('delete-all-notifications', 'Delete all notifications')) + '</a></div><h5>' + E(Words.Text('notifications', 'Notifications')) +
      '</h5><a class="close" href="#" title="' + HtmlAttr(Words.Text('close', 'Close')) + '">&times;</a></div><ul class="notifications">' +
      Drawer + '</ul></section>' +
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
      '<li><a class="js-edit-profile" href="#"><i class="fa fa-user"></i> ' + E(Words.Text('edit-profile', 'Edit Profile')) + '</a></li>' +
      '<li><a class="js-change-password" href="/profile/password"><i class="fa fa-key"></i> ' +
      E(Words.Text('changePasswordPopup-title', 'Change Password')) + '</a></li>' +
      '<li><a class="js-change-language" href="/language/popup"><i class="fa fa-globe"></i> ' +
      E(Words.Text('changeLanguagePopup-title', 'Change Language')) + '</a></li>' +
      // Member Settings / Date and Change Settings (userHeader.jade).
      '<li><a class="js-member-date-settings" href="#"><i class="fa fa-calendar"></i> ' + E(Words.Text('date', 'Date')) + '</a></li>' +
      '<li><a class="js-change-settings" href="#"><i class="fa fa-cog"></i> ' +
      E(Words.Text('change-settings', 'Change Settings')) + '</a></li>' +
      '<li><a class="js-change-avatar" href="#"><i class="fa fa-picture-o"></i> ' +
      E(Words.Text('change-avatar', 'Change Avatar')) + '</a></li>' +
      // The Admin Panel, for a site admin (memberMenuPopup's js-go-setting).
      IfThen(SiteAdmin, '<li><a class="js-go-setting" href="/admin/people"><i class="fa fa-lock"></i> ' +
        E(Words.Text('admin-panel', 'Admin Panel')) + '</a></li>', '') + '</ul></div></template>' + ProfilePopup +
      '<form class="js-logout" method="post" action="/logout"><button class="js-logout-button" type="submit">' +
      E(Words.Text('log-out', 'Log Out')) + '</button></form></div>';
  end
  else
    Header := '<div id="header" class="header-bar">' +
      Html5ViewToggle(PathAndQuery(Request), Words.Text('html4-html5-toggle', 'Toggle between HTML4 and HTML5 view')) + '</div>';
  Result := '<!DOCTYPE html>' + LineEnding +
    '<html lang="' + HtmlAttr(StringReplace(Language.Tag, '_', '-', [rfReplaceAll])) + '" dir="' + Dir + '"' +
    // No language chosen: welite.js tells the server the browser's own.
    IfThen(not ((S.UserId <> '') and ResolveTenant(Request, T) and TenantOpen(T) and ProfileLanguageSet(T.Db, S)),
      ' data-language-source="browser" data-language-tags="' + E(LanguageTags) + '"', '') + '>' +
    '<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<title>' + E(Title) + ' - WeKan</title>' + STATIC_HEAD + '</head>' +
    '<body>' + Header + '<main id="content">' + Content + '</main></body></html>' + LineEnding;
end;

// signin.pug
// Weddy's signup.pug, WeKan's register form: username, address, the
// password twice, each password with its visibility button.
function SignUpContent(Words: TWLTranslator; const Error, Username, Email: string; MinLength: Integer): string;
  function Toggle: string;
  begin
    Result := '<button class="password-toggle-btn primary" type="button" aria-label="' + HtmlAttr(Words.Text('password', 'Password') + ': ' +
      Words.Text('visibility', 'Visibility')) + '" title="' + HtmlAttr(Words.Text('password', 'Password') + ': ' +
      Words.Text('visibility', 'Visibility')) + '">&#128065;</button>';
  end;
begin
  Result := '<div class="auth-layout"><div class="auth-dialog at-form"><h1 class="at-title">' + E(Words.Text('register', 'Register')) + '</h1>';
  if Error <> '' then Result := Result + '<div class="at-error js-signup-error">' + E(Error) + '</div>';
  Result := Result + '<form id="at-signup-form" method="post" action="/sign-up">' +
    '<label for="at-field-username">' + E(Words.Text('username', 'Username')) + '</label>' +
    '<input id="at-field-username" type="text" name="username" value="' + HtmlAttr(Username) + '" autocomplete="username" required>' +
    '<label for="at-field-email">' + E(Words.Text('email', 'Email')) + '</label>' +
    '<input id="at-field-email" type="email" name="email" value="' + HtmlAttr(Email) + '" autocomplete="email" required>' +
    '<label for="at-field-password">' + E(Words.Text('password', 'Password')) + '</label>' +
    '<div class="password-input-container"><input id="at-field-password" class="password-field" type="password" name="password" ' + IfThen(MinLength > 0, 'minlength="' + IntToStr(MinLength) + '" ', '') +
    'autocomplete="new-password" required>' + Toggle + '</div>' +
    '<label for="at-field-password_again">' + E(Words.Text('password-again', 'Password (again)')) + '</label>' +
    '<div class="password-input-container"><input id="at-field-password_again" class="password-field" type="password" name="confirm" ' + IfThen(MinLength > 0, 'minlength="' + IntToStr(MinLength) + '" ', '') +
    'autocomplete="new-password" required>' + Toggle + '</div>' +
    '<button id="at-btn" class="at-btn submit primary" type="submit">' + E(Words.Text('create-account', 'Create Account')) + '</button>' +
    '</form><p><a href="/sign-in">' + E(Words.Text('log-in', 'Log In')) + '</a></p></div></div>';
end;

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
// The board's active members for the comment editor's @ mention menu
// (editor.js's mentions strategy: board.activeMembers()), as JSON
// [{"u":username,"f":full name}] - welite.js draws the menu from it.
function MentionMembersJson(Db: TWLDb; const BoardId: string): string;
var R: TWLRows; i: Integer;
begin
  R := Db.Query('SELECT u.username,COALESCE(CASE WHEN json_valid(u.profile_json) THEN json_extract(u.profile_json,''$.fullname'') END,'''') ' +
    'FROM board_members m JOIN users u ON u.id=m.userId WHERE m.boardId=' + QuotedStr(BoardId) +
    ' AND m.isActive=1 AND COALESCE(u.loginDisabled,0)=0 ORDER BY u.username;');
  Result := '[';
  for i := 0 to High(R) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '{"u":"' + StringToJSONString(R[i][0]) + '","f":"' + StringToJSONString(R[i][1]) + '"}';
  end;
  Result := Result + ']';
end;

function CommentsSection(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId: string; CanComment: Boolean): string;
var R: TWLRows; i: Integer; Shown: string;
begin
  Result := '<h3 class="card-details-item-title js-toggle-card-section" data-section="comments" role="button" tabindex="0">' +
    '<i class="fa fa-comment-o" aria-hidden="true"></i> ' + E(Words.Text('comments', 'Comments')) + '</h3><div class="comments">';
  if CanComment then
    Result := Result + '<div class="new-comment js-new-comment"><form class="js-new-comment-form" method="post" action="/b/' +
      HtmlAttr(HTTPEncode(BoardId)) + '/cards/' + HtmlAttr(HTTPEncode(CardId)) + '/comments" up-submit up-target=".board-wrapper">' +
      '<textarea class="editor js-new-comment-input" name="comment" aria-label="' + HtmlAttr(Words.Text('comment', 'Comment')) +
      '" data-mentions="' + E(MentionMembersJson(Db, BoardId)) + '" required></textarea><button class="primary confirm js-add-comment" type="submit">' + E(Words.Text('comment', 'Comment')) +
      '</button></form></div>';
  R := Db.Query('SELECT c.id,c.text,COALESCE(c.createdAt,''''),COALESCE(u.username,'''') FROM card_comments c LEFT JOIN users u ON u.id=c.userId ' +
    'WHERE c.cardId=' + QuotedStr(CardId) + ' AND (c.boardId IS NULL OR c.boardId=' + QuotedStr(BoardId) + ') ORDER BY c.createdAt,c.id;');
  for i := 0 to High(R) do
  begin
    // The stored time, as minutes: 2026-11-26T01:02:03.456Z -> 2026-11-26 01:02.
    Shown := FormatShownDate(R[i][2], ViewDateFormat);
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
var i, n, k: Integer; Field, Setting, Label_, Url, Common, Shown: string;
begin
  Result := '';
  // In the Card pane's row order (wlcardst), WeKan's own without one.
  for n := 0 to 3 do
  begin
    i := n;
    if Length(ViewCardDates) = 4 then
      for k := 0 to 3 do if Kinds[k] = ViewCardDates[n] then i := k;
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
      Shown := FormatShownDate(Values[i], ViewDateFormat);
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
    else if Kind = 'date' then Shown := FormatShownDate(Value, ViewDateFormat);
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
  // An SVG is an image again: sanitized, and served under a script-free sandbox.
  if (MimeType = 'image/png') or (MimeType = 'image/jpeg') or (MimeType = 'image/gif') or (MimeType = 'image/webp') or
    (MimeType = 'image/svg+xml') then
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
  // The list's name as WeKan's viewer draws it, under Admin Panel's text display.
  Result := Result + '<details class="card-details-list-picker"><summary>' +
    MarkdownViewer(Current, SharedSettingOn(Db, 'renderLinksAsPlainText'), SharedSettingOn(Db, 'alwaysShowCodeAsText')) + '</summary>' +
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
    // The Advanced Filter: as typed, the one applied (typed, else the last
    // that parsed), and the cards it shows.
    Advanced, Applied: string;
    HasAdvanced: Boolean;
    AdvancedIds: TStringArray;
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

// The board's cards an Advanced Filter shows (src/wladvf.pas, with the
// board's custom fields by name and a dropdown's options by name, as WeKan's
// buildAdvancedFilterResolversFromCustomFields); False for one that does not
// parse.
function AdvancedFilterCards(Db: TWLDb; const BoardId, Filter: string; out Ids: TStringArray): Boolean;
var R, V: TWLRows; Fields: array of TAdvField; Cards: array of TAdvCard; i, j, n: Integer; Node: TAdvNode;
begin
  Ids := nil;
  R := Db.Query('SELECT f.id,f.name,f.type,COALESCE((SELECT group_concat(d.name || ''='' || d.id, char(10)) FROM ' +
    '(SELECT name,id FROM custom_field_dropdown_items WHERE customFieldId=f.id ORDER BY sort,id) d),'''') FROM custom_fields f ' +
    // No rowid: in a shared store these are views.
    'JOIN custom_field_boards b ON b.customFieldId=f.id WHERE b.boardId=' + QuotedStr(BoardId) + ';');
  Fields := nil;
  for i := 0 to High(R) do
  begin
    // A name the board has twice is the first field of that name.
    n := -1;
    for j := 0 to High(Fields) do if Fields[j].Name = R[i][1] then n := j;
    if n >= 0 then Continue;
    n := Length(Fields); SetLength(Fields, n + 1);
    Fields[n].Id := R[i][0]; Fields[n].Name := R[i][1]; Fields[n].Kind := R[i][2];
    if R[i][3] <> '' then Fields[n].Options := R[i][3].Split([#10]) else Fields[n].Options := nil;
  end;
  Node := ParseAdvancedFilter(Filter, Fields);
  if Node = nil then Exit(False);
  try
    R := Db.Query('SELECT id,COALESCE(createdAt,''''),COALESCE(receivedAt,''''),COALESCE(startAt,''''),COALESCE(dueAt,''''),' +
      'COALESCE(endAt,''''),COALESCE(CASE WHEN json_valid(extra_json) THEN json_extract(extra_json,''$.listEnteredAt'') END,'''') ' +
      'FROM cards WHERE boardId=' + QuotedStr(BoardId) + ' AND deletedAt IS NULL;');
    V := Db.Query('SELECT v.cardId,v.customFieldId,COALESCE(CAST(v.value AS TEXT),''''),v.value IS NULL FROM card_custom_field_values v ' +
      'JOIN cards c ON c.id=v.cardId WHERE c.boardId=' + QuotedStr(BoardId) + ' AND c.deletedAt IS NULL ORDER BY v.cardId;');
    SetLength(Cards, 1);
    for i := 0 to High(R) do
    begin
      Cards[0] := Default(TAdvCard);
      for j := 0 to 5 do Cards[0].Dates[j] := R[i][j + 1];
      for j := 0 to High(V) do
        if V[j][0] = R[i][0] then
        begin
          n := Length(Cards[0].Values); SetLength(Cards[0].Values, n + 1);
          Cards[0].Values[n].FieldId := V[j][1]; Cards[0].Values[n].Value := V[j][2]; Cards[0].Values[n].IsNull := V[j][3] = '1';
        end;
      if AdvancedFilterMatches(Node, Cards[0]) then
      begin
        SetLength(Ids, Length(Ids) + 1);
        Ids[High(Ids)] := R[i][0];
      end;
    end;
  finally
    Node.Free;
  end;
  Result := True;
end;

function ParseBoardFilter(Db: TWLDb; const BoardId: string; Query: TStrings): TBoardFilter;
var Known: TWLRows; Unused: Boolean; Wide: UnicodeString; Candidate: string; k: Integer;
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
  // The Advanced Filter typed when it parses, else the last that did
  // (?last=), as WeKan's sidebar keeps its last selector.
  Result.Advanced := Copy(Trim(Query.Values['advanced']), 1, 2000);
  if Pos(#0, Result.Advanced) > 0 then Result.Advanced := '';
  for k := 0 to 1 do
  begin
    if k = 0 then Candidate := Result.Advanced else Candidate := Copy(Trim(Query.Values['last']), 1, 2000);
    if (Candidate = '') or (Pos(#0, Candidate) > 0) then Continue;
    if AdvancedFilterCards(Db, BoardId, Candidate, Result.AdvancedIds) then
    begin
      Result.Applied := Candidate; Result.HasAdvanced := True;
      Break;
    end;
  end;
end;

function FilterActive(const F: TBoardFilter): Boolean;
begin
  Result := (F.Text <> '') or (Length(F.Labels) > 0) or F.NoLabel or (Length(F.Excluded) > 0) or F.HasAdvanced;
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
  if F.HasAdvanced then
  begin
    if Length(F.AdvancedIds) = 0 then Result := Result + ' AND 0'
    else Result := Result + ' AND c.id IN (' + SqlList(F.AdvancedIds) + ')';
  end;
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
  Result := '<div class="filter-sidebar js-filter-view is-hidden" data-applied="' + E(F.Applied) + '"><h3><i class="fa fa-list"></i> ' +
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
  // filterSidebar's Advanced Filter, with WeKan's help and the card dates hint.
  Result := Result + '</ul><hr><h3>' + E(Words.Text('advanced-filter-label', 'Advanced Filter')) + '</h3>' +
    '<input class="js-field-advanced-filter" type="text" value="' + E(F.Advanced) + '" aria-label="' +
    E(Words.Text('advanced-filter-label', 'Advanced Filter')) + '"><span>' + E(Words.Text('advanced-filter-description', '')) +
    '</span><p class="quiet">' + E(Words.Text('advanced-filter-card-dates-hint', '')) + '</p></div>';
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

// WeKan's activities (client/components/activities, Weddy's activities.go):
// the newest first, each its member and its sentence in the reader's
// language - the sentence escaped, each name in it escaped too.
function ActivityRows(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId: string; Limit: Integer): string;
var R: TWLRows; i, k: Integer; Key, Fallback, Board, Text, Sentence, Part: string; Args: array of string;
  function Data(const Field: string): string;
  begin
    Result := 'CASE WHEN json_valid(a.data_json) THEN json_extract(a.data_json,''$.' + Field + ''') END';
  end;
  function Person(const Column: string): string;
  begin
    Result := '(SELECT COALESCE(NULLIF(CASE WHEN json_valid(u.profile_json) THEN json_extract(u.profile_json,''$.fullname'') END,''''),u.username) ' +
      'FROM users u WHERE u.id=' + Column + ')';
  end;
  procedure Say(const AKey, AFallback: string; const AArgs: array of string);
  var j: Integer;
  begin
    Key := AKey; Fallback := AFallback;
    SetLength(Args, Length(AArgs));
    for j := 0 to High(AArgs) do Args[j] := AArgs[j];
  end;
begin
  Result := '';
  if Pos(#0, BoardId + CardId) > 0 then Exit;
  R := Db.Query('SELECT a.id,a.activityType,COALESCE(' + Person('a.userId') + ',''''),' +
    'COALESCE((SELECT title FROM cards WHERE id=a.cardId),' + Data('cardTitle') + ',''''),' +
    'COALESCE((SELECT title FROM lists WHERE id=a.listId),' + Data('listName') + ',''''),' +
    'COALESCE((SELECT title FROM lists WHERE id=' + Data('oldListId') + '),' + Data('oldListName') + ',''''),' +
    'COALESCE((SELECT title FROM checklists WHERE id=' + Data('checklistId') + '),''''),' +
    'COALESCE(' + Person(Data('memberId')) + ',''''),COALESCE(' + Data('attachmentName') + ',''''),' +
    'COALESCE(' + Data('commentText') + ',''''),COALESCE(' + Data('title') + ',''''),' +
    'COALESCE((SELECT title FROM swimlanes WHERE id=a.swimlaneId),''''),' +
    'COALESCE((SELECT name FROM custom_fields WHERE id=' + Data('customFieldId') + '),''''),' +
    'COALESCE(' + Data('value') + ',''''),COALESCE(a.createdAt,''''),(SELECT title FROM boards WHERE id=a.boardId) ' +
    'FROM activities a WHERE a.boardId=' + QuotedStr(BoardId) + IfThen(CardId <> '', ' AND a.cardId=' + QuotedStr(CardId), '') +
    ' ORDER BY a.createdAt DESC LIMIT ' + IntToStr(Limit) + ';');
  for i := 0 to High(R) do
  begin
    Board := R[i][15];
    case R[i][1] of
      'a-changedTitle': Say('activity-changedTitle', 'changed title to %s of %s', [R[i][13], R[i][3]]);
      'a-changedDescription': Say('activity-changedDescription', 'changed description of %s', [R[i][3]]);
      'createBoard': Say('activity-created', 'created %s', [Board]);
      'addBoardMember': Say('activity-added', 'added %s to %s', [R[i][7], Board]);
      'removeBoardMember': Say('activity-excluded', 'excluded %s from %s', [R[i][7], Board]);
      'createCard': Say('activity-added', 'added %s to %s', [R[i][3], R[i][4]]);
      'moveCard': Say('activity-moved', 'moved %s from %s to %s', [R[i][3], R[i][5], R[i][4]]);
      'archivedCard': Say('activity-archived', '%s moved to Archive', [R[i][3]]);
      'restoredCard': Say('activity-sent', 'sent %s to %s', [R[i][3], Board]);
      'addChecklist': Say('activity-checklist-added', 'added checklist to %s', [R[i][3]]);
      'removedChecklist': Say('activity-checklist-removed', 'removed a checklist from %s', [R[i][3]]);
      'addChecklistItem', 'addedChecklistItem': Say('activity-checklist-item-added', 'added checklist item to ''%s'' in %s', [R[i][6], R[i][3]]);
      'addComment': Say('activity-on', 'on %s', [R[i][3]]);
      'editComment': Say('activity-editComment', 'edited comment %s', [R[i][9]]);
      'deleteComment': Say('activity-deleteComment', 'deleted comment %s', [R[i][9]]);
      'addAttachment': Say('activity-attached', 'attached %s to %s', [R[i][8], R[i][3]]);
      'deleteAttachment': Say('activity-delete-attach', 'deleted an attachment from %s', [R[i][3]]);
      'createList': Say('activity-added', 'added %s to %s', [R[i][4], Board]);
      'archivedList': Say('activity-archived', '%s moved to Archive', [R[i][4]]);
      'removeList': Say('activity-removed', 'removed %s from %s', [R[i][10], Board]);
      'joinMember': Say('activity-added', 'added %s to %s', [R[i][7], R[i][3]]);
      'unjoinMember': Say('activity-removed', 'removed %s from %s', [R[i][7], R[i][3]]);
      'createSwimlane': Say('activity-added', 'added %s to %s', [R[i][11], Board]);
      'createCustomField': Say('activity-customfield-created', 'created custom field %s', [R[i][12]]);
    else
      // WeKan: {{_ activity.activityType}}
      Say(R[i][1], R[i][1], []);
    end;
    Sentence := Words.Text(Key, Fallback);
    Text := ''; k := 0;
    while Pos('%s', Sentence) > 0 do
    begin
      Part := Copy(Sentence, 1, Pos('%s', Sentence) - 1);
      Text := Text + E(Part);
      if k <= High(Args) then Text := Text + E(Args[k]);
      Inc(k);
      Delete(Sentence, 1, Length(Part) + 2);
    end;
    Text := Text + E(Sentence);
    Result := Result + '<div class="activity" data-id="' + HtmlAttr(R[i][0]) + '"><div class="activity-desc"><span class="activity-member">' +
      E(R[i][2]) + '</span> ' + Text + '</div><time class="activity-time" datetime="' + HtmlAttr(R[i][14]) + '">' +
      E(FormatShownDate(R[i][14], ViewDateFormat)) + '</time></div>';
  end;
end;

// board.pug's sidebar: the board's members, the board menu (boardMenuPopup,
// its Archived Items) and the Archive (archivesSidebar) with its restore.
function BoardSidebar(Db: TWLDb; Words: TWLTranslator; const S: TWLSession; const BoardId: string; Writable: Boolean;
  const FilterView: string): string;
var R, Rooms: TWLRows; i: Integer; Archived, ListTitle: string; HasCards: Boolean;
  // WeKan's restoreArchivedCardToListPopup (#6772): the card's list is gone,
  // or full at a hard WIP limit - one of the lists with room instead.
  function BlockedPopup(const Id, ListId: string): string;
  var k: Integer; Options: string;
  begin
    Options := '';
    for k := 0 to High(Rooms) do
      Options := Options + '<option value="' + HtmlAttr(Rooms[k][0]) + '">' + E(Rooms[k][1]) + '</option>';
    Result := '<template class="js-pop-over-template" data-pop="restore-card-' + HtmlAttr(Id) + '" data-title="' +
      HtmlAttr(Words.Text('restore', 'Restore')) + '"><div class="content"><p class="js-restore-wip-reached">';
    if ListTitle <> '' then
      Result := Result + E(StringReplace(Words.Text('restore-card-wip-limit-reached',
        'The list __list__ has reached its WIP limit. Restore the card to another list:'), '__list__', ListTitle, [rfReplaceAll]))
    else
      Result := Result + E(Words.Text('error-list-doesNotExist', 'This list does not exist'));
    Result := Result + '</p>';
    if Options <> '' then
      Result := Result + '<form method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) + '/archive/restore" up-submit ' +
        'up-target=".board-wrapper"><input type="hidden" name="kind" value="cards"><input type="hidden" name="id" value="' +
        HtmlAttr(Id) + '"><select class="js-select-restore-target-list" name="toList" autofocus>' + Options + '</select>' +
        '<div class="edit-controls clearfix"><button class="primary confirm js-restore-card-to-list" type="submit">' +
        E(Words.Text('restore', 'Restore')) + '</button></div></form>'
    else
      Result := Result + '<p class="js-restore-no-list-with-room">' + E(Words.Text('restore-card-no-list-with-room',
        'Every list on this board has reached its WIP limit. Raise a limit, or move or archive cards, to restore this card.')) + '</p>';
    Result := Result + '</div></template>';
    if ViewRestoreBlocked = Id then
      Result := Result + '<span class="js-open-pop-on-load" data-pop="restore-card-' + HtmlAttr(Id) + '" hidden></span>';
  end;
  function Item(const Kind, Id, Title: string; Card: Boolean; const ListId: string = ''): string;
  var Restore, Pop: string; Blocked: Boolean;
  begin
    Restore := ''; Pop := '';
    Blocked := Card and Writable and not ListHasRoom(Db, BoardId, ListId, ListTitle);
    if Writable then
      Restore := '<form class="js-restore-form" method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) +
        '/archive/restore" up-submit up-target=".board-wrapper"><input type="hidden" name="kind" value="' + Kind +
        '"><input type="hidden" name="id" value="' + HtmlAttr(Id) + '"><a class="' + IfThen(Card, 'js-restore-card', 'js-restore') +
        // No data-pop: the page may be older than the list's limit, so the
        // server decides, and answers a full list with this popup open.
        '" href="#">' + E(Words.Text('restore', 'Restore')) + '</a></form>';
    if Blocked then Pop := BlockedPopup(Id, ListId);
    if Card then
      Result := '<div class="minicard-wrapper archived-item archived-card-item" data-kind="cards" data-id="' + HtmlAttr(Id) +
        '"><div class="minicard"><div class="minicard-title">' + E(Title) + '</div></div>' + Restore + Pop + '</div>'
    else
      Result := '<div class="archived-item" data-kind="' + Kind + '" data-id="' + HtmlAttr(Id) + '"><span class="archived-item-title">' +
        E(Title) + '</span>' + Restore + '</div>';
  end;
  function RuleMenuLink(const Cls, View, Icon, Key, Fallback: string): string;
  begin
    Result := '<li><a class="' + Cls + '" href="' + HtmlAttr(BoardRoute(BoardId, BoardSlug(Db, BoardId)) + '/rules' + View) +
      '" title="' + HtmlAttr(Words.Text(Key, Fallback)) + '"><i class="fa ' + Icon + '"></i> ' + E(Words.Text(Key, Fallback)) +
      '</a></li>';
  end;
begin
  Archived := '';
  // The open lists a card can be restored into: not full at a hard limit.
  Rooms := Db.Query('SELECT l.id,l.title FROM lists l WHERE l.boardId=' + QuotedStr(BoardId) + ' AND l.archived=0 AND l.deletedAt IS NULL ' +
    'AND NOT (COALESCE(l.wip_enabled,0)=1 AND COALESCE(l.wip_soft,0)=0 AND (SELECT count(*) FROM cards c WHERE c.listId=l.id AND ' +
    'c.archived=0 AND c.deletedAt IS NULL)>=COALESCE(l.wip_value,1)) ORDER BY l.sort,l.title;');
  R := Db.Query('SELECT id,title,COALESCE(listId,'''') FROM cards WHERE boardId=' + QuotedStr(BoardId) +
    ' AND archived=1 AND deletedAt IS NULL ORDER BY archivedAt DESC,id;');
  HasCards := Length(R) > 0;
  for i := 0 to High(R) do Archived := Archived + Item('cards', R[i][0], R[i][1], True, R[i][2]);
  R := Db.Query('SELECT id,title FROM lists WHERE boardId=' + QuotedStr(BoardId) + ' AND archived=1 AND deletedAt IS NULL ORDER BY sort,id;');
  for i := 0 to High(R) do Archived := Archived + Item('lists', R[i][0], R[i][1], False);
  R := Db.Query('SELECT id,title FROM swimlanes WHERE boardId=' + QuotedStr(BoardId) + ' AND archived=1 ORDER BY sort,id;');
  for i := 0 to High(R) do Archived := Archived + Item('swimlanes', R[i][0], R[i][1], False);
  if Archived = '' then
    Archived := '<p class="no-items-message">' + E(Words.Text('no-archived-cards', 'No archived cards.')) + '</p>'
  else if HasCards and Writable then
    // archivesSidebar's Restore all, of the cards.
    Archived := '<form class="js-restore-all-form" method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) +
      '/archive/restore-all-cards" up-submit up-target=".board-wrapper"><a class="js-restore-all-cards" href="#">' +
      E(Words.Text('restore-all', 'Restore all')) + '</a></form>' + Archived;
  // WeKan's restoreAllSkippedPopup: Restore all left cards out (#6772).
  if ViewRestoreSkipped > 0 then
    Archived := Archived + '<template class="js-pop-over-template" data-pop="restore-all-skipped" data-title="' +
      HtmlAttr(Words.Text('restore-all', 'Restore all')) + '"><div class="content"><p class="js-restore-all-skipped">' +
      E(StringReplace(Words.Text('restore-all-skipped-wip-limit', '__count__ card(s) were not restored: their lists have reached ' +
      'their WIP limits. Restore them one at a time to choose another list.'), '__count__', IntToStr(ViewRestoreSkipped), [rfReplaceAll])) +
      '</p></div></template><span class="js-open-pop-on-load" data-pop="restore-all-skipped" hidden></span>';
  Result := '<div class="board-sidebar sidebar"><a class="sidebar-xmark js-close-sidebar" href="#" aria-label="' +
    HtmlAttr(Words.Text('close', 'Close')) + '">&#10005;</a><div class="sidebar-content js-board-sidebar-content">' +
    FilterView +
    // sidebar.jade: an invitation to this board, to accept or decline.
    IfThen(ViewInvited(Db, S.UserId, BoardId), '<div class="js-board-invitation"><p><i class="fa fa-exclamation-triangle"></i> ' +
      E(Words.Text('just-invited', 'You are just invited to this board')) + '</p><button class="js-member-invite-accept primary" type="button">' +
      E(Words.Text('accept', 'Accept')) + '</button><button class="js-member-invite-decline" type="button">' + E(Words.Text('decline', 'Decline')) +
      '</button></div><hr>', '') +
    // WeKan's multiselectionSidebar: what to do with the selected cards.
    IfThen(Writable, '<div class="multiselection-sidebar js-multiselection-view is-hidden"><h3>' +
      E(Words.Text('multi-selection-on', 'Multi-Selection is on')) + '</h3><ul class="pop-over-list"><li><a class="js-archive-selection" href="#">' +
      E(Words.Text('archive-selection', 'Move selection to Archive')) + '</a></li></ul></div>', '') +
    '<div class="archives-sidebar js-archives-view is-hidden"><h3>' + E(Words.Text('archives', 'Archives')) + '</h3>' + Archived + '</div>' +
    '<div class="board-widget board-widget-members membersWidget"><h3 class="board-widget-title">' + E(Words.Text('members', 'Members')) +
    '</h3><div class="board-widget-content">';
  R := Db.Query('SELECT u.id,u.username,COALESCE(CASE WHEN json_valid(u.profile_json) THEN json_extract(u.profile_json,''$.avatarUrl'') END,'''') ' +
    'FROM board_members m JOIN users u ON u.id=m.userId WHERE m.boardId=' + QuotedStr(BoardId) +
    ' AND m.isActive=1 AND COALESCE(u.loginDisabled,0)=0 ORDER BY u.username;');
  for i := 0 to High(R) do
  begin
    Result := Result + '<a class="member js-member" href="#" data-user="' + HtmlAttr(R[i][0]) + '" title="' + HtmlAttr(R[i][1]) +
      '" aria-label="' + HtmlAttr(R[i][1]) + '">';
    // An uploaded avatar, at the path WeKan is served under now
    // (avatarDisplayUrl, wlavatar); its initials otherwise.
    if R[i][2] <> '' then
      Result := Result + '<img class="avatar avatar-image" src="' + E(AvatarDisplayUrl(R[i][2], '')) + '" alt="' + E(R[i][1]) + '">'
    else
      Result := Result + '<span class="member-initials">' + E(R[i][1]) + '</span>';
    Result := Result + '</a>';
  end;
  // membersWidget's add, for whoever may invite: a board admin.
  if (S.UserId <> '') and BoardCanAdmin(Db, S.UserId, BoardId) then
    Result := Result + '<a class="member add-member js-manage-board-members" href="#" title="' +
      HtmlAttr(Words.Text('add-members', 'Add Members')) + '" aria-label="' + HtmlAttr(Words.Text('add-members', 'Add Members')) +
      '"><i class="fa fa-plus"></i></a>';
  Result := Result + '</div></div><h3><a class="board-header-btn js-open-board-menu" href="#" title="' +
    HtmlAttr(Words.Text('boardMenuPopup-title', 'Board Settings')) + '">' + E(Words.Text('boardMenuPopup-title', 'Board Settings')) +
    '</a></h3>' +
    // The board's activities, for a board admin, put on the page when opened.
    IfThen((S.UserId <> '') and BoardCanAdmin(Db, S.UserId, BoardId), '<hr><h3 class="activity-title js-toggle-show-activities" role="button" tabindex="0" title="' +
      HtmlAttr(Words.Text('activities', 'Activities')) + '"><i class="fa fa-caret-right"></i><i class="fa fa-comment-o"></i> ' +
      E(Words.Text('activities', 'Activities')) + '</h3><div class="activities js-sidebar-activities is-hidden"><template class="js-stamp-on-open">' +
      ActivityRows(Db, Words, BoardId, '', 50) + '</template></div>', '') +
    '</div></div>' +
    '<template class="js-pop-over-template" data-pop="board-menu" data-title="' + HtmlAttr(Words.Text('boardMenuPopup-title', 'Board Settings')) +
    '"><div class="header"><span class="header-title">' + E(Words.Text('boardMenuPopup-title', 'Board Settings')) +
    '</span><a class="close-btn js-close-pop-over" href="#" aria-label="' + HtmlAttr(Words.Text('close', 'Close')) + '">&times;</a></div>' +
    '<div class="content"><ul class="pop-over-list"><li><a class="js-open-archives" href="#"><i class="fa fa-archive"></i> ' +
    E(Words.Text('archived-items', 'Archived Items')) + '</a></li>' +
    // Board Settings / Card (sidebar.jade boardMenuPopup), for a member.
    IfThen(S.UserId <> '', '<li><a class="js-open-board-card-settings" href="#" title="' + HtmlAttr(Words.Text('card-settings', 'Card Settings')) +
      '"><i class="fa fa-id-card-o"></i> ' + E(Words.Text('card-settings', 'Card Settings')) + '</a></li>', '') +
    // Board Settings / Date (sidebar.jade boardMenuPopup).
    IfThen(S.UserId <> '', '<li><a class="js-open-board-date-settings" href="#" title="' + HtmlAttr(Words.Text('date', 'Date')) +
      '"><i class="fa fa-calendar"></i> ' + E(Words.Text('date', 'Date')) + '</a></li>', '') +
    // Board Settings / Rules, for a board admin: the Rules page and its views
    // (wlrules), as Weddy's board.pug links them.
    IfThen((S.UserId <> '') and BoardCanAdmin(Db, S.UserId, BoardId),
      RuleMenuLink('js-open-rules-view', '', 'fa-magic', 'rules', 'Rules') +
      RuleMenuLink('js-open-rules-list-view', '?view=list', 'fa-list', 'r-list-view', 'List view') +
      RuleMenuLink('js-open-rules-workflow-view', '?view=workflow', 'fa-sitemap', 'r-workflow-view', 'Workflow view') +
      RuleMenuLink('js-open-rules-import-export', '?view=import', 'fa-exchange', 'rulesImportExportPopup-title', 'Import / Export'), '') +
    '</ul></div></template>' + IfThen(S.UserId <> '', BoardDateSettingsPopup(Db, Words, S.UserId, BoardId) +
      CardSettingsPopup(Db, Words, S.UserId, BoardId, BoardOwnAdmin(Db, S.UserId, BoardId),
        ProfileField(Db, S.UserId, 'showDesktopDragHandles') = '1'), '');
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
  if Text <> '' then Viewer := MarkdownViewer(Text, SharedSettingOn(Db, 'renderLinksAsPlainText'), SharedSettingOn(Db, 'alwaysShowCodeAsText'));
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
    Labels, Members, Assignees, Comments, Complete: Boolean;
    // Card Settings' minicard sides (wlcardst's table, each with its default).
    RequestedBy, Location, LastActivity, DescriptionBadge, CardColor: Boolean;
    Dates: array[0..3] of Boolean;
    SetDates: Boolean;
  end;

// A board's card setting as stored (settings_json), Default when it has none.
function BoardSettingFlag(Db: TWLDb; const BoardId, Setting: string; Default: Boolean): Boolean;
var R: TWLRows;
begin
  Result := Default;
  R := Db.Query('SELECT json_type(settings_json,''$.' + Setting + ''') FROM boards WHERE id=' + QuotedStr(BoardId) + ' AND json_valid(settings_json);');
  if (Length(R) = 1) and ((R[0][0] = 'true') or (R[0][0] = 'false')) then Result := R[0][0] = 'true'
  else if (Length(R) = 1) and (R[0][0] = 'integer') then
    Result := Db.Query('SELECT json_extract(settings_json,''$.' + Setting + ''') FROM boards WHERE id=' + QuotedStr(BoardId) + ';')[0][0] <> '0';
end;

// A person's initials as the minicard shows them: their own, or the first
// letters of the first two words of their name.
function PersonInitials(const Initials, Name: string): string;
var Words_: TStringArray; i: Integer; W: UnicodeString;
begin
  if Initials <> '' then Exit(Initials);
  Result := '';
  Words_ := Trim(Name).Split([' '], TStringSplitOptions.ExcludeEmpty);
  for i := 0 to High(Words_) do
  begin
    if i > 1 then Break;
    W := UTF8Decode(Words_[i]);
    if W <> '' then Result := Result + UpperCase(UTF8Encode(Copy(W, 1, 1)));
  end;
end;

function MinicardShows(Db: TWLDb; const BoardId: string; SetDates: Boolean): TMinicardShows;
const Settings: array[0..3] of string = ('allowsReceivedDate', 'allowsStartDate', 'allowsDueDate', 'allowsEndDate');
var i: Integer;
begin
  Result.Labels := BoardAllows(Db, BoardId, 'allowsLabels') and BoardAllows(Db, BoardId, 'allowsLabelsOnMinicard');
  Result.Members := BoardAllows(Db, BoardId, 'allowsMembers') and BoardAllows(Db, BoardId, 'allowsMembersOnMinicard');
  // getMinicardFlag: allowsAssigneeOnMinicard, else allowsAssignee, else on.
  Result.Assignees := BoardSettingFlag(Db, BoardId, 'allowsAssigneeOnMinicard', BoardSettingFlag(Db, BoardId, 'allowsAssignee', True));
  // Off unless the board turns them on.
  Result.Comments := BoardSettingFlag(Db, BoardId, 'allowsCommentsOnMinicard', False);
  Result.Complete := SetDates and BoardSettingFlag(Db, BoardId, 'allowsDueCompleteOnMinicard', False);
  Result.RequestedBy := BoardSettingFlag(Db, BoardId, 'allowsRequestedByOnMinicard', True);
  Result.Location := BoardSettingFlag(Db, BoardId, 'allowsLocationOnMinicard', False);
  Result.LastActivity := BoardSettingFlag(Db, BoardId, 'allowsActivitiesOnMinicard', False);
  Result.DescriptionBadge := BoardSettingFlag(Db, BoardId, 'allowsDescriptionBadgeOnMinicard', True);
  Result.CardColor := BoardSettingFlag(Db, BoardId, 'allowsCardColorOnMinicard', True);
  for i := 0 to 3 do
    Result.Dates[i] := BoardAllows(Db, BoardId, Settings[i]) and
      BoardAllows(Db, BoardId, StringReplace(Settings[i], 'Date', 'DateOnMinicard', []));
  Result.SetDates := SetDates;
end;

type
  // Each section's content by its id: HTML may hold line breaks, which a
  // TStringList's name=value pairs would split.
  TSectionBodies = array of record Id, Html: string; end;

procedure PutSection(var Bodies: TSectionBodies; const Id, Html: string);
var i: Integer;
begin
  for i := 0 to High(Bodies) do
    if Bodies[i].Id = Id then begin Bodies[i].Html := Bodies[i].Html + Html; Exit; end;
  SetLength(Bodies, Length(Bodies) + 1);
  Bodies[High(Bodies)].Id := Id;
  Bodies[High(Bodies)].Html := Html;
end;

function SectionOf(const Bodies: TSectionBodies; const Id: string): string;
var i: Integer;
begin
  for i := 0 to High(Bodies) do if Bodies[i].Id = Id then Exit(Bodies[i].Html);
  Result := '';
end;

// A card colour fit for a class name (minicard-<color>, card-details-<color>):
// WeKan's colour names are lowercase words.
function ColorName(const Color: string): Boolean;
var i: Integer;
begin
  Result := (Color <> '') and (Length(Color) <= 24);
  for i := 1 to Length(Color) do if not (Color[i] in ['a'..'z']) then Exit(False);
end;

// A card's places: the names of its locations (WeKan's locations), else the
// one location WeLite keeps (locationName).
function LocationNames(const Json, Single: string): TStringArray;
var D: TJSONData; i: Integer;
begin
  Result := nil;
  D := nil;
  try
    try
      D := GetJSON(Json);
    except
      D := nil;
    end;
    if D is TJSONArray then
      for i := 0 to TJSONArray(D).Count - 1 do
        if (TJSONArray(D).Items[i] is TJSONObject) and (TJSONObject(TJSONArray(D).Items[i]).Get('name', '') <> '') then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := TJSONObject(TJSONArray(D).Items[i]).Get('name', '');
        end;
  finally
    D.Free;
  end;
  if (Length(Result) = 0) and (Single <> '') then
  begin
    SetLength(Result, 1);
    Result[0] := Single;
  end;
end;

function MinicardBadges(Db: TWLDb; Words: TWLTranslator; const BoardId, CardId: string; const Shows: TMinicardShows;
  const Dates: array of string; const Extra: array of string): string;
const
  Kinds: array[0..3] of string = ('received', 'start', 'due', 'end');
  Icons: array[0..3] of string = ('fa-sign-out', 'fa-hourglass-start', 'fa-clock-o', 'fa-hourglass-end');
  Captions: array[0..3] of string = ('Received', 'Start', 'Due', 'End');
  Titles: array[0..3] of string = ('editCardReceivedDatePopup-title', 'editCardStartDatePopup-title',
    'editCardDueDatePopup-title', 'editCardEndDatePopup-title');
  TitleCaptions: array[0..3] of string = ('Change received date', 'Change start date', 'Change due date', 'Change end date');
  Defaults: array[0..3] of string = ('now', 'now', '17:00', 'now');
var R: TWLRows; i, Mark: Integer; Line, Shown, Label_, Cls: string; Pieces: TSectionBodies; Places: TStringArray;
  // What was drawn since Mark is the piece Key: kept aside, put back in the
  // Minicard pane's order at the end.
  procedure Piece(const Key: string);
  begin
    PutSection(Pieces, Key, Copy(Result, Mark + 1, MaxInt));
    SetLength(Result, Mark);
  end;
begin
  Result := '';
  Pieces := nil;
  Mark := 0;
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
  Piece('labels');
  Line := '';
  for i := 0 to 3 do
    if Shows.Dates[i] and (Dates[i] <> '') then
    begin
      Label_ := Words.Text('card-' + Kinds[i], Captions[i]);
      Shown := FormatShownDate(Dates[i], ViewDateFormat);
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
  Piece('dates');
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
  Piece('members');
  // WeKan's minicard assignees: an avatar each, their name its title.
  if Shows.Assignees then
  begin
    R := Db.Query('SELECT COALESCE(NULLIF(CASE WHEN json_valid(u.profile_json) THEN json_extract(u.profile_json,''$.fullname'') END,''''),u.username),' +
      'COALESCE(CASE WHEN json_valid(u.profile_json) THEN json_extract(u.profile_json,''$.initials'') END,'''') ' +
      'FROM card_assignees c JOIN users u ON u.id=c.userId WHERE c.cardId=' + QuotedStr(CardId) + ' ORDER BY u.username;');
    if Length(R) > 0 then
    begin
      Result := Result + '<div class="minicard-assignees js-minicard-assignees">';
      for i := 0 to High(R) do
        Result := Result + '<span class="member" title="' + HtmlAttr(R[i][0]) + '">' + E(PersonInitials(R[i][1], R[i][0])) + '</span>';
      Result := Result + '</div>';
    end;
  end;
  Piece('assignees');
  // Requested By, its location, its last activity and the description's
  // badge, as Card Settings shows them on the minicard (board.pug).
  // Extra, from the board's cards query: requestedBy, description,
  // dateLastActivity, locationName, the locations.
  if Length(Extra) = 5 then
  begin
    SetLength(R, 1);
    SetLength(R[0], 5);
    for i := 0 to 4 do R[0][i] := Extra[i];
    if Shows.RequestedBy and (R[0][0] <> '') then
      Result := Result + '<div class="minicard-requested-by" title="' + HtmlAttr(Words.Text('requested-by', 'Requested By')) +
        '"><i class="fa fa-shopping-cart"></i><span>' + E(R[0][0]) + '</span></div>';
    Piece('requestedBy');
    if Shows.Location then
    begin
      Places := LocationNames(R[0][4], R[0][3]);
      for i := 0 to High(Places) do
        Result := Result + '<div class="minicard-location"><i class="fa fa-map-marker"></i>' + E(Places[i]) + '</div>';
    end;
    Piece('location');
    if Shows.LastActivity and (R[0][2] <> '') then
      Result := Result + '<div class="minicard-last-activity" title="' + HtmlAttr(Words.Text('activities', 'Activities')) +
        '"><i class="fa fa-history"></i>' + E(FormatShownDate(R[0][2], ViewDateFormat)) + '</div>';
    Piece('activities');
    if Shows.DescriptionBadge and (Trim(R[0][1]) <> '') then
      Result := Result + '<div class="badge badge-state-image-only" title="' + HtmlAttr(R[0][1]) +
        '"><span class="badge-icon"><i class="fa fa-file-text-o"></i></span></div>';
    Piece('descriptionBadge');
  end;
  // Its newest three comments, each cut at 140 characters, each on a line
  // of its own (the 2026-10-08 report).
  if Shows.Comments then
  begin
    R := Db.Query('SELECT text FROM card_comments WHERE boardId=' + QuotedStr(BoardId) + ' AND cardId=' + QuotedStr(CardId) +
      ' ORDER BY createdAt DESC LIMIT 3;');
    if Length(R) > 0 then
    begin
      Result := Result + '<div class="minicard-comments">';
      for i := 0 to High(R) do
      begin
        Shown := R[i][0];
        if Length(UTF8Decode(Shown)) > 140 then Shown := UTF8Encode(Copy(UTF8Decode(Shown), 1, 140)) + '…';
        Result := Result + '<div class="minicard-comment"><span class="minicard-comment-icon"><i class="fa fa-comment-o"></i></span>' +
          '<span class="minicard-comment-text">' + E(Shown) + '</span></div>';
      end;
      Result := Result + '</div>';
    end;
  end;
  Piece('comments');
  // The Minicard pane's order (wlcardst): its sections, its rows.
  if Length(ViewMinicardPieces) = 0 then ViewMinicardPieces := MinicardPieceOrder(nil, '');
  for i := 0 to High(ViewMinicardPieces) do Result := Result + SectionOf(Pieces, ViewMinicardPieces[i]);
end;

// The width a list is drawn at for the user, in Weddy's (WeKan's) order: the
// user's own same width for the board while it is on (220 without one), the
// user's personal width while the board allows them; 0 for the stylesheet's.
function ListWidthOf(Db: TWLDb; const UserId, BoardId, ListId: string): Integer;
var R: TWLRows; W: Double;
  function Valid(const V: string; out N: Double): Boolean;
  begin
    N := StrToFloatDef(V, -1, DefaultFormatSettings);
    Result := (N >= 200) and (N <= 1000);
  end;
begin
  Result := 0;
  if (UserId = '') or (Pos('"', BoardId + ListId) > 0) or (Pos(#0, BoardId + ListId) > 0) then Exit;
  R := Db.Query('SELECT json_extract(profile_json,''$.fixedListWidthBoards."' + BoardId + '"''),' +
    'json_extract(profile_json,''$.fixedListWidths."' + BoardId + '"''),json_extract(profile_json,''$.listWidths."' + BoardId + '"."' + ListId + '"'') ' +
    'FROM users WHERE id=' + QuotedStr(UserId) + ' AND json_valid(profile_json);');
  if Length(R) <> 1 then Exit;
  if R[0][0] = '1' then
  begin
    if Valid(R[0][1], W) then Exit(Round(W));
    Exit(220);
  end;
  if BoardSettingFlag(Db, BoardId, 'allowsPersonalListWidth', False) and Valid(R[0][2], W) then Result := Round(W);
end;

function VisibilityButton(Words: TWLTranslator; const BoardId, Permission: string): string;
const Values: array[0..2] of string = ('private', 'instance', 'public');
  Icons: array[0..2] of string = ('fa-lock', 'fa-users', 'fa-globe');
  Captions: array[0..2] of string = ('Private', 'Signed-in users', 'Public');
var i, At: Integer;
begin
  At := 0;
  for i := 0 to 2 do if Values[i] = Permission then At := i;
  Result := '<a class="board-header-btn js-change-visibility" href="#" title="' + HtmlAttr(Words.Text(Values[At], Captions[At])) +
    '"><i class="fa ' + Icons[At] + '"></i><span class="board-header-btn-label">' + E(Words.Text(Values[At], Captions[At])) + '</span></a>' +
    '<template class="js-pop-over-template" data-pop="visibility" data-title="' +
    HtmlAttr(Words.Text('boardChangeVisibilityPopup-title', 'Change Visibility')) + '"><ul class="pop-over-list described-list">';
  for i := 0 to 2 do
    Result := Result + '<li><form method="post" action="/b/' + HtmlAttr(HTTPEncode(BoardId)) + '/visibility"><input type="hidden" name="visibility" value="' +
      Values[i] + '"><button class="js-select-visibility" type="submit"><i class="fa ' + Icons[i] + '"></i> ' + E(Words.Text(Values[i], Captions[i])) +
      '<span class="sub-name">' + E(Words.Text(Values[i] + '-desc', '')) + '</span></button></form></li>';
  Result := Result + '</ul></template>';
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
    ' AND type IN (''image/png'',''image/jpeg'',''image/gif'',''image/webp'',''image/svg+xml'') AND ' + LiveAttachmentSQL(Db) + ';')) <> 1 then Exit;
  Result := ' style="background-image: url(' + Prefix + Id + '); background-size: cover;"';
end;

threadvar
  // WeKan's mobile view for this request (body.mobile-mode, as weddy.js
  // decides it, told in the welite-mobile cookie), and its Session
  // currentList as list:swimlane (the welite-list cookie).
  BoardMobile: Boolean;
  BoardCurrentList, BoardCurrentLane: string;

// The request's mobile view and current list, from welite.js's cookies.
procedure ReadBoardView(Request: TRequest);
var V: string; At: Integer;
begin
  BoardMobile := Request.CookieFields.Values['welite-mobile'] = '1';
  V := HTTPDecode(Request.CookieFields.Values['welite-list']);
  At := Pos(':', V);
  if (At > 1) and (Length(V) <= 200) and (Pos(#0, V) = 0) then
  begin
    BoardCurrentList := Copy(V, 1, At - 1); BoardCurrentLane := Copy(V, At + 1, MaxInt);
  end
  else begin BoardCurrentList := ''; BoardCurrentLane := ''; end;
end;

type
  TCardSection = record Id, Icon, Key, Fallback: string; Header: Boolean; end;


const
  // WeKan's cardSettingsSections.js SECTIONS, in the Card pane's default
  // order: each section's icon and title. Header: drawn with its heading here
  // - the others open with a title of their own (Labels, Members, ...) or fold
  // under their own (custom fields, vote, attachments), as Weddy's
  // card_sections.go has it.
  CARD_SECTIONS: array[0..13] of TCardSection = (
    (Id: 'labels'; Icon: 'fa-tag'; Key: 'labels'; Fallback: 'Labels'; Header: False),
    (Id: 'date'; Icon: 'fa-calendar'; Key: 'date'; Fallback: 'Date'; Header: True),
    (Id: 'members'; Icon: 'fa-users'; Key: 'members'; Fallback: 'Members'; Header: False),
    (Id: 'card'; Icon: 'fa-id-card-o'; Key: 'card'; Fallback: 'Card'; Header: True),
    (Id: 'time'; Icon: 'fa-clock-o'; Key: 'time'; Fallback: 'Time'; Header: True),
    (Id: 'customFields'; Icon: 'fa-list-alt'; Key: 'custom-fields'; Fallback: 'Custom Fields'; Header: False),
    (Id: 'vote'; Icon: 'fa-thumbs-up'; Key: 'vote-question'; Fallback: 'Vote'; Header: False),
    (Id: 'poker'; Icon: 'fa-check-square'; Key: 'poker-question'; Fallback: 'Planning Poker'; Header: False),
    (Id: 'description'; Icon: 'fa-file-text-o'; Key: 'description'; Fallback: 'Description'; Header: False),
    (Id: 'scrum'; Icon: 'fa-repeat'; Key: 'scrum-settings'; Fallback: 'Scrum'; Header: True),
    (Id: 'checklists'; Icon: 'fa-check'; Key: 'checklists'; Fallback: 'Checklists'; Header: False),
    (Id: 'subtasks'; Icon: 'fa-sitemap'; Key: 'subtasks'; Fallback: 'Subtasks'; Header: False),
    (Id: 'attachments'; Icon: 'fa-paperclip'; Key: 'attachments'; Fallback: 'Attachments'; Header: False),
    (Id: 'comments'; Icon: 'fa-comment-o'; Key: 'comments'; Fallback: 'Comments'; Header: False));

// WeKan's sectionOrder(stored, 'card'): the board's stored ids that are known,
// once each, then the rest in the default order.
function CardSectionOrder(Db: TWLDb; const BoardId: string): TStringArray;
var R: TWLRows; i, n: Integer; L: TStringArray;
  function Known(const Id: string): Boolean;
  var k: Integer;
  begin
    for k := 0 to High(CARD_SECTIONS) do if CARD_SECTIONS[k].Id = Id then Exit(True);
    Result := False;
  end;
  function Has(const Id: string): Boolean;
  var k: Integer;
  begin
    for k := 0 to n - 1 do if L[k] = Id then Exit(True);
    Result := False;
  end;
begin
  SetLength(L, Length(CARD_SECTIONS));
  n := 0;
  R := Db.Query('SELECT j.value FROM boards b, json_each(CASE WHEN json_valid(b.settings_json) AND ' +
    'json_type(b.settings_json,''$.cardSettingsSectionOrder'')=''array'' THEN json_extract(b.settings_json,''$.cardSettingsSectionOrder'') ' +
    'ELSE ''[]'' END) j WHERE b.id=' + QuotedStr(BoardId) + ' AND j.type=''text'' ORDER BY j.key;');
  for i := 0 to High(R) do
    if Known(R[i][0]) and not Has(R[i][0]) then begin L[n] := R[i][0]; Inc(n); end;
  for i := 0 to High(CARD_SECTIONS) do
    if not Has(CARD_SECTIONS[i].Id) then begin L[n] := CARD_SECTIONS[i].Id; Inc(n); end;
  SetLength(L, n);
  Result := L;
end;

// The sections Card Settings hides on the card (cardSettingsHiddenOnCard).
function CardSectionHidden(Db: TWLDb; const BoardId, Id: string): Boolean;
begin
  Result := Length(Db.Query('SELECT 1 FROM boards b, json_each(CASE WHEN json_valid(b.settings_json) AND ' +
    'json_type(b.settings_json,''$.cardSettingsHiddenOnCard'')=''array'' THEN json_extract(b.settings_json,''$.cardSettingsHiddenOnCard'') ' +
    'ELSE ''[]'' END) j WHERE b.id=' + QuotedStr(BoardId) + ' AND j.value=' + QuotedStr(Id) + ';')) > 0;
end;

// cardDetails.jade's .card-details-items: each section this card has
// something for, in the Card pane's order, headed where it has no heading of
// its own. Bodies holds each section's content by its id ('' for none).
function CardSectionsHtml(Db: TWLDb; Words: TWLTranslator; const BoardId: string; const Bodies: TSectionBodies): string;
var Order: TStringArray; i, k: Integer; Body: string;
begin
  Result := '<div class="card-details-left"><div class="card-details-items">';
  Order := CardSectionOrder(Db, BoardId);
  for i := 0 to High(Order) do
  begin
    Body := SectionOf(Bodies, Order[i]);
    // Card is there on every card: its heading is the card's own place.
    if ((Body = '') and (Order[i] <> 'card')) or CardSectionHidden(Db, BoardId, Order[i]) then Continue;
    for k := 0 to High(CARD_SECTIONS) do
      if CARD_SECTIONS[k].Id = Order[i] then
      begin
        Result := Result + '<div class="card-details-section card-details-section-' + Order[i] + '" data-card-section="' + Order[i] + '">';
        if CARD_SECTIONS[k].Header then
          Result := Result + '<h3 class="card-details-item-title js-toggle-card-section" data-section="' + Order[i] +
            '" role="button" tabindex="0"><i class="fa ' + CARD_SECTIONS[k].Icon + '" aria-hidden="true"></i> ' +
            E(Words.Text(CARD_SECTIONS[k].Key, CARD_SECTIONS[k].Fallback)) + '</h3>';
        Result := Result + '<div class="card-details-section-body">' + Body + '</div></div>';
      end;
  end;
  Result := Result + '</div></div>';
end;

function BoardContent(Db: TWLDb; const S: TWLSession; Words: TWLTranslator; const BoardId, CardId: string;
  out BoardTitle: string; out Found: Boolean; Query: TStrings = nil): string;
var B, Lanes, Lists, Cards, Card: TWLRows; i, j, k: Integer; Route, Canvas, Details, Composer: string;
  Selector: TSelectionScope; Writable, Maximized, TextEditor, CanCreateLabel, BoardDates, Folded, ListFolded: Boolean;
  Width: Integer; PlainLinks, PlainSource, LaneHasCurrent: Boolean;
  Shows: TMinicardShows; Header, FilterCond, CardSort, SortSql: string; Filter: TBoardFilter; Sections: TSectionBodies; CardCollapse, CardCollapsed: Boolean;
begin
  Result := ''; BoardTitle := ''; Found := False;
  if (BoardId = '') or (Pos(#0, BoardId + CardId) > 0) then Exit;
  if not BoardCanRead(Db, S.UserId, BoardId) then Exit;
  B := Db.Query('SELECT title,color,slug,COALESCE(backgroundImageURL,''''),COALESCE(permission,''private'') FROM boards WHERE id=' + QuotedStr(BoardId) + ' AND archived=0 LIMIT 1;');
  if Length(B) <> 1 then Exit;
  BoardTitle := B[0][0];
  ViewDateFormat := ViewDateFor(Db, S.UserId, BoardId);
  ViewBoardId := BoardId;
  ViewMinicardPieces := MinicardPieceOrder(Db, BoardId);
  ViewCardDates := CardDateOrder(Db, BoardId);
  Route := BoardRoute(BoardId, B[0][2]);
  Writable := (S.UserId <> '') and BoardCanWrite(Db, S.UserId, BoardId);
  BoardDates := Writable and BoardCanEditCardText(Db, S.UserId, BoardId);
  Shows := MinicardShows(Db, BoardId, BoardDates);
  // Admin Panel's text display, for every viewer on the page.
  PlainLinks := SharedSettingOn(Db, 'renderLinksAsPlainText');
  PlainSource := SharedSettingOn(Db, 'alwaysShowCodeAsText');
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
    // WeKan's mobile view (swimlanes.jade, isMiniScreen): the current list
    // opened inside its own swimlane, every other list of a swimlane a
    // compact row (miniList) that opens it.
    LaneHasCurrent := False;
    if BoardMobile and (BoardCurrentList <> '') and (BoardCurrentLane = Lanes[i][0]) then
      for j := 0 to High(Lists) do if Lists[j][0] = BoardCurrentList then LaneHasCurrent := True;
    for j := 0 to High(Lists) do
    begin
      if BoardMobile and LaneHasCurrent and (Lists[j][0] <> BoardCurrentList) then Continue;
      if BoardMobile and not LaneHasCurrent then
      begin
        Canvas := Canvas + '<a class="mini-list js-select-list js-list mobile-view" id="js-list-' + HtmlAttr(Lists[j][0]) +
          '" href="#" data-list="' + HtmlAttr(Lists[j][0]) + '" data-swimlane="' + HtmlAttr(Lanes[i][0]) +
          '"><div class="list-header"><span class="list-header-name">' + E(Lists[j][1]) + '</span></div></a>';
        Continue;
      end;
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
      Width := ListWidthOf(Db, S.UserId, BoardId, Lists[j][0]);
      Canvas := Canvas + '<div class="list js-list' + IfThen(ListFolded, ' list-collapsed', '') + IfThen(BoardMobile, ' mobile-view', '') +
        '" id="js-list-' + HtmlAttr(Lists[j][0]) +
        '" data-list="' + HtmlAttr(Lists[j][0]) + '" data-swimlane="' + HtmlAttr(Lanes[i][0]) + '"' +
        IfThen((Width > 0) and not ListFolded, ' style="--list-width:' + IntToStr(Width) + 'px;"', '') + '><div class="list-header">' +
        IfThen(S.UserId <> '', '<a class="list-collapse-indicator js-collapse" href="#" data-collapse="' + HtmlAttr(Words.Text('collapse', 'Collapse')) +
          '" data-uncollapse="' + HtmlAttr(Words.Text('uncollapse', 'Uncollapse')) + '" title="' +
          HtmlAttr(IfThen(ListFolded, Words.Text('uncollapse', 'Uncollapse'), Words.Text('collapse', 'Collapse'))) + '" aria-label="' +
          HtmlAttr(IfThen(ListFolded, Words.Text('uncollapse', 'Uncollapse'), Words.Text('collapse', 'Collapse'))) + '"><i class="fa ' +
          IfThen(ListFolded, 'fa-caret-right', 'fa-caret-down') + '"></i></a>', '') +
        '<span class="list-header-name">' + E(Lists[j][1]) + '</span>' + Composer + '</div>' +
        '<div class="list-body js-minicards" data-list="' + HtmlAttr(Lists[j][0]) + '" data-swimlane="' + HtmlAttr(Lanes[i][0]) + '">';
      Cards := Db.Query('SELECT c.id,c.title,c.sort,COALESCE(c.receivedAt,''''),COALESCE(c.startAt,''''),' +
        'COALESCE(c.dueAt,''''),COALESCE(c.endAt,''''),COALESCE((SELECT attachments.id FROM attachments WHERE attachments.id=c.coverId AND ' +
        'attachments.cardId=c.id AND attachments.type IN (''image/png'',''image/jpeg'',''image/gif'',''image/webp'',''image/svg+xml'') AND ' +
        // LiveAttachmentSQL names the table attachments, unaliased.
        LiveAttachmentSQL(Db) + '),''''),COALESCE(c.dueComplete,0),COALESCE(c.color,''''),' +
        // The minicard's Card Settings sides (MinicardBadges' Extra).
        'COALESCE(c.requestedBy,''''),COALESCE(c.description,''''),COALESCE(c.dateLastActivity,''''),COALESCE(c.locationName,''''),' +
        'CASE WHEN json_valid(c.extra_json) AND json_type(c.extra_json,''$.locations'')=''array'' THEN ' +
        'json_extract(c.extra_json,''$.locations'') ELSE ''[]'' END FROM cards c WHERE c.boardId=' + QuotedStr(BoardId) +
        ' AND c.swimlaneId=' + QuotedStr(Lanes[i][0]) + ' AND c.listId=' + QuotedStr(Lists[j][0]) +
        ' AND c.archived=0 AND c.deletedAt IS NULL' + FilterCond + ' ORDER BY ' + SortSql + 'c.sort,c.id;');
      for k := 0 to High(Cards) do
        // A block that opens the card, as Weddy's and WeKan's minicard.
        Canvas := Canvas + '<div class="minicard-wrapper js-minicard" up-href="' +
          HtmlAttr(CardRoute(BoardId, B[0][2], Cards[k][0])) + '" up-follow up-clickable up-target=".board-wrapper" data-card="' +
          HtmlAttr(Cards[k][0]) + '" data-card-id="' + HtmlAttr(Cards[k][0]) + '" data-sort="' + HtmlAttr(Cards[k][2]) +
          // Card colour, Show on Minicard (WeKan's minicard-<color>).
          '"><div class="minicard' + IfThen(Shows.CardColor and ColorName(Cards[k][9]), ' minicard-' + Cards[k][9], '') + '">' +
          // WeKan's minicard cover: the card's cover image.
          IfThen(Cards[k][7] <> '', '<div class="minicard-cover"><img src="/cdn/storage/attachments/' + HtmlAttr(HTTPEncode(Cards[k][7])) +
            '" alt="" loading="lazy"></div>', '') + '<div class="minicard-title">' +
          // WeKan's "Mark as complete" on the minicard, when Card Settings shows it there.
          IfThen(Shows.Complete, '<a class="minicard-complete-toggle js-toggle-card-complete" href="#" data-card="' + HtmlAttr(Cards[k][0]) +
            '" data-complete="' + IfThen(Cards[k][8] = '1', 'false', 'true') + '" title="' +
            HtmlAttr(IfThen(Cards[k][8] = '1', Words.Text('card-mark-incomplete', 'Mark as incomplete'), Words.Text('card-mark-complete', 'Mark as complete'))) +
            '"><div class="materialCheckBox' + IfThen(Cards[k][8] = '1', ' is-checked', '') + '"></div></a>', '') +
          '<span class="minicard-title-text">' +
          MarkdownViewer(Cards[k][1], PlainLinks, PlainSource) + '</span></div>' + MinicardBadges(Db, Words, BoardId, Cards[k][0], Shows,
          [Cards[k][3], Cards[k][4], Cards[k][5], Cards[k][6]],
          [Cards[k][10], Cards[k][11], Cards[k][12], Cards[k][13], Cards[k][14]]) + '</div></div>';
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
        'COALESCE(startAt,''''),COALESCE(dueAt,''''),COALESCE(endAt,''''),swimlaneId,listId,COALESCE(color,'''') FROM cards WHERE id=' + QuotedStr(CardId) + ' AND boardId=' +
        QuotedStr(BoardId) + ' AND archived=0 AND deletedAt IS NULL AND ' + Selector.StringField('cards', 'id') +
        ' AND ' + Selector.StringField('cards', 'boardId') + ';');
    finally
      Selector.Free;
    end;
    if Length(Card) <> 1 then Exit;
    Maximized := ProfileFlag(Db, S.UserId, 'cardMaximized');
    // Card Settings' card sides: the caret folding the card's details (the
    // user's own fold), the header's colour, the description's badge.
    CardCollapse := BoardSettingFlag(Db, BoardId, 'allowsCardCollapse', True);
    CardCollapsed := CardCollapse and ProfileFlag(Db, S.UserId, 'cardCollapsed');
    Details := '<div class="card-details js-card-details' + IfThen(Maximized, ' card-details-maximized', '') +
      IfThen(CardCollapsed, ' card-details-collapsed', '') + '" data-card="' + HtmlAttr(CardId) + '">' +
      '<div class="card-details-header' + IfThen(BoardSettingFlag(Db, BoardId, 'allowsCardColorOnCard', True) and ColorName(Card[0][10]),
        ' card-details-' + Card[0][10], '') + '">' +
      IfThen(CardCollapse and (S.UserId <> ''), '<a class="card-collapse-toggle js-card-collapse-toggle" href="#" data-collapsed="' +
        IfThen(CardCollapsed, 'true', '') + '" title="' + HtmlAttr(Words.Text('collapse', 'Collapse')) + '" aria-label="' +
        HtmlAttr(Words.Text('collapse', 'Collapse')) + '"><i class="fa ' + IfThen(CardCollapsed, 'fa-caret-right', 'fa-caret-down') +
        '"></i></a>', '') + '<h2 class="card-details-title js-card-title">' +
      '<span class="card-details-title-edit-zone js-open-inlined-form">' + MarkdownViewer(Card[0][0], PlainLinks, PlainSource) + '</span></h2>' +
      IfThen(BoardSettingFlag(Db, BoardId, 'allowsDescriptionBadgeOnCard', False) and (Trim(Card[0][1]) <> ''),
        '<i class="fa fa-file-text-o card-details-description-badge" title="' + HtmlAttr(Words.Text('description', 'Description')) + '"></i>', '');
    // board.pug: the title's editor, opened by its leading part (weddy.js).
    if Writable then
      Details := Details + '<form class="js-card-details-title js-inlined-form is-hidden" method="post" action="/b/' +
        HtmlAttr(HTTPEncode(BoardId)) + '/cards/' + HtmlAttr(HTTPEncode(CardId)) + '/title" up-submit up-target=".board-wrapper">' +
        // A title may be cleared, as in WeKan's card details (History keeps it).
        '<textarea class="js-edit-card-title" name="title" rows="2" dir="auto" aria-label="' + HtmlAttr(Words.Text('title', 'Title')) +
        '">' + E(Card[0][0]) + '</textarea><button class="primary" type="submit">' + E(Words.Text('save', 'Save')) +
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
    // WeKan's cardButtons: the board's card button rules.
    if Writable then Details := Details + RuleButtonsHtml(Db, BoardId, 'card', Words);
    // WeKan's one section model (cardDetails.jade): each section's content,
    // drawn in the Card pane's order (CardSectionsHtml).
    TextEditor := Writable and BoardCanEditCardText(Db, S.UserId, BoardId);
    CanCreateLabel := Writable and BoardCanCreateLabel(Db, S.UserId, BoardId);
    Sections := nil;
    PutSection(Sections, 'card', ListPickerSection(Db, Words, BoardId, CardId, Card[0][8], Card[0][9], Writable));
    // Swimlane, Show on Card: the swimlane the card is in.
    if BoardSettingFlag(Db, BoardId, 'allowsSwimlaneNameOnCard', False) then
    begin
      Lists := Db.Query('SELECT title FROM swimlanes WHERE id=' + QuotedStr(Card[0][8]) + ' AND boardId=' + QuotedStr(BoardId) + ';');
      if Length(Lists) = 1 then
        PutSection(Sections, 'card', '<div class="card-details-item card-details-swimlane-name"><h3 class="card-details-item-title">' +
          '<i class="fa fa-list-alt"></i> ' + E(Words.Text('swimlane', 'Swimlane')) + '</h3>' + E(Lists[0][0]) + '</div>');
    end;
    if BoardAllows(Db, BoardId, 'allowsLabels') then
      PutSection(Sections, 'labels', LabelsSection(Db, Words, BoardId, CardId, Writable));
    if BoardAllows(Db, BoardId, 'allowsMembers') then
      PutSection(Sections, 'members', MembersSection(Db, Words, CardId, Writable));
    PutSection(Sections, 'members', PeopleSection(Db, Words, BoardId, CardId, Card[0][2], Card[0][3], TextEditor));
    PutSection(Sections, 'date', DatesSection(Db, Words, BoardId, CardId, [Card[0][4], Card[0][5], Card[0][6], Card[0][7]], TextEditor));
    PutSection(Sections, 'description', DescriptionSection(Db, Words, BoardId, CardId, Card[0][1], TextEditor));
    PutSection(Sections, 'vote', VoteSection(Db, Words, S.UserId, BoardId, CardId));
    PutSection(Sections, 'poker', PokerSection(Db, Words, S.UserId, BoardId, CardId));
    PutSection(Sections, 'customFields', CustomFieldsSection(Db, Words, S, BoardId, CardId, Writable));
    PutSection(Sections, 'attachments', AttachmentsSection(Db, Words, BoardId, CardId, Writable, Writable and BoardCanAdmin(Db, S.UserId, BoardId)));
    PutSection(Sections, 'checklists', ChecklistsSection(Db, Words, BoardId, CardId, Writable));
    PutSection(Sections, 'comments', CommentsSection(Db, Words, BoardId, CardId, (S.UserId <> '') and BoardCanComment(Db, S.UserId, BoardId)));
    Details := Details + CardSectionsHtml(Db, Words, BoardId, Sections);
    Details := Details +
      // The card's activities, opened by their heading.
      '<h3 class="card-details-item-title js-toggle-card-section" data-section="activities" role="button" tabindex="0">' +
      '<i class="fa fa-caret-right"></i> ' + E(Words.Text('activities', 'Activities')) + '</h3>' +
      '<div class="card-details-section js-card-section is-hidden" data-section="activities"><div class="activities js-card-activities">' +
      ActivityRows(Db, Words, BoardId, CardId, 100) + '</div></div></div>';
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
      E(Words.Text('add-card-to-bottom-of-list', 'Add card to bottom of list')) + '</a></li>' +
      '<li><a class="js-select-cards" href="#">' + E(Words.Text('list-select-cards', 'Select all cards in this list')) + '</a></li></ul></template>';
  Result := '<div class="board-wrapper board-color-' + HtmlAttr(B[0][1]) + '"' + BackgroundStyle(Db, BoardId, B[0][3]) +
    ' data-board="' + HtmlAttr(BoardId) + '" data-live="/b/' + HtmlAttr(HTTPEncode(BoardId)) + '/live?v=1">' +
    '<div class="board-header"><h1 class="header-board-name js-board-title">' + E(BoardTitle) + '</h1>' +
    BoardStarButton(Db, Words, S, BoardId) + BoardWatchButton(Db, Words, S, BoardId) +
    // WeKan's boardButtons: the board's button rules, for whoever may change it.
    IfThen((S.UserId <> '') and BoardCanWrite(Db, S.UserId, BoardId), RuleButtonsHtml(Db, BoardId, 'board', Words), '') +
    FilterButton(Words, Filter) + SortButton(Words, CardSort) +
    // WeKan's visibility button and boardVisibilityList, for a board admin.
    IfThen((S.UserId <> '') and BoardCanAdmin(Db, S.UserId, BoardId), VisibilityButton(Words, BoardId, B[0][4]), '') +
    // WeKan's Multi-Selection: select cards, then act on all of them.
    IfThen(Writable, '<a class="board-header-btn js-multiselection-activate" href="#" title="' +
      HtmlAttr(Words.Text('multi-selection', 'Multi-Selection')) + '" aria-label="' + HtmlAttr(Words.Text('multi-selection', 'Multi-Selection')) +
      '">&#9745;</a>', '') + '</div>' +
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
  SendResponse(Response);
end;

procedure SendJsonAnswer(Response: TResponse; Code: Integer; const Json: string);
begin
  Response.Code := Code;
  Response.ContentType := 'application/json; charset=utf-8';
  Response.SetCustomHeader('Cache-Control', 'no-store');
  Response.Content := Json;
  Response.ContentLength := Length(Response.Content);
  SendResponse(Response);
end;

// weddy.js's callAsync(name, ...args): POST /_methods/<name> with the
// arguments as a JSON array, answered {"result": ...} or, as Meteor answers a
// method error, {"error": code, "reason": text}. The methods are WeKan's
// Meteor methods of the same name, each with WeKan's own meaning.
// A key of a profile map (assertSafeMapKey): letters, digits, '-', '_', ':'.
function ProfileMapKey(const Key: string): Boolean;
var i: Integer;
begin
  Result := (Key <> '') and (Length(Key) <= 200) and (Key <> '__proto__') and (Key <> 'constructor') and (Key <> 'prototype');
  for i := 1 to Length(Key) do
    if not (Key[i] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', ':']) then Exit(False);
end;

// Board Settings / Card's writes (weddy.js): the board's fields through
// /boards/update, the user's own through /users/update, setShowLabelTextOverride
// and setCollapsedCardSection, a custom field's through /customFields/update.
// 200, or a Meteor error's code and reason.
function CardSettingsMethod(const T: TWLTenant; const UserId, Name: string; Args: TJSONArray; out Error: string): Integer;
var Selector, Modifier, Clean, SetPart: TJSONObject; BoardId, Sql, Profile, Path, Id, Cols, Deposit: string; i: Integer; V: TJSONData;
  R: TWLRows; Refused: Boolean;
begin
  Error := 'Match failed';
  Result := 400;
  if Name = '/boards/update' then
  begin
    if (Args.Count <> 2) or not (Args.Items[0] is TJSONObject) or not (Args.Items[1] is TJSONObject) then Exit;
    Selector := TJSONObject(Args.Items[0]); Modifier := TJSONObject(Args.Items[1]);
    BoardId := Selector.Get('_id', '');
    if (Selector.Count <> 1) or (BoardId = '') or (Modifier.Count <> 1) or not (Modifier.Find('$set') is TJSONObject) then Exit;
    if not BoardOwnAdmin(T.Db, UserId, BoardId) then
    begin
      if Length(T.Db.Query('SELECT 1 FROM boards WHERE id=' + QuotedStr(BoardId) + ';')) = 1 then
        try
          RecordSecurityEvent(T.Db, UserId, 'AuthBleed', 'method:/boards/update', 'authz', 'high', 'CWE-862', 'blocked',
            'Board settings change refused: not an admin of the board');
        except
          // logging must never break the guard
        end;
      Error := 'Access denied'; Exit(403);
    end;
    if not CardSettingsBoardWrite(TJSONObject(Modifier.Find('$set')), Clean) then
    begin Clean.Free; Error := 'Access denied'; Exit(403); end;
    try
      // Subtasks Settings' deposit: a board the caller may write, a landing
      // list on the subtasks board (SubtaskDepositBleed). A new board resets
      // the list and swimlane: they were the old board's.
      if Clean.Find('subtasksDefaultBoardId') <> nil then
      begin
        if Clean.Find('subtasksDefaultListId') = nil then Clean.Add('subtasksDefaultListId', TJSONNull.Create);
        if Clean.Find('subtasksDefaultSwimlaneId') = nil then Clean.Add('subtasksDefaultSwimlaneId', TJSONNull.Create);
        if Clean.Find('subtasksDefaultBoardId').JSONType = jtString then Deposit := Clean.Strings['subtasksDefaultBoardId'] else Deposit := '';
      end
      else
      begin
        R := T.Db.Query('SELECT COALESCE(subtasksDefaultBoardId,'''') FROM boards WHERE id=' + QuotedStr(BoardId) + ';');
        if Length(R) = 1 then Deposit := R[0][0] else Deposit := '';
      end;
      if Deposit = 'null' then Deposit := '';
      Refused := (Clean.Find('subtasksDefaultBoardId') <> nil) and (Deposit <> '') and (Deposit <> BoardId) and
        not BoardCanWrite(T.Db, UserId, Deposit);
      if Deposit = '' then Deposit := BoardId;
      if not Refused and (Clean.Find('subtasksDefaultListId') <> nil) and (Clean.Find('subtasksDefaultListId').JSONType = jtString) then
        Refused := Length(T.Db.Query('SELECT 1 FROM lists WHERE id=' + QuotedStr(Clean.Strings['subtasksDefaultListId']) +
          ' AND boardId=' + QuotedStr(Deposit) + ';')) = 0;
      if not Refused and (Clean.Find('subtasksDefaultSwimlaneId') <> nil) and (Clean.Find('subtasksDefaultSwimlaneId').JSONType = jtString) then
        Refused := Length(T.Db.Query('SELECT 1 FROM swimlanes WHERE id=' + QuotedStr(Clean.Strings['subtasksDefaultSwimlaneId']) +
          ' AND boardId=' + QuotedStr(Deposit) + ';')) = 0;
      if Refused then
      begin
        try
          RecordSecurityEvent(T.Db, UserId, 'SubtaskDepositBleed', 'method:/boards/update', 'authz', 'high', 'CWE-639', 'blocked',
            'Subtasks board or landing place the caller may not use refused');
        except
          // logging must never break the guard
        end;
        Error := 'Access denied'; Exit(403);
      end;
      Sql := 'CASE WHEN json_valid(settings_json) THEN settings_json ELSE ''{}'' END';
      Cols := '';
      for i := 0 to Clean.Count - 1 do
        // presentParentTask is a column of its own; the rest are the board's
        // fields kept in settings_json.
        if Clean.Names[i] = 'presentParentTask' then Cols := Cols + ',presentParentTask=' + QuotedStr(Clean.Items[i].AsString)
        else if (Clean.Names[i] = 'subtasksDefaultBoardId') or (Clean.Names[i] = 'subtasksDefaultListId') then
        begin
          if Clean.Items[i].JSONType = jtNull then Cols := Cols + ',' + Clean.Names[i] + '=NULL'
          else Cols := Cols + ',' + Clean.Names[i] + '=' + QuotedStr(Clean.Items[i].AsString);
        end
        else Sql := 'json_set(' + Sql + ',' + QuotedStr('$.' + Clean.Names[i]) + ',json(' + QuotedStr(Clean.Items[i].AsJSON) + '))';
      if not T.Db.Exec('UPDATE boards SET settings_json=' + Sql + Cols + ',modifiedAt=' +
        QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', LocalTimeToUniversal(Now))) + ' WHERE id=' + QuotedStr(BoardId) + ';') then
      begin Error := 'Could not save'; Exit(500); end;
    finally
      Clean.Free;
    end;
  end
  else if Name = '/users/update' then
  begin
    // The user's own Card Settings split and labels text override.
    if (Args.Count <> 2) or not (Args.Items[0] is TJSONObject) or not (Args.Items[1] is TJSONObject) then Exit;
    Selector := TJSONObject(Args.Items[0]); Modifier := TJSONObject(Args.Items[1]);
    if (Selector.Count <> 1) or (Selector.Get('_id', '') <> UserId) then begin Error := 'Access denied'; Exit(403); end;
    if Modifier.Count <> 1 then Exit;
    Profile := 'CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END';
    SetPart := nil;
    if Modifier.Find('$set') is TJSONObject then SetPart := TJSONObject(Modifier.Find('$set'))
    else if Modifier.Find('$unset') is TJSONObject then SetPart := TJSONObject(Modifier.Find('$unset'))
    else begin Error := 'Access denied'; Exit(403); end;
    for i := 0 to SetPart.Count - 1 do
    begin
      Path := SetPart.Names[i]; V := SetPart.Items[i];
      if Modifier.Find('$unset') <> nil then
      begin
        if Path <> 'profile.cardLabelTextOverride' then begin Error := 'Access denied'; Exit(403); end;
        Profile := 'json_remove(' + Profile + ',''$.cardLabelTextOverride'')';
      end
      else if (Path = 'profile.cardSettingsSplit') and (V.JSONType = jtNumber) and (V.AsFloat >= 0) and (V.AsFloat <= 1) then
        Profile := 'json_set(' + Profile + ',''$.cardSettingsSplit'',json(' + QuotedStr(V.AsJSON) + '))'
      else if (Path = 'profile.cardLabelTextOverride') and (V.JSONType = jtBoolean) then
        Profile := 'json_set(' + Profile + ',''$.cardLabelTextOverride'',json(''' + IfThen(V.AsBoolean, 'true', 'false') + '''))'
      else
      begin Error := 'Access denied'; Exit(403); end;
    end;
    if not T.Db.Exec('UPDATE users SET profile_json=' + Profile + ' WHERE id=' + QuotedStr(UserId) + ';') then
    begin Error := 'Could not save'; Exit(500); end;
  end
  else if Name = 'setShowLabelTextOverride' then
  begin
    // [on]: shown or hidden for this user; null follows the board again.
    if Args.Count <> 1 then Exit;
    if Args.Items[0].JSONType = jtNull then Sql := 'json_remove(' + 'CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END' +
      ',''$.showLabelTextOverride'')'
    else if Args.Items[0].JSONType = jtBoolean then
      Sql := 'json_set(CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END,''$.showLabelTextOverride'',json(''' +
        IfThen(Args.Booleans[0], 'true', 'false') + '''))'
    else Exit;
    if not T.Db.Exec('UPDATE users SET profile_json=' + Sql + ' WHERE id=' + QuotedStr(UserId) + ';') then
    begin Error := 'Could not save'; Exit(500); end;
  end
  else if Name = 'setCollapsedCardSection' then
  begin
    // [id, sectionKey, collapsed]: the user's own fold (models/users.js).
    if (Args.Count <> 3) or (Args.Items[0].JSONType <> jtString) or (Args.Items[1].JSONType <> jtString) then Exit;
    if not ProfileMapKey(Args.Strings[0]) or not ProfileMapKey(Args.Strings[1]) then begin Error := 'Invalid map key'; Exit; end;
    Profile := 'CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END';
    Path := '$.collapsedCardSections."' + Args.Strings[0] + '"';
    if not T.Db.Exec('UPDATE users SET profile_json=json_set(json_set(json_set(' + Profile + ',''$.collapsedCardSections'',' +
      'json(COALESCE(json_extract(' + Profile + ',''$.collapsedCardSections''),''{}''))),' + QuotedStr(Path) + ',json(COALESCE(json_extract(' +
      Profile + ',' + QuotedStr(Path) + '),''{}''))),' + QuotedStr(Path + '."' + Args.Strings[1] + '"') + ',json(''' +
      IfThen((Args.Items[2].JSONType = jtBoolean) and Args.Booleans[2], 'true', 'false') + ''')) WHERE id=' + QuotedStr(UserId) + ';') then
    begin Error := 'Could not save'; Exit(500); end;
  end
  else if Name = 'setBoardDragging' then
  begin
    // [boardId, kind, enabled] (server/moveBoardObjects.js): whether the board
    // lets that kind be dragged, a board admin's or the site admin's.
    if (Args.Count <> 3) or (Args.Items[0].JSONType <> jtString) or (Args.Items[1].JSONType <> jtString) or
      (Args.Items[2].JSONType <> jtBoolean) then Exit;
    case Args.Strings[1] of
      'swimlane': Path := 'allowsSwimlaneDragging';
      'list': Path := 'allowsListDragging';
      'card': Path := 'allowsCardDragging';
      'checklist': Path := 'allowsChecklistDragging';
      'item': Path := 'allowsChecklistItemDragging';
      'subtask': Path := 'allowsSubtaskDragging';
    else begin Error := 'invalid-setting'; Exit(400); end;
    end;
    BoardId := Args.Strings[0];
    if not (BoardOwnAdmin(T.Db, UserId, BoardId) or IsSiteAdmin(T.Db, UserId)) or
      (Length(T.Db.Query('SELECT 1 FROM boards WHERE id=' + QuotedStr(BoardId) + ';')) <> 1) then
    begin Error := 'not-authorized'; Exit(403); end;
    if not T.Db.Exec('UPDATE boards SET settings_json=json_set(CASE WHEN json_valid(settings_json) THEN settings_json ELSE ''{}'' END,' +
      QuotedStr('$.' + Path) + ',json(''' + IfThen(Args.Booleans[2], 'true', 'false') + ''')),modifiedAt=' +
      QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', LocalTimeToUniversal(Now))) + ' WHERE id=' + QuotedStr(BoardId) + ';') then
    begin Error := 'Could not save'; Exit(500); end;
  end
  else if Name = '/customFields/update' then
  begin
    // [{_id}, {$set}]: a field's name and its four "on card" flags, for an
    // admin of every board it is on.
    if (Args.Count <> 2) or not (Args.Items[0] is TJSONObject) or not (Args.Items[1] is TJSONObject) then Exit;
    Id := TJSONObject(Args.Items[0]).Get('_id', '');
    Modifier := TJSONObject(Args.Items[1]);
    if (Id = '') or (Modifier.Count <> 1) or not (Modifier.Find('$set') is TJSONObject) then Exit;
    R := T.Db.Query('SELECT boardId FROM custom_field_boards WHERE customFieldId=' + QuotedStr(Id) + ';');
    if Length(R) = 0 then begin Error := 'Not found'; Exit(404); end;
    for i := 0 to High(R) do
      if not BoardOwnAdmin(T.Db, UserId, R[i][0]) then begin Error := 'Access denied'; Exit(403); end;
    SetPart := TJSONObject(Modifier.Find('$set'));
    Cols := '';
    for i := 0 to SetPart.Count - 1 do
    begin
      Path := SetPart.Names[i]; V := SetPart.Items[i];
      if (Path = 'name') and (V.JSONType = jtString) and (Trim(V.AsString) <> '') and (Length(V.AsString) <= 200) then
        Cols := Cols + ',name=' + QuotedStr(V.AsString)
      else if ((Path = 'showOnCard') or (Path = 'automaticallyOnCard') or (Path = 'alwaysOnCard') or (Path = 'showLabelOnMiniCard')) and
        (V.JSONType = jtBoolean) then
        Cols := Cols + ',' + Path + '=' + IfThen(V.AsBoolean, '1', '0')
      else begin Error := 'Access denied'; Exit(403); end;
    end;
    if Cols = '' then Exit;
    if not T.Db.Exec('UPDATE custom_fields SET modifiedAt=' + QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',
      LocalTimeToUniversal(Now))) + Cols + ' WHERE id=' + QuotedStr(Id) + ';') then
    begin Error := 'Could not save'; Exit(500); end;
  end
  else begin Error := 'Method not found'; Exit(404); end;
  Error := '';
  Result := 200;
end;

// Admin Panel / Attachments / Transfer limits: avatar uploads blocked (#4740),
// a shared store's attachmentStorageSettings document; False without one.
function AvatarUploadBlocked(Db: TWLDb): Boolean;
var Doc: TJSONData; Value: TJSONData;
begin
  Result := False;
  Doc := nil;
  try
    try
      Doc := GetJSON(SharedFirstDocument(Db, 'attachmentStorageSettings'));
    except
      Doc := nil;
    end;
    if not (Doc is TJSONObject) then Exit;
    Value := TJSONObject(Doc).FindPath('limitSettings.avatarsUploadBlocked');
    Result := (Value <> nil) and (Value.JSONType = jtBoolean) and Value.AsBoolean;
  finally
    Doc.Free;
  end;
end;

procedure ServeMethod(Request: TRequest; Response: TResponse; const Name: string);
var RulesWords: TWLTranslator; FieldValues: TStringList; T: TWLTenant; S: TWLSession; Args: TJSONData; Selector: TJSONObject; Id, Error: string; R: TWLRows; Code, n: Integer; Lang: TWLLanguage; Ids: array of string; Enforce: Boolean;
  Limit: Double;
  // The values of a copy that its copier may not read: not kept.
  procedure RedactCopiedFields(const CardId, BoardId: string);
  var Policy: TFieldPolicy; V: TWLRows; k: Integer; Sql: string;
  begin
    V := T.Db.Query('SELECT customFieldId FROM card_custom_field_values WHERE cardId=' + QuotedStr(CardId) + ';');
    Sql := '';
    Policy := TFieldPolicy.Create(T.Db, S.UserId, BoardId, CardId);
    try
      for k := 0 to High(V) do
        try
          if not Policy.Allowed(V[k][0], False) then
            Sql := Sql + 'DELETE FROM card_custom_field_values WHERE cardId=' + QuotedStr(CardId) + ' AND customFieldId=' + QuotedStr(V[k][0]) + '; ';
        except
          Sql := Sql + 'DELETE FROM card_custom_field_values WHERE cardId=' + QuotedStr(CardId) + ' AND customFieldId=' + QuotedStr(V[k][0]) + '; ';
        end;
    finally
      Policy.Free;
    end;
    if (Sql <> '') and not T.Db.Exec('BEGIN IMMEDIATE; ' + Sql + 'COMMIT;') then T.Db.Exec('ROLLBACK;');
  end;

  function CardFieldsUpdate(const CardId: string; Modifier: TJSONObject; out Why: string): Integer;
  var Card: TJSONObject; Fields, V: TJSONData; Board, Key, FieldId: string; R: TWLRows; Index: Integer; Values: TStringList;
    // One field, or one field's entry, checked as a list of it.
    function ForgedOne(Item: TJSONData): Boolean;
    var One: TJSONArray;
    begin
      One := TJSONArray.Create([Item.Clone]);
      try
        Result := AdminFieldForgery(T.Db, S.UserId, Board, CardId, One, 'method:/cards/update');
      finally
        One.Free;
      end;
    end;
  begin
    Why := 'Access denied';
    R := T.Db.Query('SELECT boardId FROM cards WHERE id=' + QuotedStr(CardId) + ' AND deletedAt IS NULL;');
    if Length(R) <> 1 then Exit(404);
    Board := R[0][0];
    if not BoardCanWrite(T.Db, S.UserId, Board) then Exit(403);
    Card := nil;
    try
      try
        V := GetJSON(SharedDocument(T.Db, 'cards', CardId));
        if V is TJSONObject then Card := TJSONObject(V) else V.Free;
      except
        Card := nil;
      end;
      if Card <> nil then Fields := Card.Find('customFields') else Fields := nil;
      // Only $set of one or more customFields.N.value.
      if (Modifier.Count <> 1) or not (Modifier.Find('$set') is TJSONObject) then
      begin
        // A replace, a $push or an $unset of the array: an attempt when the
        // card holds, or the change names, a field the user may not write.
        if AdminFieldForgery(T.Db, S.UserId, Board, CardId, Fields, 'method:/cards/update') then Exit(403);
        for Index := 0 to Modifier.Count - 1 do
        begin
          V := Modifier.Items[Index];
          if (V is TJSONObject) and (TJSONObject(V).Find('customFields') <> nil) then
          begin
            if AdminFieldForgery(T.Db, S.UserId, Board, CardId, TJSONObject(V).Find('customFields'), 'method:/cards/update') then Exit(403);
            if (TJSONObject(V).Find('customFields') is TJSONObject) and ForgedOne(TJSONObject(V).Find('customFields')) then Exit(403);
          end;
        end;
        Exit(403);
      end;
      V := Modifier.Find('$set');
      for Index := 0 to V.Count - 1 do
      begin
        Key := TJSONObject(V).Names[Index];
        if Key = 'customFields' then
        begin
          if AdminFieldForgery(T.Db, S.UserId, Board, CardId, Fields, 'method:/cards/update') or
            AdminFieldForgery(T.Db, S.UserId, Board, CardId, V.Items[Index], 'method:/cards/update') then Exit(403);
          Exit(403);
        end;
        if (Copy(Key, 1, 13) <> 'customFields.') or (Copy(Key, Length(Key) - 5, 6) <> '.value') then Exit(403);
      end;
      for Index := 0 to V.Count - 1 do
      begin
        Key := TJSONObject(V).Names[Index];
        n := StrToIntDef(Copy(Key, 14, Length(Key) - 19), -1);
        if not (Fields is TJSONArray) or (n < 0) or (n >= Fields.Count) or not (Fields.Items[n] is TJSONObject) then Exit(403);
        FieldId := TJSONObject(Fields.Items[n]).Get('_id', '');
        Card.Add('_wl_field', TJSONObject.Create(['_id', FieldId]));
        if ForgedOne(Card.Objects['_wl_field']) then Exit(403);
        Card.Delete('_wl_field');
        Values := TStringList.Create;
        try
          if V.Items[Index].JSONType = jtString then Values.Values['value'] := V.Items[Index].AsString
          else Values.Values['value'] := V.Items[Index].AsJSON;
          Result := SetViewCardField(T, S.UserId, Board, CardId, FieldId, Values, False, Why);
        finally
          Values.Free;
        end;
        if Result <> 200 then Exit;
      end;
      Result := 200;
    finally
      Card.Free;
    end;
  end;
begin
  if not (ResolveTenant(Request, T) and TenantOpen(T)) then
  begin SendJsonAnswer(Response, 404, '{"error":404,"reason":"Unknown domain"}'); Exit; end;
  // server/lib/passwordPolicy.js's getPasswordPolicy answers without a
  // login: the sign-up form checks against it before anybody signed in.
  if Name = 'getPasswordPolicy' then
  begin
    PasswordPolicy(T.Db, n, Enforce);
    SendJsonAnswer(Response, 200, '{"result":{"minLength":' + IntToStr(n) + ',"enforce":' + IfThen(Enforce, 'true', 'false') + '}}');
    Exit;
  end;
  if not Html5User(T.Db, Request, S) then
  begin SendJsonAnswer(Response, 401, '{"error":401,"reason":"Must be logged in"}'); Exit; end;
  // WeKan's changeHistory.page, undoLast, redoLast and restore (wlrules).
  if Copy(Name, 1, 14) = 'changeHistory.' then
  begin
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not (Args is TJSONArray) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Code := HistoryMethod(T, S.UserId, Name, TJSONArray(Args), Error);
    finally
      Args.Free;
    end;
    if Code <> 0 then
    begin SendJsonAnswer(Response, Code, Error); Exit; end;
  end;
  // WeKan's rules.* methods (wlrules).
  if Copy(Name, 1, 6) = 'rules.' then
  begin
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not (Args is TJSONArray) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      RulesWords := TWLTranslator.Create(ViewerLanguage(T.Db, S, Request));
      try
        Code := RulesMethod(T, S.UserId, Name, TJSONArray(Args), Error, RulesWords);
      finally
        RulesWords.Free;
      end;
    finally
      Args.Free;
    end;
    if Code <> 0 then
    begin SendJsonAnswer(Response, Code, Error); Exit; end;
  end;
  // WeKan's createCardWithDueDate(boardId, listId, title, dueDate, swimlaneId):
  // the Calendar view's card on a clicked day. A refusal is recorded as
  // AuthBleed: the view offers it only to who may change the board.
  // WeKan's setCardCustomFieldCheckbox, setCardCustomFieldCurrency and
  // setCardCustomFieldAssigned (server/models/cards.js): [cardId, fieldId,
  // value] - a field already on the card for the first two, the field onto
  // the card or off it for the third - written as the card's custom fields are.
  if (Name = 'setCardCustomFieldCheckbox') or (Name = 'setCardCustomFieldCurrency') or (Name = 'setCardCustomFieldAssigned') then
  begin
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 3) and (TJSONArray(Args).Items[0].JSONType = jtString) and
        (TJSONArray(Args).Items[1].JSONType = jtString) and
        (((Name = 'setCardCustomFieldCurrency') and (TJSONArray(Args).Items[2].JSONType = jtNumber)) or
         ((Name <> 'setCardCustomFieldCurrency') and (TJSONArray(Args).Items[2].JSONType = jtBoolean)))) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      R := T.Db.Query('SELECT boardId FROM cards WHERE id=' + QuotedStr(TJSONArray(Args).Strings[0]) + ' AND deletedAt IS NULL;');
      if Length(R) <> 1 then begin SendJsonAnswer(Response, 404, '{"error":"not-found","reason":"Card not found"}'); Exit; end;
      Id := 'cardId=' + QuotedStr(TJSONArray(Args).Strings[0]) + ' AND customFieldId=' + QuotedStr(TJSONArray(Args).Strings[1]);
      n := Length(T.Db.Query('SELECT 1 FROM card_custom_field_values WHERE ' + Id + ';'));
      Ids := nil;
      if Name = 'setCardCustomFieldAssigned' then
      begin
        // On the card already, or off it already: nothing to change.
        if (n = 1) = TJSONArray(Args).Booleans[2] then
        begin SendJsonAnswer(Response, 200, '{"result":' + IfThen(n = 1, 'true', 'false') + '}'); Exit; end;
        Code := SetViewCardField(T, S.UserId, R[0][0], TJSONArray(Args).Strings[0], TJSONArray(Args).Strings[1], nil, True, Error);
      end
      else if n <> 1 then
      begin SendJsonAnswer(Response, 400, '{"error":"custom-field-not-on-card","reason":"custom-field-not-on-card"}'); Exit; end
      else
      begin
        FieldValues := TStringList.Create;
        try
          if Name = 'setCardCustomFieldCheckbox' then FieldValues.Values['value'] := IfThen(TJSONArray(Args).Booleans[2], 'true', 'false')
          else FieldValues.Values['value'] := FloatToStr(TJSONArray(Args).Floats[2], DefaultFormatSettings);
          Code := SetViewCardField(T, S.UserId, R[0][0], TJSONArray(Args).Strings[0], TJSONArray(Args).Strings[1], FieldValues, False, Error);
        finally
          FieldValues.Free;
        end;
      end;
      if Code <> 200 then
      begin SendJsonAnswer(Response, Code, '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
      SendJsonAnswer(Response, 200, '{"result":' + TJSONArray(Args).Items[2].AsJSON + '}');
    finally
      Args.Free;
    end;
    Exit;
  end;
  // Meteor's client update of a card, as WeKan's allow rules let a card
  // editor make it: (id or {_id}, {$set: {title | description}}) - the title
  // and description of a card of a board one may change, with WeKan's text
  // activities. Anything else is Meteor's 403 "Access denied".
  if Name = '/cards/update' then
  begin
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      Id := '';
      if (Args is TJSONArray) and (TJSONArray(Args).Count >= 2) then
      begin
        if TJSONArray(Args).Items[0].JSONType = jtString then Id := TJSONArray(Args).Strings[0]
        else if (TJSONArray(Args).Items[0] is TJSONObject) and (TJSONArray(Args).Items[0].Count = 1) and
          (TJSONObject(TJSONArray(Args).Items[0]).Find('_id') is TJSONString) then
          Id := TJSONObject(TJSONArray(Args).Items[0]).Strings['_id'];
      end;
      Selector := nil;
      // A card's custom fields, as WeKan's allow rules take them: the one
      // change its card details make - $set customFields.N.value - of a
      // field the user may write. Every other change of the array, and a
      // value of a field they may not write, is refused, and an attempt on
      // an admin-only field recorded (AdminFieldBleed).
      if (Id <> '') and (TJSONArray(Args).Items[1] is TJSONObject) and (Pos('customFields', TJSONArray(Args).Items[1].AsJSON) > 0) then
      begin
        Code := CardFieldsUpdate(Id, TJSONObject(TJSONArray(Args).Items[1]), Error);
        if Code <> 200 then
        begin SendJsonAnswer(Response, Code, '{"error":' + IntToStr(Code) + ',"reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
        SendJsonAnswer(Response, 200, '{"result":1}');
        Exit;
      end;
      if (Id <> '') and (TJSONArray(Args).Items[1] is TJSONObject) and (TJSONArray(Args).Items[1].Count = 1) and
        (TJSONObject(TJSONArray(Args).Items[1]).Find('$set') is TJSONObject) then
        Selector := TJSONObject(TJSONObject(TJSONArray(Args).Items[1]).Find('$set'));
      Code := 403; Error := 'Access denied';
      if (Selector <> nil) and (Selector.Count >= 1) then
      begin
        R := T.Db.Query('SELECT boardId FROM cards WHERE id=' + QuotedStr(Id) + ' AND deletedAt IS NULL;');
        if Length(R) <> 1 then begin SendJsonAnswer(Response, 200, '{"result":0}'); Exit; end;
        Code := 200;
        for n := 0 to Selector.Count - 1 do
          if (Code = 200) and not (((Selector.Names[n] = 'title') or (Selector.Names[n] = 'description')) and
            (Selector.Items[n].JSONType = jtString)) then begin Code := 403; Error := 'Access denied'; end;
        for n := 0 to Selector.Count - 1 do
          if Code = 200 then
            if Selector.Names[n] = 'title' then
              Code := RenameViewCard(T, S.UserId, R[0][0], Id, Selector.Items[n].AsString, Error)
            else
              Code := SetViewCardDescription(T, S.UserId, R[0][0], Id, Selector.Items[n].AsString, Error);
        if Code = 403 then Error := 'Access denied';
      end;
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":' + IntToStr(Code) + ',"reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":1}');
    Exit;
  end;
  // AdminFieldBleed on WeKan's other ways to write a custom field: a card
  // inserted, or copied, with values; a field defined or changed as
  // admin-only - each refused and recorded when it names what the user may
  // not write. What they do otherwise is not a method of this view.
  if (Name = '/cards/insert') or (Name = 'copyCard') or (Name = '/customFields/insert') or (Name = '/customFields/update') then
  begin
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      Code := 0;
      if Args is TJSONArray then
      begin
        Selector := nil;
        if (Name = '/cards/insert') and (TJSONArray(Args).Count >= 1) and (TJSONArray(Args).Items[0] is TJSONObject) then
        begin
          Selector := TJSONObject(TJSONArray(Args).Items[0]);
          if AdminFieldForgery(T.Db, S.UserId, Selector.Get('boardId', ''), '', Selector.Find('customFields'), 'method:/cards/insert') then Code := 403;
        end
        else if (Name = 'copyCard') and (TJSONArray(Args).Count >= 6) and (TJSONArray(Args).Items[5] is TJSONObject) and
          (TJSONArray(Args).Items[1].JSONType = jtString) then
        begin
          if AdminFieldForgery(T.Db, S.UserId, TJSONArray(Args).Strings[1], '', TJSONObject(TJSONArray(Args).Items[5]).Find('customFields'),
            'method:copyCard') then Code := 403;
        end
        else if (Name = '/customFields/insert') and (TJSONArray(Args).Count >= 1) and (TJSONArray(Args).Items[0] is TJSONObject) then
        begin
          Selector := TJSONObject(TJSONArray(Args).Items[0]);
          if (Selector.Find('adminOnly') <> nil) and (Selector.Find('boardIds') is TJSONArray) then
            for n := 0 to Selector.Arrays['boardIds'].Count - 1 do
              if (Selector.Arrays['boardIds'].Items[n].JSONType = jtString) and
                not BoardCanAdmin(T.Db, S.UserId, Selector.Arrays['boardIds'].Strings[n]) then Code := 403;
          if Code = 403 then RecordAdminFieldAttempt(T.Db, S.UserId, 'method:/customFields/insert', 'An admin-only field defined by a non-admin.');
        end
        else if (Name = '/customFields/update') and (TJSONArray(Args).Count >= 2) and (Pos('adminOnly', TJSONArray(Args).Items[1].AsJSON) > 0) then
        begin
          Id := '';
          if TJSONArray(Args).Items[0].JSONType = jtString then Id := TJSONArray(Args).Strings[0]
          else if TJSONArray(Args).Items[0] is TJSONObject then Id := TJSONObject(TJSONArray(Args).Items[0]).Get('_id', '');
          R := T.Db.Query('SELECT boardId FROM custom_field_boards WHERE customFieldId=' + QuotedStr(Id) + ';');
          for n := 0 to High(R) do
            if not BoardCanAdmin(T.Db, S.UserId, R[n][0]) then Code := 403;
          if Code = 403 then RecordAdminFieldAttempt(T.Db, S.UserId, 'method:/customFields/update', 'A field''s admin-only flag changed by a non-admin.');
        end;
      end;
    finally
      Args.Free;
    end;
    if Code = 403 then
    begin SendJsonAnswer(Response, 403, '{"error":403,"reason":"Access denied"}'); Exit; end;
  end;
  // WeKan's copyCard(cardId, boardId, swimlaneId, listId, insertAtTop,
  // mergeCardValues): the card copied as the card menu copies it; a value of
  // a custom field the copier may not read is not copied with it.
  if Name = 'copyCard' then
  begin
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count >= 4) and (TJSONArray(Args).Items[0].JSONType = jtString) and
        (TJSONArray(Args).Items[1].JSONType = jtString) and (TJSONArray(Args).Items[2].JSONType = jtString) and
        (TJSONArray(Args).Items[3].JSONType = jtString)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      R := T.Db.Query('SELECT boardId FROM cards WHERE id=' + QuotedStr(TJSONArray(Args).Strings[0]) + ' AND deletedAt IS NULL;');
      if Length(R) <> 1 then begin SendJsonAnswer(Response, 404, '{"error":"not-found","reason":"Card not found"}'); Exit; end;
      Code := CopyViewCard(T, S.UserId, R[0][0], TJSONArray(Args).Strings[0], TJSONArray(Args).Strings[1], TJSONArray(Args).Strings[2],
        TJSONArray(Args).Strings[3], '', Id, Error);
      if Code = 200 then
        RedactCopiedFields(Id, TJSONArray(Args).Strings[1]);
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":"' + StringToJSONString(Id) + '"}');
    Exit;
  end;
  // WeKan's isAvatarUploadBlocked (#4740): Admin Panel / Attachments'
  // limitSettings.avatarsUploadBlocked; avatars stay enabled without it.
  // Board Settings / Card's writes (wlcardst).
  if (Name = '/boards/update') or (Name = 'setShowLabelTextOverride') or (Name = 'setBoardDragging') or
    (Name = 'setCollapsedCardSection') or (Name = '/customFields/update') then
  begin
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not (Args is TJSONArray) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Code := CardSettingsMethod(T, S.UserId, Name, TJSONArray(Args), Error);
    finally
      Args.Free;
    end;
    // A collection write refused is Meteor's 403 "Access denied".
    if (Code = 403) and (Error = 'Access denied') then
      SendJsonAnswer(Response, 403, '{"error":403,"reason":"Access denied"}')
    else if Code <> 200 then
      SendJsonAnswer(Response, Code, '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Error) + '"}')
    else
    begin
      // The board's pages draw again, the writer's too: its cards change.
      if (Name = '/boards/update') or (Name = '/customFields/update') or (Name = 'setBoardDragging') then AnnounceToAll;
      SendJsonAnswer(Response, 200, '{"result":1}');
    end;
    Exit;
  end;
  // server/attachmentApi.js api.attachment.delete [attachmentId]: the REST
  // delete's checks - board write access, and an assigned-only writer's own
  // card (UnassignedAttachBleed) - then the same soft delete.
  if Name = 'api.attachment.delete' then
  begin
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 1) and (TJSONArray(Args).Items[0].JSONType = jtString)) then
      begin SendJsonAnswer(Response, 400, '{"error":"Match.Error","reason":"Match failed"}'); Exit; end;
      Id := TJSONArray(Args).Strings[0];
    finally
      Args.Free;
    end;
    R := T.Db.Query('SELECT boardId,COALESCE(cardId,''''),COALESCE(name,'''') FROM attachments WHERE id=' + QuotedStr(Id) + ';');
    if Length(R) <> 1 then begin SendJsonAnswer(Response, 404, '{"error":"attachment-not-found","reason":"Attachment not found"}'); Exit; end;
    if AttachmentWriteAllowed(T.Db, S.UserId, R[0][0], R[0][1], 'attachment-method:delete') <> 200 then
    begin SendJsonAnswer(Response, 403, '{"error":"not-authorized","reason":"You do not have permission to delete this attachment"}'); Exit; end;
    if not DeleteStoredAttachment(T, S.UserId, R[0][0], Id, IfThen(AssignedOnlyMember(T.Db, S.UserId, R[0][0]), R[0][1], '')) then
    begin SendJsonAnswer(Response, 500, '{"error":500,"reason":"Could not delete attachment"}'); Exit; end;
    AnnounceToAll;
    SendJsonAnswer(Response, 200, '{"result":{"success":true,"attachmentId":"' + StringToJSONString(Id) + '","fileName":"' +
      StringToJSONString(R[0][2]) + '","message":"Attachment deleted successfully"}}');
    Exit;
  end;
  // server/models/lists.js's WIP limit methods, a board admin's: applyWipLimit
  // [listId, limit] sets the value - 1 when it is no number of at least one -
  // enableWipLimit [listId] turns the limit on or off (a value of 0 becoming
  // 1), and enableSoftLimit [listId] between hard and soft.
  if (Name = 'applyWipLimit') or (Name = 'enableWipLimit') or (Name = 'enableSoftLimit') then
  begin
    Args := nil;
    Limit := 0;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (((Name = 'applyWipLimit') and (TJSONArray(Args).Count = 2)) or ((Name <> 'applyWipLimit') and (TJSONArray(Args).Count = 1))) and
        (TJSONArray(Args).Items[0].JSONType = jtString) and
        ((Name <> 'applyWipLimit') or (TJSONArray(Args).Items[1].JSONType = jtNumber))) then
      begin SendJsonAnswer(Response, 400, '{"error":"Match.Error","reason":"Match failed"}'); Exit; end;
      Id := TJSONArray(Args).Strings[0];
      if Name = 'applyWipLimit' then Limit := TJSONArray(Args).Floats[1];
    finally
      Args.Free;
    end;
    R := T.Db.Query('SELECT boardId,COALESCE(wip_value,0),COALESCE(wip_enabled,0),COALESCE(wip_soft,0) FROM lists WHERE id=' +
      QuotedStr(Id) + ' AND deletedAt IS NULL;');
    if Length(R) <> 1 then begin SendJsonAnswer(Response, 404, '{"error":"list-not-found","reason":"List not found"}'); Exit; end;
    if not BoardOwnAdmin(T.Db, S.UserId, R[0][0]) then
    begin SendJsonAnswer(Response, 403, '{"error":"not-authorized","reason":"You must be a board admin to modify WIP limits."}'); Exit; end;
    if Name = 'applyWipLimit' then
    begin
      // NaN and Infinity fail both comparisons: they become 1, as in WeKan.
      if not ((Limit >= 1) and (Limit <= 1.7e308)) then Limit := 1;
      Id := 'wip_value=' + FloatToStr(Limit, DefaultFormatSettings) + ' WHERE id=' + QuotedStr(Id);
    end
    else if Name = 'enableWipLimit' then
      Id := 'wip_enabled=' + IfThen(R[0][2] = '1', '0', '1') + IfThen(R[0][1] = '0', ',wip_value=1', '') + ' WHERE id=' + QuotedStr(Id)
    else
      Id := 'wip_soft=' + IfThen(R[0][3] = '1', '0', '1') + ' WHERE id=' + QuotedStr(Id);
    if not T.Db.Exec('UPDATE lists SET modifiedAt=' + QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', LocalTimeToUniversal(Now))) +
      ',' + Id + ';') then
    begin SendJsonAnswer(Response, 500, '{"error":500,"reason":"Could not save"}'); Exit; end;
    // The board's pages draw the list's limit again.
    AnnounceToAll;
    SendJsonAnswer(Response, 200, '{"result":null}');
    Exit;
  end;
  // server/models/lists.js lists.softRemove(listId): the list and its cards
  // soft-deleted, for whoever may change the board.
  if Name = 'lists.softRemove' then
  begin
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 1) and (TJSONArray(Args).Items[0].JSONType = jtString)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Id := TJSONArray(Args).Strings[0];
    finally
      Args.Free;
    end;
    R := T.Db.Query('SELECT boardId,COALESCE(deleteBatchId,'''') FROM lists WHERE id=' + QuotedStr(Id) + ';');
    if Length(R) <> 1 then begin SendJsonAnswer(Response, 404, '{"error":"not-found","reason":"List not found"}'); Exit; end;
    if not BoardCanWrite(T.Db, S.UserId, R[0][0]) then
    begin SendJsonAnswer(Response, 403, '{"error":"not-authorized","reason":"You cannot modify this board."}'); Exit; end;
    Code := SoftRemoveViewList(T, S.UserId, R[0][0], Id, Error);
    if Code <> 200 then begin SendJsonAnswer(Response, Code, '{"error":' + IntToStr(Code) + ',"reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    R := T.Db.Query('SELECT COALESCE(deleteBatchId,'''') FROM lists WHERE id=' + QuotedStr(Id) + ';');
    AnnounceToAll;
    SendJsonAnswer(Response, 200, '{"result":{"deleted":true,"batchId":"' + StringToJSONString(R[0][0]) + '"}}');
    Exit;
  end;
  if Name = '/settings/update' then
  begin
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not (Args is TJSONArray) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Code := SettingsUpdate(T.Db, S.UserId, TJSONArray(Args), Error);
    finally
      Args.Free;
    end;
    if Code <> 200 then
      SendJsonAnswer(Response, Code, '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Error) + '"}')
    else
      SendJsonAnswer(Response, 200, '{"result":1}');
    Exit;
  end;
  if IsPreferenceMethod(Name) then
  begin
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not (Args is TJSONArray) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Code := PreferenceMethod(T, S.UserId, Name, TJSONArray(Args), Error);
    finally
      Args.Free;
    end;
    if Code <> 200 then
      SendJsonAnswer(Response, Code, '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Error) + '"}')
    else
    begin
      // The board's other pages draw again: a board's format is theirs too.
      if Name = 'setBoardDateFormat' then AnnounceToAll;
      SendJsonAnswer(Response, 200, '{"result":true}');
    end;
    Exit;
  end;
  if Name = 'isAvatarUploadBlocked' then
  begin
    SendJsonAnswer(Response, 200, '{"result":' + IfThen(AvatarUploadBlocked(T.Db), 'true', 'false') + '}');
    Exit;
  end;
  if Name = 'createCardWithDueDate' then
  begin
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 5) and (TJSONArray(Args).Items[0].JSONType = jtString) and
        (TJSONArray(Args).Items[1].JSONType = jtString) and (TJSONArray(Args).Items[2].JSONType = jtString) and
        (TJSONArray(Args).Items[3].JSONType = jtString) and (TJSONArray(Args).Items[4].JSONType = jtString) and
        (Length(TJSONArray(Args).Strings[3]) = 24) and (TJSONArray(Args).Strings[3][11] = 'T') and
        (TJSONArray(Args).Strings[3][24] = 'Z')) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      if not BoardCanWrite(T.Db, S.UserId, TJSONArray(Args).Strings[0]) then
      begin
        if Length(T.Db.Query('SELECT 1 FROM boards WHERE id=' + QuotedStr(TJSONArray(Args).Strings[0]) + ';')) = 1 then
        begin
          try
            RecordSecurityEvent(T.Db, S.UserId, 'AuthBleed', 'method:createCardWithDueDate', 'authz', 'high', 'CWE-862', 'blocked',
              'Card insert refused: no write access to the board');
          except
            // logging must never break the guard
          end;
          SendJsonAnswer(Response, 403, '{"error":"not-authorized","reason":"not-authorized"}');
        end
        else SendJsonAnswer(Response, 404, '{"error":"not-found","reason":"not-found"}');
        Exit;
      end;
      Code := CreateViewCard(T, S.UserId, TJSONArray(Args).Strings[0], TJSONArray(Args).Strings[1], TJSONArray(Args).Strings[4],
        TJSONArray(Args).Strings[2], 'top', Id, Error);
      if (Code = 200) and not T.Db.Exec('UPDATE cards SET dueAt=' + QuotedStr(TJSONArray(Args).Strings[3]) + ' WHERE id=' +
        QuotedStr(Id) + ';') then begin Code := 500; Error := 'Could not set the due date'; end;
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":"' + StringToJSONString(Id) + '"}');
    Exit;
  end;
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
  if (Name = 'setFixedListWidthEnabled') or (Name = 'setFixedListWidth') or (Name = 'applyListWidthToStorage') then
  begin
    // server/models/users.js (#5729, #6465): the user's own same width for
    // every list of a board - on or off, and its width - and a list's own
    // personal width with its constraint; a width is 200 to 1000.
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      Code := 400;
      if Args is TJSONArray then
        if Name = 'setFixedListWidthEnabled' then
        begin
          if (TJSONArray(Args).Count = 2) and (TJSONArray(Args).Items[0].JSONType = jtString) and
            (TJSONArray(Args).Items[1].JSONType = jtBoolean) then
            Code := SetViewProfileValue(T, S.UserId, 'fixedListWidthBoards', TJSONArray(Args).Items[0].AsString, '',
              TJSONArray(Args).Items[1].AsJSON, Error);
        end
        else if Name = 'setFixedListWidth' then
        begin
          if (TJSONArray(Args).Count = 2) and (TJSONArray(Args).Items[0].JSONType = jtString) and
            (TJSONArray(Args).Items[1].JSONType = jtNumber) then
          begin
            if (TJSONArray(Args).Items[1].AsFloat < 200) or (TJSONArray(Args).Items[1].AsFloat > 1000) then
            begin SendJsonAnswer(Response, 400, '{"error":"invalid-width","reason":"Width must be >= 200"}'); Exit; end;
            Code := SetViewProfileValue(T, S.UserId, 'fixedListWidths', TJSONArray(Args).Items[0].AsString, '',
              TJSONArray(Args).Items[1].AsJSON, Error);
          end;
        end
        else if (TJSONArray(Args).Count = 4) and (TJSONArray(Args).Items[0].JSONType = jtString) and
          (TJSONArray(Args).Items[1].JSONType = jtString) and (TJSONArray(Args).Items[2].JSONType = jtNumber) and
          (TJSONArray(Args).Items[3].JSONType = jtNumber) then
        begin
          if (TJSONArray(Args).Items[2].AsFloat < 200) or (TJSONArray(Args).Items[2].AsFloat > 1000) then
          begin SendJsonAnswer(Response, 400, '{"error":"invalid-width","reason":"Width must be >= 200"}'); Exit; end;
          Code := SetViewProfileValue(T, S.UserId, 'listWidths', TJSONArray(Args).Items[0].AsString,
            TJSONArray(Args).Items[1].AsString, TJSONArray(Args).Items[2].AsJSON, Error);
          if Code = 200 then
            Code := SetViewProfileValue(T, S.UserId, 'listConstraints', TJSONArray(Args).Items[0].AsString,
              TJSONArray(Args).Items[1].AsString, TJSONArray(Args).Items[3].AsJSON, Error);
        end;
      if (Code = 400) and (Error = '') then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":' + IntToStr(Code) + ',"reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":true}');
    Exit;
  end;
  if (Name = 'setUsername') or (Name = 'setEmail') then
  begin
    // server/models/users.js: [value, userId].
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 2) and (TJSONArray(Args).Items[0].JSONType = jtString) and
        (TJSONArray(Args).Items[1].JSONType = jtString)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      if Name = 'setUsername' then
        Code := ViewSetUsername(T, S.UserId, TJSONArray(Args).Items[1].AsString, TJSONArray(Args).Items[0].AsString, Error)
      else
        Code := ViewSetEmail(T, S.UserId, TJSONArray(Args).Items[1].AsString, TJSONArray(Args).Items[0].AsString, Error);
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":null}');
    Exit;
  end;
  if Name = 'archiveSelectedCards' then
  begin
    // server/models/cards.js: [boardId, [cardId, ...]].
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 2) and (TJSONArray(Args).Items[0].JSONType = jtString) and
        (TJSONArray(Args).Items[1].JSONType = jtArray)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      SetLength(Ids, TJSONArray(TJSONArray(Args).Items[1]).Count);
      for n := 0 to High(Ids) do
      begin
        if TJSONArray(TJSONArray(Args).Items[1]).Items[n].JSONType <> jtString then
        begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
        Ids[n] := TJSONArray(TJSONArray(Args).Items[1]).Items[n].AsString;
      end;
      Code := ArchiveViewCards(T, S.UserId, TJSONArray(Args).Items[0].AsString, Ids, Error);
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":null}');
    Exit;
  end;
  if (Name = 'updateListSort') or (Name = '/lists/update') then
  begin
    // server/models/lists.js updateListSort: [listId, boardId, {sort, swimlaneId,
    // updatedAt, modifiedAt}], by whoever may change the board (#5462, #5997);
    // and the collection's own update, [{_id}, {$set: {sort / swimlaneId}}], as
    // WeKan's allow rule answers it: 403 "Access denied" without write access.
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count >= 2)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Selector := nil;
      if Name = 'updateListSort' then
      begin
        if not ((TJSONArray(Args).Count = 3) and (TJSONArray(Args).Items[0].JSONType = jtString) and
          (TJSONArray(Args).Items[1].JSONType = jtString) and (TJSONArray(Args).Items[2].JSONType = jtObject)) then
        begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
        Id := TJSONArray(Args).Items[0].AsString;
        Code := SetViewListSort(T, S.UserId, TJSONArray(Args).Items[1].AsString, Id, TJSONObject(TJSONArray(Args).Items[2]), Error);
      end
      else
      begin
        if not ((TJSONArray(Args).Items[0].JSONType = jtObject) and (TJSONArray(Args).Items[1].JSONType = jtObject) and
          (TJSONObject(TJSONArray(Args).Items[0]).Find('_id') is TJSONString) and
          (TJSONObject(TJSONArray(Args).Items[1]).Find('$set') is TJSONObject)) then
        begin SendJsonAnswer(Response, 403, '{"error":403,"reason":"Access denied"}'); Exit; end;
        Id := TJSONObject(TJSONArray(Args).Items[0]).Get('_id', '');
        R := T.Db.Query('SELECT boardId FROM lists WHERE id=' + QuotedStr(Id) + ';');
        if Length(R) <> 1 then begin SendJsonAnswer(Response, 403, '{"error":403,"reason":"Access denied"}'); Exit; end;
        Code := SetViewListSort(T, S.UserId, R[0][0], Id, TJSONObject(TJSONObject(TJSONArray(Args).Items[1]).Find('$set')), Error);
        if Code <> 200 then begin SendJsonAnswer(Response, 403, '{"error":403,"reason":"Access denied"}'); Exit; end;
        SendJsonAnswer(Response, 200, '{"result":1}');
        Exit;
      end;
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":null}');
    Exit;
  end;
  if (Name = 'acceptInvite') or (Name = 'quitBoard') then
  begin
    // server/models/boards.js: [boardId]. acceptInvite answers false without an
    // invitation (#4730); quitBoard leaves the board and clears the invitation.
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 1) and (TJSONArray(Args).Items[0].JSONType = jtString)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      Id := TJSONArray(Args).Items[0].AsString;
    finally
      Args.Free;
    end;
    if Name = 'acceptInvite' then Code := AcceptViewInvite(T, S.UserId, Id, Error)
    else Code := QuitViewBoard(T, S.UserId, Id, Error);
    if Code = 204 then begin SendJsonAnswer(Response, 200, '{"result":false}'); Exit; end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
    SendJsonAnswer(Response, 200, '{"result":true}');
    Exit;
  end;
  // The users collection's own update: the tray's read marks and removals
  // of the user's own notifications, and nothing else - WeKan's allow and
  // deny rules refuse a client writing an account, its invitations
  // (InviteProfileBleed) and its notification list (TrayBleed) included.
  if Name = '/users/update' then
  begin
    Code := ViewUsersUpdate(T.Db, S.UserId, Request.Content);
    // Else Card Settings' own: the user's split and labels text override
    // (wlcardst). Each refuses without writing what is not its own.
    if Code <> 200 then
    begin
      Args := nil;
      try
        try
          Args := GetJSON(Request.Content);
        except
          Args := nil;
        end;
        if (Args is TJSONArray) and (CardSettingsMethod(T, S.UserId, Name, TJSONArray(Args), Error) = 200) then Code := 200;
      finally
        Args.Free;
      end;
    end;
    if Code = 200 then SendJsonAnswer(Response, 200, '{"result":1}')
    else SendJsonAnswer(Response, Code, '{"error":' + IntToStr(Code) + ',"reason":"Access denied"}');
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
  if Name = 'setPassword' then
  begin
    // WeKan's setPassword (server/models/users.js): [newPassword, userId], a
    // site admin's; every session of that user is signed out.
    Args := nil;
    try
      try
        Args := GetJSON(Request.Content);
      except
        Args := nil;
      end;
      if not ((Args is TJSONArray) and (TJSONArray(Args).Count = 2) and (TJSONArray(Args).Items[0].JSONType = jtString) and
        (TJSONArray(Args).Items[1].JSONType = jtString)) then
      begin SendJsonAnswer(Response, 400, '{"error":400,"reason":"Match failed"}'); Exit; end;
      if not IsSiteAdmin(T.Db, S.UserId) then begin SendJsonAnswer(Response, 403, '{"error":"not-authorized","reason":"Access denied"}'); Exit; end;
      Code := ViewSetPassword(T, S.UserId, TJSONArray(Args).Items[1].AsString, TJSONArray(Args).Items[0].AsString, Error);
    finally
      Args.Free;
    end;
    if Code <> 200 then
    begin SendJsonAnswer(Response, Code, '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Error) + '"}'); Exit; end;
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
  // isAdmin as Meteor.user() has it: the site admin's Admin Panel.
  Result := '{"_id":"' + StringToJSONString(R[0][0]) + '","username":"' + StringToJSONString(R[0][1]) + '","profile":' + Profile +
    ',"isAdmin":' + IfThen(IsSiteAdmin(Db, R[0][0]), 'true', 'false') + '}';
end;

// cardAttachmentsPopup's upload: one file, onto a live card of a board the
// user may change, stored as the HTML4 view's upload stores it.
function AddViewAttachment(const T: TWLTenant; const UserId, BoardId, CardId: string; Request: TRequest;
  out Error: string): Integer;
var Rows: TWLRows; Upload: TUploadedFile; FileType, Id, Raw, Clean, Removed: string; Changed: Boolean;
  Body: TStream;
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
  // An SVG is stored sanitized (models/lib/sanitizeUploadedFile.js); active
  // markup taken out of it is a stored-XSS attempt defused, and is recorded.
  // One that is not well-formed is kept as it came, and only downloaded.
  Body := Upload.Stream;
  Clean := '';
  if IsSvg(FileType, Upload.FileName) and (Upload.Stream.Size <= MAX_SVG_BYTES) then
  begin
    SetLength(Raw, Upload.Stream.Size);
    Upload.Stream.Position := 0;
    if Length(Raw) > 0 then Upload.Stream.ReadBuffer(Raw[1], Length(Raw));
    Upload.Stream.Position := 0;
    if SanitizeSvg(Raw, Clean, Changed, Removed) then
    begin
      FileType := 'image/svg+xml';
      Body := TStringStream.Create(Clean);
      if Changed then
      try
        RecordSecurityEvent(T.Db, UserId, 'FileBleed', 'fileUpload', 'file', 'medium', 'CWE-79', 'sanitized',
          'removed active content (JavaScript / XML) from file content "' + ExtractFileName(Upload.FileName) + '": ' + Removed);
      except { logging must never break the upload } end;
    end
    else FileType := 'application/octet-stream';
  end
  // One too large to read is no image either.
  else if IsSvg(FileType, Upload.FileName) then FileType := 'application/octet-stream';
  try
    if not StoreAttachment(T, UserId, BoardId, Rows[0][0], Rows[0][1], CardId, ExtractFileName(Upload.FileName), FileType,
      Body, Id, True) then
    begin Error := 'Upload failed'; Exit(500); end;
  finally
    if Body <> Upload.Stream then Body.Free;
  end;
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

const
  // WeKan's avatarServer.js: an uploaded avatar is at most 72 KB.
  MAX_AVATAR_BYTES = 72000;

// The picture a file's first bytes are, by their magic (PNG, JPEG, GIF,
// WebP); '' for anything else - an SVG or a page among them.
function AvatarImageType(const Head: RawByteString): string;
begin
  Result := '';
  if Copy(Head, 1, 8) = #$89'PNG'#13#10#26#10 then Result := 'image/png'
  else if Copy(Head, 1, 3) = #$FF#$D8#$FF then Result := 'image/jpeg'
  else if (Copy(Head, 1, 6) = 'GIF87a') or (Copy(Head, 1, 6) = 'GIF89a') then Result := 'image/gif'
  else if (Copy(Head, 1, 4) = 'RIFF') and (Copy(Head, 9, 4) = 'WEBP') then Result := 'image/webp';
end;

procedure EnsureAvatarTable(Db: TWLDb);
begin
  Db.Exec('CREATE TABLE IF NOT EXISTS _wl_avatars(id TEXT PRIMARY KEY, userId TEXT NOT NULL, type TEXT NOT NULL, name TEXT NOT NULL, createdAt TEXT NOT NULL);');
end;

// POST /profile/avatar: the user's own new avatar (Member Settings / Edit
// Profile, Weddy's uploadAvatar): one raster image, by its content, of at
// most 72 KB, unless Admin Panel blocks avatar uploads. Stored in the file
// store, recorded for serving, in a shared store as WeKan's avatars row too,
// and made the profile's avatarUrl. 200, or a code and the reason.
function UploadAvatar(const T: TWLTenant; const UserId: string; Request: TRequest; out Error: string): Integer;
var Upload: TUploadedFile; Data: RawByteString; Typ, Id, Path, Name, Ext: string; F: TFileStream; Doc: TJSONObject; i: Integer;
begin
  Error := '';
  if AvatarUploadBlocked(T.Db) then begin Error := 'avatars-upload-blocked-description'; Exit(403); end;
  if (Request.Files.Count <> 1) or (Request.Files[0].FieldName <> 'avatar') then begin Error := 'avatar-too-big'; Exit(400); end;
  Upload := Request.Files[0];
  if (Upload.Size > MAX_AVATAR_BYTES) or (Upload.Size <= 0) then begin Error := 'avatar-too-big'; Exit(400); end;
  SetLength(Data, Upload.Size);
  Upload.Stream.Position := 0;
  Upload.Stream.ReadBuffer(Data[1], Upload.Size);
  Typ := AvatarImageType(Data);
  if Typ = '' then begin Error := 'avatar-too-big'; Exit(400); end;
  Id := NewId;
  Path := StoreFilePath(T.FilesDir, 'avatars', Id);
  ForceDirectories(ExtractFilePath(Path));
  F := TFileStream.Create(Path, fmCreate);
  try
    F.WriteBuffer(Data[1], Length(Data));
  finally
    F.Free;
  end;
  // The name kept only for the download's filename, safe characters only.
  Name := '';
  for i := 1 to Length(Upload.FileName) do
    if Upload.FileName[i] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.'] then Name := Name + Upload.FileName[i];
  if Name = '' then Name := 'avatar';
  Ext := Copy(Typ, 7, MaxInt);
  EnsureAvatarTable(T.Db);
  if not T.Db.Exec('INSERT INTO _wl_avatars(id,userId,type,name,createdAt) VALUES(' + QuotedStr(Id) + ',' + QuotedStr(UserId) + ',' +
    QuotedStr(Typ) + ',' + QuotedStr(Name) + ',' + QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', LocalTimeToUniversal(Now))) + ');') then
  begin DeleteFile(Path); Error := 'Could not save'; Exit(500); end;
  if IsShared(T.Db) then
  begin
    Doc := TJSONObject.Create(['_id', Id, 'name', Name, 'extension', Ext, 'ext', Ext, 'extensionWithDot', '.' + Ext, 'type', Typ,
      'mime', Typ, 'mime-type', Typ, 'size', Length(Data), 'userId', UserId, 'isImage', True, 'path', Path, '_collectionName', 'avatars',
      '_downloadRoute', '/cdn/storage', 'public', False, 'meta', TJSONObject.Create,
      'versions', TJSONObject.Create(['original', TJSONObject.Create(['path', Path, 'size', Length(Data), 'type', Typ, 'extension', Ext,
        'storage', 'fs'])])]);
    try
      try
        T.Db.Exec(InsertDocSql(T.Db, 'avatars', Doc, ''));
      except
        // WeLite serves it from _wl_avatars either way.
      end;
    finally
      Doc.Free;
    end;
  end;
  if not SetProfileField(T.Db, UserId, 'avatarUrl', '"/cdn/storage/avatars/' + Id + '"') then begin Error := 'Could not save'; Exit(500); end;
  Result := 200;
end;

// WeKan's changeAvatarPopup (userAvatar.jade): the user's uploaded avatars,
// each to choose or delete, the initials, and the upload unless Admin Panel
// blocks it. Error: a refused upload's reason, shown with the pop-over
// opened at once.
function ChangeAvatarPopup(Db: TWLDb; Words: TWLTranslator; const UserId, Error: string): string;
var R: TWLRows; Current, Item, Msg: string; i: Integer;
begin
  EnsureAvatarTable(Db);
  Current := ProfileField(Db, UserId, 'avatarUrl');
  R := Db.Query('SELECT id,name FROM _wl_avatars WHERE userId=' + QuotedStr(UserId) + ' ORDER BY createdAt,id;');
  Result := '<template class="js-pop-over-template" data-pop="change-avatar" data-popup="changeAvatarPopup" data-title="' +
    HtmlAttr(Words.Text('changeAvatarPopup-title', 'Change Avatar')) + '"><div class="content">';
  if Error <> '' then
  begin
    Msg := StringReplace(Words.Text(Error, Error), '__size__', '72 KB', [rfReplaceAll]);
    Result := Result + '<div class="warning">' + E(Msg) + '</div>';
  end;
  Result := Result + '<ul class="pop-over-list avatar-list">';
  for i := 0 to High(R) do
  begin
    Item := '/cdn/storage/avatars/' + R[i][0];
    Result := Result + '<li class="avatar-list-item' + IfThen(Item = Current, ' selected', '') + '">' +
      '<form method="post" action="/profile/avatar/select" class="js-avatar-select-form"><input type="hidden" name="avatarId" value="' +
      HtmlAttr(R[i][0]) + '"><button type="submit" class="js-select-avatar avatar-list-select" title="' + HtmlAttr(R[i][1]) +
      '"><span class="member"><img class="avatar avatar-image" src="' + HtmlAttr(Item) + '" alt=""></span><span class="avatar-list-info">' +
      '<span class="avatar-list-name">' + E(R[i][1]) + '</span></span>' + IfThen(Item = Current, '<i class="fa fa-check avatar-list-check"></i>', '') +
      '</button></form><form method="post" action="/profile/avatar/delete" class="js-avatar-delete-form"><input type="hidden" name="avatarId" value="' +
      HtmlAttr(R[i][0]) + '"><button type="submit" class="js-delete-avatar avatar-list-delete" data-avatar-id="' + HtmlAttr(R[i][0]) +
      '" title="' + HtmlAttr(Words.Text('delete', 'Delete')) + '" data-confirm="' + HtmlAttr(Words.Text('delete-avatar-confirm',
      'Are you sure you want to delete this avatar?')) + '"><i class="fa fa-trash"></i></button></form></li>';
  end;
  Result := Result + '<li class="avatar-list-item' + IfThen(Current = '', ' selected', '') + '"><form method="post" action="/profile/avatar/select" ' +
    'class="js-avatar-select-form"><input type="hidden" name="avatarId" value=""><button type="submit" class="js-select-initials avatar-list-select">' +
    '<span class="avatar-list-info"><span class="avatar-list-name">' + E(Words.Text('initials', 'Initials')) + '</span> <span class="sub-name">' +
    E(Words.Text('default-avatar', 'Default avatar')) + '</span></span>' + IfThen(Current = '', '<i class="fa fa-check avatar-list-check"></i>', '') +
    '</button></form></li></ul>';
  if not AvatarUploadBlocked(Db) then
    Result := Result + '<form method="post" action="/profile/avatar" enctype="multipart/form-data" class="js-avatar-upload-form">' +
      '<input class="js-upload-avatar-input" type="file" name="avatar" accept="image/png,image/jpeg,image/gif,image/webp" required>' +
      '<p class="avatar-upload-hints">' + E(Words.Text('max-avatar-filesize', 'Max avatar filesize in bytes:')) + ' ' + IntToStr(MAX_AVATAR_BYTES) +
      '<br>' + E(Words.Text('allowed-avatar-filetypes', 'Allowed avatar filetypes:')) + ' PNG, JPEG, GIF, WebP</p>' +
      '<button type="submit" class="full primary js-upload-avatar"><i class="fa fa-upload"></i> ' + E(Words.Text('upload-avatar', 'Upload an avatar')) +
      '</button></form>';
  Result := Result + '</div></template>';
  if Error <> '' then Result := Result + '<span class="js-open-pop-on-load" data-pop="change-avatar" hidden></span>';
end;

// changeAvatarPopup's choice: one of the user's own avatars, or '' for the
// initials (WeKan's setAvatarUrl / setAvatarUrl('')).
function SelectAvatar(Db: TWLDb; const UserId, AvatarId: string): Boolean;
begin
  EnsureAvatarTable(Db);
  if AvatarId = '' then Exit(SetProfileField(Db, UserId, 'avatarUrl', ''));
  if (Pos(#0, AvatarId) > 0) or (Length(Db.Query('SELECT 1 FROM _wl_avatars WHERE id=' + QuotedStr(AvatarId) + ' AND userId=' +
    QuotedStr(UserId) + ';')) <> 1) then Exit(False);
  Result := SetProfileField(Db, UserId, 'avatarUrl', '"/cdn/storage/avatars/' + AvatarId + '"');
end;

// deleteAvatarPopup's Delete: one of the user's own avatars, its file and its
// row; the profile back to the initials when it was the one shown.
function DeleteAvatar(const T: TWLTenant; const UserId, AvatarId: string): Boolean;
var Raw, Tbl: string;
begin
  EnsureAvatarTable(T.Db);
  if (AvatarId = '') or (Pos(#0, AvatarId) > 0) or (Length(T.Db.Query('SELECT 1 FROM _wl_avatars WHERE id=' + QuotedStr(AvatarId) +
    ' AND userId=' + QuotedStr(UserId) + ';')) <> 1) then Exit(False);
  if not T.Db.Exec('DELETE FROM _wl_avatars WHERE id=' + QuotedStr(AvatarId) + ';') then Exit(False);
  DeleteFile(StoreFilePath(T.FilesDir, 'avatars', AvatarId));
  if IsShared(T.Db) then
  try
    T.Db.Exec('DELETE FROM avatars WHERE id=' + QuotedStr(AvatarId) + ';');
  except
  end;
  if ProfileField(T.Db, UserId, 'avatarUrl') = '/cdn/storage/avatars/' + AvatarId then SetProfileField(T.Db, UserId, 'avatarUrl', '');
  Result := True;
end;

// /cdn/storage/avatars/:id[/original/:name]: an uploaded avatar, for a
// signed-in user - or for anybody when its owner is on a public board
// (WeKan's Avatars.protected; refused otherwise, as PortraitBleed). Only the picture it is, never
// a page (nosniff, sandboxed). An anonymous request for an avatar there is
// none of is refused and recorded (RelicAvatarBleed).
function ServeAvatarFile(Request: TRequest; Response: TResponse; const Path: string): Boolean;
var T: TWLTenant; S: TWLSession; P: TStringArray; Id: string; R: TWLRows; Signed: Boolean; i: Integer;
begin
  Result := False;
  P := PathParts(Path);
  if (Length(P) < 4) or (P[0] <> 'cdn') or (P[1] <> 'storage') or (P[2] <> 'avatars') then Exit;
  if not ((Length(P) = 4) or ((Length(P) = 6) and (P[4] = 'original'))) then Exit;
  if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
  Result := True;
  Id := P[3];
  i := Pos('-original-', Id);
  if i > 0 then Id := Copy(Id, 1, i - 1);
  for i := 1 to Length(Id) do
    if not (Id[i] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then begin SendJsonAnswer(Response, 404, '{"error":"Avatar not found"}'); Exit; end;
  Signed := Html5User(T.Db, Request, S);
  EnsureAvatarTable(T.Db);
  R := T.Db.Query('SELECT userId,type,name FROM _wl_avatars WHERE id=' + QuotedStr(Id) + ';');
  if Length(R) <> 1 then
  begin
    if not Signed then
    begin
      try
        RecordSecurityEvent(T.Db, '', 'RelicAvatarBleed', '/cdn/storage/avatars/:fileName', 'authz', 'high', 'CWE-862', 'blocked',
          'refused an unauthenticated request for an avatar that is not there');
      except
        // logging must never break the guard
      end;
      SendJsonAnswer(Response, 401, '{"error":"Authentication required"}');
    end
    else SendJsonAnswer(Response, 404, '{"error":"Avatar not found"}');
    Exit;
  end;
  // Avatars.protected: anybody, when the owner is on a public board.
  if not Signed and (Length(T.Db.Query('SELECT 1 FROM boards b JOIN board_members m ON m.boardId=b.id WHERE b.permission=''public'' AND ' +
    'm.userId=' + QuotedStr(R[0][0]) + ' AND m.isActive=1 LIMIT 1;')) = 0) then
  begin
    try
      RecordSecurityEvent(T.Db, '', 'PortraitBleed', 'Avatars.protected', 'authz', 'high', 'CWE-862', 'blocked',
        'refused an anonymous download of a non-public avatar');
    except
      // logging must never break the guard
    end;
    SendJsonAnswer(Response, 401, '{"error":"Authentication required"}');
    Exit;
  end;
  Response.SetCustomHeader('Content-Security-Policy', 'default-src ''none''; style-src ''unsafe-inline''; sandbox');
  if not SendStoredDownload(Response, StoreFilePath(T.FilesDir, 'avatars', Id), R[0][2], R[0][1]) then
    SendJsonAnswer(Response, 404, '{"error":"Avatar file not found in storage"}');
end;

// WeKan's file route, /cdn/storage/attachments/:id[/original/:name or
// /thumbnail]: an attachment of a live card on a board the signed-in user may
// read. Only a raster image is shown inline (SendStoredDownload); ?download=
// and every other file come as a download, with nosniff.
function ServeAttachmentFile(Request: TRequest; Response: TResponse; const Path: string): Boolean;
var T: TWLTenant; S: TWLSession; P: TStringArray; Rows: TWLRows; Preview, Removed: string; Changed: Boolean;
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
    // Unaliased: LiveAttachmentSQL names attachments itself.
    Rows := T.Db.Query('SELECT attachments.boardId,COALESCE(attachments.name,''''),COALESCE(attachments.type,'''') FROM attachments ' +
      'JOIN cards c ON c.id=attachments.cardId AND c.boardId=attachments.boardId AND c.archived=0 AND c.deletedAt IS NULL ' +
      'WHERE attachments.id=' + QuotedStr(P[3]) + ' AND ' +
      LiveAttachmentSQL(T.Db) + ';');
    if (Length(Rows) = 1) and not BoardCanRead(T.Db, S.UserId, Rows[0][0]) then Rows := nil;
  end;
  // An SVG: sanitized again on its way out, whatever is stored
  // (server/lib/svgResponse.js); one stored with active content is recorded.
  if (Length(Rows) = 1) and IsSvg(Rows[0][2], Rows[0][1]) and
    SendSvgImage(Response, StoreFilePath(T.FilesDir, 'attachme', P[3]), Rows[0][1], Request.QueryFields.Values['download'] <> '',
      Changed, Removed) then
  begin
    if Changed then
    try
      RecordSecurityEvent(T.Db, S.UserId, 'FileBleed', 'fileView', 'file', 'medium', 'CWE-79', 'sanitized',
        'removed active content (JavaScript / XML) from file content "' + Rows[0][1] + '": ' + Removed);
    except { logging must never break serving } end;
    Exit;
  end;
  Preview := '';
  if (Length(Rows) = 1) and (Request.QueryFields.Values['download'] = '') and not IsSvg(Rows[0][2], Rows[0][1]) then Preview := Rows[0][2];
  if (Length(Rows) = 1) and SendStoredDownload(Response, StoreFilePath(T.FilesDir, 'attachme', P[3]), Rows[0][1], Preview) then Exit;
  SendJsonAnswer(Response, 404, '{"error":"Attachment not found"}');
end;

type
  // The server's own response, whose connection a live board writes to.
  TLiveResponse = class(TFPHTTPConnectionResponse);

// What the board is now, as a short text that changes when the board does:
// its cards, lists, swimlanes, activities and rules.
function BoardSignature(Db: TWLDb; const BoardId: string): string;
var R: TWLRows; B: string;
begin
  B := QuotedStr(BoardId);
  // A soft delete and its undo change neither modifiedAt nor archived: the
  // live rows are counted too.
  R := Db.Query('SELECT (SELECT count(*)||max(COALESCE(modifiedAt,''''))||sum(archived)||''/''||sum(deletedAt IS NULL) FROM cards WHERE boardId=' + B + '),' +
    '(SELECT count(*)||max(COALESCE(modifiedAt,''''))||sum(archived)||''/''||sum(deletedAt IS NULL) FROM lists WHERE boardId=' + B + '),' +
    '(SELECT count(*)||max(COALESCE(modifiedAt,''''))||sum(archived) FROM swimlanes WHERE boardId=' + B + '),' +
    '(SELECT count(*)||max(createdAt) FROM activities WHERE boardId=' + B + '),' +
    // The board's fields kept in settings_json too: Card Settings' sides,
    // written by a database tool or another server without modifiedAt.
    '(SELECT COALESCE(modifiedAt,'''')||length(settings_json)||settings_json FROM boards WHERE id=' + B + ');');
  Result := '';
  if Length(R) = 1 then Result := R[0][0] + '|' + R[0][1] + '|' + R[0][2] + '|' + R[0][3] + '|' + R[0][4];
  Result := Result + '|' + RulesSignature(Db, BoardId) +
    // Admin Panel's date format draws every board's dates (wldatef).
    '|' + SharedSettingText(Db, 'globalDateFormat') + IfThen(SharedSettingOn(Db, 'hideDateFormat'), '+', '-');
end;

// weddy.js' live board: GET /b/:id/live?p=<page>, an event stream that says
// "board-changed <page that changed it>" whenever the board changes, so every
// open page of the board draws it again - another user's change, or a rule's.
// The stream ends after five minutes; EventSource opens it again.
procedure ServeLiveBoard(const T: TWLTenant; Response: TResponse; const BoardId: string);
var Last, Now_: string; i: Integer; Line: string; Socket: TSocketStream; Waits: Boolean; B: Byte;
begin
  Response.Code := 200;
  Response.ContentType := 'text/event-stream';
  Response.SetCustomHeader('Cache-Control', 'no-store');
  Response.SetCustomHeader('Connection', 'close');
  Response.SetCustomHeader('X-Accel-Buffering', 'no');
  Response.SendHeaders;
  if not (Response is TFPHTTPConnectionResponse) then begin Response.Content := ''; Response.SendContent; Exit; end;
  Socket := TLiveResponse(Response).Connection.Socket;
  Last := BoardSignature(T.Db, BoardId);
  // The second between two looks is a read with a one-second timeout: an
  // EventSource sends nothing after its request, so the read ends at the
  // timeout, or at once with 0 when the page has closed the stream - which
  // then ends here, not at the next ping up to 15 seconds later (a stopping
  // server waited for it). Without a read timeout, a plain wait.
  try
    Socket.IOTimeout := 1000;
    Waits := True;
  except
    Waits := False;
  end;
  try
    Line := 'retry: 2000'#10': live'#10#10;
    Socket.WriteBuffer(Line[1], Length(Line));
    for i := 1 to 300 do
    begin
      if not Waits then Sleep(1000)
      else if Socket.Read(B, 1) = 0 then Break;
      Now_ := BoardSignature(T.Db, BoardId);
      if Now_ <> Last then
      begin
        Last := Now_;
        Line := 'event: board-changed'#10'data: board-changed ' + RecentWriterPage + #10#10;
        Socket.WriteBuffer(Line[1], Length(Line));
      end
      else if i mod 15 = 0 then
      begin
        Line := ': ping'#10#10;
        Socket.WriteBuffer(Line[1], Length(Line));
      end;
    end;
  except
    // The page went away: the stream ends with it.
  end;
  Response.Content := '';
  Response.ContentLength := 0;
  Response.SendContent;
end;

function ServeHtml5Action(Request: TRequest; Response: TResponse): Boolean;
var T: TWLTenant; S: TWLSession; Language: TWLLanguage; Words: TWLTranslator;
  Path, BoardId, CardId, ChecklistId, ItemId, NewId, Action, Error, Content, BoardTitle, Title, Back, Columns, Values, Sets: string;
  P: TStringArray; Code, n: Integer; Found: Boolean; Proof: TWLLoginProof;
begin
  ReadBoardView(Request);
  Result := False;
  // weddy.js's GET /b/:id/places (the move and copy pop-overs' other board),
  // before WeKan's routes take /b/:id/:slug: the board's swimlanes and lists.
  // The date pop-overs as they stand now (welite.js asks when one opens): a
  // page's templates are drawn with it, and Admin Panel's or the board's
  // format may have changed since.
  if (Request.Method = 'GET') and (Request.PathInfo = '/date-settings') and ResolveTenant(Request, T) and TenantOpen(T) and
    Html5User(T.Db, Request, S) then
  begin
    Result := True;
    BoardId := Request.QueryFields.Values['board'];
    if (BoardId <> '') and not BoardCanRead(T.Db, S.UserId, BoardId) then
    begin SendJsonAnswer(Response, 404, '{"error":"not found"}'); Exit; end;
    Language := ViewerLanguage(T.Db, S, Request);
    Words := TWLTranslator.Create(Language);
    try
      if Request.QueryFields.Values['scope'] = 'board' then
      begin
        if BoardId = '' then begin SendJsonAnswer(Response, 404, '{"error":"not found"}'); Exit; end;
        Content := DateFormatEditor(T.Db, Words, S.UserId, BoardId, False);
      end
      else Content := DateFormatEditor(T.Db, Words, S.UserId, BoardId, True);
    finally
      Words.Free;
    end;
    Response.Code := 200;
    Response.ContentType := 'text/html; charset=utf-8';
    Response.SetCustomHeader('Cache-Control', 'no-store');
    Response.Content := Content;
    SendResponse(Response);
    Exit;
  end;
  // A guest's page of a public board follows it live too (#3249).
  if (Request.Method = 'GET') and (Copy(Request.PathInfo, 1, 3) = '/b/') and (Request.CookieFields.Values[LOGIN_COOKIE] = '') then
  begin
    P := PathParts(Request.PathInfo);
    if (Length(P) = 3) and (P[2] = 'live') and ResolveTenant(Request, T) and TenantOpen(T) and BoardCanRead(T.Db, '', P[1]) then
    begin
      Result := True;
      ServeLiveBoard(T, Response, P[1]);
      Exit;
    end;
  end;
  if (Request.Method = 'GET') and (Copy(Request.PathInfo, 1, 3) = '/b/') and (Request.CookieFields.Values[LOGIN_COOKIE] <> '') then
  begin
    P := PathParts(Request.PathInfo);
    // The live board (weddy.js' EventSource).
    if (Length(P) = 3) and (P[2] = 'live') and ResolveTenant(Request, T) and TenantOpen(T) and Html5User(T.Db, Request, S) then
    begin
      Result := True;
      if BoardCanRead(T.Db, S.UserId, P[1]) then ServeLiveBoard(T, Response, P[1])
      else SendJsonAnswer(Response, 404, '{"error":"not found"}');
      Exit;
    end;
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
  // Member Settings' Change Password: the password now, then the new one
  // twice. Every session ends with it, this one too (WeKan's
  // passwordChangeRequired.js), so the viewer goes to sign in again.
  // Admin Panel / Problems / Password length's Save (wlprob): the minimum
  // and its enforcement, a site admin's; back to the page.
  if Path = '/admin/problems/password-length' then
  begin
    if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
    if not Html5User(T.Db, Request, S) then Exit;
    Result := True;
    Response.Code := 303;
    if not IsSiteAdmin(T.Db, S.UserId) then begin SendJsonAnswer(Response, 404, '{"error":"not found"}'); Exit; end;
    if SavePasswordLength(T.Db, Request.ContentFields.Values['minLength'], Request.ContentFields.Values['enforce']) then
      Response.SetCustomHeader('Location', '/admin/problems/password-length?saved=1')
    else
      Response.SetCustomHeader('Location', '/admin/problems/password-length?error=minLength');
    Response.SetCustomHeader('Cache-Control', 'no-store');
    SendResponse(Response);
    Exit;
  end;
  if Path = '/profile/password' then
  begin
    if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
    if not Html5User(T.Db, Request, S) then Exit;
    Result := True;
    Error := ''; Proof := nil;
    if Request.ContentFields.Values['newPassword'] <> Request.ContentFields.Values['newPassword2'] then Error := 'password-mismatch'
    // The password now is checked as a sign-in is, within the same limit,
    // so this form is no way round it to guess the password.
    else if not ReserveLoginAttempt(T.Db, S.Username, Request.RemoteAddress, DateTimeToUnix(Now, False)) then Error := 'login-refused-braked'
    else if not AuthenticateAccount(T.Db, S.Username, Request.ContentFields.Values['oldPassword'], '', Proof) then Error := 'login-refused-bad-password';
    Proof.Free;
    if Error = '' then
    begin
      Code := ViewSetPassword(T, S.UserId, S.UserId, Request.ContentFields.Values['newPassword'], Error);
      if (Code <> 200) and (Error <> 'error-password-policy') then Error := 'error-undefined';
      // Changed: no more required, and its short-password report fixed (wlprob).
      if Error = '' then EndPasswordChangeRequirement(T.Db, S.UserId);
    end;
    Response.Code := 303;
    if Error <> '' then Response.SetCustomHeader('Location', '/profile/password?error=' + HTTPEncode(Error))
    else
    begin
      Html5ClearLoginCookie(Response);
      Response.SetCustomHeader('Location', '/sign-in');
    end;
    Response.SetCustomHeader('Cache-Control', 'no-store');
    SendResponse(Response);
    Exit;
  end;
  // The notifications drawer's menu, from weddy.js: every notification of
  // the signed-in user read, or deleted.
  if (Path = '/notifications/read-all') or (Path = '/notifications/delete-all') then
  begin
    if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
    if not Html5User(T.Db, Request, S) then Exit;
    Result := True;
    if Path = '/notifications/read-all' then Found := MarkAllNotificationsRead(T.Db, S.UserId)
    else Found := DeleteAllNotifications(T.Db, S.UserId);
    if Found then SendJsonAnswer(Response, 200, '{"ok":true}')
    else SendJsonAnswer(Response, 500, '{"error":"Internal Server Error"}');
    Exit;
  end;
  // changeAvatarPopup's forms: an upload, a choice, a delete; back where
  // they were sent from, a refused upload with its reason.
  if (Path = '/profile/avatar') or (Path = '/profile/avatar/select') or (Path = '/profile/avatar/delete') then
  begin
    if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
    if not Html5User(T.Db, Request, S) then Exit;
    Result := True;
    Error := '';
    if Path = '/profile/avatar' then
    begin
      UploadAvatar(T, S.UserId, Request, Error);
    end
    else if Path = '/profile/avatar/select' then
    begin
      if not SelectAvatar(T.Db, S.UserId, Request.ContentFields.Values['avatarId']) then Error := 'error-undefined';
    end
    else if not DeleteAvatar(T, S.UserId, Request.ContentFields.Values['avatarId']) then Error := 'error-undefined';
    Back := SafeReturnPath(Request.Referer);
    if Back = '' then Back := '/';
    if Pos('avatarError=', Back) > 0 then Back := Copy(Back, 1, Pos('avatarError=', Back) - 2);
    if Back = '' then Back := '/';
    if Error <> '' then
    begin
      if Pos('?', Back) > 0 then Back := Back + '&' else Back := Back + '?';
      Back := Back + 'avatarError=' + HTTPEncode(Error);
    end;
    Response.Code := 303;
    Response.SetCustomHeader('Location', Back);
    Response.SetCustomHeader('Cache-Control', 'no-store');
    SendResponse(Response);
    Exit;
  end;
  // editProfilePopup's form: the user's own name and initials, and the
  // username and address where they may be changed; back where it was sent from.
  if Path = '/profile' then
  begin
    if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
    if not Html5User(T.Db, Request, S) then Exit;
    Result := True;
    Code := ViewSetOwnProfile(T, S.UserId, Request.ContentFields.Values['fullname'], Request.ContentFields.Values['initials'], Error);
    Title := Trim(Request.ContentFields.Values['username']);
    if (Code = 200) and (Request.ContentFields.IndexOfName('username') >= 0) and (Title <> '') and (Title <> S.Username) then
      Code := ViewSetUsername(T, S.UserId, S.UserId, Title, Error);
    Title := LowerCase(Trim(Request.ContentFields.Values['email']));
    if (Code = 200) and (Request.ContentFields.IndexOfName('email') >= 0) and (Title <> '') and
      (Length(T.Db.Query('SELECT 1 FROM user_emails WHERE userId=' + QuotedStr(S.UserId) + ' AND lower(address)=' + QuotedStr(Title) + ';')) = 0) then
      Code := ViewSetEmail(T, S.UserId, S.UserId, Title, Error);
    Back := SafeReturnPath(Request.Referer);
    if Back = '' then Back := '/';
    if Code <> 200 then Back := '/?error=' + HTTPEncode(Error);
    Response.Code := 303;
    Response.SetCustomHeader('Location', Back);
    SendResponse(Response);
    Exit;
  end;
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
      SendResponse(Response);
      Exit;
    end;
    Response.Code := 303;
    if Code = 200 then Response.SetCustomHeader('Location', '/admin/people')
    else Response.SetCustomHeader('Location', '/admin/people?error=' + HTTPEncode(Error));
    SendResponse(Response);
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
  //   /b/:id/archive/restore                          an archived card, list or swimlane back (kind=, id=, toList=)
  //   /b/:id/archive/restore-all-cards                every archived card whose list has room back
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
    not ((P[2] = 'cards') or ((P[2] = 'archive') and (n = 4) and ((P[3] = 'restore') or (P[3] = 'restore-all-cards'))) or ((P[2] = 'title') and (n = 3)) or ((P[2] = 'watch') and (n = 3)) or ((P[2] = 'visibility') and (n = 3)) or ((P[2] = 'members') and ((n = 3) or ((n = 5) and (P[4] = 'remove')))) or (((P[2] = 'lists') or (P[2] = 'labels') or (P[2] = 'swimlanes') or (P[2] = 'custom-fields')) and (n = 3))) then Exit;
  BoardId := P[1]; CardId := ''; ChecklistId := ''; ItemId := '';
  Title := Request.ContentFields.Values['title'];
  if (n = 3) and (P[2] = 'lists') then Action := 'add-list'
  else if (n = 3) and (P[2] = 'labels') then Action := 'add-label'
  else if (n = 3) and (P[2] = 'title') then Action := 'rename-board'
  else if (n = 4) and (P[2] = 'archive') and (P[3] = 'restore-all-cards') then Action := 'restore-all'
  else if (n = 4) and (P[2] = 'archive') then Action := 'restore'
  else if (n = 3) and (P[2] = 'swimlanes') then Action := 'add-swimlane'
  else if (n = 3) and (P[2] = 'custom-fields') then Action := 'add-custom-field'
  else if (n = 3) and (P[2] = 'watch') then Action := 'watch-board'
  else if (n = 3) and (P[2] = 'visibility') then Action := 'visibility'
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
  else if (n = 5) and (P[4] = 'complete') then Action := 'complete'
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
  begin
    Code := RestoreViewItem(T, S.UserId, BoardId, Request.ContentFields.Values['kind'], Request.ContentFields.Values['id'],
      Request.ContentFields.Values['toList'], Error);
    // Its list filled up since the page was drawn: the board again, with
    // the card's "restore it to another list" open.
    if (Code = 409) and (Error = 'restore-blocked') then
    begin ViewRestoreBlocked := Request.ContentFields.Values['id']; Code := 200; end;
  end
  else if Action = 'restore-all' then
    Code := RestoreAllViewCards(T, S.UserId, BoardId, ViewRestoreSkipped, Error)
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
  else if Action = 'visibility' then
    Code := SetViewBoardVisibility(T, S.UserId, BoardId, Request.ContentFields.Values['visibility'], Error)
  else if Action = 'watch-card' then
    Code := WatchViewCard(T, S.UserId, BoardId, CardId, Error)
  else if Action = 'watch-board' then
    Code := WatchViewBoard(T, S.UserId, BoardId, Request.QueryFields.Values['level'], Error)
  else if Action = 'poker' then
    Code := PokerViewCard(T, S.UserId, BoardId, CardId, Request.ContentFields.Values['state'], Error)
  else if Action = 'complete' then
  begin
    Code := SetViewCardComplete(T, S.UserId, BoardId, CardId, Request.ContentFields.Values['complete'] = 'true', Error);
    // weddy.js redraws the board itself: no page for it.
    if Code = 200 then
    begin
      Response.Code := 204;
      SendResponse(Response);
      Exit;
    end;
  end
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
    if (Action = 'rename-board') or (Action = 'visibility') then
    begin
      Response.Code := 303;
      Response.SetCustomHeader('Location', BoardRoute(BoardId, BoardSlug(T.Db, BoardId)));
      SendResponse(Response);
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

// Meteor's Accounts.verifyEmail (#1426): the link's token, of an account that
// has it, not older than 30 days (emailVerificationTokenExpirationInDays),
// marks its address verified and is used up; the account is then signed in
// as WeKan does it - unless it needs a second factor, which a link cannot
// give (IssueLoginToken refuses it). False for any other token.
function VerifyEmailToken(Db: TWLDb; const Token: string; out UserId, LoginToken: string): Boolean;
var R: TWLRows; Address, Ref, Cutoff: string;
begin
  Result := False; UserId := ''; LoginToken := '';
  if (Token = '') or (Length(Token) > 200) or (Pos(#0, Token) > 0) then Exit;
  Cutoff := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', LocalTimeToUniversal(Now) - 30);
  R := Db.Query('SELECT u.id,json_extract(t.value,''$.address''),COALESCE(json_extract(u.services_json,''$.password''),'''') FROM users u,' +
    'json_each(CASE WHEN json_valid(u.services_json) THEN u.services_json ELSE ''{}'' END,''$.email.verificationTokens'') t ' +
    'WHERE json_extract(t.value,''$.token'')=' + QuotedStr(Token) + ' AND COALESCE(u.loginDisabled,0)=0 AND (CASE json_type(t.value,''$.when'') ' +
    'WHEN ''text'' THEN json_extract(t.value,''$.when'')>=' + QuotedStr(Cutoff) + ' ELSE 1 END) LIMIT 2;');
  if Length(R) <> 1 then Exit;
  UserId := R[0][0]; Address := R[0][1];
  if not Db.Exec('BEGIN IMMEDIATE; UPDATE user_emails SET verified=1 WHERE userId=' + QuotedStr(UserId) + ' AND lower(address)=lower(' +
    QuotedStr(Address) + '); UPDATE users SET services_json=json_set(services_json,''$.email.verificationTokens'',json((SELECT json_group_array(json(value)) ' +
    'FROM json_each(services_json,''$.email.verificationTokens'') WHERE json_extract(value,''$.token'') IS NOT ' + QuotedStr(Token) + '))) WHERE id=' +
    QuotedStr(UserId) + '; COMMIT;') then
  begin Db.Exec('ROLLBACK;'); Exit; end;
  Result := True;
  // Signed in with WeKan's own login token - a resume token, as a REST or
  // Meteor login gives one, which the login cookie carries.
  Ref := CredentialFingerprint(R[0][2]);
  LoginToken := NewAuthToken;
  if (Ref = '') or not IssueLoginToken(Db, UserId, LoginToken, Ref, 'api', ApiTokenLifetime(Db)) then LoginToken := '';
end;

function ServeHtml5(Request: TRequest; Response: TResponse): Boolean;
var T: TWLTenant; S: TWLSession; Language: TWLLanguage; Words: TWLTranslator;
  Path, Title, BoardTitle, Content, Section, Verified, LoginToken: string; Found, SignedIn: Boolean;
  procedure Send(Code: Integer; const Html: string);
  begin
    Response.Code := Code;
    Response.ContentType := 'text/html; charset=utf-8';
    Response.SetCustomHeader('Cache-Control', 'no-store');
    Response.Content := Html;
    Response.ContentLength := Length(Response.Content);
    SendResponse(Response);
  end;
begin
  ReadBoardView(Request);
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
  if Copy(Path, 1, 21) = '/cdn/storage/avatars/' then
  begin
    Result := ServeAvatarFile(Request, Response, Path);
    Exit;
  end;
  // An address's verification link: verified and signed in, or to sign-in.
  if Copy(Path, 1, 14) = '/verify-email/' then
  begin
    if not (ResolveTenant(Request, T) and TenantOpen(T)) then Exit;
    Result := True;
    if VerifyEmailToken(T.Db, Copy(Path, 15, MaxInt), Verified, LoginToken) and (LoginToken <> '') then
      Html5SignedIn(Response, LoginToken)
    else
    begin
      Response.Code := 302;
      Response.SetCustomHeader('Location', '/sign-in');
      SendResponse(Response);
    end;
    Exit;
  end;
  // The root arrives as an empty PathInfo.
  if Path = '' then Path := '/';
  if not ((Path = '/') or (Path = '/sign-in') or (Path = '/register') or (Path = '/board') or (Path = '/board/card') or
    (Path = '/allboards') or (Copy(Path, 1, 11) = '/allboards/') or (Path = '/people') or (Path = '/admin/people') or
    (Path = '/board/rules') or (Path = '/board/rules/export') or (Path = '/admin/problems/security-report') or
    (Path = '/admin/problems/password-length') or (Path = '/admin/settings/appearance') or (Path = '/admin/settings/visibility') or
    (Path = '/profile/password') or (Path = '/language/popup')) then Exit;
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
    if Path = '/register' then
    begin
      Words.Free;
      Words := nil;
      Html5SignUpPage(Request, Response, 200, '', '', '', '');
      Exit;
    end;
    // A public board is anybody's to read (#3249, WeKan's
    // readableWithoutMembership); every other page wants a sign-in.
    if not SignedIn and not (((Path = '/board') or (Path = '/board/card')) and
      BoardCanRead(T.Db, '', Request.QueryFields.Values['id'])) then
    begin
      Response.Code := 302;
      Response.SetCustomHeader('Location', '/sign-in');
      SendResponse(Response);
      Exit;
    end;
    if Path = '/language/popup' then
    begin
      Send(200, LanguagePopup(Words, Language));
      Exit;
    end;
    // A password shorter than an enforced minimum is changed first: every
    // other page is that request (WeKan's passwordChangeRequired).
    if (Path <> '/profile/password') and PasswordChangeRequired(T.Db, S.UserId) then
    begin
      Send(200, Page(Request, Language, Words, S, Words.Text('password-change-required-title', 'Change your password'), '',
        PasswordChangeRequiredContent(T.Db, Words)));
      Exit;
    end;
    // Admin Panel / Problems / Password length (wlprob), a site admin's.
    if Path = '/admin/problems/password-length' then
    begin
      if not IsSiteAdmin(T.Db, S.UserId) then
        Send(404, Page(Request, Language, Words, S, Words.Text('error-notAuthorized', 'You are not authorized to view this page.'), '',
          '<div class="big-message quiet"><h1>' + E(Words.Text('error-notAuthorized', 'You are not authorized to view this page.')) + '</h1></div>'))
      else
        Send(200, Page(Request, Language, Words, S, Words.Text('password-length-report-title', 'Password length'), '',
          PasswordLengthContent(T.Db, Words, Language.Tag, Request.QueryFields)));
      Exit;
    end;
    // Admin Panel / Settings / Appearance, a site admin's.
    if (Path = '/admin/settings/appearance') or (Path = '/admin/settings/visibility') then
    begin
      if not IsSiteAdmin(T.Db, S.UserId) then
        Send(404, Page(Request, Language, Words, S, Words.Text('error-notAuthorized', 'You are not authorized to view this page.'), '',
          '<div class="big-message quiet"><h1>' + E(Words.Text('error-notAuthorized', 'You are not authorized to view this page.')) + '</h1></div>'))
      else
        Send(200, Page(Request, Language, Words, S, Words.Text('layout', 'Layout'), '', AppearanceContent(T.Db, Words)));
      Exit;
    end;
    if Path = '/profile/password' then
    begin
      Send(200, Page(Request, Language, Words, S, Words.Text('changePasswordPopup-title', 'Change Password'), '',
        ChangePasswordContent(T.Db, Words, Request.QueryFields.Values['error'])));
      Exit;
    end;
    // Admin Panel / Problems / Security Report (wlprob), a site admin's.
    if Path = '/admin/problems/security-report' then
    begin
      if not IsSiteAdmin(T.Db, S.UserId) then
        Send(404, Page(Request, Language, Words, S, Words.Text('error-notAuthorized', 'You are not authorized to view this page.'), '',
          '<div class="big-message quiet"><h1>' + E(Words.Text('error-notAuthorized', 'You are not authorized to view this page.')) + '</h1></div>'))
      else
        Send(200, Page(Request, Language, Words, S, Words.Text('securityReportTitle', 'Security Report'), '',
          SecurityReportContent(T.Db, Words, Language.Tag, Request.QueryFields.Values['q'],
          StrToIntDef(Request.QueryFields.Values['page'], 1))));
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
    // The Rules page's downloads: the rules as JSON or CSV, the board as a
    // Wrike workflow (wlrules).
    if Path = '/board/rules/export' then
    begin
      if RulesExport(T.Db, S.UserId, Request.QueryFields.Values['id'], Request.QueryFields.Values['format'],
        Request.QueryFields.Values['ids'], Content, Section, Title) then
      begin
        Response.Code := 200;
        Response.ContentType := Section;
        Response.SetCustomHeader('Content-Disposition', 'attachment; filename="' + Title + '"');
        Response.SetCustomHeader('Cache-Control', 'no-store');
        Response.Content := Content;
        Response.ContentLength := Length(Content);
        SendResponse(Response);
      end
      else
        Send(404, Page(Request, Language, Words, S, Words.Text('board-not-found', 'Board not found'), '', NotFoundContent(Words)));
      Exit;
    end;
    // WeKan's rulesMain: the board's Rules page (wlrules).
    if Path = '/board/rules' then
    begin
      Content := '';
      if T.Db.BeginRead then
      try
        Content := RulesPageContent(T.Db, S.UserId, Request.QueryFields.Values['id'], Request.QueryFields.Values['view'], Words,
          Language.Tag, BoardTitle);
      finally
        T.Db.EndRead;
      end;
      if Content = '' then
        Send(404, Page(Request, Language, Words, S, Words.Text('board-not-found', 'Board not found'), '', NotFoundContent(Words)))
      else
        Send(200, Page(Request, Language, Words, S, Words.Text('rules', 'Rules'), '', Content));
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

procedure Html5SignUpPage(Request: TRequest; Response: TResponse; Code: Integer; const ErrorKey, Fallback, Username, Email: string);
var Language: TWLLanguage; Words: TWLTranslator; Error: string; T: TWLTenant; MinLength: Integer; Enforce: Boolean;
begin
  MinLength := 0; Enforce := False;
  if ResolveTenant(Request, T) and TenantOpen(T) then PasswordPolicy(T.Db, MinLength, Enforce);
  // Not enforced, the form keeps WeKan's own minimum (config/accounts.js).
  if not Enforce then MinLength := 6;
  Language := ViewerLanguage(nil, Default(TWLSession), Request);
  Words := TWLTranslator.Create(Language);
  try
    Error := '';
    if ErrorKey <> '' then Error := Words.Text(ErrorKey, Fallback);
    SendPage(Response, Code, Page(Request, Language, Words, Default(TWLSession), Words.Text('register', 'Register'), '',
      SignUpContent(Words, Error, Username, Email, MinLength)));
  finally
    Words.Free;
  end;
end;

procedure ResetViewState;
begin
  ViewDateFormat := '';
  ViewBoardId := '';
  ViewMinicardPieces := nil;
  ViewCardDates := nil;
  ViewRestoreBlocked := '';
  ViewRestoreSkipped := 0;
end;

end.
