unit wladvf;

{
  WeKan-Lite — WeKan's Advanced Filter (imports/lib/advancedFilter.js), as
  Weddy's advanced_filter.go has it: the language of the Filter sidebar's
  text field.

    Points = 2 and not (Other > 1)      'Field 1' == 'Value 1'
    F1 == /Tes.*/i                      @dueAt < '2026-09-01'   @endAt = none

  A custom field by its name, compared in its own value; a dropdown value by
  its option's name; a number by the whole decimal token; a date field by a
  range; the card's own dates by @name. A filter that does not parse is nil -
  the sidebar keeps showing every card, and says so.

  SQLite has no regular expressions to give, so a filter is a tree that is
  evaluated here, card by card. Pure: tests/advfilter.py checks it as data.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses SysUtils, Classes;

type
  // One custom field of the board: its name, id, type and - a dropdown's -
  // options as name=id.
  TAdvField = record
    Name, Id, Kind: string;
    Options: TStringArray;
  end;
  // One value a card has for a custom field; IsNull for one with no value.
  TAdvValue = record
    FieldId, Value: string;
    IsNull: Boolean;
  end;
  // A card as the filter reads it: its custom field values, and its own
  // dates as stored (ISO, UTC), '' for none.
  TAdvCard = record
    Values: array of TAdvValue;
    Dates: array[0..5] of string;
  end;

  TAdvNode = class
  public
    Kind: Char;   // '&' and, '|' or, '!' not, 'f' a custom field, 'd' a card date
    Left, Right: TAdvNode;
    FieldId, FieldKind, Op: string;
    Equal: TStringArray;
    Number: Double;
    IsRegex, HasRange, IsNone: Boolean;
    Pattern: string;
    IgnoreCase, MultiLine: Boolean;
    RangeStart, RangeEnd: TDateTime;
    DateIndex: Integer;
    destructor Destroy; override;
  end;

const
  // The card's dates by @name, lower case, as cardDateFields names them.
  ADV_DATE_NAMES: array[0..5] of string = ('@createdat', '@receivedat', '@startat', '@dueat', '@endat', '@listenteredat');
  ADV_DATE_COLUMNS: array[0..5] of string = ('createdAt', 'receivedAt', 'startAt', 'dueAt', 'endAt', 'listEnteredAt');

// The filter as a tree, or nil when it does not parse. DayFirst reads an
// ambiguous a/b/yyyy as day/month (the member's date format starts with D).
function ParseAdvancedFilter(const Filter: string; const Fields: array of TAdvField; DayFirst: Boolean = False): TAdvNode;

function AdvancedFilterMatches(Node: TAdvNode; const Card: TAdvCard): Boolean;

implementation

uses Math, DateUtils, RegExpr, fpjson, jsonparser;

destructor TAdvNode.Destroy;
begin
  Left.Free;
  Right.Free;
  inherited Destroy;
end;

type
  TToken = record
    Cmd: string;
    Str, Regex: Boolean;
  end;
  TTokens = array of TToken;

// WeKan's tokenizeAdvancedFilter: '...' quotes a text, /.../ a regex (not
// inside a text), \ escapes the next character outside texts, a space and a
// bracket separate.
function Tokenize(const Filter: string; out Tokens: TTokens): Boolean;
var i: Integer; Ch: Char; Cur: string; InStr, InRegex, WasStr, Ignore: Boolean;
  procedure Push;
  begin
    SetLength(Tokens, Length(Tokens) + 1);
    Tokens[High(Tokens)].Cmd := Cur;
    Tokens[High(Tokens)].Str := WasStr;
    Tokens[High(Tokens)].Regex := InRegex;
    Cur := ''; WasStr := False; InRegex := False;
  end;
begin
  Tokens := nil; Cur := ''; InStr := False; InRegex := False; WasStr := False; Ignore := False;
  for i := 1 to Length(Filter) do
  begin
    Ch := Filter[i];
    if Ignore then begin Ignore := False; Cur := Cur + Ch; Continue; end;
    if (Ch = '/') and (not InStr or InRegex) then
    begin
      InStr := not InStr;
      if InStr then InRegex := True;
      Cur := Cur + Ch;
    end
    else if (Ch = '''') and not InRegex then
    begin
      InStr := not InStr;
      if InStr then WasStr := True;
    end
    else if (Ch = '\') and not InStr then Ignore := True
    else if (Ch in ['(', ')']) and not InStr then
    begin
      if (Cur <> '') or WasStr or InRegex then Push;
      SetLength(Tokens, Length(Tokens) + 1);
      Tokens[High(Tokens)].Cmd := Ch;
      Tokens[High(Tokens)].Str := False;
      Tokens[High(Tokens)].Regex := False;
    end
    else if (Ch = ' ') and not InStr then Push
    else Cur := Cur + Ch;
  end;
  Result := not (InStr or Ignore);
  if Result and ((Cur <> '') or WasStr or InRegex) then Push;
end;

// The whole decimal token, never "2" of "2hours".
function FilterNumber(const V: string; out N: Double): Boolean;
var R: TRegExpr; F: TFormatSettings;
begin
  Result := False; N := 0;
  R := TRegExpr.Create('^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$');
  try
    if not R.Exec(V) then Exit;
  finally
    R.Free;
  end;
  F := DefaultFormatSettings; F.DecimalSeparator := '.'; F.ThousandSeparator := #0;
  Result := TryStrToFloat(V, N, F) and not IsInfinite(N) and not IsNan(N);
end;

// WeKan's buildRange: the day, minute or second typed, in the server's
// time zone, as UTC; a date that does not exist (31 February) is none.
function DateRange(Y, Mo, D: Integer; const H, Mi, Sec: string; out Start, Stop: TDateTime): Boolean;
var Hh, Mm, Ss: Integer; Local: TDateTime;
begin
  Hh := 0; Mm := 0; Ss := 0;
  if H <> '' then begin Hh := StrToInt(H); Mm := StrToInt(Mi); end;
  if Sec <> '' then Ss := StrToInt(Sec);
  Result := TryEncodeDateTime(Y, Mo, D, Hh, Mm, Ss, 0, Local);
  if not Result then Exit;
  if Sec <> '' then Stop := IncSecond(Local)
  else if H <> '' then Stop := IncMinute(Local)
  else Stop := IncDay(Local);
  Start := LocalTimeToUniversal(Local);
  Stop := LocalTimeToUniversal(Stop);
end;

// WeKan's parseAdvancedFilterDate: YYYY-MM-DD, or a/b/YYYY - day first when
// only that can be, or when DayFirst - with an optional time.
function FilterDate(const S: string; DayFirst: Boolean; out Start, Stop: TDateTime): Boolean;
var R: TRegExpr; A, B, Y, Day, Month: Integer; T: string;
begin
  Result := False;
  T := Trim(S);
  R := TRegExpr.Create('^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$');
  try
    if R.Exec(T) then
      Exit(DateRange(StrToInt(R.Match[1]), StrToInt(R.Match[2]), StrToInt(R.Match[3]), R.Match[4], R.Match[5], R.Match[6], Start, Stop));
    R.Expression := '^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$';
    if not R.Exec(T) then Exit;
    A := StrToInt(R.Match[1]); B := StrToInt(R.Match[2]); Y := StrToInt(R.Match[3]);
    Day := B; Month := A;
    if (A > 12) and (B <= 12) then begin Day := A; Month := B; end
    else if (B > 12) and (A <= 12) then begin Day := B; Month := A; end
    else if DayFirst then begin Day := A; Month := B; end;
    Result := DateRange(Y, Month, Day, R.Match[4], R.Match[5], R.Match[6], Start, Stop);
  finally
    R.Free;
  end;
end;

// A stored date: 2026-11-26T10:00:00.000Z, or milliseconds since 1970 as
// a shared store's JSON keeps a date (extra_json's listEnteredAt); as UTC.
function StoredDate(const S: string; out At: TDateTime): Boolean;
var Y, Mo, D, H, Mi, Sec, Ms, i: Integer; Millis: Int64;
begin
  Result := False;
  if (S <> '') and (Length(S) <= 16) then
  begin
    Result := True;
    for i := 1 to Length(S) do
      if not ((S[i] in ['0'..'9']) or ((i = 1) and (S[i] = '-') and (Length(S) > 1))) then Result := False;
    if Result then
    begin
      Millis := StrToInt64(S);
      At := UnixToDateTime(Millis div 1000) + (Millis mod 1000) / MSecsPerDay;
      Exit;
    end;
  end;
  if (Length(S) < 19) or (S[5] <> '-') or (S[8] <> '-') or not (S[11] in ['T', ' ']) then Exit;
  Y := StrToIntDef(Copy(S, 1, 4), -1); Mo := StrToIntDef(Copy(S, 6, 2), -1); D := StrToIntDef(Copy(S, 9, 2), -1);
  H := StrToIntDef(Copy(S, 12, 2), -1); Mi := StrToIntDef(Copy(S, 15, 2), -1); Sec := StrToIntDef(Copy(S, 18, 2), -1);
  Ms := 0;
  if (Length(S) >= 23) and (S[20] = '.') then Ms := StrToIntDef(Copy(S, 21, 3), 0);
  Result := TryEncodeDateTime(Y, Mo, D, H, Mi, Sec, Ms, At);
end;

function IsComparison(const Op: string): Boolean;
begin
  case Op of
    '>', 'gt', '>=', '>==', 'gte', '<', 'lt', '<=', '<==', 'lte': Result := True;
  else Result := False;
  end;
end;

function LowerOp(const Op: string): string;
begin
  // WeKan's cmp names: gt, Gt, GT... but not gT.
  if (Op = 'Gt') or (Op = 'GT') then Exit('gt');
  if (Op = 'Gte') or (Op = 'GTE') then Exit('gte');
  if (Op = 'Lt') or (Op = 'LT') then Exit('lt');
  if (Op = 'Lte') or (Op = 'LTE') then Exit('lte');
  Result := Op;
end;

function ParseAdvancedFilter(const Filter: string; const Fields: array of TAdvField; DayFirst: Boolean): TAdvNode;
var Raw, Tokens: TTokens; i, Pos_: Integer; Failed: Boolean;

  function At(K: Integer): Integer;
  begin
    if K <= High(Tokens) then Result := K else Result := -1;
  end;
  function OpOf(K: Integer): string;
  begin
    if (K < 0) or Tokens[K].Str or Tokens[K].Regex then Exit('');
    Result := LowerCase(Tokens[K].Cmd);
  end;

  function FieldCondition(const Name, Op: string; const Value: TToken): TAdvNode;
  var F, k: Integer; R: TRegExpr; Flags: string; N: Double; Valid: Boolean; Start, Stop: TDateTime;
  begin
    Result := nil;
    F := -1;
    for k := 0 to High(Fields) do if Fields[k].Name = Name then begin F := k; Break; end;
    if (F < 0) or (Fields[F].Id = '') then Exit;
    Result := TAdvNode.Create;
    Result.Kind := 'f'; Result.FieldId := Fields[F].Id; Result.FieldKind := Fields[F].Kind; Result.Op := Op;
    if (Fields[F].Kind = 'date') and FilterDate(Value.Cmd, DayFirst, Start, Stop) then
    begin
      Result.HasRange := True; Result.RangeStart := Start; Result.RangeEnd := Stop;
    end;
    if (Op = '=') or (Op = '==') or (Op = '===') or (Op = '!=') or (Op = '!==') then
    begin
      if Value.Regex then
      begin
        R := TRegExpr.Create('^/(.*?)/([gimy]*)$');
        try
          Valid := R.Exec(Value.Cmd);
          if Valid then begin Result.Pattern := R.Match[1]; Flags := R.Match[2]; end;
        finally
          R.Free;
        end;
        if Valid then
        try
          R := TRegExpr.Create(Result.Pattern);
          try R.Compile; finally R.Free; end;
        except
          Valid := False;
        end;
        if not Valid then begin FreeAndNil(Result); Exit; end;
        Result.IsRegex := True; Result.HasRange := False;
        Result.IgnoreCase := Pos('i', Flags) > 0; Result.MultiLine := Pos('m', Flags) > 0;
        Exit;
      end;
      if Result.HasRange then Exit;
      // The option's id for a dropdown's option name, and the number.
      SetLength(Result.Equal, 1);
      Result.Equal[0] := Value.Cmd;
      for k := 0 to High(Fields[F].Options) do
        if Copy(Fields[F].Options[k], 1, Length(Value.Cmd) + 1) = Value.Cmd + '=' then
        begin
          Result.Equal[0] := Copy(Fields[F].Options[k], Length(Value.Cmd) + 2, MaxInt);
          Break;
        end;
      if FilterNumber(Value.Cmd, N) then Result.Number := N else Result.Number := NaN;
      Exit;
    end;
    Result.Op := LowerOp(Op);
    if not IsComparison(Result.Op) then begin FreeAndNil(Result); Exit; end;
    if Result.HasRange then Exit;
    if not FilterNumber(Value.Cmd, N) then begin FreeAndNil(Result); Exit; end;
    Result.Number := N;
  end;

  function CardDate(const Name, OpTok, Value: TToken): TAdvNode;
  var k, Index: Integer; Op: string; Start, Stop: TDateTime;
  begin
    Result := nil;
    Index := -1;
    for k := 0 to High(ADV_DATE_NAMES) do if LowerCase(Name.Cmd) = ADV_DATE_NAMES[k] then Index := k;
    if (Index < 0) or OpTok.Str or OpTok.Regex or Value.Regex then Exit;
    Op := OpTok.Cmd;
    if LowerCase(Value.Cmd) = 'none' then
    begin
      if not ((Op = '=') or (Op = '==') or (Op = '===') or (Op = '!=') or (Op = '!==')) then Exit;
      Result := TAdvNode.Create;
      Result.Kind := 'd'; Result.DateIndex := Index; Result.Op := Op; Result.IsNone := True;
      Exit;
    end;
    Op := LowerOp(Op);
    if not ((Op = '=') or (Op = '==') or (Op = '===') or (Op = '!=') or (Op = '!==') or IsComparison(Op)) then Exit;
    if not FilterDate(Value.Cmd, DayFirst, Start, Stop) then Exit;
    Result := TAdvNode.Create;
    Result.Kind := 'd'; Result.DateIndex := Index; Result.Op := Op;
    Result.HasRange := True; Result.RangeStart := Start; Result.RangeEnd := Stop;
  end;

  function Expression(Depth: Integer): TAdvNode; forward;

  function Atom(Depth: Integer): TAdvNode;
  var Inner: TAdvNode;
  begin
    Result := nil;
    if Failed or (Depth > 100) then begin Failed := True; Exit; end;
    case OpOf(At(Pos_)) of
      'not', '!':
        begin
          Inc(Pos_);
          Inner := Atom(Depth + 1);
          if Failed then Exit;
          Result := TAdvNode.Create; Result.Kind := '!'; Result.Left := Inner;
          Exit;
        end;
      '(':
        begin
          Inc(Pos_);
          Inner := Expression(Depth + 1);
          if Failed then Exit;
          if OpOf(At(Pos_)) <> ')' then begin Inner.Free; Failed := True; Exit; end;
          Inc(Pos_);
          Exit(Inner);
        end;
      ')': begin Failed := True; Exit; end;
    end;
    if (At(Pos_) < 0) or (Pos_ + 3 > Length(Tokens)) then begin Failed := True; Exit; end;
    Inc(Pos_, 3);
    // name, operator, value: a card date by @name, else a custom field.
    if not Tokens[Pos_ - 3].Str and not Tokens[Pos_ - 3].Regex and (Copy(Tokens[Pos_ - 3].Cmd, 1, 1) = '@') then
      Result := CardDate(Tokens[Pos_ - 3], Tokens[Pos_ - 2], Tokens[Pos_ - 1])
    else if not Tokens[Pos_ - 2].Str then
      Result := FieldCondition(Tokens[Pos_ - 3].Cmd, Tokens[Pos_ - 2].Cmd, Tokens[Pos_ - 1]);
    if Result = nil then Failed := True;
  end;

  function Expression(Depth: Integer): TAdvNode;
  var Right, Node: TAdvNode; O: string; K: Char;
  begin
    Result := Atom(Depth);
    while not Failed do
    begin
      O := OpOf(At(Pos_));
      if (O = 'and') or (O = '&') or (O = '&&') then K := '&'
      else if (O = 'or') or (O = '|') or (O = '||') then K := '|'
      else Exit;
      Inc(Pos_);
      Right := Atom(Depth);
      if Failed then begin Result.Free; Result := nil; Exit; end;
      Node := TAdvNode.Create; Node.Kind := K; Node.Left := Result; Node.Right := Right;
      Result := Node;
    end;
    if Failed then begin Result.Free; Result := nil; end;
  end;

begin
  Result := nil;
  if not Tokenize(Filter, Raw) then Exit;
  Tokens := nil;
  for i := 0 to High(Raw) do
    if (Raw[i].Cmd <> '') or Raw[i].Str or Raw[i].Regex then
    begin
      SetLength(Tokens, Length(Tokens) + 1);
      Tokens[High(Tokens)] := Raw[i];
    end;
  Pos_ := 0; Failed := False;
  Result := Expression(0);
  if Failed or (Pos_ <> Length(Tokens)) then FreeAndNil(Result);
end;

// The scalar values of a stored value: a JSON array's items, else itself.
function Scalars(const Value: string): TStringArray;
var D: TJSONData; i: Integer;
begin
  Result := nil;
  if Copy(Value, 1, 1) = '[' then
  begin
    D := nil;
    try
      try D := GetJSON(Value); except D := nil; end;
      if D is TJSONArray then
      begin
        for i := 0 to TJSONArray(D).Count - 1 do
          if TJSONArray(D).Items[i].JSONType in [jtString, jtNumber, jtBoolean] then
          begin
            SetLength(Result, Length(Result) + 1);
            Result[High(Result)] := TJSONArray(D).Items[i].AsString;
          end;
        Exit;
      end;
    finally
      D.Free;
    end;
  end;
  SetLength(Result, 1);
  Result[0] := Value;
end;

function InRange(const V: string; Node: TAdvNode; out Inside: Boolean): Boolean;
var At: TDateTime;
begin
  Result := StoredDate(V, At);
  Inside := Result and (At >= Node.RangeStart) and (At < Node.RangeEnd);
end;

function DateCompare(const V: string; Node: TAdvNode): Boolean;
var At: TDateTime; Inside: Boolean;
begin
  if not StoredDate(V, At) then Exit(False);
  case Node.Op of
    '=', '==', '===': Result := InRange(V, Node, Inside) and Inside;
    '!=', '!==': Result := not (InRange(V, Node, Inside) and Inside);
    '>', 'gt': Result := At >= Node.RangeEnd;
    '>=', '>==', 'gte': Result := At >= Node.RangeStart;
    '<', 'lt': Result := At < Node.RangeStart;
    '<=', '<==', 'lte': Result := At < Node.RangeEnd;
  else Result := False;
  end;
end;

function Numeric(const Kind: string): Boolean;
begin
  Result := (Kind = 'number') or (Kind = 'currency');
end;

// One stored value against a custom field condition (Mongo's $elemMatch on
// the card's entry for that field).
function ValueMatches(Node: TAdvNode; const V: TAdvValue): Boolean;
var S: TStringArray; i: Integer; N: Double; R: TRegExpr; Inside, Negate: Boolean;
begin
  Negate := (Node.Op = '!=') or (Node.Op = '!==');
  if V.IsNull then
    // null is in nothing, compares with nothing, and matches no regex.
    Exit(Negate);
  S := Scalars(V.Value);
  if Node.IsRegex then
  begin
    Result := False;
    if not Numeric(Node.FieldKind) and (Node.FieldKind <> 'date') and (Node.FieldKind <> 'checkbox') then
    begin
      R := TRegExpr.Create(Node.Pattern);
      try
        R.ModifierI := Node.IgnoreCase; R.ModifierM := Node.MultiLine;
        for i := 0 to High(S) do if R.Exec(S[i]) then begin Result := True; Break; end;
      finally
        R.Free;
      end;
    end;
    if Negate then Result := not Result;
    Exit;
  end;
  if Node.HasRange then
  begin
    if Negate then
    begin
      Result := not (InRange(V.Value, Node, Inside) and Inside);
      Exit;
    end;
    Result := DateCompare(V.Value, Node);
    Exit;
  end;
  if (Node.Op = '=') or (Node.Op = '==') or (Node.Op = '===') or Negate then
  begin
    Result := False;
    for i := 0 to High(S) do
      if (S[i] = Node.Equal[0]) or (Numeric(Node.FieldKind) and not IsNan(Node.Number) and FilterNumber(S[i], N) and (N = Node.Number)) then
      begin Result := True; Break; end;
    if Negate then Result := not Result;
    Exit;
  end;
  // A comparison: only a number compares with a number.
  Result := False;
  if not Numeric(Node.FieldKind) then Exit;
  for i := 0 to High(S) do
    if FilterNumber(S[i], N) then
      case Node.Op of
        '>', 'gt': if N > Node.Number then Exit(True);
        '>=', '>==', 'gte': if N >= Node.Number then Exit(True);
        '<', 'lt': if N < Node.Number then Exit(True);
        '<=', '<==', 'lte': if N <= Node.Number then Exit(True);
      end;
end;

function AdvancedFilterMatches(Node: TAdvNode; const Card: TAdvCard): Boolean;
var i: Integer; V: string; At: TDateTime;
begin
  Result := False;
  if Node = nil then Exit;
  case Node.Kind of
    '&': Result := AdvancedFilterMatches(Node.Left, Card) and AdvancedFilterMatches(Node.Right, Card);
    '|': Result := AdvancedFilterMatches(Node.Left, Card) or AdvancedFilterMatches(Node.Right, Card);
    '!': Result := not AdvancedFilterMatches(Node.Left, Card);
    'f':
      for i := 0 to High(Card.Values) do
        if (Card.Values[i].FieldId = Node.FieldId) and ValueMatches(Node, Card.Values[i]) then Exit(True);
    'd':
      begin
        V := Card.Dates[Node.DateIndex];
        // = none: no date; != none: a date ($type date).
        if Node.IsNone then
        begin
          if (Node.Op = '!=') or (Node.Op = '!==') then Result := StoredDate(V, At)
          else Result := V = '';
          Exit;
        end;
        // A date that is not one never matches a comparison.
        if V = '' then Exit(False);
        Result := DateCompare(V, Node);
      end;
  end;
end;

end.
