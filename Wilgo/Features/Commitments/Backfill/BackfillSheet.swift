import SwiftData
import SwiftUI

struct BackfillSheet: View {
    let commitment: Commitment
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var checkInUndoManager: CheckInUndoManager

    @State private var selectedDate: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Date & Time",
                        selection: $selectedDate,
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
                    Button("Cancel") { isPresented = false }
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

        isPresented = false
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
                BackfillSheet(commitment: commitment, isPresented: .constant(true))
                    .presentationDetents([.medium])
            }
    }
    .environmentObject(CheckInUndoManager())
}
