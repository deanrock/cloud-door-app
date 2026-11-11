//
//  DoorActivityTests.swift
//  CloudDoorKitTests
//

import Foundation
import Testing
@testable import CloudDoorKit

let t0 = Date(timeIntervalSince1970: 2_000_000)

func activity(_ phase: DoorActivity.Phase, door: String = "1", message: String? = nil, at date: Date = t0) -> DoorActivity {
    DoorActivity(doorId: door, phase: phase, message: message, date: date)
}

struct DoorActivityTests {
    @Test func eachPhaseIsShownForItsOwnTime() {
        #expect(activity(.opened).expiry == t0.addingTimeInterval(3))
        #expect(activity(.failed).expiry == t0.addingTimeInterval(4))
        #expect(activity(.opening).expiry == t0.addingTimeInterval(30))
    }

    @Test func isCurrentUntilTheExpiryMoment() {
        let opened = activity(.opened)

        #expect(opened.isCurrent(at: t0.addingTimeInterval(2.9)))
        #expect(!opened.isCurrent(at: t0.addingTimeInterval(3)))
    }
}

struct DoorActivityStoreTests {
    @Test func recordsAndReadsBackTheActivity() {
        let store = DoorActivityStore(defaults: makeDefaults())
        store.record(activity(.failed, message: "Too far away"))

        #expect(store.current(for: "1", at: t0.addingTimeInterval(1)) == activity(.failed, message: "Too far away"))
    }

    @Test func expiredActivityIsNotReturned() {
        let store = DoorActivityStore(defaults: makeDefaults())
        store.record(activity(.opened))

        #expect(store.current(for: "1", at: t0.addingTimeInterval(6)) == nil)
    }

    @Test func doorsDoNotSeeEachOthersActivity() {
        let store = DoorActivityStore(defaults: makeDefaults())
        store.record(activity(.opened, door: "a"))

        #expect(store.current(for: "b", at: t0) == nil)
    }

    @Test func aNewerActivityReplacesTheOlderOne() {
        let store = DoorActivityStore(defaults: makeDefaults())
        store.record(activity(.opening))
        store.record(activity(.opened, at: t0.addingTimeInterval(1)))

        #expect(store.current(for: "1", at: t0.addingTimeInterval(2))?.phase == .opened)
    }

    @Test func corruptDataIsIgnored() {
        let defaults = makeDefaults()
        defaults.set(Data("nope".utf8), forKey: "v1-doorActivity-1")

        #expect(DoorActivityStore(defaults: defaults).current(for: "1", at: t0) == nil)
    }
}

struct DoorStatusTests {
    @Test func idleShowsTheDoorName() {
        let status = DoorStatus(doorName: "Front door", activity: nil, now: t0)

        #expect(status == DoorStatus(doorName: "Front door", activity: nil, now: t0))
        #expect(status.text == "Front door")
        #expect(status.tone == .idle)
    }

    @Test func noDoorAsksToChooseOne() {
        let status = DoorStatus(doorName: nil, activity: activity(.opened), now: t0)

        #expect(status.text == "Choose Door")
        #expect(status.tone == .idle)
    }

    @Test func openingShowsProgress() {
        let status = DoorStatus(doorName: "Front door", activity: activity(.opening), now: t0.addingTimeInterval(1))

        #expect(status.text == "Opening…")
        #expect(status.tone == .working)
    }

    @Test func openedShowsSuccess() {
        let status = DoorStatus(doorName: "Front door", activity: activity(.opened), now: t0.addingTimeInterval(1))

        #expect(status.text == "Opened")
        #expect(status.tone == .success)
    }

    @Test func failureShowsTheReason() {
        let failed = activity(.failed, message: "Too far away")
        let status = DoorStatus(doorName: "Front door", activity: failed, now: t0.addingTimeInterval(1))

        #expect(status.text == "Too far away")
        #expect(status.tone == .failure)
    }

    @Test func failureWithoutAReasonStillSaysSo() {
        let status = DoorStatus(doorName: "Front door", activity: activity(.failed), now: t0)

        #expect(status.text == "Couldn't open")
    }

    @Test func anExpiredResultFallsBackToTheNormalLook() {
        let status = DoorStatus(doorName: "Front door", activity: activity(.failed, message: "Too far away"), now: t0.addingTimeInterval(5))

        #expect(status.text == "Front door")
        #expect(status.tone == .idle)
    }
}

