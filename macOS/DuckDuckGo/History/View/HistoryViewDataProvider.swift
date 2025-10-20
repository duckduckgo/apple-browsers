//
//  HistoryViewDataProvider.swift
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

import AppKit
import BrowserServicesKit
import Common
import Foundation
import History
import HistoryView
import PixelKit

protocol HistoryDeleting: AnyObject {
    func delete(_ visits: [Visit]) async
}

protocol HistoryDataSource: HistoryGroupingDataSource, HistoryDeleting {
    var historyDictionary: [URL: HistoryEntry]? { get }
}

extension HistoryCoordinator: HistoryDataSource {
    func delete(_ visits: [Visit]) async {
        await withCheckedContinuation { continuation in
            burnVisits(visits) {
                continuation.resume()
            }
        }
    }
}

struct HistoryViewGrouping {
    let range: DataModel.HistoryRange
    let items: [DataModel.HistoryItem]

    init(range: DataModel.HistoryRange, visits: [DataModel.HistoryItem]) {
        self.range = range
        self.items = visits
    }

    init?(_ historyGrouping: HistoryGrouping, dateFormatter: HistoryViewDateFormatting) {
        guard let range = DataModel.HistoryRange(date: historyGrouping.date, referenceDate: dateFormatter.currentDate()) else {
            return nil
        }
        self.range = range
        items = historyGrouping.visits.compactMap { DataModel.HistoryItem($0, dateFormatter: dateFormatter) }
    }
}

protocol HistoryViewDataProviding: HistoryView.DataProviding {

    func titles(for urls: [URL]) -> [URL: String]

    func deleteVisits(matching query: DataModel.HistoryQueryKind, and deleteChats: Bool) async
    func burnVisits(matching query: DataModel.HistoryQueryKind, and burnChats: Bool) async

    /// Get actual visits for a given query (used for burning specific visits)
    func visits(matching query: DataModel.HistoryQueryKind) async -> [Visit]

    /// Representative URL for a given eTLD+1 domain, preferring HTTPS and most recent visit.
    @MainActor func preferredURL(forSiteDomain domain: String) -> URL?
}

extension HistoryViewDataProviding {
    func deleteVisits(matching query: DataModel.HistoryQueryKind) async {
        await deleteVisits(matching: query, and: false)
    }
}

final class HistoryViewDataProvider: HistoryViewDataProviding {

    private let featureFlagger: FeatureFlagger
    private let tld: TLD

    init(
        historyDataSource: HistoryDataSource,
        historyBurner: HistoryBurning,
        dateFormatter: HistoryViewDateFormatting = DefaultHistoryViewDateFormatter(),
        featureFlagger: FeatureFlagger,
        pixelHandler: HistoryViewDataProviderPixelFiring = HistoryViewDataProviderPixelHandler(),
        tld: TLD
    ) {
        self.dateFormatter = dateFormatter
        self.historyDataSource = historyDataSource
        self.historyBurner = historyBurner
        self.featureFlagger = featureFlagger
        self.pixelHandler = pixelHandler
        self.tld = tld
        historyGroupingProvider = { @MainActor in
            HistoryGroupingProvider(dataSource: historyDataSource, featureFlagger: featureFlagger)
        }
    }

    var ranges: [DataModel.HistoryRangeWithCount] {
        let ranges = DataModel.HistoryRange.displayedRanges(for: dateFormatter.currentDate())
        let rangesWithCounts = ranges.map { DataModel.HistoryRangeWithCount(id: $0, count: groupingsByRange[$0]?.items.count ?? 0) }

        // Remove all empty ranges from the end of the array
        var filteredRanges = Array(rangesWithCounts.reversed().drop(while: { visitsByRange[$0.id]?.isEmpty != false }).reversed())
        // All = total number of history items (exclude synthetic 'sites')
        filteredRanges.insert(.init(id: .all, count: groupingsByRange.values.compactMap {
            guard $0.range != .allSites else { return nil }
            return $0.items.count
        }.reduce(0, +)), at: 0)

        // Sites = unique domains count (items in synthetic 'sites' section)
        if isSitesSectionEnabled {
            assert(AppVersion.runType != .normal, "Enable History View Sites Section Deletion UI Tests and remove the assertion")
            let sitesCount = groupingsByRange[.allSites]?.items.count ?? uniqueETLDPlus1Domains().count
            filteredRanges.append(.init(id: .allSites, count: sitesCount))
        }
        return filteredRanges
    }

