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
  SysUtils, Classes, HTTPDefs, wldb, wltenant, wlauth, wlhtml, wlrevoke;

// True when the session's user is a tenant administrator (users.isAdmin = 1) in the given tenant db.
function IsTenantAdmin(Db: TWLDb; const S: TWLSession): Boolean;

// Shared tenant-local administrator gate for Admin Panel and Designer endpoints.
function RequireTenantAdmin(aRequest: TRequest; aResponse: TResponse;
  out T: TWLTenant; out S: TWLSession): Boolean;

// Domain management is reserved to administrators in the reserved admin tenant.
function RequireGlobalAdmin(aRequest: TRequest; aResponse: TResponse;
  out T: TWLTenant; out S: TWLSession): Boolean;

function MainNavigation(Db:TWLDb;const S:TWLSession;const LanguageTag:string;GlobalTenant:Boolean=False):string;

procedure AdminIndex(aRequest: TRequest; aResponse: TResponse);     // GET  /admin
procedure AdminDomains(aRequest: TRequest; aResponse: TResponse);   // GET/POST /admin/domains
procedure AdminPeople(aRequest: TRequest; aResponse: TResponse);    // GET/POST /admin/people

implementation

uses
  StrUtils, DateUtils, fpjson, wlregist, wllocale, wli18n, wlapi;

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

procedure AdminError(Request:TRequest;Response:TResponse;Db:TWLDb;const S:TWLSession;
  Code:Integer;const Message:string);
begin
  Response.Code:=Code;Response.ContentType:='text/html; charset=utf-8';
  Response.Content:=LanguagePage(Response,ViewerLanguage(Db,S,Request),
    'Admin','<p>'+HtmlEncode(Message)+'</p>');Response.SendContent;
end;

function IsTenantAdmin(Db: TWLDb; const S: TWLSession): Boolean;
var Rows: TWLRows;
begin
  Result := False;
  if (Db = nil) or (S.UserId = '') then Exit;
  Rows := Db.Query(Format('SELECT isAdmin FROM users WHERE id=%s AND loginDisabled=0 LIMIT 1;',
                          [QuotedStr(S.UserId)]));
  Result := (Length(Rows) > 0) and (Length(Rows[0]) > 0) and (Rows[0][0] = '1');
end;

// Resolve tenant + session and require the Global Admin role. Sends the right error response
// (404 unknown domain / 302 to sign-in / 403 forbidden) and returns False when access is denied.
function RequireTenantAdmin(aRequest: TRequest; aResponse: TResponse;
  out T: TWLTenant; out S: TWLSession): Boolean;
begin
  Result := False;
  if not (ResolveTenant(aRequest, T) and TenantOpen(T)) then
  begin
    aResponse.Code := 404; aResponse.ContentType := 'text/html; charset=utf-8';
    aResponse.Content := LanguagePage(aResponse,ViewerLanguage(nil,Default(TWLSession),aRequest),
      'Not found','<p>Unknown domain</p>'); aResponse.SendContent; Exit;
  end;
  if not ValidateSession(T.Db, aRequest, SessionIdFromRequest(aRequest), S) then
  begin
    aResponse.Code := 302;
    S.LanguageTag:=RequestLanguageTag(aRequest);
    aResponse.SetCustomHeader('Location',SessionUrl('/sign-in',S));
    aResponse.SendContent; Exit;
  end;
  if not IsTenantAdmin(T.Db, S) then
  begin
    aResponse.Code := 403; aResponse.ContentType := 'text/html; charset=utf-8';
    aResponse.Content := LanguagePage(aResponse,ViewerLanguage(T.Db,S,aRequest),'Forbidden',
      '<h1>Forbidden</h1><p>Tenant administrator only.</p><p><a href="'+HtmlAttr(SessionUrl('/',S))+'">Home</a></p>');
    aResponse.SendContent; Exit;
  end;
  Result := True;
end;

function RequireGlobalAdmin(aRequest: TRequest; aResponse: TResponse;
  out T: TWLTenant; out S: TWLSession): Boolean;
begin
  Result:=RequireTenantAdmin(aRequest,aResponse,T,S);
  if not Result then Exit;
  Result:=T.IsAdmin;
  if not Result then
  begin
    aResponse.Code:=403;
    aResponse.ContentType:='text/html; charset=utf-8';
    aResponse.Content:=LanguagePage(aResponse,ViewerLanguage(T.Db,S,aRequest),'Forbidden','<p>Domain management requires the reserved Global Admin tenant.</p>');
    aResponse.SendContent;
  end;
end;

function AdminRole(const T: TWLTenant): string;
begin
  if T.IsAdmin then Result:='Global Admin' else Result:='Domain Global Admin';
end;

