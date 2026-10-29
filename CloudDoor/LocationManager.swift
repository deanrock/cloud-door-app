//
//  LocationManager.swift
//  CloudDoor
//
//  Created by dean on 30. 9. 24.
//

import CoreLocation
import MapKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    @Published var location: CLLocation?
    /// The street address and city for the current location, once it has been looked up.
    @Published var address: String?
    private var geocodingTask: Task<Void, Never>?
    /// Where and when the address was last looked up. MapKit refuses more than 50 lookups a minute,
    /// and an address doesn't change over a few meters.
    private var lastGeocoded: (location: CLLocation, date: Date)?
    private let minimumDistance: CLLocationDistance = 50
    private let minimumInterval: TimeInterval = 15
    
    override init() {
        super.init()
        manager.delegate = self
        manager.startUpdatingLocation()
        manager.requestWhenInUseAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations[0]
        self.location = location
        
        self.reverseGeocode()
    }
    
    private func reverseGeocode() {
        guard let location = self.location else { return }

        // Wait out the interval, and then look up again only after moving, or if the last try found nothing.
        if let last = lastGeocoded,
           Date().timeIntervalSince(last.date) < minimumInterval
            || (address != nil && location.distance(from: last.location) < minimumDistance) {
            return
        }
        guard let request = MKReverseGeocodingRequest(location: location) else { return }
        lastGeocoded = (location, Date())

        // Only the newest lookup matters.
        geocodingTask?.cancel()
        geocodingTask = Task { @MainActor in
            let item = try? await request.mapItems.first
            guard !Task.isCancelled else { return }
            self.address = item?.address?.shortAddress ?? item?.address?.fullAddress
        }
    }
}
