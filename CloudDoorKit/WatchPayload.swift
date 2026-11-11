//
//  WatchPayload.swift
//  CloudDoorKit
//
//  What the iPhone sends to the Apple Watch: the saved account and the doors. The watch then talks to the server
//  itself, using its own location. Kept here, away from WatchConnectivity, so that it can be tested.
//

import Foundation

public struct WatchPayload: Codable, Equatable, Sendable {
    public var username: String
    public var password: String
    public var hostname: String
    public var doors: [Location]

    public init(username: String, password: String, hostname: String, doors: [Location]) {
        self.username = username
        self.password = password
        self.hostname = hostname
        self.doors = doors
    }

    /// True when nobody is signed in on the iPhone; the watch then signs out too.
    public var isSignedOut: Bool { hostname.isEmpty }

    /// What the iPhone has right now.
    public static func current(configuration: Configuration = Configuration(), cache: Cache = Cache()) -> WatchPayload {
        let account = configuration.get()
        return WatchPayload(
            username: account.username,
            password: account.password,
            hostname: account.hostname,
            doors: account.hostname.isEmpty ? [] : (cache.getCachedLocations() ?? []))
    }

    // MARK: Sending

    private static let contextKey = "payload"

    /// The dictionary to hand to WatchConnectivity. Only property-list types are allowed in it.
    public func context() throws -> [String: Any] {
        [Self.contextKey: try JSONEncoder().encode(self)]
    }

    /// Reads what the iPhone sent. Anything that isn't a payload from this app gives nil, and changes nothing.
    public static func decode(context: [String: Any]) -> WatchPayload? {
        guard let data = context[contextKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }

    // MARK: Receiving

    /// Makes the watch match the iPhone. An account that is already saved is left alone, so that repeated messages
    /// don't make the watch reload for nothing.
    public func apply(to configuration: Configuration = Configuration(), cache: Cache = Cache()) throws {
        guard !isSignedOut else {
            configuration.clear()
            cache.clearCachedLocations()
            return
        }

        let saved = configuration.get()
        let accountChanged = saved.username != username || saved.password != password || saved.hostname != hostname
        if accountChanged {
            try configuration.set(username: username, password: password, hostname: hostname)
        }
        cache.setCachedLocations(locations: doors)
    }
}
