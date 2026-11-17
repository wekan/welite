unit wldesign;

{
  WeKan-Lite — Designer engine (docs/designer.md, designer.sql)

  Data-driven pages: a page is a `pages` row + its `page_widgets`; the renderer turns that
  into a retro HTML 3.2 (or HTML 4) table, and the Designer is a second set of pages that edit
  the same data. No-cookie / no-JS: every edit is a <form> POST carrying wlauth action-tokens,
  every move is a button (no drag-and-drop). Works in IBrowse / NetSurf / Dillo / Lynx.

  This unit provides:
    * the TPage / TWidget model and loaders
    * RenderPage  — page data -> HTML table (via wlhtml)
    * a dataview registry (RegisterDataView) so 'boards'/'swimlanes'/'gantt' regions fill from
      schema.sql via compiled-in renderers
    * editor endpoints (index, grid editor, save, move, sort, delete)

  v0.1 reference skeleton: concrete on model/render/move/add; richer widget editors are TODO.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, Classes, HTTPDefs, fpjson, jsonparser, zipper,
  wldb, wltenant, wlauth, wlhtml, wlcolors, wlenhanc, wlbrowse;

type
  TWidget = record
    Id, Typ, Lbl, Name, Value, Target, Binding, OptionsJson: string;
    FgColor, BgColor: string;          // WeKan name or hex (wlcolors); '' = inherit
    Row, Col, RowSpan, ColSpan: Integer;
    Sort: Double;
    Required: Boolean;
  end;
  TWidgetArray = array of TWidget;

  TPage = record
    Id, Url, Title, Kind, BuiltinKey, Doctype, MinRole, Dir: string;  // Dir: auto|ltr|rtl
    Cols: Integer;
    Enabled: Boolean;
  end;

  // A dataview renderer fills a data-bound region (e.g. the board list). It gets the tenant
  // DB, placed widget/options, auth context and resolved direction/origin page URL.
  TDataViewRenderer = function(Db: TWLDb; const W: TWidget; const S: TWLSession;
    const Dir,PageUrl:string): string;

// --- dataview registry --------------------------------------------------------------------
procedure RegisterDataView(const Binding: string; Renderer: TDataViewRenderer);

function EnsureDesignerSchema(Db: TWLDb): Boolean;

function RoleAllows(Db:TWLDb;const MinRole:string;const S:TWLSession):Boolean;

// --- model --------------------------------------------------------------------------------
function LoadPageByUrl(Db: TWLDb; const Url: string; out P: TPage): Boolean;
function LoadPageById(Db: TWLDb; const Id: string; out P: TPage): Boolean;
function LoadWidgets(Db: TWLDb; const PageId: string): TWidgetArray;

// --- direction (LTR/RTL) ------------------------------------------------------------------
// True for known RTL languages (ar, he, fa, ur, …). One page definition serves both
// directions — RTL is mirrored at render time, never stored as a separate page/file.
function LangIsRtl(const Lang: string): Boolean;
// Resolve the viewer's writing direction from the request (lang query/profile/Accept-Language),
// honoring an optional per-page override (pages.dir = auto|ltr|rtl). Returns 'ltr' or 'rtl'.
function ResolveDir(aRequest: TRequest; const PageDirOverride: string; const ProfileLanguage:string=''): string;

function SessionLanguage(Db:TWLDb;const S:TWLSession):string;

// --- render -------------------------------------------------------------------------------
// Render a published page. Dir is 'ltr' or 'rtl'; when 'rtl' the table columns are reversed
// and cells right-aligned so the whole UI mirrors on HTML 3.2 browsers (IBrowse/NetSurf) that
// ignore the dir attribute. Params = the request query fields (search term + page number for
// any `table` components on the page; may be nil). Returns a full HTML doc.
function RenderPage(Db: TWLDb; const P: TPage; const S: TWLSession;
  Params: TStrings; const Dir: string;const LanguageTag:string=''): string;

// --- dispatcher hook ----------------------------------------------------------------------
// Try to serve `Path` from the pages table. Returns False if no enabled page matches (caller
// then falls through to compiled-in routes / 404). Enforces pages.minRole. Dir mirrors RTL.
function TryServePage(ATenant: TWLTenant; const S: TWLSession;
  const Path, Dir: string; Params: TStrings; aResponse: TResponse;const LanguageTag:string=''): Boolean;

// --- import / export ----------------------------------------------------------------------
// Serialize one page (its pages row + page_widgets) to a portable JSON document. Tenant-local
// ids are omitted; positions are logical (direction-neutral), so a page exported from an RTL
// tenant imports correctly into an LTR one. File extension: .wlp (JSON inside).
function ExportPageJson(Db: TWLDb; const P: TPage): string;
// Import one .wlp JSON: upsert by url (existing page with same url is replaced), new ids
// generated. Returns the imported page's url, or '' on failure.
function ImportPageJson(Db: TWLDb; const Json: string): string;
// Export ALL pages as a .zip (manifest.jsn + one numbered DOS 8.3 .wlp per page) to OutStream.
procedure ExportAllPages(Db: TWLDb; OutStream: TStream);
// Import a validated ZIP atomically. Returns count, or -1 if any entry fails.
function ImportAllPages(Db: TWLDb; InStream: TStream): Integer;

// --- editor endpoints (register these under /designer in wlhttp.lpr) ----------------------
procedure DesignerIndex(aRequest: TRequest; aResponse: TResponse);
procedure DesignerPageSave(aRequest: TRequest; aResponse: TResponse);
procedure DesignerEditPage(aRequest: TRequest; aResponse: TResponse);
procedure DesignerWidgetSort(aRequest: TRequest; aResponse: TResponse);
procedure DesignerWidgetMove(aRequest: TRequest; aResponse: TResponse);
procedure DesignerWidgetDelete(aRequest: TRequest; aResponse: TResponse);
procedure DesignerWidgetSave(aRequest: TRequest; aResponse: TResponse);
procedure DesignerPageExport(aRequest: TRequest; aResponse: TResponse);   // GET  ?id=  -> .wlp
procedure DesignerPageImport(aRequest: TRequest; aResponse: TResponse);   // POST file -> upsert
procedure DesignerExportAll(aRequest: TRequest; aResponse: TResponse);    // GET        -> .zip
procedure DesignerImportAll(aRequest: TRequest; aResponse: TResponse);    // POST .zip  -> upsert

implementation

uses
  DateUtils, StrUtils, Math, wladmin, wli18n, wllocale;

var
  DataViews: TStringList = nil;   // binding -> TDataViewRenderer (as Pointer)

procedure RegisterDataView(const Binding: string; Renderer: TDataViewRenderer);
begin
  if DataViews = nil then
  begin
    DataViews := TStringList.Create;
    DataViews.CaseSensitive := False;
    DataViews.Sorted := True;
  end;
  DataViews.AddObject(Binding, TObject(Pointer(Renderer)));
end;

function FindDataView(const Binding: string): TDataViewRenderer;
var Idx: Integer;
begin
  Result := nil;
  if DataViews = nil then Exit;
  Idx := DataViews.IndexOf(Binding);
  if Idx >= 0 then
    Result := TDataViewRenderer(Pointer(DataViews.Objects[Idx]));
end;

// Provision Designer tables independently of the portable board schema. Existing tenants
// are upgraded when they first enter Designer; never recreate or overwrite their pages.
function EnsureDesignerSchema(Db: TWLDb): Boolean;
var R: TWLRows; FileName: string; Sql: TStringList;
begin
  R := Db.Query('SELECT COUNT(*) FROM sqlite_master WHERE type=''table'' AND name IN (''pages'',''page_widgets'');');
  if (Length(R)>0) and (R[0][0]='2') then Exit(True);
  FileName := GetEnvironmentVariable('WELITE_DESIGNER');
  if FileName='' then FileName := 'src/designer.sql';
  if not FileExists(FileName) then Exit(False);
  Sql := TStringList.Create;
  try
    Sql.LoadFromFile(FileName);
    Result := Db.Exec(Sql.Text);
  finally Sql.Free; end;
end;

// ------------------------------------------------------------------ model
function LoadPageWhere(Db: TWLDb; const Where: string; out P: TPage): Boolean;
var R: TWLRows;
begin
  FillChar(P, SizeOf(P), 0);
  R := Db.Query(Format(
    'SELECT id,url,title,kind,builtinKey,cols,doctype,minRole,dir,enabled ' +
    'FROM pages WHERE %s LIMIT 1;', [Where]));
  Result := (Length(R) > 0) and (Length(R[0]) >= 10);
  if not Result then Exit;
  P.Id := R[0][0];        P.Url := R[0][1];      P.Title := R[0][2];
  P.Kind := R[0][3];      P.BuiltinKey := R[0][4];
  P.Cols := StrToIntDef(R[0][5], 1);
  P.Doctype := R[0][6];   P.MinRole := R[0][7];   P.Dir := R[0][8];
  P.Enabled := R[0][9] = '1';
end;

function LoadPageByUrl(Db: TWLDb; const Url: string; out P: TPage): Boolean;
begin
  Result := LoadPageWhere(Db, 'url='+QuotedStr(Url)+' AND enabled=1', P);
end;

function LoadPageById(Db: TWLDb; const Id: string; out P: TPage): Boolean;
begin
  Result := LoadPageWhere(Db, 'id='+QuotedStr(Id), P);
end;

function LoadWidgets(Db: TWLDb; const PageId: string): TWidgetArray;
var R: TWLRows; i: Integer;
begin
  R := Db.Query(Format(
    'SELECT id,type,label,name,value,target,binding,options_json,' +
    'row,col,rowspan,colspan,sort,required,fgColor,bgColor ' +
    'FROM page_widgets WHERE pageId=%s ORDER BY row,col,sort,id;', [QuotedStr(PageId)]));
  SetLength(Result, Length(R));
  for i := 0 to High(R) do
    if Length(R[i]) >= 16 then
    begin
      Result[i].Id := R[i][0];       Result[i].Typ := R[i][1];
      Result[i].Lbl := R[i][2];      Result[i].Name := R[i][3];
      Result[i].Value := R[i][4];    Result[i].Target := R[i][5];
      Result[i].Binding := R[i][6];  Result[i].OptionsJson := R[i][7];
      Result[i].Row := StrToIntDef(R[i][8], 0);
      Result[i].Col := StrToIntDef(R[i][9], 0);
      Result[i].RowSpan := StrToIntDef(R[i][10], 1);
      Result[i].ColSpan := StrToIntDef(R[i][11], 1);
      Result[i].Sort := StrToFloatDef(R[i][12], 0);
      Result[i].Required := R[i][13] = '1';
      Result[i].FgColor := R[i][14]; Result[i].BgColor := R[i][15];
    end;
end;

// ------------------------------------------------------------------ widget render
function RenderTable(Db: TWLDb; const W: TWidget; const S: TWLSession;
  Params: TStrings; const Dir: string): string; forward;

// Parse a single string field out of a widget's options_json (small, tolerant).
function OptStr(const Json, Key, Default: string): string;
var D: TJSONData; O: TJSONObject;
begin
  Result := Default;
  try
    D := GetJSON(Json);
    try
      if D is TJSONObject then
      begin
        O := TJSONObject(D);
        Result := O.Get(Key, Default);
      end;
    finally
      D.Free;
    end;
  except
  end;
end;

function RequiredAttrs(const W: TWidget): string;
begin
  if W.Required then Result:=' required="required"' else Result:='';
end;

function RenderSelect(const W: TWidget): string;
var D, Item: TJSONData; A: TJSONArray; i: Integer; V, L: string;
begin
  Result:=HtmlEncode(W.Lbl)+' <select name="'+HtmlAttr(W.Name)+'"'+RequiredAttrs(W)+'>';
  D:=nil;
  try
    try
      D:=GetJSON(W.OptionsJson);
      if D is TJSONObject then
      begin
        A:=TJSONObject(D).Find('options') as TJSONArray;
        if A<>nil then for i:=0 to A.Count-1 do
        begin
          Item:=A.Items[i];
          if Item is TJSONObject then
          begin
            V:=TJSONObject(Item).Get('value',''); L:=TJSONObject(Item).Get('label',V);
          end
          else begin V:=Item.AsString; L:=V; end;
          Result:=Result+'<option value="'+HtmlAttr(V)+'"';
          if V=W.Value then Result:=Result+' selected';
          Result:=Result+'>'+HtmlEncode(L)+'</option>';
        end;
      end;
    except
      // Bad imported options must not take down a published page.
    end;
  finally D.Free; end;
  Result:=Result+'</select>';
end;

function RenderWidget(Db: TWLDb; const W: TWidget; const S: TWLSession;
  Params: TStrings; const Dir,PageUrl: string): string;
var DV: TDataViewRenderer;
begin
  case LowerCase(W.Typ) of
    'table':     Result := RenderTable(Db, W, S, Params, Dir);
    'color':     // a color-input field; options_json.style picks the picker component
      Result := HtmlEncode(W.Lbl) + ' ' +
                RenderColorInput(W.Name, W.Value, OptStr(W.OptionsJson, 'style', 'hex'));
    'heading':   Result := '<h2>' + HtmlEncode(W.Lbl) + '</h2>';
    'label':     Result := HtmlEncode(W.Lbl);
    'hr', 'spacer': Result := '<hr>';
    'link':      Result := '<a href="' + HtmlAttr(SessionUrl(W.Target,S)) +
                           '">' + HtmlEncode(W.Lbl) + '</a>';
    'button':    // POST form button with action-token (no JS)
      Result := '<form method="POST" action="' + HtmlAttr(W.Target) + '">' +
                AuthHiddenFields(S, 'widget:' + W.Id) +
                '<input type="submit" value="' + HtmlAttr(W.Lbl) + '"></form>';
    'textinput': Result := HtmlEncode(W.Lbl) + ' <input name="' + HtmlAttr(W.Name) +
                           '" value="' + HtmlAttr(W.Value) + '"'+RequiredAttrs(W)+'>';
    'password':  Result := HtmlEncode(W.Lbl) + ' <input type="password" name="' +
                           HtmlAttr(W.Name) + '"'+RequiredAttrs(W)+'>';
    'textarea':  Result := HtmlEncode(W.Lbl) + '<br><textarea name="' + HtmlAttr(W.Name) +
                           '"'+RequiredAttrs(W)+'>' + HtmlEncode(W.Value) + '</textarea>';
    'checkbox':  Result := '<input type="checkbox" name="' + HtmlAttr(W.Name) +
                           '"'+RequiredAttrs(W)+'> ' + HtmlEncode(W.Lbl);
    'select':    Result := RenderSelect(W);
    'dataview':
      begin
        DV := FindDataView(W.Binding);
        if Assigned(DV) then
          Result := DV(Db,W,S,Dir,PageUrl)
        else
          Result := '<i>[dataview: ' + HtmlEncode(W.Binding) + ' — no renderer]</i>';
      end;
  else
    Result := '<i>[' + HtmlEncode(W.Typ) + ']</i>';
  end;

  if W.Required and SameText(W.Typ,'color') then
  begin
    Result:=StringReplace(Result,'<input ','<input required="required" ',[rfReplaceAll]);
    Result:=StringReplace(Result,'<select ','<select required="required" ',[rfReplaceAll]);
  end;

  if W.Required and (Pos('|'+LowerCase(W.Typ)+'|',
    '|textinput|password|textarea|checkbox|select|color|')>0) then
    Result:=Result+' <b>* (required)</b>';

  // apply per-widget colors (WeKan name or hex) the retro-safe way: <font color> for text,
  // a 1-cell bgcolor table for background. Both degrade cleanly and modern browsers honor them.
  if ResolveColor(W.FgColor) <> '' then
    Result := FontOpen(W.FgColor) + Result + FontClose(W.FgColor);
  if ResolveColor(W.BgColor) <> '' then
    Result := '<table' + BgColorAttr(W.BgColor) + ' cellpadding="2" cellspacing="0" ' +
              'border="0"><tr><td>' + Result + '</td></tr></table>';
end;

// Collect ALL values for a repeated query key (TStrings keeps repeated key=value lines), also
// splitting a single comma-joined value. Used for the column-visibility selection.
function CollectValues(Params: TStrings; const Key: string): TStringList;
var i, k: Integer; v: string; parts: TStringArray;
begin
  Result := TStringList.Create;
  if Params = nil then Exit;
  for i := 0 to Params.Count - 1 do
    if SameText(Params.Names[i], Key) then
    begin
      v := Params.ValueFromIndex[i];
      if Pos(',', v) > 0 then
      begin
        parts := v.Split([',']);
        for k := 0 to High(parts) do
          if Trim(parts[k]) <> '' then Result.Add(Trim(parts[k]));
      end
      else if Trim(v) <> '' then
        Result.Add(Trim(v));
    end;
end;

// ------------------------------------------------------------------ table component
// A reusable, no-JS data table (like WeKan's list/admin tables): search box top-left,
// "Page n / m" pagination on top, a column-visibility chooser, and click-a-cell-to-edit links.
// Configured per placement via the widget's options_json:
//   { "source":"cards", "rowKey":"id", "editUrl":"/card/edit", "pageSize":20,
//     "search":["title","description"],
//     "columns":[ {"name":"title","label":"Title"},
//                 {"name":"dueAt","label":"Due","type":"date","editable":true,"visible":true},
//                 {"name":"description","label":"Notes","visible":false} ] }
// Per-widget request params (so several tables can coexist on one page):
//   tq_<id> = search text   tp_<id> = 1-based page   tc_<id> = visible column (repeatable)
function RenderTable(Db: TWLDb; const W: TWidget; const S: TWLSession;
  Params: TStrings; const Dir: string): string;
var
  Cfg: TJSONData;
  O: TJSONObject;
  Cols, SearchCols: TJSONArray;
  Source, RowKey, EditUrl, Q, Align, SelList, WhereSql, Slug, BaseQ, ColQ, Hdr, Cell: string;
  PageSize, PageNo, Total, TotalPages, Offset, i, j: Integer;
  Rows, CountRows: TWLRows;
  ColObj: TJSONObject;
  Chosen: TStringList;                 // explicit visible set from tc_ params ('' count -> default)
  VisName, VisLabel: array of string;  // visible columns, in config order
  VisEditable: array of Boolean;
  Chooser, ColName, ColLabel: string;
  Visible: Boolean;
begin
  Result := '';
  try
    Cfg := GetJSON(W.OptionsJson);
  except
    Exit('<i>[table: bad options_json]</i>');
  end;
  Chosen := nil;
  try
    if not (Cfg is TJSONObject) then Exit('<i>[table: options must be an object]</i>');
    O := TJSONObject(Cfg);
    Source   := O.Get('source', '');
    RowKey   := O.Get('rowKey', 'id');
    EditUrl  := O.Get('editUrl', '');
    PageSize := O.Get('pageSize', 20);
    if PageSize < 1 then PageSize := 20;
    Cols       := O.Find('columns') as TJSONArray;
    SearchCols := O.Find('search')  as TJSONArray;
    if (Source = '') or (Cols = nil) then Exit('<i>[table: source/columns missing]</i>');

    if SameText(Dir, 'rtl') then Align := 'right' else Align := 'left';
    Slug := W.Id;
    if Params <> nil then
    begin
      Q := Trim(Params.Values['tq_' + Slug]);
      PageNo := StrToIntDef(Params.Values['tp_' + Slug], 1);
    end
    else begin Q := ''; PageNo := 1; end;
    if PageNo < 1 then PageNo := 1;

    // --- column visibility: tc_<id> params override per-column "visible" default ---------
    Chosen := CollectValues(Params, 'tc_' + Slug);
    Chooser := '';        // checkboxes; emitted inside the search form below
    ColQ := '';           // &tc_<id>=name for each visible col, carried on pagination links
    SetLength(VisName, 0); SetLength(VisLabel, 0); SetLength(VisEditable, 0);
    for j := 0 to Cols.Count - 1 do
    begin
      ColObj := Cols.Objects[j];
      ColName := ColObj.Get('name', '');
      ColLabel := ColObj.Get('label', ColName);
      if Chosen.Count > 0 then
        Visible := Chosen.IndexOf(ColName) >= 0
      else
        Visible := ColObj.Get('visible', True);     // default visibility from config
      Chooser := Chooser + '<label><input type="checkbox" name="tc_' + HtmlAttr(Slug) +
                 '" value="' + HtmlAttr(ColName) + '"' +
                 ifthen(Visible, ' checked', '') + '> ' + HtmlEncode(ColLabel) + '</label> ';
      if Visible then
      begin
        SetLength(VisName, Length(VisName) + 1);     VisName[High(VisName)] := ColName;
        SetLength(VisLabel, Length(VisLabel) + 1);   VisLabel[High(VisLabel)] := ColLabel;
        SetLength(VisEditable, Length(VisEditable) + 1);
        VisEditable[High(VisEditable)] := ColObj.Get('editable', False);
        ColQ := ColQ + '&tc_' + Slug + '=' + ColName;
      end;
    end;
    if Length(VisName) = 0 then    // never hide everything; fall back to first column
    begin
      SetLength(VisName, 1);  VisName[0] := (Cols.Objects[0]).Get('name', '');
      SetLength(VisLabel, 1); VisLabel[0] := (Cols.Objects[0]).Get('label', VisName[0]);
      SetLength(VisEditable, 1); VisEditable[0] := False;
      ColQ := '&tc_' + Slug + '=' + VisName[0];
    end;

    // WHERE from the configured search columns (LIKE %q%); CLI backend escapes via QuotedStr
    WhereSql := '';
    if (Q <> '') and (SearchCols <> nil) and (SearchCols.Count > 0) then
    begin
      WhereSql := ' WHERE (';
      for i := 0 to SearchCols.Count - 1 do
      begin
        if i > 0 then WhereSql := WhereSql + ' OR ';
        WhereSql := WhereSql + SearchCols.Strings[i] + ' LIKE ' + QuotedStr('%' + Q + '%');
      end;
      WhereSql := WhereSql + ')';
    end;

    // total + page count
    CountRows := Db.Query(Format('SELECT COUNT(*) FROM %s%s;', [Source, WhereSql]));
    if (Length(CountRows) > 0) and (Length(CountRows[0]) > 0) then
      Total := StrToIntDef(CountRows[0][0], 0)
    else
      Total := 0;
    TotalPages := (Total + PageSize - 1) div PageSize;
    if TotalPages < 1 then TotalPages := 1;
    if PageNo > TotalPages then PageNo := TotalPages;
    Offset := (PageNo - 1) * PageSize;

    // SELECT rowKey + only the VISIBLE columns
    SelList := RowKey;
    for j := 0 to High(VisName) do
      SelList := SelList + ',' + VisName[j];
    Rows := Db.Query(Format('SELECT %s FROM %s%s LIMIT %d OFFSET %d;',
      [SelList, Source, WhereSql, PageSize, Offset]));

    // query-only hrefs (start with '?') keep the current path on retro browsers; they replace
    // the whole query string, so we re-include sessionId + search + visible-column set each time.
    BaseQ := '?sessionId=' + S.SessionId + '&tq_' + Slug + '=' + HTTPEncode(Q) + ColQ;
    if S.LanguageTag<>'' then BaseQ:=BaseQ+'&lang='+S.LanguageTag;

    // --- top bar: search + column chooser (left), pagination "Page n / m" (right) --------
    // one GET form carries the search text AND the column checkboxes (Apply submits both)
    Result :=
      '<table border="0" width="100%"><tr>' +
      '<td align="' + Align + '">' +
        '<form method="GET">' +
        '<input type="hidden" name="sessionId" value="' + HtmlAttr(S.SessionId) + '">' +LanguageHiddenField(S)+
        'Search <input name="tq_' + HtmlAttr(Slug) + '" value="' + HtmlAttr(Q) + '"> ' +
        '<br>Columns: ' + Chooser +
        '<input type="submit" value="Apply"></form>' +
      '</td>' +
      '<td align="right" valign="top">';
    if PageNo > 1 then
      Result := Result + '<a href="' + HtmlAttr(BaseQ + '&tp_' + Slug + '=' +
                IntToStr(PageNo - 1)) + '">&lt; Prev</a> ';
    Result := Result + 'Page ' + IntToStr(PageNo) + ' / ' + IntToStr(TotalPages);
    if PageNo < TotalPages then
      Result := Result + ' <a href="' + HtmlAttr(BaseQ + '&tp_' + Slug + '=' +
                IntToStr(PageNo + 1)) + '">Next &gt;</a>';
    Result := Result + '</td></tr></table>' + LineEnding;

    // --- header row (visible columns only) ----------------------------------------------
    Hdr := '<tr>';
    for j := 0 to High(VisName) do
      Hdr := Hdr + '<th align="' + Align + '">' + HtmlEncode(VisLabel[j]) + '</th>';
    Hdr := Hdr + '</tr>';

    // --- body: visible cells; editable cells link to editUrl?id=..&field=.. --------------
    Result := Result + '<table border="1" cellpadding="3" cellspacing="0" width="100%">' +
              LineEnding + Hdr + LineEnding;
    for i := 0 to High(Rows) do
    begin
      if Length(Rows[i]) < Length(VisName) + 1 then Continue;   // [0]=rowKey, [1..]=visible cols
      Result := Result + '<tr>';
      for j := 0 to High(VisName) do
      begin
        Cell := HtmlEncode(Rows[i][j + 1]);
        // click an editable cell -> edit page for that field (date/text/etc.); that page is a
        // form and may itself be a Designer page. rowKey value is Rows[i][0].
        if VisEditable[j] and (EditUrl <> '') then
          Cell := '<a href="' + HtmlAttr(SessionUrl(
                    EditUrl + '?id=' + HTTPEncode(Rows[i][0]) + '&field=' + HTTPEncode(VisName[j]),S)) +
                   '">' + Cell + '</a>';
        Result := Result + '<td align="' + Align + '">' + Cell + '</td>';
      end;
      Result := Result + '</tr>' + LineEnding;
    end;
    Result := Result + '</table>';
  finally
    Chosen.Free;
    Cfg.Free;
  end;
end;

// ------------------------------------------------------------------ direction (LTR/RTL)
function LangIsRtl(const Lang: string): Boolean;
begin Result:=LanguageIsRtl(Lang);end;

function SessionLanguage(Db:TWLDb;const S:TWLSession):string;
begin Result:=wllocale.SessionLanguage(Db,S);end;

function ResolveDir(aRequest: TRequest; const PageDirOverride: string;const ProfileLanguage:string): string;
var Language:TWLLanguage;
begin
  if SameText(PageDirOverride,'rtl') then Exit('rtl');
  if SameText(PageDirOverride,'ltr') then Exit('ltr');
  Language:=ResolveLanguage(RequestLanguageTag(aRequest),ProfileLanguage,
    aRequest.AcceptLanguage);
  if Language.Rtl then Result:='rtl' else Result:='ltr';
end;

// A spanning cell is emitted at its visual leading edge. RTL uses the right edge
// of the same logical rectangle, so its content is rendered once in either direction.
function GridCell(const W: TWidgetArray; Row,Col,Cols:Integer; Rtl:Boolean;
  out AnchorRow,AnchorCol,RowSpan,ColSpan:Integer):Boolean;
var i,Leading:Integer;
begin
  AnchorRow:=Row; AnchorCol:=Col; RowSpan:=1; ColSpan:=1;
  Result:=True;
  for i:=0 to High(W) do
    if (W[i].Row>=0) and (W[i].Row<100) and (W[i].Col>=0) and
      (W[i].Col<Cols) and (W[i].RowSpan>0) and (W[i].ColSpan>0) and
      (W[i].RowSpan<=100-W[i].Row) and (W[i].ColSpan<=Cols-W[i].Col) and
      (Row>=W[i].Row) and (Row<W[i].Row+W[i].RowSpan) and
      (Col>=W[i].Col) and (Col<W[i].Col+W[i].ColSpan) then
    begin
      AnchorRow:=W[i].Row; AnchorCol:=W[i].Col;
      RowSpan:=W[i].RowSpan; ColSpan:=W[i].ColSpan;
      Leading:=AnchorCol;
      if Rtl then Leading:=AnchorCol+ColSpan-1;
      Exit((Row=AnchorRow) and (Col=Leading));
    end;
end;

function GridMaxRow(const W:TWidgetArray):Integer;
var i:Integer;
begin
  Result:=0;
  for i:=0 to High(W) do
    if (W[i].Row>=0) and (W[i].Row<100) and (W[i].RowSpan>0) then
      Result:=Max(Result,Min(99,W[i].Row+W[i].RowSpan-1));
end;

// ------------------------------------------------------------------ page render
function RenderPage(Db: TWLDb; const P: TPage; const S: TWLSession;
  Params: TStrings; const Dir: string;const LanguageTag:string): string;
var
  W: TWidgetArray;
  Body: string;
  r,c,i,MaxRow,ViewCol,AnchorRow,AnchorCol,RowSpan,ColSpan:Integer;
  CellHtml,Align,PageDirection:string;
  Rtl: Boolean;
begin
  W := LoadWidgets(Db, P.Id);
  MaxRow:=GridMaxRow(W);

  PageDirection:=Dir;
  if (P.Dir='rtl') or (P.Dir='ltr') then PageDirection:=P.Dir;
  Rtl := SameText(PageDirection, 'rtl');
  if Rtl then Align := 'right' else Align := 'left';

  Body := '<table dir="ltr" border="0" cellpadding="4" cellspacing="0" width="100%">' + LineEnding;
  for r := 0 to MaxRow do
  begin
    Body := Body + '<tr>' + LineEnding;
    // RTL mirroring: walk view columns right-to-left so column 0 (logical start) ends up on
    // the right. Structural — works on HTML 3.2 browsers that ignore the dir attribute.
    for ViewCol := 0 to P.Cols - 1 do
    begin
      if Rtl then c := P.Cols - 1 - ViewCol else c := ViewCol;
      if not GridCell(W,r,c,P.Cols,Rtl,AnchorRow,AnchorCol,RowSpan,ColSpan) then Continue;
      CellHtml := '';
      for i := 0 to High(W) do                       // widgets already sorted by row,col,sort
        if (W[i].Row=AnchorRow) and (W[i].Col=AnchorCol) then
        begin
          if CellHtml <> '' then CellHtml := CellHtml + '<br>';
          CellHtml := CellHtml + RenderWidget(Db,W[i],S,Params,PageDirection,P.Url);
        end;
      Body := Body + '  <td dir="'+PageDirection+'" valign="top" align="'+Align+'" rowspan="'+IntToStr(RowSpan)+
        '" colspan="'+IntToStr(ColSpan)+'" data-grid-row="'+IntToStr(AnchorRow)+
        '" data-grid-col="'+IntToStr(AnchorCol)+'">' + CellHtml + '</td>' + LineEnding;
    end;
    Body := Body + '</tr>' + LineEnding;
  end;
  Body := Body + '</table>';

  // Progressive enhancement: emit the MultiDrag/touch scripts before </body>. They self-gate
  // client-side (no-JS/retro browsers ignore them), so JS+touch features — dragging many cards
  // at once on a big touch screen — "just appear" without changing the form baseline. Passing a
  // detected browser here (instead of wbUnknown) would let us skip the bytes for no-JS clients.
  Body := Body + LineEnding + EnhancementScripts(wbUnknown);

  // doctype: html32 is the baseline; html4 adds dir="rtl" on <body> too (retro browsers ignore
  // it, hence the structural column reversal above). One page definition serves both directions.
  Result := PageDir(P.Title,Body,PageDirection,LanguageTag,P.Doctype);
end;

// ------------------------------------------------------------------ dispatcher hook
function RoleAllows(Db: TWLDb; const MinRole: string; const S: TWLSession): Boolean;
begin
  if SameText(MinRole, 'anon') then Exit(True);
  if SameText(MinRole,'admin') then Exit(IsTenantAdmin(Db,S));
  Result := SameText(MinRole,'member') and (S.UserId<>'');
end;

function TryServePage(ATenant: TWLTenant; const S: TWLSession;
  const Path, Dir: string; Params: TStrings; aResponse: TResponse;const LanguageTag:string): Boolean;
var P: TPage;Language:TWLLanguage;
begin
  Result := False;
  if not LoadPageByUrl(ATenant.Db, Path, P) then Exit;   // no enabled page at this path
  if not RoleAllows(ATenant.Db, P.MinRole, S) then Exit;             // -> caller falls through to 404
  aResponse.Code := 200;
  aResponse.ContentType := 'text/html; charset=utf-8';
  if not FindLanguage(LanguageTag,Language) then Language:=ResolveLanguage('',SessionLanguage(ATenant.Db,S),'');
  LanguageHeaders(aResponse,Language);
  aResponse.Content := RenderPage(ATenant.Db, P, S, Params, Dir,Language.Tag);
  aResponse.ContentLength := Length(aResponse.Content);
  aResponse.SendContent;
  Result := True;
end;

// ------------------------------------------------------------------ editor helpers
function NowIso: string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Now);
end;

