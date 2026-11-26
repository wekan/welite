unit wlprob;

{
  WeKan-Lite — the Admin Panel's Problems for the HTML5 view: the Security
  Report (WeKan's adminProblems.jade eventStreamReport, stream "security"),
  Weddy's securityreport.pug drawn by wltpl.

  Each row is one kind of attempt that a guard refused or noticed - its
  bleed, source, the most recent account and how many times - never a row
  per attempt (models/lib/eventLogSummary.js). A site admin's page: anybody
  else is told they may not see it.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses SysUtils, Classes, fpjson, wldb, wli18n;

const
  SECURITY_REPORT_PER_PAGE = 50;

// The Security Report's content: rows matching Search (category, bleed,
// source, detail, username, IP, severity or action contain it, any case),
// newest first, the Page'th SECURITY_REPORT_PER_PAGE of them.
function SecurityReportContent(Db: TWLDb; Words: TWLTranslator; const Lang, Search: string; Page: Integer): string;

// Admin Panel / Problems / Password length (WeKan's passwordLengthReport and
// server/shortPasswordLogins.js), on a shared store.
//
// After a password sign-in that worked: a password shorter than the minimum
// is reported - one row an account, counted, with the address and both
// sign-in times - and, while the minimum is enforced, the account must
// change it. A report never stops the sign-in.
procedure NoteSignInPassword(Db: TWLDb; const UserId, Username, Password, Address: string);
// Whether the account must change its password before anything else: the
// minimum is enforced and its last sign-in was shorter.
function PasswordChangeRequired(Db: TWLDb; const UserId: string): Boolean;
// The account changed its own password: required no more, and its open
// report fixed (a row fixed already keeps its first date).
procedure EndPasswordChangeRequirement(Db: TWLDb; const UserId: string);
// The page: the minimum and its enforcement, and the report by Filter
// (short, fixed or all) and Search, ten rows a page.
function PasswordLengthContent(Db: TWLDb; Words: TWLTranslator; const Lang: string; Query: TStrings): string;
// The page's Save: MinLength 1 to 256 (empty takes the environment's back),
// Enforce 'true' or not. False for a minimum out of range.
function SavePasswordLength(Db: TWLDb; const MinLength, Enforce: string): Boolean;
// What the required change shows in place of every page.
function PasswordChangeRequiredContent(Db: TWLDb; Words: TWLTranslator): string;
// The shared store's settings document of Id, each of Fields set (a null
// removes it), the rest as it was.
function SaveSettingsFields(Db: TWLDb; const Id: string; Fields: TJSONObject): Boolean;

implementation

uses DateUtils, StrUtils, Math, httpdefs, wlcfjson, wlsjson, wltpl, wlcase, wlshared, wlhtml;

{$I tpl/securityreport.inc}
{$I tpl/passwordlength.inc}

function Field(const Name: string): string;
begin
  Result := 'json_extract(_ferretdb_sjson,''$.' + Name + ''')';
end;

function Text(Doc: TJSONObject; const Name: string): string;
var V: TJSONData;
begin
  Result := '';
  V := Doc.Find(Name);
  if V = nil then Exit;
  case V.JSONType of
    jtString: Result := V.AsString;
    jtNumber: Result := V.AsJSON;
  end;
end;

function SecurityReportContent(Db: TWLDb; Words: TWLTranslator; const Lang, Search: string; Page: Integer): string;
var R: TWLRows; Tbl, Where, Needle, Name: string; Total, Pages, i: Integer; Data, Row: TJSONObject; Rows: TJSONArray;
  Doc: TJSONObject; Count: Int64; At: TJSONData;
  function Link(P: Integer): string;
  begin
    Result := '/admin/problems/security-report?page=' + IntToStr(P);
    if Search <> '' then Result := Result + '&q=' + HTTPEncode(Search);
  end;
begin
  Total := 0; Rows := TJSONArray.Create;
  Data := TJSONObject.Create;
  try
    Data.Add('L', Lang);
    Data.Add('SecuritySearch', Search);
    Data.Add('SecurityRows', Rows);
    R := Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''eventlog'';');
    if Length(R) = 1 then
    begin
      Tbl := '"' + StringReplace(R[0][0], '"', '""', [rfReplaceAll]) + '"';
      Where := Field('stream') + '=''security''';
      if Search <> '' then
      begin
        Needle := QuotedStr('%' + StringReplace(StringReplace(Utf8Lower(Search), '%', '\%', [rfReplaceAll]), '_', '\_', [rfReplaceAll]) + '%');
        Where := Where + ' AND (';
        for Name in ['category', 'bleed', 'source', 'detail', 'username', 'ip', 'severity', 'action'] do
          Where := Where + IfThen(Name <> 'category', ' OR ', '') + 'lower(COALESCE(' + Field(Name) + ','''')) LIKE ' + Needle + ' ESCAPE ''\''';
        Where := Where + ')';
      end;
      R := Db.Query('SELECT count(*) FROM ' + Tbl + ' WHERE ' + Where + ';');
      if Length(R) = 1 then Total := StrToIntDef(R[0][0], 0);
      Pages := (Total + SECURITY_REPORT_PER_PAGE - 1) div SECURITY_REPORT_PER_PAGE;
      if Pages < 1 then Pages := 1;
      if Page < 1 then Page := 1;
      if Page > Pages then Page := Pages;
      R := Db.Query('SELECT json(_ferretdb_sjson) FROM ' + Tbl + ' WHERE ' + Where + ' ORDER BY ' + Field('at') + ' DESC LIMIT ' +
        IntToStr(SECURITY_REPORT_PER_PAGE) + ' OFFSET ' + IntToStr((Page - 1) * SECURITY_REPORT_PER_PAGE) + ';');
      for i := 0 to High(R) do
      begin
        try
          Doc := DocumentJson(R[i][0]);
        except
          Continue;
        end;
        try
          Row := TJSONObject.Create(['Category', Text(Doc, 'category'), 'Bleed', Text(Doc, 'bleed'), 'Severity', Text(Doc, 'severity'),
            'Action', Text(Doc, 'action'), 'Source', Text(Doc, 'source'), 'Username', Text(Doc, 'username'), 'IP', Text(Doc, 'ip'),
            'Detail', Text(Doc, 'detail')]);
          // The date as Weddy shows it: UTC, "2006-01-02 15:04:05".
          At := Doc.Find('at');
          if (At <> nil) and (At.JSONType = jtString) then
            Row.Add('Date', StringReplace(Copy(At.AsString, 1, 19), 'T', ' ', []))
          else Row.Add('Date', '');
          Count := 0;
          if (Doc.Find('count') <> nil) and (Doc.Find('count').JSONType = jtNumber) then Count := Doc.Find('count').AsInt64;
          if Count > 1 then Row.Add('Attempts', IntToStr(Count)) else Row.Add('Attempts', '');
          Rows.Add(Row);
        finally
          Doc.Free;
        end;
      end;
    end
    else Pages := 1;
    if Page < 1 then Page := 1;
    Data.Add('SecurityTotal', IntToStr(Total));
    Data.Add('SecurityPage', IntToStr(Page));
    Data.Add('SecurityPages', IntToStr(Pages));
    if Page > 1 then Data.Add('SecurityPrev', Link(Page - 1)) else Data.Add('SecurityPrev', '');
    if Page < Pages then Data.Add('SecurityNext', Link(Page + 1)) else Data.Add('SecurityNext', '');
    Result := RenderTemplate(TPL_SECURITYREPORT, Data, Words, Lang);
  finally
    Data.Free;
  end;
end;

function Q(const S: string): string;
begin
  Result := QuotedStr(S);
end;

function CollectionTable(Db: TWLDb; const Name: string; out Raw, Quoted: string): Boolean;
var R: TWLRows;
begin
  Raw := ''; Quoted := '';
  Result := False;
  if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';')) <> 1 then Exit;
  R := Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=' + Q(Name) + ';');
  if Length(R) <> 1 then Exit;
  Raw := R[0][0];
  Quoted := '"' + StringReplace(Raw, '"', '""', [rfReplaceAll]) + '"';
  Result := True;
end;

function Literal(const Raw, Typed: string): string;
begin
  Result := 'CASE WHEN wl_storage(' + Q(Raw) + ')=''blob'' THEN jsonb(' + Q(Typed) + ') ELSE ' + Q(Typed) + ' END';
end;

// The document of the collection that Where (SQL over the document) finds:
// Fields set on it - a null removes one - its other fields and types kept.
// Insert, when there is none, makes it from Insert. True when written.
function WriteDoc(Db: TWLDb; const Collection, Where: string; Fields: TJSONObject; Insert: TJSONObject; const Hints: string): Boolean;
var Raw, Tbl, Previous: string; R: TWLRows; Plain: TJSONObject; i: Integer;
begin
  Result := False;
  if not CollectionTable(Db, Collection, Raw, Tbl) then Exit;
  R := Db.Query('SELECT json(_ferretdb_sjson),json_extract(_ferretdb_sjson,''$._id'') FROM ' + Tbl + ' WHERE ' + Where + ' LIMIT 1;');
  if Length(R) = 0 then
  begin
    if Insert = nil then Exit;
    Result := Db.Exec('INSERT INTO ' + Tbl + '(_ferretdb_sjson) VALUES(' + Literal(Raw, TypedDocument(Insert.AsJSON, '', Hints)) + ');');
    Exit;
  end;
  Previous := R[0][0];
  Plain := ExactObject(PlainDocument(Previous));
  try
    for i := 0 to Fields.Count - 1 do
    begin
      Plain.Delete(Fields.Names[i]);
      if Fields.Items[i].JSONType <> jtNull then Plain.Add(Fields.Names[i], Fields.Items[i].Clone);
    end;
    Result := Db.Exec('UPDATE ' + Tbl + ' SET _ferretdb_sjson=' + Literal(Raw, TypedDocument(Plain.AsJSON, Previous, Hints)) +
      ' WHERE json_extract(_ferretdb_sjson,''$._id'')=' + Q(R[0][1]) + ';');
  finally
    Plain.Free;
  end;
end;

function NowMs: Int64;
var At: TDateTime;
begin
  At := LocalTimeToUniversal(Now);
  Result := DateTimeToUnix(At, True) * 1000 + MilliSecondOf(At);
end;

// JavaScript's String length of a UTF-8 text: one for each UTF-16 unit.
function JsLength(const S: string): Integer;
var i: Integer; C: Byte;
begin
  Result := 0;
  for i := 1 to Length(S) do
  begin
    C := Ord(S[i]);
    if C < $80 then Inc(Result)
    else if C >= $F0 then Inc(Result, 2)
    else if C >= $C0 then Inc(Result);
  end;
end;

function NewDocId: string;
const A = '23456789ABCDEFGHJKLMNPQRSTWXYZabcdefghijkmnopqrstuvwxyz';
var i: Integer;
begin
  SetLength(Result, 17);
  for i := 1 to 17 do Result[i] := A[Random(Length(A)) + 1];
end;

function PasswordAccount(Db: TWLDb; const UserId: string): Boolean;
begin
  Result := Length(Db.Query('SELECT 1 FROM users WHERE id=' + Q(UserId) + ' AND COALESCE(authenticationMethod,''password'') IN ' +
    '(''password'','''') AND (json_extract(services_json,''$.password.bcrypt'') IS NOT NULL OR ' +
    'json_extract(services_json,''$.password.argon2'') IS NOT NULL);')) = 1;
