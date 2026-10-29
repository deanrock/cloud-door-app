//
//  LocationResolver.swift
//  CloudDoorKit
//
//  Decides which location to trust, fastest first: a very recent one is used at once, otherwise a fresh fix is
//  awaited briefly, and as a last resort an older but still reasonable one is accepted.
//

import CoreLocation
import Foundation

public struct LocationResolver: LocationProviding {
    public struct Policy {
        /// A last-known location this young (seconds) is used at once, without waiting for a new fix.
        public var recentAge: TimeInterval
        /// Otherwise, a last-known location up to this old (seconds) is accepted when no fresh fix arrives.
        public var maxAge: TimeInterval
        /// A last-known location less accurate than this (meters) is not trusted.
        public var maxAccuracy: CLLocationAccuracy
        /// How long to wait for a fresh fix. Kept to one second so that a failure is shown quickly;
        /// the next try then finds the location the system has meanwhile obtained.
        public var timeout: Duration

        public init(
            recentAge: TimeInterval = 30,
            maxAge: TimeInterval = 120,
            maxAccuracy: CLLocationAccuracy = 100,
            timeout: Duration = .seconds(1)
        ) {
            self.recentAge = recentAge
            self.maxAge = maxAge
            self.maxAccuracy = maxAccuracy
            self.timeout = timeout
        }
    }

    private let policy: Policy
    private let fresh: (Duration) async -> CLLocation?
    private let lastKnown: () -> CLLocation?
    private let now: () -> Date

    /// - Parameters:
    ///   - fresh: Waits up to the given duration for a new fix and returns nil if none arrives.
    ///   - lastKnown: The system's most recent location, if any.
    public init(
        policy: Policy = Policy(),
        fresh: @escaping (Duration) async -> CLLocation?,
        lastKnown: @escaping () -> CLLocation?,
        now: @escaping () -> Date = Date.init
    ) {
        self.policy = policy
        self.fresh = fresh
        self.lastKnown = lastKnown
        self.now = now
    }

    public func currentLocation() async -> CLLocation? {
        // Fastest: the system already knows where we are, a moment ago.
        if let location = lastKnown(), isAcceptable(location, maxAge: policy.recentAge) {
            return location
        }

        // A negative accuracy marks an invalid location.
        if let location = await fresh(policy.timeout), location.horizontalAccuracy >= 0 {
            return location
        }

        if let location = lastKnown(), isAcceptable(location, maxAge: policy.maxAge) {
            return location
        }

        return nil
    }

    private func isAcceptable(_ location: CLLocation, maxAge: TimeInterval) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= policy.maxAccuracy
            && now().timeIntervalSince(location.timestamp) <= maxAge
    }
}