struct ControlSymbolTests {
    func symbol(_ activity: DoorActivity?) -> String {
        DoorStatus(doorName: "Front door", activity: activity, now: t0.addingTimeInterval(1)).controlSymbol
    }

    @Test func idleControlShowsTheClosedDoor() {
        #expect(symbol(nil) == "door.left.hand.closed")
    }

    @Test func successInvertsTheIconToAnOpenDoor() {
        #expect(symbol(activity(.opened)) == "door.left.hand.open")
    }

    @Test func failureShowsAnErrorIcon() {
        #expect(symbol(activity(.failed, message: "Too far away")) == "xmark.circle.fill")
    }

    @Test func aControlWithoutADoorShowsTheClosedDoor() {
        #expect(DoorStatus(doorName: nil, activity: nil).controlSymbol == "door.left.hand.closed")
    }
}

struct OpenDoorActivityFlowTests {
    /// Runs the flow and returns every phase the widgets would have been told about, in order.
    func run(
        opener: FakeOpener,
        canContinueInForeground: Bool = true,
        doorId: String = "1"
    ) async -> (phases: [DoorActivity.Phase], message: String?, reloads: Int, threw: Bool, reverts: [TimeInterval]) {
        let store = DoorActivityStore(defaults: makeDefaults())
        var phases: [DoorActivity.Phase] = []
        var reloads = 0
        var reverts: [TimeInterval] = []
        let recorder = DoorActivityRecorder(
            store: store,
            reload: { _ in
                reloads += 1
                if let current = store.current(for: doorId) { phases.append(current.phase) }
            },
            scheduleRevert: { reverts.append($0) },
            now: { Date() })

        var threw = false
        do {
            try await OpenDoorIntent.run(
                id: doorId, using: opener, recorder: recorder,
                canContinueInForeground: canContinueInForeground, continueInForeground: {})
        } catch {
            threw = true
        }
        return (phases, store.current(for: doorId)?.message, reloads, threw, reverts)
    }

    @Test func successShowsOpeningThenOpened() async {
        let result = await run(opener: FakeOpener())

        #expect(result.phases == [.opening, .opened])
        #expect(result.threw == false)
    }

    @Test func tooFarShowsOpeningThenTheReason() async {
        let opener = FakeOpener(errors: [DoorError.tooFar(name: "Gate", distance: 90, radius: 50)])

        let result = await run(opener: opener)

        #expect(result.phases == [.opening, .failed])
        #expect(result.message == "Too far away")
        #expect(result.threw)
    }

    @Test func missingLocationWithoutForegroundShowsTheReason() async {
        let result = await run(opener: FakeOpener(errors: [DoorError.locationUnknown]), canContinueInForeground: false)

        #expect(result.message == "Location unknown")
        #expect(result.threw)
    }

    @Test func serverErrorsAreSummarisedBriefly() async {
        let result = await run(opener: FakeOpener(errors: [ApiError.runtimeError("a very long server explanation")]))

        #expect(result.message == "Couldn't open")
        #expect(result.threw)
    }

    @Test func retryingForTheLocationDoesNotShowAFailureInBetween() async {
        let result = await run(opener: FakeOpener(errors: [DoorError.locationUnknown, nil]))

        #expect(result.phases == [.opening, .opened])
        #expect(result.threw == false)
    }

    @Test func widgetsAreRefreshedAtEveryStep() async {
        #expect(await run(opener: FakeOpener()).reloads == 2)
        #expect(await run(opener: FakeOpener(errors: [DoorError.notConfigured])).reloads == 2)
    }

    @Test func theNormalLookIsRestoredAfterTheResultOnly() async {
        #expect(await run(opener: FakeOpener()).reverts == [3])
        #expect(await run(opener: FakeOpener(errors: [DoorError.locationUnknown]), canContinueInForeground: false).reverts == [4])
    }

    @Test func summariesAreShortAndSpecific() {
        #expect(DoorIntentError.summary(of: DoorError.tooFar(name: "G", distance: 1, radius: 1)) == "Too far away")
        #expect(DoorIntentError.summary(of: URLError(.notConnectedToInternet)) == "Offline")
        #expect(DoorIntentError.summary(of: URLError(.timedOut)) == "Timed out")
        #expect(DoorIntentError.summary(of: CancellationError()) == "Cancelled")
        #expect(DoorIntentError.summary(of: URLError(.badURL)) == "Couldn't open")
    }
}
