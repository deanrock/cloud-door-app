//
//  CloudDoorApp.swift
//  CloudDoor
//
//  Created by dean on 29. 9. 24.
//

import CloudDoorKit
import SwiftUI

@main
struct CloudDoorApp: App {
    init() {
        // Move data saved by earlier versions into the storage shared with widgets and the watch.
        StorageMigration.run()
        // Keep a paired Apple Watch up to date with the account and doors.
        PhoneConnection.shared.start()
    }

    private enum Tab {
        case doors, settings
    }

    @State private var selectedTab = Tab.doors
    /// Goes up whenever the account is changed in Settings, which tells the Doors tab to load the new account's doors.
    @State private var accountVersion = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                ContentView(
                    isActive: selectedTab == .doors,
                    accountVersion: accountVersion,
                    showSettings: { selectedTab = .settings })
                    .tabItem {
                        Label("Doors", systemImage: "door.french.closed")
                    }
                    .tag(Tab.doors)
                SettingsView(onAccountChanged: { accountVersion += 1 })
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(Tab.settings)
            }
        }
    }
}
