program blake;
{$mode objfpc}{$H+}
uses SysUtils,wlblake;
var Data,Line,Digest:string;i,Bytes:Integer;
begin
  try
    Readln(Line);Data:='';
    if (Length(Line) mod 2)<>0 then raise Exception.Create('hex');
    SetLength(Data,Length(Line) div 2);
    for i:=1 to Length(Data) do Data[i]:=Chr(StrToInt('$'+Copy(Line,i*2-1,2)));
    Bytes:=StrToInt(ParamStr(2));
    if ParamStr(1)='argon' then Digest:=ArgonHash(Data,Bytes) else Digest:=Blake2b(Data,Bytes);
    for i:=1 to Length(Digest) do Write(LowerCase(IntToHex(Ord(Digest[i]),2)));Writeln;
  except Writeln('error');end;
end.
