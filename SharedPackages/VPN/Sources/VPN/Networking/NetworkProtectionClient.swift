//
//  NetworkProtectionClient.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Networking
import os.log

protocol NetworkProtectionClient {
    func getLocations(authToken: String) async -> Result<[NetworkProtectionLocation], NetworkProtectionClientError>
    func getServers(authToken: String) async -> Result<[NetworkProtectionServer], NetworkProtectionClientError>
    func getServerStatus(authToken: String, serverName: String) async -> Result<NetworkProtectionServerStatus, NetworkProtectionClientError>
    func register(authToken: String, requestBody: RegisterKeyRequestBody) async -> Result<[NetworkProtectionServer], NetworkProtectionClientError>
}

public enum NetworkProtectionClientError: CustomNSError, NetworkProtectionErrorConvertible {
    case failedToFetchLocationList(Error)
    case failedToParseLocationListResponse(Error)
    case failedToFetchServerList(Error)
    case failedToParseServerListResponse(Error)
    case failedToFetchServerStatus(Error)
    case failedToParseServerStatusResponse(Error)
    case failedToEncodeRegisterKeyRequest
    case failedToFetchRegisteredServers(Error)
    case failedToParseRegisteredServersResponse(Error)
    case invalidAuthToken
    case accessDenied

    var networkProtectionError: NetworkProtectionError {
        switch self {
        case .failedToFetchLocationList(let error): return .failedToFetchLocationList(error)
        case .failedToParseLocationListResponse(let error): return .failedToParseLocationListResponse(error)
        case .failedToFetchServerList(let error): return .failedToFetchServerList(error)
        case .failedToParseServerListResponse(let error): return .failedToParseServerListResponse(error)
        case .failedToFetchServerStatus(let error): return .failedToFetchServerStatus(error)
        case .failedToParseServerStatusResponse(let error): return .failedToParseServerStatusResponse(error)
        case .failedToEncodeRegisterKeyRequest: return .failedToEncodeRegisterKeyRequest
        case .failedToFetchRegisteredServers(let error): return .failedToFetchRegisteredServers(error)
        case .failedToParseRegisteredServersResponse(let error): return .failedToParseRegisteredServersResponse(error)
        case .invalidAuthToken: return .invalidAuthToken
        case .accessDenied: return .vpnAccessRevoked
        }
    }

    public var errorCode: Int {
        switch self {
        case .failedToFetchLocationList: return 0
        case .failedToParseLocationListResponse: return 1
        case .failedToFetchServerList: return 2
        case .failedToParseServerListResponse: return 3
        case .failedToEncodeRegisterKeyRequest: return 4
        case .failedToFetchRegisteredServers: return 5
        case .failedToParseRegisteredServersResponse: return 6
        case .invalidAuthToken: return 12
        case .accessDenied: return 13
        case .failedToFetchServerStatus: return 14
        case .failedToParseServerStatusResponse: return 15
        }
    }

    public var errorUserInfo: [String: Any] {
        switch self {
        case .failedToFetchLocationList(let error),
                .failedToParseLocationListResponse(let error),
                .failedToFetchServerList(let error),
                .failedToParseServerListResponse(let error),
                .failedToFetchRegisteredServers(let error),
                .failedToParseRegisteredServersResponse(let error),
                .failedToFetchServerStatus(let error),
                .failedToParseServerStatusResponse(let error):
            return [NSUnderlyingErrorKey: error as NSError]
        case .failedToEncodeRegisterKeyRequest,
                .invalidAuthToken,
                .accessDenied:
            return [:]
        }
    }

    public var errorDescription: String? {
        switch self {
        case .failedToFetchLocationList: return "Failed to fetch location list"
        case .failedToParseLocationListResponse: return "Failed to parse location list response"
        case .failedToFetchServerList: return "Failed to fetch server list"
        case .failedToParseServerListResponse: return "Failed to parse server list response"
        case .failedToEncodeRegisterKeyRequest: return "Failed to encode register key request"
        case .failedToFetchServerStatus(let error):
            return "Failed to fetch server status: \(error)"
        case .failedToParseServerStatusResponse(let error):
            return "Failed to parse server status response: \(error)"
        case .failedToFetchRegisteredServers(let error):
            return "Failed to fetch registered servers: \(error)"
        case .failedToParseRegisteredServersResponse(let error):
            return "Failed to parse registered servers response: \(error)"
        case .invalidAuthToken: return "Invalid auth token"
        case .accessDenied: return "Access denied"
        }
    }
}