    func refreshData() async {
        lastQuery = nil
        await populateVisits()
    }

    func visitsBatch(for query: DataModel.HistoryQueryKind, source: DataModel.HistoryQuerySource, limit: Int, offset: Int) async -> DataModel.HistoryItemsBatch {
        if source == .user && offset == 0 {
            pixelHandler.fireFilterUpdatedPixel(query)
        }
        let items = await perform(query)
        let visits = items.chunk(with: limit, offset: offset)
        let finished = offset + limit >= items.count
        return DataModel.HistoryItemsBatch(finished: finished, visits: visits)
    }

    func deleteVisits(matching query: DataModel.HistoryQueryKind, and deleteChats: Bool) async {
        let visits = await allVisits(matching: query)
        await historyDataSource.delete(visits)
        if deleteChats {
            await historyBurner.burnChats()
        }
        await refreshData()
    }

    func burnVisits(matching query: DataModel.HistoryQueryKind, and burnChats: Bool) async {
        guard query != .rangeFilter(.all) || !burnChats else {
            await historyBurner.burnAll()
            await refreshData()
            return
        }
        let visits = await allVisits(matching: query)

        guard !visits.isEmpty else { return }

        let animated = query == .rangeFilter(.today)
        await historyBurner.burn(visits, and: burnChats, animated: animated)
        await refreshData()
    }

    func titles(for urls: [URL]) -> [URL: String] {
        guard let historyDictionary = historyDataSource.historyDictionary else {
            return [:]
        }

        return urls.reduce(into: [URL: String]()) { partialResult, url in
            partialResult[url] = historyDictionary[url]?.title
        }
    }

    func bestTitle(forSiteDomain domain: String) -> String {
        guard let historyDictionary = historyDataSource.historyDictionary else {
            return domain
        }

        // Collect all entries that belong to this eTLD+1 domain
        let entries: [HistoryEntry] = historyDictionary.values.filter { entry in
            let entryDomain = entry.etldPlusOne ?? entry.url.host
            return entryDomain == domain
        }

        guard !entries.isEmpty else {
            return domain
        }

        // Helper to get last visit date for an entry
        func lastVisitDate(of entry: HistoryEntry) -> Date? {
            entry.visits.map(\.date).max()
        }

        // Prefer index page records at root path on bare domain or www subdomain
        let rootHosts: Set<String> = [domain, "www." + domain]
        let rootCandidates: [HistoryEntry] = entries.filter { entry in
            let hostMatches = (entry.url.host.map { rootHosts.contains($0) } ?? false)
            let path = entry.url.path
            let isRootPath = path.isEmpty || path == "/"
            return hostMatches && isRootPath
        }

        if let bestRoot = rootCandidates
            .sorted(by: { a, b in
                // Prefer HTTPS, then by most recent visit
                if a.url.scheme == "https", b.url.scheme != "https" { return true }
                if a.url.scheme != "https", b.url.scheme == "https" { return false }
                return (lastVisitDate(of: a) ?? .distantPast) > (lastVisitDate(of: b) ?? .distantPast)
            })
                .first {
            if let title = bestRoot.title, !title.isEmpty {
                return title
            }
            // Fallback to URL string if title missing
            return bestRoot.url.absoluteString
        }

        // Otherwise pick the most recent visit title within this domain
        if let mostRecent = entries.max(by: { (lastVisitDate(of: $0) ?? .distantPast) < (lastVisitDate(of: $1) ?? .distantPast) }) {
            if let title = mostRecent.title, !title.isEmpty {
                return title
            }
            return mostRecent.url.absoluteString
        }

        return domain
    }

