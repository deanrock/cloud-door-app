//
//  WatchDoorsView.swift
//  CloudDoorWatch
//
//  The doors on the wrist: tap one to open it.
//

import CloudDoorKit
import SwiftUI

struct WatchDoorsView: View {
    let account: WatchAccountModel
    @State private var model = DoorOpenModel(opener: DoorService(locator: DoorLocator()))

    private var anyOpened: Bool { model.states.values.contains(.opened) }
    private var anyFailed: Bool {
        model.states.values.contains { if case .failed = $0 { true } else { false } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !account.isSignedIn {
                    ContentUnavailableView {
                        Label("Not signed in", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text("Sign in with the CloudDoor app on your iPhone.")
                    }
                } else if account.doors.isEmpty {
                    ContentUnavailableView {
                        Label("No doors", systemImage: "door.left.hand.closed")
                    } description: {
                        Text("Open CloudDoor on your iPhone to load your doors.")
                    }
                } else {
                    List(account.doors, id: \.id) { door in
                        DoorRow(name: door.name, state: model.state(for: door.id)) {
                            Task { await model.open(doorId: door.id) }
                        }
                    }
                }
            }
            .navigationTitle("Doors")
        }
        .sensoryFeedback(.success, trigger: anyOpened) { old, new in new && !old }
        .sensoryFeedback(.error, trigger: anyFailed) { old, new in new && !old }
    }
}

struct DoorRow: View {
    let name: String
    let state: DoorOpenModel.RowState
    let action: () -> Void

    private var symbol: String {
        switch state {
        case .idle: "door.left.hand.closed"
        case .opening: "door.left.hand.open"
        case .opened: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .idle, .opening: .accentColor
        case .opened: .green
        case .failed: .red
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .lineLimit(2)
                    switch state {
                    case .opening:
                        Text("Opening…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    case .opened:
                        Text("Opened")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    case .failed(let reason):
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    case .idle:
                        EmptyView()
                    }
                }

                Spacer(minLength: 0)

                if state == .opening {
                    ProgressView()
                }
            }
        }
        .listRowBackground(rowBackground)
        .accessibilityIdentifier("doorRow")
        .animation(.spring(duration: 0.3), value: state)
    }

    @ViewBuilder
    private var rowBackground: some View {
        switch state {
        case .opened: Color.green.opacity(0.25)
        case .failed: Color.red.opacity(0.25)
        case .opening: Color.accentColor.opacity(0.25)
        case .idle: Color.clear.opacity(0)
        }
    }
}
