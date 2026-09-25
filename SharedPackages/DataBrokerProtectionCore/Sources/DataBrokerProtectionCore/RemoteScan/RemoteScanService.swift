//
//  RemoteScanService.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import os.log

// MARK: - Wire types

/// The subset of the user's profile that a remote scan needs. Deliberately *not* `ProfileQuery`:
/// local database ids and derived fields (`age`, `fullName`, `addresses`) stay on the client.
/// The server derives `age` and the address list itself.
public struct RemoteScanProfile: Codable, Equatable, Sendable {
    public let firstName: String
    public let middleName: String?
    public let lastName: String
    public let suffix: String?
    public let city: String
    public let state: String
    public let birthYear: Int

    public init(firstName: String,
                middleName: String? = nil,
                lastName: String,
                suffix: String? = nil,
                city: String,
                state: String,
                birthYear: Int) {
        self.firstName = firstName
        self.middleName = middleName
        self.lastName = lastName
        self.suffix = suffix
        self.city = city
        self.state = state
        self.birthYear = birthYear
    }

    public init(profileQuery: ProfileQuery) {
        self.init(firstName: profileQuery.firstName,
                  middleName: profileQuery.middleName,
                  lastName: profileQuery.lastName,
                  suffix: profileQuery.suffix,
                  city: profileQuery.city,
                  state: profileQuery.state,
                  birthYear: profileQuery.birthYear)
    }
}

/// `POST /v0/scans` body. `brokerId` is the broker JSON file name (e.g. `spokeo.com.json`); the
/// server owns the broker definitions and uses its latest copy.
public struct RemoteScanRequest: Codable, Equatable, Sendable {
    public let brokerId: String
    public let profile: RemoteScanProfile

    public init(brokerId: String, profile: RemoteScanProfile) {
        self.brokerId = brokerId
        self.profile = profile
    }
}

public enum RemoteScanStatus: String, Codable, Sendable {
    case queued
    case running
    case completed
    case failed
}

public struct RemoteScanSubmitResponse: Codable, Sendable {
    public let scanId: String
    public let status: RemoteScanStatus

    public init(scanId: String, status: RemoteScanStatus) {
        self.scanId = scanId
        self.status = status
    }
}

public struct RemoteScanError: Codable, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// `GET /v0/scans/{scanId}` body. `matches` uses the same JSON shape content-scope-scripts'
/// `extract` action produces, so it decodes straight into `ExtractedProfile`.
public struct RemoteScanStatusResponse: Codable, Sendable {
    public let scanId: String
    public let status: RemoteScanStatus
    public let matches: [ExtractedProfile]?
    public let error: RemoteScanError?

    public init(scanId: String, status: RemoteScanStatus, matches: [ExtractedProfile]?, error: RemoteScanError?) {
        self.scanId = scanId
        self.status = status
        self.matches = matches
        self.error = error
    }
}

// MARK: - Service

public protocol RemoteScanServiceProviding {
    func submit(_ request: RemoteScanRequest) async throws -> RemoteScanSubmitResponse
    func status(scanId: String) async throws -> RemoteScanStatusResponse
}

/// POC HTTP client for the remote scan server. No auth. Base URL comes from
/// `DataBrokerProtectionSettings.remoteJobServerURL` (overridable from the macOS debug menu).
public final class RemoteScanService: RemoteScanServiceProviding {

    enum Constants {
        static let scansPath = "/v0/scans"
    }

    private let settings: DataBrokerProtectionSettings
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(settings: DataBrokerProtectionSettings, urlSession: URLSession = .shared) {
        self.settings = settings
        self.urlSession = urlSession

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func submit(_ request: RemoteScanRequest) async throws -> RemoteScanSubmitResponse {
        let url = try url(forScanId: nil)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try encoder.encode(request)

        Logger.dataBrokerProtection.log("🌐 [RemoteScan] POST \(url.absoluteString, privacy: .public) broker: \(request.brokerId, privacy: .public)")

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, body: data)
        return try decode(RemoteScanSubmitResponse.self, from: data)
    }

    public func status(scanId: String) async throws -> RemoteScanStatusResponse {
        let url = try url(forScanId: scanId)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, body: data)
        return try decode(RemoteScanStatusResponse.self, from: data)
    }

    // MARK: - Helpers

    func url(forScanId scanId: String?) throws -> URL {
        var components = URLComponents(url: settings.remoteJobServerURL, resolvingAgainstBaseURL: true)
        var path = components?.path ?? ""
        while path.hasSuffix("/") { path.removeLast() }
        path += Constants.scansPath
        if let scanId {
            path += "/" + scanId
        }
        components?.path = path

        guard let url = components?.url else {
            throw DataBrokerProtectionError.malformedURL
        }
        return url
    }

    private func validate(_ response: URLResponse, body: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DataBrokerProtectionError.httpError(code: 0)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(bytes: body.prefix(200), encoding: .utf8) ?? ""
            Logger.dataBrokerProtection.error("🌐 [RemoteScan] HTTP \(httpResponse.statusCode, privacy: .public): \(message, privacy: .public)")
            throw DataBrokerProtectionError.httpError(code: httpResponse.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            Logger.dataBrokerProtection.error("🌐 [RemoteScan] Failed to decode \(String(describing: type), privacy: .public): \(error, privacy: .public)")
            throw DataBrokerProtectionError.unknown("RemoteScanService: failed to decode \(type): \(error)")
        }
    }
}
