//
//  DoorWidget.swift
//  CloudDoorWidgets
//
//  One widget for one door, on the Home Screen and the Lock Screen: tap to open it.
//

import AppIntents
import CloudDoorKit
import SwiftUI
import WidgetKit

struct DoorEntry: TimelineEntry {
    let date: Date
    /// Nil when no door is chosen yet, or the chosen door no longer exists.
    let door: DoorEntity?
    /// Progress or result of the latest open; nil when there is nothing to show.
    let activity: DoorActivity?
}

struct DoorTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DoorEntry {
        DoorEntry(date: .now, door: DoorEntity(id: "preview", name: "Door"), activity: nil)
    }

    func snapshot(for configuration: SelectDoorWidgetIntent, in context: Context) async -> DoorEntry {
        if context.isPreview, configuration.door == nil {
            return placeholder(in: context)
        }
        return currentEntry(for: configuration)
    }

    func timeline(for configuration: SelectDoorWidgetIntent, in context: Context) async -> Timeline<DoorEntry> {
        let current = currentEntry(for: configuration)
        var entries = [current]

        // Show "opened" or the error for a few seconds, then go back to the normal look.
        if let activity = current.activity {
            entries.append(DoorEntry(date: activity.expiry, door: current.door, activity: nil))
        }

        // The app reloads widgets whenever the doors change; the hourly refresh is only a safety net.
        return Timeline(entries: entries, policy: .after(.now.addingTimeInterval(3600)))
    }

    private func currentEntry(for configuration: SelectDoorWidgetIntent) -> DoorEntry {
        let door = WidgetDoors.resolve(configuration.door, in: WidgetDoors.cachedDoors(), signedIn: WidgetDoors.isSignedIn())
        return DoorEntry(date: .now, door: door, activity: door.flatMap { DoorActivityStore().current(for: $0.id) })
    }
}

extension DoorStatus.Tone {
    /// The color for the Home Screen widget; the Lock Screen draws everything in the system's own style.
    var color: Color {
        switch self {
        case .idle: .primary
        case .working: .accentColor
        case .success: .green
        case .failure: .red
        }
    }
}

struct DoorWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DoorEntry

    private var status: DoorStatus {
        DoorStatus(doorName: entry.door?.name, activity: entry.activity, now: entry.date)
    }

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var content: some View {
        if let door = entry.door {
            switch family {
            case .accessoryCircular:
                button(for: door) {
                    ZStack {
                        AccessoryWidgetBackground()
                        symbol.font(.title2)
                    }
                }
            case .accessoryRectangular:
                button(for: door) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.activity == nil ? "Open" : door.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(status.text)
                                .font(.headline)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        symbol
                    }
                }
            case .accessoryInline:
                // The inline slot can't hold a button, so tapping it opens the app.
                Label(status.text, systemImage: status.symbol)
            default:
                button(for: door) {
                    VStack(spacing: 6) {
                        symbol
                            .font(.system(size: 44))
                            .foregroundStyle(status.tone.color)
                        Text(status.text)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        // While a result is showing, the title is the result, so keep the door's name visible.
                        if entry.activity != nil {
                            Text(door.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else if family == .accessoryInline {
            Label("Choose Door", systemImage: status.symbol)
        } else {
            VStack(spacing: 6) {
                symbol.font(family == .systemSmall ? .system(size: 44) : .title2)
                Text("Edit the widget to choose a door")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var symbol: some View {
        Image(systemName: status.symbol)
            .contentTransition(.symbolEffect(.replace))
    }

    private func button<Label: View>(for door: DoorEntity, @ViewBuilder label: () -> Label) -> some View {
        Button(intent: OpenDoorIntent(door: door), label: label)
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        if family == .systemSmall {
            ZStack {
                Rectangle().fill(.fill.tertiary)
                if status.tone != .idle {
                    status.tone.color.opacity(0.18)
                }
            }
        } else {
            Color.clear
        }
    }
}

struct DoorWidget: Widget {
    static let kind = "com.dejanlevec.dooropener.DoorWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SelectDoorWidgetIntent.self, provider: DoorTimelineProvider()) { entry in
            DoorWidgetView(entry: entry)
        }
        .configurationDisplayName("Open Door")
        .description("Opens the door you choose.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
