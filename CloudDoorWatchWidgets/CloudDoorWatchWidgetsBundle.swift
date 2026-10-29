//
//  CloudDoorWatchWidgetsBundle.swift
//  CloudDoorWatchWidgets
//

import AppIntents
import CloudDoorKit
import SwiftUI
import WidgetKit

/// Pulls the framework's intents and entities into this extension.
struct CloudDoorWatchWidgetsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [CloudDoorKitPackage.self]
    }
}

@main
struct CloudDoorWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        OpenDoorControl()
    }
}
