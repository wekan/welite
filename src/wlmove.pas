unit wlmove;

{
  WeKan-Lite — combined arrows move component (docs/move.md)

  The no-JS / HTML 3.2|4 baseline for moving board items. Mirrors the COMBINED toolbar in
  https://github.com/wekan/tcl-tk-kanban/blob/main/kanban.go (Go/Fyne): one arrow keypad

         [ ▲ ]
    [ ◀ ][ ▼ ][ ▶ ]

  that moves ALL currently-selected swimlanes/lists/cards at once, plus a selection summary
  and Edit/Clone/Delete/Clear actions — instead of per-item arrow controls on every swimlane/
  list/card (the non-combined kanban.tcl, which "takes too much space").

  Mechanics (no JavaScript, no cookies): the whole board is ONE <form method="POST"
  action="/board/move">. Each item carries a selection checkbox (sel_card / sel_list /
  sel_swimlane = id, repeatable). The keypad arrows use stable move_up/down/left/right
  submit names with ASCII arrow captions. The browser sends only the clicked submit name plus checked selections,
  so the server learns "move these items in this direction" in one round trip. PRG-redirects
  back with the session id in the URL.

  Spatial model (WeKan): lists are horizontal, cards vertical, swimlanes vertical.
    cards     : up/down reorder within a list; left/right move to the adjacent list
    lists     : left/right reorder within a swimlane; up/down move to adjacent swimlane
    swimlanes : up/down reorder within the board
  Maps to schema.sql sort / listId / swimlaneId.

  This is the BASELINE that MultiDrag (wlenhanc.pas) progressively enhances — drag ends in
  this same /board/move endpoint. v0.1 reference skeleton.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, Classes, HTTPDefs, wldb, wltenant, wlauth, wlhtml;

// Selection checkbox to emit on each board item (inside the move <form>).
//   Kind: 'card' | 'list' | 'swimlane'
function SelectCheckbox(const Kind, Id: string): string;

// Open / close the move <form> that must wrap the board items + the keypad.
function MoveFormBegin(const S: TWLSession; const ActionUrl: string): string;
function MoveFormEnd: string;

// The combined keypad + action buttons + selection summary. Counts are for the summary label.
function MoveKeypad(const S: TWLSession; SwimlaneSel, ListSel, CardSel: Integer;
  IncludeActions: Boolean = True; IncludeClone:Boolean=True;const LanguageTag:string=''): string;

// Normalize one native movement/action submit name to its legacy command.
// Values are presentation only. Reject ambiguity without changing Params.
function ArrowDirection(const Command:string;out Direction:string;out Edge:Boolean):Boolean;
function MoveArrowButtons:string;

function NormalizeMoveSubmit(Params:TStrings):Boolean;

// Apply a submitted move: reads dir + sel_* from Params and updates the tenant DB. Returns
// True if anything moved. Register the endpoint at POST /board/move (see wlhttp.lpr).
function ApplyCardDrop(Db:TWLDb; Params:TStrings):Boolean;
function ApplyMove(Db: TWLDb; Params: TStrings; RightToLeft:Boolean=False): Boolean;

function RestoreListAction(const BoardId,ListId,BatchId:string):string;
function RestoreDeletedList(Db:TWLDb;const UserId,BoardId,ListId,BatchId:string):Boolean;

implementation

uses
  StrUtils,wli18n,wlposhis;

function q(const V: string): string;
begin
  Result := QuotedStr(V);
end;

function SelectCheckbox(const Kind, Id: string): string;
begin
  // checkbox name is per-kind and repeatable; CollectValues-style read on submit
  Result := '<input type="checkbox" name="sel_' + Kind + '" value="' + HtmlAttr(Id) + '">';
end;

function MoveFormBegin(const S: TWLSession; const ActionUrl: string): string;
begin
  Result := '<form method="POST" action="' + HtmlAttr(ActionUrl) + '">' +
            AuthHiddenFields(S, 'board:move') +
            '<input type="hidden" name="sessionId" value="' + HtmlAttr(S.SessionId) + '">';
end;

function MoveFormEnd: string;
begin
  Result := '</form>';
end;

function ArrowDirection(const Command:string;out Direction:string;out Edge:Boolean):Boolean;
begin
  Direction:=LowerCase(Trim(Command));
  Edge:=Copy(Direction,1,5)='edge_';
  if Edge then Delete(Direction,1,5);
  Result:=(Direction='left') or (Direction='right') or (Direction='up') or (Direction='down');
end;

function MoveArrowButtons:string;
  function Arrow(const Name,Glyph:string):string;
  begin
    Result:='<input type="submit" name="move_'+Name+'" value="'+HtmlAttr(Glyph)+'" dir="ltr"> ';
  end;
begin
  Result:='<div dir="ltr">'+Arrow('edge_left','<<')+Arrow('left','<')+
    Arrow('right','>')+Arrow('edge_right','>>')+
    Arrow('edge_up','^^')+Arrow('up','^')+Arrow('down','v')+Arrow('edge_down','vv')+'</div>';
end;

function NormalizeMoveSubmit(Params:TStrings):Boolean;
var i,Count,Legacy:Integer;Name,Command,Kind,Direction:string;Edge:Boolean;
begin
  Result:=False;if Params=nil then Exit;
  Count:=0;Legacy:=0;Command:='';Kind:='';
  for i:=0 to Params.Count-1 do
  begin
    Name:=LowerCase(Params.Names[i]);
    if (Name='dir') or (Name='action') then Inc(Legacy);
    if Copy(Name,1,5)='move_' then
    begin
      Command:=Copy(Name,6,Length(Name));
      if not ArrowDirection(Command,Direction,Edge) then Exit;
      Inc(Count);Kind:='dir';
    end
    else if Copy(Name,1,7)='action_' then
    begin
      if not ((Name='action_edit') or (Name='action_delete') or
        (Name='action_clear') or (Name='action_export') or (Name='action_clone') or
        (Name='action_save') or (Name='action_confirm-delete')) then Exit;
      Inc(Count);Command:=Copy(Name,8,Length(Name));Kind:='action';
    end;
  end;
  if (Count>1) or ((Count=1) and (Legacy>0)) then Exit;
  if Count=1 then Params.Values[Kind]:=Command;
  Result:=True;
end;

function MoveKeypad(const S: TWLSession; SwimlaneSel, ListSel, CardSel: Integer;
  IncludeActions: Boolean; IncludeClone:Boolean;const LanguageTag:string): string;
var Words:TWLTranslator;Language:TWLLanguage;
  function Button(const Action,Key,Fallback:string):string;
  begin Result:='<input type="submit" name="action_'+Action+'" value="'+HtmlAttr(Words.Text(Key,Fallback))+'"> ';end;
begin
  if not FindLanguage(LanguageTag,Language) then Language:=ResolveLanguage(S.LanguageTag,'','');
  Words:=TWLTranslator.Create(Language);
  try
  Result:=MoveArrowButtons;
  if IncludeActions then Result:=Result+
    Button('edit','edit','Edit')+Button('delete','r-delete-selected','Delete selected')+
    Button('clear','r-unselect-all','Unselect all')+Button('export','r-export-selected','Export selected')+LineEnding;
  if IncludeActions and IncludeClone then
    Result:=Result+Button('clone','copySelectionPopup-title','Copy selection');
  Result:=Result+'<p>'+HtmlEncode(Words.Text('multi-selection','Multi-Selection'))+': '+
    HtmlEncode(Words.Text('swimlanes','Swimlanes'))+' '+IntToStr(SwimlaneSel)+'; '+
    HtmlEncode(Words.Text('lists','Lists'))+' '+IntToStr(ListSel)+'; '+
    HtmlEncode(Words.Text('cards','Cards'))+' '+IntToStr(CardSel)+'</p>';
  finally Words.Free;end;
end;

// ---- selection reading -------------------------------------------------------------------
function CollectSel(Params: TStrings; const Kind: string): TStringList;
var i: Integer;
begin
  Result := TStringList.Create;
  if Params = nil then Exit;
  for i := 0 to Params.Count - 1 do
    if SameText(Params.Names[i], 'sel_' + Kind) and (Trim(Params.ValueFromIndex[i]) <> '') then
      if Result.IndexOf(Trim(Params.ValueFromIndex[i]))<0 then
        Result.Add(Trim(Params.ValueFromIndex[i]));
end;

// ---- reorder within a parent (up/down) ---------------------------------------------------
// Swap the `sort` of Id with its neighbor in the same scope. GoSmaller = move toward sort 0.
procedure SwapNeighbor(Db: TWLDb; const Table, ScopeCol, Id: string; GoSmaller,Edge: Boolean);
var
  Me, N: TWLRows;
  Scope, MySort, NId, NSort, Cmp, Ord, ScopeExtra, ExtraColumn: string;
begin
  ExtraColumn:='';
  if Table='cards' then ExtraColumn:=',swimlaneId';
  Me := Db.Query(Format('SELECT %s,sort,boardId%s FROM %s WHERE id=%s LIMIT 1;', [ScopeCol,ExtraColumn,Table,q(Id)]));
  if (Length(Me) = 0) or (Length(Me[0]) < 2) then Exit;
  Scope := Me[0][0]; MySort := Me[0][1];
  ScopeExtra:=' AND boardId='+q(Me[0][2])+' AND archived=0';
  if (Table='cards') or (Table='lists') then ScopeExtra:=ScopeExtra+' AND deletedAt IS NULL';
  if Table='cards' then ScopeExtra:=ScopeExtra+' AND swimlaneId='+q(Me[0][3]);
  if GoSmaller then begin Cmp := '<'; Ord := 'DESC'; end
               else begin Cmp := '>'; Ord := 'ASC';  end;
  if Edge then
  begin
    if GoSmaller then Cmp:='MIN' else Cmp:='MAX';
    if GoSmaller then Ord:='-1' else Ord:='+1';
    Db.Exec('UPDATE '+Table+' SET sort=(SELECT COALESCE('+Cmp+'(sort),0)'+Ord+
      ' FROM '+Table+' WHERE '+ScopeCol+'='+q(Scope)+ScopeExtra+') WHERE id='+q(Id)+ScopeExtra+';');
    Exit;
  end;
  N := Db.Query(Format(
    'SELECT id,sort FROM %s WHERE %s=%s%s AND sort %s %s ORDER BY sort %s LIMIT 1;',
    [Table, ScopeCol, q(Scope), ScopeExtra, Cmp, q(MySort), Ord]));
  if (Length(N) = 0) or (Length(N[0]) < 2) then Exit;   // already at the edge
  NId := N[0][0]; NSort := N[0][1];
  Db.Exec(Format('UPDATE %s SET sort=%s WHERE id=%s;', [Table, q(NSort), q(Id)]));
  Db.Exec(Format('UPDATE %s SET sort=%s WHERE id=%s;', [Table, q(MySort), q(NId)]));
end;

// ---- relocate a card to the adjacent list (left/right) -----------------------------------
procedure MoveCardAcrossList(Db: TWLDb; const CardId: string; Next,Edge: Boolean);
var
  C, L, MaxR: TWLRows;
  Sw, CurList, Target, BoardId: string;
  i, idx: Integer;
begin
  C := Db.Query(Format('SELECT swimlaneId,listId,boardId FROM cards WHERE id=%s AND deletedAt IS NULL LIMIT 1;', [q(CardId)]));
  if (Length(C) = 0) or (Length(C[0]) < 2) then Exit;
  Sw := C[0][0]; CurList := C[0][1]; BoardId:=C[0][2];
  L := Db.Query(Format('SELECT id FROM lists WHERE boardId=%s AND (swimlaneId=%s OR swimlaneId='''') AND archived=0 AND deletedAt IS NULL ORDER BY sort,id;', [q(BoardId),q(Sw)]));
  idx := -1;
  for i := 0 to High(L) do
    if (Length(L[i]) > 0) and (L[i][0] = CurList) then begin idx := i; Break; end;
  if idx < 0 then Exit;
  if Edge then begin if Next then idx:=High(L) else idx:=0;end
  else if Next then Inc(idx) else Dec(idx);
  if (idx < 0) or (idx > High(L)) then Exit;             // no list that way
  Target := L[idx][0];
  if Target=CurList then Exit;
  MaxR := Db.Query(Format('SELECT COALESCE(MAX(sort),0)+1 FROM cards WHERE listId=%s AND swimlaneId=%s AND boardId=%s;', [q(Target),q(Sw),q(BoardId)]));
  Db.Exec(Format('UPDATE cards SET listId=%s, sort=%s WHERE id=%s;',
    [q(Target), q(MaxR[0][0]), q(CardId)]));
end;

// Relocate a list and all of its cards, including archived cards, as one transaction.
// Keep boardId in every scope: legacy rows may have an empty swimlaneId.
procedure MoveListAcrossSwimlane(Db: TWLDb; const ListId: string; Next,Edge: Boolean);
var
  L, Neighbors, MaxR: TWLRows;
  BoardId, Target, Cmp, Ord: string;
begin
  L := Db.Query('SELECT l.boardId,s.sort,s.id FROM lists l JOIN swimlanes s ' +
    'ON s.id=l.swimlaneId AND s.boardId=l.boardId ' +
    'WHERE l.archived=0 AND l.deletedAt IS NULL AND s.archived=0 AND l.id=' + q(ListId) + ';');
  if Length(L) = 0 then Exit;
  BoardId := L[0][0];
  if Next then begin Cmp := '>'; Ord := 'ASC'; end
          else begin Cmp := '<'; Ord := 'DESC'; end;
  if Edge then
  begin
    if Next then Ord:='DESC' else Ord:='ASC';
    Neighbors:=Db.Query('SELECT id FROM swimlanes WHERE boardId='+q(BoardId)+
      ' AND archived=0 ORDER BY sort '+Ord+',id '+Ord+' LIMIT 1;');
  end
  else
    Neighbors := Db.Query('SELECT id FROM swimlanes WHERE boardId=' + q(BoardId) +
    ' AND archived=0 AND (sort ' + Cmp + ' ' + q(L[0][1]) +
    ' OR (sort=' + q(L[0][1]) + ' AND id ' + Cmp + ' ' + q(L[0][2]) +
    ')) ORDER BY sort ' + Ord + ',id ' + Ord + ' LIMIT 1;');
  if Length(Neighbors) = 0 then Exit;
  Target := Neighbors[0][0];
  if Target=L[0][2] then Exit;
  MaxR := Db.Query('SELECT COALESCE(MAX(sort),-1)+1 FROM lists WHERE boardId=' +
    q(BoardId) + ' AND swimlaneId=' + q(Target) + ' AND archived=0 AND deletedAt IS NULL;');
  // One Exec also works with the CLI backend, which opens one connection per call.
  if not Db.Exec('BEGIN IMMEDIATE; UPDATE lists SET swimlaneId=' + q(Target) +
    ',sort=' + q(MaxR[0][0]) + ' WHERE id=' + q(ListId) + ' AND boardId=' +
    q(BoardId) + '; UPDATE cards SET swimlaneId=' + q(Target) +
    ' WHERE listId=' + q(ListId) + ' AND boardId=' + q(BoardId) + '; COMMIT;') then
    Db.Exec('ROLLBACK;');
end;

function ApplyCardDrop(Db:TWLDb; Params:TStrings):Boolean;
var Cards:TStringList; R:TWLRows; i:Integer; Sql,B,L,S:string;
begin
  Result:=False; B:=Params.Values['boardId'];L:=Params.Values['targetList'];S:=Params.Values['targetLane'];
  Cards:=CollectSel(Params,'card');
  try
    if Cards.Count=0 then Exit;
    R:=Db.Query('SELECT id FROM lists WHERE id='+QuotedStr(L)+' AND boardId='+QuotedStr(B)+
      ' AND archived=0 AND deletedAt IS NULL AND (swimlaneId='+QuotedStr(S)+' OR swimlaneId='''');');
    if Length(R)=0 then Exit;
    R:=Db.Query('SELECT id FROM swimlanes WHERE id='+QuotedStr(S)+' AND boardId='+QuotedStr(B)+' AND archived=0;');
    if Length(R)=0 then Exit;
    Sql:='BEGIN IMMEDIATE; ';
    for i:=0 to Cards.Count-1 do
      Sql:=Sql+'UPDATE cards SET listId='+QuotedStr(L)+',swimlaneId='+QuotedStr(S)+
        ',sort=(SELECT COALESCE(MAX(sort),-1)+1 FROM cards WHERE boardId='+QuotedStr(B)+
        ' AND listId='+QuotedStr(L)+' AND swimlaneId='+QuotedStr(S)+') WHERE id='+QuotedStr(Cards[i])+
        ' AND boardId='+QuotedStr(B)+' AND archived=0 AND deletedAt IS NULL; ';
    Result:=Db.Exec(Sql+'COMMIT;');
    if not Result then Db.Exec('ROLLBACK;');
  finally Cards.Free;end;
end;

function ApplyMove(Db: TWLDb; Params: TStrings; RightToLeft:Boolean): Boolean;
var
  Dir: string;
  Cards, Lists, Swimlanes: TStringList;
  i: Integer;
  Edge:Boolean;
  procedure OrderForEdge(Items:TStringList;const Table:string;Reverse:Boolean);
  var Ids,Id,Ordering:string;Row:TWLRow;Rows:TWLRows;
  begin
    if not Edge or (Items.Count<2) then Exit;
    Ids:='';
    for Id in Items do
    begin
      if Ids<>'' then Ids:=Ids+',';
      Ids:=Ids+q(Id);
    end;
    if Reverse then Ordering:=' DESC' else Ordering:=' ASC';
    Rows:=Db.Query('SELECT id FROM '+Table+' WHERE id IN ('+Ids+
      ') ORDER BY sort'+Ordering+',id'+Ordering+';');
    if Length(Rows)<>Items.Count then Exit;
    Items.Clear;
    for Row in Rows do Items.Add(Row[0]);
  end;
begin
  Result := False;
  if not ArrowDirection(Params.Values['dir'],Dir,Edge) then Exit;
  if RightToLeft then
    if Dir='left' then Dir:='right' else if Dir='right' then Dir:='left';

  Cards := CollectSel(Params, 'card');
  Lists := CollectSel(Params, 'list');
  Swimlanes := CollectSel(Params, 'swimlane');
  try
    OrderForEdge(Cards,'cards',Dir='up');
    OrderForEdge(Lists,'lists',Dir='left');
    OrderForEdge(Swimlanes,'swimlanes',Dir='up');
    for i := 0 to Cards.Count - 1 do
      case Dir of
        'up':    SwapNeighbor(Db, 'cards', 'listId', Cards[i], True,Edge);
        'down':  SwapNeighbor(Db, 'cards', 'listId', Cards[i], False,Edge);
        'left':  MoveCardAcrossList(Db, Cards[i], False,Edge);
        'right': MoveCardAcrossList(Db, Cards[i], True,Edge);
      end;
    for i := 0 to Lists.Count - 1 do
      case Dir of
        'left':  SwapNeighbor(Db, 'lists', 'swimlaneId', Lists[i], True,Edge);
        'right': SwapNeighbor(Db, 'lists', 'swimlaneId', Lists[i], False,Edge);
        'up':    MoveListAcrossSwimlane(Db, Lists[i], False,Edge);
        'down':  MoveListAcrossSwimlane(Db, Lists[i], True,Edge);
      end;
    for i := 0 to Swimlanes.Count - 1 do
      case Dir of
        'up':    SwapNeighbor(Db, 'swimlanes', 'boardId', Swimlanes[i], True,Edge);
        'down':  SwapNeighbor(Db, 'swimlanes', 'boardId', Swimlanes[i], False,Edge);
      end;
    Result := (Cards.Count + Lists.Count + Swimlanes.Count) > 0;
  finally
    Cards.Free; Lists.Free; Swimlanes.Free;
  end;
end;

function RestoreListAction(const BoardId,ListId,BatchId:string):string;
begin
  Result:='board:restore-list:'+IntToStr(Length(BoardId))+':'+BoardId+
    IntToStr(Length(ListId))+':'+ListId+BatchId;
end;

function RestoreDeletedList(Db:TWLDb;const UserId,BoardId,ListId,BatchId:string):Boolean;
const ClearMarkers='deletedAt=NULL,deletedBy=NULL,deleteBatchId=NULL';
var Scope,Deleted,Sql:string;Position:TWLRows;
begin
  Scope:='id='+q(ListId)+' AND boardId='+q(BoardId);
  Deleted:=Scope+' AND deletedAt IS NOT NULL AND COALESCE(deleteBatchId,'''')='+q(BatchId);
  Position:=Db.Query('SELECT swimlaneId,sort,deletedAt FROM lists WHERE '+Deleted+';');
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+Deleted+
    ')=1 THEN 1 ELSE json(''List is no longer deleted'') END; '+
    'UPDATE cards SET '+ClearMarkers+' WHERE boardId='+q(BoardId)+' AND listId='+q(ListId)+
    ' AND deletedAt IS NOT NULL AND deleteBatchId=(SELECT deleteBatchId FROM lists WHERE '+Deleted+'); '+
    'UPDATE lists SET '+ClearMarkers+' WHERE '+Deleted+
    '; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+Scope+
    ' AND deletedAt IS NULL)=1 THEN 1 ELSE json(''Could not restore list'') END; COMMIT;';
  Result:=Db.Exec(Sql);
  if not Result then Db.Exec('ROLLBACK;')
  else if Length(Position)=1 then
    try RecordListPosition(Db,UserId,BoardId,ListId,BatchId,Position[0][2],Position[0],True);except end;
end;
end.
