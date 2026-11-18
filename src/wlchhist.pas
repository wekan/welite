unit wlchhist;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses wldb;

procedure RecordListChange(Db:TWLDb;const UserId,BoardId,ListId,LaneId,BatchId,DeletedAt:string;
  Restored:Boolean);

implementation
uses SysUtils,DateUtils,fpjson,wlchhash,wlsjson,wlferr;

function Milliseconds(const Text:string):Int64;
var Date:TDateTime;Stamp,Epoch:TTimeStamp;
begin
  if not TryISO8601ToDate(Text,Date,True) then raise Exception.Create('Invalid history date');
  Stamp:=DateTimeToTimeStamp(Date);Epoch:=DateTimeToTimeStamp(EncodeDate(1970,1,1));
  Result:=Int64(Stamp.Date-Epoch.Date)*86400000+Stamp.Time;
end;

procedure RecordListChange(Db:TWLDb;const UserId,BoardId,ListId,LaneId,BatchId,DeletedAt:string;
  Restored:Boolean);
const GateCollections:array[0..1] of string=('historyWriterGates','historyChainHeads');
  Schema='CREATE TABLE IF NOT EXISTS _wl_change_history('+
  'id TEXT PRIMARY KEY,boardId TEXT NOT NULL,userId TEXT NOT NULL,integrityHash TEXT NOT NULL,'+
  'document TEXT NOT NULL CHECK(json_valid(document))); '+
  'CREATE INDEX IF NOT EXISTS _wl_change_board ON _wl_change_history(boardId);';
var Row,BeforeState,AfterState,DateState,Hints:TJSONObject;Rows:TWLRows;
  BoardSql,UserSql,Lookup,LookupSource,Previous,Stamp,Id,ChangeType,DateKey,Hash,Doc,Sql,
    TableName,TableSql,Gate,GateTable,Guard,BoardScope,RedoSql,InsertSql,HeadTable,HeadScope,HeadWrite,HeadValue,GateScope:string;
  Attempt:Integer;Shared,Coordinated:Boolean;
  function Ident(const Name:string):string;
  begin Result:='"'+StringReplace(Name,'"','""',[rfReplaceAll])+'"';end;
  function CollectionTable(const Name:string):TWLRows;
  begin
    Result:=Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(Name)+';');
  end;
