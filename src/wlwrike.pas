unit wlwrike;

{
  WeKan-Lite — a Wrike workflow and the board's lists and rules it is, as
  WeKan's models/lib/wrikeWorkflow.js (and Weddy's wrike_workflow.go): a
  workflow is a list of custom statuses, each in one of four groups -
  Active, Completed, Deferred, Cancelled - and a status of a Completed or
  Cancelled group closes a task. A board's lists are the statuses, in board
  order; a rule "moved to X, mark it complete / incomplete" is X's group; a
  list no rule speaks for takes its group from its name.

  Pure: tests/wrike.py checks it as data. wlrules writes what it reads.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses SysUtils, Classes, fpjson;

type
  TWrikeStatus = record
    Name, Group, Color: string; // Color: WeKan's list color, '' for none
  end;
  TWrikeStatuses = array of TWrikeStatus;
  // A list of the board: its title and color.
  TWrikeList = record
    Title, Color: string;
  end;
  TWrikeLists = array of TWrikeList;

const
  MAX_WRIKE_JSON = 1 shl 20;
  MAX_WRIKE_STATUSES = 200;

// The group a list's name alone suggests.
function WrikeGroupForName(const Name: string): string;

// GET /workflows' {kind, data}, its data, or one workflow: the first not
// hidden and not Wrike's standard one is read. False with Error otherwise.
// NotRead counts the workflows and statuses that were left out.
function ReadWrikeWorkflow(const Text: string; out Name: string; out Statuses: TWrikeStatuses;
  out NotRead: Integer; out Error: string): Boolean;

// The board as a workflow: Completion is "listTitle=complete|incomplete" for
// each list a move rule marks (the last rule winning).
function WrikeWorkflowFromBoard(const Title: string; const Lists: TWrikeLists; Completion: TStrings): TJSONObject;

implementation

const
  GROUPS: array[0..3] of string = ('Active', 'Completed', 'Deferred', 'Cancelled');

function GroupColor(const Group: string): string;
begin
  case Group of
    'Active': Result := 'Blue';
    'Completed': Result := 'Green';
    'Deferred': Result := 'Gray';
    'Cancelled': Result := 'Red';
  else Result := 'Gray';
  end;
end;

function WrikeToWeKan(const Color: string): string;
begin
  case Color of
    'Brown': Result := 'saddlebrown'; 'DarkCyan': Result := 'sky'; 'Gray': Result := 'gray'; 'Blue': Result := 'blue';
    'DarkBlue': Result := 'navy'; 'Orange': Result := 'orange'; 'Red': Result := 'red'; 'YellowGreen': Result := 'lime';
    'Purple': Result := 'purple'; 'Yellow': Result := 'yellow'; 'Indigo': Result := 'indigo'; 'DarkRed': Result := 'crimson';
    'Turquoise': Result := 'paleturquoise'; 'Green': Result := 'green';
  else Result := '';
  end;
end;

function WeKanToWrike(const Color: string): string;
begin
  case LowerCase(Color) of
    'white', 'black', 'silver', 'gray': Result := 'Gray';
    'peachpuff', 'orange': Result := 'Orange';
    'pink', 'mistyrose', 'red': Result := 'Red';
    'plum', 'magenta', 'purple': Result := 'Purple';
    'darkgreen', 'green': Result := 'Green';
    'slateblue', 'indigo': Result := 'Indigo';
    'gold', 'yellow': Result := 'Yellow';
    'saddlebrown': Result := 'Brown'; 'sky': Result := 'DarkCyan'; 'blue': Result := 'Blue'; 'navy': Result := 'DarkBlue';
    'lime': Result := 'YellowGreen'; 'crimson': Result := 'DarkRed'; 'paleturquoise': Result := 'Turquoise';
  else Result := '';
  end;
end;

function InWords(const Text: string; const Words: array of string): Boolean;
var W: string;
begin
  for W in Words do
    if Text = W then Exit(True);
  Result := False;
end;

