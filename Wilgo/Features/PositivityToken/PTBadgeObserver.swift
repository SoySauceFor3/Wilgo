import SwiftData
import SwiftUI

/// Headless view that feeds live SwiftData capacity into PTBadgeState.
///
/// Must be embedded in the view tree (alongside MainTabView) so @Query gets
/// a model context. Has no visual output.
struct PTBadgeObserver: View {
    @Query private var tokens: [PositivityToken]
    @Query private var checkIns: [CheckIn]
    @Environment(PTBadgeState.self) private var badgeState

    private var currentCapacity: Int {
        PositivityTokenMinting.mintCapacity(tokenCount: tokens.count, checkInCount: checkIns.count)
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { badgeState.update(currentCapacity: currentCapacity) }
            .onChange(of: currentCapacity) { _, new in badgeState.update(currentCapacity: new) }
    }
}
