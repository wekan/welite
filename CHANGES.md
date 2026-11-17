# ChangeLog

WeKan-Lite — the FreePascal reimplementation of WeKan: one native binary, SQLite-only, no-JS /
no-cookie capable, runs where Meteor cannot (Amiga 68k/PPC, MorphOS, AROS, Haiku, BSD, …).
Distilled from the [`wami/`](https://github.com/wekan/wami) and [`omi/`](https://github.com/wekan/omi) prototypes against the portable contract in `docs/`.

## 2026-11-17 Verify linked amd64 SQLite runtime

- Add optional linked SQLite coverage to the isolated amd64 cross-build check;
  disk/embedded CLI and linked variants all produce verified x86-64 executables.
- Run the directory-free embedded linked server under QEMU with verified Debian
  amd64 SQLite 3.46.1 libraries. The application and database engine execute as
  target code; bootstrap/refusal, registration, Designer, locale/resource bytes,
  translated/RTL pages, SQL privacy and clean shutdown all pass.
- Document target-only library paths and package versions. Physical hardware,
  foreign CLI deployment and other operating systems remain open in TODO.

## 2026-11-17 Verify emulated amd64 embedded HTTP runtime

- Add optional argument-safe executable runner and backend selection to the
  copied-executable embedded HTTP suite, retaining native linked/CLI defaults.
- Run the x86-64 embedded CLI server under private QEMU with target libc/libgcc.
  Admin/tenant/Designer bootstrap, missing override refusal, exact resource bytes,
  translated auth/RTL page, private SQL URLs and clean shutdown pass. Native
  linked and CLI suites also pass with the optional runner unset.
- Record that SQLite child processes are native host commands; target-native
  SQLite, linked amd64 SQLite, physical hardware and other platforms remain open.

## 2026-11-17 Verify current Linux amd64 cross-builds

- Build isolated x86-64 GNU binutils, FPC compiler/units and a verified Debian
  target libc sysroot without modifying host libraries. Resolve aarch64-host
  80-bit constant compilation and absolute target linker-script paths.
- Compile the current disk and full embedded CLI servers and verify executable
  ELF64/little-endian/x86-64 headers. Add a reproducible temporary build check;
  both variants pass, including generated public/locale/private SQL resources.
- Document exact compiler revision and build flags. Distinguish the historical
  June matrix from current verification; foreign runtime and other targets remain open.

## 2026-11-17 Embed private database bootstrap SQL

- Bundle tenant/Designer SQL separately from the public asset URL index and register
  a private seed lookup. Fresh embedded binaries no longer require schema files or
  source directories to initialize administrators, tenants and Designer tables.
- Add bounded SQL selection with explicit file precedence, embedded defaults and
  ordered disk candidates. Reject missing/empty/NUL/oversize overrides and invalid
  callbacks without silent fallback; accept UTF-8/BOM input. Disk Designer lookup
  also supports its SQL file beside the executable.
- Reproduce missing-schema initialization failure, then build linked/CLI executables
  and copy only each executable into an empty run directory. Verify admin/registration/
  Designer/page workflows, exact static/catalog/locale bytes, translated forms,
  non-public SQL URLs, explicit missing-file refusal and clean shutdown.
- Private selection, UTF-8 override, SQL-only bundle and full resource checks pass;
  both disk-mode HTTP suites retain compatibility. Update deployment docs/TODO;
  supported cross-target builds and runtime acceptance remain open.

## 2026-11-17 Skip missing aliases in embedded assets

- Skip dangling aliases and non-files when indexing embedded asset trees, matching
  disk availability while retaining valid file aliases. Reproduce the previous
  full resource build failure on missing regional locale links.
- Add a native resource/lookup regression for exact UTF-8, binary and valid-alias
  bytes with no disk asset fallback, and compile the full current public/i18n bundle.
  Require every installed catalog file in the index; all checks pass.
- Fresh directory-free HTTP/schema bootstrap and cross-target acceptance remain
  separate unfinished steps in the embedded-build checklist.

## 2026-11-17 Add Bosnian language asset

- Add the missing portable Bosnian asset in local English key order, retaining
  2,089 maintained source values. Fill the English byte unit and nine compatibility
  phrases using existing native terminology, plus two literal title templates.
- Register the native Bosanski identity: 154 language identities are installed and
  91 source entries still need assets. Add native vocabulary/legacy/unit/order and
  exact argument-inventory regressions.
- Catalog, token audit, all-identity negotiation and UTF-8 readers pass. All installed
  authentication forms pass linked/CLI HTTP checks; final byte-unit and reader checks
  also pass. The overall contextual token audit remains at 1,143 differences.

## 2026-11-17 Repair Traditional Chinese attachment activity

- Restore canonical attachment/card/list/board arguments in Hong Kong, Traditional
  and Taiwan attachment-deletion templates, using each locale's existing native
  noun labels as the reference. Replace their English swimlane fragment with the
  existing Chinese term, retaining all correct Chinese prose and other values/order.
- Record the three keys and add native-vocabulary/wrong-language-fragment regressions
  alongside exact English argument inventories. Token, French and
  installed-language UTF-8 reader checks pass.
- The audit now leaves 1,143 contextual differences. Other language quality/assets
  and untranslated application text remain open.

## 2026-11-17 Repair contextual French argument templates

- Close the French custom-field value argument and repair two stale search-code
  examples to the English source's literal `user:` and `has:-due` syntax. Compare
  against the previous commit: exactly three reviewed code-span substitutions,
  with all surrounding French prose, other values and key order unchanged.
- Record repaired keys and verify every base French argument inventory in addition
  to regional French checks. Token, Acehnese/Bulgarian and all-language UTF-8 reader
  regressions pass; no translation service is used.
- The overall audit leaves 1,146 contextual differences. Other language assets,
  wrong/mixed-language review and remaining UI message translation stay open.

## 2026-11-17 Keep viewer metadata on Designer transfer errors

- Route missing-page export and page/archive import token failures through the
  existing authenticated Designer error frame. Retain status/messages and keep
  failures HTML without attachment disposition.
- Add Arabic profile/Finnish override checks for those 403/404 paths and require HTML
  metadata/no download headers across the negative frame matrix. Full linked HTTP/
  no-JavaScript/no-cookie browser and CLI HTTP suites pass; successful JSON/ZIP
  downloads and filenames remain covered by existing transfer regressions.
- Remaining localization work is translation data/messages, broader error coverage
  and physical controls/responsive/retro acceptance; the known bare UI error bodies
  in these handlers are now framed.

## 2026-11-17 Keep viewer metadata on Admin operation errors

- Render domain/account validation, bad-token and storage failures with explicit
  authenticated request context and escaped prose through the shared viewer frame.
  Preserve existing statuses and transaction behavior.
- Verify Arabic/Finnish domain token/host/action failures and forced registry insert
  failure. Force account disable failure, checking unchanged flags and member access
  after rolled-back token revocation. Both backends pass complete Admin HTTP suites.
- Live maintained FerretDB/HTTP checks also pass on linked/CLI backends, including
  Mongo profile changes, BSON preservation, private web sessions, restart and shared
  revocation. Three early Designer import/export responses remain for the next step.

## 2026-11-17 Mirror data-table toolbar and pagination

- Mirror search/pagination cells structurally, retaining logical leading/trailing
  placement when table direction is ignored. Reverse physical previous/next order
  and arrow captions in RTL while isolating their glyph direction; keep logical
  page-number deltas and existing query/session/locale state.
- Reproduce missing RTL toolbar source order, then verify both directions in HTTP
  and no-JavaScript/no-cookie Chromium, including ignored-dir geometry and actual
  next/previous navigation. CLI also checks filtered pagination with one selected
  column, search text and locale intact; full linked/CLI browser suites pass.
- Reconcile the language TODO status so completed controls/errors no longer appear
  as stale remaining steps. Other messages/error routes and actual responsive/retro
  acceptance remain open.

## 2026-11-17 Mirror Designer data-table columns structurally

- Emit visible RTL headers/cells in reverse logical order with explicit LTR table
  flow and native cell text direction. Preserve original row-field indices and
  editable URL bindings; LTR and selected-column behavior remain consistent.
- Reproduce the missing RTL source reversal in HTTP, then verify source order,
  selected columns and locale-preserving edit links on both SQLite backends.
  No-JavaScript/no-cookie Chromium checks header/cell geometry, column selection
  and structural order when table direction is overridden to simulate ignored dir.
- Full linked HTTP/browser and CLI HTTP suites pass. Toolbar/pagination and real
  retro-platform acceptance remain part of the broader UI audit.

## 2026-11-17 Isolate Designer movement arrow captions

- Give Designer movement inputs explicit LTR text direction so physical ASCII
  left/right arrow captions cannot inherit RTL glyph mirroring. Keep surrounding
  page/widget labels in their existing direction and retain movement semantics.
- Reproduce inherited RTL with a computed-style browser assertion, then verify
  both captions use LTR alongside actual physical movement checks. The complete
  linked HTTP/no-JavaScript/no-cookie Chromium suite passes after the fix.
- Broader table/control and retro-platform acceptance remains open.

## 2026-11-17 Honor published board widget direction

- Pass resolved page direction/origin URL into data-view callbacks and render board
  widgets with that direction. Include widget identity and return to the originating
  page with locale/session intact after actions.
- Re-read the widget's enabled accessible page and matching board binding before
  interpreting physical moves. Reject missing/disabled/rebound contexts rather than
  trusting a posted direction flag; retain direct-board viewer-language behavior.
- Verify fixed RTL/LTR and automatic page directions, reversible physical card moves,
  source ordering and origin redirects. Negative HTTP cases preserve card data;
  a board writer cannot borrow an admin-only page's saved override.
- Full linked/CLI HTTP and no-JavaScript/no-cookie Chromium suites pass. CLI also
  verifies the added page-role rejection and intermediate browser move assertions.
  Wider UI/translation/retro acceptance remains open.

## 2026-11-17 Keep viewer metadata on authentication errors

- Add an escaped public authentication error frame for sign-in rate/session failures,
  enrollment admission/start failures, reserved-admin registration denial and failed
  post-registration session issuance. Resolve request/header language without a
  profile lookup, retaining existing status/messages and preset response headers.
- Verify sign-in/setup/confirmation 429 metadata with Retry-After, reserved registration
  denial and no cookies/credentials. Force enrollment storage failure to verify 500,
  no-store/no-referrer, no setup secret and unchanged account/pending state.
- Enrollment scenarios pass on linked/CLI backends; full Admin HTTP suites also pass
  on both. Translating the remaining authentication instructions/messages stays open.

## 2026-11-17 Keep viewer metadata on early board move errors

- Render missing-session, forbidden-selection, bad-token and invalid-drop failures
  through a shared local error frame with existing status/messages and escaped prose.
  Clear failed session identity before resolving public language; valid failures use
  their authenticated tenant-bound profile and validated request overrides.
- Add Arabic/Finnish rejection cases, invalid-session header fallback and signed
  invalid-drop checks, retaining card title/list/swimlane. Linked HTTP and the full
  CLI HTTP/no-JavaScript/no-cookie browser suites pass, including RTL card/list and
  Designer movement, uploads, clones and selection/drag regressions.
- Authentication/enrollment errors and translated messages remain open.

## 2026-11-17 Keep language metadata on UI not-found frames

- Render unknown-domain UI failures using validated query/posted/header language
  without a tenant/profile context. Render missing/inaccessible boards and known
  tenant route misses through the normal viewer frame. Preserve generic 404 text.
- Add a UI GET/POST matrix for Arabic/Finnish overrides and Hebrew header fallback,
  verify unknown hosts create no registry entry and inaccessible boards disclose no
  private content. Retain the API tenant error's separate JSON response format.
- Linked and CLI HTTP suites pass; CLI also covers additional authenticated
  profile-based board/route misses. Other mutation/authentication errors and
  translated messages remain open.

## 2026-11-17 Retain viewer metadata on selection errors

- Pass authenticated tenant/session/request context into the board selection error
  renderer and use the shared viewer frame for empty/invalid selections, failed
  saves, deletes, clones and attachment exports. Keep escaped prose and failure status.
- Add Arabic/Finnish invalid-action HTTP cases that assert Content-Language/Vary,
  HTML/body direction and unchanged card title/list/swimlane. Full linked and CLI
  HTTP suites pass, including existing mutation/rollback/authorization regressions.
- Other early route errors and translated error text remain open.

## 2026-11-17 Retain viewer metadata on administrator denial

- Render tenant-administrator and reserved Global Admin 403 pages through the shared
  viewer frame, using the denied authenticated account's tenant-bound profile and
  validated query/posted language. Keep existing role/host restrictions and statuses.
- Add supported GET/POST denial checks across Admin and Designer with separate
  Arabic/Hebrew accounts, Finnish overrides and invalid-choice profile fallback.
  Verify matching language/header/direction metadata and unchanged profile values.
- Full linked and CLI HTTP suites pass. Unknown-domain, other early errors and
  translated denial prose remain part of the remaining localization work.

## 2026-11-17 Keep viewer metadata on Designer errors

- Pass request, database and authenticated session explicitly into Designer error
  rendering. Use the shared viewer frame for validation, missing objects, bad action
  tokens and schema failures, including the missing-page editor response.
- Retain escaped error prose and existing status/authorization behavior while adding
  matching Content-Language/Vary and HTML/body language/direction metadata.
- Add real HTTP 400/403/404 checks for query/posted language, invalid-choice profile
  fallback and unchanged profile data. Full linked and CLI HTTP suites pass.
- Earlier tenant/authentication gates, other error routes and translated error prose
  remain open; this completes only authenticated Designer frame metadata.

## 2026-11-17 Restore Japanese Japan language asset

- Replace the broken Japanese Japan symlink with a physical portable locale,
  retaining 2,090 maintained regional source values and seven existing Japanese
  compatibility phrases. Translate the legacy membership restriction and zoom hint;
  preserve the two literal activity title templates and English key order.
- Add physical-file, catalog, native-script/vocabulary, compatibility-prose and
  exact argument-inventory regressions. Catalog/token/negotiation/UTF-8 readers and
  all 153 installed-identity authentication forms pass on linked and CLI backends.
- 92 source entries still need assets; 1,149 existing contextual token differences
  and wider translation quality/application UI work remain open.

## 2026-11-17 Register Portuguese Portugal source alias

- Map the hyphenated Portugal source loader to the protected existing `pt_PT.jsn`
  file, sharing it with the underscore source alias. Preserve both exact identities
  and native names without copying or overwriting translation data.
- Regenerate matching catalogs with 152 installed identities and 93 source entries
  still lacking local assets. Require both Portugal aliases to share the expected
  portable filename in regression coverage.
- Catalog, negotiation, UTF-8 readers and every installed-identity authentication
  form pass with linked and CLI SQLite backends. Translation quality remains open.

## 2026-11-17 Restore Colombian Spanish language asset

- Replace the broken Colombian Spanish symlink with a physical portable asset,
  retaining all 2,090 maintained regional source values. Supply the eleven legacy
  keys from three existing Spanish phrases, six direct translations and two
  code-only title templates, in local English key order.
- Add physical-file/catalog/vocabulary/legacy-prose and exact token-inventory
  regressions. Catalog, token audit, negotiation and UTF-8 reader tests pass;
  authentication forms render for all 151 installed languages on both backends.
- 94 source languages still need assets, and the existing token audit remains at
  1,149 contextual differences. Translation quality review remains open.

## 2026-11-17 Restore French regional language assets

- Replace broken French Belgium/Canada symlinks with physical portable locale
  files and register both source identities. Reuse 2,090 maintained regional values,
  eight existing French compatibility phrases and two literal title templates;
  translate the removed board-members restriction into French.
- Preserve local English key order and exact argument inventories across all
  2,101 keys per locale. Add physical-file, catalog, vocabulary and legacy-prose
  regressions without freezing future human phrasing improvements.
- Catalog, token, language negotiation and UTF-8 readers pass; all 150 installed
  languages render authentication forms on linked and CLI backends. The audit stays
  at 1,149 outstanding token differences; 95 source languages still need assets.

## 2026-11-17 Register existing Khmer and Russian regional assets

- Map Khmer/Cambodia and Russian/Russia source loaders to the existing portable
  `km_KH.jsn` and `ru_RU.jsn` files instead of excluding them for filename mismatch.
  Keep native catalog names, source identities and every translation byte unchanged.
- Regenerate matching browser/data catalogs: 148 languages are installed and 97
  source languages still need assets. Add explicit mapping regressions.
- Catalog validation, all-identity negotiation and UTF-8 translation readers pass;
  all installed-language sign-in/registration/setup rendering passes with linked
  and CLI SQLite backends. Translation quality and remaining assets stay open.

## 2026-11-17 Honor Designer page direction when moving widgets

- Resolve saved page direction and viewer language before translating a horizontal
  Designer move into a logical column change. Saved RTL overrides an English viewer;
  retain vertical movement, bounds, span-collision and action authorization checks.
- Add HTTP checks for RTL span collisions, boundary no-ops and reversible logical
  column changes, plus no-JavaScript/no-cookie Chromium geometry assertions for
  both physical arrow directions. The full linked-backend HTTP/browser suite passes.
- Broader directional-control rendering, responsive colors and actual retro-platform
  acceptance remain open; this does not close the language/RTL checklist.

## 2026-11-17 Move RTL selections toward physical neighbors

- Resolve the validated viewer language at the authenticated board move endpoint
  and invert horizontal logical deltas for RTL card relocation and list reordering.
  Keep direct kernel callers' default logical semantics, vertical moves, explicit
  drag destinations and existing authorization/action-token checks.
- Verify reversible no-JavaScript/no-cookie Arabic card moves by destination cells
  and list moves by physical geometry, restoring the original fixtures. Full linked
  and CLI SQLite HTTP/browser suites pass; linked runs covered the card flow and
  CLI runs also covered the new list geometry checks.
- Designer widget arrows and broader RTL/retro acceptance remain open.

## 2026-11-17 Follow physical neighbors in RTL board view links

- Reverse horizontal viewport coordinate deltas for RTL boards, so View left
  opens the logical next list and View right opens the previous list. Preserve
  existing bounds checks, vertical navigation and locale/session links.
- Extend the no-JavaScript/no-cookie Arabic browser flow to follow both links,
  verify logical X values and inspect the actual displayed list. The complete
  linked-backend HTTP/browser suite passes, including existing LTR navigation.
- Selection moves and Designer widget arrows remain in the direction audit.

## 2026-11-17 Mirror board columns and minimap once

- Prevent inherited RTL table direction from reversing the board's already-reversed
  source columns a second time. Keep explicit RTL text direction in list headers
  and card cells; emit minimap columns in the same structural order as the board.
  Logical list IDs and minimap coordinates stay unchanged.
- Reproduce the wrong physical column placement in no-JavaScript/no-cookie Chromium,
  then verify the first logical list and its minimap link both appear on the right.
  The complete linked-backend HTTP/browser suite passes after the fix.
- Directional move semantics, viewport navigation labels and Designer widget arrows
  still require the remaining RTL audit; retro hardware is not verified here.

## 2026-11-17 Keep RTL keypad buttons in physical order

- Give the shared movement keypad an explicit left-to-right table direction so
  an RTL page cannot place the left button on the right and vice versa. HTML 3.2
  browsers retain their existing source order.
- Reproduce the defect with a no-JavaScript/no-cookie Chromium geometry assertion
  on the Arabic board. Verify left/down/right positions and up above down, then
  pass the complete linked-backend HTTP and browser suite after the fix.
- Board/minimap mirroring, logical versus physical movement and Designer widget
  arrows remain part of the open RTL audit.

## 2026-11-17 Restore Italian and Swedish display arguments

- Restore the missing Italian list-title `%s` and the translated Swedish result
  range/count argument names from the current matching WeKan locale references.
  Compare stripped token spans before replacing: every surrounding prose character,
  other value and English key order stays unchanged.
- Record both keys for exact English token-inventory regression coverage. The token
  suite passes; the audit now leaves 1,149 differences for contextual review.

## 2026-11-17 Restore code-only activity title arguments

- Restore five malformed activity title templates in Indonesian, Georgian, Thai
  and the two Vietnamese locale files to the exact English argument inventory.
  Limit this repair to the two known code-only title keys and values containing
  only argument containers and punctuation; preserve values containing prose.
- Extend offline repair and regression coverage for translated names, single
  fences, missing arguments and empty templates, with explicit prose refusals.
  Verify all five production changes and unchanged values/key order against HEAD.
- Token, Acehnese and Bulgarian regressions pass. The audit leaves 1,151 ambiguous
  differences for contextual review; other localization and server tasks remain.

## 2026-11-17 Replace the wrong-language Acehnese seed

- Replace the Malay/Indonesian seed in `ace.jsn` with the current Acehnese source
  for 2,090 shared keys. Keep English key order and exact underscore/percent argument
  inventories across all 2,101 values; code-only legacy title templates stay literal.
- Fill nine removed-source compatibility phrases using the maintained Acehnese UI
  vocabulary and dictionary/grammar references. These nine legacy prose phrases are
  low confidence and remain open to native-speaker refinement.
- Add vocabulary/core/activity/legacy-label regressions that distinguish the old seed
  despite sharing a Latin script. Token records and installed-language reader checks
  pass; rendered form coverage checks the updated native labels on both backends.
- The ambiguous token audit now has 1,156 remaining differences. Other language data,
  missing locales and remaining application messages still need work.

## 2026-11-17 Correct a Serbian seed in Bulgarian activity text

- Replace the Serbian `act-setCustomField` value in the Bulgarian locale with
  the current Bulgarian source translation. Restore its complete `__board__`
  token while preserving every other Bulgarian value and key order.
- Add vocabulary checks against the Serbian seed, Bulgarian-specific word forms
  and the exact English placeholder inventory; script checks alone are insufficient.
  Token-repair and installed-language reader tests pass.
- The ambiguous token audit now has 1,158 remaining differences. Other mixed-language
  seeds and missing language assets remain open.

## 2026-11-17 Repair unambiguous translation tokens

- Restore 233 placeholder spellings/cases in 86 locale files from the corresponding
  English key. Repair only a unique unmatched argument or a uniquely matched case
  difference; leave missing/repeated/malformed/ambiguous slots for contextual review.
- Preserve all surrounding prose, other translation values and key order. Treat
  URL percent octets as data while retaining real named/printf arguments in URLs;
  include non-Latin token names and exact printf width/precision spelling.
- Add an offline audit/apply tool with flat/unique/UTF-8 input checks, symlink
  isolation, stale-input refusal and staged file replacement under TMPDIR. Record
  repaired keys so regression tests compare their inventories with English without
  freezing future human prose improvements.
- Verify synthetic Unicode/format/URL/ambiguity cases, dry run, guarded writes,
  unchanged human text/key order, idempotence and all recorded inventories. Compare
  every production change against the previous commit; only token spans changed.
  Installed-language reader/catalog tests also pass.
- 1,159 ambiguous token differences, wrong/mixed-language auditing and the missing
  language assets remain open; this batch does not declare translation data complete.

## 2026-11-17 Share viewer language across page frames

- Resolve query/posted language, the authenticated tenant-bound profile and standard
  Accept-Language through one viewer helper. Keep malformed/non-string profile values
  on fallback and retain explicit saved page-direction overrides.
- Emit matching HTML language/body direction and Content-Language/Vary metadata for
  home, board, Admin, Designer index/editor, published pages and selection edit/delete
  forms. Keep saved published doctypes and private enrollment headers intact.
- Verify profile/header/query/posted precedence across those real HTTP routes,
  fixed-direction pages and unchanged profiles on both backends. Live Mongo profile
  changes update matching headers/HTML while preserving typed BSON fields.
- Chromium layout/navigation/selection regressions pass with JavaScript/cookies
  disabled. Pin native HTTP test data/mode explicitly to their temporary fixture.
- Remaining translations, early error-frame metadata, physical RTL controls and
  additional language assets remain in the checklist.

## 2026-11-17 Honor saved Designer page doctypes

- Emit HTML 4.01 Transitional for a published page saved with `doctype=html4`.
  The renderer previously emitted the HTML 3.2 declaration for both saved choices.
  Retain HTML 3.2 for `html32` and the existing default page wrappers.
- Verify actual published HTML4/HTML3.2 round trips and invalid-doctype refusal on
  both HTTP backends. Chromium checks the HTML4 public identifier and standards
  parsing mode while exercising required fields, spans, RTL and no-JS sorting.
- Responsive colors and retro-browser/platform verification remain in the checklist.

## 2026-11-17 Retain locale through board and Designer navigation

- Carry validated query/posted language as transient rendering context. Keep it out
  of serialized session metadata and restore it after action-token verification.
  Include it in signed-action form fields and table search GET forms.
- Preserve locale in home/board/minimap/view links, selection returns, Designer
  edit/preview/export/mutation redirects and admin navigation/re-login. Keep session
  and locale query values before fragments and recognize existing encoded parameter
  names without confusing text inside a value for a parameter name.
- Encode search text and dynamic record IDs in generated URLs so literal query
  characters retain their value instead of becoming locale or identity parameters.
  Keep selected profile preferences unchanged and requests without explicit locale
  independent of earlier requests.
- Verify both-backend session identity/counter/idle boundaries plus actual HTTP
  links, GET/POST fields, mutation redirects, encoded search/IDs and fragments.
  No-JavaScript/no-cookie Chromium follows board/clear/home/admin/Designer/save;
  live shared-store authentication and BSON regressions also pass.
- Update older denial-text assertions to the installed translations while retaining
  all disabled-account, credential, factor and revocation checks. Remaining page
  translations, direction coverage and additional language assets stay in TODO.

## 2026-11-17 Translate enrollment credential and confirmation labels

- Reuse per-request translation readers for setup username/password/start labels,
  OTP code/confirm labels and sign-in links in enrollment and confirmation results.
  Escape text and attribute values while retaining the existing private form fields,
  proof checks, replay boundaries, response controls and language propagation.
- Verify every installed setup-form language on linked/CLI HTTP backends, Arabic
  OTP confirmation labels in the actual registration/enrollment/sign-in flow and
  no-JavaScript/no-cookie Chromium registration/setup/confirmation/login.
- Setup titles/instructions, retry explanations and completion/policy notices still
  need dedicated localized messages; this does not close the localization checklist.

## 2026-11-17 Translate registration forms and validation

- Reuse installed translations for registration title/button, username/password/
  confirmation labels and sign-in link. Add a separate native-name registration
  language picker with no JavaScript or credential fields in its GET submission.
- Re-render translated, empty forms for missing credentials, password mismatch,
  duplicate username and account-creation failure. Keep locale/RTL through retry
  without reflecting entered secrets. Use the shared invalid-credentials label for
  failed sign-in, retaining English fallback when translation assets are absent.
- Verify every installed registration language on both HTTP backends, Finnish
  validation errors, blank credential retries and duplicate-account messages.
  Chromium exercises Finnish registration with JavaScript/cookies disabled before
  continuing through the existing required-factor setup/login flow.
- First-admin notices, account-creation completion/policy messages, enrollment text
  and the rest of the application still need localized messages.

## 2026-11-17 Carry language through registration and enrollment

- Keep validated language choices in sign-in registration/setup links, registration
  forms/errors and session redirects, OTP setup/confirmation forms, retries and
  completion links. Ignore unsupported choices instead of reflecting them into URLs.
- Render registration/enrollment language/direction and Content-Language/Vary
  metadata while retaining no-store/no-referrer controls on private enrollment.
  Credential fields and setup tokens remain in POST bodies; only language is added
  to public flow URLs. Existing no-language direct requests remain supported.
- Verify required-factor Arabic registration, password failure, setup, invalid-code
  retry, confirmation and fresh-code sign-in on both backends. Assert URL state
  contains no username/password/secret/setup token, and reject unsafe language input.
- Enrollment/registration text still needs localization; this step carries preference
  state without claiming all authentication messages or general navigation translated.

## 2026-11-17 Select and retain sign-in language

- Add a plain GET language picker using installed native names and the selected
  locale. Escape option names/values and apply labels, with no onchange script,
  cookies or credential fields in the language-selection form.
- Re-render the translated form after failed login without reflecting username,
  password or OTP. Retain its locale and RTL metadata for retry. Keep a valid
  explicit choice in the successful session redirect without writing profile data.
- Verify every installed option, selected state, native names, credential secrecy,
  redirect state and hostile option/text escaping on linked/CLI HTTP backends.
  Chromium checks exercise Finnish/Arabic selection without JavaScript/cookies.
- Language propagation through enrollment/registration and general navigation,
  remaining translated messages/pages and missing language assets remain open.

## 2026-11-17 Render translated sign-in labels

- Add a per-page translation reader for the selected installed language and English
  fallback. Missing, empty, wrong-type or malformed local values fall back safely;
  unknown keys retain an explicit caller fallback. Load bounded disk/embedded
  assets without mutable global request language or whole-catalog text caches.
- Translate sign-in title, username/password/OTP labels and account-creation link
  from the existing assets. Escape text and attributes at rendering boundaries;
  preserve literal format/underscore tokens in the reader without interpreting them.
- Emit HTML language/direction and Content-Language/Vary headers. Keep selected
  language in the form's POST query, with unchanged credential field names and
  no script/cookie requirement. Missing assets retain the standalone English form.
- Verify UTF-8 lookup across every installed language, fallback/error cases and
  rendered labels/headers/forms and hostile-markup escaping on both HTTP backends.
  No-JavaScript/no-cookie Chromium enrollment/login also passes with the translated
  form; broader page/error/OTP-flow localization and language
  navigation/pickers remain in TODO.

## 2026-11-17 Negotiate server language and page direction

- Load an immutable, validated server catalog before request threads start, using
  embedded assets before disk and a bounded asset reader. Invalid or absent catalogs
  retain English fallback; unsafe filenames, duplicate identities and wrong field
  types cannot become lookup paths.
- Resolve explicit language, authenticated profile language, then weighted
  Accept-Language preferences. Support source aliases, separator normalization,
  regional parents and legacy Hebrew codes; skip malformed/zero-quality ranges.
  Read the framework's standard AcceptLanguage property so real HTTP headers work.
- Apply catalog RTL metadata to board, published Designer and Designer editor
  direction. Read only a validated session's string profile.language, preserving
  the profile and its other fields. Explicit page direction still wins.
- Verify every installed language/direction, malformed catalogs, disk/embedded
  lookup, traversal refusal, real linked/CLI HTTP profile/header precedence and
  structural RTL order. Live Mongo profile changes drive HTTP direction while
  retaining typed BSON profile fields.
- Translated labels, language pickers/state preservation, missing translation
  assets and direction across all remaining application pages are still open.

## 2026-11-17 Repair language catalog generation

- Read both current compact WeKan language metadata and the previous literal
  catalog without executing JavaScript. Locate the enclosing WeKan source by
  default, validate identities/paths/types and preserve distinct source aliases.
- Generate matching browser `langs.jsn` and strict JSON `locales.jsn` catalogs.
  Advertise existing translation files only, retain the short Valencian filename,
  require English fallback, and use the source's native language names/direction.
  Existing translation bytes remain unchanged; broken legacy aliases are excluded.
- Regenerate 146 installed language entries. Report 99 additional source languages
  awaiting local translation files; server selection/rendering, profile/header
  negotiation, complete translation imports and RTL integration remain open.
- Verify compact/literal round trips, Unicode/escaping, malformed metadata refusal,
  failed-input retention and exact browser/data catalog agreement.

## 2026-11-17 Stop Unix HTTP and maintenance cleanly

- Handle SIGTERM/SIGINT by setting a flag only. Poll it from the accept loop,
  including connection admission under continuous traffic; perform object and thread
  cleanup outside the signal handler. Keep handlers active through worker joining.
- Track connection lifetimes under a lock. After a one-second request drain,
  shut down remaining sockets before framework destruction so incomplete reads wake
  without touching a reused descriptor. Drain HTTP threads before closing tenant
  handles, then join maintenance and restore the previous signal handlers.
- Verify idle, busy and incomplete requests, repeated signals, successful cleanup,
  exit status zero, immediate port/database reuse and SQLite integrity on linked/CLI
  backends. Native and live shared HTTP workflows also pass through the custom server.
- Native Windows console controls and retro-platform shutdown remain unverified;
  the new signal handlers and tracked sockets are compiled only for Unix.

## 2026-11-17 Open existing shared stores through HTTP

- Add explicit `WELITE_SHARED=1` activation for existing public FerretDB stores,
  installing the guarded root projections when opening a tenant. Keep the admin
  registry native and refuse missing or normalized public stores in shared mode.
- Select the existing canonical `wekan.sqlite` without aliases, copies or renames.
  Refuse ambiguous database files, orphan sidecars and long shared filenames in
  strict 8.3 mode. Ordinary mode refuses source storage instead of creating a
  normalized database beside it. Validate the mode before tenant initialization.
- Use the same file selection for idle maintenance discovery. Verify linked/CLI
  HTTP login, Mongo-to-HTTP reads, HTTP-to-Mongo card writes, BSON preservation,
  private browser sessions, API restart persistence and shared revocation with the
  actual FerretDB server. Exercise filename refusal cases without creating files.
- Fresh shared creation/default activation, portable shared filenames, migration,
  Mongo-managed index/cache parity and full Meteor application workflows remain open.

## 2026-11-17 Maintain normalized legacy-store expiry

- Add a legacy-store sweep for the existing normalized token layout. Remove expired
  credentials, optional credential/orphan metadata and optional pending enrollment at
  inclusive deadlines, retaining valid sessions and OTP replay boundaries.
- Validate expected text columns/primary keys and pending/checkpoint layouts. Snapshot
  inspected schemas inside transaction guards, refuse mixed FerretDB/native stores and
  avoid creating optional auth or shared/history tables. Only the private checkpoint is
  added to a supported older store.
- Commit the ten-minute checkpoint and cleanup atomically. Ignored metadata/token/setup
  deletion or checkpoint seed/update rolls back; backwards clocks and stale concurrent
  claims cannot advance work. Keep optional-metadata-free older stores supported.
- Dispatch both layouts in the idle worker and wake it for newly opened legacy stores.
  Verify linked/CLI equality, schema refusal, rollback, concurrency, replay retention and
  actual idle cleanup. Shared interoperability and broad HTTP regressions also pass.
- Broader resume-policy parity, process-signal lifecycle, actual shared-store activation,
  migration/filename policy and full Meteor application/observer workflows remain open.

## 2026-11-17 Expire private pending enrollment during maintenance

- Remove expired private enrollment records in the existing shared-store sweep
  transaction, using the same inclusive second-based deadline as confirmation.
  Assert deletion succeeded before committing; ignored writes roll back shared/local
  credential cleanup, pending removal and the durable checkpoint together.
- Retain unexpired setup records and all OTP replay boundaries. Cleanup neither
  activates a factor nor publishes pending secrets into shared account documents.
- Verify real pending setup at equality, unexpired retention, ignored-delete rollback
  and idle-worker removal on linked/CLI SQLite. Enrollment proof, activation, replay
  and binding/expiry regressions also pass on both backends.
- Normalized legacy-store maintenance, broader resume-policy parity, process-signal
  lifecycle and full shared-store/application activation remain open.

## 2026-11-17 Sweep expired local credentials in shared stores

- Extend the due shared-store transaction to retire linked shared hash/legacy records,
  delete expired private credentials and metadata, and remove orphan metadata. Local
  expiry is inclusive at its committed deadline; shared age pruning keeps its existing
  strict-before cutoff. Healthy sibling sessions/accounts remain intact.
- Add typed digest-set retirement and the pure SQLite Meteor-hash helper. Build commands
  from distinct matching source records, using a private source/user/hash index instead
  of serializing accumulated private history. Preserve shifted BSON schemas and unknown
  scalar/object siblings.
- Preserve source-bound identity before deleting older/unlinked local rows, and retain
  seen history. Unknown legacy hashes stay on Meteor's expiry schedule until raw bearer
  observation can revoke them; never guess another session's hash or log out all siblings.
- Assert each cleanup stage before proceeding. Ignored source, metadata, token, link and
  history writes roll back private/shared changes and the checkpoint together. OTP replay
  boundaries and pending enrollment remain untouched.
- Verify linked/CLI equality, hashed/raw forms, BSON/scalar preservation, orphan cleanup,
  rollback/retry, sibling isolation and actual idle-worker private/shared cleanup. Resume
  and native/private token regressions pass. Normalized-store/pending-state maintenance,
  broader policy parity and application/observer activation remain open.

## 2026-11-17 Source-bound shared bearer links

- Add owned private `_wl_pair` metadata linking a local bearer digest to its account,
  Meteor digest and source UUID. Commit links with shared issuance/adoption and assert
  ignored writes cannot leave partially issued credentials or consumed OTP state.
- Backfill known account/source identity for older active API rows with an explicitly
  unknown shared hash. Never infer a hash from timestamps. A subsequently validated raw
  bearer fills that hash; native/browser credentials keep their existing format.
- Retain identity links after local deletion so a later raw request can still revoke its
  scoped shared record. Keep history blocking re-adoption. Remove obsolete-source links
  atomically when rebinding to a new users collection.
- Verify linked/CLI mapping, ignored writes/backfill, lazy enrichment, adoption rollback,
  post-local-deletion targeted revocation and source migration/ignored-cleanup rollback;
  native token suites pass.
- This is the linkage prerequisite for local background cleanup; the sweep still removes
  shared expired records only. Legacy unknown-hash handling and local cleanup remain open.

## 2026-11-17 Discover idle tenants before first access

- Give the HTTP maintenance worker its configured data root. Discover existing local,
  admin and enabled canonical-domain stores on startup and each polling pass, using
  registry numeric short-directory keys rather than host strings as paths.
- Refresh eligibility without a request: newly enabled/registered domains join the next
  pass; disabled, orphaned, invalid-host and missing stores are skipped. Discovery does
  not provision directories or schemas. Registry failures are isolated and retried.
- Keep explicit-path mode for standalone callers. Root-based discovery is authoritative
  when configured; tenant registration wakes a refresh. Native/registry stores without
  a shared users view are skipped without recording false sweep failures.
- Verify startup/idle discovery, registry changes and read-failure recovery on independent
  backups of actual
  shared data on linked/CLI SQLite, with no HTTP request. Existing live worker/interop
  and both-backend HTTP enrollment/registration regressions pass.
- Local credential cleanup, broader resume-policy parity, actual shared-store activation,
  filename/sidecar policy and application/observer workflows remain outstanding.

## 2026-11-16 Background shared expiry lifecycle

- Add a worker that maintains registered shared stores during idle HTTP periods, with
  one-minute polling and the existing durable ten-minute sweep checkpoint. Deduplicate
  absolute paths and wake promptly when a new store registers.
- Use separate per-pass database connections; never pass request handles to the worker.
  Isolate failed stores, count failed passes and retry without advancing a failed sweep.
  Missing files are skipped and native stores are not swept. Termination wakes and joins
  the worker, including an in-progress transaction, before releasing its state.
- Start/stop maintenance around the HTTP run loop and register shared stores through
  both cached and newly opened tenant handles. Unsupported stores do not break requests.
- Verify linked/CLI live idle cleanup, an observed failing pass followed by recovery,
  repeated work, retained BSON, native/missing-store isolation and clean worker shutdown.
  Both-backend HTTP enrollment/registration regressions also pass.
- Discovery of existing tenants before their first request, local credential cleanup,
  shared-store activation and application/observer workflows remain open.

## 2026-11-16 Guarded shared expiry sweep

- Add owned durable `_wl_sweep` scheduling state and a ten-minute due-check kernel.
  Calculate the cutoff with binary64 lifetime subtraction followed by Date truncation,
  then remove strictly older Date/legacy numeric records across shared accounts.
- Commit the due timestamp and every typed edit together. Bind work to source/settings
  snapshots, reject backwards clocks and concurrent stale claims, and assert cleanup
  and checkpoint writes succeeded. Failed/ignored writes roll back all accounts and
  scheduling state. Retained BSON types, precision, unknowns and token history survive.
- Verify linked/CLI live due boundaries, concurrent callers, ignored account/checkpoint
  updates, rollback/retry, reinstall, fractional cutoffs against Node.js and stale source.
- The callable sweep is not yet a running background service. Local credential cleanup,
  the HTTP timer hook and full shared-store/application activation remain to be connected.

## 2026-11-16 Adopt existing shared Meteor bearers

- On API validation, adopt a previously unseen shared hash or legacy raw bearer only
  from one current account with valid typed expiry and an allowed account policy.
  Preserve the original issue/expiry timestamps and bind local metadata to the current
  credential and optional OTP factor. Resume does not consume a fresh OTP code.
- Guard the transaction with the users-source, full source document, Settings, policy,
  global account-match count and absent local/history snapshots. Atomically create local
  credential/metadata/history and convert a legacy record, asserting both local rows and
  the resulting shared document. Failed/ignored writes roll back every effect.
- Keep existing web/client checks, expiry and observed revocation. Seen digests prevent
  recreating deleted local credentials from restored shared records. Concurrent validators
  may share one successful adoption and then use the same committed authorization.
- Verify live linked/CLI hashed/legacy adoption, concurrency, exact BSON and original
  expiry, ignored local/shared writes, retry, expiration, duplicate ownership, disabling,
  credential-change revocation and restored-record denial. Native token regressions pass.
- Broader resume-policy parity, scheduled expiry, normal shared-store activation and full
  Meteor application round trips remain outstanding.

## 2026-11-16 Durable shared bearer history

- Add owned private `_wl_seen` storage containing local bearer digests. Backfill current
  credentials before source cleanup, and retain history through token/account deletion,
  source UUID changes and legacy unbound-store migration.
- Record inserts, digest updates (old and new) and deletions in the credential's own
  transaction. Assert history writes succeeded so ignored/failed writes cannot commit
  partial issuance or revocation; incomplete installer backfill also rolls back.
- Verify live linked/CLI history creation, upgrade backfill, ignored-write rollback,
  SQL digest changes and retention after revocation/reinstall/source migration.
- This prepares the no-resurrection guard for existing-bearer adoption. Automatic
  adoption remains disabled until it checks this history and atomically validates and
  records source membership, account policy and original expiry.

## 2026-11-16 Typed legacy resume conversion

- Add an atomic `wl_resume` convert operation for one raw Meteor bearer. Replace the
  raw field with its SHA256/base64 hash while retaining the original timestamp/type,
  unknown fields and sibling BSON metadata. Never refresh the issue time.
- If a hash was already installed, retain its timestamp and remove matching raw
  records. Repeated/concurrent conversion is idempotent. Refuse duplicate hash ownership
  within the document, ambiguous raw-only entries, hybrid records and invalid timestamps.
- Verify TEXT/JSONB conversion, 16 simultaneous callers, already-hashed races, fractional
  legacy timestamps, rejection without mutation and transaction rollback on both SQLite
  backends. Live FerretDB tests check concurrent conversion and exact BSON preservation.
- This is a storage operation, not bearer authorization: expiry/policy/source checks,
  cross-account ambiguity and atomic local adoption must be integrated before existing
  Meteor credentials can authenticate through it.

## 2026-11-16 Fractional shared API lifetimes

- Activate decimal/scientific fractional login-expiration days in shared configuration,
  password/OTP issuance and bearer validation. Preserve binary64 milliseconds until
  Date truncation; local expiry and the existing REST response retain the committed
  millisecond timestamp. A submillisecond duration does not become a one-second grant.
- Bind expiry computation and insertion to the same source/settings snapshot. Keep the
  seconds-valued caller parameter as a rounded-up request marker, never as the shared
  expiry duration. Native-store and browser lifetimes retain their existing behavior.
- Accept fractional milliseconds in the SQLite resume checker. Verify exact live BSON
  issue-time/local-expiry agreement against Node.js, fractional OTP issuance, stored and
  environment precedence, invalid configuration and fractional SQL expiry boundaries
  on linked/CLI SQLite. Native credential/token regressions also pass.
- Scheduled expiry, legacy conversion and adoption of existing Meteor bearers remain
  outstanding, as do broader shared-store activation and application round trips.

## 2026-11-16 Fractional expiry arithmetic kernel

- Add decimal/scientific day parsing and IEEE binary64 millisecond expiry arithmetic
  matching Meteor's Date construction, including truncation after addition and Date
  range refusal. Empty/zero retains the 90-day default; negative/nonfinite/out-of-policy
  values fail closed. The supported positive day range remains at most 36500.
- Reuse the Date arithmetic in resume validation. Verify 89 vectors against Node.js in
  normal and checked builds, including fractional/submillisecond durations, negative
  timestamps, range boundaries and invalid input; retain both-backend resume regressions.
- Fractional configuration is not activated yet: shared issuer/configuration plumbing
  still uses whole seconds/days. The next step must preserve millisecond expiry through
  issuance, validation and REST responses before lifting that compatibility gate.

## 2026-11-16 Resolve stored account authentication policy

- Resolve shared Settings MFA, LDAP enable/fallback/migration and password-login
  overrides before deployment defaults, including null/empty fallback. Pass explicit
  policy values to the portable kernel without changing process environment variables.
- Use the resolved policy for password lookup, authentication proofs, issuance,
  validation, enrollment and registration. Bind proofs and writes to the source and
  settings snapshot; changed settings reject stale proofs. Denied registration creates
  no account. Observed password disabling revokes credentials durably.
- Verify stored MFA against an opposite deployment default, LDAP override combinations,
  null fallback, settings changes after proof creation and disable/restore behavior with
  live FerretDB on linked/CLI SQLite. Native policy, crypto, enrollment, admin HTTP and
  required-factor registration/enrollment HTTP regressions pass on both backends.
- Existing Meteor bearer adoption, fractional lifetimes, scheduled expiry, legacy
  conversion and broader account configuration remain open.

## 2026-11-16 Paired shared API bearer issuance

- On shared stores, commit API credentials/authmeta, optional OTP consumption and a
  typed Meteor resume record together. Refuse reused shared hashes/plain bearers across
  accounts and assert the shared append succeeded; failed/ignored writes roll back all
  local/shared effects. Browser sessions remain private and client-bound.
- Require both local authorization metadata and one unambiguous, unexpired shared record
  for co-issued API validation. Mongo removal/expiry or duplicate ownership invalidates
  the local bearer through targeted revocation. Restoring a removed source record alone
  cannot revive it. Existing private-only shared-store API tokens require a fresh login.
- Read stored loginExpirationInDays before its deployment fallback; return the committed
  local expiry in REST responses. Support default/zero 90 days and whole-day lifetimes
  from 1 to 36500. Reject unsupported values rather than issuing mismatched credentials.
- Snapshot shared settings in the issuance transaction. Refuse conflicting stored versus
  deployment MFA/LDAP policy, disabled password login and enabled SQRL-only identities.
  Direct resolution of differing authentication overrides remains a compatibility gate.
- Verify linked/CLI live paired MFA/password issuance, membership/expiry removal,
  cross-account ambiguity, global collision with OTP rollback/retry, ignored append
  rollback, stored lifetime precedence and policy refusal. Native HTTP/hash/OTP and
  enrollment regressions pass. Fixtures now issue fresh bearers instead of reusing them.
- Existing Meteor bearer adoption, scheduled expiry, broader settings resolution and
  Mongo-managed token indexes remain open; normal shared-store activation is still gated.

## 2026-11-16 Targeted shared token revocation

- Add a transaction fragment that removes one bearer's shared hashed and matching
  legacy plain records plus its scoped local credential/metadata. Keep other sessions,
  pending setup and replay counters untouched. Check source identity and assert no
  matching shared record survived an ignored write before deleting local state.
- Add the typed revoke command; derive its digest from the supplied bearer so a caller
  cannot mismatch raw/hash selectors. Serialize the bearer through escaped JSON,
  including the SQL comparison, rather than putting control bytes into SQL text.
- Connect observed credential/policy failure, local expiry and invalid stored-session
  identity to targeted cleanup. A stale collection removes only local state and never
  edits the replacement collection. Preserve existing IP/user-agent mismatch behavior.
- Centralize the unchanged tenant-scoped private hash for issuance and revocation;
  give invalid enrollment attempt digests their own explicit domain prefix.
- Verify both SQLite backends with hashed/legacy removal, ignored/failed-write rollback,
  unchanged sibling sessions/BSON, missing-token no-op, credential restoration and local
  expiry through live Mongo. Session/kernel and native HTTP account regressions pass.
- Shared bearer issuance/authorization, expiry scheduling and legacy conversion remain
  open; this step connects individual revocation to existing validation failures.

## 2026-11-16 Shared all-user token revocation

- Connect administrator account disabling and OTP enrollment to one transactional
  revocation fragment. Clear shared Meteor resume arrays, including legacy records,
  alongside local token metadata/credentials and pending enrollment tokens.
- Preserve unrelated BSON data and OTP replay boundaries. Leave absent resume paths
  absent, and scope changes to the selected user; re-enabling cannot restore removed
  shared/local bearers or pending setup. Native stores retain their private-token path.
- Guard source identity again inside the transaction and assert shared records are
  actually empty. Failed or ignored physical writes and later local deletion errors
  roll back both revocation and the owning account change.
- Share pending-enrollment schema in a small metadata unit, ensuring it exists within
  revocation's transaction without circular imports or a setup-creation race.
- Verify both SQLite backends with live Mongo enrollment/disable, shared and local
  records, pending cleanup, source changes, forced/ignored writes, rollback/retry,
  account isolation and re-enable behavior. Verify native HTTP account regressions.
- Shared bearer issuance/authorization, per-token revocation and expiry scheduling
  remain open; this step connects the all-user revocation events.

## 2026-11-16 Resume timestamp validation and expiry

- Add typed hashed-token checking with absent/valid/expired/invalid results. Require one
  matching record, a BSON Date or legacy numeric timestamp, and an explicit positive
  lifetime. Reject ambiguous hashes, malformed timestamps and invalid Date ranges;
  failed checks leave output timestamps empty.
- Match the resume expiry boundary: now equal to expiry is expired. Legacy fractional
  numeric milliseconds follow Date(number) truncation; expiration arithmetic is bounded
  to JavaScript's Date range without integer overflow.
- Add strict-before expiry pruning for Date and numeric records, including legacy plain
  records. Preserve unrelated/malformed timestamp records and shifted sibling schemas.
  Expose pure wl_rescheck alongside wl_resume on linked/CLI SQLite.
- Verify both backends with exact boundaries, future stamps, lifetime/range failures,
  legacy fractions, duplicates and live Mongo typed pruning/BSON preservation.
- Shared bearer authorization/issuance and revocation remain open. Browser sessions stay
  private so cross-application bearer use cannot bypass their client binding.

## 2026-11-16 Typed Meteor resume-token kernel

- Add Meteor SHA256/base64 token hashing, separate from WeLite's tenant-scoped private
  digest. Verify ASCII, Unicode/NUL and bounded input against Python's independent
  hashlib/base64 results; reject empty/oversized raw tokens and noncanonical digests.
- Add pure append/remove/clear operations on services.resume.loginTokens. New records
  contain a hash and BSON Date; no new raw token is stored. Retain legacy records,
  unknown fields, field order and complete sibling schemas when array positions shift.
- Expose the kernel as wl_resume on linked SQLite and the host-API CLI extension.
  Refuse duplicate appends, invalid commands/dates and malformed parent containers.
  Explicit clear can empty a malformed token value while preserving its parent fields.
- Verify TEXT/JSONB atomic writes and rollback, sixteen concurrent distinct appends
  without lost records, one winner for duplicate appends, shifted Date metadata and
  live Mongo BSON round trips including legacy tokens and precision-sensitive values.
- Keep shared token issuance/validation, expiry, logout/revocation, legacy conversion
  and Mongo token indexes open. This storage kernel does not authorize shared sessions
  or change the existing HTTP/private-token authentication paths.

## 2026-11-16 Physical model unique keys

- Install owned SQLite unique expression indexes for declared model unique keys,
  including usernames. Enforce the existing BINARY/canonical SQL NULL semantics on
  physical FerretDB documents, protecting both SQL views and direct Mongo writes.
- Record index ownership/definition in the adapter registry. Preserve exact owned
  definitions, repair an absent owned index and refuse unowned or altered objects
  without replacing them. Index creation and registry installation remain atomic;
  existing duplicates still require repair rather than rewriting account documents.
- Verify linked/CLI live Mongo duplicate inserts (11000), rejected duplicate updates,
  eight mixed Mongo/SQL writers with one winner, case/NULL/missing values, fresh server
  startup, removed-index repair, altered/unowned refusal and legacy ambiguous-login
  denial with duplicate preflight/repair. Mongo listIndexes metadata is unchanged.
- Keep Meteor-managed sparse/multikey account indexes and registry-cache coordination
  open. These private SQL constraints do not implement Mongo sparse NULL semantics,
  emails/resume-token multikey uniqueness or full Mongo duplicate-update error mapping.

## 2026-11-16 Shared authentication collection identity

- Bind private authentication state to the FerretDB users collection's physical table
  and UUID in an owned source record. Routine adapter reinstall preserves credentials,
  OTP counters and pending setup; replacing the collection invalidates the old state
  even when IDs, usernames and password records are reused.
- Check source identity during account lookup, login/enrollment proof use and web/API
  validation. Carry the observed source condition into token/setup mutations and OTP
  activation transactions, closing changes between the initial read and SQL write.
  Observed stale token validation also removes that credential and web context.
- On a known source change, atomically revoke local tokens/metadata and pending setup,
  reset the old replay ledger and bind the new source. Older unbound adapters revoke
  credentials/setup once while retaining conservative replay boundaries. Tenant attempt
  allowances survive either transition.
- Refuse missing/non-string/wrong-length UUIDs through the source-record constraints;
  failed binding rolls back cleanup and the rest of adapter installation together.
- Verify both backends against actual Mongo collection drop/recreate, reused account
  credentials, normal reinstall, proof rebinding, legacy backfill and malformed-metadata
  rollback. Native password/OTP, enrollment, session and public HTTP tests still pass.
- Mongo account index parity, shared Meteor resume tokens and application activation
  remain open; source identity does not complete those compatibility gates.

## 2026-11-16 HTTP OTP enrollment

- Add plain HTML setup and confirmation forms, linked from sign-in. Require a fresh
  password, display a manual authenticator secret and retain only an opaque setup
  token in the confirmation form. Never place setup secrets/tokens in navigation URLs
  or grant a session before activation; send no-store and no-referrer headers.
- Bind setup to socket peer and user agent. Share durable login allowances with setup
  and confirmation; derive the confirmation account from pending server state so
  posted usernames cannot rotate its budget. Denials return 429 with Retry-After.
- Send newly registered accounts covered by REQUIRE_2FA to enrollment without issuing
  application tokens or returning a misleading account-creation error. After confirming,
  instruct users to wait for a fresh authenticator code and sign in normally.
- Verify both backends through HTTP: required-factor registration, wrong passwords/codes,
  client binding, attempt caps, forwarded-header/username spoofing, setup expiry and
  replacement, restart persistence, failed activation rollback/retry, no early access
  and consumed-code denial. Verify setup, confirmation and sign-in in Chromium with
  JavaScript disabled and Cookie headers removed, plus existing HTTP regressions.
- Shared Mongo account/index/session integration and application activation remain open;
  completing enrollment does not complete the shared-database checklist.

## 2026-11-16 Limited OTP enrollment core

- Add a distinct, unit-owned password proof for accounts without an active factor,
  including accounts covered by REQUIRE_2FA. It cannot authorize application tokens.
  Bind it to the database and credential/policy snapshot, expire it after 30 seconds
  and allow only one successful setup start.
- Generate fresh 20-byte secrets and independent bearer tokens. Keep pending setup in
  private owned storage for five minutes, bound to a server-derived client digest.
  Starting setup leaves shared services unchanged and creates no login token. New setup
  invalidates an earlier pending token; user deletion removes pending secrets.
- Confirm the code and current credentials/policy, then activate the factor, consume its
  counter, remove pending setup and revoke local tokens in one transaction. Deny stale,
  expired, replaced or competing setup, and roll back failed or ignored user updates.
  The activation code cannot be reused for login; a fresh code signs in normally.
- Normalize SQLite JSON-expression subtypes at shared TEXT projection boundaries, so
  json_set updates and JSON-valued inserts reach the typed patcher as text.
- Verify linked/CLI limited proofs, independent OTPs, fresh secrets, binding/expiry,
  snapshot changes, sixteen concurrent confirmations, full rollback/retry, token
  revocation, null factor metadata and schema refusal. Verify shared BSON preservation,
  reinstall and physical user-deletion cleanup against live FerretDB.
- HTTP enrollment forms, setup confirmation routing and admission limiting remain open.
  This step supplies the core; it does not yet expose enrollment to users.

## 2026-11-16 HTTP password and OTP login

- Connect no-cookie web sign-in and REST login to the password/OTP proof factory and
  atomic token issuer. Add an optional six-digit code field to the plain HTML form;
  accept `code` alongside username/password in JSON or form REST requests.
- Reserve durable account/peer/tenant allowances before credential verification on
  both routes. Return 429 with Retry-After when denied; use the actual socket peer,
  ignoring forwarded headers for admission. Both routes share counters across restart.
- Preserve password-only accounts, factor-bound session/API validation and transactional
  replay consumption. Required accounts without an active factor remain denied pending
  enrollment. Return API credentials using proper JSON string encoding.
- Verify linked/CLI HTTP login, wrong/missing/malformed codes, replay, forced issuer
  rollback/retry, restart persistence, spoofed peer headers, shared route caps, factor
  replacement and required-factor policy. Verify actual Chromium form submission and
  reload with JavaScript disabled and Cookie headers removed on both backends.
- Keep legacy policy/secret test scenarios in independent attempt windows; token rollback
  assertions permit the intentional pre-authentication reservation while still comparing
  all other database data. Enrollment and shared Meteor session integration remain open.

## 2026-11-16 Durable login attempt reservations

- Add atomic pre-authentication reservations: five attempts per account, thirty per
  socket peer and three hundred per tenant in 300-second windows starting at the first
  reservation. Count successful attempts too; credential checks do not reset allowances.
- Store hashed account/peer buckets privately in SQLite, retaining limits across
  processes and restarts. Backward clock changes deny reservations; expired buckets
  are removed on successful reservation, bounding stored bucket cardinality to 601.
- Roll back every bucket on denial or write failure. Reject incompatible schema and
  invalid identities/time rather than admitting an uncounted attempt. Register the
  table in the shared adapter without changing account documents.
- Verify linked/CLI concurrency, boundary times, rollback/retry, peer and tenant caps,
  cleanup, separate tenants and live shared-adapter reinstall persistence.
- HTTP login integration and enrollment remain open; callers must reserve using trusted
  server time and the actual socket peer before performing credential verification.

## 2026-11-16 Password and OTP token proofs

- Add unit-owned password/OTP proofs with a 30-second lifetime and single successful
  issuance. Retain credential/policy snapshots and the matched code, never plaintext
  passwords. Recheck current policy, credentials and code before issuing a token.
- Commit token, metadata and replay consumption together. Failed writes roll back;
  competing logins using the same counter have exactly one winner. Bind web/API
  validation to the current password and canonical active factor, including Argon2
  secret-file policy. Observed changes revoke existing credentials permanently.
- Verify both SQLite backends, sixteen concurrent logins, stale account/factor policy,
  forced metadata/counter failures and retry, LDAP fallback and required-factor modes.
  Verify a live shared FerretDB account with Argon2 secret plus OTP without BSON changes.
- Keep HTTP code forms/API routing, failed-attempt limits and enrollment open. The
  existing HTTP password-only routes still deny active or required factors.

## 2026-11-16 Durable OTP replay claims

- Add private per-user/per-factor replay counters. Canonical base32 identity makes
  case/padding aliases share the same boundary. Preserve consumption across token
  logout/expiry and process restart; keep users and changed factors independent.
- Supply a claim statement for the same transaction as token/metadata insertion.
  Stale or duplicate counters violate the counter constraint, requiring rollback of
  the whole token transaction. A missing token cannot consume a counter; failed
  token/metadata/counter writes leave the code available for a valid retry.
- Distinguish unused factors from schema/query errors, NULL values, duplicate records
  and invalid stored negative counters. Validate the private table/cleanup definition.
- Include owned replay storage in the shared adapter and remove it with its physical
  user, while token deletion retains it. Verify 16 concurrent claimants (one success),
  rollback/retry, restart, aliases, isolation and corrupt-state denial on both SQLite
  backends, plus shared FerretDB ownership/cleanup and existing TOTP vectors.
- Keep second-factor proof validation, production token-issuer wiring and enrollment
  open. The replay kernel does not authorize a login by itself.

## 2026-11-16 Portable one-time-code core

- Add SHA1 HOTP/TOTP with explicit big-endian 64-bit counters, preserved leading zeroes
  and 30-second time steps. Support the six-digit Meteor profile and eight-digit RFC
  vectors. Parse bounded ASCII base32 with case-insensitive input, canonical unused
  bits and correct optional padding; clear decoded keys and HMAC working digests.
- Match the full bounded validation window without early success, return its counter,
  and reject matches at/below the caller's replay boundary. A matching used counter
  cannot be rescued by a colliding later counter in the same window. Counter consumption
  still belongs in the upcoming atomic token-issuance integration.
- Verify published RFC HOTP/TOTP SHA1 vectors and independent Python HMAC, including
  binary secrets, padding/case, maximum counters, post-2038 times, window edges and
  malformed inputs in normal/checked Pascal builds.
- Keep active-factor login guarded until replay storage, login proof/issuance and
  enrollment routes are implemented and verified.

## 2026-11-16 Shared account guards for password-only flows

- Centralize shared-account policy at login lookup, token issuance and every web/API
  token validation. Active/unknown factor types and malformed factor metadata cannot
  be bypassed with a password alone. Pending activation without a type remains usable
  when no factor requirement applies.
- Match WeKan's LDAP enable/fallback/explicit opt-out rules rather than treating every
  provider label as a local-password ban. Honor REQUIRE_2FA off/admins/all for password
  accounts, including an account promoted to admin after token issuance.
- Recheck the method, services and admin snapshot in the atomic token insert. A policy
  denial removes observed web/API credentials, so restoring the prior account state
  does not revive them. Preserve all source account metadata.
- Verify checked policy vectors, actual native/CLI password-route denial, durable
  issuance/revocation, admin promotion, live Mongo changes and pending setup. HTTP,
  secret, crypto and session/concurrent-counter tests pass. Update the older session
  fixture to require fresh login after credential revocation.
- This is a guard, not the completed two-factor flow: challenge/enrollment support,
  shared index metadata and Meteor session interoperability remain in TODO.

## 2026-11-16 Argon2 secret policy and token binding

- Keep the default empty-secret Meteor policy and add optional operator-selected binary
  `WELITE_ARGON_SECRET_FILE` input. Read 1–65,536 bytes without trimming; reject missing,
  empty or oversized configured files. Unix reads require a private regular file,
  reject symlinks/FIFOs and validate the opened inode; other targets use file sharing/ACLs.
- Capture a credential binding from the same secret snapshot used to verify a password.
  With a configured Argon2 secret, use a domain-separated HMAC fingerprint; otherwise
  preserve existing SHA256 bindings. Recheck the current binding at token issuance and
  validation, and remove rejected web/API credentials so observed rotation cannot revive
  them after restoration. Never retry an empty secret or bcrypt fallback.
- Verify exact secret bytes and HMAC markers against the official C reference/Python,
  including NUL/high-bit/newline bytes, 64 KiB and malformed/private-file cases. Test
  actual linked/CLI web/API login, rotation between proof and issuance, cross-process
  bearer validation, missing/empty secret denial, durable revocation and bcrypt isolation.
- Live FerretDB account verification preserves BSON; native/CLI HTTP and durable-token
  crypto regressions pass. Secrets and their paths are not stored in account metadata.
  Broader Mongo account/index/session policy remains in TODO.

## 2026-11-16 Legacy Argon2 compatibility

- Add explicit v16 derivation alongside default v19. Include the selected version in
  parameter hashing and use the legacy overwrite rule instead of subsequent-pass XOR.
  Keep the same validation, resource budgets and memory clearing.
- Accept explicit v16 PHC strings and versionless legacy strings (defined as v16).
  Reject unknown versions and mismatched version/tag combinations rather than trying
  both algorithms. Preserve current v19 behavior and Argon2-before-bcrypt selection.
- Compare all d/i/id variants and both versions with the official C reference at
  f57e61e19229e23c4445b85494dbf7c07de721cb, built only as an isolated test oracle.
  Normal/checked tests cover secret/associated data, lanes/passes/memory rounding,
  legacy/versionless credentials and unsupported version denial. Go/RFC v19 tests pass.
- Verify actual explicit-v16/versionless web/API logins on linked/CLI SQLite, including
  bearer validation and unchanged service metadata. Live FerretDB reads preserve BSON
  exactly during verification. Runtime remains pure Pascal with no C library dependency.
- Out-of-band secret policy and broader Mongo session/index integration remain open.

## 2026-11-16 Argon2 v19 credential verification

- Parse Argon2d/i/id PHC v19 strings with canonical unpadded base64, unsigned decimal
  parameters and optional associated data. Reject duplicate/unknown parameters,
  malformed padding/bits, short salt/hash values, unsupported versions and oversized
  records before expensive derivation. Bound structural splitting as well as output.
- Verify Meteor Argon2 objects over the SHA256 plaintext digest and compare tags in
  constant time. Keep Argon2 precedence over bcrypt even when parsing, resource checks
  or verification fails. Preserve credential metadata and existing token binding.
- Add explicit memory/pass/lane/key verification budgets with operator environment
  overrides. Reject rather than reduce stored costs; verify a higher-memory record
  only after raising its configured budget.
- Match Go-generated PHC fixtures in normal/checked builds, including associated data,
  long UTF-8/NUL passwords, malformed/duplicate records and budget changes. Both linked
  and CLI HTTP suites pass actual Argon2 web/API login and token revocation; live
  FerretDB accounts verify without BSON changes. Bcrypt/legacy oracle tests still pass.
- Keep legacy v16/out-of-band secret policy and broader shared session/index integration
  open. New account generation remains Meteor-compatible bcrypt.

## 2026-11-16 Portable Argon2 memory processing

- Implement Argon2 v1.3 d/i/id key derivation: parameter hashing, first-block expansion,
  BlaMka mixing, dependent/independent addresses, cross-lane indexing, subsequent-pass
  XOR and final lane reduction. Process synchronized slices sequentially for portability;
  retain logical lane semantics without requiring OS worker threads.
- Preserve original memory cost in the parameter hash while rounding allocated blocks
  to the required lane/slice multiple. Include secret/associated-data inputs and explicit
  little-endian block conversion. Clear allocated blocks and temporary state on exit.
- Require caller-supplied resource limits and check them before allocation; validate
  minimum memory/salt/key sizes and platform byte-count bounds. Default kernel limits
  cover 64 MiB, 16 passes, 64 lanes and 1 KiB keys without silently reducing parameters.
- Match maintained Go source and all three published RFC 9106 tags in normal and checked
  Pascal builds. Verify memory rounding, address boundaries, multiple lanes/passes,
  binary/Unicode/NUL inputs, a 64 MiB profile, budget denial and graceful allocation failure.
  Underlying BLAKE2b/H' oracle tests pass again.
- Keep PHC credential parsing, verification policy and login integration open; Argon2
  account login remains disabled until those steps are verified.

## 2026-11-16 Portable Argon2 hash foundation

- Implement unkeyed BLAKE2b and Argon2's variable-length H' in Pascal as the hashing
  foundation for shared Argon2 credentials. Use explicit little-endian byte loading/
  output and modulo-64-bit arithmetic, with no native crypto library or assembly.
- Preserve final-block handling for empty, exact-block and partial inputs, and the
  distinct digest-size parameter and length prefix required by H'. Preallocate output
  instead of repeatedly concatenating growing hashes; clear temporary working state.
- Compare BLAKE2b with Python hashlib and H' with the actual maintained Go Argon2 helper,
  using isolated cached source copies and a temporary overlay. Verify normal/checked
  Pascal builds, binary/Unicode/NUL input, input block boundaries and variable outputs
  through 1 KiB. Invalid digest lengths are rejected.
- Keep Argon2 incomplete in TODO: memory-block filling/indexing, credential parsing,
  resource checks and login integration still remain.

## 2026-11-16 Shared-format credentials for new accounts

- Make registration and local admin bootstrap create Meteor services.password bcrypt
  objects by default, using SHA256 plaintext digests, cost 10 and independent random
  salts. Bind the initial session to the complete serialized password object.
- Change `hashpw` output to the same JSON object for direct embedding at
  services.password. Update seed instructions to avoid quoting the object as a string.
  Keep existing PBKDF2 string verification and leave stored legacy records unchanged.
- Verify new registration/bootstrap object shapes and salt independence, long UTF-8
  plaintext, CLI JSON seeding, password-change token revocation and legacy web/API
  logins against an independently generated Python PBKDF2 record. Update the token
  binding test to hash an object credential correctly.
- All HTTP regressions pass on linked SQLite and CLI SQLite, with the CLI build forced
  through portable one-use entropy. Argon2, shared Mongo session/index policy and
  application storage activation remain open.

## 2026-11-16 Portable Meteor bcrypt credentials

- Add a pure Pascal bcrypt kernel with explicit modulo-32-bit Blowfish arithmetic,
  canonical salt/hash parsing, 2a/2b/2y support and constant-time hash comparison.
  Adapt maintained Go crypto expansion/constants with their BSD license retained.
  No platform crypto library or external password service is required at runtime.
- Verify Meteor services.password JSON objects using bcrypt over the SHA256 plaintext
  digest. Retain legacy Welite PBKDF2 verification and add a fresh-salt cost-10 Meteor
  credential generator. Reject malformed/duplicate-key envelopes; a nonempty Argon2
  credential takes precedence and is denied until supported, never falling back to
  potentially stale bcrypt. Existing default account creation is unchanged in this step.
- Verify against the independent Go implementation with normal and checked Pascal
  builds: several costs, versions, Unicode/NUL/72-byte inputs, malformed hashes, long
  Meteor plaintext, fresh salts and legacy credentials. Exercise real web/API logins
  and credential-bound tokens on both SQLite backends, plus byte-preserving reads of
  an actual FerretDB account. Existing HTTP regressions pass.
- Keep Argon2, default shared-format credential creation, Meteor resume-session/index
  policy and application activation open in the interoperability checklist.

## 2026-11-16 Account uniqueness and unambiguous login

- Derive non-primary unique keys from the canonical schema and enforce them in SQL
  model insert/update triggers. Check the fully typed projection so clone sources
  cannot bypass username uniqueness. Preserve BINARY case comparison and nullable
  username behavior; refuse existing duplicates during adapter preflight.
- Use one account lookup for web/API login. Require exactly one matching username,
  counting disabled matches too, then check its enabled state. Direct Mongo duplicates
  can no longer cause an arbitrary first account to be selected.
- Verify duplicate inserts/updates/source clones, NULL/case behavior, four concurrent
  writers, duplicate-source reinstall refusal and recovery, disabled/ambiguous lookup
  denial and record preservation on both SQLite backends. Linked/CLI HTTP application
  regressions and the source-codec/extension tests pass.
- Keep Mongo index provisioning and Meteor account/session compatibility as separate
  integration work; these SQL guards do not introduce a new Mongo uniqueness policy.

## 2026-11-16 Private tokens with FerretDB user views

- Install owned private `login_tokens` and `authmeta` tables alongside document views.
  Replace the invalid foreign key to a user view with explicit token insert/update
  checks; retain the real metadata-to-token foreign key. Refuse unowned or structurally
  changed private objects rather than overwriting them.
- Remove private tokens and metadata after physical user deletion, whether initiated
  by Welite SQL or Mongo. Explicit metadata cleanup also works with foreign keys off
  on the deleting connection. Keep tokens across compatible adapter reinstallation.
- Exercise the actual token issue/validate code against both adapters: restart-safe
  validation, credential changes, missing users, SQL/Mongo deletion and cleanup with
  foreign keys off. Force a Mongo cleanup failure and verify user/token restoration.
  Codec/extension and existing SHA/HMAC/durable-token regression tests also pass.
- These remain Welite private tokens, not Meteor resume tokens. Shared password/session
  compatibility, username uniqueness and application activation are still open.

## 2026-11-16 FerretDB view references and delete cascades

- Generate root foreign-key metadata directly from the canonical schema. Reject SQL
  inserts and reference-column updates that point at missing parent models, including
  typed clone-source inserts. Preserve nullable-reference semantics.
- Reproduce declared root ON DELETE CASCADE chains through writable views: deleting a
  board removes its lanes/lists/cards/comments, with card/checklist descendants removed
  recursively. Embedded children disappear with their owning document. Retain records
  whose references are deliberately not foreign keys in the schema.
- Verify every declared root reference on insert/update against live FerretDB, optional
  NULL references, unrelated-record retention and nested cascades on both backends.
  Force a checklist-item deletion failure and compare every collection's stored SJSON
  before/after to prove rollback of the complete board deletion. Source-codec tests pass.
- These checks govern Welite SQL views; no foreign-key triggers are added to FerretDB's
  physical tables. Account uniqueness/private-token references and other compatibility
  gates remain before application activation.

## 2026-11-16 Writable FerretDB child views

- Generate thirteen child contracts from the canonical SQL schema and install writable
  views for board labels/members/groups/domains, card membership/labels/custom values/
  dependencies, custom-field boards/dropdown items and user emails. Use actual `_id`
  fields and nested paths; correct dependencies to `cardDependencies`.
- Apply one sparse patch per SQL row update, including simultaneous key/value changes.
  Preserve unknown child properties and BSON metadata. Match omitted optional dependency
  types using their defaults; reject duplicate child keys, invalid booleans, missing
  parents and parent reassignment.
- Install root and child views in one transaction, refuse unowned child tables/views,
  and retain custom child-view triggers across reinstallation.
- Verify every child view against live FerretDB on linked and CLI SQLite, SQL/Mongo
  updates in both directions, typed unknown data, failed inserts and ownership refusal.
  Source-codec tests pass again. Cascades, full typed custom-value conversion, shared
  account/file support and application activation remain open.

## 2026-11-16 Typed embedded relation editing

- Add the shared `wl_relation` SQL function for sparse insert/update/delete of embedded
  object and scalar arrays, including nested array paths. Preserve sibling order,
  unmodeled member fields and existing BSON metadata instead of rebuilding arrays
  from flattened SQL rows.
- Validate required values and booleans; reject duplicate keys, missing update/delete
  targets, unknown patch columns and malformed source arrays. Return an SQL error so
  failed statements cannot partially replace documents.
- Verify real FerretDB reads after linked/CLI relation writes, including typed nested
  dates/int64, default values, Unicode scalar keys and byte-exact BSON after denial.
  Re-run the source-codec and TEXT/JSONB tests. Child SQL views, reference constraints
  and application integration remain to be wired before interoperability is complete.

## 2026-11-16 FerretDB root document projections

- Generate eleven root-model specifications from the canonical schema and install
  writable SQL views over actual registered FerretDB collections. Discover physical
  names, create compatible metadata/indexes for missing collections, and refuse
  unowned normalized tables. Preserve physical records, indexes and custom view triggers.
- Apply sparse typed patches, preserving unknown fields, BSON types and numeric bits.
  Map nested attachment parents/WIP settings, booleans, dates and JSON columns; validate
  required values and immutable IDs. Keep clone source metadata separate from child arrays.
- Resolve TEXT/JSONB storage at write time through the host SQLite metadata API, including
  the CLI's restricted trigger environment. Keep installation atomic and repeatable.
- Verify both directions over the Mongo wire against maintained FerretDB source
  984be0e8ee59afe5d19005336b81c76d44c0e695, on linked and CLI SQLite: all roots,
  fresh collections, old TEXT/restart, exact scalar bits, unknown fields and failed-edit rollback.
- Keep this installer outside application startup until child relations, account/file
  compatibility and shared-file policy are complete. Overall interoperability remains open.

## 2026-11-16 Large SQL scripts through the CLI backend

- Remove the per-argument size ceiling before installing the FerretDB model adapter.
  Feed the SQLite shell a private `query.sql` through its structured `-init` filename
  option; user SQL and values never become process arguments. Preserve the caller's
  working directory for relative ATTACH/VACUUM paths.
- Share short temporary-directory allocation with framework uploads. On Unix, reserve
  directories as 0700 and SQL files as 0600; delete script bytes and the directory after
  success, SQL failure or failure to spawn the CLI.
- Preserve control-containing string literals as parenthesized hex-to-TEXT expressions,
  avoiding the shell's physical CRLF normalization and expression-depth limits for many
  newlines. Keep comments and quoted identifiers distinct, and reject shell dot commands
  in SQL input. Replace quadratic CSV field concatenation with a geometrically
  growing byte buffer.
- Verify megabyte inputs/outputs, 2,000 newlines, Unicode and quoted paths, multiline
  defaults, relative ATTACH paths, private modes, structured arguments and failure cleanup,
  plus typed SJSON, entropy, strict paths and existing HTTP/browser regressions.
  Model mapping remains open.

## 2026-11-16 FerretDB typed storage kernel

- Add a Pascal SJSON codec preserving BSON metadata, ordered keys, nested values and
  exact numeric literals. Explicit field hints cover new dates, int32, timestamps,
  binary subtypes and ObjectIDs. Reject malformed JSON/UTF-8/schema, duplicate keys,
  incompatible hints and out-of-range values instead of silently rounding integers.
- Register pure typed-document SQL functions in linked SQLite and expose the same code
  as an optional local CLI extension using the host API table. Failed extension loading
  blocks SQL execution. This does not yet switch application models to FerretDB storage.
- Verify actual FerretDB source encoding/decoding, all its scalar types, reordered arrays,
  Unicode/NUL text and exact double bits (including negative zero), plus transactional
  SQL-view edits of old TEXT/current JSONB records on both backends. Existing SQL, entropy,
  HTTP and no-JS/no-cookie browser workflows pass with the extension loaded.
- Keep the overall interoperability task open: collection/model mappings, shared accounts
  and files, filename policy and live application-level two-way tests remain.

## 2026-11-16 Framework upload scratch paths

- Route the FPC RTL temporary-file hook into atomically reserved short directories
  under the runtime data root. Multipart uploads retain 8.3 names and cannot race
  for a shared CGI temporary filename. A router try/finally explicitly closes and
  removes framework upload bytes and their private directories, including denied
  requests and handler failures; FPC destructors alone do not remove the files.
- Extend the runtime test to verify the framework hook ignores long system paths
  and prefixes. Re-run strict linked/CLI path and multipart HTTP/browser checks.

## 2026-11-16 Short runtime paths and offline data migration

- Store tenant databases under `files/db/wekan.db`, attachment bytes under `attachme`
  and avatars under `avatars`. Persist short domain keys in the reserved registry;
  preserve full names, aliases and IDs in SQLite. Hash full file IDs into short path
  components so case-sensitive IDs remain distinct on case-insensitive filesystems.
- Atomically allocate short temporary directories and skip pre-existing names. Add
  `WELITE_DATA` for selecting the runtime root. Refuse detected legacy layouts.
- Add `releases/pathmove.py`: copy legacy databases/bytes to a fresh verified tree,
  publish only after preparation succeeds and retain the original data unchanged.
- Add strict `WELITE_SHORT_NAMES=1` validation of `SQLITE_ENABLE_8_3_NAMES=2`, including
  actual live WAL/SHM/journal filenames. Every database client must use the same policy.
  Use one CLI initialization argument to retain query execution on SQLite 3.54.1.
- Verify durable domain keys, restart and temp collisions, migrated row/byte retention,
  unsafe migration refusal, attachment upload/download/delete and full HTTP workflows
  with linked and CLI backends. Real retro filesystem verification remains pending.

## 2026-11-16 Optional selected-card and multi-touch dragging

- Activate local vendored InteractJS on editable boards while retaining checkbox and
  arrow controls. Drag one card or its checked-card group to a visible list/lane cell.
- Support disjoint simultaneous pointer selections. Serialize drop requests and refresh
  the single-use counter/MAC from each redirected form before the next queued request.
  Use the explicit form action attribute so action buttons cannot shadow its URL.
- Extend `/board/move` with validated same-board destination cells and atomic append
  of selected cards. Preserve existing session, write permission and token checks.
- Verify target ownership/lane rejection, rollback on SQL failure and replay refusal,
  plus Chromium real-pointer selection dragging and simultaneous two-finger moves with
  cookies absent. Existing JavaScript-disabled browser flows pass independently.
  Physical touch-display and retro-browser verification remains on the platform list.

## 2026-11-16 Fail-closed native and portable entropy

- Remove the weak Random fallback from password salts and authentication tokens.
  Use OS randomness or an explicitly configured private one-use SQLite entropy stock.
- Add `welite entropy random.db [bytes]` for offline provisioning from a supported
  host. Atomic committed deletion prevents concurrent consumers from reusing blocks;
  exhaustion, missing files and database failures refuse to return entropy.
- Withhold linked SQLite RETURNING rows until SQLITE_DONE succeeds, including deferred
  foreign-key commit failures. Add busy timeouts and portable rollback-journal stocks.
- Verify Linux OS randomness and forced OS-less consumption on linked/CLI backends,
  concurrent fresh processes, private-file generation, refusal to overwrite, invalid
  and exhausted stocks, and SQL failures. Target-specific native API verification
  remains in the cross-platform checklist. Full HTTP regressions pass with native RNG;
  all no-JS/no-cookie Chromium flows also pass with OS randomness disabled and a
  fresh stock through CLI SQLite.

## 2026-11-16 Cryptographic tokens, durable binding and trusted proxies

- Replace FNV with SHA-256 token/credential digests and HMAC-SHA-256 action tokens using
  an independent server-only key and unambiguous JSON context. MAC comparisons scan all
  bytes of equal-length values. Legacy weak token records have no acceptance fallback.
- Add supplemental `authmeta` binding and tenant-scoped token digests. Durable API tokens
  survive process restart, reject copied databases/credential changes, and revoke on a
  detected credential mismatch. Web tokens used in API calls retain client/idle checks.
- Ignore forwarded IP headers by default. `WELITE_TRUSTED_PROXIES` lists exact proxy IPs;
  validation walks the forwarded chain from the nearest trusted hop and normalizes IPs.
- Verified SHA/HMAC against independent Python/RFC 4231 vectors, source-wide weak-hash
  guards, proxy spoof/chain cases, fresh-process persistence and credential/tenant binding,
  plus live MAC tamper/client checks and all no-JS/no-cookie browser flows on both backends.
- Existing sessions require fresh sign-in after the digest change. Portable entropy is
  still tracked separately because the previous non-Unix `Random` fallback remains.

## 2026-11-16 Disabled-account revocation and session integrity

- Refuse disabled accounts at web/API sign-in and every token lookup. Disabling through
  People revokes durable tokens in the same transaction as the flag; re-enable keeps those
  tokens revoked. Login token persistence failures return an error instead of false success.
- Bind web metadata to the exact database, persisted user/username and password-hash
  marker; failed validation returns an empty identity. JSON metadata preserves Unicode and
  delimiter characters, and fresh login nonces replace username/time-derived session IDs.
- Lock metadata validation/counter consumption so concurrent submissions cannot reuse a
  mutation token or overwrite a newer counter. Enforce a 30-minute idle timeout (override
  `WELITE_SESSION_IDLE` in seconds), revoking expired web tokens; compare timestamps in UTC.
- Verified disabled login/live-token denial, actual panel revocation/re-enable, fresh login
  and forced persistence failures over HTTP. Native tests cover copied DB/token IDs,
  credential/client binding, empty failure identity, 16 competing token consumers and idle
  expiry with both SQLite backends.
- The audit also identified remaining FNV hashes/MACs, retro entropy fallback and API
  credential/tenant/proxy binding work. These remain explicit TODOs; this step does not
  claim to finish cryptographic or all-platform authentication hardening.

## 2026-11-16 Validate API relation IDs and author attribution

- Validate card label/member/assignee collections before creation or edits. Labels must
  belong to the board; user targets must be enabled active board members. Arrays and
  comma-separated strings support deduplication and explicit clearing.
- Apply card text/relations in one transaction and report write failures. Invalid mixed
  collections or SQL errors leave both existing cards and attempted new cards unchanged.
- Validate path-based member/assignee additions too; deletion remains available to remove
  stale associations. Ordinary editors can attribute cards/comments to themselves; tenant
  admins may explicitly attribute them to an enabled member of the same board.
- Reject malformed/non-object JSON before API writes. Verified foreign/missing/disabled/
  inactive targets, author forgery, clear/dedup formats, malformed JSON and forced SQL
  failures against both SQLite backends. Disabled-login/session audit remains in TODO.

## 2026-11-16 Deep selected-item cloning

- Enable Clone for selected cards, lists and swimlanes. Coalesce overlapping selections,
  copy their content/descendants, and remap list/lane/parent/checklist/comment/cover and
  internal dependency IDs while retaining shared board labels, fields and external targets.
- Append copied items deterministically, assign new card numbers, and record clone events
  under the acting user. Historical activities stay with the original entities.
- Copy filesystem attachment bytes before one database transaction; missing files,
  unsupported storage backends or SQL failures remove prepared copies and leave original
  rows/bytes unchanged. Existing filesystem targets are never deliberately overwritten.
- Initialize UTF-8 conversion explicitly: the host's unset Pascal codepage was turning
  non-ASCII JSON strings into question marks. Cloning/import regressions now pin Unicode
  fidelity, with embedded NUL text preserved through SQL hex literals when needed.
- Verified mixed/card/list/swimlane clone variants, child IDs, shared references, covers,
  original row preservation, byte copies, replay rejection and file/SQL rollback. HTTP and
  Chromium Clone workflows pass with JS/cookies disabled on both SQLite backends.

## 2026-11-16 Selected-item editing, deletion, clearing and export

- Enable selected-item Edit/Save forms for swimlane/list/card titles and colors, plus card
  descriptions. Validate the complete form before one transactional update; failed SQL
  rolls back all selected edits.
- Add explicit Delete confirmation, then remove selected containers, descendant cards,
  child records, activities and attachment metadata transactionally. Unlink filesystem
  attachment bytes only after commit, so rollback never removes live attachment content.
- Add Clear (including stale selections) and `select.jsn` export of selected entities,
  related records and base64 filesystem attachment content. Account/token data is excluded.
- Read-only downloads retain the visible form's token, allowing the next no-JS action;
  mutations still consume it. Mixed-case selection names now use the same ownership policy
  as movement, closing an authorization/selection parsing mismatch.
- Verified HTTP data/bytes, descendant cleanup, bad fields and forced edit/delete failures,
  plus Chromium Edit/Save/Export/Clear/Delete workflows with JS/cookies disabled on both
  SQLite backends. Deep Clone remains a separate unfinished TODO and stays hidden.

## 2026-11-16 Atomic, validated Designer imports

- Share page/widget validation and span rules between forms and imports. Decode and
  validate all content before replacing existing pages, then execute one transaction.
- ZIP imports validate every page, duplicate URLs, entry names and the manifest before
  committing the whole bundle. A malformed page or SQL error leaves every old page intact;
  ZIP entry streams never fall back to filesystem extraction.
- Add working no-JS upload/export forms and authenticated raw JSON imports using the
  same action token in `X-Welite-Action`, `X-Welite-Counter`, `X-Welite-Hash` headers.
- Export disabled pages too; use `page.wlp`, `pages.zip`, and numbered DOS 8.3 bundle entries.
- Verified invalid models, traversal/duplicate/manifest errors, token replay and forced SQL
  failures (including failure on the second ZIP page) without database changes. JSON/ZIP
  browser upload/download and round trips pass with JS/cookies disabled on both backends.

## 2026-11-16 Render Designer spans and cell ordering

- Render row/column spans once in published and editor grids, suppressing covered cells
  and using the same logical rectangles for LTR/RTL. Reject overlapping spans during
  widget save/move and inconsistent spans among widgets sharing an anchor cell.
- Add Sort up/down buttons that reorder widgets inside their cell transactionally,
  normalizing sort positions so tied values also have deterministic ordering.
- Emit required attributes and visible required markers for input widgets. Browsers
  without native constraint validation still show the marker; endpoints retain their
  own validation responsibilities.
- Honor explicit page direction and avoid double-mirroring in modern browsers by fixing
  the grid's physical direction while retaining per-cell text direction.
- Verified HTTP span/overlap/required/sort/direction cases and Chromium physical RTL,
  spanning cells and sort-button submissions with JS/cookies disabled on both backends.

## 2026-11-16 Separate Global Admin and domain administration

- Reserve the central domain registry for administrators authenticated in `data/admin`;
  administrators of `local` and served domains retain only their own People/Designer panels.
  Navigation and role labels now distinguish Global Admin from Domain Global Admin.
- Add local `welite initadmin <username>` bootstrap using `WELITE_ADMIN_PASSWORD`, refusing
  repeat initialization. Public registration never creates accounts in the reserved tenant.
- Provision new registered domains explicitly, applying the portable schema transactionally
  even when the registry DB already exists. Reject reserved/malformed domain names and
  match loopback hosts exactly instead of accepting attacker-controlled substrings.
- Verified local bootstrap, tenant/session separation, domain creation, disable/enable,
  malformed names and spoofed loopback hosts against both linked and CLI SQLite servers.
  Operational instructions are in `docs/admin.md`.

## 2026-11-16 Verify fresh linked and CLI server installations

- Keep SQL beginning with `--` comments from being parsed as SQLite command-line options;
  this fixes automatic schema provisioning and first registration on the CLI backend.
- Added the leading-comment regression and a `WELITE_DB_CLI=1` HTTP/browser test mode.
  The valid-card ownership assertion now follows the card's actual list after UI movement.
- Verified fresh linked and CLI installations through registration, Designer page/widget
  forms, board rendering/movement/minimap and 29 rejected API ownership attempts. Both
  Chromium runs disable JavaScript and cookies; all accumulated Pascal DB/move/role tests pass.

## 2026-11-16 Enforce API resource ownership

- Added a shared child-resource chain check after board authorization: swimlane/list/card,
  checklist/item/comment and custom-field IDs must belong to the board and parents named
  in the route, including when the caller is a site administrator.
- Validate card/attachment upload parents before writes. Board-scoped list/swimlane card
  queries, counts and deletes also constrain boardId, protecting against inconsistent
  legacy child rows.
- Verified 29 forged-resource requests across endpoint families return rejection without
  any database change, while the valid card remains readable. Added source-wide guard
  coverage so another child endpoint cannot silently omit ownership checks.
- Body label/member/assignee/author validation and disabled-login/session behavior remain
  explicit follow-up steps in TODO.

## 2026-11-16 Board minimap and coordinate navigation

- Added a top-right, server-rendered minimap with occupied/empty markers, a yellow
  current position and X/Y coordinates. Each cell is a session-preserving navigation link.
- Board pages default to one list in one swimlane for small-screen/retro use; view arrows
  change that window and View all restores the full-board selection surface.
- Clamp coordinates to existing rows/columns and preserve the viewport on form submission.
- Verified map links, occupancy changes after moves, highlight, out-of-range coordinates
  and all-items view. Chromium tests pass at widths 320/768/1920 with no horizontal
  overflow in the fixture, with JavaScript and cookies disabled. Retro devices still
  require the platform-specific checks listed in TODO.

## 2026-11-16 Authorized board views and no-JS card movement

- Added real board links on the home page and registered Designer board/board-list
  dataviews. Board pages render active swimlanes, lists and cards with escaped text.
- Full editors receive one selection form with board ID, action token, return path and
  shared arrow controls. Other viewers see board data without mutation controls.
- Scope neighbor/card-list queries to the board and swimlane, include legacy shared
  lists, and deduplicate repeated selections. RTL board pages reverse list columns.
- Verified HTTP visibility/controls and Chromium selection-to-right-arrow card movement
  with JavaScript and cookies disabled, including the resulting persisted list ID.
- Unfinished action buttons remain hidden until their handlers are implemented. Minimap,
  responsive retro color verification and optional drag/drop remain separate TODO steps.

## 2026-11-16 Shared board permissions and move selection isolation

- Added shared board read/write checks used by UI visibility, move authorization and
  API board guards. Private boards require active membership; full-board mutations
  exclude read-only, comment-only, assignment-limited and worker roles.
- Move requests require a validated session and an explicit board; every selected card,
  list and swimlane must exist, be active and belong to that board before any mutation.
- Restrict move return URLs to local paths and prevent anonymous home-page disclosure
  of private board titles. Unknown/archived boards and disabled admins cannot write.
- Verified both SQLite backends against a role/selection/redirect matrix and live API
  editor/read-only/comment-only requests. Separate API child-ID scoping remains in TODO.

## 2026-11-16 Reliable CLI SQLite results and errors

- Use FreePascal's process runner to drain stdout/stderr while SQLite runs and check
  its exit code. Syntax, constraint and foreign-key failures now return false.
- Use SQLite CSV output instead of splitting on pipes/newlines; preserve quoted commas,
  pipes, quotes, UTF-8 and embedded CRLF/LF while retaining empty/NULL text semantics.
- Verified both SQLite backends with executable Pascal text/error regressions and a
  5,000-row result larger than pipe capacity. Existing move and Designer HTTP tests pass.
- Reference: SQLite CLI output modes (`https://www.sqlite.org/cli.html`) and the
  FreePascal `TProcess`/`RunCommand` implementation in the installed FCL sources.

## 2026-11-16 Working Designer widget editor

- Added full no-JS widget forms and persisted creation, updates and deletion, with
  administrator gates, matching action tokens and session-preserving editor redirects.
- Validate widget types, JSON options, finite sort values, colors, local targets and
  row/column/span bounds; reject moving a widget between unrelated pages.
- Move controls derive the owning page from the widget and clamp to its column and row
  limits. Select widgets render escaped option labels/values and the selected value.
- Verified widget operations, negative inputs and movement bounds over HTTP and through
  Chromium with JavaScript and cookies disabled. Recorded separate remaining work for
  published spans/required inputs, cell-sort arrows, import validation and CLI DB fidelity.

## 2026-11-16 Working Designer page management

- Added page listing, creation, editing by ID (including disabled pages), enable/disable
  and deletion with cascading widget removal, using plain forms and action tokens.
- Provision Designer tables on first administrator access without replacing existing
  pages; schema statements are idempotent. `WELITE_DESIGNER` overrides `src/designer.sql`.
- Validate local URLs, reserved routes, columns, document type, direction and access role;
  reject duplicate URLs and column changes that would hide widgets. Published admin pages
  now require the actual administrator role; invalid sessions cannot retain page access.
- Verified page workflows, invalid inputs, authorization and deletion over HTTP, plus
  Chromium form create/edit/disable/enable/delete with JavaScript and cookies disabled.

## 2026-11-16 Require administrator permissions throughout Designer

- Guarded every Designer listing, editor, import and export endpoint with the shared
  tenant-local administrator gate. Mutations also require their action token.
- The gate now checks session validation's Boolean result, so revoked tokens and wrong
  client bindings cannot reuse residual session fields. Disabled users cannot administer.
- Verified all eight endpoints over HTTP with no cookies: anonymous, normal user,
  invalid session, mismatched client, administrator, missing action token, demotion,
  disabled account and revoked token cases (`tests/admin.py`).
- Recorded the remaining distinction between reserved-host Global Admin domain management
  and tenant-local administration in `TODO.md`; this step only secures Designer access.

## 2026-11-16 Move lists across swimlanes

- Implemented up/down list movement to adjacent active swimlanes on the same board,
  appending after existing lists and moving all list cards, including archived cards.
- List/card updates share one transaction in both SQLite backends. Boundary, archived,
  missing and legacy lists remain unchanged; other-board cards cannot be reparented.
- Verified executable Pascal regressions with `tests/movelist.py`, using the canonical
  schema and both linked and CLI SQLite backends, including multi-list movement.

## 2026-11-16 Implementation audit and remaining steps

- Added a sequential, testable implementation checklist to `TODO.md`, preserving the
  original design requirements and distinguishing existing code from remaining work.
- Confirmed password hashing already exists; identified unfinished board rendering,
  Designer handlers/permissions, move actions, minimap and progressive enhancement.
- Removed the duplicate repository instruction file; parent repository instructions
  apply here, while the existing build layout and DOS 8.3 rules remain documented below.

## 2026-06-25 Local tenant, registration / Global Admin, Admin Panel, build layout

First-run usability: browsing `http://localhost:5500/` used to answer `404 Unknown domain`
because `localhost` matched no registered domain. Added a built-in tenant, an account/registration
flow, a Global Admin Panel, and reorganized the build output. Verified on FreePascal 3.2.3 (aarch64).

- **Built-in `local` tenant** (`wltenant`): loopback hosts (`localhost`, `127.0.0.1`, `::1`) now
  resolve to a `local` tenant stored at `data/local/` (`db/data.db`, `files/attachments`,
  `files/avatars`), auto-provisioned on first request from `src/schema.sql` (override with
  `WELITE_SCHEMA`). The reserved `admin` registry dir is also created up front so a fresh checkout
  just works; unknown domains still 404 with no fallback.
- **Registration + first-user Global Admin** (`wlhttp.lpr`): `GET /` redirects to `/sign-in` when
  the tenant has no users; new `/register` page (no-JS/no-cookie) creates an account, the **first**
  account in a tenant becomes the Global Admin (`users.isAdmin=1`) and the rest are Normal users.
  Sign-in/home pages cross-link to register; passwords hashed via the existing PBKDF2 path.
- **Global Admin Panel** (new `wladmin` unit): gated to `users.isAdmin=1` (404/redirect/403 as
  appropriate) with three sections — **Domains** (registry add / enable / disable, via new
  `wlregist.RegistryListDomains`), **Designer** (links to the existing `/designer`), and **People**
  (promote/demote Global Admin, enable/disable login; cannot self-demote or self-lock-out). Same
  action-token + PRG contract as the rest of the app.
- **Build output layout** (`build.sh`/`build.bat`/`build.ami`): each target now builds into
  `build/arch/<code>/` (executable + `.o`/`.ppu`/link intermediates via `fpc -FU -FE`), then copies
  the executable to `build/bin/w<code>.exe` — a `w` prefix plus a ≤7-char platform code
  (`wlinx64.exe`, `wdos.exe`, `wami68k.exe`, …) so every path component stays ≤8 chars and the
  binaries are unique in one directory. "Build current platform" → `build/bin/wcurrent.exe`.
- **Cross-compiler installer** (`build.sh` menu option 4, Ubuntu/Debian amd64/arm64): apt can't
  provide FPC cross-compilers (none packaged, `fpc-source` is stripped of the build Makefiles,
  exotic OSes have no Ubuntu binutils), so this uses
  [fpcupdeluxe](https://github.com/LongDirtyAnimAlf/fpcupdeluxe). Preferred path: apt-install
  Lazarus (`lazbuild` + nogui LCL), build fpcupdeluxe's real headless console tool `fpclazup`
  (`LCLWidgetType=nogui`, forced to the host CPU/OS), then run it to build the FPC compiler + cross
  compiler/binutils per target — Amiga/AROS/MorphOS/Haiku/macOS as well as Linux/Windows/DOS — and
  point the session `FPC` at the result. Getting this working on Ubuntu 26.04 needed several
  pieces, all handled automatically: seed the bootstrap compiler from the system FPC; `--disablejobs`
  (the parallel RTL build races); `--fpcVersion=fixes-3.2` (FPC 3.2.2 doesn't link on glibc ≥2.34,
  which removed `__libc_csu_init/_fini`); `--only=FPC` (skip Lazarus/LCLCross); and treat "a working
  `fpc` binary exists" as success rather than fpclazup's exit code. `do_build` also exports
  `PPC_CONFIG_PATH` next to the chosen `FPC` so the fpcupdeluxe `fpc.cfg`/units are used (the static
  compiler otherwise falls back to the system `/etc/fpc.cfg`). If the build path can't be set up it
  falls back to launching the fpcupdeluxe GUI. The install dir is kept outside the repo
  (default `~/fpcupdeluxe`); fpcupdeluxe derives its basedir from the working dir and aborts if that
  is inside another git repo. Verbose log to `build/log/xtools.log`, per-target pass/fail.
- **Cross-target sweep + per-target flags**: swept all 18 cross targets (install cross FPC, then
  cross-build welite) on an aarch64 host. Working there: `x86_64-linux`, `arm-linux`, `i386-win32`,
  `x86_64-win64` (plus native `aarch64-linux`); the rest fail because fpcupdeluxe ships no
  aarch64-host cross-binutils/libs for them (they work from an x86_64 host). welite's default build
  links `libsqlite3`, which can't be cross-linked, so every non-Windows `PLATFORMS` entry now carries
  `-dWLDB_CLI` (external `sqlite3`, links nothing); Windows keeps the linked default (runtime DLL).
  armhf/armv7's hard-float flags clash with fpcupdeluxe's soft-float arm RTL ("different FPU mode").
  Each `PLATFORMS` row is annotated with its host requirement; "Build for current platform" still
  builds the native linked-SQLite default.
- **`CLAUDE.md`**: documents the DOS 8.3 filename rule (≤8-char names, ≤3-char extensions, safe
  charset, tooling exceptions) with an audit snippet, plus the build-output layout. Audited the
  tracked tree: zero 8.3 violations outside host tooling (`.gitignore`, `.tx/`).

## 2026-06-25 WeKan-Lite — `welite` rename, DOS 8.3 names, build scripts

Renamed the repo/binary to `welite` and made the whole tree DOS 8.3-safe (≤8-char names,
≤3-char extensions, one dot) so the sources copy onto a FAT filesystem and compile there.

- Added cross-platform build scripts at the repo root — `build.sh` (bash), `build.bat`
  (cmd.exe), `build.ami` (AmigaDOS) — each a 4-item menu (current platform / all / select /
  quit) that builds `src/wlhttp.lpr` with FreePascal for Linux amd64/arm64/armhf/armv7/s390x/
  ppc/ppc64le, macOS arm64, Windows x86/amd64, DOS (go32v2), Haiku, Amiga m68k, AmigaOS 4.1 PPC,
  MorphOS, and AROS x86/amd64/arm64/m68k/ppc. Output to `build/` (gitignored).
- Rebrand `wekanlite` → `welite`: binary name (also fixes its own 8.3 overflow, 9→6 chars),
  env vars `WEKANLITE_*` → `WELITE_*`, repo URL, `.gitignore`, and the designer export JSON keys
  (`welite_page` / `welite_pages`). The human product name **WeKan-Lite** is unchanged.
- 8.3 source renames (FPC unit name = filename): `wlbrowser`→`wlbrowse`, `wldesigner`→`wldesign`,
  `wlenhance`→`wlenhanc`, `wlpassword`→`wlpasswd`, `wlregistry`→`wlregist`,
  `designer-schema.sql`→`designer.sql`; designer export ext `.wlpage`→`.wlp`, zip index
  `manifest.json`→`manifest.jsn`; the glue script `wl-multidrag.js`→`wlmdrag.js`.
- 8.3 docs: `architecture`→`arch`, `sqlite-access-decision`→`sqlite`, `move-component`→`move`,
  `progressive-enhancement`→`enhance`, `static-assets`→`static`, `schema-decision`→`schema`,
  `web-stack-decision`→`webstack`; `CHANGELOG.md`→`CHANGES.md`; dirs `docs/multidrag`→`docs/mdrag`,
  `docs/roundcard`→`docs/round` (`.html`→`.htm`, `round-blue.gif`→`rndblue.gif`).
- 8.3 helper scripts: `genassets.py`→`genasset.py`, `convert-languages.py`→`convlang.py`,
  `changelog.sh`→`chglog.sh`, `releases/translations/`→`releases/xlate/`
  (`push-translation.sh`→`txpush.sh`, etc.).
- 8.3 translations: `i18n/languages.json`→`i18n/langs.jsn`; all 154 `i18n/data/<tag>.i18n.json`
  → `<tag>.jsn` (`ca@valencia`→`cavalenc.jsn`); updated the import index, `.tx/config`, and the
  `.jsn` MIME mapping in `wlstatic`.
- 8.3 static assets: `public/windows11/`→`public/win11/` (tiles renumbered `w001..w080`),
  `public/font/notification/`→`.../notif/`, `wekan.html`→`wekan.htm`,
  `interact-bottom.js`→`interbot.js`, `site.webmanifest.default`→`manifest.def`, and ~120
  favicon/PWA icons given short names; `manifest.def` (the PWA manifest) rewritten to match.
- Verified on FreePascal 3.2.3 (aarch64): builds clean, repo-wide 8.3 check passes, and the
  server serves the renamed URLs (`/i18n/langs.jsn`, `/i18n/data/en.jsn`, `/win11/w001.png`,
  `/js/interbot.js`, `/manifest.def`). DOS cross-compile additionally needs the FPC i386/go32v2
  cross build installed.

## 2026-06-25 WeKan-Lite — minimal `welite` repo

Split WeKan-Lite into its own minimal repo, https://github.com/wekan/welite (only the
required files), out of the old `wami2` tree where it lived under `freepascal/`.

- Moved the `freepascal/` contents to the repo root: FreePascal units, `wlhttp.lpr`, and the
  `*.sql` schemas now live in `src/`; design docs in `docs/`; static assets in `public/`.
- Split translations into their own tree: `public/i18n/` → `i18n/data/`, and
  `public/langs.jsn` → `i18n/langs.jsn`. `wlstatic` now serves `i18n/` as a second
  static root mounted at `/i18n` (`StaticAddRoot`), and `releases/genasset.py` embeds both the
  `public/` and `i18n/` trees, so translation URLs stay stable in disk and single-binary builds.
- Moved the build/release helper scripts under `releases/`: `genasset.py` (embed
  `public/` + `i18n/`) and `convlang.py` (regenerate `i18n/langs.jsn` from the
  sibling `../wekan` repo's `imports/i18n/languages.js`).
- Updated every cross-reference path to the new layout: `README.md`, `docs/*.md`, the FPC unit
  comments, `.tx/config` (`i18n/data/<lang>.jsn`), and the helper scripts' defaults.
- Refreshed `.gitignore` for the new binary name (`/welite`), the runtime `/data/` tree, and
  the generated embed artifacts (`src/wlassets.pas`, `src/wlpublic.{rc,res}`, `*.o` / `*.ppu`).
- Verified on FreePascal 3.2.3 (aarch64): the tree builds, and the server serves both roots —
  `/robots.txt` (public) and `/i18n/langs.jsn` + `/i18n/data/en.jsn` (translations).

## 2026-06-25 WeKan-Lite FreePascal — v0.1

First skeleton of the FreePascal backend. Compiles and links on FreePascal 3.2.3 (aarch64),
both the linked-SQLite and `-dWLDB_CLI` backends; the server runs, resolves tenants by Host,
and renders a board page from SQLite.

### Updates

- Reorganized the tree: design docs live in `freepascal/docs/`, the FreePascal code and
  `schema.sql` / `designer.sql` / `README.md` at `freepascal/`, and the [`wami/`](https://github.com/wekan/wami), [`omi/`](https://github.com/wekan/omi),
  [`tcl-tk-kanban/`](https://github.com/wekan/tcl-tk-kanban), [`minio-metadata/`](https://github.com/wekan/minio-metadata) prototypes alongside them.
- Updated every cross-reference path to match the new layout — `README.md` (docs → `docs/`,
  prototypes → siblings), `docs/*.md` (co-located docs lose `../`, prototypes/`schema.sql`
  keep `../`), and code comments (prototypes → siblings, design docs → `docs/`).
- Verified the whole unit set still builds on FreePascal 3.2.3 after the move.
- Documented SQLite on Amiga/retro targets (`docs/sqlite.md`): FreePascal
  bundles no SQLite (its `sqlite3` unit is only bindings); Amiga/MorphOS/AROS have none, so
  statically link the official amalgamation (no Aminet port needed), with retro build notes.

### Features

- Architecture & stack (`wlhttp.lpr`, `docs/arch.md`): `fphttpapp` + `httproute`
  (RTL-only, no C deps), tenant → auth → endpoint request lifecycle, HTML 3.2 baseline +
  HTML 4 enhancement tiers.
- Multitenancy (`wltenant.pas`, `wlregist.pas`, `docs/goals.md`): one binary serves many
  domains; `Host:` → `data/domains/<domain>/db/data.db` (unknown host → 404, no fallback);
  reserved `data/admin/` Global Admin tenant + per-domain Domain Global Admin; central TLS
  certs in `data/certs/<host>/`; per-operation scratch in `data/temp/YYYY-MM-DD_MM-SS_COUNTER/`.
- Authentication (`wlauth.pas`): no-cookie / no-JS sessions (session id in URL + hidden fields)
  with replay- and context-bound per-action tokens and idle timeout, persisted to
  `schema.sql` `login_tokens`.
- Database (`wldb.pas`, `docs/sqlite.md`): SQLite behind one interface — linked
  SQLite (default single binary) or the external `sqlite3` CLI (`-dWLDB_CLI` bootstrap).
- Schema & import (`schema.sql`, `docs/schema.md`): canonical 24-table schema;
  Kanboard SQLite (incl. BigBoard) and Meteor WeKan Mongo data imported into it.
- Designer (`wldesign.pas`, `designer.sql`, `docs/designer.md`): data-driven pages
  (page + widgets) with a no-JS/no-cookie form editor, custom URLs, seeded editable built-ins,
  LTR/RTL mirrored from one definition, and import/export (`.wlp` JSON, all pages as `.zip`).
- Table component (`wldesign.pas`): reusable no-JS data table — search, "Page n / m"
  pagination, column-visibility chooser, click-a-cell-to-edit — all stateless in the URL.
- Colors & theming (`wlcolors.pas`, `docs/theming.md`): WeKan named colors or any hex on any
  element; selectable picker components (hex / named / swatches / native wheel / web-safe grid);
  imported Trello/Kanboard palettes mapped to WeKan colors.
- Vector graphics (`wlvector.pas`): Red Strings render as SVG (modern/NetSurf), VML (old IE),
  or ASCII arrows (IBrowse/Dillo/Lynx).
- Progressive enhancement (`wlenhanc.pas`, `docs/enhance.md`): no-JS form
  baseline always works; MultiDrag (from [`wami/public/multidrag`](https://github.com/wekan/wami/tree/main/public/multidrag)) auto-activates with JS+touch
  to drag many cards at once on a big touch screen, driving the same endpoints.
- Combined move component (`wlmove.pas`, `docs/move.md`): one no-JS arrows keypad
  (▲◀▼▶) moves all selected swimlanes/lists/cards via `POST /board/move` (reorder/relocate over
  `sort` / `listId` / `swimlaneId`), modeled on the combined [`tcl-tk-kanban/kanban.go`](https://github.com/wekan/tcl-tk-kanban/blob/main/kanban.go).
- Static assets (`wlstatic.pas`, `docs/static.md`): serve `public/` at a configurable URL
  (default '/'), plus the `i18n/` translations tree at `/i18n` (`i18n/langs.jsn` +
  `i18n/data/`); embedded in the binary (`-dWLEMBED`, FPC resources via `releases/genasset.py`)
  or from disk; `releases/convlang.py` regenerates `i18n/langs.jsn`.
- REST API (`wlapi.pas`, `docs/api.md`): subset of `public/api/wekan.yml` with Bearer-token auth
  (`POST /users/login` + `Authorization: Bearer`), so WeKan's Python CLI `api.py` works unchanged
  — verified login → board/swimlanes/lists → createlist → addcard → cardsbyswimlane on FPC 3.2.3.
- REST API — card editing & counts (`wlapi.pas`): `PUT .../cards/:cardId`
  (title/description/color, and `labelIds` → `card_labels`), `GET .../lists/:listId/cards`, and
  `.../cards_count` / board `.../cards_count`. Verified via api.py `editcard` / `editcardcolor`
  / `get_list_cards_count` / `get_board_cards_count`.
- REST API — board title & copy (`wlapi.pas`): `PUT .../boards/:boardId/title`;
  `POST .../boards/:boardId/copy` structural deep copy (board + members + swimlanes + lists +
  cards, ids remapped). Verified via api.py `editboardtitle` / `copyboard`.
- REST API — board labels (`wlapi.pas`): `PUT .../boards/:boardId/labels` creates a label
  (nested `{label:{color,name}}` body) → `board_labels`; adding a label to a card already works
  via the card `PUT labelIds`. Verified via api.py `createlabel`.
- REST API — checklists (`wlapi.pas`): `GET`/`POST .../cards/:cardId/checklists`,
  `GET .../checklists/:checklistId` (with items), `POST .../checklists/:checklistId/items`.
  Verified via api.py `addchecklist` (title + items) and `checklistid`.
- REST API — card comments (`wlapi.pas`): `GET`/`POST .../cards/:cardId/comments`,
  `GET`/`DELETE .../comments/:commentId` → `card_comments`. Verified: post comment → `{_id}`,
  list returns it.
- REST API — create swimlane + delete operations (`wlapi.pas`): `POST .../swimlanes`, and
  `DELETE` board / swimlane / list / card. Children cascade via FK (board→swimlanes/lists/cards
  →card children; list/swimlane remove their cards first). Verified: delete card removed its
  comment, delete board removed its lists+cards.
- REST API — card members & assignees (`wlapi.pas`): `POST`/`DELETE .../cards/:cardId/members/:member`
  and `.../assignees/:assignee` → `card_members` / `card_assignees`; the card JSON now includes
  `members` and `assignees`. Verified: add/remove reflected in the returned card.
- REST API — custom fields (`wlapi.pas`): `GET`/`POST .../boards/:boardId/custom-fields`,
  `GET .../custom-fields/:customField`, and `POST .../cards/:cardId/customFields/:customField`
  (set card value → `card_custom_field_values`). Verified via curl: create → list → get → set
  value. (api.py's own `addcustomfieldtoboard` has a `json.loads('')` bug on empty settings.)
- REST API — card JSON now includes `customFields` (`[{_id,value}]`) alongside `labelIds`,
  `members`, `assignees`. Verified: getcard returns the set custom-field value.
- REST API — attachments (`wlapi.pas`, new `attachments` table in `schema.sql`): `POST
  /api/attachment/upload` (JSON + base64), `GET .../download/:id`, `.../info/:id`,
  `DELETE .../delete/:id`, and `GET /api/boards/:boardId/attachments`. Bytes are stored on disk
  in `data/domains/<domain>/files/attachments/<id>` (`storageBackend: filesystem`). Verified
  end-to-end via api.py: upload → info → download (base64 round-trip) → list → delete (row + file
  removed).
- REST API — list card attachments (`wlapi.pas`): `GET /api/attachment/list/:b/:s/:l/:cardId`
  returns `{success, attachments:[{attachmentId,fileName,fileType,fileSize,…}]}`. Verified via
  api.py `listcardattachments`.
- REST API — checklist items (`wlapi.pas`): `GET`/`PUT`/`DELETE
  .../checklists/:checklistId/items/:item`; PUT toggles `isFinished` and/or edits the title.
  Verified: get (false) → toggle (true) → delete.
- REST API — card archive (`wlapi.pas`): `POST .../cards/:cardId/archive` sets `archived=1`
  (+`archivedAt`); body `isArchive=false` unarchives. Verified: archive → 1, unarchive → 0.

### Security

- Password hashing (`wlpasswd.pas`): real PBKDF2-HMAC-SHA1 (RTL-only, salt from
  `/dev/urandom`) replaces the placeholder "any non-empty password". The stored hash lives in
  `users.services_json.password`; web sign-in and API `POST /users/login` both verify it, and
  accounts without a real hash can't be logged into. Seed/set with `welite hashpw <plain>`.
  Verified: correct password → token, wrong/empty → 401.
- Authorization (`wlapi.pas` `ApiAuthBoard`): board-scoped API endpoints now require the token's
  user to be an active `board_members` row (writes blocked for `isReadOnly`); public boards are
  read-only to non-members; site admins (`users.isAdmin`) bypass; `/api/users` is admin-only,
  `/api/users/:id/boards` self-or-admin. Verified: member read private → 200, outsider → 403,
  outsider write (even public) → 403, public read → 200.

### Fixes

- `wldesign.pas`: replaced an SQL-style `--` comment inside a Pascal record (compile error
  "END expected but - found") with a `//` comment.
- `wldesign.pas` zip import: `TUnZipper.UnZipAllFiles(stream)` is not available in
  FreePascal 3.2.x — spool the uploaded archive into a per-operation `data/temp/` dir and unzip
  via `UnZipper.FileName`, removing the dir afterwards.
- `docs/contract.md`: reverted a path-rewrite false positive — the prose "([wami](https://github.com/wekan/wami)/[omi](https://github.com/wekan/omi))
  reimplementation" was turned into a `../wami/omi` path and is now restored.
- `wldb.pas`: `journal_mode` is now `DELETE` under `{$IF DEFINED(AMIGA) or MORPHOS or AROS}`
  (WAL needs shared-memory/mmap that classic Amiga filesystems lack), WAL elsewhere.
- `wlhttp.lpr`: call `Randomize` at startup — without it `NewId` (api/designer) produced the
  same id sequence on every run, so restarts collided on board/list/card ids.
- `wlhttp.lpr`: dropped `cmem` — FPC's `hmac` unit (used by password hashing) corrupts the heap
  under `cmem` ("free(): invalid pointer"); the default FPC memory manager is already
  thread-safe, so `cmem` was unnecessary.
- `wldb.pas` (CLI backend): pass `-cmd "PRAGMA foreign_keys=ON"` to `sqlite3` so `ON DELETE
  CASCADE` fires (the CLI opens each connection with foreign keys off by default).

### Known TODO (carried forward)

Board/list `dataview` renderers; `wlmdrag.js`; password hashing into
`users.services_json`; Domain-Global-Admin role checks; list↕-across-swimlanes and the
Edit/Clone/Delete/Export move actions.
