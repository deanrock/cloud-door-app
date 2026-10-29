//
//  OpenDoorControl.swift
//  CloudDoorWidgets, CloudDoorWatchWidgets
//
//  The button for Control Center, the Lock Screen and the Action button, on the iPhone and the watch.
//

import AppIntents
import CloudDoorKit
import SwiftUI
import WidgetKit

/// Lets the person choose which door a control or widget opens.
struct SelectDoorControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Select Door"

    @Parameter(title: "Door")
    var door: DoorEntity?

    init() {}
}

struct SelectDoorWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Door"
    static let description = IntentDescription("Choose which door this widget opens.")

    @Parameter(title: "Door")
    var door: DoorEntity?

    init() {}
}

struct OpenDoorControl: ControlWidget {
    static let kind = "com.dejanlevec.dooropener.OpenDoorControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: Provider()) { value in
            ControlWidgetButton(action: value.intent) {
                // While a result is showing, the title is the result ("Opened", "Too far away").
                Label(value.status.text, systemImage: value.status.controlSymbol)
            } actionLabel: { isActive in
                if isActive {
                    Text("Opening…")
                }
            }
            .tint(value.tint)
        }
        .displayName("Open Door")
        .description("Opens a door, if you are within its radius.")
        // A control without a door is useless, so ask which door when it is added.
        .promptsForUserConfiguration()
    }
}

extension OpenDoorControl {
    struct Value {
        /// Nil when no door is chosen yet, or the chosen door no longer exists.
        let door: DoorEntity?
        let activity: DoorActivity?

        var status: DoorStatus { DoorStatus(doorName: door?.name, activity: activity) }

        /// Red on error only; success is shown by the icon changing to an open door.
        var tint: Color? {
            status.tone == .failure ? .red : nil
        }

        var intent: OpenDoorIntent {
            door.map { OpenDoorIntent(door: $0) } ?? OpenDoorIntent()
        }
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: SelectDoorControlIntent) -> Value {
            Value(door: configuration.door ?? DoorEntity(id: "preview", name: "Front door"), activity: nil)
        }

        func currentValue(configuration: SelectDoorControlIntent) async throws -> Value {
            let door = WidgetDoors.resolve(configuration.door, in: WidgetDoors.cachedDoors())
            return Value(door: door, activity: door.flatMap { DoorActivityStore().current(for: $0.id) })
        }
    }
}
