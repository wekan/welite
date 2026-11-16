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
  // DB, the placed widget (for its options_json/binding params), and the auth context.
  TDataViewRenderer = function(Db: TWLDb; const W: TWidget; const S: TWLSession): string;

// --- dataview registry --------------------------------------------------------------------
procedure RegisterDataView(const Binding: string; Renderer: TDataViewRenderer);

function EnsureDesignerSchema(Db: TWLDb): Boolean;

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
function ResolveDir(aRequest: TRequest; const PageDirOverride: string): string;

// --- render -------------------------------------------------------------------------------
// Render a published page. Dir is 'ltr' or 'rtl'; when 'rtl' the table columns are reversed
// and cells right-aligned so the whole UI mirrors on HTML 3.2 browsers (IBrowse/NetSurf) that
// ignore the dir attribute. Params = the request query fields (search term + page number for
// any `table` components on the page; may be nil). Returns a full HTML doc.
function RenderPage(Db: TWLDb; const P: TPage; const S: TWLSession;
  Params: TStrings; const Dir: string): string;

// --- dispatcher hook ----------------------------------------------------------------------
// Try to serve `Path` from the pages table. Returns False if no enabled page matches (caller
// then falls through to compiled-in routes / 404). Enforces pages.minRole. Dir mirrors RTL.
function TryServePage(ATenant: TWLTenant; const S: TWLSession;
  const Path, Dir: string; Params: TStrings; aResponse: TResponse): Boolean;

// --- import / export ----------------------------------------------------------------------
// Serialize one page (its pages row + page_widgets) to a portable JSON document. Tenant-local
// ids are omitted; positions are logical (direction-neutral), so a page exported from an RTL
// tenant imports correctly into an LTR one. File extension: .wlp (JSON inside).
function ExportPageJson(Db: TWLDb; const P: TPage): string;
// Import one .wlp JSON: upsert by url (existing page with same url is replaced), new ids
// generated. Returns the imported page's url, or '' on failure.
function ImportPageJson(Db: TWLDb; const Json: string): string;
// Export ALL pages as a .zip (manifest.jsn + one <slug>.wlp per page) to OutStream.
procedure ExportAllPages(Db: TWLDb; OutStream: TStream);
// Import a .zip produced by ExportAllPages: each .wlp entry is imported. Returns count.
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
  DateUtils, StrUtils, Math, wladmin;

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
  Params: TStrings; const Dir: string): string;
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
    'link':      Result := '<a href="' + HtmlAttr(WithSessionId(W.Target, S.SessionId)) +
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
          Result := DV(Db, W, S)
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
    BaseQ := '?sessionId=' + S.SessionId + '&tq_' + Slug + '=' + Q + ColQ;

    // --- top bar: search + column chooser (left), pagination "Page n / m" (right) --------
    // one GET form carries the search text AND the column checkboxes (Apply submits both)
    Result :=
      '<table border="0" width="100%"><tr>' +
      '<td align="' + Align + '">' +
        '<form method="GET">' +
        '<input type="hidden" name="sessionId" value="' + HtmlAttr(S.SessionId) + '">' +
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
          Cell := '<a href="' + HtmlAttr(WithSessionId(
                    EditUrl + '?id=' + Rows[i][0] + '&field=' + VisName[j], S.SessionId)) +
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
var L: string;
begin
  L := LowerCase(Copy(Trim(Lang), 1, 2));
  // WeKan's RTL set: Arabic, Hebrew, Persian, Urdu, (and 'iw' legacy Hebrew code)
  Result := (L = 'ar') or (L = 'he') or (L = 'fa') or (L = 'ur') or (L = 'iw');
end;

function ResolveDir(aRequest: TRequest; const PageDirOverride: string): string;
var Lang: string;
begin
  // explicit per-page override wins (auto = follow the viewer's language)
  if SameText(PageDirOverride, 'rtl') then Exit('rtl');
  if SameText(PageDirOverride, 'ltr') then Exit('ltr');
  // language: ?lang= wins, else (TODO) user profile, else Accept-Language
  Lang := Trim(aRequest.QueryFields.Values['lang']);
  if Lang = '' then
    Lang := Trim(aRequest.CustomHeaders.Values['Accept-Language']);
  if LangIsRtl(Lang) then Result := 'rtl' else Result := 'ltr';
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
  Params: TStrings; const Dir: string): string;
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
          CellHtml := CellHtml + RenderWidget(Db,W[i],S,Params,PageDirection);
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
  Result := PageDir(P.Title,Body,PageDirection);
