//
//  CapturingHistoryViewDataProvider.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import History
import HistoryView

@testable import DuckDuckGo_Privacy_Browser

final class CapturingHistoryViewDataProvider: HistoryViewDataProviding {

    var ranges: [DataModel.HistoryRangeWithCount] {
        rangesCallCount += 1
        return _ranges
    }

    func refreshData() {
        resetCacheCallCount += 1
    }

    func visitsBatch(for query: DataModel.HistoryQueryKind, source: DataModel.HistoryQuerySource, limit: Int, offset: Int) async -> DataModel.HistoryItemsBatch {
        visitsBatchCalls.append(.init(query: query, source: source, limit: limit, offset: offset))
        return await visitsBatch(query, source, limit, offset)
    }

    func deleteVisits(for identifiers: [VisitIdentifier]) async {
        deleteVisitsForIdentifierCalls.append(identifiers)
    }

    func burnVisits(for identifiers: [VisitIdentifier]) async {
        burnVisitsForIdentifiersCalls.append(identifiers)
    }

    func countVisibleVisits(matching query: DataModel.HistoryQueryKind) async -> Int {
        countVisibleVisitsCalls.append(query)
        return await countVisibleVisits(query)
    }

    func deleteVisits(matching query: DataModel.HistoryQueryKind) async {
        deleteVisitsMatchingQueryCalls.append(query)
    }

    func burnVisits(matching query: DataModel.HistoryQueryKind) async {
        burnVisitsMatchingQueryCalls.append(query)
    }

    func titles(for urls: [URL]) -> [URL: String] {
        titlesForURLsCalls.append(urls)
        return titlesForURLs(urls)
    }

    func cookieDomains(matching query: DataModel.HistoryQueryKind) async -> Set<String> {
        cookieDomainsMatchingQueryCalls.append(query)
        return await cookieDomainsMatchingQuery(query)
    }

    func cookieDomains(for identifiers: [VisitIdentifier]) async -> Set<String> {
        cookieDomainsForIdentifiersCalls.append(identifiers)
        return await cookieDomainsForIdentifiers(identifiers)
    }

    func visits(matching query: DataModel.HistoryQueryKind) async -> [Visit] {
        visitsMatchingQueryCalls.append(query)
        return await visitsMatchingQuery(query)
    }

    func visits(for identifiers: [DuckDuckGo_Privacy_Browser.VisitIdentifier]) async -> [History.Visit] {
        visitsForIdentifiersCalls.append(identifiers)
        return await visitsForIdentifiers(identifiers)
    }

    func preferredURL(forSiteDomain domain: String) -> URL? {
        URL(string: "https://\(domain)")
    }

    // Removed dialog-result forwarding: this is now handled by FireCoordinator

    // swiftlint:disable:next identifier_name
    var _ranges: [DataModel.HistoryRangeWithCount] = []
    var rangesCallCount: Int = 0
    var resetCacheCallCount: Int = 0

    var countVisibleVisitsCalls: [DataModel.HistoryQueryKind] = []
    var countVisibleVisits: (DataModel.HistoryQueryKind) async -> Int = { _ in return 0 }

    var deleteVisitsMatchingQueryCalls: [DataModel.HistoryQueryKind] = []
    var burnVisitsMatchingQueryCalls: [DataModel.HistoryQueryKind] = []

    var deleteVisitsForIdentifierCalls: [[VisitIdentifier]] = []
    var burnVisitsForIdentifiersCalls: [[VisitIdentifier]] = []

    var visitsBatchCalls: [VisitsBatchCall] = []
    var visitsBatch: (DataModel.HistoryQueryKind, DataModel.HistoryQuerySource, Int, Int) async -> DataModel.HistoryItemsBatch = { _, _, _, _ in .init(finished: true, visits: []) }

    var titlesForURLsCalls: [[URL]] = []
    var titlesForURLs: ([URL]) -> [URL: String] = { _ in [:] }

    var cookieDomainsMatchingQueryCalls: [DataModel.HistoryQueryKind] = []
    var cookieDomainsMatchingQuery: (DataModel.HistoryQueryKind) async -> Set<String> = { _ in return [] }

    var cookieDomainsForIdentifiersCalls: [[VisitIdentifier]] = []
    var cookieDomainsForIdentifiers: ([VisitIdentifier]) async -> Set<String> = { _ in return [] }

    var visitsMatchingQueryCalls: [DataModel.HistoryQueryKind] = []
    var visitsMatchingQuery: (DataModel.HistoryQueryKind) async -> [Visit] = { _ in return [] }

    var visitsForIdentifiersCalls: [[DuckDuckGo_Privacy_Browser.VisitIdentifier]] = []
    var visitsForIdentifiers: ([DuckDuckGo_Privacy_Browser.VisitIdentifier]) async -> [Visit] = { _ in return [] }

    // Removed call capture for dialog-result forwarding

    struct VisitsBatchCall: Equatable {
        let query: DataModel.HistoryQueryKind
        let source: DataModel.HistoryQuerySource
        let limit: Int
        let offset: Int
    }
}
