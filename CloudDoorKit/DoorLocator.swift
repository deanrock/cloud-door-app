//
//  DoorLocator.swift
//  CloudDoorKit
//
//  The real location source for intents, controls, widgets and the watch: asks Core Location for a fresh fix,
//  and falls back to the system's last-known location (see `LocationResolver` for the trust rules).
//

import CoreLocation
import Foundation

public struct DoorLocator: LocationProviding {
    private let resolver: LocationResolver

    public init(policy: LocationResolver.Policy = LocationResolver.Policy()) {
        resolver = LocationResolver(
            policy: policy,
            fresh: { timeout in await DoorLocator.freshFix(timeout: timeout, policy: policy) },
            lastKnown: { CLLocationManager().location })
    }

    public func currentLocation() async -> CLLocation? {
        await resolver.currentLocation()
    }

    /// Waits up to `timeout` for an accurate, recent fix. Returns nil on timeout, and at once when location
    /// can't be delivered at all (no permission, or the process isn't allowed to use location right now).
    static func freshFix(timeout: Duration, policy: LocationResolver.Policy) async -> CLLocation? {
        await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                // The session declares that we need when-in-use access, and must stay alive while we listen.
                let session = CLServiceSession(authorization: .whenInUse)
                defer { session.invalidate() }

                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        // Waiting longer won't help: report "no fix" right away instead of using up the timeout.
                        if update.authorizationDenied || update.insufficientlyInUse { return nil }

                        guard let location = update.location,
                              location.horizontalAccuracy >= 0,
                              location.horizontalAccuracy <= policy.maxAccuracy,
                              Date().timeIntervalSince(location.timestamp) <= policy.maxAge else { continue }
                        return location
                    }
                } catch {
                    // Treated like "no fix": the resolver falls back to the last-known location.
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            // Whichever finishes first wins; the other is cancelled.
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
