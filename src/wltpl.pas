unit wltpl;

(*
  WeKan-Lite — Weddy's page templates, drawn here.

  Weddy (caddy-wekan-plugin) writes WeKan's Jade templates as Pug, and its
  Pug library (Joker/jade) makes each one a Go html/template text:
  releases/pugtpl turns that text into a Pascal include (src/tpl/*.inc).
  This unit draws such a text over a JSON object, so a page Weddy has is the
  same page here - WeKan's class names, ids and words - without writing it a
  second time by hand.

  What the templates use of Go's template language, and so what is here:
    {{.A.B}} {{$.A}} {{.}}           a value, HTML-escaped
    {{t $.L "key"}} {{t $.L .Key}}    the viewer's words for a key
    {{copula $.L}} {{nameBeforeSubject $.L}}   WeKan's rule-trigger grammar
    {{ if X }}..{{ else }}..{{ end }}  {{ range X }}..{{ else }}..{{ end }}
    not, and, or, eq, len, index, ( ), "strings", `strings`, {{/* */}}
  A value is false as in Go: false, 0, "", null, an empty array or object.
  Anything else in a template is an error the test of that template finds
  (tests/tpl.py), never a page drawn half.
*)

{$mode objfpc}{$H+}
{$CODEPAGE UTF8}

interface

uses SysUtils, Classes, fpjson, wli18n;

// The template drawn over Data (its $), with the viewer's words; Lang is
// what $.L names, the viewer's language tag. An unknown construct raises.
function RenderTemplate(const Template: string; Data: TJSONObject; Words: TWLTranslator; const Lang: string): string;

// WeKan's ruleTriggerCopula and ruleNameBeforeSubject (Weddy's server.go).
function RuleCopula(Words: TWLTranslator; const Lang: string): string;
function RuleNameBeforeSubject(const Lang: string): Boolean;

implementation

type
  TNodeKind = (nkText, nkOut, nkIf, nkRange);
  TNode = class
    Kind: TNodeKind;
    Text: string;          // nkText: the text; else the action's pipeline
    Body, Other: TList;    // nkIf/nkRange: then (body) and else
    constructor Create(AKind: TNodeKind; const AText: string);
    destructor Destroy; override;
  end;

  TValKind = (vkNull, vkBool, vkNum, vkStr, vkJson);
  TVal = record
    Kind: TValKind;
    B: Boolean;
    N: Double;
    S: string;
    J: TJSONData; // borrowed from the data
  end;

  TRender = class
    Root: TJSONObject;
    Words: TWLTranslator;
    Lang: string;
    Buf: TStringBuilder;
    procedure Run(Nodes: TList; Dot: TJSONData);
    function Eval(const Expr: string; Dot: TJSONData): TVal;
  end;

constructor TNode.Create(AKind: TNodeKind; const AText: string);
begin
  Kind := AKind; Text := AText; Body := nil; Other := nil;
end;

procedure FreeNodes(L: TList);
var i: Integer;
begin
  if L = nil then Exit;
  for i := 0 to L.Count - 1 do TNode(L[i]).Free;
  L.Free;
end;

destructor TNode.Destroy;
begin
  FreeNodes(Body); FreeNodes(Other);
  inherited Destroy;
end;

