unit wlcardst;

{
  WeKan-Lite — Board Settings / Card in the HTML5 view: WeKan's
  boardCardSettingsPopup (client/components/sidebar/sidebar.jade,
  docs/Features/Cards/Card-Settings.md), as Weddy draws it (board.pug,
  card_settings.go): both sides at once, the Minicard pane and the Card pane,
  each the board's sections as checklists - a section's checkbox whether the
  whole section is shown on that side, its rows each a checkbox of the board's
  setting for that side.

  The table is WeKan's own (models/lib/cardSettingsRows.js and
  cardSettingsSections.js), from Weddy's card_settings.json
  (releases/gencardst.py writes src/tpl/cardset.inc). A row's checkbox is a
  board admin's: weddy.js writes it with /boards/update, which lets through
  exactly Card Settings' own fields (CardSettingsBoardWrite), as WeKan's allow
  rule for a board admin does.

  The field layouts are WeKan's models/lib/cardFieldOrder.js CARD_LAYOUT and
  MINICARD_LAYOUT, with its applyLayoutOrder (LayoutApply).
}

{$mode objfpc}{$H+}

interface

uses SysUtils, Classes, fpjson, jsonparser, wldb, wli18n;

// sectionOrder(stored, side): the stored ids that are known, once each, then
// the rest in the side's default order.
function CardSettingsSectionOrder(Stored: TJSONData; const Side: string): TStringArray;
// applyLayoutOrder for the side's layout: the canonical flat field order of a
// stored value - field keys, section keys, legacy or aliased keys; unknown
// keys dropped, no field lost or doubled.
function LayoutApply(const Side: string; const Stored: array of string): TStringArray;
// A board's stored field order of the side (cardFieldOrder,
// minicardFieldOrder), canonical.
function BoardFieldOrder(Db: TWLDb; const BoardId, Side: string): TStringArray;
// The minicard's pieces (labels, dates, members, assignees, comments) in the
// order of the board's Minicard pane: its sections, then its rows; none of a
// section the pane hides. Db nil: the default order.
function MinicardPieceOrder(Db: TWLDb; const BoardId: string): TStringArray;
// The opened card's dates (received, start, due, end) in the Card pane's
// row order.
function CardDateOrder(Db: TWLDb; const BoardId: string): TStringArray;
// The pop-over's template for the board, as the user sees it: Admin writes
// (a board admin), Handles the user's drag handles.
function CardSettingsPopup(Db: TWLDb; Words: TWLTranslator; const UserId, BoardId: string; Admin, Handles: Boolean): string;
// A /boards/update $set that is Card Settings' own, as it is to be written,
// in Clean (the caller frees it); False for anything else.
function CardSettingsBoardWrite(SetObj: TJSONObject; out Clean: TJSONObject): Boolean;

implementation

uses StrUtils, Math, wlhtml, wlaccess;

{$I tpl/cardset.inc}

const
  // WeKan's DRAG_SETTINGS of the Card section: kind, board field, label.
  DRAG_KINDS: array[0..3] of array[0..2] of string = (('card', 'allowsCardDragging', 'card'),
    ('checklist', 'allowsChecklistDragging', 'checklists'), ('item', 'allowsChecklistItemDragging', 'r-item'),
    ('subtask', 'allowsSubtaskDragging', 'subtasks'));
  // The Boards schema's presentParentTask, each its own translation key.
  PARENT_TASKS: array[0..4] of string = ('prefix-with-full-path', 'prefix-with-parent', 'subtext-with-full-path',
    'subtext-with-parent', 'no-parent');

type
  TLayoutSection = record Key: string; Fields: array of string; PinnedFirst: Boolean; end;
  TLayout = record Head, Tail: array of string; Sections: array of TLayoutSection; end;

var
  Table: TJSONObject;
  CardLayout, MinicardLayout: TLayout;
  // The board fields the rows' checkboxes write.
  BoardFields: TStringList;

function Sec(const Key: string; const Fields: array of string; Pinned: Boolean = False): TLayoutSection;
var i: Integer;
begin
  Result.Key := Key;
  SetLength(Result.Fields, Length(Fields));
  for i := 0 to High(Fields) do Result.Fields[i] := Fields[i];
  Result.PinnedFirst := Pinned;
end;

function Strs(const A: array of string): TStringArray;
var i: Integer;
begin
  SetLength(Result, Length(A));
  for i := 0 to High(A) do Result[i] := A[i];
end;

