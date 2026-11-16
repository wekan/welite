# Global Admin and domain administrators

The reserved `admin` host uses the account and registry database in `data/admin/db/data.db`.
Only its authenticated administrators can use `/admin/domains`. A normal served domain's
first registered account is its Domain Global Admin: it administers that domain's People
and Designer, without access to the central registry or another domain's accounts.

## Initialize the reserved account

From Welite's runtime directory, with the same schema configuration used by the server:

```sh
export WELITE_ADMIN_PASSWORD='your chosen password'
./welite initadmin globaladmin
unset WELITE_ADMIN_PASSWORD
```

The command initializes the reserved account locally and exits. It refuses to replace
an initialized account. Public `/register` requests on the reserved host return 403.
Sign in through the `admin` host, or configure your reverse proxy to send `Host: admin`
for the hostname you dedicate to the Global Admin interface. An HTTP Host override is
also sufficient for local testing. The server serves plaintext HTTP behind your TLS proxy.

`WELITE_SCHEMA` selects the portable schema file (default `src/schema.sql`). `initadmin`
uses it to create the reserved tenant's account tables alongside the registry tables.

## Add a domain

On the reserved host, open `/admin/domains`, enter the domain and submit Add. Welite
registers it and provisions its own schema and file directories. Visit that domain and
register its first account to create its Domain Global Admin. Later accounts are Normal.
Disable/Enable controls affect routing immediately, including previously opened tenants.

Domain entries are canonical DNS names, never filesystem paths. `admin`, `local`,
`localhost` and the loopback address are reserved. Loopback requests use the independent
`local` tenant; its administrator cannot add or disable served domains.

Every panel operation uses a session in the URL/hidden fields and an action token.
Cookies and JavaScript are optional. Tokens issued by one tenant do not authorize another.

## Disable and re-enable an account

People's Disable login control changes the account flag and removes all of its durable
login tokens in one transaction. Disabled accounts cannot sign in through either interface,
and existing tokens are refused. Re-enabling permits a fresh login; previous tokens remain
revoked. Each web login gets a new nonce, so re-enable does not recreate an old session.

Web sessions bind to the tenant database, current user identity, credential hash and client
context. Their default idle limit is 1,800 seconds; `WELITE_SESSION_IDLE` overrides it with
a positive number of seconds. Idle expiry removes the durable token. Concurrent state-changing
submissions consume a form token once; downloads retain their read-only behavior.

Token digests use tenant-scoped SHA-256; action tokens use HMAC-SHA-256 with a server-only
session key. Supplemental `authmeta` records bind durable credentials to the tenant path
and current password hash. Digest upgrades and moving a database to another path require a
fresh sign-in. Existing weak token records are not accepted through a legacy fallback.

Forwarded IP headers are ignored unless the actual peer is in `WELITE_TRUSTED_PROXIES`, a
comma-separated list of exact IPv4/IPv6 proxy addresses. The chain is walked right-to-left
until the first untrusted hop. Configure only proxies under your control that append or
replace the real client address. CIDR ranges and hostnames are not proxy-list entries.

Portable entropy remains in TODO: the existing non-Unix random fallback is unfinished.
