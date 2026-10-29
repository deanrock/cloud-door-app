//
//  Storage.swift
//  CloudDoorKit
//
//  Shared storage (keychain + App Group defaults), readable by the app, widgets and the watch app.
//

import Foundation
import KeychainSwift

public enum SharedIdentifiers {
    public static let appGroup = "group.com.dejanlevec.dooropener.shared"
}

/// A failed keychain write, carrying the Security framework status code (for example -34018 is a missing entitlement).
public struct SecretStoreError: Error, LocalizedError {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }

    public var errorDescription: String? {
        "Couldn't save credentials to the keychain (error \(status))."
    }
}

/// Secret storage abstraction, so tests don't need a real keychain.
public protocol SecretStore: AnyObject {
    func get(_ key: String) -> String?
    func set(_ value: String, forKey key: String) throws
    func remove(_ key: String)
}

/// Keychain-backed store. Items are written to the first keychain access group in the entitlements, which is the shared group.
/// `.accessibleAfterFirstUnlock` lets controls and intents read credentials while the device is locked; the intent itself requires authentication.
///
/// Items are saved so that iCloud Keychain syncs them to the person's other devices, such as a new iPhone or an Apple Watch.
/// Reading and deleting cover both synced and device-only items, so accounts saved before syncing was added are still found,
/// and signing out removes the account everywhere.
final class KeychainSecretStore: SecretStore {
    private let syncing: KeychainSwift = {
        let keychain = KeychainSwift()
        keychain.synchronizable = true
        return keychain
    }()
    private let deviceOnly = KeychainSwift()

    func get(_ key: String) -> String? {
        syncing.get(key)
    }

    func remove(_ key: String) {
        syncing.delete(key)
    }

    func set(_ value: String, forKey key: String) throws {
        // KeychainSwift deletes the old item before adding the new one, so keep it to put back if both adds fail.
        let old = syncing.get(key)

        if syncing.set(value, forKey: key, withAccess: .accessibleAfterFirstUnlock) {
            return
        }

        // If the keychain refuses a synced item, keep the account on this device rather than losing it.
        guard deviceOnly.set(value, forKey: key, withAccess: .accessibleAfterFirstUnlock) else {
            let error = SecretStoreError(status: deviceOnly.lastResultCode)
            if let old {
                deviceOnly.set(old, forKey: key, withAccess: .accessibleAfterFirstUnlock)
            }
            throw error
        }
    }
}

/// One-time move of data saved by earlier app versions into the shared stores.
public enum StorageMigration {
    /// Changing this runs the migration again on every device. v2 saves existing accounts again so that they sync.
    static let migratedKey = "v2-sharedStorageMigrated"

    /// Safe to call on every launch: it does nothing after the first fully successful run.
    public static func run(
        secrets: SecretStore? = nil,
        sharedDefaults: UserDefaults? = nil,
        legacyDefaults: UserDefaults = .standard
    ) {
        let secrets = secrets ?? KeychainSecretStore()
        let shared = sharedDefaults ?? Cache.sharedDefaults()

        guard !shared.bool(forKey: migratedKey) else { return }

        // Door cache: copy only if the shared store has nothing yet.
        if shared.data(forKey: Cache.cachedLocationsKey) == nil,
           let legacy = legacyDefaults.data(forKey: Cache.cachedLocationsKey) {
            shared.set(legacy, forKey: Cache.cachedLocationsKey)
        }

        // Credentials: reading finds items in any group the app can access; saving again writes them to the shared group.
        // Keys that don't exist (partially filled legacy store) are skipped.
        var allSucceeded = true
        for key in Configuration.keys {
            if let value = secrets.get(key) {
                do {
                    try secrets.set(value, forKey: key)
                } catch {
                    allSucceeded = false
                }
            }
        }

        // If a save failed, leave the flag unset so the next launch tries again (the old items stay readable meanwhile).
        if allSucceeded {
            shared.set(true, forKey: migratedKey)
        }
    }
}
