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

    func preferredURL(forSiteDomain domain: String) -> URL? {
        URL(string: "https://\(domain)")
    }

    // Removed dialog-result forwarding: this is now handled by FireCoordinator

    // swiftlint:disable:next identifier_name
    var _ranges: [DataModel.HistoryRangeWithCount] = []
    var rangesCallCount: Int = 0
    var resetCacheCallCount: Int = 0

    var deleteVisitsMatchingQueryCalls: [DataModel.HistoryQueryKind] = []
    var burnVisitsMatchingQueryCalls: [DataModel.HistoryQueryKind] = []

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

    struct VisitsBatchCall: Equatable {
        let query: DataModel.HistoryQueryKind
        let source: DataModel.HistoryQuerySource
        let limit: Int
        let offset: Int
    }
}

extension CapturingHistoryViewDataProvider {

    /// Generate deterministic test data and return it.
    /// - Parameters:
    ///   - domainsCount: Number of distinct domains to generate (minimum 1).
    ///   - visitsPerDomain: Number of visits to generate per domain (minimum 1).
    /// - Returns: Tuple with generated entries and visits.
    @MainActor
    func configureWithGeneratedTestData(domainsCount: Int, visitsPerDomain: Int) -> (historyEntries: [HistoryEntry], visits: [Visit]) {
        let domainCount = max(1, domainsCount)
        let perDomain = max(1, visitsPerDomain)

        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        let dayBuckets: [Date] = [today, yesterday, twoDaysAgo]

        // Domains: site1.com, site2.com, ...
        let domains: [String] = (1...domainCount).map { "site\($0).com" }

        // Build entries and visits
        var entries: [HistoryEntry] = []
        var visits: [Visit] = []
        var titlesByURL: [URL: String] = [:]

        for (idx, domain) in domains.enumerated() {
            let lastVisit = dayBuckets[idx % dayBuckets.count]
            let url = URL(string: "https://\(domain)")!
            let title = "\(domain) Home"
            var entry = HistoryEntry(identifier: UUID(), url: url, failedToLoad: false, numberOfTotalVisits: perDomain, lastVisit: lastVisit, visits: [], numberOfTrackersBlocked: 0, blockedTrackingEntities: [], trackersFound: false)
            entry.title = title
            entries.append(entry)
            titlesByURL[url] = title

            for i in 0..<perDomain {
                let d = dayBuckets[i % dayBuckets.count]
                visits.append(Visit(date: d, identifier: url, historyEntry: entry))
            }
        }

        return (entries, visits)
    }
}
