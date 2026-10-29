//
//  PhoneConnection.swift
//  CloudDoor
//
//  Keeps the Apple Watch up to date with the saved account and the doors.
//

import CloudDoorKit
import Foundation
import os
import WatchConnectivity

final class PhoneConnection: NSObject, WCSessionDelegate {
    static let shared = PhoneConnection()

    private let log = Logger(subsystem: "com.dejanlevec.dooropener", category: "watch")

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    /// Call once at launch.
    func start() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Sends the account and doors as they are now. The watch applies the newest message whenever it next runs,
    /// so it is safe to call this often. Nothing is sent when no watch with the app is paired.
    func send() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }

        do {
            try session.updateApplicationContext(WatchPayload.current().context())
        } catch {
            log.error("Couldn't send to the watch: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            log.error("Watch session didn't activate: \(String(describing: error), privacy: .public)")
        } else if activationState == .activated {
            send()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Happens when the person switches to another watch; the new one needs activating too.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// The watch app was installed, or the pairing changed: bring the watch up to date.
    func sessionWatchStateDidChange(_ session: WCSession) {
        send()
    }
}
