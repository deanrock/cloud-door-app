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
    
    init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

class Configuration {
    let keychain = KeychainSwift()
    
    func get() -> ConfigurationValues {
        let username = keychain.get("username") ?? ""
        let password = keychain.get("password") ?? ""

        return ConfigurationValues(username: username, password: password)
    }
    
    func set(username: String, password: String) {
        keychain.set(username, forKey: "username", withAccess: .accessibleWhenUnlocked)
        keychain.set(password, forKey: "password", withAccess: .accessibleWhenUnlocked)
    }
}
