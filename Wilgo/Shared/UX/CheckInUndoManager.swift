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
    struct Notice: Identifiable {
        let id: String
        let persistentModelID: PersistentIdentifier
        let createdAt: Date
        let title: String
    }

    @Published private(set) var notices: [Notice] = []

    private struct NoticeState {
        let undoClosure: () -> Void
        let autoDismissTask: Task<Void, Never>
    }

    private var stateByNoticeID: [String: NoticeState] = [:]

    private let autoDismissDuration: TimeInterval = 5

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
            title: title
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
            undoClosure: undo,
            autoDismissTask: task
        )

        // Note: `task` is stored so we can cancel it on user-initiated Undo.
    }

    /// Executes the stored undo closure for the provided notice and removes the notice immediately.
    func undo(_ notice: Notice) {
        guard let state = stateByNoticeID[notice.id] else { return }

        // Ensure idempotency: prevent double-undo if the user taps quickly.
        let undoClosure = state.undoClosure
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
}