    @MainActor
    func preferredURL(forSiteDomain domain: String) -> URL? {
        guard let historyDictionary = historyDataSource.historyDictionary else { return nil }

        let entries: [HistoryEntry] = historyDictionary.values.filter { entry in
            let entryDomain = entry.etldPlusOne ?? entry.url.host
            return entryDomain == domain
        }
        guard !entries.isEmpty else { return URL(string: "https://\(domain)") }

        func lastVisitDate(of entry: HistoryEntry) -> Date? { entry.visits.map(\.date).max() }

        let sorted = entries.sorted { a, b in
            if a.url.scheme == "https", b.url.scheme != "https" { return true }
            if a.url.scheme != "https", b.url.scheme == "https" { return false }
            return (lastVisitDate(of: a) ?? .distantPast) > (lastVisitDate(of: b) ?? .distantPast)
        }
        return sorted.first?.url
    }

    // MARK: - Private

    @MainActor
    private func populateVisits() async {
        var olderHistoryItems = [DataModel.HistoryItem]()
        var olderVisits = [Visit]()

        visitsByRange.removeAll()
        historyItems.removeAll()

        // generate groupings by day and set aside "older" days.
        groupingsByRange = await historyGroupingProvider().getVisitGroupings()
            .reduce(into: [DataModel.HistoryRange: HistoryViewGrouping]()) { partialResult, historyGrouping in
                guard let grouping = HistoryViewGrouping(historyGrouping, dateFormatter: dateFormatter) else {
                    return
                }
                guard grouping.range != .older else {
                    olderHistoryItems.append(contentsOf: grouping.items)
                    olderVisits.append(contentsOf: historyGrouping.visits)
                    return
                }
                visitsByRange[grouping.range] = historyGrouping.visits
                partialResult[grouping.range] = grouping
                historyItems.append(contentsOf: grouping.items)
            }

        // collect all "older" days into a single grouping
        if !olderHistoryItems.isEmpty {
            groupingsByRange[.older] = .init(range: .older, visits: olderHistoryItems)
            historyItems.append(contentsOf: olderHistoryItems)
        }
        if !olderVisits.isEmpty {
            visitsByRange[.older] = olderVisits
        }

        // Populate synthetic 'sites' section with one item per unique eTLD+1 domain
        if isSitesSectionEnabled {
            let domains = uniqueETLDPlus1Domains()
            let siteItems: [DataModel.HistoryItem] = domains.compactMap { domain in
                guard let url = preferredURL(forSiteDomain: domain) else { return nil }
                let title = bestTitle(forSiteDomain: domain)
                return DataModel.HistoryItem(siteDomain: domain, url: url, title: title)
            }
            groupingsByRange[.allSites] = .init(range: .allSites, visits: siteItems)
        } else {
            groupingsByRange[.allSites] = nil
        }
    }

    func visits(matching query: DataModel.HistoryQueryKind) async -> [Visit] {
        return await allVisits(matching: query)
    }

    private func allVisits(matching query: DataModel.HistoryQueryKind) async -> [Visit] {
        switch query {
        case .searchTerm(let searchTerm):
            return await allVisits(matching: searchTerm)
        case .domainFilter(let domains):
            return await allVisits(matchingDomains: domains)
        case .rangeFilter(let range):
            return await allVisits(for: range)
        case .dateFilter(let date):
            return await allVisits(for: date)
        case .visits(let identifiers):
            return await visits(for: identifiers)
        }
    }

    func allVisits(for range: DataModel.HistoryRange) async -> [Visit] {
        guard let history = await fetchHistory() else {
            return []
        }
        let date = lastQuery?.date ?? dateFormatter.currentDate()

        let allVisits: [Visit] = history.flatMap(\.visits)
        guard let dateRange = range.dateRange(for: date) else {
            return allVisits
        }
        return allVisits.filter { dateRange.contains($0.date) }
    }

    func allVisits(for date: Date) async -> [Visit] {
        guard let history = await fetchHistory() else {
            return []
        }

        let allVisits: [Visit] = history.flatMap(\.visits)
        let dateRange = date.startOfDay..<date.daysAgo(-1).startOfDay
        return allVisits.filter { dateRange.contains($0.date) }
    }

    private func allVisits(matching searchTerm: String) async -> [Visit] {
        guard let history = await fetchHistory() else {
            return []
        }

        return history.reduce(into: [Visit]()) { partialResult, historyEntry in
            if historyEntry.matches(searchTerm) {
                partialResult.append(contentsOf: historyEntry.visits)
            }
        }
    }

