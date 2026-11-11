//
//  DoorService.swift
//  CloudDoorKit
//
//  The single place that opens a door: used by the app, intents, controls, widgets and the watch.
//

import CoreLocation
import Foundation

/// The remote calls the service needs; `API` is adapted to it, tests use a fake.
public protocol DoorAPI {
    func getToken() async throws -> String
    func openDoor(token: String, accessPointId: String) async throws
}

/// Gives the current device location, or nil when none can be obtained (no permission, no fix in time).
public protocol LocationProviding {
    func currentLocation() async -> CLLocation?
}

struct APIAdapter: DoorAPI {
    let api: API

    func getToken() async throws -> String {
        try await api.getToken()
    }

    func openDoor(token: String, accessPointId: String) async throws {
        _ = try await api.openDoor(token: token, accessPointId: accessPointId)
    }
}

/// Why a door couldn't be opened before the request was even sent.
public enum DoorError: Error, Equatable, LocalizedError {
    case notConfigured
    case doorNotFound
    case locationUnknown
    case tooFar(name: String, distance: Int, radius: Int)

    public var title: String {
        switch self {
        case .notConfigured: "No credentials"
        case .doorNotFound: "Door not found"
        case .locationUnknown: "Location unknown"
        case .tooFar: "Too far away"
        }
    }

    public var message: String {
        switch self {
        case .notConfigured:
            "Sign in with your CloudDoor account in Settings first."
        case .doorNotFound:
            "Open CloudDoor once to load your doors, then try again."
        case .locationUnknown:
            "CloudDoor can't find your location. Allow location access in Settings and try again."
        case .tooFar(let name, let distance, let radius):
            "\(name) is \(distance)m away. Get within \(radius)m to open it."
        }
    }

    public var errorDescription: String? { message }
}

public final class DoorService {
    private let configuration: Configuration
    private let cache: Cache
    private let locator: LocationProviding
    private let apiFactory: (ConfigurationValues) -> DoorAPI

    public init(
        locator: LocationProviding,
        configuration: Configuration = Configuration(),
        cache: Cache = Cache(),
        apiFactory: ((ConfigurationValues) -> DoorAPI)? = nil
    ) {
        self.locator = locator
        self.configuration = configuration
        self.cache = cache
        self.apiFactory = apiFactory ?? { values in
            APIAdapter(api: API(url: values.hostname, username: values.username, password: values.password))
        }
    }

    /// Opens a door, after checking that the device is within the door's radius.
    ///
    /// Signing in starts while the location is still being found, so the two waits overlap. The door itself is
    /// only opened once every check has passed; if one fails, the sign-in is cancelled and nothing is opened.
    public func open(doorId: String) async throws {
        let values = try requireConfiguration()

        guard let location = cache.getCachedLocations()?.first(where: { $0.id == doorId }),
              !location.geolocations.isEmpty else {
            throw DoorError.doorNotFound
        }

        let api = apiFactory(values)
        async let token = api.getToken()

        guard let current = await locator.currentLocation() else {
            throw DoorError.locationUnknown
        }

        let item = getLocationsWithDistance(locations: [location], distanceToLocation: current)[0]
        guard item.inRadius else {
            throw DoorError.tooFar(
                name: location.name,
                distance: item.distance ?? 0,
                radius: location.geolocations[0].radius)
        }

        try await api.openDoor(token: try await token, accessPointId: doorId)
    }

    private func requireConfiguration() throws -> ConfigurationValues {
        let values = configuration.get()
        guard !values.hostname.isEmpty, !values.username.isEmpty else {
            throw DoorError.notConfigured
        }
        return values
    }
}
