import SwiftData
import SwiftUI

struct TagPickerSection: View {
    @Binding var selectedTags: [Tag]
    @Query(sort: \Tag.displayOrder) private var allTags: [Tag]
    @Environment(\.modelContext) private var modelContext
    @State private var isAddingTag = false
    @State private var newTagName = ""

    private var debugExtra: String {
        "allTags=\(allTags.count) selected=\(selectedTags.count) adding=\(isAddingTag)"
    }

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
                .onTapGesture {
                    MemoryProbe.log(
                        "TagPicker.toggle.tap",
                        extra: "tag=\(tag.id) selectedBefore=\(isSelected(tag)) \(debugExtra)"
                    )
                    toggleTag(tag)
                }
            }

            Button {
                MemoryProbe.log("TagPicker.add.tap", extra: debugExtra)
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
        .onAppear {
            MemoryProbe.log("TagPicker.appear", extra: debugExtra)
        }
        .onDisappear {
            MemoryProbe.log("TagPicker.disappear", extra: debugExtra)
        }
        .onChange(of: allTags) {
            MemoryProbe.log("TagPicker.query.tags", extra: debugExtra)
        }
        .onChange(of: isAddingTag) { _, isPresented in
            MemoryProbe.log(
                "TagPicker.add.presentation",
                extra: "presented=\(isPresented) \(debugExtra)"
            )
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
        MemoryProbe.log(
            "TagPicker.toggle.end",
            extra: "tag=\(tag.id) selectedAfter=\(isSelected(tag)) \(debugExtra)"
        )
    }

    private func addNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        MemoryProbe.log("TagPicker.add.start", extra: "nameLength=\(trimmed.count) \(debugExtra)")
        let nextOrder = (allTags.map(\.displayOrder).max() ?? -1) + 1
        let tag = Tag(name: trimmed, displayOrder: nextOrder)
        modelContext.insert(tag)
        selectedTags.append(tag)
        MemoryProbe.log("TagPicker.add.end", extra: "tag=\(tag.id) \(debugExtra)")
    }
}
