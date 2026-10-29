//
//  Cache.swift
//  CloudDoor
//
//  Created by dean on 1. 10. 24.
//
import Foundation

// Gracefully store/retrieve data from persistent cache.
public class Cache {
    public static let cachedLocationsKey = "v1-cachedLocations"

    private let defaults: UserDefaults

    /// App Group defaults, so the app, widgets and watch app see the same data.
    static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: SharedIdentifiers.appGroup) ?? .standard
    }
    
    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? Cache.sharedDefaults()
    }
    
    private func retrieve<T: Decodable>(key: String) -> T? {
        if let value = defaults.value(forKey: key) {
            if let value = value as? Data {
                let decoder = JSONDecoder()
             
                do {
                    return try decoder.decode(T.self, from: value)
                } catch {
                    print("Non-critical error: \(error).")
                }
            }
        }
        
        return nil
    }
    
    private func store<T: Encodable>(key: String, obj: T) {
        let encoder = JSONEncoder()

        do {
            let data = try encoder.encode(obj)
            defaults.set(data, forKey: key)
        } catch {
            print("Non-critical error: \(error).")
        }
    }

    public func getCachedLocations() -> [Location]? {
        self.retrieve(key: Cache.cachedLocationsKey)
    }
    
    public func setCachedLocations(locations: [Location]) {
        self.store(key: Cache.cachedLocationsKey, obj: locations)
    }

    public func clearCachedLocations() {
        defaults.removeObject(forKey: Cache.cachedLocationsKey)
    }
}
