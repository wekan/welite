"""Authentication error frame assertions shared by HTTP scenarios."""
from frames import Document

def check(result,tag,private=False):
    status,headers,body=result
    assert status in [403,429,500],status
    assert headers['Content-Type'].startswith('text/html')
    assert headers['Content-Language']==tag
    assert 'Accept-Language' in headers['Vary']
    doc=Document();doc.feed(body.decode())
    assert doc.html['lang']==tag
    assert (doc.html.get('dir')=='rtl')==(tag in ['ar','he'])
    assert (doc.body.get('dir')=='rtl')==(tag in ['ar','he'])
    assert 'Set-Cookie' not in headers
    assert b'test-password' not in body and b'otp-secret' not in body
    if status==429:assert headers['Retry-After']=='300'
    if private:
        assert headers['Cache-Control']=='no-store'
        assert headers['Referrer-Policy']=='no-referrer'
