unit wlpolicy;
{$mode objfpc}{$H+}
interface
uses SysUtils,fpjson,wlsjson,wltotp;
type TFactorPolicy=(fpDenied,fpNone,fpRequired,fpOTP);
function FactorPolicy(const Method,Services:string;IsAdmin:Boolean;out Secret:string):TFactorPolicy;
function PasswordOnlyAllowed(const Method,Services:string;IsAdmin:Boolean=False):Boolean;
implementation
function FactorPolicy(const Method,Services:string;IsAdmin:Boolean;out Secret:string):TFactorPolicy;
var Root:TJSONObject;Factor,Kind,Value,Password:TJSONData;Mode,Canonical:string;Required:Boolean;
begin
  Result:=fpDenied;Secret:='';Root:=nil;
  if (Method='ldap') and (GetEnvironmentVariable('LDAP_ENABLE')='true') and
    (GetEnvironmentVariable('LDAP_LOGIN_FALLBACK')<>'true') and
    (GetEnvironmentVariable('LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN')<>'true') then Exit;
  try
    try
      Root:=ExactObject(Services);Password:=Root.Find('password');
      Mode:=LowerCase(Trim(GetEnvironmentVariable('REQUIRE_2FA')));
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
