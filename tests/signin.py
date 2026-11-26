"""The session a sign-in or a registration answers with.

Both answer with the signed-in home page, which carries the session in its
forms (fd5f992), instead of a redirect with it in the Location URL."""
import re

def session_of(body):
    if isinstance(body, str): body = body.encode()
    found = re.search(rb'name="sessionId" value="([0-9a-f]{64})"', body)
    assert found, body[:400]
    return found.group(1).decode()

def signed_in(response):
    """The session of a successful sign-in or registration response."""
    status, headers, body = response
    assert status == 200 and 'Location' not in headers, (status, headers, body[:400])
    return session_of(body)

def form_to(body, path, lang=None, caption=None):
    """Whether the page has a form posting to path that carries the language
    in its hidden lang field (and, given one, the caption on its button) -
    how the sign-in pages carry the language since they post it (fd5f992)
    rather than putting ?lang= in the URL."""
    if isinstance(body, bytes): body = body.decode()
    if isinstance(caption, bytes): caption = caption.decode()
    for form in re.findall(r'<form method="POST" action="' + re.escape(path) + r'">(.*?)</form>', body, re.S):
        if lang is not None and ('<input type="hidden" name="lang" value="' + lang + '">') not in form:
            continue
        if caption is not None and ('value="' + caption + '"') not in form and ('>' + caption + '<') not in form:
            continue
        return True
    return False
