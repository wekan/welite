unit wllocale;
{$mode objfpc}{$H+}
interface
uses SysUtils,HTTPDefs,wldb,wlauth,wli18n;
function SessionLanguage(Db:TWLDb;const S:TWLSession):string;
function ViewerLanguage(Db:TWLDb;const S:TWLSession;Request:TRequest):TWLLanguage;
procedure LanguageHeaders(Response:TResponse;const Language:TWLLanguage);
function LanguagePage(Response:TResponse;const Language:TWLLanguage;
  const Title,Body:string;const Direction:string='';const DocType:string='html32'):string;
implementation
uses wlhtml;
function SessionLanguage(Db:TWLDb;const S:TWLSession):string;
var Rows:TWLRows;
begin
  Result:='';
  if (Db=nil) or (S.UserId='') or (S.TenantDb<>ExpandFileName(Db.Path)) then Exit;
  Rows:=Db.Query('SELECT CASE WHEN json_valid(profile_json) THEN CASE WHEN '+
    'json_type(profile_json,''$.language'')=''text'' THEN json_extract(profile_json,''$.language'') '+
    'ELSE '+QuotedStr('')+' END ELSE '+QuotedStr('')+' END FROM users WHERE id='+QuotedStr(S.UserId)+';');
  if (Length(Rows)=1) and (Length(Rows[0])=1) then Result:=Rows[0][0];
end;
function ViewerLanguage(Db:TWLDb;const S:TWLSession;Request:TRequest):TWLLanguage;
begin Result:=ResolveLanguage(RequestLanguageTag(Request),SessionLanguage(Db,S),Request.AcceptLanguage);end;
procedure LanguageHeaders(Response:TResponse;const Language:TWLLanguage);
begin
  Response.SetCustomHeader('Content-Language',StringReplace(Language.Tag,'_','-',[rfReplaceAll]));
  Response.SetCustomHeader('Vary','Accept-Language');
end;
function LanguagePage(Response:TResponse;const Language:TWLLanguage;
  const Title,Body,Direction,DocType:string):string;
var Dir:string;
begin
  if SameText(Direction,'rtl') or SameText(Direction,'ltr') then Dir:=LowerCase(Direction)
  else if Language.Rtl then Dir:='rtl' else Dir:='ltr';
  LanguageHeaders(Response,Language);
  Result:=PageDir(Title,Body,Dir,Language.Tag,DocType);
end;
end.
