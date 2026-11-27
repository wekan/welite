program FoldTest;
{$mode objfpc}{$H+}{$codepage utf8}

uses SysUtils, wldb, wlfold;

var Db: TWLDb;
    Rows: TWLRows;

procedure Check(const LabelName, Expected: string);
begin
  Rows := Db.Query('SELECT id FROM board_labels WHERE ' +
    LabelFoldMatch('board_labels.name', LabelName) + ';');
  if Expected = '' then
  begin
    if Length(Rows) <> 0 then Halt(1);
  end
  else if (Length(Rows) <> 1) or (Rows[0][0] <> Expected) then Halt(1);
end;

begin
  Db := WLDbOpen(ParamStr(1));
  try
    if not Db.Exec('CREATE TABLE board_labels(id TEXT, name TEXT); ' +
      'INSERT INTO board_labels VALUES (''1'',''Ääni''),(''2'',''ΣΤΑΣΗ''),' +
      '(''3'',''Straße''),(''4'',''𐐀'');') then Halt(1);
    Check('ÄÄNI', '1');
    Check('σταση', '2');
    Check('STRASSE', '3');
    Check('𐐨', '4');
    Check('Straße extra', '');
    WriteLn('PASS: SQLite Unicode case folding');
  finally
    Db.Free;
  end;
end.