function WrikeGroupForName(const Name: string): string;
var T: string; G: string;
begin
  T := LowerCase(Trim(Name));
  for G in GROUPS do
    if T = LowerCase(G) then Exit(G);
  if InWords(T, ['complete', 'completed', 'done', 'closed', 'finished', 'resolved', 'shipped', 'released', 'delivered',
    'approved', 'accepted']) then Exit('Completed');
  if InWords(T, ['cancelled', 'canceled', 'canceled', 'rejected', 'won''t do', 'wont do', 'won''t fix', 'wont fix', 'wontfix',
    'abandoned', 'dropped', 'declined', 'obsolete', 'invalid', 'duplicate']) then Exit('Cancelled');
  if InWords(T, ['deferred', 'on hold', 'paused', 'someday', 'later', 'parked', 'icebox', 'postponed', 'waiting']) then
    Exit('Deferred');
  Result := 'Active';
end;

// WeKan's trim().slice(0, 128) - counted in characters here (a UTF-8
// character never cut in two).
function WrikeName(const S: string): string;
var i, n: Integer;
begin
  Result := Trim(S);
  n := 0;
  i := 1;
  while i <= Length(Result) do
  begin
    Inc(n);
    if n > 128 then Exit(Copy(Result, 1, i - 1));
    if Ord(Result[i]) >= $F0 then Inc(i, 4)
    else if Ord(Result[i]) >= $E0 then Inc(i, 3)
    else if Ord(Result[i]) >= $C0 then Inc(i, 2)
    else Inc(i);
  end;
end;

function Str(O: TJSONObject; const Name: string): string;
var V: TJSONData;
begin
  Result := '';
  if O = nil then Exit;
  V := O.Find(Name);
  if V = nil then Exit;
  case V.JSONType of
    jtString: Result := V.AsString;
    jtNumber, jtBoolean: Result := V.AsJSON;
  end;
end;

function IsTrue(O: TJSONObject; const Name: string): Boolean;
var V: TJSONData;
begin
  V := O.Find(Name);
  Result := (V <> nil) and (V.JSONType = jtBoolean) and V.AsBoolean;
end;

function ReadWrikeWorkflow(const Text: string; out Name: string; out Statuses: TWrikeStatuses;
  out NotRead: Integer; out Error: string): Boolean;
var Root, V: TJSONData; All: TJSONArray; Chosen, St: TJSONObject; i, k, Pass: Integer; Group, SName: string; Dup: Boolean;
begin
  Result := False; Name := ''; Statuses := nil; NotRead := 0; Error := '';
  if Length(Text) > MAX_WRIKE_JSON then begin Error := 'Wrike workflow JSON is larger than 1 MB'; Exit; end;
  try
    Root := GetJSON(Text);
  except
    Error := 'Wrike workflow is not JSON';
    Exit;
  end;
  All := TJSONArray.Create;
  try
    if Root is TJSONArray then
      for i := 0 to Root.Count - 1 do All.Add(Root.Items[i].Clone)
    else if Root is TJSONObject then
    begin
      V := TJSONObject(Root).Find('data');
      if V is TJSONArray then
        for i := 0 to V.Count - 1 do All.Add(V.Items[i].Clone)
      else if TJSONObject(Root).Find('customStatuses') is TJSONArray then
        All.Add(Root.Clone);
    end;
    if All.Count = 0 then
    begin
      Error := 'Wrike workflow JSON has no workflow: expected GET /workflows'' { "kind": "workflows", "data": [...] }';
      Exit;
    end;
    Chosen := nil;
    for Pass := 0 to 2 do
      for i := 0 to All.Count - 1 do
        if (Chosen = nil) and (All.Items[i] is TJSONObject) and (TJSONObject(All.Items[i]).Find('customStatuses') is TJSONArray) then
          case Pass of
            0: if not IsTrue(All.Objects[i], 'hidden') and not IsTrue(All.Objects[i], 'standard') then Chosen := All.Objects[i];
            1: if not IsTrue(All.Objects[i], 'hidden') then Chosen := All.Objects[i];
            2: Chosen := All.Objects[i];
          end;
    if Chosen = nil then begin Error := 'Wrike workflow JSON has no workflow with customStatuses'; Exit; end;
    NotRead := All.Count - 1;
    V := Chosen.Find('customStatuses');
    for i := 0 to V.Count - 1 do
    begin
      if not (V.Items[i] is TJSONObject) then begin Inc(NotRead); Continue; end;
      St := TJSONObject(V.Items[i]);
      SName := Trim(Str(St, 'name'));
      if (SName = '') or IsTrue(St, 'hidden') then begin Inc(NotRead); Continue; end;
      Group := Str(St, 'group');
      if not ((Group = 'Active') or (Group = 'Completed') or (Group = 'Deferred') or (Group = 'Cancelled')) then
      begin
        Group := WrikeGroupForName(SName);
        Inc(NotRead);
      end;
      Dup := False;
      for k := 0 to High(Statuses) do
        if Statuses[k].Name = SName then Dup := True;
      if Dup then begin Inc(NotRead); Continue; end;
      SetLength(Statuses, Length(Statuses) + 1);
      Statuses[High(Statuses)].Name := SName;
      Statuses[High(Statuses)].Group := Group;
      Statuses[High(Statuses)].Color := WrikeToWeKan(Str(St, 'color'));
    end;
    Name := Trim(Str(Chosen, 'name'));
    if Name = '' then Name := 'Wrike workflow';
    if Length(Statuses) = 0 then begin Error := 'Wrike workflow "' + Name + '" has no status to read'; Exit; end;
    if Length(Statuses) > MAX_WRIKE_STATUSES then
    begin
      Inc(NotRead, Length(Statuses) - MAX_WRIKE_STATUSES);
      SetLength(Statuses, MAX_WRIKE_STATUSES);
    end;
    Result := True;
  finally
    All.Free;
    Root.Free;
  end;
