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

{$mode objfpc}{$H+}
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
procedure BrowserBoardExport(aRequest:TRequest;aResponse:TResponse);
procedure ApiImportBoard(aRequest:TRequest;aResponse:TResponse);
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
function CreateViewCard(const T:TWLTenant;const UserId,BoardId,ListId,Swimlane,Title,Position:string;
  out CardId,Error:string):Integer;
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
function BoardCanAdmin(Db:TWLDb;const UserId,BoardId:string):Boolean;
// The board's new title, as PUT /api/boards/:boardId/title renames it.
function RenameBoard(const T:TWLTenant;const UserId,BoardId,Title:string;out Error:string):Integer;
// WeKan's toggleBoardStar: the board in the user's starredBoards, or out of it.
function ToggleViewBoardStar(Db:TWLDb;const UserId,BoardId:string;out Error:string):Integer;
// archivesSidebar's restore of an archived card, list or swimlane (Kind
// cards, lists or swimlanes) of the board.
function RestoreViewItem(const T:TWLTenant;const UserId,BoardId,Kind,ItemId:string;out Error:string):Integer;
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
function MoveViewCard(const T:TWLTenant;const UserId,BoardId,CardId,DestBoard,DestLane,DestList:string;out Error:string):Integer;
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

implementation
uses wlstore,wlsjson,Math,wlcfjson,wlcfpol,wlpath,wlcfspec,wlselscp,wlcolors,wlposhis,wlrevoke,wlautsrc,wli18n,wllocale,wlselect,wlferr,wlwhurl,wlhtml,wlshared,wlattdel,wlroutes;

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
  aResponse.SendContent;
end;

procedure SendError(aResponse: TResponse; Code: Integer; const Reason: string);
begin
  SendJson(aResponse, Format('{"error":%d,"reason":%s}', [Code, AnsiQuotedStr(Reason, '"')]), Code);
end;

function ApiBodyValid(Request:TRequest):Boolean;
var D:TJSONData;
begin
  Result:=True;
  if (Request.Method='GET') or (Request.Content='') or
    (Pos('application/json',LowerCase(Request.ContentType))<>1) then Exit;
  D:=nil;
  try
    try D:=GetJSON(Request.Content); Result:=D is TJSONObject; except Result:=False; end;
  finally D.Free; end;
end;

