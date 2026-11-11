//
//  IntentTests.swift
//  CloudDoorKitTests
//

import Foundation
import Testing
@testable import CloudDoorKit

final class FakeOpener: DoorOpening {
    private(set) var attempts = 0
    /// What each attempt throws, in order; attempts after the list ends succeed.
    var errors: [Error?]

    init(errors: [Error?] = []) {
        self.errors = errors
    }

    func open(doorId: String) async throws {
        attempts += 1
        if errors.count >= attempts, let error = errors[attempts - 1] {
            throw error
        }
    }
}

struct OpenDoorFlowTests {
    @Test func succeedsWithoutNeedingTheForeground() async throws {
        let opener = FakeOpener()
        var continued = 0

        try await OpenDoorIntent.openDoor(id: "1", using: opener, canContinueInForeground: true) { continued += 1 }

        #expect(opener.attempts == 1)
        #expect(continued == 0)
    }

    @Test func bringsTheAppForwardOnceWhenThereIsNoLocation() async throws {
        let opener = FakeOpener(errors: [DoorError.locationUnknown, nil])
        var continued = 0

        try await OpenDoorIntent.openDoor(id: "1", using: opener, canContinueInForeground: true) { continued += 1 }

        #expect(continued == 1)
        #expect(opener.attempts == 2)
    }

    @Test func failsWhenNoLocationAndTheForegroundIsNotAvailable() async {
        let opener = FakeOpener(errors: [DoorError.locationUnknown])

        let error = await doorError {
            try await OpenDoorIntent.openDoor(id: "1", using: opener, canContinueInForeground: false) {
                Issue.record("Must not continue in the foreground")
            }
        }

        #expect(error == .locationUnknown)
        #expect(opener.attempts == 1)
    }

    @Test func triesAgainOnlyOnce() async {
        let opener = FakeOpener(errors: [DoorError.locationUnknown, DoorError.locationUnknown, nil])

        let error = await doorError {
            try await OpenDoorIntent.openDoor(id: "1", using: opener, canContinueInForeground: true) {}
        }

        #expect(error == .locationUnknown)
        #expect(opener.attempts == 2)
    }

    @Test func tooFarDoesNotBringTheAppForward() async {
        let tooFar = DoorError.tooFar(name: "Gate", distance: 90, radius: 50)
        let opener = FakeOpener(errors: [tooFar])

        let error = await doorError {
            try await OpenDoorIntent.openDoor(id: "1", using: opener, canContinueInForeground: true) {
                Issue.record("Must not continue in the foreground")
            }
        }

        #expect(error == tooFar)
        #expect(opener.attempts == 1)
    }

    @Test func aFailedContinuationDoesNotOpenTheDoor() async {
        struct Declined: Error {}
        let opener = FakeOpener(errors: [DoorError.locationUnknown])

        await #expect(throws: Declined.self) {
            try await OpenDoorIntent.openDoor(id: "1", using: opener, canContinueInForeground: true) { throw Declined() }
        }
        #expect(opener.attempts == 1)
    }

    @Test func serverErrorsAreNotRetried() async {
        let opener = FakeOpener(errors: [ApiError.runtimeError("door offline")])

        await #expect(throws: ApiError.self) {
            try await OpenDoorIntent.openDoor(id: "1", using: opener, canContinueInForeground: true) {}
        }
        #expect(opener.attempts == 1)
    }
}

struct DoorIntentErrorTests {
    func message(of error: Error) -> String? {
        (error as? DoorIntentFailure)?.message
    }

    @Test func serverMessagesBecomeReadableFailures() {
        #expect(message(of: DoorIntentError.wrap(ApiError.runtimeError("Wrong password"))) == "Wrong password")
    }

    @Test func offlineAndTimeoutGetFriendlyMessages() {
        #expect(message(of: DoorIntentError.wrap(URLError(.notConnectedToInternet)))?.contains("offline") == true)
        #expect(message(of: DoorIntentError.wrap(URLError(.timedOut)))?.contains("too long") == true)
    }

    @Test func unreachableServersGetAClearMessage() {
        let text = message(of: DoorIntentError.wrap(URLError(.cannotFindHost)))

        #expect(text?.contains("Can't reach the server") == true)
    }

    @Test func otherNetworkErrorsKeepTheirDescription() {
        let error = URLError(.badURL)
        #expect(message(of: DoorIntentError.wrap(error)) == error.localizedDescription)
    }

    @Test func serverErrorsAreExplainedInPlainWords() {
        let text = message(of: DoorIntentError.wrap(ApiError.http(status: 503, body: "<html>Service Unavailable</html>")))

        #expect(text == "The server had a problem (error 503). Try again in a moment.")
    }

    /// The system uses these to control the flow of an intent; they must reach it untouched.
    @Test func cancellationsAndDoorErrorsPassThrough() {
        #expect(DoorIntentError.wrap(CancellationError()) is CancellationError)
        #expect((DoorIntentError.wrap(URLError(.cancelled)) as? URLError)?.code == .cancelled)
        #expect(DoorIntentError.wrap(DoorError.locationUnknown) as? DoorError == .locationUnknown)
    }

    @Test func doorErrorsExplainThemselvesInSiri() {
        let tooFar = DoorError.tooFar(name: "Gate", distance: 90, radius: 50)
        let text = String(localized: tooFar.localizedStringResource)

        #expect(text == "Too far away. Gate is 90m away. Get within 50m to open it.")
        #expect(text.contains("Gate"))
        #expect(text.contains("90"))
        #expect(text.contains("50"))
        #expect(String(localized: DoorError.notConfigured.localizedStringResource).contains("credentials"))
    }
}

struct DoorQueryTests {
    let doors = [
        makeLocation(id: "a", name: "Front door"),
        makeLocation(id: "b", name: "Garage"),
        makeLocation(id: "c", name: "Café entrance"),
    ]

    @Test func resolveKeepsTheRequestedOrderAndSkipsMissingIds() {
        let result = DoorQuery.resolve(ids: ["c", "missing", "a"], in: doors)

        #expect(result.map(\.id) == ["c", "a"])
    }

    @Test func resolveCarriesTheDoorName() {
        #expect(DoorQuery.resolve(ids: ["b"], in: doors).first?.name == "Garage")
    }

    @Test func searchIgnoresCaseAndAccents() {
        #expect(DoorQuery.search("GARAGE", in: doors).map(\.id) == ["b"])
        #expect(DoorQuery.search("cafe", in: doors).map(\.id) == ["c"])
    }

    @Test func searchMatchesPartsOfTheName() {
        #expect(DoorQuery.search("door", in: doors).map(\.id) == ["a"])
    }

    @Test func emptySearchReturnsEveryDoor() {
        #expect(DoorQuery.search("  ", in: doors).count == 3)
    }

    @Test func searchWithNoMatchIsEmpty() {
        #expect(DoorQuery.search("balcony", in: doors).isEmpty)
    }

    @Test func entityKeepsTheServerIdAsItsIdentity() {
        let entity = DoorEntity(doors[0])

        #expect(entity.id == "a")
        #expect(entity.name == "Front door")
    }
}
