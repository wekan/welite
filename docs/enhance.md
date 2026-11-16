# Optional card dragging

The no-JS/no-cookie checkbox and arrow form remains the baseline. Editable boards
also load vendored `public/js/interact.js` and `public/js/wlmdrag.js`. Read-only
boards have no move form, so the script does not activate. Missing capabilities
or assets leave the form usable. No external CDN or build-time download is needed.

Drag a card to a visible list/swimlane cell to append it there. If that card is
checked, all checked cards move together. Otherwise only the dragged card moves.
`View all` exposes destinations beyond the default minimap viewport. List and
swimlane reordering continue to use their checkbox/arrow controls.

Independent pointers can drag different cards simultaneously. Each active gesture
owns a disjoint selection. Drops queue serially, using `/board/move` with `dir=drop`,
repeatable `sel_card`, `targetList`, `targetLane`, and the existing form's session,
board, return path and action-token fields. After each success, the script reads
the redirected form's fresh counter/MAC. Once gestures and requests finish, the
page reloads from the database. Requests omit cookies. A refusal shows a status
message asking for reload rather than pretending a local visual move was saved.

The server applies existing account/session, board-write, selection and single-use
MAC checks. It validates an active destination list and swimlane in the same board,
including shared lists, then appends all selected cards in one transaction. SQL
failure rolls back the whole selection. Cross-board or mismatched-lane targets
are rejected. There is no separate mutation API for JavaScript.

Verified by HTTP ownership, transaction-failure and token-replay regressions, plus
Chromium pointer/touch tests in `tests/drag.js`. The ordinary no-JS/no-cookie suite
continues to test the baseline independently. Physical wall-display and retro
browser checks remain part of the platform checklist.
