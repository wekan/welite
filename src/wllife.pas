unit wllife;
{$mode objfpc}{$H+}
interface
uses SysUtils,Math;
// Shared lifetime arithmetic uses IEEE binary64, as Meteor/JavaScript does.
// Empty/zero selects WeKan's startup default. Unsupported inputs fail closed.
function TokenLifetimeMs(const Days:string):Double;
function TokenExpirationMs(WhenMs:Int64;LifetimeMs:Double):Int64;
implementation
function TokenLifetimeMs(const Days:string):Double;
var Value:Double;Text:string;Settings:TFormatSettings;i:Integer;HasDigit:Boolean;
begin
  Text:=Trim(Days);Value:=0;
  if Text<>'' then
  begin
    // Accept decimal/scientific numbers, independent of host decimal separator.
    // Do not let Pascal-specific numeric syntax or NaN/Infinity through.
    HasDigit:=False;
    for i:=1 to Length(Text) do
    begin
      if not (Text[i] in ['0'..'9','+','-','.','e','E']) then
        raise Exception.Create('Unsupported shared token lifetime');
      if Text[i] in ['0'..'9'] then HasDigit:=True;
    end;
    Settings:=DefaultFormatSettings;Settings.DecimalSeparator:='.';
    if not HasDigit or not TryStrToFloat(Text,Value,Settings) then
      raise Exception.Create('Unsupported shared token lifetime');
  end;
  if IsNan(Value) or IsInfinite(Value) then raise Exception.Create('Unsupported shared token lifetime');
  if Value=0 then Value:=90;
  if (Value<0) or (Value>36500) then raise Exception.Create('Unsupported shared token lifetime');
  Result:=Value*86400000.0;
end;
function TokenExpirationMs(WhenMs:Int64;LifetimeMs:Double):Int64;
const MaxDateMs:Int64=8640000000000000;
var Sum:Double;
begin
  if (WhenMs< -MaxDateMs) or (WhenMs>MaxDateMs) or IsNan(LifetimeMs) or
    IsInfinite(LifetimeMs) or (LifetimeMs<=0) then
    raise Exception.Create('Invalid token expiry');
  // Assignment to Double forces the same rounding before TimeClip on x87 too.
  Sum:=Double(WhenMs)+LifetimeMs;
  if IsNan(Sum) or IsInfinite(Sum) or (Sum< -MaxDateMs) or (Sum>MaxDateMs) then
    raise Exception.Create('Invalid token expiry');
  Result:=Trunc(Sum);
end;
end.
