unit wlposhis;
{$mode objfpc}{$H+}
interface
uses wldb;

procedure RecordListPosition(Db:TWLDb;const UserId,BoardId,ListId,BatchId,DeletedAt:string;
  const Position:TWLRow;Restored:Boolean);

implementation
uses SysUtils,DateUtils,fpjson,wlsjson,wlferr;

procedure RecordListPosition(Db:TWLDb;const UserId,BoardId,ListId,BatchId,DeletedAt:string;
  const Position:TWLRow;Restored:Boolean);
var Registry,Ids:TWLRows;TableName,TableSql,Owner,DocSql,Action,Sql:string;
  Doc,Previous,Next,Hints,DateHint:TJSONObject;Date:TDateTime;Stamp,Epoch:TTimeStamp;
  Millis:Int64;Sort:Double;NumberFormat:TFormatSettings;Shared:Boolean;
begin
  if Length(Position)<2 then Exit;
  Registry:=Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'' AND type=''table'';');
  Shared:=Length(Registry)=1;
  TableName:='_wl_position_history';
  if Shared then
  begin
    if not EnsurePositionHistoryCollection(Db) then Exit;
    Registry:=Db.Query('SELECT r.table_name FROM _ferretdb_collections r JOIN sqlite_master m '+
      'ON m.name=r.table_name AND m.type=''table'' WHERE r.name=''userPositionHistory'';');
    if Length(Registry)<>1 then Exit;
    TableName:=Registry[0][0];
  end;
  TableSql:='"'+StringReplace(TableName,'"','""',[rfReplaceAll])+'"';
  Ids:=Db.Query('SELECT lower(hex(randomblob(12)));');
  if Length(Ids)<>1 then Exit;
  if not TryISO8601ToDate(DeletedAt,Date,True) then Exit;
  Stamp:=DateTimeToTimeStamp(Date);Epoch:=DateTimeToTimeStamp(EncodeDate(1970,1,1));
  Millis:=Int64(Stamp.Date-Epoch.Date)*86400000+Stamp.Time;
  NumberFormat:=DefaultFormatSettings;NumberFormat.DecimalSeparator:='.';
  Action:='delete';if Restored then Action:='restore';
  Doc:=TJSONObject.Create(['_id',Ids[0][0],'userId',UserId,'boardId',BoardId,'entityType','list',
    'entityId',ListId,'actionType',Action,'undone',False,'isCheckpoint',False]);
  Hints:=TJSONObject.Create(['createdAt','date']);
  try
    Previous:=TJSONObject.Create;Doc.Add('previousState',Previous);
    Next:=TJSONObject.Create;Doc.Add('newState',Next);
    DateHint:=TJSONObject.Create(['deletedAt','date']);
    if Restored then
    begin
      Previous.Add('deletedAt',Millis);
      Hints.Add('previousState',DateHint);
      Next.Add('deletedAt',TJSONNull.Create);
    end else
    begin
      Previous.Add('boardId',BoardId);Doc.Add('previousBoardId',BoardId);
      if Position[0]<>'' then
      begin Previous.Add('swimlaneId',Position[0]);Doc.Add('previousSwimlaneId',Position[0]);end;
      if TryStrToFloat(Position[1],Sort,NumberFormat) then
      begin Previous.Add('sort',Sort);Doc.Add('previousSort',Sort);end;
      Next.Add('deletedAt',Millis);
      Hints.Add('newState',DateHint);
    end;
    if BatchId<>'' then Doc.Add('batchId',BatchId);
    Stamp:=DateTimeToTimeStamp(LocalTimeToUniversal(Now));
    Doc.Add('createdAt',Int64(Stamp.Date-Epoch.Date)*86400000+Stamp.Time);
    DocSql:=QuotedStr(TypedDocument(Doc.AsJSON,'',Hints.AsJSON));
  finally Hints.Free;Doc.Free;end;
  Sql:='BEGIN IMMEDIATE; ';
  Owner:='1';
  if Shared then Owner:='EXISTS(SELECT 1 FROM _ferretdb_collections WHERE name=''userPositionHistory'' AND table_name='+
    QuotedStr(TableName)+') AND (SELECT count(*) FROM _ferretdb_collections WHERE table_name='+QuotedStr(TableName)+')=1';
  if not Shared then
    Sql:=Sql+'CREATE TABLE IF NOT EXISTS '+TableSql+
      '(_ferretdb_sjson TEXT NOT NULL CHECK(json_valid(_ferretdb_sjson))); '+
      'CREATE INDEX IF NOT EXISTS _wl_position_actor_board ON '+TableSql+
      '(json_extract(_ferretdb_sjson,''$.userId''),json_extract(_ferretdb_sjson,''$.boardId'')); ';
  Sql:=Sql+'DELETE FROM '+TableSql+' WHERE '+Owner+
    ' AND json_extract(_ferretdb_sjson,''$.userId'')='+QuotedStr(UserId)+
    ' AND json_extract(_ferretdb_sjson,''$.boardId'')='+QuotedStr(BoardId)+
    ' AND json_extract(_ferretdb_sjson,''$.$s.p.userId.t'')=''string'''+
    ' AND json_extract(_ferretdb_sjson,''$.$s.p.boardId.t'')=''string'''+
    ' AND json_type(_ferretdb_sjson,''$.undone'')=''true'' AND '+
    'coalesce(json_type(_ferretdb_sjson,''$.isCheckpoint''),'''')<>''true''; ';
  if Shared then DocSql:='CASE WHEN wl_storage('+QuotedStr(TableName)+
    ')=''blob'' THEN jsonb('+DocSql+') ELSE '+DocSql+' END';
  Sql:=Sql+'INSERT INTO '+TableSql+'(_ferretdb_sjson) SELECT '+DocSql+' WHERE '+Owner+'; COMMIT;';
  if not Db.Exec(Sql) then Db.Exec('ROLLBACK;');
end;

end.