// Mongo-style 17-char id (schema.sql convention). Real build uses the shared id routine; this
// is a local generator for imported rows. Vary by Randomize at startup.
function NewId: string;
const
  ALPHABET = '23456789ABCDEFGHJKLMNPQRSTWXYZabcdefghijkmnopqrstuvwxyz';
var i: Integer;
begin
  SetLength(Result, 17);
  for i := 1 to 17 do
    Result[i] := ALPHABET[Random(Length(ALPHABET)) + 1];
end;

// ------------------------------------------------------------------ import / export
function ExportPageJson(Db: TWLDb; const P: TPage): string;
var
  O, PgO, WO: TJSONObject;
  A: TJSONArray;
  W: TWidgetArray;
  i: Integer;
begin
  O := TJSONObject.Create;
  try
    O.Add('welite_page', 1);                 // format version
    PgO := TJSONObject.Create;
    PgO.Add('url', P.Url);          PgO.Add('title', P.Title);
    PgO.Add('kind', P.Kind);        PgO.Add('builtinKey', P.BuiltinKey);
    PgO.Add('cols', P.Cols);        PgO.Add('doctype', P.Doctype);
    PgO.Add('dir', P.Dir);          PgO.Add('minRole', P.MinRole);
    PgO.Add('enabled', P.Enabled);
    O.Add('page', PgO);

    A := TJSONArray.Create;
    W := LoadWidgets(Db, P.Id);     // ids omitted on purpose — regenerated on import
    for i := 0 to High(W) do
    begin
      WO := TJSONObject.Create;
      WO.Add('type', W[i].Typ);     WO.Add('label', W[i].Lbl);
      WO.Add('name', W[i].Name);    WO.Add('value', W[i].Value);
      WO.Add('target', W[i].Target);WO.Add('binding', W[i].Binding);
      WO.Add('options_json', W[i].OptionsJson);
      WO.Add('fgColor', W[i].FgColor); WO.Add('bgColor', W[i].BgColor);
      WO.Add('row', W[i].Row);      WO.Add('col', W[i].Col);
      WO.Add('rowspan', W[i].RowSpan); WO.Add('colspan', W[i].ColSpan);
      WO.Add('sort', W[i].Sort);    WO.Add('required', W[i].Required);
      A.Add(WO);
    end;
    O.Add('widgets', A);
    Result := O.FormatJSON;
  finally
    O.Free;
  end;
