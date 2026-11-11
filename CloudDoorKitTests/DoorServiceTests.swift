//
//  DoorServiceTests.swift
//  CloudDoorKitTests
//

import CoreLocation
import Foundation
import Testing
@testable import CloudDoorKit

final class FakeAPI: DoorAPI {
    private(set) var calls: [String] = []
    /// Whether a door was opened; failures before that point must leave this false.
    var opened: Bool { calls.contains { $0.hasPrefix("openDoor") } }
    var tokenError: Error?
    var openError: Error?

    func getToken() async throws -> String {
        calls.append("getToken")
        if let tokenError { throw tokenError }
        return "token"
    }

    func openDoor(token: String, accessPointId: String) async throws {
        calls.append("openDoor:\(accessPointId)")
        if let openError { throw openError }
    }
}

struct FakeLocator: LocationProviding {
    var location: CLLocation?
    func currentLocation() async -> CLLocation? { location }
}

/// The door made by `makeLocation` sits here.
let doorCoordinate = CLLocationCoordinate2D(latitude: 46.05, longitude: 14.5)

func location(metersNorthOfDoor meters: Double, accuracy: CLLocationAccuracy = 5, at date: Date = Date()) -> CLLocation {
    // One degree of latitude is about 111,195 m.
    CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: doorCoordinate.latitude + meters / 111_195, longitude: doorCoordinate.longitude),
        altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: date)
}

struct ServiceFixture {
    let api = FakeAPI()
    let cache = Cache(defaults: makeDefaults())
    let service: DoorService

    init(
        credentials: Bool = true,
        doors: [Location] = [makeLocation(id: "door-1", name: "Front door", radius: 50)],
        device: CLLocation? = location(metersNorthOfDoor: 0)
    ) {
        let secrets = FakeSecretStore(credentials ? ["username": "u", "password": "p", "hostname": "https://h"] : [:])
        cache.setCachedLocations(locations: doors)
        let api = api
        service = DoorService(
            locator: FakeLocator(location: device),
            configuration: Configuration(store: secrets),
            cache: cache,
            apiFactory: { _ in api })
    }
}

/// Runs the body and returns the `DoorError` it threw, if any.
func doorError(_ body: () async throws -> Void) async -> DoorError? {
    do {
        try await body()
        return nil
    } catch {
        return error as? DoorError
    }
}

struct DoorServiceOpenTests {
    @Test func opensDoorWhenInsideRadius() async throws {
        let fixture = ServiceFixture(device: location(metersNorthOfDoor: 10))

        try await fixture.service.open(doorId: "door-1")

        #expect(fixture.api.calls == ["getToken", "openDoor:door-1"])
    }

    @Test func rejectsDoorOutsideRadiusWithoutCallingTheAPI() async {
        let fixture = ServiceFixture(device: location(metersNorthOfDoor: 80))

        let error = await doorError { try await fixture.service.open(doorId: "door-1") }

        guard case .tooFar(let name, let distance, let radius) = error else {
            Issue.record("Expected tooFar, got \(String(describing: error))")
            return
        }
        #expect(name == "Front door")
        #expect(radius == 50)
        #expect((78...82).contains(distance))
        #expect(!fixture.api.opened)
    }

    /// The rule is `distance < radius`, so being exactly at the radius is already too far.
    @Test func exactlyAtTheRadiusIsRejected() async {
        let fixture = ServiceFixture(
            doors: [makeLocation(id: "door-1", radius: 0)],
            device: location(metersNorthOfDoor: 0))

        let error = await doorError { try await fixture.service.open(doorId: "door-1") }

        #expect(error == .tooFar(name: "Front door", distance: 0, radius: 0))
        #expect(!fixture.api.opened)
    }

    @Test func rejectsWhenLocationIsUnknown() async {
        let fixture = ServiceFixture(device: nil)

        let error = await doorError { try await fixture.service.open(doorId: "door-1") }

        #expect(error == .locationUnknown)
        #expect(!fixture.api.opened)
    }

    @Test func rejectsWhenNotConfigured() async {
        let fixture = ServiceFixture(credentials: false)

        let error = await doorError { try await fixture.service.open(doorId: "door-1") }

        #expect(error == .notConfigured)
        #expect(fixture.api.calls.isEmpty)
    }

    @Test func rejectsUnknownDoor() async {
        let fixture = ServiceFixture()

        let error = await doorError { try await fixture.service.open(doorId: "nope") }

        #expect(error == .doorNotFound)
        #expect(fixture.api.calls.isEmpty)
    }

    @Test func rejectsDoorWithoutGeolocations() async {
        let broken = Location(name: "Broken", id: "door-1", geolocations: [])
        let fixture = ServiceFixture(doors: [broken])

        let error = await doorError { try await fixture.service.open(doorId: "door-1") }

        #expect(error == .doorNotFound)
    }

