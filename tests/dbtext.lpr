program dbtext;
{$mode objfpc}{$H+}
{$CODEPAGE UTF8}
uses SysUtils, wldb;
var Db: TWLDb; R: TWLRows; Text: string;
procedure Check(Condition: Boolean; const Msg: string);
begin if not Condition then raise Exception.Create('FAIL: '+Msg); end;
begin
  Db:=TWLDb.Create(ParamStr(1));
  try
    Check(Db.Exec('-- schema comment'+#10+'CREATE TABLE textdata(id INTEGER PRIMARY KEY, value TEXT);'),'create');
    Text:=' pipe|comma,quote" apostrophe'' UTF-8: Suomi 日本語 '+#13+#10+'next'+#10+'line ';
    Check(Db.Exec('INSERT INTO textdata VALUES(1,'+QuotedStr(Text)+');'),'insert');
    R:=Db.Query('SELECT value,value,'''',NULL,42 FROM textdata;');
    Check((Length(R)=1) and (Length(R[0])=5),'row shape and duplicate columns');
    Check((R[0][0]=Text) and (R[0][1]=Text),'text round trip');
    Check((R[0][2]='') and (R[0][3]='') and (R[0][4]='42'),'empty, null and numeric');
    Check(not Db.Exec('INSERT INTO textdata VALUES(1,''duplicate'');'),'constraint failure');
    Check(not Db.Exec('INVALID SQL;'),'syntax failure');
    Check(Db.Exec('CREATE TABLE child(id INTEGER REFERENCES textdata(id));'),'foreign key setup');
    Check(not Db.Exec('INSERT INTO child VALUES(999);'),'foreign key rejection');
    R:=Db.Query('SELECT * FROM missing;'); Check(Length(R)=0,'failed query');
    R:=Db.Query('WITH RECURSIVE x(n) AS (VALUES(1) UNION ALL SELECT n+1 FROM x WHERE n<5000) SELECT n,printf(''%0100d'',n) FROM x;');
    Check((Length(R)=5000) and (R[4999][0]='5000'),'large output without pipe deadlock');
    Check(Db.Exec('INSERT INTO textdata VALUES(2,'''');'),'empty insert');
    R:=Db.Query('SELECT value FROM textdata WHERE id=2;');
    Check((Length(R)=1) and (Length(R[0])=1) and (R[0][0]=''),'single empty field');
    Check(Db.Exec('CREATE TABLE deferred_child(id INTEGER REFERENCES textdata(id) DEFERRABLE INITIALLY DEFERRED);'),'deferred setup');
    R:=Db.Query('INSERT INTO deferred_child VALUES(999) RETURNING id;');
    Check(Length(R)=0,'uncommitted RETURNING values withheld after failure');
    R:=Db.Query('SELECT COUNT(*) FROM deferred_child;');
    Check(R[0][0]='0','failed returning write rolled back');
    // More than Linux's per-argument limit, including enough control bytes to
    // exceed SQLite's expression-depth limit if rewritten as a concat per newline.
    Text:=StringOfChar('x',1024*1024)+StringOfChar(#10,2000)+#13+#10+'quote'' 日本語';
    Check(Db.Exec('INSERT INTO textdata VALUES(3,'+QuotedStr(Text)+');'),'large script input');
    R:=Db.Query('SELECT value FROM textdata WHERE id=3;');
    Check((Length(R)=1) and (R[0][0]=Text),'large script exact round trip');
    Check(Db.Exec('/* a quote '' in a block comment */ CREATE TABLE "odd''--name"(value TEXT DEFAULT '+QuotedStr('a'+#13+#10+'b')+'); INSERT INTO "odd''--name" DEFAULT VALUES;'),'quoted identifier and multiline default');
    R:=Db.Query('SELECT value FROM "odd''--name";');
    Check((Length(R)=1) and (R[0][0]='a'+#13+#10+'b'),'comment/default/identifier fidelity');
    Check(Db.Exec('ATTACH DATABASE ''side.db'' AS side; CREATE TABLE side.helper(value TEXT); DETACH DATABASE side;'),'relative attach');
    Check(FileExists('side.db'),'relative SQL paths retain caller directory');
    Writeln('PASS: SQLite text fidelity, command failures, foreign keys and large results');
  finally Db.Free; end;
end.
