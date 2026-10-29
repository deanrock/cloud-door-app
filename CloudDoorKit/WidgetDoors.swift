//
//  WidgetDoors.swift
//  CloudDoorKit
//
//  Which doors widgets and controls show. Kept here, outside the extension, so it can be unit tested.
//

import Foundation

public enum WidgetDoors {
    /// The doors in the shared cache, which the app refreshes from the server.
    public static func cachedDoors() -> [Location] {
        Cache().getCachedLocations() ?? []
    }

    /// Looks a configured door up in the current list. A door that was renamed shows its new name,
    /// and a door that no longer exists gives nil so the widget can ask for a new choice.
    public static func resolve(_ configured: DoorEntity?, in doors: [Location]) -> DoorEntity? {
        guard let configured else { return nil }
        return doors.first { $0.id == configured.id }.map(DoorEntity.init)
    }
}
