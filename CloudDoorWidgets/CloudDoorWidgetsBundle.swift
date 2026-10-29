//
//  CloudDoorWidgetsBundle.swift
//  CloudDoorWidgets
//
//  Created by Jure Jancigaj on 27. 10. 2026.
//

import AppIntents
import CloudDoorKit
import SwiftUI
import WidgetKit

/// Pulls the framework's intents and entities into this extension.
struct CloudDoorWidgetsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [CloudDoorKitPackage.self]
    }
}

@main
struct CloudDoorWidgetsBundle: WidgetBundle {
    var body: some Widget {
        OpenDoorControl()
        DoorWidget()
    }
}
