//
//  WatchAccountModel.swift
//  CloudDoorKit
//
//  The account and doors the watch shows. They come from the iPhone, which sends them whenever they change.
//

import Foundation
import Observation
import os

@MainActor
@Observable
public final class WatchAccountModel {
    public private(set) var isSignedIn: Bool
    public private(set) var doors: [Location]

    private let configuration: Configuration
    private let cache: Cache

    private static let log = Logger(subsystem: "com.dejanlevec.dooropener", category: "watch")

    public init(configuration: Configuration = Configuration(), cache: Cache = Cache()) {
        self.configuration = configuration
        self.cache = cache
        self.isSignedIn = !configuration.get().hostname.isEmpty
        self.doors = cache.getCachedLocations() ?? []
    }

    /// Reads what is saved on the watch again.
    public func reload() {
        isSignedIn = !configuration.get().hostname.isEmpty
        doors = isSignedIn ? (cache.getCachedLocations() ?? []) : []
    }

    /// Takes over what the iPhone sent. Returns false if it couldn't be saved; nothing changes then.
    @discardableResult
    public func receive(_ payload: WatchPayload) -> Bool {
        do {
            try payload.apply(to: configuration, cache: cache)
        } catch {
            Self.log.error("Couldn't save what the iPhone sent: \(String(describing: error), privacy: .public)")
            return false
        }
        reload()
        return true
    }

    /// What the watch app does at launch. Anything saved before the watch shared its storage with its widgets is
    /// moved first, so the widgets can read the account too, and only then is the account read.
    public static func atLaunch(
        secrets: SecretStore? = nil,
        sharedDefaults: UserDefaults? = nil,
        legacyDefaults: UserDefaults = .standard
    ) -> WatchAccountModel {
        StorageMigration.run(secrets: secrets, sharedDefaults: sharedDefaults, legacyDefaults: legacyDefaults)
        return WatchAccountModel(configuration: Configuration(store: secrets), cache: Cache(defaults: sharedDefaults))
    }
}
