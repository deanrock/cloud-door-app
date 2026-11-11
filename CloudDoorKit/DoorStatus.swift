//
//  DoorStatus.swift
//  CloudDoorKit
//
//  What a widget or control says about a door: its normal look, or the progress / result of opening it.
//

import Foundation

public struct DoorStatus: Equatable {
    public enum Tone: Equatable {
        case idle, working, success, failure
    }

    public let symbol: String
    public let text: String
    public let tone: Tone

    /// The icon for a control: it can't be colored on success, so it shows the opposite (open) door instead.
    public var controlSymbol: String {
        switch tone {
        case .idle: "door.left.hand.closed"
        case .working, .success: "door.left.hand.open"
        case .failure: "xmark.circle.fill"
        }
    }

    /// - Parameters:
    ///   - doorName: Nil when no door is chosen yet, or the chosen door no longer exists.
    ///   - activity: The latest activity for the door; ignored once it is too old to be worth showing.
    public init(doorName: String?, activity: DoorActivity?, now: Date = Date()) {
        guard let doorName else {
            symbol = "door.left.hand.closed"
            text = "Choose Door"
            tone = .idle
            return
        }

        guard let activity, activity.isCurrent(at: now) else {
            symbol = "door.left.hand.closed"
            text = doorName
            tone = .idle
            return
        }

        switch activity.phase {
        case .opening:
            symbol = "door.left.hand.open"
            text = "Opening…"
            tone = .working
        case .opened:
            symbol = "checkmark.circle.fill"
            text = "Opened"
            tone = .success
        case .failed:
            symbol = "xmark.circle.fill"
            text = activity.message ?? "Couldn't open"
            tone = .failure
        }
    }
}
