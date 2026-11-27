unit wlrules;

{
  WeKan-Lite — WeKan's Rules in the HTML5 view: the Rules page, the rules.*
  methods it calls, and the engine that runs a board's rules.

  A rule is WeKan's three documents - rules, triggers and actions - in the
  shared store (FerretDB's collections of the same names), as WeKan and
  Weddy keep them: the page is Weddy's rules.pug (src/tpl/rules.inc, drawn by
  wltpl), the methods and the engine follow Weddy's api_rules.go and
  rules_engine.go, which follow WeKan's models/rules.js and
  server/rulesHelper.js.

  The engine runs when a request has written: ArmRules marks the request at
  its start, and before its answer goes (SendResponse, or FlushRules from
  the senders) the activities it wrote are matched against the board's
  triggers, and the actions of each matching rule are done - as the
  activity's own user, and only what that user may do. What an action
  writes is an activity too, so rules start rules, at most MAX_RULE_DEPTH
  deep (WeKan's dos.rule-loop, recorded in Admin Panel / Problems).
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses SysUtils, Classes, fpjson, httpdefs, wldb, wltenant, wli18n;

// The Rules page's content for a viewer who can see the board; '' when the
// board is not there for them. BoardTitle is the board's title.
function RulesPageContent(Db: TWLDb; const UserId, BoardId, View: string; Words: TWLTranslator;
  const Lang: string; out BoardTitle: string): string;

// A rules.* method (rules.createRule, rules.updateRule, rules.deleteRule,
// rules.setEnabled) with its JSON arguments: the HTTP code and the answer,
// {"result":...} or Meteor's {"error":...,"reason":...}. 0 for any other name.
function RulesMethod(const T: TWLTenant; const UserId, Name: string; Args: TJSONArray; out Answer: string;
  Words: TWLTranslator = nil): Integer;

// The Rules page's downloads (/b/:id/:slug/rules/export?format=json|csv|wrike,
// ids=...): the board's rules as WeKan exports them, or the board as a Wrike
// workflow. False when the user is not the board's admin.
function RulesExport(Db: TWLDb; const UserId, BoardId, Format, Ids: string; out Body, ContentType, FileName: string): Boolean;

// WeKan's boardButtons and cardButtons: the board's enabled button rules of
// ButtonType ('board' or 'card') as the board header's links or the opened
// card's buttons; '' when there are none.
function RuleButtonsHtml(Db: TWLDb; const BoardId, ButtonType: string; Words: TWLTranslator): string;

// Rules' history, as WeKan's server/lib/ruleHistory.js: a rule as one
// snapshot - {rule, trigger, action[, extraTriggers, extraActions]} without
// timestamps, {rule: null} when it is not there - before and after each
// write, and one changeHistory row when they differ (wlchhist).
function RuleSnapshot(Db: TWLDb; const RuleId: string): TJSONObject;
procedure RecordRuleHistory(Db: TWLDb; const UserId: string; Before, After: TJSONObject);
// WeKan's changeHistory.undoLast(boardId), redoLast(boardId) and
// restore(rowId), for the rule rows of a board one administers: 0 for any
// other method name.
function HistoryMethod(const T: TWLTenant; const UserId, Name: string; Args: TJSONArray; out Answer: string): Integer;

// The engine's hooks: arm at the start of a request, flush before it answers.
procedure ArmRules(Request: TRequest);
procedure FlushRules;
// Response.SendContent, with the request's rules run first.
procedure SendResponse(Response: TResponse);

// The page that wrote last (weddy.js' X-Weddy-Page / X-Weddy-Live) if it
// wrote in the last few seconds: a board's live events name it, so that page
// does not draw again what it drew itself.
function RecentWriterPage: string;
// The live board's next change is everybody's, the writer's page too: a
// change other pages draw differently (a rule, a board's date format).
procedure AnnounceToAll;
// What the board's rules are now, as a short text that changes when they do.
function RulesSignature(Db: TWLDb; const BoardId: string): string;

// The rules an activity of a board starts, run now (the engine's own entry,
// for tests and for writes outside a request).
procedure RunRulesSince(const T: TWLTenant; const Stamp: string);
// Scheduled triggers (WeKan's server/scheduledRules.js): each that fires in
// the minute of Local (atTime, calendar) or Utc (cron) runs its rules' actions
// on the cards it chooses, once in that minute.
procedure RunScheduledRules(const T: TWLTenant; Local, Utc: TDateTime);
// A 17-character Meteor-style id; whether the store is a shared FerretDB one;
// the SQL that inserts Doc into Collection there.
function NewId: string;
function IsShared(Db: TWLDb): Boolean;
function InsertDocSql(Db: TWLDb; const Collection: string; Doc: TJSONObject; const Hints: string): string;

const
  MAX_RULE_DEPTH = 5;

implementation

uses Math, StrUtils, DateUtils, jsonparser, wlsjson, wlcfjson, wlferr, wlapi, wlaccess, wltpl, wlcase, wlwrike, wlh5, wlchhist, wlchhash, wlsched;

threadvar
  ArmedRequest: TRequest;
  ArmedStamp: string;

function Q(const S: string): string;
begin
  Result := QuotedStr(S);
end;

// A 17-character Mongo-style id, as WeKan's (schema.sql's convention).
function NewId: string;
const A = '23456789ABCDEFGHJKLMNPQRSTWXYZabcdefghijkmnopqrstuvwxyz';
var i: Integer;
begin
  SetLength(Result, 17);
  for i := 1 to 17 do Result[i] := A[Random(Length(A)) + 1];
end;

function NowIso: string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', LocalTimeToUniversal(Now));
end;

function NowMs: Int64;
begin
  Result := DateTimeToUnix(LocalTimeToUniversal(Now), True) * 1000 + MilliSecondOf(Now);
end;

// ---- the shared store's collections -----------------------------------------

function IsShared(Db: TWLDb): Boolean;
begin
  Result := Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';')) = 1;
end;

// A collection's table: its name (for wl_storage) and quoted; False when the
// store has none.
function CollectionTable(Db: TWLDb; const Name: string; out Raw, Quoted: string): Boolean;
var R: TWLRows;
begin
  Raw := ''; Quoted := '';
  if not IsShared(Db) then Exit(False);
  R := Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=' + Q(Name) + ';');
  Result := Length(R) = 1;
  if Result then
  begin
    Raw := R[0][0];
    Quoted := '"' + StringReplace(Raw, '"', '""', [rfReplaceAll]) + '"';
  end;
end;

function DocField(const Name: string): string;
begin
  Result := 'json_extract(_ferretdb_sjson,''$.' + Name + ''')';
end;

// The collection's documents matching Where (SQL over DocField), as plain JSON.
function FindDocs(Db: TWLDb; const Collection, Where, Order: string): TJSONArray;
var Raw, Tbl, Sql: string; R: TWLRows; i: Integer;
begin
  Result := TJSONArray.Create;
  if not CollectionTable(Db, Collection, Raw, Tbl) then Exit;
  Sql := 'SELECT json(_ferretdb_sjson) FROM ' + Tbl + ' WHERE ' + DocField('$s.p._id.t') + '=''string''';
  if Where <> '' then Sql := Sql + ' AND (' + Where + ')';
  if Order <> '' then Sql := Sql + ' ORDER BY ' + Order;
  R := Db.Query(Sql + ';');
  for i := 0 to High(R) do
    try
      Result.Add(DocumentJson(R[i][0]));
    except
      // A document this cannot read is not one of the rules it runs.
    end;
end;

