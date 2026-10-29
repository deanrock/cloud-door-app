//
//  DoorActivity.swift
//  CloudDoorKit
//
//  What happened the last time a door was opened from a widget or control. The intent writes it,
//  and widgets and controls show it, since they have no other way to tell the person.
//

import Foundation
import WidgetKit

public struct DoorActivity: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case opening, opened, failed
    }

    public var doorId: String
    public var phase: Phase
    /// Short text for the person, set when the phase is `failed` (for example "Too far away").
    public var message: String?
    public var date: Date

    public init(doorId: String, phase: Phase, message: String? = nil, date: Date) {
        self.doorId = doorId
        self.phase = phase
        self.message = message
        self.date = date
    }

    /// How long the phase is worth showing. "Opening" has a limit too, in case the run was killed before it finished.
    var lifetime: TimeInterval {
        switch phase {
        case .opening: 30
        case .opened: 3
        case .failed: 4
        }
    }

    /// When the widget should go back to its normal look.
    public var expiry: Date { date.addingTimeInterval(lifetime) }

    public func isCurrent(at now: Date = Date()) -> Bool {
        now < expiry
    }
}

/// Keeps the latest activity per door in the storage shared with the widgets.
public struct DoorActivityStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? Cache.sharedDefaults()
    }

    private func key(for doorId: String) -> String {
        "v1-doorActivity-\(doorId)"
    }

    public func record(_ activity: DoorActivity) {
        guard let data = try? JSONEncoder().encode(activity) else { return }
        defaults.set(data, forKey: key(for: activity.doorId))
    }

    /// The activity for the door, if it is recent enough to be worth showing.
    public func current(for doorId: String, at now: Date = Date()) -> DoorActivity? {
        guard let data = defaults.data(forKey: key(for: doorId)),
              let activity = try? JSONDecoder().decode(DoorActivity.self, from: data),
              activity.isCurrent(at: now) else { return nil }
        return activity
    }
}

/// Records each step of opening a door and refreshes the widgets and controls so they show it.
struct DoorActivityRecorder {
    private let store: DoorActivityStore
    private let reload: (DoorActivity.Phase) -> Void
    private let scheduleRevert: (TimeInterval) -> Void
    private let now: () -> Date

    init(
        store: DoorActivityStore? = nil,
        reload: @escaping (DoorActivity.Phase) -> Void = { phase in
            WidgetCenter.shared.reloadAllTimelines()
            // A control already shows its own spinner while it runs, and the system refreshes it when it finishes.
            if phase != .opening {
                ControlCenter.shared.reloadAllControls()
            }
        },
        scheduleRevert: @escaping (TimeInterval) -> Void = { delay in
            // Best effort: widgets revert on their own timeline, but a control only changes when it is reloaded.
            // This runs only if the extension is still alive; otherwise the next reload shows the normal look.
            Task {
                try? await Task.sleep(for: .seconds(delay + 0.3))
                WidgetCenter.shared.reloadAllTimelines()
                ControlCenter.shared.reloadAllControls()
            }
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store ?? DoorActivityStore()
        self.reload = reload
        self.scheduleRevert = scheduleRevert
        self.now = now
    }

    func record(_ phase: DoorActivity.Phase, doorId: String, message: String? = nil) {
        let activity = DoorActivity(doorId: doorId, phase: phase, message: message, date: now())
        store.record(activity)
        reload(phase)
        if phase != .opening {
            scheduleRevert(activity.lifetime)
        }
    }
}
