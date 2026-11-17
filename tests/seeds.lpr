program seeds;
{$mode objfpc}{$H+}
{$CODEPAGE UTF8}
uses SysUtils,wlseed;
var Folder,SQL:string;Mode,Calls,i:Integer;
procedure Need(Condition:Boolean;const Message:string);
begin if not Condition then raise Exception.Create(Message);end;
function Embedded(const Name:string;out Text:string):Boolean;
begin
  Inc(Calls);Text:='SELECT ''embedded'';'+#10;Result:=True;
  case Mode of
    1: begin Text:='partial';Result:=False;end;
    2: raise Exception.Create('unavailable resource');
    3: Text:='SELECT 1;'+#0+'SELECT 2;';
    4: Text:=' '+#9+#10;
    5: Text:=StringOfChar('x',MaxSeedBytes+1);
  end;
end;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  Folder:=IncludeTrailingPathDelimiter(ParamStr(1));
  EmbeddedSeedLookup:=nil;
  Need(LoadSeedSQL('schema.sql','',[Folder+'none.sql',Folder+'disk.sql'],SQL),'disk defaults');
  Need(SQL='SELECT ''disk'';'+#10,'disk bytes');
  Need(LoadSeedSQL('designer.sql','',[Folder+'disk.sql'],SQL),'designer defaults');
  Need(not LoadSeedSQL('schema.sql','',[Folder+'nul.sql',Folder+'disk.sql'],SQL),'invalid first default');
  Need(SQL='','invalid default cleared');
  Calls:=0;Mode:=0;EmbeddedSeedLookup:=@Embedded;
  Need(LoadSeedSQL('schema.sql','',[Folder+'disk.sql'],SQL),'embedded default');
  Need((SQL='SELECT ''embedded'';'+#10) and (Calls=1),'embedded precedes disk');
  Need(LoadSeedSQL('designer.sql',Folder+'over.sql',[Folder+'disk.sql'],SQL),'explicit override');
  Need((SQL=UTF8String('SELECT ''override ä 中文'';'+#10)) and (Calls=1),'override BOM and precedence');
  Need(not LoadSeedSQL('robots.txt',Folder+'over.sql',[Folder+'disk.sql'],SQL),'private names only');
  Need((SQL='') and (Calls=1),'unknown name cleared');
  for i:=0 to 4 do
  begin
    case i of
      0: Folder:=IncludeTrailingPathDelimiter(ParamStr(1))+'none.sql';
      1: Folder:=IncludeTrailingPathDelimiter(ParamStr(1))+'nul.sql';
      2: Folder:=IncludeTrailingPathDelimiter(ParamStr(1))+'empty.sql';
      3: Folder:=IncludeTrailingPathDelimiter(ParamStr(1))+'big.sql';
      4: Folder:=IncludeTrailingPathDelimiter(ParamStr(1))+'dir';
    end;
    Need(not LoadSeedSQL('schema.sql',Folder,[],SQL),'invalid explicit file');
    Need((SQL='') and (Calls=1),'explicit failure never falls back');
  end;
  Folder:=IncludeTrailingPathDelimiter(ParamStr(1));
  for Mode:=1 to 5 do
  begin
    Need(not LoadSeedSQL('schema.sql','',[Folder+'disk.sql'],SQL),'invalid embedded SQL');
    Need(SQL='','embedded failure cleared');
  end;
  Writeln('PASS: seed private names, disk defaults, embedded priority, explicit override/BOM, invalid-file and callback refusal without fallback');
end.
