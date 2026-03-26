import SwiftUI

/// Bottom overlay that renders stacked undo toasts for newly created `CheckIn`s.
struct CheckInUndoBannerOverlay: View {
    @EnvironmentObject private var checkInUndoManager: CheckInUndoManager

    var body: some View {
        if checkInUndoManager.notices.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                ForEach(checkInUndoManager.notices) { notice in
                    CheckInUndoToastRow(
                        notice: notice,
                        onUndo: { checkInUndoManager.undo(notice) }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .animation(.easeInOut(duration: 0.2), value: checkInUndoManager.notices.map(\.id))
        }
    }
}

private struct CheckInUndoToastRow: View {
    let notice: CheckInUndoManager.Notice
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(notice.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if notice.kind == .undo {
                Button(action: onUndo) {
                    Text("Undo")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Undo check-in")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}
