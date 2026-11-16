# WeKan-Lite — REST API — v0.1

WeKan-Lite serves a subset of WeKan's REST API (the contract frozen in
[`public/api/wekan.yml`](../public/api/wekan.yml), OpenAPI 2.0), so WeKan's Python CLI
[`api.py`](https://github.com/wekan/wekan/blob/main/api.py) works against the FreePascal server
unchanged. Code: `wlapi.pas`.

## Auth (Bearer token)

Exactly as `api.py` does it:

```
POST /users/login        JSON {"username","password"}  -> {"id","token","tokenExpires"}
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

The current password-only route refuses active or malformed second-factor policies and
covered `REQUIRE_2FA` accounts until the challenge/enrollment flow is implemented. It
also follows WeKan's LDAP enable/fallback rules; a provider label alone does not block
an otherwise valid local password. Existing Welite tokens are rechecked against these
policies on use. See [shared account policy guards](ferret.md#shared-account-policy-guards).

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
| `GET /api/boards/:boardId/custom-fields/:customField` | `customfield` | `{"_id","name","type"}` |
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