end;

// ------------------------------------------------------------------ dispatcher hook
function RoleAllows(Db: TWLDb; const MinRole: string; const S: TWLSession): Boolean;
begin
  if SameText(MinRole, 'anon') then Exit(True);
  if SameText(MinRole,'admin') then Exit(IsTenantAdmin(Db,S));
  Result := SameText(MinRole,'member') and (S.UserId<>'');
end;

function TryServePage(ATenant: TWLTenant; const S: TWLSession;
  const Path, Dir: string; Params: TStrings; aResponse: TResponse): Boolean;
var P: TPage;
begin
  Result := False;
  if not LoadPageByUrl(ATenant.Db, Path, P) then Exit;   // no enabled page at this path
  if not RoleAllows(ATenant.Db, P.MinRole, S) then Exit;             // -> caller falls through to 404
  aResponse.Code := 200;
  aResponse.ContentType := 'text/html; charset=utf-8';
  aResponse.Content := RenderPage(ATenant.Db, P, S, Params, Dir);
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

function ImportPageJson(Db: TWLDb; const Json: string): string;
var
  D: TJSONData;
  O, PgO, WO: TJSONObject;
  A: TJSONArray;
  Url, PageId: string;
  i: Integer;
begin
  Result := '';
  try
    D := GetJSON(Json);
  except
    Exit;
  end;
  try
    if not (D is TJSONObject) then Exit;
    O := TJSONObject(D);
    PgO := O.Find('page') as TJSONObject;
    if PgO = nil then Exit;
    Url := PgO.Get('url', '');
    if Url = '' then Exit;

    // upsert by url: replace any existing page of that url (cascade clears its widgets)
    Db.Exec(Format('DELETE FROM pages WHERE url=%s;', [QuotedStr(Url)]));
    PageId := NewId;
    Db.Exec(Format(
      'INSERT INTO pages(id,url,title,kind,builtinKey,cols,doctype,dir,minRole,enabled,' +
      'createdAt,modifiedAt) VALUES(%s,%s,%s,%s,%s,%d,%s,%s,%s,%d,%s,%s);',
      [ QuotedStr(PageId), QuotedStr(Url), QuotedStr(PgO.Get('title', Url)),
        QuotedStr(PgO.Get('kind', 'custom')), QuotedStr(PgO.Get('builtinKey', '')),
        PgO.Get('cols', 1), QuotedStr(PgO.Get('doctype', 'html32')),
        QuotedStr(PgO.Get('dir', 'auto')), QuotedStr(PgO.Get('minRole', 'member')),
        Ord(PgO.Get('enabled', True)), QuotedStr(NowIso), QuotedStr(NowIso) ]));

    A := O.Find('widgets') as TJSONArray;
    if A <> nil then
      for i := 0 to A.Count - 1 do
      begin
        WO := A.Objects[i];
        Db.Exec(Format(
          'INSERT INTO page_widgets(id,pageId,row,col,rowspan,colspan,sort,type,label,name,' +
          'value,target,binding,options_json,fgColor,bgColor,required,createdAt,modifiedAt) ' +
          'VALUES(%s,%s,%d,%d,%d,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,%s,%s);',
          [ QuotedStr(NewId), QuotedStr(PageId),
            WO.Get('row', 0), WO.Get('col', 0), WO.Get('rowspan', 1), WO.Get('colspan', 1),
            QuotedStr(FloatToStr(WO.Get('sort', 0.0))), QuotedStr(WO.Get('type', 'label')),
            QuotedStr(WO.Get('label', '')), QuotedStr(WO.Get('name', '')),
            QuotedStr(WO.Get('value', '')), QuotedStr(WO.Get('target', '')),
            QuotedStr(WO.Get('binding', '')), QuotedStr(WO.Get('options_json', '{}')),
            QuotedStr(WO.Get('fgColor', '')), QuotedStr(WO.Get('bgColor', '')),
            Ord(WO.Get('required', False)), QuotedStr(NowIso), QuotedStr(NowIso) ]));
      end;
    Result := Url;
  finally
    D.Free;
  end;
end;