function Contains(const A: array of string; const S: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(A) do if A[i] = S then Exit(True);
  Result := False;
end;

procedure Push(var A: TStringArray; const S: string);
begin
  SetLength(A, Length(A) + 1);
  A[High(A)] := S;
end;

function LayoutOf(const Side: string): TLayout;
begin
  if Side = 'minicard' then Result := MinicardLayout else Result := CardLayout;
end;

function SectionKeyOf(const L: TLayout; const Field: string): string;
var i: Integer;
begin
  for i := 0 to High(L.Sections) do
    if Contains(L.Sections[i].Fields, Field) then Exit(L.Sections[i].Key);
  Result := '';
end;

// WeKan's legacy keys and aliases (cardFieldOrder.js), each a list of fields.
function LegacyOf(const Side, Key: string; out Fields: TStringArray): Boolean;
begin
  Result := True;
  if Side = 'card' then
    case Key of
      'labels': Fields := Strs(['labels', 'stickers', 'location']);
      'dates': Fields := Strs(['receivedDate', 'startDate', 'dueDate', 'endDate']);
      'members': Fields := Strs(['members', 'assignee', 'creator', 'requestedBy', 'assignedBy', 'dependencies', 'cardSortingByNumber',
        'showLists', 'spentTime', 'flowtime', 'pomodoro']);
      'customFields': Fields := Strs(['customFields', 'vote', 'poker']);
      'description': Fields := Strs(['descriptionTitle', 'descriptionText']);
    else Result := False;
    end
  else Result := False;
end;

function AliasOf(const Side, Key: string; out Fields: TStringArray): Boolean;
begin
  Result := True;
  if Side = 'card' then
    case Key of
      'dates': Fields := Strs(['receivedDate', 'startDate', 'dueDate', 'endDate']);
      'sort': Fields := Strs(['cardSortingByNumber', 'showLists', 'spentTime', 'flowtime', 'pomodoro']);
      'voteAndPoker': Fields := Strs(['vote', 'poker']);
    else Result := False;
    end
  else
    case Key of
      'dates': Fields := Strs(['receivedDate', 'startDate', 'dueDate', 'endDate', 'spentTime']);
      'badges': Fields := Strs(['scrumIssueType', 'dependencies', 'stickers', 'commentCount', 'vote', 'poker', 'attachmentCount',
        'subtasks', 'checklistCount', 'cardSortingByNumber']);
    else Result := False;
    end;
end;

function LayoutApply(const Side: string; const Stored: array of string): TStringArray;
var L: TLayout; All, Fields, Keys, InSec, More: TStringArray; i, k, j: Integer; Legacy, SomeNotField, Found: Boolean;
  First: string;
begin
  L := LayoutOf(Side);
  All := nil;
  for i := 0 to High(L.Head) do Push(All, L.Head[i]);
  for i := 0 to High(L.Sections) do for k := 0 to High(L.Sections[i].Fields) do Push(All, L.Sections[i].Fields[k]);
  for i := 0 to High(L.Tail) do Push(All, L.Tail[i]);
  Legacy := Length(Stored) > 0;
  SomeNotField := False;
  for i := 0 to High(Stored) do
  begin
    if not LegacyOf(Side, Stored[i], More) then Legacy := False;
    if not Contains(All, Stored[i]) then SomeNotField := True;
  end;
  Legacy := Legacy and SomeNotField;
  Fields := nil;
  for i := 0 to High(Stored) do
    if Legacy then
    begin
      LegacyOf(Side, Stored[i], More);
      for k := 0 to High(More) do if Contains(All, More[k]) then Push(Fields, More[k]);
    end
    else if Contains(All, Stored[i]) then Push(Fields, Stored[i])
    else
    begin
      Found := False;
      for k := 0 to High(L.Sections) do
        if L.Sections[k].Key = Stored[i] then
        begin
          for j := 0 to High(L.Sections[k].Fields) do Push(Fields, L.Sections[k].Fields[j]);
          Found := True;
        end;
      if not Found and AliasOf(Side, Stored[i], More) then
        for k := 0 to High(More) do if Contains(All, More[k]) then Push(Fields, More[k]);
    end;
  Keys := nil;
  for i := 0 to High(Fields) do
  begin
    First := SectionKeyOf(L, Fields[i]);
    if (First <> '') and not Contains(Keys, First) then Push(Keys, First);
  end;
  for i := 0 to High(L.Sections) do if not Contains(Keys, L.Sections[i].Key) then Push(Keys, L.Sections[i].Key);
  Result := nil;
  for i := 0 to High(L.Head) do Push(Result, L.Head[i]);
  for i := 0 to High(Keys) do
    for k := 0 to High(L.Sections) do
      if L.Sections[k].Key = Keys[i] then
      begin
        InSec := nil;
        for j := 0 to High(Fields) do
          if Contains(L.Sections[k].Fields, Fields[j]) and not Contains(InSec, Fields[j]) then Push(InSec, Fields[j]);
        for j := 0 to High(L.Sections[k].Fields) do
          if not Contains(InSec, L.Sections[k].Fields[j]) then Push(InSec, L.Sections[k].Fields[j]);
        if L.Sections[k].PinnedFirst then
        begin
          First := L.Sections[k].Fields[0];
          Push(Result, First);
          for j := 0 to High(InSec) do if InSec[j] <> First then Push(Result, InSec[j]);
        end
        else
          for j := 0 to High(InSec) do Push(Result, InSec[j]);
      end;
  for i := 0 to High(L.Tail) do Push(Result, L.Tail[i]);
end;

function StringsOf(Data: TJSONData): TStringArray;
var i: Integer;
begin
  Result := nil;
  if not (Data is TJSONArray) then Exit;
  for i := 0 to TJSONArray(Data).Count - 1 do
    if TJSONArray(Data).Items[i].JSONType = jtString then Push(Result, TJSONArray(Data).Strings[i]);
end;

function CardSettingsSectionOrder(Stored: TJSONData; const Side: string): TStringArray;
var Known, Ids: TStringArray; i: Integer;
begin
  Known := StringsOf(TJSONObject(Table.Find('order')).Find(Side));
  Ids := StringsOf(Stored);
  Result := nil;
  for i := 0 to High(Ids) do
    if Contains(Known, Ids[i]) and not Contains(Result, Ids[i]) then Push(Result, Ids[i]);
  for i := 0 to High(Known) do
    if not Contains(Result, Known[i]) then Push(Result, Known[i]);
end;

// The board's own document, its settings_json (where the board's fields that
// WeLite keeps no column for are), parsed; nil without one.
function BoardSettings(Db: TWLDb; const BoardId: string): TJSONObject;
var R: TWLRows; D: TJSONData;
begin
  Result := nil;
  R := Db.Query('SELECT CASE WHEN json_valid(settings_json) THEN settings_json ELSE ''{}'' END FROM boards WHERE id=' +
    QuotedStr(BoardId) + ' LIMIT 1;');
  if Length(R) <> 1 then Exit;
  try
    D := GetJSON(R[0][0]);
  except
    Exit;
  end;
  if D is TJSONObject then Result := TJSONObject(D) else D.Free;
end;

// The side's field order of an already read board document (nil: none).
function FieldOrderOf(B: TJSONObject; const Side: string): TStringArray;
begin
  if B = nil then Exit(LayoutApply(Side, []));
  if Side = 'minicard' then Result := LayoutApply(Side, StringsOf(B.Find('minicardFieldOrder')))
  else Result := LayoutApply(Side, StringsOf(B.Find('cardFieldOrder')));
end;

function BoardFieldOrder(Db: TWLDb; const BoardId, Side: string): TStringArray;
var B: TJSONObject;
begin
  B := BoardSettings(Db, BoardId);
  try
    if B = nil then Exit(LayoutApply(Side, []));
    if Side = 'minicard' then Result := LayoutApply(Side, StringsOf(B.Find('minicardFieldOrder')))
    else Result := LayoutApply(Side, StringsOf(B.Find('cardFieldOrder')));
  finally
    B.Free;
  end;
end;

function SideOf(Row: TJSONObject; const Side: string): TJSONObject;
var D: TJSONData;
begin
  D := Row.Find(Side);
  if D is TJSONObject then Result := TJSONObject(D) else Result := nil;
end;

// rowsForSide (cardSettingsRows.js): the rows of one side in order - a row
// with a place in the order at its place, a row that modifies another (after)
// under it, anything left last. The list holds the table's own objects.
function RowsForSide(const Side: string; const Order: array of string): TList;
var Rows: TJSONArray; With_: TList; i, k: Integer;
  procedure Attach(const Anchor: string);
  var n, At, j: Integer; R: TJSONObject;
  begin
    for n := 0 to With_.Count - 1 do
    begin
      R := TJSONObject(With_[n]);
      if (SideOf(R, Side).Get('after', '') <> Anchor) or (Result.IndexOf(R) >= 0) then Continue;
      At := -1;
      for j := 0 to Result.Count - 1 do if TJSONObject(Result[j]).Get('key', '') = Anchor then At := j;
      if At < 0 then Result.Add(R) else Result.Insert(At + 1, R);
      Attach(R.Get('key', ''));
    end;
  end;
begin
  Rows := TJSONArray(Table.Find('rows'));
  With_ := TList.Create;
  Result := TList.Create;
  try
    for i := 0 to Rows.Count - 1 do
      if SideOf(TJSONObject(Rows.Items[i]), Side) <> nil then With_.Add(Rows.Items[i]);
    for i := 0 to High(Order) do
      for k := 0 to With_.Count - 1 do
        if (TJSONObject(With_[k]).Get('key', '') = Order[i]) and (Result.IndexOf(With_[k]) < 0) then Result.Add(With_[k]);
    for i := 0 to High(Order) do Attach(Order[i]);
    for k := 0 to With_.Count - 1 do if Result.IndexOf(With_[k]) < 0 then Result.Add(With_[k]);
  finally
    With_.Free;
  end;
end;

function E(const S: string): string;
begin
  Result := HtmlEncode(S);
end;

function Flag(B: TJSONObject; const Field: string; Default: Boolean): Boolean;
var V: TJSONData;
begin
  Result := Default;
  if B = nil then Exit;
  V := B.Find(Field);
  if (V <> nil) and (V.JSONType = jtBoolean) then Result := V.AsBoolean;
end;

function Box(Checked: Boolean): string;
begin
  Result := '<div class="materialCheckBox' + IfThen(Checked, ' is-checked', '') + '"></div>';
end;

function IconsHtml(const Icons: array of string): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(Icons) do Result := Result + '<i class="fa ' + E(Icons[i]) + '" aria-hidden="true"></i>';
  if Result <> '' then Result := Result + ' ';
end;

// A section of a pane (WeKan's cardSettingsInlineSection): its line - caret,
// checkbox, title (dragged, moved by the Up and Down keys), count - then its
// rows. A section of one row on this side is that row's own line (its
// checkbox the row's flag); Custom Fields' one row is its own flag, the
// board's fields under it, each with this side's checkbox and its form.
function SectionHtml(const BoardId, Side, Id, Icon, Title, Lines: string; Shown, Writable, Collapsed: Boolean; LineCount, CheckedCount: Integer;
  const FlagKey, FlagKind, FlagField, FlagScrum: string; FlagChecked: Boolean; const Fields: TWLRows; Words: TWLTranslator): string;
var Single, HasFlag, On_: Boolean; i: Integer; Caret, Head, Handle, Burger: string;
  function T(const Key: string): string;
  begin
    Result := Words.Text(Key, Key);
  end;
  function Flagged(const Cls, FlagName: string; Checked: Boolean; const Key: string): string;
  begin
    Result := '<a class="flex ' + Cls + IfThen(Checked, ' is-checked', '') + '" href="#" data-flag="' + FlagName + '">' + Box(Checked) +
      '<span>' + E(T(Key)) + '</span></a>';
  end;
begin
  // WeKan's section hamburger: Card's holds what is not a field, Subtasks'
  // the board's Subtasks Settings; it opens under the line.
  Burger := '<a class="card-settings-inline-menu js-open-card-settings-section-menu" href="#" role="button" aria-expanded="false" ' +
    'data-panel="section-' + E(Id) + '" title="' + E(T('actions')) + '" aria-label="' + E(T('actions')) + '"><i class="fa fa-bars" ' +
    'aria-hidden="true"></i></a>';
  HasFlag := LineCount = 1;
  Single := HasFlag and (Id <> 'customFields');
  Caret := '<a class="card-settings-inline-collapse js-toggle-card-settings-section" href="#" role="button" aria-expanded="' +
    IfThen(Collapsed, 'false', 'true') + '" title="' + E(T('collapse')) + '" aria-label="' + E(T('collapse')) + '"><i class="fa ' +
    IfThen(Collapsed, 'fa-caret-right', 'fa-caret-down') + '" aria-hidden="true"></i></a>';
  Handle := '<h4 class="card-settings-inline-section-title' + IfThen(Writable, ' js-card-settings-section-handle', '') + '"' +
    IfThen(Writable, ' tabindex="0"', '') + '><i class="fa ' + E(Icon) + '" aria-hidden="true"></i> ' + E(Title) + '</h4>';
  Result := '<div class="card-settings-inline-section js-card-settings-section' + IfThen(not Shown, ' is-section-hidden', '') +
    IfThen(Single, ' is-single', '') + IfThen(Collapsed, ' is-collapsed', '') + '" data-section="' + E(Id) + '">';
  if HasFlag then
  begin
    On_ := FlagChecked and Shown;
    Head := '<div class="card-settings-inline-section-head js-card-field-order-row" data-key="' + E(FlagKey) + '" data-side="' + Side +
      '" data-kind="' + E(FlagKind) + '" data-field="' + E(FlagField) + '" data-scrum="' + E(FlagScrum) + '" data-flag="' +
      IfThen(FlagChecked, 'true', '') + '" data-shown="' + IfThen(Shown, 'true', '') + '">' + IfThen(Single, '', Caret) +
      '<span class="card-settings-side card-settings-section-side"><a class="flex card-field-order-toggle card-settings-section-toggle ' +
      IfThen(Writable, 'js-card-settings-single-toggle', 'is-disabled') + IfThen(On_, ' is-checked', '') + '" href="#" role="checkbox" ' +
      'aria-checked="' + IfThen(On_, 'true', 'false') + '" aria-label="' + E(Title) + '">' + Box(On_) + '</a></span>' + Handle +
      IfThen(Single, '', '<span class="card-settings-inline-section-count">' + IntToStr(CheckedCount) + '/' + IntToStr(LineCount) + '</span>') +
      IfThen(Writable and (Id = 'subtasks'), Burger, '') + '</div>';
  end
  else
    Head := '<div class="card-settings-inline-section-head">' + Caret +
      '<span class="card-settings-side card-settings-section-side"><a class="flex card-field-order-toggle card-settings-section-toggle ' +
      IfThen(Writable, 'js-card-settings-section-shown', 'is-disabled') + IfThen(Shown, ' is-checked', '') + '" href="#" role="checkbox" ' +
      'aria-checked="' + IfThen(Shown, 'true', 'false') + '" aria-label="' + E(Title) + '">' + Box(Shown) + '</a></span>' + Handle +
      '<span class="card-settings-inline-section-count">' + IntToStr(CheckedCount) + '/' + IntToStr(LineCount) + '</span>' +
      IfThen(Writable and ((Id = 'card') or (Id = 'subtasks')), Burger, '') + '</div>';
  Result := Result + Head;
  if not HasFlag and (Lines <> '') then Result := Result + '<div class="card-settings-inline-items">' + Lines + '</div>';
  if Id = 'customFields' then
  begin
    Result := Result + '<div class="card-settings-custom-fields-list js-card-settings-custom-fields">';
    for i := 0 to High(Fields) do
    begin
      if Side = 'minicard' then On_ := Fields[i][2] = '1' else On_ := Fields[i][4] = '1';
      Result := Result + '<div class="card-settings-line card-settings-inline-item card-settings-custom-field js-card-settings-custom-field" ' +
        'data-id="' + E(Fields[i][0]) + '" data-side="' + Side + '"><span class="card-settings-side"><a class="flex card-field-order-toggle ' +
        IfThen(Writable, 'js-card-settings-custom-field-toggle', 'is-disabled') + IfThen(On_, ' is-checked', '') + '" href="#" ' +
        'role="checkbox" aria-checked="' + IfThen(On_, 'true', 'false') + '" aria-label="' + E(Fields[i][1]) + '">' + Box(On_) +
        '</a></span><span class="card-settings-line-label' + IfThen(Writable, ' js-card-settings-custom-field-handle', '') + '"' +
        IfThen(Writable, ' tabindex="0"', '') + '>' + E(Fields[i][1]) + '</span>';
      if Writable then
        Result := Result + '<a class="card-settings-inline-menu js-card-settings-edit-custom-field" href="#" role="button" aria-expanded="false" ' +
          'data-panel="field-' + E(Fields[i][0]) + '" title="' + E(T('edit')) + '" aria-label="' + E(T('edit')) + '"><i class="fa fa-bars" ' +
          'aria-hidden="true"></i></a><template class="js-card-settings-panel-tpl" data-panel="field-' + E(Fields[i][0]) + '">' +
          '<form class="card-settings-panel-form js-card-settings-field-form" data-id="' + E(Fields[i][0]) + '"><label>' + E(T('name')) +
          '<input class="js-field-name" type="text" name="name" value="' + E(Fields[i][1]) + '" required maxlength="200" autocomplete="off">' +
          '</label>' + Flagged('js-field-show-on-card', 'showOnCard', Fields[i][2] = '1', 'show-field-on-card') +
          Flagged('js-field-automatically-on-card', 'automaticallyOnCard', Fields[i][3] = '1', 'automatically-field-on-card') +
          Flagged('js-field-always-on-card', 'alwaysOnCard', Fields[i][4] = '1', 'always-field-on-card') +
          Flagged('js-field-show-label-on-minicard', 'showLabelOnMiniCard', Fields[i][5] = '1', 'showLabel-field-on-card') +
          '<button class="primary" type="submit">' + E(T('save')) + '</button></form></template>';
      Result := Result + '</div>';
    end;
    Result := Result + '</div>';
    // The +: a new field's form under it (createCustomFieldPopup).
    if Writable then
      Result := Result + '<a class="card-settings-add-custom-field js-card-settings-add-custom-field" href="#" role="button" ' +
        'aria-expanded="false" data-panel="field-new" title="' + E(T('createCustomField')) + '" aria-label="' + E(T('createCustomField')) +
        '"><i class="fa fa-plus" aria-hidden="true"></i></a><template class="js-card-settings-panel-tpl" data-panel="field-new">' +
        '<form class="card-settings-panel-form js-card-settings-field-create" method="post" action="/b/' + E(BoardId) + '/custom-fields">' +
        '<label>' + E(T('name')) + '<input class="js-field-name" type="text" name="name" required maxlength="200" autocomplete="off"></label>' +
        '<label>' + E(T('type')) + '<select class="js-field-type" name="type"><option value="text">' + E(T('custom-field-text')) +
        '</option><option value="number">' + E(T('custom-field-number')) + '</option><option value="date">' + E(T('custom-field-date')) +
        '</option><option value="checkbox">' + E(T('custom-field-checkbox')) + '</option><option value="currency">' +
        E(T('custom-field-currency')) + '</option><option value="dropdown">' + E(T('custom-field-dropdown')) + '</option></select></label>' +
        '<button class="primary" type="submit">' + E(T('create')) + '</button></form></template>';
  end;
  Result := Result + '</div>';
end;

// Subtasks Settings' deposit (boardSubtaskSettingsBody): the board new
// subtasks go to - one the user may write - and its list, or none.
function DepositSelects(Db: TWLDb; Words: TWLTranslator; const UserId, BoardId: string): string;
var R, Boards, Lists: TWLRows; Board, List: string; i: Integer;
  function T(const Key: string): string;
  begin
    Result := Words.Text(Key, Key);
  end;
begin
  R := Db.Query('SELECT COALESCE(subtasksDefaultBoardId,''''),COALESCE(subtasksDefaultListId,'''') FROM boards WHERE id=' + QuotedStr(BoardId) + ';');
  Board := ''; List := '';
  if Length(R) = 1 then begin Board := R[0][0]; List := R[0][1]; end;
  if Board = 'null' then Board := '';
  Boards := Db.Query('SELECT b.id,b.title FROM boards b JOIN board_members m ON m.boardId=b.id WHERE m.userId=' + QuotedStr(UserId) +
    ' AND m.isActive=1 AND b.archived=0 ORDER BY b.title,b.id;');
  Result := '<label>' + E(T('deposit-subtasks-board')) + '<select class="js-field-deposit-board">';
  for i := 0 to High(Boards) do
    if BoardCanWrite(Db, UserId, Boards[i][0]) then
      Result := Result + '<option value="' + E(Boards[i][0]) + '"' + IfThen(Boards[i][0] = Board, ' selected', '') + '>' + E(Boards[i][1]) + '</option>';
  Result := Result + '<option value="null"' + IfThen(Board = '', ' selected', '') + '>' + E(T('custom-field-dropdown-none')) + '</option></select></label>';
  if Board = '' then Lists := nil
  else Lists := Db.Query('SELECT id,title FROM lists WHERE boardId=' + QuotedStr(Board) + ' AND archived=0 AND deletedAt IS NULL ORDER BY sort,id;');
  Result := Result + '<label>' + E(T('deposit-subtasks-list')) + '<select class="js-field-deposit-list">';
  for i := 0 to High(Lists) do
    Result := Result + '<option value="' + E(Lists[i][0]) + '"' + IfThen(Lists[i][0] = List, ' selected', '') + '>' + E(Lists[i][1]) + '</option>';
  Result := Result + '<option value="null"' + IfThen((List = '') or (List = 'null'), ' selected', '') + '>' + E(T('custom-field-dropdown-none')) +
    '</option></select></label>';
end;

function CardSettingsPopup(Db: TWLDb; Words: TWLTranslator; const UserId, BoardId: string; Admin, Handles: Boolean): string;
var B, Profile, Folds, Visibility: TJSONObject; Sections: TJSONArray; Hidden, Order, Keys, Labels, Icons: TStringArray;
  Rows: TList; Side, Html, Lines, Title, Line, FoldKey, Label_, Split, Override: string; s, r, i, Checked, Count: Integer;
  Section, Row, SideSpec: TJSONObject; Shown, On_, Positioned, Writable, Collapsed, Personal, Overridden: Boolean;
  U: TWLRows; D: TJSONData; Fields: TWLRows; FlagLine, FlagKind, FlagField, FlagScrum, FlagKey: string; FlagChecked: Boolean; Dot: TFormatSettings; Revision, Panels, Parent: string; Lb: Integer; PR: TWLRows;
  function T(const Key: string): string;
  begin
    Result := Words.Text(Key, Key);
  end;
  function Obj(Parent: TJSONObject; const Key: string): TJSONObject;
  var V: TJSONData;
  begin
    Result := nil;
    if Parent = nil then Exit;
    V := Parent.Find(Key);
    if V is TJSONObject then Result := TJSONObject(V);
  end;
begin
  Dot := DefaultFormatSettings;
  Dot.DecimalSeparator := '.';
  B := BoardSettings(Db, BoardId);
  Profile := nil;
  if UserId <> '' then
  begin
    U := Db.Query('SELECT CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END FROM users WHERE id=' +
      QuotedStr(UserId) + ' LIMIT 1;');
    if Length(U) = 1 then
      try
        D := GetJSON(U[0][0]);
        if D is TJSONObject then Profile := TJSONObject(D) else D.Free;
      except
        Profile := nil;
      end;
  end;
  Fields := Db.Query('SELECT f.id,f.name,COALESCE(f.showOnCard,0),COALESCE(f.automaticallyOnCard,0),COALESCE(f.alwaysOnCard,0),' +
    'COALESCE(f.showLabelOnMiniCard,0) FROM custom_fields f JOIN custom_field_boards b ON b.customFieldId=f.id WHERE b.boardId=' +
    QuotedStr(BoardId) + IfThen(Admin, '', ' AND f.adminOnly=0') + ' ORDER BY f.sort IS NOT NULL,f.sort,f.createdAt,f.id;');
  try
    Folds := Obj(Obj(Profile, 'collapsedCardSections'), BoardId);
    Visibility := Obj(Obj(B, 'scrum'), 'visibility');
    Split := '0.5';
    if (Profile <> nil) and (Profile.Find('cardSettingsSplit') <> nil) and (Profile.Find('cardSettingsSplit').JSONType = jtNumber) then
      Split := FloatToStr(EnsureRange(Profile.Find('cardSettingsSplit').AsFloat, 0, 1), Dot);
    Sections := TJSONArray(Table.Find('sections'));
    // The board's, for the Scrum rows' scrum.configure.
    Revision := '0';
    if (B <> nil) and (B.Find('scrumRevision') <> nil) and (B.Find('scrumRevision').JSONType = jtNumber) then
      Revision := IntToStr(Round(B.Find('scrumRevision').AsFloat));
    Html := '';
    for s := 0 to 1 do
    begin
      if s = 0 then Side := 'minicard' else Side := 'card';
      if Side = 'card' then
        Html := Html + '<div class="card-settings-splitter js-card-settings-splitter" role="separator" aria-orientation="vertical" ' +
          'tabindex="0" aria-valuemin="0" aria-valuemax="100" title="' + E(T('card-drawing-resize')) + '" aria-label="' +
          E(T('card-drawing-resize')) + '"></div>';
      Html := Html + '<div class="card-settings-inline card-settings-pane js-card-settings-inline js-card-settings-pane card-settings-pane-' +
        Side + '" data-side="' + Side + '" data-board="' + E(BoardId) + '" data-revision="' + Revision + '"><div class="card-settings-pane-head">' +
        '<a class="card-settings-pane-collapse js-toggle-card-settings-pane" href="#" role="button" aria-expanded="true" title="' +
        E(T('collapse')) + '" aria-label="' + E(T('collapse')) + '"><i class="fa fa-caret-down" aria-hidden="true"></i></a>' +
        '<h3 class="card-settings-pane-title">' + E(T('show-on-' + Side)) + '</h3></div>' +
        '<div class="card-settings-pane-body js-card-settings-pane-body"><div class="card-settings-inline-sections ' +
        'js-card-settings-sections-sortable" data-side="' + Side + '">';
      Hidden := nil;
      if (B <> nil) and (Side = 'minicard') then Hidden := StringsOf(B.Find('cardSettingsHiddenOnMinicard'))
      else if B <> nil then Hidden := StringsOf(B.Find('cardSettingsHiddenOnCard'));
      Rows := RowsForSide(Side, FieldOrderOf(B, Side));
      try
        if B <> nil then
        begin
          if Side = 'minicard' then Order := CardSettingsSectionOrder(B.Find('minicardSettingsSectionOrder'), Side)
          else Order := CardSettingsSectionOrder(B.Find('cardSettingsSectionOrder'), Side);
        end
        else Order := CardSettingsSectionOrder(nil, Side);
        for i := 0 to High(Order) do
        begin
          Section := nil;
          for r := 0 to Sections.Count - 1 do
            if TJSONObject(Sections.Items[r]).Get('id', '') = Order[i] then Section := TJSONObject(Sections.Items[r]);
          if Section = nil then Continue;
          Keys := StringsOf(Section.Find('keys'));
          Shown := not Contains(Hidden, Order[i]);
          Lines := '';
          Count := 0; Checked := 0;
          FlagLine := ''; FlagChecked := False; FlagKind := ''; FlagField := ''; FlagScrum := ''; FlagKey := '';
          for r := 0 to Rows.Count - 1 do
          begin
            Row := TJSONObject(Rows[r]);
            if not Contains(Keys, Row.Get('key', '')) then Continue;
            SideSpec := SideOf(Row, Side);
            if (SideSpec = nil) or SideSpec.Get('needsCard', False) then Continue;
            Labels := StringsOf(Row.Find('label'));
            Label_ := '';
            for Lb := 0 to High(Labels) do
            begin
              if Lb > 0 then Label_ := Label_ + Row.Get('labelSeparator', ' ');
              Label_ := Label_ + T(Labels[Lb]);
            end;
            Writable := Admin;
            Personal := False; Overridden := False;
            case SideSpec.Get('kind', '') of
              'board': On_ := Flag(B, SideSpec.Get('field', ''), SideSpec.Get('default', False));
              'scrum': On_ := Flag(Visibility, SideSpec.Get('scrum', ''), False);
              'personal':
                begin
                  Personal := True;
                  Writable := UserId <> '';
                  if Side = 'minicard' then Override := 'showLabelTextOverride' else Override := 'cardLabelTextOverride';
                  Overridden := (Profile <> nil) and (Profile.Find(Override) <> nil) and (Profile.Find(Override).JSONType = jtBoolean);
                  if Overridden then On_ := Profile.Find(Override).AsBoolean
                  else if Side = 'minicard' then On_ := Flag(B, 'showLabelText', True)
                  else On_ := Flag(B, 'allowsLabelTextOnCard', True);
                end;
            else On_ := False;
            end;
            if On_ then Inc(Count);
            Positioned := (SideSpec.Get('after', '') = '') and (SectionKeyOf(LayoutOf(Side), Row.Get('key', '')) <> '');
            Icons := StringsOf(Row.Find('icons'));
            Line := '<div class="card-settings-line card-settings-inline-item js-card-field-order-row' + IfThen(Positioned, ' is-positioned', '') +
              '" data-key="' + E(Row.Get('key', '')) + '" data-side="' + Side + '" data-kind="' + E(SideSpec.Get('kind', '')) +
              '" data-field="' + E(SideSpec.Get('field', '')) + '" data-scrum="' + E(SideSpec.Get('scrum', '')) + '">' +
              '<span class="card-settings-side card-settings-side-' + Side + '"><a class="flex card-field-order-toggle ' +
              IfThen(Writable, 'js-card-settings-toggle', 'is-disabled') + IfThen(On_, ' is-checked', '') + '" href="#" role="checkbox" ' +
              'aria-checked="' + IfThen(On_, 'true', 'false') + '" aria-label="' + E(Label_) + '">' + Box(On_) + '</a></span>' +
              '<span class="card-settings-line-label' + IfThen(Writable and Positioned and not Handles,
                ' js-card-field-order-handle card-field-order-drag-label', '') + '"' +
              IfThen(Writable and Positioned and not Handles, ' tabindex="0"', '') + '>';
            if Writable and Positioned and Handles then
              Line := Line + '<a class="flex card-field-order-move card-field-order-handle js-card-field-order-handle" href="#" ' +
                'draggable="false" role="button" tabindex="0" title="' + E(T('drag-to-reorder')) + '" aria-label="' +
                E(T('drag-to-reorder')) + '"><i class="fa fa-arrows"></i></a>';
            Line := Line + IconsHtml(Icons) + E(Label_);
            if Personal then
            begin
              if Overridden then
                Line := Line + ' (<a href="#" class="' + IfThen(Side = 'minicard', 'js-reset-minicard-label-text-override',
                  'js-reset-card-label-text-override') + '" title="' + E(T('label-text-use-board-default')) + '">' +
                  E(T('label-text-overridden')) + '</a>)'
              else Line := Line + ' (' + E(T('label-text-follows-board')) + ')';
            end;
            Line := Line + '</span></div>';
            Lines := Lines + Line;
            Inc(Checked);
            if FlagKey = '' then
            begin
              FlagKey := Row.Get('key', ''); FlagKind := SideSpec.Get('kind', ''); FlagField := SideSpec.Get('field', '');
              FlagScrum := SideSpec.Get('scrum', ''); FlagChecked := On_;
              FlagLine := Label_;
            end;
          end;
          // Checked counted the lines here.
          FoldKey := 'card-settings-' + IfThen(Side = 'minicard', 'minicard-', '') + Order[i];
          Collapsed := Flag(Folds, FoldKey, False);
          if (Checked = 0) and (Order[i] <> 'card') and (Order[i] <> 'customFields') then Continue;
          Title := T(Section.Get('labelKey', ''));
          Html := Html + SectionHtml(BoardId, Side, Order[i], Section.Get('icon', ''), Title, Lines, Shown, Admin, Collapsed, Checked,
            Count, FlagKey, FlagKind, FlagField, FlagScrum, FlagChecked, Fields, Words);
        end;
      finally
        Rows.Free;
      end;
      Html := Html + '</div></div></div>';
    end;
    // What the hamburgers open (WeKan's cardSettingsInlinePanel), made under
    // the section's line when opened: Card's Ask for move reason, Subtasks'
    // Subtasks Settings - a board admin's.
    Panels := '';
    if Admin then
    begin
      On_ := Flag(B, 'askForMoveReason', False);
      Panels := '<template class="js-card-settings-panel-tpl" data-panel="section-card"><div class="card-settings-section-menu">' +
        '<div class="check-div card-settings-board-option card-settings-ask-move-reason"><a class="flex card-ask-move-reason js-ask-move-reason" ' +
        'href="#" role="checkbox" aria-checked="' + IfThen(On_, 'true', 'false') + '">' + Box(On_) + '<span>' + E(T('ask-move-reason')) +
        '</span></a></div>' +
        // WeKan's boardDragSettings of the Card section (models/lib/boardDragging.js):
        // whether each kind may be dragged on this board, on until turned off.
        '<table class="board-drag-settings" data-board="' + E(BoardId) + '"><thead><tr><th>' + E(T('name')) + '</th><th>' +
        E(T('draggable')) + '</th></tr></thead><tbody>';
      for Lb := 0 to High(DRAG_KINDS) do
      begin
        On_ := Flag(B, DRAG_KINDS[Lb][1], True);
        Panels := Panels + '<tr><td>' + E(T(DRAG_KINDS[Lb][2])) + '</td><td><input class="js-board-drag-setting" type="checkbox" data-kind="' +
          DRAG_KINDS[Lb][0] + '"' + IfThen(On_, ' checked', '') + ' aria-label="' + E(T(DRAG_KINDS[Lb][2])) + '"></td></tr>';
      end;
      Panels := Panels + '</tbody></table></div></template>';
      PR := Db.Query('SELECT COALESCE(presentParentTask,''no-parent'') FROM boards WHERE id=' + QuotedStr(BoardId) + ';');
      if Length(PR) = 1 then Parent := PR[0][0] else Parent := 'no-parent';
      Panels := Panels + '<template class="js-card-settings-panel-tpl" data-panel="section-subtasks"><div class="card-settings-section-menu">' +
        '<div class="card-settings-section-action" data-action="subtaskSettings"><h4 class="card-settings-section-action-title">' +
        '<i class="fa fa-cog" aria-hidden="true"></i> ' + E(T('subtask-settings')) + '</h4><form class="board-subtask-settings"><h3>' +
        E(T('show-parent-in-minicard')) + '</h3>';
      for Lb := 0 to 4 do
        Panels := Panels + '<a class="flex js-field-show-parent-in-minicard' + IfThen(PARENT_TASKS[Lb] = Parent, ' is-checked', '') +
          '" href="#" id="' + PARENT_TASKS[Lb] + '" data-value="' + PARENT_TASKS[Lb] + '"><i class="fa ' +
          IfThen(PARENT_TASKS[Lb] = Parent, 'fa-check', 'fa-square-o') + '"></i><span>' + E(T(PARENT_TASKS[Lb])) + '</span></a>';
      On_ := Flag(B, 'allowsSubtasks', True);
      Panels := Panels + '<hr><div class="check-div"><a class="flex js-field-has-subtasks' + IfThen(On_, ' is-checked', '') +
        '" href="#"><i class="fa ' + IfThen(On_, 'fa-check', 'fa-square-o') + '"></i><span>' + E(T('show-subtasks-field')) +
        '</span></a></div>' + DepositSelects(Db, Words, UserId, BoardId) + '</form></div></div></template>';
    end;
    Result := '<template class="js-pop-over-template" data-pop="board-card-settings" data-popup="boardCardSettingsPopup" data-title="' +
      E(T('card-settings')) + '"><div class="header"><span class="header-title">' + E(T('card-settings')) +
      '</span><a class="close-btn js-close-pop-over" href="#" aria-label="' + E(T('close')) + '">&times;</a></div>' + Panels +
      '<template class="js-card-settings-labels" data-maximize="' + E(T('maximize-card')) + '" data-minimize="' + E(T('minimize-card')) +
      '"></template><button class="js-date-popup-resize" type="button" title="' + E(T('card-drawing-resize')) + '" aria-label="' +
      E(T('card-drawing-resize')) + '"></button><div class="content card-settings-panes-container js-card-settings-panes-container">' +
      '<div class="card-settings-panes js-card-settings-panes" style="--card-settings-split: ' + Split + '">' + Html +
      '</div></div></template>';
  finally
    B.Free;
    Profile.Free;
  end;
end;

function SafeId(const Id: string): Boolean;
var i: Integer;
begin
  Result := (Id <> '') and (Length(Id) <= 64);
  for i := 1 to Length(Id) do if not (Id[i] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then Exit(False);
end;

function CardSettingsBoardWrite(SetObj: TJSONObject; out Clean: TJSONObject): Boolean;
var i, k: Integer; Path: string; V: TJSONData; Ids, Known, Ordered: TStringArray; List: TJSONArray; Side: string;
  function StringList(Data: TJSONData; out Items: TStringArray): Boolean;
  var n: Integer;
  begin
    Items := nil;
    Result := (Data is TJSONArray) and (TJSONArray(Data).Count <= 200);
    if not Result then Exit;
    for n := 0 to TJSONArray(Data).Count - 1 do
    begin
      if TJSONArray(Data).Items[n].JSONType <> jtString then Exit(False);
      Push(Items, TJSONArray(Data).Strings[n]);
    end;
  end;
  function Arr(const A: array of string): TJSONArray;
  var n: Integer;
  begin
    Result := TJSONArray.Create;
    for n := 0 to High(A) do Result.Add(A[n]);
  end;
begin
  Clean := TJSONObject.Create;
  Result := False;
  Known := nil;
  for i := 0 to TJSONArray(Table.Find('sections')).Count - 1 do
    Push(Known, TJSONObject(TJSONArray(Table.Find('sections')).Items[i]).Get('id', ''));
  for i := 0 to SetObj.Count - 1 do
  begin
    Path := SetObj.Names[i];
    V := SetObj.Items[i];
    if BoardFields.IndexOf(Path) >= 0 then
    begin
      if V.JSONType <> jtBoolean then Exit;
      Clean.Add(Path, V.AsBoolean);
    end
    else if (Path = 'cardSettingsHiddenOnCard') or (Path = 'cardSettingsHiddenOnMinicard') then
    begin
      if not StringList(V, Ids) then Exit;
      for k := 0 to High(Ids) do if not Contains(Known, Ids[k]) then Exit;
      // In the sections' own order, as WeKan's normaliseHiddenSections.
      Ordered := nil;
      for k := 0 to High(Known) do if Contains(Ids, Known[k]) then Push(Ordered, Known[k]);
      Clean.Add(Path, Arr(Ordered));
    end
    else if (Path = 'cardSettingsSectionOrder') or (Path = 'minicardSettingsSectionOrder') then
    begin
      if not StringList(V, Ids) then Exit;
      if Path = 'minicardSettingsSectionOrder' then Side := 'minicard' else Side := 'card';
      List := Arr(Ids);
      try
        Ordered := CardSettingsSectionOrder(List, Side);
      finally
        List.Free;
      end;
      Clean.Add(Path, Arr(Ordered));
    end
    else if Path = 'askForMoveReason' then
    begin
      if V.JSONType <> jtBoolean then Exit;
      Clean.Add(Path, V.AsBoolean);
    end
    else if Path = 'presentParentTask' then
    begin
      // The Boards schema's values.
      if (V.JSONType <> jtString) or not Contains(['prefix-with-full-path', 'prefix-with-parent', 'subtext-with-full-path',
        'subtext-with-parent', 'no-parent'], V.AsString) then Exit;
      Clean.Add(Path, V.AsString);
    end
    else if (Path = 'subtasksDefaultBoardId') or (Path = 'subtasksDefaultListId') or (Path = 'subtasksDefaultSwimlaneId') then
    begin
      // An id, or none (WeKan's "null" choice); whether the caller may name
      // it is the caller's check (SubtaskDepositBleed).
      if V.JSONType = jtNull then Clean.Add(Path, TJSONNull.Create)
      else if (V.JSONType = jtString) and SafeId(V.AsString) then Clean.Add(Path, V.AsString)
      else Exit;
    end
    else if (Path = 'cardFieldOrder') or (Path = 'minicardFieldOrder') then
    begin
      if not StringList(V, Ids) then Exit;
      if Path = 'minicardFieldOrder' then Side := 'minicard' else Side := 'card';
      Clean.Add(Path, Arr(LayoutApply(Side, Ids)));
    end
    else Exit;
  end;
  Result := Clean.Count > 0;
end;

function PieceOf(const Field: string): string;
begin
  case Field of
    'labels': Result := 'labels';
    'receivedDate', 'startDate', 'dueDate', 'endDate': Result := 'dates';
    'members': Result := 'members';
    'assignee': Result := 'assignees';
    'comments': Result := 'comments';
    'checklistCount': Result := 'checklistCount';
    'checklists': Result := 'checklists';
    'requestedBy': Result := 'requestedBy';
    'location': Result := 'location';
    'activities': Result := 'activities';
    'descriptionText': Result := 'descriptionBadge';
  else Result := '';
  end;
end;

function MinicardPieceOrder(Db: TWLDb; const BoardId: string): TStringArray;
var B: TJSONObject; Sections, Fields, Hidden: TStringArray; i, k: Integer; Piece: string;
begin
  B := nil;
  if Db <> nil then B := BoardSettings(Db, BoardId);
  try
    if B <> nil then
    begin
      Sections := CardSettingsSectionOrder(B.Find('minicardSettingsSectionOrder'), 'minicard');
      Fields := LayoutApply('minicard', StringsOf(B.Find('minicardFieldOrder')));
      Hidden := StringsOf(B.Find('cardSettingsHiddenOnMinicard'));
    end
    else
    begin
      Sections := CardSettingsSectionOrder(nil, 'minicard');
      Fields := LayoutApply('minicard', []);
      Hidden := nil;
    end;
    Result := nil;
    for i := 0 to High(Sections) do
    begin
      if Contains(Hidden, Sections[i]) then Continue;
      for k := 0 to High(Fields) do
        if SectionKeyOf(MinicardLayout, Fields[k]) = Sections[i] then
        begin
          Piece := PieceOf(Fields[k]);
          if (Piece <> '') and not Contains(Result, Piece) then Push(Result, Piece);
        end;
    end;
  finally
    B.Free;
  end;
end;

function CardDateOrder(Db: TWLDb; const BoardId: string): TStringArray;
var Fields: TStringArray; i: Integer;
begin
  Fields := BoardFieldOrder(Db, BoardId, 'card');
  Result := nil;
  for i := 0 to High(Fields) do
    case Fields[i] of
      'receivedDate': Push(Result, 'received');
      'startDate': Push(Result, 'start');
      'dueDate': Push(Result, 'due');
      'endDate': Push(Result, 'end');
    end;
end;

procedure Load;
var i: Integer; Rows: TJSONArray; S: TJSONObject; Side: string;
begin
  Table := TJSONObject(GetJSON(CARD_SETTINGS_JSON));
  BoardFields := TStringList.Create;
  BoardFields.Sorted := True;
  BoardFields.Duplicates := dupIgnore;
  Rows := TJSONArray(Table.Find('rows'));
  for i := 0 to Rows.Count - 1 do
    for Side in ['card', 'minicard'] do
    begin
      S := SideOf(TJSONObject(Rows.Items[i]), Side);
      if (S <> nil) and (S.Get('kind', '') = 'board') then BoardFields.Add(S.Get('field', ''));
    end;
  CardLayout.Head := Strs(['dueComplete', 'cardNumber', 'cover']);
  CardLayout.Tail := Strs(['attachmentCount', 'activities']);
  SetLength(CardLayout.Sections, 14);
  CardLayout.Sections[0] := Sec('labels', ['labels', 'stickers', 'location']);
  CardLayout.Sections[1] := Sec('date', ['receivedDate', 'startDate', 'dueDate', 'endDate']);
  CardLayout.Sections[2] := Sec('members', ['members', 'assignee', 'creator', 'requestedBy', 'assignedBy']);
  CardLayout.Sections[3] := Sec('card', ['dependencies', 'cardSortingByNumber', 'showLists', 'cardButtons', 'similarCards']);
  CardLayout.Sections[4] := Sec('time', ['spentTime', 'flowtime', 'pomodoro']);
  CardLayout.Sections[5] := Sec('customFields', ['customFields']);
  CardLayout.Sections[6] := Sec('vote', ['vote']);
  CardLayout.Sections[7] := Sec('poker', ['poker']);
  CardLayout.Sections[8] := Sec('description', ['descriptionTitle', 'descriptionText'], True);
  CardLayout.Sections[9] := Sec('scrum', ['scrumSprint', 'scrumPastSprints', 'scrumRelease', 'scrumIssueType', 'scrumAcceptanceCriteria',
    'scrumBacklogRank']);
  CardLayout.Sections[10] := Sec('checklists', ['checklistCount', 'checklists']);
  CardLayout.Sections[11] := Sec('subtasks', ['subtasks']);
  CardLayout.Sections[12] := Sec('attachments', ['attachments', 'textNotes']);
  CardLayout.Sections[13] := Sec('comments', ['comments']);
  MinicardLayout.Head := Strs(['dueComplete', 'cardNumber', 'cover']);
  MinicardLayout.Tail := nil;
  SetLength(MinicardLayout.Sections, 14);
  MinicardLayout.Sections[0] := Sec('scrum', ['scrumSprint', 'scrumPastSprints', 'scrumRelease', 'scrumAcceptanceCriteria', 'scrumBacklogRank',
    'scrumIssueType']);
  MinicardLayout.Sections[1] := Sec('date', ['receivedDate', 'startDate', 'dueDate', 'endDate']);
  MinicardLayout.Sections[2] := Sec('time', ['spentTime', 'flowtime', 'pomodoro']);
  MinicardLayout.Sections[3] := Sec('labels', ['labels', 'stickers', 'location']);
  MinicardLayout.Sections[4] := Sec('customFields', ['customFields']);
  MinicardLayout.Sections[5] := Sec('members', ['assignee', 'members', 'creator', 'requestedBy', 'assignedBy']);
  MinicardLayout.Sections[6] := Sec('checklists', ['checklists', 'checklistCount']);
  MinicardLayout.Sections[7] := Sec('card', ['dependencies', 'cardSortingByNumber', 'showLists', 'swimlaneName']);
  MinicardLayout.Sections[8] := Sec('comments', ['commentCount', 'comments', 'activities']);
  MinicardLayout.Sections[9] := Sec('vote', ['vote']);
  MinicardLayout.Sections[10] := Sec('poker', ['poker']);
  MinicardLayout.Sections[11] := Sec('attachments', ['attachmentCount', 'attachments', 'textNotes']);
  MinicardLayout.Sections[12] := Sec('subtasks', ['subtasks']);
  MinicardLayout.Sections[13] := Sec('description', ['descriptionText']);
end;

initialization
  Load;
finalization
  Table.Free;
  BoardFields.Free;
end.
