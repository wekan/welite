unit wlboard;
{$mode objfpc}{$H+}
{$CODEPAGE UTF8}
interface
uses SysUtils, Classes, HTTPDefs, fpjson, jsonparser, wldb, wlauth, wltenant,
  wlhtml, wlcolors, wlmove, wlaccess, wldesign, wlenhanc, wlbrowse;
function BoardListHtml(Db:TWLDb; const S:TWLSession):string;
function BoardHtml(Db:TWLDb; const BoardId:string; const S:TWLSession; const Dir:string; X:Integer=1; Y:Integer=1; AllItems:Boolean=False):string;
procedure BoardEndpoint(aRequest:TRequest; aResponse:TResponse);
implementation
function BoardListHtml(Db:TWLDb; const S:TWLSession):string;
var R:TWLRows; i,Count:Integer;
begin
  R:=Db.Query('SELECT id,title,color FROM boards WHERE archived=0 ORDER BY sort,id;');
  Result:='<h2>Boards</h2><ul>'; Count:=0;
  for i:=0 to High(R) do if BoardCanRead(Db,S.UserId,R[i][0]) then
  begin
    Inc(Count);
    Result:=Result+'<li><a href="'+HtmlAttr(SessionUrl('/board?id='+HTTPEncode(R[i][0]),S))+
      '">'+HtmlEncode(R[i][1])+'</a></li>';
  end;
  if Count=0 then Result:=Result+'<li>No boards available.</li>';
  Result:=Result+'</ul>';
end;
function BoardHtml(Db:TWLDb; const BoardId:string; const S:TWLSession; const Dir:string; X:Integer; Y:Integer; AllItems:Boolean):string;
var B,Lanes,Lists,Cards,MapLists:TWLRows; i,j,k,c,m,Width,MapX,MapY:Integer;
  Writable:Boolean; Back,Align,Map,Url,Color,CellText:string; Occupied:TWLRows;
  function Selection(const Kind,Id:string):string;
  begin
    if Writable then Result:=SelectCheckbox(Kind,Id)+' ' else Result:='';
  end;
begin
  Result:='';
  if not BoardCanRead(Db,S.UserId,BoardId) then Exit;
  B:=Db.Query('SELECT title,color FROM boards WHERE id='+QuotedStr(BoardId)+';');
  Writable:=BoardCanWrite(Db,S.UserId,BoardId);
  if SameText(Dir,'rtl') then Align:='right' else Align:='left';
  Back:='/board?id='+HTTPEncode(BoardId);
  Result:='<h1>'+HtmlEncode(B[0][0])+'</h1><p><a href="'+
    HtmlAttr(SessionUrl('/',S))+'">All boards</a></p>';
  Lanes:=Db.Query('SELECT id,title,color FROM swimlanes WHERE boardId='+QuotedStr(BoardId)+
    ' AND archived=0 ORDER BY sort,id;');
  if X<1 then X:=1;
  if Y<1 then Y:=1;
  if (Length(Lanes)>0) and (Y>Length(Lanes)) then Y:=Length(Lanes);
  Width:=0;
  Map:='<table align="right" border="1" cellpadding="3" cellspacing="0" summary="Board minimap">';
  for MapY:=0 to High(Lanes) do
  begin
    MapLists:=Db.Query('SELECT id,title FROM lists WHERE boardId='+QuotedStr(BoardId)+
      ' AND (swimlaneId='+QuotedStr(Lanes[MapY][0])+' OR swimlaneId='''') AND archived=0 ORDER BY sort,id;');
    if MapY=Y-1 then
    begin
      Width:=Length(MapLists);
      if (Width>0) and (X>Width) then X:=Width;
    end;
    Map:=Map+'<tr>';
    for MapX:=0 to High(MapLists) do
    begin
      Occupied:=Db.Query('SELECT id FROM cards WHERE boardId='+QuotedStr(BoardId)+
        ' AND swimlaneId='+QuotedStr(Lanes[MapY][0])+' AND listId='+QuotedStr(MapLists[MapX][0])+
        ' AND archived=0 LIMIT 1;');
      if Length(Occupied)>0 then begin Color:='#cccccc'; CellText:='*'; end
      else begin Color:='#ffffff'; CellText:='-'; end;
      if (MapX=X-1) and (MapY=Y-1) then Color:='#ffff66';
      Url:='/board?id='+HTTPEncode(BoardId)+'&x='+IntToStr(MapX+1)+'&y='+IntToStr(MapY+1);
      Map:=Map+'<td bgcolor="'+Color+'"><a href="'+HtmlAttr(SessionUrl(Url,S))+
        '" title="'+HtmlAttr(Lanes[MapY][1]+' / '+MapLists[MapX][1])+'">'+CellText+'</a></td>';
    end;
    if Length(MapLists)=0 then Map:=Map+'<td>-</td>';
    Map:=Map+'</tr>';
  end;
  Map:=Map+'</table>';
  Result:=Result+Map+'<p>X '+IntToStr(X)+' Y '+IntToStr(Y)+
    ' (yellow: current; *: cards; -: empty)</p><p>';
  for m:=0 to 3 do
  begin
    MapX:=X; MapY:=Y;
    case m of
      0: begin Dec(MapX); CellText:='View left'; end;
      1: begin Inc(MapX); CellText:='View right'; end;
      2: begin Dec(MapY); CellText:='View up'; end;
      3: begin Inc(MapY); CellText:='View down'; end;
    end;
    if (MapX>=1) and (MapX<=Width) and (MapY>=1) and (MapY<=Length(Lanes)) then
      Result:=Result+'<a href="'+HtmlAttr(SessionUrl('/board?id='+HTTPEncode(BoardId)+
        '&x='+IntToStr(MapX)+'&y='+IntToStr(MapY),S))+'">'+CellText+'</a> ';
  end;
  Result:=Result+'<a href="'+HtmlAttr(SessionUrl('/board?id='+HTTPEncode(BoardId)+'&view=all',S))+
    '">View all</a></p><br clear="all">';
  Back:='/board?id='+HTTPEncode(BoardId);
  if AllItems then Back:=Back+'&view=all'
  else Back:=Back+'&x='+IntToStr(X)+'&y='+IntToStr(Y);
  if Writable then Result:=Result+MoveFormBegin(S,'/board/move')+
    '<input type="hidden" name="boardId" value="'+HtmlAttr(BoardId)+'">'+
    '<input type="hidden" name="back" value="'+HtmlAttr(Back)+'">';

  if Length(Lanes)=0 then Result:=Result+'<p>No swimlanes yet.</p>';
  for i:=0 to High(Lanes) do
  begin
    if not AllItems and (i<>Y-1) then Continue;
    Result:=Result+'<h2'+BgColorAttr(Lanes[i][2])+'>'+Selection('swimlane',Lanes[i][0])+
      HtmlEncode(Lanes[i][1])+'</h2>';
    Lists:=Db.Query('SELECT id,title,color FROM lists WHERE boardId='+QuotedStr(BoardId)+
      ' AND (swimlaneId='+QuotedStr(Lanes[i][0])+' OR swimlaneId='''') AND archived=0 ORDER BY sort,id;');
    if Length(Lists)=0 then begin Result:=Result+'<p>No lists yet.</p>'; Continue; end;
    Result:=Result+'<table width="100%" border="1" cellpadding="5" cellspacing="0"><tr>';
    for j:=0 to High(Lists) do
    begin
      if Align='right' then c:=High(Lists)-j else c:=j;
      if not AllItems and (c<>X-1) then Continue;
      Result:=Result+'<th align="'+Align+'"'+BgColorAttr(Lists[c][2])+'>'+
        Selection('list',Lists[c][0])+HtmlEncode(Lists[c][1])+'</th>';
    end;
    Result:=Result+'</tr><tr>';
    for j:=0 to High(Lists) do
    begin
      if Align='right' then c:=High(Lists)-j else c:=j;
      if not AllItems and (c<>X-1) then Continue;
      Result:=Result+'<td valign="top" align="'+Align+'" data-list="'+HtmlAttr(Lists[c][0])+'" data-lane="'+HtmlAttr(Lanes[i][0])+'">';
      Cards:=Db.Query('SELECT id,title,color,description FROM cards WHERE boardId='+QuotedStr(BoardId)+
        ' AND swimlaneId='+QuotedStr(Lanes[i][0])+' AND listId='+QuotedStr(Lists[c][0])+
        ' AND archived=0 ORDER BY sort,id;');
      for k:=0 to High(Cards) do
        Result:=Result+'<p'+DraggableAttrs('card',Cards[k][0],'/board/move')+
          BgColorAttr(Cards[k][2])+'>'+Selection('card',Cards[k][0])+
          HtmlEncode(Cards[k][1])+'</p>';
      if Length(Cards)=0 then Result:=Result+'<p>No cards.</p>';
      Result:=Result+'</td>';
    end;
    Result:=Result+'</tr></table>';
  end;
  if Writable then Result:=Result+MoveKeypad(S,0,0,0,True,True)+MoveFormEnd;
