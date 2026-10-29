//
//  WatchModelTests.swift
//  CloudDoorKitTests
//

import Foundation
import Testing
@testable import CloudDoorKit

/// An opener that waits until the test lets it finish, so the "opening" state can be looked at.
final class GatedOpener: DoorOpening, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = 0
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func open(doorId: String) async throws {
        started += 1
        await withCheckedContinuation { continuation = $0 }
        if let error { throw error }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
struct DoorOpenModelTests {
    func model(_ opener: DoorOpening, opened: Duration = .milliseconds(20), failed: Duration = .milliseconds(20)) -> DoorOpenModel {
        DoorOpenModel(opener: opener, openedDisplay: opened, failedDisplay: failed)
    }

    @Test func aDoorStartsIdle() {
        #expect(model(FakeOpener()).state(for: "1") == .idle)
    }

    @Test func aSuccessShowsOpenedAndThenGoesBackToIdle() async {
        let model = model(FakeOpener(), opened: .milliseconds(200))

        let task = Task { await model.open(doorId: "1") }
        try? await Task.sleep(for: .milliseconds(80))
        #expect(model.state(for: "1") == .opened)

        await task.value
        #expect(model.state(for: "1") == .idle)
    }

    @Test func theRowShowsOpeningWhileTheRequestRuns() async {
        let opener = GatedOpener()
        let model = model(opener)

        let task = Task { await model.open(doorId: "1") }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.state(for: "1") == .opening)
        #expect(model.isBusy)

        opener.finish()
        await task.value
        #expect(!model.isBusy)
    }

    @Test func aFailureShowsWhyAndThenGoesBackToIdle() async {
        let tooFar = DoorError.tooFar(name: "Gate", distance: 120, radius: 80)
        let model = model(FakeOpener(errors: [tooFar]), failed: .milliseconds(200))

        let task = Task { await model.open(doorId: "1") }
        try? await Task.sleep(for: .milliseconds(80))
        #expect(model.state(for: "1") == .failed("Too far: 120m away, limit 80m"))

        await task.value
        #expect(model.state(for: "1") == .idle)
    }

    @Test func tapsAreIgnoredWhileAnotherDoorIsOpening() async {
        let opener = GatedOpener()
        let model = model(opener)

        let first = Task { await model.open(doorId: "1") }
        try? await Task.sleep(for: .milliseconds(50))

        await model.open(doorId: "2")

        #expect(opener.started == 1)
        #expect(model.state(for: "2") == .idle)

        opener.finish()
        await first.value
    }

    @Test func aCancelledAttemptLeavesNoResultBehind() async {
        let model = model(FakeOpener(errors: [CancellationError()]))

        await model.open(doorId: "1")

        #expect(model.state(for: "1") == .idle)
    }

    /// The first attempt's timer must not wipe the row while a second attempt is running.
    @Test func anOlderResultTimerDoesNotResetANewerAttempt() async {
        let opener = GatedOpener()
        let model = model(opener, opened: .milliseconds(200))

        // First attempt: succeeds at once and shows "opened" for 200 ms. Let it finish opening, but not the display.
        let firstOpen = Task { await model.open(doorId: "1") }
        try? await Task.sleep(for: .milliseconds(50))
        opener.finish()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.state(for: "1") == .opened)

        // Second attempt starts during that display and stays in "opening".
        let secondOpen = Task { await model.open(doorId: "1") }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.state(for: "1") == .opening)

        // The first attempt's 200 ms are over by now; the second attempt's row must still be "opening".
        try? await Task.sleep(for: .milliseconds(250))
        #expect(model.state(for: "1") == .opening)

        opener.finish()
        await firstOpen.value
        await secondOpen.value
    }
}

@MainActor
struct WatchAccountModelTests {
    let payload = WatchPayload(
        username: "anna@example.com", password: "secret", hostname: "https://h",
        doors: [makeLocation(id: "a", name: "Front door")])

    func model(secrets: FakeSecretStore = FakeSecretStore()) -> WatchAccountModel {
        WatchAccountModel(configuration: Configuration(store: secrets), cache: Cache(defaults: makeDefaults()))
    }

    @Test func aWatchWithNothingSavedIsSignedOut() {
        let model = model()

        #expect(!model.isSignedIn)
        #expect(model.doors.isEmpty)
    }