struct RegisterKeyRequestBody: Encodable {
    let publicKey: String
    let server: String?
    let country: String?
    let city: String?
    let mode: String?

    init(publicKey: PublicKey,
         serverSelection: RegisterServerSelection) {
        self.publicKey = publicKey.base64Key
        switch serverSelection {
        case .automatic:
            server = nil
            country = nil
            city = nil
        case .server(let name):
            server = name
            country = nil
            city = nil
        case .location(let country, let city):
            server = nil
            self.country = country
            self.city = city
        case .recovery(server: let server):
            self.server = server
            self.country = nil
            self.city = nil
        }
        mode = serverSelection.mode
    }
}

enum RegisterServerSelection {
    case automatic
    case server(name: String)
    case location(country: String, city: String?)
    case recovery(server: String)

    var mode: String? {
        switch self {
        case .recovery:
            "failureRecovery"
        case .automatic, .location, .server:
            nil
        }
    }
}

struct ExchangeAccessTokenRequestBody: Encodable {
    let token: String
}

struct AuthenticationSuccessResponse: Decodable {
    let token: String
}

final class NetworkProtectionBackendClient: NetworkProtectionClient {

    enum Constants {
        static let productionEndpoint = URL(string: "https://controller.netp.duckduckgo.com")!
        static let stagingEndpoint = URL(string: "https://staging1.netp.duckduckgo.com")!
    }

    private enum DecoderError: Error {
        case failedToDecode(key: String)
    }

    var serversURL: URL {
        endpointURL.appending("/servers")
    }

    var locationsURL: URL {
        endpointURL.appending("/locations")
    }

    var registerKeyURL: URL {
        endpointURL.appending("/register")
    }

    func serverStatusURL(serverName: String) -> URL {
        endpointURL.appending("/servers/\(serverName)/status")
    }

    private let decoder: JSONDecoder = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom({ decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            guard let date = formatter.date(from: dateString) else {
                throw DecoderError.failedToDecode(key: container.codingPath.last?.stringValue ?? String(describing: container.codingPath))
            }

            return date
        })

