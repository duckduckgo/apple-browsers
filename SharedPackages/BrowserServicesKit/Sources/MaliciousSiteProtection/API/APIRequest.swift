//
//  APIRequest.swift
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

// Enumerated request type to delegate URLs forming to an API environment instance
public enum APIRequestType {
    case hashPrefixSet(APIRequestType.HashPrefixes)
    case filterSet(APIRequestType.FilterSet)
    case matches(APIRequestType.Matches)
}

extension APIClient {
    // Protocol for defining typed requests with a specific response type.
    protocol Request {
        associatedtype Response: Decodable // Strongly-typed response type
        var requestType: APIRequestType { get } // Enumerated type of request being made
        var defaultTimeout: TimeInterval? { get }
    }

    // Protocol for requests that modify a set of malicious site detection data
    // (returning insertions/removals along with the updated revision)
    protocol ChangeSetRequest: Request {
        init(threatKind: ThreatKind, revision: Int?)
    }
}
extension APIClient.Request {
    var defaultTimeout: TimeInterval? { nil }
}

public extension APIRequestType {
    struct HashPrefixes: APIClient.ChangeSetRequest {
        typealias Response = APIClient.Response.HashPrefixesChangeSet

        let threatKind: ThreatKind
        let revision: Int?

        public init(threatKind: ThreatKind, revision: Int?) {
            self.threatKind = threatKind
            self.revision = revision
        }

        var requestType: APIRequestType {
            .hashPrefixSet(self)
        }
    }
}
/// extension to call generic `load(_: some Request)` method like this: `load(.hashPrefixes(…))`
extension APIClient.Request where Self == APIRequestType.HashPrefixes {
    static func hashPrefixes(threatKind: ThreatKind, revision: Int?) -> Self {
        .init(threatKind: threatKind, revision: revision)
    }
}

public extension APIRequestType {
    struct FilterSet: APIClient.ChangeSetRequest {
        typealias Response = APIClient.Response.FiltersChangeSet

        let threatKind: ThreatKind
        let revision: Int?

        public init(threatKind: ThreatKind, revision: Int?) {
            self.threatKind = threatKind
            self.revision = revision
        }

        var requestType: APIRequestType {
            .filterSet(self)
        }
    }
}
/// extension to call generic `load(_: some Request)` method like this: `load(.filterSet(…))`
extension APIClient.Request where Self == APIRequestType.FilterSet {
    static func filterSet(threatKind: ThreatKind, revision: Int?) -> Self {
        .init(threatKind: threatKind, revision: revision)
    }
}

public extension APIRequestType {
    struct Matches: APIClient.Request {
        typealias Response = APIClient.Response.Matches

        let hashPrefix: String

        public init(hashPrefix: String) {
            self.hashPrefix = hashPrefix
        }

        var requestType: APIRequestType {
            .matches(self)
        }

        var defaultTimeout: TimeInterval? { 5 }
    }
}
/// extension to call generic `load(_: some Request)` method like this: `load(.matches(…))`
extension APIClient.Request where Self == APIRequestType.Matches {
    static func matches(hashPrefix: String) -> Self {
        .init(hashPrefix: hashPrefix)
    }
}