end;

procedure NoteSignInPassword(Db: TWLDb; const UserId, Username, Password, Address: string);
var MinLength: Integer; Enforce: Boolean; Fields, Insert: TJSONObject; Stamp: Int64; V4, V6, Raw, Tbl: string; R: TWLRows;
begin
  try
    PasswordPolicy(Db, MinLength, Enforce);
    if JsLength(Password) >= MinLength then Exit;
    if not PasswordAccount(Db, UserId) then Exit;
    Stamp := NowMs;
    V4 := ''; V6 := '';
    if Pos(':', Address) > 0 then
    begin
      if Copy(LowerCase(Address), 1, 7) = '::ffff:' then V4 := Copy(Address, 8, MaxInt) else V6 := Address;
    end
    else V4 := Address;
    Fields := TJSONObject.Create(['at', Stamp, 'username', Username, 'fixedAt', TJSONNull.Create]);
    Insert := TJSONObject.Create(['_id', NewDocId, 'userId', UserId, 'username', Username, 'count', 1, 'firstAt', Stamp, 'at', Stamp]);
    try
      if V4 <> '' then begin Fields.Add('ipv4', V4); Insert.Add('ipv4', V4); end;
      if V6 <> '' then begin Fields.Add('ipv6', V6); Insert.Add('ipv6', V6); end;
      // A row that is there: its count one more.
      if CollectionTable(Db, 'shortPasswordLogins', Raw, Tbl) then
      begin
        R := Db.Query('SELECT COALESCE(json_extract(_ferretdb_sjson,''$.count''),0) FROM ' + Tbl +
          ' WHERE json_extract(_ferretdb_sjson,''$.userId'')=' + Q(UserId) + ' LIMIT 1;');
        if Length(R) = 1 then Fields.Add('count', StrToInt64Def(R[0][0], 0) + 1);
      end;
      WriteDoc(Db, 'shortPasswordLogins', 'json_extract(_ferretdb_sjson,''$.userId'')=' + Q(UserId), Fields, Insert,
        '{"at":"date","firstAt":"date"}');
    finally
      Fields.Free;
      Insert.Free;
    end;
    if Enforce then
    begin
      Fields := TJSONObject.Create(['passwordChangeRequired', True]);
      try
        WriteDoc(Db, 'users', 'json_extract(_ferretdb_sjson,''$._id'')=' + Q(UserId), Fields, nil, '{}');
      finally
        Fields.Free;
      end;
    end;
  except
    // A report never stops the sign-in.
  end;