        return decoder
    }()

    private let endpointURL: URL

    init(environment: VPNSettings.SelectedEnvironment = .default) {
        self.endpointURL = environment.endpointURL
    }

    public enum GetLocationsError: CustomNSError {
        case noResponse
        case unexpectedStatus(status: Int)

        var errorCode: Int {
            switch self {
            case .noResponse:
                return 0
            case .unexpectedStatus(let status):
                // Adding a large number so that we can get a somewhat reasonable status code
                return 100000 + status
            }
        }
    }

    func getLocations(authToken: String) async -> Result<[NetworkProtectionLocation], NetworkProtectionClientError> {
        var request = URLRequest(url: locationsURL)
        request.allHTTPHeaderFields = APIRequest.Headers().httpHeaders
        request.setValue("bearer \(authToken)", forHTTPHeaderField: "Authorization")
        let downloadedData: Data

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw GetLocationsError.noResponse
            }
            switch response.statusCode {
            case 200: downloadedData = data
            case 401: return .failure(.invalidAuthToken)
            default:
                throw GetLocationsError.unexpectedStatus(status: response.statusCode)
            }
        } catch {
            return .failure(NetworkProtectionClientError.failedToFetchLocationList(error))
        }

        do {
            let decodedLocations = try decoder.decode([NetworkProtectionLocation].self, from: downloadedData)
            return .success(decodedLocations)
        } catch {
            return .failure(NetworkProtectionClientError.failedToParseLocationListResponse(error))
        }
    }

    public enum GetServersError: CustomNSError {
        case noResponse
        case unexpectedStatus(status: Int)

        var errorCode: Int {
            switch self {
            case .noResponse:
                return 0
            case .unexpectedStatus(let status):
                // Adding a large number so that we can get a somewhat reasonable status code
                return 100000 + status
            }
        }
    }

    func getServers(authToken: String) async -> Result<[NetworkProtectionServer], NetworkProtectionClientError> {
        var request = URLRequest(url: serversURL)
        request.allHTTPHeaderFields = APIRequest.Headers().httpHeaders
        request.setValue("bearer \(authToken)", forHTTPHeaderField: "Authorization")
        let downloadedData: Data

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw GetServersError.noResponse
            }
            switch response.statusCode {
            case 200: downloadedData = data
            case 401: return .failure(.invalidAuthToken)
            default:
                throw GetServersError.unexpectedStatus(status: response.statusCode)
            }
        } catch {
            return .failure(NetworkProtectionClientError.failedToFetchServerList(error))
        }

        do {
            let decodedServers = try decoder.decode([NetworkProtectionServer].self, from: downloadedData)
            return .success(decodedServers)
        } catch {
            return .failure(NetworkProtectionClientError.failedToParseServerListResponse(error))
        }
    }

    public enum GetServerStatusError: CustomNSError {
        case noResponse
        case unexpectedStatus(status: Int)

        var errorCode: Int {
            switch self {
            case .noResponse:
                return 0
            case .unexpectedStatus(let status):
                // Adding a large number so that we can get a somewhat reasonable status code
                return 100000 + status
            }
        }
    }

    func getServerStatus(authToken: String, serverName: String) async -> Result<NetworkProtectionServerStatus, NetworkProtectionClientError> {
        var request = URLRequest(url: serverStatusURL(serverName: serverName))
        request.allHTTPHeaderFields = APIRequest.Headers().httpHeaders
        request.setValue("bearer \(authToken)", forHTTPHeaderField: "Authorization")
        let downloadedData: Data

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw GetServerStatusError.noResponse
            }
            switch response.statusCode {
            case 200: downloadedData = data
            case 401: return .failure(.invalidAuthToken)
            default:
                throw GetServerStatusError.unexpectedStatus(status: response.statusCode)
            }
        } catch {
            return .failure(NetworkProtectionClientError.failedToFetchServerList(error))
        }

        do {
            let serverStatus = try decoder.decode(NetworkProtectionServerStatus.self, from: downloadedData)
            return .success(serverStatus)
        } catch {
            return .failure(NetworkProtectionClientError.failedToParseServerStatusResponse(error))
        }
    }

    public enum RegisterError: CustomNSError {
        case noResponse
        case unexpectedStatus(status: Int)

        var errorCode: Int {
            switch self {
            case .noResponse:
                return 0
            case .unexpectedStatus(let status):
                // Adding a large number so that we can get a somewhat reasonable status code
                return 100000 + status
            }
        }
    }

    func register(authToken: String,
                  requestBody: RegisterKeyRequestBody) async -> Result<[NetworkProtectionServer], NetworkProtectionClientError> {
        let requestBodyData: Data

        do {
            requestBodyData = try JSONEncoder().encode(requestBody)
        } catch {
            return .failure(NetworkProtectionClientError.failedToEncodeRegisterKeyRequest)
        }

        var request = URLRequest(url: registerKeyURL)
        request.allHTTPHeaderFields = APIRequest.Headers().httpHeaders
        request.setValue("bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = requestBodyData

        let responseData: Data

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw RegisterError.noResponse
            }
            switch response.statusCode {
            case 200:
                responseData = data
            case 401:
                return .failure(.invalidAuthToken)
            case 403:
                return .failure(.accessDenied)
            default:
                throw RegisterError.unexpectedStatus(status: response.statusCode)
            }
        } catch {
            return .failure(NetworkProtectionClientError.failedToFetchRegisteredServers(error))
        }

        do {
            let decodedServers = try decoder.decode([NetworkProtectionServer].self, from: responseData)
            return .success(decodedServers)
        } catch {
            return .failure(NetworkProtectionClientError.failedToParseRegisteredServersResponse(error))
        }
    }

    public enum AuthTokenError: CustomNSError {
        case noResponse
        case unexpectedStatus(status: Int)

        var errorCode: Int {
            switch self {
            case .noResponse:
                return 0
            case .unexpectedStatus(let status):
                // Adding a large number so that we can get a somewhat reasonable status code
                return 100000 + status
            }
        }
    }

}

extension URL {

    func appending(_ path: String) -> URL {
        if #available(macOS 13.0, iOS 16.0, *) {
            return appending(path: path)
        } else {
            return appendingPathComponent(path)
        }
    }

}
