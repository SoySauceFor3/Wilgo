import SwiftData
import SwiftUI

struct AddPositivityTokenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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
        let token = PositivityToken(reason: trimmedReason)
        modelContext.insert(token)
        dismiss()
    }
}

struct AddPositivityTokenView_Previews: PreviewProvider {
    static var previews: some View {
        AddPositivityTokenView()
            .modelContainer(for: PositivityToken.self, inMemory: true)
    }
}
