unit wlpolicy;
{$mode objfpc}{$H+}
interface
uses SysUtils,fpjson,wlsjson;
// A password-only flow cannot satisfy an active/unknown second-factor policy.
// Meteor activation setup has no type until its challenge has been confirmed.
function PasswordOnlyAllowed(const Method,Services:string;IsAdmin:Boolean=False):Boolean;
implementation
function PasswordOnlyAllowed(const Method,Services:string;IsAdmin:Boolean):Boolean;
var Root:TJSONObject;Factor,Kind,Secret,Password:TJSONData;Mode:string;
begin
  Result:=False;Root:=nil;
  // Match server/lib/ldapPasswordLoginGuard.js, including de-LDAP/fallback cases.
  if (Method='ldap') and (GetEnvironmentVariable('LDAP_ENABLE')='true') and
    (GetEnvironmentVariable('LDAP_LOGIN_FALLBACK')<>'true') and
    (GetEnvironmentVariable('LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN')<>'true') then Exit;
  try
    try
      Root:=ExactObject(Services);Password:=Root.Find('password');
      Mode:=LowerCase(Trim(GetEnvironmentVariable('REQUIRE_2FA')));
      if ((Method='') or (Method='password')) and (Password<>nil) and (Password.JSONType<>jtNull) and
        ((Mode='all') or ((Mode='admins') and IsAdmin)) then Exit;
      Factor:=Root.Find('twoFactorAuthentication');
      if (Factor=nil) or (Factor.JSONType=jtNull) then Exit(True);
      if not (Factor is TJSONObject) then Exit;
      Secret:=TJSONObject(Factor).Find('secret');
      if (Secret<>nil) and (Secret.JSONType<>jtString) then Exit;
      Kind:=TJSONObject(Factor).Find('type');
      Result:=Kind=nil; // setup is not an enabled factor; every declared type needs a challenge
    except Result:=False;end;
  finally Root.Free;end;
end;
end.
