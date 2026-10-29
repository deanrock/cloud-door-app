//
//  CloudDoorWatchApp.swift
//  CloudDoorWatch
//

import CloudDoorKit
import SwiftUI
import WatchConnectivity
import WidgetKit

@main
struct CloudDoorWatchApp: App {
    @State private var account: WatchAccountModel
    private let connection: WatchConnection

    init() {
        let account = WatchAccountModel.atLaunch()
        _account = State(initialValue: account)
        connection = WatchConnection(account: account)
        connection.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchDoorsView(account: account)
        }
    }
}

/// Receives the account and doors from the iPhone.
final class WatchConnection: NSObject, WCSessionDelegate {
    private let account: WatchAccountModel

    init(account: WatchAccountModel) {
        self.account = account
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // A message may have arrived while the app wasn't running; the newest one is kept for us.
        handle(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    private func handle(_ context: [String: Any]) {
        guard let payload = WatchPayload.decode(context: context) else { return }
        let account = account
        Task { @MainActor in
            if account.receive(payload) {
                // The control reads the doors saved above, so have it look again.
                ControlCenter.shared.reloadAllControls()
            }
        }
    }
}
