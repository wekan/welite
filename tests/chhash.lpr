program chhash;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,wlsjson,wlchhash;
var Line,RowHash,PendingHash:string;Row:TJSONObject;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  while not EOF do
  begin
    ReadLn(Line);
    Row:=ExactObject(Line);
    try
      if Row.Find('$s')<>nil then
      begin
        ReservationHashes(Line,RowHash,PendingHash);
        WriteLn(RowHash,' ',PendingHash);
      end
      else WriteLn(ListLifecycleHash(Row),' ',ListReservationHash(Row));
    finally Row.Free;end;
  end;
end.
