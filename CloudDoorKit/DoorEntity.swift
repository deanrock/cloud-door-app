//
//  DoorEntity.swift
//  CloudDoorKit
//
//  A door as the system (Shortcuts, Siri, controls, widgets) sees it.
//

import AppIntents
import Foundation

/// Lets the app and the extensions include this framework's intents and entities.
public struct CloudDoorKitPackage: AppIntentsPackage {}

public struct DoorEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Door")
    public static let defaultQuery = DoorQuery()

    /// The server's door id: stable across launches and devices.
    public let id: String

    @Property(title: "Name")
    public var name: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "door.left.hand.closed"))
    }

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public init(_ location: Location) {
        self.init(id: location.id, name: location.name)
    }
}

/// Resolves doors from the shared cache, which the app refreshes from the server.
public struct DoorQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [DoorEntity] {
        Self.resolve(ids: identifiers, in: Cache().getCachedLocations() ?? [])
    }

    public func entities(matching string: String) async throws -> [DoorEntity] {
        Self.search(string, in: Cache().getCachedLocations() ?? [])
    }

    /// The list of doors is small, so every door is offered.
    public func suggestedEntities() async throws -> [DoorEntity] {
        (Cache().getCachedLocations() ?? []).map(DoorEntity.init)
    }

    /// Doors for the given ids, in the requested order. Ids that no longer exist are skipped.
    static func resolve(ids: [String], in doors: [Location]) -> [DoorEntity] {
        ids.compactMap { id in doors.first { $0.id == id }.map(DoorEntity.init) }
    }

    /// Doors whose name contains the text, ignoring case and accents. The framework doesn't filter for us.
    static func search(_ text: String, in doors: [Location]) -> [DoorEntity] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return doors.map(DoorEntity.init) }
        return doors.filter { $0.name.localizedStandardContains(text) }.map(DoorEntity.init)
    }
}
