//
//  ShukatsuApp.swift
//  Shukatsu
//
//  Created by rob on 8/2/25.
//

import SwiftUI

@main
struct ShukatsuApp: App {
    let persistenceController = PersistenceController.shared
    let profileManager = ProfileManager()

    init() {
        try? profileManager.bootstrapInitialStore(container: persistenceController.container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(profileManager)
                .id(profileManager.profileSwitchToken)      // keep your swap
//                .frame(minWidth: 900, minHeight: 600)       // optional, like Landmarks
                .frame(minWidth: 375.0, minHeight: 375.0)
                .background(.background)                    // ⟵ important: system surface
        }
        .windowStyle(.automatic)                            // ⟵ let Tahoe drive chrome
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
