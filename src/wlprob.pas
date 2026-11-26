unit wlprob;

{
  WeKan-Lite — the Admin Panel's Problems for the HTML5 view: the Security
  Report (WeKan's adminProblems.jade eventStreamReport, stream "security"),
  Weddy's securityreport.pug drawn by wltpl.

  Each row is one kind of attempt that a guard refused or noticed - its
  bleed, source, the most recent account and how many times - never a row
  per attempt (models/lib/eventLogSummary.js). A site admin's page: anybody
  else is told they may not see it.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses SysUtils, Classes, fpjson, wldb, wli18n;

const
  SECURITY_REPORT_PER_PAGE = 50;

// The Security Report's content: rows matching Search (category, bleed,
// source, detail, username, IP, severity or action contain it, any case),
// newest first, the Page'th SECURITY_REPORT_PER_PAGE of them.
function SecurityReportContent(Db: TWLDb; Words: TWLTranslator; const Lang, Search: string; Page: Integer): string;

implementation

uses DateUtils, StrUtils, httpdefs, wlcfjson, wltpl, wlcase;

{$I tpl/securityreport.inc}

function Field(const Name: string): string;
begin
  Result := 'json_extract(_ferretdb_sjson,''$.' + Name + ''')';
end;

function Text(Doc: TJSONObject; const Name: string): string;
var V: TJSONData;
begin
  Result := '';
  V := Doc.Find(Name);
  if V = nil then Exit;
  case V.JSONType of
    jtString: Result := V.AsString;
    jtNumber: Result := V.AsJSON;
  end;
end;

function SecurityReportContent(Db: TWLDb; Words: TWLTranslator; const Lang, Search: string; Page: Integer): string;
var R: TWLRows; Tbl, Where, Needle, Name: string; Total, Pages, i: Integer; Data, Row: TJSONObject; Rows: TJSONArray;
  Doc: TJSONObject; Count: Int64; At: TJSONData;
  function Link(P: Integer): string;
  begin
    Result := '/admin/problems/security-report?page=' + IntToStr(P);
    if Search <> '' then Result := Result + '&q=' + HTTPEncode(Search);
  end;
begin
  Total := 0; Rows := TJSONArray.Create;
  Data := TJSONObject.Create;
  try
    Data.Add('L', Lang);
    Data.Add('SecuritySearch', Search);
    Data.Add('SecurityRows', Rows);
    R := Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''eventlog'';');
    if Length(R) = 1 then
    begin
      Tbl := '"' + StringReplace(R[0][0], '"', '""', [rfReplaceAll]) + '"';
      Where := Field('stream') + '=''security''';
      if Search <> '' then
      begin
        Needle := QuotedStr('%' + StringReplace(StringReplace(Utf8Lower(Search), '%', '\%', [rfReplaceAll]), '_', '\_', [rfReplaceAll]) + '%');
        Where := Where + ' AND (';
        for Name in ['category', 'bleed', 'source', 'detail', 'username', 'ip', 'severity', 'action'] do
          Where := Where + IfThen(Name <> 'category', ' OR ', '') + 'lower(COALESCE(' + Field(Name) + ','''')) LIKE ' + Needle + ' ESCAPE ''\''';
        Where := Where + ')';
      end;
      R := Db.Query('SELECT count(*) FROM ' + Tbl + ' WHERE ' + Where + ';');
      if Length(R) = 1 then Total := StrToIntDef(R[0][0], 0);
      Pages := (Total + SECURITY_REPORT_PER_PAGE - 1) div SECURITY_REPORT_PER_PAGE;
      if Pages < 1 then Pages := 1;
      if Page < 1 then Page := 1;
      if Page > Pages then Page := Pages;
      R := Db.Query('SELECT json(_ferretdb_sjson) FROM ' + Tbl + ' WHERE ' + Where + ' ORDER BY ' + Field('at') + ' DESC LIMIT ' +
        IntToStr(SECURITY_REPORT_PER_PAGE) + ' OFFSET ' + IntToStr((Page - 1) * SECURITY_REPORT_PER_PAGE) + ';');
      for i := 0 to High(R) do
      begin
        try
          Doc := DocumentJson(R[i][0]);
        except
          Continue;
        end;
        try
          Row := TJSONObject.Create(['Category', Text(Doc, 'category'), 'Bleed', Text(Doc, 'bleed'), 'Severity', Text(Doc, 'severity'),
            'Action', Text(Doc, 'action'), 'Source', Text(Doc, 'source'), 'Username', Text(Doc, 'username'), 'IP', Text(Doc, 'ip'),
            'Detail', Text(Doc, 'detail')]);
          // The date as Weddy shows it: UTC, "2006-01-02 15:04:05".
          At := Doc.Find('at');
          if (At <> nil) and (At.JSONType = jtString) then
            Row.Add('Date', StringReplace(Copy(At.AsString, 1, 19), 'T', ' ', []))
          else Row.Add('Date', '');
          Count := 0;
          if (Doc.Find('count') <> nil) and (Doc.Find('count').JSONType = jtNumber) then Count := Doc.Find('count').AsInt64;
          if Count > 1 then Row.Add('Attempts', IntToStr(Count)) else Row.Add('Attempts', '');
          Rows.Add(Row);
        finally
          Doc.Free;
        end;
      end;
    end
    else Pages := 1;
    if Page < 1 then Page := 1;
    Data.Add('SecurityTotal', IntToStr(Total));
    Data.Add('SecurityPage', IntToStr(Page));
    Data.Add('SecurityPages', IntToStr(Pages));
    if Page > 1 then Data.Add('SecurityPrev', Link(Page - 1)) else Data.Add('SecurityPrev', '');
    if Page < Pages then Data.Add('SecurityNext', Link(Page + 1)) else Data.Add('SecurityNext', '');
    Result := RenderTemplate(TPL_SECURITYREPORT, Data, Words, Lang);
  finally
    Data.Free;
  end;
end;

end.
