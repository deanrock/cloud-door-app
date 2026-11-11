//
//  Token.swift
//  CloudDoor
//
//  Created by dean on 30. 9. 24.
//
import Foundation

struct TokenResponse: Decodable {
    var access_token: String
}

struct TokenErrorResponse: Decodable {
    var error: String
    var error_description: String
}

public struct Geolocation: Encodable, Decodable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var latitude: Float64
    public var longitude: Float64
    public var radius: Int
}

public struct Location: Encodable, Decodable, Equatable, Sendable {
    public var name: String
    public var id: String
    public var geolocations: [Geolocation]
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

public struct OpenDoorResponse: Decodable {
    var result: OpenDoorResponseResult
}

public enum ApiError: Error {
    case runtimeError(String)
    /// The server refused the email or password; the text is its own explanation.
    case accountRejected(String)
    /// The server answered with an unexpected HTTP status; `body` is a short excerpt of its reply.
    case http(status: Int, body: String)

    /// True when the server explicitly refused the account, as opposed to being unreachable or broken.
    public var isAccountRejection: Bool {
        switch self {
        case .accountRejected: true
        case .http(let status, _): status == 401 || status == 403
        case .runtimeError: false
        }
    }

    /// The start of a reply as text, so that errors show what the server said.
    static func excerpt(of data: Data) -> String {
        String(decoding: data.prefix(500), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
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

public class API {
    let url: String
    let username: String
    let password: String

    public init(url: String, username: String, password: String) {
        self.url = url
        self.username = username
        self.password = password
    }
    
    public static func initFromConfiguration(configuration: Configuration) -> API {
        let values = configuration.get()
        return API(url: values.hostname, username: values.username, password: values.password)
    }
    
    private func request<T: Decodable>(method: String, path: String, contentType: String?, data: String?, token: String?) async throws -> T {
        let url = URL(string: "\(self.url)\(path)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
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
                throw ApiError.accountRejected(error.error_description)
            }

            if httpResponse.statusCode != 200 {
                throw ApiError.http(status: httpResponse.statusCode, body: ApiError.excerpt(of: returnedData))
            }
        } else {
            throw ApiError.runtimeError("The server didn't send a valid response.")
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: returnedData)
        } catch {
            print("Unexpected error: \(error).")
            throw error
        }
    }

    public func getToken() async throws -> String {
        let data = try urlEncodedParams(params: [
            "client_id": "DoorCloudWebApp",
            "grant_type": "password",
            "username": username,
            "password": password,
        ])
        let response: TokenResponse = try await self.request(method: "POST", path: "/token", contentType: "application/x-www-form-urlencoded", data: data, token: nil)
        return response.access_token
    }
    
    public func getLocations(token: String) async throws -> [Location] {
        let response: GetUserLocationsResponse = try await self.request(method: "GET", path: "/api/Location/GetUserLocations", contentType: nil, data: nil, token: token)
        return response.result
    }
    
    public func openDoor(token: String, accessPointId: String) async throws -> OpenDoorResponse {
        let data = "accessPointId=\(accessPointId)"
        return try await self.request(method: "POST", path: "/api/Location/OpenDoorOnLocation", contentType: nil, data: data, token: token)
    }
}
