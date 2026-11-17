"""Authenticated native profile and weighted-header direction over real HTTP."""
import json
import sqlite3
def check_language(request,database,session):
    route='/board?id=protected&view=all&sessionId='+session
    with sqlite3.connect(database) as con:
        original=con.execute("SELECT profile_json FROM users WHERE username='administrator'").fetchone()[0]
    def profile(value):
        with sqlite3.connect(database) as con:con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(json.dumps(value),))
    def page(query='',header=''):
        status,_,body=request('GET',route+query,extra_headers={'Accept-Language':header})
        assert status==200
        return body
    try:
        profile({'language':'ar','unrelated':{'keep':True}})
        assert b'dir="rtl"' in page(header='fi')
        assert b'dir="rtl"' not in page('&lang=fi',header='he')
        assert b'dir="rtl"' in page('&lang=unknown',header='fi')
        with sqlite3.connect(database) as con:
            assert json.loads(con.execute("SELECT profile_json FROM users WHERE username='administrator'").fetchone()[0])=={'language':'ar','unrelated':{'keep':True}}
        profile({})
        rtl=page(header='fi;q=0.1,he;q=0.8')
        ltr=page(header='he;q=0,fi;q=0.8')
        assert b'dir="rtl"' in rtl and b'dir="rtl"' not in ltr
        assert rtl.index(b'data-list="doing"')<rtl.index(b'data-list="todo"')
        assert ltr.index(b'data-list="todo"')<ltr.index(b'data-list="doing"')
        profile({'language':{'bad':'ar'}})
        assert b'dir="rtl"' not in page(header='fi')
        with sqlite3.connect(database) as con:con.execute("UPDATE users SET profile_json='{broken' WHERE username='administrator'")
        assert b'dir="rtl"' not in page(header='fi')
    finally:
        with sqlite3.connect(database) as con:con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(original,))
    print('PASS: actual HTTP explicit/profile/weighted-header language precedence, zero-quality exclusion, typed profile refusal, preserved profile data and structural RTL order')