end;

function GroupForList(const Title: string; Completion: TStrings): string;
begin
  Result := WrikeGroupForName(Title);
  if Completion = nil then Exit;
  if Completion.Values[Title] = 'complete' then
  begin
    if Result <> 'Cancelled' then Result := 'Completed';
  end
  else if Completion.Values[Title] = 'incomplete' then
    if Result <> 'Deferred' then Result := 'Active';
end;

function StatusDoc(const Name, Color, Group: string): TJSONObject;
begin
  Result := TJSONObject.Create(['name', Name, 'standardName', False, 'color', Color, 'standard', False, 'group', Group,
    'hidden', False]);
end;

function WrikeWorkflowFromBoard(const Title: string; const Lists: TWrikeLists; Completion: TStrings): TJSONObject;
var Statuses: TJSONArray; Seen: TStringList; i, n: Integer; T, Name, Group, Color: string; Has: Boolean; G: string; Wf: TJSONObject;
  function Taken(const S: string): Boolean;
  var j: Integer;
  begin
    for j := 0 to Statuses.Count - 1 do
      if Statuses.Objects[j].Strings['name'] = S then Exit(True);
    Result := False;
  end;
begin
  Statuses := TJSONArray.Create;
  Seen := TStringList.Create;
  try
    for i := 0 to High(Lists) do
    begin
      T := Trim(Lists[i].Title);
      if (T = '') or (Seen.IndexOf(T) >= 0) then Continue;
      Seen.Add(T);
      Name := WrikeName(T);
      n := 2;
      while Taken(Name) do
      begin
        Name := WrikeName(Copy(T, 1, 124)) + ' (' + IntToStr(n) + ')';
        Inc(n);
      end;
      Group := GroupForList(T, Completion);
      Color := WeKanToWrike(Lists[i].Color);
      if Color = '' then Color := GroupColor(Group);
      Statuses.Add(StatusDoc(Name, Color, Group));
    end;
    for G in ['Active', 'Completed'] do
    begin
      Has := False;
      for i := 0 to Statuses.Count - 1 do
        if Statuses.Objects[i].Strings['group'] = G then Has := True;
      if Has then Continue;
      Name := G;
      n := 2;
      while Taken(Name) do
      begin
        Name := G + ' (' + IntToStr(n) + ')';
        Inc(n);
      end;
      if G = 'Active' then Statuses.Insert(0, StatusDoc(Name, GroupColor(G), G))
      else Statuses.Add(StatusDoc(Name, GroupColor(G), G));
    end;
  finally
    Seen.Free;
  end;
  Name := WrikeName(Title);
  if Name = '' then Name := 'WeKan board';
  Wf := TJSONObject.Create(['name', Name, 'standard', False, 'hidden', False]);
  Wf.Add('customStatuses', Statuses);
  Result := TJSONObject.Create(['kind', 'workflows']);
  Result.Add('data', TJSONArray.Create([Wf]));
end;

end.
