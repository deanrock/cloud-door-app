//
//  ContentView.swift
//  CloudDoor
//
//  Created by dean on 29. 9. 24.
//

import CoreLocation
import SwiftUI

struct ContentView: View {
    @State var alertTitle = ""
    @State var alertMessage = ""
    @State var showAlert = false
    @State var locations: [LocationWithDistance]
    
    @ObservedObject var locationManager = LocationManager()
    
    let configuration = Configuration()
    let cache = Cache()
    
    init() {
        // When starting the application, load locations from cache, to avoid waiting for the initial response from the API.
        let cachedLocations = cache.getCachedLocations() ?? []
        self.locations = getLocationsWithDistance(locations: cachedLocations, distanceToLocation: nil)
    }
    
    func refresh() {
        Task {
            do {
                let api = API.initFromConfiguration(configuration: self.configuration)
                let token = try await api.getToken()
                let locations = try await api.getLocations(token: token)
                cache.setCachedLocations(locations: locations)
                
                self.locations = getLocationsWithDistance(locations: locations, distanceToLocation: locationManager.location)
            } catch {
                alertTitle = "Error"
                alertMessage = "\(error)"
                showAlert = true
            }
        }
    }

    var body: some View {
        ZStack {
            VStack {
                Label("Please configure credentials in Settings.", systemImage: "info.circle")
            }
            .opacity(configuration.get().username.isEmpty ? 1 : 0)
            VStack {
                List(locations) { index in
                    HStack {
                        Text("\(index.location.name) \(optionalDistanceToString(distance: index.distance))")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onReceive(locationManager.$location) { value in
                        let rawLocations = self.locations.map { $0.location }
                        self.locations = getLocationsWithDistance(locations: rawLocations, distanceToLocation: value)
                    }
                    .onTapGesture {
                        if index.inRadius {
                            Task {
                                do {
                                    let api = API.initFromConfiguration(configuration: Configuration())
                                    let token = try await api.getToken()
                                    let _ = try await api.openDoor(token: token, accessPointId: index.id)
                                    
                                    alertTitle = "Success"
                                    alertMessage = "Door '\(index.location.name)' opened"
                                    showAlert = true
                                } catch {
                                    alertTitle = "Error"
                                    alertMessage = "\(error)"
                                    showAlert = true
                                }
                            }
                        } else {
                            alertTitle = "Error"
                            
                            if let distance = index.distance {
                                alertMessage = "Door '\(index.location.name)' too far away (\(distance)m > \(index.location.geolocations[0].radius)m)"
                            } else {
                                alertMessage = "Cannot open door, since location of the device is not known. Please check device settings, to ensure application has location permissions."
                            }
                            showAlert = true
                        }
                    }
                }
                if let placemark = locationManager.placemark {
                    Text("Location: \(placemark.subThoroughfare ?? "") \(placemark.thoroughfare ?? ""), \(placemark.locality ?? "")")
                } else {
                    Text("Location: unknown")
                }
            }
            .padding()
            .onAppear {
                if configuration.get().username != "" {
                    refresh()
                }
            }
            .alert(isPresented: $showAlert, content: {
                Alert(title: Text(self.alertTitle), message: Text(self.alertMessage), dismissButton: .default(Text("OK")))
            })
            .opacity(configuration.get().username.isEmpty ? 0 : 1)
        }
    }
}

#Preview {
    ContentView()
}
