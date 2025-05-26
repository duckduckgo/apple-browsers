//
//  MockMaliciousSiteProtectionEmbeddedDataProvider.swift
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

final class MockMaliciousSiteProtectionEmbeddedDataProvider: MaliciousSiteProtection.EmbeddedDataProviding {
    var embeddedRevision: Int = 65
    var loadHashPrefixesCalled: Bool = false
    var loadFilterSetCalled: Bool = true
    var hashPrefixes: Set<String> = [] {
        didSet {
            hashPrefixesData = try! JSONEncoder().encode(hashPrefixes)
        }
    }
    var hashPrefixesData: Data!

    var filterSet: Set<Filter> = [] {
        didSet {
            filterSetData = try! JSONEncoder().encode(filterSet)
        }
    }
    var filterSetData: Data!

    init() {
        hashPrefixes = Set(["aabb"])
        filterSet = Set([Filter(hash: "dummyhash", regex: "dummyregex")])
    }

    func revision(for detectionKind: MaliciousSiteProtection.DataManager.StoredDataType) -> Int {
        embeddedRevision
    }

    func url(for dataType: MaliciousSiteProtection.DataManager.StoredDataType) -> URL {
        switch dataType {
        case .filterSet:
            self.loadFilterSetCalled = true
            return URL(string: "filterSet")!
        case .hashPrefixSet:
            self.loadHashPrefixesCalled = true
            return URL(string: "hashPrefixSet")!
        }
    }

    func hash(for dataType: MaliciousSiteProtection.DataManager.StoredDataType) -> String {
        let url = url(for: dataType)
        let data = try! data(withContentsOf: url)
        let sha = data.sha256
        return sha
    }

    func data(withContentsOf url: URL) throws -> Data {
        switch url.absoluteString {
        case "filterSet":
            self.loadFilterSetCalled = true
            return filterSetData
        case "hashPrefixSet":
            self.loadHashPrefixesCalled = true
            return hashPrefixesData
        default:
            fatalError("Unexpected url \(url.absoluteString)")
        }
    }

}