function FindDoc(Db: TWLDb; const Collection, Id: string): TJSONObject;
var A: TJSONArray;
begin
  Result := nil;
  if (Id = '') or (Pos(#0, Id) > 0) then Exit;
  A := FindDocs(Db, Collection, DocField('_id') + '=' + Q(Id), '');
  try
    if A.Count = 1 then Result := TJSONObject(A.Extract(0));
  finally
    A.Free;
  end;
end;

function DocLiteral(const Raw, Typed: string): string;
var P: string;
begin
  P := Q(Typed);
  Result := 'CASE WHEN wl_storage(' + Q(Raw) + ')=''blob'' THEN jsonb(' + P + ') ELSE ' + P + ' END';
end;

// The SQL that inserts Doc into the collection (createdAt etc. as dates).
function InsertDocSql(Db: TWLDb; const Collection: string; Doc: TJSONObject; const Hints: string): string;
var Raw, Tbl: string;
begin
  if not (EnsureSharedCollection(Db, Collection) and CollectionTable(Db, Collection, Raw, Tbl)) then
    raise Exception.Create('No ' + Collection + ' collection');
  Result := 'INSERT INTO ' + Tbl + '(_ferretdb_sjson) VALUES(' + DocLiteral(Raw, TypedDocument(Doc.AsJSON, '', Hints)) + '); ';
end;

// The SQL that sets Fields (plain JSON values) on the document Id, keeping its
// other fields and their types.
function UpdateDocSql(Db: TWLDb; const Collection, Id: string; Fields: TJSONObject; const Hints: string): string;
var Raw, Tbl, Previous: string; R: TWLRows; Plain: TJSONObject; i: Integer;
begin
  if not CollectionTable(Db, Collection, Raw, Tbl) then raise Exception.Create('No ' + Collection + ' collection');
  R := Db.Query('SELECT json(_ferretdb_sjson) FROM ' + Tbl + ' WHERE ' + DocField('_id') + '=' + Q(Id) + ';');
  if Length(R) <> 1 then raise Exception.Create('No such document');
  Previous := R[0][0];
  Plain := ExactObject(PlainDocument(Previous));
  try
    for i := 0 to Fields.Count - 1 do
    begin
      Plain.Delete(Fields.Names[i]);
      // null is WeKan's $unset: the field goes.
      if Fields.Items[i].JSONType <> jtNull then Plain.Add(Fields.Names[i], Fields.Items[i].Clone);
    end;
    Result := 'UPDATE ' + Tbl + ' SET _ferretdb_sjson=' + DocLiteral(Raw, TypedDocument(Plain.AsJSON, Previous, Hints)) +
      ' WHERE ' + DocField('_id') + '=' + Q(Id) + '; ';
  finally
    Plain.Free;
  end;
end;

function DeleteDocSql(Db: TWLDb; const Collection, Id: string): string;
var Raw, Tbl: string;
begin
  Result := '';
  if CollectionTable(Db, Collection, Raw, Tbl) then
    Result := 'DELETE FROM ' + Tbl + ' WHERE ' + DocField('_id') + '=' + Q(Id) + '; ';
end;

function Str(Doc: TJSONObject; const Name: string): string;
var V: TJSONData;
begin
  Result := '';
  if Doc = nil then Exit;
  V := Doc.Find(Name);
  if (V <> nil) and (V.JSONType = jtString) then Result := V.AsString;
end;

// ---- the Rules page -----------------------------------------------------------

// ruleDetails.js: a description with a capital first letter.
function CapitalFirst(const S: string): string;
begin
  Result := Utf8CapitalFirst(S);
end;

// WeKan's stripDoc: a trigger or an action without what ties it to a board.
function PortableDoc(Doc: TJSONObject): TJSONObject;
var Key: string;
begin
  Result := TJSONObject(Doc.Clone);
  for Key in ['_id', 'boardId', 'createdAt', 'modifiedAt', 'updatedAt'] do Result.Delete(Key);
end;

function RuleActionIds(Rule: TJSONObject): TStringArray;
var V: TJSONData; i: Integer;
begin
  Result := nil;
  if Str(Rule, 'actionId') <> '' then
  begin
    SetLength(Result, 1);
    Result[0] := Str(Rule, 'actionId');
  end;
  V := Rule.Find('extraActionIds');
  if V is TJSONArray then
    for i := 0 to V.Count - 1 do
      if V.Items[i].JSONType = jtString then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := V.Items[i].AsString;
      end;
end;

function Palette(Words: TWLTranslator; Triggers: Boolean): TJSONArray;
const
  TriggerKeys: array[0..12] of string = ('r-w-card-created', 'r-when-a-card-is-moved', 'r-w-card-archived',
    'r-w-card-unarchived', 'r-w-label-added', 'r-w-label-removed', 'r-w-member-added', 'r-w-member-removed',
    'r-w-assignee-added', 'r-w-assignee-removed', 'r-w-checklist-added', 'r-w-attachment-added', 'r-w-every-day-at');
  TriggerDocs: array[0..12] of string = (
    '{"activityType":"createCard","listName":"*","swimlaneName":"*","cardTitle":"*","userId":"*"}',
    '{"activityType":"moveCard","listName":"*","oldListName":"*","swimlaneName":"*","cardTitle":"*","userId":"*"}',
    '{"activityType":"archivedCard","userId":"*"}',
    '{"activityType":"restoredCard","userId":"*"}',
    '{"activityType":"addedLabel","labelId":"*","userId":"*"}',
    '{"activityType":"removedLabel","labelId":"*","userId":"*"}',
    '{"activityType":"joinMember","username":"*","userId":"*"}',
    '{"activityType":"unjoinMember","username":"*","userId":"*"}',
    '{"activityType":"joinAssignee","username":"*","userId":"*"}',
    '{"activityType":"unjoinAssignee","username":"*","userId":"*"}',
    '{"activityType":"addChecklist","checklistName":"*","userId":"*"}',
    '{"activityType":"addAttachment","userId":"*"}',
    '{"activityType":"scheduledTrigger","scheduleKind":"calendar","scheduleType":"daily","atTime":"09:00","listName":"*","swimlaneName":"*"}');
  ActionKeys: array[0..8] of string = ('r-d-move-to-top-gen', 'r-d-move-to-bottom-gen', 'r-d-archive', 'r-d-unarchive',
    'r-mark-complete', 'r-mark-incomplete', 'r-remove-all', 'r-remove-all-assignees', 'r-w-set-received-now');
  ActionDocs: array[0..8] of string = (
    '{"actionType":"moveCardToTop","listName":"*","swimlaneName":"*"}',
    '{"actionType":"moveCardToBottom","listName":"*","swimlaneName":"*"}',
    '{"actionType":"archive"}', '{"actionType":"unarchive"}',
    '{"actionType":"markCardComplete"}', '{"actionType":"markCardIncomplete"}',
    '{"actionType":"removeMember","username":"*"}', '{"actionType":"removeAssignee","username":"*"}',
    '{"actionType":"setDate","dateField":"receivedAt"}');
var i: Integer; Doc: TJSONObject; Lbl: string;
  procedure Add(const Key, Json: string);
  begin
    Lbl := StringReplace(Words.Text(Key, Key), '__time__', '09:00', [rfReplaceAll]);
    Doc := TJSONObject(GetJSON(Json));
    Doc.Add('desc', Lbl);
    Result.Add(TJSONObject.Create(['Idx', Result.Count, 'Label', Lbl, 'Doc', Doc.AsJSON]));
    Doc.Free;
  end;
begin
  Result := TJSONArray.Create;
  if Triggers then
    for i := 0 to High(TriggerKeys) do Add(TriggerKeys[i], TriggerDocs[i])
  else
    for i := 0 to High(ActionKeys) do Add(ActionKeys[i], ActionDocs[i]);
end;

{$I tpl/rules.inc}

function RulesPageContent(Db: TWLDb; const UserId, BoardId, View: string; Words: TWLTranslator;
  const Lang: string; out BoardTitle: string): string;
var R, L: TWLRows; Data, Board, Row, Trig, Act, Copy_: TJSONObject; Rules, Acts, Labels, Boards, Copies, Lists, Lanes, Tokens: TJSONArray;
  Docs: TJSONArray; i, k: Integer; CanEdit: Boolean; Ids: TStringArray; ShownView, Desc: string;
begin
  Result := ''; BoardTitle := '';
  if (BoardId = '') or (Pos(#0, BoardId) > 0) or not BoardCanRead(Db, UserId, BoardId) then Exit;
  R := Db.Query('SELECT id,title,slug,color FROM boards WHERE id=' + Q(BoardId) + ';');
  if Length(R) <> 1 then Exit;
  BoardTitle := R[0][1];
  CanEdit := BoardCanAdmin(Db, UserId, BoardId);
  ShownView := View;
  if not ((View = 'list') or (View = 'workflow') or (View = 'import') or (View = 'bots') or (View = 'blocks')) then ShownView := 'list';
  Data := TJSONObject.Create;
  try
    Board := TJSONObject.Create(['ID', R[0][0], 'Title', R[0][1], 'Slug', R[0][2], 'Color', R[0][3]]);
    Data.Add('Board', Board);
    Data.Add('L', Lang);
    Data.Add('View', ShownView);
    Data.Add('CanEdit', CanEdit);
    Data.Add('TriggerPalette', Palette(Words, True));
    Data.Add('ActionPalette', Palette(Words, False));
    Tokens := TJSONArray.Create(['{creator}', '{assignees}', '{members}', '{card}', '{list}', '{board}']);
    L := Db.Query('SELECT DISTINCT trim(f.name) FROM custom_fields f JOIN custom_field_boards b ON b.customFieldId=f.id ' +
      'WHERE b.boardId=' + Q(BoardId) + ' AND f.adminOnly=0 AND trim(f.name)<>'''' AND instr(f.name,''{'')=0 AND instr(f.name,''}'')=0 ' +
      'ORDER BY f.name;');
    for i := 0 to High(L) do Tokens.Add('{customField:' + L[i][0] + '}');
    Data.Add('RuleTokens', Tokens);
    Rules := TJSONArray.Create;
    Data.Add('Rules', Rules);
    if CanEdit then
    begin
      Docs := FindDocs(Db, 'rules', DocField('boardId') + '=' + Q(BoardId), DocField('createdAt') + ',' + DocField('_id'));
      try
        for i := 0 to Docs.Count - 1 do
        begin
          Row := TJSONObject.Create(['ID', Str(Docs.Objects[i], '_id'), 'Title', Str(Docs.Objects[i], 'title'),
            'Enabled', not ((Docs.Objects[i].Find('enabled') <> nil) and (Docs.Objects[i].Find('enabled').JSONType = jtBoolean) and
            not Docs.Objects[i].Booleans['enabled'])]);
          Trig := FindDoc(Db, 'triggers', Str(Docs.Objects[i], 'triggerId'));
          if Trig <> nil then
          try
            Desc := Str(Trig, 'desc');
            if Desc = '' then Desc := Str(Trig, 'activityType');
            Row.Add('Trigger', CapitalFirst(Desc));
            Copy_ := PortableDoc(Trig);
            Row.Add('TriggerDoc', Copy_.AsJSON);
            Copy_.Free;
          finally
            Trig.Free;
          end
          else
          begin
            Row.Add('Trigger', '');
            Row.Add('TriggerDoc', '{}');
          end;
          Acts := TJSONArray.Create;
          Row.Add('Actions', Acts);
          Ids := RuleActionIds(Docs.Objects[i]);
          for k := 0 to High(Ids) do
          begin
            Act := FindDoc(Db, 'actions', Ids[k]);
            if Act = nil then Continue;
            Desc := Str(Act, 'desc');
            if Desc = '' then Desc := Str(Act, 'actionType');
            Acts.Add(CapitalFirst(Desc));
            Act.Free;
          end;
          Rules.Add(Row);
        end;
      finally
        Docs.Free;
      end;
      Labels := TJSONArray.Create;
      Data.Add('Labels', Labels);
      L := Db.Query('SELECT id,COALESCE(name,'''') FROM board_labels WHERE boardId=' + Q(BoardId) + ' ORDER BY id;');
      for i := 0 to High(L) do Labels.Add(TJSONObject.Create(['ID', L[i][0], 'Name', L[i][1]]));
      // The boards an action may name: those the user may change, not
      // archived, not templates - the current one first (boardActions).
      Boards := TJSONArray.Create;
      Copies := TJSONArray.Create;
      Data.Add('Boards', Boards);
      Data.Add('CopyBoards', Copies);
      L := Db.Query('SELECT b.id,b.title FROM boards b JOIN board_members m ON m.boardId=b.id WHERE m.userId=' + Q(UserId) +
        ' AND m.isActive=1 AND b.archived=0 AND b.type NOT LIKE ''template%'' ORDER BY (b.id<>' + Q(BoardId) + '),b.title LIMIT 500;');
      for i := 0 to High(L) do
      begin
        if not BoardCanWrite(Db, UserId, L[i][0]) then Continue;
        Boards.Add(TJSONObject.Create(['ID', L[i][0], 'Title', L[i][1]]));
        Copy_ := TJSONObject.Create(['ID', L[i][0], 'Title', L[i][1], 'Current', L[i][0] = BoardId]);
        Lists := TJSONArray.Create;
        Lanes := TJSONArray.Create;
        Copy_.Add('Lists', Lists);
        Copy_.Add('Swimlanes', Lanes);
        R := Db.Query('SELECT id,title FROM lists WHERE boardId=' + Q(L[i][0]) + ' AND archived=0 AND deletedAt IS NULL ORDER BY sort LIMIT 500;');
        for k := 0 to High(R) do Lists.Add(TJSONObject.Create(['ID', R[k][0], 'Title', R[k][1], 'Board', L[i][0]]));
        R := Db.Query('SELECT id,title FROM swimlanes WHERE boardId=' + Q(L[i][0]) + ' AND archived=0 ORDER BY sort LIMIT 500;');
        for k := 0 to High(R) do Lanes.Add(TJSONObject.Create(['ID', R[k][0], 'Title', R[k][1], 'Board', L[i][0]]));
        Copies.Add(Copy_);
      end;
    end;
    Result := RenderTemplate(TPL_RULES, Data, Words, Lang);
  finally
    Data.Free;
  end;
end;

// ---- the methods ----------------------------------------------------------------

function MethodError(Code: Integer; const Error, Reason: string; out Answer: string): Integer;
begin
  Answer := '{"error":"' + StringToJSONString(Error) + '","reason":"' + StringToJSONString(Reason) + '"}';
  Result := Code;
end;

function ValidFieldName(const S: string): Boolean;
var i: Integer;
begin
  Result := (Length(S) >= 1) and (Length(S) <= 64) and (S[1] in ['A'..'Z', 'a'..'z']);
  if Result then
    for i := 2 to Length(S) do
      if not (S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then Exit(False);
end;

// Weddy's ruleValueAt: text, numbers, booleans, null, lists of them, and
// small objects of them - never an operator or a path as a key.
function ValidValue(V: TJSONData; ListOK: Boolean; Depth: Integer): Boolean;
var i: Integer;
begin
  case V.JSONType of
    jtNull, jtBoolean, jtNumber: Result := True;
    jtString: Result := Length(V.AsString) <= 10000;
    jtArray:
      begin
        Result := ListOK and (V.Count <= 1000);
        if Result then
          for i := 0 to V.Count - 1 do
            if not ValidValue(V.Items[i], False, Depth + 1) then Exit(False);
      end;
    jtObject:
      begin
        Result := (Depth < 3) and (V.Count <= 64);
        if Result then
          for i := 0 to V.Count - 1 do
            if not ValidFieldName(TJSONObject(V).Names[i]) or not ValidValue(V.Items[i], True, Depth + 1) then Exit(False);
      end;
  else Result := False;
  end;
end;

// Weddy's ruleComponent: a trigger or an action from a request.
function RuleComponent(V: TJSONData; const KindField: string; out Doc: TJSONObject; out Error: string): Boolean;
var i: Integer; Name: string;
begin
  Doc := nil; Error := '';
  if not (V is TJSONObject) or (V.Count > 64) then begin Error := 'a trigger and an action are objects'; Exit(False); end;
  Doc := TJSONObject.Create;
  for i := 0 to V.Count - 1 do
  begin
    Name := TJSONObject(V).Names[i];
    if (Name = '_id') or (Name = 'boardId') or (Name = 'createdAt') or (Name = 'modifiedAt') or (Name = 'updatedAt') then Continue;
    if not ValidFieldName(Name) then begin Error := 'a field of a trigger or an action is a plain name: ' + Name; FreeAndNil(Doc); Exit(False); end;
    if not ValidValue(V.Items[i], True, 0) then
    begin Error := 'the value of ' + Name + ' is text, a number, true or false, or a list of them'; FreeAndNil(Doc); Exit(False); end;
    Doc.Add(Name, V.Items[i].Clone);
  end;
  if Str(Doc, KindField) = '' then begin Error := KindField + ' is required'; FreeAndNil(Doc); Exit(False); end;
  Result := True;
end;

// WeKan's trigger matching fields, each unset one made "*".
procedure NormalizeTrigger(Trigger: TJSONObject);
var Fields: string; Parts: TStringArray; F: string; V: TJSONData;
begin
  case Str(Trigger, 'activityType') of
    'createCard': Fields := 'boardId,listName,userId,swimlaneName,cardTitle';
    'moveCard': Fields := 'boardId,listName,oldListName,userId,swimlaneName,cardTitle';
    'archivedCard', 'addComment', 'restoredCard': Fields := 'boardId,userId,cardTitle';
    'joinMember', 'unjoinMember', 'joinAssignee', 'unjoinAssignee': Fields := 'boardId,username,userId';
    'addChecklist', 'removeChecklist', 'completeChecklist', 'uncompleteChecklist': Fields := 'boardId,checklistName,userId';
    'addedChecklistItem', 'removedChecklistItem', 'checkedItem', 'uncheckedItem': Fields := 'boardId,checklistItemName,userId';
    'addedLabel', 'removedLabel': Fields := 'boardId,labelId,userId';
    'addAttachment', 'deleteAttachment', 'a-receivedAt', 'a-startAt', 'a-dueAt', 'a-endAt': Fields := 'boardId,userId';
  else Fields := '';
  end;
  if Fields = '' then Exit;
  Parts := Fields.Split([',']);
  for F in Parts do
  begin
    if F = 'boardId' then Continue;
    V := Trigger.Find(F);
    if (V = nil) or (V.JSONType = jtNull) or ((V.JSONType = jtString) and (V.AsString = '')) then
    begin
      Trigger.Delete(F);
      Trigger.Add(F, '*');
    end;
  end;
end;

procedure RecordRuleBleed(Db: TWLDb; const UserId, Source, Detail: string);
begin
  try
    RecordSecurityEvent(Db, UserId, 'RuleBleed', Source, 'authz', 'high', 'CWE-862', 'blocked', Detail);
  except
    // logging must never break the guard
  end;
end;

// RuleBleed (GHSA-9w4x-hf2r-hc9v): an action naming another board is kept
// only when its creator may change that board.
function DestinationOK(Db: TWLDb; const UserId, BoardId: string; Action: TJSONObject): Boolean;
var Dest: string;
begin
  Dest := Str(Action, 'boardId');
  Result := (Dest = '') or (Dest = BoardId) or ((Pos(#0, Dest) = 0) and BoardCanWrite(Db, UserId, Dest));
  if not Result then
    RecordRuleBleed(Db, UserId, 'rules.createRule', 'A rule''s action named a board its creator may not change.');
end;

function DateHints: string;
begin
  Result := '{"createdAt":"date","modifiedAt":"date","updatedAt":"date"}';
end;

// Weddy's insertRule: the trigger, the action and the rule, in one transaction.
function InsertRule(const T: TWLTenant; const BoardId, Title: string; Trigger, Action: TJSONObject; out Ids: string): Boolean;
var RuleId, TriggerId, ActionId, Sql: string; Rule: TJSONObject; Stamp: Int64;
begin
  Stamp := NowMs;
  NormalizeTrigger(Trigger);
  TriggerId := NewId; ActionId := NewId; RuleId := NewId;
  Trigger.Delete('_id'); Trigger.Add('_id', TriggerId);
  Trigger.Delete('boardId'); Trigger.Add('boardId', BoardId);
  Trigger.Add('createdAt', Stamp); Trigger.Add('updatedAt', Stamp);
  // #5536: an action's own board is its destination; without one, the rule's.
  if Str(Action, 'boardId') = '' then begin Action.Delete('boardId'); Action.Add('boardId', BoardId); end;
  Action.Delete('_id'); Action.Add('_id', ActionId);
  Action.Add('createdAt', Stamp); Action.Add('modifiedAt', Stamp);
  Rule := TJSONObject.Create(['_id', RuleId, 'title', Title, 'triggerId', TriggerId, 'actionId', ActionId,
    'boardId', BoardId, 'enabled', True, 'createdAt', Stamp, 'modifiedAt', Stamp]);
  try
    if Str(Trigger, 'activityType') = 'button' then
    begin
      if Str(Trigger, 'buttonType') = 'board' then Rule.Add('buttonType', 'board') else Rule.Add('buttonType', 'card');
      if Str(Trigger, 'buttonLabel') <> '' then Rule.Add('buttonLabel', Str(Trigger, 'buttonLabel'))
      else if Title <> '' then Rule.Add('buttonLabel', Title)
      else Rule.Add('buttonLabel', 'Rule');
    end;
    Sql := InsertDocSql(T.Db, 'triggers', Trigger, DateHints) + InsertDocSql(T.Db, 'actions', Action, DateHints) +
      InsertDocSql(T.Db, 'rules', Rule, DateHints);
  finally
    Rule.Free;
  end;
  Result := T.Db.Exec('BEGIN IMMEDIATE; ' + Sql + 'COMMIT;');
  if not Result then T.Db.Exec('ROLLBACK;');
  Ids := '{"_id":"' + RuleId + '","triggerId":"' + TriggerId + '","actionId":"' + ActionId + '"}';
end;

// Weddy's removeRule: the rule, and its trigger and action when no other rule
// shares them.
function RemoveRuleSql(Db: TWLDb; Rule: TJSONObject): string;
var Part, Field, Extra, Coll, Id: string; V: TJSONData; Ids: TStringArray; i: Integer; Others: TJSONArray; RuleId: string;
begin
  RuleId := Str(Rule, '_id');
  Result := DeleteDocSql(Db, 'rules', RuleId);
  for Part in ['trigger', 'action'] do
  begin
    Field := Part + 'Id'; Extra := 'extra' + UpperCase(Part[1]) + Copy(Part, 2, MaxInt) + 'Ids';
    if Part = 'trigger' then Coll := 'triggers' else Coll := 'actions';
    SetLength(Ids, 0);
    if Str(Rule, Field) <> '' then begin SetLength(Ids, 1); Ids[0] := Str(Rule, Field); end;
    V := Rule.Find(Extra);
    if V is TJSONArray then
      for i := 0 to V.Count - 1 do
        if V.Items[i].JSONType = jtString then
        begin SetLength(Ids, Length(Ids) + 1); Ids[High(Ids)] := V.Items[i].AsString; end;
    for Id in Ids do
    begin
      Others := FindDocs(Db, 'rules', DocField('_id') + '<>' + Q(RuleId) + ' AND (' + DocField(Field) + '=' + Q(Id) +
        ' OR EXISTS(SELECT 1 FROM json_each(_ferretdb_sjson,''$.' + Extra + ''') WHERE value=' + Q(Id) + '))', '');
      try
        if Others.Count = 0 then Result := Result + DeleteDocSql(Db, Coll, Id);
      finally
        Others.Free;
      end;
    end;
  end;
end;

// A rule of a board the user administers (Weddy's adminRule).
function AdminRule(Db: TWLDb; const UserId: string; Args: TJSONArray; out Rule: TJSONObject; out Code: Integer; out Answer: string): Boolean;
begin
  Rule := nil;
  Result := False;
  if (Args.Count < 1) or (Args.Items[0].JSONType <> jtString) then
  begin Code := MethodError(400, 'Match.Error', 'Expected a rule id', Answer); Exit; end;
  Rule := FindDoc(Db, 'rules', Args.Strings[0]);
  if Rule = nil then begin Code := MethodError(404, 'not-found', 'Rule not found', Answer); Exit; end;
  if not BoardCanAdmin(Db, UserId, Str(Rule, 'boardId')) then
  begin FreeAndNil(Rule); Code := MethodError(403, 'not-authorized', 'Must be a board admin', Answer); Exit; end;
  Result := True;
end;

// A document without its timestamps (WeKan's document()).
function Untimed(Doc: TJSONObject): TJSONData;
begin
  if Doc = nil then Exit(TJSONNull.Create);
  Result := Doc.Clone;
  TJSONObject(Result).Delete('createdAt');
  TJSONObject(Result).Delete('updatedAt');
  TJSONObject(Result).Delete('modifiedAt');
end;

function RuleSnapshot(Db: TWLDb; const RuleId: string): TJSONObject;
var Rule, Part: TJSONObject; V: TJSONData; Docs: TJSONArray; i: Integer; Key, Coll, Field: string;
begin
  Result := TJSONObject.Create;
  Rule := FindDoc(Db, 'rules', RuleId);
  if Rule = nil then begin Result.Add('rule', TJSONNull.Create); Exit; end;
  try
    Result.Add('rule', Untimed(Rule));
    Part := FindDoc(Db, 'triggers', Str(Rule, 'triggerId'));
    Result.Add('trigger', Untimed(Part)); Part.Free;
    Part := FindDoc(Db, 'actions', Str(Rule, 'actionId'));
    Result.Add('action', Untimed(Part)); Part.Free;
    for Key in ['extraTriggers', 'extraActions'] do
    begin
      if Key = 'extraTriggers' then begin Field := 'extraTriggerIds'; Coll := 'triggers'; end
      else begin Field := 'extraActionIds'; Coll := 'actions'; end;
      V := Rule.Find(Field);
      if not (V is TJSONArray) or (V.Count = 0) then Continue;
      Docs := TJSONArray.Create;
      for i := 0 to V.Count - 1 do
      begin
        if V.Items[i].JSONType = jtString then Part := FindDoc(Db, Coll, V.Items[i].AsString) else Part := nil;
        Docs.Add(Untimed(Part));
        Part.Free;
      end;
      Result.Add(Key, Docs);
    end;
  finally
    Rule.Free;
  end;
end;

procedure RecordRuleHistory(Db: TWLDb; const UserId: string; Before, After: TJSONObject);
var Rule: TJSONData; Kind: string;
begin
  if (UserId = '') or (Before = nil) or (After = nil) then Exit;
  if CanonicalHistoryValue(Before) = CanonicalHistoryValue(After) then Exit;
  AnnounceToAll;
  Rule := After.Find('rule');
  if not (Rule is TJSONObject) then Rule := Before.Find('rule');
  if not (Rule is TJSONObject) then Exit;
  Kind := 'edited';
  if not (Before.Find('rule') is TJSONObject) then Kind := 'added'
  else if not (After.Find('rule') is TJSONObject) then Kind := 'removed';
  try
    RecordHistoryRow(Db, UserId, Str(TJSONObject(Rule), 'boardId'), 'rule', Str(TJSONObject(Rule), '_id'), 'rules', Kind, Before, After);
  except
    // History never fails the write it records.
  end;
end;

function RunButton(const T: TWLTenant; const UserId: string; Args: TJSONArray; out Answer: string): Integer; forward;

function ImportWrike(const T: TWLTenant; const UserId: string; Args: TJSONArray; Words: TWLTranslator; out Answer: string): Integer; forward;

function RulesMethodBody(const T: TWLTenant; const UserId, Name: string; Args: TJSONArray; out Answer: string;
  Words: TWLTranslator): Integer; forward;

// Each write of a rule between two snapshots of it: one history row (WeKan's
// withRuleHistory) when it changed something.
function RulesMethod(const T: TWLTenant; const UserId, Name: string; Args: TJSONArray; out Answer: string;
  Words: TWLTranslator): Integer;
var RuleId: string; Before, After: TJSONObject; Reply: TJSONData;
begin
  if (Name <> 'rules.createRule') and (Name <> 'rules.updateRule') and (Name <> 'rules.deleteRule') and (Name <> 'rules.setEnabled') then
    Exit(RulesMethodBody(T, UserId, Name, Args, Answer, Words));
  RuleId := '';
  if (Name <> 'rules.createRule') and (Args.Count > 0) and (Args.Items[0].JSONType = jtString) then RuleId := Args.Strings[0];
  Before := nil; After := nil;
  try
    if RuleId <> '' then Before := RuleSnapshot(T.Db, RuleId)
    else Before := TJSONObject.Create(['rule', TJSONNull.Create]);
    Result := RulesMethodBody(T, UserId, Name, Args, Answer, Words);
    if Result <> 200 then Exit;
    if Name = 'rules.createRule' then
    begin
      Reply := nil;
      try
        Reply := GetJSON(Answer);
        if (Reply is TJSONObject) and (TJSONObject(Reply).Find('result') is TJSONObject) then
          RuleId := TJSONObject(TJSONObject(Reply).Find('result')).Get('_id', '');
      except
        RuleId := '';
      end;
      Reply.Free;
    end;
    if RuleId = '' then Exit;
    After := RuleSnapshot(T.Db, RuleId);
    RecordRuleHistory(T.Db, UserId, Before, After);
  finally
    Before.Free;
    After.Free;
  end;
end;

function RulesMethodBody(const T: TWLTenant; const UserId, Name: string; Args: TJSONArray; out Answer: string;
  Words: TWLTranslator): Integer;
var BoardId, Title, Error, Ids, Sql, TriggerId, ActionId: string; Trigger, Action, Rule, Fields: TJSONObject;
  Stamp: Int64;
  // The part (trigger or action) the rule's edit writes: in place when only
  // this rule names it, else a new one. Its SQL goes into Sql; its id is the result.
  function PartFor(const Part, Collection: string; Doc: TJSONObject; const CurrentId, Changed: string): string;
  var Others: TJSONArray; Old: TJSONObject; Extra: string; Shared: Boolean;
  begin
    Extra := 'extra' + UpperCase(Part[1]) + Copy(Part, 2, MaxInt) + 'Ids';
    Others := FindDocs(T.Db, 'rules', DocField('_id') + '<>' + Q(Str(Rule, '_id')) + ' AND (' + DocField(Part + 'Id') + '=' +
      Q(CurrentId) + ' OR EXISTS(SELECT 1 FROM json_each(_ferretdb_sjson,''$.' + Extra + ''') WHERE value=' + Q(CurrentId) + '))', '');
    try
      Shared := Others.Count > 0;
    finally
      Others.Free;
    end;
    Old := nil;
    if not Shared then Old := FindDoc(T.Db, Collection, CurrentId);
    try
      if Old = nil then Result := NewId else Result := CurrentId;
      Doc.Delete('_id'); Doc.Add('_id', Result);
      Doc.Delete('boardId');
      if (Part = 'action') and (Str(TJSONObject(Args.Items[3]), 'boardId') <> '') then Doc.Add('boardId', Str(TJSONObject(Args.Items[3]), 'boardId'))
      else Doc.Add('boardId', BoardId);
      Doc.Delete('createdAt'); Doc.Add('createdAt', Stamp);
      Doc.Delete(Changed); Doc.Add(Changed, Stamp);
      if Old <> nil then
      begin
        Sql := Sql + DeleteDocSql(T.Db, Collection, CurrentId);
      end;
      Sql := Sql + InsertDocSql(T.Db, Collection, Doc, DateHints);
    finally
      Old.Free;
    end;
  end;
begin
  Answer := '';
  if (Name <> 'rules.createRule') and (Name <> 'rules.updateRule') and (Name <> 'rules.deleteRule') and
    (Name <> 'rules.setEnabled') and (Name <> 'rules.runButton') and (Name <> 'rules.importWrikeWorkflow') then Exit(0);
  if not IsShared(T.Db) then Exit(MethodError(501, 'not-supported', 'Rules need the shared store', Answer));
  if Name = 'rules.runButton' then Exit(RunButton(T, UserId, Args, Answer));
  if Name = 'rules.importWrikeWorkflow' then Exit(ImportWrike(T, UserId, Args, Words, Answer));
  if Name = 'rules.deleteRule' then
  begin
    if not AdminRule(T.Db, UserId, Args, Rule, Result, Answer) then Exit;
    try
      Sql := RemoveRuleSql(T.Db, Rule);
    finally
      Rule.Free;
    end;
    if not T.Db.Exec('BEGIN IMMEDIATE; ' + Sql + 'COMMIT;') then
    begin T.Db.Exec('ROLLBACK;'); Exit(MethodError(500, 'internal-error', 'Could not delete the rule', Answer)); end;
    Answer := '{"result":true}';
    Exit(200);
  end;
  if Name = 'rules.setEnabled' then
  begin
    if not AdminRule(T.Db, UserId, Args, Rule, Result, Answer) then Exit;
    try
      if (Args.Count < 2) or (Args.Items[1].JSONType <> jtBoolean) then Exit(MethodError(400, 'Match.Error', 'Expected boolean', Answer));
      Fields := TJSONObject.Create(['enabled', Args.Booleans[1], 'modifiedAt', NowMs]);
      try
        Sql := UpdateDocSql(T.Db, 'rules', Str(Rule, '_id'), Fields, DateHints);
      finally
        Fields.Free;
      end;
    finally
      Rule.Free;
    end;
    if not T.Db.Exec('BEGIN IMMEDIATE; ' + Sql + 'COMMIT;') then
    begin T.Db.Exec('ROLLBACK;'); Exit(MethodError(500, 'internal-error', 'Could not change the rule', Answer)); end;
    Answer := '{"result":true}';
    Exit(200);
  end;
  // createRule(boardId, title, trigger, action) / updateRule(ruleId, title, trigger, action)
  if (Args.Count < 4) or (Args.Items[0].JSONType <> jtString) or not (Args.Items[2] is TJSONObject) or
    not (Args.Items[3] is TJSONObject) or not (Args.Items[1].JSONType in [jtString, jtNull]) then
    Exit(MethodError(400, 'Match.Error', 'Expected objects', Answer));
  Title := '';
  if Args.Items[1].JSONType = jtString then Title := Trim(Args.Strings[1]);
  Rule := nil;
  if Name = 'rules.updateRule' then
  begin
    if not AdminRule(T.Db, UserId, Args, Rule, Result, Answer) then Exit;
    BoardId := Str(Rule, 'boardId');
  end
  else
  begin
    BoardId := Args.Strings[0];
    if (Pos(#0, BoardId) > 0) or (Length(T.Db.Query('SELECT 1 FROM boards WHERE id=' + Q(BoardId) + ';')) <> 1) then
      Exit(MethodError(404, 'not-found', 'Board not found', Answer));
    if not BoardCanAdmin(T.Db, UserId, BoardId) then Exit(MethodError(403, 'not-authorized', 'Must be a board admin', Answer));
  end;
  Trigger := nil; Action := nil;
  try
    if not RuleComponent(Args.Items[2], 'activityType', Trigger, Error) then Exit(MethodError(400, 'Match.Error', Error, Answer));
    if not RuleComponent(Args.Items[3], 'actionType', Action, Error) then Exit(MethodError(400, 'Match.Error', Error, Answer));
    // #5536: the Rules page names an action's destination board.
    if (TJSONObject(Args.Items[3]).Find('boardId') <> nil) and (TJSONObject(Args.Items[3]).Find('boardId').JSONType = jtString) and
      (TJSONObject(Args.Items[3]).Strings['boardId'] <> '') then
      Action.Add('boardId', TJSONObject(Args.Items[3]).Strings['boardId']);
    if not DestinationOK(T.Db, UserId, BoardId, Action) then
      Exit(MethodError(403, 'not-authorized', 'Must have write access to the destination board', Answer));
    if Title = '' then
    begin
      Title := Trim(Str(Trigger, 'desc') + ' ' + Str(Action, 'desc'));
      if Title = '' then Title := 'Rule';
    end;
    if Name = 'rules.createRule' then
    begin
      if not InsertRule(T, BoardId, Title, Trigger, Action, Ids) then
        Exit(MethodError(500, 'internal-error', 'Could not create the rule', Answer));
      Answer := '{"result":' + Ids + '}';
      Exit(200);
    end;
    // updateRule: the rule's trigger and action are changed where they are,
    // keeping their ids, as WeKan's; one another rule shares is left as it
    // is and this rule gets a copy of its own - an edit never changes
    // another rule.
    Stamp := NowMs;
    NormalizeTrigger(Trigger);
    Sql := '';
    TriggerId := PartFor('trigger', 'triggers', Trigger, Str(Rule, 'triggerId'), 'updatedAt');
    ActionId := PartFor('action', 'actions', Action, Str(Rule, 'actionId'), 'modifiedAt');
    Fields := TJSONObject.Create(['triggerId', TriggerId, 'actionId', ActionId, 'title', Title, 'modifiedAt', Stamp]);
    try
      if Str(Trigger, 'activityType') = 'button' then
      begin
        if Str(Trigger, 'buttonType') = 'board' then Fields.Add('buttonType', 'board') else Fields.Add('buttonType', 'card');
        if Str(Trigger, 'buttonLabel') <> '' then Fields.Add('buttonLabel', Str(Trigger, 'buttonLabel'))
        else Fields.Add('buttonLabel', Title);
      end
      else
      begin
        // WeKan's ruleButtonMetadata: no button, no button fields.
        Fields.Add('buttonType', TJSONNull.Create);
        Fields.Add('buttonLabel', TJSONNull.Create);
      end;
      Sql := Sql + UpdateDocSql(T.Db, 'rules', Str(Rule, '_id'), Fields, DateHints);
    finally
      Fields.Free;
    end;
    if not T.Db.Exec('BEGIN IMMEDIATE; ' + Sql + 'COMMIT;') then
    begin T.Db.Exec('ROLLBACK;'); Exit(MethodError(500, 'internal-error', 'Could not change the rule', Answer)); end;
    Answer := '{"result":true}';
    Result := 200;
  finally
    Trigger.Free; Action.Free; Rule.Free;
  end;
end;

// ---- the engine -------------------------------------------------------------------

type
  TActivity = record
    Id, Kind, UserId, BoardId, CardId, ListId, SwimlaneId: string;
    Data: TJSONObject;
  end;

function DataStr(const A: TActivity; const Name: string): string;
begin
  Result := Str(A.Data, Name);
end;

function TitleOf(Db: TWLDb; const Table, Id: string): string;
var R: TWLRows;
begin
  Result := '';
  if Id = '' then Exit;
  R := Db.Query('SELECT COALESCE(title,'''') FROM ' + Table + ' WHERE id=' + Q(Id) + ';');
  if Length(R) = 1 then Result := R[0][0];
end;

function UsernameOf(Db: TWLDb; const Id: string): string;
var R: TWLRows;
begin
  Result := '';
  if Id = '' then Exit;
  R := Db.Query('SELECT COALESCE(username,'''') FROM users WHERE id=' + Q(Id) + ';');
  if Length(R) = 1 then Result := R[0][0];
end;

// WeKan's cardTitleMatchList: "*", unset, the whole title or one of its words.
function CardTitleMatches(const Want, Title: string): Boolean;
var i, Start: Integer; W: string;
begin
  if (Want = '*') or (Want = Title) then Exit(True);
  if Want = '' then Exit(False);
  Start := 1;
  for i := 1 to Length(Title) + 1 do
    if (i > Length(Title)) or not (Title[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', #$80..#$FF]) then
    begin
      W := Copy(Title, Start, i - Start);
      if W = Want then Exit(True);
      Start := i + 1;
    end;
  Result := False;
end;

// What a trigger field is for this activity (WeKan's buildMatchingFieldsMap).
function ActivityValue(Db: TWLDb; const A: TActivity; const Field: string): string;
begin
  Result := DataStr(A, Field);
  if Result <> '' then Exit;
  case Field of
    'userId': Result := A.UserId;
    'listName': Result := TitleOf(Db, 'lists', A.ListId);
    'oldListName': Result := TitleOf(Db, 'lists', DataStr(A, 'oldListId'));
    'swimlaneName': Result := TitleOf(Db, 'swimlanes', A.SwimlaneId);
    'cardTitle': Result := TitleOf(Db, 'cards', A.CardId);
    'checklistName': Result := TitleOf(Db, 'checklists', DataStr(A, 'checklistId'));
    'checklistItemName': Result := TitleOf(Db, 'checklist_items', DataStr(A, 'checklistItemId'));
    'labelId': Result := DataStr(A, 'labelId');
    'username':
      begin
        Result := DataStr(A, 'memberId');
        if Result = '' then Result := DataStr(A, 'assigneeId');
        Result := UsernameOf(Db, Result);
      end;
  end;
end;

// The trigger fields of an activity type that a trigger may narrow.
function MatchFields(const Kind: string): TStringArray;
begin
  case Kind of
    'createCard': Result := TStringArray.Create('listName', 'userId', 'swimlaneName', 'cardTitle');
    'moveCard': Result := TStringArray.Create('listName', 'oldListName', 'userId', 'swimlaneName', 'cardTitle');
    'archivedCard', 'addComment', 'restoredCard': Result := TStringArray.Create('userId', 'cardTitle');
    'joinMember', 'unjoinMember', 'joinAssignee', 'unjoinAssignee': Result := TStringArray.Create('username', 'userId');
    'addChecklist', 'removeChecklist', 'completeChecklist', 'uncompleteChecklist':
      Result := TStringArray.Create('checklistName', 'userId');
    'addedChecklistItem', 'removedChecklistItem', 'checkedItem', 'uncheckedItem':
      Result := TStringArray.Create('checklistItemName', 'userId');
    'addedLabel', 'removedLabel': Result := TStringArray.Create('labelId', 'userId');
    'addAttachment', 'deleteAttachment', 'a-receivedAt', 'a-startAt', 'a-dueAt', 'a-endAt': Result := TStringArray.Create('userId');
  else SetLength(Result, 0);
  end;
end;

function TriggerMatches(Db: TWLDb; const A: TActivity; Trigger: TJSONObject; const Fields: TStringArray): Boolean;
var F, Want, Actual: string; V: TJSONData;
begin
  V := Trigger.Find('boardId');
  if (V <> nil) and (V.JSONType = jtString) and (V.AsString <> '*') and (V.AsString <> A.BoardId) then Exit(False);
  for F in Fields do
  begin
    V := Trigger.Find(F);
    if (V = nil) or (V.JSONType = jtNull) then Continue;
    if V.JSONType <> jtString then Exit(False);
    Want := V.AsString;
    if Want = '*' then Continue;
    Actual := ActivityValue(Db, A, F);
    if F = 'cardTitle' then
    begin
      if not CardTitleMatches(Want, Actual) then Exit(False);
      Continue;
    end;
    // A trigger names a member by username; the activity its actor by id.
    if (F = 'userId') and (Want <> Actual) and (Want = UsernameOf(Db, Actual)) then Continue;
    if Want <> Actual then Exit(False);
  end;
  Result := True;
end;

// WeKan's textContainsMatch: a case-insensitive substring; empty never matches.
function TextContains(const Text, Needle: string): Boolean;
begin
  Result := (Trim(Needle) <> '') and (Text <> '') and
    (Pos(Utf8Lower(Needle), Utf8Lower(Text)) > 0);
end;

// #2076: forward to a later list in the board's list order, back to an earlier.
function MoveDirection(Db: TWLDb; const OldList, NewList: string): string;
var R: TWLRows; A, B: Double;
begin
  Result := '';
  R := Db.Query('SELECT o.sort,n.sort FROM lists o, lists n WHERE o.id=' + Q(OldList) + ' AND n.id=' + Q(NewList) +
    ' AND o.boardId=n.boardId;');
  if (Length(R) <> 1) or (R[0][0] = '') or (R[0][1] = '') then Exit;
  A := StrToFloatDef(R[0][0], NaN, DefaultFormatSettings);
  B := StrToFloatDef(R[0][1], NaN, DefaultFormatSettings);
  if IsNan(A) or IsNan(B) or (A = B) then Exit;
  if B > A then Result := 'forward' else Result := 'back';
end;

// The enabled rules of the activity's own board one of whose triggers it matches.
function MatchingRules(Db: TWLDb; const A: TActivity): TJSONArray;
var Triggers, Found: TJSONArray; Fields: TStringArray; i: Integer; Seen: TStringList; Trig, Rule: TJSONObject;
  Card: TWLRows; Direction: string; Matched: Boolean; V: TJSONData; Matches: TStringArray;
  procedure AddRules(const TriggerId: string);
  var j: Integer;
  begin
    Found := FindDocs(Db, 'rules', DocField('boardId') + '=' + Q(A.BoardId) + ' AND (' + DocField('triggerId') + '=' + Q(TriggerId) +
      ' OR EXISTS(SELECT 1 FROM json_each(_ferretdb_sjson,''$.extraTriggerIds'') WHERE value=' + Q(TriggerId) + '))',
      DocField('createdAt') + ',' + DocField('_id'));
    try
      for j := 0 to Found.Count - 1 do
      begin
        Rule := Found.Objects[j];
        V := Rule.Find('enabled');
        if (V <> nil) and (V.JSONType = jtBoolean) and not V.AsBoolean then Continue;
        if Seen.IndexOf(Str(Rule, '_id')) >= 0 then Continue;
        Seen.Add(Str(Rule, '_id'));
        Result.Add(Rule.Clone);
      end;
    finally
      Found.Free;
    end;
  end;
begin
  Result := TJSONArray.Create;
  if A.BoardId = '' then Exit;
  Seen := TStringList.Create;
  try
    Fields := MatchFields(A.Kind);
    if Length(Fields) > 0 then
    begin
      Triggers := FindDocs(Db, 'triggers', DocField('activityType') + '=' + Q(A.Kind) + ' AND (' + DocField('boardId') + '=' + Q(A.BoardId) +
        ' OR ' + DocField('boardId') + '=''*'' OR ' + DocField('boardId') + ' IS NULL)', DocField('_id'));
      try
        for i := 0 to Triggers.Count - 1 do
          if TriggerMatches(Db, A, Triggers.Objects[i], Fields) then AddRules(Str(Triggers.Objects[i], '_id'));
      finally
        Triggers.Free;
      end;
    end;
    if A.CardId <> '' then Card := Db.Query('SELECT COALESCE(title,''''),COALESCE(description,'''') FROM cards WHERE id=' + Q(A.CardId) +
      ' AND boardId=' + Q(A.BoardId) + ';')
    else SetLength(Card, 0);
    // #2076: moved forward or back.
    if (A.Kind = 'moveCard') and (DataStr(A, 'oldListId') <> '') and (A.ListId <> '') and (DataStr(A, 'oldListId') <> A.ListId) then
    begin
      Direction := MoveDirection(Db, DataStr(A, 'oldListId'), A.ListId);
      if Direction <> '' then
      begin
        Triggers := FindDocs(Db, 'triggers', DocField('activityType') + '=''moveCardDirection'' AND ' + DocField('boardId') + '=' +
          Q(A.BoardId), DocField('_id'));
        try
          for i := 0 to Triggers.Count - 1 do
          begin
            Trig := Triggers.Objects[i];
            if Str(Trig, 'direction') <> Direction then Continue;
            if (Str(Trig, 'cardTitle') <> '') and (Length(Card) = 1) and not CardTitleMatches(Str(Trig, 'cardTitle'), Card[0][0]) then Continue;
            AddRules(Str(Trig, '_id'));
          end;
        finally
          Triggers.Free;
        end;
      end;
    end;
    // #3092: the card matches the advanced filter - the Filter sidebar's own
    // language, against the card's current state, on any card activity. A
    // filter that does not parse, or names a field the board has not, never
    // matches.
    if (A.CardId <> '') and (Length(Card) = 1) then
    begin
      Triggers := FindDocs(Db, 'triggers', DocField('activityType') + '=''advancedFilterTrigger'' AND ' + DocField('boardId') + '=' +
        Q(A.BoardId), DocField('_id'));
      try
        for i := 0 to Triggers.Count - 1 do
          if AdvancedFilterCards(Db, A.BoardId, Str(Triggers.Objects[i], 'advancedFilter'), Matches) and
            (IndexStr(A.CardId, Matches) >= 0) then AddRules(Str(Triggers.Objects[i], '_id'));
      finally
        Triggers.Free;
      end;
    end;
    // #2194: the card's title or description contains a text.
    if ((A.Kind = 'createCard') or (A.Kind = 'a-changedTitle') or (A.Kind = 'a-changedDescription')) and (Length(Card) = 1) then
    begin
      Triggers := FindDocs(Db, 'triggers', DocField('activityType') + '=''textContainsTrigger'' AND ' + DocField('boardId') + '=' +
        Q(A.BoardId), DocField('_id'));
      try
        for i := 0 to Triggers.Count - 1 do
        begin
          Matched := TextContains(Card[0][0], Str(Triggers.Objects[i], 'textContains')) or
            TextContains(Card[0][1], Str(Triggers.Objects[i], 'textContains'));
          if Matched then AddRules(Str(Triggers.Objects[i], '_id'));
        end;
      finally
        Triggers.Free;
      end;
    end;
  finally
    Seen.Free;
  end;
end;

// WeKan's rule variables: what an action's text may name.
function RuleVars(Db: TWLDb; const A: TActivity): TStringList;
var R: TWLRows; Member: string;
  function Names(const Sql: string): string;
  var N: TWLRows; i: Integer;
  begin
    Result := '';
    N := Db.Query(Sql);
    for i := 0 to High(N) do
      if N[i][0] <> '' then
      begin
        if Result <> '' then Result := Result + ', ';
        Result := Result + N[i][0];
      end;
  end;
begin
  Result := TStringList.Create;
  Result.Values['date'] := FormatDateTime('yyyy-mm-dd', Now);
  Result.Values['time'] := FormatDateTime('hh:nn:ss', Now);
  Result.Values['datetime'] := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
  Result.Values['boardname'] := TitleOf(Db, 'boards', A.BoardId);
  Result.Values['board'] := Result.Values['boardname'];
  Result.Values['username'] := UsernameOf(Db, A.UserId);
  Result.Values['user'] := Result.Values['username'];
  Member := DataStr(A, 'memberId');
  if Member = '' then Member := A.UserId;
  Result.Values['membername'] := UsernameOf(Db, Member);
  Result.Values['member'] := Result.Values['membername'];
  if A.CardId = '' then Exit;
  R := Db.Query('SELECT COALESCE(title,''''),COALESCE(description,''''),COALESCE(cardNumber,0),COALESCE(listId,''''),' +
    'COALESCE(swimlaneId,''''),COALESCE(userId,'''') FROM cards WHERE id=' + Q(A.CardId) + ';');
  if Length(R) <> 1 then Exit;
  Result.Values['cardname'] := R[0][0]; Result.Values['cardtitle'] := R[0][0]; Result.Values['card'] := R[0][0];
  Result.Values['description'] := R[0][1];
  Result.Values['cardnumber'] := R[0][2];
  Result.Values['listname'] := TitleOf(Db, 'lists', R[0][3]); Result.Values['list'] := Result.Values['listname'];
  Result.Values['swimlanename'] := TitleOf(Db, 'swimlanes', R[0][4]);
  Result.Values['creator'] := UsernameOf(Db, R[0][5]);
  Result.Values['assignees'] := Names('SELECT u.username FROM card_assignees a JOIN users u ON u.id=a.userId WHERE a.cardId=' +
    Q(A.CardId) + ' ORDER BY u.username;');
  Result.Values['members'] := Names('SELECT u.username FROM card_members m JOIN users u ON u.id=m.userId WHERE m.cardId=' +
    Q(A.CardId) + ' ORDER BY u.username;');
end;

// {name} becomes the variable; an unknown one stays as it is.
function SubstituteVars(const Text: string; Vars: TStringList): string;
var i, Close: Integer; Name: string;
begin
  Result := '';
  i := 1;
  while i <= Length(Text) do
  begin
    if Text[i] = '{' then
    begin
      Close := Pos('}', Copy(Text, i + 1, MaxInt));
      if Close > 0 then
      begin
        Name := LowerCase(Copy(Text, i + 1, Close - 1));
        if (Name <> '') and (Pos('{', Name) = 0) and (Vars.IndexOfName(Name) >= 0) then
        begin
          Result := Result + Vars.Values[Name];
          i := i + Close + 1;
          Continue;
        end;
      end;
    end;
    Result := Result + Text[i];
    Inc(i);
  end;
end;

// The activity of a rule's change to a card, where the card is - or, for a
// move, at Place ('list','swimlane' quoted), where it goes.
function ActivitySql(const Kind, UserId, CardId, Extra: string; const Place: string = 'listId,swimlaneId'): string;
var Stamp: string;
begin
  Stamp := Q(NowIso);
  Result := 'INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) ' +
    'SELECT ' + Q(NewId) + ',' + Q(Kind) + ',' + Q(UserId) + ',boardId,id,' + Place + ',' + Stamp + ',' + Stamp +
    ',json_patch(json_object(''cardTitle'',title),' + Q(Extra) + ') FROM cards WHERE id=' + Q(CardId) + '; ';
end;

// The users an action's username names: the acting user, or usernames - a
// {token} naming several, comma-separated.
function RuleUsers(Db: TWLDb; const A: TActivity; const Value: string; Vars: TStringList): TStringArray;
var Names: TStringArray; N: string; R: TWLRows;
begin
  Result := nil;
  if Value = '_actinguser_' then
  begin
    if A.UserId <> '' then Result := TStringArray.Create(A.UserId);
    Exit;
  end;
  if Pos('{', Value) > 0 then Names := SubstituteVars(Value, Vars).Split([','])
  else Names := TStringArray.Create(Value);
  for N in Names do
  begin
    if (Trim(N) = '') or (Pos('{', N) > 0) then Continue;
    R := Db.Query('SELECT id FROM users WHERE username=' + Q(Trim(N)) + ';');
    if Length(R) = 1 then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := R[0][0];
    end;
  end;
end;

procedure RecordRuleCanary(Db: TWLDb; const UserId: string);
begin
  RecordRuleBleed(Db, UserId, 'canary:rule.cross-board-write', 'A rule action named a board its user may not change.');
end;

// moveCardToTop / moveCardToBottom: to a list (named, or the card's own) of
// the action's board, in its swimlane (named, the card's own, or the first).
procedure RuleMoveCard(Db: TWLDb; const A: TActivity; Act: TJSONObject; Vars: TStringList);
var Card, R: TWLRows; ToBoard, ListName, ListId, LaneName, LaneId, Sort: string;
begin
  Card := Db.Query('SELECT boardId,listId,swimlaneId,sort FROM cards WHERE id=' + Q(A.CardId) + ';');
  if Length(Card) <> 1 then Exit;
  ToBoard := Str(Act, 'boardId');
  if ToBoard = '' then ToBoard := Card[0][0];
  if ToBoard <> Card[0][0] then
  begin
    // A move to another board is the HTML4 view's (MoveViewCard); a rule's
    // stays on its board, and one naming a board its user may not change is
    // refused as RuleBleed's canary.
    if not BoardCanWrite(Db, A.UserId, ToBoard) then begin RecordRuleCanary(Db, A.UserId); Exit; end;
    ToBoard := Card[0][0];
  end;
  ListName := Str(Act, 'listName');
  if (ListName = '') or (ListName = '*') then ListId := Card[0][1]
  else
  begin
    R := Db.Query('SELECT id FROM lists WHERE boardId=' + Q(ToBoard) + ' AND title=' + Q(SubstituteVars(ListName, Vars)) +
      ' AND archived=0 AND deletedAt IS NULL ORDER BY sort LIMIT 1;');
    if Length(R) = 1 then ListId := R[0][0] else ListId := Card[0][1]; // #6472: else the card's own list
  end;
  LaneName := Str(Act, 'swimlaneName');
  LaneId := '';
  if (LaneName = '') or (LaneName = '*') then LaneId := Card[0][2]
  else
  begin
    R := Db.Query('SELECT id FROM swimlanes WHERE boardId=' + Q(ToBoard) + ' AND title=' + Q(SubstituteVars(LaneName, Vars)) +
      ' AND archived=0 ORDER BY sort LIMIT 1;');
    if Length(R) = 1 then LaneId := R[0][0];
  end;
  if LaneId = '' then
  begin
    R := Db.Query('SELECT id FROM swimlanes WHERE boardId=' + Q(ToBoard) + ' AND archived=0 ORDER BY sort LIMIT 1;');
    if Length(R) = 1 then LaneId := R[0][0] else LaneId := Card[0][2];
  end;
  if Str(Act, 'actionType') = 'moveCardToTop' then
    Sort := '(SELECT COALESCE(min(sort),0)-1 FROM cards WHERE listId=' + Q(ListId) + ' AND swimlaneId=' + Q(LaneId) +
      ' AND archived=0 AND id<>' + Q(A.CardId) + ')'
  else
    Sort := '(SELECT COALESCE(max(sort),0)+1 FROM cards WHERE listId=' + Q(ListId) + ' AND swimlaneId=' + Q(LaneId) +
      ' AND archived=0 AND id<>' + Q(A.CardId) + ')';
  if (ListId = Card[0][1]) and (LaneId = Card[0][2]) then
    Db.Exec('UPDATE cards SET sort=' + Sort + ',modifiedAt=' + Q(NowIso) + ' WHERE id=' + Q(A.CardId) + ';')
  else
    Db.Exec('BEGIN IMMEDIATE; ' + ActivitySql('moveCard', A.UserId, A.CardId,
      '{"oldListId":"' + StringToJSONString(Card[0][1]) + '","oldSwimlaneId":"' + StringToJSONString(Card[0][2]) + '"}',
      Q(ListId) + ',' + Q(LaneId)) + 'UPDATE cards SET listId=' + Q(ListId) + ',swimlaneId=' + Q(LaneId) + ',sort=' + Sort +
      ',modifiedAt=' + Q(NowIso) + ' WHERE id=' + Q(A.CardId) + '; COMMIT;');
end;

function DateField(const F: string): Boolean;
begin
  Result := (F = 'startAt') or (F = 'endAt') or (F = 'dueAt') or (F = 'receivedAt');
end;

// WeKan's relativeDateOffset: now moved by whole units.
function RelativeDate(Act: TJSONObject): string;
var V: TJSONData; Amount: Integer; Base: TDateTime; S: string;
begin
  V := Act.Find('days');
  Amount := 0;
  if V <> nil then
    case V.JSONType of
      jtNumber: Amount := Trunc(V.AsFloat);
      jtString:
        begin
          S := Trim(V.AsString);
          while (S <> '') and not (S[Length(S)] in ['0'..'9']) do Delete(S, Length(S), 1);
          Amount := StrToIntDef(S, 0);
        end;
    end;
  Base := LocalTimeToUniversal(Now);
  case Str(Act, 'unit') of
    'minutes': Base := IncMinute(Base, Amount);
    'hours': Base := IncHour(Base, Amount);
    'weeks': Base := IncWeek(Base, Amount);
    'months': Base := IncMonth(Base, Amount);
  else Base := IncDay(Base, Amount);
  end;
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Base);
end;

// One action of a rule, on the activity's card, as the activity's user.
// The copy actions that made each card of this run (WeKan's copy chain): a
// card made by a copy action is never copied by that action again, so a rule
// "when a card is added, copy it" copies each new card once.
threadvar
  CopyChain: TStringList;

procedure RuleCopyCard(const T: TWLTenant; const A: TActivity; Act: TJSONObject);
var Key, Chain, Dest, NewCard, Error: string;
begin
  Key := Str(Act, '_id');
  if Key = '' then Key := Str(Act, 'boardId') + '/' + Str(Act, 'listId') + '/' + Str(Act, 'swimlaneId');
  Chain := '';
  if CopyChain <> nil then Chain := CopyChain.Values[A.CardId];
  if Pos('|' + Key + '|', Chain) > 0 then Exit;
  Dest := Str(Act, 'boardId');
  if Dest = '' then Dest := A.BoardId;
  // RuleBleed: a stored action naming a board its user may no longer change.
  if (Dest <> A.BoardId) and not BoardCanWrite(T.Db, A.UserId, Dest) then
  begin
    RecordRuleCanary(T.Db, A.UserId);
    Exit;
  end;
  // A stored action's list and swimlane are the destination board's own, not
  // archived: an action edited to name another board's list copies nothing.
  if (Length(T.Db.Query('SELECT 1 FROM lists WHERE id=' + Q(Str(Act, 'listId')) + ' AND boardId=' + Q(Dest) +
    ' AND archived=0 AND deletedAt IS NULL;')) <> 1) or
    (Length(T.Db.Query('SELECT 1 FROM swimlanes WHERE id=' + Q(Str(Act, 'swimlaneId')) + ' AND boardId=' + Q(Dest) +
    ' AND archived=0;')) <> 1) then Exit;
  // CopyViewCard checks the rest: both boards writable, the card on its own.
  if CopyViewCard(T, A.UserId, A.BoardId, A.CardId, Dest, Str(Act, 'swimlaneId'), Str(Act, 'listId'), '', NewCard, Error) <> 200 then Exit;
  if NewCard = '' then Exit;
  if CopyChain = nil then CopyChain := TStringList.Create;
  if Chain = '' then Chain := '|';
  CopyChain.Values[NewCard] := Chain + Key + '|';
end;

// sortList: the cards of a list - named, or the card's own - in the card's
// swimlane, ordered by name, created, modified or (the default) due date.
procedure RuleSortList(Db: TWLDb; const A: TActivity; Act: TJSONObject);
var Card, R, L: TWLRows; ListId, Order, Sql: string; i: Integer;
begin
  Card := Db.Query('SELECT boardId,listId,swimlaneId FROM cards WHERE id=' + Q(A.CardId) + ';');
  if Length(Card) <> 1 then Exit;
  ListId := Card[0][1];
  if (Str(Act, 'listName') <> '') and (Str(Act, 'listName') <> '*') then
  begin
    L := Db.Query('SELECT id FROM lists WHERE boardId=' + Q(Card[0][0]) + ' AND title=' + Q(Str(Act, 'listName')) + ' LIMIT 1;');
    if Length(L) <> 1 then Exit;
    ListId := L[0][0];
  end;
  case Str(Act, 'sortField') of
    'name': Order := 'lower(title)';
    'created': Order := 'createdAt';
    'modified': Order := 'modifiedAt';
  else Order := 'dueAt IS NULL, dueAt';
  end;
  R := Db.Query('SELECT id FROM cards WHERE listId=' + Q(ListId) + ' AND swimlaneId=' + Q(Card[0][2]) +
    ' AND archived=0 AND deletedAt IS NULL ORDER BY ' + Order + ', sort;');
  Sql := '';
  for i := 0 to High(R) do Sql := Sql + 'UPDATE cards SET sort=' + IntToStr(i) + ' WHERE id=' + Q(R[i][0]) + '; ';
  if (Sql <> '') and not Db.Exec('BEGIN IMMEDIATE; ' + Sql + 'COMMIT;') then Db.Exec('ROLLBACK;');
end;

// linkCard: a linked card of this one in a list (by name) and swimlane (by
// name, else the first) of a board its user may change (RuleBleed's canary
// otherwise).
procedure RuleLinkCard(Db: TWLDb; const A: TActivity; Act: TJSONObject);
var Dest, ListId, LaneId, Source, NewCard: string; R: TWLRows;
begin
  Dest := Str(Act, 'boardId');
  if Dest = '' then Dest := A.BoardId;
  if (Pos(#0, Dest) > 0) or not BoardCanWrite(Db, A.UserId, Dest) then begin RecordRuleCanary(Db, A.UserId); Exit; end;
  R := Db.Query('SELECT id FROM lists WHERE boardId=' + Q(Dest) + ' AND title=' + Q(Str(Act, 'listName')) +
    ' AND archived=0 AND deletedAt IS NULL ORDER BY sort LIMIT 1;');
  if Length(R) <> 1 then Exit;
  ListId := R[0][0];
  R := Db.Query('SELECT id FROM swimlanes WHERE boardId=' + Q(Dest) + ' AND title=' + Q(Str(Act, 'swimlaneName')) + ' AND archived=0 LIMIT 1;');
  if Length(R) <> 1 then R := Db.Query('SELECT id FROM swimlanes WHERE boardId=' + Q(Dest) + ' AND archived=0 ORDER BY sort LIMIT 1;');
  if Length(R) <> 1 then Exit;
  LaneId := R[0][0];
  R := Db.Query('SELECT COALESCE(NULLIF(linkedId,''''),id),title FROM cards WHERE id=' + Q(A.CardId) + ' AND deletedAt IS NULL;');
  if Length(R) <> 1 then Exit;
  Source := R[0][0];
  NewCard := NewId;
  if not Db.Exec('BEGIN IMMEDIATE; ' + CardCreateSql(Dest, ListId, LaneId, NewCard, A.UserId, R[0][1], '', 'NULL',
    '(SELECT COALESCE(max(sort),-1)+1 FROM cards WHERE listId=' + Q(ListId) + ' AND swimlaneId=' + Q(LaneId) + ')', Source) + 'COMMIT;') then
    Db.Exec('ROLLBACK;');
end;

// createCard: a card named by the action (its {variables} filled) in a list
// of the rule's board - named, or the triggering card's own - in a swimlane
// named, the card's own, or the board's first.
procedure RuleCreateCard(Db: TWLDb; const A: TActivity; Act: TJSONObject; Vars: TStringList);
var Title, ListId, LaneId, Name: string; R, Card: TWLRows;
begin
  Title := Trim(SubstituteVars(Str(Act, 'cardName'), Vars));
  if (Title = '') or (A.UserId = '') then Exit;
  Card := nil;
  if A.CardId <> '' then Card := Db.Query('SELECT listId,swimlaneId FROM cards WHERE id=' + Q(A.CardId) + ' AND boardId=' + Q(A.BoardId) + ';');
  Name := Str(Act, 'listName');
  if (Name <> '') and (Name <> '*') then
  begin
    R := Db.Query('SELECT id FROM lists WHERE boardId=' + Q(A.BoardId) + ' AND title=' + Q(SubstituteVars(Name, Vars)) +
      ' AND archived=0 AND deletedAt IS NULL ORDER BY sort LIMIT 1;');
    if Length(R) <> 1 then Exit;
    ListId := R[0][0];
  end
  else if Length(Card) = 1 then ListId := Card[0][0]
  else Exit;
  LaneId := '';
  Name := Str(Act, 'swimlaneName');
  if (Name <> '') and (Name <> '*') then
  begin
    R := Db.Query('SELECT id FROM swimlanes WHERE boardId=' + Q(A.BoardId) + ' AND title=' + Q(SubstituteVars(Name, Vars)) +
      ' AND archived=0 LIMIT 1;');
    if Length(R) = 1 then LaneId := R[0][0];
  end
  else if Length(Card) = 1 then LaneId := Card[0][1];
  if LaneId = '' then
  begin
    R := Db.Query('SELECT id FROM swimlanes WHERE boardId=' + Q(A.BoardId) + ' AND archived=0 ORDER BY sort LIMIT 1;');
    if Length(R) <> 1 then Exit;
    LaneId := R[0][0];
  end;
  if not Db.Exec('BEGIN IMMEDIATE; ' + CardCreateSql(A.BoardId, ListId, LaneId, NewId, A.UserId, Title, '', 'NULL',
    '(SELECT COALESCE(max(sort),-1)+1 FROM cards WHERE listId=' + Q(ListId) + ' AND swimlaneId=' + Q(LaneId) + ')') + 'COMMIT;') then
    Db.Exec('ROLLBACK;');
end;

procedure PerformAction(const T: TWLTenant; const A: TActivity; Act: TJSONObject);
var Db: TWLDb; Kind, Field, Text, Id, Checklist, Scope, Stamp, Table, JoinKind, Key: string; Vars: TStringList;
  Card, R: TWLRows; Users: TStringArray; U: string; i: Integer; Items: TStringArray; Remove: Boolean;
begin
  Db := T.Db;
  Kind := Str(Act, 'actionType');
  if (A.BoardId = '') or not BoardCanWrite(Db, A.UserId, A.BoardId) then Exit;
  Card := Db.Query('SELECT boardId,archived,listId FROM cards WHERE id=' + Q(A.CardId) + ' AND deletedAt IS NULL;');
  if (Length(Card) <> 1) and (Kind <> 'addSwimlane') then Exit;
  Vars := RuleVars(Db, A);
  try
    Scope := ' WHERE id=' + Q(A.CardId) + ';';
    Stamp := Q(NowIso);
    case Kind of
      'moveCardToTop', 'moveCardToBottom': RuleMoveCard(Db, A, Act, Vars);
      'copyCard': RuleCopyCard(T, A, Act);
      'sortList': RuleSortList(Db, A, Act);
      'linkCard': RuleLinkCard(Db, A, Act);
      'createCard': RuleCreateCard(Db, A, Act, Vars);
      'archive':
        if Card[0][1] = '0' then
          Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET archived=1,archivedAt=' + Stamp + ',modifiedAt=' + Stamp + Scope +
            ActivitySql('archivedCard', A.UserId, A.CardId, '{}') + 'COMMIT;');
      'unarchive':
        if Card[0][1] <> '0' then
          Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET archived=0,archivedAt=NULL,modifiedAt=' + Stamp + Scope +
            ActivitySql('restoredCard', A.UserId, A.CardId, '{}') + 'COMMIT;');
      'setColor':
        Db.Exec('UPDATE cards SET color=' + Q(Str(Act, 'selectedColor')) + ',modifiedAt=' + Stamp + Scope);
      'addLabel', 'removeLabel':
        begin
          Id := Str(Act, 'labelId');
          if (Id = '') or (Length(Db.Query('SELECT 1 FROM board_labels WHERE boardId=' + Q(Card[0][0]) + ' AND id=' + Q(Id) + ';')) <> 1) then Exit;
          R := Db.Query('SELECT 1 FROM card_labels WHERE cardId=' + Q(A.CardId) + ' AND labelId=' + Q(Id) + ';');
          if (Kind = 'addLabel') and (Length(R) = 0) then
            Db.Exec('BEGIN IMMEDIATE; INSERT INTO card_labels(cardId,labelId) VALUES(' + Q(A.CardId) + ',' + Q(Id) + '); ' +
              ActivitySql('addedLabel', A.UserId, A.CardId, '{"labelId":"' + StringToJSONString(Id) + '"}') + 'COMMIT;');
          if (Kind = 'removeLabel') and (Length(R) = 1) then
            Db.Exec('BEGIN IMMEDIATE; DELETE FROM card_labels WHERE cardId=' + Q(A.CardId) + ' AND labelId=' + Q(Id) + '; ' +
              ActivitySql('removedLabel', A.UserId, A.CardId, '{"labelId":"' + StringToJSONString(Id) + '"}') + 'COMMIT;');
        end;
      'removeAllLabels':
        Db.Exec('DELETE FROM card_labels WHERE cardId=' + Q(A.CardId) + ';');
      'addMember', 'removeMember', 'addAssignee', 'removeAssignee':
        begin
          Remove := Copy(Kind, 1, 6) = 'remove';
          if Pos('Assignee', Kind) > 0 then begin Table := 'card_assignees'; JoinKind := 'Assignee'; Key := 'assigneeId'; end
          else begin Table := 'card_members'; JoinKind := 'Member'; Key := 'memberId'; end;
          if Remove and (Str(Act, 'username') = '*') then
          begin
            R := Db.Query('SELECT userId FROM ' + Table + ' WHERE cardId=' + Q(A.CardId) + ';');
            SetLength(Users, Length(R));
            for i := 0 to High(R) do Users[i] := R[i][0];
          end
          else Users := RuleUsers(Db, A, Str(Act, 'username'), Vars);
          for U in Users do
          begin
            R := Db.Query('SELECT 1 FROM ' + Table + ' WHERE cardId=' + Q(A.CardId) + ' AND userId=' + Q(U) + ';');
            if not Remove and (Length(R) = 0) and
              (Length(Db.Query('SELECT 1 FROM board_members WHERE boardId=' + Q(Card[0][0]) + ' AND userId=' + Q(U) + ' AND isActive=1;')) = 1) then
              Db.Exec('BEGIN IMMEDIATE; INSERT INTO ' + Table + '(cardId,userId) VALUES(' + Q(A.CardId) + ',' + Q(U) + '); ' +
                ActivitySql('join' + JoinKind, A.UserId, A.CardId, '{"' + Key + '":"' + StringToJSONString(U) + '","username":"' +
                StringToJSONString(UsernameOf(Db, U)) + '"}') + 'COMMIT;');
            if Remove and (Length(R) = 1) then
              Db.Exec('BEGIN IMMEDIATE; DELETE FROM ' + Table + ' WHERE cardId=' + Q(A.CardId) + ' AND userId=' + Q(U) + '; ' +
                ActivitySql('unjoin' + JoinKind, A.UserId, A.CardId, '{"' + Key + '":"' + StringToJSONString(U) + '","username":"' +
                StringToJSONString(UsernameOf(Db, U)) + '"}') + 'COMMIT;');
          end;
        end;
      'checkAll', 'uncheckAll', 'checkItem', 'uncheckItem':
        begin
          R := Db.Query('SELECT id FROM checklists WHERE cardId=' + Q(A.CardId) + ' AND title=' + Q(Str(Act, 'checklistName')) + ' LIMIT 1;');
          if Length(R) <> 1 then Exit; // #5283: no such checklist - nothing to do
          Text := 'UPDATE checklist_items SET isFinished=' + IfThen(Copy(Kind, 1, 5) = 'check', '1', '0') + ',modifiedAt=' + Stamp +
            ' WHERE checklistId=' + Q(R[0][0]);
          if Pos('Item', Kind) > 0 then Text := Text + ' AND title=' + Q(Str(Act, 'checkItemName'));
          Db.Exec(Text + ';');
        end;
      'addChecklist', 'addChecklistWithItems':
        begin
          Checklist := NewId;
          Text := SubstituteVars(Str(Act, 'checklistName'), Vars);
          Field := 'BEGIN IMMEDIATE; INSERT INTO checklists(id,cardId,boardId,title,sort,createdAt,modifiedAt) VALUES(' + Q(Checklist) + ',' +
            Q(A.CardId) + ',' + Q(Card[0][0]) + ',' + Q(Text) + ',(SELECT COALESCE(max(sort),-1)+1 FROM checklists WHERE cardId=' +
            Q(A.CardId) + '),' + Stamp + ',' + Stamp + '); ' +
            ActivitySql('addChecklist', A.UserId, A.CardId, '{"checklistId":"' + StringToJSONString(Checklist) + '","checklistName":"' +
            StringToJSONString(Text) + '"}');
          if Kind = 'addChecklistWithItems' then
          begin
            Items := SubstituteVars(Str(Act, 'checklistItems'), Vars).Split([',']);
            for i := 0 to High(Items) do
              if Trim(Items[i]) <> '' then
                Field := Field + 'INSERT INTO checklist_items(id,checklistId,cardId,boardId,title,sort,isFinished,createdAt,modifiedAt) VALUES(' +
                  Q(NewId) + ',' + Q(Checklist) + ',' + Q(A.CardId) + ',' + Q(Card[0][0]) + ',' + Q(Trim(Items[i])) + ',' + IntToStr(i) + ',0,' +
                  Stamp + ',' + Stamp + '); ';
          end;
          Db.Exec(Field + 'COMMIT;');
        end;
      'removeChecklist':
        begin
          R := Db.Query('SELECT id FROM checklists WHERE cardId=' + Q(A.CardId) + ' AND title=' + Q(Str(Act, 'checklistName')) + ' LIMIT 1;');
          if Length(R) = 1 then
            Db.Exec('BEGIN IMMEDIATE; DELETE FROM checklist_items WHERE checklistId=' + Q(R[0][0]) + '; DELETE FROM checklists WHERE id=' +
              Q(R[0][0]) + '; COMMIT;');
        end;
      'addSwimlane':
        Db.Exec('INSERT INTO swimlanes(id,boardId,title,type,sort,archived,createdAt,modifiedAt) VALUES(' + Q(NewId) + ',' + Q(A.BoardId) +
          ',' + Q(SubstituteVars(Str(Act, 'swimlaneName'), Vars)) + ',''swimlane'',(SELECT COALESCE(max(sort),-1)+1 FROM swimlanes WHERE boardId=' +
          Q(A.BoardId) + '),0,' + Stamp + ',' + Stamp + ');');
      'addComment':
        begin
          Text := Trim(SubstituteVars(Str(Act, 'comment'), Vars));
          if Text = '' then Exit;
          Id := NewId;
          Db.Exec('BEGIN IMMEDIATE; INSERT INTO card_comments(id,boardId,cardId,userId,text,createdAt,modifiedAt) VALUES(' + Q(Id) + ',' +
            Q(Card[0][0]) + ',' + Q(A.CardId) + ',' + Q(A.UserId) + ',' + Q(Text) + ',' + Stamp + ',' + Stamp + '); ' +
            ActivitySql('addComment', A.UserId, A.CardId, '{"commentId":"' + Id + '"}') + 'COMMIT;');
        end;
      'markCardComplete', 'markCardIncomplete':
        Db.Exec('UPDATE cards SET dueComplete=' + IfThen(Kind = 'markCardComplete', '1', '0') + ',modifiedAt=' + Stamp + Scope);
      'setDate', 'updateDate', 'removeDate', 'setDateRelative':
        begin
          Field := Str(Act, 'dateField');
          if not DateField(Field) then Exit;
          if Kind = 'removeDate' then Db.Exec('UPDATE cards SET ' + Field + '=NULL,modifiedAt=' + Stamp + Scope)
          else
          begin
            if Kind = 'setDateRelative' then Text := Q(RelativeDate(Act)) else Text := Stamp;
            Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET ' + Field + '=' + Text + ',modifiedAt=' + Stamp + Scope +
              ActivitySql('a-' + Field, A.UserId, A.CardId, '{}') + 'COMMIT;');
          end;
        end;
    end;
  finally
    Vars.Free;
  end;
end;

function HtmlText(const S: string): string;
begin
  Result := StringReplace(StringReplace(StringReplace(StringReplace(S, '&', '&amp;', [rfReplaceAll]), '<', '&lt;', [rfReplaceAll]),
    '>', '&gt;', [rfReplaceAll]), '"', '&quot;', [rfReplaceAll]);
end;

function RuleButtonsHtml(Db: TWLDb; const BoardId, ButtonType: string; Words: TWLTranslator): string;
var Docs: TJSONArray; i: Integer; V: TJSONData; Lbl, Items: string;
begin
  Result := '';
  if not IsShared(Db) then Exit;
  Docs := FindDocs(Db, 'rules', DocField('boardId') + '=' + Q(BoardId) + ' AND ' + DocField('buttonType') + '=' + Q(ButtonType),
    DocField('createdAt') + ',' + DocField('_id'));
  try
    Items := '';
    for i := 0 to Docs.Count - 1 do
    begin
      V := Docs.Objects[i].Find('enabled');
      if (V <> nil) and (V.JSONType = jtBoolean) and not V.AsBoolean then Continue;
      Lbl := Str(Docs.Objects[i], 'buttonLabel');
      if Lbl = '' then Lbl := Str(Docs.Objects[i], 'title');
      if ButtonType = 'board' then
        Items := Items + '<a class="board-header-btn js-run-board-button" href="#" data-rule-id="' + HtmlText(Str(Docs.Objects[i], '_id')) +
          '" title="' + HtmlText(Lbl) + '"><i class="fa fa-magic"></i><span>' + HtmlText(Lbl) + '</span></a>'
      else
        Items := Items + '<button class="primary js-run-card-button" type="button" data-rule-id="' + HtmlText(Str(Docs.Objects[i], '_id')) +
          '"><i class="fa fa-magic"></i> ' + HtmlText(Lbl) + '</button>';
    end;
  finally
    Docs.Free;
  end;
  if (Items = '') or (ButtonType = 'board') then Exit(Items);
  Result := '<div class="card-details-item card-details-item-buttons"><h3 class="card-details-item-title">' +
    '<i class="fa fa-hand-pointer-o"></i> ' + HtmlText(Words.Text('r-card-button', 'Card button')) + '</h3>' +
    '<div class="card-details-item-content card-buttons">' + Items + '</div></div>';
end;

// WeKan's rules.runButton(ruleId[, cardId]): an enabled button rule of a board
// the user may change, on the board or on one of its cards; its actions done
// as that user. Anything else is refused and recorded (RuleButtonBleed).
function RunButton(const T: TWLTenant; const UserId: string; Args: TJSONArray; out Answer: string): Integer;
var Rule, Trigger, Act: TJSONObject; V: TJSONData; A: TActivity; Ids: TStringArray; k: Integer; Allowed: Boolean;
begin
  if (Args.Count < 1) or (Args.Items[0].JSONType <> jtString) or
    ((Args.Count > 1) and not (Args.Items[1].JSONType in [jtString, jtNull])) then
    Exit(MethodError(400, 'Match.Error', 'Expected a rule id', Answer));
  Rule := FindDoc(T.Db, 'rules', Args.Strings[0]);
  if Rule = nil then Exit(MethodError(404, 'not-found', 'Rule not found', Answer));
  Trigger := nil;
  try
    V := Rule.Find('enabled');
    if (V <> nil) and (V.JSONType = jtBoolean) and not V.AsBoolean then
      Exit(MethodError(400, 'rule-disabled', 'Rule is disabled', Answer));
    Trigger := FindDoc(T.Db, 'triggers', Str(Rule, 'triggerId'));
    if (Trigger = nil) or (Str(Trigger, 'activityType') <> 'button') then
      Exit(MethodError(400, 'not-a-button', 'Rule is not a button rule', Answer));
    A := Default(TActivity);
    A.Kind := 'button'; A.UserId := UserId; A.BoardId := Str(Rule, 'boardId');
    if (Args.Count > 1) and (Args.Items[1].JSONType = jtString) then A.CardId := Args.Strings[1];
    Allowed := (A.BoardId <> '') and (Pos(#0, A.BoardId + A.CardId) = 0) and BoardCanWrite(T.Db, UserId, A.BoardId);
    if Allowed and (A.CardId <> '') then
      Allowed := Length(T.Db.Query('SELECT 1 FROM cards WHERE id=' + Q(A.CardId) + ' AND boardId=' + Q(A.BoardId) +
        ' AND deletedAt IS NULL;')) = 1;
    if not Allowed then
    begin
      try
        RecordSecurityEvent(T.Db, UserId, 'RuleButtonBleed', 'rule:button', 'authz', 'high', 'CWE-639', 'blocked',
          'Button rule denied because its caller or card is outside the writable board context.');
      except
        // logging must never break the guard
      end;
      Exit(MethodError(403, 'not-authorized', 'Button rule context is not authorized.', Answer));
    end;
    A.Data := TJSONObject.Create;
    try
      Ids := RuleActionIds(Rule);
      for k := 0 to High(Ids) do
      begin
        Act := FindDoc(T.Db, 'actions', Ids[k]);
        if Act = nil then Continue;
        try
          PerformAction(T, A, Act);
        finally
          Act.Free;
        end;
      end;
    finally
      A.Data.Free;
    end;
    Answer := '{"result":true}';
    Result := 200;
  finally
    Trigger.Free;
    Rule.Free;
  end;
end;

// The board's rules with their first action, in their order: each one's
// [rule, trigger, action] (the caller frees the array).
function BoardRuleParts(Db: TWLDb; const BoardId: string): TJSONArray;
var Rules: TJSONArray; i: Integer; Trig, Act: TJSONObject; Ids: TStringArray;
begin
  Result := TJSONArray.Create;
  Rules := FindDocs(Db, 'rules', DocField('boardId') + '=' + Q(BoardId), DocField('createdAt') + ',' + DocField('_id'));
  try
    for i := 0 to Rules.Count - 1 do
    begin
      Trig := FindDoc(Db, 'triggers', Str(Rules.Objects[i], 'triggerId'));
      Ids := RuleActionIds(Rules.Objects[i]);
      Act := nil;
      if Length(Ids) > 0 then Act := FindDoc(Db, 'actions', Ids[0]);
      if (Trig = nil) or (Act = nil) then begin Trig.Free; Act.Free; Continue; end;
      Result.Add(TJSONArray.Create([Rules.Objects[i].Clone, Trig, Act]));
    end;
  finally
    Rules.Free;
  end;
end;

// WeKan's completionByList: the lists a move rule marks complete or
// incomplete, the last rule winning.
function Completion(Parts: TJSONArray): TStringList;
var i: Integer; Trig, Act: TJSONObject; List: string;
begin
  Result := TStringList.Create;
  for i := 0 to Parts.Count - 1 do
  begin
    Trig := TJSONArray(Parts.Items[i]).Objects[1];
    Act := TJSONArray(Parts.Items[i]).Objects[2];
    List := Str(Trig, 'listName');
    if (Str(Trig, 'activityType') <> 'moveCard') or (List = '') or (List = '*') then Continue;
    if Str(Act, 'actionType') = 'markCardComplete' then Result.Values[List] := 'complete'
    else if Str(Act, 'actionType') = 'markCardIncomplete' then Result.Values[List] := 'incomplete';
  end;
end;

function LowerFirst(const S: string): string;
var U: string; Len: Integer;
begin
  if S = '' then Exit('');
  if Ord(S[1]) < $80 then Len := 1 else if Ord(S[1]) < $E0 then Len := 2 else if Ord(S[1]) < $F0 then Len := 3 else Len := 4;
  U := Copy(S, 1, Len);
  Result := Utf8Lower(U) + Copy(S, Len + 1, MaxInt);
end;

// WeKan's rules.importWrikeWorkflow(boardId, text): a board admin's import - a
// status without a list becomes a list, after the one before it, in its
// color; and each list without a complete or incomplete move rule gets the
// one its group means. A second import adds nothing.
function ImportWrike(const T: TWLTenant; const UserId: string; Args: TJSONArray; Words: TWLTranslator; out Answer: string): Integer;
var BoardId, WName, Error, ListId, Sort, Ids, Kind, Key, TriggerDesc, ActionDesc, Title, Sql: string; Statuses: TWrikeStatuses;
  NotRead, i, k, ListsCreated, RulesCreated: Integer; Lists: TWLRows; Titles, Governed: TStringList; Prev: Double; Found: Boolean;
  Parts: TJSONArray; Trig, Act: TJSONObject; Next, Low: Double; Have: Boolean; Sorts: array of Double;
  function Say(const K, Fallback: string): string;
  begin
    if Words <> nil then Result := Words.Text(K, Fallback) else Result := Fallback;
  end;
begin
  if (Args.Count < 2) or (Args.Items[0].JSONType <> jtString) or (Args.Items[1].JSONType <> jtString) then
    Exit(MethodError(400, 'Match.Error', 'Expected a board id and a text', Answer));
  BoardId := Args.Strings[0];
  if (Pos(#0, BoardId) > 0) or (Length(T.Db.Query('SELECT 1 FROM boards WHERE id=' + Q(BoardId) + ';')) <> 1) then
    Exit(MethodError(404, 'not-found', 'Board not found', Answer));
  if not BoardCanAdmin(T.Db, UserId, BoardId) then Exit(MethodError(403, 'not-authorized', 'Must be a board admin', Answer));
  if not ReadWrikeWorkflow(Args.Strings[1], WName, Statuses, NotRead, Error) then
    Exit(MethodError(400, 'invalid-import-format', Error, Answer));
  Lists := T.Db.Query('SELECT id,title,COALESCE(sort,0) FROM lists WHERE boardId=' + Q(BoardId) +
    ' AND archived=0 AND deletedAt IS NULL ORDER BY sort;');
  Titles := TStringList.Create;
  Governed := TStringList.Create;
  try
    SetLength(Sorts, Length(Lists));
    for i := 0 to High(Lists) do
    begin
      Sorts[i] := StrToFloatDef(Lists[i][2], 0, DefaultFormatSettings);
      if Titles.IndexOfName(Lists[i][1]) < 0 then Titles.Values[Lists[i][1]] := Lists[i][2];
    end;
    ListsCreated := 0;
    Have := False; Prev := 0;
    Sql := '';
    for i := 0 to High(Statuses) do
    begin
      if Titles.IndexOfName(Statuses[i].Name) >= 0 then
      begin
        Have := True;
        Prev := StrToFloatDef(Titles.Values[Statuses[i].Name], 0, DefaultFormatSettings);
        Continue;
      end;
      // WeKan's createListAfter: right after the previous status' list, or
      // before every list.
      if not Have then
      begin
        Low := 0;
        for k := 0 to High(Sorts) do
          if (k = 0) or (Sorts[k] < Low) then Low := Sorts[k];
        Prev := Low - 1;
      end
      else
      begin
        Found := False; Next := 0;
        for k := 0 to High(Sorts) do
          if (Sorts[k] > Prev) and (not Found or (Sorts[k] < Next)) then begin Next := Sorts[k]; Found := True; end;
        if Found then Prev := (Prev + Next) / 2 else Prev := Prev + 1;
      end;
      Have := True;
      Sort := FloatToStr(Prev, DefaultFormatSettings);
      ListId := NewId;
      Sql := Sql + 'INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt,color) VALUES(' + Q(ListId) + ',' + Q(BoardId) +
        ','''',' + Q(Statuses[i].Name) + ',' + Sort + ',' + Q(NowIso) + ',' + IfThen(Statuses[i].Color = '', 'NULL', Q(Statuses[i].Color)) + '); ';
      SetLength(Sorts, Length(Sorts) + 1);
      Sorts[High(Sorts)] := Prev;
      Titles.Values[Statuses[i].Name] := Sort;
      Inc(ListsCreated);
    end;
    if (Sql <> '') and not T.Db.Exec('BEGIN IMMEDIATE; ' + Sql + 'COMMIT;') then
    begin T.Db.Exec('ROLLBACK;'); Exit(MethodError(500, 'internal-error', 'Could not add the lists', Answer)); end;
    // The lists that already have a complete or incomplete move rule.
    Parts := BoardRuleParts(T.Db, BoardId);
    try
      for i := 0 to Parts.Count - 1 do
      begin
        Trig := TJSONArray(Parts.Items[i]).Objects[1];
        Act := TJSONArray(Parts.Items[i]).Objects[2];
        if (Str(Trig, 'activityType') = 'moveCard') and ((Str(Act, 'actionType') = 'markCardComplete') or
          (Str(Act, 'actionType') = 'markCardIncomplete')) then Governed.Add(Str(Trig, 'listName'));
      end;
    finally
      Parts.Free;
    end;
    RulesCreated := 0;
    for i := 0 to High(Statuses) do
    begin
      if Governed.IndexOf(Statuses[i].Name) >= 0 then Continue;
      if (Statuses[i].Group = 'Completed') or (Statuses[i].Group = 'Cancelled') then
      begin Kind := 'markCardComplete'; Key := 'r-mark-complete'; end
      else begin Kind := 'markCardIncomplete'; Key := 'r-mark-incomplete'; end;
      TriggerDesc := Say('r-when-a-card-is-moved', 'When a card is moved to another list') + ': ' + Statuses[i].Name;
      ActionDesc := Say(Key, Key);
      Title := 'Wrike ' + Statuses[i].Group + ': When ' + LowerFirst(TriggerDesc) + ', then ' + LowerFirst(ActionDesc);
      Trig := TJSONObject.Create(['activityType', 'moveCard', 'listName', Statuses[i].Name, 'oldListName', '*', 'swimlaneName', '*',
        'cardTitle', '*', 'userId', '*', 'desc', TriggerDesc]);
      Act := TJSONObject.Create(['actionType', Kind, 'desc', ActionDesc]);
      try
        if not InsertRule(T, BoardId, Title, Trig, Act, Ids) then
          Exit(MethodError(500, 'internal-error', 'Could not create the rule', Answer));
      finally
        Trig.Free;
        Act.Free;
      end;
      Governed.Add(Statuses[i].Name);
      Inc(RulesCreated);
    end;
  finally
    Governed.Free;
    Titles.Free;
  end;
  Answer := '{"result":{"name":"' + StringToJSONString(WName) + '","statuses":' + IntToStr(Length(Statuses)) + ',"listsCreated":' +
    IntToStr(ListsCreated) + ',"rulesCreated":' + IntToStr(RulesCreated) + ',"notRead":' + IntToStr(NotRead) + '}}';
  Result := 200;
end;

function CsvField(const S: string): string;
begin
  if (Pos(',', S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) or (Pos(#13, S) > 0) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else Result := S;
end;

function RulesExport(Db: TWLDb; const UserId, BoardId, Format, Ids: string; out Body, ContentType, FileName: string): Boolean;
var Parts, Entries, Extra: TJSONArray; Picked: TStringList; i, k: Integer; Rule, Trig, Act, E, Out_, TF, AF: TJSONObject;
  R: TWLRows; Lists: TWrikeLists; Comp: TStringList; ActIds: TStringArray; More: TJSONObject; Wf: TJSONObject; Title: string;
begin
  Result := False; Body := ''; ContentType := ''; FileName := '';
  if (BoardId = '') or (Pos(#0, BoardId) > 0) or not IsShared(Db) or not BoardCanAdmin(Db, UserId, BoardId) then Exit;
  Result := True;
  Parts := BoardRuleParts(Db, BoardId);
  try
    if Format = 'wrike' then
    begin
      R := Db.Query('SELECT title,COALESCE(color,'''') FROM lists WHERE boardId=' + Q(BoardId) +
        ' AND archived=0 AND deletedAt IS NULL ORDER BY sort;');
      SetLength(Lists, Length(R));
      for i := 0 to High(R) do begin Lists[i].Title := R[i][0]; Lists[i].Color := R[i][1]; end;
      R := Db.Query('SELECT title FROM boards WHERE id=' + Q(BoardId) + ';');
      Title := '';
      if Length(R) = 1 then Title := R[0][0];
      Comp := Completion(Parts);
      try
        Wf := WrikeWorkflowFromBoard(Title, Lists, Comp);
      finally
        Comp.Free;
      end;
      try
        Body := Wf.FormatJSON([], 2);
      finally
        Wf.Free;
      end;
      ContentType := 'application/json';
      FileName := 'wrike-workflow.json';
      Exit;
    end;
    Picked := TStringList.Create;
    Entries := TJSONArray.Create;
    try
      if Ids <> '' then Picked.CommaText := Ids;
      for i := 0 to Parts.Count - 1 do
      begin
        Rule := TJSONArray(Parts.Items[i]).Objects[0];
        if (Ids <> '') and (Picked.IndexOf(Str(Rule, '_id')) < 0) then Continue;
        Trig := TJSONArray(Parts.Items[i]).Objects[1];
        Act := TJSONArray(Parts.Items[i]).Objects[2];
        E := TJSONObject.Create(['title', Str(Rule, 'title')]);
        E.Add('trigger', PortableDoc(Trig));
        E.Add('action', PortableDoc(Act));
        ActIds := RuleActionIds(Rule);
        if Length(ActIds) > 1 then
        begin
          Extra := TJSONArray.Create;
          for k := 1 to High(ActIds) do
          begin
            More := FindDoc(Db, 'actions', ActIds[k]);
            if More <> nil then
            begin
              Extra.Add(PortableDoc(More));
              More.Free;
            end;
          end;
          E.Add('extraActions', Extra);
        end;
        Entries.Add(E);
      end;
      if Format = 'csv' then
      begin
        Body := 'title,triggerType,triggerFields,actionType,actionFields'#13#10;
        for i := 0 to Entries.Count - 1 do
        begin
          TF := TJSONObject(Entries.Objects[i].Objects['trigger'].Clone);
          AF := TJSONObject(Entries.Objects[i].Objects['action'].Clone);
          try
            TF.Delete('activityType');
            AF.Delete('actionType');
            Body := Body + CsvField(Str(Entries.Objects[i], 'title')) + ',' +
              CsvField(Str(Entries.Objects[i].Objects['trigger'], 'activityType')) + ',' + CsvField(TF.AsJSON) + ',' +
              CsvField(Str(Entries.Objects[i].Objects['action'], 'actionType')) + ',' + CsvField(AF.AsJSON) + #13#10;
          finally
            TF.Free;
            AF.Free;
          end;
        end;
        ContentType := 'text/csv; charset=utf-8';
        FileName := 'wekan-rules.csv';
        Exit;
      end;
      Out_ := TJSONObject.Create(['_format', 'wekan-rules-1.0.0', 'boardId', BoardId]);
      try
        Out_.Add('rules', Entries.Clone);
        Body := Out_.FormatJSON([], 2);
      finally
        Out_.Free;
      end;
      ContentType := 'application/json';
      FileName := 'wekan-rules.json';
    finally
      Entries.Free;
      Picked.Free;
    end;
  finally
    Parts.Free;
  end;
end;

// A document written back whole, with its id: the one there now replaced.
function ReplaceDocSql(Db: TWLDb; const Collection: string; Doc: TJSONObject): string;
var Copy_: TJSONObject; Stamp: Int64;
begin
  Stamp := NowMs;
  Copy_ := TJSONObject(Doc.Clone);
  try
    Copy_.Delete('createdAt'); Copy_.Add('createdAt', Stamp);
    if Collection = 'triggers' then begin Copy_.Delete('updatedAt'); Copy_.Add('updatedAt', Stamp); end
    else begin Copy_.Delete('modifiedAt'); Copy_.Add('modifiedAt', Stamp); end;
    Result := DeleteDocSql(Db, Collection, Str(Doc, '_id')) + InsertDocSql(Db, Collection, Copy_, DateHints);
  finally
    Copy_.Free;
  end;
end;

// Whether a rule other than RuleId names the part Id (Field: trigger or action).
function PartUsedElsewhere(Db: TWLDb; const Field, Id, RuleId: string): Boolean;
var Others: TJSONArray; Extra: string;
begin
  Extra := 'extra' + UpperCase(Field[1]) + Copy(Field, 2, MaxInt) + 'Ids';
  Others := FindDocs(Db, 'rules', DocField('_id') + '<>' + Q(RuleId) + ' AND (' + DocField(Field + 'Id') + '=' + Q(Id) +
    ' OR EXISTS(SELECT 1 FROM json_each(_ferretdb_sjson,''$.' + Extra + ''') WHERE value=' + Q(Id) + '))', '');
  try
    Result := Others.Count > 0;
  finally
    Others.Free;
  end;
end;

// The parts a rule used that no rule uses now: removed.
procedure RemoveUnusedParts(Db: TWLDb; Rule: TJSONObject);
var Field, Coll, Id, Sql: string; Ids: TStringArray; V: TJSONData; i: Integer;
begin
  Sql := '';
  for Field in ['trigger', 'action'] do
  begin
    if Field = 'trigger' then Coll := 'triggers' else Coll := 'actions';
    Ids := TStringArray.Create(Str(Rule, Field + 'Id'));
    V := Rule.Find('extra' + UpperCase(Field[1]) + Copy(Field, 2, MaxInt) + 'Ids');
    if V is TJSONArray then
      for i := 0 to V.Count - 1 do
        if V.Items[i].JSONType = jtString then begin SetLength(Ids, Length(Ids) + 1); Ids[High(Ids)] := V.Items[i].AsString; end;
    for Id in Ids do
      if (Id <> '') and not PartUsedElsewhere(Db, Field, Id, '') then Sql := Sql + DeleteDocSql(Db, Coll, Id);
  end;
  if (Sql <> '') and not Db.Exec('BEGIN IMMEDIATE; ' + Sql + 'COMMIT;') then Db.Exec('ROLLBACK;');
end;

// WeKan's applyRuleHistory: a snapshot of the row put back, a board admin's.
// Direction undo puts previousContent back, redo newContent, restore the
// row's content whatever the rule is now. Error is set (Meteor's error) when
// refused; False without one when there is nothing it may write.
function ApplyRuleHistory(Db: TWLDb; const UserId: string; Row: TJSONObject; const Direction: string; out Error: string): Boolean;
var BoardId, RuleId, Sql: string; Current, Content, Expected, Rule, Trig, Act, CurRule, Part, Existing: TJSONObject;
  Parts: TJSONArray; Colls, Fields: TStringList; V, W: TJSONData; i: Integer; Shared: Boolean; Key, Coll, IdsKey: string;
  function Obj(Data: TJSONData): TJSONObject;
  begin
    if Data is TJSONObject then Result := TJSONObject(Data) else Result := nil;
  end;
begin
  Result := False; Error := '';
  BoardId := Str(Row, 'boardId'); RuleId := Str(Row, 'entityId');
  if not BoardCanAdmin(Db, UserId, BoardId) then begin Error := 'not-authorized'; Exit; end;
  Current := RuleSnapshot(Db, RuleId);
  Parts := TJSONArray.Create; Colls := TStringList.Create; Fields := TStringList.Create;
  try
    CurRule := Obj(Current.Find('rule'));
    if (CurRule <> nil) and (Str(CurRule, 'boardId') <> BoardId) then begin Error := 'not-authorized'; Exit; end;
    Expected := Obj(Row.Find('previousContent'));
    Content := Obj(Row.Find('newContent'));
    if Direction = 'undo' then
    begin
      Expected := Obj(Row.Find('newContent'));
      Content := Obj(Row.Find('previousContent'));
    end
    else if (Direction = 'restore') and (Content = nil) then Content := Obj(Row.Find('previousContent'));
    // Undo and redo never overwrite a later edit by somebody else.
    if (Direction <> 'restore') and ((Expected = nil) or (CanonicalHistoryValue(Current) <> CanonicalHistoryValue(Expected))) then
    begin Error := 'history-conflict'; Exit; end;
    if (Content = nil) or (Content.Find('rule') = nil) then Exit;
    Rule := Obj(Content.Find('rule'));
    if Rule = nil then
    begin
      if CurRule = nil then Exit;
      Sql := RemoveRuleSql(Db, CurRule);
      Result := Db.Exec('BEGIN IMMEDIATE; ' + Sql + 'COMMIT;');
      if not Result then Db.Exec('ROLLBACK;');
      Exit;
    end;
    Trig := Obj(Content.Find('trigger')); Act := Obj(Content.Find('action'));
    if (Str(Rule, '_id') <> RuleId) or (Str(Rule, 'boardId') <> BoardId) or (Trig = nil) or (Act = nil) or
      (Str(Trig, '_id') <> Str(Rule, 'triggerId')) or (Str(Act, '_id') <> Str(Rule, 'actionId')) or
      (Str(Trig, 'boardId') <> BoardId) then Exit;
    Parts.Add(Trig.Clone); Colls.Add('triggers'); Fields.Add('trigger');
    Parts.Add(Act.Clone); Colls.Add('actions'); Fields.Add('action');
    for Key in ['extraTriggers', 'extraActions'] do
    begin
      if Key = 'extraTriggers' then begin Coll := 'triggers'; IdsKey := 'extraTriggerIds'; end
      else begin Coll := 'actions'; IdsKey := 'extraActionIds'; end;
      V := Content.Find(Key); W := Rule.Find(IdsKey);
      if (V = nil) and ((W = nil) or (W.Count = 0)) then Continue;
      if not (V is TJSONArray) or not (W is TJSONArray) or (V.Count <> W.Count) then Exit;
      for i := 0 to V.Count - 1 do
      begin
        Part := Obj(V.Items[i]);
        if (Part = nil) or (W.Items[i].JSONType <> jtString) or (Str(Part, '_id') <> W.Items[i].AsString) or
          (Str(Part, 'boardId') <> BoardId) then Exit;
        Parts.Add(Part.Clone); Colls.Add(Coll); Fields.Add(Copy(Coll, 1, Length(Coll) - 1));
      end;
    end;
    // Every target checked before the first write: another board's document,
    // or another rule's shared part that differs, is never replaced.
    Sql := '';
    for i := 0 to Parts.Count - 1 do
    begin
      Part := Parts.Objects[i];
      Existing := FindDoc(Db, Colls[i], Str(Part, '_id'));
      try
        if (Existing <> nil) and (Str(Existing, 'boardId') <> Str(Part, 'boardId')) then Exit;
        Shared := PartUsedElsewhere(Db, Fields[i], Str(Part, '_id'), RuleId);
        if Shared then
        begin
          W := Untimed(Existing);
          try
            if (Existing = nil) or (CanonicalHistoryValue(W) <> CanonicalHistoryValue(Part)) then Exit;
          finally
            W.Free;
          end;
          Continue;
        end;
        Sql := Sql + ReplaceDocSql(Db, Colls[i], Part);
      finally
        Existing.Free;
      end;
    end;
    Sql := Sql + ReplaceDocSql(Db, 'rules', Rule);
    Result := Db.Exec('BEGIN IMMEDIATE; ' + Sql + 'COMMIT;');
    if not Result then begin Db.Exec('ROLLBACK;'); Exit; end;
    // The parts the rule used before and uses no more.
    if CurRule <> nil then RemoveUnusedParts(Db, CurRule);
  finally
    Fields.Free; Colls.Free; Parts.Free; Current.Free;
  end;
end;

// A card's title or description row undone (previousContent back) or redone
// (newContent back): only while the card still has the value the other side
// left - a newer edit is never overwritten (history-conflict).
function ApplyCardHistory(Db: TWLDb; Row: TJSONObject; const Direction: string; out Error: string): Boolean;
var Prev, Next, Put, Expect: TJSONData; Field, CardId: string; R: TWLRows;
  function ValueOf(Content: TJSONData): string;
  var V: TJSONData;
  begin
    Result := '';
    if not (Content is TJSONObject) then Exit;
    V := TJSONObject(Content).Find('value');
    if (V <> nil) and (V.JSONType = jtString) then Result := V.AsString;
  end;
begin
  Result := False; Error := '';
  Prev := Row.Find('previousContent'); Next := Row.Find('newContent');
  if Direction = 'undo' then begin Put := Prev; Expect := Next; end else begin Put := Next; Expect := Prev; end;
  if Put is TJSONObject then Field := Str(TJSONObject(Put), 'field')
  else if Expect is TJSONObject then Field := Str(TJSONObject(Expect), 'field')
  else Field := '';
  if (Field <> 'title') and (Field <> 'description') then Exit;
  CardId := Str(Row, 'entityId');
  R := Db.Query('SELECT COALESCE(' + Field + ','''') FROM cards WHERE id=' + Q(CardId) + ' AND boardId=' + Q(Str(Row, 'boardId')) +
    ' AND deletedAt IS NULL;');
  if Length(R) <> 1 then Exit;
  if R[0][0] <> ValueOf(Expect) then begin Error := 'history-conflict'; Exit; end;
  Result := Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET ' + Field + '=' + Q(ValueOf(Put)) + ',modifiedAt=' + Q(NowIso) +
    ' WHERE id=' + Q(CardId) + '; COMMIT;');
  if not Result then Db.Exec('ROLLBACK;');
end;

// A list's lifecycle row undone (the list and the cards of its delete batch
// back) or redone (the list and its live cards deleted again, in the same
// batch). A card deleted on its own, in another batch, is not touched.
function ApplyListHistory(Db: TWLDb; const UserId: string; Row: TJSONObject; const Direction: string; out Error: string): Boolean;
var ListId, BoardId, Batch, Markers: string;
begin
  Result := False; Error := '';
  if Str(Row, 'group') <> 'lifecycle' then Exit;
  ListId := Str(Row, 'entityId'); BoardId := Str(Row, 'boardId'); Batch := Str(Row, 'batchId');
  if (ListId = '') or (Batch = '') then Exit;
  // A removal undone and a restore redone put it back; the other two delete it.
  if (Direction = 'undo') = (Str(Row, 'changeType') = 'removed') then
  begin
    if Length(Db.Query('SELECT 1 FROM lists WHERE id=' + Q(ListId) + ' AND boardId=' + Q(BoardId) + ' AND deleteBatchId=' + Q(Batch) + ';')) <> 1 then
    begin Error := 'history-conflict'; Exit; end;
    Result := Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET deletedAt=NULL,deletedBy=NULL,deleteBatchId=NULL WHERE listId=' + Q(ListId) +
      ' AND boardId=' + Q(BoardId) + ' AND deleteBatchId=' + Q(Batch) + '; UPDATE lists SET deletedAt=NULL,deletedBy=NULL,deleteBatchId=NULL ' +
      'WHERE id=' + Q(ListId) + ' AND deleteBatchId=' + Q(Batch) + '; COMMIT;');
  end
  else
  begin
    if Length(Db.Query('SELECT 1 FROM lists WHERE id=' + Q(ListId) + ' AND boardId=' + Q(BoardId) + ' AND deletedAt IS NULL;')) <> 1 then
    begin Error := 'history-conflict'; Exit; end;
    Markers := 'deletedAt=' + Q(NowIso) + ',deletedBy=' + Q(UserId) + ',deleteBatchId=' + Q(Batch);
    Result := Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET ' + Markers + ' WHERE listId=' + Q(ListId) + ' AND boardId=' + Q(BoardId) +
      ' AND deletedAt IS NULL; UPDATE lists SET ' + Markers + ' WHERE id=' + Q(ListId) + ' AND deletedAt IS NULL; COMMIT;');
  end;
  if not Result then Db.Exec('ROLLBACK;');
end;

function HistoryMethod(const T: TWLTenant; const UserId, Name: string; Args: TJSONArray; out Answer: string): Integer;
var BoardId, Direction, Key, Error, Sort: string; Rows: TJSONArray; Row, Fields, Before, After: TJSONObject; Ids: TStringList;
  i, Restored, Skipped: Integer; Applied: Boolean;
begin
  Answer := '';
  if (Name <> 'changeHistory.undoLast') and (Name <> 'changeHistory.redoLast') and (Name <> 'changeHistory.restore') then Exit(0);
  if not IsShared(T.Db) then Exit(MethodError(501, 'not-supported', 'History needs the shared store', Answer));
  if Name = 'changeHistory.restore' then
  begin
    Ids := TStringList.Create;
    try
      if (Args.Count >= 1) and (Args.Items[0].JSONType = jtString) then Ids.Add(Args.Strings[0])
      else if (Args.Count >= 1) and (Args.Items[0] is TJSONArray) then
      begin
        for i := 0 to Args.Items[0].Count - 1 do
          if Args.Items[0].Items[i].JSONType = jtString then Ids.Add(Args.Items[0].Items[i].AsString);
      end
      else Exit(MethodError(400, 'Match.Error', 'Match failed', Answer));
      Restored := 0; Skipped := 0;
      for i := 0 to Ids.Count - 1 do
      begin
        Row := FindDoc(T.Db, 'changeHistory', Ids[i]);
        if Row = nil then begin Inc(Skipped); Continue; end;
        Before := nil; After := nil;
        try
          if not BoardCanAdmin(T.Db, UserId, Str(Row, 'boardId')) then Exit(MethodError(403, 'not-authorized', 'Must be a board admin', Answer));
          if Str(Row, 'entityType') <> 'rule' then begin Inc(Skipped); Continue; end;
          Before := RuleSnapshot(T.Db, Str(Row, 'entityId'));
          Applied := ApplyRuleHistory(T.Db, UserId, Row, 'restore', Error);
          if Error <> '' then Exit(MethodError(403, Error, Error, Answer));
          if not Applied then begin Inc(Skipped); Continue; end;
          After := RuleSnapshot(T.Db, Str(Row, 'entityId'));
          RecordHistoryRow(T.Db, UserId, Str(Row, 'boardId'), 'rule', Str(Row, 'entityId'), 'rules', 'restored', Before, After,
            Str(Row, '_id'), UserId);
          AnnounceToAll;
          Inc(Restored);
        finally
          After.Free; Before.Free; Row.Free;
        end;
      end;
    finally
      Ids.Free;
    end;
    Answer := '{"result":{"restored":' + IntToStr(Restored) + ',"skipped":' + IntToStr(Skipped) + '}}';
    Exit(200);
  end;
  // undoLast / redoLast: the user's newest change on the board, or the one
  // most recently undone.
  if (Args.Count < 1) or (Args.Items[0].JSONType <> jtString) then Exit(MethodError(400, 'Match.Error', 'Match failed', Answer));
  BoardId := Args.Strings[0];
  if (Pos(#0, BoardId) > 0) or not BoardCanWrite(T.Db, UserId, BoardId) then Exit(MethodError(403, 'not-authorized', 'not-authorized', Answer));
  if Name = 'changeHistory.undoLast' then begin Direction := 'undo'; Key := 'undone'; Sort := 'createdAt'; end
  else begin Direction := 'redo'; Key := 'redone'; Sort := 'undoneAt'; end;
  Rows := FindDocs(T.Db, 'changeHistory', DocField('boardId') + '=' + Q(BoardId) + ' AND ' + DocField('userId') + '=' + Q(UserId) +
    ' AND json_type(_ferretdb_sjson,''$.undone'')=' + IfThen(Direction = 'redo', '''true''', '''false''') +
    ' AND COALESCE(json_type(_ferretdb_sjson,''$.isCheckpoint''),'''')<>''true''' +
    ' AND COALESCE(json_type(_ferretdb_sjson,''$.superseded''),'''')<>''true''', DocField(Sort) + ' DESC LIMIT 1');
  try
    if Rows.Count = 0 then begin Answer := '{"result":{"' + Key + '":false}}'; Exit(200); end;
    Row := Rows.Objects[0];
    if Str(Row, 'entityType') = 'card' then Applied := ApplyCardHistory(T.Db, Row, Direction, Error)
    else if Str(Row, 'entityType') = 'list' then Applied := ApplyListHistory(T.Db, UserId, Row, Direction, Error)
    else if Str(Row, 'entityType') = 'rule' then Applied := ApplyRuleHistory(T.Db, UserId, Row, Direction, Error)
    else begin Answer := '{"result":{"' + Key + '":false}}'; Exit(200); end;
    if Error = 'history-conflict' then Exit(MethodError(409, Error, 'It changed after this history entry', Answer));
    if Error <> '' then Exit(MethodError(403, Error, Error, Answer));
    if Applied then
    begin
      Fields := TJSONObject.Create(['undone', Direction = 'undo']);
      try
        if Direction = 'undo' then Fields.Add('undoneAt', NowMs);
        if T.Db.Exec('BEGIN IMMEDIATE; ' + UpdateDocSql(T.Db, 'changeHistory', Str(Row, '_id'), Fields, '{"undoneAt":"date","createdAt":"date"}') +
          'COMMIT;') then else T.Db.Exec('ROLLBACK;');
      finally
        Fields.Free;
      end;
    end;
    if Applied then AnnounceToAll;
    Answer := '{"result":{"' + Key + '":' + IfThen(Applied, 'true', 'false') + ',"entityType":"' + StringToJSONString(Str(Row, 'entityType')) +
      '","entityId":"' + StringToJSONString(Str(Row, 'entityId')) + '","group":"' + StringToJSONString(Str(Row, 'group')) + '"}}';
    Result := 200;
  finally
    Rows.Free;
  end;
end;

function ReadActivities(Db: TWLDb; const Stamp: string): TWLRows;
begin
  Result := Db.Query('SELECT id,activityType,COALESCE(userId,''''),COALESCE(boardId,''''),COALESCE(cardId,''''),COALESCE(listId,''''),' +
    'COALESCE(swimlaneId,''''),COALESCE(data_json,''{}'') FROM activities WHERE createdAt>=' + Q(Stamp) +
    ' AND id NOT IN (SELECT id FROM _wl_rule_seen) ORDER BY createdAt,id;');
end;

// An activity claimed for this run: the first request to write it into
// _wl_rule_seen runs its rules, and nobody else does.
function Claim(Db: TWLDb; const Id: string): Boolean;
begin
  Result := Length(Db.Query('INSERT OR IGNORE INTO _wl_rule_seen(id,at) VALUES(' + Q(Id) + ',' + Q(NowIso) + ') RETURNING id;')) = 1;
end;

procedure RunRulesSince(const T: TWLTenant; const Stamp: string);
var Rows: TWLRows; i, j, k, Depth: Integer; A: TActivity; Rules: TJSONArray; Ids: TStringArray; Act: TJSONObject; Any: Boolean;
  Raw, Tbl: string;
begin
  if (T.Db = nil) or (Stamp = '') then Exit;
  // No rule anywhere: nothing to run, and nothing to claim.
  if not CollectionTable(T.Db, 'rules', Raw, Tbl) or (Length(T.Db.Query('SELECT 1 FROM ' + Tbl + ' LIMIT 1;')) = 0) then Exit;
  T.Db.Exec('CREATE TABLE IF NOT EXISTS _wl_rule_seen(id TEXT PRIMARY KEY, at TEXT NOT NULL);');
  FreeAndNil(CopyChain);
  for Depth := 0 to MAX_RULE_DEPTH do
  begin
    Rows := ReadActivities(T.Db, Stamp);
    if Length(Rows) = 0 then Break;
    if Depth = MAX_RULE_DEPTH then
    begin
      try
        RecordSecurityEvent(T.Db, Rows[0][2], 'BypassBleed', 'rules', 'dos', 'medium', 'CWE-674', 'detected',
          'rules started by rules ' + IntToStr(Depth) + ' deep on board ' + Rows[0][3] + '; stopped');
      except
        // logging must never break the guard
      end;
      for i := 0 to High(Rows) do Claim(T.Db, Rows[i][0]);
      Break;
    end;
    Any := False;
    for i := 0 to High(Rows) do
    begin
      if not Claim(T.Db, Rows[i][0]) then Continue;
      A.Id := Rows[i][0]; A.Kind := Rows[i][1]; A.UserId := Rows[i][2]; A.BoardId := Rows[i][3];
      A.CardId := Rows[i][4]; A.ListId := Rows[i][5]; A.SwimlaneId := Rows[i][6];
      try
        A.Data := TJSONObject(GetJSON(Rows[i][7]));
      except
        A.Data := TJSONObject.Create;
      end;
      if not (A.Data is TJSONObject) then begin A.Data.Free; A.Data := TJSONObject.Create; end;
      try
        Rules := MatchingRules(T.Db, A);
        try
          for j := 0 to Rules.Count - 1 do
          begin
            Ids := RuleActionIds(Rules.Objects[j]);
            for k := 0 to High(Ids) do
            begin
              Act := FindDoc(T.Db, 'actions', Ids[k]);
              if Act = nil then Continue;
              try
                PerformAction(T, A, Act);
                Any := True;
              finally
                Act.Free;
              end;
            end;
          end;
        finally
          Rules.Free;
        end;
      finally
        A.Data.Free;
      end;
    end;
    if not Any then Break;
  end;
  FreeAndNil(CopyChain);
  // What was claimed a day ago is never read again.
  T.Db.Exec('DELETE FROM _wl_rule_seen WHERE at<' + Q(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', IncDay(LocalTimeToUniversal(Now), -1))) + ';');
end;

// A number of a document (days, weekday...) as text, also when stored as a
// string; '' without one.
function NumText(Doc: TJSONObject; const Name: string): string;
var V: TJSONData;
begin
  Result := '';
  V := Doc.Find(Name);
  if V = nil then Exit;
  case V.JSONType of
    jtNumber: Result := IntToStr(Round(V.AsFloat));
    jtString: Result := V.AsString;
  end;
end;

function NumOf(Doc: TJSONObject; const Name: string): Double;
var V: TJSONData;
begin
  Result := 0;
  V := Doc.Find(Name);
  if V = nil then Exit;
  case V.JSONType of
    jtNumber: Result := V.AsFloat;
    jtString: Result := StrToFloatDef(V.AsString, 0, DefaultFormatSettings);
  end;
end;

// WeKan's boardActorId (models/lib/boardActor.js): who a board's own timed
// work acts as - its first active admin, else its first active member.
function BoardActor(Db: TWLDb; const BoardId: string): string;
var R: TWLRows;
begin
  R := Db.Query('SELECT userId FROM board_members WHERE boardId=' + Q(BoardId) + ' AND isActive=1 ORDER BY isAdmin DESC,userId LIMIT 1;');
  if Length(R) = 1 then Result := R[0][0] else Result := '';
end;

// The cards a scheduled trigger acts on (scheduledRules.js selectCards):
// the board's open cards - of the trigger's list, unless '*' - and of them
// those whose due or start date meets dueCondition, or that have been in
// their list for at least `days` days.
function ScheduledCards(Db: TWLDb; Trig: TJSONObject; NowMs: Int64): TStringArray;
var R, Since, Lists: TWLRows; Where, ListName, Field: string; i: Integer; Keep: Boolean; At: Int64; Days: Double;
begin
  Result := nil;
  Where := 'boardId=' + Q(Str(Trig, 'boardId')) + ' AND archived=0 AND deletedAt IS NULL';
  ListName := Str(Trig, 'listName');
  if (ListName <> '') and (ListName <> '*') then
  begin
    Lists := Db.Query('SELECT id FROM lists WHERE boardId=' + Q(Str(Trig, 'boardId')) + ' AND title=' + Q(ListName) + ' LIMIT 1;');
    if Length(Lists) = 0 then Exit;
    Where := Where + ' AND listId=' + Q(Lists[0][0]);
  end;
  if Str(Trig, 'dateField') = 'startAt' then Field := 'startAt' else Field := 'dueAt';
  R := Db.Query('SELECT id,COALESCE(' + Field + ',''''),COALESCE(createdAt,'''') FROM cards WHERE ' + Where + ' ORDER BY sort,id;');
  Days := NumOf(Trig, 'days');
  for i := 0 to High(R) do
  begin
    Keep := True;
    if Str(Trig, 'scheduleKind') = 'due' then
      Keep := MatchesScheduledDate(R[i][1], Str(Trig, 'dueCondition'), Days, NowMs)
    else if Str(Trig, 'scheduleKind') = 'aging' then
    begin
      // daysInList: since its newest move or creation, else since created.
      Since := Db.Query('SELECT createdAt FROM activities WHERE cardId=' + Q(R[i][0]) +
        ' AND activityType IN (''moveCard'',''createCard'') ORDER BY createdAt DESC LIMIT 1;');
      if (Length(Since) = 1) and (Since[0][0] <> '') then Keep := MatchesScheduledDate(Since[0][0], 'overdue', Days, NowMs)
      else Keep := MatchesScheduledDate(R[i][2], 'overdue', Days, NowMs);
    end;
    if Keep then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := R[i][0];
    end;
  end;
end;

procedure RunScheduledRules(const T: TWLTenant; Local, Utc: TDateTime);
var Triggers, Rules: TJSONArray; Trig, Rule, Act, Fields: TJSONObject; i, j, k, c: Integer; Slot, Kind, At, Stamp, Sql: string;
  Cards, Ids: TStringArray; A: TActivity; NowMs: Int64; V: TJSONData; Ran: Boolean;
begin
  if (T.Db = nil) or not IsShared(T.Db) then Exit;
  Triggers := FindDocs(T.Db, 'triggers', DocField('activityType') + '=''scheduledTrigger''', DocField('_id'));
  try
    if Triggers.Count = 0 then Exit;
    Slot := SlotKey(Local);
    NowMs := DateTimeToUnix(Utc, True) * 1000;
    Stamp := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Utc);
    for i := 0 to Triggers.Count - 1 do
    try
      Trig := Triggers.Objects[i];
      // Once a minute at most (lastRunKey).
      if Str(Trig, 'lastRunKey') = Slot then Continue;
      Kind := Str(Trig, 'scheduleKind');
      if Kind = 'cron' then
      begin
        if not CronMatches(Str(Trig, 'cron'), Utc) then Continue;
      end
      else
      begin
        At := Str(Trig, 'atTime');
        if (At <> '') and (At <> HourMinute(Local)) then Continue;
        if (Kind = 'calendar') and not CalendarDue(Str(Trig, 'scheduleType'), Str(Trig, 'onDate'), NumText(Trig, 'weekday'),
          NumText(Trig, 'dayOfMonth'), Local) then Continue;
      end;
      Ran := False;
      Rules := FindDocs(T.Db, 'rules', DocField('boardId') + '=' + Q(Str(Trig, 'boardId')) + ' AND (' + DocField('triggerId') + '=' +
        Q(Str(Trig, '_id')) + ' OR EXISTS(SELECT 1 FROM json_each(_ferretdb_sjson,''$.extraTriggerIds'') WHERE value=' +
        Q(Str(Trig, '_id')) + '))', DocField('createdAt') + ',' + DocField('_id'));
      try
        for j := 0 to Rules.Count - 1 do
        begin
          Rule := Rules.Objects[j];
          // A disabled rule never fires (#2322), on a schedule too.
          V := Rule.Find('enabled');
          if (V <> nil) and (V.JSONType = jtBoolean) and not V.AsBoolean then Continue;
          Ids := RuleActionIds(Rule);
          if Length(Ids) = 0 then Continue;
          Cards := ScheduledCards(T.Db, Trig, NowMs);
          A.Id := ''; A.Kind := 'scheduledTrigger'; A.UserId := BoardActor(T.Db, Str(Trig, 'boardId'));
          A.BoardId := Str(Trig, 'boardId'); A.ListId := ''; A.SwimlaneId := '';
          for k := 0 to High(Ids) do
          begin
            Act := FindDoc(T.Db, 'actions', Ids[k]);
            if Act = nil then Continue;
            A.Data := TJSONObject.Create;
            try
              // A board-level action runs once when no card is chosen.
              if (Length(Cards) = 0) and ((Str(Act, 'actionType') = 'createCard') or (Str(Act, 'actionType') = 'addSwimlane') or
                (Str(Act, 'actionType') = 'moveAllCardsInList')) then
              begin
                A.CardId := '';
                PerformAction(T, A, Act);
              end
              else
                for c := 0 to High(Cards) do
                begin
                  A.CardId := Cards[c];
                  PerformAction(T, A, Act);
                end;
              Ran := True;
            finally
              A.Data.Free;
              Act.Free;
            end;
          end;
        end;
      finally
        Rules.Free;
      end;
      // The minute is the trigger's: it does not run again in it.
      Fields := TJSONObject.Create(['lastRunKey', Slot, 'lastRunAt', NowMs]);
      try
        Sql := UpdateDocSql(T.Db, 'triggers', Str(Trig, '_id'), Fields, '{"lastRunAt":"date"}');
      finally
        Fields.Free;
      end;
      if not T.Db.Exec('BEGIN IMMEDIATE; ' + Sql + 'COMMIT;') then T.Db.Exec('ROLLBACK;');
      // What the actions did starts the board's other rules, as a request's
      // writes do.
      if Ran then RunRulesSince(T, Stamp);
    except
      // One bad rule never stops the scan.
    end;
  finally
    Triggers.Free;
  end;
end;

var
  WriterLock: TRTLCriticalSection;
  WriterPage: string;
  WriterAt: TDateTime;

function RecentWriterPage: string;
begin
  EnterCriticalSection(WriterLock);
  try
    if (WriterPage <> '') and (SecondsBetween(Now, WriterAt) <= 5) then Result := WriterPage else Result := '';
  finally
    LeaveCriticalSection(WriterLock);
  end;
end;

function RulesSignature(Db: TWLDb; const BoardId: string): string;
var Raw, Tbl: string; R: TWLRows;
begin
  Result := '';
  if not CollectionTable(Db, 'rules', Raw, Tbl) then Exit;
  // What a rule is, not when it was written: a REST edit keeps modifiedAt.
  R := Db.Query('SELECT COALESCE(group_concat(COALESCE(' + DocField('_id') + ','''')||'':''||COALESCE(' + DocField('triggerId') +
    ','''')||'':''||COALESCE(' + DocField('actionId') + ','''')||'':''||COALESCE(' + DocField('buttonType') + ','''')||'':''||' +
    'COALESCE(' + DocField('buttonLabel') + ','''')||'':''||COALESCE(json_type(_ferretdb_sjson,''$.enabled''),'''')||'':''||' +
    'COALESCE(' + DocField('title') + ',''''),char(10)),'''') FROM ' + Tbl + ' WHERE ' + DocField('boardId') + '=' + Q(BoardId) + ';');
  if Length(R) = 1 then Result := R[0][0];
end;

// A change every page draws again, the one that made it too: a rule's
// buttons are drawn by the server (Weddy's hub.publish, not publishFrom).
procedure AnnounceToAll;
begin
  EnterCriticalSection(WriterLock);
  try
    WriterPage := '';
  finally
    LeaveCriticalSection(WriterLock);
  end;
end;

procedure NoteWriter(Request: TRequest);
var Page: string; i: Integer;
begin
  Page := Request.GetCustomHeader('X-Weddy-Page');
  if Page = '' then Page := Request.GetCustomHeader('X-Weddy-Live');
  if (Page = '') or (Length(Page) > 64) then Exit;
  for i := 1 to Length(Page) do
    if not (Page[i] in ['0'..'9', 'a'..'z', 'A'..'Z', '-', '_']) then Exit;
  EnterCriticalSection(WriterLock);
  try
    WriterPage := Page;
    WriterAt := Now;
  finally
    LeaveCriticalSection(WriterLock);
  end;
end;

procedure ArmRules(Request: TRequest);
begin
  if (Request <> nil) and (Request.Method <> 'GET') and (Request.Method <> 'HEAD') then NoteWriter(Request);
  ArmedRequest := nil;
  ArmedStamp := '';
  if (Request = nil) or (Request.Method = 'GET') or (Request.Method = 'HEAD') or (Request.Method = 'OPTIONS') then Exit;
  ArmedRequest := Request;
  // A millisecond before: an activity of this request is never older.
  ArmedStamp := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', IncMilliSecond(LocalTimeToUniversal(Now), -1));
end;

procedure FlushRules;
var Request: TRequest; Stamp: string; T: TWLTenant;
begin
  Request := ArmedRequest;
  Stamp := ArmedStamp;
  ArmedRequest := nil;
  ArmedStamp := '';
  if Request = nil then Exit;
  try
    if ResolveTenant(Request, T) and TenantOpen(T) then RunRulesSince(T, Stamp);
  except
    // A rule that fails never fails the request that started it.
  end;
end;

procedure SendResponse(Response: TResponse);
begin
  FlushRules;
  Response.SendContent;
end;

initialization
  InitCriticalSection(WriterLock);
finalization
  DoneCriticalSection(WriterLock);
end.
