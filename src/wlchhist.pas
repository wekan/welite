unit wlchhist;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses wldb;

procedure RecordListChange(Db:TWLDb;const UserId,BoardId,ListId,LaneId,BatchId,DeletedAt:string;
  Restored:Boolean);
procedure RecordAttachmentRemoval(Db:TWLDb;const UserId,BoardId,LaneId,ListId,CardId,AttachmentId,Name,BatchId,DeletedAt:string);

implementation
uses SysUtils,DateUtils,fpjson,wlchhash,wlsjson,wlferr;

function Milliseconds(const Text:string):Int64;
var Date:TDateTime;Stamp,Epoch:TTimeStamp;
begin
  if not TryISO8601ToDate(Text,Date,True) then raise Exception.Create('Invalid history date');
  Stamp:=DateTimeToTimeStamp(Date);Epoch:=DateTimeToTimeStamp(EncodeDate(1970,1,1));
  Result:=Int64(Stamp.Date-Epoch.Date)*86400000+Stamp.Time;
end;

procedure RecordLifecycleChange(Db:TWLDb;const UserId,BoardId,ListId,LaneId,BatchId,DeletedAt,
  EntityType,EntityId,CardId,Name:string;Restored:Boolean);
const GateCollections:array[0..1] of string=('historyWriterGates','historyChainHeads');
  Schema='CREATE TABLE IF NOT EXISTS _wl_change_history('+
  'id TEXT PRIMARY KEY,boardId TEXT NOT NULL,userId TEXT NOT NULL,integrityHash TEXT NOT NULL,'+
  'document TEXT NOT NULL CHECK(json_valid(document))); '+
  'CREATE INDEX IF NOT EXISTS _wl_change_board ON _wl_change_history(boardId);';
  VersionOne='json_type(_ferretdb_sjson,''$.version'') IN (''integer'',''real'')'+
    ' AND json_extract(_ferretdb_sjson,''$.version'')=1';
  MigrationId='json_extract(_ferretdb_sjson,''$.migrationId'')';
  HeadHash='json_extract(_ferretdb_sjson,''$.hash'')';
