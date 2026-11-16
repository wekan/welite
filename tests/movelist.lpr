program movelist;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wldb, wlmove;
var Db: TWLDb; P: TStringList;
procedure Check(const Sql, Expected, LabelText: string);
var R: TWLRows;
begin
  R := Db.Query(Sql);
  if (Length(R)<>1) or (Length(R[0])<>1) or (R[0][0]<>Expected) then
    raise Exception.Create('FAIL: '+LabelText);
end;
procedure Move(const Id, Dir: string);
begin
  P.Clear; P.Add('sel_list='+Id); P.Add('dir='+Dir); ApplyMove(Db,P);
end;
begin
  Db:=TWLDb.Create(ParamStr(1)); P:=TStringList.Create;
  try
    Move('l1','down');
    Check('SELECT swimlaneId FROM lists WHERE id=''l1''','s2','down');
    Check('SELECT sort FROM lists WHERE id=''l1''','8.0','append');
    Check('SELECT COUNT(*) FROM cards WHERE listId=''l1'' AND swimlaneId=''s2''','2','all cards follow');
    Move('l1','down');
    Check('SELECT swimlaneId FROM lists WHERE id=''l1''','s2','bottom edge');
    Move('l1','up');
    Check('SELECT swimlaneId FROM lists WHERE id=''l1''','s1','up');
    Move('l1','up');
    Check('SELECT swimlaneId FROM lists WHERE id=''l1''','s1','top edge');
    Move('other','down');
    Check('SELECT swimlaneId FROM lists WHERE id=''other''','os','other board edge');
    Move('legacy','down');
    Check('SELECT swimlaneId FROM lists WHERE id=''legacy''','', 'legacy no swimlane');
    Move('archived','up');
    Check('SELECT swimlaneId FROM lists WHERE id=''archived''','s2','archived list');
    Move('missing','down'); Move('l1','invalid');
    Check('SELECT swimlaneId FROM lists WHERE id=''l1''','s1','invalid direction');
    P.Clear; P.Add('dir=down'); P.Add('sel_list=l1'); P.Add('sel_list=l2');
    ApplyMove(Db,P);
    Check('SELECT COUNT(*) FROM lists WHERE id IN (''l1'',''l2'') AND swimlaneId=''s2''','2','multiple lists');
    Check('SELECT COUNT(*) FROM lists WHERE id IN (''l1'',''l2'') AND sort>7','2','multiple append');
    Check('SELECT swimlaneId FROM cards WHERE id=''foreign''','os','foreign board untouched');
    Writeln('PASS: list relocation and boundary cases');
  finally P.Free; Db.Free; end;
end.
