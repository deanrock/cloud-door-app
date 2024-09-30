//
//  Utils.swift
//  CloudDoor
//
//  Created by dean on 1. 10. 24.
//

import CoreLocation

func getLocationsWithDistance(locations: [Location], distanceToLocation: CLLocation?) -> [LocationWithDistance] {
    return locations.map { location in
        if let distanceToLocation = distanceToLocation {
            let distance = Int(distanceToLocation.distance(from: CLLocation(latitude: location.geolocations[0].latitude, longitude: location.geolocations[0].longitude)))
            
            return LocationWithDistance(location: location, distance: Int(distance))
        }
        
        return LocationWithDistance(location: location, distance: nil)
    }
}

func optionalDistanceToString(distance: Int?) -> String {
    if let distance = distance {
        if distance > 1000 {
            return " (\(distance/1000)km)"
        }

        return " (\(distance)m)"
    }
    
    return " (no distance)"
}