end;
procedure BoardEndpoint(aRequest:TRequest; aResponse:TResponse);
var T:TWLTenant; S:TWLSession; Body,Dir:string;
begin
  if not (ResolveTenant(aRequest,T) and TenantOpen(T)) then
  begin aResponse.Code:=404; aResponse.Content:='Unknown domain'; aResponse.SendContent; Exit; end;
  if not ValidateSession(T.Db,aRequest,SessionIdFromRequest(aRequest),S) then S:=Default(TWLSession);
  S.LanguageTag:=RequestLanguageTag(aRequest);
  Dir:=ResolveDir(aRequest,'',SessionLanguage(T.Db,S));
  Body:=BoardHtml(T.Db,aRequest.QueryFields.Values['id'],S,Dir,
    StrToIntDef(aRequest.QueryFields.Values['x'],1),StrToIntDef(aRequest.QueryFields.Values['y'],1),
    aRequest.QueryFields.Values['view']='all');
  if Body='' then begin aResponse.Code:=404; aResponse.Content:='Board not found'; end
  else begin aResponse.Code:=200; aResponse.Content:=PageDir('Board',Body+EnhancementScripts(wbUnknown),Dir); end;
  aResponse.ContentType:='text/html; charset=utf-8'; aResponse.SendContent;
end;
function BoardsView(Db:TWLDb; const W:TWidget; const S:TWLSession):string;
begin Result:=BoardListHtml(Db,S); end;
function BoardView(Db:TWLDb; const W:TWidget; const S:TWLSession):string;
var D:TJSONData; Id:string;
begin
  Id:=''; D:=nil;
  try
    try D:=GetJSON(W.OptionsJson); if D is TJSONObject then Id:=TJSONObject(D).Get('boardId',''); except end;
  finally D.Free; end;
  Result:=BoardHtml(Db,Id,S,'ltr',1,1,True);
  if Result='' then Result:='<p>Board not available.</p>';
end;
initialization
  RegisterDataView('boards',@BoardsView);
  RegisterDataView('swimlanes',@BoardView);
  RegisterDataView('board',@BoardView);
end.
