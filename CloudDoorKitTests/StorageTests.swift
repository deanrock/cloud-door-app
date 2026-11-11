//
//  StorageTests.swift
//  CloudDoorKitTests
//

import Foundation
import Testing
@testable import CloudDoorKit

final class FakeSecretStore: SecretStore {
    var values: [String: String]
    private(set) var setCalls: [String] = []
    var failsOnSet = false

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func get(_ key: String) -> String? { values[key] }

    func remove(_ key: String) {
        values[key] = nil
    }

    func set(_ value: String, forKey key: String) throws {
        if failsOnSet { throw SecretStoreError(status: -34018) }
        setCalls.append(key)
        values[key] = value
    }
}

/// A throwaway defaults store, removed when the test finishes.
func makeDefaults() -> UserDefaults {
    let name = "test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// Counts notifications from one specific sender, so tests running in parallel don't see each other's.
func makeLocation(id: String = "1", name: String = "Front door", radius: Int = 50) -> Location {
    Location(name: name, id: id, geolocations: [
        Geolocation(id: id, name: name, latitude: 46.05, longitude: 14.5, radius: radius)
    ])
}

struct CacheTests {
    @Test func roundTripsLocations() {
        let cache = Cache(defaults: makeDefaults())
        #expect(cache.getCachedLocations() == nil)

        cache.setCachedLocations(locations: [makeLocation(id: "a"), makeLocation(id: "b")])

        #expect(cache.getCachedLocations()?.map(\.id) == ["a", "b"])
    }

    @Test func corruptDataReturnsNil() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: Cache.cachedLocationsKey)

        #expect(Cache(defaults: defaults).getCachedLocations() == nil)
    }

    @Test func clearRemovesCachedLocations() {
        let cache = Cache(defaults: makeDefaults())
        cache.setCachedLocations(locations: [makeLocation()])

        cache.clearCachedLocations()

        #expect(cache.getCachedLocations() == nil)
    }

    /// Regression: `store(key:)` used to ignore its key and always write to the locations key.
    @Test func storeWritesUnderTheLocationsKey() {
        let defaults = makeDefaults()
        Cache(defaults: defaults).setCachedLocations(locations: [makeLocation()])

        #expect(defaults.data(forKey: Cache.cachedLocationsKey) != nil)
    }
}

struct ConfigurationTests {
    @Test func roundTripsValues() throws {
        let configuration = Configuration(store: FakeSecretStore())
        try configuration.set(username: "u", password: "p", hostname: "https://h")

        let values = configuration.get()
        #expect(values.username == "u")
        #expect(values.password == "p")
        #expect(values.hostname == "https://h")
    }

    @Test func clearRemovesTheWholeAccount() {
        let configuration = Configuration(store: FakeSecretStore(["username": "u", "password": "p", "hostname": "h"]))

        configuration.clear()

        let values = configuration.get()
        #expect(values.username == "" && values.password == "" && values.hostname == "")
    }

    @Test func clearingAnEmptyAccountIsFine() {
        let configuration = Configuration(store: FakeSecretStore())

        configuration.clear()

        #expect(configuration.get().hostname == "")
    }

    @Test func setThrowsWhenTheStoreFails() {
        let store = FakeSecretStore()
        store.failsOnSet = true

        #expect(throws: SecretStoreError.self) {
            try Configuration(store: store).set(username: "u", password: "p", hostname: "h")
        }
    }

    @Test func missingValuesAreEmptyStrings() {
        let values = Configuration(store: FakeSecretStore()).get()
        #expect(values.username == "")
        #expect(values.password == "")
        #expect(values.hostname == "")
    }
}

struct StorageMigrationTests {
    @Test func copiesLegacyCacheIntoSharedDefaults() {
        let legacy = makeDefaults()
        let shared = makeDefaults()
        Cache(defaults: legacy).setCachedLocations(locations: [makeLocation(id: "old")])

        StorageMigration.run(secrets: FakeSecretStore(), sharedDefaults: shared, legacyDefaults: legacy)

        #expect(Cache(defaults: shared).getCachedLocations()?.map(\.id) == ["old"])
    }

    @Test func runningTwiceChangesNothing() {
        let legacy = makeDefaults()
        let shared = makeDefaults()
        Cache(defaults: legacy).setCachedLocations(locations: [makeLocation(id: "old")])
        let secrets = FakeSecretStore(["username": "u"])

        StorageMigration.run(secrets: secrets, sharedDefaults: shared, legacyDefaults: legacy)
        let callsAfterFirstRun = secrets.setCalls

        // New legacy data after the first run must not be copied again.
        Cache(defaults: legacy).setCachedLocations(locations: [makeLocation(id: "newer")])
        StorageMigration.run(secrets: secrets, sharedDefaults: shared, legacyDefaults: legacy)

        #expect(Cache(defaults: shared).getCachedLocations()?.map(\.id) == ["old"])
        #expect(secrets.setCalls == callsAfterFirstRun)
    }

    @Test func neverOverwritesExistingSharedCache() {
        let legacy = makeDefaults()
        let shared = makeDefaults()
        Cache(defaults: legacy).setCachedLocations(locations: [makeLocation(id: "old")])
        Cache(defaults: shared).setCachedLocations(locations: [makeLocation(id: "current")])

        StorageMigration.run(secrets: FakeSecretStore(), sharedDefaults: shared, legacyDefaults: legacy)

        #expect(Cache(defaults: shared).getCachedLocations()?.map(\.id) == ["current"])
    }

    @Test func resavesOnlyExistingSecretsAndKeepsValues() {
        let secrets = FakeSecretStore(["username": "u", "hostname": "https://h"])

        StorageMigration.run(secrets: secrets, sharedDefaults: makeDefaults(), legacyDefaults: makeDefaults())

        #expect(Set(secrets.setCalls) == ["username", "hostname"])
        #expect(secrets.values == ["username": "u", "hostname": "https://h"])
    }

    /// Accounts saved before iCloud syncing was added are saved again once, so that they sync too.
    @Test func anAccountSavedBeforeSyncingWasAddedIsSavedAgain() {
        let shared = makeDefaults()
        shared.set(true, forKey: "v1-sharedStorageMigrated")
        let secrets = FakeSecretStore(["username": "u", "password": "p", "hostname": "h"])

        StorageMigration.run(secrets: secrets, sharedDefaults: shared, legacyDefaults: makeDefaults())

        #expect(Set(secrets.setCalls) == ["username", "password", "hostname"])
        #expect(secrets.values == ["username": "u", "password": "p", "hostname": "h"])
    }

    @Test func failedSecretSaveLeavesMigrationToRetry() {
        let shared = makeDefaults()
        let secrets = FakeSecretStore(["username": "u"])
        secrets.failsOnSet = true

        StorageMigration.run(secrets: secrets, sharedDefaults: shared, legacyDefaults: makeDefaults())
        #expect(shared.bool(forKey: StorageMigration.migratedKey) == false)

        secrets.failsOnSet = false
        StorageMigration.run(secrets: secrets, sharedDefaults: shared, legacyDefaults: makeDefaults())
        #expect(shared.bool(forKey: StorageMigration.migratedKey) == true)
    }

    @Test func emptyLegacyStoreIsFine() {
        let shared = makeDefaults()

        StorageMigration.run(secrets: FakeSecretStore(), sharedDefaults: shared, legacyDefaults: makeDefaults())

        #expect(Cache(defaults: shared).getCachedLocations() == nil)
    }
}
