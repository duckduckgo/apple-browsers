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

protocol HistoryBurning: AnyObject {
    func burn(_ visits: [Visit], animated: Bool) async
}

final class FireHistoryBurner: HistoryBurning {
    let fireproofDomains: DomainFireproofStatusProviding
    let fire: () async -> Fire

    init(fireproofDomains: DomainFireproofStatusProviding = FireproofDomains.shared, fire: (() async -> Fire)? = nil) {
        self.fireproofDomains = fireproofDomains
        self.fire = fire ?? { @MainActor in FireCoordinator.fireViewModel.fire }
    }

    func burn(_ visits: [Visit], animated: Bool) async {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                await fire().burnVisits(visits, except: fireproofDomains, isToday: animated) {
                    continuation.resume()
                }
            }
        }
    }
}

protocol HistoryDeleting: AnyObject {
    func delete(_ visits: [Visit]) async
}

extension HistoryCoordinator: HistoryDeleting {
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

final class HistoryViewDataProvider: HistoryView.DataProviding {

    init(
        historyGroupingDataSource: HistoryGroupingDataSource & HistoryDeleting,
        historyBurner: HistoryBurning = FireHistoryBurner(),
        dateFormatter: HistoryViewDateFormatting = DefaultHistoryViewDateFormatter(),
        featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger
    ) {
        self.dateFormatter = dateFormatter
        self.historyGroupingDataSource = historyGroupingDataSource
        self.historyBurner = historyBurner
        historyGroupingProvider = HistoryGroupingProvider(dataSource: historyGroupingDataSource, featureFlagger: featureFlagger)
    }

    var ranges: [DataModel.HistoryRange] {
        var ranges: [DataModel.HistoryRange] = [.all]
        ranges.append(contentsOf: groupings.map(\.range))
        return ranges
    }

    func refreshData() async {
        lastQuery = nil
        await populateVisits()
    }

    func visitsBatch(for query: DataModel.HistoryQueryKind, limit: Int, offset: Int) async -> HistoryView.DataModel.HistoryItemsBatch {
        let items = perform(query)
        let visits = items.chunk(with: limit, offset: offset)
        let finished = offset + limit >= items.count
        return DataModel.HistoryItemsBatch(finished: finished, visits: visits)
    }

    func countVisibleVisits(for range: DataModel.HistoryRange) async -> Int {
        guard range != .all else {
            return historyItems.count
        }
        return groupings.first(where: { $0.range == range })?.items.count ?? 0
    }

    func deleteVisits(for range: DataModel.HistoryRange) async {
        let visits = await allVisits(for: range)
        await historyGroupingDataSource.delete(visits)
        await refreshData()
    }

    func burnVisits(for range: DataModel.HistoryRange) async {
        let visits = await allVisits(for: range)
        let animated = range == .today || range == .all
        await historyBurner.burn(visits, animated: animated)
        await refreshData()
    }

    // MARK: - Private

    @MainActor
    private func populateVisits() {
        var olderHistoryItems = [DataModel.HistoryItem]()
        var olderVisits = [Visit]()

        // generate groupings by day and set aside "older" days.
        groupings = historyGroupingProvider.getVisitGroupings()
            .compactMap { historyGrouping -> HistoryViewGrouping? in
                guard let grouping = HistoryViewGrouping(historyGrouping, dateFormatter: dateFormatter) else {
                    return nil
                }
                guard grouping.range != .older else {
                    olderHistoryItems.append(contentsOf: grouping.items)
                    olderVisits.append(contentsOf: historyGrouping.visits)
                    return nil
                }
                visitsByRange[grouping.range] = historyGrouping.visits
                return grouping
            }

        // collect all "older" days into a single grouping
        if !olderHistoryItems.isEmpty {
            groupings.append(.init(range: .older, visits: olderHistoryItems))
        }
        if !olderVisits.isEmpty {
            visitsByRange[.older] = olderVisits
        }

        self.historyItems = groupings.flatMap(\.items)
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

    /**
     * This function is here to ensure that history is accessed on the main thread.
     *
     * `HistoryCoordinator` uses `dispatchPrecondition(condition: .onQueue(.main))` internally.
     */
    @MainActor
    private func fetchHistory() async -> BrowsingHistory? {
        historyGroupingDataSource.history
    }

    private func perform(_ query: DataModel.HistoryQueryKind) -> [DataModel.HistoryItem] {
        if let lastQuery, lastQuery.query == query {
            return lastQuery.items
        }

        let items: [DataModel.HistoryItem] = {
            switch query {
            case .rangeFilter(.all), .searchTerm(""), .domainFilter(""):
                return historyItems
            case .rangeFilter(let range):
                return groupings.first(where: { $0.range == range })?.items ?? []
            case .searchTerm(let term):
                return historyItems.filter { $0.title.localizedCaseInsensitiveContains(term) || $0.url.localizedCaseInsensitiveContains(term) }
            case .domainFilter(let domain):
                return historyItems.filter { URL(string: $0.url)?.host == domain }
            }
        }()

        lastQuery = .init(date: dateFormatter.currentDate(), query: query, items: items)
        return items
    }

    private let historyGroupingProvider: HistoryGroupingProvider
    private let historyGroupingDataSource: HistoryGroupingDataSource & HistoryDeleting
    private let dateFormatter: HistoryViewDateFormatting
    private let historyBurner: HistoryBurning

    /// this is to be optimized: https://app.asana.com/0/72649045549333/1209339909309306
    private var groupings: [HistoryViewGrouping] = []
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
            id: historyEntry.identifier.uuidString,
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
