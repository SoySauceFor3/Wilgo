import SwiftData
import SwiftUI

struct TagPickerSection: View {
    @Binding var selectedTags: [Tag]
    @Query(sort: \Tag.displayOrder) private var allTags: [Tag]
    @Environment(\.modelContext) private var modelContext
    @State private var isAddingTag = false
    @State private var newTagName = ""

    var body: some View {
        Section("Tags") {
            ForEach(allTags) { tag in
                HStack {
                    Text(tag.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if isSelected(tag) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { toggleTag(tag) }
            }

            Button {
                newTagName = ""
                isAddingTag = true
            } label: {
                Label("Add new tag\u{2026}", systemImage: "plus")
            }
        }
        .alert("New Tag", isPresented: $isAddingTag) {
            TextField("Tag name", text: $newTagName)
            Button("Add") {
                addNewTag()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Helpers

    private func isSelected(_ tag: Tag) -> Bool {
        selectedTags.contains { $0.id == tag.id }
    }

    private func toggleTag(_ tag: Tag) {
        if let index = selectedTags.firstIndex(where: { $0.id == tag.id }) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }
    }

    private func addNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (allTags.map(\.displayOrder).max() ?? -1) + 1
        let tag = Tag(name: trimmed, displayOrder: nextOrder)
        modelContext.insert(tag)
        selectedTags.append(tag)
    }
}