// Resolve the tenant for an API request, or send a JSON error. Static, no web session needed.
function ApiTenant(aRequest: TRequest; aResponse: TResponse; out T: TWLTenant): Boolean;
begin
  if not DecodeApiPath(aRequest) then
  begin Result:=False;SendError(aResponse,400,'Invalid encoded route identifier');Exit;end;
  Result := ResolveTenant(aRequest, T) and TenantOpen(T);
  if not Result then SendError(aResponse,404,'Unknown domain')
  else if not ApiBodyValid(aRequest) then
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
function RestoreViewItem(const T:TWLTenant;const UserId,BoardId,Kind,ItemId:string;out Error:string):Integer;
var Table,Scope,Extra:string;
begin
  Error:='';
  if (BoardId='') or (ItemId='') or (Pos(#0,BoardId+ItemId)>0) then begin Error:='Not found';Exit(404);end;
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  Extra:='';
  if Kind='cards' then begin Table:='cards';Extra:=' AND deletedAt IS NULL';end
  else if Kind='lists' then begin Table:='lists';Extra:=' AND deletedAt IS NULL';end
  else if Kind='swimlanes' then Table:='swimlanes'
  else begin Error:='Not found';Exit(404);end;
  Scope:='id='+QuotedStr(ItemId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=1'+Extra;
  if Length(T.Db.Query('SELECT 1 FROM '+Table+' WHERE '+Scope+';'))<>1 then begin Error:='Not found';Exit(404);end;
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE '+Table+' SET archived=0,archivedAt=NULL,modifiedAt='+QuotedStr(NowIso)+' WHERE '+Scope+
    '; SELECT CASE WHEN (SELECT count(*) FROM '+Table+' WHERE id='+QuotedStr(ItemId)+' AND archived=0)=1 THEN 1 '+
    'ELSE json(''Restore failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not restore';Exit(500);end;
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
  Body,Rule,Trigger,Action,Reply:TJSONObject;Rows:TWLRows;
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
    Reply:=TJSONObject.Create(['_id',RuleId,'triggerId',TriggerId,'actionId',ActionId]);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  finally Rule.Free;Body.Free;end;
end;

procedure ApiEditRule(aRequest:TRequest;aResponse:TResponse);
const Doc='_ferretdb_sjson';
var T:TWLTenant;UserId,BoardId,RuleId,Permission,Guard,RuleTable,RuleScope,RuleRaw,Sql,Bindings:string;
  Rows:TWLRows;Body,Rule:TJSONObject;Value:TJSONData;Policy:TFieldPolicy;
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
    SendJson(aResponse,'{"_id":"'+StringToJSONString(RuleId)+'"}');
  finally Rule.Free;Body.Free;end;
end;

procedure ApiDeleteRule(aRequest:TRequest;aResponse:TResponse);
const Doc='_ferretdb_sjson';NotFound='{"error":"Rule not found"}';
var T:TWLTenant;Actor,BoardId,RuleId,Permission,Scope,Source,Original,Bindings,Sql:string;
  Rows:TWLRows;Rule:TJSONObject;Policy:TFieldPolicy;
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
  Rule:=nil;Bindings:='';
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
      if not T.Db.Exec(Sql) then raise Exception.Create('Rule removal failed');
    except T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not delete rule');Exit;end;
    SendJson(aResponse,'{"_id":"'+StringToJSONString(RuleId)+'"}');
  finally Rule.Free;end;
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
      aResponse.SendContent;
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
      aResponse.SendContent;
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
      aResponse.SendContent;
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

procedure BoardExport(aRequest:TRequest;aResponse:TResponse;Browser:Boolean);
var T:TWLTenant;UserId,BoardId,Key,TableName:string;Payload:TJSONObject;Rows:TWLRows;Session:TWLSession;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if Browser then
  begin
    if not ValidateSession(T.Db,aRequest,SessionIdFromRequest(aRequest),Session) then
    begin SendError(aResponse,401,'Sign in to download a board');Exit;end;
    UserId:=Session.UserId;BoardId:=aRequest.QueryFields.Values['id'];
    if (BoardId='') or (Pos(#0,BoardId)>0) then
    begin SendError(aResponse,400,'Invalid board ID');Exit;end;
  end else
  begin
    if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
    BoardId:=aRequest.RouteParams['boardId'];
  end;
  if not ApiAuthBoard(T,aResponse,UserId,BoardId,False) then Exit;
  for Key in ['swimlaneId','listId','cardId','checklistId','fields'] do
    if aRequest.QueryFields.IndexOfName(Key)>=0 then
    begin SendError(aResponse,400,'Scoped export is unavailable');Exit;end;
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
  try
    Payload:=ReadRestBoardExport(T,UserId,BoardId,aRequest.QueryFields.Values['attachments']<>'false');
  except SendError(aResponse,500,'Could not export board');Exit;end;
  if Payload=nil then begin SendError(aResponse,403,'Board export forbidden');Exit;end;
  try
    if Browser then
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

function CardDateSql(Value:TJSONData;out Literal:string):Boolean; forward;

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

procedure ApiImportBoard(aRequest:TRequest;aResponse:TResponse);
const Collections:array[0..11] of string=('swimlanes','lists','cards','triggers','actions','rules',
  'comments','checklists','checklistItems','attachments','customFields','labels');
var T:TWLTenant;Actor,BoardId,Board,Title,AdminOnly,PrivateOnly,RegistryGuard,Permission,Stamp,Guard,Sql,Name,CardId,CardAuthor,CardCreated,DefaultLane,DefaultList,ListId,LaneId:string;
  Body,Input,Row,Reply,MemberMap,CardCreations,ImportedListLanes:TJSONObject;Maps:array[0..11] of TJSONObject;Arrays:array[0..11] of TJSONArray;
  Value:TJSONData;Rows:TWLRows;CardNumbers:array of Int64;I,J:Integer;Files,ImportedMembers:TStringList;Committed:Boolean;
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
  function Mapped(Index:Integer;const Id:string;Required:Boolean=False):string;
  begin
    Result:=Maps[Index].Get(Id,'');
    if Required and (Result='') then raise EConvertError.Create('Invalid import reference');
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
        Sql:=Sql+Format('INSERT INTO custom_fields(id,name,type,showOnCard,automaticallyOnCard,'+
          'showLabelOnMiniCard,showSumAtTopOfList,readOnly,adminOnly,alwaysOnCard,createdAt,modifiedAt,'+
          'currencyCode,stringtemplateFormat,stringtemplateSeparator,settings_json) '+
          'VALUES(%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%s,%s,%s,%s,%s,%s); ',
          [Id,QuotedStr(FieldName),QuotedStr(Kind),Flags[0],Flags[1],Flags[2],Flags[3],Flags[4],Flags[5],
           AlwaysOn,Stamp,Stamp,SettingsLiteral(Settings,'currencyCode'),SettingsLiteral(Settings,'stringtemplateFormat'),
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
  procedure CardPlacement(Obj:TJSONObject;out ListKey,LaneKey:string);
  begin
    ListKey:=Mapped(1,Text(Obj,'listId'));
    if ListKey='' then ListKey:=DefaultList;
    LaneKey:=ImportedListLanes.Get(ListKey,'');
    if LaneKey='' then LaneKey:=Mapped(0,Text(Obj,'swimlaneId'));
    if LaneKey='' then LaneKey:=DefaultLane;
  end;
  function SortValue(Obj:TJSONObject):string;
  var Field:TJSONData;
  begin
    Result:='0';Field:=Obj.Find('sort');
    if (Field<>nil) and (Field.JSONType=jtNumber) and not IsNan(Field.AsFloat) and not IsInfinite(Field.AsFloat) then
      Result:=Field.AsJSON;
  end;
  function ImportedDate(Obj:TJSONObject;const Key,Fallback:string):string;
  var Field:TJSONData;
  begin
    Result:=Fallback;Field:=Obj.Find(Key);
    if (Field=nil) or (Field.JSONType=jtNull) then Exit;
    if not CardDateSql(Field,Result) then raise EConvertError.Create('Invalid imported date');
    if Result='NULL' then Result:=Fallback;
  end;
  function BooleanValue(Obj:TJSONObject;const Key:string):string;
  var Field:TJSONData;
  begin
    Field:=Obj.Find(Key);
    Result:=IntToStr(Ord((Field is TJSONBoolean) and Field.AsBoolean));
  end;
  function ImportedCollapse(Entry:TJSONObject):string;
  var Field:TJSONData;
  begin
    Field:=Entry.Find('collapsed');
    if not (Field is TJSONBoolean) then Exit('NULL');
    Result:=BooleanValue(Entry,'collapsed');
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
      Entry:=Arrays[9].Objects[K];Id:=Mapped(9,Text(Entry,'_id'),True);
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
      FileField:=Entry.Find('file');
      if not (FileField is TJSONString) then raise EConvertError.Create('Attachment bytes missing');
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
        ','+IntToStr(Length(Bytes))+',''filesystem'','+QuotedStr(ImportedAuthor(Entry))+','+Stamp+'); ';
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
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,Actor) then Exit;
  Body:=nil;Guard:='1';Committed:=False;Files:=TStringList.Create;
  MemberMap:=TJSONObject.Create;CardCreations:=TJSONObject.Create;ImportedListLanes:=TJSONObject.Create;ImportedMembers:=TStringList.Create;ImportedMembers.CaseSensitive:=True;
  for I:=0 to High(Maps) do Maps[I]:=nil;
  try
    try
      try Body:=ExactObject(aRequest.Content);
      except raise EConvertError.Create('Invalid board export JSON');end;
      Value:=Body.Find('board');
      if not (Value is TJSONObject) then raise EConvertError.Create('Missing board export');
      Input:=TJSONObject(Value);
      Name:=Text(Input,'_format');
      if (Name<>'') and (Name<>'wekan-board-1.0.0') then raise EConvertError.Create('Invalid board export format');
      Title:=Text(Input,'title');
      if Trim(Title)='' then raise EConvertError.Create('Missing board title');
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
      AllocateCardNumbers;
      IndexCardCreations;
      BoardCreationSettings(T.Db,AdminOnly,PrivateOnly,RegistryGuard);
      Permission:='EXISTS(SELECT 1 FROM users WHERE id='+QuotedStr(Actor)+
        ' AND COALESCE(loginDisabled,0)=0 AND (isAdmin=1 OR NOT '+AdminOnly+'))';
      ReadImportPolicy;
      Rows:=T.Db.Query('SELECT '+Permission+';');
      if (Length(Rows)<>1) or (Rows[0][0]<>'1') then
      begin SendError(aResponse,403,'Board import is restricted');Exit;end;
      ReadMemberMapping;
      BoardId:=NewId;Board:=QuotedStr(BoardId);Stamp:=QuotedStr(NowIso);
      Name:=Text(Input,'color','belize');if Name='' then Name:='belize';
      Sql:='INSERT INTO boards(id,title,slug,description,permission,color,createdAt,modifiedAt) VALUES('+
        Board+','+QuotedStr(Title)+','+QuotedStr(Slugify(Title))+','+QuotedStr(Text(Input,'description'))+
        ',''private'','+QuotedStr(Name)+','+Stamp+','+Stamp+'); '+
        'INSERT INTO board_members(boardId,userId,isActive,isAdmin) VALUES('+Board+','+QuotedStr(Actor)+',1,1); ';
      ImportInactiveMembers;
      ImportDefinitions;
      ImportLabels;
      DefaultLane:='';DefaultList:='';
      if Arrays[0]<>nil then for J:=0 to Arrays[0].Count-1 do
      begin
        Row:=Arrays[0].Objects[J];LaneId:=Mapped(0,Text(Row,'_id'),True);
        if DefaultLane='' then DefaultLane:=LaneId;
        Sql:=Sql+'INSERT INTO swimlanes(id,boardId,title,sort,createdAt,color,archived) VALUES('+QuotedStr(LaneId)+
          ','+Board+','+QuotedStr(Text(Row,'title','Default'))+','+SortValue(Row)+','+Stamp+','+
          ImportedColor(Row)+','+BooleanValue(Row,'archived')+'); ';
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
        LaneId:=Mapped(0,Text(Row,'swimlaneId'));
        if DefaultList='' then DefaultList:=ListId;
        ImportedListLanes.Add(ListId,LaneId);
        Sql:=Sql+'INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt,color,width,archived,collapsed) VALUES('+
          QuotedStr(ListId)+','+Board+','+QuotedStr(LaneId)+','+
          QuotedStr(Text(Row,'title'))+','+SortValue(Row)+','+Stamp+','+ImportedColor(Row)+','+
          ImportedListWidth(Row)+','+BooleanValue(Row,'archived')+','+ImportedCollapse(Row)+'); ';
      end;
      if (DefaultList='') and (Arrays[2]<>nil) and (Arrays[2].Count>0) then
      begin
        DefaultList:=NewId;
        Sql:=Sql+'INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES('+QuotedStr(DefaultList)+
          ','+Board+','''',''Default'',0,'+Stamp+'); ';
      end;
      if Arrays[2]<>nil then for J:=0 to Arrays[2].Count-1 do
      begin
        Row:=Arrays[2].Objects[J];CardId:=Mapped(2,Text(Row,'_id'),True);
        CardCreation(Row,CardId,CardAuthor,CardCreated);
        CardPlacement(Row,ListId,LaneId);
        Sql:=Sql+'INSERT INTO cards(id,boardId,listId,swimlaneId,parentId,title,description,userId,sort,cardNumber,'+
          'createdAt,modifiedAt,dateLastActivity,receivedAt,startAt,dueAt,endAt,spentTime,isOvertime,requestedBy,assignedBy,archived,color) VALUES('+
          QuotedStr(CardId)+','+Board+','+
          QuotedStr(ListId)+','+QuotedStr(LaneId)+','+
          Optional(Mapped(2,Text(Row,'parentId')))+','+QuotedStr(Text(Row,'title'))+','+
          QuotedStr(Text(Row,'description'))+','+QuotedStr(CardAuthor)+','+SortValue(Row)+','+IntToStr(CardNumbers[J])+
          ','+CardCreated+','+Stamp+','+Stamp+','+
          ImportedDate(Row,'receivedAt','NULL')+','+ImportedDate(Row,'startAt','NULL')+','+
          ImportedDate(Row,'dueAt','NULL')+','+ImportedDate(Row,'endAt','NULL')+','+
          ImportedSpentTime(Row)+','+BooleanValue(Row,'isOvertime')+','+QuotedStr(Text(Row,'requestedBy'))+','+
          QuotedStr(Text(Row,'assignedBy'))+','+BooleanValue(Row,'archived')+','+ImportedColor(Row)+'); ';
        ImportCardPeople(Row,CardId);
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
      on E:EConvertError do begin SendError(aResponse,400,'Invalid board export');Exit;end;
      on E:Exception do begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not import board');Exit;end;
    end;
    Reply:=TJSONObject.Create(['_id',BoardId]);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  finally
    if not Committed then for I:=0 to Files.Count-1 do DeleteFile(Files[I]);
    ImportedMembers.Free;ImportedListLanes.Free;CardCreations.Free;MemberMap.Free;Files.Free;
    for I:=0 to High(Maps) do Maps[I].Free;
    Body.Free;
  end;
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

procedure ApiSwimlane(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"Swimlane not found"}';
var T:TWLTenant;UserId,BoardId,LaneId,Scope,Title,Permission,Sql:string;
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
  if Length(T.Db.Query('SELECT id FROM swimlanes WHERE '+Scope+';'))<>1 then
  begin SendJson(aResponse,NotFound,404);Exit;end;
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
var Stamp,Sql,GuardSql,DropdownSql,DropdownGuards:string;Data:TJSONObject;Rows:TWLRows;Policy:TFieldPolicy;
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
    Sql:='BEGIN IMMEDIATE; '+DropdownGuards+GuardSql+Format(
      'INSERT INTO custom_fields(id,name,type,showOnCard,automaticallyOnCard,'+
      'showLabelOnMiniCard,showSumAtTopOfList,readOnly,adminOnly,createdAt,modifiedAt,currencyCode,stringtemplateFormat,stringtemplateSeparator,settings_json) VALUES(%s,%s,%s,%d,%d,%d,%d,%d,%d,%s,%s,%s,%s,%s,%s);',
      [QuotedStr(Id),QuotedStr(Name),QuotedStr(Typ),Flags[0],Flags[1],Flags[2],Flags[3],Flags[4],Flags[5],QuotedStr(Stamp),QuotedStr(Stamp),SettingsLiteral(Settings,'currencyCode'),
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
var T:TWLTenant;UserId,BoardId,ListId,Scope,Sets,Permission,Value,Sql:string;
  Body,Reply:TJSONObject;Field,Wip:TJSONData;Rows:TWLRows;Policy:TFieldPolicy;
  Flag,i:Integer;Limit:Int64;Wide:UnicodeString;
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
  Rows:=T.Db.Query('SELECT id FROM lists WHERE '+Scope+';');
  if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
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
        SetColumn('title',QuotedStr(Value));
      end;
      Field:=Body.Find('color');
      if (Field<>nil) and (Field.JSONType<>jtNull) and (Field.AsString<>'') then
      begin
        Value:=Field.AsString;
        if (ResolveColor(Value)='') or ((Value[1]='#') and (Length(Value)<>7)) or
          ((Value[1]<>'#') and (NormalizeHex(Value)<>'')) then
        begin SendJson(aResponse,'{"error":"Invalid list color. Use a named palette color or a #rrggbb hex value."}',400);Exit;end;
        SetColumn('color',QuotedStr(Value));
      end;
      Field:=Body.Find('starred');
      if Field<>nil then
      begin
        if not DefinitionFlag(Field,Flag) then raise Exception.Create('Invalid starred value');
        SetColumn('starred',IntToStr(Flag));
      end;
      Wip:=Body.Find('wipLimit');
      if (Wip<>nil) and (Wip.JSONType<>jtNull) then
      begin
        if not (Wip is TJSONObject) then raise Exception.Create('Invalid WIP value');
        Field:=TJSONObject(Wip).Find('value');Limit:=1;
        if Field<>nil then
          if not TryStrToInt64(Field.AsJSON,Limit) then raise Exception.Create('Invalid WIP limit');
        SetColumn('wip_value',IntToStr(Limit));
        if not DefinitionFlag(TJSONObject(Wip).Find('enabled'),Flag) then raise Exception.Create('Invalid WIP enabled flag');
        SetColumn('wip_enabled',IntToStr(Flag));
        if not DefinitionFlag(TJSONObject(Wip).Find('soft'),Flag) then raise Exception.Create('Invalid WIP soft flag');
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
    Reply:=TJSONObject.Create(['_id',ListId]);
    try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
  finally Policy.Free;Body.Free;end;
end;

procedure ApiListArchive(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"List not found"}';
var T:TWLTenant;UserId,BoardId,ListId,Scope,Predicate,Stamp,CardArchivedAt,Sql:string;
  Archive:Boolean;Target:string;Rows:TWLRows;Reply:TJSONObject;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  BoardId:=QuotedStr(aRequest.RouteParams['boardId']);ListId:=aRequest.RouteParams['listId'];
  Archive:=Copy(aRequest.PathInfo,Length(aRequest.PathInfo)-9,10)<>'/unarchive';
  Target:=IntToStr(Ord(Archive));
  Scope:='id='+QuotedStr(ListId)+' AND boardId='+BoardId+' AND deletedAt IS NULL';
  Predicate:=Scope+' AND archived='+IntToStr(Ord(not Archive));
  Rows:=T.Db.Query('SELECT id FROM lists WHERE '+Predicate+';');
  if Length(Rows)<>1 then begin SendJson(aResponse,NotFound,404);Exit;end;
  Stamp:=QuotedStr(NowIso);CardArchivedAt:='NULL';
  if Archive then CardArchivedAt:=Stamp;
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+Predicate+
    ')=1 THEN 1 ELSE json(''List archive scope changed'') END; '+
    'UPDATE cards SET archived='+Target+',archivedAt='+CardArchivedAt+' WHERE listId='+QuotedStr(ListId)+
    ' AND boardId='+BoardId+' AND deletedAt IS NULL AND archived<> '+Target+
    ' AND EXISTS(SELECT 1 FROM lists WHERE '+Predicate+' AND type=''template-list''); '+
    'UPDATE lists SET archived='+Target+',modifiedAt='+Stamp;
  if Archive then Sql:=Sql+',archivedAt='+Stamp;
  Sql:=Sql+' WHERE '+Predicate+'; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+Scope+
    ' AND archived='+Target+')=1 THEN 1 ELSE json(''List archive failed'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not change list archive state');Exit;end;
  Reply:=TJSONObject.Create(['_id',ListId,'archived',Archive]);
  try SendJson(aResponse,Reply.AsJSON);finally Reply.Free;end;
end;

function CardCreateSql(const BoardId,ListId,Lane,CardId,Author,Title,Descr,Parent,Sort:string;const LinkedId:string=''):string;
var Stamp,Board:string;
begin
  Stamp:=QuotedStr(NowIso);Board:=QuotedStr(BoardId);
  Result:='INSERT INTO cards(id,boardId,listId,swimlaneId,title,description,userId,parentId,'+
    'dateLastActivity,createdAt,modifiedAt,sort,cardNumber,type,linkedId) SELECT '+QuotedStr(CardId)+','+Board+','+
    QuotedStr(ListId)+','+QuotedStr(Lane)+','+QuotedStr(Title)+','+QuotedStr(Descr)+','+
    QuotedStr(Author)+','+Parent+','+Stamp+','+Stamp+','+Stamp+','+Sort+
    ',(SELECT max(0,coalesce(max(cardNumber),0))+1 FROM cards WHERE boardId='+Board+'),';
  if LinkedId='' then Result:=Result+'''cardType-card'',NULL; '
  else Result:=Result+'''cardType-linkedCard'','+QuotedStr(LinkedId)+'; ';
end;

// A refused attempt in a shared store's eventlog, as WeKan's securityLog
// records one (models/lib/eventLogSummary.js): one row per kind of attempt
// that counts them, never a row per attempt.
procedure RecordSecurityEvent(Db:TWLDb;const UserId,Bleed,Source,Category,Severity,Cwe,Action,Detail:string);
const Hints='{"at":"date","firstAt":"date"}';
var Rows:TWLRows;Event:TJSONObject;TableName,Physical,AtSql,Payload,Updated,Sql,Identity:string;
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
    Event:=TJSONObject.Create(['_id',NewId,'stream','security','at',AtMs,'firstAt',AtMs,
      'severity',Severity,'category',Category,'bleed',Bleed,'action',Action,'source',Source,
      'cwe',Cwe,'count',1,'userId',UserId,'detail',Detail]);
    try Payload:=QuotedStr(TypedDocument(Event.AsJSON,'',Hints));finally Event.Free;end;
    Updated:='wl_sjson(json_set(wl_plain(json(_ferretdb_sjson)),''$.at'','+AtSql+
      ',''$.userId'','+QuotedStr(UserId)+',''$.count'',MIN(9007199254740991,MAX(0,'+
      'COALESCE(json_extract(_ferretdb_sjson,''$.count''),0))+1)),json(_ferretdb_sjson),''{"at":"date"}'')';
    Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM _ferretdb_collections WHERE name=''eventlog'''+
      ' AND table_name='+QuotedStr(TableName)+')=1 THEN 1 ELSE json(''Event log source changed'') END; '+
      'UPDATE '+Physical+' SET _ferretdb_sjson='+Stored(Updated)+' WHERE rowid=(SELECT MIN(rowid) FROM '+Physical+
      ' WHERE '+Identity+'); INSERT INTO '+Physical+'(_ferretdb_sjson) SELECT '+Stored(Payload)+
      ' WHERE NOT EXISTS(SELECT 1 FROM '+Physical+' WHERE '+Identity+'); COMMIT;';
    if not Db.Exec(Sql) then Db.Exec('ROLLBACK;');
  except Db.Exec('ROLLBACK;');end;
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
      ' AND archived=0 AND deletedAt IS NULL)',LinkedId)+InitializeSharedAssignments(Db,BoardId,Id,True,True)+
    'INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt) VALUES('+
    QuotedStr(NewId)+',''createCard'','+QuotedStr(Actor)+','+Board+','+QuotedStr(Id)+','+
    ListKey+','+LaneKey+','+Stamp+','+Stamp+'); COMMIT;';
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

function CreateViewCard(const T:TWLTenant;const UserId,BoardId,ListId,Swimlane,Title,Position:string;
  out CardId,Error:string):Integer;
var Lane,Sort,InitialFields:string;
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
  CardId:=NewId;
  try InitialFields:=InitializeCardFields(T.Db,BoardId,CardId);
  except Error:='Could not initialize custom fields';Exit(500);end;
  if not T.Db.Exec('BEGIN IMMEDIATE; '+CardCreateSql(BoardId,ListId,Lane,CardId,UserId,Title,'',QuotedStr(''),Sort)+
    InitialFields+' COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');CardId:='';Error:='Could not create card';Exit(500);end;
  Result:=200;
end;

function RenameViewCard(const T:TWLTenant;const UserId,BoardId,CardId,Title:string;out Error:string):Integer;
var Scope,Stamp:string;
begin
  Error:='';
  if (BoardId='') or (CardId='') or (Trim(Title)='') or (Pos(#0,BoardId+CardId+Title)>0) then
  begin Error:='Invalid title';Exit(400);end;
  if not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  if not ApiChildrenBelong(T.Db,BoardId,'','',CardId,'','','','') then
  begin Error:='Card not found';Exit(404);end;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  Stamp:=QuotedStr(NowIso);
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET title='+QuotedStr(Title)+',modifiedAt='+Stamp+
    ',dateLastActivity='+Stamp+' WHERE '+Scope+'; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+
    ' AND title='+QuotedStr(Title)+')=1 THEN 1 ELSE json(''Card rename failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not rename card';Exit(500);end;
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
  if not BoardCanRead(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
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

procedure ApiCardEdit(aRequest:TRequest; aResponse:TResponse);
var T:TWLTenant; UserId,CardId,BoardId,Sets,Relations,Scope,ArchiveSql,Stamp,Value:string;
  HasArchive,Archive,HasEdits,HasOvertime,HasSort,HasTitle:Boolean;Body,Decorations:TJSONObject;Input:TJSONData;
  FieldName,FieldSets,Literal:string;HasDate:Boolean;SortNumber:Double;NumberFormat:TFormatSettings;
  Code:Integer;MoveError:string;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  CardId:=aRequest.RouteParams['cardId'];BoardId:=aRequest.RouteParams['boardId'];
  HasArchive:=BodyHasField(aRequest,'archive');
  HasEdits:=BodyHasField(aRequest,'color') or BodyHasField(aRequest,'labelIds') or
    BodyHasField(aRequest,'members') or BodyHasField(aRequest,'assignees');
  FieldSets:='';HasDate:=False;Body:=nil;Decorations:=nil;
  try
    try
      if (Pos('application/json',LowerCase(aRequest.ContentType))=1) and (aRequest.Content<>'') then
        Body:=ExactObject(aRequest.Content)
      else
      begin
        Body:=TJSONObject.Create;
        for FieldName in ['receivedAt','startAt','dueAt','endAt','dueComplete','stickers','locations','isOverTime','sort','description','title'] do
          if aRequest.ContentFields.IndexOfName(FieldName)>=0 then
            Body.Add(FieldName,aRequest.ContentFields.Values[FieldName]);
      end;
      Input:=Body.Find('title');HasTitle:=Input<>nil;
      if HasTitle then
      begin
        if (Input.JSONType<>jtString) or (Pos(#0,Input.AsString)>0) then
        begin SendJson(aResponse,'{"error":"Invalid title"}',400);Exit;end;
        FieldSets:=',title='+QuotedStr(Input.AsString);
      end;
      for FieldName in ['receivedAt','startAt','dueAt','endAt'] do
      begin
        Input:=Body.Find(FieldName);
        if Input=nil then Continue;
        HasDate:=True;
        if CardDateSql(Input,Literal) then FieldSets:=FieldSets+','+FieldName+'='+Literal;
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
      Input:=Body.Find('isOverTime');
      HasOvertime:=Input<>nil;
      if HasOvertime then
      begin
        if not (Input.JSONType in [jtBoolean,jtString]) or
          ((Input.AsString<>'true') and (Input.AsString<>'false')) then
        begin SendJson(aResponse,'{"error":"Invalid isOverTime"}',400);Exit;end;
        FieldSets:=FieldSets+',isOvertime='+IntToStr(Ord(Input.AsString='true'));
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
      end;
      Input:=Body.Find('dueComplete');
      if Input<>nil then
      begin
        Value:='';
        if Input.JSONType in [jtBoolean,jtString] then Value:=Input.AsString;
        FieldSets:=FieldSets+',dueComplete='+IntToStr(Ord(SameText(Value,'true')));
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
  ArchiveSql:='';
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
    ArchiveSql:='UPDATE cards SET archived='+IntToStr(Ord(Archive))+' WHERE '+Scope+
      ' AND archived='+IntToStr(Ord(not Archive))+'; ';
  end;
  Sets:='';
  if not HasArchive or HasEdits then
  begin
    Sets:='modifiedAt='+Stamp+',dateLastActivity='+Stamp+FieldSets;
    if BodyHasField(aRequest,'color') then Sets:=Sets+',color='+QuotedStr(BodyField(aRequest,'color'));
    Sets:='UPDATE cards SET '+Sets+' WHERE '+Scope+'; ';
  end;
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+
    ')=1 THEN 1 ELSE json(''Card edit scope changed'') END; '+Sets+ArchiveSql+Relations+' COMMIT;') then
  begin
    T.Db.Exec('ROLLBACK;');
    if HasTitle and (Length(T.Db.Query('SELECT id FROM cards WHERE '+Scope+';'))<>1) then
      SendJson(aResponse,CardNotFound,404)
    else SendError(aResponse,500,'Could not edit card');
    Exit;
  end;
  // #6423: a listId or swimlaneId in the body moves the card there, within
  // its board, with WeKan's moveCard activity (MoveViewCard's checks).
  if BodyHasField(aRequest,'listId') or BodyHasField(aRequest,'swimlaneId') then
  begin
    Value:=BodyField(aRequest,'listId');
    if Value='' then Value:=aRequest.RouteParams['listId'];
    Code:=MoveViewCard(T,UserId,BoardId,CardId,BodyField(aRequest,'boardId'),BodyField(aRequest,'swimlaneId'),Value,MoveError);
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
var Scope,Stamp:string;
begin
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  if not BoardCanEditCardText(T.Db,UserId,BoardId) then begin Error:='Board access forbidden';Exit(403);end;
  if Pos(#0,Value)>0 then begin Error:='Invalid value';Exit(400);end;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  Stamp:=QuotedStr(NowIso);
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET '+Column+'='+QuotedStr(Value)+',modifiedAt='+Stamp+
    ',dateLastActivity='+Stamp+' WHERE '+Scope+'; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+
    ' AND '+Column+'='+QuotedStr(Value)+')=1 THEN 1 ELSE json(''Card write failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not update card';Exit(500);end;
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
var Scope,Stamp:string;
begin
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND deletedAt IS NULL';
  Stamp:=QuotedStr(NowIso);
  if not T.Db.Exec('BEGIN IMMEDIATE; UPDATE cards SET dueComplete='+IntToStr(Ord(Done))+',modifiedAt='+Stamp+' WHERE '+Scope+
    ' AND COALESCE(dueComplete,0)<>'+IntToStr(Ord(Done))+'; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+
    ' AND COALESCE(dueComplete,0)='+IntToStr(Ord(Done))+')=1 THEN 1 ELSE json(''Complete failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not update card';Exit(500);end;
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
  if (BoardId='') or (Pos(#0,BoardId)>0) or not BoardCanWrite(T.Db,UserId,BoardId) then begin Error:='not-authorized';Exit(403);end;
  List:='';
  for i:=0 to High(Unique) do begin if List<>'' then List:=List+',';List:=List+QuotedStr(Unique[i]);end;
  if StrToIntDef(T.Db.Query('SELECT count(*) FROM cards WHERE boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL AND id IN ('+
    List+');')[0][0],-1)<>Length(Unique) then begin Error:='invalid-card-selection';Exit(400);end;
  U:=QuotedStr(UserId);
  if Length(T.Db.Query('SELECT 1 FROM board_members WHERE boardId='+QuotedStr(BoardId)+' AND userId='+U+' AND isActive=1 AND '+
    '(COALESCE(isNormalAssignedOnly,0)=1 OR COALESCE(isCommentAssignedOnly,0)=1 OR COALESCE(isReadAssignedOnly,0)=1) AND EXISTS(SELECT 1 FROM cards c '+
    'WHERE c.id IN ('+List+') AND NOT EXISTS(SELECT 1 FROM card_assignees a WHERE a.cardId=c.id AND a.userId='+U+'));'))>0 then
  begin Error:='not-authorized';Exit(403);end;
  for i:=0 to High(Unique) do
  begin
    Result:=ArchiveViewCard(T,UserId,BoardId,Unique[i],Error);
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
var Field,Setting,Literal,Scope,Stamp,Changed,Act:string;Input:TJSONData;Year:Integer;
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
  Input:TJSONData;Year:Integer;Seen:TStringList;
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
  if not SaveCardFieldValue(T.Db,CardId,FieldId,Literal,Guard) then
  begin Error:='Could not save custom-field value';Exit(500);end;
  Result:=200;
end;

function MoveViewCard(const T:TWLTenant;const UserId,BoardId,CardId,DestBoard,DestLane,DestList:string;out Error:string):Integer;
var Card:TWLRows;Scope,Stamp,Sort,ActivityId:string;
begin
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  if (DestBoard<>'') and (DestBoard<>BoardId) then
  begin Error:='A card moves to another board from the HTML4 view only';Exit(400);end;
  if (DestList='') or (Pos(#0,DestLane+DestList)>0) then begin Error:='Invalid card move destination';Exit(400);end;
  Card:=T.Db.Query('SELECT swimlaneId,listId FROM cards WHERE id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+
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
    ',dateLastActivity='+Stamp+' WHERE id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+'; '+
    NotificationsSql(T.Db,UserId,BoardId,DestList,CardId,'',ActivityId,'moveCard')+'COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not move card';Exit(500);end;
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

function ArchiveViewCard(const T:TWLTenant;const UserId,BoardId,CardId:string;out Error:string):Integer;
var Scope,Stamp,ActivityId:string;R:TWLRows;
begin
  Result:=ViewCardScope(T,UserId,BoardId,CardId,Error);
  if Result<>200 then Exit;
  Scope:='id='+QuotedStr(CardId)+' AND boardId='+QuotedStr(BoardId)+' AND archived=0 AND deletedAt IS NULL';
  R:=T.Db.Query('SELECT COALESCE(listId,'''') FROM cards WHERE '+Scope+';');
  if Length(R)<>1 then begin Error:='Card not found';Exit(404);end;
  Stamp:=QuotedStr(NowIso);ActivityId:=NewId;
  // As POST .../cards/:cardId/archive archives it, with WeKan's archivedCard
  // activity and its notifications.
  if not T.Db.Exec('BEGIN IMMEDIATE; INSERT INTO activities(id,activityType,userId,boardId,cardId,listId,swimlaneId,createdAt,modifiedAt,data_json) '+
    'SELECT '+QuotedStr(ActivityId)+',''archivedCard'','+QuotedStr(UserId)+',boardId,id,listId,swimlaneId,'+Stamp+','+Stamp+
    ',json_object(''cardTitle'',title) FROM cards WHERE '+Scope+'; UPDATE cards SET archived=1,archivedAt='+Stamp+',modifiedAt='+Stamp+
    ' WHERE '+Scope+'; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE id='+QuotedStr(CardId)+' AND archived=1)=1 THEN 1 '+
    'ELSE json(''Archive write failed'') END; '+NotificationsSql(T.Db,UserId,BoardId,R[0][0],CardId,'',ActivityId,'archivedCard')+'COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');Error:='Could not change card archive state';Exit(500);end;
end;

function SetViewCardDescription(const T:TWLTenant;const UserId,BoardId,CardId,Text:string;out Error:string):Integer;
begin
  Result:=SetViewCardText(T,UserId,BoardId,CardId,'description',Text,Error);
end;


// POST card archive — archives by default; body isArchive=false unarchives.
procedure ApiCardArchive(aRequest: TRequest; aResponse: TResponse);
var T:TWLTenant;UserId,CardId,BoardId,LegacyValue,Scope,Predicate,Stamp,ArchivedAt:string;
  Legacy,Archive:Boolean;Rows:TWLRows;Reply:TJSONObject;
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
  Rows:=T.Db.Query('SELECT id FROM cards WHERE '+Predicate+';');
  if Length(Rows)<>1 then begin SendJson(aResponse,CardNotFound,404);Exit;end;
  Stamp:=NowIso;ArchivedAt:='NULL';
  if Archive then ArchivedAt:=QuotedStr(Stamp);
  if not T.Db.Exec('BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Predicate+
    ')=1 THEN 1 ELSE json(''Archive scope changed'') END; UPDATE cards SET archived='+IntToStr(Ord(Archive))+
    ',archivedAt='+ArchivedAt+',modifiedAt='+QuotedStr(Stamp)+' WHERE '+Predicate+
    '; SELECT CASE WHEN (SELECT count(*) FROM cards WHERE '+Scope+' AND archived='+IntToStr(Ord(Archive))+
    ')=1 THEN 1 ELSE json(''Archive write failed'') END; COMMIT;') then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not change card archive state');Exit;end;
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
    Removed:=Length(Db.Query('SELECT id FROM activities WHERE id='+Claim+';'))=1;
    Result:=True;
    if Removed and (Attachments<>'') then RecordSharedAttachmentRemovals(Db,UserId,BoardId,BatchId);
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

// DELETE list — its cards have no FK on listId, so remove them first (their children cascade).
procedure ApiListDelete(aRequest:TRequest;aResponse:TResponse);
const NotFound='{"error":"List not found"}';
var T:TWLTenant;UserId,ListId,BoardId,Scope,CardScope,Markers,Batch,BatchId,Sql,Stamp:string;Reply:TJSONObject;Position:TWLRows;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  if not ApiBoardGuard(T,aRequest,aResponse,UserId,NotFound) then Exit;
  ListId:=aRequest.RouteParams['listId'];BoardId:=QuotedStr(aRequest.RouteParams['boardId']);
  BatchId:=NewId;Batch:=QuotedStr(BatchId);Stamp:=NowIso;
  Markers:='deletedAt='+QuotedStr(Stamp)+',deletedBy='+QuotedStr(UserId)+',deleteBatchId='+Batch;
  Scope:='id='+QuotedStr(ListId)+' AND boardId='+BoardId;
  Position:=T.Db.Query('SELECT swimlaneId,sort FROM lists WHERE '+Scope+' AND deletedAt IS NULL;');
  CardScope:='listId='+QuotedStr(ListId)+' AND boardId='+BoardId+' AND deletedAt IS NULL';
  Sql:='BEGIN IMMEDIATE; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+Scope+
    ' AND deletedAt IS NULL)=1 THEN 1 ELSE json(''List delete scope changed'') END; '+
    'UPDATE cards SET '+Markers+' WHERE '+CardScope+'; UPDATE lists SET '+Markers+
    ' WHERE '+Scope+' AND deletedAt IS NULL; SELECT CASE WHEN (SELECT count(*) FROM lists WHERE '+
    Scope+' AND deleteBatchId='+Batch+')=1 AND NOT EXISTS(SELECT 1 FROM cards WHERE '+CardScope+
    ') THEN 1 ELSE json(''Could not mark list and cards deleted'') END; COMMIT;';
  if not T.Db.Exec(Sql) then
  begin T.Db.Exec('ROLLBACK;');SendError(aResponse,500,'Could not delete list');Exit;end;
  if Length(Position)=1 then
    try RecordListPosition(T.Db,UserId,aRequest.RouteParams['boardId'],ListId,BatchId,
      Stamp,Position[0],False);except end;
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

function StoreAttachment(const T:TWLTenant;const UserId,BoardId,Sw,Lst,Crd,FileName,FileType:string; Content:TStream;
  out Id:string;RequireLiveCard:Boolean):Boolean;
var Path,Sql,Guard:string;Policy:TFieldPolicy;OwnsPath:Boolean;FileSize:Int64;Destination:TFileStream;
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
  try Guard:=Guard+' AND '+Policy.ScopeBoardExpression(True);finally Policy.Free;end;
  FileSize:=Content.Size;
  Sql:=Format('INSERT INTO attachments(id,boardId,swimlaneId,listId,cardId,name,type,size,'+
    'storageBackend,userId,createdAt) VALUES(%s,%s,%s,%s,%s,%s,%s,%d,''filesystem'',%s,%s);',
    [QuotedStr(Id),QuotedStr(BoardId),QuotedStr(Sw),QuotedStr(Lst),QuotedStr(Crd),
     QuotedStr(FileName),QuotedStr(FileType),FileSize,QuotedStr(UserId),QuotedStr(NowIso)]);
  OwnsPath:=False;
  try
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
      if Trim(ContentType)='application/octet-stream' then
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
  if not ApiAuthBoard(T,aResponse,UserId,BoardId,True) then Exit;
  if not ApiChildrenBelong(T.Db,BoardId,Sw,Lst,Crd,'','','','') then
  begin SendError(aResponse,400,'Invalid attachment parent');Exit;end;

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
  if not ApiAuthBoard(T, aResponse, UserId, R[0][0], False) then Exit;
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
  if not ApiAuthBoard(T, aResponse, UserId, R[0][0], False) then Exit;
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
var T:TWLTenant;UserId,Id:string;Rows:TWLRows;Reply:TJSONObject;
begin
  if not ApiTenant(aRequest,aResponse,T) then Exit;
  if not ApiAuth(T,aRequest,aResponse,UserId) then Exit;
  Id:=aRequest.RouteParams['attachmentId'];
  if not LoadAttachment(aResponse,T.Db,Id,Rows) then Exit;
  if not ApiAuthBoard(T,aResponse,UserId,Rows[0][0],True) then Exit;
  if not DeleteStoredAttachment(T,UserId,Rows[0][0],Id) then
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
  if not ApiAuthBoard(T,aResponse,UserId,Board,False) then Exit;
  if not ApiChildrenBelong(T.Db,Board,Lane,List,Card,'','','','') then
  begin SendJson(aResponse,'{"success":false,"message":"Attachment scope not found"}',404);Exit;end;
  Selector:=TSelectionScope.Create(T.Db);
  try
    Scope:='boardId='+QuotedStr(Board)+' AND '+Selector.StringField('attachments','boardId')+
      ' AND '+Selector.StringField('attachments','id')+' AND '+LiveAttachmentSQL(T.Db);
    AddScope('swimlaneId',Lane);AddScope('listId',List);AddScope('cardId',Card);
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
