program relscope;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,jsonparser,wldb,wlmodels,wlselscp;
var Db:TWLDb;Scope:TSelectionScope;Doc,OutputDoc,Spec,RootSpec:TJSONObject;
  Models,Relations,Values:TJSONArray;Line,Name,Column,Expr,Sql,Columns:string;Rows:TWLRows;i:Integer;
function Q(const Text:string):string;
begin Result:=QuotedStr(Text);end;
function Id(const Text:string):string;
begin Result:='"'+StringReplace(Text,'"','""',[rfReplaceAll])+'"';end;
begin
  SetMultiByteConversionCodePage(CP_UTF8);Models:=TJSONArray(GetJSON(ModelJson));Relations:=TJSONArray(GetJSON(RelationJson));
  Db:=TWLDb.Create(ParamStr(1));Scope:=TSelectionScope.Create(Db);
  try
    while not EOF(Input) do
    begin
      Readln(Line);Doc:=nil;OutputDoc:=nil;
      try
        Doc:=TJSONObject(GetJSON(Line));Name:=Doc.Get('table','card_labels');Spec:=nil;RootSpec:=nil;
        for i:=0 to Relations.Count-1 do if Relations.Objects[i].Get('table','')=Name then Spec:=Relations.Objects[i];
        if Spec=nil then raise Exception.Create('Missing test model');
        for i:=0 to Models.Count-1 do if Models.Objects[i].Get('table','')=Spec.Get('parent','') then RootSpec:=Models.Objects[i];
        if Doc.Get('mode','')='spec' then
        begin OutputDoc:=TJSONObject.Create;OutputDoc.Add('relation',Spec.Clone);OutputDoc.Add('root',RootSpec.Clone);end
        else
        begin
          Column:=Doc.Get('column',Spec.Get('parentKey',''));
          if Doc.Get('before','')<>'' then if not Db.Exec(Doc.Get('before','')) then raise Exception.Create('Setup failed');
          Expr:=Scope.StringField(Name,Column);
          if Doc.Get('after','')<>'' then if not Db.Exec(Doc.Get('after','')) then raise Exception.Create('Mutation failed');
          if Doc.Get('checkBindings',True) then for i:=0 to Scope.Bindings.Count-1 do
          begin Rows:=Db.Query(Scope.Bindings[i]);if (Length(Rows)<>1) or (Rows[0][0]<>'1') then raise Exception.Create('Stale scope');end;
          Columns:=Id(Spec.Get('parentKey',''));
          for i:=0 to TJSONArray(Spec.Find('fields')).Count-1 do Columns:=Columns+','+Id(TJSONArray(Spec.Find('fields')).Objects[i].Get('name',''));
          Sql:='SELECT json_array('+Columns+') FROM '+Id(Name)+' WHERE '+Id(Spec.Get('parentKey',''))+'='+Q(Doc.Get('owner','parent'))+' AND '+Expr;
          if Doc.Find('match')<>nil then Sql:=Sql+' AND '+Id(Column)+'='+Q(Doc.Get('match',''));
          Rows:=Db.Query('SELECT ''__scope__'' UNION ALL '+Sql+';');
          if (Length(Rows)=0) or (Rows[0][0]<>'__scope__') then raise Exception.Create('Scope query failed');
          OutputDoc:=TJSONObject.Create;Values:=TJSONArray.Create;OutputDoc.Add('rows',Values);
          for i:=1 to High(Rows) do Values.Add(GetJSON(Rows[i][0]));
          OutputDoc.Add('expression',Expr);OutputDoc.Add('bindingCount',Scope.Bindings.Count);
        end;
        Writeln(OutputDoc.AsJSON);
      except on E:Exception do begin Writeln(StdErr,E.Message);Writeln('{"error":true}');end;end;
      OutputDoc.Free;Doc.Free;
    end;
  finally Scope.Free;Db.Free;Models.Free;Relations.Free;end;
end.
