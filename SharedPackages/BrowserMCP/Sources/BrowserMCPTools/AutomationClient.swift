//
//  AutomationClient.swift
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

/// A decoded response from the browser's automation server.
///
/// The server answers every request with `{"message": ..., "requestPath": ...}` and either
/// HTTP 200 or HTTP 400. See `AutomationServerCore.responseToString`.
public struct AutomationResponse: Equatable, Sendable {
    public let statusCode: Int
    public let message: String
    public let requestPath: String

    public init(statusCode: Int, message: String, requestPath: String) {
        self.statusCode = statusCode
        self.message = message
        self.requestPath = requestPath
    }
}

public enum AutomationClientError: Error, Equatable, CustomStringConvertible {
    case invalidRequest
    case browserUnreachable(String)
    case invalidResponse
    case serverError(path: String, message: String)

    public var description: String {
        switch self {
        case .invalidRequest:
            return "Could not build a request for the automation server."
        case .browserUnreachable(let reason):
            return "Could not reach the browser's automation server (\(reason)). "
                + "Use browser_launch, or start a Debug/Review build of the browser with -automationPort <port>."
        case .invalidResponse:
            return "The automation server returned a response that could not be decoded."
        case .serverError(let path, let message):
            return "The automation server rejected \(path): \(message)"
        }
    }
}

/// Transport to the automation server. Abstracted so tools can be unit-tested without a running browser.
public protocol AutomationTransport: Sendable {
    /// Sends a request. Implementations throw `AutomationClientError.serverError` for HTTP 400 responses.
    func send(method: String, path: String, query: [String: String]) async throws -> AutomationResponse
}

public extension AutomationTransport {
    func get(_ path: String, query: [String: String] = [:]) async throws -> AutomationResponse {
        try await send(method: "GET", path: path, query: query)
    }

    func post(_ path: String, query: [String: String] = [:]) async throws -> AutomationResponse {
        try await send(method: "POST", path: path, query: query)
    }
}

/// Talks plain HTTP to `AutomationServerCore` running inside a Debug or Review build of the browser.
/// This is the same contract used by `ddgdriver` in shared-web-tests and the crossbench harness.
public struct HTTPAutomationClient: AutomationTransport {
    public let baseURL: URL
    public let authToken: String?
    private let session: URLSession

    /// - Parameters:
    ///   - port: the value passed to the browser as `-automationPort`.
    ///   - authToken: optional bearer token; only required when the browser was launched with `AUTOMATION_TOKEN`.
    ///   - timeout: per-request timeout. The server itself waits up to 30s for page loads before answering.
    public init(port: Int, authToken: String? = nil, timeout: TimeInterval = 60) {
        // The server binds the IPv6 loopback with dual-stack enabled, so `localhost` resolves either way.
        self.baseURL = URL(string: "http://localhost:\(port)")!
        self.authToken = authToken.flatMap { $0.isEmpty ? nil : $0 }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.httpMaximumConnectionsPerHost = 1
        self.session = URLSession(configuration: configuration)
    }

    public func send(method: String, path: String, query: [String: String]) async throws -> AutomationResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw AutomationClientError.invalidRequest
        }
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw AutomationClientError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AutomationClientError.browserUnreachable(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AutomationClientError.invalidResponse
        }
        return try Self.decode(statusCode: httpResponse.statusCode, body: data)
    }

    struct Envelope: Decodable {
        let message: String
        let requestPath: String
    }

    static func decode(statusCode: Int, body: Data) throws -> AutomationResponse {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else {
            throw AutomationClientError.invalidResponse
        }
        guard statusCode == 200 else {
            throw AutomationClientError.serverError(path: envelope.requestPath, message: envelope.message)
        }
        return AutomationResponse(statusCode: statusCode, message: envelope.message, requestPath: envelope.requestPath)
    }
}