    @Test func tokenErrorsPropagateAndNothingIsOpened() async {
        let fixture = ServiceFixture()
        fixture.api.tokenError = ApiError.runtimeError("bad password")

        await #expect(throws: ApiError.self) {
            try await fixture.service.open(doorId: "door-1")
        }
        #expect(fixture.api.calls == ["getToken"])
    }

    @Test func openErrorsPropagate() async {
        let fixture = ServiceFixture()
        fixture.api.openError = ApiError.runtimeError("door offline")

        await #expect(throws: ApiError.self) {
            try await fixture.service.open(doorId: "door-1")
        }
        #expect(fixture.api.calls == ["getToken", "openDoor:door-1"])
    }
}

struct DoorErrorTests {
    @Test func messagesMatchWhatTheAppShows() {
        #expect(DoorError.tooFar(name: "Gate", distance: 120, radius: 50).title == "Too far away")
        #expect(DoorError.tooFar(name: "Gate", distance: 120, radius: 50).message
                == "Gate is 120m away. Get within 50m to open it.")
        #expect(DoorError.locationUnknown.title == "Location unknown")
        #expect(DoorError.notConfigured.title == "No credentials")
        #expect(DoorError.doorNotFound.title == "Door not found")
    }

    @Test func errorDescriptionIsTheMessage() {
        #expect(DoorError.locationUnknown.localizedDescription == DoorError.locationUnknown.message)
    }
}

struct LocationResolverTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func resolver(fresh: CLLocation?, lastKnown: CLLocation?, freshCalls: Counter = Counter()) -> LocationResolver {
        let now = now
        return LocationResolver(
            fresh: { _ in freshCalls.count += 1; return fresh },
            lastKnown: { lastKnown },
            now: { now })
    }

    final class Counter {
        var count = 0
    }

    @Test func aVeryRecentLastKnownLocationIsUsedWithoutWaiting() async {
        let recent = location(metersNorthOfDoor: 5, accuracy: 20, at: now.addingTimeInterval(-10))
        let calls = Counter()

        let result = await resolver(fresh: location(metersNorthOfDoor: 1, at: now), lastKnown: recent, freshCalls: calls).currentLocation()

        #expect(result === recent)
        #expect(calls.count == 0)
    }

    @Test func recentMeansAtMostThirtySeconds() async {
        let edge = location(metersNorthOfDoor: 5, at: now.addingTimeInterval(-30))
        let justOver = location(metersNorthOfDoor: 5, at: now.addingTimeInterval(-31))
        let freshFix = location(metersNorthOfDoor: 1, at: now)

        #expect(await resolver(fresh: freshFix, lastKnown: edge).currentLocation() === edge)
        #expect(await resolver(fresh: freshFix, lastKnown: justOver).currentLocation() === freshFix)
    }

    @Test func aFreshFixBeatsAnOlderLastKnownLocation() async {
        let freshFix = location(metersNorthOfDoor: 1, at: now)
        let older = location(metersNorthOfDoor: 500, at: now.addingTimeInterval(-60))

        let result = await resolver(fresh: freshFix, lastKnown: older).currentLocation()

        #expect(result === freshFix)
    }

    @Test func fallsBackToAnOlderAccurateLastKnownLocation() async {
        let older = location(metersNorthOfDoor: 5, accuracy: 20, at: now.addingTimeInterval(-60))

        let result = await resolver(fresh: nil, lastKnown: older).currentLocation()

        #expect(result === older)
    }

    @Test func acceptsAnOlderLastKnownExactlyAtTheLimits() async {
        let edge = location(metersNorthOfDoor: 5, accuracy: 100, at: now.addingTimeInterval(-120))

        #expect(await resolver(fresh: nil, lastKnown: edge).currentLocation() === edge)
    }

    @Test func rejectsLastKnownThatIsTooOld() async {
        let old = location(metersNorthOfDoor: 5, at: now.addingTimeInterval(-121))

        #expect(await resolver(fresh: nil, lastKnown: old).currentLocation() == nil)
    }

    @Test func rejectsLastKnownThatIsTooInaccurate() async {
        let vague = location(metersNorthOfDoor: 5, accuracy: 101, at: now)

        // Even a brand new location isn't used if it is too vague.
        #expect(await resolver(fresh: nil, lastKnown: vague).currentLocation() == nil)
    }

    @Test func rejectsInvalidLocations() async {
        let invalid = location(metersNorthOfDoor: 5, accuracy: -1, at: now)

        #expect(await resolver(fresh: invalid, lastKnown: invalid).currentLocation() == nil)
    }

    @Test func returnsNilWhenThereIsNothing() async {
        #expect(await resolver(fresh: nil, lastKnown: nil).currentLocation() == nil)
    }

    @Test func passesTheConfiguredTimeoutToTheFreshLookup() async {
        var requested: Duration?
        let policy = LocationResolver.Policy(timeout: .seconds(3))
        let resolver = LocationResolver(policy: policy, fresh: { requested = $0; return nil }, lastKnown: { nil })

        _ = await resolver.currentLocation()

        #expect(requested == .seconds(3))
    }

    @Test func theDefaultWaitForAFreshFixKeepsTheFirstErrorUnderASecond() {
        #expect(LocationResolver.Policy().timeout == .seconds(1))
    }
}