end;

function PasswordChangeRequired(Db: TWLDb; const UserId: string): Boolean;
var MinLength: Integer; Enforce: Boolean; Raw, Tbl: string;
begin
  Result := False;
  try
    PasswordPolicy(Db, MinLength, Enforce);
    if not Enforce or not CollectionTable(Db, 'users', Raw, Tbl) then Exit;
    Result := (Length(Db.Query('SELECT 1 FROM ' + Tbl + ' WHERE json_extract(_ferretdb_sjson,''$._id'')=' + Q(UserId) +
      ' AND json_type(_ferretdb_sjson,''$.passwordChangeRequired'')=''true'';')) = 1) and PasswordAccount(Db, UserId);
  except
    Result := False;
  end;
end;

procedure EndPasswordChangeRequirement(Db: TWLDb; const UserId: string);
var Fields: TJSONObject;
begin
  try
    Fields := TJSONObject.Create(['passwordChangeRequired', TJSONNull.Create]);
    try
      WriteDoc(Db, 'users', 'json_extract(_ferretdb_sjson,''$._id'')=' + Q(UserId), Fields, nil, '{}');
    finally
      Fields.Free;
    end;
    Fields := TJSONObject.Create(['fixedAt', NowMs]);
    try
      WriteDoc(Db, 'shortPasswordLogins', 'json_extract(_ferretdb_sjson,''$.userId'')=' + Q(UserId) +
        ' AND json_type(_ferretdb_sjson,''$.fixedAt'') IS NULL', Fields, nil, '{"fixedAt":"date"}');
    finally
      Fields.Free;
    end;
  except
    // The change itself is done; its report follows it when it can.
  end;
