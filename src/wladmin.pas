unit wladmin;

{
  WeKan-Lite — Global Admin Panel (docs/goals.md G8)

  Three sections, gated to the Global Admin (the first registered user of a tenant, users.isAdmin=1):

    /admin           panel index (links to the three sections)
    /admin/domains   the served-domain registry (wlregist, data/admin): add / enable / disable
    /designer        the data-driven page editor (wldesign) — reached from the panel nav
    /admin/people    the tenant's users: promote/demote Global Admin, enable/disable login

  Same retro contract as the rest of WeKan-Lite (docs/goals.md G4): HTML 3.2 baseline, no JS,
  no cookies. Every mutating action is a <form> POST carrying a wlauth action-token, and each
  one PRG-redirects back to its listing so tokens regenerate. v0.1 reference skeleton.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, Classes, HTTPDefs, wldb, wltenant, wlauth, wlhtml;

// True when the session's user is a Global Admin (users.isAdmin = 1) in the given tenant db.
function IsGlobalAdmin(Db: TWLDb; const S: TWLSession): Boolean;

procedure AdminIndex(aRequest: TRequest; aResponse: TResponse);     // GET  /admin
procedure AdminDomains(aRequest: TRequest; aResponse: TResponse);   // GET/POST /admin/domains
procedure AdminPeople(aRequest: TRequest; aResponse: TResponse);    // GET/POST /admin/people

implementation

uses
  StrUtils, DateUtils, wlregist;

function NowIso: string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Now);
end;

procedure SendHtml(aResponse: TResponse; const Body: string);
begin
  aResponse.Code := 200;
  aResponse.ContentType := 'text/html; charset=utf-8';
  aResponse.Content := Body;
  aResponse.ContentLength := Length(aResponse.Content);
  aResponse.SendContent;
end;

function IsGlobalAdmin(Db: TWLDb; const S: TWLSession): Boolean;
var Rows: TWLRows;
begin
  Result := False;
  if (Db = nil) or (S.UserId = '') then Exit;
  Rows := Db.Query(Format('SELECT isAdmin FROM users WHERE id=%s LIMIT 1;',
                          [QuotedStr(S.UserId)]));
  Result := (Length(Rows) > 0) and (Length(Rows[0]) > 0) and (Rows[0][0] = '1');
end;

// Resolve tenant + session and require the Global Admin role. Sends the right error response
// (404 unknown domain / 302 to sign-in / 403 forbidden) and returns False when access is denied.
function RequireGlobalAdmin(aRequest: TRequest; aResponse: TResponse;
  out T: TWLTenant; out S: TWLSession): Boolean;
begin
  Result := False;
  if not (ResolveTenant(aRequest, T) and TenantOpen(T)) then
  begin
    aResponse.Code := 404; aResponse.ContentType := 'text/plain';
    aResponse.Content := 'Unknown domain'; aResponse.SendContent; Exit;
  end;
  ValidateSession(T.Db, aRequest, SessionIdFromRequest(aRequest), S);
  if S.UserId = '' then
  begin
    aResponse.Code := 302;
    aResponse.SetCustomHeader('Location', '/sign-in');
    aResponse.SendContent; Exit;
  end;
  if not IsGlobalAdmin(T.Db, S) then
  begin
    aResponse.Code := 403; aResponse.ContentType := 'text/html; charset=utf-8';
    aResponse.Content := Page32('Forbidden',
      '<h1>Forbidden</h1><p>Global Admin only.</p><p><a href="/">Home</a></p>');
    aResponse.SendContent; Exit;
  end;
  Result := True;
end;

// ------------------------------------------------------------------ shared chrome
function NavLink(const Href, Caption, SessionId: string; Active: Boolean): string;
begin
  if Active then
    Result := '<b>' + HtmlEncode(Caption) + '</b>'
  else
    Result := '<a href="' + HtmlAttr(WithSessionId(Href, SessionId)) + '">' +
              HtmlEncode(Caption) + '</a>';
end;