    @Test func aWatchStartsWithWhatIsAlreadySaved() {
        let secrets = FakeSecretStore(["username": "u", "password": "p", "hostname": "https://h"])
        let cache = Cache(defaults: makeDefaults())
        cache.setCachedLocations(locations: [makeLocation(id: "a")])

        let model = WatchAccountModel(configuration: Configuration(store: secrets), cache: cache)

        #expect(model.isSignedIn)
        #expect(model.doors.map(\.id) == ["a"])
    }

    @Test func whatTheIPhoneSendsAppearsOnTheWatch() {
        let model = model()

        #expect(model.receive(payload))

        #expect(model.isSignedIn)
        #expect(model.doors.map(\.name) == ["Front door"])
    }

    @Test func signingOutOnTheIPhoneEmptiesTheWatch() {
        let model = model()
        model.receive(payload)

        model.receive(WatchPayload(username: "", password: "", hostname: "", doors: []))

        #expect(!model.isSignedIn)
        #expect(model.doors.isEmpty)
    }

    @Test func aMessageFromSomethingElseIsIgnored() {
        let model = model()
        model.receive(payload)

        let handled = WatchPayload.decode(context: ["unrelated": "value"]).map { model.receive($0) } ?? false

        #expect(!handled)
        #expect(model.isSignedIn)
    }

    @Test func aFailedSaveChangesNothingAndIsReported() {
        let secrets = FakeSecretStore()
        secrets.failsOnSet = true
        let model = model(secrets: secrets)

        #expect(!model.receive(payload))
        #expect(!model.isSignedIn)
    }

    @Test func reloadPicksUpChangesMadeElsewhere() {
        let secrets = FakeSecretStore()
        let model = model(secrets: secrets)
        secrets.values = ["username": "u", "password": "p", "hostname": "https://h"]

        model.reload()

        #expect(model.isSignedIn)
    }
}

@MainActor
struct WatchLaunchTests {
    let account = ["username": "me@example.com", "password": "secret", "hostname": "https://doors.example.com"]

    @Test func aSavedAccountIsMovedToTheSharedStorageAtLaunch() {
        let secrets = FakeSecretStore(account)
        let shared = makeDefaults()

        let model = WatchAccountModel.atLaunch(secrets: secrets, sharedDefaults: shared, legacyDefaults: makeDefaults())

        // Saving again is what puts the items where the widgets can read them.
        #expect(Set(secrets.setCalls) == Set(account.keys))
        #expect(shared.bool(forKey: StorageMigration.migratedKey))
        #expect(model.isSignedIn)
    }

    @Test func theDoorsAlreadyOnTheWatchAreShown() {
        let shared = makeDefaults()
        Cache(defaults: shared).setCachedLocations(locations: [makeLocation(id: "1", name: "Gate")])

        let model = WatchAccountModel.atLaunch(secrets: FakeSecretStore(account), sharedDefaults: shared, legacyDefaults: makeDefaults())

        #expect(model.doors.map(\.name) == ["Gate"])
    }

    @Test func theMigrationRunsOnlyOnce() {
        let secrets = FakeSecretStore(account)
        let shared = makeDefaults()
        _ = WatchAccountModel.atLaunch(secrets: secrets, sharedDefaults: shared, legacyDefaults: makeDefaults())
        let savesAfterFirstLaunch = secrets.setCalls.count

        _ = WatchAccountModel.atLaunch(secrets: secrets, sharedDefaults: shared, legacyDefaults: makeDefaults())

        #expect(secrets.setCalls.count == savesAfterFirstLaunch)
    }

    @Test func aFailedMoveKeepsTheAccountAndTriesAgainNextLaunch() {
        let secrets = FakeSecretStore(account)
        secrets.failsOnSet = true
        let shared = makeDefaults()

        let model = WatchAccountModel.atLaunch(secrets: secrets, sharedDefaults: shared, legacyDefaults: makeDefaults())

        #expect(model.isSignedIn)
        #expect(shared.bool(forKey: StorageMigration.migratedKey) == false)
    }

    @Test func aWatchWithoutAnAccountStartsSignedOut() {
        let model = WatchAccountModel.atLaunch(secrets: FakeSecretStore(), sharedDefaults: makeDefaults(), legacyDefaults: makeDefaults())

        #expect(model.isSignedIn == false)
        #expect(model.doors.isEmpty)
    }
}
