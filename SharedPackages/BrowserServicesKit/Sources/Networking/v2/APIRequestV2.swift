//
//  APIRequestV2.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public struct APIRequestV2: Hashable, CustomDebugStringConvertible {

    private(set) var urlRequest: URLRequest

    /// This is the retry policy for the request, if the request fails for some network error it will be retried up to `maxRetries` times with a delay of `delay` between each retry
    /// The retry is not used for DDG API requests error like .badRequest or .unauthorized but only for network errors thrown by `urlSession.data(for: ...)` like .timedOut or .cannotConnectToHost
    public struct RetryPolicy: Hashable, CustomDebugStringConvertible {

        public enum Delay: Equatable, Hashable {
            case fixed(TimeInterval)
            case exponential(baseDelay: TimeInterval)
            case jitter(backoff: TimeInterval)

            var debugDescription: String {
                switch self {
                case .fixed(let value):
                    return "fixed(\(value))"
                case .exponential(baseDelay: let value):
                    return "exponential(baseDelay: \(value))"
                case .jitter(backoff: let value):
                    return "jitter(backoff: \(value))"
                }
            }

            public func delayTimeInterval(failureRetryCount: Int) -> TimeInterval {
                switch self {
                case .fixed(let interval):
                    return interval
                case .exponential(let baseDelay):
                    if failureRetryCount == 0 {
                        return baseDelay
                    } else {
                        return pow(baseDelay, Double(failureRetryCount+1))
                    }
                case .jitter(let backoff):
                    return Double.random(in: 0...backoff)
                }
            }
        }

        public let maxRetries: Int
        public let delay: Delay

        public init(maxRetries: Int, delay: Delay = .fixed(0)) {
            self.maxRetries = maxRetries
            self.delay = delay
        }

        public var debugDescription: String {
            "MaxRetries: \(maxRetries), delay: \(delay)"
        }
    }

    let timeoutInterval: TimeInterval
    let responseConstraints: [APIResponseConstraints]?
    let retryPolicy: RetryPolicy?

    /// Designated initialiser
    /// - Parameters:
    ///   - url: The request URL, included protocol and host
    ///   - method: HTTP method
    ///   - queryItems: A key value dictionary with query parameters
    ///   - headers: HTTP headers
    ///   - body: The request body
    ///   - timeoutInterval: The request timeout interval, default is `60`s
    ///   - retryPolicy: The request retry policy, see `RetryPolicy` for more information
    ///   - cachePolicy: The request cache policy, default is `.useProtocolCachePolicy`
    ///   - responseRequirements: The response requirements
    ///   - allowedQueryReservedCharacters: The characters in this character set will not be URL encoded in the query parameters
    /// - Note: The init can return nil if the URLComponents fails to parse the provided URL
    public init?(url: URL,
                 method: HTTPRequestMethod = .get,
                 queryItems: QueryItems? = nil,
                 headers: APIRequestV2.HeadersV2? = APIRequestV2.HeadersV2(),
                 body: Data? = nil,
                 timeoutInterval: TimeInterval = 60.0,
                 retryPolicy: RetryPolicy? = nil,
                 cachePolicy: URLRequest.CachePolicy? = nil,
                 responseConstraints: [APIResponseConstraints]? = nil,
                 allowedQueryReservedCharacters: CharacterSet? = nil) {

        self.timeoutInterval = timeoutInterval
        self.responseConstraints = responseConstraints

        // Generate URL request
        guard var urlComps = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            assertionFailure("Malformed URL: \(url)")
            return nil
        }
        if let queryItems {
            // we append both the query items already added to the URL and the new passed as parameters
            let originalQI = urlComps.queryItems ?? []
            urlComps.queryItems = originalQI + queryItems.toURLQueryItems(allowedReservedCharacters: allowedQueryReservedCharacters)
        }
        guard let finalURL = urlComps.url else {
            assertionFailure("Malformed URL from URLComponents: \(urlComps)")
            return nil
        }
        var request = URLRequest(url: finalURL, timeoutInterval: timeoutInterval)
        request.allHTTPHeaderFields = headers?.httpHeaders
        request.httpMethod = method.rawValue
        request.httpBody = body
        if let cachePolicy = cachePolicy {
            request.cachePolicy = cachePolicy
        }
        self.urlRequest = request
        self.retryPolicy = retryPolicy
    }

    public var debugDescription: String {
        """
        APIRequestV2:
        URL: \(urlRequest.url?.absoluteString ?? "nil")
        Method: \(urlRequest.httpMethod ?? "nil")
        Headers: \(urlRequest.allHTTPHeaderFields?.debugDescription ?? "-")
        Body: \(urlRequest.httpBody?.debugDescription ?? "-")
        Timeout Interval: \(timeoutInterval)s
        Cache Policy: \(urlRequest.cachePolicy)
        Response Constraints: \(responseConstraints?.map { $0.rawValue } ?? [])
        Retry Policy: \(retryPolicy?.debugDescription ?? "None")
        """
    }

    public mutating func updateAuthorizationHeader(_ token: String) {
        self.urlRequest.allHTTPHeaderFields?[HTTPHeaderKey.authorization] = "Bearer \(token)"
    }

    public var isAuthenticated: Bool {
        return urlRequest.allHTTPHeaderFields?[HTTPHeaderKey.authorization] != nil
    }

    // MARK: Hashable Conformance

    public static func == (lhs: APIRequestV2, rhs: APIRequestV2) -> Bool {
        let urlLhs = lhs.urlRequest.url?.pathComponents.joined(separator: "/")
        let urlRhs = rhs.urlRequest.url?.pathComponents.joined(separator: "/")

        return urlLhs == urlRhs &&
        lhs.timeoutInterval == rhs.timeoutInterval &&
        lhs.responseConstraints == rhs.responseConstraints &&
        lhs.retryPolicy == rhs.retryPolicy
    }

    public func hash(into hasher: inout Hasher) {
        let urlPath = urlRequest.url?.pathComponents.joined(separator: "/")
        hasher.combine(urlPath)
        hasher.combine(timeoutInterval)
        hasher.combine(responseConstraints)
        hasher.combine(retryPolicy)
    }
}

extension APIRequestV2 {

    public var url: URL? {
        urlRequest.url
    }
}
