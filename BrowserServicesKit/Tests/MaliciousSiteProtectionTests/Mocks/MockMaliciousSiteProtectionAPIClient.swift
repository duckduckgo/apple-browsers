//
//  MockMaliciousSiteProtectionAPIClient.swift
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
@testable import MaliciousSiteProtection

class MockMaliciousSiteProtectionAPIClient: MaliciousSiteProtection.APIClient.Mockable {
    var updateHashPrefixesCalled: ((Int) -> Void)?
    var updateFilterSetsCalled: ((Int) -> Void)?

    var loadRequestError: Error?

    var filterRevisions: [Int: APIClient.Response.FiltersChangeSet] = [
        0: .init(insert: [
            Filter(hash: "testhash1", regex: ".*example.*"),
            Filter(hash: "testhash2", regex: ".*test.*")
        ], delete: [], revision: 1, replace: false),
        1: .init(insert: [
            Filter(hash: "testhash3", regex: ".*test.*")
        ], delete: [
            Filter(hash: "testhash1", regex: ".*example.*"),
        ], revision: 2, replace: false),
        2: .init(insert: [
            Filter(hash: "testhash4", regex: ".*test.*")
        ], delete: [
            Filter(hash: "testhash2", regex: ".*test.*"),
        ], revision: 3, replace: false),
        4: .init(insert: [
            Filter(hash: "testhash5", regex: ".*test.*")
        ], delete: [
            Filter(hash: "testhash3", regex: ".*test.*"),
        ], revision: 5, replace: false),
        5: .init(insert: [
            Filter(hash: "testhash6", regex: ".*test6.*")
        ], delete: [
            Filter(hash: "testhash3", regex: ".*test.*"),
        ], revision: 6, replace: true),
    ]

    private var hashPrefixRevisions: [Int: APIClient.Response.HashPrefixesChangeSet] = [
        0: .init(insert: [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ], delete: [], revision: 1, replace: false),
        1: .init(insert: ["93e2435e"], delete: [
            "cc00dd11",
            "dd00ee11",
        ], revision: 2, replace: false),
        2: .init(insert: ["c0be0d0a6"], delete: [
            "bb00cc11",
        ], revision: 3, replace: false),
        4: .init(insert: ["a379a6f6"], delete: [
            "aa00bb11",
        ], revision: 5, replace: false),
        5: .init(insert: ["aa55aa55"], delete: [
            "ffgghhzz",
        ], revision: 6, replace: true),
    ]

    func load<Request>(_ requestConfig: Request) async throws -> Request.Response where Request: APIClient.Request {
        if let loadRequestError {
            throw loadRequestError
        }

        switch requestConfig.requestType {
        case .hashPrefixSet(let configuration):
            return _hashPrefixesChangeSet(for: configuration.threatKind, revision: configuration.revision ?? 0) as! Request.Response
        case .filterSet(let configuration):
            return _filtersChangeSet(for: configuration.threatKind, revision: configuration.revision ?? 0) as! Request.Response
        case .matches(let configuration):
            return try matchesForHashPrefix(configuration.hashPrefix) as! Request.Response
        }
    }
    func _filtersChangeSet(for threatKind: MaliciousSiteProtection.ThreatKind, revision: Int) -> MaliciousSiteProtection.APIClient.Response.FiltersChangeSet {
        updateFilterSetsCalled?(revision)
        return filterRevisions[revision] ?? .init(insert: [], delete: [], revision: revision, replace: false)
    }

    func _hashPrefixesChangeSet(for threatKind: MaliciousSiteProtection.ThreatKind, revision: Int) -> MaliciousSiteProtection.APIClient.Response.HashPrefixesChangeSet {
        updateHashPrefixesCalled?(revision)
        return hashPrefixRevisions[revision] ?? .init(insert: [], delete: [], revision: revision, replace: false)
    }

    var matchesForHashPrefix: (String) throws -> APIClient.Response.Matches = { _ in
        .init(matches: [
            Match(hostname: "example.com", url: "https://example.com/mal", regex: ".*", hash: "a379a6f6eeafb9a55e378c118034e2751e682fab9f2d30ab13d2125586ce1947", category: "phishing"),
            Match(hostname: "test.com", url: "https://test.com/mal", regex: ".*test.*", hash: "aa00bb11aa00cc11bb00cc11", category: nil)
        ])
    }

}
