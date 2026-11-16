unit wlenhanc;

{
  Optional card drag enhancement. Checkbox/arrow forms remain the baseline.
  Vendored InteractJS supports independent pointers; wlmdrag.js serializes drops
  through /board/move, refreshing the single-use form token between requests.
}

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, wlbrowse;

// Hooks to attach to a draggable element (card/list/swimlane) so the enhancement layer can
// wire it. Harmless on retro browsers (unknown class/attributes are ignored). MoveUrl is the
// SAME endpoint the form-based move buttons post to; drops submit selected IDs and target cells.
//   Kind: 'card' | 'list' | 'swimlane'
function DraggableAttrs(const Kind, Id, MoveUrl: string): string;

// The enhancement <script> includes, to place before </body>. Emitted by default; the scripts
// self-gate on capability. Pass the detected browser to skip the bytes for no-JS clients.
function EnhancementScripts(B: TWLBrowser): string;

// True if it's worth emitting the enhancement scripts for this browser (optimization only —
// emitting them anyway is still correct, retro browsers just ignore them).
function ShouldEnhance(B: TWLBrowser): Boolean;

implementation

function HtmlAttr(const V: string): string;
begin
  Result:=StringReplace(V,'&','&amp;',[rfReplaceAll]);
  Result:=StringReplace(Result,'<','&lt;',[rfReplaceAll]);
  Result:=StringReplace(Result,'"','&quot;',[rfReplaceAll]);
end;

function ShouldEnhance(B: TWLBrowser): Boolean;
begin
  // skip for browsers known to lack usable JS; everyone else may get it (and self-gates)
  case B of
    wbIBrowse, wbDilloFreeDOS, wbDilloDesktop: Result := False;
  else
    Result := True;
  end;
end;

function DraggableAttrs(const Kind, Id, MoveUrl: string): string;
begin
  // class="draggable" is what the InteractJS setup binds to (see wami multidrag index.html);
  // data-move-url lets the enhancement POST to the same move endpoint as the buttons.
  Result :=
    ' class="draggable" id="drag-' + HtmlAttr(Id) + '"' +
    ' data-kind="' + HtmlAttr(Kind) + '"' +
    ' data-id="' + HtmlAttr(Id) + '"' +
    ' data-move-url="' + HtmlAttr(MoveUrl) + '"';
end;

function EnhancementScripts(B: TWLBrowser): string;
begin
  if not ShouldEnhance(B) then
    Exit('');
  // Both assets are local; the glue self-gates and requires an editable board form.
  Result :=
    '<script src="/js/interact.js"></script>' + LineEnding +
    '<script src="/js/wlmdrag.js"></script>' + LineEnding;
end;

end.
