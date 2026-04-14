import SwiftData
import SwiftUI

struct TagFilterChipsView: View {
    @Binding var selectedTagIDs: Set<UUID>
    @Query(sort: \Tag.displayOrder) private var allTags: [Tag]

    var body: some View {
        if allTags.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "All" chip
                    let allSelected = selectedTagIDs.isEmpty
                    Text("All")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(allSelected ? Color.accentColor : Color.clear)
                        .foregroundStyle(allSelected ? Color.white : Color.accentColor)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.accentColor, lineWidth: allSelected ? 0 : 1))
                        .onTapGesture { selectedTagIDs = [] }

                    ForEach(allTags) { tag in
                        let isSelected = selectedTagIDs.contains(tag.id)
                        Text(tag.name)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected ? Color.accentColor : Color.clear)
                            .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.accentColor, lineWidth: isSelected ? 0 : 1))
                            .onTapGesture { toggleTag(tag.id) }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }

    private func toggleTag(_ id: UUID) {
        if selectedTagIDs.contains(id) {
            selectedTagIDs.remove(id)
        } else {
            selectedTagIDs.insert(id)
        }
    }
}
