unit wlstatic;

{
  WeKan-Lite — static asset serving (docs/static-assets.md)

  Serves the development-time files under public/ at a configured URL mount (default '/'), so
  public/robots.txt -> http://<host>/robots.txt, public/js/interact.js -> /js/interact.js, etc.

  Several roots can be registered, each mapping a URL mount to an on-disk directory. The
  default wiring (wlhttp.lpr) registers two: public/ at '/' and the translations tree i18n/
  at '/i18n' (i18n/languages.json -> /i18n/languages.json, i18n/data/en.i18n.json ->
  /i18n/data/en.i18n.json). i18n used to live under public/i18n + public/languages.json; it is
  now its own tree (i18n/data + i18n/languages.json), served here so URLs stay stable.

  Two sources, tried in order per root — embedded first, then disk:
    * EMBEDDED  : when built with -dWLEMBED, the generated `wlassets` unit registers an
                  EmbeddedLookup that reads files bundled into the executable as FPC resources
                  ({$R wlpublic.rc}); true single binary, nothing on disk. Keys are the full
                  URL-relative path (Embed prefix + path under the mount), e.g.
                  'js/interact.js' and 'i18n/data/en.i18n.json'.
    * DISK      : otherwise (dev, and targets without a resource compiler) read from the
                  configured directory for that root, next to the binary.

  Why not embed everything as Pascal const byte arrays? the assets are ~24 MB (mostly i18n JSON);
  byte-array literals would balloon the source past what FPC can compile. FPC *resources*
  bundle the real bytes with no source bloat, so embedding uses those; see docs/static-assets.md
  and the generator releases/genassets.py.

  Static assets are GLOBAL (same for every tenant) and are served before tenant resolution.
  v0.1 reference skeleton.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, Classes, HTTPDefs;

type
  // Provided by the generated `wlassets` unit under -dWLEMBED (nil = disk-only build).
  // Key is the full URL-relative path (the Embed prefix + path under the mount), e.g.
  // 'js/interact.js' or 'i18n/data/en.i18n.json'.
  TEmbeddedLookup = function(const RelPath: string; out Data: TBytes; out Mime: string): Boolean;

var
  EmbeddedLookup: TEmbeddedLookup = nil;

// Configure the primary root: URL mount (e.g. '/') and the on-disk dir (e.g. 'public').
// Resets the root list to just this one. Call once, before any StaticAddRoot.
procedure StaticInit(const AMount, ADiskRoot: string);

// Register an additional root: requests under AMount are served from ADiskRoot on disk, and
// from embedded resources under the AEmbed key prefix (must match what genassets.py emits for
// that tree — e.g. AMount='/i18n', AEmbed='i18n/', ADiskRoot='i18n').
procedure StaticAddRoot(const AMount, AEmbed, ADiskRoot: string);

// Try to serve aRequest's path as a static asset. Returns True if it did (caller stops).
function ServeStatic(aRequest: TRequest; aResponse: TResponse): Boolean;

// MIME type for a file name / extension (public so other units can reuse it).
function MimeForName(const Name: string): string;

implementation

type
  TAssetRoot = record
    Mount: string;   // URL prefix, e.g. '/' or '/i18n'
    Embed: string;   // embedded-resource key prefix, e.g. '' or 'i18n/'
    Dir:   string;   // on-disk directory, with trailing path delimiter
  end;

var
  Roots: array of TAssetRoot;

procedure StaticInit(const AMount, ADiskRoot: string);
begin
  SetLength(Roots, 0);
  StaticAddRoot(AMount, '', ADiskRoot);
end;

procedure StaticAddRoot(const AMount, AEmbed, ADiskRoot: string);
var
  R: TAssetRoot;
begin
  R.Mount := AMount;
  if R.Mount = '' then R.Mount := '/';
  R.Embed := AEmbed;
  R.Dir := IncludeTrailingPathDelimiter(ADiskRoot);
  SetLength(Roots, Length(Roots) + 1);
  Roots[High(Roots)] := R;
end;

function MimeForName(const Name: string): string;
begin
  case LowerCase(ExtractFileExt(Name)) of
    '.html', '.htm':  Result := 'text/html; charset=utf-8';
    '.css':           Result := 'text/css';
    '.js':            Result := 'application/javascript';
    '.json':          Result := 'application/json';
    '.txt':           Result := 'text/plain; charset=utf-8';
    '.xml', '.yml', '.yaml': Result := 'text/plain; charset=utf-8';
    '.svg':           Result := 'image/svg+xml';
    '.png':           Result := 'image/png';
    '.gif':           Result := 'image/gif';
    '.jpg', '.jpeg':  Result := 'image/jpeg';
    '.ico':           Result := 'image/x-icon';
    '.webmanifest', '.default': Result := 'application/manifest+json';
    '.woff':          Result := 'font/woff';
    '.woff2':         Result := 'font/woff2';
  else
    Result := 'application/octet-stream';
  end;
end;

// Strip the given mount prefix and reject path traversal. Returns '' if the path is not under
// the mount or is unsafe.
function RelFromRequest(const Mount, PathInfo: string): string;
var
  P: string;
begin
  Result := '';
  P := PathInfo;
  // strip the configured mount prefix
  if Mount = '/' then
  begin
    if (P <> '') and (P[1] = '/') then Delete(P, 1, 1);
  end
  else
  begin
    if Pos(Mount, P) <> 1 then Exit;
    Delete(P, 1, Length(Mount));
    if (P <> '') and (P[1] = '/') then Delete(P, 1, 1);
  end;
  if P = '' then Exit;                          // a bare mount is not a file
  // safety: no traversal, no absolute, no NUL
  if (Pos('..', P) > 0) or (Pos(#0, P) > 0) or (P[1] = '/') then Exit;
  {$IFDEF WINDOWS}
  if (Length(P) >= 2) and (P[2] = ':') then Exit;
  {$ENDIF}
  Result := P;                                  // forward-slash relative path, e.g. 'js/interact.js'
end;

procedure SendBytes(aResponse: TResponse; const Data: TBytes; const Mime: string);
var
  S: TBytesStream;
begin
  S := TBytesStream.Create(Data);
  aResponse.Code := 200;
  aResponse.ContentType := Mime;
  aResponse.ContentLength := S.Size;
  aResponse.ContentStream := S;
  aResponse.SendContent;
  aResponse.ContentStream := nil;
  S.Free;
end;

function ServeStatic(aRequest: TRequest; aResponse: TResponse): Boolean;
var
  Rel, DiskPath, Mime: string;
  Data: TBytes;
  FS: TFileStream;
  i: Integer;
begin
  Result := False;
  if aRequest.Method <> 'GET' then Exit;

  // Try each registered root (public at '/', i18n at '/i18n', …) in order.
  for i := 0 to High(Roots) do
  begin
    Rel := RelFromRequest(Roots[i].Mount, aRequest.PathInfo);
    if Rel = '' then Continue;

    // 1) embedded (single-binary build): key is the full URL-relative path for this root
    if Assigned(EmbeddedLookup) and EmbeddedLookup(Roots[i].Embed + Rel, Data, Mime) then
    begin
      if Mime = '' then Mime := MimeForName(Rel);
      SendBytes(aResponse, Data, Mime);
      Exit(True);
    end;

    // 2) disk (dev / non-embedded targets)
    DiskPath := Roots[i].Dir + StringReplace(Rel, '/', PathDelim, [rfReplaceAll]);
    if FileExists(DiskPath) then
    begin
      FS := TFileStream.Create(DiskPath, fmOpenRead or fmShareDenyWrite);
      aResponse.Code := 200;
      aResponse.ContentType := MimeForName(Rel);
      aResponse.ContentLength := FS.Size;
      aResponse.ContentStream := FS;
      aResponse.SendContent;
      aResponse.ContentStream := nil;
      FS.Free;
      Exit(True);
    end;
  end;
end;

end.