function MainNavigation(Db:TWLDb;const S:TWLSession;const LanguageTag:string;GlobalTenant:Boolean):string;
var State:TWLSession;Words:TWLTranslator;
  function Item(const Path,Key,Caption:string):string;
  begin
    Result:='<td valign="middle">'+NavigationButton(Path,Words.Text(Key,Caption),State)+'</td>';
  end;
begin
  Result:='';
  if S.SessionId='' then Exit;
  State:=S;
  State.LanguageTag:=LanguageTag;
  Words:=TWLTranslator.Create(ResolveLanguage(LanguageTag,'',''));
  try
    Result:='<table border="0" cellpadding="2" cellspacing="0"><tr>'+
      Item('/','all-boards','All Boards');
    if IsTenantAdmin(Db,S) then
    begin
      Result:=Result+Item('/admin','admin-panel','Admin Panel')+
        Item('/designer','','Designer')+Item('/admin/people','people','People');
      if GlobalTenant then Result:=Result+Item('/admin/domains','domains','Domains');
    end;
    Result:=Result+'</tr></table>';
  finally Words.Free;end;
end;

// ------------------------------------------------------------------ shared chrome
function AdminLayout(const T:TWLTenant;const S:TWLSession;Request:TRequest;Response:TResponse;const Title,Body:string):string;
var Language:TWLLanguage;
begin
  Language:=ViewerLanguage(T.Db,S,Request);
  Result:=LanguagePage(Response,Language,AdminRole(T)+' — '+Title,
    '<h1>'+AdminRole(T)+' Panel</h1>'+MainNavigation(T.Db,S,Language.Tag,T.IsAdmin)+Body);
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
var T: TWLTenant; S: TWLSession; Body: string;
begin
  if not RequireTenantAdmin(aRequest,aResponse,T,S) then Exit;
  Body:='<p>Welcome, '+HtmlEncode(S.Username)+'. Choose a section:</p><ul>';
  if T.IsAdmin then Body:=Body+'<li>'+NavigationButton('/admin/domains','Domains',S)+
    ' &mdash; register and enable/disable served domains.</li>';
  Body:=Body+'<li>'+NavigationButton('/designer','Designer',S)+
    ' &mdash; edit this tenant''s pages.</li><li>'+NavigationButton('/admin/people','People',S)+
    ' &mdash; manage this tenant''s users and roles.</li></ul>';
  SendHtml(aResponse,AdminLayout(T,S,aRequest,aResponse,'Home',Body));
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

  if (aRequest.Method = 'POST') and ((aRequest.ContentFields.Values['nav_view']<>'1') or
    (aRequest.ContentFields.Values['action']<>'')) then
  begin
    if not VerifyActionToken(aRequest, S, 'admin:domains') then
    begin
      AdminError(aRequest,aResponse,T.Db,S,403,'Bad token');Exit;
    end;
    Action := aRequest.ContentFields.Values['action'];
    Host   := NormalizeHost(aRequest.ContentFields.Values['host']);
    if not RegistryValidHost(Host) then
    begin AdminError(aRequest,aResponse,T.Db,S,400,'Invalid or reserved domain');Exit; end;
    case Action of
      'add': begin
        if not RegistryAddDomain(Host) or not ProvisionTenant(Host) then
        begin
          RegistrySetEnabled(Host,False);
          AdminError(aRequest,aResponse,T.Db,S,500,'Could not provision domain');Exit;
        end;
      end;
      'enable': RegistrySetEnabled(Host,True);
      'disable': RegistrySetEnabled(Host,False);
    else begin AdminError(aRequest,aResponse,T.Db,S,400,'Unknown domain action');Exit; end;
    end;
    aResponse.Code := 302;
    aResponse.SetCustomHeader('Location', SessionUrl('/admin/domains',S));
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
  SendHtml(aResponse, AdminLayout(T,S,aRequest,aResponse, 'Domains', Body));
end;

