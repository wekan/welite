"""Shared-account password-only policy; malformed and unsupported modes fail closed."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wlpolicy-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    built=subprocess.run([os.environ.get('FPC','fpc'),'-Cr','-Co','-B','-Fu'+str(root/'src'),'-FU'+str(tmp),'-FE'+str(tmp),str(root/'tests/policy.lpr')],capture_output=True,text=True)
    assert built.returncode==0,built.stdout+built.stderr
    base=dict(os.environ)
    for variable in ['REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN']:base.pop(variable,None)
    def allowed(method,services,admin=False,**flags):return subprocess.check_output([str(tmp/'policy'),method,'1' if admin else '0'],input=services+'\n',env=dict(base,**flags),text=True).strip()=='yes'
    for method in ['', 'password']:
        for services in [{},dict(password=dict(bcrypt='fixture')),dict(twoFactorAuthentication=None),dict(twoFactorAuthentication={}),dict(twoFactorAuthentication=dict(secret='pending'))]:
            assert allowed(method,json.dumps(services)),(method,services)
        for factor in [False,True,'otp',[],dict(type='otp',secret='enabled'),dict(type='otp'),dict(type='other',secret='enabled'),dict(type=None),dict(type=''),dict(secret=123)]:
            assert not allowed(method,json.dumps(dict(twoFactorAuthentication=factor))),factor
        for malformed in ['', 'null','[]','{"twoFactorAuthentication":null,"twoFactorAuthentication":null}','{"twoFactorAuthentication":']:
            assert not allowed(method,malformed),malformed
    for method in ['ldap','oauth2','saml','passwordless','unknown']:
        assert allowed(method,'{}'),method
    assert not allowed('ldap','{}',LDAP_ENABLE='true')
    assert allowed('ldap','{}',LDAP_ENABLE='true',LDAP_LOGIN_FALLBACK='true')
    assert allowed('ldap','{}',LDAP_ENABLE='true',LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN='true')
    assert allowed('oauth2','{}',LDAP_ENABLE='true')
    for mode,admin,expected in [('off',True,True),('all',False,False),('admins',False,True),('admins',True,False),('invalid',True,True),(' ADMINS ',True,False)]:
        assert allowed('password','{"password":"hash"}',admin,REQUIRE_2FA=mode)==expected
    assert allowed('oauth2','{"password":"hash"}',True,REQUIRE_2FA='all')
    print('PASS: checked shared-account password-only policy, pending setup, enabled/unknown factors, malformed metadata and required-factor and LDAP fallback rules')
