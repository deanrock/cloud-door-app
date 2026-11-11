//
//  CloudDoorShortcuts.swift
//  CloudDoor
//
//  What the system offers for the app in Siri, Spotlight and the Shortcuts app.
//

import AppIntents
import CloudDoorKit

/// Pulls the framework's intents and entities into the app.
struct CloudDoorAppPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [CloudDoorKitPackage.self]
    }
}

struct CloudDoorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenDoorIntent(),
            phrases: [
                "Open \(\.$door) with \(.applicationName)",
                "Open a door with \(.applicationName)",
            ],
            shortTitle: "Open Door",
            systemImageName: "door.left.hand.open")
    }
}
