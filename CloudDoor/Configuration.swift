//
//  Configuration.swift
//  CloudDoor
//
//  Created by dean on 30. 9. 24.
//

import KeychainSwift

class ConfigurationValues {
    var username: String
    var password: String
    var hostname: String
    
    init(username: String, password: String, hostname: String) {
        self.username = username
        self.password = password
        self.hostname = hostname
    }
}

class Configuration {
    let keychain = KeychainSwift()
    
    init() {
        keychain.synchronizable = true
    }
    
    func get() -> ConfigurationValues {
        let username = keychain.get("username") ?? ""
        let password = keychain.get("password") ?? ""
        let hostname = keychain.get("hostname") ?? ""

        return ConfigurationValues(username: username, password: password, hostname: hostname)
    }
    
    func set(username: String, password: String, hostname: String) {
        keychain.set(username, forKey: "username", withAccess: .accessibleWhenUnlocked)
        keychain.set(password, forKey: "password", withAccess: .accessibleWhenUnlocked)
        keychain.set(hostname, forKey: "hostname", withAccess: .accessibleWhenUnlocked)
    }
}
