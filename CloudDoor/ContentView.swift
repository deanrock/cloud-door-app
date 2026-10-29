//
//  ContentView.swift
//  CloudDoor
//
//  Created by dean on 29. 9. 24.
//

import AppIntents
import CloudDoorKit
import CoreLocation
import os
import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var errorInfo: ErrorInfo?
    /// The latest open-door error per door: its short text shows in the row, and its details stay available.
    @State private var rowErrors: [String: ErrorInfo] = [:]
    /// The most recent error, offered under a long-press on any row until a door opens successfully.
    @State private var lastError: ErrorInfo?
    /// The row being pressed, which shows a gradient as immediate feedback.
    @State private var pressedId: String?
    /// Why the list couldn't be refreshed, shown at the top of the list.
    @State private var loadError: ErrorInfo?
    /// Set once the first attempt to load doors has finished, so an empty list isn't mistaken for "still loading".
    @State private var hasLoaded = false
    /// Whether an account is saved. Kept as state, not read from the keychain while drawing, because nothing
    /// would redraw the screen after someone signs in on the other tab.
    @State private var isSignedIn: Bool
    /// Counts account changes, so that the answer to a request made for the previous account is thrown away.
    @State private var accountGeneration = 0
    @State var locations: [LocationWithDistance]
    @State private var openingId: String?
    @State private var openedId: String?
    @State private var failedId: String?
    @State private var errorTrigger = 0
    
    /// Owned by the view so switching tabs doesn't start over without a location.
    @StateObject private var locationManager = LocationManager()
    
    let configuration = Configuration()
    let cache = Cache()
    
    /// Shows the Settings tab; used by the empty states that send the person there.
    let showSettings: () -> Void
    /// True while the Doors tab is the one on screen.
    let isActive: Bool
    /// Changes whenever the account is changed in Settings.
    let accountVersion: Int

    /// Technical details of every error are also written here, so they can be read from a device without a debugger.
    private static let log = Logger(subsystem: "com.dejanlevec.dooropener", category: "ui")

    init(isActive: Bool = true, accountVersion: Int = 0, showSettings: @escaping () -> Void = {}) {
        self.isActive = isActive
        self.accountVersion = accountVersion
        self.showSettings = showSettings
        self._isSignedIn = State(initialValue: !Configuration().get().hostname.isEmpty)
        // When starting the application, load locations from cache, to avoid waiting for the initial response from the API.
        let cachedLocations = cache.getCachedLocations() ?? []
        self.locations = getLocationsWithDistance(locations: cachedLocations, distanceToLocation: nil)
    }

    /// Reads which account is saved, and loads its doors. Called when the account changes and when the tab comes back.
    func syncAccount(accountChanged: Bool) {
        if accountChanged {
            accountGeneration += 1
            dropDoors()
            hasLoaded = false
            loadError = nil
        }

        isSignedIn = !configuration.get().hostname.isEmpty
        Self.log.info("Account sync: changed \(accountChanged, privacy: .public), signed in \(isSignedIn, privacy: .public), generation \(accountGeneration, privacy: .public)")
        guard isSignedIn else { return }
        Task { await refresh() }
    }

    func refresh() async {
        let generation = accountGeneration
        defer {
            if generation == accountGeneration { hasLoaded = true }
        }
        do {
            let api = API.initFromConfiguration(configuration: self.configuration)
            let token = try await api.getToken()
            let locations = try await api.getLocations(token: token)

            // The account was changed while this request was running: its answer belongs to the previous account.
            guard generation == accountGeneration else { return }

            cache.setCachedLocations(locations: locations)
            loadError = nil

            self.locations = getLocationsWithDistance(locations: locations, distanceToLocation: locationManager.location)

            // Siri's phrases include the door names, so let the system learn the new ones.
            CloudDoorShortcuts.updateAppShortcutParameters()

            // Widgets and controls read the same door list, so they should show the new one right away.
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadAllControls()

            // The Apple Watch shows the same doors.
            PhoneConnection.shared.send()
        } catch {
            // A cancelled request (for example a pull-to-refresh that was interrupted) isn't worth an error sheet.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            // If the server no longer accepts the account, the doors that were saved belong to someone who can't sign in.
            if (error as? ApiError)?.isAccountRejection == true {
                dropDoors()
            }
            let info = ErrorInfo(error: error, title: "Couldn't load doors")
            report(info)
            loadError = info
        }
    }

    /// Forgets the saved doors, here, for the widgets and controls, and on the Apple Watch.
    func dropDoors() {
        locations = []
        cache.clearCachedLocations()
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        // Also tells the watch about a new account or a sign-out; the account is saved before this runs.
        PhoneConnection.shared.send()
    }

    /// Logs the error with its technical details (readable without a debugger) and gives haptic feedback.
    func report(_ info: ErrorInfo) {
        errorTrigger += 1
        lastError = info
        Self.log.error("\(info.title, privacy: .public): \(info.message, privacy: .public) [\(info.details ?? "no details", privacy: .public)]")
    }

    /// A problem with opening one door. Passing problems show in that door's row; problems that need
    /// a decision (like allowing location) get a sheet, and the row still flashes red.
    func present(_ info: ErrorInfo, forDoor id: String) {
        report(info)
        Task { await flashFailure(id, seconds: 4) }

        if info.isTransient {
            rowErrors[id] = info
        } else {
            errorInfo = info
        }
    }

    /// Shows the failed state on a row for a moment, then clears it (unless a newer failure replaced it).
    func flashFailure(_ id: String, seconds: Double = 2) async {
        withAnimation(.spring) { failedId = id }
        try? await Task.sleep(for: .seconds(seconds))
        if failedId == id {
            withAnimation(.spring) { failedId = nil }
        }
    }

    func open(_ item: LocationWithDistance) {
        // Ignore taps while another request is in flight.
        guard openingId == nil else { return }

        guard item.inRadius else {
            let reason: DoorError = item.distance.map {
                .tooFar(name: item.location.name, distance: $0, radius: item.location.geolocations[0].radius)
            } ?? .locationUnknown
            present(ErrorInfo(error: reason, title: "Couldn't open '\(item.location.name)'"), forDoor: item.id)
            return
        }

        withAnimation(.spring) {
            openingId = item.id
            failedId = nil
            rowErrors[item.id] = nil
        }
        // Use the location the list was just checked against, rather than asking again.
        let currentLocation = locationManager.location
        Task {
            let started = ContinuousClock.now
            // Keep the "opening" state on screen for a minimum time, so quick responses (or quick errors) are still visible.
            func waitMinimumDuration() async {
                let elapsed = ContinuousClock.now - started
                if elapsed < .milliseconds(900) {
                    try? await Task.sleep(for: .milliseconds(900) - elapsed)
                }
            }

            do {
                let service = DoorService(locator: CurrentLocationProvider(location: currentLocation))
                try await service.open(doorId: item.id)
                await waitMinimumDuration()

                withAnimation(.spring) {
                    openedId = item.id
                    openingId = nil
                }
                lastError = nil

                // Reset the row after a moment, unless another door was opened meanwhile.
                try? await Task.sleep(for: .seconds(2))
                if openedId == item.id {
                    withAnimation(.spring) { openedId = nil }
                }
            } catch {
                await waitMinimumDuration()

                withAnimation(.spring) { openingId = nil }
                present(ErrorInfo(error: error, title: "Couldn't open '\(item.location.name)'"), forDoor: item.id)
            }
        }
    }

    @ViewBuilder
    func rowContent(_ item: LocationWithDistance) -> some View {
        let isOpening = openingId == item.id
        let isOpened = openedId == item.id
        let isFailed = failedId == item.id
        let rowError = isFailed ? rowErrors[item.id] : nil

        HStack(spacing: 12) {
            Image(systemName: isOpened ? "door.left.hand.open" : "door.left.hand.closed")
                .font(.title2)
                .foregroundStyle(isFailed ? Color.red : (item.inRadius ? Color.accentColor : Color.secondary))
                .frame(width: 32)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.location.name)
                if let rowError {
                    Text(rowError.shortMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    Text(optionalDistanceToString(distance: item.distance)
                        .trimmingCharacters(in: CharacterSet(charactersIn: " ()")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Fixed-size status slot, so state changes animate in place (insert/remove transitions are unreliable inside a List row).
            ZStack {
                ProgressView()
                    .opacity(isOpening ? 1 : 0)
                    .scaleEffect(isOpening ? 1 : 0.4)
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .opacity(isOpened ? 1 : 0)
                    .scaleEffect(isOpened ? 1 : 0.4)
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                    .opacity(isFailed ? 1 : 0)
                    .scaleEffect(isFailed ? 1 : 0.4)
            }
            .frame(width: 28, height: 28)
        }
        .contentShape(Rectangle())
        .scaleEffect(isOpening ? 0.97 : 1)
        .animation(.spring(duration: 0.4, bounce: 0.35), value: openingId)
        .animation(.spring(duration: 0.4, bounce: 0.35), value: openedId)
        .animation(.spring(duration: 0.4, bounce: 0.35), value: failedId)
    }

    func row(_ item: LocationWithDistance) -> some View {
        let status: RowStatus = openingId == item.id ? .opening
            : openedId == item.id ? .opened
            : failedId == item.id ? .failed
            : .idle

        return Button { open(item) } label: { rowContent(item) }
            .buttonStyle(PressableRowStyle { isPressed in
                if isPressed {
                    pressedId = item.id
                } else if pressedId == item.id {
                    pressedId = nil
                }
            })
            .listRowBackground(RowStatusBackground(status: status, isPressed: pressedId == item.id))
            .contextMenu {
                // The row only has room for a few words, so the full story of the latest error is one long-press away.
                if let error = lastError {
                    Button {
                        errorInfo = error
                    } label: {
                        Label("Error Details", systemImage: "info.circle")
                    }
                }
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isSignedIn {
                    ContentUnavailableView {
                        Label("Sign in to see your doors", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text("Add your CloudDoor email, password and server in Settings.")
                    } actions: {
                        Button("Go to Settings", action: showSettings)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Group {
                        if hasLoaded && locations.isEmpty {
                            ContentUnavailableView {
                                Label("No doors", systemImage: "door.left.hand.closed")
                            } description: {
                                Text(loadError?.message ?? "Your account has no doors yet. Check your account in Settings.")
                            } actions: {
                                Button("Try Again") { Task { await refresh() } }
                                    .buttonStyle(.borderedProminent)
                                Button("Go to Settings", action: showSettings)
                            }
                        } else if !hasLoaded && locations.isEmpty {
                            // The first load is still running; without this the screen would look empty.
                            ProgressView("Loading doors…")
                        } else {
                            List {
                                if let loadError {
                                    Section {
                                        Button {
                                            errorInfo = loadError
                                        } label: {
                                            Label {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(loadError.title)
                                                        .font(.subheadline.bold())
                                                    Text(loadError.shortMessage)
                                                        .font(.caption)
                                                        .foregroundStyle(.red)
                                                }
                                            } icon: {
                                                Image(systemName: loadError.symbol)
                                                    .foregroundStyle(.red)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("loadError")
                                    }
                                }
                                Section(footer: locationFooter) {
                                    ForEach(locations) { item in
                                        row(item)
                                    }
                                }
                            }
                        }
                    }
                    .onReceive(locationManager.$location) { value in
                        let rawLocations = self.locations.map { $0.location }
                        self.locations = getLocationsWithDistance(locations: rawLocations, distanceToLocation: value)
                    }
                    .sensoryFeedback(.success, trigger: openedId) { _, new in new != nil }
                    .sensoryFeedback(.error, trigger: errorTrigger)
                    .refreshable { await refresh() }
                }
            }
            .navigationTitle("Doors")
            .onAppear {
                syncAccount(accountChanged: false)
            }
            // The account was changed in Settings: drop the previous account's doors and load the new ones.
            // The app passes the change down, so this does not depend on this tab being on screen when it happens.
            .onChange(of: accountVersion) {
                syncAccount(accountChanged: true)
            }
            // Coming back to this tab: check again which account is saved, and refresh the doors.
            .onChange(of: isActive) { _, active in
                if active { syncAccount(accountChanged: false) }
            }
            .sheet(item: $errorInfo) { info in
                ErrorSheet(info: info)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    var locationFooter: some View {
        if let address = locationManager.address {
            Text("Location: \(address)")
        } else {
            Text("Location unavailable")
        }
    }
}

struct ErrorInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    /// A few words for the row.
    let shortMessage: String
    let symbol: String
    /// Technical facts for debugging: shown under "Details" and written to the log.
    let details: String?
    let action: ErrorDescription.Action?

    /// Problems that need a decision (like allowing location) get a sheet; the rest only a short banner.
    var isTransient: Bool { action == nil }

    init(error: Error, title: String) {
        let description = ErrorDescription(error: error)
        // Door problems come with their own title ("Too far away"); for everything else the caller says what failed.
        self.title = (error as? DoorError)?.title ?? title
        self.message = description.message
        self.shortMessage = description.shortMessage
        self.symbol = description.symbol
        self.details = description.details
        self.action = description.action
    }
}

/// A "Show details" button that opens the technical facts of an error in a popup.
/// A popup does not change the layout of the screen below it, unlike a panel that expands in place.
struct DetailsView: View {
    let info: ErrorInfo
    /// Where the button sits: in the middle of a sheet, or flush with the text above it in a form.
    var alignment: Alignment = .center
    @State private var showPopup = false

    var body: some View {
        Button {
            showPopup = true
        } label: {
            Label("Show details", systemImage: "info.circle")
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: alignment)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("showDetails")
        .sheet(isPresented: $showPopup) {
            DetailsPopup(info: info)
        }
    }
}

/// The error with all its technical facts, which can be selected or copied.
struct DetailsPopup: View {
    let info: ErrorInfo
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(info.title, systemImage: info.symbol)
                        .font(.headline)
                        .foregroundStyle(.red)

                    Text(info.message)
                        .font(.callout)

                    if let details = info.details {
                        Text(details)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
            }
            .navigationTitle("Error details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = [info.title, info.message, info.details]
                            .compactMap { $0 }
                            .joined(separator: "\n\n")
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct ErrorSheet: View {
    let info: ErrorInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var appeared = false

    private var okButton: some View {
        Button {
            dismiss()
        } label: {
            Text("OK")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: info.symbol)
                        .font(.system(size: 44))
                        .foregroundStyle(.red)
                        .symbolEffect(.bounce, value: appeared)
                        .padding(.top, 24)

                    Text(info.title)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)

                    Text(info.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if info.details != nil {
                        DetailsView(info: info)
                    }
                }
            }

            if info.action == .openLocationSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }

            // With another action on offer, "OK" is the quieter choice.
            if info.action == nil {
                okButton.buttonStyle(.borderedProminent)
            } else {
                okButton.buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .onAppear { appeared = true }
    }
}

/// Hands the location the app already has to `DoorService`.
struct CurrentLocationProvider: LocationProviding {
    let location: CLLocation?

    func currentLocation() async -> CLLocation? { location }
}

enum RowStatus {
    case idle, opening, opened, failed
}

/// Full-width row background: pulses with the accent color while opening, then settles to green (success) or red (failure).
struct RowStatusBackground: View {
    let status: RowStatus
    /// True while the row is being pressed: a gradient sweeps in from the left as immediate feedback.
    var isPressed = false
    @State private var bright = false

    var body: some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)

            Color.accentColor
                .opacity(status == .opening ? (bright ? 0.35 : 0.05) : 0)
            Color.green
                .opacity(status == .opened ? 0.25 : 0)
            Color.red
                .opacity(status == .failed ? 0.18 : 0)

            LinearGradient(
                colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.08)],
                startPoint: .leading,
                endPoint: .trailing)
                .opacity(isPressed ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.35), value: status)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .onChange(of: status, initial: true) { _, newStatus in
            // Restart the pulse each time the row enters the opening state.
            bright = false
            if newStatus == .opening {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { bright = true }
            }
        }
    }
}

/// Immediate press feedback (a light dim and shrink), independent of the network request.
/// The row background shows the gradient, so the style reports when the button is pressed.
struct PressableRowStyle: ButtonStyle {
    var onPressChange: (Bool) -> Void = { _ in }

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressChange(isPressed)
            }
    }
}

#Preview {
    ContentView()
}