    private func allVisits(matchingDomains domains: Set<String>) async -> [Visit] {
        guard let history = await fetchHistory() else {
            return []
        }

        return history.reduce(into: [Visit]()) { partialResult, historyEntry in
            if historyEntry.matchesDomains(domains) {
                partialResult.append(contentsOf: historyEntry.visits)
            }
        }
    }

    /**
     * Fetches all visits matching given `identifiers`.
     *
     * This function is used for deleting items in History View. Items in history view
     * are deduplicated by day, so if an item is requested to be deleted, we have to
     * find and delete all visits matching that item for a given day (because only
     * the newest one on a given day is shown in the History View).
     *
     * The procedure here is to go through all identifiers and retrieve visits from history
     * that match identifier's URL and are on the same date as identifier's date.
     */
    private func visits(for identifiers: [VisitIdentifier]) async -> [Visit] {
        guard let historyDictionary = historyDataSource.historyDictionary else {
            return []
        }

        return identifiers.reduce(into: [Visit]()) { partialResult, identifier in
            guard let visitsForIdentifier = historyDictionary[identifier.url.url ?? .empty]?.visits else {
                return
            }
            let visitsMatchingDay = visitsForIdentifier.filter { $0.date.isSameDay(identifier.date) }
            partialResult.append(contentsOf: visitsMatchingDay)
        }
    }

    /**
     * This function is here to ensure that history is accessed on the main thread.
     *
     * `HistoryCoordinator` uses `dispatchPrecondition(condition: .onQueue(.main))` internally.
     */
    @MainActor
    private func fetchHistory() async -> BrowsingHistory? {
        historyDataSource.history
    }

    private func perform(_ query: DataModel.HistoryQueryKind) async -> [DataModel.HistoryItem] {
        if let lastQuery, lastQuery.query == query {
            return lastQuery.items
        }

        await refreshData()

        let items: [DataModel.HistoryItem] = await {
            switch query {
            case .rangeFilter(.all), .searchTerm(""):
                return historyItems
            case .rangeFilter(let range):
                return groupingsByRange[range]?.items ?? []
            case .dateFilter(let date):
                let range = DataModel.HistoryRange(date: date, referenceDate: dateFormatter.currentDate()) ?? {
                    assertionFailure("Failed to create HistoryRange for date: \(date)")
                    return .older
                }()
                return groupingsByRange[range]?.items ?? []
            case .searchTerm(let term):
                return historyItems.filter { $0.matches(term) }
            case .domainFilter(let domains) where domains.isEmpty:
                return historyItems
            case .domainFilter(let domains):
                return historyItems.filter { $0.matchesDomains(domains) }
            case .visits(let identifiers):
                let visits = await visits(for: identifiers)
                let domains = Set(visits.compactMap { $0.historyEntry?.url.host })
                return historyItems.filter { historyItem in
                    historyItem.matchesDomains(domains)
                }
            }
        }()

        lastQuery = .init(date: dateFormatter.currentDate(), query: query, items: items)
        return items
    }

    /// This is an async accessor in order to be able to feed it with `NSApp.delegateTyped.featureFlagger`
    /// Could be refactored into a simple property once the feture flag is removed.
    private let historyGroupingProvider: () async -> HistoryGroupingProvider
    private let historyDataSource: HistoryDataSource
    private let dateFormatter: HistoryViewDateFormatting
    private let historyBurner: HistoryBurning

    private var groupingsByRange: [DataModel.HistoryRange: HistoryViewGrouping] = [:]
    private var historyItems: [DataModel.HistoryItem] = []

    private var visitsByRange: [DataModel.HistoryRange: [Visit]] = [:]

    private var isSitesSectionEnabled: Bool {
        featureFlagger.isFeatureOn(.historyViewSitesSection)
    }

    private func uniqueETLDPlus1Domains() -> [String] {
        guard let history = historyDataSource.historyDictionary else { return [] }
        let etldPlus1Domains = history.keys.convertedToETLDPlus1(tld: tld)
        return etldPlus1Domains.sorted()
    }