function GroupFeatureTable(Db:TWLDb;const Kind,Title:string;Words:TWLTranslator):string;
const Suffixes:array[0..2] of string=('SharedTemplates','PropagateMembersToBoards','SyncMembersFromAuth');
var Groups:TJSONArray;Entry:TJSONObject;I,J:Integer;Flag,Checked:string;
begin
  Result:='';
  Groups:=ReadGroupFeatures(Db,Kind);
  try
    if Groups.Count=0 then Exit;
    Result:='<h2>'+HtmlEncode(Title)+'</h2><table border="1" cellpadding="4" cellspacing="0">'+
      '<tr><th>'+HtmlEncode(Words.Text('name','Name'))+'</th><th>'+
      HtmlEncode(Words.Text('shortName','Short Name'))+'</th><th>'+
      HtmlEncode(Words.Text('shared-templates','Shared templates'))+'</th><th>'+
      HtmlEncode(Words.Text(Kind+'-propagate-members-to-boards','Propagate members to boards'))+'</th><th>'+
      HtmlEncode(Words.Text(Kind+'-sync-members-from-auth','Sync members from auth provider'))+'</th></tr>';
    for I:=0 to Groups.Count-1 do
    begin
      Entry:=Groups.Objects[I];
      Result:=Result+'<tr data-group-id="'+HtmlAttr(Entry.Get('_id',''))+'"><td>'+
        HtmlEncode(Entry.Get(Kind+'DisplayName',''))+'</td><td>'+
        HtmlEncode(Entry.Get(Kind+'ShortName',''))+'</td>';
      for J:=Low(Suffixes) to High(Suffixes) do
      begin
        Flag:=Kind+Suffixes[J];
        Checked:='';
        if Entry.Get(Flag,False) then Checked:=' checked';
        Result:=Result+'<td><input type="checkbox" data-feature="'+HtmlAttr(Flag)+'" disabled'+Checked+'></td>';
      end;
      Result:=Result+'</tr>';
    end;
    Result:=Result+'</table>';
  finally Groups.Free;end;
end;

// ------------------------------------------------------------------ /admin/people
procedure AdminPeople(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; S: TWLSession;
  Rows: TWLRows;
  Body, Action, Uid, Uname, IsAdm, Disabled, SetClause: string;
  i: Integer;
  SelfTarget: Boolean;
  Words:TWLTranslator;
begin
  if not RequireTenantAdmin(aRequest, aResponse, T, S) then Exit;

  if (aRequest.Method = 'POST') and ((aRequest.ContentFields.Values['nav_view']<>'1') or
    (aRequest.ContentFields.Values['action']<>'')) then
  begin
    if not VerifyActionToken(aRequest, S, 'admin:people') then
    begin
      AdminError(aRequest,aResponse,T.Db,S,403,'Bad token');Exit;
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
    begin
      try
        if Action='disable' then SetClause:='BEGIN IMMEDIATE; '+RevokeUserTokensSQL(T.Db,Uid)+
          'UPDATE users SET '+SetClause+',modifiedAt='+QuotedStr(NowIso)+' WHERE id='+QuotedStr(Uid)+'; COMMIT;'
        else SetClause:=Format('UPDATE users SET %s,modifiedAt=%s WHERE id=%s;',[SetClause,QuotedStr(NowIso),QuotedStr(Uid)]);
      except
        AdminError(aRequest,aResponse,T.Db,S,500,'Could not update account');Exit;
      end;
      if not T.Db.Exec(SetClause) then
      begin T.Db.Exec('ROLLBACK;'); AdminError(aRequest,aResponse,T.Db,S,500,'Could not update account');Exit; end;
    end;
    aResponse.Code := 302;
    aResponse.SetCustomHeader('Location', SessionUrl('/admin/people',S));
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
      IfThen(IsAdm='1',AdminRole(T),'Normal') + '</td><td>' +
      IfThen(Disabled = '1', 'disabled', 'enabled') + '</td><td>';
    // role toggle
    if IsAdm = '1' then
    begin
      if not SelfTarget then
        Body := Body + ActionButton(S, '/admin/people', 'admin:people', 'demote', 'userId', Uid, 'Make Normal');
    end
    else
      Body := Body + ActionButton(S, '/admin/people', 'admin:people', 'promote', 'userId', Uid, 'Make '+AdminRole(T));
    // login toggle
    if Disabled = '1' then
      Body := Body + ActionButton(S, '/admin/people', 'admin:people', 'enable', 'userId', Uid, 'Enable login')
    else if not SelfTarget then
      Body := Body + ActionButton(S, '/admin/people', 'admin:people', 'disable', 'userId', Uid, 'Disable login');
    Body := Body + '</td></tr>' + LineEnding;
  end;
  Body := Body + '</table>' + LineEnding +
    '<p><small>New sign-ups are Normal users after the first tenant administrator. ' +
    'You cannot demote or disable your own account.</small></p>';
  Words:=TWLTranslator.Create(ViewerLanguage(T.Db,S,aRequest));
  try
    try
      Body:=Body+GroupFeatureTable(T.Db,'org',Words.Text('organizations','Organizations'),Words)+
        GroupFeatureTable(T.Db,'team',Words.Text('teams','Teams'),Words);
    except
      Body:=Body+'<p>'+HtmlEncode(Words.Text('error','Error'))+'</p>';
    end;
  finally Words.Free;end;
  SendHtml(aResponse, AdminLayout(T,S,aRequest,aResponse, 'People', Body));
end;

end.
