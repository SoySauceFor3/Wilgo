import SwiftData
import SwiftUI

struct AddPositivityTokenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var reason: String = ""
    @State private var promptIndex: Int = .random(in: 0..<Self.prompts.count)

    private static let prompts: [String] = [
        "What's one small win you had today?",
        "What's one little thing that made you happy today?",
        "Who or what are you grateful for today?",
        "What's one thing you did for someone else today?",
        "What's something you're proud of yourself for recently?",
        "What's one moment today that felt good?",
        "What's one kind thing someone did for you lately?",
        "What's one thing you accomplished today, big or small?",
    ]

    private var currentPrompt: String {
        Self.prompts[promptIndex % Self.prompts.count]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentPrompt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Tap to change")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        promptIndex = (promptIndex + 1) % Self.prompts.count
                    }
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
        let token = PositivityToken(reason: trimmedReason)
        modelContext.insert(token)
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Commitment.self, Slot.self, CheckIn.self, PositivityToken.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return AddPositivityTokenView()
        .modelContainer(container)
}
