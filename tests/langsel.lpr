program langsel;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wlstatic,wli18n;
var Language:TWLLanguage;Data:TBytes;Input:string;
function Embedded(const Path:string;out Bytes:TBytes;out Mime:string):Boolean;
var Stream:TFileStream;
begin
  Result:=Path='i18n/locales.jsn';Bytes:=nil;Mime:='application/json';
  if not Result then Exit;
  Stream:=TFileStream.Create(ParamStr(2),fmOpenRead);
  try SetLength(Bytes,Stream.Size);if Length(Bytes)>0 then Stream.ReadBuffer(Bytes[0],Length(Bytes));
  finally Stream.Free;end;
end;
begin
  StaticInit('/',ParamStr(1));StaticAddRoot('/i18n','i18n/',ParamStr(1));
  if ParamStr(1)='embedded' then EmbeddedLookup:=@Embedded;
  if InitLanguages then Writeln('loaded') else Writeln('fallback');
  Writeln(LanguageCount);
  if ParamStr(1)='embedded' then Input:=ParamStr(3) else Input:=ParamStr(2);
  if ParamStr(1)='embedded' then Language:=ResolveLanguage(Input,ParamStr(4),ParamStr(5))
  else Language:=ResolveLanguage(Input,ParamStr(3),ParamStr(4));
  Writeln(Language.Tag);if Language.Rtl then Writeln('rtl') else Writeln('ltr');
  Writeln(Language.FileName);
  if ReadStaticAsset('/i18n','../locales.jsn',Data) or ReadStaticAsset('/i18n','\locales.jsn',Data) or
    ReadStaticAsset('/i18n','/locales.jsn',Data) then Halt(2);
end.
