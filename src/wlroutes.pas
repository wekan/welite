unit wlroutes;

{
  WeKan-Lite — WeKan's URL routes (config/router.js and models/lib/adminUrls.js
  in WeKan), so a WeKan link opens the same page in WeLite:

    /b/:id/:slug                  a board
    /b/:boardId/:slug/:cardId     a card on it
    /sign-up                      registration

  A board's slug is not checked, as in WeKan: /b/<id>/anything is that board.
  WeLite's own page routes from before (/board?id=, /board/card?id=&card=,
  /register) stay as aliases of the same pages, so old links keep working;
  WeLite builds every new link with the WeKan route.

  Pure apart from BoardSlug, which reads boards.slug: tests/routes.py checks
  the builders and the parser as plain data.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, HTTPDefs, wldb;

// /b/<id>/<slug>, each part URL-encoded; an empty slug is WeKan's default "board".
function BoardRoute(const BoardId, Slug: string): string;
// /b/<boardId>/<slug>/<cardId>
function CardRoute(const BoardId, Slug, CardId: string): string;

// The board's slug as stored (boards.slug), or "board" when there is none.
function BoardSlug(Db: TWLDb; const BoardId: string): string;

// Splits a WeKan board or card path. Returns False for anything else, including
// /b/templates (WeKan's templates container) and a path with more parts.
function SplitBoardRoute(const Path: string; out BoardId, Slug, CardId: string): Boolean;

// Rewrites a request for a WeKan route to the WeLite page that serves it:
// PathInfo becomes that page's path and the route's parts become its query
// fields. Returns True when the request was rewritten.
function RewriteWeKanRoute(Request: TRequest): Boolean;

implementation

function Part(const Value: string): string;
begin
  Result := HTTPEncode(Value);
end;

function BoardRoute(const BoardId, Slug: string): string;
var S: string;
begin
  S := Slug;
  if S = '' then S := 'board';
  Result := '/b/' + Part(BoardId) + '/' + Part(S);
end;

function CardRoute(const BoardId, Slug, CardId: string): string;
begin
  Result := BoardRoute(BoardId, Slug) + '/' + Part(CardId);
end;

function BoardSlug(Db: TWLDb; const BoardId: string): string;
var Rows: TWLRows;
begin
  Result := 'board';
  if (Db = nil) or (BoardId = '') then Exit;
  try
    Rows := Db.Query('SELECT slug FROM boards WHERE id=' + QuotedStr(BoardId) + ' LIMIT 1;');
  except
    Exit;
  end;
  if (Length(Rows) = 1) and (Length(Rows[0]) = 1) and (Trim(Rows[0][0]) <> '') then
    Result := Rows[0][0];
end;

function SplitBoardRoute(const Path: string; out BoardId, Slug, CardId: string): Boolean;
var Rest: string; Parts: array of string; i, Start: Integer;
begin
  Result := False;
  BoardId := ''; Slug := ''; CardId := '';
  if Copy(Path, 1, 3) <> '/b/' then Exit;
  Rest := Copy(Path, 4, MaxInt);
  // A trailing slash is the same route, as in FlowRouter.
  if (Rest <> '') and (Rest[Length(Rest)] = '/') then Delete(Rest, Length(Rest), 1);
  SetLength(Parts, 0);
  Start := 1;
  for i := 1 to Length(Rest) + 1 do
    if (i > Length(Rest)) or (Rest[i] = '/') then
    begin
      SetLength(Parts, Length(Parts) + 1);
      Parts[High(Parts)] := HTTPDecode(Copy(Rest, Start, i - Start));
      Start := i + 1;
    end;
  // /b/:id/:slug/rules/export: the Rules page's downloads.
  if (Length(Parts) = 4) and (Parts[2] = 'rules') and (Parts[3] = 'export') then
  begin
    BoardId := Parts[0]; Slug := Parts[1]; CardId := 'rules/export';
    Exit(True);
  end;
  if (Length(Parts) < 1) or (Length(Parts) > 3) then Exit;
  for i := 0 to High(Parts) do
    if Parts[i] = '' then Exit;
  // WeKan's /b/templates is a page of its own.
  if Parts[0] = 'templates' then Exit;
  BoardId := Parts[0];
  if Length(Parts) > 1 then Slug := Parts[1];
  if Length(Parts) > 2 then CardId := Parts[2];
  Result := True;
end;

function RewriteWeKanRoute(Request: TRequest): Boolean;
var Path, BoardId, Slug, CardId: string;
begin
  Result := False;
  Path := Request.PathInfo;
  if Path = '/sign-up' then
  begin
    Request.PathInfo := '/register';
    Exit(True);
  end;
  if not SplitBoardRoute(Path, BoardId, Slug, CardId) then Exit;
  Request.QueryFields.Values['id'] := BoardId;
  // WeKan's /b/:id/:slug/rules: the board's Rules page (wlrules).
  if CardId = 'rules' then
    Request.PathInfo := '/board/rules'
  else if CardId = 'rules/export' then
    Request.PathInfo := '/board/rules/export'
  else if CardId = '' then
    Request.PathInfo := '/board'
  else
  begin
    Request.QueryFields.Values['card'] := CardId;
    Request.PathInfo := '/board/card';
  end;
  Result := True;
end;

end.