end;

function ValidPageUrl(const Url:string):Boolean; forward;
function SafeWidgetTarget(const Target:string):Boolean; forward;

function ValidPageModel(const P:TPage):Boolean;
begin
  Result:=ValidPageUrl(P.Url) and (Trim(P.Title)<>'') and (P.Cols>=1) and (P.Cols<=12) and
    ((P.Kind='custom') or (P.Kind='builtin')) and
    ((P.Doctype='html32') or (P.Doctype='html4')) and
    ((P.Dir='auto') or (P.Dir='ltr') or (P.Dir='rtl')) and
    ((P.MinRole='anon') or (P.MinRole='member') or (P.MinRole='admin'));
end;

function ValidWidgetModel(const P:TPage; const W:TWidget):Boolean;
var D:TJSONData; OptionsValid:Boolean;
begin
  D:=nil; OptionsValid:=False;
  try
    try D:=GetJSON(W.OptionsJson); OptionsValid:=D is TJSONObject; except end;
  finally D.Free; end;
  Result:=(Pos('|'+W.Typ+'|','|heading|label|link|button|textinput|password|textarea|select|checkbox|hr|spacer|dataview|table|color|movepanel|')>0) and
    OptionsValid and (W.Row>=0) and (W.Row<=99) and (W.Col>=0) and (W.Col<P.Cols) and
    (W.RowSpan>=1) and (W.RowSpan<=100-W.Row) and (W.ColSpan>=1) and (W.ColSpan<=P.Cols-W.Col) and
    not IsNan(W.Sort) and not IsInfinite(W.Sort) and
    ((W.FgColor='') or (ResolveColor(W.FgColor)<>'')) and
    ((W.BgColor='') or (ResolveColor(W.BgColor)<>'')) and SafeWidgetTarget(W.Target);