// Wrap a section body in the panel page with the Domains | Designer | People nav.
function AdminLayout(const S: TWLSession; const Active, Title, Body: string): string;
var Nav: string;
begin
  Nav := '<p>[ ' +
    NavLink('/admin/domains', 'Domains',  S.SessionId, SameText(Active, 'domains')) + ' | ' +
    NavLink('/designer',      'Designer', S.SessionId, SameText(Active, 'designer')) + ' | ' +
    NavLink('/admin/people',  'People',   S.SessionId, SameText(Active, 'people')) +
    ' ]</p><hr>';
  Result := Page32('Global Admin — ' + Title,
    '<h1>Global Admin Panel</h1>' + Nav + Body);
end;

// A one-button POST form (action + a single id field) carrying the section's action-token.
function ActionButton(const S: TWLSession; const ActionPath, TokenName, Action,
  IdName, IdValue, Caption: string): string;
begin
  Result := '<form method="POST" action="' + HtmlAttr(ActionPath) +
            '" style="display:inline">' + AuthHiddenFields(S, TokenName) +
    '<input type="hidden" name="action" value="' + HtmlAttr(Action) + '">' +
    '<input type="hidden" name="' + HtmlAttr(IdName) + '" value="' + HtmlAttr(IdValue) + '">' +
    '<input type="submit" value="' + HtmlAttr(Caption) + '"></form>';
end;

