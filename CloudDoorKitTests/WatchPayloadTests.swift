//
//  WatchPayloadTests.swift
//  CloudDoorKitTests
//

import Foundation
import Testing
@testable import CloudDoorKit

struct WatchPayloadTests {
    let payload = WatchPayload(
        username: "anna@example.com", password: "secret", hostname: "https://h",
        doors: [makeLocation(id: "a", name: "Front door"), makeLocation(id: "b", name: "Garage")])

    // MARK: Building

    @Test func currentTakesTheAccountAndDoorsFromTheIPhone() {
        let configuration = Configuration(store: FakeSecretStore(["username": "u", "password": "p", "hostname": "https://h"]))
        let cache = Cache(defaults: makeDefaults())
        cache.setCachedLocations(locations: [makeLocation(id: "a")])

        let current = WatchPayload.current(configuration: configuration, cache: cache)

        #expect(current.username == "u" && current.password == "p" && current.hostname == "https://h")
        #expect(current.doors.map(\.id) == ["a"])
        #expect(!current.isSignedOut)
    }

    @Test func noDoorsAreSentWhenNobodyIsSignedIn() {
        let cache = Cache(defaults: makeDefaults())
        cache.setCachedLocations(locations: [makeLocation(id: "left-over")])

        let current = WatchPayload.current(configuration: Configuration(store: FakeSecretStore()), cache: cache)

        #expect(current.isSignedOut)
        #expect(current.doors.isEmpty)
    }

    // MARK: Sending and reading

    @Test func survivesTheTripThroughWatchConnectivity() throws {
        let context = try payload.context()

        #expect(WatchPayload.decode(context: context) == payload)
    }

    @Test func theContextOnlyHoldsTypesWatchConnectivityAccepts() throws {
        let context = try payload.context()

        #expect(context.values.allSatisfy { $0 is Data || $0 is String || $0 is NSNumber })
    }

    @Test func somethingThatIsNotAPayloadIsIgnored() {
        #expect(WatchPayload.decode(context: [:]) == nil)
        #expect(WatchPayload.decode(context: ["payload": "text"]) == nil)
        #expect(WatchPayload.decode(context: ["other": Data("{}".utf8)]) == nil)
    }

    @Test func aDamagedPayloadIsIgnored() {
        #expect(WatchPayload.decode(context: ["payload": Data("not json".utf8)]) == nil)
    }

    // MARK: Applying

    @Test func theWatchSavesTheAccountAndTheDoors() throws {
        let store = FakeSecretStore()
        let configuration = Configuration(store: store)
        let cache = Cache(defaults: makeDefaults())

        try payload.apply(to: configuration, cache: cache)

        let saved = configuration.get()
        #expect(saved.username == "anna@example.com" && saved.password == "secret" && saved.hostname == "https://h")
        #expect(cache.getCachedLocations()?.map(\.id) == ["a", "b"])
    }

    @Test func anAccountThatIsAlreadySavedIsNotSavedAgain() throws {
        let store = FakeSecretStore()
        let configuration = Configuration(store: store)
        let cache = Cache(defaults: makeDefaults())
        try payload.apply(to: configuration, cache: cache)
        let savesAfterFirstMessage = store.setCalls.count

        var newDoors = payload
        newDoors.doors = [makeLocation(id: "c")]
        try newDoors.apply(to: configuration, cache: cache)

        #expect(store.setCalls.count == savesAfterFirstMessage)
        #expect(cache.getCachedLocations()?.map(\.id) == ["c"])
    }

    @Test func aChangedAccountIsSaved() throws {
        let configuration = Configuration(store: FakeSecretStore())
        let cache = Cache(defaults: makeDefaults())
        try payload.apply(to: configuration, cache: cache)

        var other = payload
        other.password = "new password"
        try other.apply(to: configuration, cache: cache)

        #expect(configuration.get().password == "new password")
    }

    @Test func signingOutOnTheIPhoneSignsTheWatchOut() throws {
        let configuration = Configuration(store: FakeSecretStore())
        let cache = Cache(defaults: makeDefaults())
        try payload.apply(to: configuration, cache: cache)

        try WatchPayload(username: "", password: "", hostname: "", doors: []).apply(to: configuration, cache: cache)

        #expect(configuration.get().hostname.isEmpty)
        #expect(cache.getCachedLocations() == nil)
    }

    @Test func aFailedSaveIsReported() {
        let store = FakeSecretStore()
        store.failsOnSet = true

        #expect(throws: SecretStoreError.self) {
            try payload.apply(to: Configuration(store: store), cache: Cache(defaults: makeDefaults()))
        }
    }
}
