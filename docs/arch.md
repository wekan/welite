# WeKan-Lite — FreePascal architecture — v0.1

Companion to `contract.md`, `../src/schema.sql`, `goals.md`, `webstack.md`,
`schema.md`. This doc distills the **two working FreePascal prototypes** into the
architecture WeKan-Lite should build on, and the reference units in the repo's `src/`
directory implement the load-bearing pieces.

Prototypes mined (read them — they are real, compiling code):
- **[`wami/wekan.pas`](https://github.com/wekan/wami/blob/main/wekan.pas)** — single-file WeKan web prototype: `fphttpapp` + `httproute`,
  port 5500, HTML 4.01 Transitional, server-side browser detection
  (IBrowse/NetSurf/Dillo/…), routes mirroring WeKan's `router.js`, CSV-file user store,
  static files via a `/*` route. Proves the routing + retro-HTML surface.
- **[`omi/public/server.pas`](https://github.com/wekan/omi/blob/main/public/server.pas)** — the mature one (~3800 lines): `fphttpapp` + `httproute`,
  HTML **3.2** + a server-side pretty-printer, a full **no-cookie / no-JS auth** scheme,
  i18n with fallback resolution, brute-force lockout, and **SQLite accessed by shelling out
  to the `sqlite3` CLI via `TProcess`**. Proves auth + persistence on retro targets.

Both prototypes independently chose **`fphttpapp` + `httproute`** — so that, not the lower
`fphttpserver` named in `webstack.md` Decision 1, is the concrete stack. (They are
the same server; `fphttpapp` is the thin `TCustomApplication` wrapper + `httproute` is the
dispatcher. The portability argument in Decision 1 holds unchanged: RTL-only, no C deps.)

---

## Request lifecycle

```
TCP :PORT
  └─ fphttpapp dispatch
       └─ httproute match  (HTTPRouter.RegisterRoute pattern → handler)
            └─ [1] tenant middleware   (wltenant.pas)
            │       Host: header → data/domains/<key>/  (or data/admin/, data/local/)
            │       → open that tenant's files/db/wekan.db  → TWLTenant.Db
            └─ [2] auth middleware     (wlauth.pas)
            │       sessionId (URL/hidden field) → user; verify action-token on POST
            └─ [3] endpoint handler
                    reads/writes TWLTenant.Db → renders HTML or returns JSON
```

Route handlers resolve the tenant and apply the authorization required for the endpoint.

### 1. Tenant resolution (G8) — `wltenant.pas`
The single most important addition over the prototypes (which are single-tenant). Normalize
the `Host` header, resolve its tenant key in the registry, and provide the
`files/db/wekan.db` handle and `files/` root. The Global Admin and local tenants
use reserved directories. Unknown hosts return HTTP 404.
See [runtime storage](runtime.md) for path layout and migration.

### 2. Auth (G4) — `wlauth.pas`
Lifted from [`omi/public/server.pas`](https://github.com/wekan/omi/blob/main/public/server.pas), which already solves "auth without cookies or JS":
- Web sessions travel with navigation and hidden form fields. State-changing
  forms use HMAC action tokens with replay protection, client binding and idle
  expiry.
- Web and API login verify Meteor bcrypt or Argon2 credentials and supported
  legacy PBKDF2 records. Native storage and the shared adapter bind tokens to the
  tenant and current credentials. See [REST authentication](api.md#auth-bearer-token).

### 3. Endpoints
Same shape as the prototypes' `procedure xEndpoint(aRequest: TRequest; aResponse: TResponse)`,
registered with `HTTPRouter.RegisterRoute`. They read/write the tenant DB through the
`wldb.pas` abstraction and render retro-safe HTML.

---

## HTML rendering — retro-first, two tiers

The prototypes bracket the compatibility range; WeKan-Lite should target the **lower** one
and treat richer output as enhancement:

| Tier | Source | Prototype browser coverage | Use |
|------|--------|-------------------|-----|
| **HTML 3.2, table layout, no CSS/JS** | omi `server.pas` (`PrettyHtml32`) | IBrowse+AmiSSL (Amiga), Dillo (FreeDOS), Elinks/w3m/Lynx (text) | **Baseline.** Every page must work here. |
| HTML 4.01 + minimal CSS, optional JS drag | wami `wekan.pas` | Chrome, NetSurf, Dillo desktop | Progressive enhancement for modern browsers. |

WeLite uses links for navigation and HTML POST forms for state changes. Optional
drag and touch controls use the same board move endpoint. The WeLite
[Chromium tests](../tests/README.md) cover the form baseline with JavaScript and
cookies disabled. Retro browser and hardware acceptance remains in [TODO.md](../TODO.md).

---

## Persistence — the one real fork

The default server links SQLite. A build with `-dWLDB_CLI` runs the external
`sqlite3` executable. Both backends use the `wldb.pas` interface, including
transactional writes. See [SQLite modes](sqlite.md) and the [FerretDB adapter](ferret.md).

---

## Server unit layout

| Unit | Role | Distilled from |
|------|------|----------------|
| `wlhttp.lpr` | program entry: config, route table, start `fphttpapp` | wami `begin…end.` + omi `LoadSettings` |
| `wltenant.pas` | `Host:` → tenant dir + `files/db/wekan.db` handle (G8) | **new** (prototypes are single-tenant) |
| `wlregist.pas` | domain registry over `data/admin/files/db/wekan.db` (G8) | **new** (Global Admin store) |
| `wlauth.pas` | no-cookie/no-JS sessions + action-tokens (G4) | omi session/token functions |
| `wldb.pas` | SQLite access behind one interface (CLI or linked) | omi `ExecSqlOnDb` + `sqlite3` unit |
| `wlhtml.pas` | retro-safe HTML helpers + HTML-3.2 pretty printer + dir wrapper | omi `PrettyHtml32`, `HtmlEncode`; wami layout |
| `wlbrowse.pas` | User-Agent → browser id (tune output per client) | wami `WebBrowserName` |
| `wldesign.pas` | **Designer** — data-driven pages, render, LTR/RTL, import/export | **new** (see `designer.md`) |
| `wlcolors.pas` | color palette + picker components + import-color mapping | **new** (see `theming.md`) |
| `wlvector.pas` | Red Strings / connectors: SVG / VML / ASCII per browser | **new** (see `theming.md`) |
| `wlenhanc.pas` | progressive enhancement: MultiDrag/touch hooks + scripts | **new** (see `enhance.md`) |
| `wlmove.pas` | combined no-JS arrows move component + `/board/move` | **new** (see `move.md`) |

## Building and testing

Run `bash build.sh` from the repository root and select the current platform
build or an installed cross target. The [cross-build record](cross.md) lists
toolchain and runtime checks by target. Use a TLS-terminating proxy when serving
a deployment over HTTPS. See [the test guide](../tests/README.md) for isolated
native, shared-storage and browser runs.
