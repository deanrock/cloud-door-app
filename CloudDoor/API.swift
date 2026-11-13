//
//  Token.swift
//  CloudDoor
//
//  Created by dean on 30. 9. 24.
//
import SwiftUI

struct TokenResponse: Decodable {
    var access_token: String
}

struct TokenErrorResponse: Decodable {
    var error: String
    var error_description: String
}

struct Geolocation: Encodable, Decodable {
    var id: String
    var name: String
    var latitude: Float64
    var longitude: Float64
    var radius: Int
}

struct Location: Encodable, Decodable {
    var name: String
    var id: String
    var geolocations: [Geolocation]
}

struct GetUserLocationsResponse: Decodable {
    var result: [Location]
}

struct OpenDoorResponseResultData: Decodable {
    var id: String
}

struct OpenDoorResponseResult: Decodable {
    var data: OpenDoorResponseResultData
}

struct OpenDoorResponse: Decodable {
    var result: OpenDoorResponseResult
}

enum ApiError: Error {
    case runtimeError(String)
}

func urlEncodedParams(params: [String: String]) throws -> String {
    let queryItems = params.map({ (key, value) in
        URLQueryItem(name: key, value: value)
    })
    if var urlComponents = URLComponents(string: "") {
        urlComponents.queryItems = queryItems
        if let query = urlComponents.query {
            return query
        }
    }
    
    throw ApiError.runtimeError("Failed to urlencode parameters")
}

class API {
    let url: String
    let username: String
    let password: String

    init(url: String, username: String, password: String) {
        self.url = url
        self.username = username
        self.password = password
    }
    
    static func initFromConfiguration(configuration: Configuration) -> API {
        let values = configuration.get()
        return API(url: Hostname.hostname, username: values.username, password: values.password)
    }
    
    private func request<T: Decodable>(method: String, path: String, contentType: String?, data: String?, token: String?) async throws -> T {
        let url = URL(string: "\(self.url)\(path)")!
        var request = URLRequest(url: url)
        
        if let contentType = contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpMethod = method
        
        if let data = data {
            request.httpBody = data.data(using: String.Encoding.utf8)
        }
        
        let (returnedData, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 400 {
                let error = try JSONDecoder().decode(TokenErrorResponse.self, from: returnedData)
                throw ApiError.runtimeError(error.error_description)
            }

            if httpResponse.statusCode != 200 {
                throw ApiError.runtimeError("Response failed with '\(httpResponse.statusCode)': \(returnedData)")
            }
        } else {
            throw ApiError.runtimeError("Response failed without status code: \(returnedData)")
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: returnedData)
        } catch {
            print("Unexpected error: \(error).")
            throw error
        }
    }

    func getToken() async throws -> String {
        let data = try urlEncodedParams(params: [
            "client_id": "DoorCloudWebApp",
            "grant_type": "password",
            "username": username,
            "password": password,
        ])
        let response: TokenResponse = try await self.request(method: "POST", path: "/token", contentType: "application/x-www-form-urlencoded", data: data, token: nil)
        return response.access_token
    }
    
    func getLocations(token: String) async throws -> [Location] {
        let response: GetUserLocationsResponse = try await self.request(method: "GET", path: "/api/Location/GetUserLocations", contentType: nil, data: nil, token: token)
        return response.result
    }
    
    func openDoor(token: String, accessPointId: String) async throws -> OpenDoorResponse {
        let data = "accessPointId=\(accessPointId)"
        return try await self.request(method: "POST", path: "/api/Location/OpenDoorOnLocation", contentType: nil, data: data, token: token)
    }
}
