unit wlattdel;
{$mode objfpc}{$H+}
interface
uses wldb;
function SharedAttachmentRemovalSQL(Db:TWLDb;const Actor,BoardId,Scope,Claim:string;ClearCardCover:Boolean):string;
procedure RecordSharedAttachmentRemovals(Db:TWLDb;const Actor,BoardId,BatchId:string);
procedure RetrySharedAttachmentHistory(Db:TWLDb;const BoardId,AttachmentId:string);
implementation
uses SysUtils,DateUtils,wlshared,wlferr,wlchhist;
function SharedAttachmentRemovalSQL(Db:TWLDb;const Actor,BoardId,Scope,Claim:string;ClearCardCover:Boolean):string;
var Live,Registry,Files,Cards,Patch,ClearCover,Stamp:string;Rows:TWLRows;AtTime:TDateTime;
  function StoreExpression(const Physical,Expression:string):string;
  begin Result:='CASE WHEN wl_storage('+QuotedStr(Physical)+')=''blob'' THEN jsonb('+Expression+') ELSE '+Expression+' END';end;
  function PhysicalName(const Name:string):string;
  begin Result:='"'+StringReplace(Name,'"','""',[rfReplaceAll])+'"';end;
begin
  Result:='';
  if not SharedStore(Db) then Exit;
  Rows:=Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''attachments'';');
  if Length(Rows)<>1 then raise Exception.Create('Missing attachment collection');
  Files:=Rows[0][0];
  Registry:='(SELECT count(*) FROM _ferretdb_collections WHERE name=''attachments'' AND table_name='+QuotedStr(Files)+')=1';
  Live:=Scope+' AND '+LiveAttachmentSQL(Db);
  AtTime:=Now;
  Stamp:=QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(AtTime)));
  Patch:='wl_sjson(json_set(wl_plain(json(_ferretdb_sjson)),''$.deletedAt'','+
    IntToStr(UnixMillis(AtTime))+',''$.deletedBy'','+QuotedStr(Actor)+',''$.deleteBatchId'','+Claim+
    '),json(_ferretdb_sjson),''{"deletedAt":"date"}'')';
  if ClearCardCover then
  begin
    Rows:=Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''cards'';');
    if Length(Rows)<>1 then raise Exception.Create('Missing card collection');
    Cards:=Rows[0][0];
    Registry:=Registry+' AND (SELECT count(*) FROM _ferretdb_collections WHERE name=''cards'' AND table_name='+QuotedStr(Cards)+')=1';
    ClearCover:='wl_sjson(json_remove(wl_plain(json(_ferretdb_sjson)),''$.coverId''),json(_ferretdb_sjson),''{}'')';
    Result:='UPDATE '+PhysicalName(Cards)+' SET _ferretdb_sjson='+StoreExpression(Cards,ClearCover)+
      ' WHERE json_extract(_ferretdb_sjson,''$.boardId'')='+QuotedStr(BoardId)+
      ' AND EXISTS(SELECT 1 FROM attachments WHERE '+Live+' AND cardId=json_extract('+PhysicalName(Cards)+
      '._ferretdb_sjson,''$._id'') AND id=json_extract('+PhysicalName(Cards)+'._ferretdb_sjson,''$.coverId'')); ';
  end;
  Result:='SELECT CASE WHEN '+Registry+' THEN 1 ELSE json(''Attachment collection changed'') END; '+
    'INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) '+
    'SELECT '+Claim+'||'':''||id,''deleteAttachment'','+QuotedStr(Actor)+',boardId,cardId,listId,swimlaneId,'+
    Stamp+','+Stamp+',json_object(''attachmentId'',id,''attachmentName'',name,''type'',''card'') FROM attachments WHERE '+
    Live+' AND COALESCE(cardId,'''')<>''''; '+Result+
    'UPDATE '+PhysicalName(Files)+' SET _ferretdb_sjson='+StoreExpression(Files,Patch)+
    ' WHERE json_extract(_ferretdb_sjson,''$._id'') IN (SELECT id FROM attachments WHERE '+Live+'); '+
    'SELECT CASE WHEN '+Registry+' AND NOT EXISTS(SELECT 1 FROM attachments WHERE '+Live+
    ') THEN 1 ELSE json(''Attachment deletion failed'') END; ';
end;

function AttachmentDocumentTable(Db:TWLDb):string;
var Rows:TWLRows;
begin
  Result:='';
  Rows:=Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''attachments'';');
  if Length(Rows)=1 then Result:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
end;

procedure RecordSharedAttachmentRemovals(Db:TWLDb;const Actor,BoardId,BatchId:string);
var Rows:TWLRows;Row:TWLRow;Physical:string;
begin
  if not SharedStore(Db) then Exit;
  Physical:=AttachmentDocumentTable(Db);
  if Physical='' then Exit;
  Rows:=Db.Query('SELECT id,swimlaneId,listId,cardId,name,'+
    'strftime(''%Y-%m-%dT%H:%M:%fZ'',json_extract(a._ferretdb_sjson,''$.deletedAt'')/1000.0,''unixepoch'') '+
    'FROM attachments JOIN '+Physical+' a ON json_extract(a._ferretdb_sjson,''$._id'')=attachments.id '+
    'WHERE boardId='+QuotedStr(BoardId)+' AND json_extract(a._ferretdb_sjson,''$.deleteBatchId'')='+QuotedStr(BatchId)+
    ' AND json_extract(a._ferretdb_sjson,''$.deletedBy'')='+QuotedStr(Actor)+
    ' AND json_extract(a._ferretdb_sjson,''$."$s".p.deletedAt.t'')=''date'' ORDER BY id;');
  for Row in Rows do
    try RecordAttachmentRemoval(Db,Actor,BoardId,Row[1],Row[2],Row[3],Row[0],Row[4],BatchId,Row[5]);except end;
end;

procedure RetrySharedAttachmentHistory(Db:TWLDb;const BoardId,AttachmentId:string);
var Rows:TWLRows;Physical:string;
begin
  Physical:=AttachmentDocumentTable(Db);
  if Physical='' then Exit;
  Rows:=Db.Query('SELECT json_extract(_ferretdb_sjson,''$.deletedBy''),json_extract(_ferretdb_sjson,''$.deleteBatchId'') '+
    'FROM '+Physical+' WHERE json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(AttachmentId)+
    ' AND json_extract(_ferretdb_sjson,''$.meta.boardId'')='+QuotedStr(BoardId)+
    ' AND json_extract(_ferretdb_sjson,''$."$s".p.deletedAt.t'')=''date'''+
    ' AND json_extract(_ferretdb_sjson,''$."$s".p.deletedBy.t'')=''string'''+
    ' AND json_extract(_ferretdb_sjson,''$."$s".p.deleteBatchId.t'')=''string'';');
  if (Length(Rows)=1) and (Rows[0][0]<>'') and (Rows[0][1]<>'') then
    RecordSharedAttachmentRemovals(Db,Rows[0][0],BoardId,Rows[0][1]);
end;

end.
