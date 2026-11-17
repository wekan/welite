program selscope;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,jsonparser,wldb,wlselscp;
var Db:TWLDb;Scope:TSelectionScope;Doc,OutputDoc:TJSONObject;Ids:TJSONArray;
  Line,Name,Column,Expr,Sql:string;Rows:TWLRows;i:Integer;
function Q(const Text:string):string;
begin Result:=QuotedStr(Text);end;
begin
  SetMultiByteConversionCodePage(CP_UTF8);Db:=TWLDb.Create(ParamStr(1));Scope:=TSelectionScope.Create(Db);
  try
    while not EOF(Input) do
    begin
      Readln(Line);Doc:=nil;OutputDoc:=nil;
      try
        Doc:=TJSONObject(GetJSON(Line));Name:=Doc.Get('table','cards');Column:=Doc.Get('column','boardId');
        if Doc.Get('before','')<>'' then if not Db.Exec(Doc.Get('before','')) then raise Exception.Create('Setup failed');
        Expr:=Scope.StringField(Name,Column);
        if Doc.Get('after','')<>'' then if not Db.Exec(Doc.Get('after','')) then raise Exception.Create('Mutation failed');
        for i:=0 to Scope.Bindings.Count-1 do
        begin Rows:=Db.Query(Scope.Bindings[i]);if (Length(Rows)<>1) or (Rows[0][0]<>'1') then raise Exception.Create('Stale scope');end;
        Sql:='SELECT id FROM "'+Name+'" WHERE "'+Column+'"='+Q(Doc.Get('match',''))+' AND '+Expr;
        Rows:=Db.Query('SELECT ''__scope__'' UNION ALL '+Sql+';');
        if (Length(Rows)=0) or (Rows[0][0]<>'__scope__') then raise Exception.Create('Scope query failed');
        OutputDoc:=TJSONObject.Create;Ids:=TJSONArray.Create;OutputDoc.Add('ids',Ids);
        for i:=1 to High(Rows) do Ids.Add(Rows[i][0]);
        OutputDoc.Add('expression',Expr);Writeln(OutputDoc.AsJSON);
      except on E:Exception do Writeln('{"error":true}');end;
      OutputDoc.Free;Doc.Free;
    end;
  finally Scope.Free;Db.Free;end;
end.