function UrlToSlug(const Url: string): string;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(Url) do
    if Url[i] in ['A'..'Z','a'..'z','0'..'9','-','_'] then
      Result := Result + Url[i]
    else
      Result := Result + '_';
  while (Result <> '') and (Result[1] = '_') do Delete(Result, 1, 1);
  if Result = '' then Result := 'index';
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

    R := Db.Query('SELECT url FROM pages ORDER BY url;');
    for i := 0 to High(R) do
      if (Length(R[i]) > 0) and LoadPageByUrl(Db, R[i][0], P) then
      begin
        Entry := TStringStream.Create(ExportPageJson(Db, P));
        Streams.Add(Entry);
        Z.Entries.AddFileEntry(Entry, UrlToSlug(P.Url) + '.wlp');
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
  // small helper so TUnZipper can hand each entry to us as an in-memory stream
  TZipSink = class
    Db: TWLDb;
    Count: Integer;
    procedure DoCreate(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
    procedure DoDone(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
  end;

procedure TZipSink.DoCreate(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
begin
  AStream := TMemoryStream.Create;     // capture this entry into memory
end;

procedure TZipSink.DoDone(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
var S: TStringStream;
begin
  if LowerCase(ExtractFileExt(AItem.ArchiveFileName)) = '.wlp' then
  begin
    AStream.Position := 0;
    S := TStringStream.Create('');
    try
      S.CopyFrom(AStream, 0);
      if ImportPageJson(Db, S.DataString) <> '' then Inc(Count);
    finally
      S.Free;
    end;
  end;
  AStream.Free;
  AStream := nil;
end;

function ImportAllPages(Db: TWLDb; InStream: TStream): Integer;
var
  UZ: TUnZipper;
  Sink: TZipSink;
  Tmp, TmpDir: string;
  FS: TFileStream;
begin
  Result := 0;
  Sink := TZipSink.Create;
  UZ := TUnZipper.Create;
  // TUnZipper unzips from a FileName; spool the uploaded stream to a per-operation temp dir
  // (data/temp/<stamp>_<counter>_import/). Entry bytes are still captured in memory via the
  // OnCreateStream/OnDoneStream events.
  TmpDir := WLTempDir('import');
  Tmp := TmpDir + 'upload.zip';
  try
    InStream.Position := 0;
    FS := TFileStream.Create(Tmp, fmCreate);
    try
      FS.CopyFrom(InStream, 0);
    finally
      FS.Free;
    end;
    Sink.Db := Db;
    Sink.Count := 0;
    UZ.OnCreateStream := @Sink.DoCreate;
    UZ.OnDoneStream := @Sink.DoDone;
    UZ.FileName := Tmp;
    UZ.UnZipAllFiles;
    Result := Sink.Count;
  finally
    UZ.Free;
    Sink.Free;
    if FileExists(Tmp) then DeleteFile(Tmp);
    RemoveDir(TmpDir);                // drop the per-operation temp dir when done
  end;
end;

// Inline form button with action-token — the move/sort/edit/delete toolbar primitive.
function ToolButton(const S: TWLSession; const ActionPath, Caption: string;
  const HiddenName1, HiddenVal1, HiddenName2, HiddenVal2: string): string;
begin
  Result := '<form method="POST" action="' + HtmlAttr(ActionPath) +
            '" style="display:inline">' + AuthHiddenFields(S, 'designer:' + ActionPath);
  if HiddenName1 <> '' then
    Result := Result + '<input type="hidden" name="' + HtmlAttr(HiddenName1) +
              '" value="' + HtmlAttr(HiddenVal1) + '">';
  if HiddenName2 <> '' then
    Result := Result + '<input type="hidden" name="' + HtmlAttr(HiddenName2) +
              '" value="' + HtmlAttr(HiddenVal2) + '">';
  Result := Result + '<input type="submit" value="' + HtmlAttr(Caption) + '"></form>';
end;

// ------------------------------------------------------------------ editor endpoints
// Every editor/import/export endpoint uses the shared tenant-local administrator gate.
// Mutations additionally consume their action token before writing.

procedure DesignerError(aResponse: TResponse; Code: Integer; const Msg: string);
begin
  aResponse.Code := Code;
  aResponse.ContentType := 'text/html; charset=utf-8';
  aResponse.Content := Page32('Designer', '<p>'+HtmlEncode(Msg)+'</p>');
  aResponse.SendContent;
end;

function RequireDesigner(aRequest: TRequest; aResponse: TResponse;
  out T: TWLTenant; out S: TWLSession): Boolean;
begin
  Result := RequireTenantAdmin(aRequest, aResponse, T, S);
  if not Result then Exit;
  Result := EnsureDesignerSchema(T.Db);
  if not Result then DesignerError(aResponse, 503, 'Designer schema unavailable');
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
      HtmlAttr(WithSessionId('/designer/page?id='+Id,S.SessionId))+'">Edit</a> '+
      '<a href="'+HtmlAttr(WithSessionId(Rows[i][1],S.SessionId))+'">Preview</a> '+
      ToolButton(S,'/designer/page/save',Toggle,'pageId',Id,'action',Toggle)+
      ToolButton(S,'/designer/page/save','Delete','pageId',Id,'action','delete')+'</td></tr>';
  end;
  if Length(Rows)=0 then Body:=Body+'<tr><td colspan="4">No pages yet.</td></tr>';
  P := Default(TPage); P.Cols:=1; P.Doctype:='html32'; P.Dir:='auto'; P.MinRole:='member';
  Body:=Body+'</table><h2>Add page</h2><form method="POST" action="/designer/page/save">'+
    AuthHiddenFields(S,'designer:/designer/page/save')+PageFields(P)+
    '<input type="submit" name="action" value="save"></form>';
  aResponse.Content:=Page32('Designer',Body);
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
  begin DesignerError(aResponse,403,'Bad token'); Exit; end;
  F:=aRequest.ContentFields; Id:=F.Values['pageId']; Action:=F.Values['action'];
  if (Id<>'') and not LoadPageById(T.Db,Id,P) then
  begin DesignerError(aResponse,404,'Page not found'); Exit; end;
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
    if not ValidPageUrl(P.Url) or (P.Title='') or (P.Cols<1) or (P.Cols>12) or
      not ((P.Doctype='html32') or (P.Doctype='html4')) or
      not ((P.Dir='auto') or (P.Dir='ltr') or (P.Dir='rtl')) or
      not ((P.MinRole='anon') or (P.MinRole='member') or (P.MinRole='admin')) then
    begin DesignerError(aResponse,400,'Invalid page fields'); Exit; end;
    if Length(T.Db.Query('SELECT id FROM pages WHERE url='+QuotedStr(P.Url)+
      ' AND id<>'+QuotedStr(Id)+';'))>0 then
    begin DesignerError(aResponse,409,'Page URL already exists'); Exit; end;
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
      begin DesignerError(aResponse,400,'Columns would hide widgets'); Exit; end;
      Sql:='UPDATE pages SET url='+QuotedStr(P.Url)+',title='+QuotedStr(P.Title)+
        ',cols='+IntToStr(P.Cols)+',doctype='+QuotedStr(P.Doctype)+',dir='+QuotedStr(P.Dir)+
        ',minRole='+QuotedStr(P.MinRole)+',modifiedAt='+QuotedStr(NowIso)+
        ' WHERE id='+QuotedStr(Id)+';';
    end;
  end
  else begin DesignerError(aResponse,400,'Unknown page action'); Exit; end;
  if not T.Db.Exec(Sql) then
  begin DesignerError(aResponse,500,'Could not save page'); Exit; end;
  aResponse.Code:=302;
  aResponse.SetCustomHeader('Location',WithSessionId('/designer',S.SessionId));
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
    aResponse.Code := 404;
    aResponse.Content := Page32('Designer', '<p>Page not found.</p>');
    aResponse.ContentType := 'text/html; charset=utf-8'; aResponse.SendContent; Exit;
  end;

  W := LoadWidgets(T.Db, P.Id);
  MaxRow:=GridMaxRow(W);

  // editor mirrors the same way published pages do, so an RTL admin edits in a mirrored grid
  Dir := ResolveDir(aRequest, P.Dir);
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
            '<a href="'+HtmlAttr(WithSessionId('/designer/page?id='+P.Id+
              '&widgetId='+W[i].Id,S.SessionId))+'">Edit widget</a> ' +
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
  Body:=Body+'<p><a href="'+HtmlAttr(WithSessionId(P.Url,S.SessionId))+'">Preview</a></p>';

  aResponse.Content := PageDir('Designer — ' + P.Title, Body, Dir);
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
  aResponse.SetCustomHeader('Location',WithSessionId('/designer/page?id='+PageId,S.SessionId));
  aResponse.SendContent;
end;

function WidgetPlacementFits(Db:TWLDb; const PageId:string; const W:TWidget):Boolean;
var All:TWidgetArray; i:Integer;
begin
  All:=LoadWidgets(Db,PageId); Result:=False;
  for i:=0 to High(All) do if All[i].Id<>W.Id then
  begin
    if (All[i].Row=W.Row) and (All[i].Col=W.Col) then
    begin
      if (All[i].RowSpan<>W.RowSpan) or (All[i].ColSpan<>W.ColSpan) then Exit;
    end
    else if (W.Row<All[i].Row+All[i].RowSpan) and (W.Row+W.RowSpan>All[i].Row) and
      (W.Col<All[i].Col+All[i].ColSpan) and (W.Col+W.ColSpan>All[i].Col) then Exit;
  end;
  Result:=True;
end;

procedure DesignerWidgetSort(aRequest:TRequest; aResponse:TResponse);
var T:TWLTenant; S:TWLSession; R,Cell:TWLRows; Id,PageId,Dir,Sql,Tmp:string; i,Idx,Target:Integer;
begin
  if not RequireDesigner(aRequest,aResponse,T,S) then Exit;
  if not VerifyActionToken(aRequest,S,'designer:/designer/widget/sort') then
  begin DesignerError(aResponse,403,'Bad token'); Exit; end;
  Id:=aRequest.ContentFields.Values['widgetId'];
  R:=T.Db.Query('SELECT pageId,row,col FROM page_widgets WHERE id='+QuotedStr(Id)+';');
  if Length(R)=0 then begin DesignerError(aResponse,404,'Widget not found'); Exit; end;
  PageId:=R[0][0]; Dir:=aRequest.ContentFields.Values['dir'];
  if (Dir<>'up') and (Dir<>'down') then
  begin DesignerError(aResponse,400,'Invalid direction'); Exit; end;
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
    begin T.Db.Exec('ROLLBACK;'); DesignerError(aResponse,500,'Could not sort widgets'); Exit; end;
  end;
  EditorRedirect(aResponse,PageId,S);
end;

procedure DesignerWidgetMove(aRequest: TRequest; aResponse: TResponse);
var T:TWLTenant; S:TWLSession; WidgetId,PageId,Dir:string; W:TWidget; All:TWidgetArray;
  P:TPage; i:Integer; Found:Boolean;
begin
  if not RequireDesigner(aRequest,aResponse,T,S) then Exit;
  if not VerifyActionToken(aRequest,S,'designer:/designer/widget/move') then
  begin DesignerError(aResponse,403,'Bad token'); Exit; end;
  WidgetId:=aRequest.ContentFields.Values['widgetId'];
  if not LoadWidgetPage(T.Db,WidgetId,PageId) or not LoadPageById(T.Db,PageId,P) then
  begin DesignerError(aResponse,404,'Widget not found'); Exit; end;
  All:=LoadWidgets(T.Db,PageId); Found:=False;
  for i:=0 to High(All) do if All[i].Id=WidgetId then begin W:=All[i]; Found:=True; Break; end;
  if not Found then begin DesignerError(aResponse,404,'Widget not found'); Exit; end;
  Dir:=aRequest.ContentFields.Values['dir'];
  case Dir of
    'up': W.Row:=Max(0,W.Row-1);
    'down': W.Row:=Min(100-W.RowSpan,W.Row+1);
    'left': W.Col:=Max(0,W.Col-1);
    'right': W.Col:=Min(P.Cols-W.ColSpan,W.Col+1);
  else begin DesignerError(aResponse,400,'Invalid direction'); Exit; end;
  end;
  if not WidgetPlacementFits(T.Db,PageId,W) then
  begin DesignerError(aResponse,409,'Widget spans overlap'); Exit; end;
  if not T.Db.Exec('UPDATE page_widgets SET row='+IntToStr(W.Row)+',col='+IntToStr(W.Col)+
    ',modifiedAt='+QuotedStr(NowIso)+' WHERE id='+QuotedStr(WidgetId)+';') then
  begin DesignerError(aResponse,500,'Could not move widget'); Exit; end;
  EditorRedirect(aResponse,PageId,S);
end;

procedure DesignerWidgetDelete(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; S: TWLSession; WidgetId, PageId: string;
begin
  if not RequireDesigner(aRequest,aResponse,T,S) then Exit;
  if not VerifyActionToken(aRequest,S,'designer:/designer/widget/delete') then
  begin DesignerError(aResponse,403,'Bad token'); Exit; end;
  WidgetId:=aRequest.ContentFields.Values['widgetId'];
  if not LoadWidgetPage(T.Db,WidgetId,PageId) then
  begin DesignerError(aResponse,404,'Widget not found'); Exit; end;
  if not T.Db.Exec('DELETE FROM page_widgets WHERE id='+QuotedStr(WidgetId)+';') then
  begin DesignerError(aResponse,500,'Could not delete widget'); Exit; end;
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
  PageId, ExistingPage, Sql, Values: string; D: TJSONData; Valid: Boolean;
begin
  if not RequireDesigner(aRequest,aResponse,T,S) then Exit;
  if not VerifyActionToken(aRequest,S,'designer:/designer/widget/save') then
  begin DesignerError(aResponse,403,'Bad token'); Exit; end;
  F:=aRequest.ContentFields; PageId:=F.Values['pageId']; W:=Default(TWidget);
  W.Id:=F.Values['widgetId'];
  if not LoadPageById(T.Db,PageId,P) then
  begin DesignerError(aResponse,404,'Page not found'); Exit; end;
  if W.Id<>'' then
    if not LoadWidgetPage(T.Db,W.Id,ExistingPage) or (ExistingPage<>PageId) then
    begin DesignerError(aResponse,404,'Widget not found on page'); Exit; end;
  W.Typ:=LowerCase(F.Values['type']); W.Lbl:=F.Values['label']; W.Name:=F.Values['name'];
  W.Value:=F.Values['value']; W.Target:=F.Values['target']; W.Binding:=F.Values['binding'];
  W.Row:=StrToIntDef(F.Values['row'],-1); W.Col:=StrToIntDef(F.Values['col'],-1);
  W.RowSpan:=StrToIntDef(F.Values['rowspan'],0); W.ColSpan:=StrToIntDef(F.Values['colspan'],0);
  W.Sort:=StrToFloatDef(F.Values['sort'],NaN);
  W.FgColor:=F.Values['fgColor']; W.BgColor:=F.Values['bgColor'];
  W.Required:=F.Values['required']='1'; W.OptionsJson:=F.Values['options_json'];
  if W.OptionsJson='' then W.OptionsJson:='{}';
  D:=nil; Valid:=False;
  try
    try D:=GetJSON(W.OptionsJson); Valid:=D is TJSONObject; except end;
  finally D.Free; end;
  if (Pos('|'+W.Typ+'|','|heading|label|link|button|textinput|password|textarea|select|checkbox|hr|spacer|dataview|table|color|movepanel|')=0) or
    not Valid or (W.Row<0) or (W.Row>99) or (W.Col<0) or (W.Col>=P.Cols) or
    (W.RowSpan<1) or (W.RowSpan>100-W.Row) or (W.ColSpan<1) or (W.ColSpan>P.Cols-W.Col) or
    IsNan(W.Sort) or IsInfinite(W.Sort) or
    ((W.FgColor<>'') and (ResolveColor(W.FgColor)='')) or
    ((W.BgColor<>'') and (ResolveColor(W.BgColor)='')) or
    not SafeWidgetTarget(W.Target) then
  begin DesignerError(aResponse,400,'Invalid widget fields'); Exit; end;
  if not WidgetPlacementFits(T.Db,PageId,W) then
  begin DesignerError(aResponse,409,'Widget spans overlap'); Exit; end;
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
  begin T.Db.Exec('ROLLBACK;'); DesignerError(aResponse,500,'Could not save widget'); Exit; end;
  EditorRedirect(aResponse,PageId,S);
end;

// GET /designer/page/export?url=... -> downloads one .wlp (JSON) file
procedure DesignerPageExport(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; S: TWLSession; P: TPage;
begin
  if not RequireDesigner(aRequest, aResponse, T, S) then Exit;
  if not LoadPageByUrl(T.Db, aRequest.QueryFields.Values['url'], P) then
  begin
    aResponse.Code := 404; aResponse.Content := 'No such page'; aResponse.SendContent; Exit;
  end;
  aResponse.Code := 200;
  aResponse.ContentType := 'application/json';
  aResponse.SetCustomHeader('Content-Disposition',
    'attachment; filename="' + UrlToSlug(P.Url) + '.wlp"');
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
  aResponse.Code := 302;
  aResponse.SetCustomHeader('Location', WithSessionId('/designer', S.SessionId));
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
      'attachment; filename="' + T.Host + '-pages.zip"');
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
  N := 0;
  if aRequest.Files.Count > 0 then
    N := ImportAllPages(T.Db, aRequest.Files[0].Stream);
  Writeln('Designer: imported ', N, ' pages for ', T.Host);
  aResponse.Code := 302;
  aResponse.SetCustomHeader('Location', WithSessionId('/designer', S.SessionId));
  aResponse.SendContent;
end;

initialization

finalization
  if Assigned(DataViews) then DataViews.Free;

end.
