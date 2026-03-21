import SwiftData
import SwiftUI

struct AddPositivityTokenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let sponsoringCheckIn: CheckIn

    @State private var reason: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    Text("What is one reason you feel positive about yourself?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Reason") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle("New Positivity Token")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveToken()
                    }
                    .disabled(trimmedReason.isEmpty)
                }
            }
        }
    }

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveToken() {
        let token = PositivityToken(reason: trimmedReason, checkIn: sponsoringCheckIn)
        modelContext.insert(token)
        dismiss()
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let start = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: today) ?? today
    let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? today
    let slot = Slot(start: start, end: end)
    let commitment = Commitment(
        title: "Preview",
        slots: [slot],
        target: Target(cycle: Cycle.anchored(.daily, at: .now), count: 1),
        skipBudget: SkipBudget(cycle: Cycle.anchored(.weekly, at: .now), count: 3),
    )
    let checkIn = CheckIn(commitment: commitment)

    let container = try! ModelContainer(
        for: Commitment.self, Slot.self, CheckIn.self, PositivityToken.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(commitment)
    container.mainContext.insert(checkIn)

    return AddPositivityTokenView(sponsoringCheckIn: checkIn)
        .modelContainer(container)
}
