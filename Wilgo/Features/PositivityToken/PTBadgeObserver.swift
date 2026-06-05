import SwiftData
import SwiftUI

/// Headless view that feeds live free-token count into PTBadgeState.
///
/// Must be embedded in the view tree (alongside MainTabView) so @Query gets
/// a model context. Has no visual output.
struct PTBadgeObserver: View {
    @Query private var tokens: [PositivityToken]
    @Environment(PTBadgeState.self) private var badgeState

    private var freeTokenCount: Int {
        tokens.count(where: { $0.consumedByCycleRecord == nil })
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { badgeState.update(currentCapacity: freeTokenCount) }
            .onChange(of: freeTokenCount) { _, new in badgeState.update(currentCapacity: new) }
    }
}
