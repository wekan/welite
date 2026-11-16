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
