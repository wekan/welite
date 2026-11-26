"""Language-only state through required enrollment and registration."""
from signin import form_to, signed_in
import re
import json
import html
from pathlib import Path
from urllib.parse import parse_qs,urlsplit
def check_auth_language(request,database,otp):
    words=json.loads((Path(__file__).resolve().parents[1]/'i18n/data/ar.jsn').read_text())
    def translated(key):return html.escape(words[key],quote=True).replace('&#x27;',"'").encode()
    catalog_dir=Path(__file__).resolve().parents[1]/'i18n'/'data'
    for regional in ('ar','ar-DZ','ar-EG','ary'):
        captions=json.loads((catalog_dir/f'{regional}.jsn').read_text())
        for key in ('register','password-again','password-mismatch','create-account','otp'):
            assert re.search(r'[؀-ۿ]',captions[key]),(regional,key)
        status,headers,body=request('POST','/register?lang='+regional,
            dict(username='invalid-confirmation',password='first',confirm='second'))
        assert status==200 and headers['Content-Language']==regional and 'Set-Cookie' not in headers
        assert b'dir="rtl"' in body
        for key in ('register','password-again','password-mismatch'):
            assert captions[key].encode() in body,(regional,key)
        status,headers,body=request('GET','/sign-in?lang='+regional)
        assert status==200 and headers['Content-Language']==regional and 'Set-Cookie' not in headers
        for key in ('create-account','otp'):
            assert captions[key].encode() in body,(regional,key)
    language='ar';user='language-user';password='language-test-password'
    status,headers,body=request('GET','/sign-in?lang='+language)
    assert status==200 and headers['Content-Language']==language and 'Set-Cookie' not in headers
    assert form_to(body,'/two-factor/setup','ar',translated('two-factor-required-title'))
    status,headers,body=request('GET','/register?lang='+language)
    assert status==200 and headers['Content-Language']==language and b'dir="rtl"' in body
    # The form is WeKan's /sign-up page (src/wlroutes.pas); it posts to /register.
    assert form_to(body,'/register','ar') and form_to(body,'/sign-in','ar')
    status,headers,body=request('POST','/register?lang='+language,dict(username=user,password=password,confirm=password))
    assert status==200 and b'<h1>'+translated('enrollment-account-created')+b'</h1>' in body and form_to(body,'/two-factor/setup','ar')
    assert translated('two-factor-required-text') in body
    assert form_to(body,'/two-factor/setup','ar',translated('two-factor-required-title'))
    status,headers,body=request('GET','/two-factor/setup?lang='+language)
    assert status==200 and form_to(body,'/two-factor/setup','ar')
    assert b'<h1>'+translated('two-factor-required-title')+b'</h1>' in body
    for key in ('username','password'):
        field=('enrol-'+key).encode()
        assert b'<label for="'+field+b'">'+translated(key)+b'</label>' in body
        assert b'<input id="'+field+b'"' in body
    assert headers['Cache-Control']=='no-store' and headers['Referrer-Policy']=='no-referrer'
    status,headers,body=request('POST','/two-factor/setup?lang='+language,dict(username=user,password='wrong-private-password'))
    assert status==200 and form_to(body,'/two-factor/setup','ar') and b'wrong-private-password' not in body
    assert form_to(body,'/two-factor/setup','ar',translated('two-factor-required-title'))
    status,headers,body=request('POST','/two-factor/setup?lang='+language,dict(username=user,password=password))
    assert status==200 and headers['Content-Language']==language and 'Location' not in headers and 'Set-Cookie' not in headers
    assert form_to(body,'/two-factor/confirm','ar')
    assert b'<label for="enrol-code">'+translated('otp')+b'</label>' in body
    assert b'<input id="enrol-code" name="code"' in body and translated('confirm') in body
    assert translated('twoFactorAuth-manual-entry') in body
    assert translated('username')+b': '+user.encode() in body
    assert translated('twoFactorCode-prompt') in body
    secret=re.search(rb'<code id="otp-secret">([A-Z2-7]{32})</code>',body).group(1).decode()
    token=re.search(rb'name="setupToken" value="([a-f0-9]{64})"',body).group(1).decode()
    status,headers,body=request('POST','/two-factor/confirm?lang='+language,dict(setupToken=token,code='bad'))
    assert status==200 and form_to(body,'/two-factor/confirm','ar') and form_to(body,'/two-factor/setup','ar')
    assert translated('twoFactorCode-invalid') in body
    assert form_to(body,'/two-factor/setup','ar',translated('two-factor-required-title'))
    assert b'<h1>'+translated('twoFactorCode-prompt')+b'</h1>' in body
    import time
    counter=int(time.time())//30
    status,headers,body=request('POST','/two-factor/confirm?lang='+language,dict(setupToken=token,code=otp(secret,counter)))
    assert status==200 and translated('twoFactorAuth-enabled') in body and form_to(body,'/sign-in','ar')
    assert headers['Cache-Control']=='no-store' and headers['Referrer-Policy']=='no-referrer'
    status,headers,body=request('POST','/sign-in?lang='+language,dict(username=user,password=password,code=otp(secret,counter+1)))
    # The signed-in home page, in the posted language, carries the session in
    # its forms and never the setup token, secret or password (fd5f992).
    assert signed_in((status,headers,body)) and 'Location' not in headers
    assert headers['Content-Language']==language and b'name="lang" value="'+language.encode()+b'"' in body
    assert token.encode() not in body and secret.encode() not in body and password.encode() not in body
    # Unsupported input cannot become a retry URL or response header.
    status,headers,body=request('GET','/register?lang=..%2Fbad')
    assert status==200 and headers['Content-Language']=='en' and form_to(body,'/register')
    print('PASS: registration/setup/confirmation/retry/sign-in language continuity, safe state-only URLs, existing no-store/no-referrer controls and unsupported-language refusal')