end;

function SavePasswordLength(Db: TWLDb; const MinLength, Enforce: string): Boolean;
var Raw, Tbl, Previous: string; R: TWLRows; Plain, Options: TJSONObject; N: Integer; V: TJSONData;
begin
  Result := False;
  if (Trim(MinLength) <> '') and (not TryStrToInt(Trim(MinLength), N) or (N < 1) or (N > 256)) then Exit;
  if not CollectionTable(Db, 'settings', Raw, Tbl) then Exit;
  R := Db.Query('SELECT json(_ferretdb_sjson),json_extract(_ferretdb_sjson,''$._id'') FROM ' + Tbl + ' LIMIT 1;');
  if Length(R) <> 1 then Exit;
  Previous := R[0][0];
  Plain := ExactObject(PlainDocument(Previous));
  try
    V := Plain.Find('loginOptions');
    if V is TJSONObject then Options := TJSONObject(V)
    else
    begin
      Plain.Delete('loginOptions');
      Options := TJSONObject.Create;
      Plain.Add('loginOptions', Options);
    end;
    Options.Delete('passwordMinLength');
    if Trim(MinLength) <> '' then Options.Add('passwordMinLength', N);
    Options.Delete('passwordMinLengthEnforce');
    Options.Add('passwordMinLengthEnforce', Enforce = 'true');
    Result := Db.Exec('UPDATE ' + Tbl + ' SET _ferretdb_sjson=' + Literal(Raw, TypedDocument(Plain.AsJSON, Previous, '{}')) +
      ' WHERE json_extract(_ferretdb_sjson,''$._id'')=' + Q(R[0][1]) + ';');
  finally
    Plain.Free;
  end;