function Esc(const S: string): string;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    case S[i] of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&#34;';
      '''': Result := Result + '&#39;';
    else Result := Result + S[i];
    end;
end;

function RuleNameBeforeSubject(const Lang: string): Boolean;
var L: string;
begin
  L := LowerCase(Lang);
  Result := (L = 'eu') or (Copy(L, 1, 3) = 'eu-') or (Copy(L, 1, 3) = 'eu_');
end;

function RuleCopula(Words: TWLTranslator; const Lang: string): string;
var L, Base: string; i: Integer;
begin
  L := LowerCase(Lang); Base := L;
  for i := 1 to Length(L) do
    if L[i] in ['-', '_'] then begin Base := Copy(L, 1, i - 1); Break; end;
  if (Base = 'eu') or (Base = 'th') or (Base = 'kn') or (Base = 'ml') or (Base = 'la') or (Base = 'ga') then Exit('');
  Result := Words.Text('r-is', 'is');
end;

// ---- parsing -------------------------------------------------------------

// The text split into nodes; Stop is what ended the list: '', 'else' or 'end'.
function ParseNodes(const Src: string; var At: Integer; out Stop: string): TList;
var Open, Close: Integer; Action: string; Node: TNode; Sub: string;
begin
  Result := TList.Create;
  Stop := '';
  try
    while At <= Length(Src) do
    begin
      Open := Pos('{{', Copy(Src, At, MaxInt));
      if Open = 0 then
      begin
        Result.Add(TNode.Create(nkText, Copy(Src, At, MaxInt)));
        At := Length(Src) + 1;
        Exit;
      end;
      if Open > 1 then Result.Add(TNode.Create(nkText, Copy(Src, At, Open - 1)));
      At := At + Open + 1;
      Close := Pos('}}', Copy(Src, At, MaxInt));
      if Close = 0 then raise Exception.Create('template: unclosed action');
      Action := Trim(Copy(Src, At, Close - 1));
      At := At + Close + 1;
      if Copy(Action, 1, 2) = '/*' then Continue;
      if (Action = 'else') or (Action = 'end') then begin Stop := Action; Exit; end;
      if (Copy(Action, 1, 3) = 'if ') or (Copy(Action, 1, 6) = 'range ') then
      begin
        if Copy(Action, 1, 3) = 'if ' then Node := TNode.Create(nkIf, Trim(Copy(Action, 4, MaxInt)))
        else Node := TNode.Create(nkRange, Trim(Copy(Action, 7, MaxInt)));
        Result.Add(Node);
        Node.Body := ParseNodes(Src, At, Sub);
        if Sub = 'else' then Node.Other := ParseNodes(Src, At, Sub);
        if Sub <> 'end' then raise Exception.Create('template: missing end');
        Continue;
      end;
      Result.Add(TNode.Create(nkOut, Action));
    end;
  except
    FreeNodes(Result);
    raise;
  end;
end;

// ---- values --------------------------------------------------------------

function VNull: TVal; begin Result := Default(TVal); Result.Kind := vkNull; end;
function VBool(B: Boolean): TVal; begin Result := VNull; Result.Kind := vkBool; Result.B := B; end;
function VStr(const S: string): TVal; begin Result := VNull; Result.Kind := vkStr; Result.S := S; end;
function VNum(N: Double): TVal; begin Result := VNull; Result.Kind := vkNum; Result.N := N; end;

function VJson(J: TJSONData): TVal;
begin
  if J = nil then Exit(VNull);
  case J.JSONType of
    jtNull, jtUnknown: Result := VNull;
    jtBoolean: Result := VBool(J.AsBoolean);
    jtNumber: Result := VNum(J.AsFloat);
    jtString: Result := VStr(J.AsString);
  else
    Result := VNull; Result.Kind := vkJson; Result.J := J;
  end;
end;

function Truth(const V: TVal): Boolean;
begin
  case V.Kind of
    vkBool: Result := V.B;
    vkNum: Result := V.N <> 0;
    vkStr: Result := V.S <> '';
    vkJson: Result := V.J.Count > 0;
  else Result := False;
  end;
end;

function AsText(const V: TVal): string;
begin
  case V.Kind of
    vkBool: if V.B then Result := 'true' else Result := 'false';
    vkNum: if Frac(V.N) = 0 then Result := IntToStr(Trunc(V.N)) else Result := FloatToStr(V.N);
    vkStr: Result := V.S;
    vkJson: Result := V.J.AsJSON;
  else Result := '';
  end;
end;

function SameVal(const A, B: TVal): Boolean;
begin
  if (A.Kind = vkNum) and (B.Kind = vkNum) then Exit(A.N = B.N);
  if (A.Kind = vkBool) and (B.Kind = vkBool) then Exit(A.B = B.B);
  if A.Kind <> B.Kind then Exit(False);
  Result := AsText(A) = AsText(B);
end;

// A dotted path (A.B.C) inside a value.
function Field(Base: TJSONData; const Path: string): TVal;
var Rest, Name: string; P: Integer; Cur: TJSONData;
begin
  Cur := Base; Rest := Path;
  while Rest <> '' do
  begin
    P := Pos('.', Rest);
    if P > 0 then begin Name := Copy(Rest, 1, P - 1); Rest := Copy(Rest, P + 1, MaxInt); end
    else begin Name := Rest; Rest := ''; end;
    if not (Cur is TJSONObject) then Exit(VNull);
    Cur := TJSONObject(Cur).Find(Name);
    if Cur = nil then Exit(VNull);
  end;
  Result := VJson(Cur);
end;

// ---- expressions -----------------------------------------------------------

// The pipeline's words: names, fields, strings and parenthesised groups.
function Words_(const Expr: string): TStringArray;
var i, Depth, Start: Integer; Q: Char;
  procedure Add(const W: string);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := W;
  end;
begin
  SetLength(Result, 0);
  i := 1;
  while i <= Length(Expr) do
  begin
    if Expr[i] = ' ' then begin Inc(i); Continue; end;
    Start := i;
    if Expr[i] in ['"', '`'] then
    begin
      Q := Expr[i]; Inc(i);
      while (i <= Length(Expr)) and (Expr[i] <> Q) do
      begin
        if (Q = '"') and (Expr[i] = '\') then Inc(i);
        Inc(i);
      end;
      if i > Length(Expr) then raise Exception.Create('template: unclosed string');
      Inc(i);
    end
    else if Expr[i] = '(' then
    begin
      Depth := 0;
      repeat
        if Expr[i] = '(' then Inc(Depth) else if Expr[i] = ')' then Dec(Depth);
        Inc(i);
      until (Depth = 0) or (i > Length(Expr));
      if Depth <> 0 then raise Exception.Create('template: unbalanced parenthesis');
    end
    else
      while (i <= Length(Expr)) and (Expr[i] <> ' ') do Inc(i);
    Add(Copy(Expr, Start, i - Start));
  end;
end;

function Unquote(const W: string): string;
var i: Integer;
begin
  Result := '';
  if W[1] = '`' then Exit(Copy(W, 2, Length(W) - 2));
  i := 2;
  while i < Length(W) do
  begin
    if (W[i] = '\') and (i + 1 < Length(W)) then
    begin
      Inc(i);
      case W[i] of
        'n': Result := Result + #10;
        't': Result := Result + #9;
      else Result := Result + W[i];
      end;
    end
    else Result := Result + W[i];
    Inc(i);
  end;
end;

function TRender.Eval(const Expr: string; Dot: TJSONData): TVal;
var W: TStringArray; Name: string; i: Integer; A, B: TVal;
  function Arg(Index: Integer): TVal;
  var X: string;
  begin
    if Index > High(W) then raise Exception.Create('template: missing argument in ' + Expr);
    X := W[Index];
    if X[1] = '(' then Exit(Eval(Copy(X, 2, Length(X) - 2), Dot));
    if X[1] in ['"', '`'] then Exit(VStr(Unquote(X)));
    if X = '.' then Exit(VJson(Dot));
    if X = '$' then Exit(VJson(Root));
    if X[1] = '.' then Exit(Field(Dot, Copy(X, 2, MaxInt)));
    if Copy(X, 1, 2) = '$.' then Exit(Field(Root, Copy(X, 3, MaxInt)));
    if X = 'true' then Exit(VBool(True));
    if X = 'false' then Exit(VBool(False));
    if X[1] in ['0'..'9', '-'] then Exit(VNum(StrToFloat(X)));
    raise Exception.Create('template: unknown value ' + X);
  end;
begin
  W := Words_(Expr);
  if Length(W) = 0 then raise Exception.Create('template: empty action');
  Name := W[0];
  if (Length(W) = 1) or not (Name[1] in ['a'..'z']) then
  begin
    if Length(W) <> 1 then raise Exception.Create('template: not a function: ' + Expr);
    Exit(Arg(0));
  end;
  if Name = 't' then
  begin
    if Length(W) <> 3 then raise Exception.Create('template: t takes a language and a key');
    Exit(VStr(Words.Text(AsText(Arg(2)), AsText(Arg(2)))));
  end;
  if Name = 'copula' then Exit(VStr(RuleCopula(Words, Lang)));
  if Name = 'nameBeforeSubject' then Exit(VBool(RuleNameBeforeSubject(Lang)));
  if Name = 'not' then Exit(VBool(not Truth(Arg(1))));
  if Name = 'and' then
  begin
    for i := 1 to High(W) do
    begin
      A := Arg(i);
      if not Truth(A) then Exit(A);
    end;
    Exit(A);
  end;
  if Name = 'or' then
  begin
    for i := 1 to High(W) do
    begin
      A := Arg(i);
      if Truth(A) then Exit(A);
    end;
    Exit(A);
  end;
  if Name = 'eq' then
  begin
    A := Arg(1);
    for i := 2 to High(W) do
    begin
      B := Arg(i);
      if SameVal(A, B) then Exit(VBool(True));
    end;
    Exit(VBool(False));
  end;
  if Name = 'len' then
  begin
    A := Arg(1);
    case A.Kind of
      vkJson: Exit(VNum(A.J.Count));
      vkStr: Exit(VNum(Length(A.S)));
      vkNull: Exit(VNum(0));
    else raise Exception.Create('template: len of a scalar');
    end;
  end;
  if Name = 'index' then
  begin
    A := Arg(1); B := Arg(2);
    if (A.Kind = vkJson) and (A.J is TJSONObject) then Exit(VJson(TJSONObject(A.J).Find(AsText(B))));
    if (A.Kind = vkJson) and (A.J is TJSONArray) and (B.Kind = vkNum) and (B.N >= 0) and (B.N < A.J.Count) then
      Exit(VJson(TJSONArray(A.J).Items[Trunc(B.N)]));
    Exit(VNull);
  end;
  raise Exception.Create('template: unknown function ' + Name);
end;

procedure TRender.Run(Nodes: TList; Dot: TJSONData);
var i, k: Integer; Node: TNode; V: TVal;
begin
  if Nodes = nil then Exit;
  for i := 0 to Nodes.Count - 1 do
  begin
    Node := TNode(Nodes[i]);
    case Node.Kind of
      nkText: Buf.Append(Node.Text);
      nkOut: Buf.Append(Esc(AsText(Eval(Node.Text, Dot))));
      nkIf:
        if Truth(Eval(Node.Text, Dot)) then Run(Node.Body, Dot) else Run(Node.Other, Dot);
      nkRange:
        begin
          V := Eval(Node.Text, Dot);
          if Truth(V) and (V.Kind = vkJson) then
          begin
            if V.J is TJSONArray then
              for k := 0 to V.J.Count - 1 do Run(Node.Body, TJSONArray(V.J).Items[k])
            else
              for k := 0 to V.J.Count - 1 do Run(Node.Body, TJSONObject(V.J).Items[k]);
          end
          else Run(Node.Other, Dot);
        end;
    end;
  end;
end;

function RenderTemplate(const Template: string; Data: TJSONObject; Words: TWLTranslator; const Lang: string): string;
var Nodes: TList; At: Integer; Stop: string; R: TRender;
begin
  At := 1;
  Nodes := ParseNodes(Template, At, Stop);
  R := TRender.Create;
  try
    if Stop <> '' then raise Exception.Create('template: ' + Stop + ' without if or range');
    R.Root := Data; R.Words := Words; R.Lang := Lang;
    R.Buf := TStringBuilder.Create;
    try
      R.Run(Nodes, Data);
      Result := R.Buf.ToString;
    finally
      R.Buf.Free;
    end;
  finally
    R.Free;
    FreeNodes(Nodes);
  end;
end;

end.
