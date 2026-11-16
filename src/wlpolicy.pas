unit wlpolicy;
{$mode objfpc}{$H+}
interface
uses SysUtils,fpjson,wlsjson,wltotp;
type TFactorPolicy=(fpDenied,fpNone,fpRequired,fpOTP);
  TFactorSettings=record
    Mode,LDAPEnabled,LDAPFallback,LDAPMigration,PasswordEnabled:string;
  end;
function EnvironmentFactorSettings:TFactorSettings;
function FactorPolicyWithSettings(const Method,Services:string;IsAdmin:Boolean;
  const Settings:TFactorSettings;out Secret:string):TFactorPolicy;
function FactorPolicy(const Method,Services:string;IsAdmin:Boolean;out Secret:string):TFactorPolicy;
function PasswordOnlyAllowed(const Method,Services:string;IsAdmin:Boolean=False):Boolean;
implementation
function EnvironmentFactorSettings:TFactorSettings;
begin
  Result.Mode:=GetEnvironmentVariable('REQUIRE_2FA');Result.LDAPEnabled:=GetEnvironmentVariable('LDAP_ENABLE');
  Result.LDAPFallback:=GetEnvironmentVariable('LDAP_LOGIN_FALLBACK');Result.LDAPMigration:=GetEnvironmentVariable('LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN');
  Result.PasswordEnabled:='true'; // preserve the native-store policy contract
end;
function FactorPolicy(const Method,Services:string;IsAdmin:Boolean;out Secret:string):TFactorPolicy;
begin Result:=FactorPolicyWithSettings(Method,Services,IsAdmin,EnvironmentFactorSettings,Secret);end;
function FactorPolicyWithSettings(const Method,Services:string;IsAdmin:Boolean;const Settings:TFactorSettings;out Secret:string):TFactorPolicy;
var Root:TJSONObject;Factor,Kind,Value,Password:TJSONData;Mode,Canonical:string;Required:Boolean;
begin
  Result:=fpDenied;Secret:='';Root:=nil;
  if Settings.PasswordEnabled='false' then Exit;
  if (Method='ldap') and (Settings.LDAPEnabled='true') and
    (Settings.LDAPFallback<>'true') and (Settings.LDAPMigration<>'true') then Exit;
  try
    try
      Root:=ExactObject(Services);Password:=Root.Find('password');
      Mode:=LowerCase(Trim(Settings.Mode));
      Required:=((Method='') or (Method='password')) and (Password<>nil) and (Password.JSONType<>jtNull) and
        ((Mode='all') or ((Mode='admins') and IsAdmin));
      Factor:=Root.Find('twoFactorAuthentication');
      if (Factor<>nil) and (Factor.JSONType<>jtNull) then
      begin
        if not (Factor is TJSONObject) then Exit;
        Value:=TJSONObject(Factor).Find('secret');
        if (Value<>nil) and (Value.JSONType<>jtString) then Exit;
        Kind:=TJSONObject(Factor).Find('type');
        if Kind<>nil then
        begin
          if (Kind.JSONType<>jtString) or (Kind.AsString<>'otp') or (Value=nil) then Exit;
          Canonical:=OTPCanonicalSecret(Value.AsString);
          Secret:=Canonical;Result:=fpOTP;Exit;
        end;
      end;
      if Required then Result:=fpRequired else Result:=fpNone;
    except Result:=fpDenied;Secret:='';end;
  finally Root.Free;end;
end;
function PasswordOnlyAllowed(const Method,Services:string;IsAdmin:Boolean):Boolean;
var Secret:string;
begin
  Result:=FactorPolicy(Method,Services,IsAdmin,Secret)=fpNone;
  if Secret<>'' then begin UniqueString(Secret);FillChar(Secret[1],Length(Secret),0);end;
end;
end.
