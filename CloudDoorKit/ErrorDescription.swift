//
//  ErrorDescription.swift
//  CloudDoorKit
//
//  Turns any error into text for a person (`message`, and a one-line `shortMessage` for tight spaces) plus the
//  technical facts (`details`), so friendly wording never hides what is needed to debug a problem on a real device.
//

import Foundation

public struct ErrorDescription: Equatable {
    /// What the person can do about it, beyond reading the message.
    public enum Action: Equatable {
        case openLocationSettings
    }

    public var message: String
    /// A few words for places with little room, such as a list row.
    public var shortMessage: String
    /// The technical facts: status codes, server replies, system error codes. Shown in a "Details" section and logged.
    public var details: String?
    public var symbol: String
    public var action: Action?

    public init(error: Error) {
        switch error {
        case let doorError as DoorError:
            self.init(doorError: doorError)

        case ApiError.runtimeError(let text):
            // These come from the server (for example "wrong password") or describe a local problem.
            self.init(message: text, short: text, details: "Server message: \(text)", symbol: "exclamationmark.triangle.fill")

        case ApiError.accountRejected(let text):
            // The server answers with a code such as "msgInvalidLogin", which means nothing to a person.
            self.init(
                message: Self.serverMessage(forStatus: 401),
                short: "Account not accepted",
                details: "Server message: \(text)",
                symbol: "person.crop.circle.badge.exclamationmark")

        case ApiError.http(let status, let body):
            self.init(
                message: Self.serverMessage(forStatus: status),
                short: Self.shortServerMessage(forStatus: status),
                details: "HTTP \(status)" + (body.isEmpty ? "" : "\n\(body)"),
                symbol: "exclamationmark.icloud.fill")

        case let urlError as URLError:
            self.init(urlError: urlError)

        case is DecodingError:
            self.init(
                message: "The server replied in a way CloudDoor doesn't understand. Check the server address in Settings.",
                short: "Unexpected reply",
                details: String(describing: error),
                symbol: "exclamationmark.icloud.fill")

        case let keychainError as SecretStoreError:
            self.init(
                message: keychainError.errorDescription ?? "Couldn't save your account.",
                short: "Couldn't save",
                details: "Keychain status \(keychainError.status)",
                symbol: "lock.trianglebadge.exclamationmark.fill")

        default:
            self.init(
                message: error.localizedDescription,
                short: "Something went wrong",
                details: String(describing: error),
                symbol: "exclamationmark.triangle.fill")
        }
    }

    private init(message: String, short: String, details: String?, symbol: String, action: Action? = nil) {
        self.message = message
        self.shortMessage = short
        self.details = details
        self.symbol = symbol
        self.action = action
    }

    private init(doorError: DoorError) {
        switch doorError {
        case .notConfigured:
            self.init(
                message: doorError.message, short: "Not signed in",
                details: "No saved credentials", symbol: "person.crop.circle.badge.exclamationmark")
        case .doorNotFound:
            self.init(
                message: doorError.message, short: "Door not found",
                details: "The door is not in the saved list", symbol: "door.left.hand.closed")
        case .locationUnknown:
            self.init(
                message: doorError.message, short: "Location unavailable",
                details: "No location fix before the time limit, or location access is off or limited",
                symbol: "location.slash.fill",
                action: .openLocationSettings)
        case .tooFar(_, let distance, let radius):
            self.init(
                message: doorError.message, short: "Too far: \(distance)m away, limit \(radius)m",
                details: "Distance \(distance)m, allowed radius \(radius)m", symbol: "location.slash.fill")
        }
    }

    private init(urlError: URLError) {
        let details = "URLError \(urlError.code.rawValue): \(urlError.localizedDescription)"
        switch urlError.code {
        case .notConnectedToInternet:
            self.init(
                message: "You appear to be offline. Check your internet connection and try again.",
                short: "Offline", details: details, symbol: "wifi.slash")
        case .timedOut:
            self.init(
                message: "The server took too long to respond. Please try again.",
                short: "Timed out", details: details, symbol: "wifi.exclamationmark")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            self.init(
                message: "Can't reach the server. Check the server address in Settings and your connection.",
                short: "Can't reach the server", details: details, symbol: "wifi.exclamationmark")
        default:
            self.init(
                message: urlError.localizedDescription,
                short: "Network error", details: details, symbol: "wifi.exclamationmark")
        }
    }

    private static func serverMessage(forStatus status: Int) -> String {
        switch status {
        case 401, 403:
            "The server didn't accept your account. Check your email and password in Settings."
        case 404:
            "The server doesn't know this address (error 404). Check the server address in Settings."
        case 500...599:
            "The server had a problem (error \(status)). Try again in a moment."
        default:
            "The server answered with an unexpected error (\(status))."
        }
    }

    private static func shortServerMessage(forStatus status: Int) -> String {
        switch status {
        case 401, 403: "Account not accepted"
        case 404: "Server address not found"
        case 500...599: "Server error \(status)"
        default: "Error \(status)"
        }
    }
}
