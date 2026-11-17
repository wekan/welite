program xlate;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wlstatic,wli18n;
var Language:TWLLanguage;Translator:TWLTranslator;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  StaticInit('/',ParamStr(1));StaticAddRoot('/i18n','i18n/',ParamStr(1));InitLanguages;
  Language:=ResolveLanguage(ParamStr(2),'','');Translator:=TWLTranslator.Create(Language);
  try Write(Translator.Text(ParamStr(3),ParamStr(4)));
  finally Translator.Free;end;
end.
