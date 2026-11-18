unit wlchhist;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses wldb;

procedure RecordNativeListChange(Db:TWLDb;const UserId,BoardId,ListId,LaneId,BatchId,DeletedAt:string;
  Restored:Boolean);

implementation
uses SysUtils,DateUtils,fpjson,wlchhash,wlsjson;

function Milliseconds(const Text:string):Int64;
var Date:TDateTime;Stamp,Epoch:TTimeStamp;
begin
  if not TryISO8601ToDate(Text,Date,True) then raise Exception.Create('Invalid history date');
  Stamp:=DateTimeToTimeStamp(Date);Epoch:=DateTimeToTimeStamp(EncodeDate(1970,1,1));
  Result:=Int64(Stamp.Date-Epoch.Date)*86400000+Stamp.Time;
end;

procedure RecordNativeListChange(Db:TWLDb;const UserId,BoardId,ListId,LaneId,BatchId,DeletedAt:string;
  Restored:Boolean);
const Schema='CREATE TABLE IF NOT EXISTS _wl_change_history('+
  'id TEXT PRIMARY KEY,boardId TEXT NOT NULL,userId TEXT NOT NULL,integrityHash TEXT NOT NULL,'+
  'document TEXT NOT NULL CHECK(json_valid(document))); '+
  'CREATE INDEX IF NOT EXISTS _wl_change_board ON _wl_change_history(boardId);';
var Row,BeforeState,AfterState,DateState,Hints:TJSONObject;Rows:TWLRows;
  BoardSql,UserSql,Lookup,Previous,Stamp,Id,ChangeType,DateKey,Hash,Doc,Sql:string;Attempt:Integer;
begin
  if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))<>0 then Exit;
  if not Db.Exec(Schema) then Exit;
  BoardSql:=QuotedStr(BoardId);UserSql:=QuotedStr(UserId);
  Lookup:='SELECT integrityHash FROM _wl_change_history WHERE boardId='+BoardSql+' ORDER BY rowid DESC LIMIT 1';
  Rows:=Db.Query('SELECT lower(hex(randomblob(12)));');
  if Length(Rows)<>1 then Exit;
  Id:=Rows[0][0];
  for Attempt:=1 to 5 do
  begin
    Rows:=Db.Query(Lookup+';');Previous:='';
    if Length(Rows)=1 then Previous:=Rows[0][0];
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
    Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN coalesce(('+Lookup+'),'''')='+QuotedStr(Previous)+
      ' THEN 1 ELSE json(''History tip changed'') END; '+
      'UPDATE _wl_change_history SET document=json_set(document,''$.superseded'',json(''true''))'+
      ' WHERE boardId='+BoardSql+' AND userId='+UserSql+' AND json_type(document,''$.undone'')=''true'''+
      ' AND json_type(document,''$.superseded'')=''false''; '+
      'INSERT INTO _wl_change_history VALUES('+QuotedStr(Id)+','+BoardSql+','+UserSql+','+QuotedStr(Hash)+','+Doc+'); COMMIT;';
    if Db.Exec(Sql) then Exit;
    Db.Exec('ROLLBACK;');
  end;
end;

end.
