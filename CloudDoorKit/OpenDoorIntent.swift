//
//  OpenDoorIntent.swift
//  CloudDoorKit
//
//  Opens a door from Shortcuts, Siri, Control Center, the Lock Screen, widgets and the watch.
//

import AppIntents
import Foundation

/// What the intent needs from the door service; `DoorService` is the real one, tests use a fake.
public protocol DoorOpening {
    func open(doorId: String) async throws
}

extension DoorService: DoorOpening {}

public struct OpenDoorIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Door"
    public static let description = IntentDescription("Opens a door, if you are within its radius.")

    /// Opening a door must never happen from a locked, unattended device.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// Runs headless; if no location is available there, it can bring the app forward to get one.
    public static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    public static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$door)")
    }

    @Parameter(title: "Door")
    public var door: DoorEntity

    public init() {}

    public init(door: DoorEntity) {
        self.door = door
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = DoorService(locator: DoorLocator())
        let name = door.name

        do {
            try await Self.run(
                id: door.id,
                using: service,
                recorder: DoorActivityRecorder(),
                canContinueInForeground: systemContext.currentMode.canContinueInForeground,
                continueInForeground: {
                    try await continueInForeground("Open CloudDoor to find your location?", alwaysConfirm: false)
                })
        } catch {
            throw DoorIntentError.wrap(error)
        }

        return .result(dialog: "Opened \(name).")
    }

    /// Opens the door and records each step, so widgets and controls can show "opening", "opened" or what went wrong.
    static func run(
        id: String,
        using opener: DoorOpening,
        recorder: DoorActivityRecorder,
        canContinueInForeground: Bool,
        continueInForeground: () async throws -> Void
    ) async throws {
        recorder.record(.opening, doorId: id)
        do {
            try await openDoor(
                id: id,
                using: opener,
                canContinueInForeground: canContinueInForeground,
                continueInForeground: continueInForeground)
            recorder.record(.opened, doorId: id)
        } catch {
            recorder.record(.failed, doorId: id, message: DoorIntentError.summary(of: error))
            throw error
        }
    }

    /// The opening flow, separated from the system calls so it can be tested.
    ///
    /// If the radius check can't run because there is no location, and the app may come to the foreground,
    /// the app is brought forward once and the door is tried again. That is safe to repeat: the first attempt
    /// stops before anything is sent to the server. Every other failure is thrown as is.
    static func openDoor(
        id: String,
        using opener: DoorOpening,
        canContinueInForeground: Bool,
        continueInForeground: () async throws -> Void
    ) async throws {
        do {
            try await opener.open(doorId: id)
        } catch DoorError.locationUnknown {
            guard canContinueInForeground else { throw DoorError.locationUnknown }
            try await continueInForeground()
            try await opener.open(doorId: id)
        }
    }
}

/// A failure message that Siri and Shortcuts show to the person (they hide plain errors behind a generic message).
public struct DoorIntentFailure: Error, CustomLocalizedStringResourceConvertible {
    public let message: String

    public var localizedStringResource: LocalizedStringResource { "\(message)" }
}

enum DoorIntentError {
    /// A few words for a widget or control, which have little room: what went wrong.
    static func summary(of error: Error) -> String {
        switch error {
        case let doorError as DoorError:
            return doorError.title
        case is CancellationError:
            return "Cancelled"
        case let urlError as URLError where urlError.code == .notConnectedToInternet:
            return "Offline"
        case let urlError as URLError where urlError.code == .timedOut:
            return "Timed out"
        default:
            return "Couldn't open"
        }
    }

    /// Makes errors readable in Siri and Shortcuts. Errors the system uses for flow control (cancellation,
    /// foreground continuation) and errors that already carry a message are passed on unchanged.
    static func wrap(_ error: Error) -> Error {
        switch error {
        case is ApiError:
            return DoorIntentFailure(message: ErrorDescription(error: error).message)
        case let urlError as URLError where urlError.code != .cancelled:
            return DoorIntentFailure(message: ErrorDescription(error: urlError).message)
        default:
            return error
        }
    }
}

extension DoorError: CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConfigured:
            "No credentials. Sign in with your CloudDoor account in the app's Settings first."
        case .doorNotFound:
            "Door not found. Open CloudDoor once to load your doors, then try again."
        case .locationUnknown:
            "CloudDoor can't find your location. Allow location access in Settings and try again."
        case .tooFar(let name, let distance, let radius):
            "Too far away. \(name) is \(distance)m away. Get within \(radius)m to open it."
        }
    }
}
