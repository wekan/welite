unit wlwkweb;

{
  WeKan-Lite — HTML4 pages for WeKan data folders (docs/wekandir.md)

    /wekan          the configured roots and the domains (WeKans) found in them, with sizes
    /wekan/boards   the boards of one domain's database
    /wekan/board    one board as a kanban: swimlanes x lists of cards
    /wekan/card     one card: description, checklists, comments, custom fields, attachments
    /wekan/file     an attachment: viewer (view=1), inline raster preview (preview=1) or download

  Read-only, through wlwkdir. The data is another server's, with its own accounts, so
  WeLite's board roles cannot apply to it: every page requires the Global Admin of the
  reserved admin tenant. No JavaScript and no cookies: links carry the session and
  language the way the rest of WeLite does.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses SysUtils, Classes, HTTPDefs;

procedure WeKanDataEndpoint(aRequest: TRequest; aResponse: TResponse);
procedure WeKanBoardsEndpoint(aRequest: TRequest; aResponse: TResponse);
procedure WeKanBoardEndpoint(aRequest: TRequest; aResponse: TResponse);
procedure WeKanCardEndpoint(aRequest: TRequest; aResponse: TResponse);
procedure WeKanFileEndpoint(aRequest: TRequest; aResponse: TResponse);

implementation

uses StrUtils, Math, fpjson, wldb, wltenant, wlauth, wladmin, wlhtml, wli18n, wllocale, wlcolors,
  wlstore, wlsjson, wlwkdir;

type
  TPage = record
    T: TWLTenant;
    S: TWLSession;
    Language: TWLLanguage;
    Words: TWLTranslator;
    Dir: string;
  end;

const
  PREVIEW_BYTES = 65536;

function Param(Request: TRequest; const Name: string): string;
begin
  Result := Request.QueryFields.Values[Name];
  if (Result = '') and (Request.Method = 'POST') then Result := Request.ContentFields.Values[Name];
end;

function Start(Request: TRequest; Response: TResponse; out P: TPage): Boolean;
begin
  P := Default(TPage);
  Result := RequireGlobalAdmin(Request, Response, P.T, P.S);
  if not Result then Exit;
  P.S.LanguageTag := RequestLanguageTag(Request);
  P.Language := ViewerLanguage(P.T.Db, P.S, Request);
  if P.Language.Rtl then P.Dir := 'rtl' else P.Dir := 'ltr';
  P.Words := TWLTranslator.Create(P.Language);
end;

function W(const P: TPage; const Key, Fallback: string): string;
begin
  Result := HtmlEncode(P.Words.Text(Key, Fallback));
end;

procedure Send(Response: TResponse; var P: TPage; const Title, Body: string; Code: Integer = 200);
begin
  Response.Code := Code;
  Response.ContentType := 'text/html; charset=utf-8';
  // The session travels in the URL: keep it out of caches and Referer headers.
  Response.SetCustomHeader('Cache-Control', 'no-store');
  Response.SetCustomHeader('Referrer-Policy', 'no-referrer');
  Response.SetCustomHeader('X-Content-Type-Options', 'nosniff');
  Response.Content := LanguagePage(Response, P.Language, Title,
    MainNavigation(P.T.Db, P.S, P.Language.Tag, P.T.IsAdmin) + Body, P.Dir, 'html4');
  Response.ContentLength := Length(Response.Content);
  Response.SendContent;
  FreeAndNil(P.Words);
end;

function Url(const P: TPage; const Path, Query: string): string;
begin
  if Query = '' then Result := SessionUrl(Path, P.S) else Result := SessionUrl(Path + '?' + Query, P.S);
end;

function Link(const P: TPage; const Path, Query, Caption: string): string;
begin
  Result := '<a href="' + HtmlAttr(Url(P, Path, Query)) + '">' + HtmlEncode(Caption) + '</a>';
end;

function SiteQuery(const Site: TWKSite; const DbName: string): string;
begin
  Result := 'root=' + IntToStr(Site.Root) + '&domain=' + HTTPEncode(Site.Domain) + '&db=' + HTTPEncode(DbName);
end;

function SiteName(const Site: TWKSite): string;
begin
  if Site.Domain <> '' then Result := Site.Domain
  else Result := ExtractFileName(ExcludeTrailingPathDelimiter(Site.Base));
end;

function Bytes(Value: Int64): string;
begin
  if Value >= 1024 * 1024 then
    Result := IntToStr(Value) + ' (' + FormatFloat('0.0', Value / (1024 * 1024)) + ' MiB)'
  else if Value >= 1024 then
    Result := IntToStr(Value) + ' (' + FormatFloat('0.0', Value / 1024) + ' KiB)'
  else Result := IntToStr(Value);
end;

function Lines(const Text: string): string;
begin
  // Card text is shown as text: escaped, with its line breaks kept.
  Result := StringReplace(StringReplace(HtmlEncode(Text), #13#10, #10, [rfReplaceAll]), #10, '<br>', [rfReplaceAll]);
end;

function Crumbs(const P: TPage; const Parts: array of string): string;
var I: Integer;
begin
  Result := '<p>' + Link(P, '/wekan', '', 'WeKan: ' + P.Words.Text('domains', 'Domains'));
  for I := 0 to High(Parts) do Result := Result + ' &gt; ' + Parts[I];
  Result := Result + ' &nbsp; <small>(' + W(P, 'read-only', 'Read Only') + ')</small></p>';
end;

// Resolve root/domain/db from the request against what wlwkdir found on disk.
function OpenSite(Request: TRequest; var P: TPage; out Site: TWKSite; out DbName: string; out Db: TWKDb): Boolean;
begin
  Db := nil;
  DbName := Param(Request, 'db');
  Result := WKFindSite(StrToIntDef(Param(Request, 'root'), -1), Param(Request, 'domain'), Site);
  if not Result then Exit;
  if DbName = '' then DbName := WKDefaultDatabase(Site);
  Db := WKOpen(Site, DbName);
  Result := Db <> nil;
end;

function NoDatabase(const P: TPage): string;
begin
  Result := '<p>' + W(P, 'wekan-data-no-database', 'No readable WeKan database was found.') + '</p>';
end;

{ ---------------------------------------------------------------- /wekan }

function AttachmentTotals(Db: TWKDb; out Count, Total: Int64): Boolean;
var Rows: TWLRows;
begin
  Count := 0; Total := 0; Result := True;
  if Db.Table('attachments') = '' then Exit;
  Rows := Db.Query('SELECT count(*) AS n, CAST(total(COALESCE(' + WKField('versions.original.size') + ',' +
    WKField('size') + ',0)) AS INTEGER) AS b FROM ' + Db.From('attachments') + ' WHERE ' + WKNotDeleted + ';');
  if (Length(Rows) = 1) and (Length(Rows[0]) = 2) then
  begin
    Count := StrToInt64Def(Rows[0][0], 0); Total := StrToInt64Def(Rows[0][1], 0);
  end;
end;

procedure WeKanDataEndpoint(aRequest: TRequest; aResponse: TResponse);
var P: TPage; Roots: TStringArray; Sites: TWKSites; Site: TWKSite; Db: TWKDb;
  Body, DbName, DbFile, Row: string; I, Files: Integer; Count, Total, FolderBytes: Int64;
  Shown: Boolean;
begin
  if not Start(aRequest, aResponse, P) then Exit;
  Body := Crumbs(P, []) + '<h1>WeKan: ' + W(P, 'domains', 'Domains') + '</h1>';
  Roots := WKRoots;
  Sites := WKSites;
  if Length(Roots) = 0 then Body := Body + '<p>' + W(P, 'no-results', 'No results') + '</p>';
  for I := 0 to High(Roots) do
  begin
    Body := Body + '<h2>' + W(P, 'path', 'Path') + ': ' + HtmlEncode(Roots[I]) + '</h2>' +
      '<table border="1" cellpadding="4" cellspacing="0"><tr><th>' + W(P, 'domain', 'Domain') + '</th><th>' +
      W(P, 'continuous-backup-database', 'Database') + '</th><th>' + W(P, 'boards', 'Boards') + '</th><th>' +
      W(P, 'cards', 'Cards') + '</th><th>' + W(P, 'attachments', 'Attachments') + '</th><th>' +
      W(P, 'total-size', 'Total Size') + '</th><th>' + W(P, 'continuous-backup-database', 'Database') + ': ' +
      W(P, 'size-bytes', 'Size (bytes)') + '</th><th>' + W(P, 'cloud-start-date', 'Start Date') + '</th><th>' +
      W(P, 'cloud-end-date', 'End Date') + '</th></tr>';
    Shown := False;
    for Site in Sites do
    begin
      if Site.Root <> I then Continue;
      Shown := True;
      DbName := WKDefaultDatabase(Site);
      Db := nil;
      if DbName <> '' then Db := WKOpen(Site, DbName);
      Row := '<tr><td>' + Link(P, '/wekan/boards', SiteQuery(Site, DbName), SiteName(Site)) + '</td>';
      try
        if Db = nil then
          Row := Row + '<td colspan="6">' + W(P, 'wekan-data-no-database', 'No readable WeKan database was found.') + '</td>'
        else
        begin
          AttachmentTotals(Db, Count, Total);
          DbFile := WKDatabaseFile(Site, DbName);
          WKFolderBytes(IncludeTrailingPathDelimiter(Site.FilesDir) + 'attachments', Files, FolderBytes);
          Row := Row + '<td>' + HtmlEncode(DbName) + '</td><td>' + IntToStr(Db.Count('boards', '')) + '</td><td>' +
            IntToStr(Db.Count('cards', '')) + '</td><td>' + IntToStr(Count) + '</td><td>' + Bytes(Total) + '</td><td>' +
            Bytes(WKDatabaseBytes(DbFile)) + '</td>';
        end;
      except
        Row := '<tr><td>' + Link(P, '/wekan/boards', SiteQuery(Site, DbName), SiteName(Site)) + '</td><td colspan="6">' +
          W(P, 'wekan-data-no-database', 'No readable WeKan database was found.') + '</td>';
      end;
      Db.Free;
      Body := Body + Row + '<td>' + HtmlEncode(Site.StartDate) + '</td><td>' + HtmlEncode(Site.EndDate) + '</td></tr>';
    end;
    if not Shown then
      Body := Body + '<tr><td colspan="9">' + W(P, 'no-results', 'No results') + '</td></tr>';
    Body := Body + '</table>';
  end;
  Send(aResponse, P, 'WeKan: ' + P.Words.Text('domains', 'Domains'), Body);
end;

{ ---------------------------------------------------------------- /wekan/boards }

// Grouped counts: key -> "count|bytes" for one collection.
procedure Grouped(Db: TWKDb; const Collection, KeyField, Where, SizeExpr: string; Into: TStringList);
var Rows: TWLRows; Row: TWLRow; Sql: string;
begin
  if Db.Table(Collection) = '' then Exit;
  Sql := 'SELECT ' + WKField(KeyField) + ' AS k, count(*) AS n';
  if SizeExpr <> '' then Sql := Sql + ', CAST(total(' + SizeExpr + ') AS INTEGER) AS b';
  Sql := Sql + ' FROM ' + Db.From(Collection);
  if Where <> '' then Sql := Sql + ' WHERE ' + Where;
  Rows := Db.Query(Sql + ' GROUP BY k;');
  for Row in Rows do
    if (Length(Row) >= 2) and (Row[0] <> '') then
      if SizeExpr <> '' then Into.Values[Row[0]] := Row[1] + '|' + Row[2]
      else Into.Values[Row[0]] := Row[1];
end;

function Part(const Value: string; Index: Integer): string;
var Parts: TStringArray;
begin
  Parts := Value.Split(['|']);
  if Index <= High(Parts) then Result := Parts[Index] else Result := '0';
end;

function SizeExpr: string;
begin
  Result := 'COALESCE(' + WKField('versions.original.size') + ',' + WKField('size') + ',0)';
end;

procedure WeKanBoardsEndpoint(aRequest: TRequest; aResponse: TResponse);
var P: TPage; Site: TWKSite; Db: TWKDb; DbName, Body, Id, Query, Mark: string; Boards: TJSONArray;
  Cards, Files: TStringList; Names: TStringArray; Name: string; I: Integer; Board: TJSONObject;
begin
  if not Start(aRequest, aResponse, P) then Exit;
  if not OpenSite(aRequest, P, Site, DbName, Db) then
  begin
    Send(aResponse, P, 'WeKan', Crumbs(P, []) + NoDatabase(P), 404);
    Exit;
  end;
  Boards := nil; Cards := TStringList.Create; Files := TStringList.Create;
  try
    try
      Boards := Db.Docs('boards', '');
      WKSortDocs(Boards);
      Grouped(Db, 'cards', 'boardId', '', '', Cards);
      Grouped(Db, 'attachments', 'meta.boardId', WKNotDeleted, SizeExpr, Files);
      Body := Crumbs(P, [HtmlEncode(SiteName(Site))]) + '<h1>' + HtmlEncode(SiteName(Site)) + ' &mdash; ' +
        W(P, 'boards', 'Boards') + '</h1>';
      Names := WKDatabases(Site);
      if Length(Names) > 1 then
      begin
        Body := Body + '<p>' + W(P, 'continuous-backup-database', 'Database') + ':';
        for Name in Names do
          if Name = DbName then Body := Body + ' <b>' + HtmlEncode(Name) + '</b>'
          else Body := Body + ' ' + Link(P, '/wekan/boards', SiteQuery(Site, Name), Name);
        Body := Body + '</p>';
      end;
      Body := Body + '<table border="1" cellpadding="4" cellspacing="0"><tr><th>' + W(P, 'board', 'Board') +
        '</th><th>' + W(P, 'type', 'Type') + '</th><th>' + W(P, 'members', 'Members') + '</th><th>' +
        W(P, 'cards', 'Cards') + '</th><th>' + W(P, 'attachments', 'Attachments') + '</th><th>' +
        W(P, 'total-size', 'Total Size') + '</th></tr>';
      for I := 0 to Boards.Count - 1 do
      begin
        Board := Boards.Objects[I];
        Id := WKStr(Board, '_id');
        if not WKValidId(Id) then Continue;
        Query := SiteQuery(Site, DbName) + '&board=' + HTTPEncode(Id);
        Mark := '';
        if WKBool(Board, 'archived') then Mark := ' <small>(' + W(P, 'archived', 'Archived') + ')</small>';
        Body := Body + '<tr><td>' + Link(P, '/wekan/board', Query, WKStr(Board, 'title')) + Mark + '</td><td>' +
          HtmlEncode(WKStr(Board, 'type')) + '</td><td>';
        if WKArr(Board, 'members') <> nil then Body := Body + IntToStr(WKArr(Board, 'members').Count)
        else Body := Body + '0';
        Body := Body + '</td><td>' + IntToStr(StrToIntDef(Cards.Values[Id], 0)) + '</td><td>' +
          Part(Files.Values[Id], 0) + '</td><td>' + Bytes(StrToInt64Def(Part(Files.Values[Id], 1), 0)) + '</td></tr>';
      end;
      if Boards.Count = 0 then Body := Body + '<tr><td colspan="6">' + W(P, 'no-results', 'No results') + '</td></tr>';
      Body := Body + '</table>';
      Send(aResponse, P, SiteName(Site), Body);
    except
      Send(aResponse, P, 'WeKan', Crumbs(P, []) + NoDatabase(P), 500);
    end;
  finally
    Boards.Free; Cards.Free; Files.Free; Db.Free; P.Words.Free;
  end;
end;

{ ---------------------------------------------------------------- shared board data }

type
  TBoardData = class
    Site: TWKSite;
    DbName, BoardId: string;
    Db: TWKDb;
    Board: TJSONObject;
    Boards, Users: TJSONArray;
    destructor Destroy; override;
    function UserName(const Id: string): string;
    function LabelHtml(const Id: string): string;
    procedure LoadUsers(Cards: TJSONArray);
  end;

destructor TBoardData.Destroy;
begin
  Boards.Free; Users.Free; Db.Free;
  inherited Destroy;
end;

function TBoardData.UserName(const Id: string): string;
var I: Integer;
begin
  if Users <> nil then
    for I := 0 to Users.Count - 1 do
      if WKStr(Users.Objects[I], '_id') = Id then
      begin
        Result := WKStr(Users.Objects[I], 'username');
        if Result <> '' then Exit;
      end;
  Result := Id;
end;

function TBoardData.LabelHtml(const Id: string): string;
var Labels: TJSONArray; I: Integer; Item: TJSONObject; Name, Color: string;
begin
  Result := '';
  Labels := WKArr(Board, 'labels');
  if Labels = nil then Exit;
  for I := 0 to Labels.Count - 1 do
    if Labels.Items[I] is TJSONObject then
    begin
      Item := Labels.Objects[I];
      if WKStr(Item, '_id') <> Id then Continue;
      Name := WKStr(Item, 'name'); Color := ResolveColor(WKStr(Item, 'color'));
      if Name = '' then Name := WKStr(Item, 'color');
      Exit(FontOpen(Color) + '<b>[' + HtmlEncode(Name) + ']</b>' + FontClose(Color));
    end;
end;

procedure AddIds(List: TStringList; Values: TJSONArray);
var I: Integer;
begin
  if Values = nil then Exit;
  for I := 0 to Values.Count - 1 do
    if (Values.Items[I].JSONType = jtString) and WKValidId(Values.Items[I].AsString) and
      (List.IndexOf(Values.Items[I].AsString) < 0) then List.Add(Values.Items[I].AsString);
end;

function IdList(List: TStringList): string;
var I: Integer;
begin
  Result := '';
  for I := 0 to List.Count - 1 do
  begin
    if Result <> '' then Result := Result + ',';
    Result := Result + WKLit(List[I]);
  end;
  if Result = '' then Result := 'NULL';
end;

// Open the site and the board named by the request; nil when either is missing.
function LoadBoard(Request: TRequest; var P: TPage): TBoardData;
var Site: TWKSite; DbName: string; Db: TWKDb;
begin
  Result := nil;
  if not OpenSite(Request, P, Site, DbName, Db) then begin Db.Free; Exit; end;
  Result := TBoardData.Create;
  Result.Site := Site; Result.DbName := DbName; Result.Db := Db;
  Result.BoardId := Param(Request, 'board');
  try
    if not WKValidId(Result.BoardId) then raise Exception.Create('No board');
    Result.Boards := Db.Docs('boards', WKField('_id') + '=' + WKLit(Result.BoardId));
    if Result.Boards.Count <> 1 then raise Exception.Create('No board');
    Result.Board := Result.Boards.Objects[0];
    Result.LoadUsers(nil);
  except
    FreeAndNil(Result);
  end;
end;

// The users named by the board's members and by these cards.
procedure TBoardData.LoadUsers(Cards: TJSONArray);
var Ids: TStringList; I: Integer; Members: TJSONArray;
begin
  Ids := TStringList.Create;
  try
    Members := WKArr(Board, 'members');
    if Members <> nil then
      for I := 0 to Members.Count - 1 do
        if (Members.Items[I] is TJSONObject) and WKValidId(WKStr(Members.Objects[I], 'userId')) and
          (Ids.IndexOf(WKStr(Members.Objects[I], 'userId')) < 0) then
          Ids.Add(WKStr(Members.Objects[I], 'userId'));
    if Cards <> nil then
      for I := 0 to Cards.Count - 1 do
      begin
        AddIds(Ids, WKArr(Cards.Objects[I], 'members'));
        AddIds(Ids, WKArr(Cards.Objects[I], 'assignees'));
      end;
    FreeAndNil(Users);
    Users := Db.Docs('users', WKField('_id') + ' IN (' + IdList(Ids) + ')');
  finally Ids.Free; end;
end;

function BoardQuery(Data: TBoardData): string;
begin
  Result := SiteQuery(Data.Site, Data.DbName) + '&board=' + HTTPEncode(Data.BoardId);
end;

function Names(Data: TBoardData; Values: TJSONArray): string;
var I: Integer;
begin
  Result := '';
  if Values = nil then Exit;
  for I := 0 to Values.Count - 1 do
    if Values.Items[I].JSONType = jtString then
    begin
      if Result <> '' then Result := Result + ', ';
      Result := Result + HtmlEncode(Data.UserName(Values.Items[I].AsString));
    end;
end;

function Labels(Data: TBoardData; Card: TJSONObject): string;
var Ids: TJSONArray; I: Integer;
begin
  Result := '';
  Ids := WKArr(Card, 'labelIds');
  if Ids <> nil then
    for I := 0 to Ids.Count - 1 do
      if Ids.Items[I].JSONType = jtString then Result := Result + Data.LabelHtml(Ids.Items[I].AsString) + ' ';
end;

function Dates(const P: TPage; Card: TJSONObject; const Separator: string): string;
const Keys: array[0..3] of string = ('receivedAt', 'startAt', 'dueAt', 'endAt');
  Words: array[0..3] of string = ('card-received', 'card-start', 'card-due', 'card-end');
  English: array[0..3] of string = ('Received', 'Start', 'Due', 'End');
var I: Integer; Text: string;
begin
  Result := '';
  for I := 0 to 3 do
  begin
    Text := WKDate(WKValue(Card, Keys[I]));
    if Text <> '' then Result := Result + W(P, Words[I], English[I]) + ': ' + HtmlEncode(Text) + Separator;
  end;
end;

function SwimlaneTitle(const P: TPage; Doc: TJSONObject): string;
begin
  Result := WKStr(Doc, 'title');
  if Result = '' then Result := P.Words.Text('swimlane', 'Swimlane');
end;

{ ---------------------------------------------------------------- /wekan/board }

procedure WeKanBoardEndpoint(aRequest: TRequest; aResponse: TResponse);
var P: TPage; Data: TBoardData; Cards, Lanes, Lists: TJSONArray; Items, Comments, Files: TStringList;
  Body, BoardLit, Subquery, Cell, Id, Lane, Counts, Member: string; L, R, C, CardCount: Integer;
  Card, List: TJSONObject; LaneIds, ListIds: TStringList; Total: Int64; AttachCount: Int64;
begin
  if not Start(aRequest, aResponse, P) then Exit;
  Cards := nil; Lanes := nil; Lists := nil; Data := nil;
  Items := TStringList.Create; Comments := TStringList.Create; Files := TStringList.Create;
  LaneIds := TStringList.Create; ListIds := TStringList.Create;
  try
    try
      Data := LoadBoard(aRequest, P);
      if Data = nil then
      begin
        Send(aResponse, P, 'WeKan', Crumbs(P, []) + '<p>' + W(P, 'board-not-found', 'Board not found') + '</p>', 404);
        Exit;
      end;
      BoardLit := WKLit(Data.BoardId);
      Cards := Data.Db.Docs('cards', WKField('boardId') + '=' + BoardLit);
      Data.LoadUsers(Cards);
      WKSortDocs(Cards);
      Lanes := Data.Db.Docs('swimlanes', WKField('boardId') + '=' + BoardLit);
      Lists := Data.Db.Docs('lists', WKField('boardId') + '=' + BoardLit);
      WKSortDocs(Lanes); WKSortDocs(Lists);
      for L := Lanes.Count - 1 downto 0 do if WKBool(Lanes.Objects[L], 'archived') then Lanes.Delete(L);
      for L := Lists.Count - 1 downto 0 do if WKBool(Lists.Objects[L], 'archived') then Lists.Delete(L);
      for L := 0 to Lanes.Count - 1 do LaneIds.Add(WKStr(Lanes.Objects[L], '_id'));
      for L := 0 to Lists.Count - 1 do ListIds.Add(WKStr(Lists.Objects[L], '_id'));
      if Data.Db.Table('cards') <> '' then
      begin
        Subquery := '(SELECT ' + WKField('_id') + ' FROM ' + Data.Db.From('cards') + ' WHERE ' +
          WKField('boardId') + '=' + BoardLit + ')';
        Grouped(Data.Db, 'checklistItems', 'cardId', WKField('cardId') + ' IN ' + Subquery,
          'CASE WHEN ' + WKField('isFinished') + ' THEN 1 ELSE 0 END', Items);
        Grouped(Data.Db, 'card_comments', 'cardId', WKField('cardId') + ' IN ' + Subquery, '', Comments);
        Grouped(Data.Db, 'attachments', 'meta.cardId', WKField('meta.cardId') + ' IN ' + Subquery + ' AND ' + WKNotDeleted,
          SizeExpr, Files);
      end;
      Total := 0; AttachCount := 0;
      for L := 0 to Files.Count - 1 do
      begin
        Inc(AttachCount, StrToInt64Def(Part(Files.ValueFromIndex[L], 0), 0));
        Inc(Total, StrToInt64Def(Part(Files.ValueFromIndex[L], 1), 0));
      end;
      Body := Crumbs(P, [Link(P, '/wekan/boards', SiteQuery(Data.Site, Data.DbName), SiteName(Data.Site)),
        HtmlEncode(WKStr(Data.Board, 'title'))]) + '<h1>' + HtmlEncode(WKStr(Data.Board, 'title')) + '</h1>';
      Member := '';
      if WKArr(Data.Board, 'members') <> nil then
        for L := 0 to WKArr(Data.Board, 'members').Count - 1 do
          if WKArr(Data.Board, 'members').Items[L] is TJSONObject then
          begin
            if Member <> '' then Member := Member + ', ';
            Member := Member + HtmlEncode(Data.UserName(WKStr(WKArr(Data.Board, 'members').Objects[L], 'userId')));
          end;
      Body := Body + '<p>' + W(P, 'members', 'Members') + ': ' + Member + '<br>' + W(P, 'cards', 'Cards') + ': ' +
        IntToStr(Cards.Count) + ' &nbsp; ' + W(P, 'attachments', 'Attachments') + ': ' + IntToStr(AttachCount) +
        ' &nbsp; ' + W(P, 'total-size', 'Total Size') + ': ' + Bytes(Total) + '</p>';
      if Lists.Count = 0 then
        Body := Body + '<p>' + W(P, 'no-results', 'No results') + '</p>'
      else
      begin
        Body := Body + '<table class="wekan-kanban" border="1" cellpadding="4" cellspacing="0"><tr><th>' +
          W(P, 'swimlanes', 'Swimlanes') + ' / ' + W(P, 'lists', 'Lists') + '</th>';
        for L := 0 to Lists.Count - 1 do
        begin
          CardCount := 0;
          for C := 0 to Cards.Count - 1 do
            if not WKBool(Cards.Objects[C], 'archived') and (WKStr(Cards.Objects[C], 'listId') = ListIds[L]) then
              Inc(CardCount);
          Body := Body + '<th valign="top">' + HtmlEncode(WKStr(Lists.Objects[L], 'title')) + ' (' + IntToStr(CardCount) + ')</th>';
        end;
        Body := Body + '</tr>';
        // A board without swimlanes still shows its cards in one row.
        for R := 0 to Max(Lanes.Count, 1) - 1 do
        begin
          if Lanes.Count > 0 then
          begin
            Lane := LaneIds[R];
            Body := Body + '<tr><th align="left" valign="top">' + HtmlEncode(SwimlaneTitle(P, Lanes.Objects[R])) + '</th>';
          end
          else
          begin
            Lane := '';
            Body := Body + '<tr><th align="left" valign="top">' + W(P, 'swimlane', 'Swimlane') + '</th>';
          end;
          for L := 0 to Lists.Count - 1 do
          begin
            List := Lists.Objects[L];
            Cell := '';
            // A list of another swimlane has no cards in this one.
            if (WKStr(List, 'swimlaneId') = '') or (WKStr(List, 'swimlaneId') = Lane) or (Lanes.Count = 0) then
              for C := 0 to Cards.Count - 1 do
              begin
                Card := Cards.Objects[C];
                if WKBool(Card, 'archived') or (WKStr(Card, 'listId') <> ListIds[L]) then Continue;
                // Cards of an archived or missing swimlane are shown in the first one.
                if (Lanes.Count > 0) and (WKStr(Card, 'swimlaneId') <> Lane) and
                  not ((R = 0) and (LaneIds.IndexOf(WKStr(Card, 'swimlaneId')) < 0)) then Continue;
                Id := WKStr(Card, '_id');
                if not WKValidId(Id) then Continue;
                Counts := '';
                if Items.Values[Id] <> '' then
                  Counts := Counts + W(P, 'checklists', 'Checklists') + ' ' + Part(Items.Values[Id], 1) + '/' +
                    Part(Items.Values[Id], 0) + ' ';
                if Comments.Values[Id] <> '' then
                  Counts := Counts + W(P, 'comments', 'Comments') + ' ' + HtmlEncode(Comments.Values[Id]) + ' ';
                if Files.Values[Id] <> '' then
                  Counts := Counts + W(P, 'attachments', 'Attachments') + ' ' + Part(Files.Values[Id], 0) + ' ';
                Cell := Cell + '<table class="wekan-card" border="1" cellpadding="3" cellspacing="0" width="100%"><tr><td>';
                if Labels(Data, Card) <> '' then Cell := Cell + Labels(Data, Card) + '<br>';
                Cell := Cell + Link(P, '/wekan/card', BoardQuery(Data) + '&card=' + HTTPEncode(Id), WKStr(Card, 'title'));
                if Names(Data, WKArr(Card, 'members')) <> '' then
                  Cell := Cell + '<br><small>' + W(P, 'members', 'Members') + ': ' + Names(Data, WKArr(Card, 'members')) + '</small>';
                if Names(Data, WKArr(Card, 'assignees')) <> '' then
                  Cell := Cell + '<br><small>' + W(P, 'assignees', 'Assignees') + ': ' + Names(Data, WKArr(Card, 'assignees')) + '</small>';
                if Dates(P, Card, '') <> '' then Cell := Cell + '<br><small>' + Dates(P, Card, '<br>') + '</small>';
                if Counts <> '' then Cell := Cell + '<br><small>' + Counts + '</small>';
                Cell := Cell + '</td></tr></table>';
              end;
            if Cell = '' then Cell := '&nbsp;';
            Body := Body + '<td valign="top">' + Cell + '</td>';
          end;
          Body := Body + '</tr>';
        end;
        Body := Body + '</table>';
      end;
      Send(aResponse, P, WKStr(Data.Board, 'title'), Body);
    except
      if P.Words <> nil then Send(aResponse, P, 'WeKan', Crumbs(P, []) + NoDatabase(P), 500);
    end;
  finally
    Cards.Free; Lanes.Free; Lists.Free; Data.Free; P.Words.Free;
    Items.Free; Comments.Free; Files.Free; LaneIds.Free; ListIds.Free;
  end;
end;

{ ---------------------------------------------------------------- /wekan/card }

function FieldValue(const P: TPage; Definition: TJSONObject; Value: TJSONData): string;
var Kind: string; Items: TJSONArray; I: Integer;
begin
  Result := '';
  if Value = nil then Exit;
  Kind := WKStr(Definition, 'type');
  if (Kind = 'dropdown') and (Value.JSONType = jtString) then
  begin
    Items := WKArr(Definition, 'settings.dropdownItems');
    if Items <> nil then
      for I := 0 to Items.Count - 1 do
        if (Items.Items[I] is TJSONObject) and (WKStr(Items.Objects[I], '_id') = Value.AsString) then
          Exit(HtmlEncode(WKStr(Items.Objects[I], 'name')));
    Exit(HtmlEncode(Value.AsString));
  end;
  if Kind = 'date' then Exit(HtmlEncode(WKDate(Value)));
  case Value.JSONType of
    jtString: Result := Lines(Value.AsString);
    jtBoolean: if Value.AsBoolean then Result := '[x] ' + W(P, 'yes', 'Yes') else Result := '[ ] ' + W(P, 'no', 'No');
    jtNull: Result := '';
  else
    Result := HtmlEncode(Value.AsJSON);
  end;
end;

function AttachmentRows(const P: TPage; Data: TBoardData; const CardId: string; Files: TJSONArray): string;
var I: Integer; Doc: TJSONObject; Id, Found, Reason, Query, State: string;
begin
  Result := '';
  for I := 0 to Files.Count - 1 do
  begin
    Doc := Files.Objects[I];
    Id := WKStr(Doc, '_id');
    if not WKValidId(Id) then Continue;
    Query := BoardQuery(Data) + '&card=' + HTTPEncode(CardId) + '&file=' + HTTPEncode(Id);
    Found := WKAttachmentFile(Data.Site, Doc, Reason);
    if Found <> '' then State := Link(P, '/wekan/file', Query, P.Words.Text('download', 'Download'))
    else if Reason = 'storage' then State := HtmlEncode(WKStr(Doc, 'versions.original.storage'))
    else State := W(P, 'attachment-repair-broken', 'Not found');
    Result := Result + '<tr><td>' + Link(P, '/wekan/file', Query + '&view=1', WKStr(Doc, 'name')) + '</td><td>' +
      HtmlEncode(WKStr(Doc, 'type')) + '</td><td>' + Bytes(Trunc(Max(WKNum(Doc, 'versions.original.size'), WKNum(Doc, 'size')))) +
      '</td><td>' + State + '</td></tr>';
  end;
end;

procedure WeKanCardEndpoint(aRequest: TRequest; aResponse: TResponse);
var P: TPage; Data: TBoardData; Cards, Lanes, Lists, Fields, Checklists, ChecklistItems, Comments, Files: TJSONArray;
  Card, Definition, Item: TJSONObject; CardId, Body, CardLit, Title, Text: string; Values: TJSONArray;
  I, J: Integer; Lane, List: string;
begin
  if not Start(aRequest, aResponse, P) then Exit;
  Cards := nil; Lanes := nil; Lists := nil; Fields := nil; Checklists := nil; ChecklistItems := nil;
  Comments := nil; Files := nil; Data := nil;
  try
    try
      CardId := Param(aRequest, 'card');
      Data := LoadBoard(aRequest, P);
      if (Data <> nil) and WKValidId(CardId) then
      begin
        CardLit := WKLit(CardId);
        Cards := Data.Db.Docs('cards', WKField('_id') + '=' + CardLit + ' AND ' + WKField('boardId') + '=' + WKLit(Data.BoardId));
        if Cards.Count = 1 then Data.LoadUsers(Cards);
      end;
      if (Data = nil) or (Cards = nil) or (Cards.Count <> 1) then
      begin
        Send(aResponse, P, 'WeKan', Crumbs(P, []) + '<p>' + W(P, 'field-link-not-found', 'Card not found.') + '</p>', 404);
        Exit;
      end;
      Card := Cards.Objects[0];
      Title := WKStr(Card, 'title');
      Lanes := Data.Db.Docs('swimlanes', WKField('_id') + '=' + WKLit(WKStr(Card, 'swimlaneId')));
      Lists := Data.Db.Docs('lists', WKField('_id') + '=' + WKLit(WKStr(Card, 'listId')));
      Lane := ''; List := '';
      if Lanes.Count = 1 then Lane := WKStr(Lanes.Objects[0], 'title');
      if Lists.Count = 1 then List := WKStr(Lists.Objects[0], 'title');
      Body := Crumbs(P, [Link(P, '/wekan/boards', SiteQuery(Data.Site, Data.DbName), SiteName(Data.Site)),
        Link(P, '/wekan/board', BoardQuery(Data), WKStr(Data.Board, 'title')), HtmlEncode(Title)]) +
        '<h1>' + HtmlEncode(Title) + '</h1><table border="1" cellpadding="4" cellspacing="0">' +
        '<tr><th align="left">' + W(P, 'swimlane', 'Swimlane') + '</th><td>' + HtmlEncode(Lane) + '</td></tr>' +
        '<tr><th align="left">' + W(P, 'list', 'List') + '</th><td>' + HtmlEncode(List) + '</td></tr>';
      if Labels(Data, Card) <> '' then
        Body := Body + '<tr><th align="left">' + W(P, 'labels', 'Labels') + '</th><td>' + Labels(Data, Card) + '</td></tr>';
      if Names(Data, WKArr(Card, 'members')) <> '' then
        Body := Body + '<tr><th align="left">' + W(P, 'members', 'Members') + '</th><td>' + Names(Data, WKArr(Card, 'members')) + '</td></tr>';
      if Names(Data, WKArr(Card, 'assignees')) <> '' then
        Body := Body + '<tr><th align="left">' + W(P, 'assignees', 'Assignees') + '</th><td>' + Names(Data, WKArr(Card, 'assignees')) + '</td></tr>';
      Text := Dates(P, Card, '<br>');
      if Text <> '' then Body := Body + '<tr><th align="left">' + W(P, 'date', 'Date') + '</th><td>' + Text + '</td></tr>';
      if WKBool(Card, 'archived') then
        Body := Body + '<tr><th align="left">' + W(P, 'archived', 'Archived') + '</th><td>' + W(P, 'yes', 'Yes') + '</td></tr>';
      Body := Body + '</table>';
      if WKStr(Card, 'description') <> '' then
        Body := Body + '<h2>' + W(P, 'description', 'Description') + '</h2><p class="wekan-description">' +
          Lines(WKStr(Card, 'description')) + '</p>';
      // Custom fields: the board's definitions of the values the card has.
      Values := WKArr(Card, 'customFields');
      if (Values <> nil) and (Values.Count > 0) then
      begin
        Fields := Data.Db.Docs('customFields', '');
        Text := '';
        for I := 0 to Values.Count - 1 do
        begin
          if not (Values.Items[I] is TJSONObject) then Continue;
          Item := Values.Objects[I];
          Definition := nil;
          for J := 0 to Fields.Count - 1 do
            if WKStr(Fields.Objects[J], '_id') = WKStr(Item, '_id') then Definition := Fields.Objects[J];
          if Definition = nil then Continue;
          Text := Text + '<tr><th align="left">' + HtmlEncode(WKStr(Definition, 'name')) + '</th><td>' +
            FieldValue(P, Definition, Item.Find('value')) + '</td></tr>';
        end;
        if Text <> '' then
          Body := Body + '<h2>' + W(P, 'custom-fields', 'Custom Fields') + '</h2><table border="1" cellpadding="4" cellspacing="0">' +
            Text + '</table>';
      end;
      Checklists := Data.Db.Docs('checklists', WKField('cardId') + '=' + CardLit);
      ChecklistItems := Data.Db.Docs('checklistItems', WKField('cardId') + '=' + CardLit);
      WKSortDocs(Checklists); WKSortDocs(ChecklistItems);
      if Checklists.Count > 0 then
      begin
        Body := Body + '<h2>' + W(P, 'checklists', 'Checklists') + '</h2>';
        for I := 0 to Checklists.Count - 1 do
        begin
          Body := Body + '<h3>' + HtmlEncode(WKStr(Checklists.Objects[I], 'title')) + '</h3><ul>';
          for J := 0 to ChecklistItems.Count - 1 do
            if WKStr(ChecklistItems.Objects[J], 'checklistId') = WKStr(Checklists.Objects[I], '_id') then
            begin
              if WKBool(ChecklistItems.Objects[J], 'isFinished') then Text := '[x] ' else Text := '[ ] ';
              Body := Body + '<li>' + Text + HtmlEncode(WKStr(ChecklistItems.Objects[J], 'title')) + '</li>';
            end;
          Body := Body + '</ul>';
        end;
      end;
      Comments := Data.Db.Docs('card_comments', WKField('cardId') + '=' + CardLit, WKField('createdAt'));
      if Comments.Count > 0 then
      begin
        Body := Body + '<h2>' + W(P, 'comments', 'Comments') + '</h2>';
        for I := 0 to Comments.Count - 1 do
          Body := Body + '<p><b>' + HtmlEncode(Data.UserName(WKStr(Comments.Objects[I], 'userId'))) + '</b> <small>' +
            HtmlEncode(WKDate(WKValue(Comments.Objects[I], 'createdAt'))) + '</small><br>' +
            Lines(WKStr(Comments.Objects[I], 'text')) + '</p>';
      end;
      Files := Data.Db.Docs('attachments', WKField('meta.cardId') + '=' + CardLit + ' AND ' + WKNotDeleted, WKField('_id'));
      if Files.Count > 0 then
        Body := Body + '<h2>' + W(P, 'attachments', 'Attachments') + '</h2><table border="1" cellpadding="4" cellspacing="0"><tr><th>' +
          W(P, 'name', 'Name') + '</th><th>' + W(P, 'type', 'Type') + '</th><th>' + W(P, 'size-bytes', 'Size (bytes)') +
          '</th><th>' + W(P, 'file', 'File') + '</th></tr>' + AttachmentRows(P, Data, CardId, Files) + '</table>';
      Send(aResponse, P, Title, Body);
    except
      if P.Words <> nil then Send(aResponse, P, 'WeKan', Crumbs(P, []) + NoDatabase(P), 500);
    end;
  finally
    Cards.Free; Lanes.Free; Lists.Free; Fields.Free; Checklists.Free; ChecklistItems.Free;
    Comments.Free; Files.Free; Data.Free; P.Words.Free;
  end;
end;

{ ---------------------------------------------------------------- /wekan/file }

function TextPreview(const FileName: string): string;
var Stream: TFileStream; Count: Integer;
begin
  Result := '';
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      Count := Stream.Size;
      if Count > PREVIEW_BYTES then Count := PREVIEW_BYTES;
      SetLength(Result, Count);
      if Count > 0 then Stream.ReadBuffer(Result[1], Count);
    finally Stream.Free; end;
    CheckUtf8(Result);
  except
    // A cut multibyte character or binary data: no preview, the download stays.
    Result := '';
  end;
end;

procedure WeKanFileEndpoint(aRequest: TRequest; aResponse: TResponse);
var P: TPage; Data: TBoardData; Files, Cards: TJSONArray; Doc: TJSONObject; CardId, FileId, Found, Reason,
  Kind, Query, Body, Preview: string;
begin
  if not Start(aRequest, aResponse, P) then Exit;
  Data := nil; Files := nil; Cards := nil;
  try
    try
      CardId := Param(aRequest, 'card'); FileId := Param(aRequest, 'file');
      Data := LoadBoard(aRequest, P);
      Found := ''; Doc := nil; Reason := 'missing';
      if (Data <> nil) and WKValidId(CardId) and WKValidId(FileId) then
      begin
        // The attachment must belong to a card of this board: ids from the URL only
        // select documents, and the file name comes from wlwkdir, never the URL.
        Cards := Data.Db.Docs('cards', WKField('_id') + '=' + WKLit(CardId) + ' AND ' + WKField('boardId') + '=' + WKLit(Data.BoardId));
        if Cards.Count = 1 then
        begin
          Files := Data.Db.Docs('attachments', WKField('_id') + '=' + WKLit(FileId) + ' AND ' +
            WKField('meta.cardId') + '=' + WKLit(CardId) + ' AND ' + WKNotDeleted);
          if Files.Count = 1 then
          begin
            Doc := Files.Objects[0];
            Found := WKAttachmentFile(Data.Site, Doc, Reason);
          end;
        end;
      end;
      if Doc = nil then
      begin
        Send(aResponse, P, 'WeKan', Crumbs(P, []) + '<p>' + W(P, 'attachment-repair-broken', 'Not found') + '</p>', 404);
        Exit;
      end;
      Kind := WKStr(Doc, 'type');
      if Param(aRequest, 'view') <> '1' then
      begin
        if Found = '' then
        begin
          Send(aResponse, P, 'WeKan', Crumbs(P, []) + '<p>' + W(P, 'attachment-repair-broken', 'Not found') + '</p>', 404);
          Exit;
        end;
        if Param(aRequest, 'preview') <> '1' then Kind := '';
        FreeAndNil(P.Words);
        // SendStoredDownload serves an attachment, inline only for raster images.
        if not SendStoredDownload(aResponse, Found, WKStr(Doc, 'name'), Kind) then
        begin
          aResponse.Code := 404; aResponse.Content := ''; aResponse.SendContent;
        end;
        Exit;
      end;
      Query := BoardQuery(Data) + '&card=' + HTTPEncode(CardId) + '&file=' + HTTPEncode(FileId);
      Body := Crumbs(P, [Link(P, '/wekan/boards', SiteQuery(Data.Site, Data.DbName), SiteName(Data.Site)),
        Link(P, '/wekan/board', BoardQuery(Data), WKStr(Data.Board, 'title')),
        Link(P, '/wekan/card', BoardQuery(Data) + '&card=' + HTTPEncode(CardId), WKStr(Cards.Objects[0], 'title')),
        HtmlEncode(WKStr(Doc, 'name'))]) + '<h1>' + HtmlEncode(WKStr(Doc, 'name')) + '</h1>' +
        '<table border="1" cellpadding="4" cellspacing="0"><tr><th align="left">' + W(P, 'type', 'Type') + '</th><td>' +
        HtmlEncode(Kind) + '</td></tr><tr><th align="left">' + W(P, 'size-bytes', 'Size (bytes)') + '</th><td>' +
        Bytes(Trunc(Max(WKNum(Doc, 'versions.original.size'), WKNum(Doc, 'size')))) + '</td></tr>';
      if WKDate(WKValue(Doc, 'uploadedAt')) <> '' then
        Body := Body + '<tr><th align="left">' + W(P, 'createdAt', 'Created at') + '</th><td>' +
          HtmlEncode(WKDate(WKValue(Doc, 'uploadedAt'))) + '</td></tr>';
      Body := Body + '<tr><th align="left">' + W(P, 'file', 'File') + '</th><td>';
      if Found <> '' then
        Body := Body + Link(P, '/wekan/file', Query, P.Words.Text('download', 'Download')) + ' ' + Bytes(WKFileBytes(Found))
      else if Reason = 'storage' then Body := Body + HtmlEncode(WKStr(Doc, 'versions.original.storage'))
      else Body := Body + W(P, 'attachment-repair-broken', 'Not found');
      Body := Body + '</td></tr></table>';
      if Found <> '' then
      begin
        if RasterAttachment(Kind) then
          Body := Body + '<h2>' + W(P, 'preview', 'Preview') + '</h2><p><img src="' +
            HtmlAttr(Url(P, '/wekan/file', Query + '&preview=1')) + '" alt="' + HtmlAttr(WKStr(Doc, 'name')) + '"></p>'
        else if (Copy(Kind, 1, 5) = 'text/') or (Kind = 'application/json') then
        begin
          Preview := TextPreview(Found);
          if Preview <> '' then
            Body := Body + '<h2>' + W(P, 'preview', 'Preview') + '</h2><pre>' + HtmlEncode(Preview) + '</pre>';
        end;
      end;
      Send(aResponse, P, WKStr(Doc, 'name'), Body);
    except
      if P.Words <> nil then Send(aResponse, P, 'WeKan', Crumbs(P, []) + NoDatabase(P), 500);
    end;
  finally
    Files.Free; Cards.Free; Data.Free; P.Words.Free;
  end;
end;

end.
