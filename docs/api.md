# WeKan-Lite — REST API — v0.1

WeKan-Lite implements a subset of WeKan's REST API in `src/wlapi.pas`. Use the
endpoint list below for the supported operations. The bundled OpenAPI file
describes the upstream API and includes routes outside this subset.

## Auth (Bearer token)

Exactly as `api.py` does it:

```
POST /users/login        JSON {"username","password","code"?}  -> {"id","token","tokenExpires"}
Authorization: Bearer <token>   on every /api/... request
```

Tokens are stored in `schema.sql` `login_tokens` (`hashedToken = TokenHash(tenantDb, token)`) — the same
table the no-cookie web sessions use. Multitenancy is by `Host:` header, so point `api.py`'s
`wekanurl` at the tenant's domain.

**Passwords** for new accounts use Meteor's `services.password.bcrypt` object:
bcrypt (cost 10, independent random salts) over the lowercase SHA256 plaintext digest.
The SQL `users.services_json` column stores `{"password":{"bcrypt":"$2b$10$..."}}`.
Registration and local `initadmin` bootstrap both create that format. Generate an object
for a seed record with:

```
./welite hashpw 'mypassword'      # prints {"bcrypt":"$2b$10$..."}
```

Store this output as the **object value** of `services.password`, without quoting the
whole output as a string. Existing `pbkdf2_sha1$iters$saltHex$dkHex` string credentials
still verify; login does not rewrite them. Accounts with malformed/no password credentials
cannot log in. Existing Argon2 v16/v19 d/i/id records also verify over the SHA256 plaintext
digest, including encoded associated data. Argon2 takes precedence over bcrypt; failures
never retry an older bcrypt value. Verification budgets are documented in
[the adapter notes](ferret.md#argon2-credential-verification). Versionless legacy records use v16; unknown versions are denied. Optional out-of-band secrets come from `WELITE_ARGON_SECRET_FILE`; configured-file
failures deny Argon2 login. See the adapter notes for private-file and token-binding policy. Shared Meteor resume-token work is in progress.

For an account with an active OTP factor, include a six-digit `code` string with the
password (JSON or form fields). Leading zeroes must be preserved. The plain `/sign-in`
form offers the same optional field without JavaScript or cookies. Missing, malformed,
wrong or previously consumed codes cannot issue a token. Token issuance and replay
consumption commit together; a failed issuance does not consume the code.

Both login routes reserve attempts before password verification: 5 per account, 30 per
socket peer and 300 per tenant in 300-second windows. Successful attempts count too.
Denied reservations return HTTP 429 and `Retry-After: 300`; counters persist across
restart and are shared across web/API routes. Forwarded headers cannot change the
admission peer. Proxied clients share the proxy socket's peer allowance.

Malformed/unknown factor policies and covered `REQUIRE_2FA` accounts without an active
factor are denied until enrollment is confirmed. LDAP enable/fallback policy
still applies. Tokens are bound to the current password and canonical active factor;
observed policy or credential changes revoke them. See [shared account policy guards](ferret.md#shared-account-policy-guards).

**Enroll one-time codes** through `/two-factor/setup` (plain HTML, no JavaScript or
cookies required). Confirm your password, copy the secret to a time-based authenticator
(SHA1, six digits, 30 seconds), then submit its code to `/two-factor/confirm`. Setup
expires after five minutes and is bound to the socket peer/user agent. Its bearer token
is carried in a hidden POST field, never an application token or navigation URL. Setup
pages send `Cache-Control: no-store` and `Referrer-Policy: no-referrer`.

Setup and confirmation share login attempt allowances. Confirmation uses the account
stored with the setup token, ignoring posted usernames for admission. A wrong/expired
code cannot enable the factor; an active factor cannot be replaced by a password alone.
After confirmation, wait for a new code and sign in normally: the activation code has
already been consumed. Registration under required-factor policy directs users to setup
without issuing an application session. New setup replaces an earlier pending token.

For a shared FerretDB store, new API credentials also create typed Meteor resume
records in the same transaction. Both local authorization metadata and the shared record
must remain valid. Removing the shared record logs that bearer out of WeLite as well;
older private-only shared-store API credentials need a fresh login. Previously unseen
Meteor-issued hashed or legacy raw bearers can be adopted with their original expiry
when shared ownership, account policy and source/settings snapshots are valid. Seen
local digests are never automatically re-adopted after deletion. Browser sessions
retain their private client-bound format. Stored `loginOptions.loginExpirationInDays`
wins over `ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS`; absent/zero means 90 days. Supported
lifetimes are positive decimal/scientific days through 36500, including fractions;
unsupported values deny issuance. Expiry uses the original milliseconds with Date
truncation after addition, so subsecond lifetimes are not rounded up. The response
returns the expiry committed to the local credential. Native-store defaults stay 90 days.
Shared Settings MFA, LDAP and password-login overrides take precedence over deployment
fallbacks; null/empty values use the fallback. Proofs bind to the settings snapshot, so a
configuration change requires fresh authentication. Disabled password registration
creates no account. See [paired shared API bearers](ferret.md#paired-shared-api-bearers)
for supported policy fields and remaining compatibility gates.

**Authorization** (`ApiAuthBoard`): board-scoped endpoints require the token's user to be an
active `board_members` row (writes blocked for `isReadOnly`); public boards are readable by
anyone; site admins (`users.isAdmin`) bypass. `/api/users` is admin-only; `/api/users/:id/boards`
is self-or-admin. Non-members get `403`.

## Implemented endpoints

| Method & path | api.py command | Response |
|---------------|----------------|----------|
| `POST /users/login` | (login) | `{"id","token","tokenExpires"}` |
| `GET /api/user` | `user` | `{"_id","username"}` |
| `GET /api/users` | `users` | `[{"_id","username"}]` |
| `GET /api/boards` | `boards` | public boards `[{"_id","title"}]` |
| `GET /api/users/:userId/boards` | `boards USERID` | that user's boards |
| `GET /api/boards/:boardId` | `board BOARDID` | `{"_id","title","slug","permission","color"}` |
| `PUT /api/boards/:boardId/title` | `editboardtitle` | `{"_id","title"}` |
| `POST /api/boards/:boardId/copy` | `copyboard` | `{"_id"}` (deep copy) |
| `PUT /api/boards/:boardId/labels` | `createlabel` | `{"_id"}` (nested `{label:{color,name}}`) |
| `GET /api/boards/:boardId/cards_count` | `get_board_cards_count` | `{"board_cards_count"}` |
| `GET /api/boards/:boardId/swimlanes` | `swimlanes BOARDID` | `[{"_id","title"}]` |
| `GET /api/boards/:boardId/swimlanes/:swimlaneId/cards` | `cardsbyswimlane` | `[{"_id","title"}]` |
| `GET /api/boards/:boardId/lists` | `lists BOARDID` | `[{"_id","title"}]` |
| `POST /api/boards/:boardId/lists` | `createlist` | `{"_id"}` |
| `GET /api/boards/:boardId/lists/:listId` | `list` | `{"_id","title"}` |
| `GET /api/boards/:boardId/lists/:listId/cards` | (list cards) | `[{"_id","title"}]` |
| `POST /api/boards/:boardId/lists/:listId/cards` | `addcard` | `{"_id"}` |
| `GET /api/boards/:boardId/lists/:listId/cards_count` | `get_list_cards_count` | `{"list_cards_count"}` |
| `GET /api/boards/:boardId/lists/:listId/cards/:cardId` | `getcard` | card object (incl. labelIds/members/assignees/customFields) |
| `PUT /api/boards/:boardId/lists/:listId/cards/:cardId` | `editcard` / `editcardcolor` / `addlabel` | updated card |
| `POST ./cards/:cardId/archive` | — | archive/unarchive card (`isArchive=false` unarchives) |
| `GET`/`POST /api/boards/:boardId/cards/:cardId/checklists` | `checklistid` / `addchecklist` | list / `{"_id"}` |
| `GET /api/boards/:boardId/cards/:cardId/checklists/:checklistId` | `checklistinfo` | checklist + items |
| `POST /api/boards/:boardId/cards/:cardId/checklists/:checklistId/items` | (addchecklist items) | `{"_id"}` |
| `GET`/`PUT`/`DELETE …/checklists/:checklistId/items/:item` | — | item (PUT toggles `isFinished`/title) |
| `GET`/`POST /api/boards/:boardId/cards/:cardId/comments` | — | list / `{"_id"}` |
| `GET`/`DELETE /api/boards/:boardId/cards/:cardId/comments/:commentId` | — | comment / `{"_id"}` |
| `POST /api/boards/:boardId/swimlanes` | (new swimlane) | `{"_id"}` |
| `DELETE /api/boards/:boardId` | (delete board) | `{"_id"}` (cascade) |
| `DELETE /api/boards/:boardId/swimlanes/:swimlaneId` | — | `{"_id"}` |
| `DELETE /api/boards/:boardId/lists/:listId` | — | `{"_id"}` (+ its cards) |
| `DELETE /api/boards/:boardId/lists/:listId/cards/:cardId` | — | `{"_id"}` (children cascade) |
| `POST`/`DELETE …/cards/:cardId/members/:member` | — | card (incl. `members`) |
| `POST`/`DELETE …/cards/:cardId/assignees/:assignee` | — | card (incl. `assignees`) |
| `GET`/`POST /api/boards/:boardId/custom-fields` | `customfields` / `addcustomfieldtoboard`¹ | list / `{"_id"}` |
| `GET /api/boards/:boardId/custom-fields/:customField` | `customfield` | definition metadata and settings |
| `PUT`/`DELETE /api/boards/:boardId/custom-fields/:customField` | definition update and delete | `{"_id"}` |
| `POST /api/boards/:boardId/custom-fields/:customField/dropdown-items` | append names from `items` | definition `{"_id"}` |
| `PUT`/`DELETE /api/boards/:boardId/custom-fields/:customField/dropdown-items/:dropdownItem` | rename or delete one option | option `{"_id"}` for rename, definition `{"_id"}` for delete |
| `POST …/cards/:cardId/customFields/:customField` | `editcustomfield` | `{"_id"}` (sets card value) |
| `POST /api/attachment/upload` | `uploadattachment` | `{"success","attachmentId","fileName","fileSize"}` (JSON+base64) |
| `GET /api/attachment/download/:attachmentId` | `downloadattachment` | `{"success","base64Data","fileName","fileSize"}` |
| `GET /api/attachment/info/:attachmentId` | `attachmentinfo` | metadata `{...}` |
| `DELETE /api/attachment/delete/:attachmentId` | `deleteattachment` | `{"success","attachmentId"}` |
| `GET /api/boards/:boardId/attachments` | `listattachments` | `[{"_id","name","cardId"}]` |
| `GET /api/attachment/list/:b/:s/:l/:cardId` | `listcardattachments` | `{"success","attachments":[...]}` |

¹ api.py's `addcustomfieldtoboard` used to crash on an empty `settings` arg (`json.loads('')`);
fixed in WeKan's api.py (empty → `{}`, sent as JSON). The server endpoint works either way.

Verified end-to-end against the real `api.py` on FPC 3.2.3: login → board/swimlanes/lists →
createlist → addcard → cardsbyswimlane → editcard/editcardcolor → counts → editboardtitle →
copyboard → createlabel → addchecklist/checklistid, with rows persisting to the tenant's
SQLite DB.

Definition PUT and DELETE require write access on every board bound to the
definition. Deletion removes its card values and related activity on those boards. Deleting a dropdown option keeps
existing card selections. New API cards initialize automatic and always-on
fields as null. Enabling always-on backfills missing values on existing cards.

## Notes & TODO

- Routes use httproute `:param` patterns; handlers read `aRequest.RouteParams['boardId']` etc.
- `wekan.yml` is itself served (statically, from `public/api/`) at `/api/wekan.yml`.
- Bodies are accepted as JSON **or** form-encoded (`BodyField` tries both), matching `api.py`'s
  mix of `json=` (login) and `data=` (other calls).
- The card object includes `labelIds`, `members`, `assignees`, and `customFields` (`[{_id,value}]`).
- **Attachments**: metadata in `schema.sql` `attachments`; bytes on disk in
  `data/domains/<domain>/files/attachments/<id>` (`storageBackend: filesystem`). Upload/download
  carry the file as base64 in JSON, matching api.py's `/api/attachment/*` surface.
- Still TODO (remaining `wekan.yml` endpoints): rules/webhooks, org/teams, settings,
  import/export, label edit/delete, card move, attachment
  copy/move + board backgrounds + S3/MinIO storage backend. Real password hashing and per-board
  authorization are done.

## Relation IDs and authors

Card creation and card edits accept `labelIds`, `members`, and `assignees` as JSON arrays
or comma-separated strings. Explicit `[]` or an empty string clears the given relation;
omitting a field preserves it. Duplicate IDs are stored once. All collections validate
before the card and its relations commit in one transaction.

Labels belong to the route board. Member/assignee targets must be enabled users with
active membership on that board; the path-based add endpoints use the same rule. Removal
can clean up a user whose membership is no longer active.

An omitted `authorId` means the acting user. Ordinary editors may specify themselves.
Tenant administrators may attribute a card/comment to another enabled active member of
that same board, supporting controlled imports. Invalid attribution is rejected before
creation. Malformed JSON and invalid relation collections return 400; forbidden author
attribution returns 403; database write failures return 500 with no partial card change.

## Durable token binding

API login credentials use a tenant-scoped SHA-256 lookup and supplemental `authmeta`
credential binding. They survive a server restart at the same database path. A copied
or relocated database requires a fresh login, and a detected password-hash change revokes
the old token. Disabling a user revokes credentials as described in `admin.md`.

A web session ID used with an API route retains its client, idle and in-memory session
checks. Dedicated API credentials are issued by `/users/login`. Earlier weak digests have
no compatibility acceptance path. See `tests/crypto.py` for independent digest/MAC vectors,
process-restart persistence and copied-database/credential-revocation checks.

### Integrations

Board administrators can create an outgoing integration with
`POST /api/boards/:boardId/integrations` and a JSON `url`. The response contains
`_id`. Use `PUT /api/boards/:boardId/integrations/:intId` to edit the destination,
title, enabled flag or activity list. On Linux and Windows, destination writes require an
HTTP(S) URL whose resolved IPv4 and IPv6 addresses are public. Integration
delivery requires its own address check and connection pinning.

Both native and shared SQLite support integration reads and writes. Native
stores add the integrations table when opened and remove a board’s
integrations when the board is deleted.

Board administrators can open **Outgoing Webhooks** from the board. The HTML
page shows current integration metadata and reflects REST edits on reload.
It uses the board’s browser session and omits integration credentials.

The same page has HTML forms to create, edit and delete webhooks. The forms
use one-use action tokens scoped to the board and integration, and successful
submissions redirect back to the settings page.

Site administrators can post to `/api/createtoken/:userId` with a nonblank
`reason`. A successful response contains `_id` and the new `authToken`. The
target must be active and eligible under WeLite's account policy. Issuance and
the impersonation audit record commit together. The audit contains the actor,
target, timestamp and up to 500 characters of the reason.

Site administrators can post `userId` to `/api/deletetoken` to revoke all of
that user's login sessions. To revoke one shared Meteor bearer, also supply
its stored SHA-256 base64 digest in `token`. An unknown digest or a raw bearer
leaves sessions unchanged. A missing target account returns JSON 404.


## Card dependencies

Read dependency lines with `GET /api/boards/:boardId/dependencies`. Read or
add a card's dependencies at `/api/boards/:boardId/cards/:cardId/dependencies`.
POST takes a target `cardId` and optional `type`, `color` and `icon`. Reposting
the same source and target updates the existing entry. Append `/:targetId` for
PUT or DELETE. Writes check board and card scope within the transaction.


## Board domains

Site administrators can read `GET /api/boards/:boardId/domains`. A caller
with board access also receives the domain list with the board response.
Board and site administrators can POST a `domain` to the same path or
DELETE `/api/boards/:boardId/domains/:domain`. Names are trimmed and lowercased.
Deletion returns the remaining domains or JSON 404 for a missing entry.
