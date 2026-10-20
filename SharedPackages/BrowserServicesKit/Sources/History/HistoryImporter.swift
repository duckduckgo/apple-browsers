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
    @MainActor func importVisits(_ parseResult: HistoryImport.ParseResult) throws -> HistoryImport.Summary
}

/// Adds visits read from another browser's history to the local history.
public final class HistoryImporter: HistoryImporterProtocol {

    private let historyCoordinator: HistoryCoordinator
    private let cutoff: () -> Date

    /// - Parameter cutoff: Visits older than this are skipped. Read on every import, so a long-lived importer keeps up with the date.
    public init(historyCoordinator: HistoryCoordinator, cutoff: @escaping () -> Date = { .monthAgo }) {
        self.historyCoordinator = historyCoordinator
        self.cutoff = cutoff
    }

    /// Adds visits to history, skipping ones older than the cutoff or already present.
    @MainActor
    public func importVisits(_ parseResult: HistoryImport.ParseResult) throws -> HistoryImport.Summary {
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

        historyCoordinator.addImportedVisits(newVisits)
        summary.imported = newVisits.count
        return summary
    }

    private struct VisitKey: Hashable {
        let url: URL
        let date: Date
    }
}
