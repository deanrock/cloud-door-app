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

    /// Whether an account is saved. An empty door list means "signed out" only if this says so; it can also
    /// mean the doors haven't loaded yet.
    public static func isSignedIn(_ configuration: Configuration = Configuration()) -> Bool {
        let values = configuration.get()
        return !values.hostname.isEmpty && !values.username.isEmpty
    }

    /// Looks a configured door up in the current list. A door that was renamed shows its new name,
    /// and a door that no longer exists gives nil so the widget can ask for a new choice.
    ///
    /// An empty list says nothing about the door: the person may be signed out, the doors may not have loaded
    /// yet, or the account may have been rejected. The choice is kept, so it works again once the doors are back;
    /// opening it meanwhile fails with a message that says what is wrong.
    ///
    /// When signed out, the chosen door is replaced by the "Sign In" stand-in, so the widget says what to do
    /// right away. The choice itself stays saved and is used again once the person signs back in.
    public static func resolve(_ configured: DoorEntity?, in doors: [Location], signedIn: Bool) -> DoorEntity? {
        guard let configured else { return nil }
        guard signedIn else { return .placeholder(signedIn: false) }
        guard !doors.isEmpty else { return configured }
        return doors.first { $0.id == configured.id }.map(DoorEntity.init)
    }
}
