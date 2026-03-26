import Combine
import Foundation
import SwiftData

extension Notification.Name {
    /// Posted when a check-in is undone/revoked.
    static let CheckInRevoked = Notification.Name("CheckInRevoked")
}

enum CheckInRevokedUserInfoKeys {
    /// Value is a base64-encoded JSON string for `PersistentIdentifier`.
    static let persistentModelID = "persistentModelID"
}

/// Manages bottom undo notices for newly created `CheckIn`s.
///
/// Call sites should enqueue after inserting the `CheckIn` into a SwiftData `ModelContext`,
/// so that `checkIn.persistentModelID` is valid/stable.
@MainActor
final class CheckInUndoManager: ObservableObject {
    enum NoticeKind {
        case undo
        case info
    }

    struct Notice: Identifiable {
        let id: String
        let persistentModelID: PersistentIdentifier
        let createdAt: Date
        let title: String
        let kind: NoticeKind
    }

    @Published private(set) var notices: [Notice] = []

    private struct NoticeState {
        let undoClosure: (() -> Void)?
        let autoDismissTask: Task<Void, Never>
    }

    private var stateByNoticeID: [String: NoticeState] = [:]

    private let autoDismissDuration: TimeInterval = 5

    // Stores the last drafted PositivityToken reason so we can prefill the
    // Add view even if its sponsoring check-in is undone.
    private let lastPTDraftReasonKey = "wilgo.lastPositivityTokenDraftReason"

    init() {
    }

    /// Enqueue an undo notice for a newly created check-in.
    ///
    /// - Parameters:
    ///   - checkIn: The newly created check-in.
    ///   - title: Title shown in the notice UI.
    ///   - undo: Closure invoked if the user taps `Undo` before the notice auto-dismisses.
    func enqueue(
        checkIn: CheckIn,
        title: String = "Check-in saved",
        undo: @escaping () -> Void
    ) {
        enqueueInternal(
            checkIn: checkIn,
            title: title,
            kind: .undo,
            undoClosure: undo
        )
    }

    /// Enqueue an info notice (no `Undo`) tied to a check-in.
    func enqueueInfo(checkIn: CheckIn, title: String) {
        enqueueInternal(
            checkIn: checkIn,
            title: title,
            kind: .info,
            undoClosure: nil
        )
    }

    /// Executes the stored undo closure for the provided notice and removes the notice immediately.
    func undo(_ notice: Notice) {
        guard notice.kind == .undo else { return }
        guard let state = stateByNoticeID[notice.id], let undoClosure = state.undoClosure else {
            return
        }

        // Ensure idempotency: prevent double-undo if the user taps quickly.
        removeNotice(noticeID: notice.id)
        undoClosure()
        postCheckInRevoked(persistentModelID: notice.persistentModelID)
    }

    private func postCheckInRevoked(persistentModelID: PersistentIdentifier) {
        let pidEncoded = encodePersistentModelID(persistentModelID)
        NotificationCenter.default.post(  //UIs can listen for it without the manager needing direct references to those views.
            name: .CheckInRevoked,
            object: nil,
            userInfo: [
                CheckInRevokedUserInfoKeys.persistentModelID: pidEncoded
            ]
        )
    }

    // Removes the notice and its undo closure, and cancels the auto-dismiss task.
    private func autoDismiss(noticeID: String) {
        // If the notice already got removed (e.g. user tapped Undo), do nothing.
        guard stateByNoticeID[noticeID] != nil else { return }
        stateByNoticeID[noticeID] = nil
        notices.removeAll(where: { $0.id == noticeID })
    }

    private func removeNotice(noticeID: String) {
        if let task = stateByNoticeID[noticeID]?.autoDismissTask {
            task.cancel()
        }
        stateByNoticeID[noticeID] = nil
        notices.removeAll(where: { $0.id == noticeID })
    }

    /// Encodes a `PersistentIdentifier` to a base64 JSON string.
    /// Returns `""` if encoding fails (call sites should treat `enqueue()` as best-effort).
    private func encodePersistentModelID(_ pid: PersistentIdentifier) -> String {
        (try? JSONEncoder().encode(pid)).map { $0.base64EncodedString() } ?? ""
    }

    // MARK: Draft storage (PositivityToken reason)

    func lastPositivityTokenDraftReason() -> String {
        UserDefaults.standard.string(forKey: lastPTDraftReasonKey) ?? ""
    }

    func saveLastPositivityTokenDraftReason(_ reason: String) {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: lastPTDraftReasonKey)
    }

    // MARK: Internals

    private func enqueueInternal(
        checkIn: CheckIn,
        title: String,
        kind: NoticeKind,
        undoClosure: (() -> Void)?
    ) {
        let pid = checkIn.persistentModelID
        let noticeID = encodePersistentModelID(pid)

        // Replace any in-flight notice with the same identifier; avoids duplicate entries
        // if a call site accidentally enqueues twice for the same check-in.
        if let repeated = notices.first(where: { $0.id == noticeID }) {
            removeNotice(noticeID: repeated.id)
        }

        let notice = Notice(
            id: noticeID,
            persistentModelID: pid,
            createdAt: Date(),
            title: title,
            kind: kind
        )
        notices.append(notice)
        let duration = autoDismissDuration
        let task = Task { [weak self] in  // runs immediately
            try? await Task.sleep(
                nanoseconds: UInt64(duration * 1_000_000_000)
            )
            await MainActor.run {
                self?.autoDismiss(noticeID: noticeID)
            }
        }
        stateByNoticeID[noticeID] = NoticeState(
            undoClosure: undoClosure,
            autoDismissTask: task
        )

        // Note: `task` is stored so we can cancel it on user-initiated Undo.
    }
}