var Row,BeforeState,AfterState,DateState,Hints:TJSONObject;Rows:TWLRows;
  BoardSql,UserSql,Lookup,LookupSource,Previous,Stamp,Id,ChangeType,DateKey,Hash,Doc,Sql,
    TableName,TableSql,Gate,GateTable,Guard,BoardScope,RedoSql,InsertSql,HeadTable,HeadScope,HeadWrite,HeadValue,GateScope,AlreadyRecorded:string;
  Attempt:Integer;Shared,Coordinated:Boolean;
  function Ident(const Name:string):string;
  begin Result:='"'+StringReplace(Name,'"','""',[rfReplaceAll])+'"';end;
  function CollectionTable(const Name:string):TWLRows;
  begin
    Result:=Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(Name)+';');
  end;
  procedure RecoverLegacyLease(const GateName:string);
  var LeaseRows,WriterRows:TWLRows;WriterRow:TWLRow;LeaseName,LeaseTable,GateIdentity,Grace,UuidPattern:string;GraceMs:Int64;
    procedure RetireWriter(const WriterId:string;Joined:Boolean);
    var WriterToken,WriterGateScope,LeaseIdentity,Registry,RecoverySql,Replacement,Claim,ClaimSql,
      FenceSql,FenceDoc,HistoryIdentity,GateWrite:string;Tombstone:TJSONObject;
    begin
      WriterToken:=QuotedStr(WriterId);
      WriterGateScope:=GateIdentity+' AND (SELECT count(*) FROM json_each(_ferretdb_sjson,''$.writers'') WHERE value='+
        WriterToken+')='+IntToStr(Ord(Joined));
      LeaseIdentity:='json_extract(_ferretdb_sjson,''$._id'')='+WriterToken+
        ' AND json_extract(_ferretdb_sjson,''$.boardId'')='+BoardSql+
        ' AND json_extract(_ferretdb_sjson,''$.$s.p._id.t'')=''string'''+
        ' AND json_extract(_ferretdb_sjson,''$.$s.p.boardId.t'')=''string'''+
        ' AND '+VersionOne+' AND (json_type(_ferretdb_sjson,''$.pending'')=''null'' OR '+
        '(json_extract(_ferretdb_sjson,''$.$s.p.pending.t'')=''string'' AND '+
        'length(json_extract(_ferretdb_sjson,''$.pending'')) BETWEEN 1 AND 128))'+
        ' AND json_extract(_ferretdb_sjson,''$.$s.p.state.t'')=''string'''+
        ' AND json_extract(_ferretdb_sjson,''$.$s.p.expiresAt.t'')=''date'''+
        ' AND json_type(_ferretdb_sjson,''$.expiresAt'')=''integer'''+
        ' AND (json_extract(_ferretdb_sjson,''$.state'')=''fenced'' OR '+
        '(json_extract(_ferretdb_sjson,''$.state'')=''active'' AND '+
        'json_extract(_ferretdb_sjson,''$.expiresAt'')<=unixepoch(''subsec'')*1000-'+IntToStr(GraceMs)+'))'+
        ' AND (SELECT count(*) FROM json_each(_ferretdb_sjson))=7';
      LeaseRows:=Db.Query('SELECT coalesce(json_extract(_ferretdb_sjson,''$.pending''),'''') FROM '+LeaseTable+
        ' WHERE '+LeaseIdentity+';');
      if Length(LeaseRows)<>1 then Exit;
      Claim:=LeaseRows[0][0];FenceSql:='';
      if Pos(#0,Claim)>0 then Exit;
      if Claim='' then LeaseIdentity:=LeaseIdentity+' AND json_type(_ferretdb_sjson,''$.pending'')=''null'''
      else
      begin
        ClaimSql:=QuotedStr(Claim);
        LeaseIdentity:=LeaseIdentity+' AND json_extract(_ferretdb_sjson,''$.pending'')='+ClaimSql;
        HistoryIdentity:='json_extract(_ferretdb_sjson,''$._id'')='+ClaimSql+
          ' AND json_extract(_ferretdb_sjson,''$.$s.p._id.t'')=''string''';
        Tombstone:=TJSONObject.Create(['_id',Claim,'boardId','#history-writer-fence','fencedWriter',WriterId]);
        try FenceDoc:=QuotedStr(TypedDocument(Tombstone.AsJSON,'','{}'));finally Tombstone.Free;end;
        FenceSql:='INSERT INTO '+TableSql+'(_ferretdb_sjson) SELECT CASE WHEN wl_storage('+QuotedStr(TableName)+
          ')=''blob'' THEN jsonb('+FenceDoc+') ELSE '+FenceDoc+' END WHERE NOT EXISTS(SELECT 1 FROM '+
          TableSql+' WHERE '+HistoryIdentity+'); SELECT CASE WHEN (SELECT count(*) FROM '+TableSql+
          ' WHERE '+HistoryIdentity+')=1 THEN 1 ELSE json(''Legacy row fence failed'') END; ';
      end;
      Registry:='(SELECT count(*) FROM _ferretdb_collections WHERE name=''historyWriterLeases'' AND table_name='+
        QuotedStr(LeaseName)+')=1';
      Replacement:='wl_sjson(json_remove(wl_plain(json(_ferretdb_sjson)),''$.writers[''||'+
        '(SELECT key FROM json_each(_ferretdb_sjson,''$.writers'') WHERE value='+WriterToken+')||'']''),'+
        'json(_ferretdb_sjson),''{}'')';
      GateWrite:='';
      if Joined then
        GateWrite:='UPDATE '+Ident(GateName)+' SET _ferretdb_sjson=CASE WHEN wl_storage('+QuotedStr(GateName)+
          ')=''blob'' THEN jsonb('+Replacement+') ELSE '+Replacement+' END WHERE '+WriterGateScope+
          '; SELECT CASE WHEN changes()=1 THEN 1 ELSE json(''Legacy gate changed'') END; ';
      // Fence the checked claim before retiring the lease and removing the gate
      // token. A late insert cannot reuse the claimed ID after this commits.
      RecoverySql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Guard+' AND '+Registry+' AND (SELECT count(*) FROM '+
        Ident(GateName)+' WHERE '+WriterGateScope+')=1 AND (SELECT count(*) FROM '+LeaseTable+' WHERE '+LeaseIdentity+
        ')=1 THEN 1 ELSE json(''Legacy lease is not recoverable'') END; '+FenceSql+
        'DELETE FROM '+LeaseTable+' WHERE '+LeaseIdentity+
        '; SELECT CASE WHEN changes()=1 THEN 1 ELSE json(''Legacy lease changed'') END; '+GateWrite+'COMMIT;';
      if not Db.Exec(RecoverySql) then Db.Exec('ROLLBACK;');
    end;
  begin
    Grace:=GetEnvironmentVariable('HISTORY_WRITER_LEASE_MS');
    if Grace='' then Grace:='30000';
    if not TryStrToInt64(Grace,GraceMs) or (GraceMs<1000) or (GraceMs>600000) then Exit;
    LeaseRows:=CollectionTable('historyWriterLeases');
    if Length(LeaseRows)<>1 then Exit;
    LeaseName:=LeaseRows[0][0];LeaseTable:=Ident(LeaseName);
    UuidPattern:=QuotedStr(StringReplace('xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx','x','[0-9a-f]',[rfReplaceAll]));
    GateIdentity:='json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(HistoryBoardKey('history-writer-gate',BoardId))+
      ' AND json_extract(_ferretdb_sjson,''$.boardId'')='+BoardSql+
      ' AND json_extract(_ferretdb_sjson,''$.$s.p._id.t'')=''string'''+
      ' AND json_extract(_ferretdb_sjson,''$.$s.p.boardId.t'')=''string'''+
      ' AND '+VersionOne+' AND json_extract(_ferretdb_sjson,''$.$s.p.mode.t'')=''string'''+
      ' AND ((json_extract(_ferretdb_sjson,''$.mode'')=''legacy'' AND json_type(_ferretdb_sjson,''$.migrationId'')=''null'') OR '+
      '(json_extract(_ferretdb_sjson,''$.mode'')=''draining'' AND json_extract(_ferretdb_sjson,''$.$s.p.migrationId.t'')=''string'''+
      ' AND '+MigrationId+' GLOB '+UuidPattern+'))'+
      ' AND json_type(_ferretdb_sjson,''$.writers'')=''array'' AND json_array_length(_ferretdb_sjson,''$.writers'') BETWEEN 0 AND 1000'+
      ' AND NOT EXISTS(SELECT 1 FROM json_each(_ferretdb_sjson,''$.writers'') WHERE type<>''text'' OR value NOT GLOB '+
      UuidPattern+
      ' OR COALESCE(json_extract(_ferretdb_sjson,''$.$s.p.writers.i[''||key||''].t''),'''')<>''string'')'+
      ' AND (SELECT count(DISTINCT value) FROM json_each(_ferretdb_sjson,''$.writers''))=json_array_length(_ferretdb_sjson,''$.writers'')'+
      ' AND (SELECT count(*) FROM json_each(_ferretdb_sjson))=7';
    WriterRows:=Db.Query('SELECT w.value FROM '+Ident(GateName)+
      ' CROSS JOIN json_each(_ferretdb_sjson,''$.writers'') w WHERE '+GateIdentity+';');
    for WriterRow in WriterRows do RetireWriter(WriterRow[0],True);
    if Length(Db.Query('SELECT 1 FROM '+Ident(GateName)+' WHERE '+GateIdentity+';'))<>1 then Exit;
    WriterRows:=Db.Query('SELECT json_extract(lease._ferretdb_sjson,''$._id'') FROM '+LeaseTable+' lease'+
      ' WHERE json_extract(lease._ferretdb_sjson,''$.boardId'')='+BoardSql+
      ' AND json_extract(lease._ferretdb_sjson,''$._id'') GLOB '+UuidPattern+
      ' AND NOT EXISTS(SELECT 1 FROM '+Ident(GateName)+' g CROSS JOIN json_each(g._ferretdb_sjson,''$.writers'') w'+
      ' WHERE json_extract(g._ferretdb_sjson,''$._id'')='+QuotedStr(HistoryBoardKey('history-writer-gate',BoardId))+
      ' AND w.value=json_extract(lease._ferretdb_sjson,''$._id'')) LIMIT 1000;');
    for WriterRow in WriterRows do RetireWriter(WriterRow[0],False);
  end;

  procedure RecoverPending(const IdentityScope:string);
  var PendingRows:TWLRows;Pending:TJSONObject;Head,PendingDoc,PendingId,PendingHash,
    RowHash,OldHash,RowIdentity,Match,Replacement,RecoverySql,Encoded,HeadMatch,ExpectedRowHash,ExpectedPendingHash:string;
    function ValidHash(const Value:string):Boolean;
    var C:Char;
    begin
      if Length(Value)<>64 then Exit(False);
      for C in Value do if not (C in ['0'..'9','a'..'f']) then Exit(False);
      Result:=True;
    end;
  begin
    PendingRows:=Db.Query('SELECT json(_ferretdb_sjson),json_set(json_extract(_ferretdb_sjson,''$.pending''),'+
      '''$.$s'',json_extract(_ferretdb_sjson,''$.$s.p.pending.$s'')),coalesce('+HeadHash+',''''),'+
      'json_extract(_ferretdb_sjson,''$.pendingHash'') FROM '+Ident(HeadTable)+' WHERE '+IdentityScope+
      ' AND json_type(_ferretdb_sjson,''$.pending'')=''object'''+
      ' AND json_type(_ferretdb_sjson,''$.hash'') IN (''null'',''text'')'+
      ' AND json_type(_ferretdb_sjson,''$.pending.previousHash'')=json_type(_ferretdb_sjson,''$.hash'')'+
      ' AND json_extract(_ferretdb_sjson,''$.$s.p.pending.$s.p.createdAt.t'')=''date'''+
      ' AND (SELECT count(*) FROM json_each(_ferretdb_sjson))=7;');
    if Length(PendingRows)<>1 then Exit;
    Head:=PendingRows[0][0];PendingDoc:=PendingRows[0][1];
    OldHash:=PendingRows[0][2];PendingHash:=PendingRows[0][3];
    if (Length(PendingDoc)>1024*1024) or not ValidHash(PendingHash) or
      ((OldHash<>'') and not ValidHash(OldHash)) then Exit;
    Pending:=nil;
    try
      try
        Pending:=ExactObject(PendingDoc);
        PendingId:=Pending.Get('_id','');RowHash:=Pending.Get('integrityHash','');
        if (PendingId='') or (Pos(#0,PendingId)>0) or (Pending.Get('boardId','')<>BoardId) or
          not ValidHash(RowHash) or (Pending.Get('previousHash','')<>OldHash) then Exit;
        ReservationHashes(PendingDoc,ExpectedRowHash,ExpectedPendingHash,RowHash,PendingHash);
        if (ExpectedRowHash<>RowHash) or (ExpectedPendingHash<>PendingHash) then Exit;
      except Exit;end;
    finally Pending.Free;end;
    RowIdentity:='json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(PendingId);
    Encoded:=QuotedStr(PendingDoc);
    Match:=RowIdentity+
      ' AND json_remove(_ferretdb_sjson,''$.$s'')=json_remove('+Encoded+',''$.$s'')'+
      ' AND json_extract(_ferretdb_sjson,''$.$s'')=json_extract('+Encoded+',''$.$s'')';
    // Preserve the reserved data and SJSON metadata, including explicit nulls.
    Replacement:='wl_sjson(json_set(wl_plain(json(_ferretdb_sjson)),''$.hash'','+QuotedStr(RowHash)+
      ',''$.pending'',NULL,''$.pendingHash'',NULL),json(_ferretdb_sjson),''{}'')';
    HeadMatch:=IdentityScope+' AND json(_ferretdb_sjson)='+QuotedStr(Head);
    RecoverySql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Guard+' AND (SELECT count(*) FROM '+
      Ident(HeadTable)+' WHERE '+HeadMatch+')=1 THEN 1 ELSE json(''History reservation changed'') END; '+
      'INSERT INTO '+TableSql+'(_ferretdb_sjson) SELECT CASE WHEN wl_storage('+QuotedStr(TableName)+
      ')=''blob'' THEN jsonb('+Encoded+') ELSE '+Encoded+' END WHERE NOT EXISTS(SELECT 1 FROM '+
      TableSql+' WHERE '+RowIdentity+'); '+
      'SELECT CASE WHEN (SELECT count(*) FROM '+TableSql+' WHERE '+RowIdentity+')=1 AND '+
      '(SELECT count(*) FROM '+TableSql+' WHERE '+Match+')=1 THEN 1 ELSE json(''History reservation row conflict'') END; '+
      'UPDATE '+Ident(HeadTable)+' SET _ferretdb_sjson=CASE WHEN wl_storage('+QuotedStr(HeadTable)+
      ')=''blob'' THEN jsonb('+Replacement+') ELSE '+Replacement+' END WHERE '+HeadMatch+
      '; SELECT CASE WHEN changes()=1 THEN 1 ELSE json(''History reservation head changed'') END; COMMIT;';
    if not Db.Exec(RecoverySql) then Db.Exec('ROLLBACK;');
  end;

begin
  Shared:=Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))<>0;
  BoardSql:=QuotedStr(BoardId);UserSql:=QuotedStr(UserId);Guard:='1';LookupSource:='';Coordinated:=False;AlreadyRecorded:='';
  if Shared then
  begin
    if not EnsureSharedCollection(Db,'changeHistory') then Exit;
    Rows:=CollectionTable('changeHistory');if Length(Rows)<>1 then Exit;
    TableName:=Rows[0][0];TableSql:=Ident(TableName);
    if EntityType='attachment' then
    begin
      AlreadyRecorded:='SELECT 1 FROM '+TableSql+' WHERE json_extract(_ferretdb_sjson,''$.boardId'')='+BoardSql+
        ' AND json_extract(_ferretdb_sjson,''$.entityType'')=''attachment'''+
        ' AND json_extract(_ferretdb_sjson,''$.entityId'')='+QuotedStr(EntityId)+
        ' AND json_extract(_ferretdb_sjson,''$.changeType'')=''removed'''+
        ' AND json_extract(_ferretdb_sjson,''$.batchId'')='+QuotedStr(BatchId);
      if Length(Db.Query(AlreadyRecorded+';'))>0 then Exit;
    end;
    Guard:='(SELECT count(*) FROM _ferretdb_collections WHERE name=''changeHistory'' AND table_name='+
      QuotedStr(TableName)+')=1 AND (SELECT count(*) FROM _ferretdb_collections WHERE table_name='+QuotedStr(TableName)+')=1';
    Rows:=CollectionTable('historyWriterGates');
    if Length(Rows)=1 then
    begin
      GateTable:=Ident(Rows[0][0]);
      GateScope:='json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(HistoryBoardKey('history-writer-gate',BoardId))+
        ' AND json_extract(_ferretdb_sjson,''$.boardId'')='+BoardSql+
        ' AND '+VersionOne+' AND json_extract(_ferretdb_sjson,''$.mode'')=''coordinated'''+
        ' AND json_type(_ferretdb_sjson,''$.migrationId'')=''text'''+
        ' AND '+MigrationId+' GLOB '+QuotedStr(StringReplace('xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
          'x','[0-9a-f]',[rfReplaceAll]))+
        ' AND (SELECT count(*) FROM json_each(_ferretdb_sjson))=7'+
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
        ' AND '+VersionOne+
        ' AND json_extract(_ferretdb_sjson,''$.$s.p._id.t'')=''string'''+
        ' AND json_extract(_ferretdb_sjson,''$.$s.p.boardId.t'')=''string''';
      RecoverPending(HeadScope);
      HeadScope:=HeadScope+' AND json_type(_ferretdb_sjson,''$.pending'')=''null'' AND json_type(_ferretdb_sjson,''$.pendingHash'')=''null'''+
        ' AND (json_type(_ferretdb_sjson,''$.hash'')=''null'' OR '+
        '(json_type(_ferretdb_sjson,''$.hash'')=''text'' AND length('+HeadHash+')=64'+
        ' AND '+HeadHash+' NOT GLOB ''*[^0-9a-f]*''))'+
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
          ' AND table_name='+QuotedStr(GateTable)+')';
        GateScope:='json_extract(_ferretdb_sjson,''$.boardId'')='+BoardSql;
        if Gate='historyWriterGates' then
        begin
          RecoverLegacyLease(GateTable);
          // The complete append uses one SQLite writer transaction. An idle
          // gate cannot acquire a writer or start migration inside it.
          Guard:=Guard+' AND ((SELECT count(*) FROM '+Ident(GateTable)+' WHERE '+GateScope+')=0 OR '+
            '((SELECT count(*) FROM '+Ident(GateTable)+' WHERE '+GateScope+')=1 AND EXISTS(SELECT 1 FROM '+
            Ident(GateTable)+' WHERE '+GateScope+
            ' AND json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(HistoryBoardKey('history-writer-gate',BoardId))+
            ' AND json_extract(_ferretdb_sjson,''$.$s.p._id.t'')=''string'''+
            ' AND json_extract(_ferretdb_sjson,''$.$s.p.boardId.t'')=''string'''+
            ' AND '+VersionOne+' AND json_extract(_ferretdb_sjson,''$.mode'')=''legacy'''+
            ' AND json_extract(_ferretdb_sjson,''$.$s.p.mode.t'')=''string'''+
            ' AND json_type(_ferretdb_sjson,''$.migrationId'')=''null'''+
            ' AND json_type(_ferretdb_sjson,''$.writers'')=''array'' AND json_array_length(_ferretdb_sjson,''$.writers'')=0'+
            ' AND (SELECT count(*) FROM json_each(_ferretdb_sjson))=7)))';
        end
        else Guard:=Guard+' AND NOT EXISTS(SELECT 1 FROM '+Ident(GateTable)+' WHERE '+GateScope+')';
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
  if AlreadyRecorded<>'' then Guard:=Guard+' AND NOT EXISTS('+AlreadyRecorded+')';
  Rows:=Db.Query('SELECT lower(hex(randomblob(12)));');
  if Length(Rows)<>1 then Exit;
  Id:=Rows[0][0];
  for Attempt:=1 to 5 do
  begin
    if (AlreadyRecorded<>'') and (Length(Db.Query(AlreadyRecorded+';'))>0) then Exit;
    Rows:=Db.Query(LookupSource+Lookup+';');
    if Length(Rows)<>1 then Exit;
    Previous:=Rows[0][0];
    if (Previous<>'') and (Length(Previous)<>64) then Exit;
    Stamp:=FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(Now));
    if EntityType='attachment' then Stamp:=DeletedAt;
    ChangeType:='removed';DateKey:='newContent';
    if Restored then begin ChangeType:='added';DateKey:='previousContent';end;
    Row:=TJSONObject.Create(['_id',Id,'boardId',BoardId,'swimlaneId',LaneId,'listId',ListId,
      'entityType',EntityType,'entityId',EntityId,'group','lifecycle','changeType',ChangeType,
      'userId',UserId,'createdAt',Stamp,'undone',False,'superseded',False,'isCheckpoint',False]);
    Hints:=TJSONObject.Create(['createdAt','date']);
    try
      if CardId='' then Row.Add('cardId',TJSONNull.Create) else Row.Add('cardId',CardId);
      if (EntityType='attachment') and (ListId='') then begin Row.Delete('listId');Row.Add('listId',TJSONNull.Create);end;
      if (EntityType='attachment') and (LaneId='') then begin Row.Delete('swimlaneId');Row.Add('swimlaneId',TJSONNull.Create);end;
      Row.Add('restoredFromId',TJSONNull.Create);
      Row.Add('restoredByUserId',TJSONNull.Create);
      Row.Add('undoneAt',TJSONNull.Create);
      if BatchId='' then Row.Add('batchId',TJSONNull.Create) else Row.Add('batchId',BatchId);
      if Previous='' then Row.Add('previousHash',TJSONNull.Create) else Row.Add('previousHash',Previous);
      BeforeState:=TJSONObject.Create(['deleted',Restored]);Row.Add('previousContent',BeforeState);
      DateState:=nil;
      if EntityType='attachment' then
      begin
        BeforeState.Add('name',Name);
        Row.Add('newContent',TJSONNull.Create);
      end
      else
      begin
        AfterState:=TJSONObject.Create(['deleted',not Restored]);Row.Add('newContent',AfterState);
        BeforeState.Add('deleteBatchId',Row.Find('batchId').Clone);
        AfterState.Add('deleteBatchId',Row.Find('batchId').Clone);
        DateState:=Row.Objects[DateKey];DateState.Add('deletedAt',DeletedAt);
      end;
      Hash:=ListLifecycleHash(Row);
      Row.Add('integrityHash',Hash);
      Row.Delete('createdAt');Row.Add('createdAt',Milliseconds(Stamp));
      if DateState<>nil then
      begin
        DateState.Delete('deletedAt');DateState.Add('deletedAt',Milliseconds(DeletedAt));
        Hints.Add(DateKey,TJSONObject.Create(['deletedAt','date']));
      end;
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

procedure RecordListChange(Db:TWLDb;const UserId,BoardId,ListId,LaneId,BatchId,DeletedAt:string;
  Restored:Boolean);
begin
  RecordLifecycleChange(Db,UserId,BoardId,ListId,LaneId,BatchId,DeletedAt,'list',ListId,'','',Restored);
end;

procedure RecordAttachmentRemoval(Db:TWLDb;const UserId,BoardId,LaneId,ListId,CardId,AttachmentId,Name,BatchId,DeletedAt:string);
begin
  RecordLifecycleChange(Db,UserId,BoardId,ListId,LaneId,BatchId,DeletedAt,'attachment',AttachmentId,CardId,Name,False);
end;

end.