end;

function WidgetPairFits(const A,B:TWidget):Boolean;
begin
  if (A.Row=B.Row) and (A.Col=B.Col) then
    Exit((A.RowSpan=B.RowSpan) and (A.ColSpan=B.ColSpan));
  Result:=not ((A.Row<B.Row+B.RowSpan) and (A.Row+A.RowSpan>B.Row) and
    (A.Col<B.Col+B.ColSpan) and (A.Col+A.ColSpan>B.Col));
end;

function SqlNumber(Value:Double):string;
begin
  Result:=StringReplace(FloatToStr(Value),DefaultFormatSettings.DecimalSeparator,'.',[]);
end;

// Prepare SQL only after decoding and validating the complete page. Nothing is written here.
function PreparePageImport(const Json:string; out Url,Sql:string):Boolean;
var D:TJSONData; O,Pg,WO:TJSONObject; A:TJSONArray; P:TPage; W:TWidgetArray; i,j:Integer;
begin
  Result:=False; Url:=''; Sql:=''; D:=nil;
  if Length(Json)>8*1024*1024 then Exit;
  try
    try
      D:=GetJSON(Json);
      if not (D is TJSONObject) then Exit;
      O:=TJSONObject(D);
      if O.Get('welite_page',0)<>1 then Exit;
      if not (O.Find('page') is TJSONObject) or not (O.Find('widgets') is TJSONArray) then Exit;
      Pg:=TJSONObject(O.Find('page')); A:=TJSONArray(O.Find('widgets'));
      if A.Count>1000 then Exit;
      P:=Default(TPage); P.Id:=NewId;
      P.Url:=Trim(Pg.Get('url','')); P.Title:=Trim(Pg.Get('title',''));
      P.Kind:=Pg.Get('kind','custom'); P.BuiltinKey:=Pg.Get('builtinKey','');
      P.Cols:=Pg.Get('cols',1); P.Doctype:=Pg.Get('doctype','html32'); P.Dir:=Pg.Get('dir','auto');
      P.MinRole:=Pg.Get('minRole','member'); P.Enabled:=Pg.Get('enabled',True);
      if not ValidPageModel(P) then Exit;
      SetLength(W,A.Count);
      for i:=0 to A.Count-1 do
      begin
        if not (A.Items[i] is TJSONObject) then Exit;
        WO:=TJSONObject(A.Items[i]); W[i]:=Default(TWidget); W[i].Id:=NewId;
        W[i].Typ:=LowerCase(WO.Get('type','label')); W[i].Lbl:=WO.Get('label','');
        W[i].Name:=WO.Get('name',''); W[i].Value:=WO.Get('value',''); W[i].Target:=WO.Get('target','');
        W[i].Binding:=WO.Get('binding',''); W[i].OptionsJson:=WO.Get('options_json','{}');
        if W[i].OptionsJson='' then W[i].OptionsJson:='{}';
        W[i].FgColor:=WO.Get('fgColor',''); W[i].BgColor:=WO.Get('bgColor','');
        W[i].Row:=WO.Get('row',0); W[i].Col:=WO.Get('col',0);
        W[i].RowSpan:=WO.Get('rowspan',1); W[i].ColSpan:=WO.Get('colspan',1);
        W[i].Sort:=WO.Get('sort',0.0); W[i].Required:=WO.Get('required',False);
        if not ValidWidgetModel(P,W[i]) then Exit;
        for j:=0 to i-1 do if not WidgetPairFits(W[i],W[j]) then Exit;
      end;
      Sql:='DELETE FROM pages WHERE url='+QuotedStr(P.Url)+'; '+
        'INSERT INTO pages(id,url,title,kind,builtinKey,cols,doctype,dir,minRole,enabled,createdAt,modifiedAt) VALUES('+
        QuotedStr(P.Id)+','+QuotedStr(P.Url)+','+QuotedStr(P.Title)+','+QuotedStr(P.Kind)+','+
        QuotedStr(P.BuiltinKey)+','+IntToStr(P.Cols)+','+QuotedStr(P.Doctype)+','+QuotedStr(P.Dir)+','+
        QuotedStr(P.MinRole)+','+IntToStr(Ord(P.Enabled))+','+QuotedStr(NowIso)+','+QuotedStr(NowIso)+'); ';
      for i:=0 to High(W) do
        Sql:=Sql+'INSERT INTO page_widgets(id,pageId,row,col,rowspan,colspan,sort,type,label,name,value,target,'+
          'binding,options_json,fgColor,bgColor,required,createdAt,modifiedAt) VALUES('+
          QuotedStr(W[i].Id)+','+QuotedStr(P.Id)+','+IntToStr(W[i].Row)+','+IntToStr(W[i].Col)+','+
          IntToStr(W[i].RowSpan)+','+IntToStr(W[i].ColSpan)+','+SqlNumber(W[i].Sort)+','+
          QuotedStr(W[i].Typ)+','+QuotedStr(W[i].Lbl)+','+QuotedStr(W[i].Name)+','+QuotedStr(W[i].Value)+','+
          QuotedStr(W[i].Target)+','+QuotedStr(W[i].Binding)+','+QuotedStr(W[i].OptionsJson)+','+
          QuotedStr(W[i].FgColor)+','+QuotedStr(W[i].BgColor)+','+IntToStr(Ord(W[i].Required))+','+
          QuotedStr(NowIso)+','+QuotedStr(NowIso)+'); ';
      Url:=P.Url; Result:=True;
    except Result:=False; Url:=''; Sql:=''; end;
  finally D.Free; end;
