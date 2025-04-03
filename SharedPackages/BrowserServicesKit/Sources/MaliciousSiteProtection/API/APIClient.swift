//
//  APIClient.swift
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

import Common
import Foundation
import Networking

extension APIClient {
    // used internally for testing
    protocol Mockable {
        func load<Request: APIClient.Request>(_ requestConfig: Request) async throws -> Request.Response
    }
}
extension APIClient: APIClient.Mockable {}

public protocol APIClientEnvironment {
    func headers(for requestType: APIRequestType, platform: MaliciousSiteDetector.APIEnvironment.Platform, authToken: String?) -> APIRequestV2.HeadersV2
    func url(for requestType: APIRequestType, platform: MaliciousSiteDetector.APIEnvironment.Platform) -> URL
    func timeout(for requestType: APIRequestType) -> TimeInterval?
}

public extension APIClientEnvironment {
    func timeout(for requestType: APIRequestType) -> TimeInterval? { nil }
}

public extension MaliciousSiteDetector {
    enum APIEnvironment: APIClientEnvironment {

        case production
        case staging

        func endpoint(for platform: Platform) -> URL {
            switch self {
            case .production: URL(string: "https://duckduckgo.com/api/protection/v2/\(platform.rawValue)/")!
            case .staging: URL(string: "https://staging.duckduckgo.com/api/protection/v2/\(platform.rawValue)/")!
            }
        }

        public enum Platform: String {
            case macOS = "macos"
            case iOS = "ios"
        }

        enum APIPath {
            static let filterSet = "filterSet"
            static let hashPrefix = "hashPrefix"
            static let matches = "matches"
        }

        enum QueryParameter {
            static let category = "category"
            static let revision = "revision"
            static let hashPrefix = "hashPrefix"
        }

        public func url(for requestType: APIRequestType, platform: Platform) -> URL {
            let endpoint = endpoint(for: platform)
            return switch requestType {
            case .hashPrefixSet(let configuration):
                endpoint.appendingPathComponent(APIPath.hashPrefix).appendingParameters([
                    QueryParameter.category: configuration.threatKind.rawValue,
                    QueryParameter.revision: (configuration.revision ?? 0).description,
                ])
            case .filterSet(let configuration):
                endpoint.appendingPathComponent(APIPath.filterSet).appendingParameters([
                    QueryParameter.category: configuration.threatKind.rawValue,
                    QueryParameter.revision: (configuration.revision ?? 0).description,
                ])
            case .matches(let configuration):
                endpoint.appendingPathComponent(APIPath.matches).appendingParameter(name: QueryParameter.hashPrefix, value: configuration.hashPrefix)
            }
        }

        public func headers(for requestType: APIRequestType, platform: Platform, authToken: String?) -> APIRequestV2.HeadersV2 {
            .init(userAgent: Networking.APIRequest.Headers.userAgent,
                  additionalHeaders: [
                    HTTPHeaderKey.authToken: authToken ?? "7cf93ee564654b410b3a2ec9c769dda93b1aa9d3c490fc2abdf7dea969367fcd",
                  ])
        }
    }

}

struct APIClient {

    typealias Platform = MaliciousSiteDetector.APIEnvironment.Platform
    let platform: Platform
    let authToken: String?
    let environment: APIClientEnvironment
    private let service: APIService

    init(environment: APIClientEnvironment, platform: Platform? = nil, authToken: String? = nil, service: APIService = DefaultAPIService(urlSession: .shared)) {
        if let platform {
            self.platform = platform
        } else {
#if os(macOS)
            self.platform = .macOS
#elseif os(iOS)
            self.platform = .iOS
#else
            fatalError("Unsupported platform")
#endif
        }
        self.authToken = authToken
        self.environment = environment
        self.service = service
    }

    func load<R: Request>(_ requestConfig: R) async throws -> R.Response {
        let requestType = requestConfig.requestType
        let headers = environment.headers(for: requestType, platform: platform, authToken: authToken)
        let url = environment.url(for: requestType, platform: platform)
        let timeout = environment.timeout(for: requestType) ?? requestConfig.defaultTimeout ?? 60

        guard let apiRequest = APIRequestV2(url: url, method: .get, headers: headers, timeoutInterval: timeout) else {
            assertionFailure("Invalid URL")
            throw APIRequestV2.Error.invalidURL
        }
        let response = try await service.fetch(request: apiRequest)
        let result: R.Response = try response.decodeBody()

        return result
    }

}

// MARK: - Convenience
extension APIClient.Mockable {
    func filtersChangeSet(for threatKind: ThreatKind, revision: Int) async throws -> APIClient.Response.FiltersChangeSet {
        let result = try await load(.filterSet(threatKind: threatKind, revision: revision))
        return result
    }

    func hashPrefixesChangeSet(for threatKind: ThreatKind, revision: Int) async throws -> APIClient.Response.HashPrefixesChangeSet {
        let result = try await load(.hashPrefixes(threatKind: threatKind, revision: revision))
        return result
    }

    func matches(forHashPrefix hashPrefix: String) async throws -> APIClient.Response.Matches {
        let result = try await load(.matches(hashPrefix: hashPrefix))
        return result
    }
}
