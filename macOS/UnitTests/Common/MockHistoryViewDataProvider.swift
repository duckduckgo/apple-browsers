//
//  MockHistoryViewDataProvider.swift
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

@MainActor
public class MockHistoryViewDataProvider: @preconcurrency HistoryViewDataProviding {

    public var date = Date()
    public var allVisits: [Visit] = []
    public var allHistoryEntries: [HistoryEntry] = []
    public var allCookieDomains: [String] = []
    public var fireproofedDomains: Set<String> = []

    public init() {}

    /// Configure the provider with specific test data for a test scenario
    public func configure(visits: [Visit] = [], cookieDomains: [String] = [], fireproofedDomains: Set<String> = []) {
        self.allVisits = visits
        self.allCookieDomains = cookieDomains
        self.fireproofedDomains = fireproofedDomains
    }

    public func visits(matching query: DataModel.HistoryQueryKind) async -> [Visit] {
        switch query {
        case .rangeFilter(.all), .rangeFilter(.allSites):
            return allVisits
        case .rangeFilter(.today):
            let today = Calendar.current.startOfDay(for: Date())
            return allVisits.filter { Calendar.current.startOfDay(for: $0.date) == today }
        case .rangeFilter(.yesterday):
            let yesterday = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
            return allVisits.filter { Calendar.current.startOfDay(for: $0.date) == yesterday }
        case .rangeFilter(.sunday), .rangeFilter(.monday), .rangeFilter(.tuesday), .rangeFilter(.wednesday), .rangeFilter(.thursday), .rangeFilter(.friday), .rangeFilter(.saturday):
            fatalError("Not implemented")
        case .rangeFilter(.older):
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return allVisits.filter { $0.date < sevenDaysAgo }
        case .dateFilter(let date):
            let targetDate = Calendar.current.startOfDay(for: date)
            return allVisits.filter { Calendar.current.startOfDay(for: $0.date) == targetDate }
        case .domainFilter(let domains):
            return allVisits.filter { domains.contains($0.identifier?.host ?? "") }
        case .searchTerm(let term):
            return allVisits.filter { $0.historyEntry?.title?.contains(term) == true || $0.identifier?.absoluteString.contains(term) == true }
        case .visits(let identifiers):
            return visits(for: identifiers)
        }
    }

    private func visits(for identifiers: [VisitIdentifier]) -> [History.Visit] {
        let identifiers = Set(identifiers.compactMap(\.url.url))
        return allVisits.filter { identifiers.contains($0.identifier ?? .empty) }
    }

    /// Helper to create realistic test data with various domains and dates
    public func configureWithTestData() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        let specificDate = ISO8601DateFormatter().date(from: "2024-05-15T12:00:00Z") ?? Date(timeIntervalSince1970: 1715774400)

        // Create comprehensive history entries for different domains and scenarios
        let acomEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://a.com")!, failedToLoad: false, numberOfTotalVisits: 4, lastVisit: today, visits: [], numberOfTrackersBlocked: 2, blockedTrackingEntities: [], trackersFound: true)
        let bcomEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://b.com")!, failedToLoad: false, numberOfTotalVisits: 3, lastVisit: today, visits: [], numberOfTrackersBlocked: 1, blockedTrackingEntities: [], trackersFound: true)
        let cookieEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://cook.ie")!, failedToLoad: false, numberOfTotalVisits: 1, lastVisit: today, visits: [], numberOfTrackersBlocked: 0, blockedTrackingEntities: [], trackersFound: false)
        let figmaEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://figma.com")!, failedToLoad: false, numberOfTotalVisits: 3, lastVisit: yesterday, visits: [], numberOfTrackersBlocked: 3, blockedTrackingEntities: [], trackersFound: true)
        let xcomEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://x.com")!, failedToLoad: false, numberOfTotalVisits: 3, lastVisit: today, visits: [], numberOfTrackersBlocked: 5, blockedTrackingEntities: [], trackersFound: true)
        let exampleEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://example.com")!, failedToLoad: false, numberOfTotalVisits: 2, lastVisit: twoDaysAgo, visits: [], numberOfTrackersBlocked: 0, blockedTrackingEntities: [], trackersFound: false)
        let testEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://test.com")!, failedToLoad: false, numberOfTotalVisits: 1, lastVisit: specificDate, visits: [], numberOfTrackersBlocked: 2, blockedTrackingEntities: [], trackersFound: true)
        let dateEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://date.com")!, failedToLoad: false, numberOfTotalVisits: 2, lastVisit: specificDate, visits: [], numberOfTrackersBlocked: 1, blockedTrackingEntities: [], trackersFound: true)
        let closemeEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://close.me")!, failedToLoad: false, numberOfTotalVisits: 1, lastVisit: today, visits: [], numberOfTrackersBlocked: 0, blockedTrackingEntities: [], trackersFound: false)
        let cEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://c.com")!, failedToLoad: false, numberOfTotalVisits: 2, lastVisit: twoDaysAgo, visits: [], numberOfTrackersBlocked: 1, blockedTrackingEntities: [], trackersFound: true)
        let zEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://z.com")!, failedToLoad: false, numberOfTotalVisits: 1, lastVisit: today, visits: [], numberOfTrackersBlocked: 0, blockedTrackingEntities: [], trackersFound: false)

