//
//  DoorOpenModel.swift
//  CloudDoorKit
//
//  What each door's row shows while a door is being opened: opening, opened, or why it failed. Used by the watch app.
//

import Foundation
import Observation
import os

@MainActor
@Observable
public final class DoorOpenModel {
    public enum RowState: Equatable, Sendable {
        case idle
        case opening
        case opened
        /// A few words saying why, such as "Too far: 120m away, limit 80m".
        case failed(String)
    }

    public private(set) var states: [String: RowState] = [:]

    private let opener: DoorOpening
    private let openedDisplay: Duration
    private let failedDisplay: Duration
    /// Counts the attempts per door, so that a result that is being shown isn't wiped by an older attempt's timer.
    private var attempts: [String: Int] = [:]

    private static let log = Logger(subsystem: "com.dejanlevec.dooropener", category: "watch")

    public init(opener: DoorOpening, openedDisplay: Duration = .seconds(2), failedDisplay: Duration = .seconds(5)) {
        self.opener = opener
        self.openedDisplay = openedDisplay
        self.failedDisplay = failedDisplay
    }

    public func state(for doorId: String) -> RowState {
        states[doorId] ?? .idle
    }

    /// True while any door is being opened; further taps are ignored until it finishes.
    public var isBusy: Bool {
        states.values.contains(.opening)
    }

    /// Opens the door and keeps its row's state up to date. Returns when the result has been shown.
    public func open(doorId: String) async {
        guard !isBusy else { return }

        let attempt = (attempts[doorId] ?? 0) + 1
        attempts[doorId] = attempt
        states[doorId] = .opening

        do {
            try await opener.open(doorId: doorId)
            states[doorId] = .opened
            await showResult(for: doorId, attempt: attempt, duration: openedDisplay)
        } catch {
            if error is CancellationError {
                states[doorId] = .idle
                return
            }

            let description = ErrorDescription(error: error)
            Self.log.error("Opening failed: \(description.shortMessage, privacy: .public) [\(description.details ?? "no details", privacy: .public)]")
            states[doorId] = .failed(description.shortMessage)
            await showResult(for: doorId, attempt: attempt, duration: failedDisplay)
        }
    }

    private func showResult(for doorId: String, attempt: Int, duration: Duration) async {
        try? await Task.sleep(for: duration)
        // A newer attempt on this door owns the row now.
        guard attempts[doorId] == attempt else { return }
        states[doorId] = .idle
    }
}