end;

function DateOf(Doc: TJSONObject; const Name: string): string;
var V: TJSONData;
begin
  Result := '';
  V := Doc.Find(Name);
  if (V <> nil) and (V.JSONType = jtString) then Result := StringReplace(Copy(V.AsString, 1, 16), 'T', ' ', []);
end;

function PasswordLengthContent(Db: TWLDb; Words: TWLTranslator; const Lang: string; Query: TStrings): string;
const PER = 10;
var Data, Row, Doc: TJSONObject; Rows, Filters: TJSONArray; Filter, Search, Raw, Tbl, Where, Needle, Value: string;
  MinLength, Page, Pages, Total, i: Integer; Enforce: Boolean; R: TWLRows;
  function Link(P: Integer): string;
  begin
    Result := '/admin/problems/password-length?filter=' + Filter + '&page=' + IntToStr(P);
    if Search <> '' then Result := Result + '&q=' + HTTPEncode(Search);
  end;
begin
  Filter := Query.Values['filter'];
  if (Filter <> 'fixed') and (Filter <> 'all') then Filter := 'short';
  Search := Copy(Trim(Query.Values['q']), 1, 100);
  Page := StrToIntDef(Query.Values['page'], 1);
  if Page < 1 then Page := 1;
  PasswordPolicy(Db, MinLength, Enforce);
  Data := TJSONObject.Create(['L', Lang, 'MinLength', MinLength, 'Enforce', Enforce, 'Saved', Query.Values['saved'] <> '',
    'Filter', Filter, 'Search', Search]);
  try
    if Query.Values['error'] <> '' then
      Data.Add('SaveError', Words.Text('password-min-length', 'Minimum password length') + ': 1 - 256');
    Filters := TJSONArray.Create;
    for Value in ['short', 'fixed', 'all'] do
      Filters.Add(TJSONObject.Create(['Value', Value, 'Label', Words.Text('password-length-filter-' + Value, Value)]));
    Data.Add('Filters', Filters);
    Rows := TJSONArray.Create;
    Data.Add('Rows', Rows);
    Total := 0;
    if CollectionTable(Db, 'shortPasswordLogins', Raw, Tbl) then
    begin
      if Filter = 'fixed' then Where := 'json_type(_ferretdb_sjson,''$.fixedAt'') IN (''integer'',''real'',''text'')'
      else if Filter = 'all' then Where := '1'
      else Where := 'COALESCE(json_type(_ferretdb_sjson,''$.fixedAt''),''null'')=''null''';
      if Search <> '' then
      begin
        Needle := Q('%' + Utf8Lower(Search) + '%');
        Where := Where + ' AND (lower(COALESCE(json_extract(_ferretdb_sjson,''$.username''),'''')) LIKE ' + Needle +
          ' OR lower(COALESCE(json_extract(_ferretdb_sjson,''$.ipv4''),'''')) LIKE ' + Needle +
          ' OR lower(COALESCE(json_extract(_ferretdb_sjson,''$.ipv6''),'''')) LIKE ' + Needle + ')';
      end;
      R := Db.Query('SELECT count(*) FROM ' + Tbl + ' WHERE ' + Where + ';');
      if Length(R) = 1 then Total := StrToIntDef(R[0][0], 0);
      Pages := Max(1, (Total + PER - 1) div PER);
      if Page > Pages then Page := Pages;
      R := Db.Query('SELECT json(_ferretdb_sjson) FROM ' + Tbl + ' WHERE ' + Where + ' ORDER BY json_extract(_ferretdb_sjson,''$.at'') DESC LIMIT ' +
        IntToStr(PER) + ' OFFSET ' + IntToStr((Page - 1) * PER) + ';');
      for i := 0 to High(R) do
      begin
        try
          Doc := DocumentJson(R[i][0]);
        except
          Continue;
        end;
        try
          Value := Doc.Get('username', '');
          if Value = '' then Value := Doc.Get('userId', '');
          Row := TJSONObject.Create(['Username', Value, 'First', DateOf(Doc, 'firstAt'), 'Last', DateOf(Doc, 'at'),
            'Fixed', DateOf(Doc, 'fixedAt'), 'IPv4', Doc.Get('ipv4', ''), 'IPv6', Doc.Get('ipv6', '')]);
          if (Doc.Find('count') <> nil) and (Doc.Find('count').JSONType = jtNumber) then Row.Add('Count', Doc.Find('count').AsInt64)
          else Row.Add('Count', 0);
          Rows.Add(Row);
        finally
          Doc.Free;
        end;
      end;
    end
    else Pages := 1;
    Data.Add('Total', Total);
    Data.Add('Page', Page);
    Data.Add('Pages', Pages);
    if Page > 1 then Data.Add('Prev', Link(Page - 1)) else Data.Add('Prev', '');
    if Page < Pages then Data.Add('Next', Link(Page + 1)) else Data.Add('Next', '');
    Result := RenderTemplate(TPL_PASSWORDLENGTH, Data, Words, Lang);
  finally
    Data.Free;
  end;
end;

function PasswordChangeRequiredContent(Db: TWLDb; Words: TWLTranslator): string;
var MinLength: Integer; Enforce: Boolean; Min: string;
begin
  // Weddy's profile.pug: WeKan's passwordChangeRequired dialog, its own form.
  PasswordPolicy(Db, MinLength, Enforce);
  Min := IntToStr(MinLength);
  Result := '<div class="setting-content profile"><div class="js-password-change-required password-change-required at-form">' +
    '<h2>' + HtmlEncode(Words.Text('password-change-required-title', 'Change your password')) + '</h2>' +
    '<p>' + HtmlEncode(StringReplace(Words.Text('password-change-required-text', 'Choose a longer password.'), '__min__', Min, [rfReplaceAll])) + '</p>' +
    '<form class="js-password-change-required-form" method="post" action="/profile/password">' +
    '<label for="at-field-current_password">' + HtmlEncode(Words.Text('password', 'Password')) + '</label>' +
    '<input id="at-field-current_password" type="password" name="oldPassword" autocomplete="current-password" required>' +
    '<label for="at-field-password">' + HtmlEncode(Words.Text('change-password', 'Change password')) + '</label>' +
    '<input id="at-field-password" type="password" name="newPassword" autocomplete="new-password" minlength="' + Min + '" required>' +
    '<label for="at-field-password_again">' + HtmlEncode(Words.Text('password-again', 'Password (again)')) + '</label>' +
    '<input id="at-field-password_again" type="password" name="newPassword2" autocomplete="new-password" minlength="' + Min + '" required>' +
    '<button id="at-btn" class="at-btn primary" type="submit">' + HtmlEncode(Words.Text('change-password', 'Change password')) + '</button>' +
    '</form></div></div>';
end;

function SaveSettingsFields(Db: TWLDb; const Id: string; Fields: TJSONObject): Boolean;
begin
  Result := (Id <> '') and (Pos(#0, Id) = 0) and WriteDoc(Db, 'settings', 'json_extract(_ferretdb_sjson,''$._id'')=' + Q(Id), Fields, nil, '{}');
end;

end.
