program pathid;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
uses SysUtils,fpjson,jsonparser,HTTPDefs,wlpath;
var Line,Decoded:string;Input:TJSONObject;Output:TJSONArray;Request:TRequest;First,Second:Boolean;i:Integer;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  while not EOF(System.Input) do
  begin
    Readln(Line);Input:=nil;Output:=nil;Request:=nil;
    try
      Input:=TJSONObject(GetJSON(Line));Output:=TJSONArray.Create;
      if Input.Get('mode','decode')='all' then
      begin
        Request:=TRequest.Create;
        for i:=0 to High(ApiPathKeys) do Request.RouteParams[ApiPathKeys[i]]:=Input.Get('value','');
        First:=DecodeApiPath(Request);Second:=DecodeApiPath(Request);Output.Add(First);Output.Add(Second);
        for i:=0 to High(ApiPathKeys) do Output.Add(Request.RouteParams[ApiPathKeys[i]]);
      end
      else if Input.Get('mode','decode')='request' then
      begin
        Request:=TRequest.Create;
        Request.RouteParams['boardId']:=Input.Get('board','');
        Request.RouteParams['cardId']:=Input.Get('card','');
        Request.QueryFields.Values['_wl_path_decoded']:='1';
        First:=DecodeApiPath(Request);Second:=DecodeApiPath(Request);
        Output.Add(First);Output.Add(Second);
        Output.Add(Request.RouteParams['boardId']);Output.Add(Request.RouteParams['cardId']);
      end
      else begin
        First:=DecodePathId(Input.Get('value',''),Decoded);Output.Add(First);Output.Add(Decoded);
      end;
      Writeln(Output.AsJSON);
    except on E:Exception do Writeln('{"error":"invalid"}');end;
    Request.Free;Output.Free;Input.Free;
  end;
end.