begin
  Shared:=Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))<>0;
  BoardSql:=QuotedStr(BoardId);UserSql:=QuotedStr(UserId);Guard:='1';LookupSource:='';Coordinated:=False;
  if Shared then
  begin
    if not EnsureHistoryCollection(Db,'changeHistory') then Exit;
    Rows:=CollectionTable('changeHistory');if Length(Rows)<>1 then Exit;
    TableName:=Rows[0][0];TableSql:=Ident(TableName);
    Guard:='(SELECT count(*) FROM _ferretdb_collections WHERE name=''changeHistory'' AND table_name='+
      QuotedStr(TableName)+')=1 AND (SELECT count(*) FROM _ferretdb_collections WHERE table_name='+QuotedStr(TableName)+')=1';
    Rows:=CollectionTable('historyWriterGates');
    if Length(Rows)=1 then
    begin
      GateTable:=Ident(Rows[0][0]);
      GateScope:='json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(HistoryBoardKey('history-writer-gate',BoardId))+
        ' AND json_extract(_ferretdb_sjson,''$.boardId'')='+BoardSql+
        ' AND json_extract(_ferretdb_sjson,''$.version'')=1 AND json_extract(_ferretdb_sjson,''$.mode'')=''coordinated'''+
        ' AND json_type(_ferretdb_sjson,''$.writers'')=''array'' AND json_array_length(_ferretdb_sjson,''$.writers'')=0';
      Coordinated:=Length(Db.Query('SELECT 1 FROM '+GateTable+' WHERE '+GateScope+';'))=1;
    end;
    if Coordinated then
    begin
      Guard:=Guard+' AND EXISTS(SELECT 1 FROM _ferretdb_collections WHERE name=''historyWriterGates'' AND table_name='+
        QuotedStr(Rows[0][0])+') AND (SELECT count(*) FROM '+GateTable+' WHERE '+GateScope+')=1';
      Rows:=CollectionTable('historyChainHeads');if Length(Rows)<>1 then Exit;
      HeadTable:=Rows[0][0];
      Guard:=Guard+' AND EXISTS(SELECT 1 FROM _ferretdb_collections WHERE name=''historyChainHeads'' AND table_name='+
        QuotedStr(HeadTable)+')';
      HeadScope:='json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(HistoryBoardKey('history-chain',BoardId))+
        ' AND json_extract(_ferretdb_sjson,''$.boardId'')='+BoardSql+
        ' AND json_extract(_ferretdb_sjson,''$.version'')=1'+
        ' AND json_type(_ferretdb_sjson,''$.pending'')=''null'' AND json_type(_ferretdb_sjson,''$.pendingHash'')=''null'''+
        ' AND json_type(_ferretdb_sjson,''$.hash'') IN (''null'',''text'')'+
        ' AND (SELECT count(*) FROM json_each(_ferretdb_sjson))=7';
      Lookup:='SELECT CASE WHEN (SELECT count(*) FROM '+Ident(HeadTable)+' WHERE '+HeadScope+
        ')=1 THEN (SELECT coalesce(json_extract(_ferretdb_sjson,''$.hash''),'''') FROM '+Ident(HeadTable)+
        ' WHERE '+HeadScope+') ELSE ''invalid head'' END';
    end else
    for Gate in GateCollections do
    begin
      Rows:=CollectionTable(Gate);
      if Length(Rows)=0 then
        Guard:=Guard+' AND NOT EXISTS(SELECT 1 FROM _ferretdb_collections WHERE name='+QuotedStr(Gate)+')'
      else if Length(Rows)=1 then
      begin
        GateTable:=Rows[0][0];
        Guard:=Guard+' AND EXISTS(SELECT 1 FROM _ferretdb_collections WHERE name='+QuotedStr(Gate)+
          ' AND table_name='+QuotedStr(GateTable)+') AND NOT EXISTS(SELECT 1 FROM '+Ident(GateTable)+
          ' WHERE json_extract(_ferretdb_sjson,''$.boardId'')='+BoardSql+')';
      end else Exit;
    end;
    BoardScope:='json_extract(_ferretdb_sjson,''$.boardId'')='+BoardSql+
      ' AND json_extract(_ferretdb_sjson,''$.$s.p.boardId.t'')=''string''';
    if not Coordinated then
    begin
      LookupSource:='WITH hashed(hash,previous) AS (SELECT json_extract(_ferretdb_sjson,''$.integrityHash''),'+
        'json_extract(_ferretdb_sjson,''$.previousHash'') FROM '+TableSql+' WHERE '+BoardScope+
        ' AND json_type(_ferretdb_sjson,''$.integrityHash'')=''text'' AND json_extract(_ferretdb_sjson,''$.integrityHash'')<>''''), '+
        'tips AS (SELECT hash FROM hashed AS row WHERE NOT EXISTS(SELECT 1 FROM hashed WHERE previous=row.hash)) ';
      Lookup:='SELECT CASE WHEN (SELECT count(*) FROM hashed)=0 THEN '''' '+
        'WHEN (SELECT count(*) FROM tips)=1 THEN (SELECT hash FROM tips) ELSE ''invalid tip'' END';
    end;
    RedoSql:='UPDATE '+TableSql+' SET _ferretdb_sjson=CASE WHEN wl_storage('+QuotedStr(TableName)+
      ')=''blob'' THEN jsonb(json_set(_ferretdb_sjson,''$.superseded'',json(''true''))) '+
      'ELSE json_set(_ferretdb_sjson,''$.superseded'',json(''true'')) END WHERE '+BoardScope+
      ' AND json_extract(_ferretdb_sjson,''$.userId'')='+UserSql+
      ' AND json_extract(_ferretdb_sjson,''$.$s.p.userId.t'')=''string'''+
      ' AND json_type(_ferretdb_sjson,''$.undone'')=''true'''+
      ' AND json_type(_ferretdb_sjson,''$.superseded'')=''false''; ';
  end else
  begin
    if not Db.Exec(Schema) then Exit;
    Lookup:='SELECT coalesce((SELECT integrityHash FROM _wl_change_history WHERE boardId='+BoardSql+
      ' ORDER BY rowid DESC LIMIT 1),'''')';
    RedoSql:='UPDATE _wl_change_history SET document=json_set(document,''$.superseded'',json(''true''))'+
      ' WHERE boardId='+BoardSql+' AND userId='+UserSql+' AND json_type(document,''$.undone'')=''true'''+
      ' AND json_type(document,''$.superseded'')=''false''; ';
  end;
  Rows:=Db.Query('SELECT lower(hex(randomblob(12)));');
  if Length(Rows)<>1 then Exit;
  Id:=Rows[0][0];
  for Attempt:=1 to 5 do
  begin
    Rows:=Db.Query(LookupSource+Lookup+';');
    if Length(Rows)<>1 then Exit;
    Previous:=Rows[0][0];
    if (Previous<>'') and (Length(Previous)<>64) then Exit;
    Stamp:=FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(Now));
    ChangeType:='removed';DateKey:='newContent';
    if Restored then begin ChangeType:='added';DateKey:='previousContent';end;
    Row:=TJSONObject.Create(['_id',Id,'boardId',BoardId,'swimlaneId',LaneId,'listId',ListId,
      'entityType','list','entityId',ListId,'group','lifecycle','changeType',ChangeType,
      'userId',UserId,'createdAt',Stamp,'undone',False,'superseded',False,'isCheckpoint',False]);
    Hints:=TJSONObject.Create(['createdAt','date']);
    try
      Row.Add('cardId',TJSONNull.Create);
      Row.Add('restoredFromId',TJSONNull.Create);
      Row.Add('restoredByUserId',TJSONNull.Create);
      Row.Add('undoneAt',TJSONNull.Create);
      if BatchId='' then Row.Add('batchId',TJSONNull.Create) else Row.Add('batchId',BatchId);
      if Previous='' then Row.Add('previousHash',TJSONNull.Create) else Row.Add('previousHash',Previous);
      BeforeState:=TJSONObject.Create(['deleted',Restored]);Row.Add('previousContent',BeforeState);
      AfterState:=TJSONObject.Create(['deleted',not Restored]);Row.Add('newContent',AfterState);
      BeforeState.Add('deleteBatchId',Row.Find('batchId').Clone);
      AfterState.Add('deleteBatchId',Row.Find('batchId').Clone);
      DateState:=Row.Objects[DateKey];DateState.Add('deletedAt',DeletedAt);
      Hash:=ListLifecycleHash(Row);
      Row.Add('integrityHash',Hash);
      Row.Delete('createdAt');Row.Add('createdAt',Milliseconds(Stamp));
      DateState.Delete('deletedAt');DateState.Add('deletedAt',Milliseconds(DeletedAt));
      Hints.Add(DateKey,TJSONObject.Create(['deletedAt','date']));
      Doc:=QuotedStr(TypedDocument(Row.AsJSON,'',Hints.AsJSON));
    finally Hints.Free;Row.Free;end;
    if Shared then
      InsertSql:='INSERT INTO '+TableSql+'(_ferretdb_sjson) VALUES(CASE WHEN wl_storage('+QuotedStr(TableName)+
        ')=''blob'' THEN jsonb('+Doc+') ELSE '+Doc+' END); '
    else
      InsertSql:='INSERT INTO _wl_change_history VALUES('+QuotedStr(Id)+','+BoardSql+','+UserSql+','+QuotedStr(Hash)+','+Doc+'); ';
    HeadWrite:='';
    if Coordinated then
    begin
      HeadValue:='wl_sjson(json_set(wl_plain(json(_ferretdb_sjson)),''$.hash'','+QuotedStr(Hash)+
        '),json(_ferretdb_sjson),''{}'')';
      HeadWrite:='UPDATE '+Ident(HeadTable)+' SET _ferretdb_sjson=CASE WHEN wl_storage('+QuotedStr(HeadTable)+
        ')=''blob'' THEN jsonb('+HeadValue+') ELSE '+HeadValue+' END WHERE '+HeadScope+
        ' AND coalesce(json_extract(_ferretdb_sjson,''$.hash''),'''')='+QuotedStr(Previous)+
        '; SELECT CASE WHEN changes()=1 THEN 1 ELSE json(''History head changed'') END; ';
    end;
    Sql:='BEGIN IMMEDIATE; '+LookupSource+'SELECT CASE WHEN '+Guard+' AND ('+Lookup+')='+QuotedStr(Previous)+
      ' THEN 1 ELSE json(''History tip changed'') END; '+RedoSql+InsertSql+HeadWrite+'COMMIT;';
    if Db.Exec(Sql) then Exit;
    Db.Exec('ROLLBACK;');
  end;
end;

end.