    private struct QueryInfo {
        /// When the query happened.
        let date: Date
        /// What was the query.
        let query: DataModel.HistoryQueryKind
        /// Query result (a subset of `HistoryViewDataProvider.historyItems`)
        let items: [DataModel.HistoryItem]
    }

    /// The last query from the FE, i.e. filtered items list.
    private var lastQuery: QueryInfo?
    private let pixelHandler: HistoryViewDataProviderPixelFiring
}

protocol SearchableHistoryEntry {
    func matches(_ searchTerm: String) -> Bool
}

extension HistoryEntry: SearchableHistoryEntry {
    /**
     * Search term matching checks title and URL (case insensitive).
     */
    func matches(_ searchTerm: String) -> Bool {
        (title ?? "").localizedCaseInsensitiveContains(searchTerm) || url.absoluteString.localizedCaseInsensitiveContains(searchTerm)
    }

    /**
     * Domain matching is done by etld+1.
     *
     * This means that that `example.com` would match all of the following:
     * - `example.com`
     * - `www.example.com`
     * - `www.cdn.example.com`
     */
    func matchesDomains(_ domains: Set<String>) -> Bool {
        guard let host = etldPlusOne ?? url.host else { return false }
        return domains.contains(host)
    }
}

extension HistoryView.DataModel.HistoryItem: SearchableHistoryEntry {
    func matches(_ searchTerm: String) -> Bool {
        title.localizedCaseInsensitiveContains(searchTerm) || url.localizedCaseInsensitiveContains(searchTerm)
    }

    func matchesDomains(_ domains: Set<String>) -> Bool {
        return domains.contains(etldPlusOne ?? self.domain)
    }
}

extension HistoryView.DataModel.HistoryItem {
    /**
     * This initializer converts native side history `Visit` into FE `HistoryItem` model.
     *
     * It uses a date formatter because `HistoryItem` models are dumb and are expected
     * to contain user-visible text instead of timestamps.
     */
    init?(_ visit: Visit, dateFormatter: HistoryViewDateFormatting) {
        guard let historyEntry = visit.historyEntry else {
            return nil
        }
        let title: String = {
            guard let title = historyEntry.title, !title.isEmpty else {
                return historyEntry.url.absoluteString
            }
            return title
        }()

        let favicon: DataModel.Favicon? = {
            guard let url = visit.historyEntry?.url, let src = URL.duckFavicon(for: url)?.absoluteString else {
                return nil
            }
            return .init(maxAvailableSize: Int(Favicon.SizeCategory.small.rawValue), src: src)
        }()

        self.init(
            id: VisitIdentifier(historyEntry: historyEntry, date: visit.date).description,
            url: historyEntry.url.absoluteString,
            title: title,
            domain: historyEntry.url.host ?? historyEntry.url.absoluteString,
            etldPlusOne: historyEntry.etldPlusOne,
            dateRelativeDay: dateFormatter.dayString(for: visit.date),
            dateShort: "", // not in use at the moment
            dateTimeOfDay: dateFormatter.timeString(for: visit.date),
            favicon: favicon
        )
    }

    /// Synthetic initializer that allows overriding the display title for Sites section
    init(siteDomain: String, url: URL, title: String?) {
        let favicon: DataModel.Favicon? = {
            if let src = URL.duckFavicon(for: url)?.absoluteString {
                return .init(maxAvailableSize: Int(Favicon.SizeCategory.small.rawValue), src: src)
            }
            return nil
        }()
        let displayTitle = (title?.isEmpty == false) ? title! : siteDomain
        self.init(
            id: "site:\(siteDomain)",
            url: url.absoluteString,
            title: displayTitle,
            domain: siteDomain,
            etldPlusOne: siteDomain,
            dateRelativeDay: UserText.historySitesLabel,
            dateShort: "",
            dateTimeOfDay: "",
            favicon: favicon
        )
    }
}
extension VisitIdentifier {
    init(historyEntry: HistoryEntry, date: Date) {
        self.init(uuid: historyEntry.identifier.uuidString,
                  url: historyEntry.url,
                  date: date)

    }
}
