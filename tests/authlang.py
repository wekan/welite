"""Language-only state through required enrollment and registration."""
import re
import json
import html
from pathlib import Path
from urllib.parse import parse_qs,urlsplit
def check_auth_language(request,database,otp):
    words=json.loads((Path(__file__).resolve().parents[1]/'i18n/data/ar.jsn').read_text())
    def translated(key):return html.escape(words[key],quote=True).replace('&#x27;',"'").encode()
    language='ar';user='language-user';password='language-test-password'
    status,headers,body=request('GET','/register?lang='+language)
    assert status==200 and headers['Content-Language']==language and b'dir="rtl"' in body
    assert b'action="/register?lang=ar"' in body and b'href="/sign-in?lang=ar"' in body
    status,headers,body=request('POST','/register?lang='+language,dict(username=user,password=password,confirm=password))
    assert status==200 and b'Account created' in body and b'href="/two-factor/setup?lang=ar"' in body
    status,headers,body=request('GET','/two-factor/setup?lang='+language)
    assert status==200 and b'action="/two-factor/setup?lang=ar"' in body
    for key in ('username','password'):
        field=('enrol-'+key).encode()
        assert b'<label for="'+field+b'">'+translated(key)+b'</label>' in body
        assert b'<input id="'+field+b'"' in body
    assert headers['Cache-Control']=='no-store' and headers['Referrer-Policy']=='no-referrer'
    status,headers,body=request('POST','/two-factor/setup?lang='+language,dict(username=user,password='wrong-private-password'))
    assert status==200 and b'href="/two-factor/setup?lang=ar"' in body and b'wrong-private-password' not in body
    status,headers,body=request('POST','/two-factor/setup?lang='+language,dict(username=user,password=password))
    assert status==200 and headers['Content-Language']==language and 'Location' not in headers and 'Set-Cookie' not in headers
    assert b'action="/two-factor/confirm?lang=ar"' in body
    assert b'<label for="enrol-code">'+translated('otp')+b'</label>' in body
    assert b'<input id="enrol-code" name="code"' in body and translated('confirm') in body
    assert translated('twoFactorAuth-manual-entry') in body
    assert translated('twoFactorCode-prompt') in body
    secret=re.search(rb'<code id="otp-secret">([A-Z2-7]{32})</code>',body).group(1).decode()
    token=re.search(rb'name="setupToken" value="([a-f0-9]{64})"',body).group(1).decode()
    status,headers,body=request('POST','/two-factor/confirm?lang='+language,dict(setupToken=token,code='bad'))
    assert status==200 and b'action="/two-factor/confirm?lang=ar"' in body and b'href="/two-factor/setup?lang=ar"' in body
    assert translated('twoFactorCode-invalid') in body
    import time
    counter=int(time.time())//30
    status,headers,body=request('POST','/two-factor/confirm?lang='+language,dict(setupToken=token,code=otp(secret,counter)))
    assert status==200 and translated('twoFactorAuth-enabled') in body and b'href="/sign-in?lang=ar"' in body
    assert headers['Cache-Control']=='no-store' and headers['Referrer-Policy']=='no-referrer'
    status,headers,body=request('POST','/sign-in?lang='+language,dict(username=user,password=password,code=otp(secret,counter+1)))
    assert status==302
    params=parse_qs(urlsplit(headers['Location']).query)
    assert set(params)=={'sessionId','lang'} and params['lang']==[language]
    assert token not in headers['Location'] and secret not in headers['Location'] and user not in headers['Location'] and password not in headers['Location']
    # Unsupported input cannot become a retry URL or response header.
    status,headers,body=request('GET','/register?lang=..%2Fbad')
    assert status==200 and headers['Content-Language']=='en' and b'action="/register"' in body
    print('PASS: registration/setup/confirmation/retry/sign-in language continuity, safe state-only URLs, existing no-store/no-referrer controls and unsupported-language refusal')
