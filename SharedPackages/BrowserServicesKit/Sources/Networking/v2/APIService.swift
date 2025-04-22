//
//  APIService.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

/// Protocol describing the DDG service for fetching API requests
public protocol APIService {
    typealias AuthorizationRefresherCallback = ((_: APIRequestV2) async throws -> String)

    /// Closure called every time an authenticated request fails with a 401
    var authorizationRefresherCallback: AuthorizationRefresherCallback? { get set }

    /// Fetch an API Request
    /// - Parameter request: A configured `APIRequest`
    /// - Returns: An `APIResponseV2` containing the body data and the HTTPURLResponse
    func fetch(request: APIRequestV2) async throws -> APIResponseV2
}

/// The default implementation of `APIService`
public class DefaultAPIService: APIService {
    private let urlSession: URLSession
    public var authorizationRefresherCallback: AuthorizationRefresherCallback?

    /// Designited initialiser
    /// - Parameters:
    ///   - urlSession: The URLSession used for fetching requests
    ///   - authorizationRefresherCallback: Optional closure called every time an authenticated request fails with a 401
    public init(urlSession: URLSession = .shared, authorizationRefresherCallback: AuthorizationRefresherCallback? = nil) {
        self.urlSession = urlSession
        self.authorizationRefresherCallback = authorizationRefresherCallback
    }

    public func fetch(request: APIRequestV2) async throws -> APIResponseV2 {
        return try await fetch(request: request, authAlreadyRefreshed: false, failureRetryCount: 0)
    }

    private func fetch(request: APIRequestV2, authAlreadyRefreshed: Bool, failureRetryCount: Int) async throws -> APIResponseV2 {
        var request = request

        Logger.networking.debug("Fetching: \(request.debugDescription)")

        var result: (data: Data, response: URLResponse)
        do {
            result = try await urlSession.data(for: request.urlRequest)
        } catch {
            Logger.networking.error("Request failed: \(error.localizedDescription)\nrequest: \(request.url?.absoluteString ?? "unknown URL")")

            if let retryPolicy = request.retryPolicy,
               failureRetryCount < retryPolicy.maxRetries {

                // It's a failure and the request must be retried
                Logger.networking.debug("Retrying applying \(retryPolicy.debugDescription)")
                let delayTimeInterval = retryPolicy.delay.delayTimeInterval(failureRetryCount: failureRetryCount)
                if delayTimeInterval > 0 {
                    Logger.networking.debug("Retrying after \(delayTimeInterval) seconds")
                    try? await Task.sleep(interval: delayTimeInterval)
                }
                // Try again
                return try await fetch(request: request, authAlreadyRefreshed: authAlreadyRefreshed, failureRetryCount: failureRetryCount + 1)
            } else {
                throw APIRequestV2.Error.urlSession(error)
            }
        }

        try Task.checkCancellation()

        // Check response code
        let httpResponse = try result.response.asHTTPURLResponse()
        let responseHTTPStatus = httpResponse.httpStatus

        Logger.networking.debug("Response: [\(responseHTTPStatus.description, privacy: .public)] \(result.response.debugDescription) Data size: \(result.data.count) bytes")
#if DEBUG
        if let bodyString = String(data: result.data, encoding: .utf8),
           !bodyString.isEmpty {
            Logger.networking.debug("Response body: \(bodyString, privacy: .public)")
        }
#endif

        // First time the request is executed and the response is `.unauthorized` we try to refresh the authentication token
        if responseHTTPStatus == .unauthorized,
           request.isAuthenticated == true,
           !authAlreadyRefreshed,
           let authorizationRefresherCallback {
            Logger.networking.log("Refreshing token for \(request.url?.absoluteString ?? "unknown URL", privacy: .public)")
            // Ask to refresh the token
            let refreshedToken = try await authorizationRefresherCallback(request)
            request.updateAuthorizationHeader(refreshedToken)

            // Try again
            return try await fetch(request: request, authAlreadyRefreshed: true, failureRetryCount: failureRetryCount)
        }

        // It's not a failure, we check the constraints
        if !responseHTTPStatus.isFailure {
            try checkConstraints(in: httpResponse, for: request)
        }
        return APIResponseV2(data: result.data, httpResponse: httpResponse)
    }

    /// Check if the response satisfies the required constraints
    private func checkConstraints(in response: HTTPURLResponse, for request: APIRequestV2) throws {

        let httpResponse = try response.asHTTPURLResponse()
        let responseHTTPStatus = httpResponse.httpStatus
        let notModifiedIsAllowed: Bool = request.responseConstraints?.contains(.allowHTTPNotModified) ?? false
        if responseHTTPStatus == .notModified && !notModifiedIsAllowed {
            let error = APIRequestV2.Error.unsatisfiedRequirement(.allowHTTPNotModified)
            Logger.networking.error("Error: \(error.localizedDescription)")
            throw error
        }
        if let requirements = request.responseConstraints {
            for requirement in requirements {
                switch requirement {
                case .requireETagHeader:
                    guard httpResponse.etag != nil else {
                        let error = APIRequestV2.Error.unsatisfiedRequirement(requirement)
                        Logger.networking.error("Error: \(error.localizedDescription)")
                        throw error
                    }
                case .requireUserAgent:
                    guard let userAgent = httpResponse.allHeaderFields[HTTPHeaderKey.userAgent] as? String,
                          userAgent.isEmpty == false else {
                        let error = APIRequestV2.Error.unsatisfiedRequirement(requirement)
                        Logger.networking.error("Error: \(error.localizedDescription)")
                        throw error
                    }
                default:
                    break
                }
            }
        }

    }
}
