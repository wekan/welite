unit wlwhurl;
{$mode objfpc}{$H+}
interface

// Write-time destination validation. Delivery must independently pin a checked address.
function PublicWebhookUrl(const Value:string):Boolean;

implementation
uses SysUtils{$IFDEF LINUX},Sockets,cnetdb{$ENDIF};

{$IFDEF LINUX}
function PublicV4(const A:in_addr):Boolean;
var B:array[0..3] of Byte;
begin
  Move(A,B,SizeOf(B));
  Result:=not (B[0] in [0,10,127,224..255]) and
    not ((B[0]=100) and (B[1] in [64..127])) and
    not ((B[0]=169) and (B[1]=254)) and
    not ((B[0]=172) and (B[1] in [16..31])) and
    not ((B[0]=192) and ((B[1]=168) or ((B[1]=0) and (B[2] in [0,2])) or
      ((B[1]=88) and (B[2]=99)))) and
    not ((B[0]=198) and ((B[1] in [18,19]) or ((B[1]=51) and (B[2]=100)))) and
    not ((B[0]=203) and (B[1]=0) and (B[2]=113));
end;

function PublicV6(const A:in6_addr):Boolean;
var B:array[0..15] of Byte;
begin
  Move(A,B,SizeOf(B));
  Result:=(B[0] in [$20..$3f]) and
    not ((B[0]=$20) and ((B[1]=2) or ((B[1]=1) and ((B[2]<$02) or
      ((B[2]=$0d) and (B[3]=$b8)))))) and
    not ((B[0]=$3f) and (B[1]=$ff));
end;

function PublicHost(const Host:string):Boolean;
var Hints:TAddrInfo;Addresses,Current:PAddrInfo;
begin
  Result:=False;
  FillChar(Hints,SizeOf(Hints),0);
  Hints.ai_socktype:=SOCK_STREAM;
  Addresses:=nil;
  if getaddrinfo(PChar(Host),nil,@Hints,@Addresses)<>0 then Exit;
  try
    if Addresses=nil then Exit;
    Current:=Addresses;
    while Current<>nil do
    begin
      if Current^.ai_addr=nil then Exit;
      case Current^.ai_family of
        AF_INET: if (Current^.ai_addrlen<SizeOf(TInetSockAddr)) or
          not PublicV4(PInetSockAddr(Current^.ai_addr)^.sin_addr) then Exit;
        AF_INET6: if (Current^.ai_addrlen<SizeOf(TInetSockAddr6)) or
          not PublicV6(PInetSockAddr6(Current^.ai_addr)^.sin6_addr) then Exit;
        else Exit;
      end;
      Current:=Current^.ai_next;
    end;
    Result:=True;
  finally freeaddrinfo(Addresses);end;
end;
{$ENDIF}

function PublicWebhookUrl(const Value:string):Boolean;
{$IFDEF LINUX}
var Host,Authority,PortText:string;I,Start,Delim,Port:Integer;C:Char;
{$ENDIF}
begin
  Result:=False;
  {$IFDEF LINUX}
  if Length(Value)>2048 then Exit;
  for C in Value do if (Ord(C)<=$20) or (Ord(C)>=$7f) or (C='\') then Exit;
  if SameText(Copy(Value,1,8),'https://') then Start:=9
  else if SameText(Copy(Value,1,7),'http://') then Start:=8
  else Exit;
  I:=Start;
  while (I<=Length(Value)) and not (Value[I] in ['/','?','#']) do Inc(I);
  Authority:=Copy(Value,Start,I-Start);
  if Authority='' then Exit;
  if Authority[1]='[' then
  begin
    Delim:=Pos(']',Authority);
    if Delim=0 then Exit;
    Host:=Copy(Authority,2,Delim-2);
    if Pos(':',Host)=0 then Exit;
    for C in Host do if not (C in ['0'..'9','a'..'f','A'..'F',':','.']) then Exit;
    PortText:=Copy(Authority,Delim+1,MaxInt);
  end
  else
  begin
    Delim:=Pos(':',Authority);
    if Delim=0 then Host:=Authority else Host:=Copy(Authority,1,Delim-1);
    if Pos('.',Host)=0 then Exit;
    for C in Host do if not (C in ['0'..'9','a'..'z','A'..'Z','-','.']) then Exit;
    if Delim>0 then PortText:=Copy(Authority,Delim,MaxInt) else PortText:='';
  end;
  if PortText<>'' then
  begin
    if (Length(PortText)<2) or (PortText[1]<>':') then Exit;
    Delete(PortText,1,1);
    for C in PortText do if not (C in ['0'..'9']) then Exit;
    if not TryStrToInt(PortText,Port) or (Port<1) or (Port>65535) then Exit;
  end;
  Result:=PublicHost(Host);
  {$ENDIF}
end;
end.