// ------------------------------------------------------------------ /admin
procedure AdminIndex(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; S: TWLSession;
begin
  if not RequireGlobalAdmin(aRequest, aResponse, T, S) then Exit;
  SendHtml(aResponse, AdminLayout(S, '', 'Home',
    '<p>Welcome, ' + HtmlEncode(S.Username) + '. Choose a section:</p>' +
    '<ul>' +
    '<li>' + NavLink('/admin/domains', 'Domains', S.SessionId, False) +
      ' &mdash; register and enable/disable served domains.</li>' +
    '<li>' + NavLink('/designer', 'Designer', S.SessionId, False) +
      ' &mdash; edit data-driven pages.</li>' +
    '<li>' + NavLink('/admin/people', 'People', S.SessionId, False) +
      ' &mdash; manage users and roles.</li>' +
    '</ul>'));
end;

// ------------------------------------------------------------------ /admin/domains
procedure AdminDomains(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; S: TWLSession;
  Rows: TWLRows;
  Body, Action, Host, Enabled, Created: string;
  i: Integer;
begin
  if not RequireGlobalAdmin(aRequest, aResponse, T, S) then Exit;

  if aRequest.Method = 'POST' then
  begin
    if not VerifyActionToken(aRequest, S, 'admin:domains') then
    begin
      aResponse.Code := 403; aResponse.Content := 'Bad token'; aResponse.SendContent; Exit;
    end;
    Action := aRequest.ContentFields.Values['action'];
    Host   := NormalizeHost(aRequest.ContentFields.Values['host']);
    if Host <> '' then
      case Action of
        'add':     RegistryAddDomain(Host);
        'enable':  RegistrySetEnabled(Host, True);
        'disable': RegistrySetEnabled(Host, False);
      end;
    aResponse.Code := 302;
    aResponse.SetCustomHeader('Location', WithSessionId('/admin/domains', S.SessionId));
    aResponse.SendContent; Exit;
  end;

  Rows := RegistryListDomains;
  Body := '<h2>Domains</h2>' +
    '<table border="1" cellpadding="4" cellspacing="0">' + LineEnding +
    '<tr><th>Host</th><th>Enabled</th><th>Created</th><th>Action</th></tr>' + LineEnding;
  for i := 0 to High(Rows) do
  begin
    if Length(Rows[i]) < 3 then Continue;
    Host := Rows[i][0]; Enabled := Rows[i][1]; Created := Rows[i][2];
    Body := Body + '<tr><td>' + HtmlEncode(Host) + '</td><td>' +
      IfThen(Enabled = '1', 'yes', 'no') + '</td><td>' + HtmlEncode(Created) + '</td><td>';
    if Enabled = '1' then
      Body := Body + ActionButton(S, '/admin/domains', 'admin:domains', 'disable', 'host', Host, 'Disable')
    else
      Body := Body + ActionButton(S, '/admin/domains', 'admin:domains', 'enable', 'host', Host, 'Enable');
    Body := Body + '</td></tr>' + LineEnding;
  end;
  if Length(Rows) = 0 then
    Body := Body + '<tr><td colspan="4"><i>No domains registered.</i></td></tr>' + LineEnding;
  Body := Body + '</table>' + LineEnding +
    '<h3>Add domain</h3>' +
    '<form method="POST" action="/admin/domains">' + AuthHiddenFields(S, 'admin:domains') +
    '<input type="hidden" name="action" value="add">' +
    ' Host <input name="host"> <input type="submit" value="Add"></form>' + LineEnding +
    '<p><small>localhost is always served as the built-in <b>local</b> tenant and ' +
    'need not be registered.</small></p>';
  SendHtml(aResponse, AdminLayout(S, 'domains', 'Domains', Body));
end;

// ------------------------------------------------------------------ /admin/people
procedure AdminPeople(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; S: TWLSession;
  Rows: TWLRows;
  Body, Action, Uid, Uname, IsAdm, Disabled, SetClause: string;
  i: Integer;
  SelfTarget: Boolean;
begin
  if not RequireGlobalAdmin(aRequest, aResponse, T, S) then Exit;

  if aRequest.Method = 'POST' then
  begin
    if not VerifyActionToken(aRequest, S, 'admin:people') then
    begin
      aResponse.Code := 403; aResponse.Content := 'Bad token'; aResponse.SendContent; Exit;
    end;
    Action := aRequest.ContentFields.Values['action'];
    Uid    := aRequest.ContentFields.Values['userId'];
    SelfTarget := (Uid <> '') and (Uid = S.UserId);
    SetClause := '';
    case Action of
      'promote': SetClause := 'isAdmin=1';
      'demote':  if not SelfTarget then SetClause := 'isAdmin=0';        // never self-demote
      'enable':  SetClause := 'loginDisabled=0';
      'disable': if not SelfTarget then SetClause := 'loginDisabled=1';  // never self-lockout
    end;
    if (Uid <> '') and (SetClause <> '') then
      T.Db.Exec(Format('UPDATE users SET %s, modifiedAt=%s WHERE id=%s;',
        [SetClause, QuotedStr(NowIso), QuotedStr(Uid)]));
    aResponse.Code := 302;
    aResponse.SetCustomHeader('Location', WithSessionId('/admin/people', S.SessionId));
    aResponse.SendContent; Exit;
  end;

  Rows := T.Db.Query('SELECT id, username, isAdmin, loginDisabled FROM users ORDER BY createdAt;');
  Body := '<h2>People</h2>' +
    '<table border="1" cellpadding="4" cellspacing="0">' + LineEnding +
    '<tr><th>Username</th><th>Role</th><th>Login</th><th>Actions</th></tr>' + LineEnding;
  for i := 0 to High(Rows) do
  begin
    if Length(Rows[i]) < 4 then Continue;
    Uid := Rows[i][0]; Uname := Rows[i][1]; IsAdm := Rows[i][2]; Disabled := Rows[i][3];
    SelfTarget := Uid = S.UserId;
    Body := Body + '<tr><td>' + HtmlEncode(Uname);
    if SelfTarget then Body := Body + ' <i>(you)</i>';
    Body := Body + '</td><td>' +
      IfThen(IsAdm = '1', 'Global Admin', 'Normal') + '</td><td>' +
      IfThen(Disabled = '1', 'disabled', 'enabled') + '</td><td>';
    // role toggle
    if IsAdm = '1' then
    begin
      if not SelfTarget then
        Body := Body + ActionButton(S, '/admin/people', 'admin:people', 'demote', 'userId', Uid, 'Make Normal');
    end
    else
      Body := Body + ActionButton(S, '/admin/people', 'admin:people', 'promote', 'userId', Uid, 'Make Global Admin');
    // login toggle
    if Disabled = '1' then
      Body := Body + ActionButton(S, '/admin/people', 'admin:people', 'enable', 'userId', Uid, 'Enable login')
    else if not SelfTarget then
      Body := Body + ActionButton(S, '/admin/people', 'admin:people', 'disable', 'userId', Uid, 'Disable login');
    Body := Body + '</td></tr>' + LineEnding;
  end;
  Body := Body + '</table>' + LineEnding +
    '<p><small>The first registered user is the Global Admin; new sign-ups are Normal users. ' +
    'You cannot demote or disable your own account.</small></p>';
  SendHtml(aResponse, AdminLayout(S, 'people', 'People', Body));
end;

end.
