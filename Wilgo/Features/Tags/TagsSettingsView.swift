import SwiftData
import SwiftUI

struct TagsSettingsView: View {
    @Query(sort: \Tag.displayOrder) private var tags: [Tag]
    @Environment(\.modelContext) private var modelContext
    @State private var tagPendingDelete: Tag? = nil

    var body: some View {
        List {
            ForEach(tags) { tag in
                @Bindable var tag = tag
                TextField("Tag name", text: $tag.name)
            }
            .onMove { source, destination in
                var reordered = tags
                reordered.move(fromOffsets: source, toOffset: destination)
                for (i, tag) in reordered.enumerated() {
                    tag.displayOrder = i
                }
            }
            .onDelete { offsets in
                if let index = offsets.first {
                    tagPendingDelete = tags[index]
                }
            }
        }
        .navigationTitle("Tags")
        .toolbar { EditButton() }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: Binding(
                get: { tagPendingDelete != nil },
                set: { if !$0 { tagPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let tag = tagPendingDelete { modelContext.delete(tag) }
                tagPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { tagPendingDelete = nil }
        }
    }

    private var deleteDialogTitle: String {
        guard let tag = tagPendingDelete else { return "Delete Tag?" }
        let count = tag.commitments.count
        return count == 0
            ? "Delete '\(tag.name)'?"
            : "Delete '\(tag.name)'? Used in \(count) commitment\(count == 1 ? "" : "s")."
    }
}
