---
name: Check-in Undo Toasts
overview: Add a decoupled bottom notice system that shows a check-in “made” banner with an Undo action (auto-expiring after ~5s), supports multiple check-ins within that window, and correctly revokes any PositivityToken minted from an undone check-in (including dismissing the PT AddView while preserving the user’s typed reason as a local draft).
todos:
  - id: add-undo-manager
    content: Create `CheckInUndoManager` that enqueues bottom notices for created check-ins, keeps per-notice undo closures, auto-dismisses after ~5s, and posts a `CheckInRevoked` signal keyed by `persistentModelID`.
    status: completed
  - id: add-undo-overlay-ui
    content: Add `CheckInUndoBannerOverlay` to render stacked toasts at the bottom with an `Undo` button per toast; wire it to `CheckInUndoManager.notices`.
    status: completed
  - id: wire-manager-to-app-root
    content: Instantiate and inject the manager in `Wilgo/WilgoApp.swift`, and overlay the banner UI over `MainTabView`.
    status: completed
  - id: route-checkin-creation-through-manager
    content: Update `CommitmentStatsCard` Done action to create/register check-ins via the manager (instead of direct insert). Update `WilgoApp` deep-link “done” to do the same.
    status: completed
  - id: handle-pt-revocation-in-list
    content: Update `Features/PositivityToken/ListView.swift` to listen for check-in revocation; if the revoked check-in matches the currently-sheeted one, close the PT Add sheet and refresh eligibility.
    status: completed
  - id: handle-pt-revocation-in-addview
    content: "Update `Features/PositivityToken/AddView.swift` to (1) prefill the PT reason from a locally stored draft, (2) listen for revocation of its sponsoring check-in, and on revocation: save draft, enqueue an info notice, and dismiss."
    status: completed
isProject: false
---

## aUX decisions (based on your answers)

- Multiple check-ins within 5s produce multiple stacked/queued toasts, each with its own `Undo`.
- Undo fully reverts the check-in and any PT minted from it (including deleting the token).
  - If the user is currently in `PositivityToken/AddView` for that check-in when Undo happens, the AddView is dismissed and a notice is shown.
  - PT can still be created while the 5s check-in toast is visible; if the user later undoes that check-in, the PT is revoked.
  - The last PT.reason of either AddView or the rovoked PT is stored and will auto-populate the in the AddView next time the user opens it.

## Implementation approach (decoupled from StageView)

- Introduce a global `CheckInUndoManager` + bottom overlay in the app root (`WilgoApp`), so any future code path that creates a `CheckIn` can call the manager to register the toast.
- Update the current check-in creation call sites to route through the manager so the UX works everywhere immediately:
  - `CommitmentStatsCard` “Done” button
  - `WilgoApp` deep-link “done” handler

## Key behaviors

- Each toast stays visible for ~5 seconds unless the user taps `Undo`.
- Undo:
  - deletes the check-in
  - deletes the linked `PositivityToken` (if any), saves the reason locally. Show a notice about it.
  - posts a `CheckInRevoked` notification so PT UI can respond
- PT revocation UX:
  - `AddView` listens for revocation of its `sponsoringCheckIn`
  - on revocation: saves draft reason locally, shows notice, and dismisses.
  - `ListPositivityTokenView` dismisses the sheet if it’s open for the revoked check-in and then refreshes eligibility.

## Files to change / add

- Add: `Wilgo/Shared/UX/CheckInUndoManager.swift`
- Add: `Wilgo/Shared/UX/CheckInUndoBannerOverlay.swift`
- Update: `Wilgo/WilgoApp.swift`
- Update: `Wilgo/Features/Commitments/SingleCommitment/CommitmentStatsCard.swift`
- Update: `Wilgo/Features/PositivityToken/ListView.swift`
- Update: `Wilgo/Features/PositivityToken/AddView.swift`

## Expected code touchpoints (non-obvious)

- Replace direct `modelContext.insert(checkIn)` in `CommitmentStatsCard` with a manager call so the toast + undo closure are registered immediately.
- In the overlay, render `manager.notices` in a bottom-aligned `VStack` so multiple toasts can coexist.
- Use a notification (or manager-published signal) keyed by `checkIn.persistentModelID` so `AddView` can react even though it doesn’t own the undo logic.
