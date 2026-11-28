unit wlapi;

{
  WeKan-Lite — REST API (subset of public/api/wekan.yml), so the WeKan Python CLI api.py works
  against the FreePascal server unchanged.

  Auth (as api.py does it):
    POST /users/login   JSON {username,password,code?}     -> {"id","token","tokenExpires"}
    then every /api/... request sends  Authorization: Bearer <token>

  Tokens are persisted in schema.sql login_tokens (hashedToken = TokenHash(tenantDb,token)), the same
  table the no-cookie web sessions use. Responses use WeKan's "_id"/"title" JSON shapes.

  Implemented endpoints (the common api.py commands):
    POST /users/login
    GET  /api/user                                   current user
    GET  /api/users                                  all users
    GET  /api/boards                                 public boards
    GET  /api/users/:userId/boards                   a user's boards
    GET  /api/boards/:boardId                        board
    GET  /api/boards/:boardId/swimlanes              swimlanes
    GET  /api/boards/:boardId/lists                  lists
    POST /api/boards/:boardId/lists                  create list           -> {"_id"}
    GET  /api/boards/:boardId/lists/:listId          list
    POST /api/boards/:boardId/lists/:listId/cards    add card              -> {"_id"}
    GET  /api/boards/:boardId/lists/:listId/cards/:cardId   card
    GET  /api/boards/:boardId/swimlanes/:swimlaneId/cards   cards on a swimlane

  Password/OTP proofs and durable attempt limits are shared with the web sign-in.
}

{$mode objfpc}{$H+}{$modeswitch nestedprocvars}
{$CODEPAGE UTF8}

interface

uses
  SysUtils, Classes, HTTPDefs, fpjson, jsonparser, DateUtils, base64,
  wldb, wltenant, wlauth, wlpasswd, wlaccess, wlattemp;

procedure ApiLogin(aRequest: TRequest; aResponse: TResponse);
procedure ApiLogout(aRequest:TRequest;aResponse:TResponse);
procedure ApiCreateToken(aRequest:TRequest;aResponse:TResponse);
procedure ApiBoardDomains(aRequest:TRequest;aResponse:TResponse);
procedure ApiDependencies(aRequest:TRequest;aResponse:TResponse);
procedure ApiDeleteToken(aRequest:TRequest;aResponse:TResponse);
procedure ApiMyCards(aRequest:TRequest;aResponse:TResponse);
procedure ApiUser(aRequest: TRequest; aResponse: TResponse);
function ReadGroupFeatures(Db:TWLDb;const Kind:string):TJSONArray;
procedure ApiOrgFeatures(aRequest:TRequest;aResponse:TResponse);
procedure ApiTeamFeatures(aRequest:TRequest;aResponse:TResponse);
procedure ApiChangeUser(aRequest:TRequest;aResponse:TResponse);
procedure ApiUsers(aRequest: TRequest; aResponse: TResponse);
procedure ApiPublicBoards(aRequest: TRequest; aResponse: TResponse);
procedure ApiUserBoards(aRequest: TRequest; aResponse: TResponse);
procedure ApiBoard(aRequest: TRequest; aResponse: TResponse);
procedure ApiAddBoardMember(aRequest:TRequest;aResponse:TResponse);
procedure ApiRemoveBoardMember(aRequest:TRequest;aResponse:TResponse);
procedure ApiBoardCardSettings(aRequest:TRequest;aResponse:TResponse);
procedure ApiBoardTitle(aRequest: TRequest; aResponse: TResponse);    // PUT board title
procedure ApiDeleteRule(aRequest:TRequest;aResponse:TResponse);
procedure ApiEditRule(aRequest:TRequest;aResponse:TResponse);
procedure ApiIntegration(aRequest:TRequest;aResponse:TResponse);
procedure BrowserIntegrations(aRequest:TRequest;aResponse:TResponse);
procedure ApiCreateRule(aRequest:TRequest;aResponse:TResponse);
procedure ApiBoardRules(aRequest:TRequest;aResponse:TResponse);
procedure ApiBoardExport(aRequest:TRequest;aResponse:TResponse);
procedure ApiBoardDocument(aRequest: TRequest; aResponse: TResponse);
procedure ApiScrumVelocityReport(aRequest: TRequest; aResponse: TResponse);
procedure ApiBoardBurnReport(aRequest: TRequest; aResponse: TResponse);
procedure ApiBoardTimeReport(aRequest: TRequest; aResponse: TResponse);
procedure ApiBoardZip(aRequest: TRequest; aResponse: TResponse);
procedure ApiBoardCsv(aRequest: TRequest; aResponse: TResponse);
procedure ApiBoardCalendar(aRequest: TRequest; aResponse: TResponse);
procedure BrowserBoardExport(aRequest:TRequest;aResponse:TResponse);
function ImportRecoveryRows(Db: TWLDb; const UserId, BoardId: string): TJSONArray;
procedure ApiImportBoard(aRequest:TRequest;aResponse:TResponse);
procedure ImportBoardMethod(aRequest:TRequest;aResponse:TResponse; const Tenant: TWLTenant; const Actor: string; Args: TJSONData);
procedure ApiCreateBoard(aRequest:TRequest;aResponse:TResponse);
procedure ApiBoardCopy(aRequest: TRequest; aResponse: TResponse);     // POST copy board
procedure ApiSwimlane(aRequest:TRequest;aResponse:TResponse);
procedure ApiSwimlanes(aRequest: TRequest; aResponse: TResponse);
procedure ApiCreateLabel(aRequest: TRequest; aResponse: TResponse);    // PUT board label
procedure ApiCustomFields(aRequest: TRequest; aResponse: TResponse);   // GET list / POST create
procedure ApiCustomField(aRequest: TRequest; aResponse: TResponse);    // GET one
procedure ApiUpdateCustomField(aRequest:TRequest;aResponse:TResponse);
procedure ApiDeleteCustomField(aRequest:TRequest;aResponse:TResponse);
procedure ApiAppendDropdownItems(aRequest:TRequest;aResponse:TResponse);
procedure ApiDropdownItem(aRequest:TRequest;aResponse:TResponse);
function SaveCardFieldValue(Db:TWLDb;const CardId,FieldId,Value,GuardSql:string):Boolean;
procedure ApiCardCustomField(aRequest: TRequest; aResponse: TResponse);// POST set card value
procedure ApiLists(aRequest: TRequest; aResponse: TResponse);          // GET list / POST create
procedure ApiList(aRequest: TRequest; aResponse: TResponse);
procedure ApiListEdit(aRequest:TRequest;aResponse:TResponse);
procedure ApiListArchive(aRequest: TRequest; aResponse: TResponse);
procedure ApiCopyCard(aRequest:TRequest;aResponse:TResponse);
procedure ApiBulkCards(aRequest:TRequest;aResponse:TResponse);
procedure ApiCards(aRequest: TRequest; aResponse: TResponse);          // POST add card
// A card added from a view (the HTML5 view's Add card form), with the same
// checks and writes as POST /api/boards/:boardId/lists/:listId/cards: board
// write access, the list and swimlane on that board, the swimlane holding the
// list, the board's custom fields initialized. Position 'top' puts it first in
// its list, anything else last. Returns the HTTP status (200 when added) and
// sends nothing; Error says why not.
function CreateViewCards(const T:TWLTenant;const UserId,BoardId,ListId,Swimlane,Title,Position:string;
  Separate,BracketLabels:Boolean;out CardId,Error:string;const DueAt:string=''):Integer;
function SubtaskParentSql(const ParentId,ColumnPrefix:string):string;
function SetViewSubtaskDone(const T:TWLTenant;const UserId,ParentId,SubtaskId:string;Done:Boolean;out Error:string):Integer;
function CreateViewSubtask(const T:TWLTenant;const UserId,BoardId,ParentId,Title:string;InheritLabels:Boolean;out Error:string):Integer;
function CreateViewCard(const T:TWLTenant;const UserId,BoardId,ListId,Swimlane,Title,Position:string;
  out CardId,Error:string;const DueAt:string=''):Integer;
// A card's new title from a view (the HTML5 view's title editor), checked as
// PUT /api/boards/:boardId/lists/:listId/cards/:cardId checks a title: board
// write access, the card on that board, a title that is text. Returns the
// HTTP status (200 when renamed) and sends nothing.
function RenameViewCard(const T:TWLTenant;const UserId,BoardId,CardId,Title:string;out Error:string):Integer;
// A list added from a view, as WeKan's createListAfter adds one
// (server/models/lists.js): with board write access, into the swimlane of
// the list it follows (else the given one, else the board's first), right
// after AfterListId - halfway to the next list, or one after it - or last
// when there is none. Returns the HTTP status (200 when added).
function CreateViewList(const T:TWLTenant;const UserId,BoardId,SwimlaneId,AfterListId,Title:string;out ListId,Error:string):Integer;
// The board's admins (a site admin too): who renames the board.
// The SQL of a new card (and WeKan's createCard activity of it); a linked
// card with LinkedId.
function CardCreateSql(const BoardId,ListId,Lane,CardId,Author,Title,Descr,Parent,Sort:string;const LinkedId:string='';const TitleExpression:string=''):string;
// AdminFieldBleed (#3141): whether Fields (a card's customFields, as a
// client sent them) names a field of the board the user may not write - an
// admin-only one, for anybody but a board admin. True is an attempt, refused
// by the caller and recorded here in Admin Panel / Problems.
function AdminFieldForgery(Db:TWLDb;const UserId,BoardId,CardId:string;Fields:TJSONData;const Source:string):Boolean;
procedure RecordAdminFieldAttempt(Db:TWLDb;const UserId,Source,Detail:string);
function BoardCanAdmin(Db:TWLDb;const UserId,BoardId:string):Boolean;
// The board's new title, as PUT /api/boards/:boardId/title renames it.
function RenameBoard(const T:TWLTenant;const UserId,BoardId,Title:string;out Error:string):Integer;
// WeKan's toggleBoardStar: the board in the user's starredBoards, or out of it.
function ToggleViewBoardStar(Db:TWLDb;const UserId,BoardId:string;out Error:string):Integer;
// archivesSidebar's restore of an archived card, list or swimlane (Kind
// cards, lists or swimlanes) of the board.
// An archived card, list or swimlane back. A card goes back to its own list
// only while a hard WIP limit has not filled it (#6772, wipRestore.js), else
// to ToList when that open list of the board has room: 409 and
// 'restore-blocked' when its own list is full and no ToList was given.
function SetViewSwimlaneArchived(const T:TWLTenant;const UserId,BoardId,LaneId:string;Archive:Boolean;out Error:string):Integer;
function RestoreViewItem(const T:TWLTenant;const UserId,BoardId,Kind,ItemId,ToList:string;out Error:string):Integer;
// Is ListId an open list of BoardId that a hard WIP limit has not filled?
// Every open card of the list counts, in every swimlane (#2095). Title is
// the list's, '' when it is not an open list of the board.
function ListHasRoom(Db:TWLDb;const BoardId,ListId:string;out Title:string):Boolean;
// The Archive's Restore all: every archived card whose list has room goes
// back, each restored card counting for the next; Skipped the ones left out.
function RestoreAllViewCards(const T:TWLTenant;const UserId,BoardId:string;out Skipped:Integer;out Error:string):Integer;
// A swimlane added from a view (WeKan's swimlaneAddPopup): with board write
// access, below - or above - AfterId, between it and its neighbour, or last
// without one; a template-swimlane on a templates board.
function CreateViewSwimlane(const T:TWLTenant;const UserId,BoardId,AfterId:string;Above:Boolean;const Title:string;
  out LaneId,Error:string):Integer;
// A fold the user keeps in their profile, Map[BoardId][Key] (WeKan's
// collapsedSwimlanes, collapsedLists...): ids only (assertSafeMapKey), on a
// board the user may read.
function ProfileFold(Db:TWLDb;const UserId,Map,BoardId,Key:string):Boolean;
function SetViewProfileFold(const T:TWLTenant;const UserId,Map,BoardId,Key:string;Folded:Boolean;out Error:string):Integer;
// The user's own profile.<Map>[BoardId] (Key '') or profile.<Map>[BoardId][Key]
// set to a JSON value (a number or a boolean), on a board the user reads.
// A shared store's Admin Panel / Problems row for an event of a security
// kind (models/lib/securityCategories.js): one row per kind that counts its
// occurrences (eventLogSummary.js). Action is 'blocked', 'detected' or
// 'sanitized'. Logging never breaks the caller.
procedure RecordSecurityEvent(Db:TWLDb;const UserId,Bleed,Source,Category,Severity,Cwe,Action,Detail:string);
// A new password for Target (WeKan's setPassword, and Member Settings'
// Change Password once the caller checked the old one): a site admin's for
// anyone, or the user's own; a password account only, within the password
// policy. Every session of Target is signed out (server/passwordChangeRequired.js).
function ViewSetPassword(const T:TWLTenant;const Actor,Target,Password:string;out Error:string):Integer;
// The users collection's own update from a client (/_methods//users/update),
// as far as WeLite's views use it: the user's own notification marked read
// or unread ($set or $unset of profile.notifications.<n>.read) or removed
// ($pull from profile.notifications). Any other write of the notification
// list is TrayBleed's attack - refused and recorded in Problems - and
// everything else is refused as before (InviteProfileBleed). The HTTP status.
function ViewUsersUpdate(Db:TWLDb;const UserId,Content:string):Integer;
// The notifications drawer's menu (WeKan's notificationsDrawer): every
// notification of the user read now, or none left.
function MarkAllNotificationsRead(Db:TWLDb;const UserId:string):Boolean;
function DeleteAllNotifications(Db:TWLDb;const UserId:string):Boolean;
function SetViewProfileValue(const T:TWLTenant;const UserId,Map,BoardId,Key,JsonValue:string;out Error:string):Integer;
// WeKan's comment capability (models/lib/boardRoleCapabilities.js): a site
// admin, or an active member who may read the board and whose role may
// comment - everyone but No comments, Read only and Read assigned only.
function BoardCanComment(Db:TWLDb;const UserId,BoardId:string):Boolean;
// A comment on a card from a view (the HTML5 view's comment form), stored as
// POST /api/boards/:boardId/cards/:cardId/comments stores one.
function AddViewComment(const T:TWLTenant;const UserId,BoardId,CardId,Text:string;out CommentId,Error:string):Integer;
// A card's checklists from a view (the HTML5 view's checklists section), with
// the checks and writes of the REST API's checklist routes: board write
// access, the card - and the checklist and the item - on that board, a title
// that is text. Each returns the HTTP status (200 when done) and sends nothing.
function CreateViewChecklist(const T:TWLTenant;const UserId,BoardId,CardId,Title:string;out ChecklistId,Error:string):Integer;
function AddViewChecklistItem(const T:TWLTenant;const UserId,BoardId,CardId,ChecklistId,Title:string;out ItemId,Error:string):Integer;
function ToggleViewChecklistItem(const T:TWLTenant;const UserId,BoardId,CardId,ChecklistId,ItemId:string;out Error:string):Integer;
function RenameViewChecklist(const T: TWLTenant; const UserId, BoardId, CardId, ChecklistId, ItemId, Title: string;
  out Error: string): Integer;
function DeleteViewChecklistItem(const T: TWLTenant; const UserId, BoardId, CardId, ChecklistId, ItemId: string;
  out Error: string): Integer;
function AssignViewChecklistItem(const T: TWLTenant; const UserId, BoardId, CardId, ChecklistId, ItemId, Assignee: string;
  out Error: string): Integer;
function SortViewChecklistItems(const T: TWLTenant; const UserId, BoardId, CardId, ChecklistId: string;
  Fields: TStrings; out Error: string): Integer;
function SetViewChecklistDue(const T: TWLTenant; const UserId, BoardId, CardId, ChecklistId, ItemId, At: string;
  Remove: Boolean; out Error: string): Integer;
// Deletes the checklist and, through checklist_items' ON DELETE CASCADE, its
// items and only its items.
function DeleteViewChecklist(const T:TWLTenant;const UserId,BoardId,CardId,ChecklistId:string;out Error:string):Integer;
// A board's card setting (boards' allows*, kept in settings_json): on unless
// the board turned it off, as WeKan's defaults are.
function BoardAllows(Db:TWLDb;const BoardId,Setting:string):Boolean;
// Whoever may change the card's description, Requested By and Assigned By:
// board write access, unless a Worker (WeKan's canModifyCard, unless isWorker).
function BoardCanEditCardText(Db:TWLDb;const UserId,BoardId:string):Boolean;
// A board member on the card, or off it, from a view (the HTML5 view's
// members pop-over), with the checks, writes and activity of POST and DELETE
// /api/boards/:boardId/lists/:listId/cards/:cardId/members/:memberId.
function ToggleViewCardMember(const T:TWLTenant;const UserId,BoardId,CardId,MemberId:string;out Error:string):Integer;
// The card's Requested By or Assigned By (Field requestedBy or assignedBy),
// free text, on a board that shows it.
function SetViewCardPerson(const T:TWLTenant;const UserId,BoardId,CardId,Field,Value:string;out Error:string):Integer;
// The card's description, from the HTML5 view's description editor.
function SetViewCardDescription(const T:TWLTenant;const UserId,BoardId,CardId,Text:string;out Error:string):Integer;
// A board label from a view (WeKan's createLabelPopup), with the checks and
// write of PUT /api/boards/:boardId/labels: a board admin, a known color.
function CreateViewLabel(const T:TWLTenant;const UserId,BoardId,Name,Color:string;out LabelId,Error:string):Integer;
function BoardCanCreateLabel(Db:TWLDb;const UserId,BoardId:string):Boolean;
// A card's Received, Start, Due or End (Kind received, start, due, end) from
// the HTML5 view's date picker: set to At, or cleared, by whoever may change
// the card but a Worker, on a board that uses that date; with WeKan's
// a-<field> activity (server/lib/timingChangeActivity.js).
function CardDateSql(Value:TJSONData;out Literal:string):Boolean;
function SetViewCardDate(const T:TWLTenant;const UserId,BoardId,CardId,Kind,At:string;Remove:Boolean;
  out Error:string):Integer;
function ViewDateKindField(const Kind:string;out Field,Setting:string):Boolean;
// A card's custom field from a view (cardCustomField-* and
// cardCustomFieldsPopup): with Toggle the field onto the card, empty, or off
// it; else its value from the form's "value" (and a date's "at"/"delete"),
// parsed for the field's type. The REST API's field policy decides, and its
// write saves.
function SetViewCardField(const T:TWLTenant;const UserId,BoardId,CardId,FieldId:string;Values:TStrings;Toggle:Boolean;
  out Error:string):Integer;
// createCustomFieldPopup: a board's custom field by name and type, shown on
// cards, created as POST /api/boards/:id/custom-fields creates one.
function CreateViewCustomField(const T:TWLTenant;const UserId,BoardId,Name,Typ:string;out Id,Error:string):Integer;
// Whether the REST API's field policy lets the user read (Write False) or
// change the card's value of the field.
function ViewFieldAllowed(Db:TWLDb;const UserId,BoardId,CardId,FieldId:string;Write:Boolean):Boolean;
// The card's menu (cardDetailsActionsPopup): moved to another list or
// swimlane of its board, with WeKan's moveCard activity and last in its new
// place; copied - to this board or another the user may change - as POST
// .../cards/:cardId/copy copies one, with copyCardPopup's title; archived.
function MoveViewCard(const T:TWLTenant;const UserId,BoardId,CardId,DestBoard,DestLane,DestList:string;out Error:string;const Reason:string=''):Integer;
function CopyViewCard(const T:TWLTenant;const UserId,BoardId,CardId,DestBoard,DestLane,DestList,Title:string;
  out NewCard,Error:string):Integer;
function ArchiveViewCard(const T:TWLTenant;const UserId,BoardId,CardId:string;out Error:string):Integer;
// A board member added (made active again, with Columns/Values/Sets of the
// role flags) or removed by a board admin, as POST
// /api/boards/:boardId/members/:userId/add and /remove do it: 200, or the
// code and its Error.
// An enabled site admin of the tenant.
function IsSiteAdmin(Db: TWLDb; const UserId: string): Boolean;
function ChangeBoardMembership(const T:TWLTenant;const Actor,BoardId,TargetId:string;Add:Boolean;
  const Columns,Values,Sets:string;out Error:string):Integer;
// A card's vote (cardDetails.jade's vote section): nil-like (Present False)
// when it has none. WeKan's showVotingButtons decides CanVote: an active
// member of the board - or anybody who can see it, when the vote allows
// non-members - until the vote ends.
type
  TCardVote = record
    Present, IsPublic, CanVote, ForIt, Against: Boolean;
    Question: string;
    Positive, Negative: Integer;
  end;
function ReadCardVote(Db:TWLDb;const UserId,BoardId,CardId:string):TCardVote;
// WeKan's cards.vote from a click on Side ('positive' or 'negative'): the
// other side, or no vote yet, votes for that side; one's own side again
// takes the vote back.
function VoteViewCard(const T:TWLTenant;const UserId,BoardId,CardId,Side:string;out Error:string):Integer;
// WeKan's watch (server/notifications/watch.js) from a view: whoever can see
// the board watches a card - an assigned-only member only a card assigned to
// them (GHSA-r4gm-mjj9-g3x8) - and chooses their level on the board:
// watching, tracking or muted (WeKan's default, kept as no watcher at all).
function CardWatching(Db:TWLDb;const UserId,CardId:string):Boolean;
function BoardWatchLevel(Db:TWLDb;const UserId,BoardId:string):string;
function WatchViewCard(const T:TWLTenant;const UserId,BoardId,CardId:string;out Error:string):Integer;
function WatchViewBoard(const T:TWLTenant;const UserId,BoardId,Level:string;out Error:string):Integer;
// A card's Planning Poker (cardDetails.jade's poker section), on a board
// that allows it (allowsPoker): its question, the user's card in WeKan's
// deck, and whether they may play - WeKan's showPlanningPokerButtons: an
// active member, or anybody who can see the board when it allows
// non-members, until it ends.
const
  POKER_FIELDS: array[0..9] of string = ('one', 'two', 'three', 'five', 'eight', 'thirteen', 'twenty', 'forty',
    'oneHundred', 'unsure');
type
  TCardPoker = record
    Present, CanVote: Boolean;
    Question, Voted: string;
  end;
function ReadCardPoker(Db:TWLDb;const UserId,BoardId,CardId:string):TCardPoker;
// WeKan's cards.pokerVote: the user's card is State, and no other.
function PokerViewCard(const T:TWLTenant;const UserId,BoardId,CardId,State:string;out Error:string):Integer;
// attachmentActionsPopup: a raster image attached to the card as its cover,
// or none again, by whoever may change the card; and as the board's
// background, or none again, by a board admin. Only an attachment's own
// address (/cdn/storage/attachments/<id>) is stored as the background.
function SetViewCardCover(const T:TWLTenant;const UserId,BoardId,CardId,AttachmentId:string;out Error:string):Integer;
function SetViewBoardBackground(const T:TWLTenant;const UserId,BoardId,CardId,AttachmentId:string;out Error:string):Integer;
// Admin Panel / People from the HTML5 view (Weddy's admin_people.go, WeKan's
// editUserPopup): a site admin changes a user. Values holds the form's
// fields; with Partial only those present change (the table's Admin and
// Active toggles), else the whole form (username, fullname, initials,
// email, isAdmin, loginDisabled, and a new password when one is given).
// One's own admin and access are not one's own to take away here. A new
// password, or access taken away, signs the user out everywhere.
function AdminUpdateViewUser(const T:TWLTenant;const Actor,Target:string;Values:TStrings;Partial:Boolean;out Error:string):Integer;
// WeKan's setCreateUser: a site admin makes a password account.
function AdminCreateViewUser(const T:TWLTenant;const Actor,Fullname,Username,Initials,Password,IsAdmin,LoginDisabled,Email:string;
  out NewId,Error:string):Integer;
// The card's "Mark as complete" (dueComplete) from the minicard, by whoever
// may change the card.
function SetViewCardComplete(const T:TWLTenant;const UserId,BoardId,CardId:string;Done:Boolean;out Error:string):Integer;
// WeKan's AccountSettings (Admin Panel / People / Login): accounts-allowEmailChange
// and accounts-allowUserNameChange, read from a shared store's accountSettings
// (booleanValue); off in a store that has none.
function AccountSettingOn(Db:TWLDb;const Id:string):Boolean;
// WeKan's setUsername and setEmail: a site admin changes anybody's, a member
// their own while the setting allows it; a taken name or address is refused.
// Error is WeKan's error code (not-authorized, invalid-username,
// username-already-taken, invalid-email, email-already-taken).
function ViewSetUsername(const T:TWLTenant;const Actor,Target,Username:string;out Error:string):Integer;
function ViewSetEmail(const T:TWLTenant;const Actor,Target,Email:string;out Error:string):Integer;
// editProfilePopup: the user's own full name and initials.
function ViewSetOwnProfile(const T:TWLTenant;const UserId,Fullname,Initials:string;out Error:string):Integer;
// WeKan's archiveSelectedCards (Multi-Selection): the whole selection is
// checked first - each card on the board, not archived yet, an assigned-only
// member's only when assigned to them (GHSA-6xqf-jh8x-4wxc) - and only then
// is each archived, with its archivedCard activity.
function ArchiveViewCards(const T:TWLTenant;const UserId,BoardId:string;const Ids:array of string;out Error:string):Integer;
// WeKan's createBoardFromCard: the card becomes a link to a new board of its
// own, made by the caller - a writer of the card's board, or an assigned-only
// writer on a card assigned to them (UnassignedArchiveBleed otherwise).
function CreateBoardFromViewCard(const T:TWLTenant;const UserId,CardId,Title,DefaultLane:string;out BoardId,Error:string):Integer;
// WeKan's createBoardForm: a private board of the caller's with a Default
// swimlane, unless Admin Panel lets only admins make boards; MayCreateBoard
// answers whether they may, for the header's Create Board.
function CreateViewBoard(const T:TWLTenant;const UserId,Title,DefaultLane:string;out BoardId,Error:string):Integer;
function MayCreateBoard(Db:TWLDb;const UserId:string):Boolean;
// boardChangeVisibilityPopup: a board admin makes the board private, visible
// to the instance's signed-in users (#3249) or public.
function SetViewBoardVisibility(const T:TWLTenant;const UserId,BoardId,Visibility:string;out Error:string):Integer;
// WeKan's updateListSort: a list's sort and swimlane, by whoever may change
// its board; error codes are WeKan's (permission-denied, invalid-field,
// invalid-swimlane, board-not-found).
function SetViewListSort(const T:TWLTenant;const UserId,BoardId,ListId:string;Data:TJSONObject;out Error:string):Integer;
// A board invitation (profile.invitedBoards): WeKan's acceptInvite - 204 when
// the user holds none (#4730) - and quitBoard, which also declines one.
function ViewInvited(Db:TWLDb;const UserId,BoardId:string):Boolean;
function AcceptViewInvite(const T:TWLTenant;const UserId,BoardId:string;out Error:string):Integer;
function QuitViewBoard(const T:TWLTenant;const UserId,BoardId:string;out Error:string):Integer;
// One of the board's labels on the card, or off it (cardLabelsPopup).
function ToggleViewCardLabel(const T:TWLTenant;const UserId,BoardId,CardId,LabelId:string;out Error:string):Integer;
procedure ApiCard(aRequest: TRequest; aResponse: TResponse);
procedure ApiCardEdit(aRequest: TRequest; aResponse: TResponse);      // PUT card (title/desc/color/labels)
procedure ApiListCards(aRequest: TRequest; aResponse: TResponse);     // GET cards in a list
procedure ApiListCardsCount(aRequest: TRequest; aResponse: TResponse);
procedure ApiBoardCardsCount(aRequest: TRequest; aResponse: TResponse);
procedure ApiSwimlaneCards(aRequest: TRequest; aResponse: TResponse);
procedure ApiCardChecklists(aRequest: TRequest; aResponse: TResponse); // GET list / POST create
procedure ApiChecklist(aRequest: TRequest; aResponse: TResponse);      // GET one + items
procedure ApiChecklistItems(aRequest: TRequest; aResponse: TResponse); // POST add item
procedure ApiChecklistItem(aRequest: TRequest; aResponse: TResponse);  // GET/PUT(toggle)/DELETE item
procedure ApiCardComments(aRequest: TRequest; aResponse: TResponse);   // GET list / POST add
procedure ApiCardComment(aRequest: TRequest; aResponse: TResponse);    // GET one / DELETE one
function StoreAttachment(const T:TWLTenant;const UserId,BoardId,Sw,Lst,Crd,FileName,FileType:string; Content:TStream;
  out Id:string;RequireLiveCard:Boolean=False):Boolean;
procedure ApiAttachmentUpload(aRequest: TRequest; aResponse: TResponse);   // POST /api/attachment/upload
procedure ApiAttachmentDownload(aRequest: TRequest; aResponse: TResponse); // GET  /api/attachment/download/:id
procedure ApiAttachmentInfo(aRequest: TRequest; aResponse: TResponse);     // GET  /api/attachment/info/:id
function DeleteStoredAttachment(const T:TWLTenant;const Actor,BoardId,AttachmentId:string;
  const CardId:string=''):Boolean;
procedure ApiAttachmentDelete(aRequest: TRequest; aResponse: TResponse);   // DELETE /api/attachment/delete/:id
// May UserId change the attachments of CardId on BoardId (WeKan's
// userHasBoardWriteAccess, then mayWriteCardAttachment): a board writer, or an
// assigned-only writer on a card assigned to them. 200, or 403 - an
// assigned-only member's refusal recorded as UnassignedAttachBleed from Source.
function AttachmentWriteAllowed(Db:TWLDb;const UserId,BoardId,CardId,Source:string):Integer;
// models/lib/boardCardScope.js isAssignedOnlyMember: an active member whose
// role sees only the cards assigned to them.
function AssignedOnlyMember(Db:TWLDb;const UserId,BoardId:string):Boolean;
// A live card of BoardId that is assigned to UserId.
function CardAssignedTo(Db:TWLDb;const UserId,BoardId,CardId:string):Boolean;
procedure ApiBoardAttachments(aRequest: TRequest; aResponse: TResponse);   // GET  /api/boards/:boardId/attachments
procedure ApiCardAttachmentsList(aRequest: TRequest; aResponse: TResponse);// GET /api/attachment/list/:b/:s/:l/:c
procedure ApiCardMember(aRequest: TRequest; aResponse: TResponse);     // POST/DELETE card member
procedure ApiCardAssignee(aRequest: TRequest; aResponse: TResponse);   // POST/DELETE card assignee
procedure ApiCardArchive(aRequest: TRequest; aResponse: TResponse);    // POST archive/unarchive
procedure ApiBulkCardLabels(aRequest:TRequest;aResponse:TResponse);
procedure ApiBulkCardDelete(aRequest:TRequest;aResponse:TResponse);
procedure ApiCardDelete(aRequest: TRequest; aResponse: TResponse);     // DELETE card
procedure ApiListDelete(aRequest: TRequest; aResponse: TResponse);     // DELETE list (+ its cards)
procedure ApiBoardDelete(aRequest: TRequest; aResponse: TResponse);    // DELETE board (cascade)
procedure ApiSwimlaneDelete(aRequest: TRequest; aResponse: TResponse); // DELETE swimlane (+ its cards)

// A list soft-deleted with its cards in one batch (lists.softRemove).
function SoftRemoveViewList(const T:TWLTenant;const UserId,BoardId,ListId:string;out Error:string):Integer;
implementation
uses wlstore,wlsjson,Math,StrUtils,wlfold,wlcfjson,wlcfpol,wlpath,wlcfspec,wlselscp,wlcolors,wlposhis,wlrevoke,wlautsrc,wli18n,wllocale,wlselect,wlferr,wlwhurl,wlhtml,wlshared,wlattdel,wlroutes,wlrules,wlchhist,wlcsvexp,wlxlsxexp,zipper,wlh5,wlthumb,Types,wlzipimp;

// 17-char Mongo-style id (schema.sql convention)
function NewId: string;
const A = '23456789ABCDEFGHJKLMNPQRSTWXYZabcdefghijkmnopqrstuvwxyz';
var i: Integer;
begin
  SetLength(Result, 17);
  for i := 1 to 17 do Result[i] := A[Random(Length(A)) + 1];
end;

function NowIso: string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',LocalTimeToUniversal(Now));
end;

procedure SendJson(aResponse: TResponse; const Json: string; Code: Integer = 200);
begin
  aResponse.Code := Code;
  aResponse.ContentType := 'application/json; charset=utf-8';
  aResponse.Content := Json;
  aResponse.ContentLength := Length(aResponse.Content);
  SendResponse(aResponse);
end;

procedure SendError(aResponse: TResponse; Code: Integer; const Reason: string);
begin
  SendJson(aResponse, Format('{"error":%d,"reason":%s}', [Code, AnsiQuotedStr(Reason, '"')]), Code);
end;

function ApiBodyValid(Request:TRequest; AllowArray: Boolean):Boolean;
var D:TJSONData;
begin
  Result:=True;
  if (Request.Method='GET') or (Request.Content='') or
    (Pos('application/json',LowerCase(Request.ContentType))<>1) then Exit;
  D:=nil;
  try
    try D:=GetJSON(Request.Content); Result:=(D is TJSONObject) or (AllowArray and (D is TJSONArray)); except Result:=False; end;
  finally D.Free; end;
end;

// Resolve the tenant for an API request, or send a JSON error. Static, no web session needed.
function ApiTenant(aRequest: TRequest; aResponse: TResponse; out T: TWLTenant; AllowArray: Boolean = False): Boolean;
begin
  if not DecodeApiPath(aRequest) then
  begin Result:=False;SendError(aResponse,400,'Invalid encoded route identifier');Exit;end;
  Result := ResolveTenant(aRequest, T) and TenantOpen(T);
  if not Result then SendError(aResponse,404,'Unknown domain')
  else if not ApiBodyValid(aRequest,AllowArray) then
  begin Result:=False; SendError(aResponse,400,'Expected a valid JSON object'); end;
end;

function BearerToken(Request:TRequest):string;
var Header:string;
begin
  Header:=Request.Authorization;
  if Header='' then Header:=Request.CustomHeaders.Values['Authorization'];
  Result:='';
  if Pos('Bearer ',Header)=1 then Result:=Trim(Copy(Header,8,Length(Header)));
end;

// Bearer token -> userId via login_tokens; sends 401 JSON if missing/invalid.
function ApiAuth(const T: TWLTenant; aRequest: TRequest; aResponse: TResponse;
  out UserId: string): Boolean;
var
  Token:string;
begin
  Result:=False;UserId:='';
  Token:=BearerToken(aRequest);
  if (Token='') and (Pos('Bearer ',aRequest.Authorization)<>1) and
    (Pos('Bearer ',aRequest.CustomHeaders.Values['Authorization'])<>1) then
    Token:=Trim(aRequest.QueryFields.Values['token']);
  // WeKan's export links carry it as authToken (server/authentication.js).
  if (Token='') and (Pos('Bearer ',aRequest.Authorization)<>1) and
    (Pos('Bearer ',aRequest.CustomHeaders.Values['Authorization'])<>1) then
    Token:=Trim(aRequest.QueryFields.Values['authToken']);
  if Token = '' then begin SendError(aResponse, 401, 'No token'); Exit; end;

  Result:=ValidateLoginToken(T.Db,aRequest,Token,UserId);
  if not Result then SendError(aResponse,401,'Invalid token');
end;

function IsSiteAdmin(Db: TWLDb; const UserId: string): Boolean;
var R: TWLRows;
begin
  R := Db.Query(Format('SELECT isAdmin FROM users WHERE id=%s AND COALESCE(loginDisabled,0)=0 LIMIT 1;', [QuotedStr(UserId)]));
  Result := (Length(R) > 0) and (Length(R[0]) > 0) and (R[0][0] = '1');
end;

// Authorize the user for a board: site admin → always; active member → yes (write blocked if
// read-only); public board → read only. Sends 403 and returns False otherwise.
function ApiAuthBoard(const T: TWLTenant; aResponse: TResponse;
  const UserId, BoardId: string; NeedWrite: Boolean): Boolean;
begin
  if NeedWrite then Result:=BoardCanWrite(T.Db,UserId,BoardId)
  else Result:=BoardCanRead(T.Db,UserId,BoardId);
  if not Result then SendError(aResponse,403,'Board access forbidden');
end;

// WeKan's board.hasMember: an active member, whatever the role.
function BoardHasMember(Db:TWLDb;const UserId,BoardId:string):Boolean;
begin
  Result:=(UserId<>'') and (Pos(#0,BoardId)=0) and (Length(Db.Query('SELECT 1 FROM board_members WHERE boardId='+QuotedStr(BoardId)+
    ' AND userId='+QuotedStr(UserId)+' AND isActive=1;'))=1);
end;

// models/lib/boardCardScope.js isAssignedOnlyMember.
function AssignedOnlyMember(Db:TWLDb;const UserId,BoardId:string):Boolean;
begin
  Result:=Length(Db.Query('SELECT 1 FROM board_members WHERE boardId='+QuotedStr(BoardId)+' AND userId='+QuotedStr(UserId)+
    ' AND isActive=1 AND (COALESCE(isNormalAssignedOnly,0)=1 OR COALESCE(isCommentAssignedOnly,0)=1 OR '+
    'COALESCE(isReadAssignedOnly,0)=1);'))=1;
end;

// A live card of BoardId that is assigned to UserId.
function CardAssignedTo(Db:TWLDb;const UserId,BoardId,CardId:string):Boolean;
begin
  Result:=(CardId<>'') and (Pos(#0,CardId)=0) and (Length(Db.Query('SELECT 1 FROM cards c WHERE c.id='+QuotedStr(CardId)+
    ' AND c.boardId='+QuotedStr(BoardId)+' AND c.deletedAt IS NULL AND EXISTS(SELECT 1 FROM card_assignees a WHERE a.cardId=c.id '+
    'AND a.userId='+QuotedStr(UserId)+');'))=1);
end;

// The same as SQL, for a write's own transaction guard: an assigned-only
// writer (isNormalAssignedOnly) of a live board, on their own card.
function AssignedWriterSql(const UserId,BoardId,CardId:string):string;
begin
  Result:='(EXISTS(SELECT 1 FROM board_members m JOIN boards b ON b.id=m.boardId JOIN users u ON u.id=m.userId WHERE m.boardId='+
    QuotedStr(BoardId)+' AND m.userId='+QuotedStr(UserId)+' AND m.isActive=1 AND COALESCE(m.isNormalAssignedOnly,0)=1 AND '+
    'b.archived=0 AND u.loginDisabled=0) AND EXISTS(SELECT 1 FROM card_assignees a WHERE a.cardId='+QuotedStr(CardId)+
    ' AND a.userId='+QuotedStr(UserId)+'))';
end;

// allowIsBoardMemberWithWriteAccess: a writer of the board, or an active
// assigned-only writer (isNormalAssignedOnly), whose cards are checked apart.
function AssignedWriterOn(Db:TWLDb;const UserId,BoardId:string):Boolean;
begin
  Result:=BoardCanWrite(Db,UserId,BoardId) or (Length(Db.Query('SELECT 1 FROM board_members WHERE boardId='+QuotedStr(BoardId)+
    ' AND userId='+QuotedStr(UserId)+' AND isActive=1 AND COALESCE(isNormalAssignedOnly,0)=1;'))=1);
end;

function AttachmentWriteAllowed(Db:TWLDb;const UserId,BoardId,CardId,Source:string):Integer;
begin
  if not AssignedWriterOn(Db,UserId,BoardId) then Exit(403);
  if AssignedOnlyMember(Db,UserId,BoardId) and not CardAssignedTo(Db,UserId,BoardId,CardId) then
  begin
    try
      RecordSecurityEvent(Db,UserId,'UnassignedAttachBleed',Source,'authz','medium','CWE-863','blocked',
        'Assigned-only member tried to change an attachment of a card not assigned to them.');
    except
      // logging must never break the guard
    end;
    Exit(403);
  end;
  Result:=200;
end;

// May UserId read an attachment of CardId on BoardId (board.hasMember, then
// mayReadBoardAttachment): a member or reader of the board, and an
// assigned-only member only of a card assigned to them - the refusal recorded
// as AssignedBleed from Source.
function AttachmentReadAllowed(Db:TWLDb;const UserId,BoardId,CardId,Source:string):Boolean;
begin
  if not (BoardCanRead(Db,UserId,BoardId) or BoardHasMember(Db,UserId,BoardId)) then Exit(False);
  Result:=not AssignedOnlyMember(Db,UserId,BoardId) or CardAssignedTo(Db,UserId,BoardId,CardId);
  if not Result then
  try
    RecordSecurityEvent(Db,UserId,'AssignedBleed',Source,'authz','medium','CWE-863','blocked',
      'Assigned-only member asked for an attachment of a card not assigned to them.');
  except
    // logging must never break the guard
  end;
end;

// Common guard for board-scoped endpoints: boardId from the route, write = non-GET.
// Check the whole resource chain, even for site administrators: permission on board A
// never makes a card/list/checklist from board B a child of A.
function ApiChildrenBelong(Db:TWLDb; const BoardId, LaneId, ListId, CardId,
  ChecklistId, ItemId, CommentId, CustomFieldId:string):Boolean;
  function Exists(const Sql:string):Boolean;
  begin Result:=Length(Db.Query(Sql))>0; end;
var Scope:string;
begin
  Result:=False;
  if (LaneId<>'') and not Exists('SELECT id FROM swimlanes WHERE id='+QuotedStr(LaneId)+
    ' AND boardId='+QuotedStr(BoardId)+';') then Exit;
  Scope:='';
  if LaneId<>'' then Scope:=' AND (swimlaneId='''' OR swimlaneId='+QuotedStr(LaneId)+')';
  if (ListId<>'') and not Exists('SELECT id FROM lists WHERE id='+QuotedStr(ListId)+
    ' AND deletedAt IS NULL AND boardId='+QuotedStr(BoardId)+Scope+';') then Exit;
  Scope:='';
  if ListId<>'' then Scope:=Scope+' AND listId='+QuotedStr(ListId);
  if LaneId<>'' then Scope:=Scope+' AND swimlaneId='+QuotedStr(LaneId);
  if (CardId<>'') and not Exists('SELECT id FROM cards WHERE id='+QuotedStr(CardId)+
    ' AND deletedAt IS NULL AND boardId='+QuotedStr(BoardId)+Scope+';') then Exit;
  if (ChecklistId<>'') and not Exists('SELECT id FROM checklists WHERE id='+QuotedStr(ChecklistId)+
    ' AND cardId='+QuotedStr(CardId)+' AND (boardId IS NULL OR boardId='+QuotedStr(BoardId)+');') then Exit;
  if (ItemId<>'') and not Exists('SELECT id FROM checklist_items WHERE id='+QuotedStr(ItemId)+
    ' AND checklistId='+QuotedStr(ChecklistId)+' AND cardId='+QuotedStr(CardId)+
    ' AND (boardId IS NULL OR boardId='+QuotedStr(BoardId)+');') then Exit;
  if (CommentId<>'') and not Exists('SELECT id FROM card_comments WHERE id='+QuotedStr(CommentId)+
    ' AND cardId='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+';') then Exit;
  if (CustomFieldId<>'') and not Exists('SELECT customFieldId FROM custom_field_boards WHERE customFieldId='+
    QuotedStr(CustomFieldId)+' AND boardId='+QuotedStr(BoardId)+';') then Exit;
  Result:=True;
end;

function ApiBoardGuard(const T: TWLTenant; aRequest: TRequest; aResponse: TResponse;
  const UserId: string; const ScopeErrorJson: string = ''): Boolean;
begin
  Result := ApiAuthBoard(T, aResponse, UserId, aRequest.RouteParams['boardId'],
    aRequest.Method <> 'GET');
  if not Result then Exit;
  Result:=ApiChildrenBelong(T.Db,aRequest.RouteParams['boardId'],aRequest.RouteParams['swimlaneId'],
    aRequest.RouteParams['listId'],aRequest.RouteParams['cardId'],aRequest.RouteParams['checklistId'],
    aRequest.RouteParams['item'],aRequest.RouteParams['commentId'],aRequest.RouteParams['customField']);
  if not Result then
    if ScopeErrorJson<>'' then SendJson(aResponse,ScopeErrorJson,404)
    else SendError(aResponse,404,'Resource does not belong to this board or parent');
end;

// read a form OR json field from the request body
function BodyField(aRequest: TRequest; const Name: string): string;
var D: TJSONData;
begin
  Result := aRequest.ContentFields.Values[Name];
  if Result <> '' then Exit;
  if aRequest.Content<>'' then
    try
      D := GetJSON(aRequest.Content);
      try
        if D is TJSONObject then Result := TJSONObject(D).Get(Name, '');
      finally D.Free; end;
    except end;
end;

function BodyHasField(Request:TRequest; const Name:string):Boolean;
var D:TJSONData;
begin
  Result:=Request.ContentFields.IndexOfName(Name)>=0;
  if Result or (Request.Content='') then Exit;
  D:=nil;
  try
    try D:=GetJSON(Request.Content); Result:=(D is TJSONObject) and (TJSONObject(D).Find(Name)<>nil); except Result:=False; end;
  finally D.Free; end;
end;
function EnabledBoardMember(Db:TWLDb; const BoardId,TargetId:string):Boolean;
begin
  Result:=Length(Db.Query('SELECT u.id FROM users u JOIN board_members m ON m.userId=u.id '+
    'WHERE u.id='+QuotedStr(TargetId)+' AND COALESCE(u.loginDisabled,0)=0 AND m.boardId='+QuotedStr(BoardId)+
    ' AND m.isActive=1;'))>0;
end;
function ValidAuthor(Db:TWLDb; const BoardId,Actor,Author:string):Boolean;
begin
  Result:=False;
  if Length(Db.Query('SELECT id FROM users WHERE id='+QuotedStr(Author)+' AND COALESCE(loginDisabled,0)=0;'))=0 then Exit;
  if Actor=Author then Exit(True);
  Result:=IsSiteAdmin(Db,Actor) and EnabledBoardMember(Db,BoardId,Author);
end;
function ReadBodyIds(Request:TRequest; const Name:string; Ids:TStrings; AllowNull:Boolean=False;Entry:TJSONObject=nil):Boolean;
var D,V:TJSONData; A:TJSONArray; i:Integer; Text,Id:string; Parts:TStringArray;
begin
  Result:=False; D:=nil; Text:='';
  try
    try
      if (Entry=nil) and (Request.ContentFields.IndexOfName(Name)>=0) then Text:=Request.ContentFields.Values[Name]
      else
      begin
        if Entry=nil then
        begin
          D:=GetJSON(Request.Content);
          if not (D is TJSONObject) then Exit;
          Entry:=TJSONObject(D);
        end;
        V:=Entry.Find(Name); if V=nil then Exit;
        if AllowNull and (V.JSONType=jtNull) then Exit(True);
        if V is TJSONArray then
        begin
          A:=TJSONArray(V);
          for i:=0 to A.Count-1 do
          begin
            if A.Items[i].JSONType<>jtString then Exit;
            Id:=Trim(A.Items[i].AsString); if Id='' then Exit;
            if Ids.IndexOf(Id)<0 then Ids.Add(Id);
          end;
          Exit(True);
        end;
        if V.JSONType<>jtString then Exit;
        Text:=V.AsString;
      end;
      if Trim(Text)='' then Exit(True);
      Parts:=Text.Split([',']);
      for i:=0 to High(Parts) do
      begin
        Id:=Trim(Parts[i]); if Id='' then Exit;
        if Ids.IndexOf(Id)<0 then Ids.Add(Id);
      end;
      Result:=True;
    except Result:=False; end;
  finally D.Free; end;
end;
function InitializeSharedAssignments(Db:TWLDb;const BoardId,CardId:string;Members,Assignees:Boolean):string;
const Doc='_ferretdb_sjson';
var Rows:TWLRows;Scope:TSelectionScope;I:Integer;Name,TableName,Match,Path,Value:string;
begin
  Result:='';
  if not (Members or Assignees) then Exit;
  Rows:=Db.Query('SELECT type FROM sqlite_master WHERE name=''cards'';');
  if Length(Rows)<>1 then raise Exception.Create('Missing card source');
  if Rows[0][0]='table' then Exit;
  Scope:=TSelectionScope.Create(Db);
  try
    Scope.StringField('cards','id');
    for I:=0 to Scope.Bindings.Count-1 do Result:=Result+Scope.Bindings[I];
  finally Scope.Free;end;
  Rows:=Db.Query('SELECT m.table_name FROM _wl_models m JOIN _ferretdb_collections c ON m.table_name=c.table_name '+
    'WHERE m.name=''cards'' AND c.name=''cards'';');
  if Length(Rows)<>1 then raise Exception.Create('Ambiguous card source');
  TableName:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
  Match:='json_extract('+Doc+',''$._id'')='+QuotedStr(CardId)+
    ' AND json_extract('+Doc+',''$.boardId'')='+QuotedStr(BoardId)+
    ' AND json_extract('+Doc+',''$.$s.p._id.t'')=''string'' AND json_extract('+Doc+',''$.$s.p.boardId.t'')=''string''';
  for Name in ['members','assignees'] do
  begin
    if ((Name='members') and not Members) or ((Name='assignees') and not Assignees) then Continue;
    Path:=QuotedStr('$.'+Name);
    Value:='wl_sjson(json_set(wl_plain(json('+Doc+')),'+Path+',json(''[]'')),json('+Doc+'),''{}'')';
    Result:=Result+'UPDATE '+TableName+' SET '+Doc+'=CASE WHEN wl_storage('+QuotedStr(Rows[0][0])+')=''blob'' '+
      'THEN jsonb('+Value+') ELSE '+Value+' END WHERE '+Match+' AND COALESCE(json_type('+Doc+','+Path+
      '),''null'')=''null''; ';
    Result:=Result+'SELECT CASE WHEN (SELECT count(*) FROM '+TableName+' WHERE '+Match+
      ' AND json_type('+Doc+','+Path+')=''array'')=1 THEN 1 ELSE json(''Invalid card assignment source'') END; ';
  end;
end;

// Build relation changes only after validating all identifiers. The caller executes these
// changes with the card write in one transaction, so invalid data cannot partially edit it.
function CardRelationSql(const T:TWLTenant; Request:TRequest; Response:TResponse;
  const BoardId,CardId:string; out Sql:string; Creating:Boolean=False;Entry:TJSONObject=nil):Boolean;
const Fields:array[0..2] of string=('labelIds','members','assignees');
  Tables:array[0..2] of string=('card_labels','card_members','card_assignees');
var Ids:TStringList; i,j:Integer; Column:string;
  function Present(const Field:string):Boolean;
  begin
    if Entry<>nil then Result:=Entry.Find(Field)<>nil
    else Result:=BodyHasField(Request,Field);
  end;
  procedure Reject(Code:Integer;const Reason:string);
  begin
    if Response<>nil then SendError(Response,Code,Reason);
  end;
begin
  Result:=False; Sql:=''; Ids:=TStringList.Create; Ids.CaseSensitive:=True;
  try
    for i:=0 to High(Fields) do if Present(Fields[i]) then
    begin
      Ids.Clear;
      if not ReadBodyIds(Request,Fields[i],Ids,i>0,Entry) then
      begin Reject(400,'Expected an ID array or comma-separated string'); Exit; end;
      if i=0 then Column:='labelId' else Column:='userId';
      for j:=0 to Ids.Count-1 do
        if ((i=0) and (Length(T.Db.Query('SELECT id FROM board_labels WHERE boardId='+QuotedStr(BoardId)+
          ' AND id='+QuotedStr(Ids[j])+';'))=0)) or
          ((i>0) and not EnabledBoardMember(T.Db,BoardId,Ids[j])) then
        begin Reject(400,'ID does not belong to an enabled board member or board label'); Exit; end;
      Sql:=Sql+'DELETE FROM '+Tables[i]+' WHERE cardId='+QuotedStr(CardId)+'; ';
      for j:=0 to Ids.Count-1 do Sql:=Sql+'INSERT INTO '+Tables[i]+'(cardId,'+Column+') VALUES('+
        QuotedStr(CardId)+','+QuotedStr(Ids[j])+'); ';
    end;
    try
      Sql:=InitializeSharedAssignments(T.Db,BoardId,CardId,Creating or Present('members'),
        Creating or Present('assignees'))+Sql;
    except Reject(500,'Could not initialize card assignments');Exit;end;
    Result:=True;
  finally Ids.Free; end;
end;

// ---- rows -> JSON array of {_id,title} ---------------------------------------------------
function RowsAsIdTitle(const R: TWLRows): string;
var A: TJSONArray; O: TJSONObject; i: Integer;
begin
  A := TJSONArray.Create;
  try
    for i := 0 to High(R) do
      if Length(R[i]) >= 2 then
      begin
        O := TJSONObject.Create;
        O.Add('_id', R[i][0]); O.Add('title', R[i][1]);
        A.Add(O);
      end;
    Result := A.AsJSON;
  finally A.Free; end;
end;

// ================================ endpoints ===============================================

procedure ApiLogin(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant;
  Username, Password, Token:string;
  Proof:TWLLoginProof;
  O:TJSONObject;Ttl:Int64;Expires:TWLRows;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  Username:=Trim(BodyField(aRequest,'username'));
  if Username='' then Username:=Trim(BodyField(aRequest,'email'));
  Password:=BodyField(aRequest,'password');
  if not ReserveLoginAttempt(T.Db,Username,aRequest.RemoteAddress,DateTimeToUnix(Now,False)) then
  begin
    aResponse.SetCustomHeader('Retry-After','300');
    SendError(aResponse,429,'Too many login attempts. Try again later.');Exit;
  end;
  Proof:=nil;
  if not AuthenticateAccount(T.Db,Username,Password,BodyField(aRequest,'code'),Proof) then
  begin SendError(aResponse,401,'Incorrect credentials or one-time code');Exit;end;
  try
    Token:=NewAuthToken;Ttl:=ApiTokenLifetime(T.Db);
    if not IssueAccountToken(T.Db,Proof,Token,'api',Ttl) then
    begin SendError(aResponse,500,'Could not create login token');Exit;end;
    Expires:=T.Db.Query('SELECT expiresAt FROM login_tokens WHERE hashedToken='+QuotedStr(TokenHash(T.Db,Token))+';');
    if (Length(Expires)<>1) or (Expires[0][0]='') then begin SendError(aResponse,500,'Could not read token expiry');Exit;end;
    O:=TJSONObject.Create;
    try
      O.Add('id',Proof.UserId);O.Add('token',Token);
      O.Add('tokenExpires',Expires[0][0]);
      SendJson(aResponse,O.AsJSON);
    finally O.Free;end;
  finally Proof.Free;end;
end;

procedure ApiLogout(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;Token,UserId,Flag,Sql:string;Body,Value:TJSONData;AllSessions:Boolean;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  Token:=BearerToken(aRequest);
  if (Token='') or not ValidateLoginToken(T.Db,aRequest,Token,UserId) then
  begin SendError(aResponse,401,'Invalid bearer token');Exit;end;
  Flag:=aRequest.ContentFields.Values['all'];
  if (Pos('application/json',LowerCase(aRequest.ContentType))=1) and (aRequest.Content<>'') then
  begin
    Body:=GetJSON(aRequest.Content);
    try
      Flag:='';Value:=TJSONObject(Body).Find('all');
      if Value<>nil then
        case Value.JSONType of
          jtString: Flag:=Value.AsString;
          jtBoolean: if Value.AsBoolean then Flag:='true';
          jtNumber: if Value.AsFloat=1 then Flag:='1';
        end;
    finally Body.Free;end;
  end;
  Flag:=LowerCase(Trim(Flag));
  AllSessions:=(Flag='true') or (Flag='1') or (Flag='yes');
  try
    if AllSessions then Sql:=RevokeLoginSessionsSQL(T.Db,UserId)
    else Sql:=RevokeTokenSQL(T.Db,UserId,Token);
    if not T.Db.Exec('BEGIN IMMEDIATE; '+Sql+'COMMIT;') then
      raise Exception.Create('Logout transaction failed');
  except
    T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Logout failed');Exit;
  end;
  if AllSessions then SendJson(aResponse,'{"message":"All login tokens have been invalidated."}')
  else SendJson(aResponse,'{"message":"You''ve been logged out!"}');
end;

procedure ApiCreateToken(aRequest:TRequest;aResponse:TResponse);
const AuditCollection='impersonatedUsers';
var T:TWLTenant;Actor,Target,Reason,Token,Guard,Audit,Source,Physical,Payload,Stamp,Reference:string;
  Rows:TWLRows;Input,Doc:TJSONObject;Value:TJSONData;AtTime:TDateTime;AtMs:Int64;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  if not IsSiteAdmin(T.Db,Actor) then
  begin SendError(aResponse,403,'Site administration required');Exit;end;
  Target:=aRequest.RouteParams['userId'];
  Reason:='';Input:=nil;
  try
    try
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
      begin
        Input:=ExactObject(aRequest.Content);Value:=Input.Find('reason');
        if Value is TJSONString then Reason:=Value.AsString;
      end
      else Reason:=aRequest.ContentFields.Values['reason'];
      Reason:=Trim(Reason);
      if (Pos(#0,Reason)>0) or (Pos(#0,Target)>0) then raise Exception.Create('Invalid input');
    except SendError(aResponse,400,'Invalid token creation request');Exit;end;
  finally Input.Free;end;
  if Reason='' then
  begin SendJson(aResponse,'{"error":"A reason is required when creating a token for another user"}',400);Exit;end;
  Rows:=T.Db.Query('SELECT COALESCE(json_extract(services_json,''$.password''),''''),COALESCE(loginDisabled,0) '+
    'FROM users WHERE id='+QuotedStr(Target)+';');
  if Length(Rows)<>1 then
  begin SendJson(aResponse,'{"error":"User not found"}',404);Exit;end;
  if Rows[0][1]<>'0' then
  begin SendError(aResponse,403,'Account is disabled');Exit;end;
  Guard:='EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(Actor)+' AND isAdmin=1 AND COALESCE(loginDisabled,0)=0)'+
    ' AND (SELECT count(*) FROM users WHERE id='+QuotedStr(Target)+' AND COALESCE(loginDisabled,0)=0)=1';
  try
    // Truncate by characters inside SQLite before constructing the audit document.
    Reference:=CredentialFingerprint(Rows[0][0]);
    Rows:=T.Db.Query('SELECT substr('+QuotedStr(Reason)+',1,500);');
    if Length(Rows)<>1 then raise Exception.Create('Audit reason unavailable');
    Reason:='restCreateToken: '+Rows[0][0];
    AtTime:=LocalTimeToUniversal(Now);
    if SharedStore(T.Db) then
    begin
      if not EnsureSharedCollection(T.Db,AuditCollection) then raise Exception.Create('Audit collection unavailable');
      Rows:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(AuditCollection)+';');
      if Length(Rows)<>1 then raise Exception.Create('Audit collection unavailable');
      Source:=Rows[0][0];
      Physical:='"'+StringReplace(Source,'"','""',[rfReplaceAll])+'"';
      Guard:=Guard+' AND (SELECT count(*) FROM _ferretdb_collections WHERE name='+QuotedStr(AuditCollection)+
        ' AND table_name='+QuotedStr(Source)+')=1';
      AtMs:=DateTimeToUnix(AtTime,True)*1000+MilliSecondOf(AtTime);
      Doc:=TJSONObject.Create(['_id',NewId,'adminId',Actor,'userId',Target,'reason',Reason,'createdAt',AtMs,'modifiedAt',AtMs]);
      try Payload:=QuotedStr(TypedDocument(Doc.AsJSON,'','{"createdAt":"date","modifiedAt":"date"}'));finally Doc.Free;end;
      Audit:='INSERT INTO '+Physical+'(_ferretdb_sjson) VALUES(CASE WHEN wl_storage('+QuotedStr(Source)+
        ')=''blob'' THEN jsonb('+Payload+') ELSE '+Payload+' END); ';
    end
    else
    begin
      Stamp:=QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',AtTime));
      Audit:='CREATE TABLE IF NOT EXISTS impersonatedUsers(id TEXT PRIMARY KEY,adminId TEXT NOT NULL,'+
        'userId TEXT NOT NULL,reason TEXT NOT NULL,createdAt TEXT NOT NULL,modifiedAt TEXT NOT NULL); '+
        'INSERT INTO impersonatedUsers VALUES('+QuotedStr(NewId)+','+QuotedStr(Actor)+','+
        QuotedStr(Target)+','+QuotedStr(Reason)+','+Stamp+','+Stamp+'); ';
    end;
    Token:=NewAuthToken;
    if not IssueLoginToken(T.Db,Target,Token,Reference,'api',
      wlauth.ApiTokenLifetime(T.Db),Guard,Audit) then raise Exception.Create('Token issuance failed');
  except SendError(aResponse,403,'Could not issue a token for this account');Exit;end;
  Doc:=TJSONObject.Create(['_id',Target,'authToken',Token]);
  try SendJson(aResponse,Doc.AsJSON);finally Doc.Free;end;
end;

procedure ApiDeleteToken(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;Actor,Target,Hash,Scope,Guard,Mutation,Message:string;
  Input:TJSONObject;Value:TJSONData;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  if not IsSiteAdmin(T.Db,Actor) then
  begin SendError(aResponse,403,'Site administration required');Exit;end;
  Target:='';Hash:='';
  Input:=nil;
  try
    try
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
      begin
        Input:=ExactObject(aRequest.Content);
        Value:=Input.Find('userId');
        if (Value<>nil) and not (Value is TJSONString) then raise Exception.Create('Invalid user ID');
        if Value<>nil then Target:=Value.AsString;
        Value:=Input.Find('token');
        if (Value<>nil) and not (Value is TJSONString) then raise Exception.Create('Invalid token hash');
        if Value<>nil then Hash:=Value.AsString;
      end
      else
      begin
        Target:=aRequest.ContentFields.Values['userId'];
        Hash:=aRequest.ContentFields.Values['token'];
      end;
      if Pos(#0,Target)>0 then raise Exception.Create('Invalid user ID');
    except SendError(aResponse,400,'Invalid token deletion request');Exit;end;
  finally Input.Free;end;
  if Target='' then
  begin SendJson(aResponse,'{"message":"Expected a userId to be set but received none."}');Exit;end;
  Scope:='id='+QuotedStr(Target);
  if Length(T.Db.Query('SELECT 1 FROM users WHERE '+Scope+';'))<>1 then
  begin SendJson(aResponse,'{"error":"User not found"}',404);Exit;end;
  Guard:='(SELECT count(*) FROM users WHERE '+Scope+')=1 AND EXISTS(SELECT 1 FROM users WHERE id='+
    QuotedStr(Actor)+' AND isAdmin=1 AND COALESCE(loginDisabled,0)=0)';
  try
    if Hash='' then
    begin Mutation:=RevokeLoginSessionsSQL(T.Db,Target);Message:='All login tokens have been invalidated.';end
    else
    begin Mutation:=RevokeStoredTokenSQL(T.Db,Target,Hash);Message:='Token deletion processed.';end;
    if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN '+Guard+
      ' THEN 1 ELSE json(''Token deletion scope changed'') END; '+Mutation+
      'SELECT CASE WHEN '+Guard+' THEN 1 ELSE json(''Token deletion scope changed'') END; COMMIT;') then
      raise Exception.Create('Token deletion failed');
  except T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not revoke tokens');Exit;end;
  SendJson(aResponse,'{"message":"'+StringToJSONString(Message)+'"}');
end;

function BoardDomains(Db:TWLDb;const Scope:string):TJSONArray;
var Row:TWLRow;
begin
  Result:=TJSONArray.Create;
  try
    for Row in Db.Query('SELECT domain,isActive FROM board_domains WHERE '+Scope+';') do
      Result.Add(TJSONObject.Create(['domain',Row[0],'isActive',Row[1]='1']));
  except Result.Free;raise;end;
end;

procedure ApiBoardDomains(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"Board not found"}';
  Forbidden='{"error":"Only a board admin can change board domains"}';
var T:TWLTenant;Actor,BoardId,Board,Domain,Scope,KeyScope,Permission,Bindings,Mutation,Guard,Method,AfterWrite:string;
  Policy:TFieldPolicy;Selector:TSelectionScope;Rows:TWLRows;I:Integer;
  Reply:TJSONArray;Input:TJSONObject;Value:TJSONData;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];Board:=QuotedStr(BoardId);Method:=aRequest.Method;
  if (Method='GET') and not IsSiteAdmin(T.Db,Actor) then
  begin SendError(aResponse,403,'Site administration required');Exit;end;
  Selector:=TSelectionScope.Create(T.Db);
  try
    if Length(T.Db.Query('SELECT id FROM boards WHERE id='+Board+' AND '+Selector.StringField('boards','id')+';'))<>1 then
    begin SendJson(aResponse,NotFound,404);Exit;end;
    Scope:='boardId='+Board;
    KeyScope:=Scope+' AND '+Selector.StringField('board_domains','domain');
    if Method<>'GET' then
    begin
      Policy:=TFieldPolicy.Create(T.Db,Actor,BoardId,'');
      try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
      if Length(T.Db.Query('SELECT 1 WHERE '+Permission+';'))<>1 then
      begin SendJson(aResponse,Forbidden,403);Exit;end;
      Domain:=aRequest.RouteParams['domain'];
      if Method='POST' then
      begin
        try
          Input:=ExactObject(aRequest.Content);
          try
            Value:=Input.Find('domain');
            if not (Value is TJSONString) then raise EConvertError.Create('Missing domain');
            Domain:=Value.AsString;
          finally Input.Free;end;
        except SendError(aResponse,400,'Missing domain');Exit;end;
      end;
      Domain:=LowerCase(Trim(Domain));
      if Pos(#0,Domain)>0 then begin SendError(aResponse,400,'Invalid domain');Exit;end;
      if Method='POST' then
      begin
        if (Pos('.',Domain)=0) or (Pos('@',Domain)>0) then
        begin SendError(aResponse,400,'Invalid domain');Exit;end;
        for I:=1 to Length(Domain) do
          if Domain[I]<=' ' then begin SendError(aResponse,400,'Invalid domain');Exit;end;
      end;
      Guard:=Scope+' AND domain='+QuotedStr(Domain);
      Rows:=T.Db.Query('SELECT domain FROM board_domains WHERE '+Guard+';');
      if (Length(Rows)>1) or ((Length(Rows)=1) and
        (Length(T.Db.Query('SELECT 1 FROM board_domains WHERE '+KeyScope+' AND domain='+QuotedStr(Domain)+';'))<>1)) then
      begin SendError(aResponse,409,'Ambiguous domain');Exit;end;
      if (Method='DELETE') and (Length(Rows)=0) then
      begin SendJson(aResponse,'{"error":"Domain not found"}',404);Exit;end;
      Bindings:='';for I:=0 to Selector.Bindings.Count-1 do Bindings:=Bindings+Selector.Bindings[I];
      if Method='DELETE' then
      begin
        Mutation:='DELETE FROM board_domains WHERE '+Guard+'; ';
        AfterWrite:='NOT EXISTS(SELECT 1 FROM board_domains WHERE '+Guard+')';
      end
      else
      begin
        Mutation:='INSERT INTO board_domains(boardId,domain,isActive) SELECT '+Board+','+QuotedStr(Domain)+
          ',1 WHERE NOT EXISTS(SELECT 1 FROM board_domains WHERE '+Guard+'); ';
        AfterWrite:='(SELECT count(*) FROM board_domains WHERE '+KeyScope+' AND domain='+QuotedStr(Domain)+')=1';
      end;
      if not T.Db.Exec('BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+Permission+
        ' AND (SELECT count(*) FROM board_domains WHERE '+Guard+')='+IntToStr(Length(Rows))+
        ' AND (SELECT count(*) FROM board_domains WHERE '+KeyScope+' AND domain='+QuotedStr(Domain)+')='+IntToStr(Length(Rows))+
        ' THEN 1 ELSE json(''Domain scope changed'') END; '+Mutation+Bindings+
        'SELECT CASE WHEN '+Permission+' AND '+AfterWrite+' THEN 1 ELSE json(''Domain write changed scope'') END; COMMIT;') then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,409,'Could not save domains');Exit;end;
    end;
    Reply:=BoardDomains(T.Db,KeyScope);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  finally Selector.Free;end;
end;

procedure ApiDependencies(aRequest:TRequest;aResponse:TResponse);
const Fields:array[0..2] of string=('type','color','icon');
  Defaults:array[0..2] of string=('related-to','#eb144c','link');
  Types='|related-to|blocks|is-blocked-by|fixes|is-fixed-by|duplicates|is-duplicated-by|';
var T:TWLTenant;UserId,Actor,Board,Source,Target,Method,Member,Allowed,SourceScope,TargetScope,
  Dependency,Scope,Columns,Values,Patch,Mutation,Guard,AfterWrite,Bindings,CardFilter,RoleBinding,RoleDecision:string;
  Rows:TWLRows;Row:TWLRow;Input,Item,Reply:TJSONObject;Items:TJSONArray;
  Selector:TSelectionScope;Field:TJSONData;I:Integer;Props:array[0..2] of string;
  function TypeValid(const Value:string):Boolean;
  begin Result:=(Value<>'') and (Pos('|',Value)=0) and (Pos('|'+Value+'|',Types)>0);end;
  function CardScope(const Card:string):string;
  begin
    Result:='id='+QuotedStr(Card)+' AND boardId='+Board+' AND '+
      Selector.StringField('cards','id')+' AND '+Selector.StringField('cards','boardId');
  end;
  procedure ResolveRoleSource;
  var Registry:TWLRows;BoardTable,RoleTable,Lookup,MemberJson:string;
    function Physical(const Name:string):string;
    begin Result:='"'+StringReplace(Name,'"','""',[rfReplaceAll])+'"';end;
  begin
    RoleBinding:='1';RoleDecision:='NULL';
    if not SharedStore(T.Db) then Exit;
    Registry:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''customBoardRoles'';');
    if Length(Registry)=0 then
    begin
      RoleBinding:='NOT EXISTS(SELECT 1 FROM _ferretdb_collections WHERE name=''customBoardRoles'')';
      Exit;
    end;
    if Length(Registry)<>1 then raise Exception.Create('Ambiguous custom role collection');
    RoleTable:=Physical(Registry[0][0]);
    RoleBinding:='(SELECT count(*) FROM _ferretdb_collections WHERE name=''customBoardRoles'' AND table_name='+
      QuotedStr(Registry[0][0])+')=1';
    Registry:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''boards'';');
    if Length(Registry)<>1 then raise Exception.Create('Missing board collection');
    BoardTable:=Physical(Registry[0][0]);
    MemberJson:='CASE WHEN m.type=''object'' THEN m.value ELSE ''{}'' END';
    Lookup:=' FROM '+BoardTable+' b JOIN json_each(b._ferretdb_sjson,''$.members'') m '+
      'JOIN '+RoleTable+' r ON json_extract(r._ferretdb_sjson,''$._id'')=json_extract('+MemberJson+',''$.customRoleId'') '+
      'WHERE json_extract(b._ferretdb_sjson,''$._id'')='+Board+' AND m.type=''object'' '+
      'AND json_extract('+MemberJson+',''$.userId'')='+Actor+' AND json_type('+MemberJson+',''$.isActive'')=''true'' '+
      'AND json_extract(b._ferretdb_sjson,''$."$s".p.members.i[''||m.key||'']."$s".p.customRoleId.t'')=''string'' '+
      'AND json_extract(r._ferretdb_sjson,''$."$s".p._id.t'')=''string''';
    RoleDecision:='(SELECT CASE count(*) WHEN 0 THEN NULL WHEN 1 THEN MAX(CASE WHEN '+
      'json_type(r._ferretdb_sjson,''$.capabilities.write'')=''true'' OR '+
      'json_type(r._ferretdb_sjson,''$.capabilities.moveCard'')=''true'' THEN 1 ELSE 0 END) ELSE 0 END'+Lookup+')';
  end;
  function CanEdit(const Card:string):string;
  var Assignee:string;
  begin
    Assignee:='';
    if Card<>'' then
      Assignee:=' AND ((COALESCE(board_members.isNormalAssignedOnly,0)=0 AND COALESCE(board_members.isReadAssignedOnly,0)=0 '+
        'AND COALESCE(board_members.isCommentAssignedOnly,0)=0) OR EXISTS(SELECT 1 FROM card_assignees '+
        'WHERE cardId='+QuotedStr(Card)+' AND userId='+Actor+' AND '+Selector.StringField('card_assignees','userId')+'))';
    Result:=RoleBinding+' AND EXISTS(SELECT 1 FROM boards WHERE id='+Board+' AND archived=0 AND '+Selector.StringField('boards','id')+')'+
      ' AND EXISTS(SELECT 1 FROM users WHERE id='+Actor+' AND COALESCE(loginDisabled,0)=0 AND '+
      Selector.StringField('users','id')+' AND (isAdmin=1 OR EXISTS(SELECT 1 FROM board_members WHERE '+Member+
      ' AND ((board_members.isAdmin=1 OR COALESCE('+RoleDecision+',COALESCE(board_members.isReadOnly,0)=0 '+
      'AND COALESCE(board_members.isCommentOnly,0)=0 AND COALESCE(board_members.isReadAssignedOnly,0)=0 '+
      'AND COALESCE(board_members.isCommentAssignedOnly,0)=0))'+Assignee+'))))';
  end;
  procedure AddNumber(Entry:TJSONObject;const Key,Value:string);
  var Number:Int64;
  begin if TryStrToInt64(Value,Number) then Entry.Add(Key,Number) else Entry.Add(Key,TJSONNull.Create);end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  Actor:=QuotedStr(UserId);Board:=QuotedStr(aRequest.RouteParams['boardId']);
  Source:=aRequest.RouteParams['cardId'];Target:=aRequest.RouteParams['targetId'];Method:=aRequest.Method;
  Member:='boardId='+Board+' AND userId='+Actor+' AND isActive=1';
  Selector:=TSelectionScope.Create(T.Db);
  Input:=nil;
  try
    SourceScope:=CardScope(Source);
    if Method='GET' then
    begin
      if not ApiAuthBoard(T,aResponse,UserId,aRequest.RouteParams['boardId'],False) then Exit;
      CardFilter:='cards.boardId='+Board+' AND cards.archived=0';
      if Source<>'' then
      begin
        if Length(T.Db.Query('SELECT id FROM cards WHERE '+SourceScope+';'))<>1 then
        begin SendJson(aResponse,'{"error":"Card not found"}',404);Exit;end;
        CardFilter:='cards.boardId='+Board+' AND cards.id='+QuotedStr(Source);
      end;
      Rows:=T.Db.Query('SELECT cards.id,cards.title,cards.cardNumber,d.targetCardId,d.type,d.color,d.icon,'+
        'target.id,target.title,target.cardNumber FROM card_dependencies d JOIN cards ON cards.id=d.cardId '+
        'LEFT JOIN cards target ON target.id=d.targetCardId AND target.boardId=cards.boardId WHERE '+CardFilter+
        ' AND d.targetCardId IS NOT NULL AND d.targetCardId<>'''';');
      Items:=TJSONArray.Create;
      try
        for Row in Rows do
        begin
          Item:=TJSONObject.Create;Items.Add(Item);
          if Source<>'' then Item.Add('cardId',Row[3])
          else
          begin
            Item.Add('from',Row[0]);Item.Add('fromTitle',Row[1]);AddNumber(Item,'fromCardNumber',Row[2]);
            Item.Add('to',Row[3]);
            if Row[7]='' then Item.Add('toTitle',TJSONNull.Create) else Item.Add('toTitle',Row[8]);
            AddNumber(Item,'toCardNumber',Row[9]);
          end;
          for I:=0 to 2 do
            if (Row[I+4]='') or ((I=0) and not TypeValid(Row[I+4])) then Item.Add(Fields[I],Defaults[I])
            else Item.Add(Fields[I],Row[I+4]);
        end;
        SendJson(aResponse,Items.AsJSON);
      finally Items.Free;end;
      Exit;
    end;
    ResolveRoleSource;
    Member:=Member+' AND '+Selector.StringField('board_members','userId');
    Allowed:=CanEdit('');
    if Length(T.Db.Query('SELECT 1 WHERE '+Allowed+';'))<>1 then
    begin SendError(aResponse,403,'Board access forbidden');Exit;end;
    if Length(T.Db.Query('SELECT id FROM cards WHERE '+SourceScope+';'))<>1 then
    begin SendJson(aResponse,'{"error":"Card not found"}',404);Exit;end;
    Guard:=CanEdit(Source)+' AND EXISTS(SELECT 1 FROM cards WHERE '+SourceScope+' AND archived=0)';
    if Method<>'DELETE' then
    begin
      try
        Input:=ExactObject(aRequest.Content);
        Patch:='';
        for I:=0 to 2 do
        begin
          Field:=Input.Find(Fields[I]);
          if Field=nil then Continue;
          if not (Field is TJSONString) then raise EConvertError.Create('Invalid dependency field');
          Props[I]:=Field.AsString;
          if (Pos(#0,Props[I])>0) or ((I=0) and (Props[I]<>'') and not TypeValid(Props[I])) then
            raise EConvertError.Create('Invalid dependency field');
          if Patch<>'' then Patch:=Patch+',';
          Patch:=Patch+Fields[I]+'='+QuotedStr(Props[I]);
        end;
        if Method='POST' then
        begin
          Target:=Input.Get('cardId','');if Target='' then Target:=Input.Get('dependsOn','');
          if (Target='') or (Target=Source) or (Pos(#0,Target)>0) then
            raise EConvertError.Create('Invalid target card');
        end
        else if Patch='' then raise EConvertError.Create('Provide at least one of type, color, icon');
      except SendError(aResponse,400,'Invalid dependency request');Exit;end;
    end;
    if Method='POST' then
    begin
      TargetScope:=CardScope(Target);
      if Length(T.Db.Query('SELECT 1 FROM cards WHERE '+TargetScope+';'))<>1 then
      begin SendError(aResponse,400,'Target card is not on this board');Exit;end;
      Guard:=Guard+' AND '+CanEdit(Target)+' AND EXISTS(SELECT 1 FROM cards WHERE '+TargetScope+' AND archived=0)';
    end;
    if Length(T.Db.Query('SELECT 1 WHERE '+Guard+';'))<>1 then
    begin SendError(aResponse,403,'Card access forbidden');Exit;end;
    Scope:='cardId='+QuotedStr(Source)+' AND targetCardId='+QuotedStr(Target);
    Dependency:=Scope+' AND '+Selector.StringField('card_dependencies','targetCardId');
    Rows:=T.Db.Query('SELECT type,color,icon FROM card_dependencies WHERE '+Scope+';');
    if (Length(Rows)>1) or ((Length(Rows)=1) and
      (Length(T.Db.Query('SELECT 1 FROM card_dependencies WHERE '+Dependency+';'))<>1)) then
    begin SendError(aResponse,409,'Ambiguous dependency');Exit;end;
    if (Length(Rows)=0) and (Method<>'POST') then
    begin SendJson(aResponse,'{"error":"Dependency not found"}',404);Exit;end;
    if Method='POST' then
    begin
      Columns:='cardId,targetCardId';Values:=QuotedStr(Source)+','+QuotedStr(Target);Patch:='';
      for I:=0 to 2 do
      begin
        if (Props[I]='') and (Length(Rows)=1) then Props[I]:=Rows[0][I];
        if (Props[I]='') or ((I=0) and not TypeValid(Props[I])) then Props[I]:=Defaults[I];
        Columns:=Columns+','+Fields[I];Values:=Values+','+QuotedStr(Props[I]);
        if Patch<>'' then Patch:=Patch+',';
        Patch:=Patch+Fields[I]+'='+QuotedStr(Props[I]);
      end;
    end;
    AfterWrite:=Guard+' AND (SELECT count(*) FROM card_dependencies WHERE '+Scope+')=';
    if Method='DELETE' then AfterWrite:=AfterWrite+'0'
    else AfterWrite:=AfterWrite+'1 AND EXISTS(SELECT 1 FROM card_dependencies WHERE '+Dependency+')';
    Guard:=Guard+' AND (SELECT count(*) FROM card_dependencies WHERE '+Scope+')='+IntToStr(Length(Rows));
    if Length(Rows)=1 then
    begin
      for I:=0 to 2 do
        Dependency:=Dependency+' AND COALESCE('+Fields[I]+','''')='+QuotedStr(Rows[0][I]);
      Guard:=Guard+' AND EXISTS(SELECT 1 FROM card_dependencies WHERE '+Dependency+')';
    end;
    if Method='DELETE' then Mutation:='DELETE FROM card_dependencies WHERE '+Scope+'; '
    else if Length(Rows)=0 then Mutation:='INSERT INTO card_dependencies('+Columns+') VALUES('+Values+'); '
    else Mutation:='UPDATE card_dependencies SET '+Patch+' WHERE '+Scope+'; ';
    Bindings:='';for I:=0 to Selector.Bindings.Count-1 do Bindings:=Bindings+Selector.Bindings[I];
    if not T.Db.Exec('BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+Guard+
      ' THEN 1 ELSE json(''Dependency scope changed'') END; '+Mutation+Bindings+
      'SELECT CASE WHEN '+AfterWrite+' THEN 1 ELSE json(''Dependency write changed scope'') END; COMMIT;') then
    begin T.Db.Exec('ROLLBACK;');SendError(aResponse,409,'Could not save dependency');Exit;end;
    Reply:=TJSONObject.Create(['_id',Source]);
    try
      if Method='POST' then
      begin
        Reply.Add('cardId',Target);
        for I:=0 to 2 do Reply.Add(Fields[I],Props[I]);
      end;
      SendJson(aResponse,Reply.AsJSON);
    finally Reply.Free;end;
  finally Input.Free;Selector.Free;end;
end;

procedure ApiUser(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  R := T.Db.Query(Format('SELECT id,username FROM users WHERE id=%s LIMIT 1;', [QuotedStr(UserId)]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'User not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('username', R[0][1]);
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

function ProjectGroup(const Kind:string;SourceDoc:TJSONObject;NormalizeFlags:Boolean):TJSONObject;
var Suffix,Name:string;PropertyValue:TJSONData;
begin
  Result:=TJSONObject.Create(['_id',SourceDoc.Get('_id','')]);
  for Suffix in ['DisplayName','ShortName'] do
  begin
    Name:=Kind+Suffix;PropertyValue:=SourceDoc.Find(Name);
    if PropertyValue is TJSONString then Result.Add(Name,PropertyValue.Clone);
  end;
  for Suffix in ['SharedTemplates','PropagateMembersToBoards','SyncMembersFromAuth'] do
  begin
    Name:=Kind+Suffix;PropertyValue:=SourceDoc.Find(Name);
    if NormalizeFlags then Result.Add(Name,(PropertyValue is TJSONBoolean) and PropertyValue.AsBoolean)
    else if PropertyValue is TJSONBoolean then Result.Add(Name,PropertyValue.Clone);
  end;
end;

function GroupStorage(Db:TWLDb;const Kind:string):string;
var Rows:TWLRows;
begin
  Result:='';
  if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))=0 then Exit;
  Rows:=Db.Query('SELECT r.table_name FROM _ferretdb_collections r JOIN sqlite_master m '+
    'ON m.name=r.table_name AND m.type=''table'' WHERE r.name='+QuotedStr(Kind)+';');
  if Length(Rows)=1 then Result:=Rows[0][0];
end;

function ReadGroupFeatures(Db:TWLDb;const Kind:string):TJSONArray;
var Source,TableName:string;Rows:TWLRows;Row:TWLRow;Doc:TJSONObject;
begin
  Result:=TJSONArray.Create;
  try
    Source:=GroupStorage(Db,Kind);
    if Source='' then Exit;
    TableName:='"'+StringReplace(Source,'"','""',[rfReplaceAll])+'"';
    Rows:=Db.Query('SELECT json(_ferretdb_sjson) FROM '+TableName+
      ' WHERE json_extract(_ferretdb_sjson,''$.$s.p._id.t'')=''string'''+
      ' ORDER BY json_extract(_ferretdb_sjson,''$._id'');');
    for Row in Rows do
    begin
      Doc:=ExactObject(PlainDocument(Row[0]));
      try Result.Add(ProjectGroup(Kind,Doc,True));finally Doc.Free;end;
    end;
  except FreeAndNil(Result);raise;end;
end;

procedure GroupFeatures(aRequest:TRequest;aResponse:TResponse;const Kind,LabelText:string);
var T:TWLTenant;Actor,Id,Source,TableName,Scope,Raw,Encoded,Sql,Key,Flag,Guard,Count,Expression:string;
  Rows:TWLRows;Body,Doc,Reply:TJSONObject;Value:TJSONData;Edited,Listing,Bulk:Boolean;Entries:TJSONArray;
  procedure Missing;
  begin
    if Listing then SendJson(aResponse,'[]')
    else if Bulk then SendJson(aResponse,'{"updated":0}')
    else SendJson(aResponse,'{"error":"'+LabelText+' not found"}',404);
  end;

begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  if not IsSiteAdmin(T.Db,Actor) then
  begin SendError(aResponse,403,'Site administration required');Exit;end;
  Id:=aRequest.RouteParams[Kind+'Id'];Listing:=aRequest.Method='GET';
  Bulk:=(Id='') and not Listing;
  if Listing then
  begin
    try
      Entries:=ReadGroupFeatures(T.Db,Kind);
      try SendJson(aResponse,Entries.AsJSON);finally Entries.Free;end;
    except SendError(aResponse,500,'Could not read group features');end;
    Exit;
  end;
  if Bulk then
  begin
    Body:=nil;
    try
      try
        if aRequest.Content='' then Body:=TJSONObject.Create else Body:=ExactObject(aRequest.Content);
        Key:=Body.Get('field','');
        if (Key<>Kind+'SharedTemplates') and (Key<>Kind+'PropagateMembersToBoards') and
          (Key<>Kind+'SyncMembersFromAuth') then
        begin SendJson(aResponse,'{"error":"invalid-field"}');Exit;end;
        Value:=Body.Find('value');
        if not (Value is TJSONBoolean) then
        begin SendJson(aResponse,'{"error":"Invalid feature value"}',400);Exit;end;
        Flag:=Value.AsJSON;
      except SendJson(aResponse,'{"error":"Invalid feature update"}',400);Exit;end;
    finally Body.Free;end;
  end;
  Source:=GroupStorage(T.Db,Kind);
  if Source='' then begin Missing;Exit;end;
  TableName:='"'+StringReplace(Source,'"','""',[rfReplaceAll])+'"';
  Scope:='json_type(_ferretdb_sjson,''$._id'')=''text'''+
    ' AND json_extract(_ferretdb_sjson,''$.$s.p._id.t'')=''string''';
  Guard:='EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(Actor)+' AND isAdmin=1 AND loginDisabled=0)'+
    ' AND (SELECT count(*) FROM _ferretdb_collections WHERE name='+QuotedStr(Kind)+
    ' AND table_name='+QuotedStr(Source)+')=1';
  if Bulk then
  begin
    Rows:=T.Db.Query('SELECT count(*) FROM '+TableName+' WHERE '+Scope+';');
    if Length(Rows)<>1 then begin SendError(aResponse,500,'Could not count groups');Exit;end;
    Count:=IntToStr(StrToInt64(Rows[0][0]));
    Expression:='wl_sjson(json_set(wl_plain(json(_ferretdb_sjson)),'+
      QuotedStr('$.'+Key)+',json('+QuotedStr(Flag)+')),json(_ferretdb_sjson),''{}'')';
    Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+AuthSourceCondition(T.Db)+' AND '+Guard+
      ' AND (SELECT count(*) FROM '+TableName+' WHERE '+Scope+')='+Count+
      ' THEN 1 ELSE json(''Feature scope changed'') END; UPDATE '+TableName+
      ' SET _ferretdb_sjson=CASE WHEN wl_storage('+QuotedStr(Source)+')=''blob'' THEN jsonb('+Expression+
      ') ELSE '+Expression+' END WHERE '+Scope+
      '; SELECT CASE WHEN (SELECT count(*) FROM '+TableName+' WHERE '+Scope+
      ' AND json_type(_ferretdb_sjson,'+QuotedStr('$.'+Key)+')='+QuotedStr(Flag)+')='+Count+
      ' THEN 1 ELSE json(''Feature update failed'') END; COMMIT;';
    if not T.Db.Exec(Sql) then
    begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not update group features');Exit;end;
    SendJson(aResponse,'{"updated":'+Count+'}');Exit;
  end;
  Scope:=Scope+' AND json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(Id);
  Rows:=T.Db.Query('SELECT json(_ferretdb_sjson) FROM '+TableName+' WHERE '+Scope+';');
  if Length(Rows)<>1 then begin Missing;Exit;end;
  Raw:=Rows[0][0];Body:=nil;Doc:=nil;Reply:=nil;
  try
    try
      if aRequest.Content='' then Body:=TJSONObject.Create else Body:=ExactObject(aRequest.Content);
      for Flag in ['SharedTemplates','PropagateMembersToBoards','SyncMembersFromAuth'] do
      begin
        Value:=Body.Find(Kind+Flag);
        if (Value<>nil) and not (Value is TJSONBoolean) then
        begin SendJson(aResponse,'{"error":"Invalid feature value"}',400);Exit;end;
      end;
    except SendJson(aResponse,'{"error":"Invalid feature update"}',400);Exit;end;
    try
      Doc:=ExactObject(PlainDocument(Raw));Edited:=False;
      for Flag in ['SharedTemplates','PropagateMembersToBoards','SyncMembersFromAuth'] do
      begin
        Key:=Kind+Flag;Value:=Body.Find(Key);
        if Value=nil then Continue;
        Doc.Delete(Key);Doc.Add(Key,Value.Clone);Edited:=True;
      end;
      if Edited then
      begin
        Encoded:=QuotedStr(TypedDocument(Doc.AsJSON,Raw,'{}'));
        Guard:=Guard+' AND (SELECT count(*) FROM '+TableName+
          ' WHERE '+Scope+' AND json(_ferretdb_sjson)='+QuotedStr(Raw)+')=1';
        Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+AuthSourceCondition(T.Db)+' AND '+Guard+
          ' THEN 1 ELSE json(''Feature scope changed'') END; UPDATE '+TableName+
          ' SET _ferretdb_sjson=CASE WHEN wl_storage('+QuotedStr(Source)+')=''blob'' THEN jsonb('+Encoded+
          ') ELSE '+Encoded+' END WHERE '+Scope+'; SELECT CASE WHEN EXISTS(SELECT 1 FROM '+TableName+
          ' WHERE '+Scope+' AND json(_ferretdb_sjson)=json('+Encoded+')) THEN 1 ELSE json(''Feature update failed'') END; COMMIT;';
        if not T.Db.Exec(Sql) then raise Exception.Create('Feature update failed');
      end;
      Reply:=ProjectGroup(Kind,Doc,False);
      SendJson(aResponse,Reply.AsJSON);
    except T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not update group features');end;
  finally Reply.Free;Doc.Free;Body.Free;end;
end;

procedure ApiOrgFeatures(aRequest:TRequest;aResponse:TResponse);
begin GroupFeatures(aRequest,aResponse,'org','Organization');end;

procedure ApiTeamFeatures(aRequest:TRequest;aResponse:TResponse);
begin GroupFeatures(aRequest,aResponse,'team','Team');end;

procedure TransferAdministeredBoards(Db:TWLDb; Response:TResponse;
  const Actor,Target,Authorization:string);
var Source:TSelectionScope; MemberKey,BoardKey,Selection,Sql,Scope,ActorScope:string;
  Rows:TWLRows; I:Integer;
begin
  Source:=TSelectionScope.Create(Db);
  try
    MemberKey:=Source.StringField('board_members','userId');
    BoardKey:=Source.StringField('boards','id');
    Selection:=' FROM boards WHERE '+BoardKey+' AND EXISTS(SELECT 1 FROM board_members'+
      ' WHERE boardId=boards.id AND userId='+QuotedStr(Target)+' AND isAdmin=1 AND '+MemberKey+')';
    Rows:=Db.Query('SELECT id,title'+Selection+' ORDER BY sort,id;');
    Sql:='BEGIN IMMEDIATE; ';
    for I:=0 to Source.Bindings.Count-1 do Sql:=Sql+Source.Bindings[I];
    Sql:=Sql+'SELECT CASE WHEN '+Authorization+' AND (SELECT count(*)'+Selection+')='+
      IntToStr(Length(Rows))+' THEN 1 ELSE json(''Ownership scope changed'') END; ';
    for I:=0 to High(Rows) do
    begin
      Scope:='boardId='+QuotedStr(Rows[I][0]);
      ActorScope:=Scope+' AND userId='+QuotedStr(Actor);
      Scope:=Scope+' AND userId='+QuotedStr(Target);
      Sql:=Sql+'SELECT CASE WHEN EXISTS(SELECT 1 FROM boards WHERE id='+QuotedStr(Rows[I][0])+
        ' AND '+BoardKey+') AND (SELECT count(*) FROM board_members WHERE '+Scope+')=1'+
        ' AND EXISTS(SELECT 1 FROM board_members WHERE '+Scope+' AND isAdmin=1 AND '+MemberKey+')'+
        ' AND (SELECT count(*) FROM board_members WHERE '+ActorScope+')<=1'+
        ' AND NOT EXISTS(SELECT 1 FROM board_members WHERE '+ActorScope+' AND NOT '+MemberKey+
        ') THEN 1 ELSE json(''Ownership membership changed'') END; ';
      if Actor<>Target then
        Sql:=Sql+'DELETE FROM board_members WHERE '+ActorScope+'; '+
          'UPDATE board_members SET userId='+QuotedStr(Actor)+' WHERE '+Scope+'; '+
          'SELECT CASE WHEN '+Authorization+' AND NOT EXISTS(SELECT 1 FROM board_members WHERE '+Scope+
          ') AND (SELECT count(*) FROM board_members WHERE '+ActorScope+')=1'+
          ' AND EXISTS(SELECT 1 FROM board_members WHERE '+ActorScope+' AND isAdmin=1 AND '+MemberKey+
          ') THEN 1 ELSE json(''Ownership transfer failed'') END; ';
    end;
    if not Db.Exec(Sql+'COMMIT;') then raise Exception.Create('Ownership transfer failed');
    SendJson(Response,RowsAsIdTitle(Rows));
  finally Source.Free;end;
end;

procedure ApiChangeUser(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"User not found"}';
var T:TWLTenant;Actor,Target,Scope,Admin,Bindings,Sql,Mutation,Action,Flag:string;Source:TSelectionScope;I:Integer;
  Rows:TWLRows;Reply:TJSONObject;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  if not IsSiteAdmin(T.Db,Actor) then
  begin SendError(aResponse,403,'Site administration required');Exit;end;
  Target:=aRequest.RouteParams['userId'];
  try
    Source:=TSelectionScope.Create(T.Db);
    try
      Scope:='id='+QuotedStr(Target)+' AND '+Source.StringField('users','id');
      Admin:='EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(Actor)+
        ' AND isAdmin=1 AND COALESCE(loginDisabled,0)=0 AND '+Source.StringField('users','id')+')';
      Bindings:='';
      for I:=0 to Source.Bindings.Count-1 do Bindings:=Bindings+Source.Bindings[I];
    finally Source.Free;end;
    if Length(T.Db.Query('SELECT id FROM users WHERE '+Scope+';'))<>1 then
    begin SendJson(aResponse,NotFound,404);Exit;end;
    Mutation:='';
    if aRequest.Method='DELETE' then
      Mutation:=RevokeUserTokensSQL(T.Db,Target)+'DELETE FROM users WHERE '+Scope+'; '+
        'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(Target)+
        ') THEN 1 ELSE json(''User deletion failed'') END; '
    else
    begin
      Action:=BodyField(aRequest,'action');Flag:='';
      if (Action='disableLogin') and (Target<>Actor) then
      begin Flag:='1';Mutation:=RevokeUserTokensSQL(T.Db,Target);end
      else if Action='enableLogin' then Flag:='0'
      else if Action='takeOwnership' then
      begin
        TransferAdministeredBoards(T.Db,aResponse,Actor,Target,
          AuthSourceCondition(T.Db)+' AND '+Admin+
          ' AND (SELECT count(*) FROM users WHERE '+Scope+')=1');
        Exit;
      end;
      if Flag<>'' then Mutation:=Mutation+'UPDATE users SET loginDisabled='+Flag+' WHERE '+Scope+'; '+
        'SELECT CASE WHEN EXISTS(SELECT 1 FROM users WHERE '+Scope+' AND loginDisabled='+Flag+
        ') THEN 1 ELSE json(''User update failed'') END; ';
    end;
    Sql:='BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+AuthSourceCondition(T.Db)+' AND '+Admin+
      ' AND (SELECT count(*) FROM users WHERE '+Scope+')=1 THEN 1 ELSE json(''User scope changed'') END; '+
      Mutation+'COMMIT;';
    if not T.Db.Exec(Sql) then raise Exception.Create('User change failed');
  except T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not change user');Exit;end;
  if aRequest.Method='DELETE' then
    SendJson(aResponse,'{"_id":"'+StringToJSONString(Target)+'"}')
  else
  begin
    Rows:=T.Db.Query('SELECT username,loginDisabled FROM users WHERE '+Scope+';');
    if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
    Reply:=TJSONObject.Create(['_id',Target,'username',Rows[0][0],'loginDisabled',Rows[0][1]='1']);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  end;
end;

procedure ApiUsers(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; R: TWLRows; A: TJSONArray; O: TJSONObject; i: Integer;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not IsSiteAdmin(T.Db, UserId) then begin SendError(aResponse, 403, 'Admin only'); Exit; end;
  R := T.Db.Query('SELECT id,username FROM users ORDER BY username;');
  A := TJSONArray.Create;
  try
    for i := 0 to High(R) do
      if Length(R[i]) >= 2 then
      begin
        O := TJSONObject.Create;
        O.Add('_id', R[i][0]); O.Add('username', R[i][1]);
        A.Add(O);
      end;
    SendJson(aResponse, A.AsJSON);
  finally A.Free; end;
end;

procedure ApiPublicBoards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(
    'SELECT id,title FROM boards WHERE permission=''public'' AND archived=0 ORDER BY title;')));
end;

procedure ApiUserBoards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if (UserId <> aRequest.RouteParams['userId']) and not IsSiteAdmin(T.Db, UserId) then begin SendError(aResponse, 403, 'Forbidden'); Exit; end;
  // boards the path's user is a member of
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT b.id,b.title FROM boards b JOIN board_members m ON m.boardId=b.id ' +
    'WHERE m.userId=%s AND b.archived=0 ORDER BY b.title;',
    [QuotedStr(aRequest.RouteParams['userId'])]))));
end;

procedure ApiBoard(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId,Scope: string; R: TWLRows; O: TJSONObject; Selector:TSelectionScope;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  R := T.Db.Query(Format('SELECT id,title,slug,permission,color FROM boards WHERE id=%s LIMIT 1;',
    [QuotedStr(aRequest.RouteParams['boardId'])]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'Board not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('title', R[0][1]); O.Add('slug', R[0][2]);
    O.Add('permission', R[0][3]); O.Add('color', R[0][4]);
    Selector:=TSelectionScope.Create(T.Db);
    try Scope:=Selector.StringField('board_domains','domain');finally Selector.Free;end;
    O.Add('domains',BoardDomains(T.Db,'boardId='+QuotedStr(R[0][0])+' AND '+Scope));
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

function ChangeBoardMembership(const T:TWLTenant;const Actor,BoardId,TargetId:string;Add:Boolean;
  const Columns,Values,Sets:string;out Error:string):Integer;
var Board,Target,Scope,UserScope,Permission,Bindings,Sql,AdminCheck,MemberKey:string;Policy:TFieldPolicy;
  Source:TSelectionScope;Rows:TWLRows;I:Integer;
begin
  Error:='';Board:=QuotedStr(BoardId);
  if (BoardId='') or (Pos(#0,BoardId+TargetId)>0) or (Length(T.Db.Query('SELECT id FROM boards WHERE id='+Board+';'))<>1) then
  begin Error:='Board not found';Exit(404);end;
  Policy:=TFieldPolicy.Create(T.Db,Actor,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then begin Error:='Board administration required';Exit(403);end;
  Target:=QuotedStr(TargetId);
  Source:=TSelectionScope.Create(T.Db);
  try
    UserScope:='id='+Target+' AND '+Source.StringField('users','id');
    MemberKey:=Source.StringField('board_members','userId');
    Scope:='boardId='+Board+' AND userId='+Target;
    Bindings:='';
    for I:=0 to Source.Bindings.Count-1 do Bindings:=Bindings+Source.Bindings[I];
  finally Source.Free;end;
  Rows:=T.Db.Query('SELECT COALESCE(loginDisabled,0) FROM users WHERE '+UserScope+';');
  if Length(Rows)<>1 then begin Error:='User not found';Exit(404);end;
  Sql:='BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+Permission+' AND '+
    '(SELECT count(*) FROM users WHERE '+UserScope;
  if Add then
  begin
    if Rows[0][0]<>'0' then begin Error:='User is disabled';Exit(400);end;
    Sql:=Sql+' AND COALESCE(loginDisabled,0)=0)=1 AND NOT EXISTS(SELECT 1 FROM board_members WHERE '+Scope+
      ' AND NOT '+MemberKey+') THEN 1 ELSE json(''Board membership scope changed'') END; '+
      'UPDATE board_members SET isActive=1'+Sets+' WHERE '+Scope+' AND COALESCE(isActive,0)=0; '+
      'INSERT INTO board_members(boardId,userId,isActive'+Columns+') SELECT '+Board+','+Target+',1'+Values+
      ' WHERE NOT EXISTS(SELECT 1 FROM board_members WHERE '+Scope+'); '+
      'SELECT CASE WHEN (SELECT count(*) FROM board_members WHERE '+Scope+
      ' AND isActive=1 AND '+MemberKey+')=1 THEN 1 ELSE json(''Board member add failed'') END; COMMIT;';
  end else
  begin
    Rows:=T.Db.Query('SELECT isAdmin FROM board_members WHERE '+Scope+' AND isActive=1 AND '+MemberKey+';');
    if Length(Rows)<>1 then begin Error:='Member not found';Exit(404);end;
    AdminCheck:='(isAdmin=0 OR (SELECT count(*) FROM board_members WHERE boardId='+Board+
      ' AND isActive=1 AND isAdmin=1 AND '+MemberKey+')>1)';
    if Length(T.Db.Query('SELECT 1 FROM board_members WHERE '+Scope+' AND '+AdminCheck+';'))<>1 then
    begin Error:='The last board admin cannot be removed';Exit(409);end;
    Sql:=Sql+')=1 AND (SELECT count(*) FROM board_members WHERE '+Scope+' AND isActive=1 AND '+MemberKey+' AND '+
      AdminCheck+')=1 THEN 1 ELSE json(''Board membership scope changed'') END; '+
      'UPDATE board_members SET isActive=0,isAdmin=0 WHERE '+Scope+'; SELECT CASE WHEN '+
      '(SELECT count(*) FROM board_members WHERE '+Scope+' AND isActive=0 AND isAdmin=0)=1 '+
      'THEN 1 ELSE json(''Board member removal failed'') END; COMMIT;';
  end;
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not change board membership';Exit(500);end;
  Result:=200;
end;


procedure ApiBoardMembership(aRequest:TRequest;aResponse:TResponse;Add:Boolean);
const Flags:array[0..7] of string=('isAdmin','isNoComments','isCommentOnly','isWorker',
  'isNormalAssignedOnly','isCommentAssignedOnly','isReadOnly','isReadAssignedOnly');
  Roles:array[0..7] of string=('admin','nocomments','commentonly','worker',
  'normalassignedonly','commentassignedonly','readonly','readassignedonly');
var T:TWLTenant;Actor,BoardId,Board,Permission,Action,Role,Columns,Values,Sets:string;Policy:TFieldPolicy;
  Body:TJSONObject;Value:TJSONData;Rows:TWLRows;I,RoleIndex,Code:Integer;Enabled:Boolean;Error:string;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];Board:=QuotedStr(BoardId);
  Rows:=T.Db.Query('SELECT id FROM boards WHERE id='+Board+';');
  if Length(Rows)<>1 then begin SendJson(aResponse,'{"error":"Board not found"}',404);Exit;end;
  Policy:=TFieldPolicy.Create(T.Db,Actor,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board administration required');Exit;end;
  if Add then Action:='add' else Action:='remove';
  if BodyField(aRequest,'action')<>Action then
  begin SendError(aResponse,400,'Invalid membership action');Exit;end;
  Body:=nil;Columns:='';Values:='';Sets:='';
  try
    try
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then Body:=ExactObject(aRequest.Content)
      else
      begin
        Body:=TJSONObject.Create;
        for I:=0 to aRequest.ContentFields.Count-1 do
          Body.Add(aRequest.ContentFields.Names[I],aRequest.ContentFields.ValueFromIndex[I]);
      end;
      if Add then
      begin
        RoleIndex:=-2;Value:=Body.Find('role');
        if Value<>nil then
        begin
          if not (Value is TJSONString) then raise Exception.Create('Invalid role');
          Role:=LowerCase(Trim(Value.AsString));if Role='comment' then Role:='commentonly';
          RoleIndex:=-1;
          for I:=0 to High(Roles) do if Role=Roles[I] then RoleIndex:=I;
          if (RoleIndex<0) and (Role<>'normal') and (Role<>'member') then raise Exception.Create('Invalid role');
        end;
        for I:=0 to High(Flags) do
        begin
          Enabled:=RoleIndex=I;
          if RoleIndex=-2 then
          begin
            Value:=Body.Find(Flags[I]);
            Enabled:=(Value<>nil) and (Value.JSONType in [jtString,jtBoolean]) and SameText(Value.AsString,'true');
          end;
          Columns:=Columns+','+Flags[I];Values:=Values+','+IntToStr(Ord(Enabled));
          Sets:=Sets+','+Flags[I]+'='+IntToStr(Ord(Enabled));
        end;
      end;
    except SendError(aResponse,400,'Invalid membership role');Exit;end;
  finally Body.Free;end;
  Code:=ChangeBoardMembership(T,Actor,BoardId,aRequest.RouteParams['userId'],Add,Columns,Values,Sets,Error);
  if Code=404 then begin SendJson(aResponse,'{"error":"'+StringToJSONString(Error)+'"}',404);Exit;end;
  if Code<>200 then begin SendError(aResponse,Code,Error);Exit;end;
  Rows:=T.Db.Query('SELECT json_array(json_object(''_id'',id,''title'',title)) FROM boards WHERE id='+Board+';');
  if Length(Rows)<>1 then begin SendError(aResponse,500,'Could not read board');Exit;end;
  SendJson(aResponse,Rows[0][0]);
end;

procedure ApiAddBoardMember(aRequest:TRequest;aResponse:TResponse);
begin ApiBoardMembership(aRequest,aResponse,True);end;

procedure ApiRemoveBoardMember(aRequest:TRequest;aResponse:TResponse);
begin ApiBoardMembership(aRequest,aResponse,False);end;

procedure ApiBoardCardSettings(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"Board not found"}';
  DefaultsJson=
    '{"allowsSwimlaneDragging":true,"allowsListDragging":true,"allowsCardDragging":true,'+
    '"allowsChecklistDragging":true,"allowsChecklistItemDragging":true,"allowsSubtaskDragging":true,'+
    '"allowsMinicardCollapse":true,"labelsAboveTitleOnMinicard":false,"allowsChecklistDueDate":true,'+
    '"allowsChecklistTitle":true,"allowsCardCounterList":false,"cardAging":false,'+
    '"askForMoveReason":false,"allowsBoardMemberList":false,"allowsShowLists":true,'+
    '"allowsAttachments":true,"allowsChecklists":true,"allowsComments":true,'+
    '"allowsCommentsOnMinicard":false,"allowsDescriptionTitle":true,"allowsDescriptionText":true,'+
    '"allowsActivities":true,"allowsLabels":true,"allowsCreator":true,"allowsAssignee":true,'+
    '"allowsMembers":true,"allowsRequestedBy":true,"allowsCardSortingByNumber":true,'+
    '"allowsCardNumber":false,"allowsAssignedBy":true,"allowsReceivedDate":true,"allowsSpentTime":true,'+
    '"allowsStartDate":true,"allowsEndDate":true,"allowsDueDate":true,"allowsSubtasks":true,'+
    '"allowsCreatorOnMinicard":false,"allowsAttachmentsOnMinicard":true,'+
    '"allowsChecklistsOnMinicard":true,"allowsChecklistAtMinicard":false,'+
    '"allowsCoverAttachmentOnMinicard":true,"allowsBadgeAttachmentOnMinicard":false,'+
    '"allowsCardSortingByNumberOnMinicard":false,"allowsCardNumberOnMinicard":false,'+
    '"allowsDescriptionTitleOnMinicard":true,"allowsDescriptionTextOnMinicard":false,'+
    '"allowsLabelsOnMinicard":true,"allowsAssigneeOnMinicard":true,"allowsMembersOnMinicard":true,'+
    '"allowsRequestedByOnMinicard":true,"allowsAssignedByOnMinicard":true,'+
    '"allowsReceivedDateOnMinicard":true,"allowsSpentTimeOnMinicard":true,'+
    '"allowsStartDateOnMinicard":true,"allowsEndDateOnMinicard":true,"allowsDueDateOnMinicard":true,'+
    '"allowsSubtasksOnMinicard":true,"allowsShowListsOnMinicard":false,'+
    '"allowsSwimlaneNameOnMinicard":false,"showLabelText":true,"allowsStickers":true,'+
    '"allowsStickersOnMinicard":true,"allowsLocation":true,"allowsDependencies":true,'+
    '"allowsDependenciesOnMinicard":true,"allowsFlowtime":true,"allowsPomodoro":true,"allowsVote":true,'+
    '"allowsVoteOnMinicard":true,"allowsPoker":true,"allowsPokerOnMinicard":true,"allowsTextNotes":true,'+
    '"allowsCommentCountOnMinicard":true,"allowsIssueTypeOnMinicard":true,"allowsCardColorOnCard":true,'+
    '"allowsCardColorOnMinicard":true,"allowsParentCardOnCard":true,"allowsParentCardOnMinicard":true,'+
    '"allowsLinkedCardOnCard":true,"allowsLinkedCardOnMinicard":true,"allowsCardButtonsOnCard":true,'+
    '"allowsDescriptionBadgeOnMinicard":true,"allowsUnreadCommentsOnMinicard":true,'+
    '"allowsCardButtonsOnMinicard":null,"allowsDescriptionBadgeOnCard":null,'+
    '"allowsUnreadCommentsOnCard":null,"allowsDueFromTitleOnCard":null,'+
    '"allowsDueFromTitleOnMinicard":null,"allowsSimilarCardsOnCard":null,'+
    '"allowsSimilarCardsOnMinicard":null,"allowsAtRiskOnCard":null,"allowsAtRiskOnMinicard":null,'+
    '"allowsSuggestedMembersOnCard":null,"allowsForecastOnCard":null,"allowsForecastOnMinicard":null,'+
    '"allowsChecklistFromDescriptionOnCard":null,"allowsActionItemsOnCard":null,'+
    '"allowsWhiteboardOnCard":null,"allowsAttachmentPreviewsOnCard":null,'+
    '"allowsAttachmentDetailsOnCard":null,"allowsCardCollapse":true,'+
    '"allowsChecklistTitleOnMinicard":true,"allowsLabelTextOnCard":true,"labelsAboveTitleOnCard":null,'+
    '"allowsChecklistDueDateOnMinicard":null,"allowsLocationOnMinicard":null,'+
    '"allowsSwimlaneNameOnCard":null,"allowsFlowtimeOnMinicard":null,"allowsPomodoroOnMinicard":null,'+
    '"allowsAttachmentListOnMinicard":null,"allowsTextNotesOnMinicard":null,'+
    '"allowsCommentCountOnCard":null,"allowsActivitiesOnMinicard":null,"cardAgingDays1":7,'+
    '"cardAgingDays2":14,"cardAgingDays3":28}';
var T:TWLTenant;UserId,BoardId,Scope,Permission,Key,Sql,Raw:string;Rows:TWLRows;
  Defaults,Stored,Body,Patch,Reply:TJSONObject;Value,Fallback:TJSONData;Policy:TFieldPolicy;
  I:Integer;Days:Int64;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];Scope:='id='+QuotedStr(BoardId);
  if Length(T.Db.Query('SELECT id FROM boards WHERE '+Scope+';'))<>1 then
  begin SendJson(aResponse,NotFound,404);Exit;end;
  Defaults:=ExactObject(DefaultsJson);Stored:=nil;Body:=nil;Patch:=nil;Reply:=nil;
  try
    if aRequest.Method='PUT' then
    begin
      Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
      try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin SendError(aResponse,403,'Board administration required');Exit;end;
      try
        if Pos('application/json',LowerCase(aRequest.ContentType))=1 then Body:=ExactObject(aRequest.Content)
        else
        begin
          Body:=TJSONObject.Create;
          for I:=0 to aRequest.ContentFields.Count-1 do
            Body.Add(aRequest.ContentFields.Names[I],aRequest.ContentFields.ValueFromIndex[I]);
        end;
        Patch:=TJSONObject.Create;
        for I:=0 to Defaults.Count-1 do
        begin
          Key:=Defaults.Names[I];Value:=Body.Find(Key);
          if Value=nil then Continue;
          if Defaults.Items[I].JSONType=jtNumber then
          begin
            if (Value.JSONType in [jtNumber,jtString]) and TryStrToInt64(Trim(Value.AsString),Days) and (Days>=0) then
              Patch.Add(Key,Days);
          end else
          begin
            Raw:='';
            if Value.JSONType in [jtBoolean,jtString] then Raw:=Value.AsString;
            Patch.Add(Key,SameText(Raw,'true'));
          end;
        end;
      except SendError(aResponse,400,'Invalid card settings');Exit;end;
      if Patch.Count=0 then begin SendError(aResponse,400,'No recognized card settings in body');Exit;end;
      Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+
        ' THEN 1 ELSE json(''Board card settings permission changed'') END; UPDATE boards SET settings_json='+
        'json_patch(settings_json,'+QuotedStr(Patch.AsJSON)+') WHERE '+Scope+'; COMMIT;';
      if not T.Db.Exec(Sql) then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not write board card settings');Exit;end;
    end else if not ApiAuthBoard(T,aResponse,UserId,BoardId,False) then Exit;
    Rows:=T.Db.Query('SELECT settings_json FROM boards WHERE '+Scope+';');
    if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
    Stored:=ExactObject(Rows[0][0]);Reply:=TJSONObject.Create;
    for I:=0 to Defaults.Count-1 do
    begin
      Key:=Defaults.Names[I];Fallback:=Defaults.Items[I];Value:=Stored.Find(Key);
      if Value=nil then Value:=Fallback;
      if Value.JSONType<>jtNull then Reply.Add(Key,Value.Clone);
    end;
    SendJson(aResponse,Reply.AsJSON);
  finally Reply.Free;Patch.Free;Body.Free;Stored.Free;Defaults.Free;end;
end;

// The board admin's right (#5819's ScopeAdminExpression, a site admin too):
// what renames the board, from the REST API and from a view alike.
function BoardAdminPermission(Db:TWLDb;const UserId,BoardId:string;out Permission:string):Boolean;
var Policy:TFieldPolicy;Rows:TWLRows;
begin
  Policy:=TFieldPolicy.Create(Db,UserId,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=Db.Query('SELECT '+Permission+';');
  Result:=(Length(Rows)=1) and (Rows[0][0]='1');
end;

function BoardCanAdmin(Db:TWLDb;const UserId,BoardId:string):Boolean;
var Permission:string;
begin
  Result:=(UserId<>'') and (BoardId<>'') and (Pos(#0,BoardId)=0) and
    (Length(Db.Query('SELECT 1 FROM boards WHERE id='+QuotedStr(BoardId)+';'))=1) and
    BoardAdminPermission(Db,UserId,BoardId,Permission);
end;

function RenameBoard(const T:TWLTenant;const UserId,BoardId,Title:string;out Error:string):Integer;
var Scope,Permission:string;
begin
  Error:='';
  Scope:='id='+QuotedStr(BoardId);
  if (BoardId='') or (Pos(#0,BoardId)>0) or (Length(T.Db.Query('SELECT 1 FROM boards WHERE '+Scope+';'))=0) then
  begin Error:='Board not found';Exit(404);end;
  if not BoardAdminPermission(T.Db,UserId,BoardId,Permission) then begin Error:='Board administration required';Exit(403);end;
  if Pos(#0,Title)>0 then begin Error:='Invalid board title';Exit(400);end;
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+
    ' THEN 1 ELSE json(''Board permission changed'') END; '+
    'UPDATE boards SET title='+QuotedStr(Title)+', modifiedAt='+QuotedStr(NowIso)+' WHERE '+Scope+'; '+
    'SELECT CASE WHEN '+Permission+' AND (SELECT count(*) FROM boards WHERE '+Scope+
    ' AND title='+QuotedStr(Title)+')=1 THEN 1 ELSE json(''Board rename failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not rename board';Exit(500);end;
  Result:=200;
end;

procedure ApiBoardTitle(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,Title,Error:string;Code:Integer;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];
  if Length(T.Db.Query('SELECT 1 FROM boards WHERE id='+QuotedStr(BoardId)+';'))=0 then
  begin SendError(aResponse,404,'Board not found');Exit;end;
  if not BoardCanAdmin(T.Db,UserId,BoardId) then begin SendError(aResponse,403,'Board administration required');Exit;end;
  Title:=BodyField(aRequest,'title');
  Code:=RenameBoard(T,UserId,BoardId,Title,Error);
  if Code<>200 then begin SendError(aResponse,Code,Error);Exit;end;
  SendJson(aResponse,'{"_id":"'+StringToJSONString(BoardId)+'","title":"'+StringToJSONString(Title)+'"}');
end;

// models/users.js toggleBoardStar: the board in profile.starredBoards, or out of
// it, for a board the user may read.
function ToggleViewBoardStar(Db:TWLDb;const UserId,BoardId:string;out Error:string):Integer;
var Profile,Stars,Id:string;
begin
  Error:='';
  if (BoardId='') or (Pos(#0,BoardId)>0) or not BoardCanRead(Db,UserId,BoardId) then begin Error:='Board not found';Exit(404);end;
  Profile:='CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END';
  Stars:='COALESCE(json_extract('+Profile+',''$.starredBoards''),''[]'')';
  Id:=QuotedStr(BoardId);
  if not Db.Exec('UPDATE users SET profile_json=json_set('+Profile+',''$.starredBoards'',CASE WHEN EXISTS(SELECT 1 FROM json_each('+Stars+
    ') WHERE value='+Id+') THEN (SELECT json_group_array(value) FROM json_each('+Stars+') WHERE value<>'+Id+') ELSE json_insert('+Stars+
    ',''$[#]'','+Id+') END) WHERE id='+QuotedStr(UserId)+';') then
  begin Error:='Could not save';Exit(500);end;
  Result:=200;
end;

// archivesSidebar's restore: an archived card, list or swimlane of the board
// back on it, by whoever may change the board.
function ListHasRoom(Db:TWLDb;const BoardId,ListId:string;out Title:string):Boolean;
var R:TWLRows;
begin
  Title:='';
  if (ListId='') or (Pos(#0,BoardId+ListId)>0) then Exit(False);
  R:=Db.Query('SELECT title,CASE WHEN COALESCE(wip_enabled,0)=1 AND COALESCE(wip_soft,0)=0 AND (SELECT count(*) FROM cards c WHERE '+
    'c.listId=l.id AND c.archived=0 AND c.deletedAt IS NULL)>=COALESCE(wip_value,1) THEN 0 ELSE 1 END FROM lists l WHERE id='+
    QuotedStr(ListId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL;');
  if Length(R)<>1 then Exit(False);
  Title:=R[0][0];
  Result:=R[0][1]='1';
end;

function RestoreArchivedCard(const T:TWLTenant;const UserId,BoardId,CardId,Move:string):Boolean;
var Scope,ArchivedScope:string;
begin
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  ArchivedScope:=Scope+' AND archived=1';
  Result:=T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN EXISTS(SELECT 1 FROM cards WHERE '+ArchivedScope+
    ') THEN 1 ELSE json(''Archived card scope changed'') END; UPDATE cards SET archived=0,archivedAt=NULL'+Move+
    ',modifiedAt='+QuotedStr(NowIso)+' WHERE '+ArchivedScope+'; SELECT CASE WHEN EXISTS(SELECT 1 FROM cards WHERE '+
    Scope+' AND archived=0) THEN 1 ELSE json(''Restore failed'') END; COMMIT;');
  if Result then RecordCardBooleanHistory(T.Db,UserId,BoardId,CardId,'archived',True,False)
  else T.Db.Exec('ROLLBACK;');
end;

function RestoreAllViewCards(const T:TWLTenant;const UserId,BoardId:string;out Skipped:Integer;out Error:string):Integer;
var R:TWLRows;i:Integer;Title:string;
begin
  Error:='';Skipped:=0;
  if (BoardId='') or (Pos(#0,BoardId)>0) then begin Error:='Not found';Exit(404);end;
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  R:=T.Db.Query('SELECT id,listId FROM cards WHERE boardId='+QuotedStr(BoardId)+' AND archived=1 AND deletedAt IS NULL ORDER BY sort,id;');
  for i:=0 to High(R) do
  begin
    if not ListHasRoom(T.Db,BoardId,R[i][1],Title) then begin Inc(Skipped);Continue;end;
    if not RestoreArchivedCard(T,UserId,BoardId,R[i][0],'') then begin Error:='Could not restore';Exit(500);end;
  end;
  Result:=200;
end;

function SetViewSwimlaneArchived(const T:TWLTenant;const UserId,BoardId,LaneId:string;Archive:Boolean;out Error:string):Integer;
var Scope,CardScope,ListScope,ListUpdate,Placement,Stamp,ArchivedAt,OldState,NewState:string;Rows,Changed,ChangedLists:TWLRows;
begin
  Error:='';
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  if (LaneId='') or (Pos(#0,LaneId)>0) then begin Error:='Not found';Exit(404);end;
  OldState:=IntToStr(Ord(not Archive));NewState:=IntToStr(Ord(Archive));
  Scope:='id='+QuotedStr(LaneId)+' AND boardId='+QuotedStr(BoardId)+' AND archived='+OldState;
  if not T.Db.Exec('BEGIN IMMEDIATE;') then begin Error:='Could not change archive state';Exit(500);end;
  try
    Rows:=T.Db.Query('SELECT COALESCE(archivedAt,''''),type FROM swimlanes WHERE '+Scope+';');
    if Length(Rows)<>1 then
    begin T.Db.Exec('ROLLBACK;');Error:='Not found';Exit(404);end;
    Stamp:=QuotedStr(NowIso);
    Placement:='swimlaneId='+QuotedStr(LaneId);
    ListUpdate:='';
    ChangedLists:=nil;
    ArchivedAt:='NULL';
    if Archive then ArchivedAt:=Stamp;
    if Rows[0][1]='template-swimlane' then
    begin
      ListScope:='boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL AND archived='+OldState+
        ' AND ('+Placement+' OR COALESCE(swimlaneId,'''')='''')';
      if not Archive then ListScope:=ListScope+' AND archivedAt='+QuotedStr(Rows[0][0]);
      ChangedLists:=T.Db.Query('SELECT id FROM lists WHERE '+ListScope+' ORDER BY id;');
      ListUpdate:='UPDATE lists SET archived='+NewState+',archivedAt='+ArchivedAt+',modifiedAt='+Stamp+
        ' WHERE '+ListScope+'; ';
      Placement:=Placement+' OR listId IN (SELECT id FROM lists WHERE '+ListScope+' AND type=''template-list'')';
    end;
    CardScope:='boardId='+QuotedStr(BoardId)+' AND ('+Placement+') AND deletedAt IS NULL AND archived='+OldState;
    if not Archive then CardScope:=CardScope+' AND archivedAt='+QuotedStr(Rows[0][0]);
    Changed:=T.Db.Query('SELECT id FROM cards WHERE '+CardScope+' ORDER BY id;');
    if not T.Db.Exec('UPDATE cards SET archived='+NewState+',archivedAt='+ArchivedAt+',modifiedAt='+Stamp+
      ' WHERE '+CardScope+'; '+ListUpdate+'UPDATE swimlanes SET archived='+NewState+',archivedAt='+ArchivedAt+',modifiedAt='+Stamp+
      ' WHERE '+Scope+'; COMMIT;') then
    begin T.Db.Exec('ROLLBACK;');Error:='Could not change archive state';Exit(500);end;
  except
    T.Db.Exec('ROLLBACK;');
    raise;
  end;
  try
    RecordContainerArchiveBatch(T.Db,UserId,BoardId,'swimlane',LaneId,Archive,ChangedLists,Changed);
  except
    // History never fails the operation it records.
  end;
  Result:=200;
end;

function RestoreViewItem(const T:TWLTenant;const UserId,BoardId,Kind,ItemId,ToList:string;out Error:string):Integer;
var Table,Scope,Extra,Move,ListTitle:string;R:TWLRows;
begin
  Error:='';
  if (BoardId='') or (ItemId='') or (Pos(#0,BoardId+ItemId)>0) then begin Error:='Not found';Exit(404);end;
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  Extra:='';
  if Kind='cards' then begin Table:='cards';Extra:=' AND deletedAt IS NULL';end
  else if Kind='lists' then begin Table:='lists';Extra:=' AND deletedAt IS NULL';end
  else if Kind='swimlanes' then Exit(SetViewSwimlaneArchived(T,UserId,BoardId,ItemId,False,Error))
  else begin Error:='Not found';Exit(404);end;
  Scope:='id='+QuotedStr(ItemId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=1'+Extra;
  if Length(T.Db.Query('SELECT 1 FROM '+Table+' WHERE '+Scope+';'))<>1 then begin Error:='Not found';Exit(404);end;
  Move:='';
  if Kind='cards' then
  begin
    R:=T.Db.Query('SELECT listId,COALESCE(swimlaneId,'''') FROM cards WHERE '+Scope+';');
    if Length(R)<>1 then begin Error:='Not found';Exit(404);end;
    if ToList='' then
    begin
      // Its own list filled up since the page was drawn: choose another.
      if not ListHasRoom(T.Db,BoardId,R[0][0],ListTitle) then begin Error:='restore-blocked';Exit(409);end;
    end
    else if not ListHasRoom(T.Db,BoardId,ToList,ListTitle) then
    begin Error:='That list has reached its WIP limit';Exit(409);end
    else if ToList<>R[0][0] then
    begin
      Move:=',listId='+QuotedStr(ToList);
      // Its swimlane, while it is still open; the board's first otherwise.
      if Length(T.Db.Query('SELECT 1 FROM swimlanes WHERE id='+QuotedStr(R[0][1])+' AND boardId='+QuotedStr(BoardId)+' AND archived=0;'))<>1 then
      begin
        R:=T.Db.Query('SELECT id FROM swimlanes WHERE boardId='+QuotedStr(BoardId)+' AND archived=0 ORDER BY sort,id LIMIT 1;');
        if Length(R)=1 then Move:=Move+',swimlaneId='+QuotedStr(R[0][0]);
      end;
    end;
    if not RestoreArchivedCard(T,UserId,BoardId,ItemId,Move) then begin Error:='Could not restore';Exit(500);end;
    Exit(200);
  end;
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN EXISTS(SELECT 1 FROM '+Table+' WHERE '+Scope+
    ') THEN 1 ELSE json(''Archive scope changed'') END; UPDATE '+Table+' SET archived=0,archivedAt=NULL'+Move+',modifiedAt='+QuotedStr(NowIso)+' WHERE '+Scope+
    '; SELECT CASE WHEN (SELECT count(*) FROM '+Table+' WHERE id='+QuotedStr(ItemId)+' AND archived=0)=1 THEN 1 '+
    'ELSE json(''Restore failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not restore';Exit(500);end;
  RecordArchiveHistory(T.Db,UserId,BoardId,'list',ItemId,False);
  Result:=200;
end;

function Slugify(const S: string): string;
var i: Integer; c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if c in ['A'..'Z'] then c := Chr(Ord(c) + 32);
    if c in ['a'..'z', '0'..'9'] then Result := Result + c
    else if (Result <> '') and (Result[Length(Result)] <> '-') then Result := Result + '-';
  end;
  if Result = '' then Result := 'board';
end;

procedure NormalizeRuleTrigger(Trigger:TJSONObject);
const
  TriggerFields=
    '"createCard":["boardId","listName","userId","swimlaneName","cardTitle"],'+
    '"moveCard":["boardId","listName","oldListName","userId","swimlaneName","cardTitle"],'+
    '"archivedCard":["boardId","userId","cardTitle"],'+
    '"addComment":["boardId","userId","cardTitle"],'+
    '"restoredCard":["boardId","userId","cardTitle"],'+
    '"joinMember":["boardId","username","userId"],'+
    '"unjoinMember":["boardId","username","userId"],'+
    '"joinAssignee":["boardId","username","userId"],'+
    '"unjoinAssignee":["boardId","username","userId"],'+
    '"addChecklist":["boardId","checklistName","userId"],'+
    '"removeChecklist":["boardId","checklistName","userId"],'+
    '"completeChecklist":["boardId","checklistName","userId"],'+
    '"uncompleteChecklist":["boardId","checklistName","userId"],'+
    '"addedChecklistItem":["boardId","checklistItemName","userId"],'+
    '"removedChecklistItem":["boardId","checklistItemName","userId"],'+
    '"checkedItem":["boardId","checklistItemName","userId"],'+
    '"uncheckedItem":["boardId","checklistItemName","userId"],'+
    '"addAttachment":["boardId","userId"],'+
    '"deleteAttachment":["boardId","userId"],'+
    '"addedLabel":["boardId","labelId","userId"],'+
    '"removedLabel":["boardId","labelId","userId"],'+
    '"a-receivedAt":["boardId","userId"],'+
    '"a-startAt":["boardId","userId"],'+
    '"a-dueAt":["boardId","userId"],'+
    '"a-endAt":["boardId","userId"]';
var Fields:TJSONObject;MatchFields,Value:TJSONData;I:Integer;Name:string;
begin
  Fields:=ExactObject('{'+TriggerFields+'}');
  try
    MatchFields:=Fields.Find(Trigger.Get('activityType',''));
    if MatchFields is TJSONArray then
      for I:=0 to MatchFields.Count-1 do
      begin
        Name:=MatchFields.Items[I].AsString;Value:=Trigger.Find(Name);
        if (Value=nil) or (Value.JSONType=jtNull) or ((Value is TJSONString) and (Value.AsString='')) then
        begin Trigger.Delete(Name);Trigger.Add(Name,'*');end;
      end;
  finally Fields.Free;end;
end;

procedure ApiCreateRule(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,Permission,RuleId,TriggerId,ActionId,Title,Sql,Guards:string;
  Body,Rule,Trigger,Action,Reply,Before,After:TJSONObject;Rows:TWLRows;
  Policy:TFieldPolicy;
  function WorkflowInsert(const Collection:string;Doc:TJSONObject):string;
  var Found:TWLRows;TableName,QuotedTable,Payload:string;
  begin
    if not EnsureSharedCollection(T.Db,Collection) then raise Exception.Create('Workflow collection unavailable');
    Found:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(Collection)+';');
    if Length(Found)<>1 then raise Exception.Create('Ambiguous workflow collection');
    TableName:=Found[0][0];QuotedTable:='"'+StringReplace(TableName,'"','""',[rfReplaceAll])+'"';
    Guards:=Guards+' AND (SELECT count(*) FROM _ferretdb_collections WHERE table_name='+QuotedStr(TableName)+
      ' AND name='+QuotedStr(Collection)+')=1';
    Payload:=QuotedStr(TypedDocument(Doc.AsJSON,'','{}'));
    Result:='INSERT INTO '+QuotedTable+'(_ferretdb_sjson) VALUES(CASE WHEN wl_storage('+QuotedStr(TableName)+
      ')=''blob'' THEN jsonb('+Payload+') ELSE '+Payload+' END); '+
      'SELECT CASE WHEN (SELECT count(*) FROM '+QuotedTable+' WHERE json_extract(_ferretdb_sjson,''$._id'')='+
      QuotedStr(Doc.Get('_id',''))+')=1 THEN 1 ELSE json(''Workflow insert failed'') END; ';
  end;
  function PreparePart(const Part,Kind,Id:string):TJSONObject;
  var Raw:TJSONData;Key:string;
  begin
    Raw:=Body.Find(Part);
    if not (Raw is TJSONObject) then raise Exception.Create('Missing workflow part');
    Raw:=TJSONObject(Raw).Find(Kind);
    if not (Raw is TJSONString) or (Trim(Raw.AsString)='') then raise Exception.Create('Missing workflow part type');
    Result:=TJSONObject(Body.Find(Part));
    for Key in ['_id','boardId','createdAt','modifiedAt','updatedAt'] do Result.Delete(Key);
    Result.Add('_id',Id);Result.Add('boardId',BoardId);
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];
  Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board administration required');Exit;end;
  if Length(T.Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))<>1 then
  begin SendError(aResponse,501,'Rule creation requires shared workflow storage');Exit;end;
  Body:=nil;Rule:=nil;
  try
    RuleId:=NewId;TriggerId:=NewId;ActionId:=NewId;
    try
      Body:=ExactObject(aRequest.Content);
      Trigger:=PreparePart('trigger','activityType',TriggerId);
      Action:=PreparePart('action','actionType',ActionId);
      NormalizeRuleTrigger(Trigger);
      Title:=Body.Get('title','');if Title='' then Title:='API rule';
      Rule:=TJSONObject.Create(['_id',RuleId,'title',Title,'triggerId',TriggerId,
        'actionId',ActionId,'boardId',BoardId,'enabled',True]);
      if Trigger.Get('activityType','')='button' then
      begin
        Rule.Add('buttonType',Trigger.Get('buttonType','card'));
        Rule.Add('buttonLabel',Trigger.Get('buttonLabel',Title));
      end;
    except SendError(aResponse,400,'Invalid workflow definition');Exit;end;
    try
      Guards:='';Sql:=WorkflowInsert('triggers',Trigger)+WorkflowInsert('actions',Action)+WorkflowInsert('rules',Rule);
      if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+Guards+
        ' THEN 1 ELSE json(''Workflow scope changed'') END; '+Sql+'COMMIT;') then
        raise Exception.Create('Rule creation failed');
    except T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create rule');Exit;end;
    // One history row for the new rule (wlrules' RecordRuleHistory).
    Before:=TJSONObject.Create(['rule',TJSONNull.Create]);After:=RuleSnapshot(T.Db,RuleId);
    try RecordRuleHistory(T.Db,UserId,Before,After);finally After.Free;Before.Free;end;
    Reply:=TJSONObject.Create(['_id',RuleId,'triggerId',TriggerId,'actionId',ActionId]);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  finally Rule.Free;Body.Free;end;
end;

procedure ApiEditRule(aRequest:TRequest;aResponse:TResponse);
const Doc='_ferretdb_sjson';
var T:TWLTenant;UserId,BoardId,RuleId,Permission,Guard,RuleTable,RuleScope,RuleRaw,Sql,Bindings:string;
  Rows:TWLRows;Body,Rule,Before,After:TJSONObject;Value:TJSONData;Policy:TFieldPolicy;
  function Bind(const Collection:string;out Storage:string):string;
  var Found:TWLRows;
  begin
    Found:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(Collection)+';');
    if Length(Found)<>1 then raise Exception.Create('Missing workflow collection');
    Storage:=Found[0][0];Result:='"'+StringReplace(Storage,'"','""',[rfReplaceAll])+'"';
    Bindings:=Bindings+' AND (SELECT count(*) FROM _ferretdb_collections WHERE name='+QuotedStr(Collection)+
      ' AND table_name='+QuotedStr(Storage)+')=1';
  end;
  function KeyMatch(const Id:string):string;
  begin
    Result:='json_extract('+Doc+',''$._id'')='+QuotedStr(Id)+
      ' AND json_extract('+Doc+',''$.$s.p._id.t'')=''string''';
  end;
  procedure SetValue(Obj:TJSONObject;const Name:string;Item:TJSONData);
  begin Obj.Delete(Name);Obj.Add(Name,Item);end;
  procedure EditPart(const Part,Collection,Kind,Extra:string);
  var Patch,Stored:TJSONObject;Item:TJSONData;CurrentId,NewPartId,IdKey,TableName,Storage,Scope,Previous,
    Reference,ReferenceCheck,Encoded,Literal,Key:string;Found:TWLRows;I:Integer;SharedPart:Boolean;
  begin
    Item:=Body.Find(Part);if Item=nil then Exit;
    if not (Item is TJSONObject) then raise EConvertError.Create('Invalid workflow part');
    Patch:=TJSONObject(Item);Item:=Patch.Find(Kind);
    if not (Item is TJSONString) or (Trim(Item.AsString)='') then raise EConvertError.Create('Invalid workflow type');
    for Key in ['_id','boardId','createdAt','modifiedAt','updatedAt'] do Patch.Delete(Key);
    if Part='trigger' then NormalizeRuleTrigger(Patch);
    TableName:=Bind(Collection,Storage);IdKey:=Part+'Id';CurrentId:=Rule.Get(IdKey,'');
    Scope:=KeyMatch(CurrentId)+' AND (json_type('+Doc+',''$.boardId'') IS NULL OR '+
      'json_extract('+Doc+',''$.boardId'')='+QuotedStr(BoardId)+')';
    Found:=T.Db.Query('SELECT json('+Doc+') FROM '+TableName+' WHERE '+Scope+';');
    if Length(Found)>1 then raise Exception.Create('Ambiguous workflow part');
    Previous:='';if Length(Found)=1 then Previous:=Found[0][0];
    Reference:='EXISTS(SELECT 1 FROM '+RuleTable+' WHERE NOT ('+RuleScope+') AND ('+
      'json_extract('+Doc+','+QuotedStr('$.'+IdKey)+')='+QuotedStr(CurrentId)+
      ' OR EXISTS(SELECT 1 FROM json_each('+Doc+','+QuotedStr('$.'+Extra)+') WHERE type=''text'' AND value='+
      QuotedStr(CurrentId)+')))';
    Found:=T.Db.Query('SELECT '+Reference+';');
    if Length(Found)<>1 then raise Exception.Create('Could not read workflow references');
    SharedPart:=Found[0][0]='1';ReferenceCheck:=Reference;
    if not SharedPart then ReferenceCheck:='NOT '+Reference;
    Stored:=nil;
    try
      if Previous='' then Stored:=TJSONObject.Create else Stored:=ExactObject(PlainDocument(Previous));
      NewPartId:=CurrentId;
      if SharedPart or (Previous='') then NewPartId:=NewId;
      for I:=0 to Patch.Count-1 do SetValue(Stored,Patch.Names[I],Patch.Items[I].Clone);
      SetValue(Stored,'_id',TJSONString.Create(NewPartId));
      SetValue(Stored,'boardId',TJSONString.Create(BoardId));
      Encoded:=QuotedStr(TypedDocument(Stored.AsJSON,Previous,'{}'));
      Literal:='CASE WHEN wl_storage('+QuotedStr(Storage)+')=''blob'' THEN jsonb('+Encoded+') ELSE '+Encoded+' END';
      if Previous<>'' then
        Guard:=Guard+' AND '+ReferenceCheck+' AND (SELECT count(*) FROM '+TableName+' WHERE '+Scope+
          ' AND json('+Doc+')='+QuotedStr(Previous)+')=1'
      else Guard:=Guard+' AND NOT EXISTS(SELECT 1 FROM '+TableName+' WHERE '+Scope+')';
      if NewPartId=CurrentId then
        Sql:=Sql+'UPDATE '+TableName+' SET '+Doc+'='+Literal+' WHERE '+Scope+'; '
      else
        Sql:=Sql+'INSERT INTO '+TableName+'('+Doc+') VALUES('+Literal+'); ';
      Sql:=Sql+'SELECT CASE WHEN EXISTS(SELECT 1 FROM '+TableName+' WHERE '+KeyMatch(NewPartId)+
        ' AND json('+Doc+')=json('+Encoded+')) THEN 1 ELSE json(''Workflow part edit failed'') END; ';
      SetValue(Rule,IdKey,TJSONString.Create(NewPartId));
      if Part='trigger' then
      begin
        Rule.Delete('buttonType');Rule.Delete('buttonLabel');
        if Stored.Get('activityType','')='button' then
        begin
          Rule.Add('buttonType',Stored.Get('buttonType','card'));
          Rule.Add('buttonLabel',Stored.Get('buttonLabel',Rule.Get('title','Rule')));
        end;
      end;
    finally Stored.Free;end;
  end;
var RuleStorage,Encoded:string;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];RuleId:=aRequest.RouteParams['ruleId'];
  Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board administration required');Exit;end;
  Body:=nil;Rule:=nil;Bindings:='';Guard:='';Sql:='';
  Before:=RuleSnapshot(T.Db,RuleId);After:=nil;
  try
    try
      try Body:=ExactObject(aRequest.Content);
      except raise EConvertError.Create('Invalid workflow update');end;
      RuleTable:=Bind('rules',RuleStorage);
      RuleScope:=KeyMatch(RuleId)+' AND json_extract('+Doc+',''$.boardId'')='+QuotedStr(BoardId)+
        ' AND json_extract('+Doc+',''$.$s.p.boardId.t'')=''string''';
      Rows:=T.Db.Query('SELECT json('+Doc+') FROM '+RuleTable+' WHERE '+RuleScope+';');
      if Length(Rows)<>1 then begin SendJson(aResponse,'{"error":"Rule not found"}',404);Exit;end;
      RuleRaw:=Rows[0][0];Rule:=ExactObject(PlainDocument(RuleRaw));
      Value:=Body.Find('title');if Value is TJSONString then SetValue(Rule,'title',Value.Clone);
      Value:=Body.Find('enabled');
      if Value<>nil then SetValue(Rule,'enabled',TJSONBoolean.Create(
        ((Value is TJSONBoolean) and Value.AsBoolean) or ((Value is TJSONString) and (Value.AsString='true'))));
      EditPart('trigger','triggers','activityType','extraTriggerIds');
      EditPart('action','actions','actionType','extraActionIds');
      // WeKan's ruleButtonMetadata: a button trigger's type and label on the
      // rule, which the board's menu reads; any other trigger, none.
      Value:=Body.Find('trigger');
      if Value is TJSONObject then
      begin
        Rule.Delete('buttonType');Rule.Delete('buttonLabel');
        if TJSONObject(Value).Get('activityType','')='button' then
        begin
          if TJSONObject(Value).Get('buttonType','')='board' then Rule.Add('buttonType','board') else Rule.Add('buttonType','card');
          if TJSONObject(Value).Get('buttonLabel','')<>'' then Rule.Add('buttonLabel',TJSONObject(Value).Get('buttonLabel',''))
          else if Rule.Get('title','')<>'' then Rule.Add('buttonLabel',Rule.Get('title',''))
          else Rule.Add('buttonLabel','Rule');
        end;
      end;
      Encoded:=QuotedStr(TypedDocument(Rule.AsJSON,RuleRaw,'{}'));
      Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+Bindings+Guard+
        ' AND (SELECT count(*) FROM '+RuleTable+' WHERE '+RuleScope+' AND json('+Doc+')='+QuotedStr(RuleRaw)+
        ')=1 THEN 1 ELSE json(''Workflow scope changed'') END; '+Sql+
        'UPDATE '+RuleTable+' SET '+Doc+'=CASE WHEN wl_storage('+QuotedStr(RuleStorage)+')=''blob'' THEN jsonb('+
        Encoded+') ELSE '+Encoded+' END WHERE '+RuleScope+'; '+
        'SELECT CASE WHEN EXISTS(SELECT 1 FROM '+RuleTable+' WHERE '+RuleScope+' AND json('+Doc+')=json('+Encoded+
        ')) THEN 1 ELSE json(''Workflow edit failed'') END; COMMIT;';
      if not T.Db.Exec(Sql) then raise Exception.Create('Workflow edit failed');
    except
      on E:EConvertError do begin SendError(aResponse,400,'Invalid workflow update');Exit;end;
      on E:Exception do begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not edit rule');Exit;end;
    end;
    After:=RuleSnapshot(T.Db,RuleId);
    RecordRuleHistory(T.Db,UserId,Before,After);
    SendJson(aResponse,'{"_id":"'+StringToJSONString(RuleId)+'"}');
  finally After.Free;Before.Free;Rule.Free;Body.Free;end;
end;

procedure ApiDeleteRule(aRequest:TRequest;aResponse:TResponse);
const Doc='_ferretdb_sjson';NotFound='{"error":"Rule not found"}';
var T:TWLTenant;Actor,BoardId,RuleId,Permission,Scope,Source,Original,Bindings,Sql:string;
  Rows:TWLRows;Rule,Before,After:TJSONObject;Policy:TFieldPolicy;
  function Bind(const Collection:string):string;
  var Found:TWLRows;
  begin
    Result:='';
    Found:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(Collection)+';');
    if Length(Found)>1 then raise Exception.Create('Ambiguous workflow collection');
    if Length(Found)=0 then
    begin Bindings:=Bindings+' AND NOT EXISTS(SELECT 1 FROM _ferretdb_collections WHERE name='+QuotedStr(Collection)+')';Exit;end;
    Result:='"'+StringReplace(Found[0][0],'"','""',[rfReplaceAll])+'"';
    Bindings:=Bindings+' AND (SELECT count(*) FROM _ferretdb_collections WHERE name='+QuotedStr(Collection)+
      ' AND table_name='+QuotedStr(Found[0][0])+')=1';
  end;
  function UnusedParts(const Collection,Primary,Extra:string):string;
  var TableName,Id,Targets,Reference,Predicate:string;Value:TJSONData;Ids:TStringList;I:Integer;
    procedure Add(Value:TJSONData);
    begin
      if (Value is TJSONString) and (Value.AsString<>'') and (Pos(#0,Value.AsString)=0) then Ids.Add(Value.AsString);
    end;
  begin
    Result:='';TableName:=Bind(Collection);if TableName='' then Exit;
    Ids:=TStringList.Create;
    try
      Ids.CaseSensitive:=True;Ids.Sorted:=True;Ids.Duplicates:=dupIgnore;
      Add(Rule.Find(Primary));Value:=Rule.Find(Extra);
      if Value is TJSONArray then for I:=0 to Value.Count-1 do Add(Value.Items[I]);
      if Ids.Count=0 then Exit;
      Targets:='';
      for I:=0 to Ids.Count-1 do
      begin
        if I>0 then Targets:=Targets+',';
        Targets:=Targets+QuotedStr(Ids[I]);
      end;
      Id:='json_extract('+TableName+'.'+Doc+',''$._id'')';
      Reference:='EXISTS(SELECT 1 FROM '+Source+' r WHERE json_extract(r.'+Doc+','+QuotedStr('$.'+Primary)+')='+Id+
        ' OR EXISTS(SELECT 1 FROM json_each(r.'+Doc+','+QuotedStr('$.'+Extra)+') WHERE type=''text'' AND value='+Id+'))';
      Predicate:=Id+' IN ('+Targets+') AND json_extract('+Doc+',''$.$s.p._id.t'')=''string'' AND '+
        '(json_type('+Doc+',''$.boardId'') IS NULL OR json_extract('+Doc+',''$.boardId'')='+QuotedStr(BoardId)+
        ') AND NOT '+Reference;
      Result:='DELETE FROM '+TableName+' WHERE '+Predicate+'; '+
        'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM '+TableName+' WHERE '+Predicate+
        ') THEN 1 ELSE json(''Workflow part removal failed'') END; ';
    finally Ids.Free;end;
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];RuleId:=aRequest.RouteParams['ruleId'];
  Policy:=TFieldPolicy.Create(T.Db,Actor,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board administration required');Exit;end;
  if Length(T.Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))=0 then
  begin SendJson(aResponse,NotFound,404);Exit;end;
  Rule:=nil;Bindings:='';Before:=nil;After:=nil;
  try
    try
      Source:=Bind('rules');
      if Source='' then begin SendJson(aResponse,NotFound,404);Exit;end;
      Scope:='json_extract('+Doc+',''$._id'')='+QuotedStr(RuleId)+
        ' AND json_extract('+Doc+',''$.boardId'')='+QuotedStr(BoardId)+
        ' AND json_extract('+Doc+',''$.$s.p._id.t'')=''string'''+
        ' AND json_extract('+Doc+',''$.$s.p.boardId.t'')=''string''';
      Rows:=T.Db.Query('SELECT json('+Doc+') FROM '+Source+' WHERE '+Scope+';');
      if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
      Original:=Rows[0][0];Rule:=ExactObject(PlainDocument(Original));
      Sql:=UnusedParts('triggers','triggerId','extraTriggerIds')+UnusedParts('actions','actionId','extraActionIds');
      Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+Bindings+
        ' AND (SELECT count(*) FROM '+Source+' WHERE '+Scope+' AND json('+Doc+')='+QuotedStr(Original)+
        ')=1 THEN 1 ELSE json(''Workflow scope changed'') END; DELETE FROM '+Source+' WHERE '+Scope+
        '; SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM '+Source+' WHERE '+Scope+
        ') THEN 1 ELSE json(''Workflow removal failed'') END; '+Sql+'COMMIT;';
      Before:=RuleSnapshot(T.Db,RuleId);
      if not T.Db.Exec(Sql) then raise Exception.Create('Rule removal failed');
    except T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not delete rule');Exit;end;
    After:=RuleSnapshot(T.Db,RuleId);
    RecordRuleHistory(T.Db,Actor,Before,After);
    SendJson(aResponse,'{"_id":"'+StringToJSONString(RuleId)+'"}');
  finally After.Free;Before.Free;Rule.Free;end;
end;

procedure HandleIntegrations(aRequest:TRequest;aResponse:TResponse;Browser:Boolean);
const InvalidUrl='{"error":"invalid-webhook-url"}';
  NotFound='{"error":"Integration not found"}';
var T:TWLTenant;Actor,BoardId,Id,Permission,Source,TableName,Scope,Sql,Key,Payload,Mutation,Guard,Raw,Encoded,DocumentColumn,StorageGuard,InsertColumns,InsertValues,Operation:string;
  Rows:TWLRows;Policy:TFieldPolicy;Admin,Reading,Creating,BadUrl,Shared,Updating:Boolean;
  Session:TWLSession;Entries:TJSONArray;Doc,Entry:TJSONObject;Field:TJSONData;Row:TWLRow;
  function FormAction(const Verb,IntegrationId:string):string;
  begin
    Result:='webhook:'+Verb+':'+HashText(IntToStr(Length(BoardId))+':'+BoardId+IntegrationId);
  end;

  procedure MutationComplete;
  begin
    if Browser then
    begin
      Session.LanguageTag:=RequestLanguageTag(aRequest);
      aResponse.Code:=303;
      aResponse.Location:=SessionUrl('/board/webhooks?id='+HTTPEncode(BoardId),Session);
      aResponse.SetCustomHeader('Cache-Control','private, no-store');
      aResponse.SetCustomHeader('Referrer-Policy','no-referrer');
      SendResponse(aResponse);
    end
    else SendJson(aResponse,'{"_id":"'+StringToJSONString(Id)+'"}');
  end;

  procedure ShowIntegrations(List:TJSONArray);
  var Language:TWLLanguage;Words:TWLTranslator;Title,Body,Name,HookId,Checked:string;Hook:TJSONObject;I:Integer;
    function FormStart(const Verb,IntegrationId:string):string;
    begin
      Result:='<form method="post" action="/board/webhooks">'+AuthHiddenFields(Session,FormAction(Verb,IntegrationId))+
        '<input type="hidden" name="boardId" value="'+HtmlAttr(BoardId)+'">'+
        '<input type="hidden" name="operation" value="'+Verb+'">'+
        '<input type="hidden" name="integrationId" value="'+HtmlAttr(IntegrationId)+'">';
    end;
  begin
    Session.LanguageTag:=RequestLanguageTag(aRequest);
    Language:=ViewerLanguage(T.Db,Session,aRequest);
    Words:=TWLTranslator.Create(Language);
    try
      Title:=Words.Text('outgoing-webhooks','Outgoing Webhooks');
      Body:='<h1>'+HtmlEncode(Title)+'</h1><p><a href="'+
        HtmlAttr(SessionUrl(BoardRoute(BoardId,BoardSlug(T.Db,BoardId)),Session))+'">'+
        HtmlEncode(Words.Text('board','Board'))+'</a></p>'+FormStart('create','')+
        '<p><label>'+HtmlEncode(Words.Text('url','URL'))+' <input name="url" value=""></label> '+
        '<input type="submit" value="'+HtmlAttr(Words.Text('new-outgoing-webhook','New Outgoing Webhook'))+'"></p></form><ul>';
      if (List=nil) or (List.Count=0) then
        Body:=Body+'<li>'+HtmlEncode(Words.Text('no-items-message','No items.'))+'</li>'
      else
        for I:=0 to List.Count-1 do
        begin
          Hook:=List.Objects[I];
          Name:=Hook.Get('title','');
          if Name='' then Name:=Hook.Get('url','');
          Body:=Body+'<li><p>'+HtmlEncode(Name)+'</p>';
          if (Hook.Get('url','')<>'') and (Hook.Get('url','')<>Name) then
            Body:=Body+'<p>'+HtmlEncode(Hook.Get('url',''))+'</p>';
          if not Hook.Get('enabled',True) then
            Body:=Body+'<p>'+HtmlEncode(Words.Text('disabled','Disabled'))+'</p>';
          HookId:=Hook.Get('_id','');
          if HookId<>'' then
          begin
            Checked:='';if Hook.Get('enabled',True) then Checked:=' checked';
            Body:=Body+FormStart('save',HookId)+
              '<p><label>'+HtmlEncode(Words.Text('webhook-title','Webhook Name'))+
              ' <input name="title" value="'+HtmlAttr(Hook.Get('title',''))+'"></label> '+
              '<label>'+HtmlEncode(Words.Text('url','URL'))+' <input name="url" value="'+
              HtmlAttr(Hook.Get('url',''))+'"></label> '+
              '<label><input type="checkbox" name="enabled" value="1"'+Checked+'> '+
              HtmlEncode(Words.Text('enabled','Enabled'))+'</label> '+
              '<input type="submit" value="'+HtmlAttr(Words.Text('save','Save'))+'"></p></form>'+
              FormStart('delete',HookId)+'<p><input type="submit" value="'+
              HtmlAttr(Words.Text('delete','Delete'))+'"></p></form>';
          end;
          Body:=Body+'</li>';
        end;
      aResponse.Code:=200;aResponse.ContentType:='text/html; charset=utf-8';
      aResponse.SetCustomHeader('Cache-Control','private, no-store');
      aResponse.SetCustomHeader('Referrer-Policy','no-referrer');
      aResponse.Content:=LanguagePage(aResponse,Language,Title,Body+'</ul>','','html4');
      SendResponse(aResponse);
    finally Words.Free;end;
  end;

  procedure BrowserError(Status:Integer;const Key,Message:string);
  var Language:TWLLanguage;Words:TWLTranslator;Title,Body:string;
  begin
    Session.LanguageTag:=RequestLanguageTag(aRequest);
    Language:=ViewerLanguage(T.Db,Session,aRequest);
    Words:=TWLTranslator.Create(Language);
    try
      Title:=Words.Text('outgoing-webhooks','Outgoing Webhooks');
      Body:='<h1>'+HtmlEncode(Title)+'</h1>';
      if Status=401 then Body:=Body+'<p><a href="'+HtmlAttr(SessionUrl('/sign-in',Session))+'">'+
        HtmlEncode(Words.Text(Key,Message))+'</a></p>'
      else Body:=Body+'<p>'+HtmlEncode(Words.Text(Key,Message))+'</p>';
      if Status=400 then Body:=Body+'<p><a href="'+
        HtmlAttr(SessionUrl('/board/webhooks?id='+HTTPEncode(BoardId),Session))+'">'+HtmlEncode(Title)+'</a></p>';
      aResponse.Code:=Status;
      aResponse.ContentType:='text/html; charset=utf-8';
      aResponse.Content:=LanguagePage(aResponse,Language,Title,Body,'','html4');
      SendResponse(aResponse);
    finally Words.Free;end;
  end;

  procedure Missing;
  begin
    if Browser and Reading then ShowIntegrations(nil)
    else if Reading and (Id='') then SendJson(aResponse,'[]') else SendJson(aResponse,NotFound,404);
  end;
  procedure RejectDestination;
  begin
    if Browser then BrowserError(400,'webhook-invalid-destination','Enter a valid public HTTP or HTTPS URL.')
    else SendJson(aResponse,InvalidUrl,400);
  end;

  function ValidDestination(Value:TJSONData):Boolean;
  begin
    Result:=(Value is TJSONString) and PublicWebhookUrl(Value.AsString);
    BadUrl:=not Result;
  end;

  function StoredDocument:string;
  begin
    if Shared then
      Result:='CASE WHEN wl_storage('+QuotedStr(Source)+')=''blob'' THEN jsonb('+Encoded+') ELSE '+Encoded+' END'
    else Result:=Encoded;
  end;

  function ReadDocument(const Json:string):TJSONObject;
  begin
    if Shared then Result:=ExactObject(PlainDocument(Json)) else Result:=ExactObject(Json);
  end;

  function PrepareCreation:Boolean;
  var Input,NewDoc:TJSONObject;Value:TJSONData;Stamp:TDateTime;AtMs:Int64;
  begin
    Result:=False;Input:=nil;NewDoc:=nil;
    try
      try
        if Browser then Input:=TJSONObject.Create(['url',aRequest.ContentFields.Values['url']])
        else Input:=ExactObject(aRequest.Content);
        Value:=Input.Find('url');
        if not ValidDestination(Value) then Exit;
        Id:=NewId;
        Stamp:=LocalTimeToUniversal(Now);
        AtMs:=DateTimeToUnix(Stamp,True)*1000+MilliSecondOf(Stamp);
        NewDoc:=TJSONObject.Create(['_id',Id,'boardId',BoardId,'userId',Actor,
          'url',Value.AsString,'enabled',True,'type','outgoing-webhooks']);
        NewDoc.Add('activities',TJSONArray.Create(['all']));
        if Shared then
        begin
          NewDoc.Add('createdAt',AtMs);NewDoc.Add('modifiedAt',AtMs);
          Encoded:=QuotedStr(TypedDocument(NewDoc.AsJSON,'','{"createdAt":"date","modifiedAt":"date"}'));
        end
        else
        begin
          NewDoc.Add('createdAt',NowIso);NewDoc.Add('modifiedAt',NewDoc.Get('createdAt',''));
          Encoded:=QuotedStr(NewDoc.AsJSON);
        end;
        Result:=True;
      except Result:=False;end;
    finally Input.Free;NewDoc.Free;end;
  end;

  function UpdateStatement:Boolean;
  var Update,Original:TJSONObject;Value:TJSONData;Index,PropertyIndex:Integer;Name:string;
  begin
    Result:=False;Update:=nil;Original:=nil;
    try
      try
        Original:=ReadDocument(Raw);
        if Browser then
        begin
          Update:=TJSONObject.Create(['title',aRequest.ContentFields.Values['title'],
            'enabled',aRequest.ContentFields.Values['enabled']='1']);
          if aRequest.ContentFields.Values['url']<>Original.Get('url','') then
            Update.Add('url',aRequest.ContentFields.Values['url']);
        end
        else if aRequest.Content='' then Update:=TJSONObject.Create else Update:=ExactObject(aRequest.Content);
        for PropertyIndex:=0 to Update.Count-1 do
        begin
          Name:=Update.Names[PropertyIndex];
          Value:=Update.Find(Name);
          case Name of
            'url': if not ValidDestination(Value) then Exit;
            'title': if (not (Value is TJSONString)) or (Pos(#0,Value.AsString)>0) then Exit;
            'enabled': if not (Value is TJSONBoolean) then Exit;
            'activities':
              begin
                if not (Value is TJSONArray) then Exit;
                for Index:=0 to Value.Count-1 do
                  if not (Value.Items[Index] is TJSONString) or (Pos(#0,Value.Items[Index].AsString)>0) then Exit;
              end;
          else Exit;
          end;
        end;
        if Update.Count>0 then
        begin
          for PropertyIndex:=0 to Update.Count-1 do
          begin
            Name:=Update.Names[PropertyIndex];
            Original.Delete(Name);Original.Add(Name,Update.Find(Name).Clone);
          end;
          if Shared then Encoded:=QuotedStr(TypedDocument(Original.AsJSON,Raw,'{}'))
          else Encoded:=QuotedStr(Original.AsJSON);
          Mutation:='UPDATE '+TableName+' SET '+DocumentColumn+'='+StoredDocument+' WHERE '+Scope+'; '+
            'SELECT CASE WHEN EXISTS(SELECT 1 FROM '+TableName+' WHERE '+Scope+
            ' AND json('+DocumentColumn+')=json('+Encoded+')) THEN 1 ELSE json(''Integration update failed'') END; ';
        end;
        Result:=True;
      except Result:=False;end;
    finally Original.Free;Update.Free;end;
  end;

begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  Reading:=(aRequest.Method='GET') or (Browser and (aRequest.Method='POST') and
    (aRequest.ContentFields.Values['nav_view']='1') and
    (aRequest.ContentFields.IndexOfName('operation')<0));
  if Browser then
  begin
    if not ValidateSession(T.Db,aRequest,SessionIdFromRequest(aRequest),Session) then
    begin BrowserError(401,'log-in','Sign in');Exit;end;
    Actor:=Session.UserId;Id:='';
    if not Reading then
    begin
      BoardId:=aRequest.ContentFields.Values['boardId'];
      Id:=aRequest.ContentFields.Values['integrationId'];
      Operation:=aRequest.ContentFields.Values['operation'];
      if ((Operation='create') and (Id<>'')) or
        ((Operation<>'create') and ((Id='') or ((Operation<>'save') and (Operation<>'delete')))) or
        (Pos(#0,Id)>0) then
      begin SendError(aResponse,400,'Invalid webhook action');Exit;end;
    end
    else BoardId:=aRequest.QueryFields.Values['id'];
    if (BoardId='') or (Pos(#0,BoardId)>0) then
    begin SendError(aResponse,400,'Invalid board ID');Exit;end;
  end
  else
  begin
    if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
    BoardId:=aRequest.RouteParams['boardId'];Id:=aRequest.RouteParams['intId'];
  end;
  Creating:=(aRequest.Method='POST') and (not Browser or (Operation='create'));
  Updating:=(aRequest.Method='PUT') or (Browser and (Operation='save'));
  BadUrl:=False;
  if Browser then
  begin
    if not BoardCanRead(T.Db,Actor,BoardId) then
    begin BrowserError(403,'error-notAllowed','Board access forbidden');Exit;end;
  end
  else if not ApiAuthBoard(T,aResponse,Actor,BoardId,False) then Exit;
  Policy:=TFieldPolicy.Create(T.Db,Actor,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  Admin:=(Length(Rows)=1) and (Rows[0][0]='1');
  if (Browser or not Reading) and not Admin then
  begin
    if Browser then BrowserError(403,'error-notAllowed','Board administration required')
    else SendError(aResponse,403,'Board administration required');
    Exit;
  end;
  if Browser and not Reading and not VerifyActionToken(aRequest,Session,FormAction(Operation,Id)) then
  begin BrowserError(403,'error-notAllowed','Invalid webhook action token');Exit;end;
  // WeKan's Admin Panel / Settings / Features / Turn off all webhooks
  // (models/lib/webhooksSwitch.js): while it is on no webhook is added or
  // changed - asked after the board-admin check, so only somebody who could
  // otherwise write it is told, and recorded, as no screen offers it then. A
  // delete is the cleanup and is allowed. (WeLite sends no webhooks itself.)
  if (Creating or Updating) and SharedSettingOn(T.Db,'webhooksDisabled') then
  begin
    if Browser then Source:='html4:webhooks'
    else if Creating then Source:='rest:POST /api/boards/:boardId/integrations'
    else Source:='rest:PUT /api/boards/:boardId/integrations/:intId';
    try
      RecordSecurityEvent(T.Db,Actor,'Webhooks turned off',Source,'authz','medium','CWE-284',
        'blocked','A webhook written on board '+BoardId+' while webhooks are turned off.');
    except
      // logging must never break the guard
    end;
    if Browser then BrowserError(403,'error-notAllowed','Webhooks are turned off')
    else SendJson(aResponse,'{"error":"webhooks-disabled","reason":"Webhooks are turned off"}',403);
    Exit;
  end;
  Shared:=Length(T.Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))=1;
  if Creating and not PrepareCreation then begin RejectDestination;Exit;end;
  StorageGuard:='';
  if Shared then
  begin
    if Creating and not EnsureSharedCollection(T.Db,'integrations') then
    begin SendError(aResponse,500,'Could not prepare integration storage');Exit;end;
    Rows:=T.Db.Query('SELECT r.table_name FROM _ferretdb_collections r JOIN sqlite_master m '+
      'ON m.name=r.table_name AND m.type=''table'' WHERE r.name=''integrations'';');
    if Length(Rows)<>1 then begin Missing;Exit;end;
    Source:=Rows[0][0];TableName:='"'+StringReplace(Source,'"','""',[rfReplaceAll])+'"';
    DocumentColumn:='_ferretdb_sjson';
    Scope:='json_extract(_ferretdb_sjson,''$.boardId'')='+QuotedStr(BoardId)+
      ' AND json_extract(_ferretdb_sjson,''$.$s.p.boardId.t'')=''string'''+
      ' AND json_extract(_ferretdb_sjson,''$.$s.p._id.t'')=''string''';
    if Id<>'' then Scope:=Scope+' AND json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(Id);
    StorageGuard:=' AND (SELECT count(*) FROM _ferretdb_collections WHERE name=''integrations'''+
      ' AND table_name='+QuotedStr(Source)+')=1';
    InsertColumns:=DocumentColumn;
    if Creating then InsertValues:=StoredDocument;
  end
  else
  begin
    TableName:='integrations';DocumentColumn:='document';
    Scope:='boardId='+QuotedStr(BoardId);
    if Id<>'' then Scope:=Scope+' AND id='+QuotedStr(Id);
    InsertColumns:='id,boardId,document';
    if Creating then InsertValues:=QuotedStr(Id)+','+QuotedStr(BoardId)+','+StoredDocument;
  end;
  if Creating then
  begin
    Guard:=Permission+StorageGuard;
    Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Guard+' THEN 1 ELSE json(''Integration scope changed'') END; '+
      'INSERT INTO '+TableName+'('+InsertColumns+') VALUES ('+InsertValues+'); '+
      'SELECT CASE WHEN '+Guard+' AND (SELECT count(*) FROM '+TableName+' WHERE '+Scope+
      ' AND json('+DocumentColumn+')=json('+Encoded+'))=1 THEN 1 ELSE json(''Integration insert failed'') END; COMMIT;';
    if not T.Db.Exec(Sql) then
    begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create integration');Exit;end;
    MutationComplete;Exit;
  end;
  if not Reading then
  begin
    Rows:=T.Db.Query('SELECT json('+DocumentColumn+') FROM '+TableName+' WHERE '+Scope+';');
    if (Id='') or (Length(Rows)<>1) then begin Missing;Exit;end;
    Raw:=Rows[0][0];Mutation:='';
    if Updating then
    begin
      if not UpdateStatement then
      begin
        if BadUrl then RejectDestination
        else if Browser then BrowserError(400,'webhook-invalid-update','Invalid or unsupported webhook settings.')
        else SendJson(aResponse,'{"error":"Invalid or unsupported integration update"}',400);
        Exit;
      end;
    end
    else
      Mutation:='DELETE FROM '+TableName+' WHERE '+Scope+
        '; SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM '+TableName+' WHERE '+Scope+
        ') THEN 1 ELSE json(''Integration deletion failed'') END; ';
    Guard:=Permission+StorageGuard+' AND (SELECT count(*) FROM '+TableName+
      ' WHERE '+Scope+' AND json('+DocumentColumn+')='+QuotedStr(Raw)+')=1';
    Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Guard+' THEN 1 ELSE json(''Integration scope changed'') END; '+
      Mutation+'SELECT CASE WHEN '+Permission+' THEN 1 ELSE json(''Integration permission changed'') END; COMMIT;';
    if not T.Db.Exec(Sql) then
    begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not change integration');Exit;end;
    MutationComplete;Exit;
  end;
  if Browser then Scope:=Scope+' AND ('+Permission+')';
  Rows:=T.Db.Query('SELECT json('+DocumentColumn+') FROM '+TableName+' WHERE '+Scope+';');
  if (Id<>'') and (Length(Rows)<>1) then begin Missing;Exit;end;
  Entries:=TJSONArray.Create;
  try
    try
      for Row in Rows do
      begin
        Doc:=ReadDocument(Row[0]);
        try
          Entry:=TJSONObject.Create;Entries.Add(Entry);
          for Key in ['_id','boardId','enabled','activities','title','type','url','userId',
            'createdAt','modifiedAt','notificationDelivery'] do
          begin
            if not Admin and (Key<>'_id') and (Key<>'boardId') and (Key<>'enabled') and (Key<>'activities') then Continue;
            Field:=Doc.Find(Key);if Field<>nil then Entry.Add(Key,Field.Clone);
          end;
        finally Doc.Free;end;
      end;
      if Browser then begin ShowIntegrations(Entries);Exit;end;
      if Id<>'' then Payload:=Entries.Items[0].AsJSON else Payload:=Entries.AsJSON;
      SendJson(aResponse,Payload);
    except SendError(aResponse,500,'Could not read integrations');end;
  finally Entries.Free;end;
end;

procedure ApiIntegration(aRequest:TRequest;aResponse:TResponse);
begin HandleIntegrations(aRequest,aResponse,False);end;

procedure BrowserIntegrations(aRequest:TRequest;aResponse:TResponse);
begin
  try HandleIntegrations(aRequest,aResponse,True);
  except SendError(aResponse,500,'Could not read integrations');end;
end;

procedure ApiBoardRules(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,RuleId,Id:string;Graph,Rule,Item:TJSONObject;
  Rules,Reply,Triggers,Actions:TJSONArray;Flag:TJSONData;I:Integer;
  function Part(Parts:TJSONArray;const Key:string):TJSONData;
  var J:Integer;Entry:TJSONObject;
  begin
    Result:=nil;if Key='' then Exit;
    for J:=0 to Parts.Count-1 do
      if Parts.Objects[J].Get('_id','')=Key then
      begin
        Entry:=TJSONObject(Parts.Objects[J].Clone);
        Entry.Delete('_id');Entry.Delete('boardId');Entry.Delete('createdAt');Entry.Delete('modifiedAt');Entry.Delete('updatedAt');
        Result:=Entry;Exit;
      end;
  end;
  procedure Embed(const Name,Primary,Extra:string;Parts:TJSONArray);
  var Value,Entry:TJSONData;Items:TJSONArray;J:Integer;
  begin
    Value:=Part(Parts,Rule.Get(Primary,''));
    if Value=nil then Value:=TJSONNull.Create;
    Item.Add(Name,Value);
    Value:=Rule.Find(Extra);
    if not (Value is TJSONArray) or (Value.Count=0) then Exit;
    Items:=TJSONArray.Create;
    if Name='trigger' then Item.Add('extraTriggers',Items) else Item.Add('extraActions',Items);
    for J:=0 to Value.Count-1 do
      if Value.Items[J] is TJSONString then
      begin
        Entry:=Part(Parts,Value.Items[J].AsString);
        if Entry<>nil then Items.Add(Entry);
      end;
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];RuleId:=aRequest.RouteParams['ruleId'];
  Graph:=TJSONObject.Create;Reply:=TJSONArray.Create;
  try
    try
      if not T.Db.BeginRead then raise Exception.Create('Could not pin board rule snapshot');
      try
        if not ApiAuthBoard(T,aResponse,UserId,BoardId,False) then Exit;
        ReadExportWorkflows(T.Db,BoardId,Graph);
      finally
        if not T.Db.EndRead then raise Exception.Create('Could not close board rule snapshot');
      end;
      Rules:=TJSONArray(Graph.Find('rules'));Triggers:=TJSONArray(Graph.Find('triggers'));Actions:=TJSONArray(Graph.Find('actions'));
      for I:=0 to Rules.Count-1 do
      begin
        Rule:=Rules.Objects[I];Id:=Rule.Get('_id','');
        if (RuleId<>'') and (Id<>RuleId) then Continue;
        Flag:=Rule.Find('enabled');
        Item:=TJSONObject.Create(['_id',Id,'title',Rule.Get('title',''),
          'enabled',not ((Flag is TJSONBoolean) and not Flag.AsBoolean)]);
        Reply.Add(Item);
        Embed('trigger','triggerId','extraTriggerIds',Triggers);
        Embed('action','actionId','extraActionIds',Actions);
      end;
    except SendError(aResponse,500,'Could not read board rules');Exit;end;
    if RuleId='' then SendJson(aResponse,Reply.AsJSON)
    else if Reply.Count=1 then SendJson(aResponse,Reply.Items[0].AsJSON)
    else SendJson(aResponse,'{"error":"Rule not found"}',404);
  finally Reply.Free;Graph.Free;end;
end;

function BoardDownloadAccess(aRequest: TRequest; aResponse: TResponse; out T: TWLTenant;
  out BoardId, UserId: string; PlainNotFound: Boolean = False;
  const RouteCardId: string = ''; ScopedScrum: Boolean = False): Boolean; forward;
procedure ExcludeBoardArchive(Board: TJSONObject); forward;

function DownloadScopeId(Request: TRequest; const Key: string): string; forward;
procedure FilterBoardExportFields(Board: TJSONObject; const Fields: string); forward;
procedure ScopeBoardExport(Board: TJSONObject; const LaneId, ListId, CardId, ChecklistId: string); forward;

procedure PruneBoardExportUsers(Board: TJSONObject);
var Ids: TStringList; Rows: TJSONArray; Row: TJSONObject;
  Collection, Key: string; I: Integer;

  procedure Remember(Value: TJSONData);
  var J: Integer;
  begin
    if Value is TJSONArray then
      for J := 0 to Value.Count - 1 do Remember(Value.Items[J])
    else if Value is TJSONObject then Remember(TJSONObject(Value).Find('userId'))
    else if (Value is TJSONString) and (Value.AsString <> '') then Ids.Add(Value.AsString);
  end;

begin
  Ids := TStringList.Create;
  try
    Ids.CaseSensitive := True;
    Ids.Sorted := True;
    Ids.Duplicates := dupIgnore;
    Remember(Board.Find('members'));
    for Collection in ['lists','swimlanes','cards','subtaskItems','attachments','comments','activities','checklists','checklistItems'] do
    begin
      Rows := Board.Arrays[Collection];
      for I := 0 to Rows.Count - 1 do
      begin
        Row := Rows.Objects[I];
        Remember(Row.Find('userId'));
        if Collection = 'checklistItems' then Remember(Row.Find('assigneeId'));
        if (Collection = 'cards') or (Collection = 'subtaskItems') then
        begin
          for Key in ['members','assignees','requesters','assigners'] do Remember(Row.Find(Key));
          Remember(Row.FindPath('vote.positive'));
          Remember(Row.FindPath('vote.negative'));
        end;
      end;
    end;
    Rows := Board.Arrays['users'];
    for I := Rows.Count - 1 downto 0 do
      if Ids.IndexOf(Rows.Objects[I].Get('_id', '')) < 0 then Rows.Delete(I);
  finally
    Ids.Free;
  end;
end;

function ReadFileBytes(const Path: string): string; forward;

procedure AddFilteredExportFiles(const T: TWLTenant; Board: TJSONObject; const BoardId: string);
var Attachments: TJSONArray; Attachment: TJSONObject; I: Integer; Id, Owner, Path: string;
begin
  Attachments := Board.Arrays['attachments'];
  for I := 0 to Attachments.Count - 1 do
  begin
    Attachment := Attachments.Objects[I];
    Id := Attachment.Get('_id', '');
    if Id = '' then Continue;
    Owner := Attachment.Get('cardId', '');
    if Length(T.Db.Query('SELECT 1 FROM attachments a WHERE a.id=' + QuotedStr(Id) +
      ' AND a.boardId=' + QuotedStr(BoardId) + ' AND COALESCE(a.cardId,'''')=' + QuotedStr(Owner) +
      ' AND COALESCE(a.storageBackend,''filesystem'')=''filesystem'' AND (COALESCE(a.cardId,'''')='''' OR ' +
      'EXISTS(SELECT 1 FROM cards c WHERE c.id=a.cardId AND c.boardId=a.boardId AND c.deletedAt IS NULL));')) <> 1 then Continue;
    Path := StoreFilePath(T.FilesDir, 'attachme', Id);
    if FileExists(Path) then Attachment.Add('file', EncodeStringBase64(ReadFileBytes(Path)));
  end;
end;

procedure BoardExport(aRequest:TRequest;aResponse:TResponse;Browser:Boolean);
var T:TWLTenant;UserId,BoardId,TableName,LaneId,ListId,CardId,ChecklistId,Fields:string;Payload:TJSONObject;Rows:TWLRows;Session:TWLSession; Html5Download,Filtered,IncludeFiles,ExcludeArchive:Boolean;
begin
  Html5Download := not Browser and (aRequest.QueryFields.Values['download'] = '1');
  if Html5Download then
  begin
    if not BoardDownloadAccess(aRequest, aResponse, T, BoardId, UserId) then Exit;
  end
  else if not ApiTenant(aRequest,aResponse,T) then Exit;
  if Browser then
  begin
    if not ValidateSession(T.Db,aRequest,SessionIdFromRequest(aRequest),Session) then
    begin SendError(aResponse,401,'Sign in to download a board');Exit;end;
    UserId:=Session.UserId;BoardId:=aRequest.QueryFields.Values['id'];
    if (BoardId='') or (Pos(#0,BoardId)>0) then
    begin SendError(aResponse,400,'Invalid board ID');Exit;end;
  end else if not Html5Download then
  begin
    if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
    BoardId:=aRequest.RouteParams['boardId'];
  end;
  if not Html5Download and not ApiAuthBoard(T,aResponse,UserId,BoardId,False) then Exit;
  if Length(T.Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))=1 then
  begin
    Rows:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''settings'';');
    if Length(Rows)=1 then
    begin
      TableName:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
      Rows:=T.Db.Query('SELECT count(*) FROM '+TableName+' WHERE json_type(_ferretdb_sjson,''$.disableAllExport'')=''true'''+
        ' OR json_type(_ferretdb_sjson,''$.anonymizeExportUsers'')=''true'';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'0') then
      begin SendError(aResponse,403,'Board export restricted by instance settings');Exit;end;
    end else if Length(Rows)>1 then
    begin SendError(aResponse,500,'Ambiguous export settings source');Exit;end;
  end;
  LaneId := DownloadScopeId(aRequest, 'swimlaneId');
  ListId := DownloadScopeId(aRequest, 'listId');
  CardId := DownloadScopeId(aRequest, 'cardId');
  ChecklistId := DownloadScopeId(aRequest, 'checklistId');
  Fields := aRequest.QueryFields.Values['fields'];
  ExcludeArchive := aRequest.QueryFields.Values['archived'] = 'false';
  Filtered := ExcludeArchive or (Fields <> '') or (LaneId <> '') or (ListId <> '') or
    (CardId <> '') or (ChecklistId <> '');
  IncludeFiles := aRequest.QueryFields.Values['attachments'] <> 'false';
  try
    Payload:=ReadRestBoardExport(T,UserId,BoardId,IncludeFiles and not Filtered,Html5Download);
  except SendError(aResponse,500,'Could not export board');Exit;end;
  if Payload=nil then begin SendError(aResponse,403,'Board export forbidden');Exit;end;
  try
    try
      if ExcludeArchive then ExcludeBoardArchive(Payload);
      ScopeBoardExport(Payload, LaneId, ListId, CardId, ChecklistId);
      if Fields <> '' then FilterBoardExportFields(Payload, Fields);
      if Filtered then PruneBoardExportUsers(Payload);
      if Filtered and IncludeFiles then AddFilteredExportFiles(T, Payload, BoardId);
    except SendError(aResponse,500,'Could not scope board export');Exit;end;
    if Browser or Html5Download then
    begin
      aResponse.SetCustomHeader('Content-Disposition','attachment; filename="board.json"');
      aResponse.SetCustomHeader('Cache-Control','private, no-store');
      aResponse.SetCustomHeader('Referrer-Policy','no-referrer');
    end;
    SendJson(aResponse,Payload.AsJSON);
  finally Payload.Free;end;
end;

procedure ApiBoardExport(aRequest:TRequest;aResponse:TResponse);
begin BoardExport(aRequest,aResponse,False);end;

procedure BrowserBoardExport(aRequest:TRequest;aResponse:TResponse);
begin BoardExport(aRequest,aResponse,True);end;

procedure DownloadNotFound(Response: TResponse; const MessageText: RawByteString; Plain: Boolean);
begin
  if not Plain then begin SendError(Response, 404, MessageText); Exit; end;
  Response.Code := 404;
  Response.ContentType := 'text/plain; charset=utf-8';
  Response.Content := MessageText;
  Response.ContentLength := Length(MessageText);
  Response.SendContent;
end;

function DownloadCardExists(Db: TWLDb; const BoardId, ListId, CardId: string): Boolean;
begin
  Result := False;
  if (ListId = '') or (Pos(#0, ListId + CardId) > 0) then Exit;
  Result := Length(Db.Query('SELECT 1 FROM cards WHERE id=' + QuotedStr(CardId) +
    ' AND boardId=' + QuotedStr(BoardId) + ' AND listId=' + QuotedStr(ListId) +
    ' AND deletedAt IS NULL AND COALESCE(linkedId,'''')='''';')) = 1;
end;

function BoardDownloadAccess(aRequest: TRequest; aResponse: TResponse; out T: TWLTenant;
  out BoardId, UserId: string; PlainNotFound: Boolean;
  const RouteCardId: string; ScopedScrum: Boolean): Boolean;
var Board: TWLRows; Session: TWLSession;

begin
  Result := False;
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if SharedSettingOn(T.Db, 'disableAllExport') or SharedSettingOn(T.Db, 'anonymizeExportUsers') then
  begin SendError(aResponse, 403, 'Board export restricted by instance settings'); Exit; end;
  BoardId := aRequest.RouteParams['boardId'];
  if (BoardId = '') or (Pos(#0, BoardId) > 0) then
  begin DownloadNotFound(aResponse, 'Board not found', PlainNotFound); Exit; end;
  Board := T.Db.Query('SELECT permission FROM boards WHERE id=' + QuotedStr(BoardId) + ' AND archived=0;');
  if Length(Board) <> 1 then begin DownloadNotFound(aResponse, 'Board not found', PlainNotFound); Exit; end;
  if (RouteCardId <> '') and not DownloadCardExists(T.Db, BoardId, aRequest.RouteParams['listId'], RouteCardId) then
  begin DownloadNotFound(aResponse, 'Card not found', PlainNotFound); Exit; end;
  UserId := '';
  if (aRequest.Authorization <> '') or (aRequest.QueryFields.Values['authToken'] <> '') or
    (aRequest.QueryFields.Values['token'] <> '') then
  begin
    if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  end
  else if Html5User(T.Db, aRequest, Session) or
    ValidateSession(T.Db, aRequest, SessionIdFromRequest(aRequest), Session) then UserId := Session.UserId;
  if Board[0][0] <> 'public' then
  begin
    if UserId = '' then begin SendError(aResponse, 401, 'Sign in to download a board'); Exit; end;
    if not BoardHasMember(T.Db, UserId, BoardId) or (not ScopedScrum and AssignedOnlyMember(T.Db, UserId, BoardId)) then
    begin SendError(aResponse, 403, 'Board access forbidden'); Exit; end;
  end;
  Result := True;
end;

procedure ApiBoardCsv(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; BoardId, UserId, Separator: string; Payload: TJSONObject; Output: TMemoryStream;
begin
  if not BoardDownloadAccess(aRequest, aResponse, T, BoardId, UserId) then Exit;
  try
    Payload := ReadRestBoardExport(T, UserId, BoardId, False, True);
  except SendError(aResponse, 500, 'Could not export board'); Exit; end;
  if Payload = nil then begin SendError(aResponse, 403, 'Board export forbidden'); Exit; end;
  Output := TMemoryStream.Create;
  try
    Separator := aRequest.QueryFields.Values['delimiter'];
    if (Length(Separator) <> 1) or (Separator[1] in [#0,#10,#13,'"']) then Separator := ',';
    try
      WriteBoardCsv(Output, Payload, aRequest.QueryFields.Values['fields'], Separator);
    except SendError(aResponse, 500, 'Could not export board'); Exit; end;
    aResponse.Code := 200;
    if Separator = #9 then
    begin
      aResponse.ContentType := 'text/tsv; charset=utf-8';
      aResponse.SetCustomHeader('Content-Disposition', 'attachment; filename="board.tsv"');
    end
    else
    begin
      aResponse.ContentType := 'text/csv; charset=utf-8';
      aResponse.SetCustomHeader('Content-Disposition', 'attachment; filename="board.csv"');
    end;
    aResponse.SetCustomHeader('Cache-Control', 'private, no-store');
    aResponse.SetCustomHeader('Referrer-Policy', 'no-referrer');
    Output.Position := 0;
    aResponse.ContentLength := Output.Size;
    aResponse.ContentStream := Output;
    try aResponse.SendContent; finally aResponse.ContentStream := nil; end;
  finally Output.Free; Payload.Free; end;
end;

function DownloadScopeId(Request: TRequest; const Key: string): string;
var C: Char;
begin
  Result := Request.QueryFields.Values[Key];
  if Length(Result) > 64 then Exit('');
  for C in Result do
    if not (C in ['a'..'z', 'A'..'Z', '0'..'9', '_', '-']) then Exit('');
end;

procedure ApiScrumVelocityReport(aRequest: TRequest; aResponse: TResponse);
const Groups: array[0..5] of string = ('committed','completed','added','removed','incomplete','completedCommitment');
type TTotals = record
  Count, Unknown: Integer;
  Estimate: Double;
end;
var T: TWLTenant; Session: TWLSession; Words: TWLTranslator; BoardId, UserId, SprintTable, ChunkTable, PendingTable,
  Scope, Name, Caption, Filename, EstimateField: string; Restricted, AsPdf, Admin: Boolean;
  Report, Header, Row, StartRows, CloseRows: TJSONArray; Sprint: TJSONObject; CloseSnap: TJSONData;
  Sprints, Cards: TWLRows; Raw: TWLRow; Totals: array[0..5] of TTotals; I: Integer;
  Visible, StartIds, CloseIds, DoneIds: TStringList; Output: TMemoryStream;
  function Collection(const Name: string): string;
  var Rows: TWLRows;
  begin
    Result := '';
    if not IsShared(T.Db) then Exit;
    Rows := T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=' + QuotedStr(Name));
    if Length(Rows)=1 then Result := '"' + StringReplace(Rows[0][0], '"', '""', [rfReplaceAll]) + '"';
  end;
  function Snapshot(const Key, Kind: string): TJSONArray;
  var Data, Part: TJSONData; Snap, Chunk: TJSONObject; Chunks: TWLRows; N, J: Integer; Expected: TJSONData;
  begin
    Result := TJSONArray.Create;
    try
      Data := Sprint.Find(Key);
      if not (Data is TJSONObject) then Exit;
      Snap := TJSONObject(Data);
      if Snap.Get('stored','') <> 'rows' then
      begin
        Data := Snap.Find('cards');
        if Data is TJSONArray then
          for J:=0 to Data.Count-1 do if Data.Items[J] is TJSONObject then Result.Add(Data.Items[J].Clone);
        Exit;
      end;
      Chunks := nil;
      Expected := Snap.Find('at');
      if (ChunkTable<>'') and (Expected<>nil) then
        Chunks := T.Db.Query('SELECT json(_ferretdb_sjson) FROM ' + ChunkTable +
          ' WHERE json_extract(_ferretdb_sjson,''$.boardId'')=' + QuotedStr(BoardId) +
          ' AND json_extract(_ferretdb_sjson,''$.sprintId'')=' + QuotedStr(Sprint.Get('_id','')) +
          ' AND json_extract(_ferretdb_sjson,''$.kind'')=' + QuotedStr(Kind) +
          ' AND json_extract(_ferretdb_sjson,''$.at'')=(SELECT json_extract(_ferretdb_sjson,' +
          QuotedStr('$.'+Key+'.at') + ') FROM '+SprintTable+' WHERE json_extract(_ferretdb_sjson,''$._id'')=' +
          QuotedStr(Sprint.Get('_id','')) + ') ORDER BY CAST(COALESCE(json_extract(_ferretdb_sjson,''$.chunk.$i''),' +
          'json_extract(_ferretdb_sjson,''$.chunk'')) AS INTEGER);');
      if Length(Chunks)<>Snap.Get('chunks',-1) then raise Exception.Create('Incomplete sprint snapshot');
      for N:=0 to High(Chunks) do
      begin
        Chunk:=ExactObject(PlainDocument(Chunks[N][0]));
        try
          Part:=Chunk.Find('rows');
          if (Chunk.Get('chunk',-1)<>N) or not (Part is TJSONArray) then raise Exception.Create('Incomplete sprint snapshot');
          for J:=0 to Part.Count-1 do if Part.Items[J] is TJSONObject then Result.Add(Part.Items[J].Clone);
        finally Chunk.Free; end;
      end;
      if Result.Count<>Snap.Get('rowCount',-1) then raise Exception.Create('Incomplete sprint snapshot');
    except Result.Free; raise; end;
  end;
  function CanCount(const Id: string): Boolean;
  begin
    Result := not Restricted or (Visible.IndexOf(Id)>=0);
  end;
  procedure AddTotal(Group: Integer; Card: TJSONObject);
  var Estimate: TJSONData;
  begin
    Inc(Totals[Group].Count);
    Estimate := Card.Find('estimate');
    if (Estimate<>nil) and (Estimate.JSONType=jtNumber) and (Estimate.AsFloat>=0) then
      Totals[Group].Estimate := Totals[Group].Estimate+Estimate.AsFloat
    else Inc(Totals[Group].Unknown);
  end;
  function SnapshotField(const Field: string): string;
  var StartSnap: TJSONData;
  begin
    Result:=TJSONObject(CloseSnap).Get(Field,'');
    if Result<>'' then Exit;
    StartSnap:=Sprint.Find('startSnapshot');
    if StartSnap is TJSONObject then Result:=TJSONObject(StartSnap).Get(Field,'');
  end;
  procedure AddSprint;
  var J: Integer; Card: TJSONObject; Id: string;
  begin
    FillChar(Totals,SizeOf(Totals),0);
    StartIds.Clear; CloseIds.Clear; DoneIds.Clear;
    for J:=0 to StartRows.Count-1 do
    begin
      Card:=StartRows.Objects[J]; Id:=Card.Get('cardId','');
      if not CanCount(Id) then Continue;
      StartIds.Add(Id);
      AddTotal(0,Card);
    end;
    for J:=0 to CloseRows.Count-1 do
    begin
      Card:=CloseRows.Objects[J]; Id:=Card.Get('cardId','');
      if not CanCount(Id) then Continue;
      CloseIds.Add(Id);
      if Card.Get('done',False) then begin DoneIds.Add(Id); AddTotal(1,Card); end
      else AddTotal(4,Card);
      if StartIds.IndexOf(Id)<0 then AddTotal(2,Card);
    end;
    for J:=0 to StartRows.Count-1 do
    begin
      Card:=StartRows.Objects[J]; Id:=Card.Get('cardId','');
      if not CanCount(Id) then Continue;
      if CloseIds.IndexOf(Id)<0 then AddTotal(3,Card);
      if DoneIds.IndexOf(Id)>=0 then AddTotal(5,Card);
    end;
    EstimateField:=SnapshotField('estimateCustomFieldId');
    if (SnapshotField('estimateSource')='customField') and ((EstimateField='') or
      (Length(T.Db.Query('SELECT 1 FROM custom_fields f JOIN custom_field_boards x ON x.customFieldId=f.id ' +
      'WHERE x.boardId='+QuotedStr(BoardId)+' AND f.id='+QuotedStr(EstimateField) +
      IfThen(Admin,'',' AND COALESCE(f.adminOnly,1)=0')))<>1)) then
      raise Exception.Create('Sprint estimate field is inaccessible');
    Name:=Sprint.Get('name','');
    if Restricted then Name:=Name+' — '+Words.Text('scrum-partial-snapshot','Partial snapshot');
    if AsPdf then
    begin
      Report.Add(TJSONArray.Create([Name,SnapshotField('unit')]));
      for J:=0 to High(Totals) do
      begin
        Caption:=Words.Text('scrum-'+Groups[J],Groups[J]);
        if J=High(Groups) then Caption:=Words.Text('scrum-completed','Completed')+' / '+Words.Text('scrum-committed','Committed');
        Report.Add(TJSONArray.Create([Caption, Format('%d / %.2f / %d',[Totals[J].Count,Totals[J].Estimate,Totals[J].Unknown])]));
      end;
      Exit;
    end;
    Row:=TJSONArray.Create([Name,SnapshotField('unit')]);
    for J:=0 to High(Totals) do
    begin
      Row.Add(Totals[J].Count); Row.Add(Totals[J].Estimate); Row.Add(Totals[J].Unknown);
    end;
    Report.Add(Row);
  end;
begin
  if not BoardDownloadAccess(aRequest,aResponse,T,BoardId,UserId,True,'',True) then Exit;
  Restricted:=AssignedOnlyMember(T.Db,UserId,BoardId);
  AsPdf:=AnsiEndsStr('/exportPDF',aRequest.PathInfo);
  Admin:=Length(T.Db.Query('SELECT 1 FROM board_members WHERE boardId='+QuotedStr(BoardId)+
    ' AND userId='+QuotedStr(UserId)+' AND isActive=1 AND isAdmin=1'))=1;
  if not Admin and (Length(T.Db.Query('SELECT 1 FROM custom_fields f JOIN custom_field_boards x ON x.customFieldId=f.id ' +
    'WHERE x.boardId='+QuotedStr(BoardId)+' AND COALESCE(f.adminOnly,1)<>0 LIMIT 1'))>0) then
  begin SendError(aResponse,403,'This export requires board administrator access'); Exit; end;
  SprintTable:=Collection('scrumSprints');
  ChunkTable:=Collection('scrumSnapshotRows');
  PendingTable:=Collection('scrumImportPending');
  if (PendingTable<>'') and (Length(T.Db.Query('SELECT 1 FROM '+PendingTable+
    ' WHERE json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(BoardId)))>0) then
  begin SendError(aResponse,409,'The Scrum import is incomplete. Report exports are unavailable.'); Exit; end;
  Session:=Default(TWLSession); Session.UserId:=UserId;
  Words:=TWLTranslator.Create(ViewerLanguage(T.Db,Session,aRequest));
  Report:=TJSONArray.Create;
  Output:=TMemoryStream.Create;
  Visible:=TStringList.Create; StartIds:=TStringList.Create; CloseIds:=TStringList.Create; DoneIds:=TStringList.Create;
  try
    Visible.Sorted:=True; Visible.CaseSensitive:=True;
    StartIds.Sorted:=True; StartIds.CaseSensitive:=True;
    CloseIds.Sorted:=True; CloseIds.CaseSensitive:=True;
    DoneIds.Sorted:=True; DoneIds.CaseSensitive:=True;
    if Restricted then
    begin
      Scope:='SELECT c.id FROM cards c JOIN card_assignees a ON a.cardId=c.id WHERE c.boardId='+QuotedStr(BoardId)+
        ' AND c.deletedAt IS NULL AND a.userId='+QuotedStr(UserId);
      Cards:=T.Db.Query(Scope);
      for Raw in Cards do Visible.Add(Raw[0]);
    end;
    Header:=TJSONArray.Create([Words.Text('scrum-sprint','Sprint'),Words.Text('scrum-estimate-unit','Estimate unit')]);
    Report.Add(Header);
    for I:=0 to High(Groups) do
    begin
      Caption:=Words.Text('scrum-'+Groups[I],Groups[I]);
      if I=High(Groups) then Caption:=Words.Text('scrum-completed','Completed')+' / '+Words.Text('scrum-committed','Committed');
      Header.Add(Caption+': '+Words.Text('cards','Cards'));
      Header.Add(Caption+': '+Words.Text('scrum-estimate','Estimate'));
      Header.Add(Caption+': '+Words.Text('scrum-unknown-estimate','Unknown estimate'));
    end;
    try
      if SprintTable<>'' then
      begin
        Sprints:=T.Db.Query('SELECT json(_ferretdb_sjson) FROM '+SprintTable+' WHERE json_extract(_ferretdb_sjson,''$.boardId'')='+
          QuotedStr(BoardId)+' AND json_extract(_ferretdb_sjson,''$.state'')=''closed'' ORDER BY '+
          'COALESCE(json_extract(_ferretdb_sjson,''$.closeSnapshot.at.$d''),json_extract(_ferretdb_sjson,''$.closeSnapshot.at'')), '+
          'json_extract(_ferretdb_sjson,''$._id'');');
        for Raw in Sprints do
        begin
          Sprint:=ExactObject(PlainDocument(Raw[0]));
          try
            CloseSnap:=Sprint.Find('closeSnapshot');
            if not (CloseSnap is TJSONObject) then Continue;
            StartRows:=Snapshot('startSnapshot','start');
            try
              CloseRows:=Snapshot('closeSnapshot','close');
              try AddSprint; finally CloseRows.Free; end;
            finally StartRows.Free; end;
          finally Sprint.Free; end;
        end;
      end;
      WriteBoardDocument(Output,nil,'',True,nil,'','',nil,False,AsPdf,Report);
    except SendError(aResponse,409,'Could not export Scrum velocity report'); Exit; end;
    if AsPdf then begin Filename:='scrumVelocity.pdf'; aResponse.ContentType:='application/pdf'; end
    else begin Filename:='scrumVelocity.xlsx'; aResponse.ContentType:='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'; end;
    aResponse.Code:=200;
    aResponse.SetCustomHeader('Content-Disposition','attachment; filename="'+Filename+'"');
    aResponse.SetCustomHeader('Cache-Control','private, no-store');
    aResponse.SetCustomHeader('Referrer-Policy','no-referrer');
    Output.Position:=0; aResponse.ContentLength:=Output.Size; aResponse.ContentStream:=Output;
    try aResponse.SendContent; finally aResponse.ContentStream:=nil; end;
  finally DoneIds.Free; CloseIds.Free; StartIds.Free; Visible.Free; Output.Free; Report.Free; Words.Free; end;
end;

procedure ApiBoardBurnReport(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; Session: TWLSession; Words: TWLTranslator; BoardId, UserId, Filename: string;
  AsPdf, Burnup: Boolean; Rows: TWLRows; Row: TWLRow; Report: TJSONArray; Output: TMemoryStream;
begin
  if not BoardDownloadAccess(aRequest, aResponse, T, BoardId, UserId, True, '') then Exit;
  if AssignedOnlyMember(T.Db, UserId, BoardId) then
  begin SendError(aResponse, 403, 'Board access forbidden'); Exit; end;
  AsPdf := AnsiEndsStr('/exportPDF', aRequest.PathInfo);
  Burnup := Pos('/charts/burnup/', aRequest.PathInfo) > 0;
  Filename := IfThen(Burnup, 'burnup', 'burndown');
  Session := Default(TWLSession);
  Session.UserId := UserId;
  Words := TWLTranslator.Create(ViewerLanguage(T.Db, Session, aRequest));
  Report := TJSONArray.Create;
  Output := TMemoryStream.Create;
  try
    if Burnup then
      Report.Add(TJSONArray.Create([Words.Text('date', 'Date'), Words.Text('total', 'Total'), Words.Text('completed', 'Completed')]))
    else
      Report.Add(TJSONArray.Create([Words.Text('date', 'Date'), Words.Text('board-view-burndown', 'Burndown'), 'Ideal']));
    Rows := T.Db.Query('WITH RECURSIVE records AS (SELECT COALESCE(date(createdAt),date(''now'')) AS created,' +
      'COALESCE(date(endAt),date(archivedAt)) AS done FROM cards WHERE deletedAt IS NULL AND boardId=' + QuotedStr(BoardId) + '), ' +
      'events AS (SELECT day,sum(created) AS created,sum(done) AS done FROM (' +
      'SELECT created AS day,count(*) AS created,0 AS done FROM records GROUP BY created UNION ALL ' +
      'SELECT done,0,count(*) FROM records WHERE done IS NOT NULL GROUP BY done) GROUP BY day), ' +
      'bounds AS (SELECT min(COALESCE(min(created),date(''now'')),date(''now'')) AS first,date(''now'') AS last FROM records), ' +
      'days(day) AS (SELECT first FROM bounds UNION ALL SELECT date(day,''+1 day'') FROM days,bounds WHERE day<last), ' +
      'series AS (SELECT day,sum(COALESCE(created,0)) OVER(ORDER BY day) AS total,' +
      'sum(COALESCE(done,0)) OVER(ORDER BY day) AS completed,first_value(COALESCE(created,0)) OVER(ORDER BY day) AS initial ' +
      'FROM days LEFT JOIN events USING(day)) ' +
      'SELECT day,total,completed,max(0,total-completed),COALESCE(round(initial * (julianday(last)-julianday(day))' +
      '/NULLIF(julianday(last)-julianday(first),0),2),0) FROM series,bounds ORDER BY day;');
    for Row in Rows do
      if Burnup then Report.Add(TJSONArray.Create([Row[0], GetJSON(Row[1]), GetJSON(Row[2])]))
      else Report.Add(TJSONArray.Create([Row[0], GetJSON(Row[3]), GetJSON(Row[4])]));
    try
      WriteBoardDocument(Output, nil, '', True, nil, '', '', nil, False, AsPdf, Report);
    except SendError(aResponse, 500, 'Could not export chart'); Exit; end;
    if AsPdf then
    begin
      Filename := Filename + '.pdf';
      aResponse.ContentType := 'application/pdf';
    end
    else
    begin
      Filename := Filename + '.xlsx';
      aResponse.ContentType := 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    end;
    aResponse.Code := 200;
    aResponse.SetCustomHeader('Content-Disposition', 'attachment; filename="' + Filename + '"');
    aResponse.SetCustomHeader('Cache-Control', 'private, no-store');
    aResponse.SetCustomHeader('Referrer-Policy', 'no-referrer');
    Output.Position := 0;
    aResponse.ContentLength := Output.Size;
    aResponse.ContentStream := Output;
    try aResponse.SendContent; finally aResponse.ContentStream := nil; end;
  finally Output.Free; Report.Free; Words.Free; end;
end;

procedure ApiBoardTimeReport(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; Session: TWLSession; Words: TWLTranslator;
  BoardId, UserId, Filename, CardId, Author: string; AsPdf: Boolean;
  Report, Adjustments: TJSONArray; Row: TJSONObject; Output: TMemoryStream;
  Person, Totals: TWLRows; I: Integer;
  Breakdown:TJSONObject; Section:TJSONArray; Key:string;
const Sections:array[0..1] of string=('assignees','card');
begin
  if not BoardDownloadAccess(aRequest, aResponse, T, BoardId, UserId, True, '') then Exit;
  if AssignedOnlyMember(T.Db, UserId, BoardId) then
  begin SendError(aResponse, 403, 'Board access forbidden'); Exit; end;
  Session := Default(TWLSession);
  Session.UserId := UserId;
  Words := TWLTranslator.Create(ViewerLanguage(T.Db, Session, aRequest));
  Report := TJSONArray.Create;
  Output := TMemoryStream.Create;
  try
    Report.Add(TJSONArray.Create([Words.Text('board-view-time', 'Time')]));
    Totals := T.Db.Query('SELECT COALESCE(SUM(spentTime),0) FROM cards WHERE boardId=' + QuotedStr(BoardId) +
      ' AND archived=0 AND deletedAt IS NULL;');
    if Length(Totals) = 1 then
      Report.Add(TJSONArray.Create([Words.Text('spent-time-hours', 'Spent time (hours)'), GetJSON(Totals[0][0])]));
    Breakdown:=TimeBreakdown(T.Db,Words,BoardId,'');
    try
      Report.Add(Breakdown.Find('remaining').Clone);
      for Key in Sections do
      begin
        Section:=Breakdown.Arrays[Key];
        if Section.Count=0 then Continue;
        Report.Add(TJSONArray.Create([Words.Text(Key,Key)]));
        Report.Add(TJSONArray.Create([Words.Text('name','Name'),Words.Text('hours','Hours')]));
        for I:=0 to Section.Count-1 do Report.Add(Section.Items[I].Clone);
      end;
    finally Breakdown.Free;end;
    Report.Add(TJSONArray.Create([Words.Text('time-adjustments', 'Time adjustments by author')]));
    Report.Add(TJSONArray.Create([Words.Text('time-adjustment-note', 'Changes to recorded hours.')]));
    Report.Add(TJSONArray.Create([Words.Text('card', 'Card'), Words.Text('username', 'Username'), UTF8String(#$CE#$94),
      Words.Text('spent-time-hours', 'Spent time (hours)')]));
    Adjustments := TimeAdjustmentRows(T.Db, UserId, BoardId);
    try
      for I := 0 to Adjustments.Count - 1 do
      begin
        Row := Adjustments.Objects[I];
        CardId := Row.Get('title', '');
        Author := Row.Get('userId', '');
        Person := T.Db.Query('SELECT username FROM users WHERE id=' + QuotedStr(Author) + ';');
        if Length(Person) = 1 then Author := Person[0][0];
        Report.Add(TJSONArray.Create([CardId, Author, Row.Find('delta').Clone, Row.Find('value').Clone]));
      end;
    finally Adjustments.Free; end;
    AsPdf := AnsiEndsStr('/exportPDF', aRequest.PathInfo);
    try
      WriteBoardDocument(Output, nil, '', True, nil, '', '', nil, False, AsPdf, Report);
    except SendError(aResponse, 500, 'Could not export time report'); Exit; end;
    if AsPdf then
    begin
      Filename := 'time.pdf';
      aResponse.ContentType := 'application/pdf';
    end
    else
    begin
      Filename := 'time.xlsx';
      aResponse.ContentType := 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    end;
    aResponse.Code := 200;
    aResponse.SetCustomHeader('Content-Disposition', 'attachment; filename="' + Filename + '"');
    aResponse.SetCustomHeader('Cache-Control', 'private, no-store');
    aResponse.SetCustomHeader('Referrer-Policy', 'no-referrer');
    Output.Position := 0;
    aResponse.ContentLength := Output.Size;
    aResponse.ContentStream := Output;
    try aResponse.SendContent; finally aResponse.ContentStream := nil; end;
  finally Output.Free; Report.Free; Words.Free; end;
end;

procedure ApiBoardDocument(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; BoardId, UserId, CardId, ChecklistId, LaneId, ListId, RouteCardId, RouteListId, Filename: string;
  Payload, Card, Checklist: TJSONObject; Cards, Checklists, OtherCards: TJSONArray;
  Output: TMemoryStream; I: Integer; Matches, Scoped, SingleCard, AsPdf: Boolean;
  function LoadPreview(Attachment: TJSONObject; Target: TStream; out Size: TPoint): Boolean;
  var Mime, Id, OutputType: string; Metadata: TWLRows;
  begin
    Result := False;
    Mime := Attachment.Get('type', '');
    if not SupportsAttachmentThumbnail(Mime) then Exit;
    Id := Attachment.Get('_id', '');
    if Id = '' then Exit;
    Metadata := T.Db.Query('SELECT 1 FROM attachments a JOIN cards c ON c.id=a.cardId AND c.boardId=a.boardId ' +
      'WHERE a.id=' + QuotedStr(Id) + ' AND a.boardId=' + QuotedStr(BoardId) +
      ' AND a.cardId=' + QuotedStr(Attachment.Get('cardId', '')) +
      ' AND a.type=' + QuotedStr(Mime) +
      ' AND c.archived=0 AND c.deletedAt IS NULL AND COALESCE(a.storageBackend,''filesystem'')=''filesystem'';');
    if Length(Metadata) <> 1 then Exit;
    Result := RenderAttachmentThumbnail(Target, StoreFilePath(T.FilesDir, 'attachme', Id), Mime, False, Size, OutputType);
  end;

begin
  RouteCardId := aRequest.RouteParams['cardId'];
  RouteListId := aRequest.RouteParams['listId'];
  SingleCard := RouteCardId <> '';
  AsPdf := AnsiEndsStr('/exportPDF', aRequest.PathInfo);
  if not BoardDownloadAccess(aRequest, aResponse, T, BoardId, UserId, True, RouteCardId) then Exit;
  if SingleCard then
  begin
    CardId := RouteCardId;
    Filename := 'card';
  end
  else
  begin
    CardId := DownloadScopeId(aRequest, 'cardId');
    ChecklistId := DownloadScopeId(aRequest, 'checklistId');
    LaneId := DownloadScopeId(aRequest, 'swimlaneId');
    ListId := DownloadScopeId(aRequest, 'listId');
    Filename := 'board';
  end;
  Scoped := (CardId <> '') or (ChecklistId <> '') or (LaneId <> '') or (ListId <> '');
  try
    Payload := ReadRestBoardExport(T, UserId, BoardId, False, True, True);
  except SendError(aResponse, 500, 'Could not export board'); Exit; end;
  if Payload = nil then begin SendError(aResponse, 403, 'Board export forbidden'); Exit; end;
  Output := TMemoryStream.Create;
  OtherCards := nil;
  try
    if Scoped then
    begin
      if (CardId = '') and (ChecklistId <> '') then
      begin
        Checklists := Payload.Arrays['checklists'];
        for I := Checklists.Count - 1 downto 0 do
        begin
          Checklist := Checklists.Objects[I];
          if Checklist.Get('_id', '') = ChecklistId then CardId := Checklist.Get('cardId', '')
          else Checklists.Delete(I);
        end;
      end;
      OtherCards := TJSONArray.Create;
      Cards := Payload.Arrays['cards'];
      for I := Cards.Count - 1 downto 0 do
      begin
        Card := Cards.Objects[I];
        if CardId <> '' then Matches := Card.Get('_id', '') = CardId
        else Matches := (ChecklistId = '') and
          ((LaneId = '') or (Card.Get('swimlaneId', '') = LaneId)) and
          ((ListId = '') or (Card.Get('listId', '') = ListId));
        if SingleCard then Matches := Matches and (Card.Get('listId', '') = RouteListId);
        if not Matches or (Card.Get('linkedId', '') <> '') then OtherCards.Insert(0, Cards.Extract(I));
      end;
      if SingleCard and (Cards.Count <> 1) then
      begin DownloadNotFound(aResponse, 'Card not found', True); Exit; end;
    end;
    try
      if (CardId <> '') or (ChecklistId <> '') then
      begin
        LaneId := '';
        ListId := '';
      end;
      WriteBoardDocument(Output, Payload, aRequest.QueryFields.Values['fields'], Scoped, OtherCards, LaneId, ListId, @LoadPreview, SingleCard, AsPdf);
    except SendError(aResponse, 500, 'Could not export board'); Exit; end;
    aResponse.Code := 200;
    if AsPdf then
    begin
      Filename := Filename + '.pdf';
      aResponse.ContentType := 'application/pdf';
    end
    else
    begin
      Filename := Filename + '.xlsx';
      aResponse.ContentType := 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    end;
    aResponse.SetCustomHeader('Content-Disposition', 'attachment; filename="' + Filename + '"');
    aResponse.SetCustomHeader('Cache-Control', 'private, no-store');
    aResponse.SetCustomHeader('Referrer-Policy', 'no-referrer');
    Output.Position := 0;
    aResponse.ContentLength := Output.Size;
    aResponse.ContentStream := Output;
    try aResponse.SendContent; finally aResponse.ContentStream := nil; end;
  finally OtherCards.Free; Output.Free; Payload.Free; end;
end;

procedure FilterBoardExportFields(Board: TJSONObject; const Fields: string);
const Known = '|card-details|board-header|activities|labels|people|board-info|dates|' +
  'description|custom-fields|checklists|subtasks|comments|attachments|voting|poker|stickers|locations|dependencies|sort|scrum|';
var Selected: TStringList; Part, Key: string; Rows: TJSONArray; I: Integer;

  function CheckedArray(const Name: string): TJSONArray;
  var Value: TJSONData;
  begin
    Value := Board.Find(Name);
    if not (Value is TJSONArray) then
      raise EConvertError.Create('Invalid board export array');
    Result := TJSONArray(Value);
  end;

  procedure RemoveCardFields(const PartName: string; const Keys: array of string);
  var J: Integer; FieldName, CollectionName: string; ChildRows: TJSONArray;
    Card: TJSONObject; Parents: TJSONData; PreserveCompletion: Boolean;
  begin
    if Selected.IndexOf(PartName) >= 0 then Exit;
    for CollectionName in ['cards','subtaskItems'] do
    begin
      ChildRows := CheckedArray(CollectionName);
      for J := 0 to ChildRows.Count - 1 do
      begin
        if not (ChildRows.Items[J] is TJSONObject) then
          raise EConvertError.Create('Invalid board export row');
        Card := ChildRows.Objects[J];
        // dueComplete also represents completion in the parent's Subtasks list.
        Parents := Card.Find('parentIds');
        PreserveCompletion := (PartName = 'dates') and (Selected.IndexOf('subtasks') >= 0) and
          ((CollectionName = 'subtaskItems') or (Card.Get('parentId', '') <> '') or
          ((Parents is TJSONArray) and (Parents.Count > 0)));
        for FieldName in Keys do
          if (FieldName <> 'dueComplete') or not PreserveCompletion then Card.Delete(FieldName);
      end;
    end;
  end;

begin
  Selected := TStringList.Create;
  try
    Selected.CaseSensitive := True;
    for Part in Fields.Split([',']) do
    begin
      Key := Trim(Part);
      if (Key <> '') and (Pos('|', Key) = 0) and (Pos('|' + Key + '|', Known) > 0) then Selected.Add(Key);
    end;
    if Selected.Count = 0 then Exit;
    for Key in ['activities','attachments','comments','checklists'] do
      if Selected.IndexOf(Key) < 0 then CheckedArray(Key).Clear;
    if Selected.IndexOf('checklists') < 0 then CheckedArray('checklistItems').Clear;
    if Selected.IndexOf('custom-fields') < 0 then CheckedArray('customFields').Clear;
    if Selected.IndexOf('labels') < 0 then Board.Delete('labels');
    if Selected.IndexOf('subtasks') < 0 then CheckedArray('subtaskItems').Clear;
    RemoveCardFields('description', ['description']);
    RemoveCardFields('custom-fields', ['customFields']);
    RemoveCardFields('labels', ['labelIds']);
    RemoveCardFields('people', ['members','assignees','requesters','assigners','requestedBy','assignedBy']);
    RemoveCardFields('dates', ['modifiedAt','dateLastActivity','receivedAt','startAt','dueAt','endAt',
      'dueComplete','spentTime','isOvertime','isOverTime']);
    RemoveCardFields('voting', ['vote']);
    RemoveCardFields('poker', ['poker']);
    RemoveCardFields('stickers', ['stickers']);
    RemoveCardFields('locations', ['locations','locationName','locationAddress','locationLatitude','locationLongitude']);
    RemoveCardFields('dependencies', ['cardDependencies','dependencies']);
    RemoveCardFields('sort', ['sort']);
    RemoveCardFields('attachments', ['coverId']);
    if Selected.IndexOf('board-header') < 0 then
      for Key in ['description','members','createdAt','modifiedAt'] do Board.Delete(Key);
    if Selected.IndexOf('scrum') < 0 then
    begin
      for Key in ['scrum','scrumRevision','scrumTransfer','scrumTransferLosses'] do Board.Delete(Key);
      RemoveCardFields('scrum', ['scrum','scrumRevision']);
      for Key in ['lists','swimlanes'] do
      begin
        Rows := CheckedArray(Key);
        for I := 0 to Rows.Count - 1 do
        begin
          if not (Rows.Items[I] is TJSONObject) then
            raise EConvertError.Create('Invalid board export row');
          Rows.Objects[I].Delete('scrum');
          Rows.Objects[I].Delete('scrumRevision');
        end;
      end;
    end;
  finally
    Selected.Free;
  end;
end;

procedure ExcludeBoardArchive(Board: TJSONObject);
var ArchivedLanes, ArchivedLists, LiveCards: TStringList;
  Rows: TJSONArray; Row: TJSONObject; Collection, Owner: string; I: Integer;

  procedure RemoveArchivedContainers(const Key: string; Removed: TStringList; ParentRemoved: TStringList);
  var J: Integer; Containers: TJSONArray; Container: TJSONObject;
  begin
    Containers := Board.Arrays[Key];
    for J := Containers.Count - 1 downto 0 do
    begin
      Container := Containers.Objects[J];
      if Container.Get('archived', False) or
        ((ParentRemoved <> nil) and (ParentRemoved.IndexOf(Container.Get('swimlaneId', '')) >= 0)) then
      begin
        Removed.Add(Container.Get('_id', ''));
        Containers.Delete(J);
      end;
    end;
  end;

begin
  ArchivedLanes := TStringList.Create;
  ArchivedLists := TStringList.Create;
  LiveCards := TStringList.Create;
  try
    ArchivedLanes.CaseSensitive := True;
    ArchivedLanes.Sorted := True;
    ArchivedLists.CaseSensitive := True;
    ArchivedLists.Sorted := True;
    LiveCards.CaseSensitive := True;
    LiveCards.Sorted := True;
    RemoveArchivedContainers('swimlanes', ArchivedLanes, nil);
    RemoveArchivedContainers('lists', ArchivedLists, ArchivedLanes);
    Rows := Board.Arrays['cards'];
    for I := Rows.Count - 1 downto 0 do
    begin
      Row := Rows.Objects[I];
      if Row.Get('archived', False) or (Row.Get('deletedAt', '') <> '') or
        (ArchivedLists.IndexOf(Row.Get('listId', '')) >= 0) or
        (ArchivedLanes.IndexOf(Row.Get('swimlaneId', '')) >= 0) then Rows.Delete(I)
      else LiveCards.Add(Row.Get('_id', ''));
    end;
    for Collection in ['attachments','activities','comments','checklists','checklistItems'] do
    begin
      Rows := Board.Arrays[Collection];
      for I := Rows.Count - 1 downto 0 do
      begin
        Owner := Rows.Objects[I].Get('cardId', '');
        if (Owner <> '') and (LiveCards.IndexOf(Owner) < 0) then Rows.Delete(I);
      end;
    end;
  finally
    LiveCards.Free;
    ArchivedLists.Free;
    ArchivedLanes.Free;
  end;
end;

procedure ScopeBoardExport(Board: TJSONObject; const LaneId, ListId, CardId, ChecklistId: string);
var Cards, Checklists, Items, Entries, OutsideCards, Subtasks: TJSONArray; Entry: TJSONObject;
  CardIds, ListIds, LaneIds, CheckIds: TStringList;
  SelectedCard, Key: string; I: Integer; Matches, Scoped: Boolean;

  function NewIds: TStringList;
  begin
    Result := TStringList.Create;
    Result.Sorted := True;
    Result.CaseSensitive := True;
    Result.Duplicates := dupIgnore;
  end;

  procedure KeepRows(const Collection, PropertyName: string; Ids: TStringList);
  var Rows: TJSONArray; J: Integer; Row: TJSONObject;
  begin
    Rows := Board.Arrays[Collection];
    for J := Rows.Count - 1 downto 0 do
    begin
      Row := Rows.Objects[J];
      if Ids.IndexOf(Row.Get(PropertyName, '')) < 0 then Rows.Delete(J);
    end;
  end;

  procedure AddSubtask(Row: TJSONObject);
  var Parents: TJSONData; J: Integer; Parent: string;
  begin
    Parent := Row.Get('parentId', '');
    if (Parent = '') or (CardIds.IndexOf(Parent) < 0) then
    begin
      Parents := Row.Find('parentIds');
      if not (Parents is TJSONArray) then Exit;
      Parent := '';
      for J := 0 to Parents.Count - 1 do
        if Parents.Items[J] is TJSONString then
          if CardIds.IndexOf(Parents.Items[J].AsString) >= 0 then
          begin
            Parent := Parents.Items[J].AsString;
            Break;
          end;
      if Parent = '' then Exit;
    end;
    if Row.Get('deletedAt', '') <> '' then Exit;
    Subtasks.Add(Row.Clone);
  end;

begin
  Scoped := (LaneId <> '') or (ListId <> '') or (CardId <> '') or (ChecklistId <> '');
  CardIds := NewIds;
  ListIds := NewIds;
  LaneIds := NewIds;
  CheckIds := NewIds;
  OutsideCards := TJSONArray.Create;
  try
    SelectedCard := CardId;
    Checklists := Board.Arrays['checklists'];
    if (SelectedCard = '') and (ChecklistId <> '') then
      for I := 0 to Checklists.Count - 1 do
      begin
        Entry := Checklists.Objects[I];
        if Entry.Get('_id', '') <> ChecklistId then Continue;
        SelectedCard := Entry.Get('cardId', '');
        Break;
      end;

    Cards := Board.Arrays['cards'];
    for I := Cards.Count - 1 downto 0 do
    begin
      Entry := Cards.Objects[I];
      if SelectedCard <> '' then Matches := Entry.Get('_id', '') = SelectedCard
      else Matches := (ChecklistId = '') and
        ((LaneId = '') or (LaneId = Entry.Get('swimlaneId', ''))) and
        ((ListId = '') or (ListId = Entry.Get('listId', '')));
      if Scoped and (not Matches or (Entry.Get('linkedId', '') <> '') or (Entry.Get('deletedAt', '') <> '')) then
      begin
        OutsideCards.Add(Cards.Extract(I));
        Continue;
      end;
      CardIds.Add(Entry.Get('_id', ''));
      LaneIds.Add(Entry.Get('swimlaneId', ''));
      ListIds.Add(Entry.Get('listId', ''));
    end;
    Board.Delete('subtaskItems');
    Subtasks := TJSONArray.Create;
    Board.Add('subtaskItems', Subtasks);
    for I := 0 to Cards.Count - 1 do AddSubtask(Cards.Objects[I]);
    for I := OutsideCards.Count - 1 downto 0 do AddSubtask(OutsideCards.Objects[I]);
    if not Scoped then Exit;
    if LaneId <> '' then LaneIds.Add(LaneId);
    if ListId <> '' then ListIds.Add(ListId);
    KeepRows('lists', '_id', ListIds);
    KeepRows('swimlanes', '_id', LaneIds);
    KeepRows('attachments', 'cardId', CardIds);
    KeepRows('comments', 'cardId', CardIds);
    KeepRows('activities', 'cardId', CardIds);
    for I := Checklists.Count - 1 downto 0 do
    begin
      Entry := Checklists.Objects[I];
      if (CardIds.IndexOf(Entry.Get('cardId', '')) < 0) or
        ((ChecklistId <> '') and (Entry.Get('_id', '') <> ChecklistId)) then Checklists.Delete(I)
      else CheckIds.Add(Entry.Get('_id', ''));
    end;
    Items := Board.Arrays['checklistItems'];
    for I := Items.Count - 1 downto 0 do
    begin
      Entry := Items.Objects[I];
      if (CardIds.IndexOf(Entry.Get('cardId', '')) < 0) or
        (CheckIds.IndexOf(Entry.Get('checklistId', '')) < 0) then Items.Delete(I);
    end;
    for Key in ['rules','triggers','actions'] do
    begin
      Entries := Board.Arrays[Key];
      Entries.Clear;
    end;
  finally
    OutsideCards.Free;
    CheckIds.Free;
    LaneIds.Free;
    ListIds.Free;
    CardIds.Free;
  end;
end;

procedure ApiBoardZip(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; BoardId, UserId, Id, Name, Candidate, Path: string;
  Payload, Attachment: TJSONObject; Attachments: TJSONData; Metadata: TWLRows;
  Output: TMemoryStream; Document: TStringStream; Archive: TZipper; Used: TStringList;
  I: Integer; C: Char;

begin
  if not BoardDownloadAccess(aRequest, aResponse, T, BoardId, UserId) then Exit;
  try
    Payload := ReadRestBoardExport(T, UserId, BoardId, False, True);
  except SendError(aResponse, 500, 'Could not export board'); Exit; end;
  if Payload = nil then begin SendError(aResponse, 403, 'Board export forbidden'); Exit; end;
  try
    if aRequest.QueryFields.Values['archived'] = 'false' then ExcludeBoardArchive(Payload);
    ScopeBoardExport(Payload, DownloadScopeId(aRequest, 'swimlaneId'), DownloadScopeId(aRequest, 'listId'),
      DownloadScopeId(aRequest, 'cardId'), DownloadScopeId(aRequest, 'checklistId'));
    FilterBoardExportFields(Payload, aRequest.QueryFields.Values['fields']);
    PruneBoardExportUsers(Payload);
  except
    Payload.Free;
    SendError(aResponse, 500, 'Could not scope board export');
    Exit;
  end;
  Archive := TZipper.Create;
  Output := TMemoryStream.Create;
  Document := TStringStream.Create('');
  Used := TStringList.Create;
  try
    Used.CaseSensitive := False;
    Archive.Entries.AddFileEntry(Document, 'wekan.json');
    Attachments := Payload.Find('attachments');
    if Attachments is TJSONArray then
      for I := 0 to Attachments.Count - 1 do
      begin
        Attachment := TJSONArray(Attachments).Objects[I];
        Attachment.Delete('archivePath');
        Attachment.Add('archivePath', '');
        if aRequest.QueryFields.Values['attachments'] = 'false' then Continue;
        Id := Attachment.Get('_id', '');
        if Id = '' then Continue;
        Metadata := T.Db.Query('SELECT 1 FROM attachments a JOIN cards c ON c.id=a.cardId AND c.boardId=a.boardId ' +
          'WHERE a.id=' + QuotedStr(Id) + ' AND a.boardId=' + QuotedStr(BoardId) +
          ' AND a.cardId=' + QuotedStr(Attachment.Get('cardId', '')) +
          ' AND c.deletedAt IS NULL AND COALESCE(a.storageBackend,''filesystem'')=''filesystem'';');
        if Length(Metadata) <> 1 then Continue;
        Path := StoreFilePath(T.FilesDir, 'attachme', Id);
        if not FileExists(Path) then Continue;
        Candidate := 'attachments/' + ZipAttachmentName(Attachment.Get('name', ''), Used);
        Attachment.Strings['archivePath'] := Candidate;
        Archive.Entries.AddFileEntry(Path, Candidate);
      end;
    Document.WriteString(Payload.AsJSON + #10);
    Document.Position := 0;
    try
      Archive.SaveToStream(Output);
    except SendError(aResponse, 500, 'Could not export board'); Exit; end;
    Name := '';
    for C in Payload.Get('title', '') do
      if C in ['A'..'Z','a'..'z','0'..'9','_','-'] then Name := Name + C
      else if (Name <> '') and (Name[Length(Name)] <> '-') then Name := Name + '-';
    Name := Copy(Name, 1, 80);
    if Name = '' then Name := 'board';
    aResponse.Code := 200;
    aResponse.ContentType := 'application/zip';
    aResponse.SetCustomHeader('Content-Disposition', 'attachment; filename="' + Name + '.zip"');
    aResponse.SetCustomHeader('Cache-Control', 'private, no-store');
    aResponse.SetCustomHeader('Referrer-Policy', 'no-referrer');
    Output.Position := 0;
    aResponse.ContentLength := Output.Size;
    aResponse.ContentStream := Output;
    try aResponse.SendContent; finally aResponse.ContentStream := nil; end;
  finally Used.Free; Archive.Free; Document.Free; Output.Free; Payload.Free; end;
end;

procedure ApiBoardCalendar(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; BoardId, UserId, Base, Slug, Stamp, StartAt, EndAt, Title, Description, Link: string;
  Board, Cards: TWLRows; Card: TWLRow; Calendar: TStringStream; Session: TWLSession; C: Char;
  function EscapeText(const Value: string): string;
  begin
    Result := StringReplace(Value, '\', '\\', [rfReplaceAll]);
    Result := StringReplace(Result, ';', '\;', [rfReplaceAll]);
    Result := StringReplace(Result, ',', '\,', [rfReplaceAll]);
    Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
    Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
    Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  end;
  function CalendarDate(const Value: string): string;
  var At: TDateTime;
  begin
    Result := '';
    if (Value <> '') and TryISO8601ToDate(Value, At, True) then
      Result := FormatDateTime('yyyymmdd"T"hhnnss"Z"', At);
  end;
  procedure Line(const Value: string);
  var First, Last, Width: Integer;
  begin
    First := 1; Width := 75;
    while First + Width <= Length(Value) do
    begin
      Last := First + Width;
      while (Last > First) and ((Ord(Value[Last]) and $C0) = $80) do Dec(Last);
      Calendar.WriteString(Copy(Value, First, Last - First) + #13#10' ');
      First := Last; Width := 74;
    end;
    Calendar.WriteString(Copy(Value, First, MaxInt) + #13#10);
  end;
  procedure Event(const Suffix, Starts, Ends, Summary: string);
  begin
    Line('BEGIN:VEVENT');
    Line('UID:' + HTTPEncode(Card[0]) + '-' + Suffix + '@wekan');
    Line('DTSTAMP:' + Stamp);
    Line('DTSTART:' + Starts);
    Line('DTEND:' + Ends);
    Line('SUMMARY:' + EscapeText(Summary));
    if Description <> '' then Line('DESCRIPTION:' + EscapeText(Description));
    if Link <> '' then Line('URL:' + Link);
    Line('END:VEVENT');
  end;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if SharedSettingOn(T.Db, 'disableAllExport') or SharedSettingOn(T.Db, 'anonymizeExportUsers') then
  begin SendError(aResponse, 403, 'Board export restricted by instance settings'); Exit; end;
  BoardId := aRequest.RouteParams['boardId'];
  if (BoardId = '') or (Pos(#0, BoardId) > 0) then
  begin SendError(aResponse, 404, 'Board not found'); Exit; end;
  Board := T.Db.Query('SELECT title,slug,permission FROM boards WHERE id=' + QuotedStr(BoardId) + ' AND archived=0;');
  if Length(Board) <> 1 then begin SendError(aResponse, 404, 'Board not found'); Exit; end;
  if Board[0][2] <> 'public' then
  begin
    if (aRequest.Authorization = '') and (aRequest.QueryFields.Values['authToken'] = '') and
      (aRequest.QueryFields.Values['token'] = '') and
      (Html5User(T.Db, aRequest, Session) or
        ValidateSession(T.Db, aRequest, SessionIdFromRequest(aRequest), Session)) then UserId := Session.UserId
    else if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
    if not BoardHasMember(T.Db, UserId, BoardId) or AssignedOnlyMember(T.Db, UserId, BoardId) then
    begin SendError(aResponse, 403, 'Board access forbidden'); Exit; end;
  end;
  if not T.Db.BeginRead then begin SendError(aResponse, 500, 'Could not export calendar'); Exit; end;
  try
    if SharedSettingOn(T.Db, 'disableAllExport') or SharedSettingOn(T.Db, 'anonymizeExportUsers') then
    begin SendError(aResponse, 403, 'Board export restricted by instance settings'); Exit; end;
    Board := T.Db.Query('SELECT title,slug,permission FROM boards WHERE id=' + QuotedStr(BoardId) + ' AND archived=0;');
    if Length(Board) <> 1 then begin SendError(aResponse, 404, 'Board not found'); Exit; end;
    if (Board[0][2] <> 'public') and
      (not BoardHasMember(T.Db, UserId, BoardId) or AssignedOnlyMember(T.Db, UserId, BoardId)) then
    begin SendError(aResponse, 403, 'Board access forbidden'); Exit; end;
    Cards := T.Db.Query('SELECT id,COALESCE(title,''''),COALESCE(description,''''),COALESCE(startAt,''''),' +
      'COALESCE(endAt,''''),COALESCE(dueAt,''''),COALESCE(receivedAt,'''') FROM cards WHERE boardId=' +
      QuotedStr(BoardId) + ' AND archived=0 AND deletedAt IS NULL AND COALESCE(linkedId,'''')='''' ORDER BY sort,id;');
  finally T.Db.EndRead; end;
  Slug := Board[0][1];
  Base := GetEnvironmentVariable('ROOT_URL');
  if Base = '' then
  begin
    Base := aRequest.Host;
    for C in Base do
      if not (C in ['A'..'Z','a'..'z','0'..'9','.',':','-','[',']']) then
      begin Base := ''; Break; end;
    if Base <> '' then Base := 'http://' + Base;
  end;
  if (Base <> '') and (Base[Length(Base)] = '/') then Delete(Base, Length(Base), 1);
  if (Pos(#13, Base) > 0) or (Pos(#10, Base) > 0) then Base := '';
  Stamp := FormatDateTime('yyyymmdd"T"hhnnss"Z"', LocalTimeToUniversal(Now));
  Calendar := TStringStream.Create('');
  try
    Line('BEGIN:VCALENDAR'); Line('VERSION:2.0'); Line('PRODID:-//WeKan//iCal Export//EN');
    Line('CALSCALE:GREGORIAN'); Line('METHOD:PUBLISH'); Line('X-WR-CALNAME:' + EscapeText('WeKan - ' + Board[0][0]));
    for Card in Cards do
    begin
      Title := Card[1];
      if Title = '' then Title := '(untitled card)';
      Description := Card[2];
      Link := '';
      if Base <> '' then Link := Base + CardRoute(BoardId, Slug, Card[0]);
      StartAt := CalendarDate(Card[3]); EndAt := CalendarDate(Card[4]);
      if StartAt = '' then StartAt := EndAt;
      if EndAt = '' then EndAt := StartAt;
      if StartAt <> '' then Event('span', StartAt, EndAt, Title);
      StartAt := CalendarDate(Card[5]);
      if StartAt <> '' then Event('due', StartAt, StartAt, Title + ' (due)');
      StartAt := CalendarDate(Card[6]);
      if StartAt <> '' then Event('received', StartAt, StartAt, Title + ' (received)');
    end;
    Line('END:VCALENDAR');
    aResponse.Code := 200;
    aResponse.ContentType := 'text/calendar; charset=utf-8';
    aResponse.SetCustomHeader('Content-Disposition', 'inline; filename="board.ics"');
    aResponse.SetCustomHeader('Cache-Control', 'no-store');
    aResponse.SetCustomHeader('Referrer-Policy', 'no-referrer');
    Calendar.Position := 0;
    aResponse.ContentLength := Calendar.Size;
    aResponse.ContentStream := Calendar;
    try aResponse.SendContent; finally aResponse.ContentStream := nil; end;
  finally Calendar.Free; end;
end;

procedure BoardCreationSettings(Db:TWLDb;out AdminOnly,PrivateOnly,RegistryGuard:string);
var Registry,TableName:string;Rows:TWLRows;
  function Setting(const Name:string):string;
  begin
    Result:='EXISTS(SELECT 1 FROM '+TableName+' WHERE json_extract(_ferretdb_sjson,''$._id'')='+
      QuotedStr('tableVisibilityMode-'+Name)+' AND json_type(_ferretdb_sjson,''$.booleanValue'')=''true'')';
  end;
begin
  AdminOnly:='0';PrivateOnly:='0';RegistryGuard:='1';
  if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))=1 then
  begin
    Registry:=' FROM _ferretdb_collections WHERE name=''tableVisibilityModeSettings''';
    Rows:=Db.Query('SELECT table_name'+Registry+';');
    if Length(Rows)=1 then
    begin
      TableName:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
      AdminOnly:=Setting('boardCreationAdminOnly');PrivateOnly:=Setting('allowPrivateOnly');
      RegistryGuard:='(SELECT count(*)'+Registry+' AND table_name='+QuotedStr(Rows[0][0])+')=1';
    end else if Length(Rows)=0 then RegistryGuard:='NOT EXISTS(SELECT 1'+Registry+')'
    else raise Exception.Create('Ambiguous board creation policy');
  end;
end;

procedure ApiCreateBoard(aRequest:TRequest;aResponse:TResponse);
const Colors='|belize|nephritis|pomegranate|pumpkin|wisteria|moderatepink|strongcyan|limegreen|midnight|dark|'+
  'relax|corteza|appleglasspastel|clearblue|cleargreen|clearorange|clearpink|clearpurple|clearred|natural|modern|moderndark|exodark|cleandark|cleanlight|';
var T:TWLTenant;Actor,Title,Visibility,Color,Board,Lane,ActorScope,AdminOnly,PrivateOnly,RegistryGuard,
  Stamp,Sql,Permission,DefaultTitle,BoardId,LaneId:string;Rows:TWLRows;Reply:TJSONObject;
  Words:TWLTranslator;Body:TJSONObject;Value:TJSONData;

begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  Title:=BodyField(aRequest,'title');Visibility:=BodyField(aRequest,'permission');Color:=BodyField(aRequest,'color');
  Body:=nil;
  try
    try
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
      begin
        Body:=ExactObject(aRequest.Content);Value:=Body.Find('title');
        if not (Value is TJSONString) then raise Exception.Create('Missing board title');
        Title:=Value.AsString;
      end;
      CheckUtf8(Title);
      if (Trim(Title)='') or (Pos(#0,Title)>0) then raise Exception.Create('Invalid board title');
      if Visibility='' then Visibility:='private';
      if (Visibility<>'private') and (Visibility<>'public') then raise Exception.Create('Invalid board permission');
      if Color='' then Color:='belize';
      if (Pos('|',Color)>0) or (Pos('|'+Color+'|',Colors)=0) then raise Exception.Create('Invalid board color');
    except SendError(aResponse,400,'Invalid board settings');Exit;end;
  finally Body.Free;end;
  try BoardCreationSettings(T.Db,AdminOnly,PrivateOnly,RegistryGuard);
  except SendError(aResponse,500,'Could not read board creation policy');Exit;end;
  Actor:=QuotedStr(Actor);ActorScope:='id='+Actor+' AND COALESCE(loginDisabled,0)=0';
  Permission:='EXISTS(SELECT 1 FROM users WHERE '+ActorScope+' AND (isAdmin=1 OR NOT '+AdminOnly+'))';
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board creation is restricted to admins');Exit;end;
  BoardId:=NewId;LaneId:=NewId;Board:=QuotedStr(BoardId);Lane:=QuotedStr(LaneId);Stamp:=QuotedStr(NowIso);
  Words:=TWLTranslator.Create(ViewerLanguage(T.Db,Default(TWLSession),aRequest));
  try DefaultTitle:=QuotedStr(Words.Text('default','Default'));finally Words.Free;end;
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+AuthSourceCondition(T.Db)+' AND '+RegistryGuard+' AND '+Permission+
    ' THEN 1 ELSE json(''Board creation policy changed'') END; '+
    'INSERT INTO boards(id,title,slug,permission,color,createdAt,modifiedAt) VALUES('+Board+','+
    QuotedStr(Title)+','+QuotedStr(Slugify(Title))+',CASE WHEN '+PrivateOnly+' THEN ''private'' ELSE '+QuotedStr(Visibility)+
    ' END,'+QuotedStr(Color)+','+Stamp+','+Stamp+'); '+
    'INSERT INTO board_members(boardId,userId,isAdmin,isActive,isNoComments,isCommentOnly,isWorker) VALUES('+
    Board+','+Actor+',1,1,0,0,0); '+
    'INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES('+Lane+','+Board+','+DefaultTitle+',0,'+Stamp+'); '+
    'SELECT CASE WHEN EXISTS(SELECT 1 FROM board_members WHERE boardId='+Board+' AND userId='+Actor+
    ' AND isAdmin=1 AND isActive=1) AND EXISTS(SELECT 1 FROM swimlanes WHERE id='+Lane+
    ' AND boardId='+Board+') THEN 1 ELSE json(''Board creation incomplete'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create board');Exit;end;
  Reply:=TJSONObject.Create(['_id',BoardId,'defaultSwimlaneId',LaneId]);
  try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
end;

function CreateBoardFromViewCard(const T:TWLTenant;const UserId,CardId,Title,DefaultLane:string;out BoardId,Error:string):Integer;
var R:TWLRows;Src,BoardTitle,Board,Lane,Stamp,Sql,AdminOnly,PrivateOnly,RegistryGuard,Actor,Permission,Visibility:string;
begin
  Error:='';BoardId:='';
  if (CardId='') or (Pos(#0,CardId+Title)>0) then begin Error:='not-found';Exit(404);end;
  R:=T.Db.Query('SELECT boardId,COALESCE(title,''''),archived,COALESCE(type,''cardType-card'') FROM cards WHERE id='+QuotedStr(CardId)+
    ' AND deletedAt IS NULL;');
  if Length(R)<>1 then begin Error:='not-found';Exit(404);end;
  if R[0][2]='1' then begin Error:='invalid-card';Exit(400);end;
  // Already a link, or a template card: nothing sensible to convert.
  if (R[0][3]='template-card') or (R[0][3]='cardType-linkedCard') or (R[0][3]='cardType-linkedBoard') then
  begin Error:='invalid-linked-card';Exit(400);end;
  Src:=R[0][0];
  if not AssignedWriterOn(T.Db,UserId,Src) then begin Error:='not-authorized';Exit(403);end;
  // GHSA-6xqf-jh8x-4wxc: an assigned-only member converts only their own card.
  if AssignedOnlyMember(T.Db,UserId,Src) and not CardAssignedTo(T.Db,UserId,Src,CardId) then
  begin
    try
      RecordSecurityEvent(T.Db,UserId,'UnassignedArchiveBleed','method:createBoardFromCard','authz','medium','CWE-863','blocked',
        'Assigned-only member tried to turn a card not assigned to them into a board.');
    except
      // logging must never break the guard
    end;
    Error:='not-authorized';Exit(403);
  end;
  BoardTitle:=Trim(Title);
  if BoardTitle='' then BoardTitle:=Trim(R[0][1]);
  if BoardTitle='' then begin Error:='invalid-title';Exit(400);end;
  try BoardCreationSettings(T.Db,AdminOnly,PrivateOnly,RegistryGuard);
  except Error:='Could not read board creation policy';Exit(500);end;
  Actor:=QuotedStr(UserId);
  // CreateBleed: the card becomes a new working board.
  Permission:='EXISTS(SELECT 1 FROM users WHERE id='+Actor+' AND COALESCE(loginDisabled,0)=0 AND (isAdmin=1 OR NOT '+AdminOnly+'))';
  if T.Db.Query('SELECT '+Permission+';')[0][0]<>'1' then begin Error:='not-authorized';Exit(403);end;
  // The source board's visibility when it is open, private otherwise - and
  // private whenever Admin Panel allows private boards only.
  R:=T.Db.Query('SELECT COALESCE(permission,''private''),COALESCE(color,''belize'') FROM boards WHERE id='+QuotedStr(Src)+';');
  Visibility:=R[0][0];
  if (Visibility<>'public') and (Visibility<>'instance') then Visibility:='private';
  BoardId:=NewId;Board:=QuotedStr(BoardId);Lane:=QuotedStr(NewId);Stamp:=QuotedStr(NowIso);
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+RegistryGuard+' AND '+Permission+' THEN 1 ELSE json(''Board creation policy changed'') END; '+
    'INSERT INTO boards(id,title,slug,permission,color,createdAt,modifiedAt) VALUES('+Board+','+QuotedStr(BoardTitle)+','+
    QuotedStr(Slugify(BoardTitle))+',CASE WHEN '+PrivateOnly+' THEN ''private'' ELSE '+QuotedStr(Visibility)+' END,'+QuotedStr(R[0][1])+','+
    Stamp+','+Stamp+'); '+
    'INSERT INTO board_members(boardId,userId,isAdmin,isActive,isNoComments,isCommentOnly,isWorker) VALUES('+Board+','+Actor+',1,1,0,0,0); '+
    'INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES('+Lane+','+Board+','+QuotedStr(DefaultLane)+',0,'+Stamp+'); '+
    // The same two fields the "Link to board" flow sets; nothing else changes.
    'UPDATE cards SET type=''cardType-linkedBoard'',linkedId='+Board+',modifiedAt='+Stamp+' WHERE id='+QuotedStr(CardId)+
    ' AND archived=0 AND deletedAt IS NULL; '+
    'SELECT CASE WHEN (SELECT linkedId FROM cards WHERE id='+QuotedStr(CardId)+')='+Board+' AND EXISTS(SELECT 1 FROM swimlanes WHERE id='+Lane+
    ') THEN 1 ELSE json(''Board creation incomplete'') END; COMMIT;';
  if not T.Db.Exec(Sql) then begin T.Db.Exec('ROLLBACK;');BoardId:='';Error:='Could not create board';Exit(500);end;
  Result:=200;
end;

function MayCreateBoard(Db:TWLDb;const UserId:string):Boolean;
var AdminOnly,PrivateOnly,RegistryGuard:string;
begin
  Result:=False;
  if UserId='' then Exit;
  try BoardCreationSettings(Db,AdminOnly,PrivateOnly,RegistryGuard);except Exit;end;
  Result:=Db.Query('SELECT EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(UserId)+' AND COALESCE(loginDisabled,0)=0 AND (isAdmin=1 OR NOT '+
    AdminOnly+'));')[0][0]='1';
end;

function CreateViewBoard(const T:TWLTenant;const UserId,Title,DefaultLane:string;out BoardId,Error:string):Integer;
var BoardTitle,Board,Lane,Stamp,Sql,AdminOnly,PrivateOnly,RegistryGuard,Actor,Permission:string;
begin
  Error:='';BoardId:='';
  BoardTitle:=Trim(Title);
  if (BoardTitle='') or (Pos(#0,BoardTitle)>0) then begin Error:='a board needs a title';Exit(400);end;
  try BoardCreationSettings(T.Db,AdminOnly,PrivateOnly,RegistryGuard);
  except Error:='Could not read board creation policy';Exit(500);end;
  Actor:=QuotedStr(UserId);
  // CreateBleed: Admin Panel may let only admins make boards.
  Permission:='EXISTS(SELECT 1 FROM users WHERE id='+Actor+' AND COALESCE(loginDisabled,0)=0 AND (isAdmin=1 OR NOT '+AdminOnly+'))';
  if T.Db.Query('SELECT '+Permission+';')[0][0]<>'1' then begin Error:='Board creation is restricted to admins';Exit(403);end;
  BoardId:=NewId;Board:=QuotedStr(BoardId);Lane:=QuotedStr(NewId);Stamp:=QuotedStr(NowIso);
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+RegistryGuard+' AND '+Permission+' THEN 1 ELSE json(''Board creation policy changed'') END; '+
    'INSERT INTO boards(id,title,slug,permission,color,createdAt,modifiedAt) VALUES('+Board+','+QuotedStr(BoardTitle)+','+
    QuotedStr(Slugify(BoardTitle))+',''private'',''belize'','+Stamp+','+Stamp+'); '+
    'INSERT INTO board_members(boardId,userId,isAdmin,isActive,isNoComments,isCommentOnly,isWorker) VALUES('+Board+','+Actor+',1,1,0,0,0); '+
    'INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES('+Lane+','+Board+','+QuotedStr(DefaultLane)+',0,'+Stamp+'); '+
    'SELECT CASE WHEN EXISTS(SELECT 1 FROM swimlanes WHERE id='+Lane+') THEN 1 ELSE json(''Board creation incomplete'') END; COMMIT;';
  if not T.Db.Exec(Sql) then begin T.Db.Exec('ROLLBACK;');BoardId:='';Error:='Could not create board';Exit(500);end;
  Result:=200;
end;


procedure WriteFileBytes(const Path,Data:string); forward;

type TDefinitionFlags=array[0..5] of Integer;
const DefinitionFlagNames:array[0..5] of string=('showOnCard','automaticallyOnCard',
  'showLabelOnMiniCard','showSumAtTopOfList','readOnly','adminOnly');
function ValidDefinitionType(const Kind:string):Boolean;
begin
  case Kind of 'text','number','currency','date','checkbox','dropdown','dropdownMultiSelect','stringtemplate': Result:=True;
  else Result:=False;end;
end;
function DefinitionFlag(Data:TJSONData;out Number:Integer):Boolean;
  var Text:string;
  begin
    Number:=0;if Data=nil then Exit(True);
    if Data.JSONType=jtBoolean then begin Number:=Ord(Data.AsBoolean);Exit(True);end;
    if Data.JSONType=jtString then Text:=LowerCase(Trim(Data.AsString))
    else if Data.JSONType=jtNumber then Text:=Data.AsJSON else Exit(False);
    Result:=True;
    if (Text='true') or (Text='1') then Number:=1
    else if (Text<>'false') and (Text<>'0') and (Text<>'') then Result:=False;
  end;
function CustomValueLiteral(Data:TJSONData;out Value:string):Boolean;
var i:Integer;
begin
  Result:=False;Value:='';
  if Data=nil then Exit;
  case Data.JSONType of
    jtString:begin
      if Pos(#0,Data.AsString)>0 then Exit;
      Value:=QuotedStr(Data.AsString);
    end;
    jtNumber:begin
      if IsNan(Data.AsFloat) or IsInfinite(Data.AsFloat) then Exit;
      Value:=Data.AsJSON;
    end;
    jtBoolean:if Data.AsBoolean then Value:='1' else Value:='0';
    jtArray:begin
      for i:=0 to Data.Count-1 do
        if (Data.Items[i].JSONType<>jtString) or (Pos(#0,Data.Items[i].AsString)>0) then Exit;
      Value:=QuotedStr(Data.AsJSON);
    end;
  else Exit;
  end;
  Result:=True;
end;

function CardDecorations(Value:TJSONData;const Key:string):TJSONArray; forward;

function ImportAuthorIdentity(Authors: TJSONObject; const Name: string): string;
begin
  Result:=Authors.Get(Name,'');
  if (Name='') or (Result<>'') then Exit;
  Result:='author-'+IntToStr(Authors.Count);
  Authors.Add(Name,Result);
end;

// Kanboard JSON projects use numeric string IDs and Unix-second dates.
function KanboardImport(const Source: TJSONObject): TJSONObject;
var Meta, Board, Task, Entry, Card, Authors, Comment: TJSONObject; Columns, Lanes, Tasks, Lists, Swimlanes, Cards, Labels, Tags,
  Comments, Checklists, Items, Children: TJSONArray; I,J: Integer; Id, CheckId, LabelId, Text, Author: string; Hours: Double;
  procedure DateOf(const Input, Field: string);
  var Seconds: Int64;
  begin
    if TryStrToInt64(Task.Get(Input,''),Seconds) and (Seconds>0) and (Seconds<=253402300799) then
      Card.Add(Field,FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"',UnixToDateTime(Seconds)));
  end;
  function LabelFor(const Name: string): string;
  var K: Integer;
  begin
    for K:=0 to Labels.Count-1 do if Labels.Objects[K].Get('name','')=Name then Exit(Labels.Objects[K].Get('_id',''));
    Result:='label-'+IntToStr(Labels.Count);
    Labels.Add(TJSONObject.Create(['_id',Result,'name',Name,'color','blue']));
  end;
  function OptionalArray(Obj: TJSONObject; const Field: string): TJSONArray;
  var Value: TJSONData;
  begin
    Value:=Obj.Find(Field);
    if Value is TJSONArray then Result:=TJSONArray(Value) else Result:=nil;
  end;
begin
  if not (Source.Find('board') is TJSONObject) or not (Source.Find('columns') is TJSONArray) or
    not (Source.Find('tasks') is TJSONArray) then raise EConvertError.Create('Invalid Kanboard export');
  Meta:=TJSONObject(Source.Find('board'));
  Columns:=TJSONArray(Source.Find('columns'));
  Tasks:=TJSONArray(Source.Find('tasks'));
  Lanes:=OptionalArray(Source,'swimlanes');
  Result:=TJSONObject.Create;
  try
    Board:=TJSONObject.Create(['title',Meta.Get('name','')]); Result.Add('board',Board);
    Authors:=TJSONObject.Create; Result.Add('importedAuthors',Authors);
    Lists:=TJSONArray.Create; Board.Add('lists',Lists);
    Swimlanes:=TJSONArray.Create; Board.Add('swimlanes',Swimlanes);
    Cards:=TJSONArray.Create; Board.Add('cards',Cards);
    Labels:=TJSONArray.Create; Board.Add('labels',Labels);
    Comments:=TJSONArray.Create; Board.Add('comments',Comments);
    Checklists:=TJSONArray.Create; Board.Add('checklists',Checklists);
    Items:=TJSONArray.Create; Board.Add('checklistItems',Items);
    if Lanes<>nil then for I:=0 to Lanes.Count-1 do
    begin
      Entry:=Lanes.Objects[I];
      Swimlanes.Add(TJSONObject.Create(['_id',Entry.Get('id',''),'title',Entry.Get('name',''),'sort',I]));
    end;
    for I:=0 to Columns.Count-1 do
    begin
      Entry:=Columns.Objects[I];
      Lists.Add(TJSONObject.Create(['_id',Entry.Get('id',''),'title',Entry.Get('title',''),'sort',I]));
    end;
    for I:=0 to Tasks.Count-1 do
    begin
      Task:=Tasks.Objects[I]; Id:=Task.Get('id','');
      Card:=TJSONObject.Create(['_id',Id,'title',Task.Get('title',''),'description',Task.Get('description',''),
        'listId',Task.Get('column_id',''),'swimlaneId',Task.Get('swimlane_id',''),'sort',I,'archived',Task.Get('is_active','1')='0']);
      Cards.Add(Card);
      Author:=ImportAuthorIdentity(Authors,Task.Get('creator_username',''));
      if Author<>'' then Card.Add('userId',Author);
      Text:=MapImportColor('kanboard',Task.Get('color_id',''));
      if Task.Get('color_id','')='deep_orange' then Text:='crimson';
      if Text<>'' then Card.Add('color',Text);
      DateOf('date_due','dueAt'); DateOf('date_creation','createdAt'); DateOf('date_started','startAt'); DateOf('date_completed','endAt');
      if TryStrToFloat(Task.Get('time_spent',''),Hours,DefaultFormatSettings) and (Hours>=0) then Card.Add('spentTime',Hours);
      Tags:=TJSONArray.Create; Card.Add('labelIds',Tags);
      Children:=OptionalArray(Task,'tags');
      if Children<>nil then for J:=0 to Children.Count-1 do
        if Children.Items[J] is TJSONString then Tags.Add(LabelFor(Children.Strings[J]));
      Text:=Task.Get('priority','');
      if (Text<>'') and (Text<>'0') then Tags.Add(LabelFor('priority:'+Text));
      Children:=OptionalArray(Source,'categories');
      if Children<>nil then for J:=0 to Children.Count-1 do
      begin
        Entry:=Children.Objects[J];
        if Entry.Get('id','')<>Task.Get('category_id','') then Continue;
        LabelId:=LabelFor(Entry.Get('name',''));
        Tags.Add(LabelId);
      end;
      Children:=OptionalArray(Task,'comments');
      if Children<>nil then for J:=0 to Children.Count-1 do
      begin
        Entry:=Children.Objects[J];
        Comment:=TJSONObject.Create(['_id',Id+':comment:'+IntToStr(J),'cardId',Id,'text',Entry.Get('comment','')]);
        Comments.Add(Comment);
        Author:=ImportAuthorIdentity(Authors,Entry.Get('username',''));
        if Author<>'' then Comment.Add('userId',Author);
      end;
      Children:=OptionalArray(Task,'subtasks');
      if (Children<>nil) and (Children.Count>0) then
      begin
        CheckId:=Id+':subtasks';
        Checklists.Add(TJSONObject.Create(['_id',CheckId,'cardId',Id,'title','Subtasks','sort',0]));
        for J:=0 to Children.Count-1 do
        begin
          Entry:=Children.Objects[J];
          Items.Add(TJSONObject.Create(['_id',CheckId+':'+IntToStr(J),'checklistId',CheckId,
            'title',Entry.Get('title',''),'sort',J,'isFinished',Entry.Get('status','')='2']));
        end;
      end;
    end;
  except Result.Free; raise; end;
end;

function DeckImport(const Source: TJSONObject): TJSONObject;
var Meta, Board, Stack, Entry, Card, Comment, Authors: TJSONObject; Stacks, StackCards, Lists, Cards, Labels,
  Comments, Tags: TJSONArray; Child, Value: TJSONData; I,J,K, DeletedCards, DeletedStacks, AclCount, AttachmentCount: Integer; CardId,ListId,Name,Author,LabelId, Losses: string;
  function Identity(Obj: TJSONObject): string;
  var Field: TJSONData;
  begin
    Field:=Obj.Find('id');
    if (Field=nil) or not (Field.JSONType in [jtString,jtNumber]) then
      raise EConvertError.Create('Invalid Deck identity');
    Result:=Field.AsString;
  end;
  function Deleted(Obj: TJSONObject): Boolean;
  var DateValue: TJSONData;
  begin
    DateValue:=Obj.Find('deletedAt');
    Result:=(DateValue<>nil) and (DateValue.JSONType<>jtNull) and (DateValue.AsString<>'') and (DateValue.AsString<>'0');
  end;
  procedure CopyDate(FromRow, ToRow: TJSONObject; const SourceKey, Key: string);
  var DateValue: TJSONData; Seconds: Int64;
  begin
    DateValue:=FromRow.Find(SourceKey);
    if (DateValue=nil) or (DateValue.JSONType=jtNull) then Exit;
    if TryStrToInt64(DateValue.AsString,Seconds) then
    begin
      if (Seconds>0) and (Seconds<=253402300799) then
        ToRow.Add(Key,FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"',UnixToDateTime(Seconds)));
    end
    else if DateValue is TJSONString then ToRow.Add(Key,DateValue.AsString);
  end;
  function LabelFor(const Title: string): string;
  var L: Integer;
  begin
    for L:=0 to Labels.Count-1 do if Labels.Objects[L].Get('name','')=Title then Exit(Labels.Objects[L].Get('_id',''));
    Result:='label-'+IntToStr(Labels.Count);
    Labels.Add(TJSONObject.Create(['_id',Result,'name',Title,'color','blue']));
  end;
begin
  Meta:=Source;
  if Source.Find('board') is TJSONObject then Meta:=TJSONObject(Source.Find('board'));
  Value:=Meta.Find('stacks');
  if Value=nil then Value:=Source.Find('stacks');
  if not (Value is TJSONArray) or (Trim(Meta.Get('title',''))='') then raise EConvertError.Create('Invalid Deck export');
  Stacks:=TJSONArray(Value);
  DeletedCards:=0; DeletedStacks:=0; AttachmentCount:=0; AclCount:=0;
  Value:=Meta.Find('acl');
  if Value is TJSONArray then AclCount:=Value.Count;
  Result:=TJSONObject.Create;
  try
    Board:=TJSONObject.Create(['title',Meta.Get('title','')]); Result.Add('board',Board);
    Authors:=TJSONObject.Create; Result.Add('importedAuthors',Authors);
    Lists:=TJSONArray.Create; Board.Add('lists',Lists);
    Cards:=TJSONArray.Create; Board.Add('cards',Cards);
    Labels:=TJSONArray.Create; Board.Add('labels',Labels);
    Comments:=TJSONArray.Create; Board.Add('comments',Comments);
    for I:=0 to Stacks.Count-1 do
    begin
      Stack:=Stacks.Objects[I];
      if Deleted(Stack) then begin Inc(DeletedStacks); Continue; end;
      ListId:=Identity(Stack);
      Lists.Add(TJSONObject.Create(['_id',ListId,'title',Stack.Get('title',''),'sort',StrToIntDef(Stack.Get('order',''),I)]));
      Child:=Stack.Find('cards');
      if not (Child is TJSONArray) then Continue;
      StackCards:=TJSONArray(Child);
      for J:=0 to StackCards.Count-1 do
      begin
        Entry:=StackCards.Objects[J];
        if Deleted(Entry) then begin Inc(DeletedCards); Continue; end;
        Child:=Entry.Find('attachments');
        if Child is TJSONArray then Inc(AttachmentCount,Child.Count);
        CardId:=Identity(Entry);
        Card:=TJSONObject.Create(['_id',CardId,'listId',ListId,'title',Entry.Get('title',''),
          'description',Entry.Get('description',''),'sort',StrToIntDef(Entry.Get('order',''),J),'archived',Entry.Get('archived',False)]);
        Cards.Add(Card);
        CopyDate(Entry,Card,'duedate','dueAt'); CopyDate(Entry,Card,'createdAt','createdAt');
        Child:=Entry.Find('done');
        if (Child<>nil) and (((Child.JSONType=jtBoolean) and Child.AsBoolean) or
          ((Child is TJSONString) and (Child.AsString<>''))) then
        begin
          Card.Add('dueComplete',True);
          if Child is TJSONString then CopyDate(Entry,Card,'done','endAt');
        end;
        Child:=Entry.Find('owner');
        if Child is TJSONObject then
        begin
          Name:=TJSONObject(Child).Get('displayname',TJSONObject(Child).Get('uid',''));
          Author:=ImportAuthorIdentity(Authors,Name);
          if Author<>'' then Card.Add('userId',Author);
        end;
        Tags:=TJSONArray.Create; Card.Add('labelIds',Tags);
        Child:=Entry.Find('labels');
        if Child is TJSONArray then for K:=0 to Child.Count-1 do
        begin
          Value:=Child.Items[K];
          if Value is TJSONObject then Name:=TJSONObject(Value).Get('title','')
          else if Value is TJSONString then Name:=Value.AsString else Continue;
          if Name='' then Continue;
          LabelId:=LabelFor(Name);
          Tags.Add(LabelId);
        end;
        Child:=Entry.Find('comments');
        if Child is TJSONArray then for K:=0 to Child.Count-1 do
        begin
          if not (Child.Items[K] is TJSONObject) then Continue;
          Comment:=TJSONObject(Child.Items[K]);
          Author:=ImportAuthorIdentity(Authors,Comment.Get('actorId',Comment.Get('actorDisplayName','')));
          Value:=TJSONObject.Create(['_id',CardId+':comment:'+IntToStr(K),'cardId',CardId,'text',Comment.Get('message',''),'userId',Author]);
          Comments.Add(Value);
          CopyDate(Comment,TJSONObject(Value),'creationDateTime','createdAt');
        end;
      end;
    end;
    Losses:='';
    if AclCount>0 then Losses:='/acl: '+IntToStr(AclCount)+' sharing rule(s) skipped';
    if DeletedStacks>0 then Losses:=Losses+LineEnding+'/stacks: '+IntToStr(DeletedStacks)+' deleted stack(s) skipped';
    if DeletedCards>0 then Losses:=Losses+LineEnding+'/stacks/cards: '+IntToStr(DeletedCards)+' deleted card(s) skipped';
    if AttachmentCount>0 then Losses:=Losses+LineEnding+'/stacks/cards/attachments: '+IntToStr(AttachmentCount)+' attachment(s) skipped';
    if Trim(Losses)<>'' then Result.Add('importLosses',Trim(Losses));
  except Result.Free; raise; end;
end;

function IssueImport(const Source: TJSONData; const FormatName: string): TJSONObject;
var Issues, Lists, Cards, Labels, Comments, Tags: TJSONArray; Board, Authors, Issue, Card, Note: TJSONObject;
  Data, Value: TJSONData; I,J,K: Integer; Id, Name, LabelId, Author, Due, Description, Url: string;
  GitLab, Closed: Boolean;
  function AuthorName(Value: TJSONData): string;
  begin
    Result:='';
    if Value is TJSONObject then with TJSONObject(Value) do
      Result:=Get('login',Get('username',Get('name','')));
  end;
  function LabelFor(const Name: string): string;
  var L: Integer;
  begin
    for L:=0 to Labels.Count-1 do if Labels.Objects[L].Get('name','')=Name then Exit(Labels.Objects[L].Get('_id',''));
    Result:='label-'+IntToStr(Labels.Count);
    Labels.Add(TJSONObject.Create(['_id',Result,'name',Name,'color','blue']));
  end;
begin
  Data:=Source;
  if Data is TJSONObject then Data:=TJSONObject(Data).Find('issues');
  if not (Data is TJSONArray) then raise EConvertError.Create('Invalid issue export');
  Issues:=TJSONArray(Data);
  GitLab:=FormatName='gitlab';
  Result:=TJSONObject.Create;
  try
    Board:=TJSONObject.Create(['title',FormatName+' issues']); Result.Add('board',Board);
    Authors:=TJSONObject.Create; Result.Add('importedAuthors',Authors);
    Lists:=TJSONArray.Create; Board.Add('lists',Lists);
    Lists.Add(TJSONObject.Create(['_id','open','title','Open','sort',0]));
    Lists.Add(TJSONObject.Create(['_id','closed','title','Closed','sort',1]));
    Cards:=TJSONArray.Create; Board.Add('cards',Cards);
    Labels:=TJSONArray.Create; Board.Add('labels',Labels);
    Comments:=TJSONArray.Create; Board.Add('comments',Comments);
    for I:=0 to Issues.Count-1 do
    begin
      if not (Issues.Items[I] is TJSONObject) then raise EConvertError.Create('Invalid issue row');
      Issue:=Issues.Objects[I];
      Value:=Issue.Find('id');
      if Value=nil then Value:=Issue.Find('number');
      if Value=nil then Value:=Issue.Find('iid');
      if (Value=nil) or not (Value.JSONType in [jtString,jtNumber]) or (Trim(Issue.Get('title',''))='') then
        raise EConvertError.Create('Invalid issue identity');
      if (Issue.Find('pull_request')<>nil) then Continue;
      Id:=Value.AsString;
      Closed:=Issue.Get('state','')='closed';
      if GitLab then
      begin
        Description:=Issue.Get('description','');
        Url:=Issue.Get('web_url','');
        Data:=Issue.Find('author');
      end
      else
      begin
        Description:=Issue.Get('body','');
        Url:=Issue.Get('html_url','');
        Data:=Issue.Find('user');
      end;
      if Url<>'' then Description:=Description+LineEnding+LineEnding+Url;
      Card:=TJSONObject.Create(['_id',Id,'title',Issue.Get('title',''),'description',Description,
        'listId',IfThen(Closed,'closed','open'),'dueComplete',Closed,'sort',I]);
      Cards.Add(Card);
      Author:=ImportAuthorIdentity(Authors,AuthorName(Data));
      if Author<>'' then Card.Add('userId',Author);
      Due:=Issue.Get('due_date','');
      Value:=Issue.Find('milestone');
      if (Due='') and (Value is TJSONObject) then
        Due:=TJSONObject(Value).Get('due_on',TJSONObject(Value).Get('due_date',''));
      if Due<>'' then Card.Add('dueAt',Due);
      if Issue.Get('created_at','')<>'' then Card.Add('createdAt',Issue.Get('created_at',''));
      if Issue.Get('closed_at','')<>'' then Card.Add('endAt',Issue.Get('closed_at',''));
      Tags:=TJSONArray.Create; Card.Add('labelIds',Tags);
      Data:=Issue.Find('labels');
      if Data is TJSONArray then for J:=0 to Data.Count-1 do
      begin
        Value:=Data.Items[J];
        if Value is TJSONObject then Name:=TJSONObject(Value).Get('name','')
        else if Value is TJSONString then Name:=Value.AsString else Continue;
        if Name='' then Continue;
        LabelId:=LabelFor(Name);
        Tags.Add(LabelId);
      end;
      Data:=Issue.Find('notes');
      if not (Data is TJSONArray) then Data:=Issue.Find('comments_data');
      if not (Data is TJSONArray) then Data:=Issue.Find('comments');
      if Data is TJSONArray then for K:=0 to Data.Count-1 do
      begin
        if not (Data.Items[K] is TJSONObject) then Continue;
        Note:=TJSONObject(Data.Items[K]);
        if Note.Get('system',False) or (Note.Get('body','')='') then Continue;
        Value:=Note.Find('author');
        if Value=nil then Value:=Note.Find('user');
        Author:=ImportAuthorIdentity(Authors,AuthorName(Value));
        Value:=TJSONObject.Create(['_id',Id+':comment:'+IntToStr(K),'cardId',Id,'text',Note.Get('body',''),'userId',Author]);
        Comments.Add(Value);
        if Note.Get('created_at','')<>'' then TJSONObject(Value).Add('createdAt',Note.Get('created_at',''));
      end;
    end;
  except Result.Free; raise; end;
end;

function AsanaImport(const Source: TJSONData): TJSONObject;
var Board, Authors, Task, Card, Entry, Comment, Field: TJSONObject;
  Lists, Cards, Labels, Comments, Checks, Items, Definitions, Tags, Fields: TJSONArray;
  Tasks, Data, Value, Child: TJSONData; I,J: Integer; Id, ListId, Title, Name, CheckId, FieldId, Kind: string;
  function ChildObject(Obj: TJSONObject; const Key: string): TJSONObject;
  var V: TJSONData;
  begin
    V:=Obj.Find(Key);
    if V is TJSONObject then Result:=TJSONObject(V) else Result:=nil;
  end;
  procedure AddNamed(Rows: TJSONArray; const Id, NameKey, Name, Kind: string);
  var K: Integer; Row: TJSONObject;
  begin
    for K:=0 to Rows.Count-1 do if Rows.Objects[K].Get('_id','')=Id then Exit;
    Row:=TJSONObject.Create(['_id',Id,NameKey,Name,'sort',Rows.Count]);
    if Kind<>'' then Row.Add('type',Kind);
    Rows.Add(Row);
  end;
  procedure CopyDate(Obj, Target: TJSONObject; const SourceKey, TargetKey: string);
  begin
    if Obj.Get(SourceKey,'')<>'' then Target.Add(TargetKey,Obj.Get(SourceKey,''));
  end;
begin
  Tasks:=Source;
  if Source is TJSONObject then Tasks:=TJSONObject(Source).Find('data');
  if not (Tasks is TJSONArray) then raise EConvertError.Create('Invalid Asana task export');
  Result:=TJSONObject.Create;
  try
    Board:=TJSONObject.Create; Result.Add('board',Board);
    Authors:=TJSONObject.Create; Result.Add('importedAuthors',Authors);
    Lists:=TJSONArray.Create; Board.Add('lists',Lists);
    Cards:=TJSONArray.Create; Board.Add('cards',Cards);
    Labels:=TJSONArray.Create; Board.Add('labels',Labels);
    Comments:=TJSONArray.Create; Board.Add('comments',Comments);
    Checks:=TJSONArray.Create; Board.Add('checklists',Checks);
    Items:=TJSONArray.Create; Board.Add('checklistItems',Items);
    Definitions:=TJSONArray.Create; Board.Add('customFields',Definitions);
    Title:='';
    for I:=0 to Tasks.Count-1 do
    begin
      if not (Tasks.Items[I] is TJSONObject) then raise EConvertError.Create('Invalid Asana task');
      Task:=TJSONObject(Tasks.Items[I]);
      Id:=Task.Get('gid','');
      if (Id='') or (Trim(Task.Get('name',''))='') then raise EConvertError.Create('Invalid Asana task identity');
      ListId:='unsectioned'; Name:='Tasks';
      Data:=Task.Find('memberships');
      if Data is TJSONArray then for J:=0 to Data.Count-1 do
      begin
        if not (Data.Items[J] is TJSONObject) then Continue;
        Entry:=TJSONObject(Data.Items[J]);
        Field:=ChildObject(Entry,'project');
        if (Title='') and (Field<>nil) then Title:=Field.Get('name','');
        Field:=ChildObject(Entry,'section');
        if (Field=nil) or (Field.Get('gid','')='') then Continue;
        ListId:=Field.Get('gid',''); Name:=Field.Get('name','Tasks'); Break;
      end;
      AddNamed(Lists,ListId,'title',Name,'');
      Card:=TJSONObject.Create(['_id',Id,'listId',ListId,'title',Task.Get('name',''),
        'description',Task.Get('notes',''),'dueComplete',Task.Get('completed',False),'sort',I]);
      Cards.Add(Card);
      if Task.Get('due_at','')<>'' then CopyDate(Task,Card,'due_at','dueAt') else CopyDate(Task,Card,'due_on','dueAt');
      if Task.Get('start_at','')<>'' then CopyDate(Task,Card,'start_at','startAt') else CopyDate(Task,Card,'start_on','startAt');
      CopyDate(Task,Card,'created_at','createdAt'); CopyDate(Task,Card,'completed_at','endAt');
      Tags:=TJSONArray.Create; Card.Add('labelIds',Tags);
      Data:=Task.Find('tags');
      if Data is TJSONArray then for J:=0 to Data.Count-1 do
      begin
        if not (Data.Items[J] is TJSONObject) then Continue;
        Entry:=TJSONObject(Data.Items[J]); Name:=Entry.Get('name','');
        if Name='' then Continue;
        FieldId:=Entry.Get('gid',Name);
        AddNamed(Labels,FieldId,'name',Name,''); Tags.Add(FieldId);
      end;
      Data:=Task.Find('subtasks');
      if (Data is TJSONArray) and (Data.Count>0) then
      begin
        CheckId:=Id+':subtasks';
        Checks.Add(TJSONObject.Create(['_id',CheckId,'cardId',Id,'title','Subtasks','sort',0]));
        for J:=0 to Data.Count-1 do
        begin
          if not (Data.Items[J] is TJSONObject) then Continue;
          Entry:=TJSONObject(Data.Items[J]);
          Items.Add(TJSONObject.Create(['_id',CheckId+':'+IntToStr(J),'checklistId',CheckId,
            'title',Entry.Get('name',''),'isFinished',Entry.Get('completed',False),'sort',J]));
        end;
      end;
      Fields:=TJSONArray.Create; Card.Add('customFields',Fields);
      Data:=Task.Find('custom_fields');
      if Data is TJSONArray then for J:=0 to Data.Count-1 do
      begin
        if not (Data.Items[J] is TJSONObject) then Continue;
        Entry:=TJSONObject(Data.Items[J]); FieldId:=Entry.Get('gid',''); Name:=Entry.Get('name','');
        if (FieldId='') or (Name='') then Continue;
        Kind:='text';
        case Entry.Get('resource_subtype','') of
          'number': begin Kind:='number'; Value:=Entry.Find('number_value'); end;
          'enum': begin
            Child:=Entry.Find('enum_value'); Value:=nil;
            if Child is TJSONObject then Value:=TJSONObject(Child).Find('name');
          end;
          'text': Value:=Entry.Find('text_value');
          else Value:=Entry.Find('display_value');
        end;
        if (Value=nil) or (Value.JSONType=jtNull) then Continue;
        AddNamed(Definitions,FieldId,'name',Name,Kind);
        Field:=TJSONObject.Create(['_id',FieldId]); Fields.Add(Field); Field.Add('value',Value.Clone);
      end;
      Data:=Task.Find('stories');
      if Data is TJSONArray then for J:=0 to Data.Count-1 do
      begin
        if not (Data.Items[J] is TJSONObject) then Continue;
        Entry:=TJSONObject(Data.Items[J]);
        if Entry.Get('resource_subtype','')<>'comment_added' then Continue;
        Comment:=TJSONObject.Create(['_id',Id+':comment:'+IntToStr(J),'cardId',Id,'text',Entry.Get('text','')]);
        Comments.Add(Comment);
        Field:=ChildObject(Entry,'created_by');
        if Field<>nil then Comment.Add('userId',ImportAuthorIdentity(Authors,Field.Get('name','')));
        CopyDate(Entry,Comment,'created_at','createdAt');
      end;
    end;
    if Title='' then Title:='Asana tasks';
    Board.Add('title',Title);
  except Result.Free; raise; end;
end;

function OpenProjectImport(const Source: TJSONData): TJSONObject;
var Board, Authors, Package, Card, Links, Embedded, Schema, Definition, Comment, RelationLinks: TJSONObject;
  Lists, Cards, Labels, Comments, Definitions, Tags, Fields, Dependencies: TJSONArray;
  Packages, Activities, Relations, Data, Value: TJSONData; I,J: Integer; Id, ListId, ProjectTitle, Name, Key, Kind, Text, Target: string;
  Hours: Double;
  function Obj(Data: TJSONData; const Key: string): TJSONObject;
  var Field: TJSONData;
  begin
    Result:=nil;
    if not (Data is TJSONObject) then Exit;
    Field:=TJSONObject(Data).Find(Key);
    if Field is TJSONObject then Result:=TJSONObject(Field);
  end;
  function Str(Data: TJSONObject; const Key: string): string;
  begin
    Result:='';
    if Data<>nil then Result:=Data.Get(Key,'');
  end;
  function Reference(Link: TJSONObject): string;
  var Path: string; Slash, Delimiter: Integer;
  begin
    Path:=Str(Link,'href');
    Delimiter:=Pos('?',Path);
    if Delimiter>0 then SetLength(Path,Delimiter-1);
    Delimiter:=Pos('#',Path);
    if Delimiter>0 then SetLength(Path,Delimiter-1);
    Slash:=LastDelimiter('/',Path);
    Result:=Copy(Path,Slash+1,MaxInt);
  end;
  procedure AddNamed(Rows: TJSONArray; const Id, NameKey, Name, Kind: string);
  var K: Integer; Row: TJSONObject;
  begin
    for K:=0 to Rows.Count-1 do if Rows.Objects[K].Get('_id','')=Id then Exit;
    Row:=TJSONObject.Create(['_id',Id,NameKey,Name,'sort',Rows.Count]);
    if Kind<>'' then Row.Add('type',Kind);
    Rows.Add(Row);
  end;
  procedure AddField(const Key, Name, Kind: string; Value: TJSONData);
  var Field: TJSONObject;
  begin
    if (Name='') or (Value=nil) or (Value.JSONType=jtNull) then Exit;
    AddNamed(Definitions,Key,'name',Name,Kind);
    Field:=TJSONObject.Create(['_id',Key]); Fields.Add(Field); Field.Add('value',Value.Clone);
  end;
  procedure AddDate(FromRow, ToRow: TJSONObject; const SourceKey, TargetKey: string);
  begin
    if Str(FromRow,SourceKey)<>'' then ToRow.Add(TargetKey,Str(FromRow,SourceKey));
  end;
  function Duration(const Value: string; out Total: Double): Boolean;
  var K, Start: Integer; Number, Factor: Double; InTime: Boolean; Decimal: TFormatSettings;
  begin
    Total:=0; Result:=False;
    if (Length(Value)<2) or (Value[1]<>'P') then Exit;
    Decimal:=DefaultFormatSettings; Decimal.DecimalSeparator:='.';
    K:=2; InTime:=False;
    while K<=Length(Value) do
    begin
      if (Value[K]='T') and not InTime then begin InTime:=True; Inc(K); end;
      Start:=K;
      while (K<=Length(Value)) and (Value[K] in ['0'..'9','.']) do Inc(K);
      if (K>Length(Value)) or (K=Start) or not TryStrToFloat(Copy(Value,Start,K-Start),Number,Decimal) then Exit(False);
      case Value[K] of
        'D': if InTime then Exit(False) else Factor:=24;
        'H': if not InTime then Exit(False) else Factor:=1;
        'M': if not InTime then Exit(False) else Factor:=1/60;
        'S': if not InTime then Exit(False) else Factor:=1/3600;
        else Exit(False);
      end;
      Total:=Total+Number*Factor;
      Inc(K);
    end;
    Result:=not IsInfinite(Total) and not IsNan(Total);
  end;
begin
  Packages:=Source;
  if Source is TJSONObject then
  begin
    Embedded:=Obj(Source,'_embedded');
    if Embedded=nil then raise EConvertError.Create('Invalid OpenProject collection');
    Packages:=Embedded.Find('elements');
  end;
  if not (Packages is TJSONArray) then raise EConvertError.Create('Invalid OpenProject export');
  Result:=TJSONObject.Create;
  try
    Board:=TJSONObject.Create; Result.Add('board',Board);
    Authors:=TJSONObject.Create; Result.Add('importedAuthors',Authors);
    Lists:=TJSONArray.Create; Board.Add('lists',Lists);
    Cards:=TJSONArray.Create; Board.Add('cards',Cards);
    Labels:=TJSONArray.Create; Board.Add('labels',Labels);
    Comments:=TJSONArray.Create; Board.Add('comments',Comments);
    Definitions:=TJSONArray.Create; Board.Add('customFields',Definitions);
    ProjectTitle:='';
    for I:=0 to Packages.Count-1 do
    begin
      if not (Packages.Items[I] is TJSONObject) then raise EConvertError.Create('Invalid work package');
      Package:=TJSONObject(Packages.Items[I]);
      Value:=Package.Find('id');
      if (Value=nil) or not (Value.JSONType in [jtString,jtNumber]) or (Trim(Str(Package,'subject'))='') then
        raise EConvertError.Create('Invalid work package identity');
      Id:=Value.AsString;
      Links:=Obj(Package,'_links'); Embedded:=Obj(Package,'_embedded'); Schema:=Obj(Embedded,'schema');
      if ProjectTitle='' then ProjectTitle:=Str(Obj(Links,'project'),'title');
      Name:=Str(Obj(Links,'status'),'title');
      if Name='' then Name:='Work packages';
      ListId:=Str(Obj(Links,'status'),'href');
      if ListId='' then ListId:=Name;
      AddNamed(Lists,ListId,'title',Name,'');
      Card:=TJSONObject.Create(['_id',Id,'listId',ListId,'title',Str(Package,'subject'),
        'description',Str(Obj(Package,'description'),'raw'),'sort',I]);
      Cards.Add(Card);
      Name:=ImportAuthorIdentity(Authors,Str(Obj(Links,'author'),'title'));
      if Name<>'' then Card.Add('userId',Name);
      AddDate(Package,Card,'dueDate','dueAt'); AddDate(Package,Card,'startDate','startAt');
      AddDate(Package,Card,'createdAt','createdAt'); AddDate(Package,Card,'updatedAt','modifiedAt');
      if Duration(Str(Package,'spentTime'),Hours) then Card.Add('spentTime',Hours);
      Tags:=TJSONArray.Create; Card.Add('labelIds',Tags);
      for Key in ['type','priority'] do
      begin
        Name:=Str(Obj(Links,Key),'title');
        if Name='' then Continue;
        if Key='priority' then Name:='priority:'+Name;
        AddNamed(Labels,Name,'name',Name,''); Tags.Add(Name);
      end;
      Fields:=TJSONArray.Create; Card.Add('customFields',Fields);
      if Duration(Str(Package,'estimatedTime'),Hours) then
      begin
        Value:=TJSONFloatNumber.Create(Hours);
        try AddField('estimatedTime','Estimated time (hours)','number',Value); finally Value.Free; end;
      end;
      AddField('percentageDone','Progress (%)','number',Package.Find('percentageDone'));
      if Schema<>nil then for J:=0 to Schema.Count-1 do
      begin
        Key:=Schema.Names[J];
        if not AnsiStartsStr('customField',Key) then Continue;
        Definition:=Obj(Schema,Key); Name:=Str(Definition,'name');
        Kind:='text'; Value:=Package.Find(Key);
        if Str(Definition,'type')='CustomOption' then
        begin
          Text:=Str(Obj(Links,Key),'title');
          if Text<>'' then
          begin
            Value:=TJSONString.Create(Text);
            try AddField(Key,Name,Kind,Value); finally Value.Free; end;
          end;
          Continue;
        end;
        if Str(Definition,'type')='Integer' then Kind:='number'
        else if Str(Definition,'type')='Float' then Kind:='number';
        AddField(Key,Name,Kind,Value);
      end;
      Target:=Reference(Obj(Links,'parent'));
      if (Target<>'') and (Target<>Id) then Card.Add('parentId',Target);
      Data:=Obj(Embedded,'relations');
      if Data<>nil then
      begin
        Relations:=TJSONObject(Data).Find('elements');
        if Relations is TJSONArray then
        begin
          Dependencies:=TJSONArray.Create; Card.Add('cardDependencies',Dependencies);
          for J:=0 to Relations.Count-1 do
          begin
            Data:=Relations.Items[J];
            RelationLinks:=Obj(Data,'_links');
            if Reference(Obj(RelationLinks,'from'))<>Id then Continue;
            Target:=Reference(Obj(RelationLinks,'to'));
            if (Target='') or (Target=Id) then Continue;
            case Str(TJSONObject(Data),'type') of
              'blocks': Kind:='blocks';
              'blocked': Kind:='is-blocked-by';
              'duplicates': Kind:='duplicates';
              'duplicated': Kind:='is-duplicated-by';
              else Kind:='related-to';
            end;
            Dependencies.Add(TJSONObject.Create(['cardId',Target,'type',Kind]));
          end;
        end;
      end;
      Data:=Obj(Embedded,'activities');
      if Data=nil then Continue;
      Activities:=TJSONObject(Data).Find('elements');
      if Activities is TJSONArray then for J:=0 to Activities.Count-1 do
      begin
        if not (Activities.Items[J] is TJSONObject) then Continue;
        Data:=Activities.Items[J];
        Text:=Str(Obj(Data,'comment'),'raw');
        if Text='' then Continue;
        Name:=ImportAuthorIdentity(Authors,Str(Obj(Obj(Data,'_links'),'user'),'title'));
        Comment:=TJSONObject.Create(['_id',Id+':comment:'+IntToStr(J),'cardId',Id,'text',Text,'userId',Name]);
        Comments.Add(Comment);
        AddDate(TJSONObject(Data),Comment,'createdAt','createdAt');
      end;
    end;
    if ProjectTitle='' then ProjectTitle:='OpenProject work packages';
    Board.Add('title',ProjectTitle);
  except Result.Free; raise; end;
end;

function ZenkitImport(const Source: TJSONData): TJSONObject;
var Input, Board, Authors, Entry, Card, Element, Check, Child, Field: TJSONObject;
  Lists, Cards, Labels, Comments, Checks, Items, Definitions, Tags, Fields: TJSONArray;
  Entries, Schema, Data, Value, Row: TJSONData; I,J,K: Integer; IsApi: Boolean;
  Title, Id, Stage, Name, Key, CheckId, Author, Kind: string;
  procedure AddNamed(Rows: TJSONArray; const Id, NameKey, Name, Kind: string);
  var A: Integer; Added: TJSONObject;
  begin
    for A:=0 to Rows.Count-1 do if Rows.Objects[A].Get('_id','')=Id then Exit;
    Added:=TJSONObject.Create(['_id',Id,NameKey,Name,'sort',Rows.Count]);
    if Kind<>'' then Added.Add('type',Kind);
    Rows.Add(Added);
  end;
  procedure AddTag(const Name: string);
  begin
    if Name='' then Exit;
    AddNamed(Labels,Name,'name',Name,'');
    Tags.Add(Name);
  end;
  procedure AddField(const Key, Name: string; Value: TJSONData);
  begin
    if (Name='') or (Value=nil) or not (Value.JSONType in [jtNumber,jtString,jtBoolean]) then Exit;
    Kind:='text';
    if Value.JSONType=jtNumber then Kind:='number';
    if Value.JSONType=jtBoolean then Kind:='checkbox';
    AddNamed(Definitions,Key,'name',Name,Kind);
    Field:=TJSONObject.Create(['_id',Key]); Fields.Add(Field); Field.Add('value',Value.Clone);
  end;
  procedure CopyText(FromRow, ToRow: TJSONObject; const FromKey, ToKey: string);
  var Text: string;
  begin
    Text:=FromRow.Get(FromKey,'');
    if Text<>'' then ToRow.Add(ToKey,Text);
  end;
  procedure ReadApiEntry;
  var A,B, Category: Integer; Suffix, Column, Semantic: string; V, CategoryRow: TJSONData;
  begin
    for A:=0 to Schema.Count-1 do
    begin
      if not (Schema.Items[A] is TJSONObject) then Continue;
      Element:=TJSONObject(Schema.Items[A]);
      Column:=Element.Get('uuid','');
      if Column='' then Continue;
      Semantic:=LowerCase(Element.Get('name',''));
      Category:=Element.Get('elementcategory',0);
      if Element.Get('isPrimary',False) then
      begin
        if Entry.Get(Column+'_text','')<>'' then
        begin Card.Delete('title'); Card.Add('title',Entry.Get(Column+'_text','')); end;
        Continue;
      end;
      if (Category=1) and (Semantic='description') then
      begin CopyText(Entry,Card,Column+'_text','description'); Continue; end;
      if (Category=4) and ((Semantic='due date') or (Semantic='due')) then
      begin CopyText(Entry,Card,Column+'_date','dueAt'); Continue; end;
      if Category=6 then
      begin
        V:=Entry.Find(Column+'_categories_sort');
        if not (V is TJSONArray) then Continue;
        for B:=0 to V.Count-1 do
        begin
          CategoryRow:=V.Items[B];
          if not (CategoryRow is TJSONObject) then Continue;
          Name:=TJSONObject(CategoryRow).Get('name','');
          if (Name<>'') and ((Semantic='stage') or (Semantic='status')) then
          begin Stage:=Name; Break; end;
          if (Semantic='labels') or (Semantic='tags') then AddTag(Name);
        end;
        Continue;
      end;
      if (Category=17) and (Semantic='parent') then
      begin
        V:=Entry.Find(Column+'_references_sort');
        if (V is TJSONArray) and (V.Count>0) and (V.Items[0] is TJSONObject) then
          CopyText(TJSONObject(V.Items[0]),Card,'uuid','parentId');
        Continue;
      end;
      case Category of
        1: Suffix:='_text';
        2: Suffix:='_number';
        4: Suffix:='_date';
        else Continue;
      end;
      AddField(Column,Element.Get('name',''),Entry.Find(Column+Suffix));
    end;
  end;
begin
  if not (Source is TJSONObject) then raise EConvertError.Create('Invalid Zenkit export');
  Input:=TJSONObject(Source);
  Entries:=Input.Find('items'); Schema:=Input.Find('elements');
  IsApi:=not (Entries is TJSONArray);
  Title:=Input.Get('title','');
  if IsApi then
  begin
    Entries:=Input.Find('entries');
    Data:=Input.Find('list');
    if not (Schema is TJSONArray) or not (Data is TJSONObject) then raise EConvertError.Create('Invalid Zenkit API export');
    Title:=TJSONObject(Data).Get('name','');
  end;
  if not (Entries is TJSONArray) or (Trim(Title)='') then raise EConvertError.Create('Invalid Zenkit export');
  Result:=TJSONObject.Create;
  try
    Board:=TJSONObject.Create(['title',Title]); Result.Add('board',Board);
    Authors:=TJSONObject.Create; Result.Add('importedAuthors',Authors);
    Lists:=TJSONArray.Create; Board.Add('lists',Lists);
    Cards:=TJSONArray.Create; Board.Add('cards',Cards);
    Labels:=TJSONArray.Create; Board.Add('labels',Labels);
    Comments:=TJSONArray.Create; Board.Add('comments',Comments);
    Checks:=TJSONArray.Create; Board.Add('checklists',Checks);
    Items:=TJSONArray.Create; Board.Add('checklistItems',Items);
    Definitions:=TJSONArray.Create; Board.Add('customFields',Definitions);
    Data:=Input.Find('stages');
    if Data is TJSONArray then for I:=0 to Data.Count-1 do
      if Data.Items[I] is TJSONObject then
      begin
        Name:=TJSONObject(Data.Items[I]).Get('name','');
        if Name<>'' then AddNamed(Lists,Name,'title',Name,'');
      end;
    for I:=0 to Entries.Count-1 do
    begin
      if not (Entries.Items[I] is TJSONObject) then raise EConvertError.Create('Invalid Zenkit item');
      Entry:=TJSONObject(Entries.Items[I]);
      if Entry.Get('deprecated_at','')<>'' then Continue;
      Id:=Entry.Get('id',Entry.Get('uuid',''));
      if Id='' then raise EConvertError.Create('Missing Zenkit item identity');
      Card:=TJSONObject.Create(['_id',Id,'title',Entry.Get('title',Entry.Get('displayString','')),
        'sort',Entry.Get('sortOrder',I)]);
      Cards.Add(Card);
      Fields:=TJSONArray.Create; Card.Add('customFields',Fields);
      Tags:=TJSONArray.Create; Card.Add('labelIds',Tags);
      Stage:=Entry.Get('stage_name','Tasks');
      CopyText(Entry,Card,'created_at','createdAt');
      if IsApi then ReadApiEntry
      else
      begin
        CopyText(Entry,Card,'description','description');
        CopyText(Entry,Card,'due','dueAt');
        Data:=Entry.Find('tags');
        if Data is TJSONArray then for J:=0 to Data.Count-1 do
          if Data.Items[J] is TJSONString then AddTag(Data.Items[J].AsString);
        Data:=Entry.Find('fields');
        if Data is TJSONObject then for J:=0 to Data.Count-1 do
        begin
          Key:=TJSONObject(Data).Names[J];
          AddField(Key,Key,Data.Items[J]);
        end;
      end;
      AddNamed(Lists,Stage,'title',Stage,''); Card.Add('listId',Stage);
      Data:=Entry.Find('checklists');
      if Data is TJSONArray then for J:=0 to Data.Count-1 do
      begin
        if not (Data.Items[J] is TJSONObject) then Continue;
        Check:=TJSONObject(Data.Items[J]); CheckId:=Id+':checklist:'+IntToStr(J);
        Checks.Add(TJSONObject.Create(['_id',CheckId,'cardId',Id,'title',Check.Get('name','Checklist'),'sort',J]));
        Row:=Check.Find('items');
        if Row is TJSONArray then for K:=0 to Row.Count-1 do
        begin
          if not (Row.Items[K] is TJSONObject) then Continue;
          Child:=TJSONObject(Row.Items[K]);
          Items.Add(TJSONObject.Create(['_id',CheckId+':'+IntToStr(K),'checklistId',CheckId,'title',Child.Get('text',''),
            'isFinished',Child.Get('checked',False),'sort',K]));
        end;
      end;
      Data:=Entry.Find('comments');
      if Data is TJSONArray then for J:=0 to Data.Count-1 do
      begin
        if not (Data.Items[J] is TJSONObject) then Continue;
        Child:=TJSONObject(Data.Items[J]);
        Author:=ImportAuthorIdentity(Authors,Child.Get('author',''));
        Value:=TJSONObject.Create(['_id',Id+':comment:'+IntToStr(J),'cardId',Id,'text',Child.Get('text',''),'userId',Author]);
        Comments.Add(Value); CopyText(Child,TJSONObject(Value),'date','createdAt');
      end;
    end;
  except Result.Free; raise; end;
end;

function JiraImport(const Source: TJSONData): TJSONObject;
var Board, Authors, Issue, JiraFields, Card, Names, Entry, Person, Part, Field: TJSONObject;
  Lists, Cards, Labels, Comments, Checks, Items, Definitions, Tags, Fields: TJSONArray;
  Issues, Data, Value: TJSONData; I,J: Integer;
  Id, ListId, Name, Title, Key, Kind, Text, Author, CheckId, SubtaskTitle: string;
  function Obj(Data: TJSONData; const Key: string): TJSONObject;
  var V: TJSONData;
  begin
    Result:=nil;
    if not (Data is TJSONObject) then Exit;
    V:=TJSONObject(Data).Find(Key);
    if V is TJSONObject then Result:=TJSONObject(V);
  end;
  function Str(Data: TJSONObject; const Key: string): string;
  begin
    Result:='';
    if Data<>nil then Result:=Data.Get(Key,'');
  end;
  function RichText(Value: TJSONData; Depth: Integer): string;
  var Content: TJSONData; Node: TJSONObject; NodeType: string; K: Integer;
  begin
    Result:='';
    if Depth>64 then raise EConvertError.Create('Jira rich text nesting is too deep');
    if Value is TJSONString then Exit(Value.AsString);
    if not (Value is TJSONObject) then Exit;
    Node:=TJSONObject(Value); NodeType:=Node.Get('type','');
    if NodeType='text' then Exit(Node.Get('text',''));
    if NodeType='hardBreak' then Exit(LineEnding);
    Content:=Node.Find('content');
    if not (Content is TJSONArray) then Exit;
    for K:=0 to Content.Count-1 do
    begin
      if (K>0) and ((NodeType='doc') or (NodeType='bulletList') or (NodeType='orderedList')) then Result:=Result+LineEnding;
      Result:=Result+RichText(Content.Items[K],Depth+1);
    end;
  end;
  procedure AddNamed(Rows: TJSONArray; const Id, NameKey, Name, Kind: string);
  var K: Integer; Added: TJSONObject;
  begin
    for K:=0 to Rows.Count-1 do if Rows.Objects[K].Get('_id','')=Id then Exit;
    Added:=TJSONObject.Create(['_id',Id,NameKey,Name,'sort',Rows.Count]);
    if Kind<>'' then Added.Add('type',Kind);
    Rows.Add(Added);
  end;
  procedure AddTag(const Name: string);
  begin
    if Name='' then Exit;
    AddNamed(Labels,Name,'name',Name,'');
    Tags.Add(Name);
  end;
  procedure AddDate(FromRow, ToRow: TJSONObject; const SourceKey, TargetKey: string);
  var DateText: string; Offset: Integer;
  begin
    DateText:=Str(FromRow,SourceKey);
    if DateText='' then Exit;
    Offset:=Length(DateText)-4;
    if (Offset>10) and (DateText[Offset] in ['+','-']) and (Pos(':',Copy(DateText,Offset,MaxInt))=0) then
      Insert(':',DateText,Offset+3);
    ToRow.Add(TargetKey,DateText);
  end;
begin
  Issues:=Source;
  Names:=Obj(Source,'names');
  if Source is TJSONObject then Issues:=TJSONObject(Source).Find('issues');
  if not (Issues is TJSONArray) then raise EConvertError.Create('Invalid Jira issue export');
  Result:=TJSONObject.Create;
  try
    Board:=TJSONObject.Create; Result.Add('board',Board);
    Authors:=TJSONObject.Create; Result.Add('importedAuthors',Authors);
    Lists:=TJSONArray.Create; Board.Add('lists',Lists);
    Cards:=TJSONArray.Create; Board.Add('cards',Cards);
    Labels:=TJSONArray.Create; Board.Add('labels',Labels);
    Comments:=TJSONArray.Create; Board.Add('comments',Comments);
    Checks:=TJSONArray.Create; Board.Add('checklists',Checks);
    Items:=TJSONArray.Create; Board.Add('checklistItems',Items);
    Definitions:=TJSONArray.Create; Board.Add('customFields',Definitions);
    Title:='';
    for I:=0 to Issues.Count-1 do
    begin
      if not (Issues.Items[I] is TJSONObject) then raise EConvertError.Create('Invalid Jira issue');
      Issue:=TJSONObject(Issues.Items[I]); JiraFields:=Obj(Issue,'fields');
      Id:=Issue.Get('id',Issue.Get('key',''));
      if (Id='') or (Trim(Str(JiraFields,'summary'))='') then raise EConvertError.Create('Invalid Jira issue identity');
      if Title='' then Title:=Str(Obj(JiraFields,'project'),'name');
      Name:=Str(Obj(JiraFields,'status'),'name');
      if Name='' then Name:='Issues';
      ListId:=Name; AddNamed(Lists,ListId,'title',Name,'');
      Card:=TJSONObject.Create(['_id',Id,'title',JiraFields.Get('summary',''),'listId',ListId,'sort',I,
        'description',RichText(JiraFields.Find('description'),0),
        'dueComplete',Str(Obj(Obj(JiraFields,'status'),'statusCategory'),'key')='done']);
      Cards.Add(Card);
      AddDate(JiraFields,Card,'duedate','dueAt'); AddDate(JiraFields,Card,'created','createdAt');
      AddDate(JiraFields,Card,'updated','modifiedAt'); AddDate(JiraFields,Card,'resolutiondate','endAt');
      Person:=Obj(JiraFields,'reporter');
      Author:=ImportAuthorIdentity(Authors,Str(Person,'displayName'));
      if Author<>'' then Card.Add('userId',Author);
      Tags:=TJSONArray.Create; Card.Add('labelIds',Tags);
      Data:=JiraFields.Find('labels');
      if Data is TJSONArray then for J:=0 to Data.Count-1 do
        if Data.Items[J] is TJSONString then AddTag(Data.Items[J].AsString);
      Name:=Str(Obj(JiraFields,'priority'),'name');
      if Name<>'' then AddTag('priority:'+Name);
      for Key in ['components','fixVersions'] do
      begin
        Data:=JiraFields.Find(Key);
        if not (Data is TJSONArray) then Continue;
        for J:=0 to Data.Count-1 do
        begin
          if not (Data.Items[J] is TJSONObject) then Continue;
          Name:=Str(TJSONObject(Data.Items[J]),'name');
          if (Name<>'') and (Key='fixVersions') then Name:='version:'+Name;
          AddTag(Name);
        end;
      end;
      Fields:=TJSONArray.Create; Card.Add('customFields',Fields);
      for J:=0 to JiraFields.Count-1 do
      begin
        Key:=JiraFields.Names[J]; Value:=JiraFields.Items[J];
        if not AnsiStartsStr('customfield_',Key) then Continue;
        if Value is TJSONObject then Value:=TJSONObject(Value).Find('value');
        if (Value=nil) or not (Value.JSONType in [jtString,jtNumber,jtBoolean]) then Continue;
        Name:=Str(Names,Key); if Name='' then Name:=Key;
        Kind:='text';
        if Value.JSONType=jtNumber then Kind:='number';
        if Value.JSONType=jtBoolean then Kind:='checkbox';
        AddNamed(Definitions,Key,'name',Name,Kind);
        Field:=TJSONObject.Create(['_id',Key]); Fields.Add(Field); Field.Add('value',Value.Clone);
      end;
      Data:=Obj(JiraFields,'comment');
      if Data<>nil then Data:=TJSONObject(Data).Find('comments');
      if Data is TJSONArray then for J:=0 to Data.Count-1 do
      begin
        if not (Data.Items[J] is TJSONObject) then Continue;
        Entry:=TJSONObject(Data.Items[J]); Text:=RichText(Entry.Find('body'),0);
        if Text='' then Continue;
        Name:=Str(Obj(Entry,'author'),'displayName');
        if Name<>'' then Text:=Name+': '+Text;
        Part:=TJSONObject.Create(['_id',Id+':comment:'+IntToStr(J),'cardId',Id,'text',Text]);
        Comments.Add(Part); AddDate(Entry,Part,'created','createdAt');
      end;
      Data:=JiraFields.Find('subtasks');
      if (Data is TJSONArray) and (Data.Count>0) then
      begin
        CheckId:=Id+':subtasks';
        Checks.Add(TJSONObject.Create(['_id',CheckId,'cardId',Id,'title','Subtasks','sort',0]));
        for J:=0 to Data.Count-1 do
        begin
          if not (Data.Items[J] is TJSONObject) then Continue;
          Entry:=TJSONObject(Data.Items[J]); Part:=Obj(Entry,'fields');
          SubtaskTitle:=Str(Part,'summary'); Name:=Entry.Get('key','');
          if Name<>'' then SubtaskTitle:='['+Name+'] '+SubtaskTitle;
          Items.Add(TJSONObject.Create(['_id',CheckId+':'+IntToStr(J),'checklistId',CheckId,'title',SubtaskTitle,
            'sort',J,'isFinished',Str(Obj(Obj(Part,'status'),'statusCategory'),'key')='done']));
        end;
      end;
    end;
    if Title='' then Title:='Jira issues';
    Board.Add('title',Title);
  except Result.Free; raise; end;
end;

function KanriImport(const Source: TJSONData): TJSONObject;
var Input, Board, Column, Entry, Card, Tag, Task: TJSONObject;
  Lists, Cards, Labels, Checks, Items, Tags: TJSONArray;
  Columns, ColumnCards, Data: TJSONData; I,J,K: Integer;
  CardId, ListId, CheckId, Color, Name: string;
  function KanriColor(const Raw: string): string;
  var Parts: TStringArray;
  begin
    Result:=LowerCase(Trim(Raw));
    if AnsiStartsStr('bg-',Result) then
    begin
      Parts:=Result.Split(['-']);
      if Length(Parts)>1 then Result:=Parts[1];
    end;
    if ResolveColor(Result)='' then Result:='';
  end;
  function LabelFor(Tag: TJSONObject): string;
  var K: Integer; Title, Color: string;
  begin
    Title:=Tag.Get('text','');
    if Title='' then Exit('');
    Result:=Tag.Get('id',Title);
    for K:=0 to Labels.Count-1 do if Labels.Objects[K].Get('_id','')=Result then Exit;
    Color:=KanriColor(Tag.Get('color',''));
    if Color='' then Color:='blue';
    Labels.Add(TJSONObject.Create(['_id',Result,'name',Title,'color',Color]));
  end;
begin
  if not (Source is TJSONObject) then raise EConvertError.Create('Invalid Kanri board export');
  Input:=TJSONObject(Source); Columns:=Input.Find('columns');
  if not (Columns is TJSONArray) or (Trim(Input.Get('title',''))='') then
    raise EConvertError.Create('Invalid Kanri board export');
  Result:=TJSONObject.Create;
  try
    Board:=TJSONObject.Create(['title',Input.Get('title','')]); Result.Add('board',Board);
    Result.Add('importedAuthors',TJSONObject.Create);
    Lists:=TJSONArray.Create; Board.Add('lists',Lists);
    Cards:=TJSONArray.Create; Board.Add('cards',Cards);
    Labels:=TJSONArray.Create; Board.Add('labels',Labels);
    Checks:=TJSONArray.Create; Board.Add('checklists',Checks);
    Items:=TJSONArray.Create; Board.Add('checklistItems',Items);
    Data:=Input.Find('globalTags');
    if Data is TJSONArray then for I:=0 to Data.Count-1 do
      if Data.Items[I] is TJSONObject then LabelFor(TJSONObject(Data.Items[I]));
    for I:=0 to Columns.Count-1 do
    begin
      if not (Columns.Items[I] is TJSONObject) then raise EConvertError.Create('Invalid Kanri column');
      Column:=TJSONObject(Columns.Items[I]);
      ListId:=Column.Get('id','column-'+IntToStr(I));
      Lists.Add(TJSONObject.Create(['_id',ListId,'title',Column.Get('title','List'),'sort',I]));
      ColumnCards:=Column.Find('cards');
      if not (ColumnCards is TJSONArray) then Continue;
      for J:=0 to ColumnCards.Count-1 do
      begin
        if not (ColumnCards.Items[J] is TJSONObject) then raise EConvertError.Create('Invalid Kanri card');
        Entry:=TJSONObject(ColumnCards.Items[J]);
        CardId:=Entry.Get('id','column-'+IntToStr(I)+'-card-'+IntToStr(J));
        Card:=TJSONObject.Create(['_id',CardId,'listId',ListId,'title',Entry.Get('name',''),
          'description',Entry.Get('description',''),'sort',J,'dueComplete',Entry.Get('isDueDateCompleted',False)]);
        Cards.Add(Card);
        Color:=KanriColor(Entry.Get('color','')); if Color<>'' then Card.Add('color',Color);
        if Entry.Get('dueDate','')<>'' then Card.Add('dueAt',Entry.Get('dueDate',''));
        Tags:=TJSONArray.Create; Card.Add('labelIds',Tags);
        Data:=Entry.Find('tags');
        if Data is TJSONArray then for K:=0 to Data.Count-1 do
        begin
          if not (Data.Items[K] is TJSONObject) then Continue;
          Tag:=TJSONObject(Data.Items[K]); Name:=LabelFor(Tag);
          if Name<>'' then Tags.Add(Name);
        end;
        Data:=Entry.Find('tasks');
        if (Data is TJSONArray) and (Data.Count>0) then
        begin
          CheckId:=CardId+':tasks';
          Checks.Add(TJSONObject.Create(['_id',CheckId,'cardId',CardId,'title','Tasks','sort',0]));
          for K:=0 to Data.Count-1 do
          begin
            if not (Data.Items[K] is TJSONObject) then Continue;
            Task:=TJSONObject(Data.Items[K]);
            Items.Add(TJSONObject.Create(['_id',CheckId+':'+IntToStr(K),'checklistId',CheckId,
              'title',Task.Get('name',''),'isFinished',Task.Get('finished',False),'sort',K]));
          end;
        end;
      end;
    end;
  except Result.Free; raise; end;
end;

function ExternalImportSupported(const FormatName: string): Boolean;
begin
  Result:=(FormatName='kanboard') or (FormatName='deck') or (FormatName='github') or
    (FormatName='gitlab') or (FormatName='gitea') or (FormatName='forgejo') or (FormatName='asana') or (FormatName='openproject') or (FormatName='zenkit') or (FormatName='jira') or (FormatName='kanri');
end;

function ImportRecoveryRows(Db: TWLDb; const UserId, BoardId: string): TJSONArray;
var Rows: TWLRows; Row: TWLRow; Physical, Scope: string;
begin
  Result:=TJSONArray.Create;
  if not IsShared(Db) then Exit;
  Rows:=Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''recoveryEvents'';');
  if Length(Rows)<>1 then Exit;
  Physical:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
  Scope:='';
  if UserId<>'' then
    Scope:=' AND json_extract(e._ferretdb_sjson,''$.userId'')='+QuotedStr(UserId)+
      ' AND EXISTS(SELECT 1 FROM json_each(e._ferretdb_sjson,''$.boardIds'') WHERE value='+QuotedStr(BoardId)+')'+
      ' AND datetime(json_extract(e._ferretdb_sjson,''$.createdAt'')/1000,''unixepoch'')>=datetime(''now'',''-1 hour'')';
  Rows:=Db.Query('SELECT json_extract(e._ferretdb_sjson,''$.detail''),strftime(''%Y-%m-%dT%H:%M:%fZ'',json_extract(e._ferretdb_sjson,''$.createdAt'')/1000.0,''unixepoch''),' +
    'json_extract(e._ferretdb_sjson,''$.type'') FROM '+Physical+' e WHERE '+
    'json_extract(e._ferretdb_sjson,''$.type'')=''import-completed-with-warnings'''+Scope+
    ' ORDER BY json_extract(e._ferretdb_sjson,''$.createdAt'') DESC LIMIT '+IfThen(UserId='','100','5')+';');
  for Row in Rows do
    if UserId='' then Result.Add(TJSONObject.Create(['detail',Row[0],'createdAt',Row[1],'type',Row[2]]))
    else Result.Add(TJSONObject.Create(['detail',Row[0],'createdAt',Row[1]]));
end;

procedure ImportBoardRequest(aRequest:TRequest;aResponse:TResponse; const Tenant: TWLTenant; const MethodActor, MethodBody, MethodFormat: string);
const Collections:array[0..11] of string=('swimlanes','lists','cards','triggers','actions','rules',
  'comments','checklists','checklistItems','attachments','customFields','labels');
var T:TWLTenant;Actor,BoardId,Board,Title,AdminOnly,PrivateOnly,RegistryGuard,Permission,Stamp,Guard,Sql,Name,CardId,CardAuthor,CardCreated,DefaultLane,DefaultList,ListId,LaneId,TargetBoard,TargetLane,TargetList,TargetCard,ListLane,LaneGuard,LanePosition,ListPosition,CardScope,CardPosition,NumberSql,SortSql,SourceFormat,LossDetail:string;
  Body,Input,Row,Reply,SourceDocument,MemberMap,CardCreations,ImportedListLanes:TJSONObject;Maps:array[0..11] of TJSONObject;Arrays:array[0..11] of TJSONArray;
  Value:TJSONData;Rows:TWLRows;CardNumbers:array of Int64;I,J:Integer;Files,ImportedMembers:TStringList;Committed, IsZip, ZipRoute:Boolean; Session:TWLSession; Policy:TFieldPolicy;
  function Text(Obj:TJSONObject;const Key:string;const Fallback:string=''):string;
  var Field:TJSONData;
  begin
    Field:=Obj.Find(Key);
    if (Field=nil) or (Field.JSONType=jtNull) then Exit(Fallback);
    if not (Field is TJSONString) or (Pos(#0,Field.AsString)>0) then
      raise EConvertError.Create('Invalid import text field');
    Result:=Field.AsString;
  end;
  function ImportedAuthor(Obj:TJSONObject):string;
  begin Result:=MemberMap.Get(Text(Obj,'userId'),Actor);end;
  procedure ReadMemberMapping;
  var Mapping,Target:TJSONData;Source:TSelectionScope;FindUser,Identity,SourceId:string;Found:TWLRows;K:Integer;
  begin
    Mapping:=Body.Find('membersMapping');
    if Mapping=nil then Exit;
    if not (Mapping is TJSONObject) then raise EConvertError.Create('Invalid member mapping');
    Source:=TSelectionScope.Create(T.Db);
    try
      FindUser:=Source.StringField('users','id');
      for K:=0 to Mapping.Count-1 do
      begin
        Target:=Mapping.Items[K];SourceId:=TJSONObject(Mapping).Names[K];
        if not (Target is TJSONString) or (Target.AsString='') or (Pos(#0,Target.AsString)>0) or
          (SourceId='') or (Pos(#0,SourceId)>0) then raise EConvertError.Create('Invalid member identity');
        Identity:='(SELECT count(*) FROM users WHERE id='+QuotedStr(Target.AsString)+
          ' AND COALESCE(loginDisabled,0)=0 AND '+FindUser+')=1';
        Found:=T.Db.Query('SELECT '+Identity+';');
        if (Length(Found)<>1) or (Found[0][0]<>'1') then raise EConvertError.Create('Invalid mapped account');
        Guard:=Guard+' AND '+Identity;
        MemberMap.Add(SourceId,Target.AsString);
      end;
    finally Source.Free;end;
  end;
  procedure CreateImportedAuthors;
  var Authors: TJSONObject; K: Integer; Id: string;
  begin
    if SourceFormat='' then Exit;
    Authors:=Body.Objects['importedAuthors'];
    for K:=0 to Authors.Count-1 do
    begin
      Id:=NewId;
      MemberMap.Add(Authors.Items[K].AsString,Id);
      Sql:=Sql+'INSERT INTO users(id,username,createdAt,modifiedAt,profile_json,loginDisabled,isAdmin) VALUES('+
        QuotedStr(Id)+','+QuotedStr('imported-'+Id)+','+Stamp+','+Stamp+',json_object(''fullname'','+
        QuotedStr(Authors.Names[K])+'),1,0); ';
    end;
  end;
  procedure ImportInactiveMembers;
  var Members,Entry:TJSONData;LocalId:string;K:Integer;
  begin
    Members:=Input.Find('members');
    if not (Members is TJSONArray) then Exit;
    for K:=0 to Members.Count-1 do
    begin
      Entry:=Members.Items[K];if not (Entry is TJSONObject) then Continue;
      LocalId:=MemberMap.Get(Text(TJSONObject(Entry),'userId',Text(TJSONObject(Entry),'id')),'');
      if (LocalId='') or (LocalId=Actor) or (ImportedMembers.IndexOf(LocalId)>=0) then Continue;
      ImportedMembers.Add(LocalId);
      Sql:=Sql+'INSERT INTO board_members(boardId,userId,isActive,isAdmin) VALUES('+Board+','+
        QuotedStr(LocalId)+',0,0); ';
    end;
  end;
  procedure ImportCardPeople(Entry:TJSONObject;const Id:string);
  var Source:TJSONData;Selected:TStringList;Extra:TJSONObject;Items:TJSONArray;
    Field,LocalId,Column:string;K:Integer;
  begin
    Selected:=TStringList.Create;Selected.CaseSensitive:=True;Extra:=TJSONObject.Create;
    try
      Sql:=Sql+InitializeSharedAssignments(T.Db,BoardId,Id,True,True);
      for Field in ['members','assignees','requesters','assigners'] do
      begin
        Selected.Clear;Source:=Entry.Find(Field);
        if (Source=nil) or (Source.JSONType=jtNull) then Continue;
        if not (Source is TJSONArray) then raise EConvertError.Create('Invalid card participant list');
        for K:=0 to Source.Count-1 do
        begin
          if not (Source.Items[K] is TJSONString) then raise EConvertError.Create('Invalid card participant');
          LocalId:=MemberMap.Get(Source.Items[K].AsString,'');
          if (LocalId<>'') and (Selected.IndexOf(LocalId)<0) then Selected.Add(LocalId);
        end;
        if (Field='members') or (Field='assignees') then
        begin
          if Field='members' then Column:='card_members' else Column:='card_assignees';
          for K:=0 to Selected.Count-1 do
            Sql:=Sql+'INSERT INTO '+Column+'(cardId,userId) VALUES('+QuotedStr(Id)+','+QuotedStr(Selected[K])+'); ';
        end else
        begin
          Items:=TJSONArray.Create;Extra.Add(Field,Items);
          for K:=0 to Selected.Count-1 do Items.Add(Selected[K]);
        end;
      end;
      if Extra.Count>0 then
        Sql:=Sql+'UPDATE cards SET extra_json=json_patch(extra_json,'+QuotedStr(Extra.AsJSON)+
          ') WHERE id='+QuotedStr(Id)+' AND boardId='+Board+'; ';
    finally Extra.Free;Selected.Free;end;
  end;
  procedure ImportCardDecorations(Entry:TJSONObject;const Id:string);
  var Extra:TJSONObject; Field:TJSONData; Key,Sets:string;
  begin
    Extra:=TJSONObject.Create;
    try
      Sets:='';
      for Key in ['locations','stickers'] do
      begin
        Field:=Entry.Find(Key);
        if (Field=nil) or (Field.JSONType=jtNull) then Continue;
        try
          Extra.Add(Key,CardDecorations(Field,Key));
        except
          on E:Exception do raise EConvertError.Create('Invalid imported card decoration');
        end;
      end;
      if Extra.Count>0 then Sets:=',extra_json=json_patch(extra_json,'+QuotedStr(Extra.AsJSON)+')';
      for Key in ['locationName','locationAddress','locationLatitude','locationLongitude'] do
      begin
        Field:=Entry.Find(Key);
        if (Field=nil) or (Field.JSONType=jtNull) then Continue;
        if (Key='locationName') or (Key='locationAddress') then
        begin
          if (Field.JSONType<>jtString) or (Pos(#0,Field.AsString)>0) then
            raise EConvertError.Create('Invalid imported location text');
          Sets:=Sets+','+Key+'='+QuotedStr(Field.AsString);
        end
        else
        begin
          if (Field.JSONType<>jtNumber) or IsNan(Field.AsFloat) or IsInfinite(Field.AsFloat) then
            raise EConvertError.Create('Invalid imported location coordinate');
          Sets:=Sets+','+Key+'='+Field.AsJSON;
        end;
      end;
      if Sets<>'' then Sql:=Sql+'UPDATE cards SET '+Copy(Sets,2,Length(Sets))+
        ' WHERE id='+QuotedStr(Id)+' AND boardId='+Board+'; ';
    finally Extra.Free;end;
  end;
  function Mapped(Index:Integer;const Id:string;Required:Boolean=False):string;
  begin
    Result:=Maps[Index].Get(Id,'');
    if Required and (Result='') then raise EConvertError.Create('Invalid import reference');
  end;
  procedure MergeSubtasks;
  var Source, Existing: TJSONData; Cards: TJSONArray; Subtask: TJSONObject;
    Id: string; K: Integer; Seen: TStringList;
  begin
    Source := Input.Find('subtaskItems');
    if Source = nil then Exit;
    if not (Source is TJSONArray) then raise EConvertError.Create('Invalid imported subtasks');
    if Source.Count = 0 then Exit;
    Existing := Input.Find('cards');
    if Existing = nil then
    begin
      Cards := TJSONArray.Create;
      Input.Add('cards', Cards);
    end
    else if Existing is TJSONArray then Cards := TJSONArray(Existing)
    else raise EConvertError.Create('Invalid imported cards');
    Seen := TStringList.Create;
    try
      Seen.CaseSensitive := True;
      Seen.Sorted := True;
      Seen.Duplicates := dupIgnore;
      for K := 0 to Cards.Count - 1 do
        if Cards.Items[K] is TJSONObject then Seen.Add(Text(Cards.Objects[K], '_id'));
      for K := 0 to Source.Count - 1 do
      begin
        if not (Source.Items[K] is TJSONObject) then raise EConvertError.Create('Invalid imported subtask');
        Subtask := TJSONObject(Source.Items[K]);
        Id := Text(Subtask, '_id');
        if Id = '' then raise EConvertError.Create('Missing imported subtask ID');
        if Seen.IndexOf(Id) >= 0 then Continue;
        Seen.Add(Id);
        Cards.Add(Subtask.Clone);
      end;
    finally Seen.Free; end;
  end;

  procedure ImportParentLinks(Entry: TJSONObject; const Id: string);
  var Source: TJSONData; Parents: TJSONArray; Parent: string; K, J: Integer;
    Duplicate: Boolean;
  begin
    Source := Entry.Find('parentIds');
    if (Source = nil) or (Source.JSONType = jtNull) then Exit;
    if not (Source is TJSONArray) then raise EConvertError.Create('Invalid imported parent IDs');
    Parents := TJSONArray.Create;
    try
      for K := 0 to Source.Count - 1 do
      begin
        if not (Source.Items[K] is TJSONString) then raise EConvertError.Create('Invalid imported parent ID');
        Parent := Mapped(2, Source.Items[K].AsString);
        if (Parent = '') or (Parent = Id) then Continue;
        Duplicate := False;
        for J := 0 to Parents.Count - 1 do
          if Parents.Strings[J] = Parent then begin Duplicate := True; Break; end;
        if not Duplicate then Parents.Add(Parent);
      end;
      Sql := Sql + 'UPDATE cards SET extra_json=json_set(extra_json,''$.parentIds'',json(' +
        QuotedStr(Parents.AsJSON) + ')) WHERE id=' + QuotedStr(Id) + ' AND boardId=' + Board + '; ';
    finally Parents.Free; end;
  end;

  procedure ImportLabels;
  var Entry:TJSONObject;K:Integer;
  begin
    if Arrays[11]=nil then Exit;
    for K:=0 to Arrays[11].Count-1 do
    begin
      Entry:=Arrays[11].Objects[K];
      Sql:=Sql+'INSERT INTO board_labels(boardId,id,name,color) VALUES('+Board+','+
        QuotedStr(Mapped(11,Text(Entry,'_id'),True))+','+QuotedStr(Text(Entry,'name'))+','+
        QuotedStr(Text(Entry,'color','green'))+'); ';
    end;
  end;
  procedure ImportCardLabels(Entry:TJSONObject;const CardKey:string);
  var Labels:TJSONData;LabelKey:string;K:Integer;
  begin
    Labels:=Entry.Find('labelIds');
    if (Labels=nil) or (Labels.JSONType=jtNull) then Exit;
    if not (Labels is TJSONArray) then raise EConvertError.Create('Invalid imported card labels');
    for K:=0 to Labels.Count-1 do
    begin
      if not (Labels.Items[K] is TJSONString) then raise EConvertError.Create('Invalid imported card label');
      LabelKey:=QuotedStr(Mapped(11,Labels.Items[K].AsString,True));
      Sql:=Sql+'INSERT INTO card_labels(cardId,labelId) SELECT '+QuotedStr(CardKey)+','+LabelKey+
        ' WHERE NOT EXISTS(SELECT 1 FROM card_labels WHERE cardId='+QuotedStr(CardKey)+' AND labelId='+LabelKey+'); ';
    end;
  end;
  procedure ImportAttachedCards(Entry:TJSONObject;const CardKey:string);
  var Source:TJSONData;Targets:TJSONArray;Seen:TStringList;Target:string;K:Integer;
  begin
    Source:=Entry.Find('attachedCardIds');
    if not (Source is TJSONArray) then Exit;
    Targets:=TJSONArray.Create;Seen:=TStringList.Create;
    try
      Seen.CaseSensitive:=True;
      for K:=0 to Source.Count-1 do
      begin
        if not (Source.Items[K] is TJSONString) then Continue;
        Target:=Mapped(2,Source.Items[K].AsString);
        if (Target='') or (Target=CardKey) or (Seen.IndexOf(Target)>=0) then Continue;
        Seen.Add(Target);Targets.Add(Target);
      end;
      if Targets.Count>0 then
        Sql:=Sql+'UPDATE cards SET extra_json=json_set(extra_json,''$.attachedCardIds'',json('+
          QuotedStr(Targets.AsJSON)+')) WHERE id='+QuotedStr(CardKey)+' AND boardId='+Board+'; ';
    finally Seen.Free;Targets.Free;end;
  end;
  procedure ImportCardDependencies(Entry:TJSONObject;const CardKey:string);
  var Dependencies,Item:TJSONData;Link:TJSONObject;K:Integer;Target,Kind,Color,Icon,Source:string;
  begin
    Dependencies:=Entry.Find('cardDependencies');
    if (Dependencies=nil) or (Dependencies.JSONType=jtNull) then Exit;
    if not (Dependencies is TJSONArray) then raise EConvertError.Create('Invalid imported card dependencies');
    Source:=QuotedStr(CardKey);
    for K:=0 to Dependencies.Count-1 do
    begin
      Item:=Dependencies.Items[K];
      Kind:='related-to';Color:='#eb144c';Icon:='link';
      if Item is TJSONString then Target:=Mapped(2,Item.AsString)
      else if Item is TJSONObject then
      begin
        Link:=TJSONObject(Item);Target:=Mapped(2,Text(Link,'cardId'));
        if Target='' then Continue;
        Kind:=Text(Link,'type',Kind);Color:=Text(Link,'color',Color);Icon:=Text(Link,'icon',Icon);
      end else raise EConvertError.Create('Invalid imported card dependency');
      if Target='' then Continue;
      Target:=QuotedStr(Target);Kind:=QuotedStr(Kind);
      Sql:=Sql+'INSERT INTO card_dependencies(cardId,targetCardId,type,color,icon) SELECT '+
        Source+','+Target+','+Kind+','+QuotedStr(Color)+','+QuotedStr(Icon)+
        ' WHERE NOT EXISTS(SELECT 1 FROM card_dependencies WHERE cardId='+Source+' AND targetCardId='+Target+
        ' AND type='+Kind+'); ';
    end;
  end;
  function SortValue(Obj:TJSONObject;const Fallback:string='0'):string;
  var Field:TJSONData;
  begin
    Result:=Fallback;Field:=Obj.Find('sort');
    if (Field<>nil) and (Field.JSONType=jtNumber) and not IsNan(Field.AsFloat) and not IsInfinite(Field.AsFloat) then
      Result:=Field.AsJSON;
  end;
  function ImportedDate(Obj:TJSONObject;const Key,Fallback:string;IgnoreInvalid:Boolean=False):string;
  var Field:TJSONData;
  begin
    Result:=Fallback;Field:=Obj.Find(Key);
    if (Field=nil) or (Field.JSONType=jtNull) then Exit;
    if not CardDateSql(Field,Result) then
    begin
      if IgnoreInvalid then Exit(Fallback);
      raise EConvertError.Create('Invalid imported date');
    end;
    if Result='NULL' then Result:=Fallback;
  end;
  procedure ImportDefinitions;
  var Entry,Settings:TJSONObject;Id,FieldName,Kind,Dropdown,DropdownGuard:string;
    Flags:TDefinitionFlags;AlwaysOn,K,L:Integer;
  begin
    if Arrays[10]=nil then Exit;
    for K:=0 to Arrays[10].Count-1 do
    begin
      Entry:=Arrays[10].Objects[K];
      Id:=QuotedStr(Mapped(10,Text(Entry,'_id'),True));
      FieldName:=Text(Entry,'name');Kind:=Text(Entry,'type','text');
      if (Trim(FieldName)='') or not ValidDefinitionType(Kind) then
        raise EConvertError.Create('Invalid imported custom-field definition');
      for L:=0 to High(Flags) do
        if not DefinitionFlag(Entry.Find(DefinitionFlagNames[L]),Flags[L]) then
          raise EConvertError.Create('Invalid imported custom-field flag');
      if not DefinitionFlag(Entry.Find('alwaysOnCard'),AlwaysOn) then
        raise EConvertError.Create('Invalid imported custom-field flag');
      if not SettingsInput(Entry.Find('settings'),Settings) then
        raise EConvertError.Create('Invalid imported custom-field settings');
      try
        Dropdown:=DropdownScript(T.Db,Mapped(10,Text(Entry,'_id'),True),Settings,DropdownGuard);
        Sql:=Sql+Format('INSERT INTO custom_fields(id,name,type,sort,showOnCard,automaticallyOnCard,'+
          'showLabelOnMiniCard,showSumAtTopOfList,readOnly,adminOnly,alwaysOnCard,createdAt,modifiedAt,'+
          'currencyCode,stringtemplateFormat,stringtemplateSeparator,settings_json) '+
          'VALUES(%s,%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%s,%s,%s,%s,%s,%s); ',
          [Id,QuotedStr(FieldName),QuotedStr(Kind),SortValue(Entry,'NULL'),Flags[0],Flags[1],Flags[2],Flags[3],Flags[4],Flags[5],
           AlwaysOn,ImportedDate(Entry,'createdAt','NULL',True),ImportedDate(Entry,'modifiedAt',Stamp,True),
           SettingsLiteral(Settings,'currencyCode'),SettingsLiteral(Settings,'stringtemplateFormat'),
           SettingsLiteral(Settings,'stringtemplateSeparator'),SettingsRemainder(Settings)])+
          'INSERT INTO custom_field_boards(customFieldId,boardId) VALUES('+Id+','+Board+'); '+Dropdown+DropdownGuard;
      finally Settings.Free;end;
    end;
  end;
  procedure ImportCardFields(Entry:TJSONObject;const Id:string);
  var Fields,Data:TJSONData;Field:TJSONObject;Seen:TStringList;FieldId,Literal:string;K:Integer;
  begin
    Fields:=Entry.Find('customFields');
    if (Fields=nil) or (Fields.JSONType=jtNull) then Exit;
    if not (Fields is TJSONArray) then raise EConvertError.Create('Invalid imported custom-field values');
    Seen:=TStringList.Create;
    try
      Seen.CaseSensitive:=True;
      for K:=0 to Fields.Count-1 do
      begin
        if not (Fields.Items[K] is TJSONObject) then raise EConvertError.Create('Invalid imported custom-field value');
        Field:=TJSONObject(Fields.Items[K]);FieldId:=Mapped(10,Text(Field,'_id'),True);
        if Seen.IndexOf(FieldId)>=0 then raise EConvertError.Create('Duplicate imported custom-field value');
        Seen.Add(FieldId);Data:=Field.Find('value');
        if (Data=nil) or (Data.JSONType=jtNull) then Literal:='NULL'
        else if not CustomValueLiteral(Data,Literal) then raise EConvertError.Create('Invalid imported custom-field value');
        Sql:=Sql+'INSERT INTO card_custom_field_values(cardId,customFieldId,value) VALUES('+
          QuotedStr(Id)+','+QuotedStr(FieldId)+','+Literal+'); ';
      end;
    finally Seen.Free;end;
  end;
  function Optional(const TextValue:string):string;
  begin
    if TextValue='' then Result:='NULL' else Result:=QuotedStr(TextValue);
  end;
  function ReserveSortSlots(const TableName, Scope, Anchor: string; Count: Integer): string;
  begin
    Result := 'WITH ordered AS MATERIALIZED (SELECT id, ROW_NUMBER() OVER (ORDER BY sort,id) AS position '+
      'FROM '+TableName+' WHERE '+Scope+'), destination AS MATERIALIZED (SELECT position FROM ordered WHERE id='+
      QuotedStr(Anchor)+') UPDATE '+TableName+' SET sort=(SELECT position+CASE WHEN position>'+
      '(SELECT position FROM destination) THEN '+IntToStr(Count)+' ELSE 0 END FROM ordered '+
      'WHERE ordered.id='+TableName+'.id) WHERE '+Scope+'; ';
  end;
  procedure CardPlacement(Obj:TJSONObject;out ListKey,LaneKey:string);
  begin
    ListKey:='';
    if TargetCard='' then ListKey:=Mapped(1,Text(Obj,'listId'));
    if ListKey='' then ListKey:=DefaultList;
    LaneKey:=ImportedListLanes.Get(ListKey,'');
    if (LaneKey='') and (TargetList='') then LaneKey:=Mapped(0,Text(Obj,'swimlaneId'));
    if LaneKey='' then LaneKey:=DefaultLane;
  end;
  procedure ImportCardVoting(Entry:TJSONObject;const Id:string);
  var Source,Field:TJSONData; Extra,Settings:TJSONObject; Group,Key,Deadline:string;
    procedure ImportBallots(const Choice:string);
    var Values:TJSONData; Mapped:TJSONArray; LocalId:string; K,J:Integer; Seen:Boolean;
    begin
      Values:=Source.FindPath(Choice);
      if (Values=nil) or (Values.JSONType=jtNull) then Exit;
      if not (Values is TJSONArray) then raise EConvertError.Create('Invalid imported ballots');
      Mapped:=TJSONArray.Create;
      Settings.Add(Choice,Mapped);
      for K:=0 to Values.Count-1 do
      begin
        if not (Values.Items[K] is TJSONString) then raise EConvertError.Create('Invalid imported voter');
        LocalId:=MemberMap.Get(Values.Items[K].AsString,'');
        if LocalId='' then Continue;
        Seen:=False;
        for J:=0 to Mapped.Count-1 do
          if Mapped.Strings[J]=LocalId then Seen:=True;
        if not Seen then Mapped.Add(LocalId);
      end;
    end;
  begin
    Extra:=TJSONObject.Create;
    try
      for Group in ['vote','poker'] do
      begin
        Source:=Entry.Find(Group);
        if (Source=nil) or (Source.JSONType=jtNull) then Continue;
        if not (Source is TJSONObject) then raise EConvertError.Create('Invalid imported voting settings');
        Settings:=TJSONObject.Create;
        Extra.Add(Group,Settings);
        Field:=Source.FindPath('question');
        if (Field is TJSONString) or ((Group='poker') and (Field is TJSONBoolean)) then
          Settings.Add('question',Field.Clone);
        for Key in ['public','allowNonBoardMembers'] do
        begin
          Field:=Source.FindPath(Key);
          if Field is TJSONBoolean then Settings.Add(Key,Field.Clone);
        end;
        Deadline:=ImportedDate(TJSONObject(Source),'end','NULL');
        if Deadline<>'NULL' then Settings.Add('end',Copy(Deadline,2,Length(Deadline)-2));
        if Group='vote' then
        begin
          ImportBallots('positive');
          ImportBallots('negative');
        end
        else
        begin
          Field:=Source.FindPath('estimation');
          if (Field<>nil) and (Field.JSONType=jtNumber) and not IsNan(Field.AsFloat) and not IsInfinite(Field.AsFloat) then
            Settings.Add('estimation',Field.Clone);
          for Key in POKER_FIELDS do ImportBallots(Key);
        end;
      end;
      if Extra.Count>0 then
        Sql:=Sql+'UPDATE cards SET extra_json=json_patch(extra_json,'+QuotedStr(Extra.AsJSON)+
          ') WHERE id='+QuotedStr(Id)+' AND boardId='+Board+'; ';
    finally Extra.Free;end;
  end;
  function BooleanValue(Obj:TJSONObject;const Key:string;const Fallback:string='0'):string;
  var Field:TJSONData;
  begin
    Field:=Obj.Find(Key);
    if Field is TJSONBoolean then Exit(IntToStr(Ord(Field.AsBoolean)));
    if (Field<>nil) and (Field.JSONType=jtNumber) then
    begin
      if Field.AsFloat=0 then Exit('0');
      if Field.AsFloat=1 then Exit('1');
    end;
    Result:=Fallback;
  end;
  function ImportedColor(Entry:TJSONObject):string;
  var Field:TJSONData;Color:string;
  begin
    Field:=Entry.Find('color');
    if not (Field is TJSONString) then Exit('NULL');
    Color:=Field.AsString;
    if ResolveColor(Color)='' then Exit('NULL');
    Result:=QuotedStr(Color);
  end;
  function ImportedListWidth(Entry:TJSONObject):string;
  var Field:TJSONData;Width:Double;
  begin
    Field:=Entry.Find('width');
    if (Field=nil) or (Field.JSONType<>jtNumber) then Exit('272');
    Width:=Field.AsFloat;
    if IsNan(Width) or (Width<100) or (Width>1000) or (Width<>Trunc(Width)) then Exit('272');
    Result:=IntToStr(Trunc(Width));
  end;
  procedure AllocateCardNumbers;
  const MaxSequence=9007199254740990;
  var Used:TStringList;Field:TJSONData;Number:Double;K:Integer;Next:Int64;Key:string;
  begin
    if Arrays[2]=nil then Exit;
    SetLength(CardNumbers,Arrays[2].Count);
    Used:=TStringList.Create;
    try
      Used.Sorted:=True;
      for K:=0 to High(CardNumbers) do
      begin
        Field:=Arrays[2].Objects[K].Find('cardNumber');
        if (Field=nil) or (Field.JSONType<>jtNumber) then Continue;
        Number:=Field.AsFloat;
        if IsNan(Number) or (Number<1) or (Number>MaxSequence) or (Number<>Trunc(Number)) then Continue;
        Key:=IntToStr(Trunc(Number));
        if Used.IndexOf(Key)>=0 then Continue;
        Used.Add(Key);
        CardNumbers[K]:=Trunc(Number);
      end;
      Next:=1;
      for K:=0 to High(CardNumbers) do if CardNumbers[K]=0 then
      begin
        while Used.IndexOf(IntToStr(Next))>=0 do Inc(Next);
        CardNumbers[K]:=Next;
        Inc(Next);
      end;
    finally Used.Free;end;
  end;
  procedure IndexCardCreations;
  var Activities,Item,Kind,SourceId:TJSONData;Entry:TJSONObject;Id:string;K:Integer;
  begin
    Activities:=Input.Find('activities');
    if (Activities=nil) or (Activities.JSONType=jtNull) then Exit;
    if not (Activities is TJSONArray) then raise EConvertError.Create('Invalid imported activities');
    for K:=0 to Activities.Count-1 do
    begin
      Item:=Activities.Items[K];
      if not (Item is TJSONObject) then Continue;
      Entry:=TJSONObject(Item);Kind:=Entry.Find('activityType');SourceId:=Entry.Find('cardId');
      if not (Kind is TJSONString) or (Kind.AsString<>'createCard') or not (SourceId is TJSONString) then Continue;
      Id:=Mapped(2,SourceId.AsString);
      if Id='' then Continue;
      CardCreations.Delete(Id);CardCreations.Add(Id,K);
    end;
  end;
  procedure CardCreation(Entry:TJSONObject;const Id:string;out Author,Created:string);
  var Activities:TJSONArray;Event:TJSONObject;Field,Index:TJSONData;Literal:string;
  begin
    Author:=ImportedAuthor(Entry);Created:='';
    Index:=CardCreations.Find(Id);
    if Index<>nil then
    begin
      Activities:=TJSONArray(Input.Find('activities'));Event:=Activities.Objects[Index.AsInteger];
      Field:=Event.Find('userId');
      if (Field is TJSONString) and (Field.AsString<>'') then Author:=MemberMap.Get(Field.AsString,Actor);
      Field:=Event.Find('createdAt');
      if (Field<>nil) and CardDateSql(Field,Literal) and (Literal<>'NULL') then Created:=Literal;
    end;
    if Created='' then Created:=ImportedDate(Entry,'createdAt',Stamp);
  end;
  function ImportedSpentTime(Entry:TJSONObject):string;
  var Field:TJSONData;
  begin
    Field:=Entry.Find('spentTime');
    if (Field=nil) or (Field.JSONType=jtNull) then Exit('NULL');
    if (Field.JSONType<>jtNumber) or IsNan(Field.AsFloat) or IsInfinite(Field.AsFloat) then
      raise EConvertError.Create('Invalid imported spent time');
    Result:=Field.AsJSON;
  end;
  procedure ImportCardChildren;
  var K,L:Integer;Entry,Checklist:TJSONObject;Id,CardKey,CheckKey,OriginalCheck,Parent:string;
  begin
    if Arrays[6]<>nil then for K:=0 to Arrays[6].Count-1 do
    begin
      Entry:=Arrays[6].Objects[K];
      Id:=QuotedStr(Mapped(6,Text(Entry,'_id'),True));
      CardKey:=QuotedStr(Mapped(2,Text(Entry,'cardId'),True));
      Parent:=Mapped(6,Text(Entry,'parentId'));
      Sql:=Sql+'INSERT INTO card_comments(id,boardId,cardId,userId,text,parentId,createdAt,modifiedAt) VALUES('+
        Id+','+Board+','+CardKey+','+QuotedStr(ImportedAuthor(Entry))+','+QuotedStr(Text(Entry,'text'))+','+QuotedStr(Parent)+','+
        ImportedDate(Entry,'createdAt',Stamp)+','+ImportedDate(Entry,'modifiedAt',Stamp)+'); ';
      if SourceFormat<>'' then
        Sql:=Sql+'INSERT INTO activities(id,activityType,boardId,cardId,userId,createdAt,modifiedAt,data_json) VALUES('+
          QuotedStr(NewId)+',''addComment'','+Board+','+CardKey+','+QuotedStr(ImportedAuthor(Entry))+','+
          ImportedDate(Entry,'createdAt',Stamp)+','+Stamp+',json_object(''commentId'','+Id+')); ';
    end;
    if Arrays[7]<>nil then for K:=0 to Arrays[7].Count-1 do
    begin
      Entry:=Arrays[7].Objects[K];
      Id:=QuotedStr(Mapped(7,Text(Entry,'_id'),True));
      CardKey:=QuotedStr(Mapped(2,Text(Entry,'cardId'),True));
      Sql:=Sql+'INSERT INTO checklists(id,boardId,cardId,title,sort,finishedAt,dueAt,hideCheckedChecklistItems,'+
        'hideAllChecklistItems,showChecklistAtMinicard,createdAt,modifiedAt) VALUES('+
        Id+','+Board+','+CardKey+','+QuotedStr(Text(Entry,'title','Checklist'))+','+SortValue(Entry)+','+
        ImportedDate(Entry,'finishedAt','NULL')+','+ImportedDate(Entry,'dueAt','NULL')+','+
        BooleanValue(Entry,'hideCheckedChecklistItems')+','+BooleanValue(Entry,'hideAllChecklistItems')+','+
        BooleanValue(Entry,'showChecklistAtMinicard')+','+ImportedDate(Entry,'createdAt',Stamp)+','+
        ImportedDate(Entry,'modifiedAt',Stamp)+'); ';
    end;
    if Arrays[8]<>nil then for K:=0 to Arrays[8].Count-1 do
    begin
      Entry:=Arrays[8].Objects[K];
      Id:=QuotedStr(Mapped(8,Text(Entry,'_id'),True));
      OriginalCheck:=Text(Entry,'checklistId');
      CheckKey:=QuotedStr(Mapped(7,OriginalCheck,True));
      Checklist:=nil;
      for L:=0 to Arrays[7].Count-1 do
        if Text(Arrays[7].Objects[L],'_id')=OriginalCheck then begin Checklist:=Arrays[7].Objects[L];Break;end;
      if Checklist=nil then raise EConvertError.Create('Invalid imported checklist');
      CardKey:=Text(Checklist,'cardId');
      if Text(Entry,'cardId',CardKey)<>CardKey then raise EConvertError.Create('Invalid checklist item card');
      CardKey:=QuotedStr(Mapped(2,CardKey,True));
      Sql:=Sql+'INSERT INTO checklist_items(id,boardId,checklistId,cardId,title,sort,isFinished,createdAt,dueAt,'+
        'modifiedAt) VALUES('+Id+','+Board+','+CheckKey+','+CardKey+','+QuotedStr(Text(Entry,'title'))+','+
        SortValue(Entry)+','+BooleanValue(Entry,'isFinished')+','+ImportedDate(Entry,'createdAt','NULL')+','+
        ImportedDate(Entry,'dueAt','NULL')+','+ImportedDate(Entry,'modifiedAt',Stamp)+'); ';
    end;
  end;
  procedure ImportAttachments;
  var K,L:Integer;Entry,Card:TJSONObject;FileField:TJSONData;Id,CardId,CardKey,ListKey,LaneKey,Filename,
    Mime,Encoded,Bytes,Path:string;
  begin
    if Arrays[9]=nil then Exit;
    for K:=0 to Arrays[9].Count-1 do
    begin
      Entry:=Arrays[9].Objects[K];
      FileField:=Entry.Find('file');
      if (FileField=nil) or (FileField.JSONType=jtNull) then Continue;
      if not (FileField is TJSONString) then raise EConvertError.Create('Invalid attachment data');
      Id:=Mapped(9,Text(Entry,'_id'),True);
      Card:=nil;CardId:=Text(Entry,'cardId');CardKey:='NULL';ListKey:='NULL';LaneKey:='NULL';
      if CardId<>'' then
      begin
        CardKey:=QuotedStr(Mapped(2,CardId,True));
        for L:=0 to Arrays[2].Count-1 do
          if Text(Arrays[2].Objects[L],'_id')=CardId then begin Card:=Arrays[2].Objects[L];Break;end;
        if Card=nil then raise EConvertError.Create('Invalid attachment card');
        CardPlacement(Card,ListKey,LaneKey);
        ListKey:=QuotedStr(ListKey);LaneKey:=QuotedStr(LaneKey);
      end;
      Filename:=Text(Entry,'name','file');Mime:=Text(Entry,'type','application/octet-stream');
      if Filename='' then Filename:='file';
      if Mime='' then Mime:='application/octet-stream';
      if (Pos(#13,Filename+Mime)>0) or (Pos(#10,Filename+Mime)>0) then
        raise EConvertError.Create('Invalid attachment name or type');
      Encoded:=FileField.AsString;
      try Bytes:=DecodeStringBase64(Encoded,True);
      except raise EConvertError.Create('Invalid attachment encoding');end;
      if EncodeStringBase64(Bytes)<>Encoded then raise EConvertError.Create('Invalid attachment encoding');
      Path:=StoreFilePath(T.FilesDir,'attachme',Id);
      if FileExists(Path) or not ForceDirectories(ExtractFileDir(Path)) then
        raise Exception.Create('Attachment destination unavailable');
      Files.Add(Path);WriteFileBytes(Path,Bytes);
      Sql:=Sql+'INSERT INTO attachments(id,boardId,swimlaneId,listId,cardId,name,type,size,storageBackend,userId,createdAt) VALUES('+
        QuotedStr(Id)+','+Board+','+LaneKey+','+ListKey+','+CardKey+','+QuotedStr(Filename)+','+QuotedStr(Mime)+
        ','+IntToStr(Length(Bytes))+',''filesystem'','+QuotedStr(ImportedAuthor(Entry))+','+
        ImportedDate(Entry,'createdAt',ImportedDate(Entry,'uploadedAt',Stamp,True),True)+'); ';
      Sql:=Sql+'SELECT CASE WHEN EXISTS(SELECT 1 FROM attachments WHERE id='+QuotedStr(Id)+' AND boardId='+Board+
        ' AND size='+IntToStr(Length(Bytes))+') THEN 1 ELSE json(''Attachment import failed'') END; ';
      if (Card<>nil) and (Text(Card,'coverId')=Text(Entry,'_id')) then
        Sql:=Sql+'UPDATE cards SET coverId='+QuotedStr(Id)+' WHERE id='+CardKey+' AND boardId='+Board+'; ';
    end;
  end;
  procedure PutString(Obj:TJSONObject;const Key,Content:string);
  begin Obj.Delete(Key);Obj.Add(Key,Content);end;
  procedure RemapExtras(Obj:TJSONObject;const Key:string;Index:Integer);
  var Items:TJSONArray;Parts:TJSONData;K:Integer;
  begin
    Parts:=Obj.Find(Key);if Parts=nil then Exit;
    if not (Parts is TJSONArray) then raise EConvertError.Create('Invalid workflow extras');
    Items:=TJSONArray.Create;
    try
      for K:=0 to Parts.Count-1 do
      begin
        if not (Parts.Items[K] is TJSONString) then raise EConvertError.Create('Invalid workflow extra');
        Items.Add(Mapped(Index,Parts.Items[K].AsString,True));
      end;
      Obj.Delete(Key);Obj.Add(Key,Items);Items:=nil;
    finally Items.Free;end;
  end;
  procedure ImportWorkflow(Index:Integer);
  var Source,TableName,Payload,Id,Key:string;Found:TWLRows;K:Integer;Part:TJSONObject;
  begin
    if (Arrays[Index]=nil) or (Arrays[Index].Count=0) then Exit;
    Name:=Collections[Index];
    if not EnsureSharedCollection(T.Db,Name) then raise Exception.Create('Workflow collection unavailable');
    Found:=T.Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(Name)+';');
    if Length(Found)<>1 then raise Exception.Create('Ambiguous workflow collection');
    Source:=Found[0][0];TableName:='"'+StringReplace(Source,'"','""',[rfReplaceAll])+'"';
    Guard:=Guard+' AND (SELECT count(*) FROM _ferretdb_collections WHERE name='+QuotedStr(Name)+
      ' AND table_name='+QuotedStr(Source)+')=1';
    for K:=0 to Arrays[Index].Count-1 do
    begin
      Part:=TJSONObject(Arrays[Index].Objects[K].Clone);
      try
        Id:=Mapped(Index,Text(Part,'_id'),True);
        for Key in ['createdAt','modifiedAt','updatedAt'] do Part.Delete(Key);
        PutString(Part,'_id',Id);PutString(Part,'boardId',BoardId);
        if (Index in [3,4]) and (Text(Part,'labelId')<>'') then
          PutString(Part,'labelId',Mapped(11,Text(Part,'labelId'),True));
        case Index of
          3: begin
            if Text(Part,'activityType')='' then raise EConvertError.Create('Invalid imported trigger');
            NormalizeRuleTrigger(Part);
          end;
          4: if Text(Part,'actionType')='' then raise EConvertError.Create('Invalid imported action');
          5: begin
            PutString(Part,'triggerId',Mapped(3,Text(Part,'triggerId'),True));
            PutString(Part,'actionId',Mapped(4,Text(Part,'actionId'),True));
            RemapExtras(Part,'extraTriggerIds',3);RemapExtras(Part,'extraActionIds',4);
          end;
        end;
        Payload:=QuotedStr(TypedDocument(Part.AsJSON,'','{}'));
        Sql:=Sql+'INSERT INTO '+TableName+'(_ferretdb_sjson) VALUES(CASE WHEN wl_storage('+QuotedStr(Source)+
          ')=''blob'' THEN jsonb('+Payload+') ELSE '+Payload+' END); ';
      finally Part.Free;end;
    end;
  end;
  procedure ReadImportPolicy;
  var Found:TWLRows;Physical,Registry:string;
  begin
    if Length(T.Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))<>1 then Exit;
    Registry:=' FROM _ferretdb_collections WHERE name=''settings''';
    Found:=T.Db.Query('SELECT table_name'+Registry+';');
    if Length(Found)=0 then
    begin Guard:=Guard+' AND NOT EXISTS(SELECT 1'+Registry+')';Exit;end;
    if Length(Found)<>1 then raise Exception.Create('Ambiguous import settings');
    Physical:='"'+StringReplace(Found[0][0],'"','""',[rfReplaceAll])+'"';
    Guard:=Guard+' AND (SELECT count(*)'+Registry+' AND table_name='+QuotedStr(Found[0][0])+')=1';
    Permission:=Permission+' AND NOT EXISTS(SELECT 1 FROM '+Physical+
      ' WHERE json_type(_ferretdb_sjson,''$.disableAllImport'')=''true'')';
  end;
begin
  if MethodActor<>'' then T:=Tenant
  else if not ApiTenant(aRequest,aResponse,T,aRequest.QueryFields.Values['source']<>'') then Exit;
  IsZip := SameText(Trim(aRequest.ContentType.Split([';'])[0]), 'application/zip');
  SourceFormat := aRequest.QueryFields.Values['source'];
  if MethodActor<>'' then SourceFormat:=MethodFormat;
  if (SourceFormat<>'') and (not ExternalImportSupported(SourceFormat) or IsZip) then
  begin SendError(aResponse,400,'Invalid import source'); Exit; end;
  if MethodActor<>'' then Actor:=MethodActor
  else if (IsZip or (SourceFormat<>'')) and SameText(aRequest.HTTPXRequestedWith, 'XMLHttpRequest') and
    (aRequest.Authorization = '') and (aRequest.QueryFields.Values['authToken'] = '') and
    (aRequest.QueryFields.Values['token'] = '') and Html5User(T.Db, aRequest, Session) then Actor := Session.UserId
  else if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  ZipRoute := aRequest.PathInfo = '/api/import/zip';
  TargetBoard := '';
  TargetLane := '';
  TargetList := '';
  TargetCard := '';
  if ZipRoute then
  begin
    if not IsZip then begin SendError(aResponse, 400, 'Expected a board ZIP'); Exit; end;
    if aRequest.QueryFields.Values['newBoard'] <> '1' then
    begin
      TargetBoard := DownloadScopeId(aRequest, 'boardId');
      if TargetBoard = '' then begin SendError(aResponse, 400, 'Missing destination board'); Exit; end;
      TargetLane := DownloadScopeId(aRequest, 'swimlaneId');
      if (TargetLane = '') and (aRequest.QueryFields.Values['swimlaneId'] <> '') then
      begin SendError(aResponse, 400, 'Invalid destination swimlane'); Exit; end;
      TargetList := DownloadScopeId(aRequest, 'listId');
      if (TargetList = '') and (aRequest.QueryFields.Values['listId'] <> '') then
      begin SendError(aResponse, 400, 'Invalid destination list'); Exit; end;
      TargetCard := DownloadScopeId(aRequest, 'cardId');
      if (TargetCard = '') and (aRequest.QueryFields.Values['cardId'] <> '') then
      begin SendError(aResponse, 400, 'Invalid destination card'); Exit; end;
      if aRequest.QueryFields.Values['checklistId'] <> '' then
      begin SendError(aResponse, 400, 'Import placement is unavailable'); Exit; end;
      if not BoardCanWrite(T.Db, Actor, TargetBoard) then
      begin SendError(aResponse, 403, 'Board import is restricted'); Exit; end;
    end;
  end;
  Body:=nil;Guard:='1';Committed:=False;Files:=TStringList.Create;
  MemberMap:=TJSONObject.Create;CardCreations:=TJSONObject.Create;ImportedListLanes:=TJSONObject.Create;ImportedMembers:=TStringList.Create;ImportedMembers.CaseSensitive:=True;
  for I:=0 to High(Maps) do Maps[I]:=nil;
  try
    try
      try
        if IsZip then Body:=ReadBoardZip(aRequest.Content)
        else if SourceFormat<>'' then
        begin
          SourceDocument:=ExactObject('{"payload":'+IfThen(MethodActor<>'',MethodBody,aRequest.Content)+'}');
          try
            Value:=SourceDocument.Find('payload');
            if SourceFormat='deck' then
            begin
              if not (Value is TJSONObject) then raise EConvertError.Create('Invalid Deck export');
              Body:=DeckImport(TJSONObject(Value));
            end
            else if SourceFormat='kanboard' then
            begin
              if not (Value is TJSONObject) then raise EConvertError.Create('Invalid Kanboard export');
              Body:=KanboardImport(TJSONObject(Value));
            end
            else if SourceFormat='asana' then Body:=AsanaImport(Value)
            else if SourceFormat='openproject' then Body:=OpenProjectImport(Value)
            else if SourceFormat='zenkit' then Body:=ZenkitImport(Value)
            else if SourceFormat='jira' then Body:=JiraImport(Value)
            else if SourceFormat='kanri' then Body:=KanriImport(Value)
            else Body:=IssueImport(Value,SourceFormat);
          finally SourceDocument.Free; end;
        end
        else Body:=ExactObject(aRequest.Content);
      except raise EConvertError.Create('Invalid board export');end;
      Value:=Body.Find('board');
      if not (Value is TJSONObject) then raise EConvertError.Create('Missing board export');
      Input:=TJSONObject(Value);
      Name:=Text(Input,'_format');
      if (Name<>'') and (Name<>'wekan-board-1.0.0') then raise EConvertError.Create('Invalid board export format');
      Title:=Text(Input,'title');
      if Trim(Title)='' then raise EConvertError.Create('Missing board title');
      if TargetBoard <> '' then
      begin
        Input.Delete('rules');
        Input.Delete('triggers');
        Input.Delete('actions');
      end;
      if ZipRoute then
      begin
        if Input.Find('cards') = nil then Input.Add('cards', TJSONArray.Create);
        if Input.Find('subtaskItems') = nil then Input.Add('subtaskItems', TJSONArray.Create);
        for Name in ['activities','attachments','comments','checklists','checklistItems','customFields','lists','swimlanes'] do
          if Input.Find(Name) = nil then Input.Add(Name, TJSONArray.Create);
        FilterBoardExportFields(Input, aRequest.QueryFields.Values['fields']);
      end;
      MergeSubtasks;
      for I:=0 to High(Maps) do
      begin
        Maps[I]:=TJSONObject.Create;Arrays[I]:=nil;
        Value:=Input.Find(Collections[I]);if Value=nil then Continue;
        if not (Value is TJSONArray) then raise EConvertError.Create('Invalid board export array');
        Arrays[I]:=TJSONArray(Value);
        for J:=0 to Arrays[I].Count-1 do
        begin
          if not (Arrays[I].Items[J] is TJSONObject) then raise EConvertError.Create('Invalid board export row');
          Name:=Text(Arrays[I].Objects[J],'_id');
          if (Name='') or (Maps[I].Find(Name)<>nil) then raise EConvertError.Create('Invalid export identity');
          Maps[I].Add(Name,NewId);
        end;
      end;
      if TargetBoard = '' then AllocateCardNumbers;
      IndexCardCreations;
      if TargetBoard = '' then
      begin
        BoardCreationSettings(T.Db,AdminOnly,PrivateOnly,RegistryGuard);
        Permission:='EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(Actor)+
          ' AND COALESCE(loginDisabled,0)=0 AND (isAdmin=1 OR NOT '+AdminOnly+'))';
      end
      else
      begin
        RegistryGuard := '1';
        Policy := TFieldPolicy.Create(T.Db, Actor, TargetBoard, '');
        try Permission := Policy.ScopeBoardExpression(True); finally Policy.Free; end;
      end;
      ReadImportPolicy;
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin SendError(aResponse,403,'Board import is restricted');Exit;end;
      ReadMemberMapping;
      Stamp:=QuotedStr(NowIso);
      Sql := '';
      if TargetBoard = '' then
      begin
        BoardId:=NewId;Board:=QuotedStr(BoardId);
      Name:=Text(Input,'color','belize');if Name='' then Name:='belize';
      Sql:='INSERT INTO boards(id,title,slug,description,permission,color,createdAt,modifiedAt) VALUES('+
        Board+','+QuotedStr(Title)+','+QuotedStr(Slugify(Title))+','+QuotedStr(Text(Input,'description'))+
        ',''private'','+QuotedStr(Name)+','+ImportedDate(Input,'createdAt',Stamp,True)+','+
        ImportedDate(Input,'modifiedAt',Stamp,True)+'); '+
        'INSERT INTO board_members(boardId,userId,isActive,isAdmin) VALUES('+Board+','+QuotedStr(Actor)+',1,1); ';
      CreateImportedAuthors;
      ImportInactiveMembers;
      end
      else
      begin
        BoardId := TargetBoard;
        Board := QuotedStr(BoardId);
        if (Arrays[10] <> nil) and (Arrays[10].Count > 0) and not BoardCanAdmin(T.Db, Actor, BoardId) then
        begin SendError(aResponse,403,'Importing custom field definitions requires board administration');Exit;end;
        if (Arrays[10] <> nil) and (Arrays[10].Count > 0) then
        begin
          Policy := TFieldPolicy.Create(T.Db, Actor, BoardId, '');
          try Guard := Guard + ' AND ' + Policy.ScopeAdminExpression(True); finally Policy.Free; end;
        end;
      end;
      ImportDefinitions;
      ImportLabels;
      DefaultLane:='';DefaultList:='';
      if TargetCard <> '' then
      begin
        CardScope := 'boardId='+Board+' AND archived=0 AND deletedAt IS NULL';
        CardPosition := CardScope+' AND id='+QuotedStr(TargetCard);
        Rows := T.Db.Query('SELECT listId,swimlaneId FROM cards WHERE '+CardPosition+';');
        if (Length(Rows)<>1) or (Rows[0][0]='') or (Rows[0][1]='') or
          ((TargetList<>'') and (TargetList<>Rows[0][0])) or
          ((TargetLane<>'') and (TargetLane<>Rows[0][1])) then
        begin SendError(aResponse,404,'Destination card not found');Exit;end;
        TargetList := Rows[0][0];
        TargetLane := Rows[0][1];
        CardScope := CardScope+' AND listId='+QuotedStr(TargetList)+' AND swimlaneId='+QuotedStr(TargetLane);
        CardPosition := ' FROM cards WHERE '+CardScope+' AND id='+QuotedStr(TargetCard);
        Guard := Guard+' AND EXISTS(SELECT 1'+CardPosition+')';
        CardPosition := '(SELECT sort'+CardPosition+')';
        Arrays[1]:=nil;
        if (Arrays[2]<>nil) and (Arrays[2].Count>0) then
          Sql := Sql+ReserveSortSlots('cards',CardScope,TargetCard,Arrays[2].Count);
      end;
      if TargetList <> '' then
      begin
        ListPosition := ' FROM lists WHERE boardId='+Board+' AND archived=0 AND deletedAt IS NULL AND id='+QuotedStr(TargetList);
        Rows := T.Db.Query('SELECT COALESCE(swimlaneId,'''')'+ListPosition+';');
        if Length(Rows)<>1 then
        begin SendError(aResponse,404,'Destination list not found');Exit;end;
        ListLane := Rows[0][0];
        if (ListLane<>'') and (TargetLane<>'') and (ListLane<>TargetLane) then
        begin SendError(aResponse,404,'Destination list not found in swimlane');Exit;end;
        Guard := Guard+' AND EXISTS(SELECT 1'+ListPosition+
          ' AND COALESCE(swimlaneId,'''')='+QuotedStr(ListLane)+')';
        ListPosition := '(SELECT sort'+ListPosition+')';
        if TargetLane='' then TargetLane:=ListLane;
        Arrays[0]:=nil;
        DefaultList:=TargetList;
        if (Arrays[1]<>nil) and (Arrays[1].Count>0) then
        begin
          Sql := Sql+ReserveSortSlots('lists','boardId='+Board,TargetList,Arrays[1].Count);
          DefaultList:='';
        end;
      end;
      if TargetLane <> '' then
      begin
        LaneGuard := 'EXISTS(SELECT 1 FROM swimlanes WHERE boardId='+Board+
          ' AND archived=0 AND id='+QuotedStr(TargetLane)+')';
        Rows := T.Db.Query('SELECT '+LaneGuard+';');
        if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
        begin SendError(aResponse,404,'Destination swimlane not found');Exit;end;
        Guard := Guard+' AND '+LaneGuard;
        LanePosition := '(SELECT sort FROM swimlanes WHERE id='+QuotedStr(TargetLane)+')';
        if (Arrays[0]<>nil) and (Arrays[0].Count>0) then
          Sql := Sql+ReserveSortSlots('swimlanes','boardId='+Board,TargetLane,Arrays[0].Count)
        else DefaultLane := TargetLane;
      end;
      if Arrays[0]<>nil then for J:=0 to Arrays[0].Count-1 do
      begin
        Row:=Arrays[0].Objects[J];LaneId:=Mapped(0,Text(Row,'_id'),True);
        if DefaultLane='' then DefaultLane:=LaneId;
        SortSql := SortValue(Row);
        if TargetLane <> '' then SortSql := LanePosition+'+'+IntToStr(J+1)
        else if TargetBoard <> '' then
          SortSql := '(SELECT COALESCE(MAX(sort),-1)+1 FROM swimlanes WHERE boardId='+Board+')';
        Sql:=Sql+'INSERT INTO swimlanes(id,boardId,title,sort,createdAt,modifiedAt,color,archived) VALUES('+QuotedStr(LaneId)+
          ','+Board+','+QuotedStr(Text(Row,'title','Default'))+','+SortSql+','+ImportedDate(Row,'createdAt',Stamp,True)+','+
          ImportedDate(Row,'modifiedAt','NULL',True)+','+
          ImportedColor(Row)+','+BooleanValue(Row,'archived')+'); ';
      end;
      if (DefaultLane='') and (TargetBoard<>'') then
      begin
        Rows:=T.Db.Query('SELECT id FROM swimlanes WHERE boardId='+Board+' AND archived=0 ORDER BY sort,id LIMIT 1;');
        if Length(Rows)=1 then
        begin
          DefaultLane:=Rows[0][0];
          Guard:=Guard+' AND EXISTS(SELECT 1 FROM swimlanes WHERE boardId='+Board+' AND archived=0 AND id='+QuotedStr(DefaultLane)+')';
        end;
      end;
      if DefaultLane='' then
      begin
        DefaultLane:=NewId;
        Sql:=Sql+'INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES('+QuotedStr(DefaultLane)+
          ','+Board+',''Default'',0,'+Stamp+'); ';
      end;
      if Arrays[1]<>nil then for J:=0 to Arrays[1].Count-1 do
      begin
        Row:=Arrays[1].Objects[J];ListId:=Mapped(1,Text(Row,'_id'),True);
        if TargetList<>'' then LaneId:=TargetLane
        else LaneId:=Mapped(0,Text(Row,'swimlaneId'));
        if (LaneId='') and (DefaultLane=TargetLane) then LaneId:=TargetLane;
        if DefaultList='' then DefaultList:=ListId;
        ImportedListLanes.Add(ListId,LaneId);
        SortSql := SortValue(Row);
        if TargetList <> '' then SortSql := ListPosition+'+'+IntToStr(J+1)
        else if TargetBoard <> '' then
          SortSql := '(SELECT COALESCE(MAX(sort),-1)+1 FROM lists WHERE boardId='+Board+')';
        Sql:=Sql+'INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt,modifiedAt,color,width,archived,collapsed) VALUES('+
          QuotedStr(ListId)+','+Board+','+QuotedStr(LaneId)+','+
          QuotedStr(Text(Row,'title'))+','+SortSql+','+ImportedDate(Row,'createdAt',Stamp,True)+','+
          ImportedDate(Row,'modifiedAt','NULL',True)+','+ImportedColor(Row)+','+
          ImportedListWidth(Row)+','+BooleanValue(Row,'archived')+','+BooleanValue(Row,'collapsed','NULL')+'); ';
      end;
      if (DefaultList='') and (Arrays[2]<>nil) and (Arrays[2].Count>0) then
      begin
        DefaultList:=NewId;
        Sql:=Sql+'INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES('+QuotedStr(DefaultList)+
          ','+Board+','+QuotedStr(TargetLane)+',''Default'',0,'+Stamp+'); ';
      end;
      if Arrays[2]<>nil then for J:=0 to Arrays[2].Count-1 do
      begin
        Row:=Arrays[2].Objects[J];CardId:=Mapped(2,Text(Row,'_id'),True);
        CardCreation(Row,CardId,CardAuthor,CardCreated);
        CardPlacement(Row,ListId,LaneId);
        Name:=Mapped(2,Text(Row,'parentId'));
        if Name=CardId then Name:='';
        if TargetBoard = '' then NumberSql := IntToStr(CardNumbers[J])
        else NumberSql := '(SELECT COALESCE(MAX(cardNumber),0)+1 FROM cards WHERE boardId='+Board+')';
        SortSql := SortValue(Row,IntToStr(J));
        if TargetCard <> '' then SortSql := CardPosition+'+'+IntToStr(J+1);
        Sql:=Sql+'INSERT INTO cards(id,boardId,listId,swimlaneId,parentId,title,description,userId,sort,cardNumber,'+
          'createdAt,modifiedAt,dateLastActivity,receivedAt,startAt,dueAt,endAt,spentTime,isOvertime,requestedBy,assignedBy,archived,color,dueComplete) VALUES('+
          QuotedStr(CardId)+','+Board+','+
          QuotedStr(ListId)+','+QuotedStr(LaneId)+','+
          Optional(Name)+','+QuotedStr(Text(Row,'title'))+','+
          QuotedStr(Text(Row,'description'))+','+QuotedStr(CardAuthor)+','+SortSql+','+NumberSql+
          ','+CardCreated+','+ImportedDate(Row,'modifiedAt',Stamp)+','+
          ImportedDate(Row,'dateLastActivity',Stamp)+','+
          ImportedDate(Row,'receivedAt','NULL')+','+ImportedDate(Row,'startAt','NULL')+','+
          ImportedDate(Row,'dueAt','NULL')+','+ImportedDate(Row,'endAt','NULL')+','+
          ImportedSpentTime(Row)+','+BooleanValue(Row,'isOvertime')+','+QuotedStr(Text(Row,'requestedBy'))+','+
          QuotedStr(Text(Row,'assignedBy'))+','+BooleanValue(Row,'archived')+','+ImportedColor(Row)+','+BooleanValue(Row,'dueComplete')+'); ';
        ImportParentLinks(Row,CardId);
        ImportCardPeople(Row,CardId);
        ImportCardDecorations(Row,CardId);
        ImportCardVoting(Row,CardId);
        ImportCardFields(Row,CardId);
        ImportCardLabels(Row,CardId);
        ImportCardDependencies(Row,CardId);
        ImportAttachedCards(Row,CardId);
      end;
      ImportCardChildren;
      ImportAttachments;
      for I:=3 to 5 do ImportWorkflow(I);
      if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN '+AuthSourceCondition(T.Db)+' AND '+RegistryGuard+
        ' AND '+Guard+' AND '+Permission+' THEN 1 ELSE json(''Board import policy changed'') END; '+Sql+'COMMIT;') then
        raise Exception.Create('Board import failed');
      Committed:=True;
    except
      on E:EConvertError do
      begin
        if MethodActor<>'' then SendJson(aResponse,'{"error":"invalid-import-format","reason":"Invalid board export"}',400)
        else SendError(aResponse,400,'Invalid board export');
        Exit;
      end;
      on E:Exception do begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not import board');Exit;end;
    end;
    LossDetail:=Body.Get('importLosses','');
    if (SourceFormat<>'') and (LossDetail<>'') and IsShared(T.Db) then
    begin
      Row:=TJSONObject.Create(['_id',NewId,'type','import-completed-with-warnings','severity','warning',
        'source','import:'+SourceFormat,'detail',LossDetail,'userId',Actor,'createdAt',DateTimeToUnix(Now,False)*1000,'done',True,'deletedData',False]);
      try
        Row.Add('boardIds',TJSONArray.Create([BoardId]));
        Row.Add('boardTitles',TJSONArray.Create([Title]));
        try if not T.Db.Exec(InsertDocSql(T.Db,'recoveryEvents',Row,'{"createdAt":"date"}')) then WriteLn(StdErr,'Recovery SQL failed'); except on E:Exception do WriteLn(StdErr,'Recovery event could not be recorded'); end;
      finally Row.Free; end;
    end;
    if MethodActor<>'' then
    begin
      Reply:=TJSONObject.Create(['_id',BoardId,'boardId',BoardId]);
      if LossDetail<>'' then Reply.Add('importLosses',TJSONArray.Create([LossDetail]));
      try SendJson(aResponse,'{"result":'+Reply.AsJSON+'}'); finally Reply.Free; end;
      Exit;
    end;
    Reply:=TJSONObject.Create(['_id',BoardId]);
    if ZipRoute then
    begin
      Reply.Add('ok', True);
      Reply.Add('boardId', BoardId);
      Row := TJSONObject.Create;
      Reply.Add('counts', Row);
      for I in [0,1,2,6,7,8,9] do
        if Arrays[I] <> nil then Row.Add(Collections[I], Arrays[I].Count);
    end;
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  finally
    if not Committed then for I:=0 to Files.Count-1 do DeleteFile(Files[I]);
    ImportedMembers.Free;ImportedListLanes.Free;CardCreations.Free;MemberMap.Free;Files.Free;
    for I:=0 to High(Maps) do Maps[I].Free;
    Body.Free;
  end;
end;

procedure ApiImportBoard(aRequest:TRequest;aResponse:TResponse);
begin
  ImportBoardRequest(aRequest,aResponse,Default(TWLTenant),'','','');
end;

procedure ImportBoardMethod(aRequest:TRequest;aResponse:TResponse; const Tenant: TWLTenant; const Actor: string; Args: TJSONData);
begin
  if not (Args is TJSONArray) or (Args.Count<>3) or not (Args.Items[0].JSONType in [jtObject,jtArray]) or
    not (Args.Items[1] is TJSONObject) or (Args.Items[2].JSONType<>jtString) then
  begin SendJson(aResponse,'{"error":"Match.Error","reason":"Match failed"}',400); Exit; end;
  if not ExternalImportSupported(Args.Items[2].AsString) then
  begin SendJson(aResponse,'{"error":"invalid-import-format","reason":"Unknown import source"}',400); Exit; end;
  if Args.Items[1].Count<>0 then
  begin SendJson(aResponse,'{"error":"invalid-member-mapping","reason":"External import member mapping is unavailable"}',400); Exit; end;
  ImportBoardRequest(aRequest,aResponse,Tenant,Actor,Args.Items[0].AsJSON,Args.Items[2].AsString);
end;

function CopyBoardWorkflows(Db:TWLDb;const Source,Destination,Actor:string):string;
const Collections:array[0..3] of string=('triggers','actions','rules','integrations');
var Graph,Part:TJSONObject;Copies:TJSONArray;Rows:TWLRows;Raw,TableName,Physical,Storage,Payload,
  Key,Mapped,Guards:string;Maps:array[0..1] of TJSONObject;I,J:Integer;
  procedure SetString(Obj:TJSONObject;const Name,Text:string);
  begin Obj.Delete(Name);Obj.Add(Name,Text);end;
  procedure WriteRow(Row:TJSONObject;const Previous:string);
  begin
    Payload:=QuotedStr(TypedDocument(Row.AsJSON,Previous,'{}'));
    Result:=Result+'INSERT INTO '+Physical+'(_ferretdb_sjson) VALUES(CASE WHEN wl_storage('+QuotedStr(Storage)+
      ')=''blob'' THEN jsonb('+Payload+') ELSE '+Payload+' END); ';
  end;
  procedure RemapParts(Row:TJSONObject;const Primary,Extra:string;IdMap:TJSONObject);
  var Parts:TJSONArray;V:TJSONData;N:Integer;Id:string;
  begin
    Id:=IdMap.Get(Row.Get(Primary,''),'');
    if Id='' then raise Exception.Create('Missing workflow component');
    SetString(Row,Primary,Id);
    V:=Row.Find(Extra);if not (V is TJSONArray) then Exit;
    Parts:=TJSONArray.Create;
    for N:=0 to V.Count-1 do
      if V.Items[N] is TJSONString then
      begin
        Id:=IdMap.Get(V.Items[N].AsString,'');if Id<>'' then Parts.Add(Id);
      end;
    Row.Delete(Extra);Row.Add(Extra,Parts);
  end;
begin
  Result:='';
  if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))=0 then Exit;
  Graph:=TJSONObject.Create;Maps[0]:=nil;Maps[1]:=nil;Guards:='';
  try
    if not Db.BeginRead then raise Exception.Create('Could not pin board workflow source');
    try
      ReadExportWorkflows(Db,Source,Graph);
      for I:=0 to High(Collections) do
      begin
        TableName:=Collections[I];
        Rows:=Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name='+QuotedStr(TableName)+';');
        if Length(Rows)>1 then raise Exception.Create('Ambiguous board workflow source');
        if Length(Rows)=0 then
        begin
          Guards:=Guards+' AND NOT EXISTS(SELECT 1 FROM _ferretdb_collections WHERE name='+QuotedStr(TableName)+')';
          Continue;
        end;
        Storage:=Rows[0][0];Physical:='"'+StringReplace(Storage,'"','""',[rfReplaceAll])+'"';
        Guards:=Guards+' AND (SELECT count(*) FROM _ferretdb_collections WHERE name='+QuotedStr(TableName)+
          ' AND table_name='+QuotedStr(Storage)+')=1';
        if TableName='integrations' then
        begin
          Rows:=Db.Query('SELECT json(_ferretdb_sjson) FROM '+Physical+
            ' WHERE json_extract(_ferretdb_sjson,''$.boardId'')='+QuotedStr(Source)+
            ' AND json_extract(_ferretdb_sjson,''$.$s.p.boardId.t'')=''string'''+
            ' AND json_extract(_ferretdb_sjson,''$.$s.p._id.t'')=''string'';');
          for J:=0 to High(Rows) do
          begin
            Raw:=Rows[J][0];Part:=ExactObject(PlainDocument(Raw));
            try
              SetString(Part,'_id',NewId);SetString(Part,'boardId',Destination);SetString(Part,'userId',Actor);
              WriteRow(Part,Raw);
            finally Part.Free;end;
          end;
          Continue;
        end;
        Copies:=TJSONArray(Graph.Find(TableName));
        if I<2 then Maps[I]:=TJSONObject.Create;
        for J:=0 to Copies.Count-1 do
        begin
          Key:=Copies.Objects[J].Get('_id','');Mapped:=NewId;
          if I<2 then Maps[I].Add(Key,Mapped);
          Rows:=Db.Query('SELECT json(_ferretdb_sjson) FROM '+Physical+
            ' WHERE json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(Key)+
            ' AND json_extract(_ferretdb_sjson,''$.$s.p._id.t'')=''string'';');
          if Length(Rows)<>1 then raise Exception.Create('Workflow source changed');
          Raw:=Rows[0][0];Part:=ExactObject(PlainDocument(Raw));
          try
            SetString(Part,'_id',Mapped);SetString(Part,'boardId',Destination);
            if TableName='rules' then
            begin
              if (Maps[0]=nil) or (Maps[1]=nil) then raise Exception.Create('Missing workflow components');
              RemapParts(Part,'triggerId','extraTriggerIds',Maps[0]);
              RemapParts(Part,'actionId','extraActionIds',Maps[1]);
            end;
            WriteRow(Part,Raw);
          finally Part.Free;end;
        end;
      end;
    finally
      if not Db.EndRead then raise Exception.Create('Could not close board workflow source');
    end;
    if Guards<>'' then Result:='SELECT CASE WHEN 1'+Guards+' THEN 1 ELSE json(''Workflow source changed'') END; '+Result;
  finally Maps[1].Free;Maps[0].Free;Graph.Free;end;
end;

// POST copy board — structural deep copy: board + members + swimlanes + lists + cards, with
// remapped ids. (Labels/checklists/comments copy is TODO.)
procedure ApiBoardCopy(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; UserId, SrcId, Title, NewBoard,Sql,Permission,AdminOnly,PrivateOnly,RegistryGuard,Visibility: string;
  Policy:TFieldPolicy;
  B, Rows: TWLRows;
  swMap, listMap: TStringList;
  i: Integer;
  newSw, newList, newCard: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  SrcId := aRequest.RouteParams['boardId'];
  Policy:=TFieldPolicy.Create(T.Db,UserId,SrcId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board administration required');Exit;end;
  try BoardCreationSettings(T.Db,AdminOnly,PrivateOnly,RegistryGuard);
  except SendError(aResponse,500,'Could not read board creation policy');Exit;end;
  Permission:=Permission+' AND (NOT '+AdminOnly+' OR EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(UserId)+
    ' AND isAdmin=1 AND COALESCE(loginDisabled,0)=0))';
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board creation is restricted to admins');Exit;end;
  Title := BodyField(aRequest, 'title');

  B := T.Db.Query(Format('SELECT title,permission,type,color FROM boards WHERE id=%s LIMIT 1;',
    [QuotedStr(SrcId)]));
  if Length(B) = 0 then begin SendError(aResponse, 404, 'Board not found'); Exit; end;
  if Title = '' then Title := B[0][0] + ' Copy';
  if Pos(#0,Title)>0 then begin SendError(aResponse,400,'Invalid board title');Exit;end;
  NewBoard := NewId;
  Visibility:='CASE WHEN '+PrivateOnly+' THEN ''private'' ELSE '+QuotedStr(B[0][1])+' END';
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+' AND '+RegistryGuard+' THEN 1 ELSE json(''Copy permission changed'') END; '+Format(
    'INSERT INTO boards(id,title,slug,permission,type,color,createdAt,modifiedAt) ' +
    'VALUES(%s,%s,%s,%s,%s,%s,%s,%s);',
    [QuotedStr(NewBoard), QuotedStr(Title), QuotedStr(Slugify(Title)),
     Visibility, QuotedStr(B[0][2]), QuotedStr(B[0][3]),
     QuotedStr(NowIso), QuotedStr(NowIso)]);

  // members
  Rows := T.Db.Query(Format('SELECT userId,isAdmin FROM board_members WHERE boardId=%s AND isActive=1;', [QuotedStr(SrcId)]));
  for i := 0 to High(Rows) do
    if Length(Rows[i]) >= 2 then
      Sql:=Sql+Format('INSERT INTO board_members(boardId,userId,isAdmin) VALUES(%s,%s,%s);',
        [QuotedStr(NewBoard), QuotedStr(Rows[i][0]), QuotedStr(Rows[i][1])]);

  swMap := TStringList.Create; swMap.CaseSensitive := True;
  listMap := TStringList.Create; listMap.CaseSensitive := True;
  try
    // swimlanes
    Rows := T.Db.Query(Format('SELECT id,title,COALESCE(sort,0) FROM swimlanes WHERE boardId=%s;', [QuotedStr(SrcId)]));
    for i := 0 to High(Rows) do
      if Length(Rows[i]) >= 3 then
      begin
        newSw := NewId; swMap.Values[Rows[i][0]] := newSw;
        Sql:=Sql+Format('INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES(%s,%s,%s,%s,%s);',
          [QuotedStr(newSw), QuotedStr(NewBoard), QuotedStr(Rows[i][1]), QuotedStr(Rows[i][2]), QuotedStr(NowIso)]);
      end;
    // lists
    Rows := T.Db.Query(Format('SELECT id,title,COALESCE(sort,0),swimlaneId FROM lists WHERE boardId=%s AND deletedAt IS NULL;', [QuotedStr(SrcId)]));
    for i := 0 to High(Rows) do
      if Length(Rows[i]) >= 4 then
      begin
        newList := NewId; listMap.Values[Rows[i][0]] := newList;
        Sql:=Sql+Format('INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES(%s,%s,%s,%s,%s,%s);',
          [QuotedStr(newList), QuotedStr(NewBoard), QuotedStr(swMap.Values[Rows[i][3]]),
           QuotedStr(Rows[i][1]), QuotedStr(Rows[i][2]), QuotedStr(NowIso)]);
      end;
    // cards
    Rows := T.Db.Query(Format(
      'SELECT id,title,description,listId,swimlaneId,userId,color,COALESCE(sort,0) FROM cards WHERE boardId=%s AND deletedAt IS NULL;',
      [QuotedStr(SrcId)]));
    for i := 0 to High(Rows) do
      if Length(Rows[i]) >= 8 then
      begin
        newCard := NewId;
        Sql:=Sql+Format(
          'INSERT INTO cards(id,boardId,listId,swimlaneId,title,description,userId,color,sort,' +
          'dateLastActivity,createdAt,modifiedAt) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);',
          [QuotedStr(newCard), QuotedStr(NewBoard),
           QuotedStr(listMap.Values[Rows[i][3]]), QuotedStr(swMap.Values[Rows[i][4]]),
           QuotedStr(Rows[i][1]), QuotedStr(Rows[i][2]), QuotedStr(Rows[i][5]),
           QuotedStr(Rows[i][6]), QuotedStr(Rows[i][7]),
           QuotedStr(NowIso), QuotedStr(NowIso), QuotedStr(NowIso)]);
      end;
  finally
    swMap.Free; listMap.Free;
  end;
  try
    Sql:=Sql+CopyBoardWorkflows(T.Db,SrcId,NewBoard,UserId)+'COMMIT;';
    if not T.Db.Exec(Sql) then raise Exception.Create('Board copy failed');
  except T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not copy board');Exit;end;
  SendJson(aResponse,'"'+StringToJSONString(NewBoard)+'"');
end;

procedure RecordContainerText(Db:TWLDb;const UserId,BoardId,Entity,Id,Field,OldTitle,NewTitle:string);
var Before,After:TJSONObject;
begin
  if OldTitle=NewTitle then Exit;
  Before:=TJSONObject.Create(['field',Field,'value',OldTitle]);
  After:=TJSONObject.Create(['field',Field,'value',NewTitle]);
  try
    try RecordHistoryRow(Db,UserId,BoardId,Entity,Id,'title','edited',Before,After);except end;
  finally Before.Free;After.Free;end;
end;

procedure ApiSwimlane(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"Swimlane not found"}';
var T:TWLTenant;UserId,BoardId,LaneId,Scope,Title,OldTitle,Permission,Sql:string;
  Rows:TWLRows;Body:TJSONObject;Value:TJSONData;Policy:TFieldPolicy;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];LaneId:=aRequest.RouteParams['swimlaneId'];
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  Scope:='id='+QuotedStr(LaneId)+' AND boardId='+QuotedStr(BoardId);
  if aRequest.Method='GET' then
  begin
    Rows:=T.Db.Query('SELECT json_object(''_id'',id,''boardId'',boardId,''title'',title,''type'',type,'+
      '''color'',color,''sort'',sort,''height'',height,''archived'',json(''false''),''createdAt'',createdAt,'+
      '''modifiedAt'',modifiedAt,''updatedAt'',updatedAt) FROM swimlanes WHERE '+Scope+' AND archived=0;');
    if Length(Rows)<>1 then SendJson(aResponse,NotFound,404)
    else SendJson(aResponse,Rows[0][0]);
    Exit;
  end;
  Rows:=T.Db.Query('SELECT title FROM swimlanes WHERE '+Scope+';');
  if Length(Rows)<>1 then
  begin SendJson(aResponse,NotFound,404);Exit;end;
  OldTitle:=Rows[0][0];
  Body:=nil;
  try
    try
      Title:=aRequest.ContentFields.Values['title'];
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
      begin
        Body:=ExactObject(aRequest.Content);Value:=Body.Find('title');
        if not (Value is TJSONString) then raise Exception.Create('Invalid title');
        Title:=Value.AsString;
      end;
      CheckUtf8(Title);
      if (Trim(Title)='') or (Pos(#0,Title)>0) then raise Exception.Create('Invalid title');
    except SendError(aResponse,400,'Invalid swimlane title');Exit;end;
  finally Body.Free;end;
  Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
  try Permission:=Policy.ScopeBoardExpression(True);finally Policy.Free;end;
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+' AND (SELECT count(*) FROM swimlanes WHERE '+Scope+
    ')=1 THEN 1 ELSE json(''Swimlane scope changed'') END; UPDATE swimlanes SET title='+QuotedStr(Title)+
    ' WHERE '+Scope+'; SELECT CASE WHEN EXISTS(SELECT 1 FROM swimlanes WHERE '+Scope+
    ' AND title='+QuotedStr(Title)+') THEN 1 ELSE json(''Swimlane update failed'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not edit swimlane');Exit;end;
  RecordContainerText(T.Db,UserId,BoardId,'swimlane',LaneId,'title',OldTitle,Title);
  SendJson(aResponse,'{"_id":"'+StringToJSONString(LaneId)+'"}');
end;

procedure ApiSwimlanes(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, Title, Id: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  if aRequest.Method = 'POST' then
  begin
    Title := BodyField(aRequest, 'title');
    if Title = '' then Title := 'Default';
    Id := NewId;
    T.Db.Exec(Format('INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES(%s,%s,%s,0,%s);',
      [QuotedStr(Id), QuotedStr(BoardId), QuotedStr(Title), QuotedStr(NowIso)]));
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
    Exit;
  end;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT id,title FROM swimlanes WHERE boardId=%s AND archived=0 ORDER BY sort;',
    [QuotedStr(BoardId)]))));
end;

// PUT board label — return the existing or newly created label ID as JSON.
const
  LabelColors='|white|green|yellow|orange|red|purple|blue|sky|lime|pink|black|silver|'+
    'peachpuff|crimson|plum|darkgreen|slateblue|magenta|gold|navy|gray|saddlebrown|paleturquoise|mistyrose|indigo|';

// Who may create a board's labels: its board admins (#5819). Permission is
// the SQL expression the write checks again inside its transaction.
function BoardLabelPermission(Db:TWLDb;const UserId,BoardId:string;out Permission,Error:string):Integer;
var Policy:TFieldPolicy;Rows:TWLRows;
begin
  Permission:='';Error:='';
  if (BoardId='') or (Pos(#0,BoardId)>0) or
    (Length(Db.Query('SELECT id FROM boards WHERE id='+QuotedStr(BoardId)+';'))<>1) then
  begin Error:='Board not found';Exit(404);end;
  Policy:=TFieldPolicy.Create(Db,UserId,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=Db.Query('SELECT '+Permission+';');
  if Length(Rows)<>1 then begin Error:='Could not check label permission';Exit(500);end;
  if Rows[0][0]<>'1' then begin Error:='Only a board admin can create or edit labels';Exit(403);end;
  Result:=200;
end;

// The label, or the board's label of the same name and color: its id.
function WriteBoardLabel(const T:TWLTenant;const BoardId,Permission,RawName,RawColor:string;out LabelId,Error:string):Integer;
var Name,Color,Existing,Id,Board:string;Rows:TWLRows;
begin
  LabelId:='';Error:='';
  Name:=Trim(RawName);Color:=RawColor;
  try CheckUtf8(Name);except Error:='Invalid label';Exit(400);end;
  if Pos(#0,Name)>0 then begin Error:='Invalid label';Exit(400);end;
  if Color='' then Color:='green';
  if (Pos('|',Color)>0) or (Pos('|'+Color+'|',LabelColors)=0) then begin Error:='Invalid label';Exit(400);end;
  Board:=QuotedStr(BoardId);
  Existing:='SELECT id FROM board_labels WHERE boardId='+Board+' AND name='+QuotedStr(Name)+
    ' AND color='+QuotedStr(Color)+' ORDER BY id LIMIT 1';
  Rows:=T.Db.Query('SELECT lower(hex(randomblob(3)));');
  if Length(Rows)<>1 then begin Error:='Could not create label';Exit(500);end;
  Id:=Rows[0][0];
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+' THEN 1 ELSE json(''Label permission changed'') END; '+
    'INSERT INTO board_labels(boardId,id,name,color) SELECT '+Board+','+QuotedStr(Id)+','+
    QuotedStr(Name)+','+QuotedStr(Color)+' WHERE NOT EXISTS('+Existing+'); '+
    'SELECT CASE WHEN '+Permission+' AND EXISTS('+Existing+') THEN 1 ELSE json(''Label write failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not create label';Exit(500);end;
  Rows:=T.Db.Query(Existing+';');
  if Length(Rows)<>1 then begin Error:='Could not find label';Exit(500);end;
  LabelId:=Rows[0][0];
  Result:=200;
end;

procedure ApiCreateLabel(aRequest: TRequest; aResponse: TResponse);
var T:TWLTenant;UserId,BoardId,Color,Name,Id,Permission,Error:string;Code:Integer;
  Body:TJSONObject;LabelData,Value:TJSONData;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];
  Code:=BoardLabelPermission(T.Db,UserId,BoardId,Permission,Error);
  if Code<>200 then begin SendError(aResponse,Code,Error);Exit;end;
  Name:='';Color:='';Body:=nil;
  try
    try
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
      begin
        Body:=ExactObject(aRequest.Content);LabelData:=Body.Find('label');
        if LabelData=nil then raise Exception.Create('Missing label');
        if LabelData.JSONType=jtString then Name:=LabelData.AsString
        else if LabelData is TJSONObject then
        begin
          Value:=TJSONObject(LabelData).Find('name');
          if (Value<>nil) and (Value.JSONType<>jtNull) then Name:=Value.AsString;
          Value:=TJSONObject(LabelData).Find('color');
          if (Value<>nil) and (Value.JSONType<>jtNull) then Color:=Value.AsString;
        end else raise Exception.Create('Invalid label');
      end else
      begin
        Name:=aRequest.ContentFields.Values['label'];
        if Name='' then Name:=aRequest.ContentFields.Values['name'];
        Color:=aRequest.ContentFields.Values['color'];
        if (Name='') and (Color='') then raise Exception.Create('Missing label');
      end;
    except SendError(aResponse,400,'Invalid label');Exit;end;
  finally Body.Free;end;
  Code:=WriteBoardLabel(T,BoardId,Permission,Name,Color,Id,Error);
  if Code<>200 then begin SendError(aResponse,Code,Error);Exit;end;
  SendJson(aResponse,'"'+StringToJSONString(Id)+'"');
end;

function CreateViewLabel(const T:TWLTenant;const UserId,BoardId,Name,Color:string;out LabelId,Error:string):Integer;
var Permission:string;
begin
  LabelId:='';
  Result:=BoardLabelPermission(T.Db,UserId,BoardId,Permission,Error);
  if Result=200 then Result:=WriteBoardLabel(T,BoardId,Permission,Name,Color,LabelId,Error);
end;

function BoardCanCreateLabel(Db:TWLDb;const UserId,BoardId:string):Boolean;
var Permission,Error:string;
begin
  Result:=BoardLabelPermission(Db,UserId,BoardId,Permission,Error)=200;
end;

function BoolInt(const S: string): Integer;
begin
  if (LowerCase(Trim(S)) = 'true') or (Trim(S) = '1') then Result := 1 else Result := 0;
end;

function DefinitionInput(Request:TRequest;out Name,Kind:string;out Flags:TDefinitionFlags;out Settings:TJSONObject):Boolean;
var Doc:TJSONObject;Value,Legacy:TJSONData;i,Other:Integer;Key:string;
begin
  Result:=False;Name:='';Kind:='';Doc:=nil;Settings:=nil;
  try
    try
      if Pos('application/json',LowerCase(Request.ContentType))=1 then Doc:=ExactObject(Request.Content)
      else begin
        Doc:=TJSONObject.Create;
        for i:=0 to Request.ContentFields.Count-1 do
        begin
          Key:=LowerCase(Request.ContentFields.Names[i]);
          if (Key='') or (Doc.Find(Key)<>nil) then Exit;
          Doc.Add(Key,Request.ContentFields.ValueFromIndex[i]);
        end;
      end;
      Value:=Doc.Find('name');if (Value=nil) or (Value.JSONType<>jtString) then Exit;
      Name:=Value.AsString;if (Trim(Name)='') or (Pos(#0,Name)>0) then Exit;CheckUtf8(Name);
      Kind:='text';Value:=Doc.Find('type');
      if Value<>nil then begin if Value.JSONType<>jtString then Exit;Kind:=Value.AsString;end;
      if Kind='' then Kind:='text';
      if not ValidDefinitionType(Kind) then Exit;
      if not SettingsInput(Doc.Find('settings'),Settings) then Exit;
      for i:=0 to High(Flags) do
      begin
        Value:=Doc.Find(DefinitionFlagNames[i]);Legacy:=Doc.Find(LowerCase(DefinitionFlagNames[i]));
        if Value=nil then Value:=Legacy;
        if not DefinitionFlag(Value,Flags[i]) then Exit;
        if (Value<>Legacy) and (Legacy<>nil) then
        begin if not DefinitionFlag(Legacy,Other) or (Other<>Flags[i]) then Exit;end;
      end;
      Result:=True;
    except Result:=False;end;
  finally if not Result then FreeAndNil(Settings);Doc.Free;end;
end;

// A board's new custom field: the field policy's definition right, its
// dropdown items, the createCustomField activity. 200 and its id, or the
// status and why not.
function WriteBoardField(const T:TWLTenant;const UserId,BoardId,Name,Typ:string;const Flags:TDefinitionFlags;
  Settings:TJSONObject;out Id,Error:string):Integer;
var Stamp,Sql,GuardSql,DropdownSql,DropdownGuards,SortSql:string;Data:TJSONObject;Rows:TWLRows;Policy:TFieldPolicy;
begin
  Id:='';Error:='';
  Policy:=nil;
  try
    try
      Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
      Rows:=T.Db.Query('SELECT '+Policy.DefinitionExpression('',Flags[5]=1)+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin Error:='Custom-field creation forbidden';Exit(403);end;
    except Error:='Custom-field creation forbidden';Exit(403);end;
    Id:=NewId;Stamp:=NowIso;
    try DropdownSql:=DropdownScript(T.Db,Id,Settings,DropdownGuards);
    except Error:='Could not prepare dropdown settings';Id:='';Exit(500);end;
    GuardSql:='SELECT CASE WHEN '+Policy.DefinitionExpression('',Flags[5]=1)+' THEN 1 ELSE json(''Field creation forbidden'') END; ';
    SortSql:='(SELECT COALESCE(MAX(f.sort),-1)+1 FROM custom_fields f JOIN custom_field_boards b '+
      'ON b.customFieldId=f.id WHERE b.boardId='+QuotedStr(BoardId)+')';
    Sql:='BEGIN IMMEDIATE; '+DropdownGuards+GuardSql+Format(
      'INSERT INTO custom_fields(id,name,type,sort,showOnCard,automaticallyOnCard,'+
      'showLabelOnMiniCard,showSumAtTopOfList,readOnly,adminOnly,createdAt,modifiedAt,currencyCode,stringtemplateFormat,stringtemplateSeparator,settings_json) VALUES(%s,%s,%s,%s,%d,%d,%d,%d,%d,%d,%s,%s,%s,%s,%s,%s);',
      [QuotedStr(Id),QuotedStr(Name),QuotedStr(Typ),SortSql,Flags[0],Flags[1],Flags[2],Flags[3],Flags[4],Flags[5],QuotedStr(Stamp),QuotedStr(Stamp),SettingsLiteral(Settings,'currencyCode'),
       SettingsLiteral(Settings,'stringtemplateFormat'),SettingsLiteral(Settings,'stringtemplateSeparator'),SettingsRemainder(Settings)])+
      'INSERT INTO custom_field_boards(customFieldId,boardId) VALUES('+QuotedStr(Id)+','+QuotedStr(BoardId)+'); '+DropdownSql;
    Data:=TJSONObject.Create(['customFieldId',Id]);
    try
      Sql:=Sql+'INSERT INTO activities(id,activityType,userId,boardId,createdAt,modifiedAt,data_json) VALUES('+
        QuotedStr(NewId)+',''createCustomField'','+QuotedStr(UserId)+','+QuotedStr(BoardId)+','+
        QuotedStr(Stamp)+','+QuotedStr(Stamp)+','+QuotedStr(Data.AsJSON)+'); '+
        'SELECT CASE WHEN '+Policy.DefinitionExpression(Id,Flags[5]=1)+' THEN 1 ELSE json(''Field creation forbidden'') END; '+DropdownGuards+'COMMIT;';
    finally Data.Free;end;
    if not T.Db.Exec(Sql) then
    begin T.Db.Exec('ROLLBACK;');Id:='';Error:='Could not create custom field';Exit(500);end;
  finally Policy.Free;end;
  Result:=200;
end;

// createCustomFieldPopup from the card's picker: a field of the board by its
// name and type, shown on cards, with the REST API's checks.
function CreateViewCustomField(const T:TWLTenant;const UserId,BoardId,Name,Typ:string;out Id,Error:string):Integer;
var Flags:TDefinitionFlags;Settings:TJSONObject;i:Integer;
begin
  Id:='';
  if (BoardId='') or (Trim(Name)='') or (Length(Name)>200) or (Pos(#0,BoardId+Name)>0) or not ValidDefinitionType(Typ) then
  begin Error:='a name and a known type are needed';Exit(400);end;
  try CheckUtf8(Name);except Error:='a name and a known type are needed';Exit(400);end;
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Custom-field creation forbidden';Exit(403);end;
  for i:=0 to High(Flags) do Flags[i]:=0;
  Flags[0]:=1;
  Settings:=TJSONObject.Create;
  try Result:=WriteBoardField(T,UserId,BoardId,Trim(Name),Typ,Flags,Settings,Id,Error);
  finally Settings.Free;end;
end;

// GET board custom fields / POST create a custom field
procedure ApiCustomFields(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, Id, Name, Typ, Error: string;Flags:TDefinitionFlags;Reply,Settings:TJSONObject;Rows:TWLRows;Items:TJSONArray;Index,Code:Integer;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  if aRequest.Method = 'POST' then
  begin
    if not DefinitionInput(aRequest,Name,Typ,Flags,Settings) then
    begin SendError(aResponse,400,'Invalid custom-field name, type, options or unsupported settings');Exit;end;
    try
      Code:=WriteBoardField(T,UserId,BoardId,Name,Typ,Flags,Settings,Id,Error);
    finally Settings.Free;end;
    if Code<>200 then begin SendError(aResponse,Code,Error);Exit;end;
    Reply:=TJSONObject.Create(['_id',Id]);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
    Exit;
  end;
  Rows:=T.Db.Query(Format('SELECT cf.id,cf.name,cf.type FROM custom_fields cf '+
    'JOIN custom_field_boards b ON b.customFieldId=cf.id WHERE b.boardId=%s ORDER BY cf.name;',[QuotedStr(BoardId)]));
  Items:=TJSONArray.Create;
  try
    for Index:=0 to High(Rows) do
      Items.Add(TJSONObject.Create(['_id',Rows[Index][0],'name',Rows[Index][1],'type',Rows[Index][2]]));
    SendJson(aResponse,Items.AsJSON);
  finally Items.Free;end;
end;

const CustomFieldNotFound = '{"error":"Custom field not found"}';

procedure ApiCustomField(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId, CustomFieldNotFound) then Exit;
  O:=nil;
  try
    try O:=ReadDefinition(T.Db,aRequest.RouteParams['customField']);
    except SendError(aResponse,500,'Could not read custom-field definition');Exit;end;
    if O=nil then begin SendJson(aResponse,CustomFieldNotFound,404);Exit;end;
    SendJson(aResponse,O.AsJSON);
  finally O.Free;end;
end;

// Pin both the authorized boards and the exact size of the binding set.
procedure DefinitionWriteScope(Db:TWLDb;const UserId,FieldId,RouteBoardId:string;
  out BoardIds,Permission,AfterDelete:string);
var Rows:TWLRows;Row:TWLRow;Policy:TFieldPolicy;Previous:string;RouteFound:Boolean;
begin
  Rows:=Db.Query('SELECT boardId FROM custom_field_boards WHERE customFieldId='+QuotedStr(FieldId)+' ORDER BY boardId;');
  if Length(Rows)=0 then raise Exception.Create('Missing definition bindings');
  BoardIds:='';AfterDelete:='1';Previous:='';RouteFound:=False;
  Permission:='(SELECT count(*) FROM custom_field_boards WHERE customFieldId='+QuotedStr(FieldId)+')='+IntToStr(Length(Rows));
  for Row in Rows do
  begin
    if (Length(Row)<>1) or (Row[0]='') then raise Exception.Create('Invalid definition binding');
    if Row[0]=Previous then raise Exception.Create('Duplicate definition binding');
    Previous:=Row[0];RouteFound:=RouteFound or (Row[0]=RouteBoardId);
    if BoardIds<>'' then BoardIds:=BoardIds+',';
    BoardIds:=BoardIds+QuotedStr(Row[0]);
    Policy:=TFieldPolicy.Create(Db,UserId,Row[0],'');
    try
      Permission:=Permission+' AND '+Policy.ScopeWriteExpression(FieldId);
      AfterDelete:=AfterDelete+' AND '+Policy.DefinitionExpression('',False);
    finally Policy.Free;end;
  end;
  if not RouteFound then raise Exception.Create('Definition bindings changed');
  BoardIds:='('+BoardIds+')';
end;

procedure ApiUpdateCustomField(aRequest:TRequest;aResponse:TResponse);
const Keys:array[0..6] of string=('name','type','showOnCard','automaticallyOnCard','alwaysOnCard',
  'showLabelOnMiniCard','showSumAtTopOfList');
var T:TWLTenant;UserId,BoardId,FieldId,Permission,Sql,Changes,SettingsSql,Guards,ValueSql,TextValue,BackfillSql,BoardIds,AfterDelete:string;
  Scope:TSelectionScope;Rows:TWLRows;Doc,Settings,Reply:TJSONObject;
  Value:TJSONData;i,FlagValue:Integer;
  function Guard(const Condition:string):string;
  begin Result:='SELECT CASE WHEN '+Condition+' THEN 1 ELSE json(''Custom field update guard failed'') END; ';end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,CustomFieldNotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];FieldId:=aRequest.RouteParams['customField'];
  Doc:=nil;Settings:=nil;Scope:=nil;
  try
    try
      Scope:=TSelectionScope.Create(T.Db);
      Rows:=T.Db.Query('SELECT count(*) FROM custom_fields WHERE id='+QuotedStr(FieldId)+
        ' AND '+Scope.StringField('custom_fields','id')+' AND EXISTS(SELECT 1 FROM custom_field_boards WHERE customFieldId='+
        QuotedStr(FieldId)+' AND boardId='+QuotedStr(BoardId)+' AND '+Scope.StringField('custom_field_boards','boardId')+');');
      if Length(Rows)<>1 then raise Exception.Create('Could not validate scope');
      if Rows[0][0]='0' then begin SendJson(aResponse,CustomFieldNotFound,404);Exit;end;
      DefinitionWriteScope(T.Db,UserId,FieldId,BoardId,BoardIds,Permission,AfterDelete);
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin SendError(aResponse,403,'Custom field update forbidden');Exit;end;
      if (aRequest.Content<>'') and (Pos('application/json',LowerCase(aRequest.ContentType))=1) then
        Doc:=ExactObject(aRequest.Content)
      else
      begin
        Doc:=TJSONObject.Create;
        for i:=0 to aRequest.ContentFields.Count-1 do
          Doc.Add(aRequest.ContentFields.Names[i],aRequest.ContentFields.ValueFromIndex[i]);
      end;
      Changes:='';BackfillSql:='';
      for i:=0 to High(Keys) do
      begin
        Value:=Doc.Find(Keys[i]);if Value=nil then Continue;
        if i<2 then
        begin
          if not (Value is TJSONString) then raise Exception.Create('Invalid definition text');
          TextValue:=Value.AsString;CheckUtf8(TextValue);
          if (Trim(TextValue)='') or (Pos(#0,TextValue)>0) or ((i=1) and not ValidDefinitionType(TextValue)) then
            raise Exception.Create('Invalid definition text');
          ValueSql:=QuotedStr(TextValue);
        end else begin
          if not DefinitionFlag(Value,FlagValue) then raise Exception.Create('Invalid definition flag');
          ValueSql:=IntToStr(FlagValue);
          if (Keys[i]='alwaysOnCard') and (FlagValue=1) then
            BackfillSql:='INSERT INTO card_custom_field_values(cardId,customFieldId,value) SELECT id,'+
              QuotedStr(FieldId)+',NULL FROM cards WHERE boardId IN '+BoardIds+
              ' AND '+Scope.StringField('cards','boardId')+
              ' AND NOT EXISTS(SELECT 1 FROM card_custom_field_values WHERE cardId=cards.id AND customFieldId='+
              QuotedStr(FieldId)+'); ';
        end;
        Changes:=Changes+Keys[i]+'='+ValueSql+',';
      end;
      SettingsSql:='';Guards:='';Value:=Doc.Find('settings');
      if Value<>nil then
      begin
        if ((Value is TJSONString) and (Pos('application/json',LowerCase(aRequest.ContentType))=1)) or
          not SettingsInput(Value,Settings) then raise Exception.Create('Invalid definition settings');
        SettingsSql:=ReplaceDefinitionSettings(T.Db,FieldId,Settings,Guards);
      end;
      for i:=0 to Scope.Bindings.Count-1 do Guards:=Guards+Scope.Bindings[i];
      if (Changes<>'') or (SettingsSql<>'') then
      begin
        Sql:='BEGIN IMMEDIATE; '+Guards+Guard(Permission)+'UPDATE custom_fields SET '+Changes+
          'modifiedAt='+QuotedStr(NowIso)+' WHERE id='+QuotedStr(FieldId)+'; '+SettingsSql+BackfillSql+Guards+Guard(Permission)+'COMMIT;';
        if not T.Db.Exec(Sql) then
        begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not update custom field');Exit;end;
      end;
      Reply:=TJSONObject.Create(['_id',FieldId]);
      try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
    except SendError(aResponse,500,'Could not update custom field');end;
  finally Scope.Free;Settings.Free;Doc.Free;end;
end;

procedure ApiDeleteCustomField(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,FieldId,DefinitionRows,ValuesRows,ActivityRows,ActivitySource,Bindings,Permission,Sql,BoardIds,AfterDelete:string;
  Scope:TSelectionScope;Rows:TWLRows;Reply:TJSONObject;i:Integer;
  function Q(const Value:string):string;
  begin Result:=QuotedStr(Value);end;
  function Guard(const Condition:string):string;
  begin Result:='SELECT CASE WHEN '+Condition+' THEN 1 ELSE json(''Custom field deletion guard failed'') END; ';end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,CustomFieldNotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];FieldId:=aRequest.RouteParams['customField'];
  Scope:=nil;
  try
    try
      Scope:=TSelectionScope.Create(T.Db);
      DefinitionRows:=' FROM custom_fields WHERE id='+Q(FieldId);
      Rows:=T.Db.Query('SELECT count(*)'+DefinitionRows+' AND '+Scope.StringField('custom_fields','id')+
        ' AND EXISTS(SELECT 1 FROM custom_field_boards WHERE customFieldId='+Q(FieldId)+
        ' AND boardId='+Q(BoardId)+' AND '+Scope.StringField('custom_field_boards','boardId')+');');
      if (Length(Rows)<>1) or (Length(Rows[0])<>1) then
      begin SendError(aResponse,500,'Could not validate custom field');Exit;end;
      if Rows[0][0]='0' then begin SendJson(aResponse,CustomFieldNotFound,404);Exit;end;
      DefinitionWriteScope(T.Db,UserId,FieldId,BoardId,BoardIds,Permission,AfterDelete);
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin SendError(aResponse,403,'Custom field deletion forbidden');Exit;end;
      ValuesRows:=' FROM card_custom_field_values WHERE customFieldId='+Q(FieldId)+
        ' AND EXISTS(SELECT 1 FROM cards WHERE id=card_custom_field_values.cardId AND boardId IN '+BoardIds+
        ' AND '+Scope.StringField('cards','boardId')+') AND '+Scope.StringField('card_custom_field_values','customFieldId');
      ActivityRows:=' FROM activities WHERE boardId IN '+BoardIds+' AND '+
        'json_type(data_json,''$.customFieldId'')=''text'' AND json_extract(data_json,''$.customFieldId'')='+Q(FieldId)+
        ' AND '+Scope.StringField('activities','boardId');
      Rows:=T.Db.Query('SELECT type FROM sqlite_master WHERE name=''activities'';');
      if Length(Rows)<>1 then raise Exception.Create('Missing activity source');
      if Rows[0][0]='view' then
      begin
        Rows:=T.Db.Query('SELECT table_name FROM _wl_models WHERE name=''activities'';');
        if Length(Rows)<>1 then raise Exception.Create('Ambiguous activity source');
        ActivitySource:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
        ActivityRows:=ActivityRows+' AND EXISTS(SELECT 1 FROM '+ActivitySource+' a WHERE '+
          'json_extract(a._ferretdb_sjson,''$._id'')=activities.id AND '+
          'json_extract(a._ferretdb_sjson,''$.$s.p.customFieldId.t'')=''string'')';
      end
      else if Rows[0][0]<>'table' then raise Exception.Create('Invalid activity source');
      Bindings:='';for i:=0 to Scope.Bindings.Count-1 do Bindings:=Bindings+Scope.Bindings[i];
      Sql:='BEGIN IMMEDIATE; '+Bindings+Guard(Permission)+
        'DELETE'+ValuesRows+'; DELETE'+ActivityRows+'; '+Bindings+Guard(Permission+' AND NOT EXISTS(SELECT 1'+ValuesRows+')')+
        'DELETE'+DefinitionRows+'; '+Bindings+Guard('NOT EXISTS(SELECT 1'+DefinitionRows+
        ') AND NOT EXISTS(SELECT 1'+ValuesRows+') AND NOT EXISTS(SELECT 1'+ActivityRows+') AND '+AfterDelete)+'COMMIT;';
      if not T.Db.Exec(Sql) then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not delete custom field');Exit;end;
      Reply:=TJSONObject.Create(['_id',FieldId]);
      try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
    except SendError(aResponse,500,'Could not delete custom field');end;
  finally Scope.Free;end;
end;

const DropdownNotFound = '{"error":"Dropdown item not found"}';

function OptionNameInput(Request:TRequest;out Name:string;out Present:Boolean):Boolean;
var Doc:TJSONObject;Value:TJSONData;i:Integer;
begin
  Result:=False;Name:='';Present:=False;Doc:=nil;
  try
    try
      if Pos('application/json',LowerCase(Request.ContentType))=1 then Doc:=ExactObject(Request.Content)
      else
      begin
        Doc:=TJSONObject.Create;
        for i:=0 to Request.ContentFields.Count-1 do
        begin
          if Doc.Find(Request.ContentFields.Names[i])<>nil then Exit;
          Doc.Add(Request.ContentFields.Names[i],Request.ContentFields.ValueFromIndex[i]);
        end;
      end;
      Value:=Doc.Find('name');Present:=Value<>nil;
      if Present then
      begin
        if Value.JSONType<>jtString then Exit;
        Name:=Value.AsString;CheckUtf8(Name);
        if (Trim(Name)='') or (Pos(#0,Name)>0) then Exit;
      end;
      Result:=True;
    except Result:=False;end;
  finally Doc.Free;end;
end;

procedure ApiAppendDropdownItems(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,FieldId,Permission,Sql,Guards,Mutation,Name,CheckSql:string;
  Doc,Settings,Reply:TJSONObject;Value,Entry:TJSONData;Items:TJSONArray;
  Policy:TFieldPolicy;Scope:TSelectionScope;Rows:TWLRows;i:Integer;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,CustomFieldNotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];FieldId:=aRequest.RouteParams['customField'];
  Doc:=nil;Settings:=nil;Policy:=nil;Scope:=nil;
  try
    try
      if aRequest.Content<>'' then
        if Pos('application/json',LowerCase(aRequest.ContentType))=1 then Doc:=ExactObject(aRequest.Content)
        else if aRequest.ContentFields.IndexOfName('items')>=0 then
          Doc:=ExactObject('{"items":'+aRequest.ContentFields.Values['items']+'}');
      Settings:=TJSONObject.Create;
      Items:=TJSONArray.Create;Settings.Add('dropdownItems',Items);
      if Doc<>nil then
      begin
        Value:=Doc.Find('items');
        if Value is TJSONArray then
          for i:=0 to Value.Count-1 do
          begin
            Entry:=Value.Items[i];
            if Entry is TJSONString then
            begin
              Name:=Entry.AsString;CheckUtf8(Name);
              if (Trim(Name)='') or (Pos(#0,Name)>0) then raise Exception.Create('Invalid dropdown option name');
              Items.Add(TJSONObject.Create(['_id',NewId,'name',Name]));
            end;
          end;
      end;
    except SendError(aResponse,400,'Invalid dropdown options');Exit;end;
    try
      Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
      Permission:=Policy.ScopeWriteExpression(FieldId);
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin SendError(aResponse,403,'Dropdown mutation forbidden');Exit;end;
      if Items.Count>0 then
      begin
        Mutation:=DropdownScript(T.Db,FieldId,Settings,Guards,True);
        Scope:=TSelectionScope.Create(T.Db);
        CheckSql:='';
        for i:=0 to Items.Count-1 do
        begin
          Entry:=Items.Items[i];
          CheckSql:=CheckSql+' AND (SELECT count(*) FROM custom_field_dropdown_items WHERE customFieldId='+
            QuotedStr(FieldId)+' AND id='+QuotedStr(TJSONObject(Entry).Get('_id',''))+' AND name='+
            QuotedStr(TJSONObject(Entry).Get('name',''))+' AND '+Scope.StringField('custom_field_dropdown_items','id')+')=1';
        end;
        Sql:='BEGIN IMMEDIATE; '+Guards+
          'SELECT CASE WHEN '+Permission+' THEN 1 ELSE json(''Dropdown append forbidden'') END; '+
          'UPDATE custom_fields SET modifiedAt='+QuotedStr(NowIso)+' WHERE id='+QuotedStr(FieldId)+'; '+Mutation+Guards+
          'SELECT CASE WHEN '+Permission+CheckSql+' THEN 1 ELSE json(''Dropdown append failed'') END; COMMIT;';
        if not T.Db.Exec(Sql) then
        begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not append dropdown options');Exit;end;
      end;
      Reply:=TJSONObject.Create(['_id',FieldId]);
      try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
    except SendError(aResponse,500,'Could not append dropdown options');end;
  finally Scope.Free;Policy.Free;Settings.Free;Doc.Free;end;
end;

procedure ApiDropdownItem(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,FieldId,ItemId,Parent,Item,Bindings,Permission,BeforeSql,AfterSql,Sql,Name,Mutation,ReplyId:string;Rename,Present:Boolean;
  Scope:TSelectionScope;Policy:TFieldPolicy;Rows:TWLRows;i:Integer;Reply:TJSONObject;
  function Q(const Text:string):string;
  begin Result:=QuotedStr(Text);end;
  function Guard(const Condition:string):string;
  begin Result:='SELECT CASE WHEN '+Condition+' THEN 1 ELSE json(''Dropdown mutation guard failed'') END; ';end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];FieldId:=aRequest.RouteParams['customField'];ItemId:=aRequest.RouteParams['dropdownItem'];
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,DropdownNotFound) then Exit;
  Scope:=nil;Policy:=nil;Rename:=aRequest.Method='PUT';
  try
    try
      Scope:=TSelectionScope.Create(T.Db);Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
      Parent:='EXISTS(SELECT 1 FROM custom_fields WHERE id='+Q(FieldId)+' AND '+Scope.StringField('custom_fields','id')+') AND '+
        'EXISTS(SELECT 1 FROM custom_field_boards WHERE customFieldId='+Q(FieldId)+' AND boardId='+Q(BoardId)+' AND '+Scope.StringField('custom_field_boards','boardId')+')';
      Item:=' FROM custom_field_dropdown_items WHERE customFieldId='+Q(FieldId)+' AND id='+Q(ItemId);
      Rows:=T.Db.Query('SELECT CASE WHEN '+Parent+' THEN (SELECT count(*)'+Item+' AND '+Scope.StringField('custom_field_dropdown_items','id')+') ELSE 0 END;');
      if Length(Rows)<>1 then begin SendError(aResponse,500,'Could not validate dropdown item');Exit;end;
      if Rows[0][0]='0' then begin SendJson(aResponse,DropdownNotFound,404);Exit;end;
      if Rows[0][0]<>'1' then begin SendError(aResponse,500,'Ambiguous dropdown item');Exit;end;
      Permission:=Policy.ScopeWriteExpression(FieldId);
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then begin SendError(aResponse,403,'Dropdown mutation forbidden');Exit;end;
      if Rename then
      begin
        if not OptionNameInput(aRequest,Name,Present) then begin SendError(aResponse,400,'Invalid dropdown option name');Exit;end;
        if not Present then
        begin
          Reply:=TJSONObject.Create(['_id',ItemId]);
          try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;Exit;
        end;
      end;
      Bindings:='';for i:=0 to Scope.Bindings.Count-1 do Bindings:=Bindings+Scope.Bindings[i];
      BeforeSql:=Bindings+Guard(Permission+' AND '+Parent+' AND (SELECT count(*)'+Item+' AND '+Scope.StringField('custom_field_dropdown_items','id')+')=1');
      Sql:='BEGIN IMMEDIATE; '+BeforeSql;ReplyId:=FieldId;
      if Rename then
      begin
        Mutation:=DropdownRenameScript(T.Db,FieldId,ItemId,Name);ReplyId:=ItemId;
        AfterSql:=Bindings+Guard(Permission+' AND '+Parent+' AND (SELECT count(*)'+Item+' AND name='+Q(Name)+' AND '+Scope.StringField('custom_field_dropdown_items','id')+')=1');
      end
      else
      begin
        AfterSql:=Bindings+Guard(Permission+' AND '+Parent+' AND NOT EXISTS(SELECT 1'+Item+')');
        Rows:=T.Db.Query('SELECT type FROM sqlite_master WHERE name=''custom_fields'';');
        if (Length(Rows)=1) and (Rows[0][0]='table') then
          Sql:=Sql+'UPDATE custom_fields SET dropdownItemsPresent=1 WHERE id='+Q(FieldId)+'; ';
        Mutation:='DELETE'+Item+'; ';
      end;
      Sql:=Sql+'UPDATE custom_fields SET modifiedAt='+Q(NowIso)+' WHERE id='+Q(FieldId)+'; '+Mutation+AfterSql+'COMMIT;';
      if not T.Db.Exec(Sql) then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not change dropdown item');Exit;end;
      Reply:=TJSONObject.Create(['_id',ReplyId]);
      try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
    except SendError(aResponse,500,'Could not change dropdown item');end;
  finally Policy.Free;Scope.Free;end;
end;

// Keep JSON arrays as array text for the SQL relation contract. A JSON number
// or Boolean remains a SQL scalar; form values and JSON strings remain literal.
function CustomValueSql(Request:TRequest;out Value:string):Boolean;
var Doc:TJSONObject;Data:TJSONData;i,Count:Integer;
begin
  Result:=False;Value:='';Doc:=nil;
  try
    try
      if Pos('application/json',LowerCase(Request.ContentType))=1 then
      begin
        Doc:=ExactObject(Request.Content);Data:=Doc.Find('value');
        if Data=nil then Exit;
        if not CustomValueLiteral(Data,Value) then Exit;
      end
      else
      begin
        Count:=0;
        for i:=0 to Request.ContentFields.Count-1 do
          if Request.ContentFields.Names[i]='value' then Inc(Count);
        if Count<>1 then Exit;
        if Pos(#0,Request.ContentFields.Values['value'])>0 then Exit;
        Value:=QuotedStr(Request.ContentFields.Values['value']);
      end;
      Result:=True;
    except Result:=False;end;
  finally Doc.Free;end;
end;

// POST set a card's value for a custom field. Do not delete an existing embedded
// row: its unknown properties and BSON type metadata belong to the source store.
function SaveCardFieldValue(Db:TWLDb;const CardId,FieldId,Value,GuardSql:string):Boolean;
var Scope:string;
begin
  Scope:='cardId='+QuotedStr(CardId)+' AND customFieldId='+QuotedStr(FieldId);
  Result:=Db.Exec('BEGIN IMMEDIATE; '+GuardSql+'UPDATE card_custom_field_values SET value='+Value+
    ' WHERE '+Scope+'; INSERT INTO card_custom_field_values(cardId,customFieldId,value) SELECT '+
    QuotedStr(CardId)+','+QuotedStr(FieldId)+','+Value+' WHERE NOT EXISTS(SELECT 1 FROM card_custom_field_values WHERE '+Scope+'); '+GuardSql+'COMMIT;');
  if not Result then Db.Exec('ROLLBACK;');
end;

procedure ApiCardCustomField(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, CardId, CfId, Value,GuardSql: string;Reply:TJSONObject;Policy:TFieldPolicy;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  CardId := aRequest.RouteParams['cardId'];
  CfId   := aRequest.RouteParams['customField'];
  if not CustomValueSql(aRequest,Value) then
  begin SendError(aResponse,400,'Expected one scalar or string-array value');Exit;end;
  Policy:=nil;
  try
    try
      Policy:=TFieldPolicy.Create(T.Db,UserId,aRequest.RouteParams['boardId'],CardId);
      if not Policy.Allowed(CfId,True) then
      begin SendError(aResponse,403,'Custom-field write forbidden');Exit;end;
      GuardSql:=Policy.Guard(CfId);
    except SendError(aResponse,403,'Custom-field write forbidden');Exit;end;
    if not SaveCardFieldValue(T.Db,CardId,CfId,Value,GuardSql) then
    begin SendError(aResponse,500,'Could not save custom-field value');Exit;end;
    Reply:=TJSONObject.Create(['_id',CardId]);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  finally Policy.Free;end;
end;

procedure ApiLists(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, Title, Id, BoardSql, Stamp, LaneId, LaneSql, Guard: string;Rows:TWLRows;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];BoardSql:=QuotedStr(BoardId);
  if aRequest.Method = 'POST' then
  begin
    Title:=BodyField(aRequest,'title');LaneId:=BodyField(aRequest,'swimlaneId');
    if (Trim(Title)='') or (Pos(#0,Title)>0) or (Pos(#0,LaneId)>0) then
    begin SendError(aResponse,400,'Invalid list title or swimlane');Exit;end;
    Guard:='';
    if LaneId<>'' then
    begin
      LaneSql:=QuotedStr(LaneId);
      Guard:='SELECT CASE WHEN (SELECT count(*) FROM swimlanes WHERE id='+LaneSql+
        ' AND boardId='+BoardSql+')=1 THEN 1 ELSE json(''List swimlane changed'') END; ';
      Rows:=T.Db.Query('SELECT id FROM swimlanes WHERE id='+LaneSql+' AND boardId='+BoardSql+';');
      if Length(Rows)<>1 then begin SendError(aResponse,400,'Swimlane does not belong to this board');Exit;end;
    end else
      LaneSql:='COALESCE((SELECT id FROM swimlanes WHERE boardId='+BoardSql+
        ' ORDER BY archived,sort,id LIMIT 1),'''')';
    Id:=NewId;Stamp:=QuotedStr(NowIso);
    if not T.Db.Exec('BEGIN IMMEDIATE; '+Guard+
      'INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt,modifiedAt) VALUES('+
      QuotedStr(Id)+','+BoardSql+','+LaneSql+','+QuotedStr(Title)+
      ',(SELECT count(*) FROM lists WHERE boardId='+BoardSql+' AND archived=0 AND deletedAt IS NULL),'+Stamp+','+Stamp+'); COMMIT;') then
    begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create list');Exit;end;
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
    Exit;
  end;
  Rows:=T.Db.Query('WITH card_dates AS (SELECT listId,'+
    'max(strftime(''%Y-%m-%dT%H:%M:%fZ'',modifiedAt)) edited,'+
    'max(strftime(''%Y-%m-%dT%H:%M:%fZ'',dateLastActivity)) activity FROM cards WHERE boardId='+BoardSql+
    ' GROUP BY listId) SELECT json_group_array(json(payload)) FROM (SELECT json_object(''_id'',l.id,''title'',l.title,'+
    '''modifiedAt'',strftime(''%Y-%m-%dT%H:%M:%fZ'',l.modifiedAt),'+
    '''cardsModifiedAt'',max(coalesce(d.edited,d.activity),coalesce(d.activity,d.edited))) payload '+
    'FROM lists l LEFT JOIN card_dates d ON d.listId=l.id WHERE l.boardId='+BoardSql+
    ' AND l.archived=0 AND l.deletedAt IS NULL ORDER BY l.sort,l.id);');
  if Length(Rows)=1 then SendJson(aResponse,Rows[0][0])
  else SendError(aResponse,500,'Could not read lists');
end;

procedure ApiList(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"List not found"}';
var T:TWLTenant;UserId,BoardId,ListId:string;Rows:TWLRows;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];ListId:=aRequest.RouteParams['listId'];
  Rows:=T.Db.Query('SELECT json_object(''_id'',id,''boardId'',boardId,''swimlaneId'',swimlaneId,'+
    '''title'',title,''type'',type,''color'',color,''sort'',sort,''width'',width,'+
    '''starred'',json(CASE WHEN starred=1 THEN ''true'' ELSE ''false'' END),''archived'',json(''false''),'+
    '''archivedAt'',archivedAt,''createdAt'',createdAt,''modifiedAt'',modifiedAt,''updatedAt'',updatedAt,'+
    '''wipLimit'',json_object(''value'',wip_value,''enabled'',json(CASE WHEN wip_enabled=1 THEN ''true'' ELSE ''false'' END),'+
    '''soft'',json(CASE WHEN wip_soft=1 THEN ''true'' ELSE ''false'' END))) FROM lists WHERE id='+
    QuotedStr(ListId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL;');
  if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
  SendJson(aResponse,Rows[0][0]);
end;

procedure ApiListEdit(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"List not found"}';
var T:TWLTenant;UserId,BoardId,ListId,Scope,Sets,Permission,Value,Sql,OldTitle,NewTitle,OldColor,NewColor:string;
  Body,Reply,Before,After:TJSONObject;Field,Wip:TJSONData;Rows:TWLRows;Policy:TFieldPolicy;
  Flag,i:Integer;Limit:Int64;OldLimit:Double;NumberFormat:TFormatSettings;Enabled,Soft,OldEnabled,OldSoft,HasWip:Boolean;Wide:UnicodeString;
  procedure SetColumn(const Column,Literal:string);
  begin
    if Sets<>'' then Sets:=Sets+',';
    Sets:=Sets+Column+'='+Literal;
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];ListId:=aRequest.RouteParams['listId'];
  Scope:='id='+QuotedStr(ListId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL';
  Rows:=T.Db.Query('SELECT title,COALESCE(color,''''),CASE WHEN typeof(wip_value)=''real'' THEN printf(''%!.26g'',wip_value) ELSE COALESCE(wip_value,1) END,COALESCE(wip_enabled,0),COALESCE(wip_soft,0) FROM lists WHERE '+Scope+';');
  if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
  OldTitle:=Rows[0][0];NewTitle:=OldTitle;OldColor:=Rows[0][1];NewColor:=OldColor;
  NumberFormat:=DefaultFormatSettings;NumberFormat.DecimalSeparator:='.';NumberFormat.ThousandSeparator:=#0;
  OldLimit:=StrToFloatDef(Rows[0][2],1,NumberFormat);OldEnabled:=Rows[0][3]='1';OldSoft:=Rows[0][4]='1';
  Body:=nil;Policy:=nil;Sets:='';Permission:='1';
  try
    try
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then Body:=ExactObject(aRequest.Content)
      else
      begin
        Body:=TJSONObject.Create;
        for i:=0 to aRequest.ContentFields.Count-1 do
          Body.Add(aRequest.ContentFields.Names[i],aRequest.ContentFields.ValueFromIndex[i]);
      end;
      Field:=Body.Find('title');
      if (Field<>nil) and (Field.JSONType<>jtNull) and (Field.AsString<>'') then
      begin
        Value:=Field.AsString;CheckUtf8(Value);
        if Pos(#0,Value)>0 then raise Exception.Create('Invalid title');
        Wide:=UTF8Decode(Value);
        if Length(Wide)>1000 then
        begin
          i:=1000;if Ord(Wide[i]) in [$D800..$DBFF] then Dec(i);
          Value:=UTF8Encode(Copy(Wide,1,i));
        end;
        NewTitle:=Value;
        SetColumn('title',QuotedStr(NewTitle));
      end;
      Field:=Body.Find('color');
      if (Field<>nil) and (Field.JSONType<>jtNull) and (Field.AsString<>'') then
      begin
        Value:=Field.AsString;
        if (ResolveColor(Value)='') or ((Value[1]='#') and (Length(Value)<>7)) or
          ((Value[1]<>'#') and (NormalizeHex(Value)<>'')) then
        begin SendJson(aResponse,'{"error":"Invalid list color. Use a named palette color or a #rrggbb hex value."}',400);Exit;end;
        NewColor:=Value;
        SetColumn('color',QuotedStr(NewColor));
      end;
      Field:=Body.Find('starred');
      if Field<>nil then
      begin
        if not DefinitionFlag(Field,Flag) then raise Exception.Create('Invalid starred value');
        SetColumn('starred',IntToStr(Flag));
      end;
      Wip:=Body.Find('wipLimit');
      HasWip:=(Wip<>nil) and (Wip.JSONType<>jtNull);
      if HasWip then
      begin
        if not (Wip is TJSONObject) then raise Exception.Create('Invalid WIP value');
        Field:=TJSONObject(Wip).Find('value');Limit:=1;
        if Field<>nil then
          if not TryStrToInt64(Field.AsJSON,Limit) then raise Exception.Create('Invalid WIP limit');
        SetColumn('wip_value',IntToStr(Limit));
        if not DefinitionFlag(TJSONObject(Wip).Find('enabled'),Flag) then raise Exception.Create('Invalid WIP enabled flag');
        Enabled:=Flag=1;
        SetColumn('wip_enabled',IntToStr(Flag));
        if not DefinitionFlag(TJSONObject(Wip).Find('soft'),Flag) then raise Exception.Create('Invalid WIP soft flag');
        Soft:=Flag=1;
        SetColumn('wip_soft',IntToStr(Flag));
        Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
        Permission:=Policy.ScopeAdminExpression;
      end;
    except SendJson(aResponse,'{"error":"Invalid list update"}',400);Exit;end;
    if Sets='' then begin SendJson(aResponse,'{"message":"Error"}',404);Exit;end;
    SetColumn('modifiedAt',QuotedStr(NowIso));
    Rows:=T.Db.Query('SELECT '+Permission+';');
    if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
    begin SendError(aResponse,403,'Board administration required');Exit;end;
    Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+' AND (SELECT count(*) FROM lists WHERE '+
      Scope+')=1 THEN 1 ELSE json(''List edit scope changed'') END; UPDATE lists SET '+Sets+' WHERE '+Scope+
      '; SELECT CASE WHEN '+Permission+' AND (SELECT count(*) FROM lists WHERE '+Scope+
      ')=1 THEN 1 ELSE json(''List edit scope changed'') END; COMMIT;';
    if not T.Db.Exec(Sql) then
    begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not edit list');Exit;end;
    RecordContainerText(T.Db,UserId,BoardId,'list',ListId,'title',OldTitle,NewTitle);
    RecordContainerText(T.Db,UserId,BoardId,'list',ListId,'color',OldColor,NewColor);
    if HasWip and ((OldLimit<>Limit) or (OldEnabled<>Enabled) or (OldSoft<>Soft)) then
    begin
      Before:=TJSONObject.Create(['field','wipLimit','value',
        TJSONObject.Create(['value',OldLimit,'enabled',OldEnabled,'soft',OldSoft])]);
      After:=TJSONObject.Create(['field','wipLimit','value',
        TJSONObject.Create(['value',Limit,'enabled',Enabled,'soft',Soft])]);
      try
        try RecordHistoryRow(T.Db,UserId,BoardId,'list',ListId,'title','edited',Before,After);
        except
          // History never fails the edit it records.
        end;
      finally Before.Free;After.Free;end;
    end;
    Reply:=TJSONObject.Create(['_id',ListId]);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  finally Policy.Free;Body.Free;end;
end;

procedure ApiListArchive(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"List not found"}';
var T:TWLTenant;UserId,BoardId,BoardKey,ListId,Scope,Predicate,Stamp,CardArchivedAt,Sql,CardScope,CardIdQuery:string;
  Archive:Boolean;Target:string;Rows,CardIds:TWLRows;Reply:TJSONObject;ChangedCards:TJSONData;I:Integer;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];BoardKey:=QuotedStr(BoardId);ListId:=aRequest.RouteParams['listId'];
  Archive:=Copy(aRequest.PathInfo,Length(aRequest.PathInfo)-9,10)<>'/unarchive';
  Target:=IntToStr(Ord(Archive));
  Scope:='id='+QuotedStr(ListId)+' AND boardId='+BoardKey+' AND deletedAt IS NULL';
  Predicate:=Scope+' AND archived='+IntToStr(Ord(not Archive));
  Rows:=T.Db.Query('SELECT id FROM lists WHERE '+Predicate+';');
  if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
  Stamp:=QuotedStr(NowIso);CardArchivedAt:='NULL';
  if Archive then CardArchivedAt:=Stamp;
  CardScope:='listId='+QuotedStr(ListId)+' AND boardId='+BoardKey+' AND deletedAt IS NULL AND archived<> '+Target+
    ' AND EXISTS(SELECT 1 FROM lists WHERE '+Predicate+' AND type=''template-list'')';
  CardIdQuery:='SELECT json_group_array(id) FROM (SELECT id FROM cards WHERE '+CardScope+' ORDER BY id)';
  Rows:=T.Db.Query(CardIdQuery+';');
  if Length(Rows)<>1 then begin SendError(aResponse,500,'Could not read archive scope');Exit;end;
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+Predicate+
    ')=1 AND ('+CardIdQuery+')='+QuotedStr(Rows[0][0])+' THEN 1 ELSE json(''List archive scope changed'') END; '+
    'UPDATE cards SET archived='+Target+',archivedAt='+CardArchivedAt+' WHERE '+CardScope+'; '+
    'UPDATE lists SET archived='+Target+',modifiedAt='+Stamp;
  if Archive then Sql:=Sql+',archivedAt='+Stamp;
  Sql:=Sql+' WHERE '+Predicate+'; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+Scope+
    ' AND archived='+Target+')=1 THEN 1 ELSE json(''List archive failed'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not change list archive state');Exit;end;
  ChangedCards:=GetJSON(Rows[0][0]);
  try
    if ChangedCards.Count=0 then RecordArchiveHistory(T.Db,UserId,BoardId,'list',ListId,Archive)
    else
    begin
      SetLength(CardIds,ChangedCards.Count);
      for I:=0 to High(CardIds) do
      begin
        SetLength(CardIds[I],1);
        CardIds[I][0]:=ChangedCards.Items[I].AsString;
      end;
      try
        RecordContainerArchiveBatch(T.Db,UserId,BoardId,'list',ListId,Archive,nil,CardIds);
      except
        // History never fails the operation it records.
      end;
    end;
  finally ChangedCards.Free;end;
  Reply:=TJSONObject.Create(['_id',ListId,'archived',Archive]);
  try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
end;

function CardCreateSql(const BoardId,ListId,Lane,CardId,Author,Title,Descr,Parent,Sort:string;const LinkedId:string='';const TitleExpression:string=''):string;
var Stamp,Board,TitleSql:string;
begin
  Stamp:=QuotedStr(NowIso);Board:=QuotedStr(BoardId);
  TitleSql:=TitleExpression;
  if TitleSql='' then TitleSql:=QuotedStr(Title);
  Result:='INSERT INTO cards(id,boardId,listId,swimlaneId,title,description,userId,parentId,'+
    'dateLastActivity,createdAt,modifiedAt,sort,cardNumber,type,linkedId) SELECT '+QuotedStr(CardId)+','+Board+','+
    QuotedStr(ListId)+','+QuotedStr(Lane)+','+TitleSql+','+QuotedStr(Descr)+','+
    QuotedStr(Author)+','+Parent+','+Stamp+','+Stamp+','+Stamp+','+Sort+
    ',(SELECT max(0,coalesce(max(cardNumber),0))+1 FROM cards WHERE boardId='+Board+'),';
  if LinkedId='' then Result:=Result+'''cardType-card'',NULL; '
  else Result:=Result+'''cardType-linkedCard'','+QuotedStr(LinkedId)+'; ';
  // WeKan's createCard activity, as its cards.after.insert writes one for
  // every new card (models/activities.js): what the board's activities show
  // and what a "when a card is added" rule starts from (wlrules).
  Result:=Result+'INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) '+
    'SELECT '+QuotedStr(NewId)+',''createCard'','+QuotedStr(Author)+',c.boardId,c.id,c.listId,c.swimlaneId,'+Stamp+','+Stamp+
    ',json_object(''cardTitle'',c.title,''listName'',(SELECT l.title FROM lists l WHERE l.id=c.listId),'+
    '''swimlaneName'',(SELECT s.title FROM swimlanes s WHERE s.id=c.swimlaneId)) FROM cards c WHERE c.id='+QuotedStr(CardId)+'; ';
end;

// A refused attempt in a shared store's eventlog, as WeKan's securityLog
// records one (models/lib/eventLogSummary.js): one row per kind of attempt
// that counts them, never a row per attempt.
procedure RecordSecurityEvent(Db:TWLDb;const UserId,Bleed,Source,Category,Severity,Cwe,Action,Detail:string);
const Hints='{"at":"date","firstAt":"date"}';
var Rows:TWLRows;Event:TJSONObject;TableName,Physical,AtSql,Payload,Updated,Sql,Identity,Username:string;
  Stamp:TDateTime;AtMs:Int64;
  function Stored(const Data:string):string;
  begin
    Result:='CASE WHEN wl_storage('+QuotedStr(TableName)+')=''blob'' THEN jsonb('+Data+') ELSE '+Data+' END';
  end;
begin
  Identity:='json_extract(_ferretdb_sjson,''$.stream'')=''security'''+
    ' AND json_extract(_ferretdb_sjson,''$.bleed'')='+QuotedStr(Bleed)+
    ' AND json_extract(_ferretdb_sjson,''$.source'')='+QuotedStr(Source)+
    ' AND json_extract(_ferretdb_sjson,''$.category'')='+QuotedStr(Category)+
    ' AND json_extract(_ferretdb_sjson,''$.action'')='+QuotedStr(Action);
  try
    if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))<>1 then Exit;
    if not EnsureSharedCollection(Db,'eventlog') then Exit;
    Rows:=Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''eventlog'';');
    if Length(Rows)<>1 then Exit;
    TableName:=Rows[0][0];Physical:='"'+StringReplace(TableName,'"','""',[rfReplaceAll])+'"';
    Stamp:=LocalTimeToUniversal(Now);
    AtMs:=DateTimeToUnix(Stamp,True)*1000+MilliSecondOf(Stamp);AtSql:=IntToStr(AtMs);
    // The most recent occurrence's account, by name too, as WeKan's summary
    // row has it (models/lib/eventLogSummary.js).
    Rows:=Db.Query('SELECT COALESCE(username,'''') FROM users WHERE id='+QuotedStr(UserId)+';');
    if Length(Rows)=1 then Username:=Rows[0][0] else Username:='';
    Event:=TJSONObject.Create(['_id',NewId,'stream','security','at',AtMs,'firstAt',AtMs,
      'severity',Severity,'category',Category,'bleed',Bleed,'action',Action,'source',Source,
      'cwe',Cwe,'count',1,'userId',UserId,'username',Username,'detail',Detail]);
    try Payload:=QuotedStr(TypedDocument(Event.AsJSON,'',Hints));finally Event.Free;end;
    Updated:='wl_sjson(json_set(wl_plain(json(_ferretdb_sjson)),''$.at'','+AtSql+
      ',''$.userId'','+QuotedStr(UserId)+',''$.username'','+QuotedStr(Username)+',''$.count'',MIN(9007199254740991,MAX(0,'+
      'COALESCE(json_extract(_ferretdb_sjson,''$.count''),0))+1)),json(_ferretdb_sjson),''{"at":"date"}'')';
    Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM _ferretdb_collections WHERE name=''eventlog'''+
      ' AND table_name='+QuotedStr(TableName)+')=1 THEN 1 ELSE json(''Event log source changed'') END; '+
      'UPDATE '+Physical+' SET _ferretdb_sjson='+Stored(Updated)+' WHERE rowid=(SELECT MIN(rowid) FROM '+Physical+
      ' WHERE '+Identity+'); INSERT INTO '+Physical+'(_ferretdb_sjson) SELECT '+Stored(Payload)+
      ' WHERE NOT EXISTS(SELECT 1 FROM '+Physical+' WHERE '+Identity+'); COMMIT;';
    if not Db.Exec(Sql) then Db.Exec('ROLLBACK;');
  except Db.Exec('ROLLBACK;');end;
end;

procedure RecordAdminFieldAttempt(Db:TWLDb;const UserId,Source,Detail:string);
begin
  try
    RecordSecurityEvent(Db,UserId,'AdminFieldBleed',Source,'authz','high','CWE-863','blocked',Detail);
  except
    // logging must never break the guard
  end;
end;

function AdminFieldForgery(Db:TWLDb;const UserId,BoardId,CardId:string;Fields:TJSONData;const Source:string):Boolean;
var Policy:TFieldPolicy;I:Integer;FieldId:string;Item:TJSONData;
begin
  Result:=False;
  if not (Fields is TJSONArray) then Exit;
  Policy:=TFieldPolicy.Create(Db,UserId,BoardId,CardId);
  try
    for I:=0 to Fields.Count-1 do
    begin
      Item:=Fields.Items[I];
      if not (Item is TJSONObject) then Continue;
      FieldId:=TJSONObject(Item).Get('_id','');
      if (FieldId='') or (Pos(#0,FieldId)>0) then Continue;
      if Length(Db.Query('SELECT 1 FROM custom_field_boards WHERE customFieldId='+QuotedStr(FieldId)+
        ' AND boardId='+QuotedStr(BoardId)+';'))<>1 then Continue;
      try
        if not Policy.Allowed(FieldId,True) then Result:=True;
      except
        Result:=True;
      end;
    end;
  finally Policy.Free;end;
  if Result then RecordAdminFieldAttempt(Db,UserId,Source,'A custom field the user may not write was named.');
end;

procedure RecordSecurityDenial(Db:TWLDb;const UserId,Bleed,Source,Category,Severity,Cwe,Detail:string);
begin
  RecordSecurityEvent(Db,UserId,Bleed,Source,Category,Severity,Cwe,'blocked',Detail);
end;

procedure RecordParentDenial(Db:TWLDb;const UserId:string);
begin
  RecordSecurityDenial(Db,UserId,'ParentBleed','parentId','authz','high','CWE-862',
    'A card on a board the user cannot see was named as a parent.');
end;

procedure ApiBulkCards(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,ListId,Lane,DefaultLane,Parent,ParentSql,ParentGuard,CardId,Relations,Sql,Guard,WritePermission,LaneGuard:string;
  Body,Entry,Item:TJSONObject;Input:TJSONData;Items,Reply:TJSONArray;Rows:TWLRows;I:Integer;
  function Permission(const Board:string;WriteAccess:Boolean):string;
  var Policy:TFieldPolicy;
  begin
    Policy:=TFieldPolicy.Create(T.Db,UserId,Board,'');
    try Result:=Policy.ScopeBoardExpression(WriteAccess);finally Policy.Free;end;
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];ListId:=aRequest.RouteParams['listId'];
  if not ApiAuthBoard(T,aResponse,UserId,BoardId,True) then Exit;
  Guard:='id='+QuotedStr(ListId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL';
  if Length(T.Db.Query('SELECT id FROM lists WHERE '+Guard+';'))<>1 then
  begin SendError(aResponse,400,'Invalid card list');Exit;end;
  WritePermission:=Permission(BoardId,True);
  Body:=nil;Reply:=TJSONArray.Create;
  try
    try Body:=ExactObject(aRequest.Content);
    except SendError(aResponse,400,'Expected a valid JSON object');Exit;end;
    Input:=Body.Find('cards');
    if not (Input is TJSONArray) or (Input.Count=0) or (Input.Count>500) then
    begin SendError(aResponse,400,'cards must contain between 1 and 500 entries');Exit;end;
    Items:=TJSONArray(Input);DefaultLane:=Body.Get('swimlaneId','');
    for I:=0 to Items.Count-1 do
    begin
      Item:=TJSONObject.Create(['index',I]);Reply.Add(Item);
      if not (Items.Items[I] is TJSONObject) then
      begin Item.Add('error','Invalid card');Continue;end;
      Entry:=Items.Objects[I];Lane:=Entry.Get('swimlaneId',DefaultLane);
      if Lane='' then Lane:=DefaultLane;
      if not ApiChildrenBelong(T.Db,BoardId,Lane,ListId,'','','','','') or
        ((Lane<>'') and (Length(T.Db.Query('SELECT id FROM lists WHERE '+Guard+
          ' AND (swimlaneId='''' OR swimlaneId='+QuotedStr(Lane)+');'))<>1)) then
      begin Item.Add('error','Invalid card placement');Continue;end;
      LaneGuard:='';
      if Lane<>'' then LaneGuard:=' AND EXISTS(SELECT 1 FROM swimlanes WHERE id='+QuotedStr(Lane)+
        ' AND boardId='+QuotedStr(BoardId)+' AND archived=0)';
      Parent:=Entry.Get('parentId','');ParentSql:='NULL';ParentGuard:='';
      if Parent<>'' then
      begin
        Rows:=T.Db.Query('SELECT boardId FROM cards WHERE id='+QuotedStr(Parent)+' AND deletedAt IS NULL AND archived=0;');
        if Length(Rows)<>1 then begin Item.Add('error','Forbidden');Continue;end;
        if not BoardCanRead(T.Db,UserId,Rows[0][0]) then
        begin RecordParentDenial(T.Db,UserId);Item.Add('error','Forbidden');Continue;end;
        ParentSql:=QuotedStr(Parent);
        ParentGuard:=' AND EXISTS(SELECT 1 FROM cards WHERE id='+ParentSql+
          ' AND boardId='+QuotedStr(Rows[0][0])+' AND archived=0 AND deletedAt IS NULL) AND '+Permission(Rows[0][0],False);
      end;
      CardId:=NewId;
      if not CardRelationSql(T,nil,nil,BoardId,CardId,Relations,True,Entry) then
      begin Item.Add('error','Invalid card assignments');Continue;end;
      try
        Sql:=CardCreateSql(BoardId,ListId,Lane,CardId,UserId,Entry.Get('title',''),Entry.Get('description',''),
          ParentSql,'(SELECT count(*) FROM cards WHERE boardId='+QuotedStr(BoardId)+' AND listId='+QuotedStr(ListId)+
          ' AND archived=0 AND deletedAt IS NULL)')+Relations+InitializeCardFields(T.Db,BoardId,CardId);
        if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN '+WritePermission+' AND EXISTS(SELECT 1 FROM lists WHERE '+Guard+')'+
          LaneGuard+ParentGuard+' THEN 1 ELSE json(''Card placement changed'') END; '+Sql+'COMMIT;') then
          raise Exception.Create('Bulk card creation failed');
        Item.Add('_id',CardId);
      except
        T.Db.Exec('ROLLBACK;');Item.Add('error','Could not create card');
      end;
    end;
    SendJson(aResponse,Reply.AsJSON);
  finally Body.Free;Reply.Free;end;
end;

procedure CreateLinkedRestCard(Db:TWLDb;Response:TResponse;const Actor,BoardId,ListId,Lane,LinkedId:string);
var Rows:TWLRows;Source,Title,Id,Board,ListKey,LaneKey,Scope,Placement,Permission,Stamp,Sql,Bindings:string;
  Policy:TFieldPolicy;Selector:TSelectionScope;I:Integer;
  function WritePermission(const BoardKey:string):string;
  begin
    Policy:=TFieldPolicy.Create(Db,Actor,BoardKey,'');
    try Result:=Policy.ScopeBoardExpression(True);finally Policy.Free;end;
  end;
begin
  if (Lane='') or (Pos(#0,LinkedId)>0) then
  begin SendError(Response,400,'Invalid linked card placement');Exit;end;
  Board:=QuotedStr(BoardId);ListKey:=QuotedStr(ListId);LaneKey:=QuotedStr(Lane);
  Selector:=TSelectionScope.Create(Db);
  try
    Scope:='id='+QuotedStr(LinkedId)+' AND '+Selector.StringField('cards','id')+
      ' AND '+Selector.StringField('cards','boardId');
    Placement:='EXISTS(SELECT 1 FROM lists WHERE id='+ListKey+' AND boardId='+Board+
      ' AND archived=0 AND deletedAt IS NULL AND (COALESCE(swimlaneId,'''')='''' OR swimlaneId='+LaneKey+') AND '+
      Selector.StringField('lists','id')+' AND '+Selector.StringField('lists','boardId')+')'+
      ' AND EXISTS(SELECT 1 FROM swimlanes WHERE id='+LaneKey+' AND boardId='+Board+' AND archived=0 AND '+
      Selector.StringField('swimlanes','id')+' AND '+Selector.StringField('swimlanes','boardId')+')';
    Bindings:='';
    for I:=0 to Selector.Bindings.Count-1 do Bindings:=Bindings+Selector.Bindings[I];
  finally Selector.Free;end;
  Rows:=Db.Query('SELECT boardId,title FROM cards WHERE '+Scope+';');
  if Length(Rows)<>1 then begin SendJson(Response,'{"error":"Card not found"}',404);Exit;end;
  Source:=Rows[0][0];Title:=Rows[0][1];
  if not BoardCanWrite(Db,Actor,Source) then
  begin SendError(Response,403,'Source board write access required');Exit;end;
  Scope:=Scope+' AND boardId='+QuotedStr(Source)+' AND archived=0 AND deletedAt IS NULL AND '+
    'COALESCE(linkedId,'''')='''' AND type NOT IN (''template-card'',''cardType-linkedCard'',''cardType-linkedBoard'')';
  Rows:=Db.Query('SELECT 1 WHERE '+Placement+' AND EXISTS(SELECT 1 FROM cards WHERE '+Scope+');');
  if Length(Rows)<>1 then begin SendError(Response,400,'Invalid linked card');Exit;end;
  Permission:=WritePermission(Source)+' AND '+WritePermission(BoardId);
  Id:=NewId;Stamp:=QuotedStr(NowIso);
  Sql:='BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+Permission+' AND '+Placement+
    ' AND EXISTS(SELECT 1 FROM cards WHERE '+Scope+' AND COALESCE(title,'''')='+QuotedStr(Title)+
    ') THEN 1 ELSE json(''Linked card scope changed'') END; '+
    CardCreateSql(BoardId,ListId,Lane,Id,Actor,Title,'','NULL',
      '(SELECT count(*) FROM cards WHERE listId='+ListKey+' AND boardId='+Board+
      ' AND archived=0 AND deletedAt IS NULL)',LinkedId)+InitializeSharedAssignments(Db,BoardId,Id,True,True)+'COMMIT;';
  if not Db.Exec(Sql) then
  begin Db.Exec('ROLLBACK;');SendError(Response,500,'Could not create linked card');Exit;end;
  SendJson(Response,'{"_id":"'+StringToJSONString(Id)+'"}');
end;

procedure ApiCopyCard(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;Actor,BoardId,ListId,CardId,DestBoard,DestList,DestLane,Raw,NewCard:string;
  Position:Int64;Body:TJSONObject;Value:TJSONData;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,Actor,'{"error":"Card not found"}') then Exit;
  BoardId:=aRequest.RouteParams['boardId'];ListId:=aRequest.RouteParams['listId'];CardId:=aRequest.RouteParams['cardId'];
  DestBoard:=BodyField(aRequest,'toBoardId');if DestBoard='' then DestBoard:=BoardId;
  DestList:=BodyField(aRequest,'toListId');if DestList='' then DestList:=ListId;
  DestLane:=BodyField(aRequest,'toSwimlaneId');
  if (DestLane='') or (Pos(#0,DestBoard+DestList+DestLane)>0) then
  begin SendError(aResponse,400,'Invalid card copy destination');Exit;end;
  if not ApiAuthBoard(T,aResponse,Actor,DestBoard,True) then Exit;
  if not ApiChildrenBelong(T.Db,DestBoard,DestLane,DestList,'','','','','') then
  begin SendError(aResponse,400,'Invalid card copy destination');Exit;end;
  Raw:=aRequest.ContentFields.Values['position'];Position:=-1;
  if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
  begin
    Body:=ExactObject(aRequest.Content);
    try
      Value:=Body.Find('position');
      if (Value<>nil) and (Value.JSONType in [jtNumber,jtString]) then Raw:=Value.AsString;
    finally Body.Free;end;
  end;
  if TryStrToInt64(Raw,Position) then
  begin if Position<0 then Position:=0;end else Position:=-1;
  try
    if not CopyRestCard(T,Actor,BoardId,ListId,CardId,DestBoard,DestList,DestLane,Position,NewCard) then
      raise Exception.Create('Card copy failed');
  except SendError(aResponse,500,'Could not copy card');Exit;end;
  SendJson(aResponse,'{"_id":"'+StringToJSONString(NewCard)+'"}');
end;

procedure ApiCards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId,BoardId,ListId,Id,Author,Title,Descr,Swimlane,Relations,InitialFields,LinkedId,
  ParentId,ParentSql,ParentScope,ParentGuard:string;Body:TJSONObject;Field:TJSONData;Rows:TWLRows;Policy:TFieldPolicy;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  if aRequest.Method <> 'POST' then begin SendError(aResponse, 405, 'Use POST'); Exit; end;
  BoardId  := aRequest.RouteParams['boardId'];
  ListId   := aRequest.RouteParams['listId'];
  LinkedId:=BodyField(aRequest,'linkedId');
  if LinkedId<>'' then
  begin
    CreateLinkedRestCard(T.Db,aResponse,UserId,BoardId,ListId,BodyField(aRequest,'swimlaneId'),LinkedId);
    Exit;
  end;
  ParentId:='';ParentGuard:='';
  if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
  begin
    Body:=nil;
    try
      try Body:=ExactObject(aRequest.Content);
      except SendError(aResponse,400,'Invalid card creation');Exit;end;
      Field:=Body.Find('parentId');
      if (Field<>nil) and (Field.JSONType<>jtNull) then
      begin
        if not (Field is TJSONString) then
        begin SendJson(aResponse,'{"error":"Invalid parentId"}',400);Exit;end;
        ParentId:=Field.AsString;
      end;
    finally Body.Free;end;
  end
  else ParentId:=aRequest.ContentFields.Values['parentId'];
  if Pos(#0,ParentId)>0 then
  begin SendJson(aResponse,'{"error":"Invalid parentId"}',400);Exit;end;
  ParentSql:=QuotedStr(ParentId);
  if ParentId<>'' then
  begin
    ParentScope:='id='+ParentSql+' AND deletedAt IS NULL';
    Rows:=T.Db.Query('SELECT boardId FROM cards WHERE '+ParentScope+';');
    if Length(Rows)<>1 then
    begin SendJson(aResponse,'{"error":"Card not found"}',404);Exit;end;
    if not BoardCanRead(T.Db,UserId,Rows[0][0]) then
    begin RecordParentDenial(T.Db,UserId);SendError(aResponse,403,'Board access forbidden');Exit;end;
    Policy:=TFieldPolicy.Create(T.Db,UserId,Rows[0][0],'');
    try
      ParentGuard:='SELECT CASE WHEN EXISTS(SELECT 1 FROM cards WHERE '+ParentScope+' AND boardId='+
        QuotedStr(Rows[0][0])+') AND '+Policy.ScopeBoardExpression(False)+
        ' THEN 1 ELSE json(''Card parent scope changed'') END; ';
    finally Policy.Free;end;
  end;
  Author   := BodyField(aRequest, 'authorId'); if Author = '' then Author := UserId;
  if not ValidAuthor(T.Db,BoardId,UserId,Author) then
  begin SendError(aResponse,403,'Invalid author attribution'); Exit; end;
  Title    := BodyField(aRequest, 'title');
  Descr    := BodyField(aRequest, 'description');
  Swimlane := BodyField(aRequest, 'swimlaneId');
  if not ApiChildrenBelong(T.Db,BoardId,Swimlane,ListId,'','','','','') then
  begin SendError(aResponse,400,'Invalid card parent'); Exit; end;
  if (Swimlane<>'') and (Length(T.Db.Query('SELECT id FROM lists WHERE id='+QuotedStr(ListId)+
    ' AND (swimlaneId='''' OR swimlaneId='+QuotedStr(Swimlane)+');'))=0) then
  begin SendError(aResponse,400,'List is in another swimlane'); Exit; end;
  Id := NewId;
  if not CardRelationSql(T,aRequest,aResponse,BoardId,Id,Relations,True) then Exit;
  try InitialFields:=InitializeCardFields(T.Db,BoardId,Id);
  except SendError(aResponse,500,'Could not initialize custom fields');Exit;end;
  if not T.Db.Exec('BEGIN IMMEDIATE; '+ParentGuard+CardCreateSql(BoardId,ListId,Swimlane,Id,Author,Title,Descr,ParentSql,'0')+
    Relations+InitialFields+' COMMIT;') then
  begin T.Db.Exec('ROLLBACK;'); SendError(aResponse,500,'Could not create card'); Exit; end;
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
end;

function SubtaskParentSql(const ParentId,ColumnPrefix:string):string;
var Parent,Extra,ArrayValue:string;
begin
  Parent:=QuotedStr(ParentId);
  Extra:=ColumnPrefix+'extra_json';
  ArrayValue:='CASE WHEN json_valid('+Extra+') THEN CASE WHEN json_type('+Extra+',''$.parentIds'')=''array'' '+
    'THEN json_extract('+Extra+',''$.parentIds'') ELSE ''[]'' END ELSE ''[]'' END';
  Result:='('+ColumnPrefix+'parentId='+Parent+' OR EXISTS(SELECT 1 FROM json_each('+ArrayValue+
    ') parentLink WHERE parentLink.type=''text'' AND parentLink.value='+Parent+'))';
end;

function CardCompletionOf(Db:TWLDb;const Scope:string):Boolean;
var Rows:TWLRows;
begin
  Rows:=Db.Query('SELECT COALESCE(dueComplete,0) FROM cards WHERE '+Scope+';');
  Result:=(Length(Rows)=1) and (Rows[0][0]='1');
end;

function SetViewSubtaskDone(const T:TWLTenant;const UserId,ParentId,SubtaskId:string;Done:Boolean;out Error:string):Integer;
var Rows:TWLRows; ParentScope,SubtaskScope,TargetScope,ParentBoard,SubtaskBoard,TargetBoard,TargetId,Guard,Value:string; Policy:TFieldPolicy;
  OldDone:Boolean;
begin
  Error:='not-found';
  if (ParentId='') or (SubtaskId='') or (Pos(#0,ParentId+SubtaskId)>0) then Exit(404);
  ParentScope:='id='+QuotedStr(ParentId)+' AND archived=0 AND deletedAt IS NULL';
  Rows:=T.Db.Query('SELECT boardId FROM cards WHERE '+ParentScope+';');
  if Length(Rows)<>1 then Exit(404);
  ParentBoard:=Rows[0][0];
  if not BoardCanRead(T.Db,UserId,ParentBoard) and
    not (AssignedOnlyMember(T.Db,UserId,ParentBoard) and CardAssignedTo(T.Db,UserId,ParentBoard,ParentId)) then Exit(404);
  SubtaskScope:='id='+QuotedStr(SubtaskId)+' AND '+SubtaskParentSql(ParentId,'')+
    ' AND archived=0 AND deletedAt IS NULL';
  Rows:=T.Db.Query('SELECT boardId,COALESCE(type,''cardType-card''),COALESCE(linkedId,'''') FROM cards WHERE '+SubtaskScope+';');
  if Length(Rows)<>1 then Exit(404);
  SubtaskBoard:=Rows[0][0];
  if not BoardCanRead(T.Db,UserId,SubtaskBoard) and
    not (AssignedOnlyMember(T.Db,UserId,SubtaskBoard) and CardAssignedTo(T.Db,UserId,SubtaskBoard,SubtaskId)) then Exit(404);
  if Rows[0][1]='cardType-linkedCard' then
  begin
    TargetId:=Rows[0][2];
    if TargetId='' then Exit(404);
    SubtaskScope:=SubtaskScope+' AND type=''cardType-linkedCard'' AND linkedId='+QuotedStr(TargetId);
  end
  else if Rows[0][1]='cardType-card' then
  begin
    TargetId:=SubtaskId;
    SubtaskScope:=SubtaskScope+' AND COALESCE(type,''cardType-card'')=''cardType-card''';
  end
  else Exit(404);
  SubtaskScope:=SubtaskScope+' AND boardId='+QuotedStr(SubtaskBoard);
  TargetScope:='id='+QuotedStr(TargetId)+' AND archived=0 AND deletedAt IS NULL AND COALESCE(type,''cardType-card'')=''cardType-card''';
  Rows:=T.Db.Query('SELECT boardId FROM cards WHERE '+TargetScope+';');
  if Length(Rows)<>1 then Exit(404);
  TargetBoard:=Rows[0][0];
  if not BoardCanWrite(T.Db,UserId,TargetBoard) then begin Error:='not-authorized';Exit(403);end;
  Policy:=TFieldPolicy.Create(T.Db,UserId,TargetBoard,'');
  try Guard:=Policy.ScopeBoardExpression(True);finally Policy.Free;end;
  TargetScope:=TargetScope+' AND boardId='+QuotedStr(TargetBoard);
  OldDone:=CardCompletionOf(T.Db,TargetScope);
  Value:=IntToStr(Ord(Done));
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN '+Guard+' AND EXISTS(SELECT 1 FROM cards WHERE '+ParentScope+
    ' AND boardId='+QuotedStr(ParentBoard)+') AND EXISTS(SELECT 1 FROM cards WHERE '+SubtaskScope+
    ') AND EXISTS(SELECT 1 FROM cards WHERE '+TargetScope+') THEN 1 ELSE json(''Subtask scope changed'') END; UPDATE cards SET dueComplete='+Value+
    ',modifiedAt='+QuotedStr(NowIso)+' WHERE '+TargetScope+' AND COALESCE(dueComplete,0)<>'+Value+'; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not update subtask';Exit(500);end;
  RecordCardCompletionHistory(T.Db,UserId,TargetBoard,TargetId,OldDone,Done);
  Error:='';Result:=200;
end;

function CreateViewSubtask(const T:TWLTenant;const UserId,BoardId,ParentId,Title:string;InheritLabels:Boolean;out Error:string):Integer;
var Rows:TWLRows; Target,ListId,Lane,Id,ParentScope,Landing,Guard,Sort,Sql,Fields,Labels:string; Policy:TFieldPolicy;
begin
  Error:='Invalid subtask';
  if (Trim(Title)='') or (Pos(#0,BoardId+ParentId+Title)>0) then Exit(400);
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  if not BoardAllows(T.Db,BoardId,'allowsSubtasks') then begin Error:='Subtasks disabled';Exit(403);end;
  ParentScope:='c.id='+QuotedStr(ParentId)+' AND c.boardId='+QuotedStr(BoardId)+' AND c.archived=0 AND c.deletedAt IS NULL';
  Rows:=T.Db.Query('SELECT c.listId,c.swimlaneId,COALESCE(NULLIF(b.subtasksDefaultBoardId,''''),b.id),'+
    'COALESCE(b.subtasksDefaultListId,''''),CASE WHEN json_valid(b.settings_json) THEN '+
    'COALESCE(json_extract(b.settings_json,''$.subtasksDefaultSwimlaneId''),'''') ELSE '''' END '+
    'FROM cards c JOIN boards b ON b.id=c.boardId WHERE '+ParentScope+';');
  if Length(Rows)<>1 then begin Error:='Card not found';Exit(404);end;
  Target:=Rows[0][2];ListId:=Rows[0][3];Lane:=Rows[0][4];
  if not BoardCanWrite(T.Db,UserId,Target) then begin Error:='Board access forbidden';Exit(403);end;
  if (ListId='') and (Target=BoardId) then
  begin
    ListId:=Rows[0][0];
    if Lane='' then Lane:=Rows[0][1];
  end;
  Landing:='l.boardId='+QuotedStr(Target)+' AND l.archived=0 AND l.deletedAt IS NULL AND sw.archived=0 '+
    'AND (l.swimlaneId='''' OR l.swimlaneId=sw.id)';
  if ListId<>'' then Landing:=Landing+' AND l.id='+QuotedStr(ListId);
  if Lane<>'' then Landing:=Landing+' AND sw.id='+QuotedStr(Lane);
  Rows:=T.Db.Query('SELECT l.id,sw.id FROM lists l JOIN swimlanes sw ON sw.boardId=l.boardId WHERE '+
    Landing+' ORDER BY l.sort,l.id,sw.sort,sw.id LIMIT 1;');
  if Length(Rows)<>1 then begin Error:='Invalid subtask destination';Exit(400);end;
  ListId:=Rows[0][0];Lane:=Rows[0][1];Id:=NewId;
  Guard:='EXISTS(SELECT 1 FROM cards c WHERE '+ParentScope+') AND EXISTS(SELECT 1 FROM lists l '+
    'JOIN swimlanes sw ON sw.boardId=l.boardId WHERE '+Landing+' AND l.id='+QuotedStr(ListId)+' AND sw.id='+QuotedStr(Lane)+')';
  Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
  try Guard:=Guard+' AND '+Policy.ScopeBoardExpression(True);finally Policy.Free;end;
  if Target<>BoardId then
  begin
    Policy:=TFieldPolicy.Create(T.Db,UserId,Target,'');
    try Guard:=Guard+' AND '+Policy.ScopeBoardExpression(True);finally Policy.Free;end;
  end;
  Sort:='(SELECT coalesce(max(sort),-1)+1 FROM cards WHERE boardId='+QuotedStr(Target)+' AND listId='+QuotedStr(ListId)+
    ' AND swimlaneId='+QuotedStr(Lane)+' AND deletedAt IS NULL)';
  try Fields:=InitializeCardFields(T.Db,Target,Id);
  except Error:='Could not initialize custom fields';Exit(500);end;
  Labels:='';
  if InheritLabels then
    Labels:='INSERT INTO card_labels(cardId,labelId) SELECT '+QuotedStr(Id)+',labelId FROM card_labels WHERE cardId='+
      QuotedStr(ParentId)+'; ';
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Guard+' THEN 1 ELSE json(''Subtask scope changed'') END; '+
    CardCreateSql(Target,ListId,Lane,Id,UserId,Trim(Title),'',QuotedStr(ParentId),Sort)+Fields+Labels+' COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not create subtask';Exit(500);end;
  Error:='';Result:=200;
end;

function CreateViewCard(const T:TWLTenant;const UserId,BoardId,ListId,Swimlane,Title,Position:string;
  out CardId,Error:string;const DueAt:string):Integer;
begin
  Result:=CreateViewCards(T,UserId,BoardId,ListId,Swimlane,Title,Position,False,False,CardId,Error,DueAt);
end;

function CreateViewCards(const T:TWLTenant;const UserId,BoardId,ListId,Swimlane,Title,Position:string;
  Separate,BracketLabels:Boolean;out CardId,Error:string;const DueAt:string):Integer;
var Lane,Sort,Sql,Id,TitleSql,LabelSql,Name,Rest,Raw,Permission,ColorSql,Color:string;
  Titles:TStringList; i,Index,CloseAt:Integer;
begin
  CardId:='';Error:='';
  if (BoardId='') or (ListId='') or (Trim(Title)='') or (Pos(#0,BoardId+ListId+Swimlane+Title)>0) then
  begin Error:='Invalid card';Exit(400);end;
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  Lane:=Swimlane;
  if not ApiChildrenBelong(T.Db,BoardId,Lane,ListId,'','','','','') then
  begin Error:='Invalid card parent';Exit(400);end;
  if (Lane<>'') and (Length(T.Db.Query('SELECT id FROM lists WHERE id='+QuotedStr(ListId)+
    ' AND (swimlaneId='''' OR swimlaneId='+QuotedStr(Lane)+');'))=0) then
  begin Error:='List is in another swimlane';Exit(400);end;
  // First or last among the cards of this list in this swimlane.
  if Position='top' then
    Sort:='(SELECT coalesce(min(sort),1)-1 FROM cards WHERE boardId='+QuotedStr(BoardId)+' AND listId='+
      QuotedStr(ListId)+' AND swimlaneId='+QuotedStr(Lane)+' AND deletedAt IS NULL)'
  else
    Sort:='(SELECT coalesce(max(sort),-1)+1 FROM cards WHERE boardId='+QuotedStr(BoardId)+' AND listId='+
      QuotedStr(ListId)+' AND swimlaneId='+QuotedStr(Lane)+' AND deletedAt IS NULL)';
  Titles:=TStringList.Create;
  try
    if Separate then
    begin
      Titles.Text:=StringReplace(StringReplace(Title,#13#10,#10,[rfReplaceAll]),#13,#10,[rfReplaceAll]);
      for i:=Titles.Count-1 downto 0 do
        if Trim(Titles[i])='' then Titles.Delete(i) else Titles[i]:=Trim(Titles[i]);
    end
    else Titles.Add(Title);
    if Titles.Count=0 then begin Error:='Invalid card';Exit(400);end;
    Permission:='';
    if BracketLabels and (BoardLabelPermission(T.Db,UserId,BoardId,Permission,Error)<>200) then
    begin Permission:='';Error:='';end;
    if Permission<>'' then
    begin
      ColorSql:='CASE';
      for Color in SplitString(LabelColors,'|') do
        if (Color<>'') and (Color<>'white') then
          ColorSql:=ColorSql+' WHEN NOT EXISTS(SELECT 1 FROM board_labels WHERE boardId='+QuotedStr(BoardId)+
            ' AND color='+QuotedStr(Color)+') THEN '+QuotedStr(Color);
      ColorSql:=ColorSql+' ELSE ''green'' END';
    end;
    Sql:='BEGIN IMMEDIATE; ';
    try
      for i:=0 to Titles.Count-1 do
      begin
        Index:=i;
        if Position='top' then Index:=Titles.Count-1-i;
        Id:=NewId;
        Raw:=Titles[Index];TitleSql:='';LabelSql:='';
        if BracketLabels and (Copy(Trim(Raw),1,1)='[') then
        begin
          Rest:=Trim(Raw); CloseAt:=Pos(']',Rest);
          if (CloseAt>2) and (CloseAt<Length(Rest)) and (Rest[CloseAt+1] in [#9,#10,#13,' ']) then
          begin
            Name:=Trim(Copy(Rest,2,CloseAt-2));
            Rest:=Trim(Copy(Rest,CloseAt+1,MaxInt));
            if (Name<>'') and (Rest<>'') and (Pos('[',Name)=0) then
            begin
              LabelSql:='SELECT id FROM board_labels WHERE boardId='+QuotedStr(BoardId)+
                ' AND '+LabelFoldMatch('board_labels.name',Name)+' ORDER BY id LIMIT 1';
              if (Permission<>'') and (Length(Name)<=200) then
                Sql:=Sql+'INSERT INTO board_labels(boardId,id,name,color) SELECT '+QuotedStr(BoardId)+
                  ',lower(hex(randomblob(3))),'+QuotedStr(Name)+','+ColorSql+' WHERE '+Permission+
                  ' AND NOT EXISTS('+LabelSql+'); ';
              TitleSql:='CASE WHEN EXISTS('+LabelSql+') THEN '+QuotedStr(Rest)+' ELSE '+QuotedStr(Raw)+' END';
            end;
          end;
        end;
        Sql:=Sql+CardCreateSql(BoardId,ListId,Lane,Id,UserId,Raw,'',QuotedStr(''),Sort,'',TitleSql)+
          InitializeCardFields(T.Db,BoardId,Id);
        if DueAt<>'' then Sql:=Sql+'UPDATE cards SET dueAt='+QuotedStr(DueAt)+' WHERE id='+QuotedStr(Id)+'; ';
        if LabelSql<>'' then
          Sql:=Sql+'INSERT INTO card_labels(cardId,labelId) SELECT '+QuotedStr(Id)+',id FROM ('+LabelSql+'); ';
        if Index=0 then CardId:=Id;
      end;
    except CardId:='';Error:='Could not initialize custom fields';Exit(500);end;
    if not T.Db.Exec(Sql+' COMMIT;') then
    begin T.Db.Exec('ROLLBACK;');CardId:='';Error:='Could not create card';Exit(500);end;
  finally
    Titles.Free;
  end;
  Result:=200;
end;

// WeKan's after.update activities of a card's text: a-changedTitle or
// a-changedDescription with the old and the new value, when it changes -
// what the card's activities show and what the board's rules read (wlrules).
// The SQL goes before the update, in its transaction.
function CardTextActivitySql(const UserId,Scope,Column,Value:string):string;
var Kind,Title:string;
begin
  Result:='';
  if Column='title' then begin Kind:='a-changedTitle';Title:=QuotedStr(Value);end
  else if Column='description' then begin Kind:='a-changedDescription';Title:='title';end
  else Exit;
  Result:='INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) SELECT '+
    QuotedStr(NewId)+','+QuotedStr(Kind)+','+QuotedStr(UserId)+',boardId,id,listId,swimlaneId,'+QuotedStr(NowIso)+','+QuotedStr(NowIso)+
    ',json_object(''cardTitle'','+Title+',''oldValue'',COALESCE('+Column+',''''),''value'','+QuotedStr(Value)+
    ') FROM cards WHERE '+Scope+' AND COALESCE('+Column+','''')<>'+QuotedStr(Value)+'; ';
end;

// A card's title, description or color now, as text ('' when it has none).
function CardTextOf(Db:TWLDb;const CardId,Column:string):string;
var R:TWLRows;
begin
  Result:='';
  if (Column<>'title') and (Column<>'description') and (Column<>'color') then Exit;
  R:=Db.Query('SELECT COALESCE('+Column+','''') FROM cards WHERE id='+QuotedStr(CardId)+';');
  if Length(R)=1 then Result:=R[0][0];
end;

// WeKan's History of a card's title, description or color (changeHistoryGroups.js):
// one row in the field's group, 'added' from empty, 'removed'
// to empty, else 'edited'; nothing when the value did not change. In a
// shared store, as every History row (wlchhist).
procedure RecordCardTextHistory(Db:TWLDb;const UserId,BoardId,CardId,Column,Old,New:string);
var Before,After:TJSONObject;Kind,Group:string;
begin
  if (Old=New) or ((Column<>'title') and (Column<>'description') and (Column<>'color')) then Exit;
  Group:=Column;
  if Column='color' then Group:='title';
  if Old='' then Kind:='added' else if New='' then Kind:='removed' else Kind:='edited';
  Before:=TJSONObject.Create(['field',Column,'value',Old]);
  After:=TJSONObject.Create(['field',Column,'value',New]);
  try
    try
      RecordHistoryRow(Db,UserId,BoardId,'card',CardId,Group,Kind,Before,After);
    except
      // History never fails the edit it records.
    end;
  finally
    Before.Free;After.Free;
  end;
end;

function RenameViewCard(const T:TWLTenant;const UserId,BoardId,CardId,Title:string;out Error:string):Integer;
var Scope,Stamp,Title_,Old:string;
begin
  Error:='';
  // A title may be cleared (WeKan's card details), and is kept without the
  // spaces around it.
  Title_:=Trim(Title);
  if (BoardId='') or (CardId='') or (Pos(#0,BoardId+CardId+Title)>0) then
  begin Error:='Invalid title';Exit(400);end;
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  if not ApiChildrenBelong(T.Db,BoardId,'','',CardId,'','','','') then
  begin Error:='Card not found';Exit(404);end;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  Stamp:=QuotedStr(NowIso);
  Old:=CardTextOf(T.Db,CardId,'title');
  if not T.Db.Exec('BEGIN IMMEDIATE; '+CardTextActivitySql(UserId,Scope,'title',Title_)+'UPDATE cards SET title='+QuotedStr(Title_)+',modifiedAt='+Stamp+
    ',dateLastActivity='+Stamp+' WHERE '+Scope+'; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+
    ' AND title='+QuotedStr(Title_)+')=1 THEN 1 ELSE json(''Card rename failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not rename card';Exit(500);end;
  RecordCardTextHistory(T.Db,UserId,BoardId,CardId,'title',Old,Title_);
  Result:=200;
end;

function BoardCanComment(Db:TWLDb;const UserId,BoardId:string):Boolean;
begin
  Result:=False;
  if (UserId='') or (BoardId='') or not BoardCanRead(Db,UserId,BoardId) then Exit;
  if Length(Db.Query('SELECT 1 FROM users WHERE id='+QuotedStr(UserId)+' AND isAdmin=1 AND COALESCE(loginDisabled,0)=0;'))=1 then Exit(True);
  Result:=Length(Db.Query('SELECT 1 FROM board_members WHERE boardId='+QuotedStr(BoardId)+' AND userId='+QuotedStr(UserId)+
    ' AND isActive=1 AND COALESCE(isNoComments,0)=0 AND COALESCE(isReadOnly,0)=0 AND COALESCE(isReadAssignedOnly,0)=0;'))=1;
end;

// WeKan's @mentions in a comment: @name or @"a name".
function CommentMentions(const Text:string):TStringArray;
var i,j:Integer;Name:string;
  procedure Add(const N:string);
  begin if N<>'' then begin SetLength(Result,Length(Result)+1);Result[High(Result)]:=N;end;end;
begin
  Result:=nil;i:=1;
  while i<=Length(Text) do
  begin
    if (Text[i]='@') and ((i=1) or not (Text[i-1] in ['A'..'Z','a'..'z','0'..'9','_'])) then
    begin
      j:=i+1;Name:='';
      if (j<=Length(Text)) and (Text[j]='"') then
      begin
        Inc(j);
        while (j<=Length(Text)) and (Text[j]<>'"') do begin Name:=Name+Text[j];Inc(j);end;
        if j>Length(Text) then Name:='';
      end
      else
        while (j<=Length(Text)) and (Text[j] in ['A'..'Z','a'..'z','0'..'9','_','.','@','-']) do begin Name:=Name+Text[j];Inc(j);end;
      Add(Name);i:=j;
    end;
    Inc(i);
  end;
end;

function HasId(const L:TStringArray;const Id:string):Boolean;
var i:Integer;
begin
  Result:=False;for i:=0 to High(L) do if L[i]=Id then Exit(True);
end;

procedure AddId(var L:TStringArray;const Id:string);
begin
  if (Id<>'') and not HasId(L,Id) then begin SetLength(L,Length(L)+1);L[High(L)]:=Id;end;
end;

procedure AddRows(var L:TStringArray;const R:TWLRows);
var i:Integer;
begin
  for i:=0 to High(R) do AddId(L,R[i][0]);
end;

// The statements that put the activity into each recipient's
// profile.notifications, once, as WeKan makes them
// (server/models/activities.js, models/lib/boardNotificationRecipients.js):
// the people who take part in the card and the board's watchers, or those
// a comment mentions; only active members who watch or track the board, or
// watch the list or the card (#6658); never the actor, unless they mention
// themselves. The member an activity is about (memberId) takes part in it,
// and one just put on the card as a member or an assignee is told (#5833,
// unless NOTIFY_ON_ASSIGN=false) - still only when watching or tracking.
// Nothing when Admin Panel turned notifications off (#5820), and only once
// the activity is there: a statement that wrote none notifies nobody.
function NotificationsSql(Db:TWLDb;const ActorId,BoardId,ListId,CardId,CommentText,ActivityId:string;
  const ActivityType:string='';const MemberId:string=''):string;
var Participants,Watchers,Scoped,Watching,Tracking,Members,Names:TStringArray;R:TWLRows;i,j:Integer;
  Mentioned,SelfMention:Boolean;Doc:TJSONData;Arr:TJSONData;
begin
  Result:='';Participants:=nil;Watchers:=nil;Scoped:=nil;Watching:=nil;Tracking:=nil;Members:=nil;
  if (BoardId='') or SharedSettingOn(Db,'disableNotifications') then Exit;
  if MemberId<>'' then AddId(Participants,MemberId);
  AddRows(Members,Db.Query('SELECT m.userId FROM board_members m JOIN users u ON u.id=m.userId WHERE m.boardId='+QuotedStr(BoardId)+
    ' AND m.isActive=1 AND COALESCE(u.loginDisabled,0)=0;'));
  // The list's watchers: a shared store's lists document has them.
  if ListId<>'' then
  begin
    Doc:=nil;
    try
      try Doc:=GetJSON(SharedDocument(Db,'lists',ListId));except Doc:=nil;end;
      if Doc is TJSONObject then
      begin
        Arr:=TJSONObject(Doc).Find('watchers');
        if Arr is TJSONArray then
          for i:=0 to TJSONArray(Arr).Count-1 do
            if TJSONArray(Arr).Items[i].JSONType=jtString then
            begin AddId(Scoped,TJSONArray(Arr).Items[i].AsString);AddId(Watchers,TJSONArray(Arr).Items[i].AsString);end;
      end;
    finally Doc.Free;end;
  end;
  if CardId<>'' then
  begin
    AddRows(Participants,Db.Query('SELECT userId FROM cards WHERE id='+QuotedStr(CardId)+';'));
    AddRows(Participants,Db.Query('SELECT userId FROM card_members WHERE cardId='+QuotedStr(CardId)+';'));
    AddRows(Participants,Db.Query('SELECT userId FROM card_assignees WHERE cardId='+QuotedStr(CardId)+';'));
    R:=Db.Query('SELECT w.value FROM cards,json_each(CASE WHEN json_valid(cards.extra_json) THEN cards.extra_json ELSE ''{}'' END,''$.watchers'') w '+
      'WHERE cards.id='+QuotedStr(CardId)+';');
    AddRows(Scoped,R);AddRows(Watchers,R);
  end;
  Mentioned:=False;SelfMention:=False;
  Names:=CommentMentions(CommentText);
  for i:=0 to High(Names) do
  begin
    if Names[i]='board_members' then for j:=0 to High(Members) do AddId(Watchers,Members[j])
    else if Names[i]='board_assignees' then
      AddRows(Watchers,Db.Query('SELECT DISTINCT a.userId FROM card_assignees a JOIN cards c ON c.id=a.cardId WHERE c.boardId='+QuotedStr(BoardId)+';'))
    else if Names[i]='card_members' then AddRows(Watchers,Db.Query('SELECT userId FROM card_members WHERE cardId='+QuotedStr(CardId)+';'))
    else if Names[i]='card_assignees' then AddRows(Watchers,Db.Query('SELECT userId FROM card_assignees WHERE cardId='+QuotedStr(CardId)+';'))
    else
    begin
      R:=Db.Query('SELECT id FROM users WHERE username='+QuotedStr(Names[i])+';');
      if (Length(R)<>1) or not HasId(Members,R[0][0]) then Continue;
      AddId(Watchers,R[0][0]);
      if R[0][0]=ActorId then SelfMention:=True;
    end;
    Mentioned:=True;
  end;
  R:=Db.Query('SELECT json_extract(w.value,''$.userId''),json_extract(w.value,''$.level'') FROM boards,json_each(CASE WHEN json_valid(boards.settings_json) '+
    'THEN boards.settings_json ELSE ''{}'' END,''$.watchers'') w WHERE boards.id='+QuotedStr(BoardId)+' AND w.type=''object'';');
  for i:=0 to High(R) do
    if R[i][1]='watching' then AddId(Watching,R[i][0])
    else if R[i][1]='tracking' then AddId(Tracking,R[i][0]);
  if not Mentioned then
  begin
    for i:=0 to High(Watching) do AddId(Watchers,Watching[i]);
    for i:=0 to High(Participants) do if HasId(Tracking,Participants[i]) then AddId(Watchers,Participants[i]);
  end;
  if (MemberId<>'') and ((ActivityType='joinMember') or (ActivityType='joinAssignee')) and
    (LowerCase(GetEnvironmentVariable('NOTIFY_ON_ASSIGN'))<>'false') then AddId(Watchers,MemberId);
  for i:=0 to High(Watchers) do
    if HasId(Members,Watchers[i]) and (HasId(Watching,Watchers[i]) or HasId(Tracking,Watchers[i]) or HasId(Scoped,Watchers[i])) and
      ((Watchers[i]<>ActorId) or SelfMention) then
      Result:=Result+'UPDATE users SET profile_json=json_set(CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END,'+
        '''$.notifications'',json_insert(COALESCE(json_extract(CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END,''$.notifications''),json(''[]'')),'+
        '''$[#]'',json_object(''activity'','+QuotedStr(ActivityId)+',''read'',json(''null'')))) WHERE id='+QuotedStr(Watchers[i])+
        ' AND NOT EXISTS(SELECT 1 FROM json_each(CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END,''$.notifications'') n '+
        'WHERE json_extract(n.value,''$.activity'')='+QuotedStr(ActivityId)+') AND EXISTS(SELECT 1 FROM activities WHERE id='+
        QuotedStr(ActivityId)+'); ';
end;

function AddViewComment(const T:TWLTenant;const UserId,BoardId,CardId,Text:string;out CommentId,Error:string):Integer;
var Stamp,ActivityId:string;Card:TWLRows;
begin
  CommentId:='';Error:='';
  if (BoardId='') or (CardId='') or (Pos(#0,BoardId+CardId+Text)>0) then begin Error:='Card not found';Exit(404);end;
  if not BoardCanComment(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  if not ApiChildrenBelong(T.Db,BoardId,'','',CardId,'','','','') then
  begin Error:='Resource does not belong to this board or parent';Exit(404);end;
  if Trim(Text)='' then begin Error:='Invalid comment';Exit(400);end;
  CommentId:=NewId;ActivityId:=NewId;Stamp:=QuotedStr(NowIso);
  Card:=T.Db.Query('SELECT COALESCE(listId,''''),COALESCE(swimlaneId,'''') FROM cards WHERE id='+QuotedStr(CardId)+';');
  if Length(Card)<>1 then begin Error:='Card not found';Exit(404);end;
  // WeKan's addComment activity, and the notifications it makes.
  if not T.Db.Exec('BEGIN IMMEDIATE; INSERT INTO card_comments(id,boardId,cardId,userId,text,createdAt,modifiedAt) VALUES('+
    QuotedStr(CommentId)+','+QuotedStr(BoardId)+','+QuotedStr(CardId)+','+QuotedStr(UserId)+','+QuotedStr(Text)+','+
    Stamp+','+Stamp+'); INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) VALUES('+
    QuotedStr(ActivityId)+',''addComment'','+QuotedStr(UserId)+','+QuotedStr(BoardId)+','+QuotedStr(CardId)+','+QuotedStr(Card[0][0])+','+
    QuotedStr(Card[0][1])+','+Stamp+','+Stamp+',json_object(''commentId'','+QuotedStr(CommentId)+')); '+
    NotificationsSql(T.Db,UserId,BoardId,Card[0][0],CardId,Text,ActivityId)+'COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');CommentId:='';Error:='Could not add comment';Exit(500);end;
  Result:=200;
end;

function CreateViewList(const T:TWLTenant;const UserId,BoardId,SwimlaneId,AfterListId,Title:string;out ListId,Error:string):Integer;
var Lane,Sort,Stamp:string;After,Next,R:TWLRows;Fmt:TFormatSettings;AfterSort,NextSort:Double;
begin
  ListId:='';Error:='';
  if (BoardId='') or (Trim(Title)='') or (Pos(#0,BoardId+SwimlaneId+AfterListId+Title)>0) then
  begin Error:='Invalid list';Exit(400);end;
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Access denied';Exit(403);end;
  Fmt:=DefaultFormatSettings;Fmt.DecimalSeparator:='.';Fmt.ThousandSeparator:=#0;
  Lane:=SwimlaneId;
  if (Lane<>'') and (Length(T.Db.Query('SELECT 1 FROM swimlanes WHERE id='+QuotedStr(Lane)+' AND boardId='+QuotedStr(BoardId)+';'))<>1) then
  begin Error:='Swimlane does not belong to this board';Exit(400);end;
  if Lane='' then
  begin
    R:=T.Db.Query('SELECT id FROM swimlanes WHERE boardId='+QuotedStr(BoardId)+' ORDER BY archived,sort,id LIMIT 1;');
    if Length(R)=1 then Lane:=R[0][0];
  end;
  if AfterListId<>'' then
  begin
    After:=T.Db.Query('SELECT COALESCE(swimlaneId,''''),json_quote(sort) FROM lists WHERE id='+QuotedStr(AfterListId)+
      ' AND boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL;');
    if Length(After)<>1 then begin Error:='Selected list not found';Exit(404);end;
    if After[0][0]<>'' then Lane:=After[0][0];
    AfterSort:=StrToFloatDef(After[0][1],0,Fmt);
    // The next list of that swimlane (or of every swimlane), by sort.
    Next:=T.Db.Query('SELECT json_quote(sort) FROM lists WHERE boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL'+
      ' AND (swimlaneId='+QuotedStr(Lane)+' OR swimlaneId='''') AND sort>'+FloatToStr(AfterSort,Fmt)+' ORDER BY sort LIMIT 1;');
    if Length(Next)=1 then
    begin
      NextSort:=StrToFloatDef(Next[0][0],AfterSort+2,Fmt);
      Sort:=FloatToStr(AfterSort+(NextSort-AfterSort)/2,Fmt);
    end
    else Sort:=FloatToStr(AfterSort+1,Fmt);
  end
  else
    Sort:='(SELECT coalesce(max(sort),-1)+1 FROM lists WHERE boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL'+
      ' AND (swimlaneId='+QuotedStr(Lane)+' OR swimlaneId=''''))';
  ListId:=NewId;Stamp:=QuotedStr(NowIso);
  if not T.Db.Exec('BEGIN IMMEDIATE; INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt,modifiedAt) VALUES('+
    QuotedStr(ListId)+','+QuotedStr(BoardId)+','+QuotedStr(Lane)+','+QuotedStr(Title)+','+Sort+','+Stamp+','+Stamp+'); COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');ListId:='';Error:='Could not create list';Exit(500);end;
  Result:=200;
end;

// A map key of the user's profile, as WeKan's assertSafeMapKey allows one:
// an id of letters, digits, '-' and '_'.
function SafeMapKey(const Key:string):Boolean;
var i:Integer;
begin
  Result:=(Key<>'') and (Length(Key)<=128);
  for i:=1 to Length(Key) do
    if not (Key[i] in ['A'..'Z','a'..'z','0'..'9','-','_']) then Exit(False);
  // PrototypeBleed (WeKan's assertSafeMapKey): never an object's own key.
  if (Key='__proto__') or (Key='constructor') or (Key='prototype') then Exit(False);
end;

// A key of a profile fold map: an id, or a list's "listId:swimlaneId" (#6712).
function SafeFoldKey(const Key:string):Boolean;
var At:Integer;
begin
  At:=Pos(':',Key);
  if At=0 then Exit(SafeMapKey(Key));
  Result:=SafeMapKey(Copy(Key,1,At-1)) and SafeMapKey(Copy(Key,At+1,MaxInt));
end;

function ProfileFold(Db:TWLDb;const UserId,Map,BoardId,Key:string):Boolean;
var R:TWLRows;
begin
  Result:=False;
  if (UserId='') or not SafeMapKey(BoardId) or not SafeFoldKey(Key) then Exit;
  R:=Db.Query('SELECT CASE WHEN json_valid(profile_json) AND json_extract(profile_json,'+
    QuotedStr('$.'+Map+'."'+BoardId+'"."'+Key+'"')+')=1 THEN 1 ELSE 0 END FROM users WHERE id='+QuotedStr(UserId)+' LIMIT 1;');
  Result:=(Length(R)=1) and (R[0][0]='1');
end;

function SetViewProfileValue(const T:TWLTenant;const UserId,Map,BoardId,Key,JsonValue:string;out Error:string):Integer;
var Profile,Path,Target:string;
begin
  Error:='';
  if not SafeMapKey(BoardId) or ((Key<>'') and not SafeFoldKey(Key)) then begin Error:='Invalid map key';Exit(400);end;
  // The user's own setting of a board they can see - an assigned-only
  // member's board too (WeKan's isVisibleBy).
  if not (BoardCanRead(T.Db,UserId,BoardId) or AssignedOnlyMember(T.Db,UserId,BoardId)) then begin Error:='Board access forbidden';Exit(403);end;
  Profile:='CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END';
  Path:='$.'+Map+'."'+BoardId+'"';
  if Key='' then
    Target:='json_set(json_set('+Profile+','''+'$.'+Map+''',json(COALESCE(json_extract('+Profile+','''+'$.'+Map+'''),''{}''))),'''+
      Path+''',json('+QuotedStr(JsonValue)+'))'
  else
    Target:='json_set(json_set(json_set('+Profile+','''+'$.'+Map+''',json(COALESCE(json_extract('+Profile+','''+'$.'+Map+'''),''{}''))),'''+
      Path+''',json(COALESCE(json_extract('+Profile+','''+Path+'''),''{}''))),'''+Path+'."'+Key+'"'',json('+QuotedStr(JsonValue)+'))';
  if not T.Db.Exec('UPDATE users SET profile_json='+Target+' WHERE id='+QuotedStr(UserId)+';') then
  begin Error:='Could not save';Exit(500);end;
  Result:=200;
end;

function SetViewProfileFold(const T:TWLTenant;const UserId,Map,BoardId,Key:string;Folded:Boolean;out Error:string):Integer;
var Profile,Path,Value:string;
begin
  Error:='';
  if Folded then Value:='true' else Value:='false';
  if not SafeMapKey(BoardId) or not SafeFoldKey(Key) then begin Error:='Invalid map key';Exit(400);end;
  if not BoardCanRead(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  Profile:='CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END';
  Path:='$.'+Map+'."'+BoardId+'"';
  // json_set makes no missing parent: the map and the board's object first.
  if not T.Db.Exec('UPDATE users SET profile_json=json_set(json_set(json_set('+Profile+','''+'$.'+Map+''','+
    'json(COALESCE(json_extract('+Profile+','''+'$.'+Map+'''),''{}''))),'''+Path+''',json(COALESCE(json_extract('+Profile+
    ','''+Path+'''),''{}''))),'''+Path+'."'+Key+'"'',json('''+Value+''')) WHERE id='+QuotedStr(UserId)+';') then
  begin Error:='Could not save';Exit(500);end;
  Result:=200;
end;

function CreateViewSwimlane(const T:TWLTenant;const UserId,BoardId,AfterId:string;Above:Boolean;const Title:string;
  out LaneId,Error:string):Integer;
var Lanes:TWLRows;Fmt:TFormatSettings;i,At:Integer;Sort,Stamp:string;Prev,Next:Double;HasPrev,HasNext:Boolean;
begin
  LaneId:='';Error:='';
  if (BoardId='') or (Trim(Title)='') or (Pos(#0,BoardId+AfterId+Title)>0) then begin Error:='Invalid swimlane';Exit(400);end;
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Access denied';Exit(403);end;
  Fmt:=DefaultFormatSettings;Fmt.DecimalSeparator:='.';Fmt.ThousandSeparator:=#0;
  // swimlaneHeader.js swimlaneAddPopup: below (or above) the chosen swimlane,
  // between it and its neighbour (titleSortIndexes); last without one.
  Lanes:=T.Db.Query('SELECT id,json_quote(COALESCE(sort,0)) FROM swimlanes WHERE boardId='+QuotedStr(BoardId)+
    ' AND archived=0 ORDER BY sort,id;');
  At:=-1;
  for i:=0 to High(Lanes) do if Lanes[i][0]=AfterId then At:=i;
  if (AfterId<>'') and (At<0) then begin Error:='Swimlane does not belong to this board';Exit(404);end;
  if At<0 then At:=Length(Lanes) else if not Above then Inc(At);
  HasPrev:=At>0;HasNext:=At<Length(Lanes);
  if HasPrev then Prev:=StrToFloatDef(Lanes[At-1][1],0,Fmt);
  if HasNext then Next:=StrToFloatDef(Lanes[At][1],0,Fmt);
  if HasPrev and HasNext then Sort:=FloatToStr(Prev+(Next-Prev)/2,Fmt)
  else if HasPrev then Sort:=FloatToStr(Prev+1,Fmt)
  else if HasNext then Sort:=FloatToStr(Next-1,Fmt)
  else Sort:='0';
  LaneId:=NewId;Stamp:=QuotedStr(NowIso);
  if not T.Db.Exec('BEGIN IMMEDIATE; INSERT INTO swimlanes(id,boardId,title,type,sort,createdAt,modifiedAt) SELECT '+
    QuotedStr(LaneId)+','+QuotedStr(BoardId)+','+QuotedStr(Title)+',CASE WHEN type=''template-container'' THEN '+
    '''template-swimlane'' ELSE ''swimlane'' END,'+Sort+','+Stamp+','+Stamp+' FROM boards WHERE id='+QuotedStr(BoardId)+'; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');LaneId:='';Error:='Could not create swimlane';Exit(500);end;
  Result:=200;
end;

function ViewChecklistScope(const T:TWLTenant;const UserId,BoardId,CardId,ChecklistId,ItemId:string;out Error:string):Integer;
begin
  Error:='';
  if (BoardId='') or (CardId='') or (Pos(#0,BoardId+CardId+ChecklistId+ItemId)>0) then
  begin Error:='Card not found';Exit(404);end;
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  if not ApiChildrenBelong(T.Db,BoardId,'','',CardId,ChecklistId,ItemId,'','') then
  begin Error:='Resource does not belong to this board or parent';Exit(404);end;
  Result:=200;
end;

function ValidViewTitle(const Title:string):Boolean;
begin
  Result:=(Trim(Title)<>'') and (Pos(#0,Title)=0);
end;

function CreateViewChecklist(const T:TWLTenant;const UserId,BoardId,CardId,Title:string;out ChecklistId,Error:string):Integer;
var Stamp:string;
begin
  ChecklistId:='';
  Result:=ViewChecklistScope(T,UserId,BoardId,CardId,'','',Error);
  if Result<>200 then Exit;
  if not ValidViewTitle(Title) then begin Error:='Invalid checklist title';Exit(400);end;
  ChecklistId:=NewId;Stamp:=QuotedStr(NowIso);
  // Last among the card's checklists.
  if not T.Db.Exec('BEGIN IMMEDIATE; INSERT INTO checklists(id,cardId,boardId,title,sort,createdAt,modifiedAt) VALUES('+
    QuotedStr(ChecklistId)+','+QuotedStr(CardId)+','+QuotedStr(BoardId)+','+QuotedStr(Title)+
    ',(SELECT coalesce(max(sort),-1)+1 FROM checklists WHERE cardId='+QuotedStr(CardId)+'),'+Stamp+','+Stamp+'); COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');ChecklistId:='';Error:='Could not create checklist';Exit(500);end;
end;

function AddViewChecklistItem(const T:TWLTenant;const UserId,BoardId,CardId,ChecklistId,Title:string;out ItemId,Error:string):Integer;
var Stamp:string;
begin
  ItemId:='';
  if ChecklistId='' then begin Error:='Checklist not found';Exit(404);end;
  Result:=ViewChecklistScope(T,UserId,BoardId,CardId,ChecklistId,'',Error);
  if Result<>200 then Exit;
  if not ValidViewTitle(Title) then begin Error:='Invalid item title';Exit(400);end;
  ItemId:=NewId;Stamp:=QuotedStr(NowIso);
  if not T.Db.Exec('BEGIN IMMEDIATE; INSERT INTO checklist_items(id,checklistId,cardId,boardId,title,sort,createdAt,modifiedAt) VALUES('+
    QuotedStr(ItemId)+','+QuotedStr(ChecklistId)+','+QuotedStr(CardId)+','+QuotedStr(BoardId)+','+QuotedStr(Title)+
    ',(SELECT coalesce(max(sort),-1)+1 FROM checklist_items WHERE checklistId='+QuotedStr(ChecklistId)+'),'+Stamp+','+Stamp+'); COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');ItemId:='';Error:='Could not create checklist item';Exit(500);end;
end;

function ToggleViewChecklistItem(const T:TWLTenant;const UserId,BoardId,CardId,ChecklistId,ItemId:string;out Error:string):Integer;
var Predicate:string;
begin
  if (ChecklistId='') or (ItemId='') then begin Error:='Item not found';Exit(404);end;
  Result:=ViewChecklistScope(T,UserId,BoardId,CardId,ChecklistId,ItemId,Error);
  if Result<>200 then Exit;
  Predicate:='id='+QuotedStr(ItemId)+' AND checklistId='+QuotedStr(ChecklistId)+' AND cardId='+QuotedStr(CardId)+
    ' AND (boardId IS NULL OR boardId='+QuotedStr(BoardId)+')';
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM checklist_items WHERE '+Predicate+
    ')=1 THEN 1 ELSE json(''Checklist item scope changed'') END; UPDATE checklist_items SET isFinished=CASE WHEN isFinished=1 '+
    'THEN 0 ELSE 1 END,modifiedAt='+QuotedStr(NowIso)+' WHERE '+Predicate+'; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not update checklist item';Exit(500);end;
end;

function DeleteViewChecklist(const T:TWLTenant;const UserId,BoardId,CardId,ChecklistId:string;out Error:string):Integer;
var Predicate:string;
begin
  if ChecklistId='' then begin Error:='Checklist not found';Exit(404);end;
  Result:=ViewChecklistScope(T,UserId,BoardId,CardId,ChecklistId,'',Error);
  if Result<>200 then Exit;
  Predicate:='id='+QuotedStr(ChecklistId)+' AND cardId='+QuotedStr(CardId)+' AND (boardId IS NULL OR boardId='+QuotedStr(BoardId)+')';
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM checklists WHERE '+Predicate+
    ')=1 THEN 1 ELSE json(''Checklist scope changed'') END; DELETE FROM checklists WHERE '+Predicate+
    '; SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM checklists WHERE '+Predicate+') THEN 1 ELSE json(''Checklist write failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not delete checklist';Exit(500);end;
end;

function DeleteViewChecklistItem(const T: TWLTenant; const UserId, BoardId, CardId, ChecklistId, ItemId: string;
  out Error: string): Integer;
var Scope: string;
begin
  if (ChecklistId = '') or (ItemId = '') then begin Error := 'Item not found'; Exit(404); end;
  Result := ViewChecklistScope(T, UserId, BoardId, CardId, ChecklistId, ItemId, Error);
  if Result <> 200 then Exit;
  Scope := 'id=' + QuotedStr(ItemId) + ' AND checklistId=' + QuotedStr(ChecklistId) +
    ' AND cardId=' + QuotedStr(CardId) + ' AND (boardId IS NULL OR boardId=' + QuotedStr(BoardId) + ')';
  if not T.Db.Exec('BEGIN IMMEDIATE; DELETE FROM checklist_items WHERE ' + Scope +
    ' AND EXISTS(SELECT 1 FROM cards WHERE id=' + QuotedStr(CardId) +
    ' AND boardId=' + QuotedStr(BoardId) + ' AND deletedAt IS NULL)' +
    '; SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM checklist_items WHERE ' + Scope +
    ') THEN 1 ELSE json(''Checklist item delete failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;'); Error := 'Could not delete checklist item'; Exit(500); end;
end;

// Send one card as JSON (incl. its labelIds). Returns False (and sends 404) if missing.
function ChecklistReadSql(const BoardId,CardId,ChecklistId:string):string;
begin
  Result:='SELECT json_object(''_id'',c.id,''cardId'',c.cardId,''title'',c.title,''sort'',c.sort,''dueAt'',c.dueAt,'+
    '''items'',json((SELECT json_group_array(json(item)) FROM (SELECT json_object(''_id'',i.id,''title'',i.title,'+
    '''isFinished'',json(CASE WHEN i.isFinished=1 THEN ''true'' ELSE ''false'' END),''dueAt'',i.dueAt) item '+
    'FROM checklist_items i WHERE i.checklistId=c.id AND i.cardId=c.cardId AND (i.boardId IS NULL OR i.boardId='+
    QuotedStr(BoardId)+') ORDER BY i.sort,i.id)))) AS payload FROM checklists c WHERE c.cardId='+QuotedStr(CardId)+
    ' AND (c.boardId IS NULL OR c.boardId='+QuotedStr(BoardId)+')';
  if ChecklistId<>'' then Result:=Result+' AND c.id='+QuotedStr(ChecklistId);
  Result:=Result+' ORDER BY c.sort,c.id';
end;

function ChecklistCollectionSql(const BoardId,CardId:string):string;
begin
  Result:='SELECT json_group_array(json(payload)) FROM ('+ChecklistReadSql(BoardId,CardId,'')+');';
end;

const CardNotFound = '{"error":"Card not found"}';

function SendCardById(aResponse: TResponse; Db: TWLDb; const CardId,UserId: string; IncludeChecklists:Boolean=False; const RequiredBoardId:string=''; const ActiveListId:string=''): Boolean;
var ReadSql,ParentId:string; R, L: TWLRows; O: TJSONObject; A: TJSONArray; i: Integer;Policy:TFieldPolicy;
begin
  Result := False;
  ReadSql:='SELECT id,title,description,listId,swimlaneId,boardId,color,isOvertime,json_quote(sort),parentId FROM cards WHERE deletedAt IS NULL AND id='+QuotedStr(CardId);
  if RequiredBoardId<>'' then ReadSql:=ReadSql+' AND boardId='+QuotedStr(RequiredBoardId);
  if ActiveListId<>'' then ReadSql:=ReadSql+' AND listId='+QuotedStr(ActiveListId)+' AND archived=0';
  R:=Db.Query(ReadSql+' LIMIT 1;');
  if Length(R)=0 then begin SendJson(aResponse,CardNotFound,404);Exit;end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('title', R[0][1]); O.Add('description', R[0][2]);
    O.Add('listId', R[0][3]); O.Add('swimlaneId', R[0][4]); O.Add('boardId', R[0][5]);
    O.Add('color', R[0][6]); O.Add('isOvertime', R[0][7]='1'); O.Add('sort',GetJSON(R[0][8]));
    ParentId:=R[0][9];
    if (ParentId<>'') and (Pos(#0,ParentId)=0) then
    begin
      L:=Db.Query('SELECT boardId FROM cards WHERE id='+QuotedStr(ParentId)+' AND deletedAt IS NULL;');
      if (Length(L)=1) and BoardCanRead(Db,UserId,L[0][0]) then O.Add('parentId',ParentId);
    end;
    A := TJSONArray.Create;
    L := Db.Query(Format('SELECT labelId FROM card_labels WHERE cardId=%s;', [QuotedStr(CardId)]));
    for i := 0 to High(L) do if Length(L[i]) > 0 then A.Add(L[i][0]);
    O.Add('labelIds', A);
    A := TJSONArray.Create;
    L := Db.Query(Format('SELECT userId FROM card_members WHERE cardId=%s;', [QuotedStr(CardId)]));
    for i := 0 to High(L) do if Length(L[i]) > 0 then A.Add(L[i][0]);
    O.Add('members', A);
    A := TJSONArray.Create;
    L := Db.Query(Format('SELECT userId FROM card_assignees WHERE cardId=%s;', [QuotedStr(CardId)]));
    for i := 0 to High(L) do if Length(L[i]) > 0 then A.Add(L[i][0]);
    O.Add('assignees', A);
    try A:=ReadCustomFields(Db,CardId);
    except
      SendError(aResponse,500,'Could not read custom-field values');Exit;
    end;
    Policy:=nil;
    try
      try
        Policy:=TFieldPolicy.Create(Db,UserId,R[0][5],CardId);Policy.Redact(A);
      except
        // Failure to resolve policy never returns the unredacted array.
        for i:=0 to A.Count-1 do if TJSONObject(A.Items[i]).Find('value')<>nil then
        begin TJSONObject(A.Items[i]).Delete('value');TJSONObject(A.Items[i]).Add('value',TJSONNull.Create);end;
      end;
    finally Policy.Free;end;
    O.Add('customFields', A);
    if IncludeChecklists then
    begin
      L:=Db.Query(ChecklistCollectionSql(R[0][5],CardId));
      if Length(L)<>1 then begin SendError(aResponse,500,'Could not read card checklists');Exit;end;
      O.Add('checklists',GetJSON(L[0][0]));
    end;
    SendJson(aResponse, O.AsJSON);
    Result := True;
  finally O.Free; end;
end;

procedure ApiCard(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId,BoardId,CardId,ListId: string; Rows:TWLRows;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];CardId:=aRequest.RouteParams['cardId'];
  ListId:=aRequest.RouteParams['listId'];
  if BoardId<>'' then
  begin
    if not ApiBoardGuard(T,aRequest,aResponse,UserId,CardNotFound) then Exit;
  end else
  begin
    Rows:=T.Db.Query('SELECT boardId FROM cards WHERE id='+QuotedStr(CardId)+' AND deletedAt IS NULL;');
    if Length(Rows)=0 then begin SendJson(aResponse,CardNotFound,404);Exit;end;
    if (Length(Rows)<>1) or (Rows[0][0]='') then begin SendError(aResponse,403,'Board access forbidden');Exit;end;
    BoardId:=Rows[0][0];
    if not ApiAuthBoard(T,aResponse,UserId,BoardId,False) then Exit;
  end;
  SendCardById(aResponse,T.Db,CardId,UserId,True,BoardId,ListId);
end;

// PUT card — update any of title/description/color and replace labelIds if given.
function ChecklistDeadlineSql(Value:TJSONData;out Literal:string):Boolean; forward;

function CardDateSql(Value:TJSONData;out Literal:string):Boolean;
const TimeClip=8640000000000000;
var Text:string;Ms:Int64;I:Integer;Number:Double;Formatted,Input:TJSONData;
begin
  if Value.JSONType=jtNull then begin Literal:='NULL';Exit(True);end;
  Text:='';Result:=False;
  if Value.JSONType=jtString then
  begin
    Text:=Trim(Value.AsString);
    if (Value.AsString='') or (Value.AsString='null') then
    begin Literal:='NULL';Exit(True);end;
    I:=1;
    if (Text<>'') and (Text[1]='-') then Inc(I);
    while (I<=Length(Text)) and (Text[I] in ['0'..'9']) do Inc(I);
    if not ((I>1) and (I>Length(Text)) and TryStrToInt64(Text,Ms)) then
    begin
      if (Length(Text)=10) then Text:=Text+'T00:00:00Z';
      Input:=TJSONString.Create(Text);
      try Exit(ChecklistDeadlineSql(Input,Literal));finally Input.Free;end;
    end;
  end else if Value.JSONType=jtNumber then
  begin
    Number:=Value.AsFloat;
    if IsNan(Number) or IsInfinite(Number) or (Abs(Number)>TimeClip) then Exit;
    Ms:=Trunc(Number);
  end else Exit;
  if (Ms< -TimeClip) or (Ms>TimeClip) then Exit;
  Formatted:=JsonDate(Ms);
  try
    Text:=Formatted.AsString;
    if (Length(Text)=24) and (Copy(Text,1,4)<>'0000') then Literal:=QuotedStr(Text)
    else Literal:=QuotedStr(IntToStr(Ms));
  finally Formatted.Free;end;
  Result:=True;
end;

procedure ApiMyCards(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;Source:TSelectionScope;UserId,UserSql,Members,Assignees,Assigned,Related,BoardMember,
  Scope,Due,FromDate,ToDate,Sql,CardScope:string;Rows:TWLRows;
  function DateNumber(const Value:string):string;
  begin
    Result:='CASE WHEN instr('+Value+',''T'')>0 THEN unixepoch('+Value+
      ',''subsec'')*1000 ELSE CAST('+Value+' AS INTEGER) END';
  end;
  function Bound(const Name:string;out Literal:string):Boolean;
  var Raw:string;Input:TJSONData;
  begin
    Raw:=aRequest.QueryFields.Values[Name];Literal:='';
    if Raw='' then Exit(True);
    Input:=TJSONString.Create(Raw);
    try Result:=CardDateSql(Input,Literal) and (Literal<>'NULL');finally Input.Free;end;
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not Bound('from',FromDate) or not Bound('to',ToDate) then
  begin SendError(aResponse,400,'Invalid due date range');Exit;end;
  UserSql:=QuotedStr(UserId);Source:=TSelectionScope.Create(T.Db);
  try
    CardScope:=Source.StringField('cards','id')+' AND '+Source.StringField('cards','boardId');
    Members:='SELECT userId FROM card_members WHERE cardId=cards.id AND '+Source.StringField('card_members','userId');
    Assignees:='SELECT userId FROM card_assignees WHERE cardId=cards.id AND '+Source.StringField('card_assignees','userId');
    Assigned:=UserSql+' IN ('+Assignees+')';
    Related:='('+Assigned+' OR '+UserSql+' IN ('+Members+') OR EXISTS(SELECT 1 FROM json_each(cards.extra_json) relation '+
      'JOIN json_each(CASE WHEN relation.type=''array'' THEN relation.value ELSE ''[]'' END) participant '+
      'WHERE relation.key IN (''requesters'',''assigners'') AND participant.type=''text'' AND participant.value='+UserSql+'))';
    BoardMember:='EXISTS(SELECT 1 FROM board_members WHERE boardId=cards.boardId AND userId='+UserSql+
      ' AND isActive=1 AND '+Source.StringField('board_members','userId')+
      ' AND ((COALESCE(isReadAssignedOnly,0)=0 AND COALESCE(isCommentAssignedOnly,0)=0 AND '+
      'COALESCE(isNormalAssignedOnly,0)=0) OR '+Assigned+'))';
  finally Source.Free;end;
  Scope:='cards.archived=0 AND cards.deletedAt IS NULL AND '+CardScope+
    ' AND EXISTS(SELECT 1 FROM boards WHERE id=cards.boardId AND archived=0) AND '+Related+' AND '+BoardMember;
  Due:=DateNumber('cards.dueAt');
  if (LowerCase(aRequest.QueryFields.Values['due'])='true') or
    (LowerCase(aRequest.QueryFields.Values['due'])='yes') or
    (aRequest.QueryFields.Values['due']='1') or (FromDate<>'') or (ToDate<>'') then
    Scope:=Scope+' AND cards.dueAt IS NOT NULL AND cards.dueAt<>''''';
  if FromDate<>'' then Scope:=Scope+' AND ('+Due+')>=('+DateNumber(FromDate)+')';
  if ToDate<>'' then Scope:=Scope+' AND ('+Due+')<=('+DateNumber(ToDate)+')';
  Sql:='SELECT json_group_array(json(card)) FROM (SELECT json_patch(''{}'',json_object(''_id'',cards.id,'+
    '''title'',cards.title,''boardId'',cards.boardId,''swimlaneId'',cards.swimlaneId,''listId'',cards.listId,'+
    '''dueAt'',cards.dueAt,''startAt'',cards.startAt,''endAt'',cards.endAt,'+
    '''members'',json((SELECT json_group_array(userId) FROM ('+Members+'))),'+
    '''assignees'',json((SELECT json_group_array(userId) FROM ('+Assignees+'))))) card FROM cards WHERE '+Scope+
    ' ORDER BY '+Due+',cards.id);';
  Rows:=T.Db.Query(Sql);
  if Length(Rows)<>1 then begin SendError(aResponse,500,'Could not read user cards');Exit;end;
  SendJson(aResponse,Rows[0][0]);
end;

function CardDecorations(Value:TJSONData;const Key:string):TJSONArray;
var Parsed:TJSONObject;Entry,Item:TJSONObject;Field:TJSONData;I:Integer;
  Name,Text:string;Number:Double;Format:TFormatSettings;
begin
  Result:=TJSONArray.Create;Parsed:=nil;
  try
    try
      if Value.JSONType=jtString then
      begin
        Parsed:=ExactObject('{"array":'+Value.AsString+'}');
        Value:=Parsed.Find('array');
      end;
      if not (Value is TJSONArray) then raise Exception.Create('Invalid card decoration array');
      Format:=DefaultFormatSettings;Format.DecimalSeparator:='.';
      for I:=0 to Value.Count-1 do
      begin
        if not (Value.Items[I] is TJSONObject) then raise Exception.Create('Invalid card decoration entry');
        Entry:=TJSONObject(Value.Items[I]);Item:=TJSONObject.Create;Result.Add(Item);
        if Key='stickers' then
        begin
          for Name in ['icon','name','highlight'] do
          begin
            Field:=Entry.Find(Name);
            if Field=nil then Continue;
            if Field.JSONType<>jtString then raise Exception.Create('Invalid sticker field');
            Text:=Field.AsString;
            if (Name='highlight') and (Text<>'underline') and (Text<>'round') then
              raise Exception.Create('Invalid sticker highlight');
            Item.Add(Name,Text);
          end;
        end else
        begin
          Text:=Entry.Get('_id','');if Text='' then Text:=NewId;Item.Add('_id',Text);
          Item.Add('name',Entry.Get('name',''));Item.Add('address',Entry.Get('address',''));
          for Name in ['latitude','longitude'] do
          begin
            Field:=Entry.Find(Name);
            if (Field=nil) or ((Field.JSONType=jtString) and (Field.AsString='')) then Continue;
            if not (Field.JSONType in [jtNumber,jtString]) or
              not TryStrToFloat(Field.AsString,Number,Format) or IsNan(Number) or IsInfinite(Number) then
              raise Exception.Create('Invalid location coordinate');
            Item.Add(Name,Number);
          end;
        end;
      end;
    except FreeAndNil(Result);raise;end;
  finally Parsed.Free;end;
end;

procedure RecordCardDateHistory(Db:TWLDb;const UserId,BoardId,CardId,Field,OldDate,NewDate:string);
var Previous,Next:TJSONObject; ChangeType:string;
begin
  if OldDate=NewDate then Exit;
  if OldDate='' then ChangeType:='added'
  else if NewDate='' then ChangeType:='removed'
  else ChangeType:='edited';
  Previous:=CardHistoryDateValue(Field,OldDate);
  Next:=CardHistoryDateValue(Field,NewDate);
  try
    try
      RecordHistoryRow(Db,UserId,BoardId,'card',CardId,'dates',ChangeType,Previous,Next);
    except
      // History never fails the edit it records.
    end;
  finally Previous.Free;Next.Free;end;
end;

procedure ApiCardEdit(aRequest:TRequest; aResponse:TResponse);
const DateFields:array[0..3] of string=('receivedAt','startAt','dueAt','endAt');
var T:TWLTenant; UserId,CardId,BoardId,Sets,Relations,Scope,ArchiveSql,ArchiveGuard,ArchiveAt,Stamp,Value,RestMoveReason:string;
  HasArchive,Archive,WasArchived,HasEdits,HasOvertime,HasSort,HasTitle:Boolean;Body,Decorations:TJSONObject;Input:TJSONData;
  FieldName,FieldSets,Literal:string;HasDate:Boolean;SortNumber,SpentHours:Double;NumberFormat:TFormatSettings;
  Code:Integer;MoveError:string;HasDescription,HasColor,HasCompletion,OldDone,Done,OldOvertime,Overtime,HasSpentTime:Boolean;NewTitle,NewDescription,OldTitle,OldDescription,NewColor,OldColor,OldSpentTime,NewSpentTime:string;
  BeforeTime,AfterTime:TJSONObject; TimeRows,OldDates,ArchiveRows:TWLRows; DateIndex:Integer; DateWrites:array[0..3] of string;
begin
  HasCompletion:=False;OldDone:=False;Done:=False;OldOvertime:=False;Overtime:=False;
  HasDescription:=False;NewTitle:='';NewDescription:='';OldTitle:='';OldDescription:='';
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  CardId:=aRequest.RouteParams['cardId'];BoardId:=aRequest.RouteParams['boardId'];
  HasArchive:=BodyHasField(aRequest,'archive');
  HasColor:=BodyHasField(aRequest,'color');
  HasEdits:=HasColor or BodyHasField(aRequest,'labelIds') or
    BodyHasField(aRequest,'members') or BodyHasField(aRequest,'assignees');
  FieldSets:='';HasDate:=False;Body:=nil;Decorations:=nil;
  try
    try
      if (Pos('application/json',LowerCase(aRequest.ContentType))=1) and (aRequest.Content<>'') then
        Body:=ExactObject(aRequest.Content)
      else
      begin
        Body:=TJSONObject.Create;
        for FieldName in ['receivedAt','startAt','dueAt','endAt','dueComplete','stickers','locations','isOverTime','spentTime','moveReason','sort','description','title'] do
          if aRequest.ContentFields.IndexOfName(FieldName)>=0 then
            Body.Add(FieldName,aRequest.ContentFields.Values[FieldName]);
      end;
      // AdminFieldBleed: a custom field the user may not write, refused.
      if (Body.Find('customFields')<>nil) and
        AdminFieldForgery(T.Db,UserId,BoardId,CardId,Body.Find('customFields'),'rest:PUT card') then
      begin SendError(aResponse,403,'Custom-field write forbidden');Exit;end;
      Input:=Body.Find('moveReason');
      if (Input<>nil) and (Input.JSONType=jtString) then RestMoveReason:=Trim(Input.AsString);
      if (Length(RestMoveReason)>4096) or (Pos(#0,RestMoveReason)>0) then
      begin SendJson(aResponse,'{"error":"Invalid move reason"}',400);Exit;end;
      Input:=Body.Find('title');HasTitle:=Input<>nil;
      if HasTitle then
      begin
        if (Input.JSONType<>jtString) or (Pos(#0,Input.AsString)>0) then
        begin SendJson(aResponse,'{"error":"Invalid title"}',400);Exit;end;
        // A title of only spaces clears it (WeKan trims a title).
        NewTitle:=Trim(Input.AsString);
        FieldSets:=',title='+QuotedStr(NewTitle);
      end;
      for DateIndex:=Low(DateFields) to High(DateFields) do
      begin
        FieldName:=DateFields[DateIndex];
        Input:=Body.Find(FieldName);
        if Input=nil then Continue;
        HasDate:=True;
        if CardDateSql(Input,Literal) then
        begin
          DateWrites[DateIndex]:=Literal;
          FieldSets:=FieldSets+','+FieldName+'='+Literal;
        end;
      end;
      Input:=Body.Find('sort');HasSort:=Input<>nil;
      if HasSort then
      begin
        NumberFormat:=DefaultFormatSettings;NumberFormat.DecimalSeparator:='.';NumberFormat.ThousandSeparator:=#0;
        if not (Input.JSONType in [jtNumber,jtString]) or (Trim(Input.AsString)='') or
          not TryStrToFloat(Trim(Input.AsString),SortNumber,NumberFormat) or IsNan(SortNumber) or IsInfinite(SortNumber) then
        begin SendJson(aResponse,'{"error":"Invalid sort"}',400);Exit;end;
        FieldSets:=FieldSets+',sort='+FloatToStrF(SortNumber,ffGeneral,17,0,NumberFormat);
      end;
      Input:=Body.Find('spentTime');HasSpentTime:=Input<>nil;
      if HasSpentTime then
      begin
        NumberFormat:=DefaultFormatSettings;NumberFormat.DecimalSeparator:='.';NumberFormat.ThousandSeparator:=#0;
        if not (Input.JSONType in [jtNumber,jtString]) or
          not TryStrToFloat(Trim(Input.AsString),SpentHours,NumberFormat) or
          IsNan(SpentHours) or IsInfinite(SpentHours) or (SpentHours<0) then
        begin SendJson(aResponse,'{"error":"Invalid spentTime"}',400);Exit;end;
        Str(SpentHours,NewSpentTime);
        NewSpentTime:=Trim(NewSpentTime);
        FieldSets:=FieldSets+',spentTime='+NewSpentTime;
      end;
      Input:=Body.Find('isOverTime');
      HasOvertime:=Input<>nil;
      if HasOvertime then
      begin
        if not (Input.JSONType in [jtBoolean,jtString]) or
          ((Input.AsString<>'true') and (Input.AsString<>'false')) then
        begin SendJson(aResponse,'{"error":"Invalid isOverTime"}',400);Exit;end;
        Overtime:=Input.AsString='true';
        FieldSets:=FieldSets+',isOvertime='+IntToStr(Ord(Overtime));
      end;
      Input:=Body.Find('description');
      if Input<>nil then
      begin
        Value:='';
        case Input.JSONType of
          jtNull: ;
          jtString: Value:=Input.AsString;
        else SendJson(aResponse,'{"error":"Invalid description"}',400);Exit;
        end;
        if Pos(#0,Value)>0 then
        begin SendJson(aResponse,'{"error":"Invalid description"}',400);Exit;end;
        FieldSets:=FieldSets+',description='+QuotedStr(Value);
        HasDescription:=True;NewDescription:=Value;
      end;
      Input:=Body.Find('dueComplete');
      HasCompletion:=Input<>nil;
      if HasCompletion then
      begin
        Value:='';
        if Input.JSONType in [jtBoolean,jtString] then Value:=Input.AsString;
        Done:=SameText(Value,'true');
        FieldSets:=FieldSets+',dueComplete='+IntToStr(Ord(Done));
      end;
      Decorations:=TJSONObject.Create;
      for FieldName in ['stickers','locations'] do
      begin
        Input:=Body.Find(FieldName);
        if Input<>nil then Decorations.Add(FieldName,CardDecorations(Input,FieldName));
      end;
      if Decorations.Count>0 then
        FieldSets:=FieldSets+',extra_json=json_patch(extra_json,'+QuotedStr(Decorations.AsJSON)+')';
    except SendError(aResponse,400,'Invalid card update');Exit;end;
  finally Decorations.Free;Body.Free;end;
  HasEdits:=HasEdits or (FieldSets<>'');
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  if HasArchive and not HasEdits then
  begin
    if not ApiAuthBoard(T,aResponse,UserId,BoardId,True) then Exit;
    if Length(T.Db.Query('SELECT id FROM cards WHERE '+Scope+';'))<>1 then
    begin SendJson(aResponse,CardNotFound,404);Exit;end;
  end else
  begin
    if not ApiBoardGuard(T,aRequest,aResponse,UserId,CardNotFound) then Exit;
    Scope:=Scope+' AND listId='+QuotedStr(aRequest.RouteParams['listId']);
  end;
  if HasTitle then
  begin
    Scope:=Scope+' AND archived=0';
    if Length(T.Db.Query('SELECT id FROM cards WHERE '+Scope+';'))<>1 then
    begin SendJson(aResponse,CardNotFound,404);Exit;end;
  end;
  if HasDate and (FieldSets='') and not (HasArchive or HasEdits) then
  begin SendJson(aResponse,'{"message":"Error"}',404);Exit;end;
  if not CardRelationSql(T,aRequest,aResponse,BoardId,CardId,Relations) then Exit;
  Stamp:=QuotedStr(NowIso);
  ArchiveSql:='';ArchiveGuard:='';Archive:=False;WasArchived:=False;
  if HasArchive then
  begin
    Value:=aRequest.ContentFields.Values['archive'];
    if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
    begin
      Body:=nil;
      try
        try
          Body:=ExactObject(aRequest.Content);Input:=Body.Find('archive');
          if (Input<>nil) and (Input.JSONType in [jtString,jtBoolean]) then Value:=Input.AsString;
        except SendError(aResponse,400,'Invalid card update');Exit;end;
      finally Body.Free;end;
    end;
    Archive:=SameText(Value,'true');
    ArchiveRows:=T.Db.Query('SELECT COALESCE(archived,0) FROM cards WHERE '+Scope+';');
    if Length(ArchiveRows)<>1 then begin SendJson(aResponse,CardNotFound,404);Exit;end;
    WasArchived:=ArchiveRows[0][0]='1';
    ArchiveGuard:=' AND COALESCE(archived,0)='+IntToStr(Ord(WasArchived));
    if Archive<>WasArchived then
    begin
      ArchiveAt:='NULL';
      if Archive then ArchiveAt:=Stamp;
      ArchiveSql:='UPDATE cards SET archived='+IntToStr(Ord(Archive))+',archivedAt='+ArchiveAt+' WHERE '+Scope+'; ';
    end;
  end;
  Sets:='';
  if not HasArchive or HasEdits then
  begin
    Sets:='modifiedAt='+Stamp+',dateLastActivity='+Stamp+FieldSets;
    if HasColor then
    begin
      NewColor:=BodyField(aRequest,'color');
      OldColor:=CardTextOf(T.Db,CardId,'color');
      Sets:=Sets+',color='+QuotedStr(NewColor);
    end;
    Sets:='UPDATE cards SET '+Sets+' WHERE '+Scope+'; ';
  end;
  OldSpentTime:='';
  if HasSpentTime then
  begin
    TimeRows:=T.Db.Query('SELECT '+HistorySpentTimeSql+' FROM cards WHERE '+Scope+';');
    if Length(TimeRows)=1 then OldSpentTime:=TimeRows[0][0];
  end;
  if HasDate then OldDates:=T.Db.Query('SELECT receivedAt,startAt,dueAt,endAt FROM cards WHERE '+Scope+';');
  if HasCompletion then OldDone:=CardCompletionOf(T.Db,Scope);
  if HasOvertime then OldOvertime:=Length(T.Db.Query('SELECT 1 FROM cards WHERE '+Scope+' AND isOvertime=1;'))=1;
  if HasTitle then OldTitle:=CardTextOf(T.Db,CardId,'title');
  if HasDescription then OldDescription:=CardTextOf(T.Db,CardId,'description');
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+ArchiveGuard+
    ')=1 THEN 1 ELSE json(''Card edit scope changed'') END; '+Sets+ArchiveSql+Relations+' COMMIT;') then
  begin
    T.Db.Exec('ROLLBACK;');
    if HasTitle and (Length(T.Db.Query('SELECT id FROM cards WHERE '+Scope+';'))<>1) then
      SendJson(aResponse,CardNotFound,404)
    else SendError(aResponse,500,'Could not edit card');
    Exit;
  end;
  if Length(OldDates)=1 then
    for DateIndex:=Low(DateFields) to High(DateFields) do
      if DateWrites[DateIndex]<>'' then
      begin
        Literal:=DateWrites[DateIndex];
        Value:='';
        if Literal<>'NULL' then Value:=Copy(Literal,2,Length(Literal)-2);
        RecordCardDateHistory(T.Db,UserId,BoardId,CardId,DateFields[DateIndex],OldDates[0][DateIndex],Value);
      end;
  if HasTitle then RecordCardTextHistory(T.Db,UserId,BoardId,CardId,'title',OldTitle,NewTitle);
  if HasDescription then RecordCardTextHistory(T.Db,UserId,BoardId,CardId,'description',OldDescription,NewDescription);
  if HasSpentTime then
  begin
    BeforeTime:=CardHistoryDateValue('spentTime',OldSpentTime);
    AfterTime:=CardHistoryDateValue('spentTime',NewSpentTime);
    try
      if BeforeTime.AsJSON<>AfterTime.AsJSON then
        try
          RecordHistoryRow(T.Db,UserId,BoardId,'card',CardId,'dates','edited',BeforeTime,AfterTime);
        except
          // History never fails the edit it records.
        end;
    finally BeforeTime.Free;AfterTime.Free;end;
  end;
  if HasArchive then RecordCardBooleanHistory(T.Db,UserId,BoardId,CardId,'archived',WasArchived,Archive);
  if HasOvertime and (Sets<>'') then RecordCardBooleanHistory(T.Db,UserId,BoardId,CardId,'isOvertime',OldOvertime,Overtime);
  if HasCompletion then RecordCardCompletionHistory(T.Db,UserId,BoardId,CardId,OldDone,Done);
  if HasColor then RecordCardTextHistory(T.Db,UserId,BoardId,CardId,'color',OldColor,NewColor);
  // #6423: a listId or swimlaneId in the body moves the card there, within
  // its board, with WeKan's moveCard activity (MoveViewCard's checks).
  if BodyHasField(aRequest,'listId') or BodyHasField(aRequest,'swimlaneId') then
  begin
    Value:=BodyField(aRequest,'listId');
    if Value='' then Value:=aRequest.RouteParams['listId'];
    Code:=MoveViewCard(T,UserId,BoardId,CardId,BodyField(aRequest,'boardId'),BodyField(aRequest,'swimlaneId'),Value,MoveError,RestMoveReason);
    if Code<>200 then begin SendError(aResponse,Code,MoveError);Exit;end;
  end;
  if HasSort or HasOvertime or HasTitle then SendJson(aResponse,'{"_id":"'+StringToJSONString(CardId)+'"}')
  else SendCardById(aResponse,T.Db,CardId,UserId,False,BoardId);
end;

procedure ApiListCards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT id,title FROM cards WHERE listId=%s AND boardId=%s AND archived=0 AND deletedAt IS NULL ORDER BY sort;',
    [QuotedStr(aRequest.RouteParams['listId']),QuotedStr(aRequest.RouteParams['boardId'])]))));
end;

function CountOf(Db: TWLDb; const WhereCol, Id, BoardId: string): Integer;
var R: TWLRows;
begin
  R := Db.Query(Format('SELECT COUNT(*) FROM cards WHERE %s=%s AND boardId=%s AND archived=0 AND deletedAt IS NULL;',
    [WhereCol, QuotedStr(Id),QuotedStr(BoardId)]));
  if (Length(R) > 0) and (Length(R[0]) > 0) then Result := StrToIntDef(R[0][0], 0) else Result := 0;
end;

procedure ApiListCardsCount(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, Format('{"list_cards_count":%d}',
    [CountOf(T.Db, 'listId', aRequest.RouteParams['listId'],aRequest.RouteParams['boardId'])]));
end;

procedure ApiBoardCardsCount(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, Format('{"board_cards_count":%d}',
    [CountOf(T.Db, 'boardId', aRequest.RouteParams['boardId'],aRequest.RouteParams['boardId'])]));
end;

procedure ApiSwimlaneCards(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  SendJson(aResponse, RowsAsIdTitle(T.Db.Query(Format(
    'SELECT id,title FROM cards WHERE swimlaneId=%s AND boardId=%s AND archived=0 AND deletedAt IS NULL ORDER BY sort;',
    [QuotedStr(aRequest.RouteParams['swimlaneId']),QuotedStr(aRequest.RouteParams['boardId'])]))));
end;

function ChecklistDeadlineSql(Value:TJSONData;out Literal:string):Boolean;
const Prefix='0000-00-00T00:00:00';
var Text,Zone:string;Stamp:TDateTime;i,Offset:Integer;
begin
  if Value.JSONType=jtNull then begin Literal:='NULL';Exit(True);end;
  Result:=False;
  if Value.JSONType<>jtString then Exit;
  Text:=Value.AsString;
  if Length(Text)<20 then Exit;
  for i:=1 to Length(Prefix) do
    if Prefix[i]='0' then begin if not (Text[i] in ['0'..'9']) then Exit;end
    else if Text[i]<>Prefix[i] then Exit;
  Offset:=20;
  if Text[Offset]='.' then
  begin
    Inc(Offset);
    while (Offset<=Length(Text)) and (Text[Offset] in ['0'..'9']) do Inc(Offset);
    if (Offset<22) or (Offset>24) then Exit;
  end;
  Zone:=Copy(Text,Offset,MaxInt);
  if Zone<>'Z' then
  begin
    if Length(Zone)<>6 then Exit;
    if not (Zone[1] in ['+','-']) or (Zone[4]<>':') then Exit;
    for i in [2,3,5,6] do if not (Zone[i] in ['0'..'9']) then Exit;
    if (StrToInt(Copy(Zone,2,2))>23) or (StrToInt(Copy(Zone,5,2))>59) then Exit;
  end;
  try
    if not TryISO8601ToDate(Text,Stamp,True) then Exit;
    Literal:=QuotedStr(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',Stamp));
    Result:=True;
  except Result:=False;end;
end;

function WriteViewChecklistField(const T: TWLTenant; const BoardId, CardId, ChecklistId, ItemId, Field, Literal: string;
  out Error: string; const ExtraScope: string = ''): Integer;
var Scope, TableName: string;
begin
  Result := 200;
  Scope := 'id=' + QuotedStr(ChecklistId) + ' AND cardId=' + QuotedStr(CardId) +
    ' AND (boardId IS NULL OR boardId=' + QuotedStr(BoardId) + ')' +
    ' AND EXISTS(SELECT 1 FROM cards WHERE id=' + QuotedStr(CardId) +
    ' AND boardId=' + QuotedStr(BoardId) + ' AND deletedAt IS NULL)';
  TableName := 'checklists';
  if ItemId <> '' then
  begin
    TableName := 'checklist_items';
    Scope := 'id=' + QuotedStr(ItemId) + ' AND checklistId=' + QuotedStr(ChecklistId) +
      ' AND cardId=' + QuotedStr(CardId) + ' AND (boardId IS NULL OR boardId=' + QuotedStr(BoardId) +
      ') AND EXISTS(SELECT 1 FROM checklists WHERE ' + Scope + ')';
  end;
  Scope := Scope + ExtraScope;
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE ' + TableName + ' SET ' + Field + '=' + Literal +
    ',modifiedAt=' + QuotedStr(NowIso) + ' WHERE ' + Scope +
    '; SELECT CASE WHEN (SELECT count(*) FROM ' + TableName + ' WHERE ' + Scope + ' AND ' + Field + ' IS ' + Literal +
    ')=1 THEN 1 ELSE json(''Checklist field write failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;'); Error := 'Could not update checklist'; Exit(500); end;
end;

function RenameViewChecklist(const T: TWLTenant; const UserId, BoardId, CardId, ChecklistId, ItemId, Title: string;
  out Error: string): Integer;
begin
  if ChecklistId = '' then begin Error := 'Checklist not found'; Exit(404); end;
  Result := ViewChecklistScope(T, UserId, BoardId, CardId, ChecklistId, ItemId, Error);
  if Result <> 200 then Exit;
  if not ValidViewTitle(Title) then begin Error := 'Invalid title'; Exit(400); end;
  Result := WriteViewChecklistField(T, BoardId, CardId, ChecklistId, ItemId, 'title', QuotedStr(Title), Error);
end;

function SetViewChecklistDue(const T: TWLTenant; const UserId, BoardId, CardId, ChecklistId, ItemId, At: string;
  Remove: Boolean; out Error: string): Integer;
var Input: TJSONData; Literal: string;
begin
  if ChecklistId = '' then begin Error := 'Checklist not found'; Exit(404); end;
  Result := ViewChecklistScope(T, UserId, BoardId, CardId, ChecklistId, ItemId, Error);
  if Result <> 200 then Exit;
  if not BoardAllows(T.Db, BoardId, 'allowsChecklistDueDate') then
  begin Error := 'This board does not use checklist deadlines'; Exit(403); end;
  if Remove then Literal := 'NULL'
  else
  begin
    Input := TJSONString.Create(At);
    try
      if not ChecklistDeadlineSql(Input, Literal) then
      begin Error := 'Invalid checklist deadline'; Exit(400); end;
    finally Input.Free; end;
  end;
  Result := WriteViewChecklistField(T, BoardId, CardId, ChecklistId, ItemId, 'dueAt', Literal, Error);
end;

function AssignViewChecklistItem(const T: TWLTenant; const UserId, BoardId, CardId, ChecklistId, ItemId, Assignee: string;
  out Error: string): Integer;
var Literal, Guard: string;
begin
  if (ChecklistId = '') or (ItemId = '') then begin Error := 'Item not found'; Exit(404); end;
  Result := ViewChecklistScope(T, UserId, BoardId, CardId, ChecklistId, ItemId, Error);
  if Result <> 200 then Exit;
  Literal := 'NULL';
  Guard := '';
  if Assignee <> '' then
  begin
    if Pos(#0, Assignee) > 0 then begin Error := 'Invalid assignee'; Exit(400); end;
    Literal := QuotedStr(Assignee);
    Guard := 'EXISTS(SELECT 1 FROM board_members WHERE boardId=' + QuotedStr(BoardId) +
      ' AND userId=' + Literal + ' AND isActive=1)';
    if Length(T.Db.Query('SELECT 1 WHERE ' + Guard + ';')) <> 1 then
    begin Error := 'Not an active member of this board'; Exit(400); end;
    Guard := ' AND ' + Guard;
  end;
  Result := WriteViewChecklistField(T, BoardId, CardId, ChecklistId, ItemId, 'assigneeId', Literal, Error, Guard);
end;

function SortViewChecklistItems(const T: TWLTenant; const UserId, BoardId, CardId, ChecklistId: string;
  Fields: TStrings; out Error: string): Integer;
var Order: TJSONArray; I: Integer; Id, Scope, Entries, Valid, Positions, FromId, MovedId, WriteScope, Destination, SourceScope, ExtraGuard: string;
begin
  if ChecklistId = '' then begin Error := 'Checklist not found'; Exit(404); end;
  Result := ViewChecklistScope(T, UserId, BoardId, CardId, ChecklistId, '', Error);
  if Result <> 200 then Exit;
  if not BoardAllows(T.Db, BoardId, 'allowsChecklistItemDragging') then
  begin Error := 'This board does not allow checklist item dragging'; Exit(403); end;
  FromId := Fields.Values['from'];
  MovedId := Fields.Values['moved'];
  if (FromId <> '') or (MovedId <> '') then
  begin
    if (FromId = '') or (MovedId = '') or (FromId = ChecklistId) or (Pos(#0,FromId+MovedId)>0) then
    begin Error := 'Invalid checklist move'; Exit(400); end;
    Result := ViewChecklistScope(T,UserId,BoardId,CardId,FromId,MovedId,Error);
    if Result <> 200 then Exit;
  end;
  Order := TJSONArray.Create;
  try
    for I := 0 to Fields.Count - 1 do
      if Fields.Names[I] = 'item' then
      begin
        Id := Fields.ValueFromIndex[I];
        if (Id = '') or (Pos(#0, Id) > 0) then begin Error := 'Invalid checklist item order'; Exit(400); end;
        Order.Add(Id);
      end;
    Entries := 'json_each(' + QuotedStr(Order.AsJSON) + ')';
  finally Order.Free; end;
  Scope := 'checklistId=' + QuotedStr(ChecklistId) + ' AND cardId=' + QuotedStr(CardId) +
    ' AND (boardId IS NULL OR boardId=' + QuotedStr(BoardId) + ')';
  WriteScope:=Scope;
  Destination:='';
  ExtraGuard:='';
  if MovedId<>'' then
  begin
    SourceScope:='checklistId='+QuotedStr(FromId)+' AND cardId='+QuotedStr(CardId)+
      ' AND (boardId IS NULL OR boardId='+QuotedStr(BoardId)+') AND id='+QuotedStr(MovedId);
    WriteScope:='('+Scope+') OR ('+SourceScope+')';
    Destination:='checklistId='+QuotedStr(ChecklistId)+',';
    ExtraGuard:=' AND EXISTS(SELECT 1 FROM checklists WHERE id='+QuotedStr(FromId)+' AND cardId='+QuotedStr(CardId)+
      ' AND (boardId IS NULL OR boardId='+QuotedStr(BoardId)+'))'+
      ' AND EXISTS(SELECT 1 FROM checklist_items WHERE '+SourceScope+')';
  end;
  Valid := 'EXISTS(SELECT 1 FROM cards WHERE id=' + QuotedStr(CardId) + ' AND boardId=' + QuotedStr(BoardId) +
    ' AND deletedAt IS NULL) AND EXISTS(SELECT 1 FROM checklists WHERE id=' + QuotedStr(ChecklistId) +
    ' AND cardId=' + QuotedStr(CardId) + ' AND (boardId IS NULL OR boardId=' + QuotedStr(BoardId) +
    ')) AND (SELECT count(*) FROM ' + Entries + ')=(SELECT count(*) FROM checklist_items WHERE ' + WriteScope +
    ') AND (SELECT count(*) FROM checklist_items WHERE (' + WriteScope + ') AND id IN (SELECT value FROM ' + Entries +
    '))=(SELECT count(*) FROM ' + Entries + ')' + ExtraGuard;
  if Length(T.Db.Query('SELECT 1 WHERE ' + Valid + ';')) <> 1 then
  begin Error := 'Invalid checklist item order'; Exit(400); end;
  Positions := '(SELECT key FROM ' + Entries + ' WHERE value=checklist_items.id)';
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN ' + Valid +
    ' THEN 1 ELSE json(''Checklist scope changed'') END; UPDATE checklist_items SET ' + Destination + 'sort=' + Positions +
    ',modifiedAt=' + QuotedStr(NowIso) + ' WHERE ' + WriteScope +
    '; SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM checklist_items WHERE ' + Scope +
    ' AND sort IS NOT ' + Positions + ')' + IfThen(MovedId<>'',' AND EXISTS(SELECT 1 FROM checklist_items WHERE '+
      Scope+' AND id='+QuotedStr(MovedId)+')','') + ' THEN 1 ELSE json(''Checklist sort failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;'); Error := 'Could not reorder checklist items'; Exit(500); end;
end;

// GET checklists of a card / POST create a checklist
procedure ApiCardChecklists(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, CardId, Title, Id, Due, Sql, Stamp, ItemTitle: string;
  Body:TJSONObject;Value,Items,Item:TJSONData;i,Count:Integer;Rows:TWLRows;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  CardId  := aRequest.RouteParams['cardId'];
  if aRequest.Method = 'POST' then
  begin
    Body:=nil;
    try
      try
        if Pos('application/json',LowerCase(aRequest.ContentType))=1 then Body:=ExactObject(aRequest.Content)
        else
        begin
          Body:=TJSONObject.Create;
          for i:=0 to aRequest.ContentFields.Count-1 do
            Body.Add(aRequest.ContentFields.Names[i],aRequest.ContentFields.ValueFromIndex[i]);
        end;
        Title:='Checklist';Value:=Body.Find('title');
        if Value<>nil then
        begin
          if (Value.JSONType<>jtString) or (Trim(Value.AsString)='') or (Pos(#0,Value.AsString)>0) then
            raise Exception.Create('Invalid checklist title');
          Title:=Value.AsString;
        end;
        Due:='NULL';Value:=Body.Find('dueAt');
        if (Value<>nil) and not ChecklistDeadlineSql(Value,Due) then raise Exception.Create('Invalid deadline');
        Items:=Body.Find('items');Count:=0;
        if (Items<>nil) and (Items.JSONType<>jtNull) then
          case Items.JSONType of
            jtArray: Count:=Items.Count;
            jtString: if Items.AsString<>'' then Count:=1;
            else raise Exception.Create('Invalid checklist items');
          end;
        Id:=NewId;Stamp:=QuotedStr(NowIso);
        Sql:='BEGIN IMMEDIATE; INSERT INTO checklists(id,cardId,boardId,title,sort,createdAt,modifiedAt,dueAt) VALUES('+
          QuotedStr(Id)+','+QuotedStr(CardId)+','+QuotedStr(BoardId)+','+QuotedStr(Title)+',0,'+Stamp+','+Stamp+','+Due+'); ';
        for i:=0 to Count-1 do
        begin
          Item:=Items;if Items.JSONType=jtArray then Item:=Items.Items[i];
          if (Item.JSONType<>jtString) or (Pos(#0,Item.AsString)>0) then raise Exception.Create('Invalid checklist item');
          ItemTitle:=Item.AsString;
          Sql:=Sql+'INSERT INTO checklist_items(id,checklistId,cardId,boardId,title,sort,createdAt,modifiedAt) VALUES('+
            QuotedStr(NewId)+','+QuotedStr(Id)+','+QuotedStr(CardId)+','+QuotedStr(BoardId)+','+
            QuotedStr(ItemTitle)+','+IntToStr(i)+','+Stamp+','+Stamp+'); ';
        end;
      except SendJson(aResponse,'{"error":"Invalid checklist title, items or dueAt"}',400);Exit;end;
      if not T.Db.Exec(Sql+'COMMIT;') then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create checklist');Exit;end;
      SendJson(aResponse,Format('{"_id":%s}',[AnsiQuotedStr(Id,'"')]));
    finally Body.Free;end;
    Exit;
  end;
  Rows:=T.Db.Query(ChecklistCollectionSql(BoardId,CardId));
  if Length(Rows)=1 then SendJson(aResponse,Rows[0][0])
  else SendError(aResponse,500,'Could not read checklists');
end;

function ChecklistChanges(Request:TRequest;out Changes:string;ItemUpdate:Boolean=False):Boolean;
var Body:TJSONObject;Title,Deadline,Finished:TJSONData;Literal:string;
begin
  Changes:='';Result:=False;Body:=nil;
  try
    try
      if Pos('application/json',LowerCase(Request.ContentType))=1 then Body:=ExactObject(Request.Content)
      else
      begin
        Body:=TJSONObject.Create;
        if Request.ContentFields.IndexOfName('title')>=0 then Body.Add('title',Request.ContentFields.Values['title']);
        if Request.ContentFields.IndexOfName('isFinished')>=0 then Body.Add('isFinished',Request.ContentFields.Values['isFinished']);
        if Request.ContentFields.IndexOfName('dueAt')>=0 then Body.Add('dueAt',Request.ContentFields.Values['dueAt']);
      end;
      Title:=Body.Find('title');Deadline:=Body.Find('dueAt');
      if Title<>nil then
      begin
        if (Title.JSONType<>jtString) or (Trim(Title.AsString)='') or (Pos(#0,Title.AsString)>0) then Exit;
        Changes:='title='+QuotedStr(Title.AsString);
      end;
      if Deadline<>nil then
      begin
        if not ChecklistDeadlineSql(Deadline,Literal) then Exit;
        if Changes<>'' then Changes:=Changes+',';
        Changes:=Changes+'dueAt='+Literal;
      end;
      Finished:=Body.Find('isFinished');
      if ItemUpdate and (Finished<>nil) then
      begin
        if not (LowerCase(Finished.AsString)='true') and not (LowerCase(Finished.AsString)='false') and
          not (Finished.AsString='0') and not (Finished.AsString='1') then Exit;
        if Changes<>'' then Changes:=Changes+',';
        Changes:=Changes+'isFinished='+IntToStr(BoolInt(Finished.AsString));
      end;
      Result:=ItemUpdate or (Changes<>'');
    except Result:=False;end;
  finally Body.Free;end;
end;

// GET one checklist with its items
procedure ApiChecklist(aRequest: TRequest; aResponse: TResponse);
const CardScopeError = '{"error":"Card not found or does not belong to the specified board"}';
  NotFound = '{"error":"Checklist not found or does not belong to the specified card"}';
var T: TWLTenant; UserId, BoardId, CardId, ChecklistId, Predicate, Changes, Statement, FinalCheck: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];CardId:=aRequest.RouteParams['cardId'];
  if aRequest.Method='GET' then
  begin
    if not ApiAuthBoard(T,aResponse,UserId,BoardId,False) then Exit;
    if (CardId='') or not ApiChildrenBelong(T.Db,BoardId,'','',CardId,'','','','') then
    begin SendJson(aResponse,CardScopeError,404);Exit;end;
  end
  else if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  ChecklistId := aRequest.RouteParams['checklistId'];
  if aRequest.Method <> 'GET' then
  begin
    Predicate := 'id='+QuotedStr(ChecklistId)+' AND cardId='+QuotedStr(aRequest.RouteParams['cardId'])+
      ' AND (boardId IS NULL OR boardId='+QuotedStr(aRequest.RouteParams['boardId'])+')';
    if aRequest.Method='PUT' then
    begin
      if not ChecklistChanges(aRequest,Changes) then
      begin SendJson(aResponse,'{"error":"Valid title or dueAt is required"}',400);Exit;end;
      Statement:='UPDATE checklists SET '+Changes+' WHERE '+Predicate;
      FinalCheck:='(SELECT count(*) FROM checklists WHERE '+Predicate+')=1';
    end else
    begin
      Statement:='DELETE FROM checklists WHERE '+Predicate;
      FinalCheck:='NOT EXISTS(SELECT 1 FROM checklists WHERE '+Predicate+')';
    end;
    if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM checklists WHERE '+
      Predicate+')=1 THEN 1 ELSE json(''Checklist scope changed'') END; '+Statement+
      '; SELECT CASE WHEN '+FinalCheck+' THEN 1 ELSE json(''Checklist write failed'') END; COMMIT;') then
    begin T.Db.Exec('ROLLBACK;'); SendError(aResponse,500,'Could not change checklist');Exit;end;
    O:=TJSONObject.Create(['_id',ChecklistId]);
    try SendJson(aResponse,O.AsJSON);finally O.Free;end;
    Exit;
  end;
  R:=T.Db.Query(ChecklistReadSql(BoardId,CardId,ChecklistId)+';');
  if Length(R)=1 then SendJson(aResponse,R[0][0])
  else SendJson(aResponse,NotFound,404);
end;

// POST add an item to a checklist
procedure ApiChecklistItems(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, BoardId, CardId, ChecklistId, Title, Id, Due: string;
  Body:TJSONObject;Value:TJSONData;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId     := aRequest.RouteParams['boardId'];
  CardId      := aRequest.RouteParams['cardId'];
  ChecklistId := aRequest.RouteParams['checklistId'];
  Title:=BodyField(aRequest,'title');Due:='NULL';Body:=nil;
  try
    try
      if Pos('application/json',LowerCase(aRequest.ContentType))=1 then
      begin
        Body:=ExactObject(aRequest.Content);
        Value:=Body.Find('title');
        if (Value=nil) or (Value.JSONType<>jtString) then raise Exception.Create('Invalid item title');
        Title:=Value.AsString;
        Value:=Body.Find('dueAt');
        if (Value<>nil) and not ChecklistDeadlineSql(Value,Due) then raise Exception.Create('Invalid deadline');
      end else if aRequest.ContentFields.IndexOfName('dueAt')>=0 then
      begin
        Value:=TJSONString.Create(aRequest.ContentFields.Values['dueAt']);
        try
          if not ChecklistDeadlineSql(Value,Due) then raise Exception.Create('Invalid deadline');
        finally Value.Free;end;
      end;
      if (Trim(Title)='') or (Pos(#0,Title)>0) then raise Exception.Create('Invalid item title');
    except SendJson(aResponse,'{"error":"Invalid item title or dueAt"}',400);Exit;end;
  finally Body.Free;end;
  Id := NewId;
  if not T.Db.Exec(Format(
    'BEGIN IMMEDIATE; INSERT INTO checklist_items(id,checklistId,cardId,boardId,title,sort,createdAt,modifiedAt,dueAt) ' +
    'VALUES(%s,%s,%s,%s,%s,0,%s,%s,%s); COMMIT;',
    [QuotedStr(Id), QuotedStr(ChecklistId), QuotedStr(CardId), QuotedStr(BoardId),
     QuotedStr(Title), QuotedStr(NowIso), QuotedStr(NowIso),Due])) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not create checklist item');Exit;end;
  SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
end;

// GET item / PUT toggle-or-edit (isFinished/title) / DELETE a checklist item
procedure ApiChecklistItem(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, ItemId, Changes, Predicate: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  ItemId := aRequest.RouteParams['item'];
  if aRequest.Method = 'DELETE' then
  begin
    T.Db.Exec(Format('DELETE FROM checklist_items WHERE id=%s;', [QuotedStr(ItemId)]));
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(ItemId, '"')]));
    Exit;
  end;
  if aRequest.Method = 'PUT' then
  begin
    if not ChecklistChanges(aRequest,Changes,True) then
    begin SendJson(aResponse,'{"error":"Invalid checklist item update"}',400);Exit;end;
    if Changes<>'' then
    begin
      Predicate:='id='+QuotedStr(ItemId)+' AND checklistId='+QuotedStr(aRequest.RouteParams['checklistId'])+
        ' AND cardId='+QuotedStr(aRequest.RouteParams['cardId'])+' AND (boardId IS NULL OR boardId='+QuotedStr(aRequest.RouteParams['boardId'])+')';
      if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM checklist_items WHERE '+
        Predicate+')=1 THEN 1 ELSE json(''Checklist item scope changed'') END; UPDATE checklist_items SET '+
        Changes+',modifiedAt='+QuotedStr(NowIso)+' WHERE '+Predicate+'; COMMIT;') then
      begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not update checklist item');Exit;end;
    end;
    O:=TJSONObject.Create(['_id',ItemId]);
    try SendJson(aResponse,O.AsJSON);finally O.Free;end;
    Exit;
  end;
  R := T.Db.Query(Format('SELECT id,title,isFinished,dueAt FROM checklist_items WHERE id=%s LIMIT 1;',
    [QuotedStr(ItemId)]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'Item not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('title', R[0][1]); O.Add('isFinished', R[0][2] = '1');
    if R[0][3]='' then O.Add('dueAt',TJSONNull.Create) else O.Add('dueAt',R[0][3]);
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

// GET comments of a card / POST add a comment
procedure ApiCardComments(aRequest: TRequest; aResponse: TResponse);
var
  T: TWLTenant; UserId, BoardId, CardId, Author, Text1, Id: string;
  R: TWLRows; A: TJSONArray; O: TJSONObject; i: Integer;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  BoardId := aRequest.RouteParams['boardId'];
  CardId  := aRequest.RouteParams['cardId'];
  if aRequest.Method = 'POST' then
  begin
    Author := BodyField(aRequest, 'authorId'); if Author = '' then Author := UserId;
    if not ValidAuthor(T.Db,BoardId,UserId,Author) then
    begin SendError(aResponse,403,'Invalid author attribution'); Exit; end;
    Text1  := BodyField(aRequest, 'comment');
    Id := NewId;
    T.Db.Exec(Format(
      'INSERT INTO card_comments(id,boardId,cardId,userId,text,createdAt,modifiedAt) ' +
      'VALUES(%s,%s,%s,%s,%s,%s,%s);',
      [QuotedStr(Id), QuotedStr(BoardId), QuotedStr(CardId), QuotedStr(Author),
       QuotedStr(Text1), QuotedStr(NowIso), QuotedStr(NowIso)]));
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(Id, '"')]));
    Exit;
  end;
  R := T.Db.Query(Format(
    'SELECT id,text FROM card_comments WHERE cardId=%s ORDER BY createdAt;', [QuotedStr(CardId)]));
  A := TJSONArray.Create;
  try
    for i := 0 to High(R) do
      if Length(R[i]) >= 2 then
      begin
        O := TJSONObject.Create;
        O.Add('_id', R[i][0]); O.Add('comment', R[i][1]);
        A.Add(O);
      end;
    SendJson(aResponse, A.AsJSON);
  finally A.Free; end;
end;

// GET one comment / DELETE one comment
procedure ApiCardComment(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, CommentId: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  CommentId := aRequest.RouteParams['commentId'];
  if aRequest.Method = 'DELETE' then
  begin
    T.Db.Exec(Format('DELETE FROM card_comments WHERE id=%s;', [QuotedStr(CommentId)]));
    SendJson(aResponse, Format('{"_id":%s}', [AnsiQuotedStr(CommentId, '"')]));
    Exit;
  end;
  R := T.Db.Query(Format('SELECT id,text,userId FROM card_comments WHERE id=%s LIMIT 1;',
    [QuotedStr(CommentId)]));
  if Length(R) = 0 then begin SendError(aResponse, 404, 'Comment not found'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('_id', R[0][0]); O.Add('comment', R[0][1]); O.Add('authorId', R[0][2]);
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

// Dedicated member and assignee routes record history only for actual changes.
// The guarded transaction that puts TargetId on the card or takes them off
// (TableName card_members or card_assignees), with its join/unjoin activity;
// Scope selects the one card.
function CardAssignmentSql(Db:TWLDb;const Actor,BoardId,CardId,Scope,TableName,ActivityNoun,ActivityKey,TargetId:string;
  Remove:Boolean):string;
var Target,Pair,Present,Changing,ActivityType,ActivityId,Stamp,Mutation,FinalState,TargetGuard,Notify:string;R:TWLRows;
begin
  Target:=QuotedStr(TargetId);
  Pair:='cardId='+QuotedStr(CardId)+' AND userId='+Target;
  Present:='EXISTS(SELECT 1 FROM '+TableName+' WHERE '+Pair+')';
  TargetGuard:='';
  if Remove then
  begin
    ActivityType:='unjoin'+ActivityNoun;Changing:=Present;FinalState:='NOT '+Present;
    Mutation:='DELETE FROM '+TableName+' WHERE '+Pair+'; ';
  end
  else
  begin
    TargetGuard:='SELECT CASE WHEN EXISTS(SELECT 1 FROM users u JOIN board_members m ON m.userId=u.id '+
      'WHERE u.id='+Target+' AND COALESCE(u.loginDisabled,0)=0 AND m.boardId='+QuotedStr(BoardId)+
      ' AND m.isActive=1) THEN 1 ELSE json(''Assignment target changed'') END; ';
    ActivityType:='join'+ActivityNoun;Changing:='NOT '+Present;FinalState:=Present;
    Mutation:='INSERT INTO '+TableName+'(cardId,userId) SELECT '+QuotedStr(CardId)+','+Target+
      ' WHERE '+Changing+'; ';
  end;
  ActivityId:=NewId;Stamp:=QuotedStr(NowIso);
  // The notifications of the activity, when the change writes one.
  R:=Db.Query('SELECT COALESCE(listId,'''') FROM cards WHERE id='+QuotedStr(CardId)+';');
  Notify:='';
  if Length(R)=1 then Notify:=NotificationsSql(Db,Actor,BoardId,R[0][0],CardId,'',ActivityId,ActivityType,TargetId);
  ActivityId:=QuotedStr(ActivityId);
  Result:='BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+
    ')=1 THEN 1 ELSE json(''Card scope changed'') END; '+TargetGuard+
    'INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) SELECT '+
    ActivityId+','+QuotedStr(ActivityType)+','+QuotedStr(Actor)+',boardId,id,listId,swimlaneId,'+Stamp+','+Stamp+
    ',json_patch(json_object('+QuotedStr(ActivityKey)+','+Target+'),json_object(''username'',(SELECT username FROM users WHERE id='+Target+
    '))) FROM cards WHERE '+Scope+' AND '+Changing+'; '+
    'SELECT CASE WHEN NOT ('+Changing+') OR EXISTS(SELECT 1 FROM activities WHERE id='+ActivityId+
    ') THEN 1 ELSE json(''Assignment activity missing'') END; '+Mutation+
    'SELECT CASE WHEN '+FinalState+' THEN 1 ELSE json(''Assignment change failed'') END; '+Notify+'COMMIT;';
end;

procedure ChangeCardAssignment(aRequest:TRequest;aResponse:TResponse;
  const RouteKey,TableName,ActivityNoun,ActivityKey:string);
var T:TWLTenant;Actor,CardId,BoardId,ListId,TargetId,Scope:string;Remove:Boolean;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,Actor,CardNotFound) then Exit;
  CardId:=aRequest.RouteParams['cardId'];BoardId:=aRequest.RouteParams['boardId'];
  ListId:=aRequest.RouteParams['listId'];TargetId:=aRequest.RouteParams[RouteKey];
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+
    ' AND listId='+QuotedStr(ListId)+' AND deletedAt IS NULL';
  Remove:=aRequest.Method='DELETE';
  if not Remove and not EnabledBoardMember(T.Db,BoardId,TargetId) then
  begin SendJson(aResponse,'{"error":"userId is not an active member of this board"}',400);Exit;end;
  if not T.Db.Exec(CardAssignmentSql(T.Db,Actor,BoardId,CardId,Scope,TableName,ActivityNoun,ActivityKey,TargetId,Remove)) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not update card membership');Exit;end;
  SendCardById(aResponse,T.Db,CardId,Actor,False,BoardId);
end;

procedure ApiCardMember(aRequest:TRequest;aResponse:TResponse);
begin
  ChangeCardAssignment(aRequest,aResponse,'member','card_members','Member','memberId');
end;

procedure ApiCardAssignee(aRequest:TRequest;aResponse:TResponse);
begin
  ChangeCardAssignment(aRequest,aResponse,'assignee','card_assignees','Assignee','assigneeId');
end;

function BoardAllows(Db:TWLDb;const BoardId,Setting:string):Boolean;
var R:TWLRows;
begin
  R:=Db.Query('SELECT COALESCE(json_extract(settings_json,'+QuotedStr('$.'+Setting)+'),1) FROM boards WHERE id='+
    QuotedStr(BoardId)+';');
  Result:=(Length(R)<>1) or ((R[0][0]<>'0') and (R[0][0]<>''));
end;

function BoardCanEditCardText(Db:TWLDb;const UserId,BoardId:string):Boolean;
begin
  Result:=(UserId<>'') and (BoardId<>'') and BoardCanWrite(Db,UserId,BoardId) and
    (Length(Db.Query('SELECT 1 FROM board_members WHERE boardId='+QuotedStr(BoardId)+' AND userId='+QuotedStr(UserId)+
      ' AND isActive=1 AND COALESCE(isWorker,0)=1;'))=0);
end;

function ViewCardScope(const T:TWLTenant;const UserId,BoardId,CardId:string;out Error:string):Integer;
begin
  Error:='';
  if (BoardId='') or (CardId='') or (Pos(#0,BoardId+CardId)>0) then begin Error:='Card not found';Exit(404);end;
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  if not ApiChildrenBelong(T.Db,BoardId,'','',CardId,'','','','') then begin Error:='Card not found';Exit(404);end;
  Result:=200;
end;

function ToggleViewCardMember(const T:TWLTenant;const UserId,BoardId,CardId,MemberId:string;out Error:string):Integer;
var Scope:string;Remove:Boolean;
begin
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  if (MemberId='') or (Pos(#0,MemberId)>0) then begin Error:='Member not found';Exit(404);end;
  Remove:=Length(T.Db.Query('SELECT 1 FROM card_members WHERE cardId='+QuotedStr(CardId)+' AND userId='+QuotedStr(MemberId)+';'))=1;
  if not Remove and not EnabledBoardMember(T.Db,BoardId,MemberId) then
  begin Error:='userId is not an active member of this board';Exit(400);end;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  if not T.Db.Exec(CardAssignmentSql(T.Db,UserId,BoardId,CardId,Scope,'card_members','Member','memberId',MemberId,Remove)) then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not update card membership';Exit(500);end;
end;

function SetViewCardText(const T:TWLTenant;const UserId,BoardId,CardId,Column,Value:string;out Error:string):Integer;
var Scope,Stamp,Old:string;
begin
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  if not BoardCanEditCardText(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  if Pos(#0,Value)>0 then begin Error:='Invalid value';Exit(400);end;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  Stamp:=QuotedStr(NowIso);
  Old:=CardTextOf(T.Db,CardId,Column);
  if not T.Db.Exec('BEGIN IMMEDIATE; '+CardTextActivitySql(UserId,Scope,Column,Value)+'UPDATE cards SET '+Column+'='+QuotedStr(Value)+',modifiedAt='+Stamp+
    ',dateLastActivity='+Stamp+' WHERE '+Scope+'; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+
    ' AND '+Column+'='+QuotedStr(Value)+')=1 THEN 1 ELSE json(''Card write failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not update card';Exit(500);end;
  RecordCardTextHistory(T.Db,UserId,BoardId,CardId,Column,Old,Value);
end;

function SetViewCardPerson(const T:TWLTenant;const UserId,BoardId,CardId,Field,Value:string;out Error:string):Integer;
var Setting:string;
begin
  // Only WeKan's two, each on a board that shows it.
  Error:='';
  if Field='requestedBy' then Setting:='allowsRequestedBy'
  else if Field='assignedBy' then Setting:='allowsAssignedBy'
  else begin Error:='this field is not yours to change';Exit(403);end;
  if Length(Value)>1000 then begin Error:='Invalid value';Exit(400);end;
  if (BoardId<>'') and not BoardAllows(T.Db,BoardId,Setting) then
  begin Error:='this field is not yours to change';Exit(403);end;
  Result:=SetViewCardText(T,UserId,BoardId,CardId,Field,Trim(Value),Error);
end;

// Whether the card's <Path>.end - a date as an ISO string, milliseconds, or
// {"$date": ...} - is before now.
function CardEndedSql(const Path:string):string;
var Ms,Iso,P:string;
begin
  Ms:=IntToStr(UnixMillis(LocalTimeToUniversal(Now)));Iso:=QuotedStr(NowIso);P:='''$.'+Path+'.end''';
  Result:='CASE json_type(extra_json,'+P+') WHEN ''text'' THEN json_extract(extra_json,'+P+')<'+Iso+
    ' WHEN ''integer'' THEN json_extract(extra_json,'+P+')<'+Ms+' WHEN ''real'' THEN json_extract(extra_json,'+P+')<'+Ms+
    ' WHEN ''object'' THEN COALESCE(json_extract(extra_json,''$.'+Path+'.end."$date"'')<'+Iso+',0) ELSE 0 END';
end;

function ReadCardVote(Db:TWLDb;const UserId,BoardId,CardId:string):TCardVote;
var Rows:TWLRows;U,Ended:string;
begin
  Result:=Default(TCardVote);
  if (UserId='') or (CardId='') or (Pos(#0,UserId+BoardId+CardId)>0) then Exit;
  U:=QuotedStr(UserId);
  Ended:=CardEndedSql('vote');
  Rows:=Db.Query('SELECT COALESCE(json_extract(extra_json,''$.vote.question''),''''),'+
    'COALESCE(json_extract(extra_json,''$.vote.public''),0),'+
    'COALESCE(json_extract(extra_json,''$.vote.allowNonBoardMembers''),0),'+
    '(SELECT count(*) FROM json_each(extra_json,''$.vote.positive'')),'+
    '(SELECT count(*) FROM json_each(extra_json,''$.vote.negative'')),'+
    'EXISTS(SELECT 1 FROM json_each(extra_json,''$.vote.positive'') WHERE value='+U+'),'+
    'EXISTS(SELECT 1 FROM json_each(extra_json,''$.vote.negative'') WHERE value='+U+'),'+Ended+
    ' FROM cards WHERE id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+
    ' AND deletedAt IS NULL AND json_valid(extra_json);');
  if (Length(Rows)<>1) or (Rows[0][0]='') then Exit;
  Result.Present:=True;
  Result.Question:=Rows[0][0];
  Result.IsPublic:=Rows[0][1]='1';
  Result.Positive:=StrToIntDef(Rows[0][3],0);
  Result.Negative:=StrToIntDef(Rows[0][4],0);
  Result.ForIt:=Rows[0][5]='1';
  Result.Against:=Rows[0][6]='1';
  Result.CanVote:=(Rows[0][7]<>'1') and (EnabledBoardMember(Db,BoardId,UserId) or
    ((Rows[0][2]='1') and BoardCanRead(Db,UserId,BoardId)));
end;

function VoteViewCard(const T:TWLTenant;const UserId,BoardId,CardId,Side:string;out Error:string):Integer;
var V:TCardVote;Scope,Owned,Stamp,U,Add,Drop,Without:string;
begin
  Error:='';
  if (Side<>'positive') and (Side<>'negative') then begin Error:='Invalid vote';Exit(400);end;
  if (BoardId='') or (CardId='') or (UserId='') or (Pos(#0,BoardId+CardId+UserId)>0) or
    not BoardCanRead(T.Db,UserId,BoardId) or
    not ApiChildrenBelong(T.Db,BoardId,'','',CardId,'','','','') then begin Error:='Card not found';Exit(404);end;
  V:=ReadCardVote(T.Db,UserId,BoardId,CardId);
  if not (V.Present and V.CanVote) then begin Error:='this vote is not open to you';Exit(403);end;
  U:=QuotedStr(UserId);
  Without:='(SELECT json_group_array(value) FROM json_each(extra_json,''$.vote.%s'') WHERE value<>'+U+')';
  if Side='positive' then begin Add:='positive';Drop:='negative';end else begin Add:='negative';Drop:='positive';end;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  // json_each has an id of its own: the card's columns by name.
  Owned:='cards.id='+QuotedStr(CardId)+' AND cards.boardId='+QuotedStr(BoardId)+' AND cards.deletedAt IS NULL';
  Stamp:=QuotedStr(NowIso);
  if (not V.ForIt and not V.Against) or (V.Against and (Side='positive')) or (V.ForIt and (Side='negative')) then
    // $pull the other side, $addToSet this one.
    Result:=Ord(T.Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET extra_json=json_set(extra_json,''$.vote.'+Drop+''',json('+
      Format(Without,[Drop])+'),''$.vote.'+Add+''',json_insert(json('+Format(Without,[Add])+'),''$[#]'','+U+')),modifiedAt='+
      Stamp+',dateLastActivity='+Stamp+' WHERE '+Scope+'; SELECT CASE WHEN EXISTS(SELECT 1 FROM cards,json_each(cards.extra_json,''$.vote.'+
      Add+''') WHERE '+Owned+' AND value='+U+') THEN 1 ELSE json(''Vote failed'') END; COMMIT;'))
  else
    // The same side again: $pull from both.
    Result:=Ord(T.Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET extra_json=json_set(extra_json,''$.vote.positive'',json('+
      Format(Without,['positive'])+'),''$.vote.negative'',json('+Format(Without,['negative'])+')),modifiedAt='+Stamp+
      ',dateLastActivity='+Stamp+' WHERE '+Scope+'; SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM cards,json_each(cards.extra_json,''$.vote'') v,'+
      'json_each(v.value) WHERE '+Owned+' AND v.key IN (''positive'',''negative'') AND json_each.value='+U+
      ') THEN 1 ELSE json(''Vote failed'') END; COMMIT;'));
  if Result=1 then Result:=200
  else begin T.Db.Exec('ROLLBACK;');Error:='Could not vote';Result:=500;end;
end;

function CardWatching(Db:TWLDb;const UserId,CardId:string):Boolean;
begin
  Result:=(UserId<>'') and (Pos(#0,UserId+CardId)=0) and (Length(Db.Query('SELECT 1 FROM cards,json_each(cards.extra_json,''$.watchers'') w '+
    'WHERE cards.id='+QuotedStr(CardId)+' AND json_valid(cards.extra_json) AND w.value='+QuotedStr(UserId)+' LIMIT 1;'))=1);
end;

function BoardWatchLevel(Db:TWLDb;const UserId,BoardId:string):string;
var R:TWLRows;
begin
  Result:='muted';
  if (UserId='') or (Pos(#0,UserId+BoardId)>0) then Exit;
  R:=Db.Query('SELECT json_extract(w.value,''$.level'') FROM boards,json_each(boards.settings_json,''$.watchers'') w '+
    'WHERE boards.id='+QuotedStr(BoardId)+' AND json_valid(boards.settings_json) AND w.type=''object'' AND '+
    'json_extract(w.value,''$.userId'')='+QuotedStr(UserId)+' LIMIT 1;');
  if (Length(R)=1) and ((R[0][0]='watching') or (R[0][0]='tracking')) then Result:=R[0][0];
end;

function WatchViewCard(const T:TWLTenant;const UserId,BoardId,CardId:string;out Error:string):Integer;
var U,Scope,Owned,Others,Next,Negate:string;Watching:Boolean;
begin
  Error:='';
  if (BoardId='') or (CardId='') or (UserId='') or (Pos(#0,BoardId+CardId+UserId)>0) or
    not BoardCanRead(T.Db,UserId,BoardId) or
    not ApiChildrenBelong(T.Db,BoardId,'','',CardId,'','','','') then begin Error:='Card not found';Exit(404);end;
  U:=QuotedStr(UserId);
  // An assigned-only member: only a card assigned to them.
  if Length(T.Db.Query('SELECT 1 FROM board_members WHERE boardId='+QuotedStr(BoardId)+' AND userId='+U+
    ' AND isActive=1 AND (COALESCE(isNormalAssignedOnly,0)=1 OR COALESCE(isCommentAssignedOnly,0)=1 OR '+
    'COALESCE(isReadAssignedOnly,0)=1) AND NOT EXISTS(SELECT 1 FROM card_assignees WHERE cardId='+QuotedStr(CardId)+
    ' AND userId='+U+');'))=1 then begin Error:='Card not found';Exit(404);end;
  Watching:=CardWatching(T.Db,UserId,CardId);
  Others:='(SELECT json_group_array(value) FROM json_each(CASE WHEN json_type(extra_json,''$.watchers'')=''array'' '+
    'THEN json_extract(extra_json,''$.watchers'') ELSE ''[]'' END) WHERE value IS NOT '+U+')';
  if Watching then begin Next:='json('+Others+')';Negate:='NOT ';end
  else begin Next:='json_insert(json('+Others+'),''$[#]'','+U+')';Negate:='';end;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  Owned:='cards.id='+QuotedStr(CardId)+' AND cards.boardId='+QuotedStr(BoardId);
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET extra_json=json_set(extra_json,''$.watchers'','+Next+') WHERE '+Scope+
    ' AND json_valid(extra_json); SELECT CASE WHEN '+Negate+'EXISTS(SELECT 1 FROM cards,json_each(cards.extra_json,'+
    '''$.watchers'') w WHERE '+Owned+' AND w.value='+U+') THEN 1 ELSE json(''Watch failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not watch the card';Exit(500);end;
  Result:=200;
end;

function WatchViewBoard(const T:TWLTenant;const UserId,BoardId,Level:string;out Error:string):Integer;
var U,Others,Next:string;
begin
  Error:='';
  if (Level<>'watching') and (Level<>'tracking') and (Level<>'muted') then
  begin Error:='watching, tracking or muted';Exit(400);end;
  if (BoardId='') or (UserId='') or (Pos(#0,BoardId+UserId)>0) or not BoardCanRead(T.Db,UserId,BoardId) then
  begin Error:='Board not found';Exit(404);end;
  U:=QuotedStr(UserId);
  Others:='(SELECT json_group_array(json(value)) FROM json_each(CASE WHEN json_type(settings_json,''$.watchers'')=''array'' '+
    'THEN json_extract(settings_json,''$.watchers'') ELSE ''[]'' END) WHERE type<>''object'' OR json_extract(value,''$.userId'') IS NOT '+U+')';
  // setWatcher: the default level is no watcher.
  if Level='muted' then Next:='json('+Others+')'
  else Next:='json_insert(json('+Others+'),''$[#]'',json_object(''userId'','+U+',''level'','+QuotedStr(Level)+'))';
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE boards SET settings_json=json_set(settings_json,''$.watchers'','+Next+') WHERE id='+
    QuotedStr(BoardId)+' AND json_valid(settings_json); COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not watch the board';Exit(500);end;
  if BoardWatchLevel(T.Db,UserId,BoardId)<>Level then begin Error:='Could not watch the board';Exit(500);end;
  Result:=200;
end;

function ReadCardPoker(Db:TWLDb;const UserId,BoardId,CardId:string):TCardPoker;
var Rows:TWLRows;Voted:string;i:Integer;
begin
  Result:=Default(TCardPoker);
  if (UserId='') or (CardId='') or (Pos(#0,UserId+BoardId+CardId)>0) or not BoardAllows(Db,BoardId,'allowsPoker') then Exit;
  Voted:='''''';
  for i:=High(POKER_FIELDS) downto 0 do
    Voted:='CASE WHEN EXISTS(SELECT 1 FROM json_each(extra_json,''$.poker.'+POKER_FIELDS[i]+''') WHERE value='+
      QuotedStr(UserId)+') THEN '''+POKER_FIELDS[i]+''' ELSE '+Voted+' END';
  Rows:=Db.Query('SELECT CASE WHEN json_type(extra_json,''$.poker.question'')=''text'' THEN json_extract(extra_json,''$.poker.question'') ELSE '''' END,'+
    'COALESCE(json_extract(extra_json,''$.poker.allowNonBoardMembers''),0),'+CardEndedSql('poker')+','+Voted+
    ' FROM cards WHERE id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL AND json_valid(extra_json);');
  if (Length(Rows)<>1) or (Rows[0][0]='') then Exit;
  Result.Present:=True;
  Result.Question:=Rows[0][0];
  Result.Voted:=Rows[0][3];
  Result.CanVote:=(Rows[0][2]<>'1') and (EnabledBoardMember(Db,BoardId,UserId) or
    ((Rows[0][1]='1') and BoardCanRead(Db,UserId,BoardId)));
end;

function PokerViewCard(const T:TWLTenant;const UserId,BoardId,CardId,State:string;out Error:string):Integer;
var P:TCardPoker;U,Sets,Owned,Stamp:string;i:Integer;Known:Boolean;
begin
  Error:='';Known:=False;
  for i:=0 to High(POKER_FIELDS) do if POKER_FIELDS[i]=State then Known:=True;
  if not Known then begin Error:='Invalid Planning Poker card';Exit(400);end;
  if (BoardId='') or (CardId='') or (UserId='') or (Pos(#0,BoardId+CardId+UserId)>0) or
    not BoardCanRead(T.Db,UserId,BoardId) or
    not ApiChildrenBelong(T.Db,BoardId,'','',CardId,'','','','') then begin Error:='Card not found';Exit(404);end;
  P:=ReadCardPoker(T.Db,UserId,BoardId,CardId);
  if not (P.Present and P.CanVote) then begin Error:='this Planning Poker is not open to you';Exit(403);end;
  U:=QuotedStr(UserId);Sets:='';
  // setPoker: $pull from every other card, $addToSet to this one.
  for i:=0 to High(POKER_FIELDS) do
  begin
    if Sets<>'' then Sets:=Sets+',';
    Sets:=Sets+'''$.poker.'+POKER_FIELDS[i]+''',';
    if POKER_FIELDS[i]=State then Sets:=Sets+'json_insert(';
    Sets:=Sets+'json((SELECT json_group_array(value) FROM json_each(extra_json,''$.poker.'+POKER_FIELDS[i]+''') WHERE value<>'+U+'))';
    if POKER_FIELDS[i]=State then Sets:=Sets+',''$[#]'','+U+')';
  end;
  Owned:='cards.id='+QuotedStr(CardId)+' AND cards.boardId='+QuotedStr(BoardId)+' AND cards.deletedAt IS NULL';
  Stamp:=QuotedStr(NowIso);
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET extra_json=json_set(extra_json,'+Sets+'),modifiedAt='+Stamp+
    ',dateLastActivity='+Stamp+' WHERE id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+
    ' AND deletedAt IS NULL; SELECT CASE WHEN (SELECT count(*) FROM cards,json_each(cards.extra_json,''$.poker'') f,json_each(f.value) v '+
    'WHERE '+Owned+' AND f.type=''array'' AND v.value='+U+')=1 AND EXISTS(SELECT 1 FROM cards,json_each(cards.extra_json,''$.poker.'+
    State+''') v WHERE '+Owned+' AND v.value='+U+') THEN 1 ELSE json(''Planning Poker failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not play the card';Exit(500);end;
  Result:=200;
end;

// The attachment, of the card on the board, an image still there - a raster
// one, or an SVG, which is stored and served sanitized (src/wlsvg.pas).
function ViewImageAttachment(const T:TWLTenant;const BoardId,CardId,AttachmentId:string;out Error:string):Integer;
begin
  Error:='';
  if (AttachmentId='') or (Pos(#0,AttachmentId)>0) or (Length(T.Db.Query('SELECT 1 FROM attachments WHERE id='+QuotedStr(AttachmentId)+
    ' AND boardId='+QuotedStr(BoardId)+' AND cardId='+QuotedStr(CardId)+' AND '+LiveAttachmentSQL(T.Db)+';'))<>1) then begin Error:='Attachment not found';Exit(404);end;
  if Length(T.Db.Query('SELECT 1 FROM attachments WHERE id='+QuotedStr(AttachmentId)+
    ' AND type IN (''image/png'',''image/jpeg'',''image/gif'',''image/webp'',''image/svg+xml'');'))<>1 then
  begin Error:='Only an image is a cover or a background';Exit(400);end;
  Result:=200;
end;

function SetViewCardCover(const T:TWLTenant;const UserId,BoardId,CardId,AttachmentId:string;out Error:string):Integer;
var Scope,Next:string;
begin
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  Result:=ViewImageAttachment(T,BoardId,CardId,AttachmentId,Error);
  if Result<>200 then Exit;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  // The same image again takes the cover off.
  if Length(T.Db.Query('SELECT 1 FROM cards WHERE '+Scope+' AND coverId='+QuotedStr(AttachmentId)+';'))=1 then Next:=''''''
  else Next:=QuotedStr(AttachmentId);
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET coverId='+Next+' WHERE '+Scope+'; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+
    Scope+' AND COALESCE(coverId,'''')='+Next+')=1 THEN 1 ELSE json(''Cover failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not set the cover';Exit(500);end;
end;

function SetViewBoardBackground(const T:TWLTenant;const UserId,BoardId,CardId,AttachmentId:string;out Error:string):Integer;
var Url,NextUrl,NextId:string;
begin
  Error:='';
  if (BoardId='') or (UserId='') or (Pos(#0,BoardId+CardId+UserId)>0) or not BoardCanRead(T.Db,UserId,BoardId) then
  begin Error:='Board not found';Exit(404);end;
  if not BoardCanAdmin(T.Db,UserId,BoardId) then begin Error:='Only a board admin sets the background';Exit(403);end;
  Result:=ViewImageAttachment(T,BoardId,CardId,AttachmentId,Error);
  if Result<>200 then Exit;
  Url:='/cdn/storage/attachments/'+AttachmentId;
  if Length(T.Db.Query('SELECT 1 FROM boards WHERE id='+QuotedStr(BoardId)+' AND backgroundImageURL='+QuotedStr(Url)+';'))=1 then
  begin NextUrl:='''''';NextId:='''''';end
  else begin NextUrl:=QuotedStr(Url);NextId:=QuotedStr(AttachmentId);end;
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE boards SET backgroundImageURL='+NextUrl+',backgroundImageId='+NextId+' WHERE id='+
    QuotedStr(BoardId)+'; SELECT CASE WHEN (SELECT count(*) FROM boards WHERE id='+QuotedStr(BoardId)+' AND COALESCE(backgroundImageURL,'''')='+
    NextUrl+')=1 THEN 1 ELSE json(''Background failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not set the background';Exit(500);end;
end;

function ViewUsernameValid(const Username:string):Boolean;
var i:Integer;
begin
  Result:=(Length(Username)>=2) and (Length(Username)<=64);
  if Result then
    for i:=1 to Length(Username) do
      if not (Username[i] in ['A'..'Z','a'..'z','0'..'9','.','_','-']) then Exit(False);
end;

function ViewEmailValid(const Email:string):Boolean;
var At:Integer;
begin
  At:=Pos('@',Email);
  Result:=(Length(Email)<=254) and (At>1) and (Pos(' ',Email)=0) and (Pos(#9,Email)=0) and (Pos('@',Copy(Email,At+1,MaxInt))=0) and
    (Pos('.',Copy(Email,At+2,MaxInt))>0) and (Email[Length(Email)]<>'.') and (Pos(#0,Email)=0);
end;

// The guarded statement's start: the actor is an enabled site admin, of the
// accounts this store selects, and the target is one of them.
function ViewAdminGuard(const T:TWLTenant;const Actor,Target:string;out Scope,Bindings:string):string;
var Source:TSelectionScope;I:Integer;Admin:string;
begin
  Source:=TSelectionScope.Create(T.Db);
  try
    Scope:='id='+QuotedStr(Target)+' AND '+Source.StringField('users','id');
    Admin:='EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(Actor)+
      ' AND isAdmin=1 AND COALESCE(loginDisabled,0)=0 AND '+Source.StringField('users','id')+')';
    Bindings:='';
    for I:=0 to Source.Bindings.Count-1 do Bindings:=Bindings+Source.Bindings[I];
  finally Source.Free;end;
  Result:=AuthSourceCondition(T.Db)+' AND '+Admin;
end;

function AdminUpdateViewUser(const T:TWLTenant;const Actor,Target:string;Values:TStrings;Partial:Boolean;out Error:string):Integer;
var Scope,Bindings,Guard,Sets,Mutation,Username,Fullname,Initials,Email,Password,Profile,Hash:string;
  Rows:TWLRows;Revoke:Boolean;
  function Has(const Name:string):Boolean;
  begin Result:=not Partial or (Values.IndexOfName(Name)>=0);end;
begin
  Error:='';
  if (Actor='') or not IsSiteAdmin(T.Db,Actor) then begin Error:='Not found';Exit(404);end;
  if (Target='') or (Pos(#0,Target)>0) then begin Error:='User not found';Exit(404);end;
  Guard:=ViewAdminGuard(T,Actor,Target,Scope,Bindings);
  Rows:=T.Db.Query('SELECT username,COALESCE(authenticationMethod,'''') FROM users WHERE '+Scope+';');
  if Length(Rows)<>1 then begin Error:='User not found';Exit(404);end;
  Sets:='modifiedAt='+QuotedStr(NowIso);Mutation:='';Revoke:=False;
  Profile:='CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END';
  if Has('fullname') or Has('initials') then
  begin
    Fullname:=Trim(Values.Values['fullname']);Initials:=Trim(Values.Values['initials']);
    if (Length(Fullname)>200) or (Length(UTF8Decode(Initials))>8) or (Pos(#0,Fullname+Initials)>0) then
    begin Error:='error-user-notCreated';Exit(400);end;
    Sets:=Sets+',profile_json=json_set('+Profile+',''$.fullname'','+QuotedStr(Fullname)+',''$.initials'','+QuotedStr(Initials)+')';
  end;
  Username:=Trim(Values.Values['username']);
  if Has('username') and (Username<>'') and (Username<>Rows[0][0]) then
  begin
    if not ViewUsernameValid(Username) then begin Error:='error-user-notCreated';Exit(400);end;
    if Length(T.Db.Query('SELECT 1 FROM users WHERE username='+QuotedStr(Username)+' COLLATE NOCASE AND id<>'+QuotedStr(Target)+';'))>0 then
    begin Error:='error-username-taken';Exit(409);end;
    Sets:=Sets+',username='+QuotedStr(Username);
  end;
  Email:=LowerCase(Trim(Values.Values['email']));
  if Has('email') and (Email<>'') and (Length(T.Db.Query('SELECT 1 FROM user_emails WHERE userId='+QuotedStr(Target)+
    ' AND lower(address)='+QuotedStr(Email)+';'))=0) then
  begin
    if not ViewEmailValid(Email) then begin Error:='error-user-notCreated';Exit(400);end;
    if Length(T.Db.Query('SELECT 1 FROM user_emails WHERE lower(address)='+QuotedStr(Email)+';'))>0 then
    begin Error:='error-email-taken';Exit(409);end;
    Mutation:=Mutation+'DELETE FROM user_emails WHERE userId='+QuotedStr(Target)+'; INSERT INTO user_emails(userId,address,verified) VALUES('+
      QuotedStr(Target)+','+QuotedStr(Email)+','+IntToStr(Ord(Values.Values['verified']='true'))+'); ';
  end;
  if Target<>Actor then
  begin
    if Has('isAdmin') then Sets:=Sets+',isAdmin='+IntToStr(Ord(Values.Values['isAdmin']='true'));
    if Has('loginDisabled') then
    begin
      Sets:=Sets+',loginDisabled='+IntToStr(Ord(Values.Values['loginDisabled']='true'));
      Revoke:=Values.Values['loginDisabled']='true';
    end;
  end;
  Password:=Values.Values['password'];
  if Has('password') and (Password<>'') then
  begin
    if (Rows[0][1]<>'') and (Rows[0][1]<>'password') then begin Error:='This account uses an external sign-in provider.';Exit(400);end;
    if (Length(Password)>4096) or (Pos(#0,Password)>0) then begin Error:='error-password-policy';Exit(400);end;
    Hash:=HashMeteorPassword(Password);
    Sets:=Sets+',services_json=json_set(CASE WHEN json_valid(services_json) THEN services_json ELSE ''{}'' END,''$.password'',json('+
      QuotedStr(Hash)+'))';
    Revoke:=True;
  end;
  if Revoke then Mutation:=RevokeUserTokensSQL(T.Db,Target)+Mutation;
  if not T.Db.Exec('BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+Guard+' AND (SELECT count(*) FROM users WHERE '+Scope+
    ')=1 THEN 1 ELSE json(''User scope changed'') END; UPDATE users SET '+Sets+' WHERE '+Scope+'; '+Mutation+'COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not update account';Exit(500);end;
  Result:=200;
end;

function AdminCreateViewUser(const T:TWLTenant;const Actor,Fullname,Username,Initials,Password,IsAdmin,LoginDisabled,Email:string;
  out NewId,Error:string):Integer;
var Scope,Bindings,Guard,Stamp,Mail:string;
begin
  NewId:='';Error:='';
  if (Actor='') or not IsSiteAdmin(T.Db,Actor) then begin Error:='Only administrators can create users';Exit(403);end;
  if (Pos('/',Fullname+Username+Email+Initials)>0) or (Pos(#0,Fullname+Username+Email+Initials+Password)>0) then
  begin Error:='error-user-notCreated';Exit(400);end;
  if ((IsAdmin<>'true') and (IsAdmin<>'false')) or ((LoginDisabled<>'true') and (LoginDisabled<>'false')) then
  begin Error:='invalid-parameters';Exit(400);end;
  Mail:=LowerCase(Trim(Email));
  if not ViewUsernameValid(Username) or not ViewEmailValid(Mail) or (Length(Fullname)>200) or (Length(UTF8Decode(Initials))>8) then
  begin Error:='error-user-notCreated';Exit(400);end;
  if (Password='') or (Length(Password)>4096) then begin Error:='error-password-policy';Exit(400);end;
  if Length(T.Db.Query('SELECT 1 FROM users WHERE username='+QuotedStr(Username)+' COLLATE NOCASE;'))>0 then
  begin Error:='username-already-taken';Exit(409);end;
  if Length(T.Db.Query('SELECT 1 FROM user_emails WHERE lower(address)='+QuotedStr(Mail)+';'))>0 then
  begin Error:='email-already-taken';Exit(409);end;
  NewId:=Copy(NewAuthToken,1,17);
  Guard:=ViewAdminGuard(T,Actor,NewId,Scope,Bindings);
  Stamp:=QuotedStr(NowIso);
  if not T.Db.Exec('BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+Guard+' AND NOT EXISTS(SELECT 1 FROM users WHERE username='+
    QuotedStr(Username)+' COLLATE NOCASE) THEN 1 ELSE json(''User scope changed'') END; '+
    'INSERT INTO users(id,username,createdAt,modifiedAt,services_json,profile_json,isAdmin,loginDisabled) VALUES('+QuotedStr(NewId)+','+
    QuotedStr(Username)+','+Stamp+','+Stamp+','+QuotedStr('{"password":'+HashMeteorPassword(Password)+'}')+','+
    'json_object(''fullname'','+QuotedStr(Fullname)+',''initials'','+QuotedStr(Initials)+'),'+IntToStr(Ord(IsAdmin='true'))+','+
    IntToStr(Ord(LoginDisabled='true'))+'); INSERT INTO user_emails(userId,address,verified) VALUES('+QuotedStr(NewId)+','+QuotedStr(Mail)+
    ',0); SELECT CASE WHEN EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(NewId)+') THEN 1 ELSE json(''User creation failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');NewId:='';Error:='error-user-notCreated';Exit(500);end;
  Result:=200;
end;

function SetViewCardComplete(const T:TWLTenant;const UserId,BoardId,CardId:string;Done:Boolean;out Error:string):Integer;
var Scope,Stamp:string;OldDone:Boolean;
begin
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  OldDone:=CardCompletionOf(T.Db,Scope);
  Stamp:=QuotedStr(NowIso);
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET dueComplete='+IntToStr(Ord(Done))+',modifiedAt='+Stamp+' WHERE '+Scope+
    ' AND COALESCE(dueComplete,0)<>'+IntToStr(Ord(Done))+'; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+
    ' AND COALESCE(dueComplete,0)='+IntToStr(Ord(Done))+')=1 THEN 1 ELSE json(''Complete failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not update card';Exit(500);end;
  RecordCardCompletionHistory(T.Db,UserId,BoardId,CardId,OldDone,Done);
end;

function AccountSettingOn(Db:TWLDb;const Id:string):Boolean;
var Rows:TWLRows;
begin
  Result:=False;
  if Length(Db.Query('SELECT 1 FROM sqlite_master WHERE type=''table'' AND name=''_ferretdb_collections'';'))=0 then Exit;
  Rows:=Db.Query('SELECT table_name FROM _ferretdb_collections WHERE name=''accountSettings'';');
  if Length(Rows)<>1 then Exit;
  Rows:=Db.Query('SELECT json_extract(_ferretdb_sjson,''$.booleanValue'') FROM "'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+
    '" WHERE json_extract(_ferretdb_sjson,''$._id'')='+QuotedStr(Id)+' LIMIT 1;');
  Result:=(Length(Rows)=1) and (Rows[0][0]='1');
end;

function ViewMayChangeAccount(const T:TWLTenant;const Actor,Target,Setting:string):Boolean;
begin
  Result:=(Actor<>'') and (IsSiteAdmin(T.Db,Actor) or ((Actor=Target) and AccountSettingOn(T.Db,Setting)));
end;

function ViewSetUsername(const T:TWLTenant;const Actor,Target,Username:string;out Error:string):Integer;
var Scope,Bindings,Guard,Name:string;
begin
  Error:='';Name:=Trim(Username);
  if (Pos('/',Username+Target)>0) or (Pos(#0,Username+Target)>0) then begin Error:='not-authorized';Exit(400);end;
  if not ViewMayChangeAccount(T,Actor,Target,'accounts-allowUserNameChange') then begin Error:='not-authorized';Exit(403);end;
  if not ViewUsernameValid(Name) then begin Error:='invalid-username';Exit(400);end;
  if Length(T.Db.Query('SELECT 1 FROM users WHERE username='+QuotedStr(Name)+' COLLATE NOCASE;'))>0 then
  begin Error:='username-already-taken';Exit(409);end;
  Guard:=ViewAdminGuard(T,Actor,Target,Scope,Bindings);
  if not IsSiteAdmin(T.Db,Actor) then Guard:='1';
  if Length(T.Db.Query('SELECT 1 FROM users WHERE '+Scope+';'))<>1 then begin Error:='not-authorized';Exit(404);end;
  if not T.Db.Exec('BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+Guard+' AND NOT EXISTS(SELECT 1 FROM users WHERE username='+
    QuotedStr(Name)+' COLLATE NOCASE) THEN 1 ELSE json(''Username taken'') END; UPDATE users SET username='+QuotedStr(Name)+
    ',modifiedAt='+QuotedStr(NowIso)+' WHERE '+Scope+'; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='username-already-taken';Exit(409);end;
  Result:=200;
end;

function ViewSetEmail(const T:TWLTenant;const Actor,Target,Email:string;out Error:string):Integer;
var Mail:string;
begin
  Error:='';Mail:=LowerCase(Trim(Email));
  if (Pos('/',Email+Target)>0) or (Pos(#0,Email+Target)>0) then begin Error:='not-authorized';Exit(400);end;
  if not ViewMayChangeAccount(T,Actor,Target,'accounts-allowEmailChange') then begin Error:='not-authorized';Exit(403);end;
  if not ViewEmailValid(Mail) then begin Error:='invalid-email';Exit(400);end;
  if Length(T.Db.Query('SELECT 1 FROM users WHERE id='+QuotedStr(Target)+';'))<>1 then begin Error:='not-authorized';Exit(404);end;
  if Length(T.Db.Query('SELECT 1 FROM user_emails WHERE lower(address)='+QuotedStr(Mail)+';'))>0 then
  begin Error:='email-already-taken';Exit(409);end;
  if not T.Db.Exec('BEGIN IMMEDIATE; DELETE FROM user_emails WHERE userId='+QuotedStr(Target)+'; INSERT INTO user_emails(userId,address,verified) VALUES('+
    QuotedStr(Target)+','+QuotedStr(Mail)+',0); COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='email-already-taken';Exit(409);end;
  Result:=200;
end;

function ViewSetOwnProfile(const T:TWLTenant;const UserId,Fullname,Initials:string;out Error:string):Integer;
var Name,Ini:string;
begin
  Error:='';Name:=Trim(Fullname);Ini:=Trim(Initials);
  if (UserId='') or (Length(Name)>200) or (Length(UTF8Decode(Ini))>8) or (Pos(#0,Name+Ini)>0) then
  begin Error:='error-user-notCreated';Exit(400);end;
  if not T.Db.Exec('UPDATE users SET profile_json=json_set(CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END,'+
    '''$.fullname'','+QuotedStr(Name)+',''$.initials'','+QuotedStr(Ini)+'),modifiedAt='+QuotedStr(NowIso)+' WHERE id='+QuotedStr(UserId)+';') then
  begin Error:='Could not save';Exit(500);end;
  Result:=200;
end;

function ArchiveCheckedCard(const T:TWLTenant;const UserId,BoardId,CardId:string;out Error:string):Integer; forward;

function ArchiveViewCards(const T:TWLTenant;const UserId,BoardId:string;const Ids:array of string;out Error:string):Integer;
var Unique:array of string;i,j:Integer;Seen:Boolean;List,U:string;
begin
  Error:='';Unique:=nil;
  for i:=0 to High(Ids) do
  begin
    if (Ids[i]='') or (Pos(#0,Ids[i])>0) then begin Error:='invalid-card-selection';Exit(400);end;
    Seen:=False;
    for j:=0 to High(Unique) do if Unique[j]=Ids[i] then Seen:=True;
    if not Seen then begin SetLength(Unique,Length(Unique)+1);Unique[High(Unique)]:=Ids[i];end;
  end;
  if (Length(Unique)=0) or (Length(Unique)>5000) then begin Error:='invalid-card-selection';Exit(400);end;
  // allowIsBoardMemberWithWriteAccess: a writer, an assigned-only writer too.
  if (BoardId='') or (Pos(#0,BoardId)>0) or not AssignedWriterOn(T.Db,UserId,BoardId) then begin Error:='not-authorized';Exit(403);end;
  List:='';
  for i:=0 to High(Unique) do begin if List<>'' then List:=List+',';List:=List+QuotedStr(Unique[i]);end;
  if StrToIntDef(T.Db.Query('SELECT count(*) FROM cards WHERE boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL AND id IN ('+
    List+');')[0][0],-1)<>Length(Unique) then begin Error:='invalid-card-selection';Exit(400);end;
  U:=QuotedStr(UserId);
  if Length(T.Db.Query('SELECT 1 FROM board_members WHERE boardId='+QuotedStr(BoardId)+' AND userId='+U+' AND isActive=1 AND '+
    '(COALESCE(isNormalAssignedOnly,0)=1 OR COALESCE(isCommentAssignedOnly,0)=1 OR COALESCE(isReadAssignedOnly,0)=1) AND EXISTS(SELECT 1 FROM cards c '+
    'WHERE c.id IN ('+List+') AND NOT EXISTS(SELECT 1 FROM card_assignees a WHERE a.cardId=c.id AND a.userId='+U+'));'))>0 then
  begin
    // GHSA-6xqf-jh8x-4wxc: a selection with a card not theirs changes none of it.
    try
      RecordSecurityEvent(T.Db,UserId,'UnassignedArchiveBleed','method:archiveSelectedCards','authz','medium','CWE-863','blocked',
        'Assigned-only member tried to archive a card not assigned to them.');
    except
      // logging must never break the guard
    end;
    Error:='not-authorized';Exit(403);
  end;
  for i:=0 to High(Unique) do
  begin
    Result:=ArchiveCheckedCard(T,UserId,BoardId,Unique[i],Error);
    if Result<>200 then Exit;
  end;
  Result:=200;
end;

function SetViewBoardVisibility(const T:TWLTenant;const UserId,BoardId,Visibility:string;out Error:string):Integer;
begin
  Error:='';
  if (Visibility<>'private') and (Visibility<>'instance') and (Visibility<>'public') then begin Error:='Invalid visibility';Exit(400);end;
  if (BoardId='') or (Pos(#0,BoardId)>0) or not BoardCanRead(T.Db,UserId,BoardId) then begin Error:='Board not found';Exit(404);end;
  if not BoardCanAdmin(T.Db,UserId,BoardId) then begin Error:='Board administration required';Exit(403);end;
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE boards SET permission='+QuotedStr(Visibility)+',modifiedAt='+QuotedStr(NowIso)+' WHERE id='+
    QuotedStr(BoardId)+'; SELECT CASE WHEN (SELECT permission FROM boards WHERE id='+QuotedStr(BoardId)+')='+QuotedStr(Visibility)+
    ' THEN 1 ELSE json(''Visibility failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not change visibility';Exit(500);end;
  Result:=200;
end;

function SetViewListSort(const T:TWLTenant;const UserId,BoardId,ListId:string;Data:TJSONObject;out Error:string):Integer;
var i:Integer;Key,Sets,Lane:string;Value:TJSONData;Fmt:TFormatSettings;
begin
  Error:='';
  if (BoardId='') or (ListId='') or (Pos(#0,BoardId+ListId)>0) or
    (Length(T.Db.Query('SELECT 1 FROM boards WHERE id='+QuotedStr(BoardId)+';'))<>1) then begin Error:='board-not-found';Exit(404);end;
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='permission-denied';Exit(403);end;
  if Length(T.Db.Query('SELECT 1 FROM lists WHERE id='+QuotedStr(ListId)+' AND boardId='+QuotedStr(BoardId)+';'))<>1 then
  begin Error:='permission-denied';Exit(403);end;
  Fmt:=DefaultFormatSettings;Fmt.DecimalSeparator:='.';
  Sets:='modifiedAt='+QuotedStr(NowIso);
  for i:=0 to Data.Count-1 do
  begin
    Key:=Data.Names[i];Value:=Data.Items[i];
    if Key='sort' then
    begin
      if Value.JSONType<>jtNumber then begin Error:='invalid-field';Exit(400);end;
      Sets:=Sets+',sort='+FloatToStr(Value.AsFloat,Fmt);
    end
    else if Key='swimlaneId' then
    begin
      if Value.JSONType<>jtString then begin Error:='invalid-swimlane';Exit(400);end;
      Lane:=Value.AsString;
      if (Lane<>'') and (Length(T.Db.Query('SELECT 1 FROM swimlanes WHERE id='+QuotedStr(Lane)+' AND boardId='+QuotedStr(BoardId)+';'))<>1) then
      begin Error:='invalid-swimlane';Exit(400);end;
      Sets:=Sets+',swimlaneId='+QuotedStr(Lane);
    end
    else if (Key<>'updatedAt') and (Key<>'modifiedAt') then begin Error:='invalid-field';Exit(400);end;
  end;
  if not T.Db.Exec('UPDATE lists SET '+Sets+' WHERE id='+QuotedStr(ListId)+' AND boardId='+QuotedStr(BoardId)+';') then
  begin Error:='Could not update list';Exit(500);end;
  Result:=200;
end;

function ViewInvited(Db:TWLDb;const UserId,BoardId:string):Boolean;
begin
  Result:=(UserId<>'') and (Pos(#0,UserId+BoardId)=0) and (Length(Db.Query('SELECT 1 FROM users,json_each(CASE WHEN json_valid(users.profile_json) '+
    'THEN users.profile_json ELSE ''{}'' END,''$.invitedBoards'') i WHERE users.id='+QuotedStr(UserId)+' AND i.value='+QuotedStr(BoardId)+';'))>0);
end;

// The statement that clears the user's invitation to the board.
function ViewPullInviteSql(const UserId,BoardId:string):string;
begin
  Result:='UPDATE users SET profile_json=json_set(profile_json,''$.invitedBoards'',json((SELECT json_group_array(value) FROM '+
    'json_each(profile_json,''$.invitedBoards'') WHERE value IS NOT '+QuotedStr(BoardId)+'))) WHERE id='+QuotedStr(UserId)+
    ' AND json_valid(profile_json); ';
end;

function AcceptViewInvite(const T:TWLTenant;const UserId,BoardId:string;out Error:string):Integer;
begin
  Error:='';
  if (BoardId='') or (Length(T.Db.Query('SELECT 1 FROM boards WHERE id='+QuotedStr(BoardId)+';'))<>1) then
  begin Error:='error-board-doesNotExist';Exit(404);end;
  // #4730: only a user holding an invitation (re)activates their membership.
  if not ViewInvited(T.Db,UserId,BoardId) then Exit(204);
  if not T.Db.Exec('BEGIN IMMEDIATE; '+ViewPullInviteSql(UserId,BoardId)+'UPDATE board_members SET isActive=1 WHERE boardId='+
    QuotedStr(BoardId)+' AND userId='+QuotedStr(UserId)+'; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not accept';Exit(500);end;
  Result:=200;
end;

function QuitViewBoard(const T:TWLTenant;const UserId,BoardId:string;out Error:string):Integer;
var Member,Invited:Boolean;Sql:string;
begin
  Error:='';
  if (BoardId='') or (Pos(#0,BoardId)>0) or (Length(T.Db.Query('SELECT 1 FROM boards WHERE id='+QuotedStr(BoardId)+';'))<>1) then
  begin Error:='error-board-doesNotExist';Exit(404);end;
  Member:=Length(T.Db.Query('SELECT 1 FROM board_members WHERE boardId='+QuotedStr(BoardId)+' AND userId='+QuotedStr(UserId)+' AND isActive=1;'))=1;
  Invited:=ViewInvited(T.Db,UserId,BoardId);
  if not (Member or Invited) then begin Error:='error-board-notAMember';Exit(403);end;
  Sql:='BEGIN IMMEDIATE; ';
  if Invited then Sql:=Sql+ViewPullInviteSql(UserId,BoardId);
  if Member then Sql:=Sql+'UPDATE board_members SET isActive=0,isAdmin=0 WHERE boardId='+QuotedStr(BoardId)+' AND userId='+QuotedStr(UserId)+'; ';
  if not T.Db.Exec(Sql+'COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not quit';Exit(500);end;
  Result:=200;
end;

function ToggleViewCardLabel(const T:TWLTenant;const UserId,BoardId,CardId,LabelId:string;out Error:string):Integer;
var Pair,Present:string;
begin
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  if (LabelId='') or (Pos(#0,LabelId)>0) or (Length(T.Db.Query('SELECT 1 FROM board_labels WHERE boardId='+
    QuotedStr(BoardId)+' AND id='+QuotedStr(LabelId)+';'))<>1) then
  begin Error:='Label is not on this board';Exit(400);end;
  Pair:='cardId='+QuotedStr(CardId)+' AND labelId='+QuotedStr(LabelId);
  Present:='EXISTS(SELECT 1 FROM card_labels WHERE '+Pair+')';
  if Length(T.Db.Query('SELECT 1 WHERE '+Present+';'))=1 then
  begin
    if not T.Db.Exec('BEGIN IMMEDIATE; DELETE FROM card_labels WHERE '+Pair+'; SELECT CASE WHEN NOT '+Present+
      ' THEN 1 ELSE json(''Card label change failed'') END; COMMIT;') then
    begin T.Db.Exec('ROLLBACK;');Error:='Could not update card labels';Exit(500);end;
  end
  else if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN EXISTS(SELECT 1 FROM board_labels WHERE boardId='+
    QuotedStr(BoardId)+' AND id='+QuotedStr(LabelId)+') THEN 1 ELSE json(''Label changed'') END; '+
    'INSERT INTO card_labels(cardId,labelId) SELECT '+QuotedStr(CardId)+','+QuotedStr(LabelId)+' WHERE NOT '+Present+
    '; SELECT CASE WHEN '+Present+' THEN 1 ELSE json(''Card label change failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not update card labels';Exit(500);end;
end;

function ViewDateKindField(const Kind:string;out Field,Setting:string):Boolean;
begin
  Result:=True;
  if Kind='received' then begin Field:='receivedAt';Setting:='allowsReceivedDate';end
  else if Kind='start' then begin Field:='startAt';Setting:='allowsStartDate';end
  else if Kind='due' then begin Field:='dueAt';Setting:='allowsDueDate';end
  else if Kind='end' then begin Field:='endAt';Setting:='allowsEndDate';end
  else Result:=False;
end;

function SetViewCardDate(const T:TWLTenant;const UserId,BoardId,CardId,Kind,At:string;Remove:Boolean;
  out Error:string):Integer;
var Field,Setting,Literal,Scope,Stamp,Changed,Act,OldDate,NewDate:string;Input:TJSONData;Year:Integer;
  Rows:TWLRows;
begin
  Error:='';
  if not ViewDateKindField(Kind,Field,Setting) then begin Error:='not found';Exit(404);end;
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  if not BoardCanEditCardText(T.Db,UserId,BoardId) then begin Error:='your role on this board cannot change it';Exit(403);end;
  if not BoardAllows(T.Db,BoardId,Setting) then begin Error:='this board does not use this date';Exit(403);end;
  if Remove then Literal:='NULL'
  else
  begin
    // The time the date picker made (weddy.js: toISOString), as Weddy's
    // datePickerValue takes it: an RFC 3339 time of a four-digit year.
    Year:=StrToIntDef(Copy(At,1,4),0);
    if (Length(At)<20) or (At[5]<>'-') or (At[11]<>'T') or (Pos(#0,At)>0) then
    begin Error:='invalid-date';Exit(400);end;
    if (Year<1000) or (Year>9999) then begin Error:='invalid-year';Exit(400);end;
    Input:=TJSONString.Create(At);
    try
      if not CardDateSql(Input,Literal) or (Literal='NULL') then begin Error:='invalid-date';Exit(400);end;
    finally Input.Free;end;
  end;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  Rows:=T.Db.Query('SELECT COALESCE('+Field+', '''') FROM cards WHERE '+Scope+';');
  if Length(Rows)<>1 then begin Error:='Card not found';Exit(404);end;
  OldDate:=Rows[0][0];
  Stamp:=QuotedStr(NowIso);
  // timingChangeActivity.js: a date set carries timeValue, a date cleared
  // timeOldValue alone, and clearing a date the card did not have records nothing.
  if Remove then
    Changed:='COALESCE('+Field+','''')<>'''''
  else Changed:='1';
  Act:='INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) SELECT '+
    QuotedStr(NewId)+','+QuotedStr('a-'+Field)+','+QuotedStr(UserId)+',boardId,id,listId,swimlaneId,'+Stamp+','+Stamp+
    ',json_object(''timeKey'','+QuotedStr(Field)+',''timeOldValue'',COALESCE('+Field+',''''),''cardTitle'',title,'+
    '''username'',(SELECT username FROM users WHERE id='+QuotedStr(UserId)+')';
  if not Remove then Act:=Act+',''timeValue'','+Literal;
  Act:=Act+') FROM cards WHERE '+Scope+' AND '+Changed+'; ';
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+
    ')=1 THEN 1 ELSE json(''Card scope changed'') END; '+Act+'UPDATE cards SET '+Field+'='+Literal+
    ',modifiedAt='+Stamp+',dateLastActivity='+Stamp+' WHERE '+Scope+'; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not update card';Exit(500);end;
  NewDate:='';
  if not Remove then NewDate:=Copy(Literal,2,Length(Literal)-2);
  RecordCardDateHistory(T.Db,UserId,BoardId,CardId,Field,OldDate,NewDate);
end;

function ViewFieldNumber(const Raw:string;Currency:Boolean;out Literal:string):Boolean;
var Text,Clean:string;i:Integer;Number:Double;Fmt:TFormatSettings;
begin
  Result:=False;Literal:='NULL';
  Text:=Trim(Raw);
  if Currency then
  begin
    // Weddy's parseFieldValue: 123,45 is 123.45 (the decimal comma); 1,234.5 keeps its point.
    Clean:='';
    for i:=1 to Length(Text) do if Text[i] in ['0'..'9','.',',','+','-'] then Clean:=Clean+Text[i];
    if (Pos(',',Clean)>0) and (Pos('.',Clean)=0) then Clean:=StringReplace(Clean,',','.',[]);
    Text:=StringReplace(Clean,',','',[rfReplaceAll]);
  end;
  if Text='' then Exit(True);
  Fmt:=DefaultFormatSettings;Fmt.DecimalSeparator:='.';Fmt.ThousandSeparator:=#0;
  if not TryStrToFloat(Text,Number,Fmt) or IsNan(Number) or IsInfinite(Number) or (Abs(Number)>1e300) then Exit;
  Literal:=FloatToStrF(Number,ffGeneral,17,0,Fmt);
  Result:=True;
end;

function ViewFieldAllowed(Db:TWLDb;const UserId,BoardId,CardId,FieldId:string;Write:Boolean):Boolean;
var Policy:TFieldPolicy;
begin
  Result:=False;
  if (UserId='') or (Pos(#0,FieldId)>0) then Exit;
  Policy:=TFieldPolicy.Create(Db,UserId,BoardId,CardId);
  try
    try Result:=Policy.Allowed(FieldId,Write);except Result:=False;end;
  finally Policy.Free;end;
end;

function SetViewCardField(const T:TWLTenant;const UserId,BoardId,CardId,FieldId:string;Values:TStrings;Toggle:Boolean;
  out Error:string):Integer;
var Def,Rows:TWLRows;Kind,Literal,Raw,Guard,At,Scope:string;Policy:TFieldPolicy;Allowed:Boolean;Items:TJSONArray;i:Integer;
  Input:TJSONData;Year:Integer;Seen:TStringList;Previous,Next:TJSONObject;
  function Known(const ItemId:string):Boolean;
  begin
    Result:=Length(T.Db.Query('SELECT 1 FROM custom_field_dropdown_items WHERE customFieldId='+QuotedStr(FieldId)+
      ' AND id='+QuotedStr(ItemId)+';'))=1;
  end;
begin
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  if (FieldId='') or (Pos(#0,FieldId)>0) then begin Error:='custom-field-not-found';Exit(404);end;
  if not BoardAllows(T.Db,BoardId,'allowsCustomFields') then begin Error:='this board does not use custom fields';Exit(403);end;
  Def:=T.Db.Query('SELECT f.type FROM custom_fields f JOIN custom_field_boards b ON b.customFieldId=f.id WHERE f.id='+
    QuotedStr(FieldId)+' AND b.boardId='+QuotedStr(BoardId)+';');
  if Length(Def)<>1 then begin Error:='custom-field-not-found';Exit(404);end;
  Kind:=Def[0][0];
  Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,CardId);
  try
    try Allowed:=Policy.Allowed(FieldId,True);Guard:=Policy.Guard(FieldId);except Allowed:=False;end;
  finally Policy.Free;end;
  if not Allowed then begin Error:='Custom-field write forbidden';Exit(403);end;
  Scope:='cardId='+QuotedStr(CardId)+' AND customFieldId='+QuotedStr(FieldId);
  if Toggle then
  begin
    // cardCustomFieldsPopup: the field onto the card, empty, or off it.
    if Length(T.Db.Query('SELECT 1 FROM card_custom_field_values WHERE '+Scope+';'))=1 then
    begin
      if not T.Db.Exec('BEGIN IMMEDIATE; '+Guard+'DELETE FROM card_custom_field_values WHERE '+Scope+'; COMMIT;') then
      begin T.Db.Exec('ROLLBACK;');Error:='Could not save custom-field value';Exit(500);end;
    end
    else if not SaveCardFieldValue(T.Db,CardId,FieldId,'NULL',Guard) then
    begin Error:='Could not save custom-field value';Exit(500);end;
    Exit(200);
  end;
  Raw:=Values.Values['value'];
  Literal:='NULL';
  // The value of the form for the field's type, as WeKan's cardCustomField-*
  // editors make it (Weddy's parseFieldValue): an empty one clears it.
  if Kind='text' then
  begin
    if (Length(Raw)>100000) or (Pos(#0,Raw)>0) then begin Error:='invalid-custom-field-value';Exit(400);end;
    if Trim(Raw)<>'' then Literal:=QuotedStr(Raw);
  end
  else if (Kind='number') or (Kind='currency') then
  begin
    if not ViewFieldNumber(Raw,Kind='currency',Literal) then begin Error:='invalid-custom-field-value';Exit(400);end;
  end
  else if Kind='checkbox' then
  begin
    if (Raw='true') or (Raw='on') or (Raw='1') then Literal:='1' else Literal:='0';
  end
  else if Kind='date' then
  begin
    if Values.Values['delete']<>'1' then
    begin
      At:=Values.Values['at'];Year:=StrToIntDef(Copy(At,1,4),0);
      if (Length(At)<20) or (At[5]<>'-') or (At[11]<>'T') or (Pos(#0,At)>0) or (Year<1000) or (Year>9999) then
      begin Error:='invalid-custom-field-value';Exit(400);end;
      Input:=TJSONString.Create(At);
      try
        if not CardDateSql(Input,Literal) or (Literal='NULL') then begin Error:='invalid-custom-field-value';Exit(400);end;
      finally Input.Free;end;
    end;
  end
  else if Kind='dropdown' then
  begin
    if Raw<>'' then
    begin
      if not Known(Raw) then begin Error:='invalid-custom-field-value';Exit(400);end;
      Literal:=QuotedStr(Raw);
    end;
  end
  else if (Kind='dropdownMultiSelect') or (Kind='stringtemplate') then
  begin
    Items:=TJSONArray.Create;Seen:=TStringList.Create;
    try
      for i:=0 to Values.Count-1 do
      begin
        if Values.Names[i]<>'value' then Continue;
        Raw:=Values.ValueFromIndex[i];
        if Pos(#0,Raw)>0 then begin Error:='invalid-custom-field-value';Exit(400);end;
        if Kind='dropdownMultiSelect' then
        begin
          if Raw='' then Continue;
          if not Known(Raw) then begin Error:='invalid-custom-field-value';Exit(400);end;
          if Seen.IndexOf(Raw)>=0 then Continue;
          Seen.Add(Raw);
        end
        else
        begin
          if Trim(Raw)='' then Continue;
          if (Length(Raw)>10000) or (Items.Count>=200) then begin Error:='invalid-custom-field-value';Exit(400);end;
        end;
        Items.Add(Raw);
      end;
      if Items.Count>0 then Literal:=QuotedStr(Items.AsJSON);
    finally Items.Free;Seen.Free;end;
  end
  else begin Error:='not editable here';Exit(403);end;
  Rows:=T.Db.Query('SELECT CASE WHEN value IS NULL THEN char(0) ELSE CAST(value AS TEXT) END FROM card_custom_field_values WHERE '+Scope+';');
  if Length(Rows)=1 then Raw:=Rows[0][0] else Raw:=#0;
  Previous:=nil;Next:=nil;
  try
    if IsShared(T.Db) then
      try Previous:=CustomFieldHistorySnapshot(T.Db,CardId); except end;
    if not SaveCardFieldValue(T.Db,CardId,FieldId,Literal,Guard) then
    begin Error:='Could not save custom-field value';Exit(500);end;
    // WeKan's cardCustomFields hook: a changed value is an activity -
    // setCustomField with the value, or unsetCustomField - which notifies the
    // card's watchers and starts the board's rules (an advanced-filter
    // trigger reads the card as it is now).
    Rows:=T.Db.Query('SELECT CASE WHEN value IS NULL THEN char(0) ELSE CAST(value AS TEXT) END,'+
      'CASE WHEN value IS NULL THEN ''unsetCustomField'' ELSE ''setCustomField'' END,'+
      'json_object(''customFieldId'','+QuotedStr(FieldId)+',''value'',value) FROM card_custom_field_values WHERE '+Scope+';');
    if (Length(Rows)=1) and (Rows[0][0]<>Raw) then
      T.Db.Exec('INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) '+
        'SELECT '+QuotedStr(NewId)+','+QuotedStr(Rows[0][1])+','+QuotedStr(UserId)+',boardId,id,listId,swimlaneId,'+QuotedStr(NowIso)+','+
        QuotedStr(NowIso)+','+QuotedStr(Rows[0][2])+' FROM cards WHERE id='+QuotedStr(CardId)+';');
    if Previous<>nil then
      try
        Next:=CustomFieldHistorySnapshot(T.Db,CardId);
        if Previous.AsJSON<>Next.AsJSON then
          RecordHistoryRow(T.Db,UserId,BoardId,'card',CardId,'customFields','edited',Previous,Next);
      except
        // History never fails the edit it records.
      end;
  finally Previous.Free;Next.Free;end;
  Result:=200;
end;

function MoveViewCard(const T:TWLTenant;const UserId,BoardId,CardId,DestBoard,DestLane,DestList:string;out Error:string;const Reason:string):Integer;
var Card,Current:TWLRows;Scope,Stamp,Sort,ActivityId,MoveReason:string;Before,After:TJSONObject;
  function Snapshot(const Row:TWLRow):TJSONObject;
  begin
    Result:=TJSONObject.Create(['boardId',BoardId,'swimlaneId',Row[0],'listId',Row[1],
      'sort',GetJSON(Row[2]),'lastMoveReason',Row[3]]);
  end;
begin
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  if (DestBoard<>'') and (DestBoard<>BoardId) then
  begin Error:='A card moves to another board from the HTML4 view only';Exit(400);end;
  MoveReason:=Trim(Reason);
  if (Pos(#0,MoveReason)>0) or (Length(MoveReason)>4096) then begin Error:='Invalid move reason';Exit(400);end;
  if (DestList='') or (Pos(#0,DestLane+DestList)>0) then begin Error:='Invalid card move destination';Exit(400);end;
  Card:=T.Db.Query('SELECT swimlaneId,listId,json_quote(sort),COALESCE(json_extract(extra_json,''$.lastMoveReason''),'''') FROM cards WHERE id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+
    ' AND archived=0 AND deletedAt IS NULL;');
  if Length(Card)<>1 then begin Error:='Card not found';Exit(404);end;
  // The card keeps its swimlane unless another is chosen; the list is one of
  // the board's, of every swimlane or of that one.
  Scope:=DestLane;if Scope='' then Scope:=Card[0][0];
  if not ApiChildrenBelong(T.Db,BoardId,Scope,DestList,'','','','','') or
    (Length(T.Db.Query('SELECT 1 FROM lists WHERE id='+QuotedStr(DestList)+' AND boardId='+QuotedStr(BoardId)+
      ' AND archived=0 AND deletedAt IS NULL AND (COALESCE(swimlaneId,'''')='''' OR swimlaneId='+QuotedStr(Scope)+');'))<>1) then
  begin Error:='Invalid card move destination';Exit(400);end;
  if (Scope=Card[0][0]) and (DestList=Card[0][1]) then Exit(200);
  Stamp:=QuotedStr(NowIso);
  Sort:='(SELECT coalesce(max(sort),-1)+1 FROM cards WHERE boardId='+QuotedStr(BoardId)+' AND listId='+QuotedStr(DestList)+
    ' AND swimlaneId='+QuotedStr(Scope)+' AND deletedAt IS NULL)';
  // WeKan's moveCard activity (models/cards.js), with the lists' names, and
  // its notifications.
  ActivityId:=NewId;
  if not T.Db.Exec('BEGIN IMMEDIATE; INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) '+
    'SELECT '+QuotedStr(ActivityId)+',''moveCard'','+QuotedStr(UserId)+',boardId,id,'+QuotedStr(DestList)+','+QuotedStr(Scope)+','+Stamp+','+Stamp+
    ',json_object(''cardTitle'',title,''oldListId'',listId,''oldSwimlaneId'',swimlaneId,'+
    '''listName'',(SELECT title FROM lists WHERE id='+QuotedStr(DestList)+'),''oldListName'',(SELECT title FROM lists WHERE id=cards.listId),'+
    '''swimlaneName'',(SELECT title FROM swimlanes WHERE id='+QuotedStr(Scope)+')) FROM cards WHERE id='+QuotedStr(CardId)+'; '+
    'UPDATE cards SET swimlaneId='+QuotedStr(Scope)+',listId='+QuotedStr(DestList)+',sort='+Sort+',modifiedAt='+Stamp+
    ',dateLastActivity='+Stamp+',extra_json=json_set(extra_json,''$.lastMoveReason'','+QuotedStr(MoveReason)+') WHERE id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+'; '+
    NotificationsSql(T.Db,UserId,BoardId,DestList,CardId,'',ActivityId,'moveCard')+'COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not move card';Exit(500);end;
  Current:=T.Db.Query('SELECT swimlaneId,listId,json_quote(sort),COALESCE(json_extract(extra_json,''$.lastMoveReason''),'''') FROM cards WHERE id='+
    QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+';');
  if Length(Current)=1 then
  begin
    Before:=Snapshot(Card[0]);After:=Snapshot(Current[0]);
    try
      try RecordHistoryRow(T.Db,UserId,BoardId,'card',CardId,'position','moved',Before,After);
      except
        // History never fails the move it records.
      end;
    finally Before.Free;After.Free;end;
  end;
  Result:=200;
end;

function CopyViewCard(const T:TWLTenant;const UserId,BoardId,CardId,DestBoard,DestLane,DestList,Title:string;
  out NewCard,Error:string):Integer;
var Card:TWLRows;Board:string;
begin
  NewCard:='';
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  Board:=DestBoard;if Board='' then Board:=BoardId;
  if (DestList='') or (DestLane='') or (Pos(#0,Board+DestLane+DestList+Title)>0) then
  begin Error:='Invalid card copy destination';Exit(400);end;
  if not BoardCanWrite(T.Db,UserId,Board) then begin Error:='Board access forbidden';Exit(403);end;
  if not ApiChildrenBelong(T.Db,Board,DestLane,DestList,'','','','','') then begin Error:='Invalid card copy destination';Exit(400);end;
  Card:=T.Db.Query('SELECT listId FROM cards WHERE id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL;');
  if Length(Card)<>1 then begin Error:='Card not found';Exit(404);end;
  try
    if not CopyRestCard(T,UserId,BoardId,Card[0][0],CardId,Board,DestList,DestLane,-1,NewCard) then
    begin Error:='Could not copy card';Exit(500);end;
  except Error:='Could not copy card';Exit(500);end;
  // copyCardPopup's title: the copy's own.
  if Trim(Title)<>'' then Result:=RenameViewCard(T,UserId,Board,NewCard,Title,Error) else Result:=200;
end;

// The archive itself, once the caller's right to it is checked.
function ArchiveCheckedCard(const T:TWLTenant;const UserId,BoardId,CardId:string;out Error:string):Integer;
var Scope,Stamp,ActivityId:string;R:TWLRows;
begin
  Error:='';Result:=200;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL';
  R:=T.Db.Query('SELECT COALESCE(listId,'''') FROM cards WHERE '+Scope+';');
  if Length(R)<>1 then begin Error:='Card not found';Exit(404);end;
  Stamp:=QuotedStr(NowIso);ActivityId:=NewId;
  // As POST .../cards/:cardId/archive archives it, with WeKan's archivedCard
  // activity and its notifications.
  if not T.Db.Exec('BEGIN IMMEDIATE; INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) '+
    'SELECT '+QuotedStr(ActivityId)+',''archivedCard'','+QuotedStr(UserId)+',boardId,id,listId,swimlaneId,'+Stamp+','+Stamp+
    ',json_object(''cardTitle'',title) FROM cards WHERE '+Scope+'; UPDATE cards SET archived=1,archivedAt='+Stamp+',modifiedAt='+Stamp+
    ' WHERE '+Scope+'; SELECT CASE WHEN EXISTS(SELECT 1 FROM activities WHERE id='+QuotedStr(ActivityId)+
    ') AND EXISTS(SELECT 1 FROM cards WHERE id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=1) THEN 1 '+
    'ELSE json(''Archive write failed'') END; '+NotificationsSql(T.Db,UserId,BoardId,R[0][0],CardId,'',ActivityId,'archivedCard')+'COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not change card archive state';Exit(500);end;
  RecordCardBooleanHistory(T.Db,UserId,BoardId,CardId,'archived',False,True);
end;

function ArchiveViewCard(const T:TWLTenant;const UserId,BoardId,CardId:string;out Error:string):Integer;
begin
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  Result:=ArchiveCheckedCard(T,UserId,BoardId,CardId,Error);
end;

function SetViewCardDescription(const T:TWLTenant;const UserId,BoardId,CardId,Text:string;out Error:string):Integer;
begin
  Result:=SetViewCardText(T,UserId,BoardId,CardId,'description',Text,Error);
end;


// POST card archive — archives by default; body isArchive=false unarchives.
procedure ApiCardArchive(aRequest: TRequest; aResponse: TResponse);
var T:TWLTenant;UserId,CardId,BoardId,LegacyValue,Scope,Predicate,Stamp,ArchivedAt:string;
  Legacy,Archive,WasArchived:Boolean;Rows:TWLRows;Reply:TJSONObject;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,CardNotFound) then Exit;
  CardId:=aRequest.RouteParams['cardId'];BoardId:=aRequest.RouteParams['boardId'];
  Archive:=Copy(aRequest.PathInfo,Length(aRequest.PathInfo)-9,10)<>'/unarchive';
  LegacyValue:=BodyField(aRequest,'isArchive');Legacy:=Archive and (LegacyValue<>'');
  if Legacy then Archive:=BoolInt(LegacyValue)=1;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+
    ' AND listId='+QuotedStr(aRequest.RouteParams['listId']);
  Predicate:=Scope;
  if not Legacy then Predicate:=Predicate+' AND archived='+IntToStr(Ord(not Archive));
  Rows:=T.Db.Query('SELECT archived FROM cards WHERE '+Predicate+';');
  if Length(Rows)<>1 then begin SendJson(aResponse,CardNotFound,404);Exit;end;
  WasArchived:=Rows[0][0]='1';
  if Legacy then Predicate:=Predicate+' AND archived='+IntToStr(Ord(WasArchived));
  Stamp:=NowIso;ArchivedAt:='NULL';
  if Archive then ArchivedAt:=QuotedStr(Stamp);
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Predicate+
    ')=1 THEN 1 ELSE json(''Archive scope changed'') END; UPDATE cards SET archived='+IntToStr(Ord(Archive))+
    ',archivedAt='+ArchivedAt+',modifiedAt='+QuotedStr(Stamp)+' WHERE '+Predicate+
    '; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+' AND archived='+IntToStr(Ord(Archive))+
    ')=1 THEN 1 ELSE json(''Archive write failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not change card archive state');Exit;end;
  RecordCardBooleanHistory(T.Db,UserId,BoardId,CardId,'archived',WasArchived,Archive);
  if Legacy then SendCardById(aResponse,T.Db,CardId,UserId,False,BoardId)
  else
  begin
    Reply:=TJSONObject.Create(['_id',CardId,'archived',Archive]);
    try
      if Archive then Reply.Add('archivedAt',Stamp);
      SendJson(aResponse,Reply.AsJSON);
    finally Reply.Free;end;
  end;
end;

// DELETE card — children (labels/members/comments/checklists/…) cascade via FK.
// The activity records the claimed delete in the same transaction as the cascade.
function DeleteRestCard(Db:TWLDb;const UserId,BoardId,ListId,CardId:string;out Removed:Boolean):Boolean;
var Scope,Claim,Actor,Stamp,Sql,Permission,Bindings,Attachments,AttachmentScope,BatchId,Notify:string;Policy:TFieldPolicy;Source:TSelectionScope;I:Integer;
  R:TWLRows;
begin
  Result:=False;Removed:=False;BatchId:=NewId;Claim:=QuotedStr(BatchId);Actor:=QuotedStr(UserId);Stamp:=QuotedStr(NowIso);
  try
    Policy:=TFieldPolicy.Create(Db,UserId,BoardId,'');
    try Permission:=Policy.ScopeBoardExpression(True);finally Policy.Free;end;
    Attachments:='';
    Source:=TSelectionScope.Create(Db);
    try
      Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+
        ' AND '+Source.StringField('cards','id')+' AND '+Source.StringField('cards','boardId');
      if ListId<>'' then Scope:=Scope+' AND listId='+QuotedStr(ListId);
      if SharedStore(Db) then
      begin
        AttachmentScope:='boardId='+QuotedStr(BoardId)+' AND cardId='+QuotedStr(CardId)+
          ' AND '+Source.StringField('attachments','id')+' AND '+Source.StringField('attachments','boardId')+
          ' AND '+Source.StringField('attachments','cardId')+' AND EXISTS(SELECT 1 FROM cards WHERE '+Scope+')';
        Attachments:=SharedAttachmentRemovalSQL(Db,UserId,BoardId,AttachmentScope,Claim,False);
      end;
      Bindings:='';
      for I:=0 to Source.Bindings.Count-1 do Bindings:=Bindings+Source.Bindings[I];
    finally Source.Free;end;
    // WeKan's deleteCard activity notifies those of the card, read before it goes.
    R:=Db.Query('SELECT COALESCE(listId,'''') FROM cards WHERE id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+';');
    Notify:='';
    if Length(R)=1 then Notify:=NotificationsSql(Db,UserId,BoardId,R[0][0],CardId,'',BatchId,'deleteCard');
    Sql:='BEGIN IMMEDIATE; '+Bindings+
      'SELECT CASE WHEN '+Permission+' THEN 1 ELSE json(''Card deletion permission changed'') END; '+
      'INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) '+
      'SELECT '+Claim+',''deleteCard'','+Actor+',boardId,id,listId,swimlaneId,'+Stamp+','+Stamp+
      ',json_object(''cardTitle'',title) FROM cards WHERE '+Scope+'; '+Attachments+
      'DELETE FROM cards WHERE '+Scope+' AND EXISTS(SELECT 1 FROM activities WHERE id='+Claim+'); '+
      'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM cards WHERE '+Scope+
      ') THEN 1 ELSE json(''Card deletion failed'') END; '+Notify+'COMMIT;';
    if not Db.Exec(Sql) then begin Db.Exec('ROLLBACK;');Exit;end;
    R:=Db.Query('SELECT COALESCE(listId,''''),COALESCE(swimlaneId,''''),'+
      'COALESCE(json_extract(data_json,''$.cardTitle''),'''') FROM activities WHERE id='+Claim+';');
    Removed:=Length(R)=1;
    Result:=True;
    if Removed then
    begin
      RecordCardRemoval(Db,UserId,BoardId,R[0][0],R[0][1],CardId,R[0][2]);
      if Attachments<>'' then RecordSharedAttachmentRemovals(Db,UserId,BoardId,BatchId);
    end;
  except Db.Exec('ROLLBACK;');end;
end;

procedure ApiCardDelete(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,CardId:string;Removed:Boolean;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,CardNotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];CardId:=aRequest.RouteParams['cardId'];
  if not DeleteRestCard(T.Db,UserId,BoardId,aRequest.RouteParams['listId'],CardId,Removed) then
  begin SendError(aResponse,500,'Could not delete card');Exit;end;
  if not Removed then begin SendJson(aResponse,CardNotFound,404);Exit;end;
  SendJson(aResponse,'{"_id":"'+StringToJSONString(CardId)+'"}');
end;

procedure ApiBulkCardLabels(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,Cards,AddIds,RemoveIds,CardScope,LabelCheck,Permission,Bindings,Sql,CardId:string;
  Body,Reply,Item:TJSONObject;Input:TJSONData;Updated,NotFound,Labels:TJSONArray;
  Source:TSelectionScope;Policy:TFieldPolicy;Rows:TWLRows;I,J:Integer;
  function ReadIds(const Name:string;Required:Boolean):string;
  var Value:TJSONData;K:Integer;
  begin
    Result:='[]';Value:=Body.Find(Name);
    if (Value=nil) and not Required then Exit;
    if not (Value is TJSONArray) or (Value.Count>500) or (Required and (Value.Count=0)) then
      raise Exception.Create('Invalid ID list');
    for K:=0 to Value.Count-1 do
      if (Value.Items[K].JSONType<>jtString) or (Value.Items[K].AsString='') or
        (Pos(#0,Value.Items[K].AsString)>0) then raise Exception.Create('Invalid ID');
    if Value.Count<>0 then Result:=Value.AsJSON;
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];
  if not ApiAuthBoard(T,aResponse,UserId,BoardId,True) then Exit;
  Body:=nil;Reply:=nil;
  try
    try
      Body:=ExactObject(aRequest.Content);
      Cards:=ReadIds('cardIds',True);AddIds:=ReadIds('addLabelIds',False);RemoveIds:=ReadIds('removeLabelIds',False);
      if (AddIds='[]') and (RemoveIds='[]') then raise Exception.Create('Missing label changes');
    except SendError(aResponse,400,'Invalid card or label IDs');Exit;end;
    Cards:=QuotedStr(Cards);AddIds:=QuotedStr(AddIds);RemoveIds:=QuotedStr(RemoveIds);
    Source:=TSelectionScope.Create(T.Db);
    try
      CardScope:='boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL AND '+
        Source.StringField('cards','id')+' AND '+Source.StringField('cards','boardId');
      LabelCheck:='NOT EXISTS(SELECT 1 FROM json_each('+AddIds+') wanted WHERE NOT EXISTS(SELECT 1 FROM board_labels'+
        ' WHERE boardId='+QuotedStr(BoardId)+' AND id=wanted.value AND '+Source.StringField('board_labels','id')+'))';
      Bindings:='';
      for I:=0 to Source.Bindings.Count-1 do Bindings:=Bindings+Source.Bindings[I];
    finally Source.Free;end;
    Rows:=T.Db.Query('SELECT '+LabelCheck+';');
    if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
    begin SendError(aResponse,400,'addLabelIds contains labels not on this board');Exit;end;
    Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
    try Permission:=Policy.ScopeBoardExpression(True);finally Policy.Free;end;
    CardScope:=CardScope+' AND id IN (SELECT value FROM json_each('+Cards+'))';
    Sql:='BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+Permission+' AND '+LabelCheck+
      ' THEN 1 ELSE json(''Card label scope changed'') END; '+
      'DELETE FROM card_labels WHERE cardId IN (SELECT id FROM cards WHERE '+CardScope+
      ') AND labelId IN (SELECT value FROM json_each('+RemoveIds+')); '+
      'INSERT INTO card_labels(cardId,labelId) SELECT c.id,l.value FROM (SELECT id FROM cards WHERE '+CardScope+
      ') c CROSS JOIN (SELECT value,min(key) position FROM json_each('+AddIds+') GROUP BY value) l '+
      'WHERE NOT EXISTS(SELECT 1 FROM card_labels WHERE cardId=c.id AND labelId=l.value) ORDER BY c.id,l.position; COMMIT;';
    if not T.Db.Exec(Sql) then
    begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not update card labels');Exit;end;
    Reply:=TJSONObject.Create;Updated:=TJSONArray.Create;Reply.Add('updated',Updated);
    NotFound:=TJSONArray.Create;Reply.Add('notFound',NotFound);
    Input:=Body.Find('cardIds');
    for I:=0 to Input.Count-1 do
    begin
      CardId:=Input.Items[I].AsString;
      if Length(T.Db.Query('SELECT id FROM cards WHERE '+CardScope+' AND id='+QuotedStr(CardId)+';'))=0 then
      begin NotFound.Add(CardId);Continue;end;
      Item:=TJSONObject.Create(['_id',CardId]);Updated.Add(Item);
      Labels:=TJSONArray.Create;Item.Add('labelIds',Labels);
      Rows:=T.Db.Query('SELECT labelId FROM card_labels WHERE cardId='+QuotedStr(CardId)+';');
      for J:=0 to High(Rows) do Labels.Add(Rows[J][0]);
    end;
    SendJson(aResponse,Reply.AsJSON);
  finally Reply.Free;Body.Free;end;
end;

procedure ApiBulkCardDelete(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,CardId:string;Body,Reply:TJSONObject;
  Value:TJSONData;Cards,Deleted,NotFound:TJSONArray;Removed:Boolean;I:Integer;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];
  if not ApiAuthBoard(T,aResponse,UserId,BoardId,True) then Exit;
  Body:=nil;Reply:=TJSONObject.Create;
  try
    try Body:=ExactObject(aRequest.Content);
    except SendError(aResponse,400,'Expected a valid JSON object');Exit;end;
    Value:=Body.Find('cardIds');
    if not (Value is TJSONArray) or (Value.Count=0) or (Value.Count>500) then
    begin SendError(aResponse,400,'cardIds must contain between 1 and 500 entries');Exit;end;
    Cards:=TJSONArray(Value);
    for I:=0 to Cards.Count-1 do
      if (Cards.Items[I].JSONType<>jtString) or (Cards.Items[I].AsString='') or
        (Pos(#0,Cards.Items[I].AsString)>0) then
      begin SendError(aResponse,400,'Invalid card ID');Exit;end;
    Deleted:=TJSONArray.Create;Reply.Add('deleted',Deleted);
    NotFound:=TJSONArray.Create;Reply.Add('notFound',NotFound);
    for I:=0 to Cards.Count-1 do
    begin
      CardId:=Cards.Strings[I];
      if not DeleteRestCard(T.Db,UserId,BoardId,'',CardId,Removed) then
      begin SendError(aResponse,500,'Could not delete card');Exit;end;
      if Removed then Deleted.Add(CardId) else NotFound.Add(CardId);
    end;
    SendJson(aResponse,Reply.AsJSON);
  finally Reply.Free;Body.Free;end;
end;

// A list soft-deleted with its live cards in one batch (WeKan's
// softRemoveList): marked, not destroyed, and recorded in History, so undo
// restores it whole. 200 also for a list already deleted; 404 for none.
function SoftRemoveViewList(const T:TWLTenant;const UserId,BoardId,ListId:string;out Error:string):Integer;
var Scope,CardScope,Markers,Batch,BatchId,Sql,Stamp:string;Position:TWLRows;
begin
  Error:='';
  if (BoardId='') or (ListId='') or (Pos(#0,BoardId+ListId)>0) then begin Error:='List not found';Exit(404);end;
  Scope:='id='+QuotedStr(ListId)+' AND boardId='+QuotedStr(BoardId);
  if Length(T.Db.Query('SELECT 1 FROM lists WHERE '+Scope+';'))<>1 then begin Error:='List not found';Exit(404);end;
  if Length(T.Db.Query('SELECT 1 FROM lists WHERE '+Scope+' AND deletedAt IS NOT NULL;'))=1 then Exit(200);
  BatchId:=NewId;Batch:=QuotedStr(BatchId);Stamp:=NowIso;
  Markers:='deletedAt='+QuotedStr(Stamp)+',deletedBy='+QuotedStr(UserId)+',deleteBatchId='+Batch;
  Position:=T.Db.Query('SELECT swimlaneId,sort FROM lists WHERE '+Scope+' AND deletedAt IS NULL;');
  CardScope:='listId='+QuotedStr(ListId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+Scope+
    ' AND deletedAt IS NULL)=1 THEN 1 ELSE json(''List delete scope changed'') END; '+
    'UPDATE cards SET '+Markers+' WHERE '+CardScope+'; UPDATE lists SET '+Markers+
    ' WHERE '+Scope+' AND deletedAt IS NULL; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+
    Scope+' AND deleteBatchId='+Batch+')=1 AND NOT EXISTS(SELECT 1 FROM cards WHERE '+CardScope+
    ') THEN 1 ELSE json(''Could not mark list and cards deleted'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not delete list';Exit(500);end;
  if Length(Position)=1 then
    try RecordListPosition(T.Db,UserId,BoardId,ListId,BatchId,Stamp,Position[0],False);except end;
  Result:=200;
end;

// DELETE list — its cards have no FK on listId, so remove them first (their children cascade).
procedure ApiListDelete(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"List not found"}';
var T:TWLTenant;UserId,ListId,BoardId,Scope,CardScope,Markers,Batch,BatchId,Sql,Stamp:string;Reply:TJSONObject;Position:TWLRows;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  ListId:=aRequest.RouteParams['listId'];BoardId:=aRequest.RouteParams['boardId'];
  // A list already deleted is not found here, as before.
  if Length(T.Db.Query('SELECT 1 FROM lists WHERE id='+QuotedStr(ListId)+' AND boardId='+QuotedStr(BoardId)+
    ' AND deletedAt IS NULL;'))<>1 then begin SendError(aResponse,500,'Could not delete list');Exit;end;
  if SoftRemoveViewList(T,UserId,BoardId,ListId,Sql)<>200 then
  begin SendError(aResponse,500,'Could not delete list');Exit;end;
  Reply:=TJSONObject.Create(['_id',ListId]);
  try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
end;

// A swimlane and its cards are removed in one board-scoped transaction.
procedure ApiSwimlaneDelete(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"Swimlane not found"}';
var T:TWLTenant;UserId,BoardId,SwimlaneId,Scope,CardScope,Permission,Sql:string;
  Policy:TFieldPolicy;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];SwimlaneId:=aRequest.RouteParams['swimlaneId'];
  Scope:='id='+QuotedStr(SwimlaneId)+' AND boardId='+QuotedStr(BoardId);
  CardScope:='swimlaneId='+QuotedStr(SwimlaneId)+' AND boardId='+QuotedStr(BoardId);
  Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
  try Permission:=Policy.ScopeBoardExpression(True);finally Policy.Free;end;
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+
    ' AND (SELECT count(*) FROM swimlanes WHERE '+Scope+')=1 THEN 1 ELSE json(''Swimlane scope changed'') END; '+
    'DELETE FROM cards WHERE '+CardScope+'; DELETE FROM swimlanes WHERE '+Scope+'; '+
    'SELECT CASE WHEN '+Permission+' AND NOT EXISTS(SELECT 1 FROM swimlanes WHERE '+Scope+
    ') AND NOT EXISTS(SELECT 1 FROM cards WHERE '+CardScope+
    ') THEN 1 ELSE json(''Swimlane deletion failed'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not delete swimlane');Exit;end;
  SendJson(aResponse,'{"_id":"'+StringToJSONString(SwimlaneId)+'"}');
end;

// DELETE board — swimlanes/lists/cards/labels/members cascade via boardId FKs (and card
// children transitively); list/swimlane-scoped cards also go via the board cascade on cards.
procedure ApiBoardDelete(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,Board,Permission,Sql,Guards,Collection,Registry,Physical,Scope:string;
  Policy:TFieldPolicy;Rows:TWLRows;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  BoardId:=aRequest.RouteParams['boardId'];Board:=QuotedStr(BoardId);
  Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
  try Permission:=Policy.ScopeAdminExpression(True);finally Policy.Free;end;
  Rows:=T.Db.Query('SELECT '+Permission+';');
  if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
  begin SendError(aResponse,403,'Board administration required');Exit;end;
  Guards:='';Sql:='';
  if Length(T.Db.Query('SELECT 1 FROM sqlite_master WHERE name=''_ferretdb_collections'';'))=1 then
    for Collection in ['rules','triggers','actions','integrations'] do
    begin
      Registry:=' FROM _ferretdb_collections WHERE name='+QuotedStr(Collection);
      Rows:=T.Db.Query('SELECT table_name'+Registry+';');
      if Length(Rows)>1 then begin SendError(aResponse,500,'Ambiguous board source');Exit;end;
      if Length(Rows)=0 then
      begin Guards:=Guards+' AND NOT EXISTS(SELECT 1'+Registry+')';Continue;end;
      Guards:=Guards+' AND (SELECT count(*)'+Registry+' AND table_name='+QuotedStr(Rows[0][0])+')=1';
      Physical:='"'+StringReplace(Rows[0][0],'"','""',[rfReplaceAll])+'"';
      Scope:='json_extract(_ferretdb_sjson,''$.boardId'')='+Board+
        ' AND json_extract(_ferretdb_sjson,''$.$s.p.boardId.t'')=''string''';
      Sql:=Sql+'DELETE FROM '+Physical+' WHERE '+Scope+'; '+
        'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM '+Physical+' WHERE '+Scope+
        ') THEN 1 ELSE json(''Board workflow deletion failed'') END; ';
    end;
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+Guards+
    ' THEN 1 ELSE json(''Board deletion permission changed'') END; '+Sql+
    'DELETE FROM boards WHERE id='+Board+'; SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM boards WHERE id='+Board+
    ') THEN 1 ELSE json(''Board deletion failed'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not delete board');Exit;end;
  SendJson(aResponse,'{"_id":"'+StringToJSONString(BoardId)+'"}');
end;

// ---- attachments: metadata in `attachments`, bytes in files/attachme/<digest components> --------------
function AttachDir(const T: TWLTenant): string;
begin
  Result := T.FilesDir + 'attachme' + PathDelim;
end;

function ReadFileBytes(const Path: string): string;
var fs: TFileStream;
begin
  Result := '';
  if not FileExists(Path) then Exit;
  fs := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then fs.ReadBuffer(Result[1], fs.Size);
  finally fs.Free; end;
end;

procedure WriteFileBytes(const Path, Data: string);
var fs: TFileStream;
begin
  fs := TFileStream.Create(Path, fmCreate);
  try
    if Length(Data) > 0 then fs.WriteBuffer(Data[1], Length(Data));
  finally fs.Free; end;
end;

function DecodeAttachmentUtf16(const Bytes:string;BigEndian,Truncated:Boolean):string;
var Text:UnicodeString; i,Count:Integer; UnitValue:Word; NeedsLow:Boolean;
begin
  Result:='';
  if Odd(Length(Bytes)) and not Truncated then Exit;
  SetLength(Text,(Length(Bytes)-2) div 2);
  Count:=0;
  NeedsLow:=False;
  i:=3;
  while i<Length(Bytes) do
  begin
    if BigEndian then UnitValue:=(Ord(Bytes[i]) shl 8) or Ord(Bytes[i+1])
    else UnitValue:=Ord(Bytes[i]) or (Ord(Bytes[i+1]) shl 8);
    if UnitValue=0 then Exit;
    if NeedsLow then
    begin
      if (UnitValue<$DC00) or (UnitValue>$DFFF) then Exit;
      NeedsLow:=False;
    end
    else if (UnitValue>=$D800) and (UnitValue<=$DBFF) then NeedsLow:=True
    else if (UnitValue>=$DC00) and (UnitValue<=$DFFF) then Exit;
    Inc(Count);
    Text[Count]:=WideChar(UnitValue);
    Inc(i,2);
  end;
  if NeedsLow then
  begin
    if not Truncated then Exit;
    Dec(Count);
  end;
  SetLength(Text,Count);
  Result:=UTF8Encode(Text);
end;

// Match WeKan's bounded indexing for common text formats.
function AttachmentSearchText(Content:TStream;const FileType:string):string;
const MaxSearchBytes=2*1024*1024;
var Mime,Raw:string; Separator,Bytes,i,n,Last,TryCount:Integer; Space:Boolean; C:Char;
begin
  Result:='';
  Mime:=LowerCase(Trim(FileType));
  Separator:=Pos(';',Mime);
  if Separator>0 then Mime:=Trim(Copy(Mime,1,Separator-1));
  if (Mime<>'text/plain') and (Mime<>'text/csv') and (Mime<>'text/tab-separated-values') and
    (Mime<>'text/markdown') and (Mime<>'application/json') then Exit;
  Bytes:=Min(Content.Size,Int64(MaxSearchBytes));
  if Bytes<=0 then Exit;
  SetLength(Raw,Bytes);
  Content.Position:=0;
  Content.ReadBuffer(Raw[1],Bytes);
  if (Copy(Raw,1,2)=#$FF#$FE) or (Copy(Raw,1,2)=#$FE#$FF) then
    Raw:=DecodeAttachmentUtf16(Raw,Raw[1]=#$FE,Content.Size>Bytes)
  else
  begin
    if Pos(#0,Raw)>0 then Exit;
    // If the bounded read cuts a multibyte character, discard that suffix.
    for TryCount:=0 to 3 do
    begin
      try
        CheckUtf8(Raw);
        Break;
      except
        if (Content.Size<=Bytes) or (TryCount=3) then Exit;
        SetLength(Raw,Length(Raw)-1);
      end;
    end;
  end;
  i:=1;
  if Copy(Raw,1,3)=#$EF#$BB#$BF then i:=4;
  n:=0;
  Space:=False;
  Last:=Length(Raw);
  SetLength(Result,Last);
  while i<=Last do
  begin
    C:=Raw[i];
    if C in [#9,#10,#13,' '] then Space:=n>0
    else if not (C in [#1..#8,#11,#12,#14..#31,#127]) then
    begin
      if Space then begin Inc(n);Result[n]:=' ';end;
      Space:=False;
      Inc(n);Result[n]:=C;
    end;
    Inc(i);
  end;
  SetLength(Result,n);
end;

function StoreAttachment(const T:TWLTenant;const UserId,BoardId,Sw,Lst,Crd,FileName,FileType:string; Content:TStream;
  out Id:string;RequireLiveCard:Boolean):Boolean;
var Path,Sql,Guard,SearchText:string;Policy:TFieldPolicy;OwnsPath:Boolean;FileSize:Int64;Destination:TFileStream;
  Preview:TJSONObject;Stamp:TDateTime;
begin
  Id:=NewId;
  Path:=StoreFilePath(T.FilesDir,'attachme',Id);
  Guard:='1';
  if Sw<>'' then Guard:=Guard+' AND EXISTS(SELECT 1 FROM swimlanes WHERE id='+QuotedStr(Sw)+
    ' AND boardId='+QuotedStr(BoardId)+')';
  if Lst<>'' then Guard:=Guard+' AND EXISTS(SELECT 1 FROM lists WHERE id='+QuotedStr(Lst)+
    ' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL AND ('+QuotedStr(Sw)+
    '='''' OR swimlaneId='''' OR swimlaneId='+QuotedStr(Sw)+'))';
  if Crd<>'' then
    Guard:=Guard+' AND EXISTS(SELECT 1 FROM cards WHERE id='+QuotedStr(Crd)+' AND boardId='+QuotedStr(BoardId)+
      ' AND deletedAt IS NULL AND ('+QuotedStr(Lst)+'='''' OR listId='+QuotedStr(Lst)+
      ') AND ('+QuotedStr(Sw)+'='''' OR swimlaneId='+QuotedStr(Sw)+'))';
  if RequireLiveCard then Guard:=Guard+' AND EXISTS(SELECT 1 FROM cards WHERE id='+QuotedStr(Crd)+
    ' AND boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL)';
  Policy:=TFieldPolicy.Create(T.Db,UserId,BoardId,'');
  try Guard:=Guard+' AND ('+Policy.ScopeBoardExpression(True)+' OR '+AssignedWriterSql(UserId,BoardId,Crd)+')';finally Policy.Free;end;
  FileSize:=Content.Size;
  Sql:=Format('INSERT INTO attachments(id,boardId,swimlaneId,listId,cardId,name,type,size,'+
    'storageBackend,userId,createdAt) VALUES(%s,%s,%s,%s,%s,%s,%s,%d,''filesystem'',%s,%s);',
    [QuotedStr(Id),QuotedStr(BoardId),QuotedStr(Sw),QuotedStr(Lst),QuotedStr(Crd),
     QuotedStr(FileName),QuotedStr(FileType),FileSize,QuotedStr(UserId),QuotedStr(NowIso)]);
  OwnsPath:=False;
  try
    if Crd<>'' then SearchText:=AttachmentSearchText(Content,FileType);
    if SearchText<>'' then
    begin
      if IsShared(T.Db) then
      begin
        Stamp:=LocalTimeToUniversal(Now);
        Preview:=TJSONObject.Create(['_id',NewId,'attachmentId',Id,'boardId',BoardId,'cardId',Crd,
          'searchText',SearchText,'generatedAt',DateTimeToUnix(Stamp,True)*1000+MilliSecondOf(Stamp)]);
        try Sql:=Sql+InsertDocSql(T.Db,'documentPreviews',Preview,'{"generatedAt":"date"}');
        finally Preview.Free;end;
      end
      else
        Sql:=Sql+'CREATE TABLE IF NOT EXISTS attachment_search_text (attachmentId TEXT PRIMARY KEY '+
          'REFERENCES attachments(id) ON DELETE CASCADE, searchText TEXT NOT NULL); '+
          'INSERT INTO attachment_search_text(attachmentId,searchText) VALUES('+QuotedStr(Id)+','+QuotedStr(SearchText)+'); ';
    end;
    if FileExists(Path) then raise EInOutError.Create('Attachment path already exists');
    if not ForceDirectories(ExtractFileDir(Path)) then raise EInOutError.Create('Attachment directory unavailable');
    OwnsPath:=True;
    Destination:=TFileStream.Create(Path,fmCreate);
    try
      Content.Position:=0;
      if FileSize>0 then Destination.CopyFrom(Content,FileSize);
    finally Destination.Free;end;
    if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN '+Guard+
      ' THEN 1 ELSE json(''Attachment scope changed'') END; '+Sql+
      'SELECT CASE WHEN '+Guard+' AND EXISTS(SELECT 1 FROM attachments WHERE id='+QuotedStr(Id)+
      ') THEN 1 ELSE json(''Attachment insertion failed'') END; COMMIT;') then
      raise EInOutError.Create('Attachment registration failed');
  except
    T.Db.Exec('ROLLBACK;');
    if OwnsPath and FileExists(Path) then DeleteFile(Path);
    Exit(False);
  end;
  Result:=True;
end;

procedure ApiAttachmentUpload(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,BoardId,Sw,Lst,Crd,FileName,FileType,Id,Bytes,ContentType:string;
  Input,Reply:TJSONObject;Separator:Integer;Content:TStringStream;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  Input:=nil;
  try
    try
      ContentType:=LowerCase(aRequest.ContentType);
      Separator:=Pos(';',ContentType);
      if Separator>0 then SetLength(ContentType,Separator-1);
      // A raw upload: any body but JSON is the file itself (WeKan's raw branch).
      if Trim(ContentType)<>'application/json' then
      begin
        BoardId:=aRequest.QueryFields.Values['boardId'];Sw:=aRequest.QueryFields.Values['swimlaneId'];
        Lst:=aRequest.QueryFields.Values['listId'];Crd:=aRequest.QueryFields.Values['cardId'];
        FileName:=aRequest.QueryFields.Values['fileName'];FileType:=aRequest.QueryFields.Values['fileType'];
        Bytes:=aRequest.Content;
      end
      else
      begin
        Input:=ExactObject(aRequest.Content);
        BoardId:=Input.Get('boardId','');Sw:=Input.Get('swimlaneId','');
        Lst:=Input.Get('listId','');Crd:=Input.Get('cardId','');
        FileName:=Input.Get('fileName','');FileType:=Input.Get('fileType','');
        Bytes:=DecodeStringBase64(Input.Get('fileData',''));
      end;
      if Pos(#0,BoardId+Sw+Lst+Crd+FileName+FileType)>0 then raise EConvertError.Create('Invalid attachment metadata');
    except SendError(aResponse,400,'Invalid attachment upload');Exit;end;
  finally Input.Free;end;
  if FileName='' then FileName:='file';
  if FileType='' then FileType:='application/octet-stream';
  if not ApiChildrenBelong(T.Db,BoardId,Sw,Lst,Crd,'','','','') then
  begin SendError(aResponse,400,'Invalid attachment parent');Exit;end;
  if AttachmentWriteAllowed(T.Db,UserId,BoardId,Crd,'attachment-api:upload')<>200 then
  begin SendError(aResponse,403,'You do not have permission to modify this card');Exit;end;

  Content:=TStringStream.Create(Bytes);
  try
    if not StoreAttachment(T,UserId,BoardId,Sw,Lst,Crd,FileName,FileType,Content,Id) then
    begin SendError(aResponse,500,'Could not store attachment');Exit;end;
  finally Content.Free;end;
  Reply:=TJSONObject.Create(['success',True,'attachmentId',Id,'fileName',FileName,
    'fileSize',Length(Bytes),'storageBackend','filesystem']);
  try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
end;

// look up an attachment row; returns False (and 404 json) if missing
function LoadAttachment(aResponse: TResponse; Db: TWLDb; const Id: string; out R: TWLRows): Boolean;
begin
  R := Db.Query(Format(
    'SELECT boardId,swimlaneId,listId,cardId,name,type,size,createdAt FROM attachments WHERE id=%s LIMIT 1;',
    [QuotedStr(Id)]));
  Result := Length(R) > 0;
  if not Result then SendJson(aResponse, '{"success":false,"message":"Attachment not found"}', 404);
end;

procedure ApiAttachmentDownload(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, Id: string; R: TWLRows; Bytes,Path: string; O:TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  Id := aRequest.RouteParams['attachmentId'];
  if not LoadAttachment(aResponse, T.Db, Id, R) then Exit;
  if not AttachmentReadAllowed(T.Db, UserId, R[0][0], R[0][3], 'attachment-api:read') then
  begin SendError(aResponse, 403, 'You do not have permission to access this attachment'); Exit; end;
  Path:=StoreFilePath(T.FilesDir,'attachme',Id);
  if not FileExists(Path) then
  begin SendJson(aResponse,'{"success":false,"message":"Attachment bytes not found"}',404);Exit;end;
  if aRequest.QueryFields.Values['raw']='1' then
  begin
    if not SendStoredDownload(aResponse,Path) then SendError(aResponse,500,'Could not open attachment');
    Exit;
  end;
  try Bytes:=ReadFileBytes(Path);
  except SendError(aResponse,500,'Could not read attachment');Exit;end;
  O:=TJSONObject.Create(['success',True,'base64Data',EncodeStringBase64(Bytes),
    'fileName',R[0][4],'fileSize',Length(Bytes),'storageBackend','filesystem']);
  try SendJson(aResponse,O.AsJSON);finally O.Free;end;
end;

procedure ApiAttachmentInfo(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId, Id: string; R: TWLRows; O: TJSONObject;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  Id := aRequest.RouteParams['attachmentId'];
  if not LoadAttachment(aResponse, T.Db, Id, R) then Exit;
  if not AttachmentReadAllowed(T.Db, UserId, R[0][0], R[0][3], 'attachment-api:read') then
  begin SendError(aResponse, 403, 'You do not have permission to access this attachment'); Exit; end;
  O := TJSONObject.Create;
  try
    O.Add('success', True);          O.Add('attachmentId', Id);
    O.Add('boardId', R[0][0]);       O.Add('swimlaneId', R[0][1]);
    O.Add('listId', R[0][2]);        O.Add('cardId', R[0][3]);
    O.Add('fileName', R[0][4]);      O.Add('fileType', R[0][5]);
    O.Add('fileSize', StrToIntDef(R[0][6], 0));
    O.Add('storageBackend', 'filesystem');
    O.Add('createdAt', R[0][7]);
    O.Add('isImage', Copy(R[0][5], 1, 6) = 'image/');
    O.Add('versions', TJSONArray.Create);
    SendJson(aResponse, O.AsJSON);
  finally O.Free; end;
end;

function DeleteStoredAttachment(const T:TWLTenant;const Actor,BoardId,AttachmentId:string;
  const CardId:string):Boolean;
var Db:TWLDb;Scope,Permission,Bindings,Sql,BatchId,Path:string;Policy:TFieldPolicy;Selector:TSelectionScope;I:Integer;
begin
  Db:=T.Db;
  Selector:=TSelectionScope.Create(Db);
  try
    Scope:='id='+QuotedStr(AttachmentId)+' AND boardId='+QuotedStr(BoardId)+
      ' AND '+Selector.StringField('attachments','id')+' AND '+Selector.StringField('attachments','boardId');
    if CardId<>'' then
      Scope:=Scope+' AND cardId='+QuotedStr(CardId)+' AND '+Selector.StringField('attachments','cardId')+
        ' AND (SELECT count(*) FROM cards WHERE id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+
        ' AND archived=0 AND deletedAt IS NULL AND '+Selector.StringField('cards','id')+
        ' AND '+Selector.StringField('cards','boardId')+')=1';
    Bindings:='';for I:=0 to Selector.Bindings.Count-1 do Bindings:=Bindings+Selector.Bindings[I];
  finally Selector.Free;end;
  Policy:=TFieldPolicy.Create(Db,Actor,BoardId,'');
  try Permission:=Policy.ScopeBoardExpression(True);finally Policy.Free;end;
  if CardId<>'' then Permission:='('+Permission+' OR '+AssignedWriterSql(Actor,BoardId,CardId)+')';
  if not SharedStore(Db) then
  begin
    Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN '+Permission+
      ' AND (SELECT count(*) FROM attachments WHERE '+Scope+')=1 THEN 1 ELSE json(''Attachment scope changed'') END; '+
      'DELETE FROM attachments WHERE '+Scope+'; COMMIT;';
    Result:=Db.Exec(Sql);
    if not Result then Db.Exec('ROLLBACK;')
    else
    begin
      Path:=StoreFilePath(T.FilesDir,'attachme',AttachmentId);
      if FileExists(Path) then DeleteFile(Path);
    end;
    Exit;
  end;
  BatchId:=NewId;
  Sql:='BEGIN IMMEDIATE; '+Bindings+'SELECT CASE WHEN '+Permission+
    ' AND (SELECT count(*) FROM attachments WHERE '+Scope+')=1 THEN 1 ELSE json(''Attachment scope changed'') END; '+
    SharedAttachmentRemovalSQL(Db,Actor,BoardId,Scope,QuotedStr(BatchId),True)+
    Bindings+'SELECT CASE WHEN '+Permission+' AND (SELECT count(*) FROM attachments WHERE '+Scope+
    ')=1 THEN 1 ELSE json(''Attachment scope changed'') END; COMMIT;';
  Result:=Db.Exec(Sql);
  if not Result then Db.Exec('ROLLBACK;')
  else RetrySharedAttachmentHistory(Db,BoardId,AttachmentId);
end;

procedure ApiAttachmentDelete(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,Id:string;Rows:TWLRows;Reply:TJSONObject;Ok:Boolean;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  Id:=aRequest.RouteParams['attachmentId'];
  if not LoadAttachment(aResponse,T.Db,Id,Rows) then Exit;
  if AttachmentWriteAllowed(T.Db,UserId,Rows[0][0],Rows[0][3],'attachment-api:delete')<>200 then
  begin SendError(aResponse,403,'You do not have permission to delete this attachment');Exit;end;
  // The card in the delete's own guard only for an assigned-only writer,
  // whose write is that card's; a board writer deletes as before.
  if AssignedOnlyMember(T.Db,UserId,Rows[0][0]) then Ok:=DeleteStoredAttachment(T,UserId,Rows[0][0],Id,Rows[0][3])
  else Ok:=DeleteStoredAttachment(T,UserId,Rows[0][0],Id);
  if not Ok then
  begin SendError(aResponse,500,'Could not delete attachment');Exit;end;
  Reply:=TJSONObject.Create(['success',True,'attachmentId',Id,'fileName',Rows[0][4]]);
  try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
end;

// GET /api/boards/:boardId/attachments — list a board's attachments
procedure ApiBoardAttachments(aRequest: TRequest; aResponse: TResponse);
var T: TWLTenant; UserId: string; R: TWLRows; A: TJSONArray; O: TJSONObject; i: Integer;
begin
  if not ApiTenant(aRequest, aResponse, T) then Exit;
  if not ApiAuth(T, aRequest, aResponse, UserId) then Exit;
  if not ApiBoardGuard(T, aRequest, aResponse, UserId) then Exit;
  R := T.Db.Query(Format(
    'SELECT id,name,cardId FROM attachments WHERE boardId=%s AND %s ORDER BY createdAt,id;',
    [QuotedStr(aRequest.RouteParams['boardId']),LiveAttachmentSQL(T.Db)]));
  A := TJSONArray.Create;
  try
    for i := 0 to High(R) do
      if Length(R[i]) >= 3 then
      begin
        O := TJSONObject.Create;
        O.Add('_id', R[i][0]); O.Add('name', R[i][1]); O.Add('cardId', R[i][2]);
        A.Add(O);
      end;
    SendJson(aResponse, A.AsJSON);
  finally A.Free; end;
end;

// GET /api/attachment/list/:boardId/:swimlaneId/:listId/:cardId — a card's attachments
procedure ApiCardAttachmentsList(aRequest:TRequest;aResponse:TResponse);
var T:TWLTenant;UserId,Board,Lane,List,Card,Scope:string;Rows:TWLRows;Row:TWLRow;
  Attachments:TJSONArray;Reply:TJSONObject;Selector:TSelectionScope;
  function OptionalRouteId(const Key:string):string;
  begin
    Result:=aRequest.RouteParams[Key];
    if Result='null' then Result:='';
  end;
  procedure AddScope(const Field,Value:string);
  begin
    if Value<>'' then Scope:=Scope+' AND '+Field+'='+QuotedStr(Value)+' AND '+Selector.StringField('attachments',Field);
  end;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  Board:=aRequest.RouteParams['boardId'];Lane:=OptionalRouteId('swimlaneId');
  List:=OptionalRouteId('listId');Card:=OptionalRouteId('cardId');
  // board.hasMember: an assigned-only member too, of their own cards only.
  if not (BoardCanRead(T.Db,UserId,Board) or BoardHasMember(T.Db,UserId,Board)) then
  begin SendError(aResponse,403,'You do not have permission to access this board');Exit;end;
  if not ApiChildrenBelong(T.Db,Board,Lane,List,Card,'','','','') then
  begin SendJson(aResponse,'{"success":false,"message":"Attachment scope not found"}',404);Exit;end;
  Selector:=TSelectionScope.Create(T.Db);
  try
    Scope:='boardId='+QuotedStr(Board)+' AND '+Selector.StringField('attachments','boardId')+
      ' AND '+Selector.StringField('attachments','id')+' AND '+LiveAttachmentSQL(T.Db);
    AddScope('swimlaneId',Lane);AddScope('listId',List);AddScope('cardId',Card);
    if AssignedOnlyMember(T.Db,UserId,Board) then
      Scope:=Scope+' AND cardId IN (SELECT a.cardId FROM card_assignees a WHERE a.userId='+QuotedStr(UserId)+')';
    Rows:=T.Db.Query('SELECT id,name,type,size,createdAt,storageBackend,boardId,swimlaneId,listId,cardId '+
      'FROM attachments WHERE '+Scope+' ORDER BY createdAt,id;');
  finally Selector.Free;end;
  Reply:=TJSONObject.Create;
  try
    Attachments:=TJSONArray.Create;
    Reply.Add('attachments',Attachments);
    for Row in Rows do
      Attachments.Add(TJSONObject.Create(['attachmentId',Row[0],'fileName',Row[1],'fileType',Row[2],
        'fileSize',StrToInt64Def(Row[3],0),'createdAt',Row[4],'storageBackend',Row[5],
        'boardId',Row[6],'swimlaneId',Row[7],'listId',Row[8],'cardId',Row[9],'isImage',Copy(Row[2],1,6)='image/']));
    Reply.Add('success',True);
    Reply.Add('count',Attachments.Count);
    SendJson(aResponse,Reply.AsJSON);
  finally Reply.Free;end;
end;


function MarkAllNotificationsRead(Db: TWLDb; const UserId: string): Boolean;
begin
  Result := Db.Exec('UPDATE users SET profile_json=json_set(profile_json,''$.notifications'',(SELECT json_group_array(json(v)) FROM (SELECT ' +
    'CASE WHEN json_extract(n.value,''$.read'') IS NULL THEN json_set(n.value,''$.read'',strftime(''%Y-%m-%dT%H:%M:%fZ'',''now'')) ' +
    'ELSE n.value END AS v FROM json_each(json_extract(profile_json,''$.notifications'')) n ORDER BY n.key))) WHERE id=' + QuotedStr(UserId) +
    ' AND json_valid(profile_json) AND json_type(profile_json,''$.notifications'')=''array'';');
end;

function DeleteAllNotifications(Db: TWLDb; const UserId: string): Boolean;
begin
  Result := Db.Exec('UPDATE users SET profile_json=json_set(CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END,' +
    '''$.notifications'',json(''[]'')) WHERE id=' + QuotedStr(UserId) + ';');
end;


function ViewUsersUpdate(Db:TWLDb;const UserId,Content:string):Integer;
var Args,Selector,Modifier,Ops,Value,Field:TJSONData;i,j,Index:Integer;Op,Path,Sql,Profile,Stored,At:string;Tray,Other:Boolean;
  function IsIsoInstant(const V:string):Boolean;
  const Shape='dddd-dd-ddTdd:dd:dd.dddZ';
  var k:Integer;
  begin
    Result:=Length(V)=Length(Shape);
    if Result then
      for k:=1 to Length(Shape) do
        if ((Shape[k]='d') and not (V[k] in ['0'..'9'])) or ((Shape[k]<>'d') and (V[k]<>Shape[k])) then Exit(False);
  end;
  // profile.notifications.<n>.read: the n.
  function ReadIndex(const P:string):Integer;
  const Prefix='profile.notifications.';
  var Rest:string;k:Integer;
  begin
    Result:=-1;
    if (Copy(P,1,Length(Prefix))<>Prefix) or (Copy(P,Length(P)-4,5)<>'.read') then Exit;
    Rest:=Copy(P,Length(Prefix)+1,Length(P)-Length(Prefix)-5);
    if (Rest='') or (Length(Rest)>6) then Exit;
    for k:=1 to Length(Rest) do if not (Rest[k] in ['0'..'9']) then Exit;
    Result:=StrToInt(Rest);
  end;
begin
  Result:=403;Args:=nil;Sql:='';Tray:=False;Other:=False;
  Profile:='CASE WHEN json_valid(profile_json) THEN profile_json ELSE ''{}'' END';
  try
    try Args:=GetJSON(Content);except Exit(400);end;
    if not (Args is TJSONArray) or (TJSONArray(Args).Count<2) then Exit(400);
    Selector:=TJSONArray(Args).Items[0];Modifier:=TJSONArray(Args).Items[1];
    if not (Modifier is TJSONObject) or (TJSONObject(Modifier).Count=0) then Exit(400);
    for i:=0 to TJSONObject(Modifier).Count-1 do
    begin
      Op:=TJSONObject(Modifier).Names[i];Ops:=TJSONObject(Modifier).Items[i];
      if not (Ops is TJSONObject) then begin Other:=True;Continue;end;
      for j:=0 to TJSONObject(Ops).Count-1 do
      begin
        Path:=TJSONObject(Ops).Names[j];Value:=TJSONObject(Ops).Items[j];
        if (Path<>'profile.notifications') and (Copy(Path,1,22)<>'profile.notifications.') then begin Other:=True;Continue;end;
        Index:=ReadIndex(Path);
        At:='''$.notifications['+IntToStr(Index)+']''';
        if (Op='$unset') and (Index>=0) then
          Sql:=Sql+'UPDATE users SET profile_json=json_remove('+Profile+',''$.notifications['+IntToStr(Index)+'].read'') WHERE id='+
            QuotedStr(UserId)+' AND json_type('+Profile+','+At+')=''object''; '
        else if (Op='$set') and (Index>=0) then
        begin
          // Read at a date - EJSON's {"$date":ms} - or unread, null.
          Field:=nil;
          if Value is TJSONObject then Field:=TJSONObject(Value).Find('$date');
          if Value.JSONType=jtNull then Stored:='json(''null'')'
          else if (Field<>nil) and (Field.JSONType=jtNumber) and (TJSONObject(Value).Count=1) then
            Stored:='strftime(''%Y-%m-%dT%H:%M:%fZ'','+FloatToStr(Field.AsFloat/1000,DefaultFormatSettings)+',''unixepoch'')'
          // JSON.stringify's date, 2026-11-26T10:00:00.000Z, and no other text.
          else if (Value.JSONType=jtString) and IsIsoInstant(Value.AsString) then Stored:=QuotedStr(Value.AsString)
          else begin Tray:=True;Continue;end;
          Sql:=Sql+'UPDATE users SET profile_json=json_set('+Profile+',''$.notifications['+IntToStr(Index)+'].read'','+Stored+
            ') WHERE id='+QuotedStr(UserId)+' AND json_type('+Profile+','+At+')=''object''; ';
        end
        else if (Op='$pull') and (Path='profile.notifications') and (Value is TJSONObject) and (TJSONObject(Value).Count=1) and
          (TJSONObject(Value).Find('activity')<>nil) and (TJSONObject(Value).Find('activity').JSONType=jtString) then
          Sql:=Sql+'UPDATE users SET profile_json=json_set('+Profile+',''$.notifications'',(SELECT json_group_array(json(v)) FROM '+
            '(SELECT n.value AS v FROM json_each('+Profile+',''$.notifications'') n WHERE COALESCE(json_extract(n.value,''$.activity''),'''')<>'+
            QuotedStr(TJSONObject(Value).Find('activity').AsString)+' ORDER BY n.key))) WHERE id='+QuotedStr(UserId)+
            ' AND json_type('+Profile+',''$.notifications'')=''array''; '
        else Tray:=True;
      end;
    end;
    if Tray then
    begin
      // No WeLite page adds to or rewrites the tray: only an attempt reaches here.
      try
        RecordSecurityDenial(Db,UserId,'TrayBleed','ddp:user-notifications','authz','high','CWE-639',
          'Client write of server-issued notification entries denied.');
      except { logging must never break the guard } end;
      Exit(403);
    end;
    if Other or (Sql='') then Exit(403);
    // Only the user's own account.
    if not (Selector is TJSONObject) or (TJSONObject(Selector).Count<>1) or (TJSONObject(Selector).Find('_id')=nil) or
      (TJSONObject(Selector).Find('_id').JSONType<>jtString) or (TJSONObject(Selector).Find('_id').AsString<>UserId) then Exit(403);
    if Db.Exec('BEGIN IMMEDIATE; '+Sql+'COMMIT;') then Result:=200
    else begin Db.Exec('ROLLBACK;');Result:=500;end;
  finally Args.Free;end;
end;


function ViewSetPassword(const T:TWLTenant;const Actor,Target,Password:string;out Error:string):Integer;
var Rows:TWLRows;MinLength:Integer;Enforce:Boolean;
begin
  Error:='';
  if (Actor='') or ((Actor<>Target) and not IsSiteAdmin(T.Db,Actor)) then begin Error:='Access denied';Exit(403);end;
  if (Target='') or (Pos(#0,Target+Password)>0) or (Length(Password)>4096) or (Password='') then
  begin Error:='error-password-policy';Exit(400);end;
  Rows:=T.Db.Query('SELECT COALESCE(authenticationMethod,'''') FROM users WHERE id='+QuotedStr(Target)+';');
  if Length(Rows)<>1 then begin Error:='User not found';Exit(404);end;
  if (Rows[0][0]<>'') and (Rows[0][0]<>'password') then begin Error:='This account uses an external sign-in provider.';Exit(400);end;
  PasswordPolicy(T.Db,MinLength,Enforce);
  if Enforce and (Length(UTF8Decode(Password))<MinLength) then begin Error:='error-password-policy';Exit(400);end;
  if not T.Db.Exec('BEGIN IMMEDIATE; '+RevokeUserTokensSQL(T.Db,Target)+'UPDATE users SET services_json=json_set(CASE WHEN json_valid(services_json) '+
    'THEN services_json ELSE ''{}'' END,''$.password'',json('+QuotedStr(HashMeteorPassword(Password))+')) WHERE id='+QuotedStr(Target)+'; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not update account';Exit(500);end;
  Result:=200;
end;

end.
