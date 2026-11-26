unit wldatef;

{
  WeKan-Lite — the date format a date is drawn in: WeKan's
  models/lib/dateFormatPolicy.js (resolveDateFormat) and
  formatDateByUserPreference.

  The member's own format while their override is on, else the board's while
  its override is on, else Admin Panel / Settings / Appearance's while it is
  enabled (stored under its legacy name hideDateFormat), else YYYY-MM-DD. A
  format that is not one of WeKan's six is never used. Dates stay stored as
  they are; only the text drawn changes.

  Pure: tests/datefmt.py checks it.
}

{$mode objfpc}{$H+}

interface

const
  DATE_FORMATS: array[0..5] of string = ('YYYY-MM-DD', 'DD-MM-YYYY', 'MM-DD-YYYY',
    'YYYY-MM-DD-date-only', 'DD-MM-YYYY-date-only', 'MM-DD-YYYY-date-only');

function ValidDateFormat(const Format: string): Boolean;
function ResolveDateFormat(const Member: string; MemberOverride: Boolean; const Board: string; BoardOverride: Boolean;
  const Global: string; GlobalOn: Boolean): string;
// A stored date (2026-03-21T12:00:00.000Z) as text in Format, its time to
// the minute unless the format is date-only; a value that is no such date
// as it was drawn before (its first 16 characters, T as a space).
function FormatShownDate(const Value, Format: string): string;

implementation

uses SysUtils;

function ValidDateFormat(const Format: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(DATE_FORMATS) do
    if DATE_FORMATS[i] = Format then Exit(True);
  Result := False;
end;

function ResolveDateFormat(const Member: string; MemberOverride: Boolean; const Board: string; BoardOverride: Boolean;
  const Global: string; GlobalOn: Boolean): string;
begin
  if MemberOverride and ValidDateFormat(Member) then Exit(Member);
  if BoardOverride and ValidDateFormat(Board) then Exit(Board);
  if GlobalOn and ValidDateFormat(Global) then Exit(Global);
  Result := DATE_FORMATS[0];
end;

function FormatShownDate(const Value, Format: string): string;
var Y, M, D, Clock, Base: string; WithTime: Boolean; i: Integer;
begin
  Result := StringReplace(Copy(Value, 1, 16), 'T', ' ', []);
  // YYYY-MM-DD, then optionally THH:MM.
  if (Length(Value) < 10) or (Value[5] <> '-') or (Value[8] <> '-') then Exit;
  for i := 1 to 10 do
    if not (i in [5, 8]) and not (Value[i] in ['0'..'9']) then Exit;
  Y := Copy(Value, 1, 4); M := Copy(Value, 6, 2); D := Copy(Value, 9, 2);
  Clock := '';
  if (Length(Value) >= 16) and (Value[11] = 'T') and (Value[14] = ':') then Clock := Copy(Value, 12, 5);
  Base := Format;
  WithTime := True;
  if Copy(Base, Length(Base) - 9, 10) = '-date-only' then
  begin
    Base := Copy(Base, 1, Length(Base) - 10);
    WithTime := False;
  end;
  if Base = 'DD-MM-YYYY' then Result := D + '-' + M + '-' + Y
  else if Base = 'MM-DD-YYYY' then Result := M + '-' + D + '-' + Y
  else Result := Y + '-' + M + '-' + D;
  if WithTime and (Clock <> '') then Result := Result + ' ' + Clock;
end;

end.
