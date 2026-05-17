import Combine
import Foundation
import SwiftData
import SwiftUI
import WidgetKit

extension Notification.Name {
    /// Posted when a check-in is undone/revoked.
    static let CheckInRevoked = Notification.Name("CheckInRevoked")
}

enum CheckInRevokedUserInfoKeys {
    /// Value is the `UUID` of the revoked `CheckIn`.
    static let checkInID = "checkInID"
}

/// Manages bottom undo notices for newly created `CheckIn`s.
///
/// Call sites should enqueue after inserting the `CheckIn` into a SwiftData `ModelContext`,
/// so that `checkIn.id` is valid.
@MainActor
final class CheckInUndoManager: ObservableObject {
    enum NoticeKind {
        case undo
        case info
    }

    struct Notice: Identifiable {
        let id: UUID
        let createdAt: Date
        let title: String
        let kind: NoticeKind
    }

    @Published private(set) var notices: [Notice] = []

    private struct NoticeState {
        let checkIn: CheckIn
        let context: ModelContext
        let autoDismissTask: Task<Void, Never>
    }

    private var stateByNoticeID: [UUID: NoticeState] = [:]

    private let autoDismissDuration: TimeInterval = 5

    init() {}

    /// Enqueue an undo notice for a newly created check-in.
    ///
    /// - Parameters:
    ///   - checkIn: The newly created check-in. **Must already be inserted into `context`**
    ///     before calling this method — `checkIn.id` must be a stable, persistent identifier.
    ///   - title: Title shown in the notice UI.
    ///   - context: The `ModelContext` that owns `checkIn`. Used internally to delete the
    ///     check-in if the user taps Undo.
    func enqueue(
        checkIn: CheckIn,
        title: String = "Check-in saved",
        context: ModelContext
    ) {
        let noticeID = checkIn.id

        // Replace any in-flight notice with the same identifier; avoids duplicate entries
        // if a call site accidentally enqueues twice for the same check-in.
        if let repeated = notices.first(where: { $0.id == noticeID }) {
            removeNotice(noticeID: repeated.id)
        }

        let notice = Notice(
            id: noticeID,
            createdAt: Date(),
            title: title,
            kind: .undo
        )
        notices.append(notice)
        print("Enqueued notice: \(notice.title)")
        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)
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
            checkIn: checkIn,
            context: context,
            autoDismissTask: task
        )

        // Note: `task` is stored so we can cancel it on user-initiated Undo.
    }

    /// Deletes the check-in associated with the provided notice and removes the notice immediately.
    func undo(_ notice: Notice) {
        guard notice.kind == .undo else { return }
        guard let state = stateByNoticeID[notice.id] else { return }

        // Ensure idempotency: prevent double-undo if the user taps quickly.
        removeNotice(noticeID: notice.id)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            state.context.delete(state.checkIn)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)
        postCheckInRevoked(checkInID: notice.id)
    }

    private func postCheckInRevoked(checkInID: UUID) {
        NotificationCenter.default.post(  // UIs can listen for it without the manager needing direct references to those views.
            name: .CheckInRevoked,
            object: nil,
            userInfo: [
                CheckInRevokedUserInfoKeys.checkInID: checkInID
            ]
        )
    }

    /// Immediately dismisses all pending notices (e.g. when a competing sheet opens).
    func dismissAll() {
        for noticeID in stateByNoticeID.keys {
            removeNotice(noticeID: noticeID)
        }
    }

    // Removes the notice and its associated state, and cancels the auto-dismiss task.
    private func autoDismiss(noticeID: UUID) {
        guard stateByNoticeID[noticeID] != nil else { return }
        stateByNoticeID[noticeID] = nil
        notices.removeAll(where: { $0.id == noticeID })
    }

    private func removeNotice(noticeID: UUID) {
        if let task = stateByNoticeID[noticeID]?.autoDismissTask {
            task.cancel()
        }
        stateByNoticeID[noticeID] = nil
        notices.removeAll(where: { $0.id == noticeID })
    }
}
