//
//  IncrementallyUpdatableDataSet.swift
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

protocol IncrementallyUpdatableDataSet: Codable, Equatable {
    /// Set Element Type (Hash Prefix or Filter)
    associatedtype Element: Codable, Hashable
    /// API Request type used to fetch updates for the data set
    associatedtype APIRequest: APIClient.ChangeSetRequest where APIRequest.Response == APIClient.ChangeSetResponse<Element>

    var revision: Int { get set }

    init(revision: Int, items: some Sequence<Element>)

    mutating func subtract<Seq: Sequence>(_ itemsToDelete: Seq) where Seq.Element == Element
    mutating func formUnion<Seq: Sequence>(_ itemsToAdd: Seq) where Seq.Element == Element

    /// Apply ChangeSet from local data revision to actual revision loaded from API
    mutating func apply(_ changeSet: APIClient.ChangeSetResponse<Element>)
}

extension IncrementallyUpdatableDataSet {
    mutating func apply(_ changeSet: APIClient.ChangeSetResponse<Element>) {
        if changeSet.replace {
            self = .init(revision: changeSet.revision, items: changeSet.insert)
        } else {
            self.subtract(changeSet.delete)
            self.formUnion(changeSet.insert)
            self.revision = changeSet.revision
        }
    }
}

extension HashPrefixSet: IncrementallyUpdatableDataSet {
    typealias Element = String
    typealias APIRequest = APIRequestType.HashPrefixes

    static func apiRequest(for threatKind: ThreatKind, revision: Int) -> APIRequest {
        .hashPrefixes(threatKind: threatKind, revision: revision)
    }
}

extension FilterDictionary: IncrementallyUpdatableDataSet {
    typealias Element = Filter
    typealias APIRequest = APIRequestType.FilterSet

    init(revision: Int, items: some Sequence<Filter>) {
        let filtersDictionary = items.reduce(into: [String: Set<String>]()) { result, filter in
            result[filter.hash, default: []].insert(filter.regex)
        }
        self.init(revision: revision, filters: filtersDictionary)
    }

    static func apiRequest(for threatKind: ThreatKind, revision: Int) -> APIRequest {
        .filterSet(threatKind: threatKind, revision: revision)
    }
}
