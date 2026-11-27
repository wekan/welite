# ChangeLog

WeKan-Lite — the FreePascal reimplementation of WeKan: one native binary, SQLite-only, no-JS /
no-cookie capable, runs where Meteor cannot (Amiga 68k/PPC, MorphOS, AROS, Haiku, BSD, …).
Distilled from the [`wami/`](https://github.com/wekan/wami) and [`omi/`](https://github.com/wekan/omi) prototypes against the portable contract in `docs/`.

## HTML5 mobile board navigation

- Download the board as an Excel workbook. Card details presents each card
  as labeled values, and the table layout puts one card on each row. Both
  use the selected field groups from the Export menu. The API can limit
  either layout to a swimlane, list, card, or the card containing a checklist.
  Both layouts wrap long values and style headings. The table freezes its
  header row, and the card layout gives values a wider column. Selecting
  Activity adds a worksheet with comments on the exported cards. The Export
  menu now offers Board and Activities for Excel. Board includes the whole
  board’s description, members and timestamps in the card layout or on a
  separate Board worksheet in the table layout. In the card layout, each
  card can include its checklists with item completion, comments, and
  attachment names. A checklist scope includes only that checklist. The
  card layout also shows same-board subtasks with their completion state,
  and includes the comment author and creation time when available.
  Planning Poker exports the question and estimate. Stickers export their
  names, and locations export their names, addresses and coordinates.
  Attachments include file type, byte size, upload time and uploader when
  available. Dependencies identify live cards on the same board and show
  their relationship type. The card layout groups cards under swimlane and
  list headings in board order. Swimlane and list exports start at that
  level, and a card scope omits the group headings. The card layout uses
  A4 portrait printing with page breaks between card blocks.

- Export a whole board as a WeKan ZIP from the board menu. The archive
  stores wekan.json and local attachment files separately, with duplicate
  filenames numbered. The API also supports metadata-only ZIP downloads.

- The board Export menu downloads comma- or semicolon-separated CSV, TSV
  and iCalendar. CSV and TSV honor the selected column groups on public
  and private boards. Spreadsheet formula prefixes in text are escaped.

- Export a board’s dated cards as an iCalendar feed. Public boards support
  subscriptions without a token. Private boards require a full board member.
  Archived, deleted and linked cards are excluded.

- Record custom-field edits in shared-store History. Restoring a snapshot
  uses its date metadata to preserve BSON dates and date-looking text.
  The same nested-date History spec runs in WeLite and Weddy.

- Open History for a single list or swimlane from the board. Search,
  contributor, pagination and restore requests retain that scope.

- Open History in a pop-over from the board or card menu. Search, page,
  filter by contributor and restore selected changes without leaving the
  board. The same links still open the standalone History page in a new tab.
  A board refresh after restoring a row leaves the next History window open.

- Card date edits from the date picker appear in History. Undo, redo and
  selected-row restore preserve the stored instant and BSON date type.

- History shows translated change groups, formatted timestamps and date
  values, and readable numeric, text and document details. Search and
  contributor controls wrap on narrow screens.

- Restore a deleted list from History together with the cards deleted in
  the same operation. Cards deleted separately stay deleted.

- Restore selected card title, description and rule history rows from the
  History page. The form returns to the same search, contributor and page.

- Open the shared-store History view from the board or card menu. Browse
  authorized history rows by contributor, search and page. The six shared
  History scope tests and the board History navigation test pass in Chromium.

- Board Settings appends new custom fields and saves the order set by mouse
  or keyboard. Open cards follow that order. Turning on Show on Card adds
  the field to existing cards while preserving their values.

- Render title-change activities with the board’s text display settings on
  cards and in the sidebar. The sidebar restores its expanded activities
  after a board refresh. Three shared activity viewer tests passed in Chromium.

- Drag items to reorder them within a checklist. The server saves the order
  shown by the drop placeholder, with or without desktop drag handles.

- Assign a checklist item to an active board member or clear its assignee.
  The picker highlights the current assignee and the card shows their name.

- Edit checklist and item titles in place on the open card, using the same
  inline forms as Weddy. Delete a single item from its editor after confirming
  the removal. Other items stay on the checklist.

- Apply the member’s saved calendar and first weekday to card dates and date
  pickers when the page opens. WeLite now runs the same complete calendar
  display, Today marker, date-format and Change Settings specs as Weddy.

- Set, edit or clear deadlines for checklists and individual checklist items
  with the same calendar as Weddy. The board’s checklist due-date setting
  controls display and edits. The eight shared WeKan checklist tests and an
  item deadline round trip passed in Chromium.

- Play the optional checklist chime when an item is checked off. The
  member's Change Settings preference applies immediately and after reload.

- Board admins can create, edit, enable, disable and remove WIP limit
  groups in Board Settings. Pick lists individually with the mouse or
  keyboard, or select the lists of a swimlane together. Member list headers
  show the combined count and highlight when the group exceeds its limit.
  The highlighted group is advisory, and per-list limits govern adding cards.

- Multi Board Calendar shows dated cards from active board memberships in
  one read-only view, with each event prefixed by its board name. It respects
  card access, the current filters and the member's calendar preferences.

- Open Calendar Mode from Board View for week and month grids of due
  cards. Each day shows the cards in list and card order, with labels
  and full titles. Switching board views preserves the current filters.

- Open Calendar from Board View to see card dates with the current filter
  applied. Select a day to create a card due on that day. The title editor
  uses the member's Submit on Enter preference. All 26 editor shortcut tests
  now run against both Weddy and WeLite. Calendar assets come from
  Weddy's bundled FullCalendar and use DOS 8.3 filenames.

- Mark subtasks done or undone on the parent card. The section reports the
  completed and total counts and shows the state read-only to viewers.
  A subtask with multiple parents appears under each, with one shared status.
  Linked subtasks read and update the original card's status according to
  the viewer's permissions on that card.
- Add and open subtasks from the card's Subtasks section. The title editor
  follows the member's Submit on Enter setting in both modes. Optionally
  copy the parent's current labels when creating a subtask.

- Run 28 more of WeKan's Chromium tests from Weddy's list. Coverage
  includes board membership and rendering, card voting and watching,
  Rules workflows and Wrike import and export. The list also now checks
  disabling Submit on Enter from Member Settings without a reload.

- Inspect global search with `debug:selector`, `debug:projection`, or
  `debug:all`. The diagnostics show the parsed filters and sort or the
  result fields and pagination, according to the selected mode.

- Search readable custom-field values on archived boards in an explicit
  archive search. Admin-only values remain visible to board admins only.

- Include archived boards in explicit archive searches. Archived hits open
  a read-only card preview with the title and description. Search and preview
  both require active board membership and respect assigned-only access.

- Scope Search All Boards text to descriptions, readable custom fields,
  live attachment filenames, or checklist and checklist-item titles. The
  search instructions show the operators in the selected language.

- Find exact card numbers with the localized `number:` operator. The
  `org:` and `team:` filters match active board assignments by display name
  or ID, and recognize group short names in the shared store.

- Set the number of Search All Boards results per page with the localized
  `limit:` operator. The page size carries through next and previous links.

- Filter Search All Boards by archived or all cards, open or ended cards,
  and public or private boards. Within active boards, archive searches
  include cards in archived lists and swimlanes.

- Sort Search All Boards results by due, created or modified date, in either
  direction. The selected order applies across boards and result pages.

- Step to a board-search match even when the active filter hides it or its
  list is closed. Search shows the selected card on the board and temporarily
  opens the relevant swimlane and list. Closing Search restores the original
  view and leaves the saved filters and folds intact.

- Search All Boards accepts numeric day ranges for due dates, creation and
  modification. The search instructions describe these filters using the
  selected language. Signed day offsets and the localized week, month,
  quarter and year filters are also available. Named periods use the start
  of the following period as their upper bound.

- Open board Search from the header. Search matches the titles of loaded
  lists and cards. On mobile, Back closes the sidebar and returns directly
  to the board, including after a board refresh.
- Step through matched cards with Enter, Shift+Enter or the Previous and
  Next buttons. The sidebar shows the position, and the board scrolls to
  and highlights the selected card.
- Open a matching card from its minicard in the search sidebar. Search
  results are excluded from board dragging and multi-selection.
- Search the board's stored cards by title, description, comments and
  checklist text. Results include matching cards outside the rendered canvas
  and follow the viewer's board and assigned-card permissions.
- Find cards by readable custom-field text and exact number or currency
  values, including search terms with a decimal comma. Admin-only field
  values contribute matches only for viewers who can read them.
- Match text already indexed by WeKan for live attachments in a shared
  store. Board Search and the text filter check that each index entry still
  belongs to an attachment on the matching card and board.
- Index UTF-8 plain-text card attachments up to 64 KiB on upload. The
  attachment and its search entry are registered together. Shared stores
  write WeKan's document preview collection, and native stores keep a local
  index.
- Index the first 2 MiB of UTF-8 plain text, CSV, TSV, Markdown and JSON
  uploads. Strip the UTF-8 byte-order mark and collapse whitespace so phrases
  can match across line breaks and tabs.
- Decode BOM-marked UTF-16LE and UTF-16BE text attachments for the same
  index, including characters represented by surrogate pairs.
- Search All Boards uses the same text search across the signed-in user's
  active board memberships. The page links to matching cards and shows 25
  results at a time.
- Move a card to another list in its current swimlane from Search All
  Boards. The move uses the card's existing write and destination checks
  and returns to the same search query and page.
- Search All Boards accepts one title, board, list, or swimlane operator,
  or the overdue predicate for due dates. It recognizes the operator names
  in the viewer's locale and in English.
- Combine supported operators with each other and with free text. Repeated
  operators match any of their values. Different operators and the free
  text must all match. Quote operator values that contain spaces.
- Filter by the presence or absence of attachments, checklists,
  descriptions, start/due/end dates, assignees and members. An expandable
  help section shows the supported operators in the viewer's language.
- Search specifically in card comments or match labels by name or color.
  The label operator also accepts the `#` shorthand.
- Search for card members, assignees, or creators by username. `user` and
  its `@` shorthand match a card member or assignee. `me` selects the
  signed-in user.

## HTML5 minicards

- Show picked requesters alongside the free-text requester on a minicard,
  in their saved order. Resolve active board members only and use initials
  when there is no local avatar.
- Show the Markdown description preview with an optional heading when the
  board enables description text. Otherwise the description badge follows
  its own setting. Locations use their name or address, with a fallback to
  the legacy location. HTTP checks cover these modes, the free-text requester
  and the last-activity timestamp.
- Show the optional finished/total checklist item badge in the board's
  configured minicard section order. An empty checklist shows `0/0`, and a
  nonempty set of fully checked items gets the finished style. The badge is
  off by default.

## HTML5 card attachments

- Honor JPEG EXIF orientation in thumbnails, including attachments stored
  with the legacy `image/pjpeg` MIME type.
- Preview uncompressed 24-bit BMP attachments in the gallery and on
  minicard covers. The decoder checks image dimensions and row lengths
  before reading pixels.
- On Linux with `libwebp.so.7`, decode WebP attachments and encode thumbnails
  in WebP. PNG and JPEG attachments still produce PNG previews on builds
  without the optional library.
- Serve 512-pixel previews of PNG and JPEG card attachments through the
  existing attachment access checks. The gallery and raster minicard covers
  request previews. Unsupported raster decoders and failed conversions fall
  back to the original. SVG uses its sanitized original route.
- Rename attachments in the open card using the same storage operation as
  HTML4. The rename changes the displayed and downloaded filename, retains
  the existing extension, and leaves the stored file bytes intact.

## HTML5 card comments and checklists

- Render Markdown in card comments, checklist titles and checklist items
  with the same viewer and plain-text settings as card descriptions. The
  API continues to return the stored Markdown source.

## Shared storage tests

- Verify that a running FerretDB (`10635f841e`) discovers a database newly
  provisioned through WeLite HTTP. Update the bootstrap sign-in and native
  registration checks in `tests/shrhttp.py` to use cookie-free form navigation.
  The linked SQLite run passes these checks and proceeds through board import.
- Verify that the public HTML4 board renders imported named and hexadecimal
  card colors around its navigation forms, reveals subtasks on request, and
  reflects a REST sort update on subsequent requests.
- Exercise the HTML4 webhook settings after cookie-free sign-in, including
  localized errors, board access checks and webhook creation, editing and
  deletion. The linked SQLite run passes these HTTP checks.

## 2026-11-26 The HTML5 view for modern browsers

- Serve two views on one backend: modern browsers (Chromium 90+, Firefox 90+,
  Safari 14+) get the HTML5 view, Weddy's pages - WeKan's own markup, class
  names, CSS and script - and IBrowse, NetSurf, Dillo, old and unknown
  browsers the HTML4 view as before (`src/wlview.pas`).
- Add the HTML4/HTML5 toggle to the top header of both views, made like
  WeKan's mobile/desktop toggle. `?ui=html4` or `?ui=html5` switches and is
  kept in a `welite-ui` cookie where the browser keeps cookies. The toggle
  from the HTML4 view carries its session into the HTML5 view, and the HTML4
  view uses that session again after the toggle back.
- Render Weddy's sign-in form, All Boards with its Starred and Remaining
  sections, the board with its swimlanes, lists and minicards, the opened
  card's details and "Board not found" from WeLite's data, with the same
  queries and access checks as the HTML4 view (`src/wlh5.pas`). Weddy's
  static files are in `public/static/` under 8.3 names.
- Sign in to the HTML5 view with WeKan's `meteor_login_token` cookie: a WeLite
  session, or a Meteor login token of a shared store. Log Out revokes it.
- Run WeKan's own Playwright tests against the HTML5 view with
  `bash tests/wkui/run.sh`: FerretDB makes the shared store, WeKan's
  `helpers/db.js` seeds it, WeLite serves it, and the specs listed in
  `tests/wkui/specs.txt` run in Chromium. All 7 listed pass: a board loads
  and renders its lists, a member sees the board in All Boards and a
  non-member gets "Board not found", a minicard opens the card's details,
  which are not maximized and close again.
- Add a card in the HTML5 view: the list header's "+", the list menu's
  Add card to top or bottom of list, and Weddy's composer, posting to
  `/b/:id/cards`. The card is added with the REST API's own checks and writes
  (`CreateViewCard` in `src/wlapi.pas`), first or last in its list. Three more
  of WeKan's tests pass: add to top, add to bottom, and a minicard title that
  opens the card.
- Answer weddy.js's `callAsync` at `POST /_methods/<name>`, WeKan's Meteor
  methods by the same names, as Meteor answers them: `{"result": ...}`, or
  `{"error", "reason"}` - 401 when not signed in, 404 for a method WeLite has
  not got. The first is `toggleCardMaximized`, the user's own full-screen
  card (`users.profile.cardMaximized`), and the card's maximize and minimize
  buttons. Two more of WeKan's tests pass.
- Rename a card in the HTML5 view: its title's editor posts to
  `/b/:id/cards/:cardId/title`, checked as the REST API checks a card's title
  (`RenameViewCard`). One more of WeKan's tests passes.
- Run two more of WeKan's tests: a card's description shows when it opens,
  and a card added from the bottom of a list appears. 15 pass.
- Show a card's checklists in the HTML5 view, with their progress and items,
  and add a checklist, add an item, check or uncheck it, and delete a
  checklist with its items and only its items - by the section's forms and
  by WeKan's own `/checklists/remove` method - with the REST API's checks
  (`CreateViewChecklist`, `AddViewChecklistItem`, `ToggleViewChecklistItem`,
  `DeleteViewChecklist`). The 7 checklist tests of WeKan's `12-checklists`
  run against it and pass, none of them by finding the section missing. 22
  pass in all.
- Show a card's comments in the HTML5 view, with who wrote them and when,
  and comment on a card with WeKan's comment capability
  (`BoardCanComment`, models/lib/boardRoleCapabilities.js in WeKan): Comment
  only may comment, No comments, Read only and non-members may not. Two more
  of WeKan's tests pass, 24 in all.
- Add a list in the HTML5 view: the swimlane's Add list form at the end of
  the lists, the "+" beside a list's header, and WeKan's `createListAfter`
  method, sorted as WeKan sorts a list added after another
  (`CreateViewList`). The header has WeKan's notifications toggle, so
  weddy.js reads the signed-in user at `GET /api/user` and checks the
  session at `/_session` with the cookie alone; the cookie opens no other
  REST route. WeKan's `#6865` test opens the form, but it also expects
  Escape to close it, and the form to stay open after a list is added. WeLite's
  own `public/static/welite.js` closes it on Escape, as WeKan's EscapeActions;
  weddy.js closes it after adding, so the test is not listed.
- Show a card's members in the HTML5 view and put a board member on the card
  or take them off from WeKan's members pop-over, with the REST API's member
  checks and its join/unjoin activity (`ToggleViewCardMember`, sharing
  `CardAssignmentSql` with the REST route). Show Requested By and Assigned
  By where the board shows them, Edit when set and Add when empty, and
  change them (`SetViewCardPerson`); edit the description
  (`SetViewCardDescription`). A Worker may change neither, as in WeKan.
  `welite.js` opens and closes the Requested By and Assigned By forms, which
  weddy.js leaves alone. All 6 tests of WeKan's `16-card-members-description`
  pass, none by finding the section missing; 28 pass in all.
- Show a card's labels in the HTML5 view, put one of the board's labels on
  the card or take it off from WeKan's labels pop-over
  (`ToggleViewCardLabel`), and create a label from it as a board admin with
  the checks and write of `PUT /api/boards/:id/labels`, which now share
  `BoardLabelPermission` and `WriteBoardLabel`. Three more of WeKan's tests
  pass, 31 in all.
- Show a card's Received, Start, Due and End in the HTML5 view where the
  board uses them, as a badge or a "+", and set or clear them from Weddy's
  date picker (`SetViewCardDate`): by whoever may change the card but a
  Worker, a four-digit year, with WeKan's `a-<field>` activity and its old
  value (timingChangeActivity.js). Six more of WeKan's tests pass, 37 in all.
- Show the minicard's labels, dates and members in the HTML5 view where Card
  Settings shows them on the minicard (`allows*OnMinicard`). A minicard's
  date opens the date picker for whoever may set it, as WeKan's minicard
  dates do (Weddy's are badges only), so one more of WeKan's tests passes,
  38 in all.
- Add a swimlane in the HTML5 view below or above the one whose "+" opened
  WeKan's swimlaneAddPopup, sorted between it and its neighbour as WeKan's
  titleSortIndexes (`CreateViewSwimlane`), and fold a swimlane for its user
  only with WeKan's `setSwimlaneCollapsedState` (`SetViewProfileFold`: ids
  only as keys, as assertSafeMapKey, on a board the user may read). Five of
  WeKan's `13-swimlanes` tests pass, 43 in all; "adding a new swimlane"
  looks for a link Weddy's and WeLite's pop-over do not have, so the add is
  verified by `tests/view.py`.
- Show a card's custom fields in the HTML5 view, for whoever may change the
  card on a board that uses them: each field the REST API's field policy lets
  the user see, with its cardCustomField-* editor - text, number, currency
  (123,45 is 123.45), checkbox (its square saves at once), date (the date
  picker), dropdown, multi-select and string template - and the section's
  picker that puts a field on the card or takes it off, creates a field of
  the board (`CreateViewCustomField`, sharing `WriteBoardField` with
  `POST /api/boards/:id/custom-fields`), and the user's own layout
  (`toggleCustomFieldsGrid`). Writes go through the field policy and
  `SaveCardFieldValue` (`SetViewCardField`). Six more of WeKan's tests pass,
  49 in all.
- Show a card's attachments in the HTML5 view as WeKan's attachmentGallery,
  upload one from cardAttachmentsPopup (multipart, stored as the HTML4 view's
  upload stores it) and delete one, and serve them at WeKan's
  `/cdn/storage/attachments/:id[/original/:name]` to a signed-in user who may
  read the board: only a raster image is shown inline, everything else -
  HTML and SVG among them - comes as a download with `nosniff`, and
  `?download=` always does. Five more of WeKan's tests pass, 54 in all.
- Add the card's menu to the HTML5 view (cardDetailsActionsPopup): copy the
  card's link, move it to another list or swimlane of its board with WeKan's
  moveCard activity (`MoveViewCard`), copy it - here or to another board the
  user may change, with its own title - as the REST API copies one
  (`CopyViewCard`), and archive it (`ArchiveViewCard`); and the card's list
  picker. weddy.js reads another board's swimlanes and lists at
  `GET /b/:id/places`. Eight more of WeKan's tests pass, 62 in all.
- Add the board's header and sidebar to the HTML5 view: the board admin
  renames the board from its title in the top header (boardChangeTitlePopup;
  `RenameBoard`, which `PUT /api/boards/:id/title` now shares), the user stars
  it (WeKan's `toggleBoardStar`), and the sidebar - opened from the header's
  hamburger - has the board's members, the board menu and its Archived Items:
  the archived cards, lists and swimlanes, each restored by whoever may change
  the board (`RestoreViewItem`). The member menu opens All Boards' Archive,
  `/allboards/archive`, the archived boards the user is a member of. Eight
  more of WeKan's tests pass, 70 in all.
- Add the card's vote, Planning Poker and watch, and the board's watch, to
  the HTML5 view, with WeKan's rules: an active board member - or anybody who
  can see the board, when the vote or Planning Poker allows non-members -
  votes until the end date (showVotingButtons, `cards.vote`: the other side
  moves the vote, the same side again takes it back) and plays one card of
  the deck (`cards.pokerVote`), on a board that allows Planning Poker;
  whoever can see the board watches a card - an assigned-only member only a
  card assigned to them - and chooses watching, tracking or muted for the
  board (`watch`, muted being no watcher at all). weddy.js's `setLanguage`
  sets the user's language, and the HTML5 view now reads that language for a
  viewer signed in with WeKan's own login token too. All of WeKan's spec 14
  passes.
- Add the Filter to the HTML5 view: the board header's Filter button - on,
  with its reset, while a filter is - and the sidebar's card text and label
  filters (WeKan's client/lib/filter.js, Weddy's board_filter.go). The card
  text is matched in titles, descriptions, comments, checklists and their
  items, case-insensitive; labels are any or every chosen one, or no label,
  and an excluded label always wins. Only the board's own labels filter, and
  the filter is the board drawn for the viewer, never an access check. The
  key filter-card-text-label is copied from WeKan's catalogs. 212 of WeKan's
  tests pass, all of those listed.
- Add Sort Cards to the HTML5 view, as WeKan's cardsSortPopup and Weddy's
  board_sort.go: due date (cards without one first), title, newest or oldest
  first, votes (positive minus negative) and the board's label order (cards
  without a label last), kept in the board's URL beside the filter, with
  Sort is on and its reset while an order is. A display order only: no
  card's sort changes, and ties keep the manual order. weddy.js is Weddy's
  again, with its Sort Cards; sort-by-votes and sort-by-label-order are
  copied from WeKan's catalogs. 213 of WeKan's tests pass.
- Add WeKan's header to the HTML5 view's board: Home, the toggle beside it
  that hides the header's icons for the session, and the board's title, in
  that order, then the mobile/desktop toggle - WeKan's setMobileMode, kept in
  localStorage's wekan-mobile-mode and the user's profile.mobileMode, chosen
  by a narrow or touch screen until the user chooses. weddy.js and wekan.css
  are Weddy's again, with the toggles and the glyphs of the header's new
  icons. WeKan's mobile layout itself (body.mobile-mode) is still to come.
  214 of WeKan's tests pass.
- Add the sidebar's members to the HTML5 view, as WeKan's membersWidget,
  addMemberPopup, memberPopup and removeMemberPopup: a board admin searches
  users by username, full name or address (`GET /b/:id/members/search`),
  adds one and removes one - never oneself - through the same checks and
  writes as `POST /api/boards/:boardId/members/:userId/add` and `/remove`
  (`ChangeBoardMembership`, which those REST routes now share).
- Move a card with `PUT /api/boards/:boardId/lists/:listId/cards/:cardId`
  and a `listId` or `swimlaneId` in the body (#6423), within its board, with
  WeKan's moveCard activity; a list of another board is refused.
- WeKan's spec 01 and spec 40 pass whole, and the HTML5 view's board and card
  are right-to-left in Arabic and Urdu. 225 of WeKan's tests pass.
- Add WeKan's viewer to the HTML5 view (`src/wlmd.pas`): a card's title on
  its minicard and in its details, and its description, are Markdown -
  paragraphs, headings, quotes, lists, fenced code, strong, emphasis, strike,
  code and links, bare http(s) addresses too. Every character is escaped
  first, so HTML a user wrote stays text, and a link goes only to an http,
  https or mailto address or a path of this site. `tests/markdown.py` checks
  17 texts, the attacks among them, and that each tag in the output is the
  viewer's own.
- Add attachmentActionsPopup to the HTML5 view: an image attached to a card
  is its cover on the minicard, or the board's background for a board
  admin, and off again by the same button; only the board's own raster
  image attachments, by their address, are ever used.
- Fold a list per user and per swimlane (#6712, WeKan's
  setListCollapsedState into profile.collapsedLists), kept after a reload.
- Fix the minicard query in a shared store: LiveAttachmentSQL names the
  attachments table unaliased, and a test now fails on any query that
  aliases it beside LiveAttachmentSQL. 227 of WeKan's tests pass.
- Add Admin Panel / People to the HTML5 view (`/people`, `/admin/people`),
  as WeKan's peopleBody and editUserPopup and Weddy's people.pug: a site
  admin edits a user's username, full name, initials, address, admin and
  access and sets a new password, switches Admin and Active in the table,
  and makes a user with WeKan's setCreateUser. One's own admin and access
  are not one's own to take away; a new password or access taken away signs
  the user out everywhere. The member menu has the Admin Panel for a site
  admin.
- Show a refused sign-in in the HTML5 view as its own form again, with
  WeKan's error and the typed username, and give the password field
  WeKan's visibility button. 236 of WeKan's tests pass.
- Add the HTML5 view's sign-up form (Weddy's signup.pug): username,
  address and the password twice, each with its visibility button. The
  address is kept as the account's email, one account's only; the form shows
  its errors with what was typed, and a new account is signed in with the
  login cookie. WeKan's spec 05 passes whole: 237 of WeKan's tests pass.
- Add the activities to the HTML5 view, as WeKan's activities.jade and
  Weddy's activities.go: the card's, opened by their heading, and the
  board's in the sidebar for a board admin, put on the page when opened -
  newest first, each its member and WeKan's sentence in the reader's
  language, every name in it escaped. 238 of WeKan's tests pass.
- Add the minicard's assignees (an avatar each, their initials), its newest
  three comments on lines of their own, and "Mark as complete" for whoever
  may change the card, as the board's Card Settings show them (WeKan's
  getMinicardFlag; Weddy's minicard_badges.go). A test fails on any
  WideString case function, which needs a widestring manager the server is
  not linked with. 240 of WeKan's tests pass.
- Add the user's own list widths to the HTML5 view (#5729, #6465): the same
  width for every list of a board (WeKan's setFixedListWidthEnabled and
  setFixedListWidth, 200 to 1000, 220 until one is set) and a list's personal
  width while the board allows them (applyListWidthToStorage), drawn for
  that user only. A profile map key is never an object's own key
  (`__proto__`, `constructor`, `prototype`), as WeKan's assertSafeMapKey
  refuses them. 242 of WeKan's tests pass.
- Add Member Settings' Edit Profile to the HTML5 view (editProfilePopup):
  one's own full name and initials, and the username and address where
  Admin Panel's accounts-allowUserNameChange and accounts-allowEmailChange
  allow changing them - for a site admin always - with WeKan's setUsername
  and setEmail, a taken name or address refused and a new address
  unverified. A shared store's accountSettings are read for the switches;
  `tests/wkui/run.sh` makes them as WeKan's collectionBootstrap does. 243 of
  WeKan's tests pass.
- Add Multi-Selection to the HTML5 view: the board header's button, a
  list's Select all cards, and the sidebar's Move selection to Archive, with
  WeKan's archiveSelectedCards - every card of the selection checked before
  the first is archived (on the board, not archived yet, an assigned-only
  member's only when assigned to them, GHSA-6xqf-jh8x-4wxc). 247 of WeKan's
  tests pass.
- Add the board's visibility to the HTML5 view (boardVisibilityList): a
  board admin makes it private, visible to signed-in users or public. An
  instance board (#3249) is read by every enabled, signed-in user of the
  instance and changed only by its members, as WeKan's
  readableWithoutMembership - in the access rules every view and the REST
  API share.
- Add WeKan's password policy (passwordPolicy.js): the minimum length from
  a shared store's settings.loginOptions or PASSWORD_MIN_LENGTH (8 without
  one), enforced when passwordMinLengthEnforce or
  PASSWORD_MIN_LENGTH_ENFORCE says so, and never more than 512 characters.
  Sign-up refuses a shorter password in both views, the HTML5 form carries
  the minimum, and getPasswordPolicy answers signed out. `tests/wkui/run.sh`
  makes the site settings document WeKan makes at startup. 249 of WeKan's
  tests pass.
- Add markdown-it-emoji's shortcodes (`:thumbsup:` is 👍, never inside code)
  and Admin Panel's text display to the HTML5 view's viewer: with
  renderLinksAsPlainText no link is drawn, with alwaysShowCodeAsText the
  source itself is shown, for the minicard's and the card's title, the
  description and the card's list picker. The emoji table is generated from
  markdown-it-emoji 3.1.0's full set (MIT) by `releases/genemoji.py`.
  258 of WeKan's tests pass.
- Answer WeKan's updateListSort and the lists collection's own update in the
  HTML5 view (#5462, #5997): a list's sort and swimlane, by whoever may
  change its board - a read-only or comment-only member is refused with
  WeKan's permission-denied, and the collection update with its 403 "Access
  denied" - and only sort, swimlaneId and the time stamps, a swimlane of the
  same board. 259 of WeKan's tests pass.
- Answer an address's verification link in the HTML5 view (#1426, Meteor's
  Accounts.verifyEmail): `/verify-email/<token>` with a token of the
  account, not older than 30 days, marks the address verified, uses the
  token up and signs the account in with WeKan's own login token - unless it
  needs a second factor, which a link cannot give. A used, unknown or too
  old token goes to sign-in and changes nothing. 261 of WeKan's tests pass.
- Add board invitations to the HTML5 view (sidebar.jade): an invited user
  accepts (WeKan's acceptInvite) or declines (quitBoard) from the board's
  sidebar. Only a user holding an invitation is (re)activated (#4730); the
  users collection's own update is refused with WeKan's 403, so nobody
  forges an invitation (InviteProfileBleed). A test fails on a transaction
  begun or committed in an Exec of its own, which the CLI backend runs as a
  process of its own. 264 of WeKan's tests pass.
- Add notifications to the HTML5 view: a comment writes WeKan's addComment
  activity and puts it into each recipient's profile.notifications, once,
  as WeKan's boardNotificationRecipients.js chooses them - those who take
  part in the card and the board's watchers, or those it mentions (@name,
  @"a name", @board_members, @card_members...), only active members who
  watch or track the board or watch the list or the card (#6658), never the
  author unless they mention themselves. A list's watchers are read from a
  shared store's lists document. The header's bell shows them unread, from
  `/api/user`. 267 of WeKan's tests pass.
- Add the comment editor's @ mention menu to the HTML5 view (editor.js,
  #6704): typing @ and part of an active board member's username or full
  name, in any case, opens `.textcomplete-dropdown` on top of the card; a
  click, Enter or Tab writes "@username (Full Name) " and Enter does not send
  the comment. The members come with the textarea as escaped JSON, and the
  menu writes them as text. 269 of WeKan's tests pass.
- Add the notifications drawer's list to the HTML5 view (notificationsDrawer,
  as Weddy's): the user's notifications newest first, each the activity's
  act-* sentence in the user's language with its board, its actor and its
  names in bold and the card a link to it, only of boards the user may
  still read, and an entry scheduled for later (#5171 showAt) not before
  its time. The tray grouping - the member's, the board's or Admin Panel's -
  puts one card's or one board's entries in one row (#5171). Its menu marks
  all read or deletes all, after the confirmation in the user's language.
  271 of WeKan's tests pass.
- Notify of a card's other activities as of its comments (WeKan's
  prepareActivityNotification): moved, archived, deleted, and a member or
  an assignee put on it or taken off - the member it is about takes part,
  and one just put on it is told (#5833, unless NOTIFY_ON_ASSIGN=false),
  still only when watching or tracking (#6658). Nothing when Admin Panel
  turned notifications off (#5820), and nothing from a change that wrote no
  activity.
- Let the tray mark the user's own notification read or unread and remove
  it through the users collection's update, as WeKan's allow rule does; any
  other write of the notification list is refused and recorded in Admin
  Panel / Problems as TrayBleed, and every other account write is refused
  as before. 272 of WeKan's tests pass.
- Add Member Settings' Change Password to the HTML5 view (changePasswordPopup,
  `/profile/password`): the password now and the new one twice, within the
  password policy; the password now is checked within the sign-in limit, so
  the form is no way round it. Every session of the account ends with the
  change, this one too (WeKan's passwordChangeRequired.js), and so does
  WeKan's setPassword, a site admin's. In a shared store the HTML5 view
  signs in with a Meteor login token in services.resume, as WeKan does, so
  WeKan and WeLite see the same sessions. 273 of WeKan's tests pass.
- Add Member Settings' Change Language to the HTML5 view (WeKan's
  changeLanguagePopup): every language by its name, with its language's
  flag, its region's flag and name and (RTL), across the whole window. The
  flags come from WeKan's languageFlags.js (`releases/genflags.py` makes
  `src/wlflags.inc`, `src/wlflag.pas` draws them), and `tests/langflag.py`
  compares them with WeKan's own for each of its languages.
- Bring the catalogs up to WeKan's (`releases/synclang.py`): each text a
  catalog has is now WeKan's, so the corrections made in WeKan - a Veps or
  Tamazight catalog that held Finnish or Arabic, a Mongolian one that held
  Russian - reach WeLite. `tests/catalogs.py` fails on a text that differs
  from WeKan's or a placeholder that is not the English one. 277 of WeKan's
  tests pass.
- Add the Filter sidebar's Advanced Filter to the HTML5 view (WeKan's
  advancedFilter.js, as Weddy's advanced_filter.go): custom fields by name,
  a dropdown by its option's name, numbers by the whole token, date fields
  and the card's own @dates by range, `= none`, regexes, and/or, not and
  brackets. One that does not parse keeps the last that did (?last=). SQLite
  has no regular expressions to give, so `src/wladvf.pas` evaluates the
  filter in Pascal, card by card - nothing typed reaches the database as
  SQL. `tests/advfilter.py` checks it as data. 279 of WeKan's tests pass.
- Show an SVG attachment as an image again (WeKan's svgSanitizer.js and
  svgResponse.js, as Weddy's svg_sanitize.go): stored sanitized and served
  sanitized again, inline, under `default-src 'none'; ... sandbox` - no
  script, foreignObject, animation or frame element, no on* handler, no
  script URL however it is spelled, no data: document, no dangerous style,
  no DOCTYPE or entity. `src/wlsvg.pas` reads the XML itself, so no entity
  is ever expanded; a file that is not well-formed is only downloaded.
  Active content taken out is recorded in Admin Panel / Problems
  (FileBleed). An SVG is a card's cover and the board's background too.
  `tests/svgclean.py` checks the sanitizer as data.
- Fix the attachment route of a shared store: its query aliased the
  attachments table beside LiveAttachmentSQL, which names it, so every
  attachment answered 404; the guard in `tests/view.py` now also finds
  the JOIN form. 280 of WeKan's tests pass.
- With no language chosen, show the HTML5 view in the browser's own
  languages, as WeKan's preferredLanguage does: welite.js gives the server
  navigator.languages in the `welite-languages` cookie and draws the page
  again once, and the server takes the first WeKan has, with WeKan's
  aliases (vep is ve-PP, es-419 es-LA...), which Accept-Language now uses
  too. Nothing is saved in the profile, and a chosen language wins. The
  page is drawn again only when that gives another language than the
  page's: welite.js chooses among the view's tags as WeKan's
  matchBrowserLanguage does.
- Add WeKan's mobile view of the board (swimlanes.jade, isMiniScreen): in
  mobile mode every list of a swimlane is a compact row (miniList), and
  the one chosen opens inside its own swimlane while the other swimlanes
  keep their rows. weddy.js decides the mode as before; welite.js tells the
  server in the `welite-mobile` cookie and the chosen list (WeKan's Session
  currentList) in `welite-list`, and draws the board again only when the
  mode differs from what was drawn. 286 of WeKan's tests pass.
- Add WeKan's Rules (`src/wlrules.pas`): the board's Rules page
  (/b/:id/:slug/rules) with its list, the wizard - title, trigger, action -
  and the Workflow view's palette; the rules.createRule, updateRule,
  deleteRule and setEnabled methods, a board admin's, with RuleBleed's check
  that an action names only a board its creator may change (a refusal is in
  Admin Panel / Problems); and the engine. A request that writes runs the
  rules its activities start before it answers: card created, moved (to a
  list, or forward or back), archived, restored, commented, labels, members,
  assignees, checklists, items, attachments, dates, and a title or
  description containing a text; the actions move to the top or bottom,
  archive, restore, color, labels, members, assignees, checklists and their
  items, swimlane, comment, complete and dates, with WeKan's {variables}.
  Rules started by rules stop 5 deep (BypassBleed's rule loop, recorded).
  The page is Weddy's rules.pug: `releases/pugtpl` turns a Pug template into
  the Go template text Weddy draws, and `src/wltpl.pas` draws that text, so
  Weddy's other pages can come the same way. `src/wlcase.pas` gives upper and
  lower case without a unicodestring manager, which WeLite has none of.
  `tests/tpl.py` and `tests/textcase.py` check both as data. 368 of WeKan's
  tests pass.
- Add the rest of WeKan's Rules that the Rules page offers: button rules -
  the board's in its header, the card's on the opened card - and
  rules.runButton (RuleButtonBleed: a button outside the writable board is
  refused and recorded); the Copy Card action, which copies a card once per
  event and never into a list or a board its user may not change; the
  advanced-filter trigger, which reads the card as it is on every card
  activity; the Wrike workflow import and the rules' JSON, CSV and Wrike
  downloads (`src/wlwrike.pas`, `tests/wrike.py`); and Board Settings' Rules
  entries on the board. rules.updateRule changes a rule's trigger and action
  where they are, as WeKan does, and copies one another rule shares.
- Write WeKan's activities where they were missing: createCard for every new
  card, a-changedTitle and a-changedDescription when a card's text changes,
  setCustomField and unsetCustomField when a custom field's value does - what
  the card's activities show and what the rules start from. Add WeKan's
  /cards/update (a card's title and description), createCardWithDueDate
  (AuthBleed recorded) and setCardCustomFieldCheckbox, -Currency and
  -Assigned methods. A copied card's ObjectId-keyed rows (written by a
  database tool) are copied too. 393 of WeKan's tests pass.
- Add the Rules' history, as WeKan's server/lib/ruleHistory.js: every
  rule write - from the Rules page or the REST API - is one changeHistory
  row with the rule's snapshot before and after, in the board's hash chain
  (`src/wlchhist.pas`; `src/wlchhash.pas` writes WeKan's canonical text,
  numbers and arrays included, `tests/histhash.py`).
  changeHistory.undoLast and redoLast put it back for a board admin and
  refuse to overwrite another admin's newer edit; restore takes an older
  snapshot on purpose, never replacing a part another rule shares. A REST
  edit keeps the rule's button fields in step with its trigger.
- Draw the board again when it changes elsewhere, as Weddy's live board:
  weddy.js' EventSource reads /b/:id/live, which says board-changed when the
  board's cards, lists, swimlanes, activities or rules change - naming the
  page that changed it, which keeps what it drew (a rule's change is drawn
  on every page, its own too, as its buttons are the server's). 402 of
  WeKan's tests pass.
- Add the Sort List, Link Card and Create Card rule actions: a list's cards in the order
  of their name, creation, change or due date; a linked card in a list of a
  board the rule's user may change, and nothing - recorded as RuleBleed - in
  one they may not; a follow-up card named with {variables}. `tests/rules.py`
  runs the rules on FerretDB over HTTP:
  both actions, their refusal, and the history's undo, redo, conflict and
  refusal. 406 of WeKan's tests pass.
- Refuse every way to write an admin-only custom field (#3141,
  AdminFieldBleed, recorded in Admin Panel / Problems with the account's
  name): Meteor's /cards/update takes only $set customFields.N.value of a
  field the user may write, and a replace, $push or $unset of the array, a
  /cards/insert or copyCard naming such a field, the REST card edit, and a
  non-admin's /customFields/insert or update of adminOnly are refused. WeKan's
  copyCard copies a card without the values its copier may not write. 415 of
  WeKan's tests pass.
- Add Admin Panel / Problems / Security Report (`src/wlprob.pas`, Weddy's
  securityreport.pug): the security stream's summary rows - kind, source,
  the most recent account and how many times - newest first, searched and a
  page at a time, for a site admin. 416 of WeKan's tests pass.
- Add Admin Panel / Problems / Password length (WeKan's
  passwordLengthReport, Weddy's passwordlength.pug): the minimum and its
  enforcement, saved as the Admin Panel's login settings, and the report of
  who signs in with a shorter password - one row an account, counted, with
  its address and both sign-in times, by Too short, Fixed and All. While the
  minimum is enforced, such an account changes its password before anything
  else (WeKan's passwordChangeRequired), and the change fixes its row. The
  sign-up form keeps WeKan's own minimum of 6 while none is enforced. 421 of
  WeKan's tests pass.
- Draw a member's uploaded avatar in the board's members widget at the path
  WeKan is served under now (WeKan's avatarDisplayUrl, `src/wlavatar.pas`):
  an old host or ROOT_URL prefix before `/cdn/storage/avatars/` is dropped,
  anything that is not a WeKan avatar is left as stored and escaped. Answer
  WeKan's isAvatarUploadBlocked (#4740) from Admin Panel's
  attachmentStorageSettings. `tests/avatar.py` compares every case with
  WeKan's own JavaScript. 424 of WeKan's tests pass.
- Draw every date in the format WeKan would (`src/wldatef.pas`, WeKan's
  resolveDateFormat): the member's own while their override is on, else the
  board's, else Admin Panel's, else YYYY-MM-DD, with or without the time.
  `tests/datefmt.py` compares all 512 combinations with WeKan's own
  JavaScript. Add Member Settings / Date (format, first day of the week,
  calendar) and Change Settings (#6835, its nine toggles), Board Settings /
  Date with the week of the year for a board admin of the board's own, and
  Admin Panel / Settings / Appearance's date format for everyone and Hide
  Logo, with WeKan's changeDateFormat, changeStartDayOfWeek,
  changeCalendarSystem, setBoardDateFormat, the toggles and /settings/update
  - each refusing a format that is not one of WeKan's six, and the last
  anybody but the site admin and any other field. A change of the board's or
  Admin Panel's format draws the board's other pages again, a guest's page of
  a public board too, which now opens in the HTML5 view.
- Draw the opened card's sections in the board's Card Settings order (WeKan's
  one section model), each section this card has something for, Date and
  Card under their own headings. 427 of WeKan's tests pass.
- Add Board Settings / Card (WeKan's boardCardSettingsPopup, `src/wlcardst.pas`
  from Weddy's table of WeKan's rows): the Minicard and Card panes side by
  side, each section's checkbox and rows, the section and row drags, the
  folds, the splitter, the hamburgers (Ask for move reason, Subtasks
  Settings) and the custom fields edited and created in place. The card and
  the minicard follow their pane: its sections, its rows (the card's dates,
  the minicard's dates, people and comments), none of a hidden section.
  /boards/update writes exactly Card Settings' own fields for an admin of the
  board's own (others refused and recorded, AuthBleed), /users/update also
  the user's own split and labels text, and setCollapsedCardSection,
  setShowLabelTextOverride and /customFields/update are added. 11 of WeKan's
  Card Settings tests pass; 437 of WeKan's tests pass in one run.
- Draw the rows' new minicard and card sides as Card Settings has them:
  Requested By, location, last activity, the description's badge and the
  card colour on the minicard; the caret folding the card's details (WeKan's
  setCardCollapsed, the user's own), the swimlane name, the header's colour
  and the description's badge on the card. A colour is a class only when it
  is a colour name. A board's settings written by another server or a
  database tool draw its open pages again. The board page reads the
  minicards' sides with its cards and the profile once, so it is no slower
  for them. 13 of WeKan's 14 Card Settings tests pass, and 440 of WeKan's
  tests in one run.
- Add Card's hamburger's table of what may be dragged on the board (WeKan's
  setBoardDragging, a board admin's or the site admin's) and Subtasks
  Settings' deposit board and list: only a board the user may write, and a
  list or swimlane on it; anything else is refused and recorded
  (SubtaskDepositBleed).
- Run WeKan's scheduled rule triggers (`src/wlsched.pas`, WeKan's
  scheduledRules.js, cronSchedule.js and scheduledDueFilter.js): a cron
  schedule in UTC, a calendar one (once, daily, weekdays, weekly, monthly) at
  its time of day, and a card's due or start date or its days in its list -
  each once in its minute, as the board's first admin, its actions on the
  cards it chooses and then the rules those start. The maintenance pass runs
  them at the start of each minute and catches up on missed ones.
  `tests/sched.py` compares 286 answers with WeKan's own JavaScript;
  `tests/rules.py` runs one end to end, and a disabled and an invalid one.
- Keep a card's title and description in History (WeKan's
  changeHistoryGroups diffFields: added, edited, removed) from the card
  details, `/cards/update` and the REST API, and undo and redo them - never
  over a newer edit (history-conflict). A title may be cleared and is kept
  without the spaces around it, as WeKan keeps it. Add lists.softRemove, and
  undo and redo of a deleted list with the cards of its batch only (#1023); a
  soft delete and its undo draw the board's pages again.
- Add Member Settings / Change Avatar (WeKan's changeAvatarPopup): upload one
  PNG, JPEG, GIF or WebP picture of at most 72 KB, judged by its content, unless
  Admin Panel blocks avatar uploads; choose between the uploaded ones and the
  initials, and delete one. `/cdn/storage/avatars/:id` serves it to a
  signed-in user, and to anybody only while its owner is on a public board,
  as a picture only (nosniff, sandboxed). An anonymous download of any other
  avatar is refused and recorded (PortraitBleed), as is an anonymous request
  for one that is not there (RelicAvatarBleed); a page or an SVG named a PNG,
  a file too large, and a choice or delete of somebody else's avatar are
  refused. `tests/view.py` checks each.
- Add WeKan's WIP limit methods, a board admin's: applyWipLimit (1 for a
  value below one, NaN or infinite), enableWipLimit and enableSoftLimit.
  Restore a card from the Archive into its own list only while a hard limit
  has not filled it - every open card of the list counts, in every swimlane
  (#2095) - else let the user choose a list with room (#6772, WeKan's
  restoreArchivedCardToListPopup); Restore all leaves the rest in the
  Archive and says how many. A soft limit only warns. `tests/view.py` checks
  the methods' refusals and each restore, and WeKan's restore-wip-limit spec
  passes.
- Add WeKan's changeHistory.page, the read every History view makes: a
  board's, swimlane's, list's or card's rows and what is in them, a user's or
  an entity's, newest first, searched (the change, its kind and the text of
  both contents), paged - past the end, the last page - with each author's
  count. Only the rows the caller may read are in it, and counted: on a
  board they can see, and for an assigned-only member about a card assigned
  to them; a board they cannot see answers not-authorized, a row holding card
  custom fields is a board or site admin's only. Restore a card's title or
  description row as WeKan does, for whoever may edit that card where it is
  now - an assigned-only writer their own card - and record the restore.
  A card's own History rows now carry its card, list and swimlane, as
  WeKan's do, so the card's, list's and swimlane's History find them.
  `tests/rules.py` checks the page and the restore, and five of WeKan's
  history-read-scope tests pass.
- Give WeKan's attachment API an assigned-only member's rules (AssignedBleed's
  read siblings, UnassignedAttachBleed): `/api/attachment/list` lets them in
  and lists only their own cards' files; info and download refuse another
  card's (403, recorded as AssignedBleed); upload, the REST delete and the
  new api.attachment.delete method change only their own card's
  (UnassignedAttachBleed otherwise) - an assigned-only writer may, on that
  card, as in WeKan. A raw upload takes any body but JSON, as WeKan's does.
  `tests/view.py` checks each allowed and refused call; WeKan's
  assigned-only-reads list test and unassigned-attach-bleed pass.
- Draw the board for an assigned-only member (WeKan's isVisibleBy and
  assignedOnlyCardScope): of its cards only those assigned to them, on the
  board, opened by address and in the Archive; the board's activities are not
  theirs. `tests/view.py` checks each, and all six of WeKan's
  history-read-scope tests pass.
- Read an API token from WeKan's authToken query parameter too, as WeKan's
  export links carry it; an assigned-only member's unfiltered board export is
  refused with 403, as WeKan's export-access tests.
- Add WeKan's board announcement (#1566): a board admin's text, from the
  board menu, shown to every member above the board as plain text until they
  dismiss it, and again after it is edited; in a shared store it is the board
  document's own, its version a date WeKan reads. A member's own dismissal no
  longer keeps the next change from reaching their page. Board settings an
  assigned-only member keeps of their own (their dismissal among them) are
  theirs to write. `tests/view.py` checks each; WeKan's board-announcement
  passes, its four languages too.
- In the HTML5 mobile view, Back returns from an open list to its
  swimlane's compact list rows. WeKan's mobile swimlane spec passes in WeLite
  and Weddy.
- Verify Argon2d, Argon2i and Argon2id v16/v19 against the official C
  reference at tag `20190702` (`62358ba2123abd17fccf2a108a301d4b52c01a7c`).
  The standard and checked builds pass, including legacy PHC records,
  secret and associated data, and varied lane and pass counts.
- Verify the directory-free embedded server with the current cookieless
  sign-in and form navigation on both SQLite backends. The HTTP test
  checks translated pages, private SQL resources and clean shutdown.
- Verify path decoding across every declared route key, including keys
  used outside the main API unit. The regular and checked builds pass.
- Run the short-path provisioning and offline migration tests in native
  storage mode. Both SQLite backends verify persistent tenant paths and
  reopening the migrated data.
- Pass the full live FerretDB interoperability test on linked and CLI
  SQLite with the regenerated model. It checks bidirectional BSON writes,
  child projections, rollback and reopening existing stores.
- Regenerate the shared SQLite model from the current schema. Preserve
  list collapse as a BSON boolean and make the model freshness check pass.
- Update the native keypad test to check the three-row control and its
  explicit left-to-right direction. The test passes on both SQLite backends.
- Show ISO week numbers next to the dates on cards and minicards in the
  HTML5 view. The member can switch them on or off from the board Date
  menu, and the open board updates immediately.
- Match existing bracket labels with Unicode case folding, including
  accented letters, Greek and multi-character folds such as ß and SS.
  The comparison works in linked SQLite and the SQLite CLI.
- Apply the optional bracket label from a new card title within the card
  composer transaction. Board admins can create a missing label with the
  first unused palette color. The shared #6810 browser scenario passes.
- Add one card per nonempty title line when separate cards are selected.
  The batch uses one SQLite transaction and preserves title order at the
  top or bottom of the list. The shared #6827 browser scenario passes.
- Respect Keep the Add card form open in the HTML5 view. The composer
  closes by default. With the preference on, a successful save opens an
  empty, focused composer in the same list and position.
- Apply Member Settings' Show focus outline choice in the HTML5 view.
  The focus ring is on by default, and a saved choice to hide it takes
  effect immediately and after reload.
- Add WeKan's Create Board to the header (header.jade's createBoardForm):
  one private board with a Default swimlane, or one a line when the title
  has many lines and "Add many lines as separate items" is chosen, for a user
  the Admin Panel's board creation policy lets create one. Put Member
  Settings' Submit editors with Enter on the page's body
  (data-submit-on-enter), so every editor follows it, and add the board
  header's board view switcher, with Swimlanes, the one view WeLite draws.
  `tests/view.py` passed with linked and CLI SQLite, covering board creation,
  the body setting and the view switcher. All 21 listed
  editor-enter-preference scenarios passed in Chromium.
- Keep what was done in a custom field's editor opened before the last save
  is drawn: a box turned over is turned over from the new value, a changed
  text is kept (Weddy's weddy.js, as its fix of 03-cards-operations' checkbox
  test).
- Follow Admin Panel / Settings / Features / Turn off all webhooks
  (webhooksDisabled, as WeKan and Weddy set it in the shared store): while it
  is on, a board admin adds and changes no webhook - REST or the HTML4 view's
  Outgoing Webhooks - each attempt recorded in Problems; a delete still
  works. WeLite sends no webhooks itself. `tests/rules.py` checks each.
- Serve a file at WeKan's older address too, /cfs/files/attachments/:id,
  and to an API client's Bearer token; an assigned-only member gets their own
  cards' files and a 403 for another card's, recorded as AssignedBleed. Add
  WeKan's searchAttachmentDocumentText: the board's documents whose extracted
  text has the words, of an assigned-only member's own cards only
  (GHSA-3cgr-47wm-9cc9). `tests/view.py` checks each; both of WeKan's
  assigned-only-reads tests pass.
- Add WeKan's createBoardFromCard: a card becomes a link to a new board of
  the caller's, as private as the policy wants, by a writer of its board or
  an assigned-only writer on their own card; archiveSelectedCards lets that
  writer archive their own cards and answers how many. A card not theirs is
  refused and recorded as UnassignedArchiveBleed (GHSA-6xqf-jh8x-4wxc).
  `tests/view.py` checks each; WeKan's assigned-card-methods passes.
- Add Board Settings / Swimlane / One shared list header row (#6902,
  sharedListHeaders): every swimlane shows every list of the board, each with
  the cards of the swimlane it is shown in, under the first swimlane's
  headers, and the swimlanes scroll sideways together; nothing is written to
  a list. Without it each swimlane shows its own lists as before.
- Draw a board again when it changed between its page and its live
  connection: the page names the board as it drew it, and the connection
  sends the change at once. A REST write right after the page loaded was
  never shown (rules-history's REST button test, now and then).
- Give WeKan's scripts and tests Blaze.getData(element): a list's or card's
  id, from the element, and nothing else.
- Run 87 more of WeKan's own tests that Weddy passes, in
  `tests/wkui/specs.txt`: the REST API, viewport, RTL, stability,
  notification and board-action specs among them, and shared-list-row-6902.
- End the live board's stream as soon as its page closes it, rather than at
  the next ping up to 15 seconds later, so a stopping server no longer waits
  for it.
- A copy of a card whose source `_id` is an ObjectId gets a string id, and
  only an ObjectId: a source `_id` of any other type is refused again as no
  identity. `/b/:id/:slug/rules` is the board's Rules page now.
- Bring the 189 catalogs that lacked them up to en.jsn's keys and order from
  WeKan's catalogs (`releases/synclang.py` now adds a missing key); the
  enrollment texts of 2026-11-18 had reached only a few of them. Bosnian
  "Bajtovi" in place of the English "Bytes", in WeKan first.
- Bring `tests/admin.py` and the suites it runs, and the sign-in, enrollment,
  session, OTP and copy suites, up to the signed-in page that sign-in and
  registration answer with since fd5f992 (2026-11-19): the session is read
  from its forms, navigation from its POSTed buttons, and a move from the
  board redraws it in place. A navigation button's caption is now escaped as
  element content, not only as an attribute.
- Verify on linked and CLI SQLite (`tests/view.py`): the choice by
  User-Agent, the toggle URL, every page over HTTP, the cookie sign-in and
  Log Out, the switch both ways, and negative cases - a user who is no member,
  a forged cookie, another browser presenting the session, retro browsers.

## 2026-11-26 WeKan's URL routes

- Serve a board at WeKan's `/b/:id/:slug` and a card at
  `/b/:boardId/:slug/:cardId` (WeKan's config/router.js), and registration at
  `/sign-up`. The slug is not checked, as in WeKan, and `/b/:id` is the board
  too. WeKan's own `/b/templates` and `/b/:id/:slug/rules` are not boards.
- Build every board, card and registration link with these routes and the
  board's stored slug (`src/wlroutes.pas`). The former `/board?id=`,
  `/board/card?id=&card=` and `/register` still open the same pages, so old
  links keep working. A Designer page cannot take a WeKan route.
- A board its viewer may change still opens a card inside its POSTed form, so
  the session never goes into a URL.
- Verify on linked and CLI SQLite (`tests/routes.py`): the builders and the
  parser, every route over HTTP, links in All Boards and on the board, the
  former routes, and negative cases - an unknown board, a path with more
  parts, `/b/templates`, and no board without a session.

## 2026-11-22 Read WeKan data folders as HTML4 kanban

- Read WeKan's own folders read-only, in FreePascal: FerretDB v1 SQLite
  databases in `files/db`, through `_ferretdb_collections` and TEXT or JSONB
  `_ferretdb_sjson` documents, and Meteor-Files attachments in
  `files/attachments`. Find Docker and bundle `WRITABLE_PATH` folders, Snap
  `files` folders and Weddy `domains/<domain>` folders with their Cloud Panel
  dates under the roots in `WELITE_WEKAN_ROOTS`.
- Open a running FerretDB's WAL database with `mode=ro` and a stopped one with
  `immutable=1`, so no file is created or changed; refuse hot journals and
  short-name sidecars. Serve an attachment only as a single checked file name
  inside the attachments folder, never a path from the database or the URL.
- Show the domains with card, attachment and database sizes, the boards of a
  domain, a board as swimlanes by lists with labels, members, dates and
  counts, a card with its description, custom fields, checklists, comments
  and attachments, and an attachment viewer and download. Only the Global
  Admin sees these pages, because WeKan's accounts are not WeLite's.
- Add WeKan's `wekan-data-no-database` message in every language and reuse
  WeKan's database and Cloud Panel date captions.
- Verify on linked and CLI SQLite against databases written by FerretDB
  v1.110.0, live and stopped, including path traversal, symbolic links,
  malformed databases, HTML escaping and an unchanged data folder.

## 2026-11-19 Combine board movement arrows

- Use one set of arrows to navigate the viewport when nothing is selected
  and to move checked cards, lists or swimlanes. Add edge arrows in all
  four directions and keep the viewport in place for selected-item moves.

## 2026-11-19 Edit accounts in Admin Panel / People

- Add local accounts, rename them, replace passwords, manage TOTP and confirm
  account deletion through server-rendered forms. Bind each edit to its
  account and operation, hide stored credentials, and revoke affected sessions
  when identity or credentials change. Verify the forms with JavaScript and
  first-party cookies disabled.

## 2026-11-19 Group the minimap by viewport size

- Use the selected list and swimlane counts as the minimap tile size and
  show any remaining lists or lanes in smaller edge tiles.
- Number duplicate sample list and card captions and descriptions. Update
  existing demo data once, retaining manually edited text.

## 2026-11-19 Add a configurable Kanban viewport

- Put wrapping POST navigation under the board title, followed by viewport
  arrows, coordinates, size selectors and the minimap. Put the selection
  keypad, actions and summary before the first visible swimlane.
- Show six lists by four swimlanes by default. Let both sizes range from 1
  through 40 and retain them during viewport navigation. Replace board-view
  links with buttons.
- Expand the garden example to eight lanes, 80 lists and 248 cards. Add the
  sample rows to existing example databases once, preserving earlier edits.

## 2026-11-19 Add a local Kanban example and board calendar

- Create an isolated SQLite example from the build menu with three accounts,
  a colored board, lanes, lists, cards, labels, and assignments. Run the
  example on loopback and keep any existing example edits when selecting it again.
- Show board card due dates in an HTML4 month grid. Month navigation and card
  buttons carry the language and session in POST fields. Verify the example in
  Chromium with JavaScript and first-party cookies disabled.

## 2026-11-19 Reuse WeKan's account-created message

- Use WeKan's `account-created` message when registration saves the account
  and session creation fails. Synchronize the message from the WeKan catalogs
  and remove the redundant WeLite key.
- Verify the Finnish failure message, persisted account, and subsequent
  sign-in on linked and CLI SQLite. Run required-factor setup, confirmation
  and sign-in in Chromium with JavaScript and first-party cookies disabled
  on both backends.

## 2026-11-19 Fill Azerbaijani enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Azerbaijani form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-19 Fill Armenian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Armenian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-19 Fill Georgian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Georgian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-19 Fill Macedonian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Macedonian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-19 Fill Serbian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Serbian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-19 Fill Albanian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Albanian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-19 Fill Maltese enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Maltese form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-19 Fill Scottish Gaelic enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the setup form over HTTP and in Chromium with JavaScript and
  first-party cookies disabled on both SQLite backends.

## 2026-11-19 Fill Irish enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Irish form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-19 Fill Welsh enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Welsh form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-19 Fill Malay enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Malay form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Swahili enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Swahili form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Afrikaans enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Afrikaans form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Esperanto enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Esperanto form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Lithuanian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Lithuanian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Latvian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Latvian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Galician enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Galician form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Basque enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Basque form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Catalan enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Catalan form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Slovenian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Slovenian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Croatian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Croatian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Bulgarian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Bulgarian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Icelandic enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Icelandic form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Norwegian Bokmål enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Bokmål form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Tamil enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Tamil form over HTTP and in Chromium with JavaScript and
  first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Bengali enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Bengali form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Hindi enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Hindi form over HTTP and in Chromium with JavaScript and
  first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Thai enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Thai form over HTTP and in Chromium with JavaScript and
  first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Persian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the right-to-left Persian form over HTTP and in Chromium with
  JavaScript and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Hebrew enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the right-to-left Hebrew form over HTTP and in Chromium with
  JavaScript and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Russian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Russian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Korean enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Korean form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Japanese enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Japanese form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Ukrainian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Ukrainian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Vietnamese enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Vietnamese form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Indonesian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Indonesian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Turkish enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Turkish form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Greek enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Greek form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Portuguese enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Portuguese form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Danish enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Danish form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Romanian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Romanian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Hungarian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Hungarian form over HTTP and in Chromium with JavaScript
  and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Slovak enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Slovak form over HTTP and in Chromium with JavaScript and
  first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Czech enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Czech form over HTTP and in Chromium with JavaScript and
  first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Polish enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Polish form over HTTP and in Chromium with JavaScript and
  first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Dutch enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Dutch form over HTTP and in Chromium with JavaScript and
  first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Swedish enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Swedish form over HTTP and in Chromium with JavaScript and
  first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Italian enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Italian form over HTTP and in Chromium with JavaScript and
  first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill Spanish enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the Spanish enrollment form over HTTP and in Chromium with
  JavaScript and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Fill French enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify French and Canadian French parent fallback on both SQLite
  backends, including Chromium with JavaScript and first-party cookies
  disabled.

## 2026-11-18 Fill German enrollment and registration messages

- Translate twelve setup, registration and authentication messages.
  Verify the German enrollment form over HTTP and in Chromium with
  JavaScript and first-party cookies disabled on both SQLite backends.

## 2026-11-18 Localize disabled password registration

- Translate the shared-store password registration denial in Finnish
  and Arabic. Both SQLite backends verify the Arabic response when
  FerretDB policy disables password registration, with no account or
  session created.

## 2026-11-18 Localize registration recovery after a session write failure

- Tell users in Finnish and Arabic that their account was saved and they
  can sign in. Linked and CLI tests verify the Finnish response, absence
  of a new session token and successful sign-in after storage recovers.

## 2026-11-18 Localize sign-in session creation failures

- Translate the session creation error in Finnish and Arabic. Verify that
  a forced token write failure returns the Arabic 500 response without
  a redirect or a new token on both SQLite backends.

## 2026-11-18 Localize the Global Admin registration denial

- Translate the public registration denial in Finnish and Arabic.
  Linked and CLI tenant tests verify the Arabic 403 response and
  the absence of a session redirect.

## 2026-11-18 Localize the enrollment storage error

- Translate the setup failure message in Finnish and Arabic. Verify the
  Finnish response during a forced storage failure, including rollback,
  HTTP status and privacy headers, on both SQLite backends.

## 2026-11-18 Localize authentication rate-limit messages

- Show the retry message in Finnish and Arabic for sign-in and enrollment.
  Linked and CLI HTTP tests verify the 429 status, Retry-After and enrollment
  privacy headers. Chromium also verifies enrollment with JavaScript and
  first-party cookies disabled on both backends.

## 2026-11-18 Localize the first-account administrator notice

- Translate the registration notice in Finnish and Arabic. Verify it
  appears before the first account and disappears after registration
  on both SQLite backends.

## 2026-11-18 Localize the required enrollment registration confirmation

- Use the locale catalog for the account-created heading and page title
  when two-factor setup is still required. Verify Finnish Chromium and
  Arabic HTTP rendering on both SQLite backends, with the existing
  session-free setup handoff.

## 2026-11-18 Pass the expanded WeKan REST suite on both SQLite backends

- Pass all 117 cases across 23 specs with linked SQLite (2.2 minutes)
  and the SQLite CLI. Verify the same frozen WeLite `017c9ce` and WeKan
  `d2966d0624` sources on both backends using FerretDB `c33d4a9a`
  with external collection discovery.
- Verify server-rendered REST browser workflows with JavaScript disabled
  and Cookie request headers removed. Separate native board and enrollment
  tests verify Chromium's first-party cookie blocking directly.

## 2026-11-18 Associate registration labels with their controls

- Link the localized username, password and confirmation labels to their
  HTML inputs. Verify Finnish registration and subsequent enrollment by
  label in Chromium with JavaScript and first-party cookies disabled
  on both SQLite backends.

## 2026-11-18 Fill missing Arabic catalog entries

- Carry over 4,029 maintained Arabic strings for matching WeKan source
  entries in ar, ar-DZ, ar-EG and ary. Keep existing Arabic prose and
  protected tokens. Verify the catalog audit and the People, webhook
  settings and attachment specs on both SQLite backends.

## 2026-11-18 Verify enrollment with browser-level cookie blocking

- Run board and enrollment workflows with an isolated Chromium profile
  that blocks first-party cookies and disables JavaScript. A loopback
  probe verifies both settings before each workflow.

## 2026-11-18 Correct Arabic sign-in and registration captions

- Replace seven English or French authentication strings in each of four
  Arabic catalogs with the maintained WeKan translations. Verify localized
  registration validation, account links and code labels over HTTP with
  both SQLite backends.

## 2026-11-18 Fall back to the parent catalog for missing regional strings

- Prefer the installed regional catalog, then its installed parent for
  missing or empty values, then English. Preserve the selected language
  and direction. Verify Arabic Algeria and Egypt over HTTP and Chromium
  on both SQLite backends.
- Catalog conversion publishes matching browser and strict-JSON catalogs
  for 245 installed identities with names, direction and portable assets.
  Negotiation validates disk and embedded catalogs and handles explicit,
  profile and weighted-header precedence with aliases and parent fallback.

## 2026-11-18 Localize authentication error page titles

- Render the sign-in, two-factor setup and registration error page titles
  from the viewer's catalog. Verify Finnish and Arabic titles with the
  existing admission status, privacy headers and direction.

## 2026-11-18 Translate the remaining two-factor setup instructions

- Use the catalog for setup denial, time-based code parameters and the next
  sign-in instructions. Verify the Finnish setup and confirmation workflow and
  the Arabic denial in Chromium with JavaScript disabled and no Cookie headers
  on both SQLite backends. Other locales use the English fallback.

## 2026-11-18 Keep untitled cards visible and reachable

- Use the localized Card caption for blank titles on boards, card detail
  pages and subtask links. Keep the stored title unchanged and verify the
  board link opens the card in Chromium with JavaScript disabled and no cookies.

## 2026-11-18 Verify FerretDB account index boundaries

- Check real Mongo-wire account index creation and nested resume-token
  lookup against FerretDB. Document sparse metadata and nested multikey
  limitations in the interoperability notes.

## 2026-11-18 Verify the current Amiga-family disk builds

- Cross-link SQLite CLI builds for m68k AmigaOS, PowerPC AmigaOS 4 and
  PowerPC MorphOS. Recheck the missing socket-library startup diagnostic
  under vamos with the newly built m68k binary.

## 2026-11-18 Match WeKan REST card title updates

- Clear card titles with an explicit empty string in JSON and form PUT requests.
  Reject invalid title types before writing other fields, preserve omitted titles
  and return 404 for archived cards. Verify persistence and board rendering on
  both SQLite backends with the upstream card-title spec.

## 2026-11-18 Localize the two-factor setup password instructions

- Render the password setup instructions from the language catalog. Verify Finnish
  and Arabic on both SQLite backends over HTTP and in Chromium with JavaScript
  disabled and Cookie request headers removed. Other locales use the English fallback.

## 2026-11-18 Diagnose a missing Amiga TCP/IP stack

- Stop HTTP startup before socket calls when bsdsocket.library is unavailable.
  Verify the diagnostic and exit status with the m68k build under vamos.
  The offline initadmin command bypasses the socket requirement.

## 2026-11-18 Check the Amiga Free Pascal thread driver

- Verify that the linked scratch server can load `athreads` and reach
  native process creation with its maintenance worker enabled.

## 2026-11-18 Trace synchronous Amiga startup to the socket library

- Run a scratch linked server without worker threads and trace its next
  startup failure to the Amiga socket library call under vamos.

## 2026-11-18 Initialize the Amiga registry with linked SQLite

- Cross-link the full disk server in a scratch build and verify its
  global registry on Linux. Identify missing thread support at startup.

## 2026-11-18 Load the WeLite tenant schema with linked Amiga SQLite

- Execute the full tenant schema in a fresh database using the linked
  Pascal probe. Verify database integrity under vamos and on Linux.

## 2026-11-18 Write an Amiga SQLite database from linked Pascal

- Identify the default VFS lock error and verify a persistent JSONB write
  using SQLite's dotfile VFS under 68040 emulation. Reopen the file on Linux
  and verify its integrity and value.

## 2026-11-18 Execute linked Amiga SQLite in-memory SQL

- Open and close an in-memory SQLite database and return JSON through a
  Pascal callback under 68040 emulation. Trace the remaining file I/O failure.

## 2026-11-18 Run a vlink-linked Amiga SQLite version probe

- Strip GCC archive debug relocations and select library members through
  vlink. Verify SQLite 3.53.4 through the Pascal C interface under vamos.
  Record the outstanding database open failure.

## 2026-11-18 Identify the Amiga SQLite process requirements

- Compare the pinned Amiga Free Pascal process implementation with the
  one-shot CLI and read snapshot protocols. Record the missing streams
  and the required runtime behavior.

## 2026-11-18 Trace packaged Amiga startup to the SQLite child call

- Verify that the packaged executable opens its resources and writes
  registry SQL scripts. Record the emulator's missing Execute support.

## 2026-11-18 Verify the packaged Amiga resource lookup

- Observe the packaged m68k server opening its renamed resource under
  vamos. Verify exact schema bytes and missing-sidecar failure with a
  resource probe under the same basename.

## 2026-11-18 Package the Amiga external resource file

- Collect the resource bundle under the same basename as the executable.
  Verify the embedded pair and stale resource cleanup on a disk rebuild.

## 2026-11-18 Localize Designer missing-page responses

- Use the viewer catalog for missing pages in Designer edit, export and
  save routes. Verify Arabic profile and Finnish query selection on 404s.

## 2026-11-18 Localize Designer widget sorting controls

- Use the viewer's Sort caption and ASCII direction markers. Keep
  widget sort commands independent of the displayed text.

## 2026-11-18 Verify standalone SQLite build and startup instructions

- Build both native variants and launch each against a fresh standalone
  database. Verify the Finnish home response and the native database path.

## 2026-11-18 Verify Free Pascal AROS target availability

- Confirm x86 and AMD64 accept the AROS target and identify 32-bit ARM
  support in the pinned compiler source. Record the compiler support
  still required for AROS ARM64, m68k and PowerPC.

## 2026-11-18 Cross-link the MorphOS PowerPC server

- Build disk and embedded CLI variants on ARM64 Linux. Verify the ELF
  architecture and exact public, locale and private SQL bytes in the
  embedded output. Reverify all Windows x86 and AMD64 build variants.

## 2026-11-18 Localize Designer import and export controls

- Translate the Designer import and export actions. Identify the JSON and
  ZIP upload controls by file format and label both file inputs.

## 2026-11-18 Reverify the upstream REST suite

- Pass all 114 cases across 22 specs from WeKan `7f7389a217` against
  WeLite `8a7dd5c` on both Linux SQLite backends in shared mode.
  The REST browser cases use JavaScript and cookies disabled.

## 2026-11-18 Label Designer widget fields

- Associate widget settings with their controls and use the viewer
  catalog for Type, Label, Name and Sort.

## 2026-11-18 Localize Designer widget actions

- Use the page viewer's catalog for widget Add, Edit, Save and Delete
  controls and the page editor Preview link.

## 2026-11-18 Localize Designer page settings

- Translate the page title label, access choices, edit heading and Save
  control. Associate settings labels with their fields and keep the
  submitted save command and access values independent of the captions.

## 2026-11-18 Localize the Designer page list

- Use the viewer catalog for page-list headings, status, row actions and the
  empty state. Verify the RTL listing and language-preserving forms over HTTP.

## 2026-11-18 Localize attachment form validation

- Show the viewer-language filename validation message for rejected renames
  and the confirmation prompt when a delete is submitted without confirmation.
  Verify the RTL error pages and attachment preservation in the HTTP suite.

## 2026-11-18 Cross-link the AmigaOS 4 PowerPC server

- Verify disk and embedded PowerPC CLI builds on ARM64 Linux and record
  the FPC linker-script adjustments. Verify public, locale and private
  SQL bytes in the embedded executable.

## 2026-11-18 Check GNU linking for the Amiga SQLite probe

- Produce a mixed FreePascal and GCC Hunk executable with Amiga GNU ld.
  Its startup fails under vamos, as does the smaller GNU-linked C control.
  The vlink control still executes successfully.

## 2026-11-18 Verify FreePascal and C linkage on Amiga m68k

- Link and call a GCC C object from FreePascal under vamos. Locate the
  remaining static SQLite link failure in the compiler runtime archive.

## 2026-11-18 Create the WeLite schema with the Amiga SQLite shell

- Run the real CLI startup options and load the schema under vamos with a
  512 KiB stack. Verify the resulting database passes the integrity check.
  WeLite writes query scripts, but vamos does not execute its SQLite child.

## 2026-11-18 Execute JSON queries in the Amiga SQLite shell

- Build SQLite 3.53.4 in single-threaded mode with the existing Amiga
  VFS patches. Verify JSON and JSONB queries in vamos and read back a
  database written by the shell. The startup script still fails in vamos.

## 2026-11-18 Build an Amiga SQLite 3.53.4 shell

- Run the Amiga C cross-compiler through QEMU on ARM64 Linux. Link the
  upstream shell with the Amiga SQLite library and verify the version
  under vamos. SQL execution still hits an emulator memory error.

## 2026-11-18 Probe the Amiga SQLite command-line port

- Execute the m68k SQLite 3.34 shell under vamos and verify an on-disk
  write and read. Its build lacks JSON support, and the startup script
  hits an emulator file-handle error. A compatible SQLite CLI is still open.

## 2026-11-18 Verify m68k resource loading under vamos

- Execute a FreePascal m68k probe and compare the schema bytes read from the
  full resource sidecar with the source file. The server reaches tenant
  registry initialization. SQLite CLI and complete HTTP runtime remain open.

## 2026-11-18 Link the Amiga m68k server

- Link both CLI SQLite server variants with vlink 0.18a. Verify AmigaOS
  executable headers and check representative asset, locale, and SQL bytes
  in the resource build’s companion file. Amiga runtime remains open.

## 2026-11-18 Build the Amiga m68k cross-toolchain on ARM64 Linux

- Build native ARM64 assembler and linker tools, then the FreePascal m68k
  cross-compiler and target packages. Link a stripped AmigaOS probe.
  WeLite server units compile. Full linking and runtime remain open.

## 2026-11-18 Verify signed-in attachment navigation in retro browsers

- Open the board’s Attachments link in Dillo and NetSurf and verify the
  Finnish response, authenticated board return link and cookie-free session.

## 2026-11-18 Verify signed-in board navigation in retro browsers

- Open the board URL emitted by the signed-in home page in Dillo and
  NetSurf. Verify the Finnish board and signed-in attachment link render
  without cookies.

## 2026-11-18 Verify cookie-free sign-in in retro browsers

- Submit the Finnish sign-in form in Dillo and NetSurf at 640×480. Verify
  the login redirect and signed-in home page preserve the Finnish locale
  without sending or issuing cookies.

## 2026-11-18 Verify Finnish form submission in retro browsers

- Check that Dillo and NetSurf submit the selected Finnish locale and
  receive the matching Content-Language header without cookies.

## 2026-11-18 Verify the sign-in language form in retro browsers

- At 640×480, submit the sign-in language form in Dillo and NetSurf and
  verify its successful HTTP request and response carry no cookies.

## 2026-11-18 Verify cookie-free retro browser navigation on the wire

- Confirm Dillo and NetSurf exchange no cookies on the HTML4 board load
  and viewport change at 640×480 and 320×480. Retain the minimap color
  and navigation checks.

## 2026-11-18 Correct Arabic labels in browser controls

- Restore the webhook name, value defaults, attachment preview and upload
  captions where Arabic catalogs contained Persian text. Chromium verifies
  the webhook label in all four Arabic locales without JavaScript or cookies.

## 2026-11-18 Correct regional Arabic People captions

- Restore the Algerian, Egyptian, and Moroccan Arabic short-name labels
  from their WeKan catalogs. Verify each locale on the organization and
  team tables with JavaScript and cookies disabled.

## 2026-11-18 Localize the People short-name column

- Use the existing catalog label for organization and team short names.
  Restore the Arabic label from WeKan. Chromium verifies the column and
  RTL layout with JavaScript and cookies disabled.

## 2026-11-18 Render webhook validation errors in HTML

- Return an HTML error and a link back to settings after invalid browser
  submissions. Preserve the session and page language. Verify invalid
  create and edit requests leave the stored webhooks unchanged.

## 2026-11-18 Localize browser webhook access errors

- Render HTML for signed-out requests, board access denials and rejected
  form tokens. Keep the status codes and REST error responses. Verify a
  Finnish sign-in link and Arabic RTL denial without cookies.

## 2026-11-18 Pass the full upstream REST suite on CLI SQLite

- Pass all 114 cases across 22 specs with the regular SQLite CLI. Chromium
  workflows run with JavaScript and cookies disabled. Linked SQLite also
  passes the complete suite.

## 2026-11-18 Run upstream CLI tests with the ordinary SQLite executable

- Load the test-only SQLite proxy only for runs that exercise injected
  snapshot writes. The upstream assignment and attachment browser cases
  pass through the regular SQLite CLI with JavaScript and cookies disabled.

## 2026-11-18 Record verified shared database workflows

- Record the Linux shared-database coverage for permissions, restart,
  rollback, clone and export, and short SQLite sidecars. The current
  linked run passes 114 upstream REST cases and 112 shared HTTP checks.

## 2026-11-18 Link attachment management from published boards

- Render the attachment link in the board shared by direct and published
  views. The signed-in link preserves the current language and session.
  Native HTTP checks verify Finnish navigation and signed-out refusal.

## 2026-11-18 Localize the attachment preview link

- Use the existing Preview translation for the raster preview action.
  Verify the Finnish label in Chromium with JavaScript and cookies disabled.
- Recheck HTML4 minimap navigation on Linux Dillo and NetSurf at both
  640×480 and 320×480.

## 2026-11-18 Verify the HTML attachment list in embedded builds

- Run copied linked and CLI executables without external asset or schema
  directories. Verify localized attachment-list errors and the signed-in
  Arabic RTL empty state, without JavaScript or cookies.

## 2026-11-18 Recheck Windows builds after the attachment and session changes

- Cross-compile Windows x86 and amd64 with disk and embedded assets on both
  SQLite backends. Check console executable headers and SQLite DLL imports.
  The Windows resolver probes compile. Windows runtime checks remain open.

## 2026-11-18 Run the upstream REST suite as one selection

- Select all 22 REST specs with `WELITE_WEKAN_API_SPECS=all`. Document the
  options for each SQLite backend and for filtering by test title. The
  complete linked SQLite run passed 114 cases.

## 2026-11-18 Verify both upstream browser board export modes

- Pass 41 upstream core REST cases on shared linked SQLite. On both shared
  SQLite backends, download board JSON from HTML with JavaScript and cookies
  disabled and verify that only the full export contains the attachment bytes.

## 2026-11-18 Pass the upstream webhook settings REST spec

- Pass all six cases on shared linked SQLite. The HTML settings page shows
  accepted REST updates and deletions after reload, retains rejected state
  and sibling webhooks, and works with JavaScript and cookies disabled.

## 2026-11-18 Revoke individual browser sessions through the REST API

- Allow site administrators to revoke a private browser session by its
  stored digest. The next authenticated request is rejected and other
  sessions remain active.
- Pass all four upstream revocation cases on linked and CLI SQLite with
  JavaScript and cookies disabled in the browser case.

## 2026-11-18 Pass upstream custom-field update and deletion specs

- Pass all seven REST cases on shared linked SQLite. Verify accepted names
  and scoped deletion on the HTML board with JavaScript and cookies disabled.
  The board retains sibling fields and their values.

## 2026-11-18 Verify the upstream Version Control Attachments workflow

- Open the board's HTML attachment list to preview raster images, download
  original bytes, rename files, and confirm removal. The Chromium spec passes
  with JavaScript and cookies disabled on both shared SQLite backends.
- Previews require a valid browser session and board read access. Other file
  types are served as downloads, and only writers see edit forms.

## 2026-11-18 Remove card attachments from HTML

- Require board write access, a card-scoped form token and confirmation.
  Reuse REST deletion semantics. Shared stores retain recovery bytes, while
  native stores remove the file. Verify both with linked SQLite.

## 2026-11-18 Rename card attachments from HTML

- Board writers can rename a card attachment from a form. Keep its extension,
  storage identifier, and bytes. Verify the rename and rejection of a missing
  form token with JavaScript and cookies disabled on linked and CLI SQLite.

## 2026-11-18 Pass the upstream card attachment cascade spec

- Verify single and bulk REST card deletion and HTML selection deletion on
  linked and CLI SQLite in Chromium with JavaScript and cookies disabled. Upload through the HTML
  form and check that deletion records history and activity, preserves bytes
  for recovery, and leaves sibling attachments intact.

## 2026-11-18 Pass the upstream dropdown deletion REST spec

- All three cases pass against WeLite and FerretDB with linked SQLite.
  Chromium verifies that a rejected deletion preserves both choices and a
  successful deletion removes only the requested option. The selected value
  remains intact after reload with JavaScript and cookies disabled.

## 2026-11-18 Pass the upstream card overtime REST spec

- Native Chromium shows the spent-time or overtime heading after JSON and
  form REST edits. Both upstream cases pass, including validation and scope.

## 2026-11-18 Pass the upstream subtask REST spec

- The original parent, validation and permission assertions pass. Native
  Chromium opens the parent card and shows the REST-created child after reload.

## 2026-11-18 Pass the upstream card archive and restore REST spec

- Native Chromium confirms archived cards disappear and restored cards
  return on reload. The original REST and Mongo authorization tests pass.

## 2026-11-18 Pass the upstream card-sort REST spec

- Both cases pass in native Chromium mode. Verify the persisted sort and
  the rendered card order after reload with JavaScript and cookies disabled.

## 2026-11-18 Pass the upstream ownership REST spec

- Select WeLite mode in the upstream harness so the ownership spec uses
  native sign-in and board links. Both upstream cases pass while retaining
  their REST and Mongo assertions.

## 2026-11-18 Pass the upstream dropdown rename REST spec

- Native Chromium checks updated option labels and verifies the selected
  option ID is preserved after reload. All upstream cases pass.

## 2026-11-18 Pass the upstream card assignment REST spec

- Native Chromium checks that member and assignee changes appear after
  reload. All seven REST cases pass, including stale assignments and activity.

## 2026-11-18 Pass the upstream REST write scope spec

- Native Chromium verifies a wrong-list delete leaves the card and its
  checklist visible, and the valid delete removes both.

## 2026-11-18 Pass the upstream checklist REST spec

- Native Chromium shows the real checklist and its item after an incorrectly
  scoped REST read returns 404 and the card is reloaded.

## 2026-11-18 Pass the upstream People login-status REST spec

- Native Chromium verifies enabled and disabled login states on reload and
  confirms that a missing-user update leaves the People row unchanged.

## 2026-11-18 Pass the upstream organization and team feature specs

- Native Chromium verifies both feature tables after successful and rejected
  REST updates. All eight People cases pass against linked shared storage.

## 2026-11-18 Show organization and team features in People

- Render the organization and team feature flags on the native People page
  using the same public projection as the administrator REST list routes.
  Verify that REST updates appear after a cookie-free reload.
  Chromium checks both tables with JavaScript and cookies disabled and
  confirms that a missing-record update leaves the flag unchanged.

## 2026-11-18 Preserve language on dropdown form errors

- Show a localized HTML error and a return link to the card for rejected
  submissions. Verify Arabic direction and language without cookies.

## 2026-11-18 Edit dropdown values with native card forms

- Card editors can change assigned single-select fields without JavaScript
  or cookies. Reject missing options and replayed submissions, and verify
  field, card and option scope inside the write transaction.
  Chromium verifies that removing another option preserves the selection,
  and that choosing a replacement updates the native minicard.
  When the selected option is removed, the form starts blank and keeps the
  stored value until the editor explicitly chooses a replacement.

## 2026-11-18 Show custom fields on the native card page

- Show permitted values and current dropdown labels to card editors. Honor
  the board setting that hides custom fields on cards.

## 2026-11-18 Localize checkbox values on minicards

- Show localized Yes or No for a stored checkbox value, including false.

## 2026-11-18 Show dropdown option names on native minicards

- Resolve current option names for single and multiple selections in stored
  order. A renamed option appears after reload and its text is HTML-escaped.
  Chromium verifies a Mongo-backed option rename with JavaScript and cookies disabled.
  It also verifies a definition rename and confirms a rejected update leaves
  the accepted name and choice intact.
  A successful definition deletion removes the field from the minicard.

## 2026-11-18 Show custom fields on native minicards

- When enabled by the board, show permitted nonblank scalar field values
  and optional definition labels. Read the policy and values in one
  snapshot. Verify that REST label changes appear after reload and that
  read-only members cannot see admin-only fields.

## 2026-11-18 Add a Windows webhook resolver runtime check

- Compile the resolver probe for Windows x86 and amd64 and support running
  it with a configured runtime. The same probe passes on native Linux.

## 2026-11-18 Stream native multipart attachments into storage

- Copy from the temporary multipart file in bounded chunks. Keep the same
  file size, metadata transaction and file cleanup on failed registration.
  Chromium verifies a 262,400-byte file through upload, download and deletion.

## 2026-11-18 Check the Windows resolver imports

- Verify the Winsock startup, lookup, result disposal and cleanup imports
  in all eight Windows cross-builds.

## 2026-11-18 Verify native attachment upload and deletion together

- Upload a real file and delete its card via native HTML selection. Verify
  the FerretDB record retains its metadata and gains typed deletion markers,
  with one activity and a history entry whose hash matches the stored record,
  and the original file remains downloadable through the authorized API. The
  full shared CLI suite at `b20099e` also passed the four-byte upload and
  deletion scenario.

## 2026-11-18 Verify card attachment upload in Chromium

- Upload a file with a Unicode name through the native card form, then
  download and compare its bytes with JavaScript and cookies disabled. The
  linked and CLI shared-storage checks also verify the attachment metadata
  through FerretDB.

## 2026-11-18 Upload attachments from the native card page

- Card editors can submit a multipart file using the HTML form. Upload
  uses a one-use action token bound to the card and redirects back to the
  card without setting a cookie. Verify guest and read-only refusal, cross-card refusal, replay refusal
  exact downloaded bytes, and preservation of Arabic through the redirect.

## 2026-11-18 Share attachment persistence with the card upload work

- Extract the filesystem write and transactional metadata registration from
  the REST handler. The linked shared HTTP suite verifies existing uploads
  and cleanup on metadata failure.

## 2026-11-18 Translate the username caption during enrollment

- Reuse the translated username label beside the account name on the
  authenticator setup screen.

## 2026-11-18 Explain required enrollment in the selected language

- Use WeKan's two-factor requirement message after account creation.

## 2026-11-18 Translate enrollment restart links

- Retain the selected language on the setup links after failed credentials
  or an invalid confirmation code.

## 2026-11-18 Translate the enrollment confirmation heading

- Use the translated six-digit prompt as the heading and retry page title.

## 2026-11-18 Translate the sign-in link to two-factor setup

- The sign-in form uses the translated setup link and retains its resolved
  language when opening enrollment.

## 2026-11-18 Translate the registration link to two-factor setup

- The required-enrollment link uses the translated setup title and carries
  the selected language on the account-created page.

## 2026-11-18 Translate the two-factor setup heading

- Use the existing WeKan setup title across the initial, retry and
  confirmation-code setup screens. Verify the Arabic heading and the
  Chromium flow with JavaScript and cookies disabled on both backends.

## 2026-11-18 Translate successful two-factor enrollment

- Use WeKan's translated success message as the document title and heading.
  Verify Arabic enrollment and the cookie-free sign-in link on both SQLite
  backends.

## 2026-11-18 Verify the current embedded build on emulated Linux amd64

- At `427177f`, the embedded HTTP suite passes in QEMU on both SQLite
  backends, including the expanded locale catalog, translated errors and
  directory-free initialization. The CLI run uses the host SQLite executable.

## 2026-11-18 Verify bulk card attachment cleanup in Chromium

- After a bulk REST delete, both cards disappear on reload and their files
  disappear from the active attachment list. A sibling attachment remains
  downloadable with its original bytes. Deleting its card individually then removes
  the sibling attachment from the active list. The linked and CLI shared
  HTTP suites both passed these Chromium checks.

## 2026-11-18 Verify board ownership transfer in Chromium

- With JavaScript and cookies disabled, the target user can still see the
  card on a board where they have ordinary membership after reload.

## 2026-11-18 Transfer administered boards through the user API

- Implement the site-admin `takeOwnership` action. Transfer the target's
  board-admin memberships in one transaction and return board IDs and
  titles in board order. Ordinary memberships remain intact and a repeat
  returns an empty array. An interrupted transfer leaves both boards unchanged.

## 2026-11-18 Verify REST login changes in the native People panel

- The server-rendered People row reflects REST disable and enable requests
  after reload, and a missing-user update leaves the row unchanged. Check
  the stored flag and cookie-free response on both SQLite backends.

## 2026-11-18 Verify shared HTTP on CLI SQLite

- The full shared storage HTTP suite at `a9d7254` passed using CLI SQLite
  and the companion FerretDB server. The run covered Mongo/HTTP persistence,
  REST permissions and Chromium card workflows with JavaScript and cookies
  disabled.

## 2026-11-18 Translate the authenticator retry message

- Use WeKan's invalid-code translation in the native confirmation form.
  Verify the Arabic error and both retry actions through the cookie-free
  enrollment flow on linked and CLI SQLite.

## 2026-11-18 Translate authenticator setup prompts

- Reuse WeKan's translations for the manual-entry caption and six-digit
  confirmation prompt in the native enrollment form. Verify the Arabic
  prompts through the cookie-free setup flow on both SQLite backends.

## 2026-11-18 Associate translated enrollment labels with their inputs

- Give the username, password and one-time code native HTML labels. Verify
  the Arabic labels and the cookie-free enrollment flow on both SQLite
  backends.

## 2026-11-18 Verify narrow HTML4 board navigation in Linux NetSurf

- NetSurf 3.11 at 320×480 displays the minimap highlight and moves the
  viewport when the next marker is clicked, with JavaScript disabled.

## 2026-11-18 Localize missing page responses

- Use the existing page-not-found translation for the HTML title and body.
  Embedded HTTP tests check locale direction, 404 status and cookie-free
  responses on both SQLite backends.

## 2026-11-18 Cross-build the expanded language catalog

- The 245-language catalog cross-build passed for disk and embedded WeLite on
  Linux amd64 and Windows x86 and amd64, using both SQLite backends. Linux armhf
  and armv7 also passed the disk and embedded CLI build checks. These checks
  inspect the executable format and platform metadata. Runtime verification
  on Windows and ARM remains open.

## 2026-11-18 Localize HTML card and attachment 404 pages

- Use WeKan’s card-not-found translation and the existing attachment label.
  Embedded tests verify the HTTP status, language and direction with
  JavaScript and cookie-free requests.

## 2026-11-18 Finish the installed locale placeholder audit

- Correct the 397 remaining entries using current WeKan translations with
  identical English source and matching argument inventories. Add a test
  for the full installed catalog.

## 2026-11-18 Restore Arabic and Tamazight activity arguments

- Repair 160 named activity messages. Retain Arabic wording when the old
  arguments identify their source tokens and use current WeKan translations
  for ambiguous or wrong-language wording.

## 2026-11-18 Restore checklist activity arguments

- Fix 50 checklist and checklist-item activity strings in 35 catalogs.
  Preserve the checklist, item and card arguments required by the source.

## 2026-11-18 Restore comment arguments in translated activities

- Restore the missing comment argument in 45 edit and delete activity
  strings across 24 catalogs.

## 2026-11-18 Restore numbered translation placeholders

- Restore protected tokens in 515 entries across eight catalogs. Preserve
  the surrounding translated prose and verify argument inventories against
  English.

## 2026-11-18 Install 91 more language catalogs

- Add the remaining WeKan language identities with portable filenames,
  native names and direction metadata. Import the WeLite English key
  inventory and use English when a source value is missing or has
  incompatible placeholders.

## 2026-11-18 Correct another 80 Persian phrases in the Arabic catalog

- Match Persian vocabulary and the Persian catalog to find wrong-language
  entries that use shared letters. Use current WeKan Arabic translations
  and verify their placeholder inventories.

## 2026-11-18 Correct Persian entries in the Arabic catalog

- Replace 117 wrong-language entries with current WeKan Arabic translations.
  Preserve the English source’s placeholder tokens.

## 2026-11-18 Recover attachment history after an occupied writer gate

- A repeated attachment DELETE can append deferred removal history using
  the original deletion date, actor and batch. An existing removal row for
  that attachment and batch is retained.

## 2026-11-18 Append attachment removals to shared change history

- Record direct and cascaded removals with their batch, actor and original
  filename in the existing board hash chain when its writer gate permits.

## 2026-11-18 Retain shared attachments after HTML selection deletion

- Mark attachments from selected cards, lists and lanes in the same
  transaction as selection deletion. Preserve their bytes for recovery and
  omit them from live listings.

## 2026-11-18 Retain shared attachments after REST card deletion

- Single and bulk card deletion mark the card’s active attachments under one
  batch in the card deletion transaction. Preserve file bytes and leave
  earlier deletion markers intact.

## 2026-11-18 Retain shared files after REST attachment deletion

- Record a typed deletion date, actor and batch. Clear the card cover and
  record a deletion activity in the same transaction. Keep the attachment
  metadata and bytes available for recovery.

## 2026-11-18 List REST attachments by board, lane, list or card

- Support the shorter WeKan attachment listing paths. Verify board and
  resource ownership and omit records marked deleted in shared storage.

## 2026-11-18 Verify foreign-card dependency route scope

- Exercise foreign-card dependency GET, POST, PUT and DELETE requests in the
  native scope suite, including rollback-free rejection of every request.

## 2026-11-18 Accept binary REST attachment uploads

- Accept octet-stream uploads with query-string metadata alongside JSON
  base64 uploads. Recheck board and resource scope when recording the
  attachment, and clean up the staged file if registration fails.

## 2026-11-18 Download attachments from HTML card details

- Show active attachments for signed-in viewers. Downloads use the browser
  session in the link and verify the board and card before sending file bytes
  with the stored filename.

## 2026-11-18 Stream raw REST attachment downloads

- Serve exact attachment bytes when callers request `raw=1`. Keep the
  base64 JSON format for existing callers. Both formats check board access
  and return 404 if the stored file is missing.

## 2026-11-18 Show subtasks on HTML card details

- Link to active subtasks on the same board. Chromium verifies that a
  REST-created subtask appears after reload and disappears when archived,
  with JavaScript disabled and cookies stripped.
- Card GET returns the saved parent ID when its board is readable.

## 2026-11-18 Show members and assignees on HTML card details

- Show the usernames assigned to the card in separate lists. Chromium
  verifies that REST additions and removals appear after reload with
  JavaScript disabled and cookies stripped.

## 2026-11-18 Correct Arabic board and spent-time labels

- Use the Arabic values from WeKan’s current catalog. Verify both labels
  on the right-to-left HTML card page in Chromium.

## 2026-11-18 Show spent time and overtime on HTML card details

- Render the saved hours with the appropriate heading when the board permits
  spent time. Chromium verifies JSON and form REST changes after reload with
  JavaScript disabled and cookies stripped.

## 2026-11-18 Open card checklists from the HTML board

- Click a card title to read its description, checklists and items without
  JavaScript or cookies. Check board and card scope before rendering.
- Verify that a failed REST checklist lookup leaves the real checklist and
  items visible after reload.

## 2026-11-18 Verify REST card ordering in Chromium

- A REST sort value of zero is readable through the API and moves the card
  ahead of its sibling after reload with JavaScript disabled and cookies
  stripped.

## 2026-11-18 Honor custom roles in REST dependency edits

- Check shared custom role write and move-card capabilities during dependency
  edits. Respect assignment scope and retain saved membership flags when the
  role definition is removed.

## 2026-11-18 Support legacy dependency targets in REST

- Read bare BSON string targets with default styling. Edit or delete the
  selected row while retaining untouched siblings. Reject ambiguous duplicates
  and preserve BSON lookalikes. Allow a first dependency in a null array.

## 2026-11-18 Verify REST card archive and restore in Chromium

- With JavaScript disabled and cookies stripped, the board hides archived
  cards and shows restored cards after reload. Unauthenticated and repeated
  archive or restore requests are rejected.

## 2026-11-18 Verify wrong-list card deletion in Chromium

- With JavaScript disabled and cookie headers stripped, a wrong-list REST
  delete keeps the card visible and its checklist readable. Deletion through
  the correct list removes both records. A repeated delete returns 404.

## 2026-11-18 Add REST board domain routes

- Site administrators can read the dedicated domains endpoint. Authorized
  board reads include their domains. Board or site administrators can add and
  remove domains within a guarded transaction.
- Normalize encoded domain names on deletion, preserve sibling domains, and
  return the upstream JSON 404 for missing entries.

## 2026-11-18 Add REST card dependency routes

- Read card dependencies and board dependency lines. Create, update and delete
  structured entries with board and card scope checks. Re-adding a target
  updates its existing entry.
- Pass upstream dependency CRUD and unauthenticated-request cases on both
  linked and CLI SQLite.

## 2026-11-18 Add audited administrative REST token issuance

- Issue a bearer for an active account through `POST /api/createtoken/:userId`
  when a site administrator supplies a reason. Store the impersonation audit
  record in the same transaction as the bearer and its shared resume entry.
- Pass the three upstream REST token issuance and revocation cases.

## 2026-11-18 Add administrative REST token revocation

- Return a JSON 404 for missing users. Revoke all sessions or one shared
  stored hash with a transactional site-admin check and secret-free responses.

## 2026-11-18 Require administrators for REST board renames

- Require active board administration or site administration. Recheck
  permission and the stored title within the same write transaction.

## 2026-11-18 Scope REST swimlane deletion and roll back failures

- Return the upstream JSON 404 for missing, foreign or already-deleted
  swimlanes. Delete the lane and its cards in one transaction.

## 2026-11-18 Verify plain-text descriptions in both board downloads

- The browser and HTTP export fixtures check that formatted card text
  becomes plain text and script content is omitted. The stored
  description remains intact.

## 2026-11-18 Verify both board export links in Chromium

- Download both JSON variants without JavaScript or cookies. Verify
  the attachment metadata in each and the exact file bytes in the
  variant that includes files.

## 2026-11-18 Verify REST webhook changes in the HTML settings page

- Chromium checks that a reload reflects accepted edits and deletion,
  preserves rejected changes, and leaves sibling webhooks intact.

## 2026-11-18 Manage webhooks through HTML forms

- Board admins can create, edit and delete webhooks without JavaScript or
  cookies. Form tokens bind the action to the board and integration.

## 2026-11-18 Render outgoing webhook settings without JavaScript or cookies

- Show board admins the current webhook settings from native and shared
  stores. Link the page from the board and reflect REST mutations on reload.

## 2026-11-18 Resolve webhook destinations through Winsock on Windows

- Apply the public IPv4 and IPv6 destination policy to Winsock results.
  Verify resolver imports in x86 and AMD64 builds for both SQLite backends.

## 2026-11-18 Store REST integrations in native SQLite

- Add board-scoped integration CRUD to native stores. Existing stores
  gain the table on open, and board deletion removes its integrations.

## 2026-11-18 Create and update shared webhook integrations over REST

- Board admins can create integrations and update their destination on
  Linux using validated public HTTP(S) addresses. Preserve typed defaults
  and unrelated fields. The four upstream integration REST cases pass.

## 2026-11-18 Provision fresh strict shared databases through WeLite

- In explicit strict shared mode, initialize a fresh `wekan.db` with the
  same empty-schema guard as normal shared mode. Verify live FerretDB
  discovery and preservation of existing native databases.

## 2026-11-18 Verify strict shared SQLite sidecars with FerretDB

- Exercise both WeLite SQLite backends against FerretDB’s strict driver.
  Verify live short WAL/SHM, cookie-free sign-in and API bearer reuse
  after restarting WeLite while FerretDB keeps the database open.

## 2026-11-18 Check live 8.3 SQLite sidecars on native Linux

- Assert linked SQLite creates `wekan.wal`, `wekan.shm` and a short
  rollback journal. Allow either database backend to run independently
  in the short-filename test suite.

## 2026-11-18 Share wekan.db with FerretDB using normal sidecars

- Verify Mongo and HTTP access to the same `wekan.db` when FerretDB uses
  `dbext=db` and WeLite uses explicit shared mode.
- Refuse a sidecar layout incompatible with the selected filename mode.

## 2026-11-18 Provision new tenants in shared format by default

- Default to a canonical FerretDB SQLite database on compatible
  backends. Preserve explicit native mode, existing native tenants
  and native provisioning on strict short-name builds.

## 2026-11-18 Detect existing canonical shared stores by default

- Activate a registered `wekan.sqlite` when `WELITE_SHARED` is unset.
  Keep native provisioning for empty paths and preserve explicit
  mode selection, the admin registry and ambiguous-file checks.

## 2026-11-18 Verify live discovery of freshly provisioned shared databases

- Verify that a running FerretDB server discovers a new WeLite store
  through Mongo lookup and database listing, then use a Mongo-created
  account for API and cookie-free HTML sign-in.

## 2026-11-18 Provision fresh canonical shared stores through HTTP

- In explicit shared mode, initialize an empty public tenant store at
  `wekan.sqlite` and open it with FerretDB. Preserve existing normalized
  files and refuse ambiguous paths and orphan sidecars.

## 2026-11-18 Verify shared registry errors and repair without restarting

- Verify that Mongo find reports malformed SQLite registration settings
  and reads the new collection once the settings are repaired.

## 2026-11-18 Verify live FerretDB discovery of shared history collections

- Read and list history collections created by WeLite while the same
  FerretDB process runs. The shared HTTP suite requires a build with
  live SQLite registry discovery.

## 2026-11-18 Keep unverifiable regular expressions pending

- Preserve the pending row and chain head when BSON regex patterns and
  options are absent from both hashes after WeKan’s default Mongo read.

## 2026-11-18 Recover coordinated history with additional BSON types

- Hash Long, Timestamp, ObjectId and Binary as WeKan’s Mongo driver
  reads them, then preserve their exact BSON values during recovery.

## 2026-11-18 Recover coordinated reservations with legacy row hashes

- Accept the legacy digest forms WeKan verifies for omitted undefined
  content keys and empty IDs or labels cleaned to null or omitted.
- Require both the pending digest and the row digest before recovery.

## 2026-11-18 Recover coordinated history containing fractional positions

- Match WeKan’s finite double serialization, including shortest decimal
  rounding, exponent cutoffs, subnormal values and negative zero.
- Verify and finalize a pending card position change containing a fraction.

## 2026-11-18 Recover typed coordinated card history reservations

- Validate both WeKan hashes from the stored BSON types and recover
  saved or unsaved reservations with dates, nested objects, arrays and
  safe integers before appending the next list lifecycle row.

## 2026-11-18 Retire expired orphan history writer leases

- Fence claimed rows and retire expired leases whose writer tokens
  are absent from a valid legacy or draining gate.

## 2026-11-18 Retire expired history writers during gate draining

- Recover expired leases and fence their claimed rows in a valid
  draining gate. Preserve the migration ID and keep appends paused.

## 2026-11-18 Recover expired leases in multi-writer legacy gates

- Retire each eligible writer and keep sibling tokens in their
  original order. Defer new history while any writer remains.

## 2026-11-18 Fence claimed rows from expired legacy writers

- Preserve an already written history row or reserve its claimed ID
  with a tombstone before retiring the expired lease.

## 2026-11-18 Retire idle expired legacy history leases

- Remove an expired legacy lease and its writer token together when
  the writer has no claimed row, then append the list lifecycle change.

## 2026-11-18 Recover unsaved coordinated list history reservations

- Insert a validated reserved list lifecycle record and advance the
  coordinated head in one SQLite transaction.

## 2026-11-18 Finish saved list history reservations

- Advance the coordinated head when a validated list lifecycle
  reservation already has its exact row in shared history.

## 2026-11-18 Append list history through an idle legacy writer gate

- Allow a list lifecycle change to extend the legacy history chain when
  the WeKan writer gate is valid and idle throughout the SQLite transaction.

## 2026-11-18 Verify HTML4 board navigation in Linux NetSurf

- Verify minimap color and viewport navigation in NetSurf 3.11 at
  640×480 with JavaScript disabled and a fresh browser profile.

## 2026-11-18 Verify HTML4 board navigation in Linux Dillo

- Run Dillo 3.0.5 at 640×480 and 320×480 with cookies denied. Verify that the
  minimap renders the current color and that clicking the next cell
  moves the viewport and the highlight.

## 2026-11-18 Verify the embedded amd64 SQLite CLI process

- Pass the embedded HTTP suite under QEMU with both the WeLite binary
  and the SQLite CLI running as amd64 code.

## 2026-11-18 Verify embedded amd64 boards under QEMU

- Verify RTL HTML4, directory-free bootstrap, and clean shutdown on
  both embedded SQLite backends. The linked build uses amd64 SQLite.

## 2026-11-18 Verify HTML4 boards in embedded deployments

- Test an RTL HTML4 board from a copied standalone executable on both
  SQLite backends. Recheck disk and embedded Linux amd64 and Windows
  x86 and amd64 cross-builds.

## 2026-11-18 Use HTML 4.01 on the standalone board

- Declare HTML 4.01 Transitional for board pages and give HTML4 pages a
  device-width viewport. Verify narrow board navigation in Chromium.

## 2026-11-18 Show card spent time on the HTML board

- Render recorded hours with the translated spent-time or overtime
  label. Respect the board's minicard visibility setting.

## 2026-11-18 View subtasks on the HTML board

- Open or close a card's same-board subtask list with an ordinary link.
  Preserve the board view and session without JavaScript or cookies.
  Verified opening and closing in Chromium with both disabled.

## 2026-11-18 Update shared organization and team flags in bulk

- Let site administrators set one feature flag across the selected
  collection in a single transaction and return the number of records.

## 2026-11-18 List shared organization and team features through REST

- Return organization and team names and feature flags to site
  administrators. Treat missing flags as false.

## 2026-11-18 Update shared organization and team features through REST

- Let site administrators update shared template, membership propagation,
  and authentication sync flags on existing shared organizations and teams.
  Reject missing records and preserve unrelated stored settings.

## 2026-11-18 Manage account login through REST

- Let site administrators enable or disable a user's login. Disabling
  revokes sessions, protects the acting administrator from self-lockout,
  and returns account status without authentication secrets.

## 2026-11-18 Update shared integration settings through REST

- Let board administrators edit integration titles, enabled flags, and
  activity selections atomically while preserving unrelated fields.

## 2026-11-18 Read and delete shared integrations through REST

- Scope integration reads and deletes to the requested board. Hide tokens
  on reads and restrict webhook URLs and deletion to administrators.

## 2026-11-18 Verify upstream API regressions on SQLite CLI

- Pass twelve unchanged WeKan API cases covering assignment removals,
  overtime validation, parent creation, and checklist read scope.
  Document the shared test harness's CLI backend selector.

## 2026-11-18 Honor parent IDs on REST card creation

- Store visible parent card references, validate parent input, and
  refuse missing or inaccessible parents before inserting a card.

## 2026-11-18 Match REST card description validation

- Clear card descriptions with a null or empty value. Reject invalid
  description types before applying any part of the card update.

## 2026-11-18 Record REST card assignment additions

- Store member and assignee addition activity with the target username
  in the same transaction as the assignment. Repeated adds are idempotent.

## 2026-11-18 Record REST card assignment removals

- Record member and assignee removals atomically, including stale
  assignments to deleted accounts. Repeated removals leave history
  unchanged. Match upstream card scope and inactive-member errors.

## 2026-11-18 Preserve zero and fractional REST card sort values

- Store and return numeric sort values for JSON and form edits, including
  zero. Reject invalid sort values before applying any card edits. A regression checks the new order in cookie-free HTML
  after loading and reloading the board.

## 2026-11-18 Match checklist read scope errors

- Return the card-scope JSON 404 for a missing or foreign card and the
  checklist-scope JSON 404 for a missing or foreign checklist.

## 2026-11-18 Match REST card overtime validation

- Accept booleans and the strings `true` and `false` in `isOverTime` edits,
  store the canonical `isOvertime` field, and reject invalid requests
  before applying any card edits.

## 2026-11-18 Select upstream REST regression files

- Allow the shared HTTP harness to run named WeKan Playwright specs
  against an isolated WeLite and FerretDB instance.

## 2026-11-18 Restore card covers on board import

- Set the new cover ID when a card's own cover attachment is imported.
  Leave covers unset when their source attachments are unavailable.

## 2026-11-18 Restore attached card links on board import

- Remap linked cards in source order. Omit duplicates, self-references,
  and targets outside the export.

## 2026-11-18 Restore card dependencies on board import

- Remap typed dependencies and legacy string references to the imported
  cards. Omit references to cards outside the export.

## 2026-11-18 Preserve card numbers on board import

- Keep valid source card numbers and fill gaps for missing or duplicate
  numbers. New cards continue above the imported maximum.

## 2026-11-18 Preserve card colors on board import

- Keep palette and custom card colors. Use the default appearance for
  unknown colors.

## 2026-11-18 Open collapsed lists from the HTML board

- Respect stored collapse defaults. Expand and close a list using links
  that preserve the current board view, language, and session.

## 2026-11-18 Preserve shared list collapse on board import

- Store explicitly collapsed or expanded lists and leave the flag unset
  for older exports. Upgrade existing native tenant databases in place.

## 2026-11-18 Preserve list and swimlane settings on board import

- Import list widths, list and swimlane colors, and archived status.
  Use defaults for unsupported colors and out-of-range widths.

## 2026-11-18 Restore card placement in older board exports

- Recover cards with missing lists or swimlanes using the first imported
  list and a compatible swimlane. Create default containers when needed,
  and store attachment locations with their restored cards.

## 2026-11-18 Recover card creation data from board exports

- Prefer matching card creation events for creation dates and mapped
  authors. Fall back to card data when the export lacks usable events.

## 2026-11-18 Preserve scheduling data on board import

- Restore card creation and scheduling dates, elapsed time, overtime and
  archived flags, and the free-text requester and assigner fields.

## 2026-11-18 Import board labels and references

- Copy labels with new board-local IDs and remap references on cards,
  triggers, and actions. Reject dangling label references and collapse
  duplicate assignments on the same card.

## 2026-11-18 Import board custom fields

- Copy board custom-field definitions and settings with new field IDs.
  Keep dropdown option IDs and order so existing selections remain valid,
  and remap card values to the imported definitions in the same transaction.

## 2026-11-18 Map imported card participants

- Apply explicit account mappings to card member, assignee, requester and
  assigner lists. Deduplicate mapped accounts and omit unmapped references.

## 2026-11-18 Map board import authors to local accounts

- Resolve explicit member mappings to enabled local accounts. Preserve
  mapped authorship without giving imported board members active access
  or administrator privileges.

## 2026-11-18 Import board attachment bytes

- Import embedded Base64 files with new attachment IDs and remapped card
  references. Remove staged files if the board import fails.

## 2026-11-18 Import board comments and checklists

- Import comments, checklists, and checklist items with mapped card and
  checklist IDs. Preserve checklist dates and completion. Attribute
  imported comments to the caller until member mapping is available.

## 2026-11-18 Import board structure and workflows over REST

- Import boards, lanes, lists, cards, and shared workflows in one transaction
  with remapped identities. Apply the instance import and board creation
  policies and create the imported board as private.

## 2026-11-18 Record rejected parent references

- Count blocked parent references in the shared security event log without
  recording the hidden card or board identifiers.

## 2026-11-18 Remove owned workflows on board deletion

- Require board administration for REST board deletion and remove owned
  rules, triggers, actions, and webhook rows in the same transaction.

## 2026-11-18 Copy shared board workflows and webhooks

- Copy a board’s rules, triggers, actions, and webhook records with fresh
  identities. Commit them with the board, apply board creation policy, and
  return the new board ID in the WeKan REST response format.

## 2026-11-18 Copy cards over REST

- Reuse the typed clone transaction for card copies, including subtasks,
  checklists, and comments. Validate destination write access, preserve
  comment attribution and creation time, and support zero-based placement.

## 2026-11-18 Delete shared rules over REST

- Remove a board rule and its unused primary or additional workflow parts
  in one transaction. Retain parts referenced by other rules.

## 2026-11-18 Edit shared rules over REST

- Update rule titles, enabled state, and workflow parts in one transaction.
  Preserve existing fields and copy a part when another rule references it.

## 2026-11-18 Create rules over REST in shared storage

- Add board-admin rule creation with typed triggers and actions in one
  transaction. Apply default matching fields to activity-driven triggers.

## 2026-11-18 Read board rules over REST

- Add authenticated board-scoped rule collection and individual reads.
  Embed ordered triggers and actions from the shared workflow snapshot.

## 2026-11-18 Include shared board workflows in JSON export

- Read board rules and their referenced triggers and actions in the same
  snapshot as the board, including additional rule parts.

## 2026-11-18 Include participant identities in board JSON

- Export board participants and activities with an explicit user field
  allowlist. Include usernames and basic names or initials when present.

## 2026-11-18 Download board JSON without JavaScript or cookies

- Add native board links for JSON downloads with and without attachment file
  data. Use the existing browser session and shared export checks.

## 2026-11-18 Export whole boards over REST

- Add authenticated whole-board JSON export through the typed selection
  snapshot. Support omitting attachment file data and enforce custom-field
  access and the shared instance export restriction.

## 2026-11-18 Edit card completion, stickers and locations over REST

- Persist the due-complete checkbox and replace sticker and location arrays
  through card PUT. Validate decorations before writing, generate location
  IDs when absent, and store coordinates as numbers.

## 2026-11-18 Create linked cards over REST

- Create a linked card from an eligible source when `linkedId` is supplied.
  Recheck source and destination write access and placement in the same
  transaction as the linked card and its creation activity.

## 2026-11-18 Create boards over REST

- Create the board, caller ownership and default swimlane in one transaction.
  Honor the shared admin-only creation and private-only visibility settings.

## 2026-11-18 Add and remove board members over REST

- Require board or site administration, accept named roles, and reject
  disabled accounts and mismatched actions. Retain inactive membership for
  reactivation and protect the last active board administrator.

## 2026-11-18 Delete users over REST

- Require site administration and commit account removal with credential
  cleanup. Return the removed ID or a 404 when the user is absent.

## 2026-11-18 List the current user's cards over REST

- Add the authenticated My Cards endpoint with due-date bounds, active board
  membership checks, and the assignee constraint for assigned-only roles.

## 2026-11-18 Read and update board card settings over REST

- Expose board card display flags and aging thresholds. Use board defaults
  for absent settings and require board administration for partial writes.

## 2026-11-18 Merge card labels in REST batches

- Add the board-scoped bulk label route. Validate additions against the board,
  preserve unrelated card labels, deduplicate additions, and report missing
  cards. Pass the site-admin option through the board label creation guard.

## 2026-11-18 Read and edit swimlanes over REST

- Add board-scoped GET and PUT for individual swimlanes. Return the active
  swimlane on GET and validate the title and current write permission on PUT.

## 2026-11-18 Delete REST cards in batches

- Add the board-scoped bulk-delete route with deleted and missing ID lists.
  Single and bulk card removal commit the cascade and one delete activity
  together while retaining earlier activity history.

## 2026-11-18 Create REST cards in batches

- Add the bulk-create route with indexed results, bounded input, placement
  checks, parent visibility, assignment arrays and custom-field defaults.
  Single and bulk REST creates allocate board card numbers in their insert
  transaction from the existing board cards.

## 2026-11-18 Store empty card assignment arrays over REST

- Initialize members and assignees on single-card creation. Explicit clears
  normalize missing or null shared fields to typed empty arrays without
  changing unrelated BSON fields.

## 2026-11-18 Set and clear card dates over REST

- Persist received, start, due and end dates as typed BSON dates in shared
  storage. Clear them with an empty string, null, or the string `null`.
  Live tests verify field removal and preservation on invalid input.

## 2026-11-18 Revoke REST bearer tokens on logout

- Add `POST /users/logout` with single-token and logout-everywhere modes.
  Shared resume tokens and local credentials are revoked in one transaction.
  Default logout preserves other sessions.

## 2026-11-18 Require board administration for REST label creation

- Allow board and site admins to create labels and recheck authorization in
  the write transaction. Match WeKan’s bare JSON label ID, validate the
  color, and reuse existing labels with the same trimmed name and color.

## 2026-11-18 Run upstream REST API specs against WeLite

- Add an opt-in runner that points WeKan’s unchanged REST specs and MongoDB
  fixtures at an isolated WeLite and FerretDB instance. Allow filtering by
  test title when working through parity failures.

## 2026-11-18 Validate coordinated history gates and idle heads

- Check the gate shape and migration UUID and require a numeric version and
  a valid predecessor hash before appending. Live FerretDB coverage checks
  that malformed gate and head data leave the chain unchanged.

## 2026-11-18 Reuse the shared HTTP browser session

- Use the same cookie-free browser session for list restore and the profile
  checks so the fixture stays within the sign-in limit. The linked SQLite
  shared HTTP suite passes end to end.

## 2026-11-18 Verify preservation of occupied history heads

- Exercise a shared list deletion while WeKan owns a pending reservation.
  Confirm that the reservation and history records are preserved.

## 2026-11-18 Append list history to idle coordinated heads

- Verify the WeKan coordinated gate and empty pending slot, then insert the
  list lifecycle record and advance the board head in one SQLite transaction.
  Live FerretDB verifies the new head and its predecessor link.

## 2026-11-18 Append list lifecycle history on shared legacy boards

- Write typed deletion and restore records to shared changeHistory with a
  guarded chain-tip link. Defer to WeKan on boards with a writer gate or
  coordinated head.

## 2026-11-18 Chain native list deletion and restore history

- Record typed lifecycle content and WeKan-compatible hashes in native
  SQLite. Verify the board's current tip before appending and retry a
  concurrent tip change. Shared change-history integration remains open.

## 2026-11-18 Verify WeKan list lifecycle integrity hashes

- Build the canonical list lifecycle hash and compare it with WeKan's
  implementation for delete and restore records. Change-history append
  integration remains open.

## 2026-11-18 Provision position history in shared FerretDB stores

- Create the missing position-history collection using the shared collection
  registry format. Verify typed delete and restore records over Mongo wire
  after restarting FerretDB to refresh its database registry cache.

## 2026-11-18 Persist list position history in native SQLite

- Create the private position-history table when needed and store typed
  deletion and restore records with the same board, actor and batch.

## 2026-11-18 Record shared list deletion and restore in position history

- Append WeKan position-history records when the shared collection exists.
  Preserve the list position, typed dates and deletion batch. Clear redo
  entries for the same actor and board in the history write transaction.

## 2026-11-18 Verify list restore in Chromium without JavaScript or cookies

- Exercise the actual HTML form, confirm the deleted list stays off the
  board until restored, and verify its card returns with the list.

## 2026-11-18 Bind list restore to the displayed deletion batch

- Reject stale restore forms when the list has a different deletion batch.
  Verify tamper refusal and unchanged markers over native HTTP.
- The shared CLI SQLite run also verified BSON restore and rollback.

## 2026-11-18 Restore shared list batches without BSON null markers

- Clear deletion fields with WeKan's unset semantics. Live linked
  FerretDB tests verify byte-exact restore and rollback from the HTML form.

## 2026-11-18 Restore deleted list batches from the HTML board

- Render a restore form for board writers. Bind the action token to the
  board and list, then clear deletion markers for the list and its matching
  card batch in one transaction. The form needs no JavaScript or cookies.

## 2026-11-18 Verify list deletion markers on live FerretDB

- Verify matching BSON date, actor and batch markers on retained lists and
  cards. A failed write restores both source documents byte-for-byte.

## 2026-11-18 Soft-delete lists and their cards through REST

- Mark a list and its live cards with the same deletion batch in one
  transaction. Keep their rows and hide them from board HTML, selection
  and normal REST reads. Failed writes roll back the whole batch.

## 2026-11-18 Store reversible deletion metadata for lists and cards

- Map the WeKan deletion date, actor and batch IDs in fresh native SQLite
  and shared FerretDB models. Upgrade existing native stores concurrently
  without dropping rows. REST soft deletion and undo handling remain open.

## 2026-11-18 Place new REST lists in the requested or default swimlane

- Honor a same-board swimlane and prefer the first active swimlane for
  omitted values. Assign the initial sort from the active list count and
  reject invalid placement without creating a list.

## 2026-11-18 Report list and card change dates through REST

- Return modifiedAt and cardsModifiedAt in the list collection. Include
  archived card changes, normalize valid timestamps to UTC and use null
  when no usable date exists. Stamp list creation, edit and archive changes.

## 2026-11-18 Return active list metadata through REST GET

- Return list color, starred state, timestamps and nested WIP settings.
  Missing, archived and out-of-board lists return the WeKan JSON 404.

## 2026-11-18 Verify list edits against live FerretDB

- Verify list PUT preserves nested BSON WIP values and explicit booleans.
  Invalid color and non-admin WIP edits leave the list unchanged.

## 2026-11-18 Edit list metadata and WIP limits through REST

- Add scoped list PUT for title, color, starred state and WIP limits.
  Validate changes before writing and require board administration for
  WIP changes. Apply the accepted fields in one transaction.

## 2026-11-18 Archive and restore lists through REST

- Add board-scoped archive and unarchive routes with WeKan responses.
  Reject repeated operations without writing. Apply template-list card
  transitions in the same transaction while preserving ordinary list cards.

## 2026-11-18 Change card archive state through REST PUT

- Authorize archive-only PUT by board and card so callers can restore cards
  without the current list ID. Repeated requests preserve the stored row.
- Keep list scope for requests that also change card fields or relations.

## 2026-11-18 Archive and restore cards through separate REST routes

- Add unarchive and make the archive transitions check the current state,
  board and list. Repeated requests return the WeKan JSON 404 without writing.
- Preserve the existing explicit isArchive form behavior.

## 2026-11-18 Match WeKan scoped card GET behavior

- Read an active card from the authorized board and requested list. Return
  the same JSON 404 for missing, wrong-list and archived cards. Global card
  GET continues to return authorized archived cards.

## 2026-11-18 Read a card by ID through the global REST route

- Add authenticated card GET by ID, including archived cards and embedded
  checklists. Resolve the board, verify read access and bind serialization
  to the board that was authorized.

## 2026-11-18 Include checklists in scoped card GET

- Return the card's checklists with ordered items, completion state and
  deadlines. Reuse the checklist collection response builder.

## 2026-11-18 Include items and deadlines in checklist collection responses

- Use the same scoped checklist representation for collection and individual
  GET. Return ordered items, completion state and nullable deadlines.

## 2026-11-18 Verify checklist CRUD with live WeKan-shaped FerretDB documents

- Resolve legacy checklists and items without a redundant board ID via their
  parent card. Keep rejecting records that explicitly name another board.
- Verify native BSON dates, deadline clearing and item cascades through live
  shared HTTP.

## 2026-11-18 Store checklist-item deadlines through REST

- Accept deadlines when adding or updating an item and include them in item
  GET. Keep omitted values unchanged and clear deadlines on JSON null.
- Apply title, completion and deadline updates together. Return the item ID
  from PUT and report storage errors.

## 2026-11-18 Create checklist deadlines and ordered items through REST

- Validate the checklist deadline and initial items before writing. Create
  the checklist and its items in one transaction and report storage failures.

## 2026-11-18 Update checklist titles and deadlines through REST

- Add scoped checklist PUT with atomic title and deadline validation.
  Normalize timezone offsets to UTC, leave omitted values alone and clear
  deadlines on explicit JSON null. Checklist GET includes deadline fields.

## 2026-11-18 Store checklist and checklist-item deadlines

- Add nullable deadline columns to fresh and legacy native SQLite stores.
  Verify concurrent upgrades, preserved rows and refusal of incompatible columns.
- Map the new columns to typed dates in the shared FerretDB model. Checklist
  deadline API handling remains open.

## 2026-11-18 Delete a checklist through the card REST API

- Register scoped checklist DELETE and return the WeKan JSON response.
  Checklist items cascade within the transaction. A storage failure rolls
  back the deletion, and an unrelated checklist remains unchanged.

## 2026-11-18 Select a SQLite backend for shared HTTP tests

- Label each backend pass and allow targeted linked or CLI runs. The default
  still exercises both backends.

## 2026-11-18 Match the WeKan custom-field GET error

- Return HTTP 404 with the WeKan JSON error when a custom field is missing or
  outside the requested board. Verify the body before and after deletion.

## 2026-11-18 Update and delete multi-board custom fields

- Require field write access on all bound boards and recheck the binding set
  during the transaction. Backfill and deletion cover the authorized boards.
- Native and live shared HTTP coverage verify refusal without data changes when
  one board is archived and verify cleanup across both boards after authorization.

## 2026-11-18 Remove scoped activity when deleting a custom field

- Delete activity records for the field on the authorized board in the same
  transaction as the definition and card values. Preserve sibling activity and
  roll back all three on a failed definition write.

## 2026-11-18 Backfill always-on custom fields on existing cards

- Enabling always-on for a single-board definition fills missing values with
  null on existing board cards. Assigned values and cards on other boards are
  left in place. The definition update and backfill roll back together.

## 2026-11-18 Reconcile implementation and platform documentation

- Document the current tenant layout, authentication, SQLite modes and build entry
  point. Describe the verified Chromium workflow and separate platform runtime
  coverage from cross-build checks.
- Document the custom-field REST routes and remaining compatibility limits.

## 2026-11-18 Archive completed implementation checklist items

- Audit the current implementation and record the remaining work (2026-11-16).
- Move lists up/down across swimlanes, preserving their cards and board boundaries.
- Enforce tenant-local administrator permissions on every Designer endpoint.
- Separate reserved-host Global Admin domain management from tenant administrators.
- Finish Designer page listing, creation, editing, disabling and deletion.
- Finish Designer widget add/edit/delete, options and bounded layout controls.
- Honor widget row/column spans and required inputs in published pages; add cell sort arrows.
- Make Designer imports validate atomically against the same page/widget rules.
- Report CLI SQLite failures and preserve UTF-8 text, delimiters, quotes and line endings.
- Render authorized board/list/swimlane/card data with the shared selection form.
- Implement selected-item Edit/Save, confirmed Delete, Clear and Export actions.
- Implement deep selected-item Clone with remapped child IDs and attachment copies.
- Add shared board read/write checks, validate move selections and safe return URLs.
- Validate API child routes against their board/parent chain and block unrestricted assignment roles.
- Validate API body label/member/assignee/author IDs before atomic writes.
- Enforce disabled-account denial/revocation, session identity/credential binding, idle expiry and atomic action counters.
- Use cryptographic token hashes/MACs, durable API credential/tenant binding and trusted-proxy client-IP handling.
- Remove weak entropy fallback; verify native Linux and portable one-use SQLite stocks (both backends).
  Windows APIs and retro hardware remain part of the cross-platform verification below.
- Add the board minimap, coordinates and occupied/current-position indicators.
  Empty lanes now have clickable/highlighted X 1 map positions and vertical neighbors; no-swimlane boards normalize to X 1/Y 1. Linked/CLI HTTP and no-JS/no-cookie Chromium cover middle/last empty-lane round trips, LTR/RTL bounds, locale continuity and unchanged board content.
- Add optional card drag/drop, checked-card groups and simultaneous pointers through the shared move endpoint.
- Align tenant/file/temp paths with DOS 8.3 and Weddy files/db layout; verify strict SQLite sidecars, framework upload scratch and offline legacy migration.
- Verify fresh native linked/CLI SQLite installs with HTTP and no-JS/no-cookie Chromium workflows.
  Common response initialization now advertises the pinned FPC server's one-request connection closure. Both backends pass mixed-status/EOF/pooled-client checks and shutdown/restart/integrity tests; an isolated committed-source transport patch also passes all eight Windows build variants. Windows/retro runtime acceptance remains in the cross-platform checklist.

## 2026-11-18 Initialize automatic fields on new API cards

- Add explicit null values for board-scoped automatic and always-on definitions.
  Native and shared storage commit those values together with the card.
- Exercise untouched manual fields and complete card rollback when initial field
  insertion fails. Backfilling existing cards remains open.

## 2026-11-18 Verify the board with Chromium cookies and JavaScript disabled

- Block first-party cookies in a temporary Chromium profile and prove that the
  browser rejects Set-Cookie, omits Cookie and leaves inline JavaScript dormant.
- Exercise selection movement, the rendered HTML4 minimap highlight, viewport
  navigation and layout at 320, 768 and 1920 pixels with native linked and CLI SQLite.

## 2026-11-18 Update single-board custom-field definitions through the API

- Validate proposed fields before any write and commit the definition change
  together with settings replacement. Explicit false values persist and
  omitted or unsupported keys leave their fields unchanged.
- Preserve the distinction between omitted, empty and populated dropdown
  arrays. Exercise all three states and failure rollback in native and shared
  live HTTP tests.
- Follow the current WeKan wrong-board 404 contract. Multi-board definition
  edits and automatic card updates remain open.

## 2026-11-18 Delete single-board custom-field definitions through the API

- Return the WeKan JSON error for missing and out-of-scope fields.
- Delete the definition and its scoped card values atomically. Preserve sibling
  fields and their values, including typed data in shared storage.
- Refuse multi-board definitions at this board-scoped route. Activity cleanup
  and multi-board deletion parity remain open.

## 2026-11-18 Append dropdown options through the scoped API

- Append options in request order with server-generated IDs. Missing or non-array
  input and arrays containing only nonstrings preserve the definition unchanged.
- Support JSON and form-encoded JSON arrays. Initialize omitted arrays and retain
  existing options and unrelated settings in both native and shared storage.
- Check field write access before and during the transaction. Roll back the batch
  and timestamp if an option fails to persist.

## 2026-11-18 Match dropdown mutation authorization and missing-item replies

- Return the WeKan JSON error for missing options and out-of-scope fields.
- Apply field write policy to dropdown mutations before and during the transaction.
  Regular members can edit unprotected options and board administrators can edit
  protected options.

## 2026-11-18 Rename dropdown options without losing typed data

- Add PUT on the scoped dropdown-option route. Resolve the exact option ID,
  validate JSON/form string names and reject invalid/duplicate input. A missing
  name is a successful no-op without timestamp or source changes; replies name
  the option, matching the maintained API.
- Share typed parent/board/item and transaction-time permission/binding guards
  with deletion. Rename the exact current key rather than a remembered array
  index; update modifiedAt atomically and preserve option order, unknown typed
  siblings and existing card assignments.
- Shared explicit name writes establish a BSON string even when a legacy Regex
  has the same plain rendering. Keep the complete sibling schemas and verify the
  final stored name/type before commit; post-write type injection rolls back.
- Normal/checked kernel tests cover same-text type repair with retained Long
  metadata. HTTP regressions cover JSON/form Unicode/newlines, reserved IDs,
  absent-name no-op, invalid/missing refusal, exact BSON and failure/revocation/
  type-injection rollback, alongside existing option-delete cases.
- Option append and full definition edit/delete/automatic-card lifecycle remain
  unfinished.

## 2026-11-18 Delete dropdown options through the scoped API

- Add DELETE `/api/boards/:boardId/custom-fields/:customField/dropdown-items/:dropdownItem`.
  Resolve the exact once-decoded option identity under its canonical definition
  and board link; missing/foreign resources return 404, malformed IDs return 400,
  and ambiguous typed source keys deny deletion.
- Recheck current board-write permission, typed parent/item identity and shared
  model/relation/view bindings inside the transaction. Update modifiedAt and
  delete the option atomically; later account revocation or storage failure rolls
  all changes back. The response names the custom-field definition.
- Retain other options, their array order and unknown BSON data, and leave card
  assignments untouched, matching the maintained API. Removing the last option
  retains an explicit empty array on native and shared stores.
- Normal/checked route tests cover the new key. Native/shared HTTP regressions
  cover quoted Unicode/plus/percent IDs, repeated/missing/malformed deletion,
  retained assignments/empty arrays, typed siblings and post-mutation failure/
  revocation rollback. Shared cases exclude Regex key/board lookalikes and refuse
  mixed duplicate keys without mutation. Checked shared tests and full native HTTP
  suites pass on both backends; targeted native checks also cover legacy populated
  definitions whose presence marker is still zero.
- Option rename/append, definition edit/delete and automatic-card behavior remain
  separate unfinished lifecycle work.

## 2026-11-18 Create dropdown definitions atomically

- Definition POST now accepts optional `settings.dropdownItems` in JSON and form
  settings. Validate arrays of `_id`/`name` string objects, nonempty identities and
  names, unique case-sensitive IDs, UTF-8 and recursive JSON. Reject malformed,
  duplicate and extra item fields instead of dropping them.
- Preserve omitted, explicitly empty and ordered populated arrays. Native stores
  use their presence bit and item sort positions; shared stores retain canonical
  BSON `_id`/`name` objects in array order without adding SQL-only sort fields.
- Missing-only managed-array initialization refuses existing/null/invalid parents.
  Append preserves omitted optional fields and typed siblings; ordinary SQL
  relation inserts retain their existing projection behavior.
- Create the definition, board link, array/items and activity in one guarded
  transaction. Shared source/descriptor/view bindings are pinned around the writes;
  canonical unambiguous parent identity is required before initialization.
- Normal/checked parser and kernel regressions pass. HTTP tests cover JSON/form,
  missing/empty/ordered/case-distinct arrays, exact BSON/GET round trips, invalid
  input and complete rollback after the second item write or later activity failure.
  Checked live shared tests pass on both backends, including binding-change and
  duplicate-parent injection rollback. Full native HTTP suites pass on linked
  and CLI backends.
- Definition edit/delete and automatic-card policies remain unfinished.

## 2026-11-18 Preserve native optional dropdown-array presence

- Native custom-field definitions now retain an explicit dropdown-array presence
  bit. Definition GET can distinguish an omitted array from an explicitly empty
  one, including after its final item is removed; existing ordered item rows still
  imply presence without changing legacy data.
- Fresh stores include the constrained bit; existing native stores gain it through
  an additive, concurrent-safe tenant-open upgrade. Shared/foreign stores, views,
  incompatible columns and invalid values are refused without replacing data.
- Normal/checked linked/CLI regressions cover omitted/empty/ordered arrays,
  retained emptiness, concurrent upgrades and refusal cases. Existing native
  settings/policy upgrade regressions and full native HTTP suites pass on both
  backends.
- This is groundwork for dropdown definition creation. API dropdown payloads remain
  refused until managed-array initialization and atomic creation are implemented;
  shared BSON keeps its existing source-level missing/empty distinction.

## 2026-11-17 Collect clone/export graphs in one read snapshot

- Pin clone/export graph collection to one read-only SQLite transaction, covering
  root resolution, metadata, relation rows and typed source/audit captures. End
  the read before file preparation, current permission checks and clone writes;
  retain existing metadata and transaction guards for those later phases.
- Gate cached database handles while a snapshot is active. Linked reads use the
  existing handle; CLI reads keep one private read-only process and transaction,
  using bounded CSV streaming and private per-query scripts rather than copying
  the tenant database or spawning a connection for every graph query.
- Frame private CLI responses with one secure nonce per snapshot and a query
  counter. Reject transaction control, writes and extra statements; incomplete
  responses/failed SQL deny collection and release the child/transaction. Restore
  live handle behavior after closure, validation failure and exhaustion.
- Normal/checked tests cover independently committed WAL data/schema changes,
  nested begin refusal, SQL/handler failures, quoted UTF-8 paths, handle gating,
  reuse and cleanup. Portable no-OS-random tests verify one stock block per CLI
  snapshot, no per-query consumption and safe exhaustion.
- A live test writer commits board/card changes between graph reads: export and
  clone retain the original consistent version while live sources keep the new
  data. File-byte stability, authorization lifetime and later mutation consistency
  remain separate work; collection consistency alone does not establish full
  clone/export lifecycle parity.
- Full native/shared HTTP suites pass on both backends, alongside normal/checked
  database streaming, snapshot, field-policy and entropy tests. Final checked
  shared export/relation/concurrent-writer tests pass on both backends. Eight Windows
  x86/x64 linked/CLI disk/embedded variants cross-build; Windows execution remains
  unverified.

## 2026-11-17 Keep embedded relation identities inside clone/export scope

- Scope selected board labels, card members/assignees/labels/custom values/
  dependencies and definition board/dropdown links against their actual owned
  BSON parent and embedded keys. Regex/ObjectId/numeric renderings cannot gain
  string-reference authority; duplicate logical keys, including mixed-type
  shadows and dependency defaults, deny collection instead of choosing one row.
- Preserve missing/null dependency-type defaults and existing typed clone copies.
  Require SQL root identity/link projections to remain text as well as matching
  a canonical BSON string, closing numeric-cast projection lookalikes.
- Validate compiled relation descriptor shape and parent ID mapping; pin relation
  model/version, parent collection settings and root/relation view SQL through
  collection and clone/export guards, including empty relation sets. Card relation
  owners are rechecked against the canonical board scope in their read query.
- Normal/checked linked/CLI tests cover 282 TEXT/JSONB relation cases and 44 root
  scope cases, with actual indexed owner probes, descriptor/view/epoch changes,
  nested dropdown keys and native compatibility. Live tests verify filtering,
  duplicate refusal, exact source/clone arrays and relation-epoch rollback.
- Full native HTTP, normal shared clone/export and final checked shared relation
  tests pass on both backends. Eight Windows x86/x64 linked/CLI disk/embedded
  variants cross-build; Windows execution remains unverified.
- Ordinary root edit/save/delete forms retain their existing legacy-array behavior;
  a title editor remains available when a copy/export would reject an ambiguous
  relation. Other legacy forms, noncopy relation surfaces and graph-wide
  snapshot/lifecycle parity remain open.

## 2026-11-17 Stream export source validation with bounded row buffering

- Add a row-scan database API and consume complete card/definition validation
  batches one row at a time. Keep one SQL statement per batch, source ownership
  and cardinality guards, full BSON/settings validation and stored-flag checks.
  The bootstrap CLI still works with plain SQLite without a new extension.
- Linked scans finalize their statement on SQL or handler failure. CLI scans
  decode CSV incrementally, preserving UTF-8, quotes and embedded line endings;
  drain stdout/stderr concurrently, reject malformed/incomplete output and child
  failures, and remove private SQL scratch files. Rows remain provisional until
  the whole scan succeeds; no partially validated batch authorizes export.
- Normal/checked linked/CLI tests cover chunk boundaries, empty fields/results,
  SQL/handler errors, continued database use, pipe pressure and scratch cleanup.
  On Linux, both backends validate over 128 MiB of complete card sources/native
  settings under a 96 MiB address-space limit, including late corruption. An
  isolated prior buffered validator succeeds uncapped and fails under that cap.
- Native/shared HTTP suites pass on both backends, as do final checked shared
  exports and existing database/policy/settings regressions. All eight Windows
  x86/x64 linked/CLI disk/embedded variants cross-build; execution remains untested.
- Row/document buffering no longer scales with total batch payload. SQLite work
  sets, collected selection/export graphs and broader snapshot/lifecycle parity
  remain separate resource/consistency work.

## 2026-11-17 Batch board export definition validation

- Validate all board-associated definitions in a native/shared batch instead of
  reconstructing a full response per definition. Shared batches recheck owned
  table bindings and exact source cardinality, preserving quoted identity lookup
  and complete BSON validation; native batches reuse the definition settings
  validator without fetching unused dropdown and board response arrays.
- Check active board administration once when any definition requires it. Stored
  shared `adminOnly` flags must be missing/null or actual booleans: Date/NaN conversion to
  JSON null cannot bypass the gate. Malformed native administrative flags also
  deny export rather than becoming false during integer conversion.
- Normal/checked linked/CLI regressions cover TEXT/JSONB/native sources, late
  corruption/private definitions, settings shadows, ownership/cardinality errors,
  quoted IDs and unrelated boards. Process-count checks prove that adding 130
  definitions adds no per-definition CLI database subprocesses; 130 private
  definitions require only one additional board-admin permission query.
- Expanded live CLI scope exports measured about 2.5–2.9 seconds locally after
  the batches (earlier about 13 seconds; about 3.3 after the previous step).
- Full live shared API/export/clone suites pass on both backends; final checked
  export runs also pass, including Date/NaN flag refusal and source preservation.
- Bounded memory for very large card/definition batches and broader graph
  snapshot/lifecycle parity remain open.

## 2026-11-17 Batch complete board card-source validation

- Read shared board card sources in one database batch, retaining exactly-one
  physical source checks for every projected card. Pin the owned table lookup in
  that statement and use the installed physical identity index for probes.
- Validate every complete typed document in memory, including absent/null fields;
  missing/duplicate sources, corrupt unrelated BSON metadata, malformed field rows
  and failed SQL all deny export. Native TEXT tables need no BSON conversion.
- Normal/checked linked/CLI tests cover TEXT/JSONB, quoted Unicode identities,
  ownership/cardinality failures, numeric identity refusal, late corrupt documents,
  other-board isolation and native fallback. A CLI process-count regression
  proves adding 70 cards adds
  no per-card subprocesses. Existing field-policy regressions also pass.
- Live shared export/clone/rollback suites pass on both backends, with final
  checked shared export runs passing too. The expanded
  CLI scope export measured about 3.3 seconds locally after the value/source
  batches, versus the earlier 13-second measurement; linked remains about 0.07s.
- Per-definition reads, bounded memory for very large source batches and broader
  graph snapshot/lifecycle parity remain open.

## 2026-11-17 Batch board export value authorization

- Check all nonnull assigned board custom-field values in one correlated SQL
  statement, reusing the owned source policy instead of rebuilding it per card
  and spawning a database process for each value. Correlate both card and field
  identities, preserving canonical BSON checks and active board-admin rules.
- Retain full source validation for cards with missing/null fields, definition
  administration checks and storage NULL semantics; JSON conversion does not
  exempt nonnull Date or special-number data from authorization.
- Normal/checked linked/CLI regressions cover later-card orphan refusal, readable
  multi-card values, null orphans and other-board isolation. A CLI process-count
  regression checks that 130 readable assignments add no per-value subprocesses.
- Full live shared HTTP suites pass on linked and CLI SQLite, including export
  identity/history checks, exact source preservation and clone rollback.
- Per-card source reads and per-definition validation remain to be batched;
  broader snapshot/lifecycle and field-policy parity remain open.

## 2026-11-17 Keep typed root references inside selection scope

- Validate exact canonical board and explicit root identities before any selection
  action. Reject mixed invalid roots instead of allowing edit/save parameters to
  bypass filtering, and preserve case-distinct IDs during collection/deduplication.
- Require BSON string identity for root board/lane/list/card/checklist links used
  in expansion and collection, including nested attachment metadata and history.
  Pair each OR branch with its own type check, retaining valid alternative links
  and optional board fields on card/checklist-owned rows.
- Cache owned root descriptors per graph, validate declared column mappings and
  agree with projected values. Pin model/version/collection settings and view SQL
  in queries and clone/export guards; ambiguous IDs and stale bindings deny use.
  Physical ID probes use the installed index rather than repeated table scans.
- Normal/checked linked/CLI tests cover typed fields, nested paths, descriptor/view
  changes and indexed lookup. Live tests cover lookalikes, valid OR alternatives,
  exact-case selections, mixed edit/save refusal and source/file preservation.
  Native/shared HTTP and eight Windows cross-builds pass; Windows execution is
  still unverified.
- The expanded CLI export fixture took about 13 seconds locally because board-wide
  permission checks issue per-card subprocess queries. Its test keeps all data and
  assertions with a 30-second export timeout; policy batching remains open, along
  with embedded-relation identities and broader graph/lifecycle parity.

## 2026-11-17 Respect BSON reference identity in shared checks and cascades

- Declared root foreign keys now require actual nonempty BSON string references
  and string parent IDs, validating matching parent source metadata. ObjectId or
  Regex lookalikes cannot acquire authority from a plain text SQL projection;
  nullable/missing references remain optional.
- Explicit reference writes establish BSON string metadata, including same-text
  repairs of old Regex fields. Null clearing and unrelated typed source data are
  preserved; source-based inserts without a canonical reference are rejected.
- Delete cascades follow only canonical string owner/child relationships and
  preserve unsupported lookalikes unchanged. Generate cascade predicates after
  all physical root names are known and restore custom triggers after owned ones,
  retaining their prior delete ordering through adapter reinstall.
- Normal/checked SQL tests cover 48 mixed TEXT/JSONB reference cases, explicit
  repairs, invalid-write rollback and typed cascade isolation. Live Mongo/SQL
  tests verify parent/child identity, source preservation and custom delete order
  on both backends. Native/shared HTTP and eight Windows cross-builds also pass;
  Windows execution is unverified. Other scopes and lifecycle work stay open.

## 2026-11-17 Preserve mapped root-field presence during selection clones

- Build explicit shared-root clone patches containing only intentional ID, title,
  timestamp, ordering/counter and canonical reference changes. Untouched mapped
  fields retain original BSON types, bits, nulls and absence, including required
  fields missing in an existing source and nested parent objects.
- Carry the partial patch in an insert-only source envelope through existing root
  views, retaining their reference/unique checks. Ordinary inserts keep their
  initialization/default behavior, and selection download formats stay unchanged.
- Require a canonical string source ID and distinct string destination ID; reject
  malformed envelopes, unknown patch columns and invalid identities. Nonstring
  reference lookalikes retain their original data identity. Shared descendant
  traversal accepts only BSON string parent links, and failed ID queries deny
  graph collection instead of silently narrowing the selection.
- Normal/checked and real SQL tests cover presence/type/identity and TEXT/JSONB
  behavior. Live both-backend lane clones cover all seven root models, nested
  settings, remapped references and preserved attachment bytes. Native HTTP,
  root interoperability and eight Windows cross-builds pass; Windows execution
  remains unverified. Legacy forms, other typed scopes and lifecycle parity stay open.

## 2026-11-17 Retain typed managed card relations during selection clones

- Capture complete typed card source privately alongside the root seed. Audit
  copied relation metadata as well as projected values before preparing files.
- Copy shared members, assignees, labels, custom-field values and dependencies in
  a final typed transaction stage. Preserve stored BSON types, row extras, order
  and missing/null/empty states instead of recreating values from today's field
  definition. Native relation insertion keeps its existing behavior.
- Remap selected dependency targets, including forward/back/self references;
  retain external targets and opaque nested data. Validate canonical string keys,
  destination identity/board binding and duplicate logical relation keys.
- Recheck source/permission and destination-card guards before and after typed
  relation writes. Failed validation, stale bindings and trigger-injected protected
  values roll back records/activities and prepared attachment files.
- Normal/checked kernel and live both-backend tests cover typed values, metadata,
  presence, remapping, duplicate/type refusal and permission rollback. SQL extension
  tests verify TEXT/JSONB and failed-transaction preservation; native HTTP and eight
  Windows cross-builds cover existing behavior (Windows execution is unverified).
  Mapped root field presence, other legacy forms and lifecycle parity remain open.

## 2026-11-17 Check typed BSON identity during selection exports

- Capture complete typed source beside shared root projections in the same SQLite
  read snapshot. Audit board/card/definition/history and other selected root data
  using BSON metadata, so Regex/ObjectId/Date lookalikes cannot acquire string
  identifier authority through a plain SQL JSON rendering.
- Preserve literal nonstring activity markers and metadata-like string keys.
  Audit native and relation rows with the existing payload checks, and recheck
  captured root model/collection bindings before delivery. Missing ownership denies
  collection without a downloadable payload.
- Keep audit sources and binding checks private: downloaded selection JSON retains
  its existing keys and null source columns, and source BSON remains unchanged.
- Live tests cover typed field/board identifiers in nested card data, activities
  and selected definitions, literal Regex markers, ownership refusal and exact
  source preservation in normal and checked builds on both backends. Native/shared
  HTTP and eight Windows cross-builds cover existing behavior; Windows execution
  remains unverified. Broader clone/import/query and lifecycle work remains open.

## 2026-11-17 Retain unknown BSON subtrees in cloned root records

- Capture typed root seeds alongside projected columns in the same SQLite read
  snapshot. Validate owned root model/collection bindings and pin the descriptor,
  version and collection settings through clone preflight and transaction guards.
- Remove managed relations from seeds so existing clone remapping reconstructs
  them once. Insert overlays retain unchanged unknown Date, Long, Binary subtype,
  ObjectId, Timestamp, Regex and special-double metadata, bits and subtree order.
- Validate plain JSON columns without inferring BSON integer widths, allowing
  unsigned timestamps to be inspected. Decode SQL serialization boundaries once;
  metadata-like string keys inside source data remain ordinary literal values.
  Typed seed checks distinguish BSON identifiers from string lookalikes; existing
  card field rows also require canonical string IDs before API/clone access.
- Fail selection collection on SQL/ownership/source errors instead of silently
  treating an error as an empty selection. Later model/collection changes roll
  back cloned records and metadata through existing transaction/file cleanup.
- Normal/checked seed and payload tests cover metadata retention, managed-array
  exclusion, insert overlays, invalid paths/source, unsigned JSON and literal keys.
  Live shared HTML clones compare stored opaque BSON byte-for-byte, including
  types/bits/order; native/shared HTTP and Windows checks cover existing behavior.
- The current FerretDB source oracle passes with installed Go 1.27.3 using only a
  temporary probe-module directive override; its declared Go 1.27.4 toolchain is
  unavailable. Maintained source files are unchanged.
- Exact managed-relation metadata/presence, mapped-field presence and other clone
  lifecycle details remain open, alongside import and generic query permissions.

## 2026-11-17 Enforce custom-field permissions during selection clones

- Check only rows actually copied by a clone, including recognized fields inside
  their JSON/source payloads. Nonnull hidden/read-only values require active
  board administration; site-admin status alone is insufficient. Assigned nulls
  remain copyable, and unrelated history that is not copied does not block cloning.
- Collect current payload/board/source-card guards before preparing files, execute
  them inside the write transaction and repeat them before commit. Check every
  destination card's actual nonnull custom values, including values introduced
  by a trigger after an assigned null was copied.
- Roll back copied rows, activities, policy changes and prepared attachment files
  on failed guards. Preserve existing deep-clone remapping and file failure cleanup.
- Both-backend native/shared HTML tests cover normal/protected/null/admin cases,
  revocation, injected destination values and unchanged originals. Checked/normal
  helper tests exercise correlated card guards and collected payload SQL checks.
  The committed clone copies a read-only value for an ordinary editor under the
  new regression. All eight Windows cross-build variants pass.
- Exact unknown BSON/type/presence cloning, import permissions, generic HTML/query
  surfaces and the remaining definition/automatic-card lifecycle stay in TODO.md.

## 2026-11-17 Check activity and embedded field payloads in selection exports

- Inspect exported payloads recursively before delivery, including activity old/new
  values, customFieldValue aliases, nested custom-field arrays and integrity hashes.
  Decode JSON columns and validate typed source seeds where provided; refuse
  unreadable values, malformed encodings and non-admin hash exports.
- Resolve historical field visibility by board/definition without requiring a live
  card. Board admins retain readable history; site-admin status alone does not
  grant access to protected values or hashes. Preserve null/missing semantics.
- Inspect without rewriting payloads or source rows. Unknown Date/Long/Binary
  data and readable JSON remain unchanged, while denied responses contain no
  graph or attachment headers. Existing board-wide and captured-row gates remain.
- Normal/checked tests cover 156 direct/nested/JSON/BSON payload cases on both SQL
  backends, including invalid input, aliases, hashes, case-sensitive IDs and
  historical access. Native/shared HTML tests cover orphan activity data,
  readable history, hash administration and nested card extras without mutation.
  The committed exporter exposes orphan activity values under the new test; all
  eight Windows linked/CLI disk/embedded cross-build variants pass.
- Clone/import, generic HTML/query surfaces and other value-bearing paths remain
  in TODO.md. This step covers selection export payloads, not every field surface.

## 2026-11-17 Gate selection exports on board-wide field visibility

- Check every board card and associated definition before collecting a selection
  export, following the source's board-wide export gate. A narrower selection
  cannot bypass private values or unassigned admin-only definitions elsewhere.
- Require active board administration for boards with admin-only definitions;
  site administration alone does not bypass the gate. Unknown/wrong-board
  nonnull custom values block exports even for admins. Null/missing orphan values
  and readable read-only fields retain the source export behavior.
- Validate shared typed source metadata and fail closed on missing/error policy
  queries. Recheck board policy before response delivery and check captured
  nonnull value rows too, including rows cleared after graph collection.
- Native/shared HTML HTTP tests cover narrowed selections, private/orphan values,
  global/admin boundaries, readable read-only fields and nulls. Normal/checked
  tests cover board-wide checks and captured-row refusal on both SQL backends.
  The committed selection handler fails the new export gate regression; all
  eight Windows linked/CLI disk/embedded cross-build variants pass.
- Activity payloads and other embedded/unknown export data still require their
  own policy reconciliation. Clone/import and other value-bearing paths remain
  open in TODO.md; this step does not establish full export/field-policy parity.

## 2026-11-17 Validate and authorize definition permission flags

- Accept readOnly/adminOnly on definition creation through canonical JSON, form
  fields and lowercase aliases. Validate their boolean values and reject invalid
  or conflicting aliases before mutation; store native integers/shared BSON
  booleans and return them through definition GET.
- Follow model creation permissions: ordinary board writers may create read-only
  fields, while admin-only fields require active administration of the board.
  Site administration alone does not grant that protected-field permission.
- Reuse typed board/user policy checks inside the creation transaction before
  writes and after the activity. Check the resulting definition and exact board
  association before commit; revoked roles, disabled users, changed bindings,
  foreign-board additions and malformed permission flags roll back every write.
- Both-backend native/shared HTTP tests cover input aliases, stored flags, editor
  and global-admin boundaries and post-activity revocation rollback. Normal/checked
  policy tests cover creation gates and exact board associations; the committed
  API baseline silently discards requested flags. Windows cross-build checks pass.
- HTML, selection clone/export, activity and query policy boundaries, definition
  edit/delete, dropdown creation and automatic-card behavior remain in TODO.md.

## 2026-11-17 Enforce custom-field value policies at the API boundary

- Mask unreadable values as null on every API card response while preserving field
  IDs, array positions and absent values. Missing definitions and definitions not
  linked to the card board are unreadable, including for administrators.
- Require active board administration to read adminOnly values or write adminOnly
  and readOnly fields. Ordinary readOnly values remain readable. Site-admin status
  alone does not grant protected-field access; ordinary board access is also checked.
- Evaluate the current field, card, board and user inside the write transaction,
  both before mutation and before commit. Revoked membership, disabled users,
  changed definitions/associations, moved cards and changed adapter bindings cause
  rollback of the value and triggered changes.
- Resolve shared sources through owned metadata, validate complete typed documents
  and require actual BSON string identifiers/boolean policy flags. Ambiguous,
  missing, malformed or incompatible policy data fails closed without returning
  unmasked values. Batch read checks in groups of 64.
- Native/shared HTTP regressions on both backends cover all card response routes,
  role changes, global-admin boundaries, missing definitions, malformed BSON and
  post-write policy revocation. Normal/checked helper tests cover 132-field batches,
  Unicode/quoted IDs and query-error masking; live shared tests cover 70-field
  batches and corrupt metadata. The committed API baseline exposes missing/wrong-
  board definition values under the new regression. Eight Windows cross-build
  variants pass.
- Definition permission-flag input controls and HTML, selection clone/export,
  activity, query and other value-bearing policy paths remain open in TODO.md.

## 2026-11-17 Store custom-field permission flags for policy enforcement

- Add native readOnly/adminOnly boolean columns with false defaults and boolean
  constraints. Upgrade older native stores before caching tenant handles, keeping
  existing rows, related data and previously stored flags intact.
- Validate existing column shape and values before adding either missing column;
  refuse incompatible columns, views and foreign source stores. Accept concurrent
  successful upgrades without rebuilding the definition table.
- Map shared flags as BSON booleans and include native flags in definition reads.
  Regression tests cover preserved true flags, defaults, incompatible data, live
  Mongo/SQL edits, exact unrelated BSON preservation and older adapter upgrades.
- Normal/checked definition tests and both-backend native upgrade/live SQL/shared
  HTTP suites pass, as do both native HTTP suites. All eight Windows x86/x64 linked/CLI disk/embedded
  cross-build variants pass; the committed baseline fails the new policy fixture.
- This supplies storage and metadata only. Value visibility/write enforcement,
  definition input controls and HTML/export/clone/activity policy parity remain
  unfinished in TODO.md.

## 2026-11-17 Map scalar custom-field settings through the definition API

- Parse settings objects or form JSON, persist currency/template properties through
  their canonical columns and retain other JSON settings in the protected remainder.
  Definition creation keeps settings, board association and activity transactional.
- Validate known string types, Jira enums/field IDs, strict recursive JSON and the
  schema's JavaScript UTF-16 length limit. Reject invalid input before mutation.
- Return supported native metadata with reconstructed settings and shared source
  documents with BSON Date JSON conversion, flags, board IDs and timestamps.
- Normal/checked validation tests and native/shared HTTP suites verify JSON/form
  round trips, empty strings, Unicode limits, metadata reads and failure rollback.
  The old committed API silently discards a supplied currency setting; all eight
  Windows x86/x64 linked/CLI disk/embedded cross-build variants pass.
- Dropdown-array creation remains a separate presence/managed-relation step and
  is refused rather than silently discarded. Definition edit/delete, field-policy
  parity, automatic-card policies, typed migration and clone/export remain in TODO.

## 2026-11-17 Store unmapped custom-field settings without shadowing columns

- Add settings_json as a JSON-object remainder for settings beyond currency,
  template fields and dropdown items. Generate explicit protected child names and
  support scoped remainder projection/writes while retaining existing root remainders.
  New shared definitions receive the object default without replacing seeded settings.
- Preserve mapped settings/dropdowns and unchanged typed BSON when round-tripping
  the remainder. Reject malformed objects, protected child keys and incompatible
  parents; multi-row failures leave source data unchanged.
- Add a transactional native column upgrade before handle caching, preserving
  existing rows/relations and accepting concurrent successful upgrades. Validate
  existing column shape/data and refuse conflicts, views and foreign source stores.
- Both-backend upgrade tests cover fresh/old stores, concurrent openers, JSON checks
  and refusal without mutation. Live SQL tests cover typed remainder round trips
  and upgrades from older views/descriptors lacking the column; HTTP suites pass.
  All eight Windows x86/x64 linked/CLI disk/embedded cross-build variants pass.
- Full settings API mapping/validation, legacy-root normalization, typed migration
  and remaining definition/clone/export lifecycle work stay open in TODO.

## 2026-11-17 Map custom-field SQL settings to their nested source paths

- Generate currencyCode, stringtemplateFormat and stringtemplateSeparator columns
  from settings.currencyCode/settings.stringtemplateFormat/settings.stringtemplateSeparator,
  matching the maintained model instead of reading/writing unrelated root fields.
- Verify live two-way SQL/Mongo edits, new SQL definitions, missing settings objects,
  dropdown coexistence and exact preservation of unknown Date/Long/Binary metadata.
  Refuse incompatible scalar settings parents with full multi-row rollback.
- Reinstall corrected views/descriptors over the old flat projection without
  changing source documents or legacy root properties. The old committed mapping
  reproduces wrong root-value reads rather than the canonical settings values.
  Shared HTTP checks and all eight Windows x86/x64 cross-build variants pass.
- Full settings API payloads/storage, legacy-root normalization policy, definition
  lifecycle, typed migration and clone/export remain in TODO; native schema columns
  and the wider interoperability/platform gates are unchanged.

## 2026-11-17 Make custom-field definition creation atomic

- Commit the definition, board association and authenticated createCustomField
  activity in one transaction. Roll back all three on storage failure and return
  an error rather than a successful ID for partially created data.
- Validate non-empty string names, the eight supported types and Boolean options.
  Support canonical camel-case options and legacy lowercase spellings, reject
  conflicting aliases/duplicate inputs, and retain the default text type.
- Return _id/name/type from the definition-list endpoint, matching the maintained
  API rather than renaming the field name to title and omitting its type.
- Native/shared HTTP tests cover every type, canonical/legacy/form flags, malformed
  bodies, authenticated activity attribution and injected AFTER-write failure at
  each transaction stage. Against committed old code, a failed board link returns
  HTTP 200 and leaves changed data. All eight Windows x86/x64 cross-build variants
  pass. Source-side definition settings and remaining lifecycle
  operations stay open in TODO alongside typed migration and clone/export.

## 2026-11-17 Type first edits of assigned custom-field values

- Match WeKan's actual assignment paths, which initialize custom fields with null.
  Use the live definition when SQL first edits an assigned null/missing value,
  rather than turning numbers, checkboxes, dates and multi-select arrays into text.
- Read definition counts/types inside the statement. Reject unsupported or ambiguous
  definitions; preserve the established text fallback for untyped legacy rows with
  no definition. Already typed values retain their stored BSON-type policy.
- Apply Date schema hints to the selected existing row, preserving sibling/root
  metadata and freeing the previous schema snapshot before rebuilding the hint.
- Add live SQL tests for all eight supported definition types in null/missing states,
  exact BSON, invalid-value refusal, definition changes and multi-row rollback.
  Shared HTTP regressions now start typed fields in assigned-null state and verify
  both database backends, typed responses and unchanged unknown BSON properties.
  Against the previous commit, a first multi-select edit becomes text. All eight
  Windows x86/x64 linked/CLI disk/embedded cross-build variants pass.
- Explicit type changes, normalized typed migration/validation, clone/export and
  the broader interoperability/platform gates remain in TODO.

## 2026-11-17 Decode API route identifiers once before scope checks

- Decode the pinned FPC router's raw captured identifiers before API tenant,
  authentication and resource-parent handling. Preserve path plus signs and
  decode encoded slash/percent characters inside the captured ID without routing
  the path again.
- Validate percent escapes, UTF-8 and control bytes. Stage all parameters before
  committing them, then mark trusted request-local completion to prevent a second
  decoding pass; query fields cannot supply that marker.
- Normal/checked tests cover every API parameter, malformed input, atomic failure,
  plus preservation and idempotence. Native/shared HTTP tests cover encoded Unicode,
  spaces, plus/percent/slash IDs, user/member/assignee routes and foreign-parent
  denial without mutation. Restore Unicode quoted IDs in custom-value regressions.
  The old committed entry point reproduces the Unicode-ID 404; all eight Windows
  x86/x64 linked/CLI disk/embedded cross-build variants pass.
- Keep normalized typed migration/validation, explicit type changes and selection
  clone/export in TODO, along with the broader platform/interoperability gates.

## 2026-11-17 Return typed shared custom-field JSON values

- Read shared card values through matching owned-model/collection metadata and
  validate their complete SJSON before producing a response. Preserve numbers,
  booleans, string arrays, nulls and missing values; keep literal text literal.
- Render BSON Date values as UTC JSON Date strings, including year zero, signed
  extended years and TimeClip boundaries. Match JSON.stringify for invalid dates,
  non-finite doubles and negative zero without platform calendar dependencies.
- Omit root/row-private fields and BSON schema metadata. Refuse corrupt typed data
  with one complete HTTP error, leaving stored BSON unchanged. Native normalized
  stores retain their existing TEXT response contract.
- Normal/checked kernels pass 177 independent Node Date vectors. Shared HTTP tests
  on both backends cover live typed values, full-range dates, read-only behavior,
  missing/null values and corrupt metadata; native HTTP tests retain text output.
  Against committed old code, the HTTP regression receives a string for an array.
  All eight Windows x86/x64 linked/CLI disk/embedded cross-build variants pass.
- Normalized typed migration/validation, explicit type changes, percent-encoded
  route IDs and selection clone/export remain in TODO.

## 2026-11-17 Make custom-field API replacement atomic and truthful

- Replace unchecked INSERT OR REPLACE with one transactional UPDATE followed by
  insertion only when the row is absent. Existing embedded row properties and
  BSON type metadata survive replacements; failed writes roll back and return
  an error rather than a false success.
- Parse JSON scalars and string arrays explicitly, retain form/JSON string input,
  and reject missing/duplicate values, objects, nulls, non-string array elements,
  NUL characters and non-finite JSON numbers before SQL mutation.
- Serialize successful card IDs with the JSON writer, including quoted IDs.
  Native/shared HTTP tests cover repeated writes, empty values, JSON/form arrays,
  numbers, booleans, dates, Unicode text, scope guards and rollback after an
  injected AFTER-write failure on both SQLite backends. Against committed old
  code, a replacement returns HTTP 200 while Mongo still contains the old value.
- Typed API response values, explicit field-type changes, normalized-store typed
  migration, percent-encoded route IDs and clone/export compatibility remain open.

## 2026-11-17 Insert shared custom values by field definition

- Read the current custom-field definition inside each shared SQL insertion.
  Convert text, number/currency, checkbox, date, dropdown/multi-select and
  stringtemplate values to their corresponding BSON types.
- Supply an explicit Date schema hint for appended date values while retaining
  existing sibling/root BSON metadata. Refuse missing/ambiguous/unsupported
  definitions and invalid input rather than silently storing text.
- Add real FerretDB tests for every supported type, live definition changes,
  missing/empty source arrays, duplicate refusal, exact BSON and multi-row rollback
  on both SQLite backends. The regression fails against the previous committed
  code because a numeric value is stored as text.
- Explicit type changes, typed API input/output, normalized migration and selection
  clone/export remain in TODO; the broader interoperability milestone stays open.

## 2026-11-17 Preserve existing shared custom-field value types

- Use the stored BSON schema when SQL updates an existing custom-field value.
  Preserve numeric/boolean/Date/string-array values rather than turning them into
  text; keep text literal and unknown fields/siblings intact.
- Accept finite numeric input, checkbox values, integer/ISO dates and strict JSON
  string-array text. Refuse invalid values and unsupported BSON replacement;
  preserve unchanged values and statement-level rollback.
- Add real FerretDB/SQL regression cases for both database backends, exact BSON,
  integers above 2^53, pre-epoch dates, Unicode/escaped arrays, no-op updates and
  multi-row rollback. The new test reproduces type loss with committed old code.
- New typed insertion/type-change and API/clone/export contracts remain in TODO;
  this step does not close the broader interoperability milestone.

## 2026-11-17 Render native deletion confirmation details

- Replace the English generic confirmation count with native Confirm/Delete selected,
  Details and Cancel captions plus per-kind selected/affected data counts. Count
  card cascades and explicit same-board inbound dependencies; omit retained board
  labels/custom-field definitions from the deletion list.
- Dispatch fixed action_confirm-delete independently of captions, preserving legacy
  confirmation, scoped permission checks and transactional deletion. Preview errors
  retain the existing viewer frame without performing deletion.
- Installed-locale HTTP and linked/CLI no-JS/no-cookie Chromium checks pass for
  descendant cards, related rows, legacy duplicated comment metadata, inbound links,
  retained definitions/foreign-card links, attachment bytes and cancel/confirm flows.
  A valid-session probe precedes replay against an intact sibling, proving consumed
  proof refusal without relying on missing IDs or incorrect client binding.
- Existing complete HTTP/browser suites and native parser checks pass. Validation/
  error prose, enrollment instructions, remaining locale data and broader RTL/platform
  acceptance remain open in TODO.

## 2026-11-17 Advertise single-request HTTP connection closure

- Reproduce HTTP/1.1 responses without Connection: close while the pinned FPC
  server frees each socket after one request, causing immediate pooled requests
  to fail with connection resets.
- Set the close policy in common response initialization on every target. Retain
  Unix connection tracking/signal handling and the default server on other targets.
- Verify both database backends with mixed HTML/static/JSON/error/redirect statuses,
  wire EOF, reusable Python clients and rapid pooled Node GET/POST requests.
  Shutdown/restart/integrity tests and all eight Windows build variants pass.
- Recheck committed source plus only this transport patch in an isolated snapshot,
  independently of pending confirmation UI changes. Windows/retro runtime behavior
  and other unfinished platform acceptance remain open in TODO.

## 2026-11-17 Translate selection edit fields and native Save

- Reuse native edit/selection, item-kind, title/color/description and Save keys
  under the same resolved viewer locale as the edit frame. Retain stable submitted
  field names and escaped original user values.
- Add label associations on supporting browsers, with safe deterministic textarea
  targets independent of Unicode/punctuation object IDs. Avoid including textarea
  user content in its accessible label. Show a code-only color example; the shared
  color component keeps its existing hint by default for other callers.
- Dispatch fixed action_save independently of captions, retaining legacy Save and
  selection/proof guards. Both-backend parser/color checks and linked/CLI installed-
  locale HTTP/no-JS/no-cookie Chromium pass, including UTF-8 ID/content save round
  trips, scoped fields, invalid saves and foreign/ambiguous command refusal.
- Confirmation explanations, validation/error prose, other application text and
  remaining locale/RTL/platform acceptance stay open in TODO.

## 2026-11-17 Translate native selection toolbar actions

- Reuse existing native Edit/Delete selected/Unselect all/Export selected/Copy
  selection captions and Multi-Selection/swimlane/list/card summary labels. Pass
  the resolved board locale into the toolbar, including header/profile selection.
- Submit fixed action_edit/delete/clear/export/clone names independently of their
  captions. Normalize before authorization/proof admission and reject duplicate,
  unknown, multiple, arrow-mixed or legacy-mixed native commands. Legacy action
  forms and non-consuming export semantics remain compatible.
- Both-backend parser/markup checks, installed-locale guest/admin HTTP captions
  and no-JS/no-cookie Chromium native labels/actions pass. Foreign selections and
  ambiguous commands retain data/proofs; native export retains JSON and proof reuse.
- Selection edit/confirmation prose, enrollment instructions, other application
  messages and remaining language/RTL/platform acceptance stay open in TODO.

## 2026-11-17 Keep empty swimlane viewport positions reachable

- Reproduce an empty lane retaining X 999 with no vertical escape. Clamp its
  column to X 1, keep vertical neighbors independent of horizontal list count,
  and normalize a board with no swimlanes to X 1 / Y 1.
- Render an empty lane's map placeholder as a clickable, current-position-colored
  cell with a native no-items description, preserving session/locale URLs.
- Linked/CLI HTTP and no-JS/no-cookie Chromium verify middle/last empty lanes,
  up/down/map round trips, LTR/RTL locale continuity, coordinate bounds, current
  color and unchanged board content. Existing movement and widget suites pass.
- Record this completed minimap behavior in TODO; broader responsive/retro and
  remaining localization/platform work remain open.

## 2026-11-17 Translate viewport captions and minimap legend

- Reuse native View/Board/color/current/cards/no-items keys for physical viewport
  captions, map description and legend. Keep arrow captions in an isolated LTR
  run; logical coordinates and physical RTL neighbor mapping remain unchanged.
- Add stable map/direction data attributes so behavior does not depend on English
  descriptions. Extend installed-locale HTTP checks to descriptions/legend/arrows
  and browser checks to native captions and real Finnish/Arabic/Hebrew navigation.
- Linked/CLI HTTP and no-JS/no-cookie Chromium suites pass, including existing
  movement, published widget, map and progressive drag workflows.
- Action-button/selection captions, other application prose, remaining language
  assets and broader responsive/retro acceptance remain open in TODO.

## 2026-11-17 Decouple native movement arrows from submitted captions

- Render fixed move_up/down/left/right submit names with ASCII arrow captions,
  keeping input/table direction isolated and the physical keypad order intact.
  Direction no longer depends on visible English words; HTML3.2 inputs remain usable.
- Normalize one native arrow before selection/proof admission. Reject duplicate,
  unknown, multiple or legacy-mixed commands without data changes or proof
  consumption. Existing legacy direction/drop/action clients retain their behavior.
- Both-backend parser/markup checks pass. Linked/CLI real HTTP and no-JS/no-cookie
  Chromium cover native RTL moves, caption-independent dispatch, rejected-command
  rollback/proof reuse, published widget direction and progressive drag workflows.
- Action-button/selection captions and minimap explanations remain untranslated
  work in TODO; document the new input protocol and legacy compatibility.

## 2026-11-17 Translate board navigation and empty/not-found states

- Reuse existing native board/title, all-boards/view-all and empty-item strings
  in direct and published board rendering. Pass the resolved direct viewer locale
  into the body so header-only selection matches its frame.
- Translate inaccessible/missing board responses and published unavailable-board
  text while retaining 404/access checks and escaping user-controlled titles.
- Reproduce English output under an Acehnese frame; verify installed locale
  captions plus query/profile/header selection, no-lane/list/card states and
  private-board denial. Linked/CLI HTTP and no-JS/no-cookie Chromium navigation,
  empty-state and translated 404 checks pass with existing movement workflows.
- Movement/action captions, minimap explanations and other application text remain
  separate unfinished localization steps; submitted command values are unchanged.

## 2026-11-17 Share resolved page locale with published widgets

- Reproduce a Finnish published frame with an English board-list heading when
  language comes only from Accept-Language. Pass the resolved page locale into
  widget rendering through a transient copy of the validated session.
- Keep native view captions, board/state links and signed widget hidden fields
  consistent with the frame for header/profile/query selection. Preserve user
  preferences, session identity, access checks and independent saved page direction.
- Add HTTP and no-JS/no-cookie Chromium checks for guest/member/admin views,
  private boards, invalid sessions, query overrides, fixed LTR/RTL pages, fragments
  and signed action context. Existing full linked/CLI HTTP/browser suites pass.
- Other page/message translations, missing assets and remaining RTL/platform
  acceptance continue in TODO.

## 2026-11-17 Translate native home-page captions

- Resolve the viewer language before rendering the home body. Reuse existing
  board/empty-state, account/admin and sign-in/register translations, escaping
  all captions and retaining board title text and access checks.
- Reproduce the English-only body under an Acehnese frame, then verify every
  installed locale on guest/member home views. Check profile/query/header
  precedence, administrator isolation, invalid/client-mismatched sessions,
  private-board refusal, escaped titles and absence of request-state leakage.
- Linked/CLI HTTP suites and no-JS/no-cookie Chromium home/navigation checks pass.
  OTP/enrollment HTTP/browser flows retain account identity; update stale browser
  assertions to select the login form and retain its validated locale URL.
- Home captions are complete for installed assets; other application messages,
  enrollment instructions, language assets and RTL/retro acceptance remain open.

## 2026-11-17 Verify ARM hard-float cross-builds and record runtime limits

- Build a separate ARMHF compiler and matching EABIHF/VFPV3 runtime units. Reproduce
  the incorrect ARMEL loader from an ARMEL compiler with application ABI flags;
  a clean compiler build with FPC_ARMHF selects the correct hard-float loader.
- Add four current armhf/armv7 disk/embedded CLI compile checks with ELF32/ARM/
  EABI5/loader validation and a compile-time hard-float libc/libm ABI probe.
- Record the pinned compiler's known soft-float ELF metadata (FPC 40374). Runtime
  ABI and embedded HTTP attempts fail inside QEMU's target loader on the 16 KiB-page
  host, matching Debian 1114725; page-size override does not help. No ARM runtime
  acceptance is claimed. Keep those checks and other platform work open in TODO.

## 2026-11-17 Verify current Windows x86 cross-builds

- Build a separate pinned Windows i386 compiler/runtime prefix and compile the
  current disk/embedded linked/CLI servers as PE32 console executables.
- Generalize the Windows regression to independent x86/amd64 prefixes and parse
  actual PE import directories through section headers. Require the correct
  machine/format, kernel32 import and linked-only sqlite3.dll dependency.
- All eight variants pass. Update reproduction docs and remaining TODO; Windows
  runtime, entropy, DLL/resource and shutdown acceptance remain unverified.

## 2026-11-17 Fix Windows embedded resource compilation

- Reproduce the current Windows amd64 embedded build failure: RT_RCDATA is not
  declared by Classes on Windows. Conditionally import Windows in the generated
  resource unit for public assets and private SQL lookup.
- Add a four-variant Windows build regression and verify MZ/PE signatures, AMD64
  architecture, PE32+ console format and linked SQLite DLL reference. Disk and
  embedded linked/CLI builds all pass with the pinned aarch64-hosted compiler.
- Native exact-byte/private-seed resource checks and all four Linux amd64 builds
  also pass. Record current verification separately from the historical matrix;
  Windows runtime, DLL/entropy/shutdown and other platform acceptance remain open.

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
