//
//  Configuration.swift
//  CloudDoor
//
//  Created by dean on 30. 9. 24.
//

import Foundation

public class ConfigurationValues {
    public var username: String
    public var password: String
    public var hostname: String
    
    public init(username: String, password: String, hostname: String) {
        self.username = username
        self.password = password
        self.hostname = hostname
    }
}

public class Configuration {
    static let keys = ["username", "password", "hostname"]

    private let store: SecretStore
    
    public init(store: SecretStore? = nil) {
        self.store = store ?? KeychainSecretStore()
    }
    
    public func get() -> ConfigurationValues {
        let username = store.get("username") ?? ""
        let password = store.get("password") ?? ""
        let hostname = store.get("hostname") ?? ""

        return ConfigurationValues(username: username, password: password, hostname: hostname)
    }
    
    /// Signs out: removes the saved account.
    public func clear() {
        for key in Self.keys {
            store.remove(key)
        }
    }

    /// Throws `SecretStoreError` if any value couldn't be saved.
    public func set(username: String, password: String, hostname: String) throws {
        try store.set(username, forKey: "username")
        try store.set(password, forKey: "password")
        try store.set(hostname, forKey: "hostname")
    }
}
