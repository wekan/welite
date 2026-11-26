unit wlsched;

{
  WeKan-Lite — when a scheduled rule trigger fires, and which cards it acts
  on: WeKan's server/scheduledRules.js (calendarDue, the time of day),
  models/lib/cronSchedule.js (five-field cron, in UTC as GitHub Actions runs
  it) and models/lib/scheduledDueFilter.js (a card's due or start date set,
  soon or overdue by some days).

  Pure: tests/sched.py compares each with WeKan's own JavaScript.
}

{$mode objfpc}{$H+}

interface

// Whether the five-field cron expression is valid, and fires in the minute
// of Utc.
function IsValidCron(const Expression: string): Boolean;
function CronMatches(const Expression: string; Utc: TDateTime): Boolean;
// A calendar schedule's day condition on the local day of Local: once (on
// OnDate, YYYY-MM-DD), daily, weekday (Monday to Friday), weekly (on Weekday,
// 0 = Sunday) or monthly (on DayOfMonth).
function CalendarDue(const ScheduleType, OnDate, Weekday, DayOfMonth: string; Local: TDateTime): Boolean;
// matchesScheduledDate: the card's date (ISO text, '' unset) and the
// trigger's dueCondition (set, soon, overdue) within Days days of NowMs.
function MatchesScheduledDate(const Value, Condition: string; Days: Double; NowMs: Int64): Boolean;
// The minute a trigger last ran in (lastRunKey): YYYY-MM-DD HH:MM, local.
function SlotKey(Local: TDateTime): string;
function HourMinute(Local: TDateTime): string;

implementation

uses SysUtils, StrUtils, DateUtils;

type
  TSet = array[0..59] of Boolean;
  TCron = record
    Minutes, Hours, Days, Months, Weekdays: TSet;
    DayRestricted, WeekdayRestricted: Boolean;
  end;

const
  MONTHS: array[0..11] of string = ('JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC');
  WEEKDAYS: array[0..6] of string = ('SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT');

function Digits(const S: string): Boolean;
var i: Integer;
begin
  Result := S <> '';
  for i := 1 to Length(S) do if not (S[i] in ['0'..'9']) then Exit(False);
end;

// A field's value: a number in range, or a month or weekday name.
function ValueOf(const Text: string; Field, Min, Max: Integer; out N: Integer): Boolean;
var i: Integer; Up: string;
begin
  Up := UpperCase(Text);
  if Field = 3 then for i := 0 to 11 do if MONTHS[i] = Up then begin N := i + 1; Exit(True); end;
  if Field = 4 then for i := 0 to 6 do if WEEKDAYS[i] = Up then begin N := i; Exit(True); end;
  if not Digits(Text) or (Length(Text) > 3) then Exit(False);
  N := StrToInt(Text);
  Result := (N >= Min) and (N <= Max);
end;

function ParseField(const Text: string; Field: Integer; out S: TSet): Boolean;
const MINS: array[0..4] of Integer = (0, 0, 1, 1, 0); MAXS: array[0..4] of Integer = (59, 23, 31, 12, 7);
var Parts: TStringArray; Part, Range, StepText: string; i, Slash, Dash, Step, From_, To_, n: Integer;
begin
  for i := 0 to 59 do S[i] := False;
  Result := False;
  if Text = '' then Exit;
  Parts := Text.Split([',']);
  for i := 0 to High(Parts) do
  begin
    Part := Parts[i];
    Slash := Pos('/', Part);
    if Slash > 0 then
    begin
      Range := Copy(Part, 1, Slash - 1); StepText := Copy(Part, Slash + 1, MaxInt);
      if not Digits(StepText) or (Length(StepText) > 3) then Exit;
      Step := StrToInt(StepText);
      if Step < 1 then Exit;
    end
    else begin Range := Part; Step := 1; end;
    if (Range = '') or (Pos('/', Range) > 0) then Exit;
    if Range = '*' then
    begin
      From_ := MINS[Field];
      if Field = 4 then To_ := 6 else To_ := MAXS[Field];
    end
    else
    begin
      Dash := Pos('-', Range);
      if Dash > 0 then
      begin
        if not ValueOf(Copy(Range, 1, Dash - 1), Field, MINS[Field], MAXS[Field], From_) or
          not ValueOf(Copy(Range, Dash + 1, MaxInt), Field, MINS[Field], MAXS[Field], To_) then Exit;
      end
      else
      begin
        if not ValueOf(Range, Field, MINS[Field], MAXS[Field], From_) then Exit;
        if Slash > 0 then
        begin
          if Field = 4 then To_ := 6 else To_ := MAXS[Field];
        end
        else To_ := From_;
      end;
    end;
    if From_ > To_ then Exit;
    n := From_;
    while n <= To_ do
    begin
      if (Field = 4) and (n = 7) then S[0] := True else S[n] := True;
      Inc(n, Step);
    end;
  end;
  Result := True;
end;