end;

function ExecuteImport(Db:TWLDb; const Sql:string):Boolean;
begin
  Result:=Db.Exec('BEGIN IMMEDIATE; '+Sql+' COMMIT;');
  if not Result then Db.Exec('ROLLBACK;');
end;

function ImportPageJson(Db:TWLDb; const Json:string):string;
var Url,Sql:string;
begin
  Result:='';
  if PreparePageImport(Json,Url,Sql) and ExecuteImport(Db,Sql) then Result:=Url;
end;

procedure ExportAllPages(Db: TWLDb; OutStream: TStream);
var
  Z: TZipper;
  R: TWLRows;
  P: TPage;
  i: Integer;
  Manifest: TJSONObject;
  Urls: TJSONArray;
  Entry: TStringStream;
  Streams: TList;            // keep entry streams alive until SaveToStream
begin
  Z := TZipper.Create;
  Streams := TList.Create;
  try
    Manifest := TJSONObject.Create;
    Urls := TJSONArray.Create;

    R := Db.Query('SELECT id FROM pages ORDER BY url;');
    for i := 0 to High(R) do
      if (Length(R[i]) > 0) and LoadPageById(Db,R[i][0],P) then
      begin
        Entry := TStringStream.Create(ExportPageJson(Db, P));
        Streams.Add(Entry);
        Z.Entries.AddFileEntry(Entry,'p'+Format('%.7d',[Urls.Count+1])+'.wlp');
        Urls.Add(P.Url);
      end;

    Manifest.Add('welite_pages', 1);
    Manifest.Add('count', Urls.Count);
    Manifest.Add('urls', Urls);
    Entry := TStringStream.Create(Manifest.FormatJSON);
    Streams.Add(Entry);
    Z.Entries.AddFileEntry(Entry, 'manifest.jsn');
    Manifest.Free;

    Z.SaveToStream(OutStream);   // NOTE: exact stream API may vary by FPC version
  finally
    for i := 0 to Streams.Count - 1 do TObject(Streams[i]).Free;
    Streams.Free;
    Z.Free;
  end;
end;

type
  TZipSink = class
    Pages:TStringList;
    Manifest:string;
    HasManifest:Boolean;
    Total:Int64;
    constructor Create;
    destructor Destroy; override;
    procedure DoCreate(Sender:TObject; var AStream:TStream; AItem:TFullZipFileEntry);
    procedure DoDone(Sender:TObject; var AStream:TStream; AItem:TFullZipFileEntry);
  end;
