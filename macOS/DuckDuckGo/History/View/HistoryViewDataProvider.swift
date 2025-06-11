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

import BrowserServicesKit
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

    func countVisibleVisits(matching query: DataModel.HistoryQueryKind) async -> Int
    func deleteVisits(for identifiers: [VisitIdentifier]) async
    func burnVisits(for identifiers: [VisitIdentifier]) async
}

final class HistoryViewDataProvider: HistoryViewDataProviding {

    init(
        historyDataSource: HistoryDataSource,
        historyBurner: HistoryBurning,
        dateFormatter: HistoryViewDateFormatting = DefaultHistoryViewDateFormatter(),
        featureFlagger: FeatureFlagger? = nil,
        pixelHandler: HistoryViewDataProviderPixelFiring = HistoryViewDataProviderPixelHandler()
    ) {
        self.dateFormatter = dateFormatter
        self.historyDataSource = historyDataSource
        self.historyBurner = historyBurner
        self.pixelHandler = pixelHandler
        historyGroupingProvider = { @MainActor in
            HistoryGroupingProvider(dataSource: historyDataSource, featureFlagger: featureFlagger ?? NSApp.delegateTyped.featureFlagger)
        }
    }

    var ranges: [DataModel.HistoryRangeWithCount] {
        let ranges = DataModel.HistoryRange.displayedRanges(for: dateFormatter.currentDate())
        let rangesWithCounts = ranges.map { DataModel.HistoryRangeWithCount(id: $0, count: groupingsByRange[$0]?.items.count ?? 0) }

        // Remove all empty ranges from the end of the array
        var filteredRanges = Array(rangesWithCounts.reversed().drop(while: { visitsByRange[$0.id]?.isEmpty != false }).reversed())
        filteredRanges.insert(.init(id: .all, count: groupingsByRange.values.map(\.items.count).reduce(0, +)), at: 0)
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

    func countVisibleVisits(matching query: DataModel.HistoryQueryKind) async -> Int {
        guard let lastQuery, lastQuery.query == query else {
            let items = await perform(query)
            return items.count
        }
        return lastQuery.items.count
    }

    func deleteVisits(matching query: DataModel.HistoryQueryKind) async {
        let visits = await allVisits(matching: query)
        await historyDataSource.delete(visits)
        await refreshData()
    }

    func burnVisits(matching query: DataModel.HistoryQueryKind) async {
        guard query != .rangeFilter(.all) else {
            await historyBurner.burnAll()
            await refreshData()
            return
        }
        let visits = await allVisits(matching: query)

        guard !visits.isEmpty else {
            return
        }

        let animated = query == .rangeFilter(.today)
        await historyBurner.burn(visits, animated: animated)
        await refreshData()
    }

    func deleteVisits(for identifiers: [VisitIdentifier]) async {
        let visits = await visits(for: identifiers)
        await historyDataSource.delete(visits)
        await refreshData()
    }

    func burnVisits(for identifiers: [VisitIdentifier]) async {
        let visits = await visits(for: identifiers)
        await historyBurner.burn(visits, animated: false)
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
    }

    private func allVisits(matching query: DataModel.HistoryQueryKind) async -> [Visit] {
        switch query {
        case .searchTerm(let searchTerm):
            return await allVisits(matching: searchTerm)
        case .domainFilter(let domain):
            return await allVisits(matchingDomain: domain)
        case .rangeFilter(let range):
            return await allVisits(for: range)
        }
    }

    private func allVisits(for range: DataModel.HistoryRange) async -> [Visit] {
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

    private func allVisits(matchingDomain domain: String) async -> [Visit] {
        guard let history = await fetchHistory() else {
            return []
        }

        return history.reduce(into: [Visit]()) { partialResult, historyEntry in
            if historyEntry.matchesDomain(domain) {
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
            guard let visitsForIdentifier = historyDictionary[identifier.url]?.visits else {
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

        let items: [DataModel.HistoryItem] = {
            switch query {
            case .rangeFilter(.all), .searchTerm(""), .domainFilter(""):
                return historyItems
            case .rangeFilter(let range):
                return groupingsByRange[range]?.items ?? []
            case .searchTerm(let term):
                return historyItems.filter { $0.matches(term) }
            case .domainFilter(let domain):
                return historyItems.filter { $0.matchesDomain(domain) }
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
    func matchesDomain(_ domain: String) -> Bool
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
    func matchesDomain(_ domain: String) -> Bool {
        (etldPlusOne ?? url.host) == domain
    }
}

extension HistoryView.DataModel.HistoryItem: SearchableHistoryEntry {
    func matches(_ searchTerm: String) -> Bool {
        title.localizedCaseInsensitiveContains(searchTerm) || url.localizedCaseInsensitiveContains(searchTerm)
    }

    func matchesDomain(_ domain: String) -> Bool {
        (etldPlusOne ?? self.domain) == domain
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
}
