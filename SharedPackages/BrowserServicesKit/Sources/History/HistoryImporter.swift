//
//  HistoryImporter.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import FoundationExtensions

public protocol HistoryImporterProtocol {
    @MainActor func importVisits(_ parseResult: HistoryImport.ParseResult) async throws -> HistoryImport.Summary
}

public final class HistoryImporter: HistoryImporterProtocol {
    private struct VisitKey: Hashable {
        let url: URL
        let date: Date
    }

    private let historyCoordinator: HistoryCoordinating
    private let cutoff: () -> Date
    private let historyLoadTimeout: TimeInterval

    /// `cutoff` is read on every import, so a long-lived importer keeps up with the date.
    /// An import that starts while history is still loading, such as one right after launch, waits up to `historyLoadTimeout`.
    public init(
        historyCoordinator: HistoryCoordinating,
        cutoff: @escaping () -> Date = { .monthAgo },
        historyLoadTimeout: TimeInterval = 10
    ) {
        self.historyCoordinator = historyCoordinator
        self.cutoff = cutoff
        self.historyLoadTimeout = historyLoadTimeout
    }

    @MainActor
    public func importVisits(_ parseResult: HistoryImport.ParseResult) async throws -> HistoryImport.Summary {
        try await waitForHistoryToLoad()
        guard let historyDictionary = historyCoordinator.historyDictionary else {
            throw HistoryImport.Error.historyNotLoaded
        }

        var summary = HistoryImport.Summary(skipped: parseResult.skipped)
        var knownVisits = Set<VisitKey>()
        for (url, entry) in historyDictionary {
            for visit in entry.visits {
                knownVisits.insert(VisitKey(url: url, date: visit.date))
            }
        }

        let cutoff = cutoff()
        let newVisits = parseResult.visits.filter { visit in
            guard visit.date >= cutoff else {
                summary.tooOld += 1
                return false
            }
            guard knownVisits.insert(VisitKey(url: visit.url, date: visit.date)).inserted else {
                summary.alreadyInHistory += 1
                return false
            }
            return true
        }

        try await historyCoordinator.addImportedVisits(newVisits)
        summary.imported = newVisits.count
        return summary
    }

    @MainActor
    private func waitForHistoryToLoad() async throws {
        let deadline = Date().addingTimeInterval(historyLoadTimeout)
        while !historyCoordinator.isHistoryLoaded {
            guard Date() < deadline else {
                throw HistoryImport.Error.historyNotLoaded
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