constructor TZipSink.Create;
begin inherited Create; Pages:=TStringList.Create; Total:=0; end;
destructor TZipSink.Destroy;
begin Pages.Free; inherited Destroy; end;
procedure TZipSink.DoCreate(Sender:TObject; var AStream:TStream; AItem:TFullZipFileEntry);
var Name:string;
begin
  Name:=AItem.ArchiveFileName;
  if (Name='') or (Pos('/',Name)>0) or (Pos('\',Name)>0) or (Pos(':',Name)>0) or
    (Name[1]='.') or ((LowerCase(Name)<>'manifest.jsn') and (LowerCase(ExtractFileExt(Name))<>'.wlp')) then
    raise Exception.Create('Invalid archive entry');
  if (AItem.Size<0) or (AItem.Size>8*1024*1024) or (Pages.Count>1000) then
    raise Exception.Create('Archive limits exceeded');
  Total:=Total+AItem.Size;
  if Total>64*1024*1024 then raise Exception.Create('Archive limits exceeded');
  // Never return nil: TUnZipper would otherwise fall back to filesystem extraction.
  AStream:=TMemoryStream.Create;
end;
procedure TZipSink.DoDone(Sender:TObject; var AStream:TStream; AItem:TFullZipFileEntry);
var S:TStringStream;
begin
  S:=TStringStream.Create('');
  try
    AStream.Position:=0; S.CopyFrom(AStream,0);
    if LowerCase(AItem.ArchiveFileName)='manifest.jsn' then
    begin
      if HasManifest then raise Exception.Create('Duplicate manifest');
      HasManifest:=True; Manifest:=S.DataString;
    end
    else Pages.Add(S.DataString);
  finally S.Free; FreeAndNil(AStream); end;
end;

function ImportAllPages(Db:TWLDb; InStream:TStream):Integer;
var UZ:TUnZipper; Sink:TZipSink; Tmp,TmpDir,Sql,Part,Url:string; FS:TFileStream;
  i:Integer; D:TJSONData; O:TJSONObject; Urls:TJSONArray; Seen:TStringList;
begin
  Result:=-1; D:=nil; Seen:=TStringList.Create; Seen.CaseSensitive:=True;
  Sink:=TZipSink.Create; UZ:=TUnZipper.Create;
  TmpDir:=WLTempDir('import'); Tmp:=TmpDir+'upload.zip';
  try
    try
      InStream.Position:=0;
      FS:=TFileStream.Create(Tmp,fmCreate);
      try FS.CopyFrom(InStream,0); finally FS.Free; end;
      UZ.OnCreateStream:=@Sink.DoCreate; UZ.OnDoneStream:=@Sink.DoDone;
      UZ.FileName:=Tmp; UZ.UnZipAllFiles;
      if Sink.Manifest='' then Exit;
      D:=GetJSON(Sink.Manifest);
      if not (D is TJSONObject) then Exit;
      O:=TJSONObject(D);
      if (O.Get('welite_pages',0)<>1) or (O.Get('count',-1)<>Sink.Pages.Count) or
        not (O.Find('urls') is TJSONArray) then Exit;
      Urls:=TJSONArray(O.Find('urls'));
      if Urls.Count<>Sink.Pages.Count then Exit;
      Sql:='';
      for i:=0 to Sink.Pages.Count-1 do
      begin
        if not PreparePageImport(Sink.Pages[i],Url,Part) or (Seen.IndexOf(Url)>=0) then Exit;
        Seen.Add(Url); Sql:=Sql+Part;
      end;
      // The manifest must describe exactly this bundle, independent of archive order.
      for i:=0 to Urls.Count-1 do
      begin
        if Seen.IndexOf(Urls.Strings[i])<0 then Exit;
        Seen.Delete(Seen.IndexOf(Urls.Strings[i]));
      end;
      if ExecuteImport(Db,Sql) then Result:=Sink.Pages.Count;
    except Result:=-1; end;
  finally
    D.Free; Seen.Free; UZ.Free; Sink.Free;
    if FileExists(Tmp) then DeleteFile(Tmp);
    RemoveDir(TmpDir);
  end;
end;

// Inline form button with action-token — the move/sort/edit/delete toolbar primitive.
function ToolButton(const S: TWLSession; const ActionPath, Caption: string;
  const HiddenName1, HiddenVal1, HiddenName2, HiddenVal2: string): string;
var DirectionAttr:string;
begin
  DirectionAttr:='';
  if ActionPath='/designer/widget/move' then DirectionAttr:=' dir="ltr"';
  Result := '<form method="POST" action="' + HtmlAttr(ActionPath) +
            '" style="display:inline">' + AuthHiddenFields(S, 'designer:' + ActionPath);
  if HiddenName1 <> '' then
    Result := Result + '<input type="hidden" name="' + HtmlAttr(HiddenName1) +
              '" value="' + HtmlAttr(HiddenVal1) + '">';
  if HiddenName2 <> '' then
    Result := Result + '<input type="hidden" name="' + HtmlAttr(HiddenName2) +
              '" value="' + HtmlAttr(HiddenVal2) + '">';
  Result := Result + '<input type="submit" value="' + HtmlAttr(Caption) + '"'+DirectionAttr+'></form>';
end;

// ------------------------------------------------------------------ editor endpoints
// Every editor/import/export endpoint uses the shared tenant-local administrator gate.
// Mutations additionally consume their action token before writing.

procedure DesignerError(aRequest:TRequest; aResponse:TResponse; Db:TWLDb;
  const S:TWLSession; Code:Integer; const Msg:string);
begin
  aResponse.Code := Code;
  aResponse.ContentType := 'text/html; charset=utf-8';
  aResponse.Content := LanguagePage(aResponse,ViewerLanguage(Db,S,aRequest),
    'Designer','<p>'+HtmlEncode(Msg)+'</p>');
  aResponse.SendContent;
end;

function RequireDesigner(aRequest: TRequest; aResponse: TResponse;
  out T: TWLTenant; out S: TWLSession): Boolean;
begin
  Result := RequireTenantAdmin(aRequest, aResponse, T, S);
  if not Result then Exit;
  Result := EnsureDesignerSchema(T.Db);
  if not Result then DesignerError(aRequest,aResponse,T.Db,S, 503, 'Designer schema unavailable');
end;

function PageFields(const P: TPage): string;
begin
  Result := ' URL <input name="url" value="'+HtmlAttr(P.Url)+'">' +
    ' Title <input name="title" value="'+HtmlAttr(P.Title)+'">' +
    ' Columns <input name="cols" size="2" value="'+IntToStr(P.Cols)+'">' +
    ' HTML <select name="doctype"><option>'+HtmlEncode(P.Doctype)+'</option>' +
    '<option>html32</option><option>html4</option></select>' +
    ' Direction <select name="dir"><option>'+HtmlEncode(P.Dir)+'</option>' +
    '<option>auto</option><option>ltr</option><option>rtl</option></select>' +
    ' Access <select name="minRole"><option>'+HtmlEncode(P.MinRole)+'</option>' +
    '<option>anon</option><option>member</option><option>admin</option></select>';
end;

procedure DesignerIndex(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; S: TWLSession; Rows: TWLRows; P: TPage; Body, Id, Toggle: string; i: Integer;
begin
  if not RequireDesigner(aRequest, aResponse, T, S) then Exit;
  Rows := T.Db.Query('SELECT id,url,title,enabled FROM pages ORDER BY url;');
  Body := '<h1>Designer</h1><table border="1" cellpadding="4"><tr>' +
    '<th>Page</th><th>URL</th><th>Enabled</th><th>Actions</th></tr>';
  for i:=0 to High(Rows) do
  begin
    Id := Rows[i][0];
    if Rows[i][3]='1' then Toggle:='disable' else Toggle:='enable';
    Body := Body+'<tr><td>'+HtmlEncode(Rows[i][2])+'</td><td>'+HtmlEncode(Rows[i][1])+
      '</td><td>'+HtmlEncode(Rows[i][3])+'</td><td><a href="'+
      HtmlAttr(SessionUrl('/designer/page?id='+HTTPEncode(Id),S))+'">Edit</a> '+
      '<a href="'+HtmlAttr(SessionUrl(Rows[i][1],S))+'">Preview</a> '+
      '<a href="'+HtmlAttr(SessionUrl('/designer/page/export?id='+HTTPEncode(Id),S))+'">Export</a> '+
      ToolButton(S,'/designer/page/save',Toggle,'pageId',Id,'action',Toggle)+
      ToolButton(S,'/designer/page/save','Delete','pageId',Id,'action','delete')+'</td></tr>';
  end;
  if Length(Rows)=0 then Body:=Body+'<tr><td colspan="4">No pages yet.</td></tr>';
  P := Default(TPage); P.Cols:=1; P.Doctype:='html32'; P.Dir:='auto'; P.MinRole:='member';
  Body:=Body+'</table><h2>Import/export</h2><p><a href="'+
    HtmlAttr(SessionUrl('/designer/export',S))+'">Export all pages</a></p>'+
    '<form method="POST" enctype="multipart/form-data" action="/designer/page/import">'+
    AuthHiddenFields(S,'designer:/designer/page/import')+
    '<input type="file" name="file"><input type="submit" value="Import page"></form>'+
    '<form method="POST" enctype="multipart/form-data" action="/designer/import">'+
    AuthHiddenFields(S,'designer:/designer/import')+
    '<input type="file" name="file"><input type="submit" value="Import ZIP"></form>'+
    '<h2>Add page</h2><form method="POST" action="/designer/page/save">'+
    AuthHiddenFields(S,'designer:/designer/page/save')+PageFields(P)+
    '<input type="submit" name="action" value="save"></form>';
  aResponse.Content:=LanguagePage(aResponse,ViewerLanguage(T.Db,S,aRequest),'Designer',Body);
  aResponse.ContentType:='text/html; charset=utf-8'; aResponse.SendContent;
end;

function ValidPageUrl(const Url: string): Boolean;
var i: Integer;
begin
  Result:=False;
  if (Length(Url)<2) or (Url[1]<>'/') or (Pos('//',Url)>0) or
    (Pos('..',Url)>0) or (Url[Length(Url)]='/') then Exit;
  for i:=2 to Length(Url) do
    if not (Url[i] in ['a'..'z','A'..'Z','0'..'9','/','-','_']) then Exit;
  if (Url='/sign-in') or (Url='/register') or (Url='/users/login') or
    (Url='/admin') or (Pos('/admin/',Url)=1) or (Url='/designer') or
    (Pos('/designer/',Url)=1) or (Url='/api') or (Pos('/api/',Url)=1) or
    ((Url='/board') or (Pos('/board/',Url)=1)) then Exit;
  Result:=True;
end;

procedure DesignerPageSave(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; S: TWLSession; P: TPage; Id, Action, Sql: string; F: TStrings;
begin
  if not RequireDesigner(aRequest,aResponse,T,S) then Exit;
  if not VerifyActionToken(aRequest,S,'designer:/designer/page/save') then
  begin DesignerError(aRequest,aResponse,T.Db,S,403,'Bad token'); Exit; end;
  F:=aRequest.ContentFields; Id:=F.Values['pageId']; Action:=F.Values['action'];
  P:=Default(TPage); P.Kind:='custom';
  if (Id<>'') and not LoadPageById(T.Db,Id,P) then
  begin DesignerError(aRequest,aResponse,T.Db,S,404,'Page not found'); Exit; end;
  if Action='delete' then
    Sql:='DELETE FROM pages WHERE id='+QuotedStr(Id)+';'
  else if (Action='enable') or (Action='disable') then
    Sql:='UPDATE pages SET enabled='+IntToStr(Ord(Action='enable'))+
      ',modifiedAt='+QuotedStr(NowIso)+' WHERE id='+QuotedStr(Id)+';'
  else if Action='save' then
  begin
    P.Url:=Trim(F.Values['url']); P.Title:=Trim(F.Values['title']);
    P.Cols:=StrToIntDef(F.Values['cols'],0); P.Doctype:=F.Values['doctype'];
    P.Dir:=F.Values['dir']; P.MinRole:=F.Values['minRole'];
    if not ValidPageModel(P) then
    begin DesignerError(aRequest,aResponse,T.Db,S,400,'Invalid page fields'); Exit; end;
    if Length(T.Db.Query('SELECT id FROM pages WHERE url='+QuotedStr(P.Url)+
      ' AND id<>'+QuotedStr(Id)+';'))>0 then
    begin DesignerError(aRequest,aResponse,T.Db,S,409,'Page URL already exists'); Exit; end;
    if Id='' then
    begin
      Id:=NewId;
      Sql:='INSERT INTO pages(id,url,title,cols,doctype,dir,minRole,createdAt,modifiedAt) VALUES('+
        QuotedStr(Id)+','+QuotedStr(P.Url)+','+QuotedStr(P.Title)+','+IntToStr(P.Cols)+','+
        QuotedStr(P.Doctype)+','+QuotedStr(P.Dir)+','+QuotedStr(P.MinRole)+','+
        QuotedStr(NowIso)+','+QuotedStr(NowIso)+');';
    end
    else
    begin
      // Reject shrinking a page if it would hide existing widgets.
      if Length(T.Db.Query('SELECT id FROM page_widgets WHERE pageId='+QuotedStr(Id)+
        ' AND col+colspan>'+IntToStr(P.Cols)+' LIMIT 1;'))>0 then
      begin DesignerError(aRequest,aResponse,T.Db,S,400,'Columns would hide widgets'); Exit; end;
      Sql:='UPDATE pages SET url='+QuotedStr(P.Url)+',title='+QuotedStr(P.Title)+
        ',cols='+IntToStr(P.Cols)+',doctype='+QuotedStr(P.Doctype)+',dir='+QuotedStr(P.Dir)+
        ',minRole='+QuotedStr(P.MinRole)+',modifiedAt='+QuotedStr(NowIso)+
        ' WHERE id='+QuotedStr(Id)+';';
    end;
  end
  else begin DesignerError(aRequest,aResponse,T.Db,S,400,'Unknown page action'); Exit; end;
  if not T.Db.Exec(Sql) then
  begin DesignerError(aRequest,aResponse,T.Db,S,500,'Could not save page'); Exit; end;
  aResponse.Code:=302;
  aResponse.SetCustomHeader('Location',SessionUrl('/designer',S));
  aResponse.SendContent;
end;

function WidgetForm(const S: TWLSession; const PageId: string; const W: TWidget;
  const Caption: string): string;
  function Field(const Name, Value: string): string;
  begin
    Result:=' '+HtmlEncode(Name)+' <input name="'+Name+'" value="'+HtmlAttr(Value)+'">';
  end;
begin
  Result:='<h2>'+HtmlEncode(Caption)+'</h2><form method="POST" action="/designer/widget/save">'+
    AuthHiddenFields(S,'designer:/designer/widget/save')+
    '<input type="hidden" name="pageId" value="'+HtmlAttr(PageId)+'">'+
    '<input type="hidden" name="widgetId" value="'+HtmlAttr(W.Id)+'">'+
    Field('type',W.Typ)+Field('label',W.Lbl)+Field('name',W.Name)+Field('value',W.Value)+
    Field('target',W.Target)+Field('binding',W.Binding)+
    Field('row',IntToStr(W.Row))+Field('col',IntToStr(W.Col))+
    Field('rowspan',IntToStr(W.RowSpan))+Field('colspan',IntToStr(W.ColSpan))+
    Field('sort',FloatToStr(W.Sort))+Field('fgColor',W.FgColor)+Field('bgColor',W.BgColor)+
    ' Options JSON <textarea name="options_json">'+HtmlEncode(W.OptionsJson)+'</textarea>'+
    ' <input type="checkbox" name="required" value="1"';
  if W.Required then Result:=Result+' checked';
  Result:=Result+'> Required <input type="submit" value="'+HtmlAttr(Caption)+'"></form>';
end;

procedure DesignerEditPage(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; S: TWLSession;
  P: TPage; W: TWidgetArray; EditWidget: TWidget;
  PageId, Body, Cell, Dir: string;
  r,c,i,MaxRow,ViewCol,AnchorRow,AnchorCol,RowSpan,ColSpan:Integer;
  Rtl: Boolean;
begin
  if not RequireDesigner(aRequest, aResponse, T, S) then Exit;

  PageId := aRequest.QueryFields.Values['id'];
  if not ((PageId<> '') and LoadPageById(T.Db,PageId,P)) and
    not LoadPageByUrl(T.Db,aRequest.QueryFields.Values['url'],P) then
  begin
    DesignerError(aRequest,aResponse,T.Db,S,404,'Page not found.'); Exit;
  end;

  W := LoadWidgets(T.Db, P.Id);
  MaxRow:=GridMaxRow(W);

  // editor mirrors the same way published pages do, so an RTL admin edits in a mirrored grid
  Dir := ResolveDir(aRequest, P.Dir,SessionLanguage(T.Db,S));
  Rtl := SameText(Dir, 'rtl');

  // grid editor: outer table = page grid; each cell shows widget preview + a button toolbar
  Body := '<h1>Edit: ' + HtmlEncode(P.Title) + '</h1>' +
    '<form method="POST" action="/designer/page/save">'+
    AuthHiddenFields(S,'designer:/designer/page/save')+
    '<input type="hidden" name="pageId" value="'+HtmlAttr(P.Id)+'">'+PageFields(P)+
    '<input type="submit" name="action" value="save"></form>'+LineEnding +
          '<table dir="ltr" border="1" cellpadding="4" cellspacing="0" width="100%">' + LineEnding;
  for r := 0 to MaxRow do
  begin
    Body := Body + '<tr>' + LineEnding;
    for ViewCol := 0 to P.Cols - 1 do
    begin
      if Rtl then c := P.Cols - 1 - ViewCol else c := ViewCol;
      if not GridCell(W,r,c,P.Cols,Rtl,AnchorRow,AnchorCol,RowSpan,ColSpan) then Continue;
      Cell := '';
      for i := 0 to High(W) do
        if (W[i].Row=AnchorRow) and (W[i].Col=AnchorCol) then
        begin
          Cell := Cell +
            '<b>[' + HtmlEncode(W[i].Typ) + ']</b> ' + HtmlEncode(W[i].Lbl) + '<br>' +
            ToolButton(S, '/designer/widget/move', '^', 'widgetId', W[i].Id, 'dir', 'up') +
            ToolButton(S, '/designer/widget/move', 'v', 'widgetId', W[i].Id, 'dir', 'down') +
            ToolButton(S, '/designer/widget/move', '<', 'widgetId', W[i].Id, 'dir', 'left') +
            ToolButton(S, '/designer/widget/move', '>', 'widgetId', W[i].Id, 'dir', 'right') +
            ToolButton(S,'/designer/widget/sort','Sort up','widgetId',W[i].Id,'dir','up')+
            ToolButton(S,'/designer/widget/sort','Sort down','widgetId',W[i].Id,'dir','down')+
            '<a href="'+HtmlAttr(SessionUrl('/designer/page?id='+HTTPEncode(P.Id)+
              '&widgetId='+HTTPEncode(W[i].Id),S))+'">Edit widget</a> ' +
            ToolButton(S, '/designer/widget/delete', 'Del', 'widgetId', W[i].Id, '', '') +
            '<hr>';
        end;
      Body := Body + '  <td dir="'+Dir+'" valign="top" rowspan="'+IntToStr(RowSpan)+'" colspan="'+IntToStr(ColSpan)+'">'+Cell + '</td>' + LineEnding;
    end;
    Body := Body + '</tr>' + LineEnding;
  end;
  Body:=Body+'</table>'+LineEnding;
  EditWidget:=Default(TWidget); EditWidget.Typ:='label';
  EditWidget.RowSpan:=1; EditWidget.ColSpan:=1; EditWidget.OptionsJson:='{}';
  for i:=0 to High(W) do
    if W[i].Id=aRequest.QueryFields.Values['widgetId'] then
    begin EditWidget:=W[i]; Break; end;
  if EditWidget.Id='' then
    Body:=Body+WidgetForm(S,P.Id,EditWidget,'Add widget')
  else
    Body:=Body+WidgetForm(S,P.Id,EditWidget,'Save widget');
  Body:=Body+'<p><a href="'+HtmlAttr(SessionUrl(P.Url,S))+'">Preview</a></p>';

  aResponse.Content := LanguagePage(aResponse,ViewerLanguage(T.Db,S,aRequest),'Designer — '+P.Title,Body,Dir);
  aResponse.ContentType := 'text/html; charset=utf-8';
  aResponse.SendContent;
end;

function LoadWidgetPage(Db: TWLDb; const WidgetId: string; out PageId: string): Boolean;
var R: TWLRows;
begin
  R:=Db.Query('SELECT pageId FROM page_widgets WHERE id='+QuotedStr(WidgetId)+';');
  Result:=Length(R)>0;
  if Result then PageId:=R[0][0] else PageId:='';
end;

procedure EditorRedirect(aResponse: TResponse; const PageId: string; const S: TWLSession);
begin
  aResponse.Code:=302;
  aResponse.SetCustomHeader('Location',SessionUrl('/designer/page?id='+HTTPEncode(PageId),S));
  aResponse.SendContent;
end;

function WidgetPlacementFits(Db:TWLDb; const PageId:string; const W:TWidget):Boolean;
var All:TWidgetArray; i:Integer;
begin
  All:=LoadWidgets(Db,PageId); Result:=False;
  for i:=0 to High(All) do
    if (All[i].Id<>W.Id) and not WidgetPairFits(All[i],W) then Exit;
  Result:=True;
end;

procedure DesignerWidgetSort(aRequest:TRequest; aResponse:TResponse);
var T:TWLTenant; S:TWLSession; R,Cell:TWLRows; Id,PageId,Dir,Sql,Tmp:string; i,Idx,Target:Integer;
begin
  if not RequireDesigner(aRequest,aResponse,T,S) then Exit;
  if not VerifyActionToken(aRequest,S,'designer:/designer/widget/sort') then
  begin DesignerError(aRequest,aResponse,T.Db,S,403,'Bad token'); Exit; end;
  Id:=aRequest.ContentFields.Values['widgetId'];
  R:=T.Db.Query('SELECT pageId,row,col FROM page_widgets WHERE id='+QuotedStr(Id)+';');
  if Length(R)=0 then begin DesignerError(aRequest,aResponse,T.Db,S,404,'Widget not found'); Exit; end;
  PageId:=R[0][0]; Dir:=aRequest.ContentFields.Values['dir'];
  if (Dir<>'up') and (Dir<>'down') then
  begin DesignerError(aRequest,aResponse,T.Db,S,400,'Invalid direction'); Exit; end;
  Cell:=T.Db.Query('SELECT id FROM page_widgets WHERE pageId='+QuotedStr(PageId)+
    ' AND row='+R[0][1]+' AND col='+R[0][2]+' ORDER BY sort,id;');
  Idx:=-1;
  for i:=0 to High(Cell) do if Cell[i][0]=Id then Idx:=i;
  Target:=Idx;
  if Dir='up' then Dec(Target) else Inc(Target);
  if (Idx>=0) and (Target>=0) and (Target<Length(Cell)) then
  begin
    Tmp:=Cell[Idx][0]; Cell[Idx][0]:=Cell[Target][0]; Cell[Target][0]:=Tmp;
    Sql:='BEGIN IMMEDIATE; ';
    for i:=0 to High(Cell) do Sql:=Sql+'UPDATE page_widgets SET sort='+IntToStr(i)+
      ',modifiedAt='+QuotedStr(NowIso)+' WHERE id='+QuotedStr(Cell[i][0])+'; ';
    if not T.Db.Exec(Sql+'COMMIT;') then
    begin T.Db.Exec('ROLLBACK;'); DesignerError(aRequest,aResponse,T.Db,S,500,'Could not sort widgets'); Exit; end;
  end;
  EditorRedirect(aResponse,PageId,S);
end;

procedure DesignerWidgetMove(aRequest: TRequest; aResponse: TResponse);
var T:TWLTenant; S:TWLSession; WidgetId,PageId,Dir:string; W:TWidget; All:TWidgetArray;
  P:TPage; i:Integer; Found:Boolean;
begin
  if not RequireDesigner(aRequest,aResponse,T,S) then Exit;
  if not VerifyActionToken(aRequest,S,'designer:/designer/widget/move') then
  begin DesignerError(aRequest,aResponse,T.Db,S,403,'Bad token'); Exit; end;
  WidgetId:=aRequest.ContentFields.Values['widgetId'];
  if not LoadWidgetPage(T.Db,WidgetId,PageId) or not LoadPageById(T.Db,PageId,P) then
  begin DesignerError(aRequest,aResponse,T.Db,S,404,'Widget not found'); Exit; end;
  All:=LoadWidgets(T.Db,PageId); Found:=False;
  for i:=0 to High(All) do if All[i].Id=WidgetId then begin W:=All[i]; Found:=True; Break; end;
  if not Found then begin DesignerError(aRequest,aResponse,T.Db,S,404,'Widget not found'); Exit; end;
  Dir:=aRequest.ContentFields.Values['dir'];
  if ResolveDir(aRequest,P.Dir,SessionLanguage(T.Db,S))='rtl' then
    if Dir='left' then Dir:='right' else if Dir='right' then Dir:='left';
  case Dir of
    'up': W.Row:=Max(0,W.Row-1);
    'down': W.Row:=Min(100-W.RowSpan,W.Row+1);
    'left': W.Col:=Max(0,W.Col-1);
    'right': W.Col:=Min(P.Cols-W.ColSpan,W.Col+1);
  else begin DesignerError(aRequest,aResponse,T.Db,S,400,'Invalid direction'); Exit; end;
  end;
  if not WidgetPlacementFits(T.Db,PageId,W) then
  begin DesignerError(aRequest,aResponse,T.Db,S,409,'Widget spans overlap'); Exit; end;
  if not T.Db.Exec('UPDATE page_widgets SET row='+IntToStr(W.Row)+',col='+IntToStr(W.Col)+
    ',modifiedAt='+QuotedStr(NowIso)+' WHERE id='+QuotedStr(WidgetId)+';') then
  begin DesignerError(aRequest,aResponse,T.Db,S,500,'Could not move widget'); Exit; end;
  EditorRedirect(aResponse,PageId,S);
end;

procedure DesignerWidgetDelete(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; S: TWLSession; WidgetId, PageId: string;
begin
  if not RequireDesigner(aRequest,aResponse,T,S) then Exit;
  if not VerifyActionToken(aRequest,S,'designer:/designer/widget/delete') then
  begin DesignerError(aRequest,aResponse,T.Db,S,403,'Bad token'); Exit; end;
  WidgetId:=aRequest.ContentFields.Values['widgetId'];
  if not LoadWidgetPage(T.Db,WidgetId,PageId) then
  begin DesignerError(aRequest,aResponse,T.Db,S,404,'Widget not found'); Exit; end;
  if not T.Db.Exec('DELETE FROM page_widgets WHERE id='+QuotedStr(WidgetId)+';') then
  begin DesignerError(aRequest,aResponse,T.Db,S,500,'Could not delete widget'); Exit; end;
  EditorRedirect(aResponse,PageId,S);
end;

function SafeWidgetTarget(const Target: string): Boolean;
var i: Integer;
begin
  if Target='' then Exit(True);
  Result:=False;
  if (Target[1]<>'/') or (Copy(Target,1,2)='//') or (Pos('\',Target)>0) then Exit;
  for i:=1 to Length(Target) do if Ord(Target[i])<32 then Exit;
  Result:=True;
end;

procedure DesignerWidgetSave(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; S: TWLSession; P: TPage; W: TWidget; F: TStrings;
  PageId,ExistingPage,Sql,Values:string;
begin
  if not RequireDesigner(aRequest,aResponse,T,S) then Exit;
  if not VerifyActionToken(aRequest,S,'designer:/designer/widget/save') then
  begin DesignerError(aRequest,aResponse,T.Db,S,403,'Bad token'); Exit; end;
  F:=aRequest.ContentFields; PageId:=F.Values['pageId']; W:=Default(TWidget);
  W.Id:=F.Values['widgetId'];
  if not LoadPageById(T.Db,PageId,P) then
  begin DesignerError(aRequest,aResponse,T.Db,S,404,'Page not found'); Exit; end;
  if W.Id<>'' then
    if not LoadWidgetPage(T.Db,W.Id,ExistingPage) or (ExistingPage<>PageId) then
    begin DesignerError(aRequest,aResponse,T.Db,S,404,'Widget not found on page'); Exit; end;
  W.Typ:=LowerCase(F.Values['type']); W.Lbl:=F.Values['label']; W.Name:=F.Values['name'];
  W.Value:=F.Values['value']; W.Target:=F.Values['target']; W.Binding:=F.Values['binding'];
  W.Row:=StrToIntDef(F.Values['row'],-1); W.Col:=StrToIntDef(F.Values['col'],-1);
  W.RowSpan:=StrToIntDef(F.Values['rowspan'],0); W.ColSpan:=StrToIntDef(F.Values['colspan'],0);
  W.Sort:=StrToFloatDef(F.Values['sort'],NaN);
  W.FgColor:=F.Values['fgColor']; W.BgColor:=F.Values['bgColor'];
  W.Required:=F.Values['required']='1'; W.OptionsJson:=F.Values['options_json'];
  if W.OptionsJson='' then W.OptionsJson:='{}';
  if not ValidWidgetModel(P,W) then
  begin DesignerError(aRequest,aResponse,T.Db,S,400,'Invalid widget fields'); Exit; end;
  if not WidgetPlacementFits(T.Db,PageId,W) then
  begin DesignerError(aRequest,aResponse,T.Db,S,409,'Widget spans overlap'); Exit; end;
  // Numeric sort uses an explicit dot independent of the process locale.
  Values:= 'type='+QuotedStr(W.Typ)+',label='+QuotedStr(W.Lbl)+',name='+QuotedStr(W.Name)+
    ',value='+QuotedStr(W.Value)+',target='+QuotedStr(W.Target)+',binding='+QuotedStr(W.Binding)+
    ',options_json='+QuotedStr(W.OptionsJson)+',fgColor='+QuotedStr(W.FgColor)+
    ',bgColor='+QuotedStr(W.BgColor)+',row='+IntToStr(W.Row)+',col='+IntToStr(W.Col)+
    ',rowspan='+IntToStr(W.RowSpan)+',colspan='+IntToStr(W.ColSpan)+
    ',sort='+StringReplace(FloatToStr(W.Sort),DefaultFormatSettings.DecimalSeparator,'.',[])+
    ',required='+IntToStr(Ord(W.Required))+',modifiedAt='+QuotedStr(NowIso);
  if W.Id='' then
  begin
    W.Id:=NewId;
    Sql:='INSERT INTO page_widgets(id,pageId,type,createdAt,modifiedAt) VALUES('+
      QuotedStr(W.Id)+','+QuotedStr(PageId)+',''label'','+QuotedStr(NowIso)+','+QuotedStr(NowIso)+');';
  end
  else Sql:='';
  if not T.Db.Exec('BEGIN IMMEDIATE; '+Sql+' UPDATE page_widgets SET '+Values+
    ' WHERE id='+QuotedStr(W.Id)+'; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;'); DesignerError(aRequest,aResponse,T.Db,S,500,'Could not save widget'); Exit; end;
  EditorRedirect(aResponse,PageId,S);
end;

// GET /designer/page/export?url=... -> downloads one .wlp (JSON) file
procedure DesignerPageExport(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; S: TWLSession; P: TPage;
begin
  if not RequireDesigner(aRequest, aResponse, T, S) then Exit;
  if not ((aRequest.QueryFields.Values['id']<>'') and
    LoadPageById(T.Db,aRequest.QueryFields.Values['id'],P)) and
    not LoadPageByUrl(T.Db,aRequest.QueryFields.Values['url'],P) then
  begin
    aResponse.Code := 404; aResponse.Content := 'No such page'; aResponse.SendContent; Exit;
  end;
  aResponse.Code := 200;
  aResponse.ContentType := 'application/json';
  aResponse.SetCustomHeader('Content-Disposition',
    'attachment; filename="page.wlp"');
  aResponse.Content := ExportPageJson(T.Db, P);
  aResponse.ContentLength := Length(aResponse.Content);
  aResponse.SendContent;
end;

// POST /designer/page/import  (multipart file 'file', or raw JSON body) -> upsert one page
procedure DesignerPageImport(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; S: TWLSession; Json, Url: string;
begin
  if not RequireDesigner(aRequest, aResponse, T, S) then Exit;
  if not VerifyActionToken(aRequest, S, 'designer:/designer/page/import') then
  begin
    aResponse.Code := 403; aResponse.Content := 'Bad token'; aResponse.SendContent; Exit;
  end;
  if aRequest.Files.Count > 0 then
    with TStringStream.Create('') do
    try
      CopyFrom(aRequest.Files[0].Stream, 0);
      Json := DataString;
    finally
      Free;
    end
  else
    Json := aRequest.Content;

  Url := ImportPageJson(T.Db, Json);
  if Url='' then begin DesignerError(aRequest,aResponse,T.Db,S,400,'Invalid page or import failed; existing pages are unchanged'); Exit; end;
  aResponse.Code := 302;
  aResponse.SetCustomHeader('Location', SessionUrl('/designer',S));
  aResponse.SendContent;
end;

// GET /designer/export -> downloads pages.zip with every page + manifest
procedure DesignerExportAll(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; S: TWLSession; Zip: TMemoryStream;
begin
  if not RequireDesigner(aRequest, aResponse, T, S) then Exit;
  Zip := TMemoryStream.Create;
  try
    ExportAllPages(T.Db, Zip);
    Zip.Position := 0;
    aResponse.Code := 200;
    aResponse.ContentType := 'application/zip';
    aResponse.SetCustomHeader('Content-Disposition',
      'attachment; filename="pages.zip"');
    aResponse.ContentStream := Zip;        // response takes ownership / streams it out
    aResponse.SendContent;
  finally
    // ContentStream is freed by the response; if not assigned, free here
    if aResponse.ContentStream <> Zip then Zip.Free;
  end;
end;

// POST /designer/import (multipart .zip 'file') -> import every .wlp in the archive
procedure DesignerImportAll(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; S: TWLSession; N: Integer;
begin
  if not RequireDesigner(aRequest, aResponse, T, S) then Exit;
  if not VerifyActionToken(aRequest, S, 'designer:/designer/import') then
  begin
    aResponse.Code := 403; aResponse.Content := 'Bad token'; aResponse.SendContent; Exit;
  end;
  N := -1;
  if aRequest.Files.Count > 0 then
    N := ImportAllPages(T.Db, aRequest.Files[0].Stream);
  if N<0 then begin DesignerError(aRequest,aResponse,T.Db,S,400,'Invalid archive or import failed; existing pages are unchanged'); Exit; end;
  Writeln('Designer: imported ', N, ' pages for ', T.Host);
  aResponse.Code := 302;
  aResponse.SetCustomHeader('Location', SessionUrl('/designer',S));
  aResponse.SendContent;
end;

initialization

finalization
  if Assigned(DataViews) then DataViews.Free;

end.