        // Fireproofed domains - these should appear in selectable but not be deletable
        let duckduckgoEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://duckduckgo.com")!, failedToLoad: false, numberOfTotalVisits: 3, lastVisit: today, visits: [], numberOfTrackersBlocked: 0, blockedTrackingEntities: [], trackersFound: false)
        let githubEntry = HistoryEntry(identifier: UUID(), url: URL(string: "https://github.com")!, failedToLoad: false, numberOfTotalVisits: 2, lastVisit: yesterday, visits: [], numberOfTrackersBlocked: 1, blockedTrackingEntities: [], trackersFound: true)

        // Create comprehensive visits covering all test scenarios
        self.allVisits = [
            // Today visits - covers Fire Button, History Today, Main Menu Today scenarios
            Visit(date: today, identifier: acomEntry.url, historyEntry: acomEntry),      // a.com×2 today
            Visit(date: today, identifier: acomEntry.url, historyEntry: acomEntry),
            Visit(date: today, identifier: bcomEntry.url, historyEntry: bcomEntry),      // b.com×1 today
            Visit(date: today, identifier: cookieEntry.url, historyEntry: cookieEntry),  // cook.ie×1 today
            Visit(date: today, identifier: xcomEntry.url, historyEntry: xcomEntry),      // x.com×2 today
            Visit(date: today, identifier: xcomEntry.url, historyEntry: xcomEntry),
            Visit(date: today, identifier: closemeEntry.url, historyEntry: closemeEntry), // close.me×1 today
            Visit(date: today, identifier: zEntry.url, historyEntry: zEntry),            // z.com×1 today
            Visit(date: today, identifier: duckduckgoEntry.url, historyEntry: duckduckgoEntry), // duckduckgo.com×2 today (fireproofed)
            Visit(date: today, identifier: duckduckgoEntry.url, historyEntry: duckduckgoEntry),

            // Yesterday visits - covers History Yesterday scenarios
            Visit(date: yesterday, identifier: acomEntry.url, historyEntry: acomEntry),      // a.com×1 yesterday
            Visit(date: yesterday, identifier: figmaEntry.url, historyEntry: figmaEntry),    // figma.com×2 yesterday
            Visit(date: yesterday, identifier: figmaEntry.url, historyEntry: figmaEntry),
            Visit(date: yesterday, identifier: xcomEntry.url, historyEntry: xcomEntry),      // x.com×1 yesterday
            Visit(date: yesterday, identifier: githubEntry.url, historyEntry: githubEntry),  // github.com×1 yesterday (fireproofed)

            // Two days ago visits - covers cross-contamination validation
            Visit(date: twoDaysAgo, identifier: exampleEntry.url, historyEntry: exampleEntry), // example.com×1 two days ago
            Visit(date: twoDaysAgo, identifier: cEntry.url, historyEntry: cEntry),            // c.com×2 two days ago
            Visit(date: twoDaysAgo, identifier: cEntry.url, historyEntry: cEntry),

            // Specific date visits - covers History Date scenarios
            Visit(date: specificDate, identifier: dateEntry.url, historyEntry: dateEntry),    // date.com×2 on 2024-05-15
            Visit(date: specificDate, identifier: dateEntry.url, historyEntry: dateEntry),
            Visit(date: specificDate, identifier: bcomEntry.url, historyEntry: bcomEntry),    // b.com×1 on 2024-05-15
            Visit(date: specificDate, identifier: testEntry.url, historyEntry: testEntry)     // test.com×1 on 2024-05-15
        ]

        self.allHistoryEntries = [acomEntry, bcomEntry, cookieEntry, figmaEntry, xcomEntry, exampleEntry, testEntry, dateEntry, closemeEntry, cEntry, zEntry, duckduckgoEntry, githubEntry]

        // Set up cookie domains (domains that have stored cookies/site data)
        // Covers all domains that appear in tests, including fireproofed ones
        self.allCookieDomains = ["a.com", "b.com", "cook.ie", "figma.com", "x.com", "example.com", "test.com", "date.com", "close.me", "c.com", "z.com", "duckduckgo.com", "github.com"]

        // Set up fireproofed domains (these should not be deletable)
        self.fireproofedDomains = ["duckduckgo.com", "github.com"]
    }

    // MARK: - HistoryView.DataProviding methods
    public var ranges: [DataModel.HistoryRangeWithCount] { [] }

    public func refreshData() async {}

    public func visitsBatch(for query: DataModel.HistoryQueryKind, source: DataModel.HistoryQuerySource, limit: Int, offset: Int) async -> DataModel.HistoryItemsBatch {
        return DataModel.HistoryItemsBatch(finished: true, visits: [])
    }

    // MARK: - HistoryViewDataProviding methods
    public func titles(for urls: [URL]) -> [URL: String] {
        return [:]
    }

    public func deleteVisits(matching query: HistoryView.DataModel.HistoryQueryKind, and deleteChats: Bool) async {}
    public func burnVisits(matching query: HistoryView.DataModel.HistoryQueryKind, and burnChats: Bool) async {}

    public func cookieDomains(matching query: DataModel.HistoryQueryKind) async -> Set<String> {
        let visits = await visits(matching: query)
        let domains = Set(visits.map { $0.historyEntry!.url.host! })
        return domains.intersection(Set(allCookieDomains))
    }

    public func preferredURL(forSiteDomain domain: String) -> URL? {
        return URL(string: "https://\(domain)")
    }
}