function ParseCron(const Expression: string; out C: TCron): Boolean;
var Parts: TStringArray; Clean: string; i: Integer;
begin
  Result := False;
  Clean := Trim(Expression);
  for i := 1 to Length(Clean) do if Clean[i] in [#9, #10, #13] then Clean[i] := ' ';
  while Pos('  ', Clean) > 0 do Clean := StringReplace(Clean, '  ', ' ', [rfReplaceAll]);
  Parts := Clean.Split([' ']);
  if Length(Parts) <> 5 then Exit;
  if not ParseField(Parts[0], 0, C.Minutes) or not ParseField(Parts[1], 1, C.Hours) or not ParseField(Parts[2], 2, C.Days) or
    not ParseField(Parts[3], 3, C.Months) or not ParseField(Parts[4], 4, C.Weekdays) then Exit;
  C.DayRestricted := Parts[2] <> '*';
  C.WeekdayRestricted := Parts[4] <> '*';
  Result := True;
end;

function IsValidCron(const Expression: string): Boolean;
var C: TCron;
begin
  Result := ParseCron(Expression, C);
end;

function CronMatches(const Expression: string; Utc: TDateTime): Boolean;
var C: TCron; Day, Weekday: Boolean;
begin
  Result := False;
  if not ParseCron(Expression, C) then Exit;
  if not C.Minutes[MinuteOf(Utc)] or not C.Hours[HourOf(Utc)] or not C.Months[MonthOf(Utc)] then Exit;
  Day := C.Days[DayOf(Utc)];
  // DayOfWeek: 1 = Sunday.
  Weekday := C.Weekdays[DayOfWeek(Utc) - 1];
  if C.DayRestricted and C.WeekdayRestricted then Result := Day or Weekday
  else Result := Day and Weekday;
end;

function CalendarDue(const ScheduleType, OnDate, Weekday, DayOfMonth: string; Local: TDateTime): Boolean;
var Dow: Integer;
begin
  Dow := DayOfWeek(Local) - 1; // 0 = Sunday
  case ScheduleType of
    'once': Result := OnDate = FormatDateTime('yyyy-mm-dd', Local);
    'daily': Result := True;
    'weekday': Result := (Dow >= 1) and (Dow <= 5);
    'weekly': Result := StrToIntDef(Weekday, -1) = Dow;
    'monthly': Result := StrToIntDef(DayOfMonth, -1) = DayOf(Local);
  else Result := False;
  end;
end;

// An ISO 8601 UTC date (2026-03-21T12:00:00.000Z, its fraction and Z
// optional) as whole milliseconds since 1970, exactly: a TDateTime loses one.
function IsoMs(const Value: string; out Ms: Int64): Boolean;
var Y, Mo, D, H, Mi, S, F, Digit, i: Integer; Day: TDateTime;
  function Num(At, Len: Integer; out N: Integer): Boolean;
  var k: Integer;
  begin
    N := 0;
    Result := At + Len - 1 <= Length(Value);
    if not Result then Exit;
    for k := At to At + Len - 1 do
    begin
      if not (Value[k] in ['0'..'9']) then Exit(False);
      N := N * 10 + Ord(Value[k]) - Ord('0');
    end;
  end;
begin
  Result := False;
  if (Length(Value) < 19) or (Value[5] <> '-') or (Value[8] <> '-') or not (Value[11] in ['T', ' ']) or (Value[14] <> ':') or (Value[17] <> ':') then Exit;
  if not (Num(1, 4, Y) and Num(6, 2, Mo) and Num(9, 2, D) and Num(12, 2, H) and Num(15, 2, Mi) and Num(18, 2, S)) then Exit;
  F := 0;
  i := 20;
  if (i <= Length(Value)) and (Value[i] = '.') then
  begin
    Inc(i);
    Digit := 0;
    while (i <= Length(Value)) and (Value[i] in ['0'..'9']) do
    begin
      if Digit < 3 then F := F * 10 + Ord(Value[i]) - Ord('0');
      Inc(Digit); Inc(i);
    end;
    while Digit < 3 do begin F := F * 10; Inc(Digit); end;
  end;
  if not TryEncodeDate(Y, Mo, D, Day) or (H > 23) or (Mi > 59) or (S > 59) then Exit;
  Ms := ((DateTimeToUnix(Day, True) + H * 3600 + Mi * 60 + S) * 1000) + F;
  Result := True;
end;

function MatchesScheduledDate(const Value, Condition: string; Days: Double; NowMs: Int64): Boolean;
var AtMs, Window: Int64;
begin
  Result := False;
  if (Value = '') or not IsoMs(Value, AtMs) then Exit;
  if Days <> Days then Days := 0;
  Window := Round(Days * 24 * 60 * 60 * 1000);
  case Condition of
    'set': Result := True;
    'soon': Result := (AtMs >= NowMs) and (AtMs - NowMs <= Window);
    'overdue': Result := NowMs - AtMs >= Window;
  end;
end;

function SlotKey(Local: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn', Local);
end;

function HourMinute(Local: TDateTime): string;
begin
  Result := FormatDateTime('hh:nn', Local);
end;

end.
