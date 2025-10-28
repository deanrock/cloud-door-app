//
//  LocationManager.swift
//  CloudDoor
//
//  Created by dean on 30. 9. 24.
//

import CoreLocation
import UserNotifications

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var placemark: CLPlacemark?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.startUpdatingLocation()
        manager.requestAlwaysAuthorization()
        self.monitor()
    }
    
    func monitor() {
        
        Task {
            let center = UNUserNotificationCenter.current()
            
            
            do {
                try await center.requestAuthorization(options: [.alert, .sound, .badge])
                print("yes permissions notif")
            } catch {
                // Handle the error here.
                print("nope permissions notif")
            }
        }
        if CLLocationManager.isMonitoringAvailable(for:
                                                    CLBeaconRegion.self) {
            
            
            // Create the region and begin monitoring it.
            let region = CLBeaconRegion(uuid: UUID.init(uuidString: "c29ce823-e67a-4e71-bff2-abaa32e77a98")!, identifier: "beacon")
            let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
            trigger.region.notifyOnEntry = true
            trigger.region.notifyOnExit = false
            
            let content = UNMutableNotificationContent()
            content.title = "title"
            content.body = "Body"
            content.interruptionLevel = .active

            
            let request = UNNotificationRequest(identifier: "X", content: content, trigger: trigger)

            // Add the request
            let center = UNUserNotificationCenter.current()
            center.add(request, withCompletionHandler: { (error) in
                 if let error = error {
                      print("\n\t ERROR: \(error)")
                 } else {
                      print("\n\t request fulfilled \(request)")
                 }
            })
            
            print("AVAILABLE")
            
            self.manager.startMonitoring(for: region)
            self.manager.startRangingBeacons(in: region)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        if let beacon = beacons.first {
            print("proximity", beacon.proximity)
        } else {
            print("nope?")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations[0]
        self.location = location
        
        self.reverseGeocode()
    }
    
    private func reverseGeocode() {
        if let location = self.location {
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location,
                                            completionHandler: { (placemarks, error) in
                if error == nil {
                    self.placemark = placemarks?[0]
                }
                else {
                    self.placemark = nil
                }
            })
        }
    }
}
