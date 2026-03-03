//
//  WilgoApp.swift
//  Wilgo
//
//  Created by Xinya Yang on 2/24/26.
//

import SwiftData
import SwiftUI

@main
struct WilgoApp: App {
    let sharedModelContainer: ModelContainer
    let liveActivityManager: LiveActivityManager

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([
            Habit.self,
            HabitSlot.self,
            HabitCheckIn.self,
            SnoozedSlot.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            sharedModelContainer = container
            liveActivityManager = LiveActivityManager(modelContext: container.mainContext)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(liveActivityManager)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                liveActivityManager.sync()
            }
        }
    }
}
