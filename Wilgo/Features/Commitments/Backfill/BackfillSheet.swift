import SwiftData
import SwiftUI

struct BackfillSheet: View {
    let commitment: Commitment
    /// When provided, clamps the date picker to the cycle's date range so the
    /// user doesn't accidentally backfill into the wrong cycle.
    var dateRange: ClosedRange<Date>? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var checkInUndoManager: CheckInUndoManager

    @State private var selectedDate: Date

    init(commitment: Commitment, dateRange: ClosedRange<Date>? = nil) {
        self.commitment = commitment
        self.dateRange = dateRange
        // Pre-select the start of the cycle (most recent missed check-in is likely near there),
        // or now when there is no range constraint.
        _selectedDate = State(initialValue: dateRange?.lowerBound ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Date & Time",
                        selection: $selectedDate,
                        in: dateRange ?? Date.distantPast...Date.distantFuture,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } footer: {
                    Text("A check-in will be recorded at the selected date and time.")
                }
            }
            .navigationTitle("Backfill Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        addBackfill()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func addBackfill() {
        let checkIn = CheckIn(commitment: commitment, createdAt: selectedDate)
        modelContext.insert(checkIn)
        commitment.checkIns.append(checkIn)

        let bannerTitle = "Backfill of \(commitment.title) saved for \(formattedDate(selectedDate))"
        checkInUndoManager.enqueue(checkIn: checkIn, title: bannerTitle) {
            if let token = checkIn.positivityToken {
                modelContext.delete(token)
            }
            modelContext.delete(checkIn)
        }

        dismiss()
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let container = HeatmapPreviewFactory.richHistoryContainer()
    PreviewWithFirstCommitment(container: container) { commitment in
        Color.clear
            .sheet(isPresented: .constant(true)) {
                BackfillSheet(commitment: commitment)
                    .presentationDetents([.medium])
            }
    }
    .environmentObject(CheckInUndoManager())
}
