//
//  SubscriptionAPIService.swift
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
import Common
import os.log
import Networking

public enum APIServiceError: DDGError {
    case decodingError
    case encodingError
    case serverError(statusCode: Int, errorCode: String?)
    case unknownServerError
    case connectionError
    case invalidToken

    public var description: String {
        switch self {
        case .decodingError:
            return "Decoding error"
        case .encodingError:
            return "Encoding error"
        case .serverError(statusCode: let statusCode, errorCode: let error):
            return "Server error (\(statusCode)): \(error ?? "No error description provided")"
        case .unknownServerError:
            return "Unknown server error"
        case .connectionError:
            return "Connection error"
        case .invalidToken:
            return "Invalid Token"
        }
    }

    public var errorDomain: String { "com.duckduckgo.subscription.APIServiceError" }

    public var errorCode: Int {
        switch self {
        case .decodingError: 12500
        case .encodingError: 12501
        case .serverError: 12502
        case .unknownServerError: 12503
        case .connectionError:  12504
        case .invalidToken: 12505
        }
    }
}

struct ErrorResponse: Decodable {
    let error: String
}

public protocol SubscriptionAPIService {
    func executeAPICall<T>(method: String, endpoint: String, headers: [String: String]?, body: Data?) async -> Result<T, APIServiceError> where T: Decodable
    func makeAuthorizationHeader(for token: String) -> [String: String]
}

public enum APICachePolicy {
    case reloadIgnoringLocalCacheData
    case returnCacheDataElseLoad

    public var subscriptionCachePolicy: SubscriptionCachePolicy {
        switch self {
        case .reloadIgnoringLocalCacheData:
            return .remoteFirst
        case .returnCacheDataElseLoad:
            return .cacheFirst
        }
    }
}

public struct DefaultSubscriptionAPIService: SubscriptionAPIService {
    private let baseURL: URL
    private let userAgent: String
    private let session: URLSession

    public init(baseURL: URL, userAgent: String, session: URLSession) {
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.session = session
    }

    public func executeAPICall<T>(method: String, endpoint: String, headers: [String: String]? = nil, body: Data? = nil) async -> Result<T, APIServiceError> where T: Decodable {
        let request = makeAPIRequest(method: method, endpoint: endpoint, headers: headers, body: body)

        do {
            let (data, urlResponse) = try await session.data(for: request)

            printDebugInfo(method: method, endpoint: endpoint, data: data, response: urlResponse)

            guard let httpResponse = urlResponse as? HTTPURLResponse else { return .failure(.unknownServerError) }

            if (200..<300).contains(httpResponse.statusCode) {
                if let decodedResponse = decode(T.self, from: data) {
                    return .success(decodedResponse)
                } else {
                    Logger.subscription.error("Service error: APIServiceError.decodingError")
                    return .failure(.decodingError)
                }
            } else if httpResponse.statusCode == 401 {
                return .failure(.invalidToken)
            } else {
                var errorString: String?

                if let decodedResponse = decode(ErrorResponse.self, from: data) {
                    errorString = decodedResponse.error
                }

                let errorLogMessage = "/\(endpoint) \(httpResponse.statusCode): \(errorString ?? "")"
                Logger.subscription.error("Service error: \(errorLogMessage, privacy: .public)")
                return .failure(.serverError(statusCode: httpResponse.statusCode, errorCode: errorString))
            }
        } catch {
            Logger.subscription.error("Service error: \(error.localizedDescription, privacy: .public)")
            return .failure(.connectionError)
        }
    }

    private func makeAPIRequest(method: String, endpoint: String, headers: [String: String]?, body: Data?) -> URLRequest {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.allHTTPHeaderFields = headers ?? [:]
        request.allHTTPHeaderFields?[HTTPHeaderKey.userAgent] = userAgent

        if let body = body {
            request.httpBody = body
        }

        return request
    }

    private func decode<T>(_: T.Type, from data: Data) -> T? where T: Decodable {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .millisecondsSince1970

        return try? decoder.decode(T.self, from: data)
    }

    private func printDebugInfo(method: String, endpoint: String, data: Data, response: URLResponse) {
        let statusCode = (response as? HTTPURLResponse)!.statusCode
        let stringData = String(data: data, encoding: .utf8) ?? ""

        Logger.subscription.info("[API] \(statusCode) \(method, privacy: .public) \(endpoint, privacy: .public) :: \(stringData, privacy: .public)")
    }

    public func makeAuthorizationHeader(for token: String) -> [String: String] {
        ["Authorization": "Bearer " + token]
    }
}

fileprivate extension URLResponse {

    var httpStatusCodeAsString: String? {
        guard let httpStatusCode = (self as? HTTPURLResponse)?.statusCode else { return nil }
        return String(httpStatusCode)
    }
}
