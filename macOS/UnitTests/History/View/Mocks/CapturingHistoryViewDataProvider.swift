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

    struct VisitsBatchCall: Equatable {
        let query: DataModel.HistoryQueryKind
        let source: DataModel.HistoryQuerySource
        let limit: Int
        let offset: Int
    }
}
